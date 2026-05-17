---
command: visual-review
description: "Multi-LLM code review with mockup-context preamble forcing reviewers to ground tokens against a reference artifact (lestephen.23 — closes GH #11 cheapest leg)"
argument-hint: '<reference-path> [--wait|--background] [--base <ref>] [--scope auto|working-tree|branch|pr|staged]'
---

# /octo:visual-review

Thin shortcut around `/octo:review` that injects a `reference` artifact (mockup PNG, screenshot, PDF spec) into the review profile so the multi-LLM fleet is forced to acknowledge visual ground-truth before rubber-stamping code-internal consistency.

## Why this exists

GH #11 documented a class of bug `/octo:review` consistently misses: **visual divergence between rendered output and a mockup artifact**. Seven sequential PRs went through the standard `/octo:review` pattern, the fleet found ~50 valid code-internal findings, and all seven PRs missed a fundamental palette divergence between the kiosk and the mockup PNG checked into the repo. None of the reviewers ever loaded the artifact.

The cheapest fix (per the issue) is a **preamble that forces reviewers to acknowledge the artifact**. Even when the headless review fleet cannot see image pixels, requiring the acknowledgement converts silent rubber-stamps into flagged `visual-unverified` findings — which is the right signal to surface to the user.

The full fix (a visual-diff specialist with Playwright + deltaE-2000 comparison) is multi-day work and tracked separately as a deferred follow-up.

## Positioning

| Command | When |
|---|---|
| `/octo:review` | Standard multi-LLM review, no mockup reference |
| **`/octo:visual-review <ref>`** (this) | Frontend / kiosk / dashboard work with a source-of-truth mockup or spec |

> The underlying `reference` profile field is settable by anything that constructs the review profile JSON (e.g., `bash orchestrate.sh code-review '{"reference":"...","target":"staged",...}'`). `/octo:review` itself does **not** parse a `--reference` flag — this slash command is the supported user-facing path for setting `reference`. Tracked as a future enhancement (see GH #11 follow-ups).

## Usage

```
/octo:visual-review ./design/virtual-pet-mockup.png
/octo:visual-review ./docs/spec.pdf --scope branch --wait
/octo:visual-review ./reference/dashboard.png --scope pr --base origin/main
```

The first positional argument is the reference artifact path. All remaining flags pass through to `/octo:review` unchanged.

## MANDATORY COMPLIANCE

When the user invokes `/octo:visual-review <ref> [flags...]`, you MUST:

1. **Validate the reference path exists** before dispatching. If missing, refuse with a clear error.
2. **Construct the review profile JSON** with `reference` set to the absolute path of the artifact. Include `visual-fidelity` in the focus list alongside the user-requested focuses (or alongside the defaults if no focus list was given).
3. **Invoke `orchestrate.sh code-review` with the constructed profile** — do not substitute Claude-native `/review`, do not run a single-model review, do not skip the multi-provider dispatch.
4. **Display the multi-provider banner** with vision-status disclosure: explicitly tell the user which providers in the fleet can attach image bytes (codex-via-`-i` if vision-routed) and which will degrade to text-only with the preamble (claude headless, gemini headless, etc).

## Execution

```bash
# Parse positional reference + pass-through flags.
# Per dogfood (lestephen.23 codex SEV-2): forward --scope/--base/--wait/
# --background and any focus words so this command honors its argument-hint.
REF_PATH=""
SCOPE=""
BASE=""
EXEC_MODE=""        # --wait | --background
EXTRA_FOCUS=()      # extra focus words appended after defaults

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)       SCOPE="$2"; shift 2 ;;
        --base)        BASE="$2"; shift 2 ;;
        --wait)        EXEC_MODE="wait"; shift ;;
        --background)  EXEC_MODE="background"; shift ;;
        -h|--help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --*)
            echo "❌ Unknown flag: $1" >&2; exit 1 ;;
        *)
            if [[ -z "$REF_PATH" ]]; then
                REF_PATH="$1"
            else
                EXTRA_FOCUS+=("$1")
            fi
            shift
            ;;
    esac
done

# Validate
if [[ -z "$REF_PATH" ]]; then
    echo "❌ /octo:visual-review requires a reference artifact path as the first argument."
    echo "Usage: /octo:visual-review <path-to-mockup.png|spec.pdf> [--scope MODE] [--base REF] [--wait|--background] [focus ...]"
    exit 1
fi
if [[ ! -f "$REF_PATH" ]]; then
    echo "❌ Reference artifact not found: $REF_PATH" >&2
    exit 1
fi

# Convert to absolute path so the review subprocess can resolve it
REF_ABS=$(cd "$(dirname "$REF_PATH")" && pwd)/$(basename "$REF_PATH")

# Build the focus list — defaults + visual-fidelity + any extra focus words
FOCUS_LIST=("correctness" "security" "architecture" "visual-fidelity")
if [[ ${#EXTRA_FOCUS[@]} -gt 0 ]]; then
    FOCUS_LIST+=("${EXTRA_FOCUS[@]}")
fi
FOCUS_JSON=$(printf '%s\n' "${FOCUS_LIST[@]}" | jq -R . | jq -s .)

# Map scope → target. review_run accepts target=staged|working-tree|branch|pr
# directly; --scope is the slash-command flag name. PR numbers can also be
# passed as the target value when scope=pr.
TARGET="staged"
case "$SCOPE" in
    working-tree|staged|branch|pr|auto|"") ;;  # accepted
    *) echo "❌ Unknown --scope value: $SCOPE" >&2; exit 1 ;;
esac
[[ -n "$SCOPE" && "$SCOPE" != "auto" ]] && TARGET="$SCOPE"

# Build profile JSON. The `reference` field is the new lestephen.23 hook;
# `base` (if set) flows through as `target` modifier (gitops layer handles).
# review.sh maps `target=fresh → working-tree` for back-compat.
PROFILE_JSON=$(jq -n \
    --arg ref "$REF_ABS" \
    --arg target "$TARGET" \
    --arg base "$BASE" \
    --argjson focus "$FOCUS_JSON" \
    '{
        target: $target,
        focus: $focus,
        reference: $ref,
        provenance: "ai-assisted",
        autonomy: "supervised",
        publish: "ask"
    } + (if $base != "" then {base: $base} else {} end)')

# EXEC_MODE is informational here — review_run runs synchronously; --background
# vs --wait is a Claude-Code-side execution choice, not an orchestrate.sh flag.
# When EXEC_MODE=background, the caller (slash command host) is expected to
# wrap this invocation in a background Bash task. Surface that intent here.
if [[ "$EXEC_MODE" == "background" ]]; then
    echo "ℹ️  --background requested: wrap this invocation in a background Bash task at the host layer."
fi

# Dispatch via orchestrate.sh code-review (review_run reads profile, picks up
# the reference field, injects the mockup-context preamble into every
# reviewer prompt, and surfaces visual-unverified findings).
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" code-review "$PROFILE_JSON"
```

## Provider vision status disclosure (banner)

Before dispatching, output the standard banner with explicit vision status:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** — Multi-LLM Visual Review

Reference artifact: <REF_ABS>

Pixel-attachment status per provider (lestephen.23 — NOT model-level vision):
🔴 Codex CLI: pixel attachment ✅ via -i (if vision-routed model selected)
🔵 Claude (--print headless): pixel attachment ❌ — CLI has no --image flag (model itself has vision)
🟡 Gemini (headless): pixel attachment ❌ — CLI rejects @file attachments (model itself has vision)

Visual-fidelity findings from text-degraded reviewers (Claude, Gemini)
will be tagged 'visual-unverified' and require manual pixel-grounding
before merge. Only Codex findings are pixel-grounded in this dispatch.
```

## Follow-up (deferred to dedicated issue)

The full visual-diff specialist with Playwright screenshot + deltaE-2000 comparison is GH #11 enhancement (1) — multi-day work, tracked as a follow-up. This command implements enhancements (2) `reference` field, (3) preamble, and (4) shortcut from that issue's lightweight leg.
