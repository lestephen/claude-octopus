---
name: skill-lib-multi-inspect-figure
description: "Library: dispatch a rendered figure to multiple vision-capable providers with a rules prompt — call this from other skills/plugins"
interface_version: 2
---

> **Interface version 2** (lestephen.23) — When `--image <path>` is supplied, the library forwards it to `lib-multi-dispatch.sh --image`, which splices the appropriate per-provider image flag into the dispatched subprocess command. Callers from interface_version 1 (which passed the image path as text only) should re-pin to v2 and pass real paths.
>
> ⚠️ **Model vision vs. headless-CLI attachment — they are NOT the same thing.** Gemini Pro/Flash, Claude Sonnet/Opus, and GPT-vision all have full pixel-vision capability *at the model level*. The dispatch-path limitation below is about whether the **subprocess CLI** we shell out to has a documented mechanism to attach image bytes from the command line, not about whether the model can see images:
>
> | Provider | Model has vision? | Headless CLI dispatch attaches pixels? | Notes |
> |---|---|---|---|
> | `codex` family | Yes (GPT-vision) | ✅ Yes — `-i <file>` confirmed end-to-end | Closes GH #7 |
> | `claude` (`--print` headless) | Yes (Sonnet/Opus vision) | ❌ No — `--print` has no `--image` flag | Vision in Claude reaches the model via host conversation context (Read tool, drag-drop). For subprocess dispatch, use the host Claude or the Anthropic API directly. |
> | `gemini`/`qwen`/`cursor-agent` headless | Yes (Gemini Pro Vision) | ❌ No — `@file` + `--include-directories` returned 400 in spike testing | Interactive Gemini (paste image) works. Headless attachment may land in a future SDK update. |
> | `perplexity`/`ollama`/`copilot`/`opencode`/`openrouter` | Varies by routed model | ❌ No documented headless image flag | Some can route to vision models via API directly; not through our subprocess CLI path. |
>
> For text-degraded providers, the prompt body is prepended with an explicit "you cannot see pixels in this dispatch" warning so the model self-limits to structural critique rather than hallucinating pixel observations.

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

**Headless image-attachment via this dispatch path** (lestephen.23): only **`codex`** is confirmed (`-i` flag end-to-end). All other providers — including Claude and Gemini, whose *models* fully support vision — degrade text-only because their **headless CLI** does not expose a pixel-attachment flag. See the matrix in the version banner above for the model-vs-CLI distinction.

## ⚠️ MANDATORY: Visual Indicators Protocol

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-LLM Figure Inspection (library)`

Then output the provider banner:

```
🛠️ Library Phase: Multi-LLM figure inspection (interface_version 2)

Pixel attachment status (NOT model-level vision — see SKILL.md matrix):
🔴 Codex CLI — pixel attachment ✅ (-i flag, confirmed)
🔵 Claude --print — pixel attachment ❌ (subprocess CLI lacks --image; model itself does have vision)
🟡 Gemini headless — pixel attachment ❌ (CLI lacks --image; model itself does have vision)
```

Mark each provider's *dispatch-path* status explicitly. Text-degraded providers still produce useful structural critique (their prompt is prepended with an explicit "you cannot see pixels" warning so they self-limit). Be clear with the caller: a "text-degraded gemini didn't find issues" is NOT evidence the figure is fine.

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

Then filter to vision-capable providers. **Under interface_version 2 (lestephen.23) the vision-capability table inverts**: `codex` is the *only* confirmed-vision headless provider (via `-i` flag and `lib-multi-dispatch.sh --image`). Treat `gemini`, `qwen`, `cursor-agent`, `copilot`, `perplexity`, `ollama`, `opencode`, `openrouter` and headless `claude` (`--print`) as **text-degraded** — they accept the dispatch but the model receives only the filename (the prompt is prepended with an explicit "you cannot see pixels" warning, so they won't hallucinate). Always include codex when available; include text-degraded providers only when the rules are dominated by structural critique (axis labels described in caption, etc.) rather than pixel inspection.

### STEP 2: Validate inputs

```bash
[[ ! -f "$image_path" ]] && { echo "❌ image_path does not exist: $image_path"; exit 1; }
[[ ! -s "$image_path" ]] && { echo "❌ image_path is empty: $image_path"; exit 1; }
case "$image_path" in
  *.png|*.jpg|*.jpeg|*.webp|*.gif) ;;
  *) echo "⚠️ image_path is not a common raster format; vision providers may refuse it: $image_path" ;;
esac
```

### STEP 3: Dispatch via lib-multi-dispatch.sh (interface_version 2)

Use the shared dispatcher with `--image $image_path` so vision-capable providers receive actual image bytes via per-provider attachment flags. Build a reviewers JSON file with one entry per available provider, then call `lib-multi-dispatch.sh`:

```bash
OUTPUT_DIR="${output_dir:-$HOME/.claude-octopus/results/lib-inspect-figure/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTPUT_DIR"

INSPECTION_PROMPT=$(cat <<EOF
You are visually inspecting a rendered figure. The image is attached via the
provider's image-attachment mechanism — examine the pixels, do not infer
content from filenames. If you see a "Images requested but ... lacks headless
image attachment" line in your dispatch context, say so explicitly and limit
your report to structural critique from the rules text only.

Apply the rules below and report every issue you observe. Format each issue as:

ISSUE <n>: <one-line description>
  Location: <pixel region or chart element>
  Evidence: <quote what you see>
  Severity: <high|medium|low>

If you see no issues for a rule, say: NO ISSUES under rule: <rule>

Rules:
$rules

Reference: $image_path (also passed via --image attachment when supported)
EOF
)

# Build reviewers JSON — one entry per vision-routed provider available.
# providers[] from caller defaults to the lestephen.23 vision-capable set.
REVIEWERS_JSON="$OUTPUT_DIR/reviewers.json"
jq -n --arg p "$INSPECTION_PROMPT" '
  [ {agent_type:"codex",  perspective_label:"vision-codex",  prompt:$p} ]
' > "$REVIEWERS_JSON"

# The image path goes into a tiny doc-bundle so lib-multi-dispatch's
# --doc-path preflight (-f, -s) is satisfied. The actual image bytes
# travel via --image, not via doc-path content.
DOC_BUNDLE="$OUTPUT_DIR/image-context.md"
{
  echo "# Image inspection context"
  echo ""
  echo "Image path: $image_path"
  echo "Image size: $(stat -c%s "$image_path" 2>/dev/null || stat -f%z "$image_path") bytes"
  [[ -n "${context_doc:-}" && -f "${context_doc:-}" ]] && {
      echo ""
      echo "## Surrounding context"
      cat "$context_doc"
  }
} > "$DOC_BUNDLE"

bash "${HOME}/.claude-octopus/plugin/scripts/helpers/lib-multi-dispatch.sh" \
  --doc-path        "$DOC_BUNDLE" \
  --reviewers       "$REVIEWERS_JSON" \
  --output-dir      "$OUTPUT_DIR" \
  --image           "$image_path" \
  --task-prefix     "lib-inspect" \
  --min-reviewers   1 \
  --min-output-size 1   # visual inspections may answer in single words (e.g. "Green", "OK")
```

The dispatcher writes `<provider>-<task_id>.md` per reviewer and `dispatch.json` + `synthesis-input.md` for the synthesis step. Per-result-file headers will indicate whether image bytes attached (`# Images attached (codex -i): ...`) or degraded (`# Images requested but provider X lacks headless image attachment`).

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
