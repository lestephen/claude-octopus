#!/usr/bin/env bash
# lib-multi-dispatch.sh — Real-bash multi-LLM dispatch helper.
#
# Replaces the pseudocode-in-skill-prose pattern that the lib-* skills
# previously used. Consumer skills (skill-lib-multi-review-doc, skill-defensibility-pass,
# skill-argument-strength, skill-critique, eki-kw skills) now call this
# helper instead of re-running prose. Closes:
#   - audit issue #1: validation-gate weakness (file-exists vs Output-content)
#   - audit C5: skill-prose pseudocode is not testable
#   - audit G1: $OUTPUT_DIR drift between parent and library skills
#   - audit C6 (partial): centralizes the resume substrate
#
# Usage:
#   lib-multi-dispatch.sh \
#       --doc-path <path> \
#       --reviewers <json-file> \
#       --output-dir <dir> \
#       [--min-reviewers <N>]    # default 2
#       [--task-prefix <slug>]   # default "lib-dispatch"
#
# Inputs:
#   --doc-path     Absolute path to the document/scope-bundle each reviewer reads.
#                  MUST be a real file (the helper enforces -f). Strings or
#                  process-substitutions are rejected.
#   --reviewers    Path to a JSON file containing an array of:
#                    [{"agent_type":"codex","perspective_label":"technical","prompt":"..."}]
#   --output-dir   Directory to write per-reviewer files + dispatch.json +
#                  synthesis-input.md. Created if missing.
#   --min-reviewers N
#                  Validation gate: require at least N successful reviewers
#                  (out of len(reviewers)) before declaring success. Default 2.
#   --task-prefix  Optional prefix for task IDs (helps cross-reference logs).
#
# Output:
#   stdout: structured key=value lines for the caller to parse:
#       DISPATCH_OUTPUT_DIR=<dir>
#       DISPATCH_TOTAL=<N>
#       DISPATCH_SUCCESS=<K>
#       DISPATCH_FAILED=<M>
#       SYNTHESIS_INPUT=<dir>/synthesis-input.md
#
#   <output-dir>/<agent_type>-<task_id>.md per reviewer (written by orchestrate.sh)
#   <output-dir>/dispatch.json  — structured summary
#   <output-dir>/synthesis-input.md — concatenated Output sections of successful reviewers
#
# Exit codes:
#   0 — success (>= min-reviewers passed strong validation gate)
#   2 — usage / preflight failure (bad inputs)
#   3 — dispatch infrastructure failure (orchestrate.sh missing, etc.)
#   4 — partial / insufficient reviewers passed validation (caller should not synthesize)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ORCHESTRATE="$PLUGIN_ROOT/orchestrate.sh"

# Defaults
DOC_PATH=""
REVIEWERS_JSON=""
OUTPUT_DIR=""
MIN_REVIEWERS=2
TASK_PREFIX="lib-dispatch"
RESUME=false   # lestephen.22 (C6): --resume picks up where prior run left off

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --doc-path)      DOC_PATH="$2"; shift 2 ;;
        --reviewers)     REVIEWERS_JSON="$2"; shift 2 ;;
        --output-dir)    OUTPUT_DIR="$2"; shift 2 ;;
        --min-reviewers) MIN_REVIEWERS="$2"; shift 2 ;;
        --task-prefix)   TASK_PREFIX="$2"; shift 2 ;;
        --resume)        RESUME=true; shift ;;
        -h|--help)       usage 0 ;;
        *)               echo "ERROR: unknown arg '$1'" >&2; usage 2 ;;
    esac
done

# Preflight
[[ -n "$DOC_PATH" ]] || { echo "ERROR: --doc-path required" >&2; exit 2; }
[[ -f "$DOC_PATH" ]] || { echo "ERROR: --doc-path is not a file: $DOC_PATH" >&2; exit 2; }
[[ -s "$DOC_PATH" ]] || { echo "ERROR: --doc-path is empty: $DOC_PATH" >&2; exit 2; }
[[ -n "$REVIEWERS_JSON" ]] || { echo "ERROR: --reviewers required" >&2; exit 2; }
[[ -f "$REVIEWERS_JSON" ]] || { echo "ERROR: --reviewers is not a file: $REVIEWERS_JSON" >&2; exit 2; }
[[ -n "$OUTPUT_DIR" ]] || { echo "ERROR: --output-dir required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }
[[ -x "$ORCHESTRATE" ]] || { echo "ERROR: orchestrate.sh not executable: $ORCHESTRATE" >&2; exit 3; }

mkdir -p "$OUTPUT_DIR"

# Parse reviewers
reviewers_count=$(jq 'length' "$REVIEWERS_JSON" 2>/dev/null) || {
    echo "ERROR: --reviewers JSON malformed: $REVIEWERS_JSON" >&2; exit 2;
}
if [[ "$reviewers_count" -lt 1 ]]; then
    echo "ERROR: --reviewers JSON contains 0 entries" >&2; exit 2
fi
if [[ "$MIN_REVIEWERS" -gt "$reviewers_count" ]]; then
    echo "ERROR: --min-reviewers ($MIN_REVIEWERS) > reviewers in JSON ($reviewers_count)" >&2; exit 2
fi

# Snapshot doc content into the reviewer prompt so providers see the full
# context (probe-single's perspective slot IS the prompt body the model sees;
# see lestephen.12 for the call-signature fix). Document is read once.
DOC_CONTENT=$(cat "$DOC_PATH")

# Stable timestamp for task IDs
TS=$(date +%s)

# Track dispatched tasks for the validation gate
declare -a TASK_LABELS  # perspective_label
declare -a TASK_AGENTS  # agent_type
declare -a TASK_IDS     # task_id (used to construct expected file path)
declare -a TASK_PIDS    # background pid

# lestephen.22 (C6): --resume — build set of labels that succeeded last time
# so we can skip them and dispatch only the failures.
declare -A PRIOR_SUCCESS_LABELS  # label -> output_file from prior dispatch.json
declare -A PRIOR_SUCCESS_AGENTS  # label -> agent_type from prior dispatch.json
declare -A PRIOR_SUCCESS_IDS     # label -> task_id from prior dispatch.json
PRIOR_SUCCESS_COUNT=0
if [[ "$RESUME" == "true" && -f "$OUTPUT_DIR/dispatch.json" ]]; then
    echo "Resume mode — reading prior dispatch.json..." >&2
    while IFS=$'\t' read -r label agent task_id outcome output_file; do
        [[ -z "$label" || -z "$outcome" ]] && continue
        if [[ "$outcome" == "success" && -s "$output_file" ]]; then
            PRIOR_SUCCESS_LABELS[$label]="$output_file"
            PRIOR_SUCCESS_AGENTS[$label]="$agent"
            PRIOR_SUCCESS_IDS[$label]="$task_id"
            ((PRIOR_SUCCESS_COUNT++))
        fi
    done < <(jq -r '.reviewers[] | [.label, .agent_type, .task_id, .outcome, .output_file] | @tsv' "$OUTPUT_DIR/dispatch.json" 2>/dev/null)
    echo "Resuming: $PRIOR_SUCCESS_COUNT reviewers already succeeded; will dispatch only failures." >&2
fi

# Dispatch each reviewer (skipping ones that succeeded in a prior --resume run)
for i in $(seq 0 $((reviewers_count - 1))); do
    agent=$(jq -r ".[$i].agent_type" "$REVIEWERS_JSON")
    label=$(jq -r ".[$i].perspective_label" "$REVIEWERS_JSON")
    prompt=$(jq -r ".[$i].prompt" "$REVIEWERS_JSON")

    [[ -z "$agent" || "$agent" == "null" ]] && {
        echo "ERROR: reviewers[$i].agent_type missing" >&2; exit 2;
    }
    [[ -z "$label" || "$label" == "null" ]] && label="reviewer-$i"
    [[ -z "$prompt" || "$prompt" == "null" ]] && {
        echo "ERROR: reviewers[$i].prompt missing" >&2; exit 2;
    }

    # lestephen.22 (C6): skip reviewers that succeeded in a prior dispatch
    if [[ -n "${PRIOR_SUCCESS_LABELS[$label]:-}" ]]; then
        echo "⏭️  ${label} (${agent}) — skipped (prior success: ${PRIOR_SUCCESS_LABELS[$label]})" >&2
        # Re-record so they appear in dispatch.json + synthesis-input.md
        TASK_LABELS+=("$label")
        TASK_AGENTS+=("${PRIOR_SUCCESS_AGENTS[$label]}")
        TASK_IDS+=("${PRIOR_SUCCESS_IDS[$label]}")
        TASK_PIDS+=("")  # no pid — already done
        continue
    fi

    # Slugify label for task_id
    slug=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed 's/--*/-/g; s/^-\|-$//g')
    task_id="${TASK_PREFIX}-${slug}-${TS}-${i}"

    # Construct the full prompt body: reviewer instruction + document
    full_prompt="${prompt}

---

Document under review (path: ${DOC_PATH}):

${DOC_CONTENT}"

    echo "Dispatching ${agent} as ${label} (task=${task_id})..." >&2

    # Per lestephen.12: prompt body goes in $2 (perspective slot), metadata in $4
    timeout 600 bash "$ORCHESTRATE" probe-single \
        "$agent" "$full_prompt" "$task_id" \
        "lib-multi-dispatch: ${label} on ${DOC_PATH}" \
        --output-dir "$OUTPUT_DIR" \
        > "$OUTPUT_DIR/.dispatch-${i}.stdout" 2>&1 &
    pid=$!

    TASK_LABELS+=("$label")
    TASK_AGENTS+=("$agent")
    TASK_IDS+=("$task_id")
    TASK_PIDS+=("$pid")
done

# Wait for all dispatches (skip ones that were resumed — empty PID slot)
declare -a TASK_RCS
for i in "${!TASK_PIDS[@]}"; do
    pid="${TASK_PIDS[$i]}"
    if [[ -z "$pid" ]]; then
        TASK_RCS+=("0")  # resumed — assume success (validated below)
        continue
    fi
    wait "$pid" 2>/dev/null
    TASK_RCS+=("$?")
done

# Strong validation gate — also check that the Output section has real content,
# not just headers + "Status: FAILED". Closes audit issue #1.
declare -a TASK_OUTCOMES  # success | failed
SUCCESS_COUNT=0
FAILED_COUNT=0
for i in "${!TASK_LABELS[@]}"; do
    agent="${TASK_AGENTS[$i]}"
    task_id="${TASK_IDS[$i]}"
    file="$OUTPUT_DIR/${agent}-${task_id}.md"
    outcome="failed"
    reason=""

    if [[ ! -s "$file" ]]; then
        reason="file missing or empty: $file"
    else
        # Extract Output section content (between '## Output' and the next '## ')
        output_body=$(awk '/^## Output/{flag=1;next} /^## /{flag=0} flag' "$file" 2>/dev/null | sed '/^```$/d')
        output_size=$(printf '%s' "$output_body" | wc -c)
        status_line=$(grep "^## Status:" "$file" | head -1)

        if [[ "$status_line" == *"FAILED"* ]]; then
            reason="provider Status: FAILED"
        elif [[ "$output_size" -lt 50 ]]; then
            reason="provider output body < 50 chars (likely empty or just code-fence)"
        else
            outcome="success"
        fi
    fi

    TASK_OUTCOMES+=("$outcome")
    if [[ "$outcome" == "success" ]]; then
        ((SUCCESS_COUNT++))
        echo "✅ ${TASK_LABELS[$i]} (${agent}) -> $file" >&2
    else
        ((FAILED_COUNT++))
        echo "❌ ${TASK_LABELS[$i]} (${agent}) -> $file [$reason]" >&2
    fi
done

# Build dispatch.json summary
{
    echo '{'
    echo '  "output_dir": "'"$OUTPUT_DIR"'",'
    echo '  "doc_path": "'"$DOC_PATH"'",'
    echo '  "min_reviewers": '"$MIN_REVIEWERS"','
    echo '  "total": '"$reviewers_count"','
    echo '  "success": '"$SUCCESS_COUNT"','
    echo '  "failed": '"$FAILED_COUNT"','
    echo '  "reviewers": ['
    for i in "${!TASK_LABELS[@]}"; do
        sep=","
        [[ $i -eq $((${#TASK_LABELS[@]} - 1)) ]] && sep=""
        printf '    {"label":"%s","agent_type":"%s","task_id":"%s","outcome":"%s","output_file":"%s"}%s\n' \
            "${TASK_LABELS[$i]}" \
            "${TASK_AGENTS[$i]}" \
            "${TASK_IDS[$i]}" \
            "${TASK_OUTCOMES[$i]}" \
            "$OUTPUT_DIR/${TASK_AGENTS[$i]}-${TASK_IDS[$i]}.md" \
            "$sep"
    done
    echo '  ]'
    echo '}'
} > "$OUTPUT_DIR/dispatch.json"

# Validation gate
if [[ "$SUCCESS_COUNT" -lt "$MIN_REVIEWERS" ]]; then
    echo "❌ VALIDATION FAILED: $SUCCESS_COUNT/$reviewers_count reviewers passed strong validation (min: $MIN_REVIEWERS)" >&2
    echo "Inspect ~/.claude-octopus/logs/ and $OUTPUT_DIR/.dispatch-*.stdout for details" >&2
    echo "Do NOT synthesize — surface the failure to the caller" >&2
    # Emit structured summary even on failure so caller can decide
    echo "DISPATCH_OUTPUT_DIR=$OUTPUT_DIR"
    echo "DISPATCH_TOTAL=$reviewers_count"
    echo "DISPATCH_SUCCESS=$SUCCESS_COUNT"
    echo "DISPATCH_FAILED=$FAILED_COUNT"
    echo "DISPATCH_VERDICT=insufficient"
    exit 4
fi

# Build synthesis-input.md — concatenated Output sections of successful reviewers
{
    echo "# Multi-LLM dispatch — synthesis input"
    echo ""
    echo "**Document:** $DOC_PATH"
    echo "**Reviewers run:** $reviewers_count (success: $SUCCESS_COUNT, failed: $FAILED_COUNT)"
    echo ""
    for i in "${!TASK_LABELS[@]}"; do
        [[ "${TASK_OUTCOMES[$i]}" != "success" ]] && continue
        echo "---"
        echo ""
        echo "## ${TASK_LABELS[$i]} (${TASK_AGENTS[$i]})"
        echo ""
        file="$OUTPUT_DIR/${TASK_AGENTS[$i]}-${TASK_IDS[$i]}.md"
        # Print the Output section verbatim
        awk '/^## Output/{flag=1;next} /^## /{flag=0} flag' "$file" | sed '/^```$/d'
        echo ""
    done
} > "$OUTPUT_DIR/synthesis-input.md"

# Structured summary for caller parsing
echo "DISPATCH_OUTPUT_DIR=$OUTPUT_DIR"
echo "DISPATCH_TOTAL=$reviewers_count"
echo "DISPATCH_SUCCESS=$SUCCESS_COUNT"
echo "DISPATCH_FAILED=$FAILED_COUNT"
echo "DISPATCH_VERDICT=ok"
echo "SYNTHESIS_INPUT=$OUTPUT_DIR/synthesis-input.md"
echo "DISPATCH_JSON=$OUTPUT_DIR/dispatch.json"

exit 0
