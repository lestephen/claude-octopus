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
#       [--min-reviewers <N>]            # default 2
#       [--task-prefix <slug>]           # default "lib-dispatch"
#       [--resume]                       # reuse prior dispatch.json successes
#       [--image <path>]                 # repeatable, attach image to dispatch
#       [--min-output-size <bytes>]      # min Output-section size, default 50
#       [--required-lib-interface <N>]   # opt-in lib-skill version pin (GH #9)
#       [--check-lib-skill <name>]       # opt-in lib-skill version pin (GH #9)
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
#   --resume       Skip dispatch for reviewers whose prior run succeeded
#                  (read from existing dispatch.json). lestephen.22 (C6).
#   --image <path> Repeatable. Pass image file paths through to each reviewer's
#                  probe-single call. lestephen.23/.24 (closes GH #7).
#   --min-output-size N
#                  Required minimum bytes in the per-reviewer Output section.
#                  Default 50; lower (e.g. 1) for visual inspections that
#                  answer in one word. lestephen.23 dogfood find.
#   --required-lib-interface N
#                  Opt-in min interface_version for a library skill (paired
#                  with --check-lib-skill). Reads SKILL.md frontmatter; refuses
#                  dispatch (exit 2) if installed < required. Replaces the
#                  dead-text "consumers should pin this version" promise.
#                  lestephen.29 (closes GH #9).
#   --check-lib-skill <name>
#                  Skill name to interface-check (e.g. skill-lib-multi-inspect-figure).
#                  Required when --required-lib-interface is set. Searches
#                  PLUGIN_ROOT/skills/<name>/SKILL.md and
#                  ~/.claude-octopus/plugin/skills/<name>/SKILL.md.
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
# lestephen.23: --image <path> (repeatable) — image attachments for each
# reviewer. Validated upfront; forwarded to every per-reviewer probe-single
# invocation. Vision-capable providers (codex) get -i flags; others degrade
# gracefully (see workflows.sh::probe_single_agent).
IMAGES=()
# lestephen.23 (dogfood find): --min-output-size N — minimum Output-section
# body bytes for a reviewer to count as success. Default 50 (prose reviews).
# Lower (e.g., 1) for visual inspection where "Green" is a valid answer.
MIN_OUTPUT_SIZE=50
# lestephen.29 (closes GH #9): --required-lib-interface N — opt-in caller-
# declared minimum interface version for a referenced library skill. When set
# together with --check-lib-skill <skill-name>, the dispatcher reads the
# SKILL.md frontmatter `interface_version:` line and refuses to dispatch if
# the library has a LOWER version than required (semver-style: 2 satisfies
# 1, but 1 does not satisfy 2). Both flags are optional — consumers that
# don't care about lib versioning omit them. Replaces the dead-text v.21
# promise that "consumers should pin this version" (was honor-system).
REQUIRED_LIB_INTERFACE=""
CHECK_LIB_SKILL=""

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
        --image)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --image requires a path argument" >&2; exit 2
            fi
            if [[ ! -f "$2" ]]; then
                echo "ERROR: --image is not a file: $2" >&2; exit 2
            fi
            IMAGES+=("$2"); shift 2 ;;
        --min-output-size)
            if [[ -z "${2:-}" || ! "$2" =~ ^[0-9]+$ ]]; then
                echo "ERROR: --min-output-size requires a non-negative integer" >&2; exit 2
            fi
            MIN_OUTPUT_SIZE="$2"; shift 2 ;;
        --required-lib-interface)
            if [[ -z "${2:-}" || ! "$2" =~ ^[0-9]+$ ]]; then
                echo "ERROR: --required-lib-interface requires a non-negative integer" >&2; exit 2
            fi
            REQUIRED_LIB_INTERFACE="$2"; shift 2 ;;
        --check-lib-skill)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --check-lib-skill requires a skill name (e.g. skill-lib-multi-review-doc)" >&2; exit 2
            fi
            CHECK_LIB_SKILL="$2"; shift 2 ;;
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

# lestephen.29 (closes GH #9): interface_version compatibility check. When
# the caller declared both --required-lib-interface and --check-lib-skill,
# read the SKILL.md frontmatter `interface_version:` for the named skill and
# refuse to dispatch if it's lower than required. Semver-style: higher is
# backward-compatible.
if [[ -n "$REQUIRED_LIB_INTERFACE" && -n "$CHECK_LIB_SKILL" ]]; then
    # Resolve skill dir — try PLUGIN_ROOT/skills/<name>/SKILL.md, fall back
    # to a search if the layout changes upstream.
    _libcheck_path=""
    for _candidate in \
        "$PLUGIN_ROOT/skills/$CHECK_LIB_SKILL/SKILL.md" \
        "$HOME/.claude-octopus/plugin/skills/$CHECK_LIB_SKILL/SKILL.md"; do
        if [[ -f "$_candidate" ]]; then
            _libcheck_path="$_candidate"
            break
        fi
    done
    if [[ -z "$_libcheck_path" ]]; then
        echo "ERROR: --check-lib-skill '$CHECK_LIB_SKILL': SKILL.md not found" >&2
        echo "       Searched: $PLUGIN_ROOT/skills/$CHECK_LIB_SKILL/SKILL.md" >&2
        echo "                 $HOME/.claude-octopus/plugin/skills/$CHECK_LIB_SKILL/SKILL.md" >&2
        exit 2
    fi
    # Extract interface_version: N from frontmatter. Distinguish "absent
    # field" (sentinel "__ABSENT__") from "explicit 0" so we can give the
    # right diagnostic — lestephen.30 v2 fix to claude SEV-2 (was conflated
    # as "Has version: 0"). Permissive regex trims trailing whitespace and
    # rejects inline comments — fix to gemini SEV-2 (strict-regex fragility).
    _libcheck_actual=$(awk '
        /^---$/ { fm++ ; if (fm == 2) exit ; next }
        fm == 1 && /^interface_version:[[:space:]]*[0-9]+/ {
            # Trim leading key+spaces, then trailing spaces or # comments
            sub(/^interface_version:[[:space:]]*/, "")
            sub(/[[:space:]]*(#.*)?$/, "")
            print
            found = 1
            exit
        }
        END { if (!found) print "__ABSENT__" }
    ' "$_libcheck_path")
    if [[ "$_libcheck_actual" == "__ABSENT__" ]]; then
        cat >&2 <<EOF
ERROR: --check-lib-skill '$CHECK_LIB_SKILL': SKILL.md exists but has no
       'interface_version:' line in frontmatter.
       Path: $_libcheck_path
       Either add 'interface_version: N' to the SKILL.md frontmatter,
       or omit --check-lib-skill if the skill hasn't adopted versioning yet.
EOF
        exit 2
    fi
    if [[ ! "$_libcheck_actual" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --check-lib-skill '$CHECK_LIB_SKILL': interface_version frontmatter value '$_libcheck_actual' is not a non-negative integer" >&2
        exit 2
    fi
    if [[ "$_libcheck_actual" -lt "$REQUIRED_LIB_INTERFACE" ]]; then
        cat >&2 <<EOF
ERROR: Library skill interface version mismatch (closes GH #9).
       Skill:        $CHECK_LIB_SKILL ($_libcheck_path)
       Has version:  $_libcheck_actual
       Required min: $REQUIRED_LIB_INTERFACE
       Caller pinned a higher interface version than the library currently
       provides. This usually means the library was rolled back, or the
       caller was written against a future version that hasn't landed yet.
       Pin a lower --required-lib-interface, or update the library skill.
EOF
        exit 2
    fi
    echo "Lib interface check OK: $CHECK_LIB_SKILL v$_libcheck_actual >= required v$REQUIRED_LIB_INTERFACE" >&2
fi

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
declare -a TASK_LABELS        # perspective_label
declare -a TASK_AGENTS        # agent_type
declare -a TASK_IDS           # task_id (used to construct expected file path)
declare -a TASK_PIDS          # background pid
declare -a TASK_FINGERPRINTS  # sha256 of (agent|prompt|doc|images) — GH #8

# lestephen.22 (C6): --resume — build set of labels that succeeded last time
# so we can skip them and dispatch only the failures.
# lestephen.30 (closes GH #8): also load fingerprints — a label match alone
# isn't enough. If the reviewer prompt, doc content, agent_type, or image set
# changes between runs, the prior output is stale and must NOT be reused.
declare -A PRIOR_SUCCESS_LABELS       # label -> output_file
declare -A PRIOR_SUCCESS_AGENTS       # label -> agent_type
declare -A PRIOR_SUCCESS_IDS          # label -> task_id
declare -A PRIOR_SUCCESS_FINGERPRINTS # label -> sha256:agent|prompt|doc|images
PRIOR_SUCCESS_COUNT=0
if [[ "$RESUME" == "true" && -f "$OUTPUT_DIR/dispatch.json" ]]; then
    echo "Resume mode — reading prior dispatch.json..." >&2
    # v2 SEV-2 gemini fix: jq @tsv escapes literal tabs in values as \t,
    # then bash IFS=$'\t' splits on real tabs — the escaped \t stays glued
    # to its field, corrupting labels with tabs in them. Use NUL-delimited
    # iteration via jq -j + read -d '' (handles any byte except NUL).
    while IFS= read -r _entry; do
        [[ -z "$_entry" ]] && continue
        # Each $_entry is a JSON object {label, agent_type, task_id, outcome,
        # output_file, fingerprint}. Parse with jq, which handles all
        # quoting / escaping correctly (closes v2 SEV-1 JSON injection from
        # gemini consensus + v2 SEV-2 label-with-special-chars from same).
        label=$(jq -r '.label'                              <<<"$_entry")
        agent=$(jq -r '.agent_type'                         <<<"$_entry")
        task_id=$(jq -r '.task_id'                          <<<"$_entry")
        outcome=$(jq -r '.outcome'                          <<<"$_entry")
        output_file=$(jq -r '.output_file'                  <<<"$_entry")
        fingerprint=$(jq -r '.fingerprint // "__MISSING__"' <<<"$_entry")
        [[ -z "$label" || -z "$outcome" ]] && continue
        if [[ "$outcome" == "success" && -s "$output_file" ]]; then
            PRIOR_SUCCESS_LABELS[$label]="$output_file"
            PRIOR_SUCCESS_AGENTS[$label]="$agent"
            PRIOR_SUCCESS_IDS[$label]="$task_id"
            # fingerprint may be missing in dispatch.json from older runs
            # (pre-lestephen.30) — treat absent as "always re-dispatch" so
            # stale-by-omission doesn't slip through.
            PRIOR_SUCCESS_FINGERPRINTS[$label]="${fingerprint:-__MISSING__}"
            ((PRIOR_SUCCESS_COUNT++))
        fi
    done < <(jq -c '.reviewers[]' "$OUTPUT_DIR/dispatch.json" 2>/dev/null)
    echo "Resuming: $PRIOR_SUCCESS_COUNT reviewers from prior run (will validate fingerprints before reuse)." >&2
fi

# Pre-compute IMAGES fingerprint (newline-separated paths + per-file sha256
# of the bytes — if the file changes between runs, fingerprint changes too).
# v2 SEV-2 gemini fix: use printf %s not %b so backslashes in image paths
# (e.g. Windows-style) aren't interpreted as escape sequences.
_images_fp_input=""
if [[ ${#IMAGES[@]} -gt 0 ]]; then
    for _img in "${IMAGES[@]}"; do
        _img_hash=$(sha256sum "$_img" 2>/dev/null | cut -c1-16)
        _images_fp_input+=$(printf '%s@%s\n' "$_img" "${_img_hash:-MISSING}")
        _images_fp_input+=$'\n'  # explicit newline (not via printf interpretation)
    done
fi

# Pre-compute DOC content sha256 — hash the file BYTES directly, not the
# $(cat)-stripped version. v2 SEV-2 gemini fix: $(cat) strips trailing
# newlines, so a doc that only differs by trailing whitespace would be
# treated as identical. Hashing the file bytes preserves all bytes.
_doc_sha=$(sha256sum "$DOC_PATH" 2>/dev/null | cut -c1-16)

# Helper: compute reviewer fingerprint.
# Inputs: agent_type, prompt. Globals: $_doc_sha, $_images_fp_input.
# Output: 16-char sha256 hex.
# v2 SEV-2 gemini fix: printf %s for all inputs (NOT %b — would interpret
# escape sequences in arbitrary input). Newlines are explicit string concats.
compute_reviewer_fingerprint() {
    local _agent="$1"
    local _prompt="$2"
    {
        printf '%s\n' "$_agent"
        printf '%s\n' "$_doc_sha"
        printf '%s\n' "$_prompt"
        printf '%s' "$_images_fp_input"
    } | sha256sum | cut -c1-16
}

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

    # Compute fingerprint for this reviewer (used both for resume-validation
    # and for the eventual dispatch.json entry).
    current_fp=$(compute_reviewer_fingerprint "$agent" "$prompt")

    # lestephen.22 (C6) + lestephen.30 (closes GH #8): skip reviewers that
    # succeeded in a prior dispatch ONLY when the fingerprint matches —
    # i.e. agent_type, prompt, doc content, AND image bytes are all unchanged.
    # Otherwise, re-dispatch with the new input.
    if [[ -n "${PRIOR_SUCCESS_LABELS[$label]:-}" ]]; then
        prior_fp="${PRIOR_SUCCESS_FINGERPRINTS[$label]:-__MISSING__}"
        if [[ "$prior_fp" == "$current_fp" ]]; then
            echo "⏭️  ${label} (${agent}) — skipped (fingerprint match: $current_fp; prior: ${PRIOR_SUCCESS_LABELS[$label]})" >&2
            TASK_LABELS+=("$label")
            TASK_AGENTS+=("${PRIOR_SUCCESS_AGENTS[$label]}")
            TASK_IDS+=("${PRIOR_SUCCESS_IDS[$label]}")
            TASK_FINGERPRINTS+=("$current_fp")
            TASK_PIDS+=("")  # no pid — already done
            continue
        else
            # Fingerprint changed — prior output is stale. Tell the user
            # specifically why we're re-dispatching.
            echo "🔁  ${label} (${agent}) — re-dispatch (fingerprint differs: prior=$prior_fp current=$current_fp)" >&2
            # Fall through to fresh dispatch.
        fi
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

    # lestephen.23: build per-call --image args (repeatable) for vision-capable
    # providers. Text-only providers will warn + degrade in probe_single_agent.
    image_args=()
    if [[ ${#IMAGES[@]} -gt 0 ]]; then
        for _img in "${IMAGES[@]}"; do
            image_args+=(--image "$_img")
        done
    fi

    # Per lestephen.12: prompt body goes in $2 (perspective slot), metadata in $4
    # Empty-array-safe expansion under set -u: ${arr[@]+"${arr[@]}"}
    timeout 600 bash "$ORCHESTRATE" probe-single \
        "$agent" "$full_prompt" "$task_id" \
        "lib-multi-dispatch: ${label} on ${DOC_PATH}" \
        --output-dir "$OUTPUT_DIR" \
        ${image_args[@]+"${image_args[@]}"} \
        > "$OUTPUT_DIR/.dispatch-${i}.stdout" 2>&1 &
    pid=$!

    TASK_LABELS+=("$label")
    TASK_AGENTS+=("$agent")
    TASK_IDS+=("$task_id")
    TASK_FINGERPRINTS+=("$current_fp")
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
        elif [[ "$output_size" -lt "$MIN_OUTPUT_SIZE" ]]; then
            reason="provider output body < ${MIN_OUTPUT_SIZE} chars (likely empty or just code-fence; tune via --min-output-size)"
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

# Build dispatch.json summary via jq (closes GH #8 v2 gemini SEV-1: prior
# printf-based construction didn't escape double quotes or backslashes in
# labels/agent_types/paths — would produce invalid JSON and break --resume).
# jq -n with --arg/--argjson handles all escaping automatically.
{
    # Build reviewers array as a JSON document. Loop emits one object per
    # reviewer; jq -s concatenates and the outer jq merges with metadata.
    _reviewers_array='[]'
    for i in "${!TASK_LABELS[@]}"; do
        _reviewers_array=$(jq -n \
            --argjson existing "$_reviewers_array" \
            --arg label       "${TASK_LABELS[$i]}" \
            --arg agent_type  "${TASK_AGENTS[$i]}" \
            --arg task_id     "${TASK_IDS[$i]}" \
            --arg outcome     "${TASK_OUTCOMES[$i]}" \
            --arg output_file "$OUTPUT_DIR/${TASK_AGENTS[$i]}-${TASK_IDS[$i]}.md" \
            --arg fingerprint "${TASK_FINGERPRINTS[$i]:-MISSING}" \
            '$existing + [{label: $label, agent_type: $agent_type, task_id: $task_id, outcome: $outcome, output_file: $output_file, fingerprint: $fingerprint}]')
    done
    jq -n \
        --arg output_dir "$OUTPUT_DIR" \
        --arg doc_path "$DOC_PATH" \
        --arg doc_sha "$_doc_sha" \
        --argjson min_reviewers "$MIN_REVIEWERS" \
        --argjson total "$reviewers_count" \
        --argjson success "$SUCCESS_COUNT" \
        --argjson failed "$FAILED_COUNT" \
        --argjson reviewers "$_reviewers_array" \
        '{output_dir: $output_dir, doc_path: $doc_path, doc_sha: $doc_sha, min_reviewers: $min_reviewers, total: $total, success: $success, failed: $failed, fingerprint_version: 1, reviewers: $reviewers}'
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
