#!/usr/bin/env bash
# Claude Octopus — Code Review Pipeline
# Extracted from orchestrate.sh
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════
# CODE REVIEW PIPELINE (v8.50.0)
# review_run() — multi-LLM competitor to CC Code Review managed service
# ═══════════════════════════════════════════════════════════════════════════

# parse_review_md: reads REVIEW.md from repo root, outputs directive vars
# WHY: CC Code Review supports REVIEW.md for customization; we match that
# convention so repos already configured for CC work with /octo:review too.
parse_review_md() {
    local repo_root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    local review_md="$repo_root/REVIEW.md"

    REVIEW_ALWAYS_CHECK=""
    REVIEW_STYLE_RULES=""
    REVIEW_SKIP_PATTERNS=""

    [[ ! -f "$review_md" ]] && return 0

    local section=""
    while IFS= read -r line; do
        case "$line" in
            "## Always check"|"## Always Check") section="always" ;;
            "## Style")                          section="style" ;;
            "## Skip")                           section="skip" ;;
            "## "*)                              section="" ;;
            "- "*)
                local item="${line#- }"
                case "$section" in
                    always) REVIEW_ALWAYS_CHECK+="${item}"$'\n' ;;
                    style)  REVIEW_STYLE_RULES+="${item}"$'\n' ;;
                    skip)   REVIEW_SKIP_PATTERNS+="${item}"$'\n' ;;
                esac
                ;;
        esac
    done < "$review_md"

    log DEBUG "parse_review_md: always=$(echo "$REVIEW_ALWAYS_CHECK" | wc -l) style=$(echo "$REVIEW_STYLE_RULES" | wc -l) skip=$(echo "$REVIEW_SKIP_PATTERNS" | wc -l)"
}

# _review_fleet_from_config (v9.31.0): build fleet from routing.features.review
# in providers.json. /octo:model-config wizard already writes a "Review providers"
# array to this path; before this change there was no consumer, so the wizard's
# selection had no effect. Returns empty when config absent/empty so callers fall
# back to the cascade.
# Output: agent_type:role:specialty triples, newline-separated.
_review_fleet_from_config() {
    local config_file="${HOME}/.claude-octopus/config/providers.json"
    [[ ! -f "$config_file" ]] && return 0
    command -v jq >/dev/null 2>&1 || return 0

    local participants
    participants=$(jq -r '
        (.routing.features.review // [])
        | if type == "array" then .[] else empty end
    ' "$config_file" 2>/dev/null)
    [[ -z "$participants" ]] && return 0

    local fleet=""
    local has_logic=false has_security=false has_arch=false has_cve=false has_diversity=false

    while IFS= read -r provider; do
        [[ -z "$provider" ]] && continue
        case "$provider" in
            codex|codex-*)
                if [[ "$has_logic" == "false" ]]; then
                    fleet+="${provider}:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
                    has_logic=true
                fi
                ;;
            opencode|opencode-*)
                if [[ "$has_logic" == "false" ]]; then
                    fleet+="${provider}:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
                    has_logic=true
                fi
                ;;
            gemini|gemini-*)
                if [[ "$has_security" == "false" ]]; then
                    fleet+="${provider}:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
                    has_security=true
                fi
                ;;
            claude|claude-sonnet|claude-opus)
                if [[ "$has_arch" == "false" ]]; then
                    local agent="${provider}"
                    [[ "$provider" == "claude" ]] && agent="claude-sonnet"
                    fleet+="${agent}:arch-reviewer:architecture, integration, API contracts, breaking changes"$'\n'
                    has_arch=true
                fi
                ;;
            perplexity|perplexity-*)
                if [[ "$has_cve" == "false" ]]; then
                    fleet+="${provider}:cve-reviewer:known CVEs, library advisories, live web search"$'\n'
                    has_cve=true
                fi
                ;;
            openrouter|openrouter-*)
                if [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:diversity-reviewer:cross-family perspective on logic, missed assumptions, training-data divergence from primary providers"$'\n'
                    has_diversity=true
                fi
                ;;
            qwen|qwen-*)
                if [[ "$has_security" == "false" ]]; then
                    fleet+="${provider}:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
                    has_security=true
                elif [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:diversity-reviewer:cross-family perspective on logic and assumptions"$'\n'
                    has_diversity=true
                fi
                ;;
            copilot|copilot-*)
                if [[ "$has_cve" == "false" ]]; then
                    fleet+="${provider}:cve-reviewer:known CVEs via web search, library advisories"$'\n'
                    has_cve=true
                elif [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:diversity-reviewer:cross-perspective review"$'\n'
                    has_diversity=true
                fi
                ;;
        esac
    done <<< "$participants"

    [[ -z "$fleet" ]] && return 0

    # Anchor: always include arch-reviewer (claude-sonnet) if config didn't supply one.
    # Architecture context bridges per-finding noise from the specialist agents.
    if [[ "$has_arch" == "false" ]]; then
        fleet+="claude-sonnet:arch-reviewer:architecture, integration, API contracts, breaking changes"$'\n'
    fi

    log INFO "review fleet: config-driven (.routing.features.review)"
    echo "$fleet"
}

# build_review_fleet: builds active agent list. Config-driven if
# .routing.features.review is set in ~/.claude-octopus/config/providers.json
# (the path /octo:model-config writes to); otherwise falls back to the original
# command -v cascade so existing installations are unchanged.
# Returns a newline-separated list of "agent_type:role:specialty" triples.
# NOTE: Uses command -v for provider detection — safe with set -euo pipefail.
build_review_fleet() {
    local fleet=""

    # v9.31.0: honor wizard-configured participants if present
    fleet=$(_review_fleet_from_config)
    if [[ -n "$fleet" ]]; then
        echo "$fleet"
        return 0
    fi

    # ── Cascade fallback (original behavior — no config or empty config) ──

    # logic-reviewer: Codex (OpenAI) → OpenCode → Copilot → claude-sonnet fallback
    if command -v codex >/dev/null 2>&1; then
        fleet+="codex:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    elif command -v opencode >/dev/null 2>&1; then
        fleet+="opencode:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    elif command -v copilot >/dev/null 2>&1; then
        fleet+="copilot:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    else
        fleet+="claude-sonnet:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    fi

    # security-reviewer: Gemini (Google) → Qwen → Copilot → claude-sonnet fallback
    # Prefer different family from logic-reviewer for diversity
    if command -v gemini >/dev/null 2>&1; then
        fleet+="gemini:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    elif command -v qwen >/dev/null 2>&1; then
        fleet+="qwen:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    elif command -v copilot >/dev/null 2>&1; then
        fleet+="copilot:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    else
        fleet+="claude-sonnet:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    fi

    # arch-reviewer: claude-sonnet (always available — best at holistic analysis)
    fleet+="claude-sonnet:arch-reviewer:architecture, integration, API contracts, breaking changes"$'\n'

    # cve-reviewer: Perplexity → Gemini search → Copilot → Qwen → claude WebSearch
    if command -v perplexity >/dev/null 2>&1 || [[ -n "${PERPLEXITY_API_KEY:-}" ]]; then
        fleet+="perplexity:cve-reviewer:known CVEs, library advisories, live web search"$'\n'
    elif command -v gemini >/dev/null 2>&1; then
        fleet+="gemini:cve-reviewer:known CVEs via web search, library advisories"$'\n'
        log INFO "CVE lookup: Perplexity unavailable, using Gemini search"
    elif command -v copilot >/dev/null 2>&1; then
        fleet+="copilot:cve-reviewer:known CVEs via web search, library advisories"$'\n'
        log INFO "CVE lookup: Perplexity+Gemini unavailable, using Copilot"
    elif command -v qwen >/dev/null 2>&1; then
        fleet+="qwen:cve-reviewer:known CVEs via web search, library advisories"$'\n'
        log INFO "CVE lookup: Perplexity+Gemini unavailable, using Qwen"
    else
        fleet+="claude-sonnet:cve-reviewer:known CVEs via WebSearch tool, library advisories"$'\n'
        log WARN "CVE lookup: no dedicated web-search provider, using Claude WebSearch (degraded)"
    fi

    echo "$fleet"
}

# review_collect_diff: resolves a review target to unified diff content.
# Targets can be built-in scopes (staged, working-tree, branch), a PR number,
# a git pathspec, or an already-generated .diff/.patch file.
#
# lestephen.35 (closes petrics dogfood SEV-1 on GH #11 reopen): `branch` was
# silently falling through to the pathspec arm, producing an empty diff and
# a "No issues found" false-negative review. Now properly resolved to
# `git diff <merge-base>..HEAD` against the supplied base ref.
review_collect_diff() {
    local target="$1"
    local base="${2:-}"  # optional base ref for branch-scope; defaults to origin/HEAD
    local diff_content=""

    case "$target" in
        staged)       diff_content=$(git diff --cached 2>/dev/null || true) ;;
        working-tree) diff_content=$(git diff 2>/dev/null || true) ;;
        branch)
            # Resolve effective base: explicit > origin/HEAD's branch >
            # origin/main > main > fail loudly. Refuse silent default to "" —
            # that's what made the original bug a silent false-negative.
            local _eff_base="$base"
            if [[ -z "$_eff_base" ]]; then
                _eff_base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
            fi
            if [[ -z "$_eff_base" ]] && git rev-parse --verify --quiet origin/main >/dev/null; then
                _eff_base="origin/main"
            fi
            if [[ -z "$_eff_base" ]] && git rev-parse --verify --quiet main >/dev/null; then
                _eff_base="main"
            fi
            if [[ -z "$_eff_base" ]]; then
                # Refuse rather than silently produce empty diff — branch-target
                # was the literal SEV-1 from petrics dogfood. Emit a magic
                # sentinel that review_run detects to fail loudly.
                echo "BRANCH_BASE_UNRESOLVED" >&2
                return 0
            fi
            local _mb
            _mb=$(git merge-base HEAD "$_eff_base" 2>/dev/null || true)
            if [[ -z "$_mb" ]]; then
                echo "BRANCH_MERGEBASE_UNRESOLVED:$_eff_base" >&2
                return 0
            fi
            diff_content=$(git diff "$_mb..HEAD" 2>/dev/null || true)
            ;;
        [0-9]*)       diff_content=$(gh pr diff "$target" 2>/dev/null || true) ;;
        *)
            if [[ -f "$target" ]] && [[ -r "$target" ]] && head -n 20 "$target" 2>/dev/null | grep -Ec "^(diff --git|--- |\+\+\+ |@@ )" >/dev/null; then
                diff_content=$(cat "$target" 2>/dev/null || true)
            else
                diff_content=$(git diff HEAD -- "$target" 2>/dev/null || true)
            fi
            ;;
    esac

    printf '%s' "$diff_content"
}

# review_run: canonical 3-round multi-LLM code review pipeline
# WHY: replaces the single-model "codex exec review" dispatch with a
# v9.0: Provider report card — prints post-run summary of provider status
# Args: provider_status_file (one line per event: "provider|status|detail")
# WHY: Mid-stream warnings vanish in terminal scroll. This prints AFTER all output,
# making provider failures impossible to miss.
print_provider_report() {
    local status_file="$1"
    local fallback_log="${HOME}/.claude-octopus/provider-fallbacks.log"

    if [[ ! -f "$status_file" ]]; then
        return 0
    fi

    # Determine status per provider
    local codex_status="not used" gemini_status="not used" claude_status="✓ OK" perplexity_status="not used"
    local codex_detail="" gemini_detail="" perplexity_detail=""
    local had_fallback=false

    while IFS='|' read -r provider status detail; do
        case "$provider" in
            codex)
                if [[ "$status" == "ok" ]]; then
                    codex_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    codex_status="✗ FALLBACK"
                    codex_detail="$detail"
                    had_fallback=true
                elif [[ "$status" == "auth-failed" ]]; then
                    codex_status="✗ AUTH FAILED"
                    codex_detail="$detail"
                    had_fallback=true
                fi
                ;;
            gemini)
                if [[ "$status" == "ok" ]]; then
                    gemini_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    gemini_status="✗ FALLBACK"
                    gemini_detail="$detail"
                    had_fallback=true
                fi
                ;;
            perplexity)
                if [[ "$status" == "ok" ]]; then
                    perplexity_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    perplexity_status="✗ FALLBACK"
                    perplexity_detail="$detail"
                    had_fallback=true
                fi
                ;;
        esac
    done < "$status_file"

    # Always print the report card
    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│ 🐙 Provider Status                          │"
    echo "│                                             │"
    printf "│ 🔴 Codex:      %-28s│\n" "$codex_status"
    [[ -n "$codex_detail" ]] && printf "│    → %-38s│\n" "$codex_detail"
    printf "│ 🟡 Gemini:     %-28s│\n" "$gemini_status"
    [[ -n "$gemini_detail" ]] && printf "│    → %-38s│\n" "$gemini_detail"
    printf "│ 🔵 Claude:     %-28s│\n" "$claude_status"
    printf "│ 🟣 Perplexity: %-28s│\n" "$perplexity_status"
    [[ -n "$perplexity_detail" ]] && printf "│    → %-38s│\n" "$perplexity_detail"
    if [[ "$had_fallback" == "true" ]]; then
        echo "│                                             │"
        echo "│ ⚠ Some providers failed — run /octo:doctor  │"
    fi
    echo "└─────────────────────────────────────────────┘"

    # Persist failures for /octo:doctor
    if [[ "$had_fallback" == "true" ]]; then
        mkdir -p "$(dirname "$fallback_log")"
        local ts
        ts=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
        while IFS='|' read -r provider status detail; do
            if [[ "$status" == "fallback" || "$status" == "auth-failed" ]]; then
                echo "[$ts] provider=$provider status=$status detail=$detail" >> "$fallback_log"
            fi
        done < "$status_file"
        # Keep only last 50 entries
        if [[ -f "$fallback_log" ]] && [[ $(wc -l < "$fallback_log") -gt 50 ]]; then
            tail -50 "$fallback_log" > "${fallback_log}.tmp" && mv "${fallback_log}.tmp" "$fallback_log"
        fi
    fi

    rm -f "$status_file"
}

# parallel fleet (Round 1) + verification (Round 2) + synthesis (Round 3)
# that competes with CC Code Review's managed service.
#
# Args: JSON profile string with fields:
#   target, focus, provenance, autonomy, publish, debate
review_run() {
    local _ts; _ts=$(date +%s)
    local profile_json="${1:-"{}"}"

    # Parse profile fields (with defaults)
    local target focus provenance autonomy publish debate history reference
    target=$(echo "$profile_json"     | jq -r '.target     // "staged"')
    focus=$(echo "$profile_json"      | jq -r '.focus      // ["correctness","security","architecture","tdd"]  | join(",")')
    provenance=$(echo "$profile_json" | jq -r '.provenance // "unknown"')
    autonomy=$(echo "$profile_json"   | jq -r '.autonomy   // "supervised"')
    publish=$(echo "$profile_json"    | jq -r '.publish    // "ask"')
    debate=$(echo "$profile_json"     | jq -r '.debate     // "auto"')
    history=$(echo "$profile_json"    | jq -r '.history    // "auto"')
    # lestephen.35 (petrics dogfood SEV-1 on GH #11): parse `base` field
    # so target=branch can compute merge-base diff against the right ref.
    # Previously `base` was set by /octo:visual-review but never read.
    local base
    base=$(echo "$profile_json"       | jq -r '.base       // ""')
    # lestephen.23: optional `reference` field — a path to the source-of-truth
    # artifact (mockup PNG, screenshot, design spec PDF). When set, the
    # mockup-context preamble is prepended to every reviewer prompt so reviewers
    # are explicitly forced to engage with the artifact rather than only the
    # code-internal consistency. Closes the cheapest leg of GH #11. Full pixel-
    # attachment via --image plumbing into spawn_agent is a follow-up.
    reference=$(echo "$profile_json"  | jq -r '.reference  // ""')
    # lestephen.33 (closes GH #11 expensive-leg cheap-half): optional
    # `visual.*` profile fields drive the sample-pixel/delta-e tooling.
    # Without these, the cheap leg from .23 still applies — preamble only.
    # With them, reviewers are instructed to actually CALL the tools per
    # token, closing the "no tool means eyeballing" gap from team feedback.
    local visual_delta_e_threshold visual_render_script visual_preexisting_pass
    visual_delta_e_threshold=$(echo "$profile_json" | jq -r '.visual.delta_e_threshold // 5.0')
    visual_render_script=$(echo "$profile_json"     | jq -r '.visual.render_script    // ""')
    # lestephen.38 (closes GH #22): opt-in flag to run a pre-existing-state
    # pass — reviewers sample the reference artifact for any visible feature
    # and flag contradictions in current file state (NOT just the diff).
    # Default false because it's noisier; petrics opted in for defense-in-depth
    # against pre-existing divergences (Pixi bg literal that was wrong before
    # the diff but only surfaced when reviewing rendered output).
    visual_preexisting_pass=$(echo "$profile_json" | jq -r '.visual.preexisting_pass // false')
    if [[ "$target" == "fresh" ]]; then
        target="working-tree"
        history="fresh"
    fi

    # Validate reference path if set — surface broken paths early
    if [[ -n "$reference" && ! -f "$reference" ]]; then
        log "WARN" "review_run: reference path does not exist: $reference (skipping preamble)"
        reference=""
    fi
    # Validate render_script if set
    if [[ -n "$visual_render_script" && ! -x "$visual_render_script" ]]; then
        log "WARN" "review_run: visual.render_script not executable: $visual_render_script (skipping render-diff)"
        visual_render_script=""
    fi

    # lestephen.28 (closes GH #14): export the reference path as OCTO_AGENT_IMAGES
    # so spawn_agent (Round 1 fleet) and run_agent_sync (Round 2 verification,
    # Round 3 synthesis) all attach the image via the shared image-attach
    # helper. Previously the reference field only injected a text preamble;
    # the reviewers couldn't actually see pixels.
    #
    # Stash/restore the env var around the review so it doesn't leak past
    # this function (consensus SEV-2 from both codex+claude: stale
    # OCTO_AGENT_IMAGES could attach prior review's image to subsequent
    # dispatches in the same shell). Distinguish "unset" from "set-but-empty"
    # using ${VAR+set} so a caller's "" is restored as "" (not unset),
    # closing the v2 SEV-3 claude flagged.
    local _saved_octo_agent_images_was_set="${OCTO_AGENT_IMAGES+yes}"
    local _saved_octo_agent_images="${OCTO_AGENT_IMAGES:-}"
    local _restore_octo_agent_images=false

    # lestephen.42 (closes GH #19): defensive cleanup helper used by BOTH
    # the RETURN trap AND an explicit call at the end of review_run.
    # Belt-and-suspenders against the gemini SEV-2 (nested function setting
    # its own RETURN trap clobbering ours) and the claude SEV-3
    # (export-before-trap leak window — addressed by installing the trap
    # BEFORE we export). Idempotent: safe to call twice.
    _review_restore_octo_agent_images() {
        [[ "$_restore_octo_agent_images" == "true" ]] || return 0
        if [[ "$_saved_octo_agent_images_was_set" != "yes" ]]; then
            unset OCTO_AGENT_IMAGES
        else
            export OCTO_AGENT_IMAGES="$_saved_octo_agent_images"
        fi
        # Mark restored so a redundant call is a true no-op.
        _restore_octo_agent_images=false
    }

    # Install the trap BEFORE export so a failure inside the resolve-path
    # block (or the export itself under set -e) can't bypass restoration.
    # _restore_octo_agent_images stays false until we successfully export,
    # so the trap is a no-op until then. Signal-interrupt (SIGINT) cleanup
    # is moot — OCTO_AGENT_IMAGES is exported into this orchestrate.sh
    # process only; when the process dies, the env var dies with it. The
    # trap only matters for restoring across function returns within this
    # same shell process.
    trap _review_restore_octo_agent_images RETURN

    if [[ -n "$reference" ]]; then
        # Use realpath -m for robust absolution (works even if parent path is
        # tricky); fall back to cd-based for portability if realpath missing.
        # Closes consensus SEV-3 (claude): cd-fallback silently emitted
        # "/<basename>" when cd failed.
        local _ref_abs=""
        if command -v realpath >/dev/null 2>&1; then
            _ref_abs=$(realpath -m "$reference" 2>/dev/null)
        fi
        if [[ -z "$_ref_abs" ]]; then
            local _ref_dir
            _ref_dir=$(cd "$(dirname "$reference")" 2>/dev/null && pwd)
            if [[ -n "$_ref_dir" ]]; then
                _ref_abs="$_ref_dir/$(basename "$reference")"
            else
                log "WARN" "review_run: could not resolve absolute path for reference=$reference; skipping image export"
                _ref_abs=""
            fi
        fi
        if [[ -n "$_ref_abs" ]]; then
            export OCTO_AGENT_IMAGES="$_ref_abs"
            _restore_octo_agent_images=true
            log "INFO" "review_run: exporting OCTO_AGENT_IMAGES=$_ref_abs for review fleet"
        fi
    fi

    # v9.0: Provider status tracking for post-run report card
    local provider_status_file
    provider_status_file=$(mktemp "${TMPDIR:-/tmp}/octopus-provider-status.XXXXXX")

    # v9.0: Preflight — check Codex auth before review pipeline
    if command -v codex >/dev/null 2>&1; then
        if ! check_codex_auth_freshness 2>/dev/null; then
            log "WARN" "review_run: Codex auth may be stale — review fleet may fall back to claude-sonnet"
            log "USER" "⚠ Codex auth check failed. Run 'codex auth' or /octo:doctor to fix. Falling back to claude-sonnet for Codex roles."
            echo "codex|auth-failed|Run: codex auth" >> "$provider_status_file"
        fi
    else
        echo "codex|not-installed|Install: npm i -g @openai/codex" >> "$provider_status_file"
    fi

    local timestamp="$_ts"
    local results_dir="${RESULTS_DIR:-$HOME/.claude-octopus/results}"
    # Sync RESULTS_DIR global so spawn_agent writes to the same directory
    RESULTS_DIR="$results_dir"
    local findings_file="$results_dir/review-findings-${timestamp}.json"
    mkdir -p "$results_dir"

    local proof_dir=""
    if declare -F octo_proof_init >/dev/null 2>&1 && octo_proof_enabled; then
        proof_dir=$(octo_proof_init "review" "target=${target} focus=${focus}" "$profile_json" 2>/dev/null || true)
    fi

    log INFO "review_run: target=$target focus=$focus provenance=$provenance autonomy=$autonomy history=$history"

    # ── REVIEW.md ────────────────────────────────────────────────────────────
    parse_review_md
    local review_context=""
    if [[ -n "$REVIEW_ALWAYS_CHECK" || -n "$REVIEW_STYLE_RULES" ]]; then
        review_context="Repository review rules (from REVIEW.md):\nAlways check:\n${REVIEW_ALWAYS_CHECK}\nStyle:\n${REVIEW_STYLE_RULES}"
    fi

    # Graphify companion context is passive: use an existing graph report when
    # present, but never build or refresh a graph from /octo:review itself.
    local graphify_context=""
    if declare -F octo_graphify_context_for_prompt >/dev/null 2>&1; then
        local graphify_root
        graphify_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
        graphify_context=$(octo_graphify_context_for_prompt "$graphify_root" 12000 2>/dev/null || true)
    fi

    # ── Collect diff ─────────────────────────────────────────────────────────
    # lestephen.35: capture stderr separately so branch-target sentinels
    # (BRANCH_BASE_UNRESOLVED / BRANCH_MERGEBASE_UNRESOLVED) can be detected
    # and surfaced as errors rather than swallowed into "no changes".
    local diff_content="" _collect_err=""
    _collect_err=$(mktemp)
    diff_content=$(review_collect_diff "$target" "$base" 2>"$_collect_err")
    if [[ -s "$_collect_err" ]]; then
        local _sentinel
        _sentinel=$(head -n 1 "$_collect_err")
        case "$_sentinel" in
            BRANCH_BASE_UNRESOLVED)
                log ERROR "review_run: target=branch but no base ref resolved (no profile.base, no origin/HEAD, no origin/main, no main). Pass --base <ref> explicitly."
                echo "{\"findings\":[],\"error\":\"branch-target needs a base ref; pass --base <ref> or configure origin/HEAD\"}" > "$findings_file"
                rm -f "$_collect_err"
                return 1
                ;;
            BRANCH_MERGEBASE_UNRESOLVED:*)
                local _bad_base="${_sentinel#BRANCH_MERGEBASE_UNRESOLVED:}"
                log ERROR "review_run: target=branch but git merge-base HEAD '$_bad_base' returned nothing (no shared history). Check that '$_bad_base' is a valid ref reachable from HEAD."
                echo "{\"findings\":[],\"error\":\"merge-base unresolved against base=$_bad_base\"}" > "$findings_file"
                rm -f "$_collect_err"
                return 1
                ;;
        esac
    fi
    rm -f "$_collect_err"

    if [[ -z "$diff_content" ]]; then
        log WARN "review_run: no diff found for target=$target"
        echo '{"findings":[],"message":"No changes found to review"}' > "$findings_file"
        if [[ -n "$proof_dir" ]]; then
            octo_proof_artifact "$proof_dir" "review-findings" "$findings_file" "no changes found"
            octo_proof_claim "$proof_dir" "No changes found to review" "verified" "$findings_file"
            octo_proof_capture_provider_status "$proof_dir" "$provider_status_file"
            octo_proof_finalize "$proof_dir" "no_changes" "No changes found to review."
            echo "Proof packet: $proof_dir"
        fi
        rm -f "$provider_status_file"
        render_terminal_report "$findings_file"
        return 0
    fi

    # Apply skip patterns from REVIEW.md (pre-filter before spending tokens)
    if [[ -n "$REVIEW_SKIP_PATTERNS" ]]; then
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            diff_content=$(echo "$diff_content" | grep -v "$pattern" || true)
        done <<< "$REVIEW_SKIP_PATTERNS"
    fi

    # ── Round-aware PR review state (#322) ───────────────────────────────────
    # OCTOPUS_PR_HISTORY=0 disables all local history read/write.
    local review_pr_number="" review_repo="" review_host="github.com" review_head_sha=""
    local review_state_file="" review_previous_findings="[]" review_history_context="" review_timeline=""
    if declare -F pr_review_state_enabled >/dev/null 2>&1 && pr_review_state_enabled; then
        if [[ "$target" =~ ^[0-9]+$ ]]; then
            review_pr_number="$target"
            review_head_sha=$(gh pr view "$target" --json headRefOid -q .headRefOid 2>/dev/null || true)
        else
            review_pr_number=$(gh pr view --json number -q .number 2>/dev/null || true)
            review_head_sha=$(gh pr view --json headRefOid -q .headRefOid 2>/dev/null || true)
        fi
        [[ -z "$review_head_sha" ]] && review_head_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

        if [[ -n "$review_pr_number" ]]; then
            local repo_json
            repo_json=$(gh repo view --json nameWithOwner,url 2>/dev/null || echo '{}')
            review_repo=$(echo "$repo_json" | jq -r '.nameWithOwner // empty')
            review_host=$(echo "$repo_json" | jq -r '(.url // "") | sub("^https?://";"") | split("/")[0] // "github.com"')
            [[ -z "$review_host" || "$review_host" == "null" ]] && review_host="github.com"

            if [[ -n "$review_repo" ]]; then
                review_state_file=$(pr_review_state_path "$review_host" "$review_repo" "$review_pr_number")
                if [[ "$history" != "fresh" ]] && pr_review_state_validate "$review_state_file"; then
                    local previous_round previous_head since_last_round_diff
                    previous_round=$(pr_review_state_previous_round "$review_state_file" 2>/dev/null || true)
                    previous_head=$(echo "$previous_round" | jq -r '.head_sha // empty' 2>/dev/null || true)
                    review_previous_findings=$(echo "$previous_round" | jq -c '.findings // []' 2>/dev/null || echo "[]")
                    if [[ -n "$previous_head" && "$previous_head" != "unknown" ]]; then
                        since_last_round_diff=$(pr_review_state_diff_since "$previous_head" "$review_head_sha" 2>/dev/null || true)
                    fi
                    review_history_context=$(pr_review_state_context_for_prompt "$review_state_file" "$since_last_round_diff" 12000)
                fi
            fi
        fi
    fi

    # ── Scale timeout by diff size (#303) ───────────────────────────────────
    local diff_lines
    diff_lines=$(echo "$diff_content" | wc -l | tr -d ' ')
    local review_timeout="${OCTOPUS_REVIEW_TIMEOUT:-480}"
    if [[ "$review_timeout" -eq 480 ]]; then
        if [[ "$diff_lines" -gt 5000 ]]; then
            review_timeout=900
        elif [[ "$diff_lines" -gt 2000 ]]; then
            review_timeout=600
        fi
    fi
    export TIMEOUT="$review_timeout"

    if [[ -n "$proof_dir" ]]; then
        octo_proof_event "$proof_dir" "review_scope" "$(jq -n \
            --arg target "$target" \
            --arg focus "$focus" \
            --arg provenance "$provenance" \
            --arg autonomy "$autonomy" \
            --arg publish "$publish" \
            --arg debate "$debate" \
            --arg history "$history" \
            --argjson diff_lines "$diff_lines" \
            '{target:$target, focus:$focus, provenance:$provenance, autonomy:$autonomy, publish:$publish, debate:$debate, history:$history, diff_lines:$diff_lines}')"
    fi

    # ── ROUND 1: Parallel agent fleet ────────────────────────────────────────
    log INFO "review_run: Round 1 — parallel specialist fleet (timeout=${review_timeout}s, diff=${diff_lines} lines)"
    local fleet
    fleet=$(build_review_fleet)

    if [[ -n "$proof_dir" ]]; then
        octo_proof_event "$proof_dir" "provider_fleet" "$(printf '%s\n' "$fleet" | jq -R -s 'split("\n")[:-1]')"
    fi

    # lestephen.23: mockup-context preamble (cheapest leg of GH #11).
    # When the profile sets `reference`, force reviewers to ground the diff
    # against the source-of-truth artifact (mockup, screenshot, spec PDF).
    # This is a text-only preamble — the headless review fleet still cannot
    # see image pixels (deferred follow-up). Even text-only context forces the
    # reviewer to flag "this code claims X but I cannot verify against the
    # artifact" rather than silently rubber-stamping code-internal consistency.
    local reference_preamble=""
    if [[ -n "$reference" ]]; then
        local _ref_basename
        _ref_basename=$(basename "$reference")
        local _ref_size
        _ref_size=$(stat -c%s "$reference" 2>/dev/null || stat -f%z "$reference" 2>/dev/null || echo "unknown")
        local _ref_kind="artifact"
        case "$reference" in
            *.png|*.jpg|*.jpeg|*.webp|*.gif|*.svg) _ref_kind="image mockup" ;;
            *.pdf)                                  _ref_kind="PDF spec" ;;
            *.md|*.txt|*.rst)                       _ref_kind="text spec" ;;
        esac
        # lestephen.33 (closes GH #11 expensive-leg cheap-half per team
        # feedback): preamble now includes a tool-use protocol with concrete
        # commands the reviewer SHOULD run, not just an instruction to "look
        # at the artifact". Closes the "no tool means eyeballing" failure
        # mode: reviewers can run sample_pixel + delta_e against named
        # coordinates and assert against the threshold mechanically.
        #
        # v2 fixes from consensus dispatch:
        # - Plugin-dir resolution mirrors bin/octo-consensus (env → canonical
        #   → walk-up from this script). Closes gemini SEV-1 + claude SEV-2
        #   "hardcoded path 404s for non-canonical installs".
        # - Reference path is shell-quoted via printf %q so paths-with-spaces
        #   work (gemini SEV-2).
        # - Pillow setup note included so reviewers know to install if missing
        #   (gemini SEV-2 dependency-management; tools already error helpfully).
        # - Coord-mapping gap acknowledged explicitly (claude SEV-2); preamble
        #   instructs reviewers what to do when no @sample annotations exist.
        local _plugin_dir=""
        if [[ -n "${OCTOPUS_PLUGIN_DIR:-}" && -d "$OCTOPUS_PLUGIN_DIR" ]]; then
            _plugin_dir="$OCTOPUS_PLUGIN_DIR"
        elif [[ -d "$HOME/.claude-octopus/plugin/scripts/helpers" ]]; then
            _plugin_dir="$HOME/.claude-octopus/plugin"
        else
            # Walk up from review.sh's location: $PLUGIN_ROOT/scripts/lib/review.sh
            local _here
            _here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null)" || _here=""
            if [[ -n "$_here" && -d "$_here/../helpers" ]]; then
                _plugin_dir="$(cd "$_here/../.." && pwd -P)"
            else
                _plugin_dir="(plugin-dir-not-resolved; set OCTOPUS_PLUGIN_DIR)"
            fi
        fi
        local _ref_q _plugin_dir_q
        _ref_q=$(printf '%q' "$reference")
        # lestephen.33 v3 fix (both providers SEV-2): also quote _plugin_dir
        # so paths-with-spaces work (npm-install under /Users/Lucy Smith/...
        # or under /home/.../My Project/...). v2 quoted ref + render but
        # missed plugin_dir in the same heredoc.
        _plugin_dir_q=$(printf '%q' "$_plugin_dir")
        local _render_script_q=""
        [[ -n "$visual_render_script" ]] && _render_script_q=$(printf '%q' "$visual_render_script")
        local _tool_protocol=""
        # Q3 (proportion) gated on render_script; Q4 (pre-existing) gated on
        # visual.preexisting_pass. Both are "question without measurement
        # anchor" failure modes if emitted ungated — claude SEV-2 v1/v2 GH #22.
        local _q3_block _q4_block _category_distinction
        if [[ -n "$visual_render_script" ]]; then
            _q3_block="3. DOES THE RENDERED PROPORTION MATCH the reference artifact's proportion?
   render_script is set in this profile, so the comparison is grounded.
   Methodology:
   - Run render_diff.sh (see TOOLS block) to get a screenshot
   - For named UI regions (sprite, header, sidebar, card), eyeball the
     proportion of the viewport each occupies in rendered vs. mockup
   - If the proportion delta is >20%, flag. Concrete example: petrics
     PR-25 pet sprite was ~50% of stage area in rendered but ~30% in
     mockup (delta=20pp, ~67%-of-mockup) → flag.
   Category: 'visual-proportion-divergence', severity 'normal'."
            _q3_distinction="- visual-proportion-divergence → resize the rendered element"
        else
            _q3_block="3. (PROPORTION CHECK skipped — no render_script in this profile.
   Setting visual.render_script enables comparing rendered viewport
   proportions to the mockup; without it the comparison would be
   speculative and ungrounded. Tracking: GH #21.)"
            _q3_distinction=""
        fi
        if [[ "$visual_preexisting_pass" == "true" ]]; then
            _q4_block="4. WHAT PRE-EXISTING CODE STATE is contradicted by the reference artifact?
   - Outside the diff. Mostly catches things the diff implementer
     inherited and didn't realize were wrong. Example: Pixi.js canvas
     init uses literal 0x0d1117 (in code untouched by THIS diff) but
     mockup canvas region samples #1b2227. Pre-existing palette mismatch
     that the diff doesn't fix and the team may not know about.
   - The PRE-EXISTING STATE PASS block below gives sampling methodology.
   - Surface so user can decide whether to widen scope.
   - Category: 'visual-preexisting-divergence', severity 'nit'."
            _q4_distinction="- visual-preexisting-divergence → fix pre-existing token (may widen scope)"
        else
            _q4_block="4. (PRE-EXISTING STATE check skipped — visual.preexisting_pass not
   enabled in this profile. Enable with visual.preexisting_pass=true to
   surface divergences in code the diff doesn't touch. Default-off
   because the findings are 'nit'-severity and add review noise that
   not every project wants.)"
            _q4_distinction=""
        fi
        # Build CATEGORY DISTINCTION dynamically so it only lists categories
        # whose questions are actually active in this dispatch.
        _category_distinction="CATEGORY DISTINCTION (don't collapse — each maps to a different action):
- product-semantics-unclear → reword the label/value/unit
- product-redundant-affordance → remove one of the duplicates"
        [[ -n "$_q3_distinction" ]] && _category_distinction="${_category_distinction}
${_q3_distinction}"
        [[ -n "$_q4_distinction" ]] && _category_distinction="${_category_distinction}
${_q4_distinction}"
        if [[ "$_ref_kind" == "image mockup" ]]; then
            _tool_protocol="
TOOLS YOU SHOULD CALL (per-token, not just per-review):
  Sample a pixel from the mockup at coords (x, y):
    python3 ${_plugin_dir_q}/scripts/helpers/sample_pixel.py ${_ref_q} <x> <y>
    → outputs hex color like '#1b2227'
    → requires Pillow: 'pip install Pillow' (script errors with helpful hint)
    → for high-frequency content (icon edges, text, antialiased borders), add
      '--patch 3' (or 5) to average an N×N region — single-pixel sampling
      can be unrepresentative of the perceived token colour. lestephen.35.
  Compute deltaE color distance (CIE76 by default):
    python3 ${_plugin_dir_q}/scripts/helpers/delta_e.py <hex1> <hex2>
    → pure-stdlib; no install needed
    → outputs float; threshold for THIS project is ${visual_delta_e_threshold}
    → findings with deltaE > ${visual_delta_e_threshold} are flagged
       category 'visual-divergence' severity 'normal'
  Detect 0x-prefixed hex literals (e.g. Pixi.js color codes):
    git grep -nE '0x[0-9a-fA-F]{6}' -- '*.ts' '*.tsx' '*.js' '*.jsx'
    → these are equivalent to #-prefixed hex; sample-and-compare both
${visual_render_script:+
  Render the project for rendered-output comparison (project-supplied):
    bash ${_plugin_dir_q}/scripts/helpers/render_diff.sh ${_render_script_q}
    → outputs absolute path to the rendered screenshot on its last stdout
       line; sample THAT against the mockup at the same coords to catch
       rendering-pipeline divergence (Tailwind compilation, CSS specificity,
       GL color literals, alpha compositing) that token-only inspection misses.}

WHEN TO CALL TOOLS (mechanical trigger):
- For EVERY color hex literal added/changed in the diff (whether #-prefixed
  or 0x-prefixed), sample the corresponding mockup coord and compare. Do
  this per literal, not per file.
- For each design-token file change (tailwind.config.*, *.css, *.scss,
  *.tokens.*, styles.ts), repeat per added/changed value.
- If a diff comment says \"sampled from mockup at (x,y)\" or has '// @sample
  (x,y)' annotation, VERIFY by running sample_pixel at those coords —
  the comment may be wrong (that was the lestephen.23 trigger case).

COORD-MAPPING GAP (acknowledged honestly):
The diff usually does NOT carry mockup coordinates per token. When a hex
literal lacks an explicit '// @sample (x,y)' annotation:
1. Inspect the mockup to FIND a candidate region the token semantically
   represents (e.g. 'canvas.DEFAULT' → main background area; 'accent' →
   the most prominent non-background fill). Use the descriptive name in
   the diff to guide which mockup region to sample.
2. Sample at the center of that region; if uncertain about the region,
   sample at multiple coords (corners, center, edges) and report the
   sampled range.
3. Flag with category 'visual-coord-unverified' (NOT 'visual-divergence')
   when the coord-to-token mapping required guessing; this signals to the
   human reader that the finding needs human-verified coords before
   actioning. This is honest about the limit, not a workaround.
4. Recommend the project add '// @sample (x,y)' annotations to design-
   token definitions (in the synthesis output) so future reviews are
   mechanical end-to-end.

WHAT TO FLAG:
- deltaE > ${visual_delta_e_threshold} (with verified coord) → category
  'visual-divergence', severity 'normal'. Include in detail: code value,
  sampled value, deltaE, sample coord. Example: \"canvas.DEFAULT = '#0e1a24'
  but mockup @(680,300) = '#1b2227' (deltaE=5.83 > threshold
  ${visual_delta_e_threshold})\".
- deltaE > ${visual_delta_e_threshold} (with guessed coord) → category
  'visual-coord-unverified', severity 'nit' until coords are confirmed.
- Comment claims sampling at (x,y) but actual sample differs from code
  value → 'visual-token-comment-mismatch'.
- Code uses 0x-literal that is code-internally consistent but diverges
  from rendered output → 'rendered-divergence' (requires render_script).

PRODUCT SEMANTICS — lestephen.38 (closes GH #22 petrics-feedback). The
visual-fidelity checks above catch palette/coord divergence but miss
structural / product-design issues that shipped past prior reviews.
Categories are distinct — don't collapse them. Each has a worked
example from petrics PR-25 (the calibration case).

1. WHAT DOES THIS DATUM MEAN to a user looking at the device for 2 seconds?
   Concrete worked examples (all petrics PR-25 actuals):
   - 'Mood: 50%' → MEANING UNCLEAR: percentages map intuitively to
     batteries/progress/completion, not to moods. Flag.
   - 'Chats: 7' → MEANING UNCLEAR: 7 what? unread? total? pinned?
     active in last hour? The bare number with a category label leaves
     intent ambiguous. Flag.
   - 'Focus task: 84%' → MEANING UNCLEAR: tasks aren't %-done; sessions
     or projects are. The framing reuses a unit that doesn't apply to
     the noun. Flag.
   - 'Battery: 50%' → CLEAR: standard idiom; no flag.
   - 'Steps: 7,243' → CLEAR: count with implied 'today' from app context.
   Category: 'product-semantics-unclear', severity 'normal'.

2. IS THIS AFFORDANCE REDUNDANT with another part of the visible UI?
   Concrete worked examples:
   - An on-screen 'F1 / F2 / F3 / Action' footer row INSIDE the kiosk
     screen that duplicates the device's physical button bezel (petrics
     PR-25 actual). Flag with: which is canonical (physical), which is
     noise (on-screen). Category: 'product-redundant-affordance'.
   - Two cards both showing the same 'last sync time' with slightly
     different formatting. Flag the duplicate.
   - A 'Settings' gear in the header AND a 'Settings' tab in the footer.
     Flag if both navigate to the same destination.
   Category: 'product-redundant-affordance', severity 'normal'.

${_q3_block}

${_q4_block}

${_category_distinction}"

            # Optional pre-existing state pass — gated on opt-in flag because
            # it's noisier (more low-sev findings to triage). Closes GH #22
            # ask (2) with the proposed visual.preexisting_pass profile flag.
            if [[ "$visual_preexisting_pass" == "true" ]]; then
                _tool_protocol="${_tool_protocol}

PRE-EXISTING STATE PASS (enabled via visual.preexisting_pass=true):
Beyond the diff: sample the reference artifact for any visible feature
you can name (color tokens, layout regions, key typography, character
proportions). For each, locate the corresponding token/literal/component
in the CURRENT file state (not just the diff). If you find a contradiction,
flag it with category 'visual-preexisting-divergence', severity 'nit'.
The user may not have realized something pre-existing is wrong.

Examples of the kind of finding this surfaces (petrics PR-25 case):
- Pixi.js canvas background uses literal 0x0d1117 (in canvas init code,
  not in the diff) but mockup canvas region samples #1b2227 — pre-
  existing palette mismatch.
- Component import paths reference a deleted icon set."
            fi
        fi

        reference_preamble="VISUAL/SPEC GROUND-TRUTH (lestephen.33):
The reference ${_ref_kind} for this work is: ${reference}
  (basename: ${_ref_basename}, size: ${_ref_size} bytes)
${_tool_protocol}

REQUIRED BEHAVIOR — apply BEFORE evaluating code-internal consistency:
1. Open and inspect the reference. Headless CLIs in this dispatch path
   (codex / claude --print / gemini) can all read referenced image and
   PDF paths — use that capability. Confirm in your output that you
   actually inspected the artifact (e.g. \"I see a chartreuse accent at
   roughly the top bar\").
2. For visual-fidelity claims (color tokens, layout constants, typography
   weights, spacing, iconography): when the reference is an image, USE
   THE TOOLS ABOVE — don't eyeball. Sample mockup pixels at specific
   coords and compute deltaE against code values mechanically.
3. For PDF / text-spec references: read the spec and compare claims in
   the diff against the spec text. Flag contradictions as 'spec-divergence'.
4. Do NOT silently rubber-stamp code-internal consistency (e.g. \"canvas
   token matches consumers\") as evidence of ground-truth fidelity —
   those are different properties.
5. If the reference is truly unreadable in your environment (rare), say so
   explicitly and tag visual-fidelity findings as 'visual-unverified'
   rather than skipping them.

"
    fi

    local agent_prompt_base
    agent_prompt_base="You are a code reviewer. Review the following diff and return ONLY a JSON object with a 'findings' array.

Each finding must have: file (string), line (integer), severity (normal|nit|pre-existing), category (string), title (string), detail (string), confidence (0.0-1.0).

Severity guide:
- normal: bug that should be fixed before merging (red)
- nit: minor issue, not blocking (yellow)
- pre-existing: bug not introduced by this PR (purple)

${reference_preamble}${review_context}
${review_history_context}
${graphify_context}

Focus areas for this review: ${focus}
Provenance: ${provenance}
$(if [[ "$provenance" == "autonomous" || "$provenance" == "ai-assisted" ]]; then echo "ELEVATED RIGOR: Check for TDD evidence, placeholder logic, unwired components, speculative abstractions."; fi)
$(if [[ "$autonomy" == "autonomous" ]]; then echo "AUTONOMOUS MODE: Apply maximum rigor. Flag every potential issue with full detail."; fi)

Diff to review:
\`\`\`
${diff_content}
\`\`\`

CRITICAL OUTPUT FORMAT: Return ONLY a valid JSON object. No markdown, no prose, no explanations, no code blocks wrapping the JSON. Start with { and end with }. If you cannot parse the diff or find no issues, return: {\"findings\": []}"

    local round1_files=()
    local round1_agent_types=()

    fleet_dispatch_begin
    while IFS=: read -r agent_type role specialty; do
        [[ -z "$agent_type" ]] && continue
        local task_id="review-r1-${role}-${timestamp}"
        # Use spawn_agent's actual output path convention: ${RESULTS_DIR}/${agent_type}-${task_id}.md
        local result_file="${RESULTS_DIR}/${agent_type}-${task_id}.md"
        round1_files+=("$result_file")
        round1_agent_types+=("$agent_type")

        local agent_prompt="You are the ${role} specialist. Focus on: ${specialty}.

${agent_prompt_base}"

        spawn_agent "$agent_type" "$agent_prompt" "$task_id" "$role" "review" &
    done <<< "$fleet"

    fleet_dispatch_end

    # Wait for all Round 1 agents
    # v9.3.1: wait only catches direct children; spawn_agent's actual CLI runs as
    # grandchild processes. Poll result files for ## Status markers instead (#190).
    wait  # Wait for spawn_agent setup to finish
    local _poll_start
    _poll_start=$(date +%s)
    while true; do
        local _all_done=true
        for _rf in "${round1_files[@]}"; do
            if [[ ! -f "$_rf" ]] || [[ $(grep -cE '^## Status:' "$_rf" 2>/dev/null || true) -eq 0 ]]; then
                _all_done=false
                break
            fi
        done
        [[ "$_all_done" == "true" ]] && break
        if [[ $(( $(date +%s) - _poll_start )) -ge $review_timeout ]]; then
            log WARN "review_run: Round 1 timed out after ${review_timeout}s — collecting partial results"
            break
        fi
        sleep 2
    done
    log INFO "review_run: Round 1 complete"

    # Collect Round 1 findings — extract ## Output section, strip markdown fences, parse JSON
    local all_findings="[]"
    local idx=0
    for f in "${round1_files[@]}"; do
        [[ ! -f "$f" ]] && continue
        local agent_findings
        # v9.20.1: Extract content from ## Output section (portable awk, fixes BSD sed #255)
        agent_findings=$(awk '/^## Output$/{found=1;next} /^## /{if(found)exit} found && !/^```(json|JSON)?$/{print}' "$f" | \
            jq -r '.findings // []' 2>/dev/null || echo "[]")
        all_findings=$(printf '%s\n%s' "$all_findings" "$agent_findings" | \
            jq -s 'add' 2>/dev/null || echo "$all_findings")

        # v9.3.1: Write provider status for Round 1 agents (#187)
        local atype="${round1_agent_types[$idx]}"
        local provider_key="${atype%%[-_]*}"
        if [[ $(grep -c "Status: FAILED" "$f" 2>/dev/null || true) -gt 0 ]]; then
            echo "${provider_key}|fallback|Round 1 agent failed" >> "$provider_status_file"
        elif [[ "$agent_findings" != "[]" ]]; then
            echo "${provider_key}|ok|Round 1 findings" >> "$provider_status_file"
        fi
        ((idx++)) || true
    done

    # v9.20.1: Detect total fleet failure — all providers crashed/timed out (#255)
    local _r1_total=${#round1_files[@]}
    local _r1_failed=0
    for _rf in "${round1_files[@]}"; do
        if [[ ! -f "$_rf" ]] || \
           grep -qE '^## Status: (FAILED|TIMEOUT)' "$_rf" 2>/dev/null || \
           [[ $(grep -c '^## Status:' "$_rf" 2>/dev/null || true) -eq 0 ]]; then
            ((_r1_failed++)) || true
        fi
    done
    if [[ $_r1_failed -ge $_r1_total ]] && [[ $_r1_total -gt 0 ]]; then
        log ERROR "review_run: ALL Round 1 providers failed ($_r1_failed/$_r1_total). Review output is unreliable."
        echo "{\"findings\":[],\"warning\":\"All $_r1_total review providers failed. No code was actually reviewed. Run /octo:doctor to diagnose provider issues.\"}" > "$findings_file"
        if [[ -n "$proof_dir" ]]; then
            octo_proof_artifact "$proof_dir" "review-findings" "$findings_file" "all providers failed"
            octo_proof_claim "$proof_dir" "Code was reviewed by at least one provider" "contradicted" "$findings_file"
            octo_proof_capture_provider_status "$proof_dir" "$provider_status_file"
            octo_proof_finalize "$proof_dir" "fail" "All ${_r1_total} Round 1 review providers failed."
            echo "Proof packet: $proof_dir"
        fi
        render_terminal_report "$findings_file"
        print_provider_report "$provider_status_file"
        return 1
    fi

    # ── ROUND 2: Verification ─────────────────────────────────────────────────
    log INFO "review_run: Round 2 — verification"
    local verifier_prompt
    # lestephen.28 (closes GH #13): inject reference_preamble into Round 2.
    # Previously the preamble only fed Round 1; the verifier judged against
    # diff-only and could drop visual-unverified findings as "unsupported by
    # the diff" — defeating the cheapest leg of GH #11.
    verifier_prompt="You are a code review verifier. For each finding below, check whether it is a real bug (confirmed), a false positive, or needs debate (uncertain/conflicting).

${reference_preamble}When verifying visual-fidelity findings tagged 'visual-divergence' or 'visual-unverified': do NOT downgrade or drop them solely because the diff lacks evidence — the diff WOULD lack evidence; the reference artifact is the source of truth. Inspect the reference (you can read the path) and confirm the divergence yourself.

Return ONLY JSON: same findings array with an added 'verdict' field: confirmed|false-positive|needs-debate.
Also add 'pre_existing_newly_reachable': true if a pre-existing finding becomes reachable via this PR changes.

Diff:
\`\`\`
${diff_content}
\`\`\`

Findings to verify:
$(echo "$all_findings" | jq -c '.')

Return ONLY valid JSON with 'findings' array including verdict field."

    local verified_findings
    verified_findings=$(run_agent_sync "codex" "$verifier_prompt" 180 "code-reviewer" "review") && {
        echo "codex|ok|Round 2 verification" >> "$provider_status_file"
    } || {
        log WARN "review_run: codex verifier failed, falling back to claude-sonnet"
        log "USER" "⚠ Round 2: Codex unavailable → claude-sonnet (fallback). Codex API usage will NOT change."
        echo "codex|fallback|Round 2 → claude-sonnet" >> "$provider_status_file"
        verified_findings=$(run_agent_sync "claude-sonnet" "$verifier_prompt" 180 "code-reviewer" "review") || {
            log WARN "review_run: verification failed entirely, using all findings as confirmed"
            verified_findings="{\"findings\":$(echo "$all_findings" | \
                jq 'map(. + {"verdict":"confirmed"})' 2>/dev/null || echo "[]")}"
        }
    }
    # v9.3.1: Strip markdown fences that LLMs wrap around JSON responses (#188)
    verified_findings=$(echo "$verified_findings" | sed '/^```json$/d; /^```JSON$/d; /^```$/d')

    # Filter false positives
    local confirmed_findings
    confirmed_findings=$(echo "$verified_findings" | \
        jq '.findings | map(select(.verdict != "false-positive"))' 2>/dev/null || \
        echo "$all_findings")

    # ── Debate gate (if enabled) ──────────────────────────────────────────────
    if [[ "$debate" != "off" ]]; then
        local debate_candidates
        debate_candidates=$(echo "$confirmed_findings" | \
            jq '[.[] | select(.verdict == "needs-debate")]' 2>/dev/null || echo "[]")
        local debate_count
        debate_count=$(echo "$debate_candidates" | jq 'length' 2>/dev/null || echo "0")
        if [[ "$debate_count" -gt 0 ]]; then
            log INFO "review_run: debating $debate_count contested findings"
            # lestephen.28 (closes GH #13): inject preamble into debate too.
            local debate_prompt="Challenge these $debate_count contested code review findings. For each, state whether it is a real bug (include) or false positive (exclude). Be adversarial.

${reference_preamble}Visual-fidelity findings tagged 'visual-divergence' or 'visual-unverified' must be assessed by inspecting the reference artifact, NOT by checking the diff. The whole point of those tags is that the diff would not show the divergence.

Findings: $(echo "$debate_candidates" | jq -c '.')
Return JSON: {\"include\": [...finding titles...], \"exclude\": [...finding titles...]}"
            local debate_result
            debate_result=$(run_agent_sync "codex" "$debate_prompt" 120 "code-reviewer" "review") && {
                echo "codex|ok|Round 3 debate" >> "$provider_status_file"
            } || {
                log WARN "review_run: debate agent failed, including all contested findings"
                log "USER" "⚠ Round 3: Codex debate gate unavailable — including all contested findings without debate."
                echo "codex|fallback|Round 3 debate → skipped" >> "$provider_status_file"
                debate_result="{\"include\":[],\"exclude\":[]}"
            }
            # v9.3.1: Strip markdown fences from debate result (#188)
            debate_result=$(echo "$debate_result" | sed '/^```json$/d; /^```JSON$/d; /^```$/d')
            local exclude_titles
            exclude_titles=$(echo "$debate_result" | jq -r '.exclude // [] | .[]' 2>/dev/null || true)
            if [[ -n "$exclude_titles" ]]; then
                while IFS= read -r title; do
                    confirmed_findings=$(echo "$confirmed_findings" | \
                        jq --arg t "$title" '[.[] | select(.title != $t)]' 2>/dev/null || \
                        echo "$confirmed_findings")
                done <<< "$exclude_titles"
            fi
        fi
    fi

    # ── ROUND 3: Synthesis ────────────────────────────────────────────────────
    log INFO "review_run: Round 3 — synthesis"
    local synthesis_prompt
    # lestephen.28 (closes GH #13): inject preamble into synthesis too. The
    # synthesizer must preserve visual-divergence/visual-unverified findings
    # (don't merge them into generic "review findings" that lose the visual
    # context, don't downgrade their severity in deduplication).
    synthesis_prompt="Deduplicate and rank these code review findings by severity (normal first, then nit, then pre-existing). Merge duplicate findings (same bug from multiple agents) into one entry, preserving all agent perspectives in the detail field.

${reference_preamble}Visual-fidelity findings (category 'visual-divergence' or 'visual-unverified') must be preserved at their original severity — do not downgrade them during deduplication, and do not merge them with non-visual findings that lose the reference-artifact context.

Findings: $(echo "$confirmed_findings" | jq -c '.')

Return ONLY JSON: {\"findings\": [...ranked, deduplicated findings...]}"

    local final_json
    final_json=$(run_agent_sync "claude-sonnet" "$synthesis_prompt" 120 "code-reviewer" "review") || {
        log WARN "review_run: synthesis failed, using confirmed findings sorted as-is"
        final_json="{\"findings\":$(echo "$confirmed_findings" | jq -c 'sort_by(.severity)' 2>/dev/null || echo "[]")}"
    }

    # v9.3.1: Strip markdown fences from synthesis result (#188)
    final_json=$(echo "$final_json" | sed '/^```json$/d; /^```JSON$/d; /^```$/d')

    # Write findings file
    echo "$final_json" > "$findings_file"
    log INFO "review_run: findings saved to $findings_file"

    if [[ -n "$proof_dir" ]]; then
        octo_proof_artifact "$proof_dir" "review-findings" "$findings_file" "final review findings"
    fi

    if [[ -n "$review_state_file" ]] && declare -F pr_review_state_append_round >/dev/null 2>&1; then
        local final_findings classification providers_json
        final_findings=$(echo "$final_json" | jq -c '.findings // []' 2>/dev/null || echo "[]")
        classification=$(pr_review_state_classify_findings "$review_previous_findings" "$final_findings" 2>/dev/null || echo '{"addressed":0,"persistent":0,"new":0,"regressed":0}')
        providers_json=$(printf '%s\n' "${round1_agent_types[@]}" | jq -R -s 'split("\n")[:-1]' 2>/dev/null || echo "[]")
        local current_round
        current_round=$(pr_review_state_next_round "$review_state_file")
        review_timeline=$(pr_review_state_render_timeline "$review_state_file" "$review_head_sha" "$classification" "$current_round" 2>/dev/null || true)
        if pr_review_state_append_round "$review_state_file" "$review_host" "$review_repo" "$review_pr_number" "$review_head_sha" "$providers_json" "$final_findings" "$classification" 2>/dev/null; then
            log INFO "review_run: round-aware state saved to $review_state_file"
            if [[ -n "$proof_dir" ]]; then
                octo_proof_artifact "$proof_dir" "review-history-state" "$review_state_file" "round-aware PR review state"
            fi
        fi
    fi

    # ── Output ────────────────────────────────────────────────────────────────
    local pr_number=""
    pr_number=$(gh pr view --json number -q .number 2>/dev/null || true)

    if [[ -n "$pr_number" && "$publish" != "never" ]]; then
        local avg_confidence
        avg_confidence=$(jq '[.findings[].confidence] | if length > 0 then add/length else 0 end' \
            "$findings_file" 2>/dev/null || echo "0")
        if [[ "$publish" == "auto" ]] && awk "BEGIN{exit !($avg_confidence >= 0.85)}"; then
            log INFO "review_run: auto-publishing to PR #$pr_number (confidence=$avg_confidence)"
            post_inline_comments "$pr_number" "$findings_file" || render_terminal_report "$findings_file"
        elif [[ "$publish" == "ask" ]]; then
            render_terminal_report "$findings_file"
            echo ""
            echo "PR #$pr_number is open. Post findings as inline comments? (y/N)"
            read -r response
            [[ "$response" =~ ^[Yy] ]] && { post_inline_comments "$pr_number" "$findings_file" || render_terminal_report "$findings_file"; }
        fi
    else
        render_terminal_report "$findings_file"
    fi

    if [[ -n "$review_timeline" ]]; then
        echo ""
        echo "$review_timeline"
    fi

    if [[ -n "$proof_dir" ]]; then
        local proof_finding_count proof_warning proof_verdict proof_summary
        proof_finding_count=$(jq '.findings | length' "$findings_file" 2>/dev/null || echo "0")
        proof_warning=$(jq -r '.warning // empty' "$findings_file" 2>/dev/null || true)
        if [[ -n "$proof_warning" ]]; then
            proof_verdict="fail"
        elif [[ "$proof_finding_count" -gt 0 ]]; then
            proof_verdict="findings"
        else
            proof_verdict="pass"
        fi
        proof_summary="/octo:review completed with ${proof_finding_count} finding(s)."
        octo_proof_claim "$proof_dir" "Review findings were written to disk" "verified" "$findings_file"
        octo_proof_capture_provider_status "$proof_dir" "$provider_status_file"
        octo_proof_finalize "$proof_dir" "$proof_verdict" "$proof_summary"
        echo ""
        echo "Proof packet: $proof_dir"
    fi

    # v9.0: Print provider report card — always last, impossible to miss
    print_provider_report "$provider_status_file"

    # lestephen.42 (closes GH #19 gemini SEV-2): explicit cleanup as
    # belt-and-suspenders against the RETURN trap being clobbered by a
    # nested function that sets its own RETURN trap. Idempotent — the
    # trap will run AFTER this returns and be a no-op (the helper resets
    # _restore_octo_agent_images to false after restoring).
    _review_restore_octo_agent_images
}

# post_inline_comments: posts findings as inline PR comments via gh API
# WHY: inline line-level comments match CC Code Review UX exactly.
post_inline_comments() {
    local pr_number="$1"
    local findings_file="$2"

    local repo=""
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [[ -z "$repo" ]]; then
        log ERROR "post_inline_comments: could not determine repo (is gh auth configured?)"
        render_terminal_report "$findings_file"
        return 1
    fi

    local commit_id=""
    commit_id=$(gh pr view "$pr_number" --json headRefOid -q .headRefOid 2>/dev/null || true)

    if [[ -z "$commit_id" ]]; then
        log WARN "post_inline_comments: could not determine commit SHA for PR #$pr_number — posting summary comment only"
        local summary
        summary=$(render_review_summary "$findings_file")
        gh pr review "$pr_number" --comment --body "$summary" 2>/dev/null || true
        return 0
    fi

    local summary
    summary=$(render_review_summary "$findings_file")
    gh pr review "$pr_number" --comment --body "$summary" 2>/dev/null || true

    local finding_count
    finding_count=$(jq '.findings | length' "$findings_file" 2>/dev/null || echo "0")
    log INFO "post_inline_comments: posting $finding_count inline comments to PR #$pr_number"

    jq -c '.findings[]' "$findings_file" 2>/dev/null | while IFS= read -r finding; do
        local file line severity title detail
        file=$(echo "$finding"     | jq -r '.file')
        line=$(echo "$finding"     | jq -r '.line')
        severity=$(echo "$finding" | jq -r '.severity')
        title=$(echo "$finding"    | jq -r '.title')
        detail=$(echo "$finding"   | jq -r '.detail')

        local icon
        case "$severity" in
            normal)       icon="[NORMAL]" ;;
            nit)          icon="[NIT]" ;;
            pre-existing) icon="[PRE-EXISTING]" ;;
            *)            icon="[INFO]" ;;
        esac

        local body="${icon} **${title}**

${detail}

_Reviewed by /octo:review (multi-LLM fleet)_"

        gh api "repos/${repo}/pulls/${pr_number}/comments" \
            --method POST \
            -f body="$body" \
            -f commit_id="$commit_id" \
            -f path="$file" \
            -F line="$line" \
            -f side="RIGHT" 2>/dev/null || \
        log WARN "post_inline_comments: failed to post comment on $file:$line"
    done
}

# render_terminal_report: formats findings for terminal display
render_terminal_report() {
    local findings_file="$1"

    local finding_count
    finding_count=$(jq '.findings | length' "$findings_file" 2>/dev/null || echo "0")

    echo ""
    echo "+-----------------------------------------------------------------+"
    echo "|  /octo:review - Multi-LLM Code Review Results                  |"
    echo "+-----------------------------------------------------------------+"
    echo ""

    if [[ "$finding_count" -eq 0 ]]; then
        # v9.20.1: Distinguish "clean review" from "all providers failed" (#255)
        local warning_msg
        warning_msg=$(jq -r '.warning // empty' "$findings_file" 2>/dev/null)
        if [[ -n "$warning_msg" ]]; then
            echo "⚠️  WARNING: $warning_msg"
            echo ""
            echo "This is NOT a clean review — zero providers returned results."
            echo "Do not merge based on this output."
        else
            echo "No issues found."
        fi
        return 0
    fi

    echo "Found $finding_count issue(s):"
    echo ""

    jq -c '.findings[]' "$findings_file" 2>/dev/null | while IFS= read -r finding; do
        local severity title file line detail
        severity=$(echo "$finding" | jq -r '.severity')
        title=$(echo "$finding"    | jq -r '.title')
        file=$(echo "$finding"     | jq -r '.file')
        line=$(echo "$finding"     | jq -r '.line')
        detail=$(echo "$finding"   | jq -r '.detail')

        local icon
        case "$severity" in
            normal)       icon="[NORMAL]" ;;
            nit)          icon="[NIT]" ;;
            pre-existing) icon="[PRE-EXISTING]" ;;
            *)            icon="[INFO]" ;;
        esac

        echo "${icon} ${title}"
        echo "   ${file}:${line}"
        echo "   ${detail}"
        echo ""
    done
}

# render_review_summary: short markdown summary for PR-level comment
render_review_summary() {
    local findings_file="$1"
    local normal_count nit_count preexisting_count
    normal_count=$(jq '[.findings[] | select(.severity=="normal")] | length' "$findings_file" 2>/dev/null || echo "0")
    nit_count=$(jq '[.findings[] | select(.severity=="nit")] | length' "$findings_file" 2>/dev/null || echo "0")
    preexisting_count=$(jq '[.findings[] | select(.severity=="pre-existing")] | length' "$findings_file" 2>/dev/null || echo "0")

    echo "## /octo:review - Multi-LLM Code Review"
    echo ""
    echo "| Severity | Count |"
    echo "|----------|-------|"
    echo "| Normal | $normal_count |"
    echo "| Nit | $nit_count |"
    echo "| Pre-existing | $preexisting_count |"
    echo ""
    echo "_Reviewed by Codex + Gemini + Claude + Perplexity fleet_"
    echo "_See inline comments for details_"
}
