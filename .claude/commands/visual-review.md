---
command: visual-review
description: "Multi-LLM code review with mockup-context preamble + sample_pixel/delta_e tooling forcing reviewers to ground tokens against a reference artifact (lestephen.23 cheap leg + lestephen.33 tooling leg per GH #11)"
argument-hint: '[--wait|--background] [--base <ref>] [--scope auto|working-tree|branch|pr|staged] <reference-path>'
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

Vision providers (lestephen.24 retest — all see attached pixels):
🔴 Codex CLI: ✅ (-i flag + prompt-body path)
🔵 Claude --print: ✅ (auto-reads referenced paths)
🟡 Gemini headless: ✅ (@file / prompt-body path)

All three providers will inspect the reference artifact pixels alongside the diff.
```

## Visual-review tooling (lestephen.33 — per team's structural feedback on GH #11)

The cheap-leg (.23) preamble told reviewers to "look at the artifact"; the team noted this just reproduces the eyeballing failure mode that motivated the issue. lestephen.33 ships standalone tooling reviewers can CALL to mechanically sample-and-compare:

- `scripts/helpers/sample_pixel.py <image> <x> <y>` — outputs `#rrggbb` or `r,g,b`
- `scripts/helpers/delta_e.py <hex1> <hex2>` — outputs deltaE distance (CIE76 by default; --method cie94|ciede2000 for alternatives)
- `scripts/helpers/render_diff.sh <project-script>` — runs a project-supplied render script that produces a screenshot (project handles dev-server lifecycle + Playwright/etc.)

The reviewer fleet's mockup-context preamble (in `review.sh`) now includes:
- A TOOLS YOU SHOULD CALL block listing exact command invocations with the current reference path substituted
- A WHEN TO CALL TOOLS mechanical-trigger list (per-token, not per-review)
- A WHAT TO FLAG criterion using `visual.delta_e_threshold` from the profile

The original Phase 4 canvas-color bug from GH #11's report (`canvas.DEFAULT = '#0e1a24'` vs sampled mockup `#1b2227`) measures deltaE = 5.83 — would have been flagged at the default threshold of 5.0.

## Profile fields

```yaml
visual:
  delta_e_threshold: 5.0           # (lestephen.33) CIE76; default 5.0
  render_script: ./scripts/render-for-review.sh  # (lestephen.33) optional, for rendered-vs-mockup checks
  preexisting_pass: false          # (lestephen.38, default false) opt in to noisier defense-in-depth
                                   # pass: reviewers also flag contradictions in CURRENT file state
                                   # against the reference, not just in the diff. Findings tagged
                                   # 'visual-preexisting-divergence' severity 'nit'.
```

## Preamble coverage (what reviewers are now asked)

Per petrics dogfood feedback (GH #22), the preamble covers FOUR categories of question, not just code-internal correctness:

1. **Visual fidelity** (token sampling vs mockup pixels) — categories `visual-divergence`, `visual-coord-unverified`, `visual-token-comment-mismatch`
2. **Product semantics** — categories `product-semantics-unclear`, `product-redundant-affordance`, `visual-proportion-divergence`. Asks: what does this datum mean in 2 seconds? Is this affordance redundant? Does the rendered proportion match the mockup?
3. **Rendered divergence** — category `rendered-divergence` (requires `render_script`)
4. **Pre-existing state** (opt-in via `visual.preexisting_pass: true`) — category `visual-preexisting-divergence` severity `nit`. Catches divergences in code that wasn't touched by the diff.

The render_script (when set) must be executable and end its stdout with the absolute path to the produced screenshot — see `scripts/helpers/render_diff.sh` header for the contract.

## Follow-up (deferred to dedicated issue)

The full visual-diff specialist agent — a dedicated Round-1 fleet member whose job is structured tool calls + JSON findings (claim/ground_truth/deltaE/threshold) — is GH #11 enhancement (1) proper. The tools-and-preamble combo shipped here is sufficient for petrics' immediate workflow; the dedicated agent is a follow-up tracked as a new issue (will be filed after this patch lands).
