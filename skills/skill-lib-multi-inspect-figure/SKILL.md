---
name: skill-lib-multi-inspect-figure
description: "Library: dispatch a rendered figure to multiple vision-capable providers with a rules prompt — call this from other skills/plugins"
interface_version: 1
---

> **Interface version 1** — Consumer skills should pin this version. The image-attachment path is known-incomplete (see audit issue F12); when v2 lands with provider-specific multimodal payload support, the interface_version will bump and old consumers will get a compat warning.

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Library Skill — Multi-LLM Figure Inspection

This is a **library skill**. It dispatches a rendered image (PNG, JPG, SVG converted, PDF page rendered, etc.) to multiple vision-capable providers, asks each to apply the caller's `rules` prompt, and returns flagged issues with synthesis.

This exists because single vision models miss different categories of issues in the same image. Empirically, Claude Vision catches text-overflow and label-cutoff issues that Gemini Vision often misses, and vice versa for color-contrast and layout-tightness. Running multiple in parallel surfaces a more complete issue list per inspection.

## When to use this skill

- A consumer skill needs to lint a figure against publication / accessibility / project-style rules and wants higher recall than single-vision
- Direct user invocation: "check this chart for legend overlap, axis-label collision, font-size compliance"

## When NOT to use this skill

- You're reviewing text content — use `skill-lib-multi-review-doc`
- You only need to confirm an image renders / exists — read it directly without orchestration
- Bulk lint of dozens of figures with deterministic rules (DPI, font size from font metadata) — write a Python lint script instead; vision is for the *visual* checks (overlap, legibility, cropping) that lint cannot do

## Input contract

| Input | Description | Example |
|---|---|---|
| `image_path` | Absolute path to rendered figure | `/home/user/project/analysis/output/figure3.png` |
| `rules` | Inspection prompt: what counts as an issue | `"Flag: (a) legend overlapping data marks, (b) any axis label clipped or cut off, (c) any text smaller than 12pt apparent. Quote what you see and give pixel-region descriptions."` |
| `providers` (optional) | Subset of vision-capable providers to use. Default: all available | `["claude", "gemini"]` |
| `output_dir` (optional) | Where to write per-provider + synthesis files | default: `~/.claude-octopus/results/lib-inspect-figure/<timestamp>/` |
| `context_doc` (optional) | Path to a doc that gives the figure context (e.g., the report it appears in) — useful for "does this figure support the surrounding claim" checks | |

Vision-capable providers (as of v9.38.0): `claude`, `gemini`, `copilot` (vision-routed models only). `codex`/`opencode`/`qwen` are text-only; this skill skips them with a note.

## ⚠️ MANDATORY: Visual Indicators Protocol

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-LLM Figure Inspection (library)`

Then output the provider banner:

```
🛠️ Library Phase: Multi-LLM figure inspection

Vision providers:
🔵 Claude Vision - Visual lint
🟡 Gemini Vision - Visual lint
🔴 Codex - (text-only, skipped)
```

Mark unavailable or non-vision providers explicitly. Continue with whichever vision providers are available.

## ⚠️ MANDATORY COMPLIANCE — DO NOT SKIP

You are PROHIBITED from:

- Inspecting the image with only one vision provider and pretending you ran the multi-LLM dispatch
- Falling back to "I can describe the image based on the filename" when no vision providers are available — surface the failure
- Silently dropping a provider's report if it didn't flag anything — absence of issues is a valid result and must be recorded
- Skipping the validation gate

If zero vision providers are available, refuse: print the failure and exit non-zero.

## Steps

### STEP 1: Provider check (MANDATORY)

@skills/blocks/provider-check.md

Then filter to vision-capable providers only. Treat `codex`, `qwen`, `opencode` as text-only by default (override at caller's risk via the `providers` input).

### STEP 2: Validate inputs

```bash
[[ ! -f "$image_path" ]] && { echo "❌ image_path does not exist: $image_path"; exit 1; }
[[ ! -s "$image_path" ]] && { echo "❌ image_path is empty: $image_path"; exit 1; }
case "$image_path" in
  *.png|*.jpg|*.jpeg|*.webp|*.gif) ;;
  *) echo "⚠️ image_path is not a common raster format; vision providers may refuse it: $image_path" ;;
esac
```

### STEP 3: Dispatch per provider in parallel

For each available vision provider, dispatch a probe-single inspection. The provider's prompt is the caller's `rules` plus a directive to attach the image:

```bash
OUTPUT_DIR="${output_dir:-$HOME/.claude-octopus/results/lib-inspect-figure/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTPUT_DIR"

INSPECTION_PROMPT=$(cat <<EOF
You are visually inspecting a rendered figure. Apply the rules below and report
every issue you observe. Format each issue as:

ISSUE <n>: <one-line description>
  Location: <pixel region or chart element>
  Evidence: <quote what you see>
  Severity: <high|medium|low>

If you see no issues for a rule, say: NO ISSUES under rule: <rule>

Rules:
$rules

Image path: $image_path
EOF
)

# Important: probe-single's $2 (the "perspective" arg) IS the prompt the model
# receives. $4 (original_prompt) is metadata only. File pattern written by
# probe_single_agent: <agent_type>-<task_id>.md.
TASK_ID="lib-inspect-$(date +%s)-<provider>"
"${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" probe-single \
  "<provider>" \
  "$INSPECTION_PROMPT" \
  "$TASK_ID" \
  "figure inspection: $(basename "$image_path")" \
  --output-dir "$OUTPUT_DIR" &
```

After spawning, `wait`.

### STEP 4: Validation gate (MANDATORY)

For each dispatched provider, the expected output file is
`$OUTPUT_DIR/<provider>-<task_id>.md`. Confirm each is present and
non-empty. If any missing, report the failure and the relevant log path.
Partial results require explicit opt-in via a `min_providers` threshold
passed by the caller.

### STEP 5: Synthesize issue list

Read each per-provider output. Build a unified issue table by union (not intersection — we want recall):

| Issue | Reported by | Severity (max across providers) | Provider notes |
|---|---|---|---|
| Legend overlaps bars in upper-right region | Claude, Gemini | high | both flagged; consistent |
| Y-axis label clipped on left edge | Gemini only | medium | Claude did not flag — re-inspect manually if borderline |
| Annotation text < 10pt | Claude only | low | apparent size estimate; verify in source |

For each issue, prefer keeping multi-provider corroborations together; flag single-provider issues as `single-provider` so the caller knows they're lower-confidence.

Write the synthesis to `$OUTPUT_DIR/synthesis.md`:

```markdown
# Multi-LLM Figure Inspection — Synthesis

**Image:** <image_path>
**Providers run:** <list>
**Providers skipped:** <list, with reason>
**Rules applied:** <verbatim from caller>

## Unified issue list

<the table above>

## Per-provider raw findings

<each provider's output under its own ## header>
```

### STEP 6: Memorialize for graduation-to-lint

Append a one-line JSON entry to `$OUTPUT_DIR/../inspection-log.jsonl` (creates if missing). One entry per inspection:

```json
{"timestamp":"2026-05-16T21:30:00Z","image":"<image_path>","rules_hash":"<sha1 of rules>","issue_classes":["legend_overlap","axis_label_clip"],"providers":["claude","gemini"],"issue_count":3}
```

This is the substrate for the "what visual-AI repeatedly catches" analysis (per the design from session 365b55d7) — when an issue class recurs N+ times, it's a candidate for graduating into a deterministic static lint.

### STEP 7: Return to caller

```
SYNTHESIS: <path-to-synthesis.md>
HEADLINE:  <N issues across M rules — K high, K medium, K low>
LOG:       <path-to-inspection-log.jsonl>
```

## Failure modes

| Failure | Skill behavior |
|---|---|
| Zero vision providers available | Refuse (`❌ no vision providers`); exit non-zero |
| Only 1 vision provider available | Proceed with caller warning: `⚠️ Single-provider inspection — recall will be lower than multi-provider.` Mark all issues as `single-provider`. |
| Image refused by all providers (size, format, content policy) | Surface each provider's refusal; do not synthesize |

## Integration notes for consumer skills

`eki-kw:check-figures` is the primary expected consumer:

1. Consumer walks a document and finds all `![](path/to/figure.png)` references
2. For each, calls this library skill with the project's lint rules (read from `analysis/plot_config.py` or `report-format-standard.md`)
3. Consumer aggregates per-figure synthesis files into a single report for the user
