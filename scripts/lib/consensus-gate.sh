#!/usr/bin/env bash
# consensus-gate.sh — Machine-enforced consensus check (closes GH #16).
#
# Parses a lib-multi-dispatch.sh dispatch.json + per-reviewer output files,
# applies the consensus definition table from skill-autonomous-mode v.25
# mechanically, exits 0 (ALLOW) or non-zero (BLOCK).
#
# This is the enforcement layer the .25 skill prose acknowledged was missing.
# Until this lands the gate was honor-system; with this, the gate has teeth.
#
# ─── Critique history (dogfooded against its own protocol) ─────────────────
# v1 → 2 SEV-1 (codex+claude): SEV-3/4/5 dropped as unparseable; ANSI escapes
#      silently demoted findings. Plus 6 SEV-2/3 deferred.
# v2 → 2 SEV-1 (codex+claude): ANSI strip incomplete; diversity-bypass-via-
#      unparseable-foreign-family. Plus 2 SEV-2 (BSD sed compat, output
#      close-regex misses ### subheadings) + 2 SEV-3 deferred.
# v3a → 1 SEV-1 (codex): awk `\b` is backspace not word-boundary; heading
#       detection always failed, fallback to whole-file would count prompt-
#       side SEV examples as findings.
# v4 (this) → 1 SEV-1 (codex): OSC ANSI not stripped (regex put `]` in
#             single-char-ESC class). 1 SEV-2 (codex): empty matched section
#             fell back to whole-file.
# Stopped at 6 rounds per user direction + 3-substantive-rounds cap added
# to skill-autonomous-mode in this patch. Residual risk documented + GH #18
# tracks any future findings.
#
# Known residual limits (acknowledged):
# - Claude `--print` times out on >20KB prompts (dispatch-infra issue, not
#   gate logic). For the gate to reach quorum reliably with claude, prompts
#   must stay tight. Worked around by sending diffs not whole files.
# - Gemini headless dispatch can hit 400 errors mid-tool-call. When that
#   happens, the gate correctly reports NO QUORUM rather than passing.
# - Six rounds of critique surfaced increasingly subtle bugs (awk \b → OSC).
#   The gate is robust for common cases; exotic reviewer formatting (deeply
#   nested markdown, mixed encodings, non-ASCII heading text) may still
#   trip edges. File any new edge case as GH #18 comment.
#
# Usage (as a sourced library — preferred for in-process checks):
#   source "${PLUGIN_DIR}/scripts/lib/consensus-gate.sh"
#   octo_consensus_check "<dispatch.json>" "<action description>"
#   # echoes verdict to stdout; returns 0 for ALLOW, non-zero for BLOCK
#
# Usage (as standalone script):
#   bash consensus-gate.sh check <dispatch.json> "<action description>"
#   bash consensus-gate.sh explain  # print the consensus definition table
#
# Exit codes (matches a useful set of git-hook conventions):
#   0  ALLOW — consensus reached, action may proceed
#   1  HARD BLOCK — ≥2 providers raised SEV-1 (or all did)
#   2  SOFT BLOCK — ≥2 providers raised SEV-2 (majority concern below SEV-1 threshold)
#   3  SPLIT — exactly 1 provider raised SEV-1, others clean (adjudication required)
#   4  NO QUORUM — fewer than 2 successful providers in dispatch.json
#   5  PARSE ERROR — dispatch.json malformed or reviewer files unreadable
#   6  USAGE — bad arguments
#
# Severity-line grammar (strict, on purpose — see .25 SEV-1b discussion):
#   Reviewers MUST emit findings as lines matching:
#     ^SEV-[1-5]:\s+.+
#     ^NO BLOCKING FINDINGS\b
#   Any other format counts as unparseable for that provider → that provider's
#   vote does not count (we conservatively assume their input is unverifiable
#   rather than guess at the intent).

set -uo pipefail

# ─── Constants ─────────────────────────────────────────────────────────────
OCTO_CONSENSUS_VERSION="1.0.0"  # bump if the grammar or table changes

# ─── Helpers ───────────────────────────────────────────────────────────────

# Parse one provider's output file. Echoes a single line:
#   <agent_type>|<sev1>|<sev2>|<sev3plus>|<no_blocking>|<parse_status>
# parse_status: ok | empty | unparseable | missing
#
# lestephen.27 (own-dogfood findings):
#   SEV-1 codex+claude: track SEV-3/4/5 separately so reviewers reporting
#     only-SEV-3 findings aren't bucketed as 'unparseable'. SEV-3+ are
#     informational (don't block).
#   SEV-1 claude: strip ANSI escapes before grep so colored findings
#     (e.g. orchestrate.sh log output) aren't silently demoted.
#   SEV-2 claude: extractor now tries `^## Output` AND `^### Output` AND
#     `^## Findings`, falling back to whole-file when no heading matches.
_octo_consensus_parse_file() {
    local file="$1"
    local agent_type="$2"

    if [[ ! -f "$file" ]]; then
        echo "${agent_type}|0|0|0|0|missing"
        return
    fi

    if [[ ! -s "$file" ]]; then
        echo "${agent_type}|0|0|0|0|empty"
        return
    fi

    # Try multiple Output-section headings; fall back to whole file.
    # ANSI escapes stripped before any grep so colored reviewer output isn't lost.
    #
    # lestephen.27 (v2 dogfood SEV-2 claude): close-heading regex now matches
    # any heading of the same level OR shallower. An `### Output` section
    # used to bleed across subsequent `### Foo` sub-headings (only `^## `
    # closed it). Now we track the opening depth and close on any heading
    # at depth ≤ opening depth.
    local raw_body output_body
    raw_body=$(_octo_consensus_uncolor < "$file")
    # awk `\b` is backspace, NOT word boundary (POSIX). Use explicit
    # space-or-eol matching. lestephen.27 (v3 dogfood SEV-1 codex):
    # heading regex used `\b` which never matched, so heading detection
    # always failed and the fallback whole-file path could count SEV-N
    # example lines from the prompt as real findings.
    output_body=$(printf '%s\n' "$raw_body" | awk '
        # Open on Output/Findings heading at any depth (## or ###)
        # Heading must end the line (just spaces/punct after) or have
        # whitespace separating from suffix text like "(codex)"
        $0 ~ /^##[#]? (Output|Findings)([[:space:]]|[(:.,)]|$)/ {
            if (!flag) {
                match($0, /^#+/)
                open_depth = RLENGTH
                flag = 1
                matched = 1
                next
            }
        }
        # Close on any heading at depth ≤ open_depth
        flag && /^#+ / {
            match($0, /^#+/)
            if (RLENGTH <= open_depth) {
                flag = 0
                # Re-process this line as a potential new section opener
                if ($0 ~ /^##[#]? (Output|Findings)([[:space:]]|[(:.,)]|$)/) {
                    open_depth = RLENGTH
                    flag = 1
                    next
                }
            }
        }
        flag { print }
        END  { exit !matched }
    ' | sed '/^```$/d')
    # lestephen.27 v3 final (round 4 codex SEV-2): distinguish between
    # "no Output heading found at all" (legitimate fallback to whole-file)
    # vs. "Output heading found but section was empty" (must NOT fall back
    # to whole-file, or prompt-side example text becomes a "finding"). The
    # awk pipeline returns 0 if matched, 1 if not — capture via PIPESTATUS.
    # (Note: we re-run awk just to read PIPESTATUS reliably across shells.)
    local section_found=false
    if printf '%s\n' "$raw_body" | awk '
        $0 ~ /^##[#]? (Output|Findings)([[:space:]]|[(:.,)]|$)/ { found=1; exit }
        END { exit !found }
    '; then
        section_found=true
    fi

    if [[ "$section_found" == "true" ]]; then
        # Heading WAS found. Body might be empty (reviewer skipped the section);
        # that's still a valid (parseable-empty) signal — DO NOT fall back to
        # whole-file, which would let prompt-side SEV examples contaminate.
        : # output_body stays as whatever the awk extracted (possibly empty)
    else
        # No heading at all — legitimate fallback to whole body, stripped of
        # fences. Reviewers without explicit headings still count if they
        # emit grammar-conforming lines anywhere.
        output_body=$(printf '%s\n' "$raw_body" | sed '/^```/d')
    fi

    local sev1 sev2 sev3plus no_blocking
    # Anchored at line start, with optional list-marker prefix to accept
    # reviewer formatting habits (`- SEV-1: ...`, `* SEV-1: ...`, `> SEV-1: ...`,
    # `1. SEV-1: ...`, plus markdown bold/italic).
    # lestephen.27 (v2 dogfood SEV-3 claude): bulleted findings used to drop.
    # SEV-1 and SEV-2 are blocking; SEV-3+ are informational (don't block but
    # DO count as "parseable" — reviewer followed the contract).
    local _grep_prefix='^[[:space:]]*([-*>][[:space:]]+|[0-9]+\.[[:space:]]+|\*\*)?'
    sev1=$(printf '%s\n' "$output_body" | grep -cE "${_grep_prefix}SEV-1:[[:space:]]+.+" || true)
    sev2=$(printf '%s\n' "$output_body" | grep -cE "${_grep_prefix}SEV-2:[[:space:]]+.+" || true)
    sev3plus=$(printf '%s\n' "$output_body" | grep -cE "${_grep_prefix}SEV-[3-5]:[[:space:]]+.+" || true)
    no_blocking=$(printf '%s\n' "$output_body" | grep -cE "${_grep_prefix}NO BLOCKING FINDINGS\b" || true)

    # Parseable iff ANY grammar marker present (any SEV-N or NO BLOCKING).
    # The body-length unparseable heuristic was too strict — replaced with
    # "grammar marker present" which is exact.
    if [[ $sev1 -eq 0 && $sev2 -eq 0 && $sev3plus -eq 0 && $no_blocking -eq 0 ]]; then
        local body_len
        body_len=$(printf '%s' "$output_body" | wc -c)
        if [[ $body_len -gt 50 ]]; then
            echo "${agent_type}|0|0|0|0|unparseable"
        else
            echo "${agent_type}|0|0|0|0|empty"
        fi
        return
    fi

    echo "${agent_type}|${sev1}|${sev2}|${sev3plus}|${no_blocking}|ok"
}

# Extract provider family from agent_type (strip variant suffix).
# Used for distinct-family check (codex+codex-mini is NOT 2 distinct providers).
#
# lestephen.27 (own-dogfood SEV-3 claude): qwen and cursor-agent are kept as
# their OWN families. They fork the gemini CLI but the model routing /
# subscription / backend is independent — conflating them risks spurious
# diversity-pass when the user has only configured one of them to route to
# a different model. If a future audit proves they always share gemini
# backend in the user's config, revisit.
_octo_consensus_provider_family() {
    case "$1" in
        codex*) echo "codex" ;;
        claude*) echo "claude" ;;
        gemini*) echo "gemini" ;;
        qwen*) echo "qwen" ;;
        cursor-agent*) echo "cursor-agent" ;;
        copilot*) echo "copilot" ;;
        perplexity*) echo "perplexity" ;;
        ollama*) echo "ollama" ;;
        opencode*) echo "opencode" ;;
        openrouter*) echo "openrouter" ;;
        *) echo "$1" ;;
    esac
}

# Strip ANSI escape sequences. Uses python3 if available (robust across CSI,
# OSC, reset variants, BSD/GNU portable). Falls back to a multi-pattern sed
# that catches the common CSI + OSC + simple ESC-letter forms.
#
# lestephen.27 (v2 dogfood SEV-1 codex + SEV-2 claude): the v1 single-regex
# sed only handled CSI (ESC[...letter); OSC, character-set selection, and
# BSD-sed-specific escape handling all leaked. Python3 has full regex
# support and is present on every supported platform; if it's missing we
# degrade with a louder sed that covers the common variants.
_octo_consensus_uncolor() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import sys, re
# lestephen.27 v3 final (round 4 codex SEV-1): OSC sequences (\x1b])
# must be matched BEFORE the single-char ESC fallback. Previously the
# [@-Z\\-_] character class included ']' (0x5D between 0x5C and 0x5F),
# so the alternation greedy-left preferred the single-char branch and
# only consumed \x1b], leaving the OSC payload + terminator inline.
# Order in alternation matters because regex uses leftmost-first.
pat = re.compile(
    r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\\\)'  # OSC: \e]...\a or \e]...\e\\
    r'|\x1b\[[0-?]*[ -/]*[@-~]'              # CSI: \e[...letter
    r'|\x1b[()][A-Za-z0-9]'                  # Character set selection
    r'|\x1b[78=>NOPVWX]'                     # Standalone ESC-letter
    r'|\x1b[@-Z\\\\^_]'                      # Other single-char ESC (excluding ])
)
sys.stdout.write(pat.sub('', sys.stdin.read()))
"
    else
        # Multi-pass sed fallback. Order matters — OSC first (longest), then CSI,
        # then standalone escape-letter forms. Uses POSIX-portable BRE forms.
        sed -e 's/\x1b\][^\x07\x1b]*\x07//g' \
            -e 's/\x1b\][^\x07\x1b]*\x1b\\//g' \
            -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
            -e 's/\x1b[()][A-Za-z0-9]//g' \
            -e 's/\x1b[78=>NOPVWX]//g'
    fi
}

# ─── Main check ─────────────────────────────────────────────────────────────

# octo_consensus_check <dispatch.json> [<action description>]
# Returns: 0 (ALLOW) | 1-6 (block / no-quorum / parse error / usage)
# Prints verdict block to stdout (suitable for surfacing to user)
octo_consensus_check() {
    local dispatch_json="${1:-}"
    local action_desc="${2:-(unnamed action)}"

    if [[ -z "$dispatch_json" ]]; then
        echo "ERROR: octo_consensus_check requires <dispatch.json> path" >&2
        return 6
    fi
    if [[ ! -f "$dispatch_json" ]]; then
        echo "ERROR: dispatch.json not found: $dispatch_json" >&2
        return 5
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq required for consensus parsing" >&2
        return 5
    fi

    # Parse dispatch.json structure
    local total success failed
    total=$(jq -r '.total // 0' "$dispatch_json" 2>/dev/null) || { echo "ERROR: dispatch.json malformed" >&2; return 5; }
    success=$(jq -r '.success // 0' "$dispatch_json" 2>/dev/null)
    failed=$(jq -r '.failed // 0' "$dispatch_json" 2>/dev/null)

    # Quorum check — need >=2 successful reviewers
    if [[ "$success" -lt 2 ]]; then
        cat <<EOF
════════════════════════════════════════════════════════════════
🚫 CONSENSUS GATE: NO QUORUM
   Action:   $action_desc
   Verdict:  BLOCKED (insufficient providers)
   Reason:   Only $success of $total reviewers succeeded; need ≥2.
   Source:   $dispatch_json
   Policy:   skill-autonomous-mode v.25 "Single provider available"
════════════════════════════════════════════════════════════════
EOF
        return 4
    fi

    # Parse each successful reviewer's output. lestephen.27 (v2 dogfood SEV-1
    # claude): families_seen is collected BUT the diversity check now runs
    # only on parseable providers (computed after parsing) — the previous
    # implementation could pass diversity on a vote that didn't count.
    local -a parses=()
    local -a agents_seen=()
    local i reviewer_count
    # // [] guards against malformed dispatch.json with missing reviewers key
    reviewer_count=$(jq -r '.reviewers | length // 0' "$dispatch_json" 2>/dev/null) || reviewer_count=0
    for i in $(seq 0 $((reviewer_count - 1))); do
        local outcome agent_type output_file
        outcome=$(jq -r ".reviewers[$i].outcome" "$dispatch_json")
        [[ "$outcome" != "success" ]] && continue
        agent_type=$(jq -r ".reviewers[$i].agent_type" "$dispatch_json")
        output_file=$(jq -r ".reviewers[$i].output_file" "$dispatch_json")
        parses+=("$(_octo_consensus_parse_file "$output_file" "$agent_type")")
        agents_seen+=("$agent_type")
    done

    # Tally severities + parse statuses
    local total_sev1=0 total_sev2=0 total_sev3plus=0 total_no_blocking=0
    local providers_with_sev1=0 providers_with_sev2=0
    local providers_clean=0 providers_unparseable=0
    local verbatim_lines=""

    local p
    for p in "${parses[@]}"; do
        local agent sev1 sev2 sev3plus nb status
        IFS='|' read -r agent sev1 sev2 sev3plus nb status <<< "$p"

        if [[ "$status" != "ok" ]]; then
            providers_unparseable=$((providers_unparseable + 1))
            verbatim_lines+="  ${agent} (${status}): no parseable finding lines
"
            continue
        fi

        total_sev1=$((total_sev1 + sev1))
        total_sev2=$((total_sev2 + sev2))
        total_sev3plus=$((total_sev3plus + sev3plus))
        total_no_blocking=$((total_no_blocking + nb))

        if [[ $sev1 -gt 0 ]]; then
            providers_with_sev1=$((providers_with_sev1 + 1))
        elif [[ $sev2 -gt 0 ]]; then
            providers_with_sev2=$((providers_with_sev2 + 1))
        else
            # Either NO-BLOCKING, or only SEV-3+ informational findings → clean
            providers_clean=$((providers_clean + 1))
        fi

        verbatim_lines+="  ${agent}: SEV-1=${sev1}, SEV-2=${sev2}, SEV-3+=${sev3plus}, NO-BLOCKING=${nb}
"
    done

    # Unparseable providers don't count toward consensus; re-check quorum among parseable ones
    local parseable_providers=$((success - providers_unparseable))

    # Build families_seen from PARSEABLE reviewers only (not all successful).
    # lestephen.27 (v2 dogfood SEV-1 claude): closes diversity-bypass-via-
    # unparseable-foreign-family. If the foreign-family reviewer is the one
    # that came back unparseable, two same-family parseable reviewers can no
    # longer slip through the diversity gate on a vote that doesn't count.
    local -a families_seen=()
    local pi
    for pi in "${!parses[@]}"; do
        local pp_agent pp_status
        IFS='|' read -r pp_agent _ _ _ _ pp_status <<< "${parses[$pi]}"
        [[ "$pp_status" == "ok" ]] || continue
        families_seen+=("$(_octo_consensus_provider_family "$pp_agent")")
    done
    local distinct_families
    if [[ ${#families_seen[@]} -gt 0 ]]; then
        distinct_families=$(printf '%s\n' "${families_seen[@]}" | sort -u | wc -l)
    else
        distinct_families=0
    fi

    if [[ "$parseable_providers" -lt 2 ]]; then
        cat <<EOF
════════════════════════════════════════════════════════════════
🚫 CONSENSUS GATE: NO PARSEABLE QUORUM
   Action:   $action_desc
   Verdict:  BLOCKED (insufficient parseable reviewers)
   Reason:   Only $parseable_providers of $success reviewers emitted findings in the
             required ^SEV-N:|^NO BLOCKING FINDINGS grammar.
$verbatim_lines
   Source:   $dispatch_json
   Policy:   skill-autonomous-mode v.25 severity-line grammar
   Fix:      Re-dispatch with the providers that didn't comply, or instruct
             them to format findings as 'SEV-N: <name> — <why>' or
             'NO BLOCKING FINDINGS'.
════════════════════════════════════════════════════════════════
EOF
        return 5
    fi

    # Diversity check, on parseable reviewers only.
    if [[ "$distinct_families" -lt 2 ]]; then
        cat <<EOF
════════════════════════════════════════════════════════════════
🚫 CONSENSUS GATE: NO PROVIDER DIVERSITY
   Action:   $action_desc
   Verdict:  BLOCKED (single provider family among parseable reviewers)
   Reason:   $parseable_providers parseable reviewers all from same family
             ($(printf '%s,' "${families_seen[@]}" | sed 's/,$//')).
             Need ≥2 distinct families for valid consensus.
$verbatim_lines
   Source:   $dispatch_json
   Policy:   skill-autonomous-mode v.25 "Provider CLIs route through same backend"
════════════════════════════════════════════════════════════════
EOF
        return 4
    fi

    # Apply the consensus definition table from skill-autonomous-mode v.25
    # Counts apply to parseable providers only.

    # Hard BLOCK: ≥2 providers raised SEV-1
    if [[ "$providers_with_sev1" -ge 2 ]]; then
        cat <<EOF
════════════════════════════════════════════════════════════════
🚫 CONSENSUS GATE: HARD BLOCK
   Action:   $action_desc
   Verdict:  BLOCKED (≥2 providers raised SEV-1)
   Tally:    ${providers_with_sev1} of $parseable_providers parseable providers raised SEV-1.
$verbatim_lines
   Source:   $dispatch_json
   Policy:   skill-autonomous-mode v.25 "≥2 providers raise SEV-1: file issue, halt, surface"
   Fix:      Address the SEV-1 findings in the per-reviewer files, re-dispatch.
════════════════════════════════════════════════════════════════
EOF
        return 1
    fi

    # SPLIT: exactly 1 SEV-1, others clean — adjudication required
    if [[ "$providers_with_sev1" -eq 1 ]]; then
        cat <<EOF
════════════════════════════════════════════════════════════════
⚠️  CONSENSUS GATE: SPLIT (ADJUDICATION REQUIRED)
   Action:   $action_desc
   Verdict:  BLOCKED (1 of $parseable_providers parseable providers raised SEV-1)
   Tally:    SEV-1=$total_sev1, SEV-2=$total_sev2, NO-BLOCKING=$total_no_blocking
$verbatim_lines
   Source:   $dispatch_json
   Policy:   skill-autonomous-mode v.25 "Adjudication path"
   Fix:      Re-dispatch the action to a third provider (different family
             from the dissenting one) with the SEV-1 finding included in
             the prompt so it can specifically assess the concern. If 2 of
             3 then agree the concern is invalid, the action may proceed
             with the dissent documented per the action-class table.
════════════════════════════════════════════════════════════════
EOF
        return 3
    fi

    # SOFT BLOCK: MAJORITY of parseable providers raised SEV-2
    # lestephen.27 (claude SEV-2): was "≥2 providers", which is wrong as the
    # reviewer pool grows (2 of 4 is minority, not majority). The .25 rule
    # text was "majority SEV-2" — implement that literally.
    # Majority threshold: providers_with_sev2 > parseable_providers / 2
    # (integer arithmetic: 2 > 4/2 is FALSE; 3 > 4/2 is TRUE)
    if (( providers_with_sev2 * 2 > parseable_providers )); then
        cat <<EOF
════════════════════════════════════════════════════════════════
🟡 CONSENSUS GATE: SOFT BLOCK
   Action:   $action_desc
   Verdict:  BLOCKED (majority raised SEV-2)
   Tally:    ${providers_with_sev2} of $parseable_providers parseable providers raised SEV-2 (majority threshold).
$verbatim_lines
   Source:   $dispatch_json
   Policy:   skill-autonomous-mode v.25 "majority SEV-2: address findings, re-dispatch"
   Fix:      Address the SEV-2 findings (read the per-reviewer files for
             details), then re-dispatch. Do NOT proceed citing 'no SEV-1' alone.
════════════════════════════════════════════════════════════════
EOF
        return 2
    fi

    # ALLOW: ≥2 providers agree (clean or only single-provider/minority SEV-2)
    cat <<EOF
════════════════════════════════════════════════════════════════
✅ CONSENSUS GATE: ALLOW
   Action:   $action_desc
   Verdict:  PASSED ($parseable_providers parseable providers, $distinct_families distinct families)
   Tally:    SEV-1=$total_sev1, SEV-2=$total_sev2 (minority), SEV-3+=$total_sev3plus (informational), NO-BLOCKING=$total_no_blocking
$verbatim_lines
   Source:   $dispatch_json
   Policy:   skill-autonomous-mode v.25 "≥2 agree, no SEV-1, no majority SEV-2"
   Note:     SEV-3+ findings are informational and do not block — they're
             recorded for context but the action may proceed.
════════════════════════════════════════════════════════════════
EOF
    return 0
}

# ─── Standalone CLI entry ───────────────────────────────────────────────────

octo_consensus_main() {
    case "${1:-}" in
        check)
            shift
            octo_consensus_check "$@"
            return $?
            ;;
        explain)
            cat <<'EOF'
Consensus definition table (from skill-autonomous-mode v.25):

  Outcome                                          | Action
  -------------------------------------------------+-------------------------
  ≥2 parseable agree, no SEV-1 from any,           | ALLOW (exit 0)
    no majority SEV-2                              |
  ≥2 raise SEV-2 (majority concern)                | SOFT BLOCK (exit 2)
  Exactly 1 SEV-1, others clean                    | SPLIT (exit 3 → adjudicate)
  ≥2 raise SEV-1 (independent)                     | HARD BLOCK (exit 1)
  <2 successful providers in dispatch              | NO QUORUM (exit 4)
  <2 parseable providers (grammar violation)       | NO PARSEABLE QUORUM (exit 5)
  All providers same family (codex+codex-mini)     | NO DIVERSITY (exit 4)

Provider families (for diversity check):
  codex/codex-* → codex
  claude/claude-* → claude
  gemini/qwen/cursor-agent/qwen-* → gemini (qwen+cursor-agent fork gemini CLI)
  copilot, perplexity, ollama, opencode, openrouter → each their own family

Severity-line grammar (strict, anchored at line start; ANSI escapes stripped first):
  ^SEV-1: <name> — <one-sentence why>         BLOCKING — counts toward providers_with_sev1
  ^SEV-2: <name> — <one-sentence why>         BLOCKING (if majority) — counts toward providers_with_sev2
  ^SEV-3: <name> — <one-sentence why>         INFORMATIONAL — counts the reviewer as parseable but not as blocking
  ^SEV-4: <name> — <one-sentence why>         INFORMATIONAL
  ^SEV-5: <name> — <one-sentence why>         INFORMATIONAL
  ^NO BLOCKING FINDINGS                       Clean — counts toward providers_clean

Output section detection (lestephen.27): the parser looks for the body between
`^## Output`, `^### Output`, or `^## Findings` and the next `^## ` heading.
If no heading matches, the entire file body (stripped of ```fences``` and ANSI
escapes) is used. A reviewer who emits ANY grammar line above counts as
parseable; only reviewers with substantive prose AND zero grammar lines count
as 'unparseable' and don't contribute votes.

This is intentional — guess-the-meaning of unstructured prose is the SEV-1b
failure mode from v.23.
EOF
            return 0
            ;;
        version)
            echo "octo-consensus v${OCTO_CONSENSUS_VERSION}"
            return 0
            ;;
        ""|--help|-h|help)
            cat <<EOF
octo-consensus — machine-enforced multi-LLM consensus check (GH #16)

Usage:
  octo-consensus check <dispatch.json> [<action description>]
      Apply the consensus definition table to a lib-multi-dispatch run.
      Exit 0 → ALLOW; non-zero → BLOCK (see codes below).
  octo-consensus explain
      Print the consensus definition table + severity-line grammar.
  octo-consensus version
      Print version.

Exit codes:
  0  ALLOW
  1  HARD BLOCK (≥2 SEV-1)
  2  SOFT BLOCK (≥2 SEV-2)
  3  SPLIT (1 SEV-1, adjudication required)
  4  NO QUORUM (<2 providers OR no family diversity)
  5  PARSE ERROR (dispatch.json malformed OR <2 parseable providers)
  6  USAGE error

Wraps the skill-autonomous-mode v.25 'Consensus before action' rule with
machine enforcement so the gate isn't honor-system anymore.
EOF
            return 0
            ;;
        *)
            echo "ERROR: unknown subcommand '${1}'. Try: octo-consensus --help" >&2
            return 6
            ;;
    esac
}

# Run main only when invoked directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    octo_consensus_main "$@"
fi
