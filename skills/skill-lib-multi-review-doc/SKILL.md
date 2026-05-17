---
name: skill-lib-multi-review-doc
description: "Library: fan a document out to N providers with per-reviewer prompts, then synthesize — call this from other skills/plugins"
---

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

### STEP 2: Build per-reviewer dispatch commands

For each reviewer in the caller's list whose `agent_type` is available:

1. Generate a unique `task_id` (slug-safe, will appear in the output filename): `lib-review-$(date +%Y%m%d-%H%M%S)-<perspective_label_slug>`
2. Construct the full prompt body: `<reviewer.prompt>\n\n---\n\nDocument under review (path: <doc_path>):\n\n<contents of doc_path>`
3. Dispatch via `orchestrate.sh probe-single`. **Important call-signature notes (verified against `probe_single_agent` in `scripts/lib/workflows.sh`):**
   - The PROMPT-the-model-actually-sees is argument `$2` (the "perspective" slot — name is historical; it is the prompt body after persona injection).
   - Argument `$4` (`original_prompt`) is optional metadata for downstream synthesis context; the model does not receive it. Pass the document/topic summary here if you want; do not put the reviewer's instructions in `$4`.
   - The output file is written to `${output_dir}/<agent_type>-<task_id>.md`.

```bash
OUTPUT_DIR="${output_dir:-$HOME/.claude-octopus/results/lib-multi-review-doc/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTPUT_DIR"

# Per reviewer (run all in parallel using & + wait):
"${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" probe-single \
  "<reviewer.agent_type>" \
  "<full_prompt_body>" \
  "<task_id>" \
  "review of <doc_path basename>" \
  --output-dir "$OUTPUT_DIR" &
```

After spawning all reviewers, `wait` for them to finish.

### STEP 3: Render reviewer status table

While reviewers run (or as they complete), surface progress to the user:

```
🔴 technical-rigor       ⏳ running
🟡 structural-clarity    ✅ done (12s)
```

### STEP 4: Validation gate (MANDATORY)

After `wait`, confirm each expected per-reviewer output file exists. File pattern is `<agent_type>-<task_id>.md` (set by `probe_single_agent` in `scripts/lib/workflows.sh:128`):

```bash
FAIL=0
declare -A TASK_BY_LABEL  # populated when dispatching, keyed by perspective_label
for label in "${!TASK_BY_LABEL[@]}"; do
  task_id="${TASK_BY_LABEL[$label]}"
  agent_type="${AGENT_BY_LABEL[$label]}"
  FILE="${OUTPUT_DIR}/${agent_type}-${task_id}.md"
  if [[ ! -s "$FILE" ]]; then
    echo "❌ VALIDATION FAILED: no output for reviewer '$label' (expected $FILE)"
    FAIL=1
  else
    echo "✅ $label -> $FILE"
  fi
done
[[ $FAIL -eq 1 ]] && {
  echo "Multi-LLM dispatch did not produce expected files. Inspect ~/.claude-octopus/logs/."
  echo "Do NOT fall back to single-model review — surface the failure to the caller."
  exit 1
}
```

If validation fails: report which reviewers failed, show relevant log paths, and return failure to the caller. DO NOT proceed to synthesis with partial results unless the caller explicitly opted in via a `min_reviewers` threshold.

### STEP 5: Synthesis

Concatenate the per-reviewer outputs and apply the caller's `synthesis_prompt`. Synthesis runs on the host (Claude in Claude Code, Codex in Codex CLI), not as a fourth multi-provider call.

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
