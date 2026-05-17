---
name: skill-lib-multi-review-doc
description: "Library: fan a document out to N providers with per-reviewer prompts, then synthesize — call this from other skills/plugins"
interface_version: 2
---

> **Interface version 2** (lestephen.21+) — STEP 2-4 dispatch is now done via `scripts/helpers/lib-multi-dispatch.sh` (real bash). Consumer skills should rely on that helper, not on the inline pseudocode that was here in v1. The `lib-multi-dispatch.sh` helper enforces the strong validation gate (Status: SUCCESS + Output content) and writes `dispatch.json` + `synthesis-input.md` for the caller. v1 callers that walked the pseudocode by hand still work but should migrate.

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Library Skill — Multi-LLM Document Review

This is a **library skill**. It is meant to be invoked from other skills (including third-party plugins like `eki-kw`) or directly by the user when the multi-LLM review primitive is needed without the opinions baked into `/octo:review` or `flow-deliver`.

It takes a document, a set of reviewer perspectives, and a synthesis prompt, and returns the synthesis. It has no opinion on *what* to review for — that is supplied by the caller via per-reviewer prompts.

## When to use this skill

- A consumer skill needs N independent LLM perspectives on a document and a synthesis
- Direct user invocation when `/octo:review` or `flow-deliver` is the wrong shape (e.g., the doc is prose, not code, or the review angles are project-specific)

## When NOT to use this skill

- Single-LLM review is sufficient — invoke Claude directly with the doc and prompt, no orchestration needed
- The review angles you want are already captured by `/octo:review` (code) or `/octo:debate` (decisions) — use those
- You want to review an image, not text — use `skill-lib-multi-inspect-figure` instead
- You want to recompute a numerical claim from source data — use `skill-lib-independent-recompute` instead

## Input contract

The caller (a parent skill or the user) must supply:

| Input | Description | Example |
|---|---|---|
| `doc_path` | Absolute path to document under review | `/home/user/project/docs/draft-memo.md` |
| `reviewers` | Ordered list of `{agent_type, perspective_label, prompt}` | see below |
| `synthesis_prompt` | One-line synthesis instruction; the skill fills in the per-reviewer outputs | `"Identify the strongest objection across the three reviews and summarize what must change."` |
| `output_dir` (optional) | Where to write per-reviewer + synthesis files. Default: `~/.claude-octopus/results/lib-multi-review-doc/<timestamp>/` | |

Reviewer agent_types are the standard octopus persona/CLI names: `codex`, `gemini`, `claude` (host), `copilot`, `qwen`, `opencode`. Each per-reviewer prompt should be self-contained — it will be prepended to the doc content at dispatch time.

A minimal `reviewers` list:

```yaml
reviewers:
  - agent_type: codex
    perspective_label: technical-rigor
    prompt: |
      Review this document for technical correctness. Flag any claim where the
      stated evidence does not support the stated conclusion. Quote the specific
      sentences. Do not propose rewrites — only flag issues.
  - agent_type: gemini
    perspective_label: structural-clarity
    prompt: |
      Review this document for argument structure. For each major claim, trace
      whether the supporting evidence appears before or after the claim, and
      whether the reader can follow the logical chain without back-tracking.
```

## ⚠️ MANDATORY: Visual Indicators Protocol

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-LLM Document Review (library)`

Then output the provider banner:

```
🛠️ Library Phase: Multi-LLM document review fan-out + synthesis

Reviewers:
🔴 Codex CLI - <perspective_label from caller>
🟡 Gemini CLI - <perspective_label from caller>
🔵 Claude - Synthesis
```

Substitute the actual perspective labels from the caller's `reviewers` list. Mark any reviewer whose `agent_type` is unavailable as `(unavailable - skipping)` and continue with the rest.

## ⚠️ MANDATORY COMPLIANCE — DO NOT SKIP

You are PROHIBITED from:

- Doing a single-model review under any of the perspectives and pretending you ran the multi-LLM dispatch
- Substituting Agent subagents (which use Claude under the hood) for the genuine multi-provider call — the whole point is provider diversity
- Skipping the validation gate (see Step 4)
- Returning before the synthesis file is written

If a reviewer's provider is unavailable, skip THAT reviewer and report which were skipped. Do not silently fall back to Claude-only.

## Steps

### STEP 1: Provider check (MANDATORY)

@skills/blocks/provider-check.md

### STEP 2: Dispatch via `scripts/helpers/lib-multi-dispatch.sh` (v2 path — recommended)

**lestephen.21:** The dispatch + validation gate is now a real bash helper. Skill prose pseudocode (the v1 path documented below) is preserved as a fallback but should not be used by new consumer skills.

**Write the reviewers spec to a JSON file**, then call the helper:

```bash
OUTPUT_DIR="${output_dir:-$HOME/.claude-octopus/results/lib-multi-review-doc/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTPUT_DIR"

# Build reviewers.json from caller's input (filter to available providers first):
cat > "$OUTPUT_DIR/reviewers.json" <<EOF
[
  {"agent_type": "codex",  "perspective_label": "technical-rigor",     "prompt": "..."},
  {"agent_type": "gemini", "perspective_label": "structural-clarity", "prompt": "..."}
]
EOF

# Dispatch — single command, fan-out + validation + synthesis-input in one shot:
bash "${HOME}/.claude-octopus/plugin/scripts/helpers/lib-multi-dispatch.sh" \
    --doc-path     "$doc_path" \
    --reviewers    "$OUTPUT_DIR/reviewers.json" \
    --output-dir   "$OUTPUT_DIR" \
    --min-reviewers 2 \
    --task-prefix  "lib-review" \
    > "$OUTPUT_DIR/dispatch.stdout" 2>&1
DISPATCH_RC=$?
```

The helper output (`dispatch.stdout`) contains structured key=value lines:

```
DISPATCH_OUTPUT_DIR=<dir>
DISPATCH_TOTAL=<N>
DISPATCH_SUCCESS=<K>
DISPATCH_FAILED=<M>
DISPATCH_VERDICT=ok | insufficient
SYNTHESIS_INPUT=<dir>/synthesis-input.md
DISPATCH_JSON=<dir>/dispatch.json
```

Parse these to drive the synthesis step (STEP 5). The helper also writes:

- `<output-dir>/<agent>-<task_id>.md` per reviewer
- `<output-dir>/dispatch.json` — structured summary of all dispatch outcomes
- `<output-dir>/synthesis-input.md` — concatenated Output sections of successful reviewers, ready to feed into synthesis

### STEP 3: (informational) Render reviewer status to the user

The helper writes per-reviewer success/failure lines to stderr in real time. Parent skills can `tee` to surface progress to the user, or just wait for the helper to complete and report from `dispatch.json`.

### STEP 4: Validation gate (handled by the helper)

The helper enforces a **strong validation gate** (per audit issue #1):

1. Each expected output file exists and is non-empty
2. Each file's `## Status:` line is not `FAILED`
3. Each file's `## Output` section body is ≥ 50 chars (not just code-fence-only or headers)

If fewer than `--min-reviewers` pass: helper exits with code 4, writes `DISPATCH_VERDICT=insufficient`, and the caller MUST NOT proceed to synthesis with partial results. Surface the failure with a pointer to `dispatch.json` and `.dispatch-*.stdout` for the per-reviewer logs.

```bash
if [[ $DISPATCH_RC -ne 0 ]]; then
    echo "❌ VALIDATION FAILED — see $OUTPUT_DIR/dispatch.json"
    cat "$OUTPUT_DIR/dispatch.stdout"
    exit $DISPATCH_RC
fi
```

### STEP 5: Synthesis

The helper already wrote `synthesis-input.md` with the concatenated Output sections of successful reviewers. Read it and apply the caller's `synthesis_prompt`. Synthesis runs on the host (Claude in Claude Code, Codex in Codex CLI), not as a fourth multi-provider call.

```bash
SYNTHESIS_INPUT=$(grep '^SYNTHESIS_INPUT=' "$OUTPUT_DIR/dispatch.stdout" | cut -d= -f2-)
# Read $SYNTHESIS_INPUT, apply the synthesis_prompt, write to $OUTPUT_DIR/synthesis.md
```

Write the synthesis to `$OUTPUT_DIR/synthesis.md` with this structure:

```markdown
# Multi-LLM Review Synthesis

**Document:** <doc_path>
**Reviewers run:** <list of perspective_label : agent_type>
**Reviewers skipped (unavailable):** <list>
**Synthesis prompt:** <synthesis_prompt>

## Synthesis

<the synthesis prose>

## Per-reviewer findings (full text below)

<concatenated reviewer outputs, each under its own ## header>
```

### STEP 6: Return to caller

The skill's return value is the path to `synthesis.md` plus a one-paragraph headline. Print both:

```
SYNTHESIS: <path-to-synthesis.md>
HEADLINE:  <one-paragraph plain-English summary of what the reviewers found and what the synthesis concluded>
```

A parent skill (e.g., `skill-defensibility-pass`) reads the synthesis file to drive its next decision. A direct human caller reads the headline and opens the synthesis file for detail.

## Failure modes

| Failure | Skill behavior |
|---|---|
| Zero providers available | Refuse: print `❌ No multi-LLM providers available. Library skill requires at least 2 distinct providers (excluding host).` and exit non-zero |
| Only 1 reviewer succeeded, others failed | Report which succeeded/failed; ask caller whether to proceed with single-reviewer synthesis or abort. Default = abort. |
| `doc_path` does not exist or is empty | Refuse: print error and exit non-zero before dispatching |
| Synthesis prompt empty | Use a generic default: `"Identify the most important findings across the reviews. Group by severity. Note where reviewers agree vs. disagree."` |

## Integration notes for consumer skills

When a parent skill (e.g., `eki-kw:report-lint`, `skill-defensibility-pass`) calls this library skill:

1. Parent constructs the `reviewers` list specific to its purpose
2. Parent invokes this skill via the host's Skill tool (Claude Code: `Skill(skill="skill-lib-multi-review-doc", args="<yaml input block>")`)
3. Parent reads the returned synthesis path and uses it to inform its own output
4. Parent does NOT re-run any reviewers — this library handles all multi-LLM dispatch

If the parent needs additional perspectives later (e.g., a second pass after the first synthesis surfaces a new question), it should call this library skill again with a fresh `reviewers` list — do not extend an in-flight dispatch.
