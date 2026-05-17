---
command: review
description: Enhanced multi-LLM review with inline PR comments — escalation path beyond Claude-native /review
argument-hint: '[--wait|--background] [--base <ref>] [--scope auto|working-tree|branch|pr|staged] [focus ...]'
---

# /octo:review

## MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:review`, you MUST execute the enhanced multi-provider review workflow below.** You are PROHIBITED from substituting Claude-native `/review`, direct reading, or a single-model review unless the user changes commands.

## Argument flags (lestephen.19+)

`/octo:review` accepts the same scope / execution flags as `/codex:review` to make scope explicit and skip the interactive Q&A when the caller already knows what they want. Raw arguments are available as `$ARGUMENTS`.

| Flag | Default | Description |
|---|---|---|
| `--scope <mode>` | `auto` | One of: `auto`, `working-tree`, `branch`, `pr`, `staged`. `auto` picks based on git state (see Step 0.5). |
| `--base <ref>` | inferred | Base ref for branch-scope diff. Defaults to `origin/main`, falling back to `main`, then merge-base of current branch. |
| `--wait` | — | Force foreground execution. Skip the size-based "wait vs background" prompt. |
| `--background` | — | Force background execution via Claude background Bash task. Skip the prompt. |

The remaining argument words (e.g. `correctness security`) are interpreted as focus areas — equivalent to selecting them in the focus Q&A.

If `--scope` is supplied, skip the "What should be reviewed?" question in Step 1. If `--wait` or `--background` is supplied, skip the size-based prompt in Step 0.5.

## Positioning

Three review entry points coexist in Claude Code v2.1.111+ — pick the right one per context:

| Command | Scope | Providers | When |
|---|---|---|---|
| Claude-native `/review` | Single-turn, current diff | Claude only | Ordinary review, one perspective suffices |
| `/ultrareview` (CC v2.1.111+) | Cloud, parallel multi-agent | Claude parallelism | Pre-merge PR review without leaving CC |
| `/octo:review` (this) | Multi-LLM, inline PR comments | Codex + Gemini + Claude | Provider diversity, adversarial cross-check, stricter escalation |

Use `/octo:review` when the user explicitly wants enhanced multi-LLM review, multiple model opinions, provider diversity, or stricter escalation workflows. If CC v2.1.111+ and the user just says "review this", prefer `/ultrareview` unless provider diversity is specifically requested.

When the user invokes this command (e.g., `/octo:review <arguments>`):

**MANDATORY: Before displaying the banner or starting the review, use the Bash tool to check provider availability:**

```bash
echo "PROVIDER_CHECK_START"
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
printf "gemini:%s\n" "$(command -v gemini >/dev/null 2>&1 && echo available || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)"
printf "opencode:%s\n" "$(command -v opencode >/dev/null 2>&1 && echo available || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo available || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo available || echo missing)"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
printf "openrouter:%s\n" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)"
echo "PROVIDER_CHECK_END"
```

Then display the banner with ACTUAL results:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** — Multi-LLM Code Review

Providers:
🔴 Codex CLI: [Available ✓ / Not installed ✗] — logic and correctness
🟡 Gemini CLI: [Available ✓ / Not installed ✗] — security and edge cases
🔵 Claude: Available ✓ — architecture and synthesis
🟣 Perplexity: [Available ✓ / Not configured ✗] — CVE lookup
```

**PROHIBITED: Displaying only "🔵 Claude: Available ✓" without checking and listing other providers.**

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST execute this command by calling `orchestrate.sh` as documented below. You are PROHIBITED from:**
- ❌ Doing the work yourself using only Claude-native tools (Agent, Read, Grep, Write)
- ❌ Using a single Claude subagent instead of multi-provider dispatch via orchestrate.sh
- ❌ Skipping orchestrate.sh because "I can do this faster directly"

**Multi-LLM orchestration is the purpose of this command.** If you execute using only Claude, you've violated the command's contract.

---

## Step 0: Parse flags from `$ARGUMENTS`

Before asking any questions, parse the raw argument string for the flags documented above. Strip recognized flags out of `$ARGUMENTS`; remaining words become focus-area hints.

```
SCOPE=auto              # from --scope
BASE=                   # from --base
EXEC_MODE=              # "wait" | "background" | "" (ask)
FOCUS_HINTS=()          # remaining words after flag stripping
```

`--scope` values:

- `auto` — inspect git state (Step 0.5) and pick one of the others
- `working-tree` — uncommitted changes (`git status --short`; `git diff` + `git diff --cached`)
- `staged` — staged changes only (`git diff --cached`)
- `branch` — committed range vs `--base` (default `origin/main` → fallback chain)
- `pr` — current branch's open PR (`gh pr view --json number`)

## Step 0.5: Estimate review size & decide execution mode

If `EXEC_MODE` is empty (caller didn't pass `--wait` or `--background`), estimate the work size to recommend foreground vs. background. Run these in order:

```bash
# Common to all scopes
git status --short --untracked-files=all
```

Per scope:

- `working-tree`: also run `git diff --shortstat` and `git diff --shortstat --cached`
- `staged`: `git diff --shortstat --cached`
- `branch`: resolve `BASE` (try `origin/main` → `main` → `git merge-base @{u} HEAD`), then `git diff --shortstat <BASE>...HEAD`
- `pr`: `gh pr diff $(gh pr view --json number --jq .number) --name-only` and `git diff --shortstat <BASE>...HEAD`
- `auto`: pick `pr` if open PR exists; else `staged` if non-empty cached diff; else `working-tree`

Treat untracked files or directories as reviewable work even when `git diff --shortstat` is empty. Only conclude "nothing to review" when the relevant scope is genuinely empty (status empty AND diff empty AND no untracked files).

Recommend the execution mode:

- **Foreground (wait)**: the review is clearly tiny — roughly 1-2 files total and no sign of broader directory-sized changes
- **Background**: in every other case, including unclear size
- **When in doubt, run the review** in the background rather than declaring there's nothing to review

Then use `AskUserQuestion` exactly once to confirm — putting the recommended option first and suffixing its label with `(Recommended)`:

```javascript
AskUserQuestion({
  questions: [{
    question: "How should this review run?",
    header: "Execution",
    multiSelect: false,
    options: [
      // Recommended option first; example shown for "background" recommendation:
      {label: "Run in background (Recommended)", description: "Dispatch as a Claude background Bash task. ~N files changed."},
      {label: "Wait for foreground completion", description: "Run synchronously. You'll see the multi-LLM dispatch results inline."}
    ]
  }]
})
```

Skip this Q&A if `EXEC_MODE` was already set by `--wait` / `--background`.

If the size estimate shows zero work AND no untracked files AND no open PR, tell the user there's nothing to review and stop. Do not invent work to do.

## Step 1: Ask Clarifying Questions / Context Acquisition

**Determine mode based on session autonomy:**

If `AUTONOMY_MODE` env var is `autonomous`, or session is running headlessly, or `OCTOPUS_WORKFLOW_PHASE` is set (indicating a pipeline context like `/octo:develop` or `/octo:embrace`), skip Q&A and auto-infer with ALL focus areas:
1. If `SCOPE` was set by `--scope`, use it; else: run `git diff --cached` — if non-empty, `target=staged`
2. Run `gh pr view --json number` — if open PR exists, set `target=<pr_number>`
3. Otherwise `target=working-tree`
4. Set `provenance=unknown`, `autonomy=autonomous`, `publish=ask`, `debate=auto`, `history=auto`, `focus=["correctness","security","architecture","tdd"]`

**Otherwise (supervised mode), use AskUserQuestion to ask the remaining questions.**

**Skip the "What should be reviewed?" question when `SCOPE` was set via `--scope` in Step 0** — use the resolved scope as `target` directly. Otherwise include the target question:

```javascript
AskUserQuestion({
  questions: [
    // ↓ Include this first question ONLY when SCOPE was not set via --scope:
    {
      question: "What should be reviewed?",
      header: "Target",
      multiSelect: false,
      options: [
        {label: "Staged changes", description: "git diff --cached — what you're about to commit"},
        {label: "Open PR", description: "Review the current branch's open pull request"},
        {label: "Working tree", description: "All uncommitted changes"},
        {label: "Specific path", description: "A file or directory"}
      ]
    },
    {
      question: "What should the fleet focus on?",
      header: "Focus",
      multiSelect: true,
      options: [
        {label: "Correctness", description: "Logic bugs, edge cases, regressions"},
        {label: "Security & Edge Cases", description: "OWASP, race conditions, partial failures"},
        {label: "Architecture", description: "API contracts, integration, breaking changes"},
        {label: "TDD discipline", description: "Verify failing-test-first evidence and minimal implementation"},
        {label: "All areas (Recommended)", description: "Correctness + Security + Architecture + TDD"}
      ]
    },
    {
      question: "How was this code produced?",
      header: "Provenance",
      multiSelect: false,
      options: [
        {label: "Human-authored", description: "Standard review"},
        {label: "AI-assisted", description: "Review for over-abstraction and weak tests"},
        {label: "Autonomous / Dark Factory", description: "Elevated rigor: verify tests, wiring, operational safety"},
        {label: "Unknown", description: "Assume less context, verify from code and tests"}
      ]
    },
    {
      question: "Should findings be posted to the open PR?",
      header: "Publish",
      multiSelect: false,
      options: [
        {label: "Ask me after review", description: "Show findings first, then decide"},
        {label: "Auto-post if confident", description: "Post inline comments when confidence ≥ 85%"},
        {label: "Never — terminal only", description: "Always show in terminal, never post to PR"}
      ]
    }
  ]
})
```

**WAIT for the user's answers before proceeding.**

## Step 2: Build Review Profile

After receiving answers, map them to a JSON profile:

```javascript
const profile = {
  target: <from answer or inference>,  // "staged" | "working-tree" | PR# | path
  focus: <multi-select answers as array>,
  provenance: <answer>,                // "human" | "ai-assisted" | "autonomous" | "unknown"
  autonomy: <detected mode>,           // "supervised" | "autonomous"
  publish: <answer>,                   // "ask" | "auto" | "never"
  debate: "auto",                      // always default to auto debate
  history: "auto"                      // "auto" | "fresh"
}
```

If the user includes `fresh` in the command text, do not treat it as a file path. Keep the normal target inference and set `history: "fresh"` so this run ignores prior PR review rounds.

## Step 2.5: Ensure plugin root is resolvable (run via Bash tool)

```bash
OCTO_ROOT="${HOME}/.claude-octopus/plugin"
if [[ ! -x "$OCTO_ROOT/scripts/orchestrate.sh" ]]; then
  helper="$OCTO_ROOT/scripts/helpers/ensure-plugin-root.sh"
  if [[ ! -x "$helper" ]]; then
    helper="$(find "${HOME}/.claude/plugins/cache" "${HOME}/Library/Application Support/Claude" "${LOCALAPPDATA:-/dev/null}/Claude" "${XDG_DATA_HOME:-${HOME}/.local/share}/Claude" -maxdepth 8 -path "*/nyldn-plugins/octo/*/scripts/helpers/ensure-plugin-root.sh" -print -quit 2>/dev/null)"
  fi
  [[ -x "$helper" ]] && bash "$helper" >/dev/null 2>&1 || true
fi
test -x "$OCTO_ROOT/scripts/orchestrate.sh" && echo "plugin-root:ok" || echo "plugin-root:missing"
```

If the output is `plugin-root:missing`, stop and ask the user to run `/octo:setup`.

## Step 3: Execute Review Pipeline

Run via Bash tool. **Honor `EXEC_MODE`** from Step 0:

- If `EXEC_MODE=wait` (or user chose foreground in Step 0.5): run synchronously (`run_in_background: false` — the default).
- If `EXEC_MODE=background` (or user chose background in Step 0.5): dispatch as a Claude background Bash task (`run_in_background: true`). You'll be notified when it completes; in the meantime, do not poll — continue with other work the user gives you.

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh code-review '<profile-json>'
```

Where `<profile-json>` is the JSON profile built in Step 2. The profile's `target` field reflects the resolved scope from Step 0 / Step 1.

The pipeline runs 3 rounds (parallel fleet → verification → synthesis) and outputs findings. If a PR is open and publish is not "never", it offers to post inline comments.

Round-aware PR history is enabled automatically for open PR reviews. Local state is stored at `~/.claude-octopus/pr-state/<host>/<owner>/<repo>/<pr>.json` and is used to show addressed, persistent, new, and regressed finding counts across repeated `/octo:review` runs. Set `OCTOPUS_PR_HISTORY=0` before invoking the command to disable all history reads and writes.

Each review also writes a local proof packet under `~/.claude-octopus/runs/<run-id>/`. The packet includes `state.json`, `proof.jsonl`, `summary.md`, findings artifacts, and provider substitution records so review claims can be checked after the chat scroll is gone. Set `OCTOPUS_PROOF_PACKET=0` to disable proof packet writes.

If a project already has `graphify-out/GRAPH_REPORT.md`, `/octo:review` also passes a compact Graphify companion context into the reviewer prompt as an orientation map. This is passive: Octopus does not build or refresh the graph during review, and `OCTOPUS_GRAPHIFY=0` disables the injection.

## What `/octo:review` checks

- Correctness: logic bugs, edge cases, regressions, unreachable code
- Security: OWASP Top 10, injection, auth flaws, data exposure (Gemini specialist)
- Architecture: API contracts, integration issues, breaking changes (Claude specialist)
- CVE lookup: known vulnerabilities in dependencies (Perplexity → Gemini → Claude WebSearch)
- TDD compliance and test-first evidence (when provenance is AI-assisted/autonomous)
- Autonomous codegen risk: placeholder logic, unwired code, speculative abstractions

## REVIEW.md support

Add a `REVIEW.md` file to your repository root to guide what `/octo:review` flags.
Drop-in compatible with Claude Code's managed Code Review service.

```markdown
# Code Review Guidelines

## Always check
- New API endpoints have corresponding integration tests

## Style
- Prefer early returns over nested conditionals

## Skip
- Generated files under src/gen/
```
