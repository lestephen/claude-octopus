---
name: skill-lib-independent-recompute
description: "Library: ask one or more providers to recompute a quantitative claim from source data, then report deltas — call this from other skills/plugins"
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Library Skill — Independent Recompute of Quantitative Claims

This is a **library skill**. It takes a quantitative claim from a document plus the source data the claim is supposed to come from, and asks one or more providers to recompute the claim independently. It reports each provider's computed value alongside the original claim, with deltas.

This is the verification primitive behind `skill-defensibility-pass` Pass A. It exists separately so other workflows (audit, contract review, regulatory submission prep) can verify a single claim without invoking the full defensibility pipeline.

## When to use this skill

- A document makes a numerical claim that must hold up to hostile review and you want independent verification from the underlying source
- A consumer skill is gating on whether a claim is reproducible from the cited evidence
- Direct user: "this report says X% reduction over Y period from CSV Z — does that actually compute?"

## When NOT to use this skill

- The claim is qualitative ("materially below design intent") — use `skill-lib-multi-review-doc` instead with an appropriate critique prompt
- The source data is not accessible to providers (proprietary database behind auth they can't reach) — first export a reproducible extract, then call this skill with the extract
- You want a fast sanity check, not a defensibility-grade verification — just write a one-liner and read the source yourself

## Input contract

| Input | Description | Example |
|---|---|---|
| `claim` | The exact quantitative claim as written in the document | `"NH3 slip exceeded 5 ppm at 87% of operating hours during the December–January window."` |
| `source_paths` | List of files containing the source data the claim is drawn from | `["data/operating_hours.csv", "data/ammonia_slip.parquet"]` |
| `methodology_hint` (optional) | One-line hint about how the claim was computed, if known | `"Hourly average of stack NH3 sensor; threshold 5.0 ppm; coverage = hours with sensor data."` |
| `providers` (optional) | Which providers to dispatch. Default: all available code-capable providers (codex, gemini, claude) | |
| `tolerance` (optional) | Numerical tolerance for "agrees with claim". Default: 2% relative, 0.1 absolute (whichever is wider) | |
| `output_dir` (optional) | | default: `~/.claude-octopus/results/lib-recompute/<timestamp>/` |

`source_paths` must be readable by the provider being dispatched. For Codex/Gemini/Claude that means files on the local filesystem accessible to the host shell.

## ⚠️ MANDATORY: Visual Indicators Protocol

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Independent Recompute (library)`

Then output the provider banner:

```
🛠️ Library Phase: Independent recompute of quantitative claim

Computers:
🔴 Codex CLI - Independent recompute
🟡 Gemini CLI - Independent recompute
🔵 Claude - Independent recompute (host)
```

## ⚠️ MANDATORY COMPLIANCE — DO NOT SKIP

You are PROHIBITED from:

- "Recomputing" without actually reading the source data
- Accepting the claim and saying "matches" without independent computation
- Reporting agreement when providers actually disagreed but you decided one was probably right
- Falling back to a single computer when multi-provider was requested

Each provider must perform its own read+compute. If a provider can't access a source file (permission denied, missing, format unreadable), record that as `compute_status: unavailable` and continue with the others.

## Steps

### STEP 1: Provider check (MANDATORY)

@skills/blocks/provider-check.md

### STEP 2: Pre-flight on source data

For each `source_paths` entry, confirm it exists and is non-empty on the host. Print a small summary (size, mtime, first/last line for CSVs, schema for parquet via `head` or `parquet-tools` if available). If any source is missing, refuse and exit non-zero — recompute against absent source is meaningless.

### STEP 3: Build the recompute prompt

The prompt asks the provider to:

1. Read the source files at the given paths
2. State the methodology it will use to compute the claim
3. Show the computed value, with arithmetic
4. State whether it matches the claim within `tolerance`
5. List any caveats or assumptions it had to make

```
You are independently verifying a quantitative claim from a document.

CLAIM (verbatim from document):
$claim

SOURCE DATA (read these files; do not ask the user for input):
$source_paths

METHODOLOGY HINT (use as a starting point, but state your own methodology
and any deviation):
$methodology_hint

TOLERANCE: $tolerance

Report in this format:

## Methodology used
<your methodology in 3-6 sentences>

## Computation
<arithmetic showing how you got from source data to a value>

## Computed value
<single number or quantity>

## Comparison to claim
- Claim:    <restate>
- Computed: <your value>
- Delta:    <signed difference>
- Within tolerance: <yes | no | tolerance does not apply>

## Caveats
<anything you had to assume or anything the source did not let you verify>
```

### STEP 4: Dispatch per provider in parallel

For each available provider in `providers`:

```bash
OUTPUT_DIR="${output_dir:-$HOME/.claude-octopus/results/lib-recompute/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTPUT_DIR"

"${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" probe-single \
  "<provider>" \
  "recompute" \
  "lib-recompute-$(date +%s)-<provider>" \
  "$RECOMPUTE_PROMPT" \
  --output-dir "$OUTPUT_DIR" &
```

After spawning, `wait`.

### STEP 5: Validation gate (MANDATORY)

Confirm one output per dispatched provider. If any missing, surface the failure with log path. Partial results require explicit opt-in.

### STEP 6: Aggregate and compare

Parse each provider's "Computed value" and "Within tolerance" lines. Build the comparison table:

| Provider | Computed | Delta from claim | Within tolerance | Methodology notes |
|---|---|---|---|---|
| Codex | 87.3% | +0.3 pp | yes | hourly averages, 5.0 ppm strict |
| Gemini | 84.1% | −2.9 pp | no | hourly averages but excluded sensor-fault hours |
| Claude | 87.0% | 0 | yes | matched hint methodology |

Compute the cross-provider verdict:

- **CORROBORATED** — all providers within tolerance of claim AND within tolerance of each other
- **CLAIM MATCHES SOME** — at least one provider matches claim within tolerance; others disagree
- **CLAIM UNSUPPORTED** — no provider matches claim within tolerance
- **PROVIDERS DISAGREE** — providers' computed values differ from each other beyond tolerance; the claim is moot until methodology is resolved

The last verdict is the most informative for defensibility work: it surfaces methodology ambiguity that the document failed to anchor.

### STEP 7: Write synthesis

`$OUTPUT_DIR/synthesis.md`:

```markdown
# Independent Recompute — Synthesis

**Claim under verification:** <claim>
**Source files:** <list>
**Methodology hint:** <verbatim, or "(none provided)">
**Tolerance:** <as configured>

## Verdict: <CORROBORATED | CLAIM MATCHES SOME | CLAIM UNSUPPORTED | PROVIDERS DISAGREE>

<2-3 sentence summary of why>

## Per-provider comparison table

<the table from step 6>

## Per-provider raw output

<each provider's full output under its own ## header>
```

### STEP 8: Return to caller

```
SYNTHESIS: <path-to-synthesis.md>
VERDICT:   <one of the four>
HEADLINE:  <one-sentence summary including the claim and the most informative computed value>
```

## Failure modes

| Failure | Skill behavior |
|---|---|
| Zero recompute providers available | Refuse; exit non-zero |
| Only one provider available | Proceed with `⚠️ Single-provider recompute — cannot cross-check methodology.` Verdict is at best `MATCHES` or `UNSUPPORTED` (never `CORROBORATED`). |
| All providers report `compute_status: unavailable` for source access | Refuse; surface what failed |
| Providers report different units (ppm vs ppb, % vs ratio) | Do not auto-convert; surface as `PROVIDERS DISAGREE` with unit-mismatch note |

## Integration notes for consumer skills

`skill-defensibility-pass` Pass A is the primary consumer. The defensibility skill iterates over quantitative claims in a document (it identifies them via prior pass or via caller hint), calls this library per claim, and rolls up the per-claim verdicts.

A consumer that needs to verify many claims should dispatch this skill once per claim sequentially (not in parallel) — each invocation already fans out across providers, and overlapping invocations would hit provider rate limits.
