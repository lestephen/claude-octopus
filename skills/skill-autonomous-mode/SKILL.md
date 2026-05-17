---
name: skill-autonomous-mode
description: "Autonomous execution protocol — work through a task without halting on user input. File issues for blockers at discovery time so context isn't lost."
interface_version: 1
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Autonomous Mode

When the user says "work autonomously", "do it all", "don't ask, just do it", or similar — they are explicitly granting permission to:

- Make reasonable judgment calls without confirming every choice
- Power through ambiguity rather than halting to ask
- File issues for things you can't resolve, but continue past them

This skill codifies that protocol. The goal: maximize what gets done in a single session, while losing **no context** about things that need follow-up.

## When this skill applies

**Explicit invocation only** (lestephen.22 codex F6 tightening):

- User invokes `/octo:autonomous <task>` directly
- User says any of these unambiguous phrases:
  - "work autonomously"
  - "do it all autonomously"
  - "no more questions, just do it" (note: "no more questions" alone is ambiguous; the conjunction matters)
  - "complete the work autonomously"
  - "you have permission to make calls without asking"
  - "fix them all and file issues for anything you can't"

**Does NOT activate on** ambiguous approval phrases: bare "do it", "go ahead", "proceed", "yes", "complete the work", "fix them". These usually mean "proceed with the agreed change", NOT "switch into blocker-skipping autonomous protocol". Activating autonomy on ambiguous approval surrenders user control unexpectedly.

When in doubt, ask once: *"Do you want me to enter autonomous mode (skip blockers, file issues for follow-up), or proceed step-by-step?"*

**It does NOT apply when:**

- User explicitly asks for input before each step
- Task involves destructive/irreversible actions (see the destructive-actions list below — these always halt for confirmation even in autonomous mode)
- The user is uncertain about scope and is actively exploring with you

## ⚠️ MANDATORY: Visual indicator

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Autonomous Mode`

Then briefly state your understanding of the task, your assumed scope, and any obvious risk flags. This is your one chance to be told you've misread the scope before you commit to a direction.

```
🐙 Autonomous: <one-sentence scope summary>
🛡️ Risk flags: <anything destructive, irreversible, or that touches external systems>
📋 Tracking: <where issues will be logged — GH repo or local ISSUES.md path>
```

## Core protocol

### 1. Plan before executing

Always start with `TaskCreate` for the major work items. Visible progress lets the user spot misdirection early. Don't plan every detail — just the top-level outline. Refine as you go.

### 2. Reasonable judgment, documented

When you make a non-obvious choice, document the assumption in:

- The commit message (one line per major assumption)
- The relevant code comment (if the assumption is encoded in the code)
- The issue body (if the assumption is something the user might want to revisit)

Examples of "reasonable judgment":

- Picking an API design from 2-3 equally-good alternatives → document the choice + why
- Naming a new function → just pick something idiomatic
- Choosing strict vs lenient error handling → default to strict, document
- Adding a new dependency → if it's a single-purpose utility, just add it; if it's a framework choice, file an issue

### 3. File issues at discovery time — NOT at end-of-session

The single most important behavior: **the moment you hit something the user needs to decide, file the issue immediately while context is fresh**. Do NOT batch up issues into a final summary list — you'll lose the specifics by the time you get there.

Issue triggers:

- Design choices that meaningfully change scope or shape of the deliverable
- Missing credentials / access that you've worked around but the user should provide properly
- Domain decisions you don't have the expertise to make
- Items deferred from current scope ("we said we'd come back to X")
- Anything you discovered while doing the requested work that's adjacent but out of scope

### 4. Issue tracker selection

Run this selection logic when filing the first issue, then reuse:

```bash
# Check if we're in a git repo with a known remote
REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || true)

if [[ "$REMOTE_URL" == *github.com* ]]; then
    # Confirm gh CLI is authenticated for the repo
    if gh auth status >/dev/null 2>&1 && gh repo view "$(echo "$REMOTE_URL" | sed -E 's|.*github.com[:/]([^/]+/[^/]+)\.git$|\1|; s|\.git$||')" --json hasIssuesEnabled --jq .hasIssuesEnabled 2>/dev/null | grep -q true; then
        ISSUE_TRACKER=gh
        ISSUE_TRACKER_TARGET="<owner>/<repo>"
    fi
elif [[ "$REMOTE_URL" == *dev.azure.com* || "$REMOTE_URL" == *visualstudio.com* ]]; then
    # Azure DevOps — file as Work Item via `az boards work-item create` if az CLI is available
    if command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; then
        ISSUE_TRACKER=azdo
    fi
fi

# Fallback: local ISSUES.md in the repo root (or current working dir if no repo)
if [[ -z "${ISSUE_TRACKER:-}" ]]; then
    ISSUE_TRACKER=local
    ISSUE_TRACKER_TARGET="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/ISSUES.md"
fi
```

### 5. Filing an issue

**For GitHub:**

```bash
gh issue create --repo "$ISSUE_TRACKER_TARGET" \
  --title "<one-line headline>" \
  --body "$(cat <<EOF
## What

<1-3 sentences: the specific thing that needs user input or resolution>

## Why it matters

<1-2 sentences: what breaks / what's degraded if this isn't fixed>

## Context

- Found during: <task you were doing when you hit this>
- Files affected: <list>
- Related commits: <SHAs or "in-flight on $(git branch --show-current)">

## Workaround / current state

<what you did instead while continuing the autonomous work>

## What I'd suggest

<concrete next step — implementation sketch, decision the user needs to make, etc.>

---
Filed by /octo:autonomous on $(date -u +%FT%TZ)
EOF
)"
```

**For Azure DevOps:**

```bash
az boards work-item create \
  --title "<one-line headline>" \
  --type "Bug" \
  --description "<same body shape as GH issue above, plain text or HTML>"
```

**For local fallback (no remote / no auth):**

Append to `ISSUES.md` at the repo root (or `pwd` if not in a repo). Format:

```markdown
## <ISO-8601-date> — <one-line headline>

**Triggered by:** /octo:autonomous during <task>
**Status:** open
**Files affected:** <list>

### What
<1-3 sentences>

### Why it matters
<1-2 sentences>

### Workaround / current state
<what was done instead>

### What I'd suggest
<concrete next step>

---
```

Create `ISSUES.md` if it doesn't exist; prepend a header noting that issues filed here can be migrated to a tracker later.

### 6. Continue past the blocker

After filing the issue, **continue the work**. Don't stop unless:

- The blocker is truly load-bearing for the rest of the task (e.g., missing credential needed for everything else)
- A reasonable workaround would do active harm (e.g., guessing at a config value that could expose secrets)

For each issue-and-continue, document in your in-session output:

```
⚠️ Filed issue #<N>: <title> — continuing with assumption: <what you assumed>
```

So the user sees in scrollback what you decided.

### 7. End-of-session summary

When the autonomous batch is complete, summarize:

- What was shipped (commits, tags, files changed)
- Issues filed during the session with links + one-line descriptions
- Assumptions that became encoded in the work (so the user can audit)
- Anything you specifically chose NOT to do and why

Format:

```markdown
## Autonomous session complete

### Shipped
- <commit SHA>: <description>
- <tag>: <version bump>
- ...

### Issues filed for user follow-up
- #<N>: <title> — <one-line context>
- #<M>: <title> — <one-line context>

### Encoded assumptions
- <file>:<line> assumes <X>; revisit if <condition>
- ...

### Explicitly deferred
- <thing>: deferred because <reason>; <suggested next step>
```

## Precedence vs other skills' MANDATORY COMPLIANCE rules

**Autonomous mode overrides standard "STOP / ask user" halts in other skills EXCEPT in these always-halt categories:**

1. **Safety / compliance gates** — `/octo:defensibility-pass` returns BLOCKED, `/octo:security` finds a HIGH-severity vulnerability, `skill-ship` reports critical issues. Autonomous mode does NOT bypass these; it stops, files the issue, and surfaces.
2. **Destructive actions** — see expanded list below. Never executed under autonomy without explicit per-action confirmation.
3. **Explicit user intent unambiguously requires their input** — e.g., the user previously said "ask me before X"; the user's task explicitly asks "should we…?"

For everything else (clarifying questions about implementation choices, "do you want option A or B" questions when one is reasonable, "should I add tests" etc.), autonomous mode SUPPRESSES the halt and proceeds with judgment + an issue if non-obvious.

## ⚠️ MANDATORY COMPLIANCE — DO NOT SKIP

You are PROHIBITED from:

- **Halting work to ask the user a question that you could reasonably resolve via judgment + an issue.** The whole point of autonomy is to keep moving.
- **Bypassing safety/compliance gates** (defensibility-BLOCKED, security HIGH findings, ship critical issues). See precedence section above — these always halt.
- **Batching issues to file at end-of-session.** File at discovery time. By end-of-session you will not remember the specifics.
- **Filing issues without a concrete "What I'd suggest" section.** "TODO: fix this" is not an actionable issue.
- **Continuing past a blocker silently.** Always print the `⚠️ Filed issue #N` line so the user can see in scrollback what you decided.
- **Working on irreversible destructive actions under autonomy** — see expanded list below; always require explicit confirmation.

## Destructive actions that ALWAYS halt for confirmation (Codex F7 expansion)

Even in autonomous mode, the following require an explicit user "yes" — judgment alone is not enough:

**Filesystem:**
- `rm -rf` (any recursive delete outside of clearly scoped temp dirs)
- Wholesale `find ... -delete` operations
- Overwriting files outside the current branch's known scope

**Git:**
- `git push --force` (any form)
- `git reset --hard` to a different commit than where you currently are
- `git clean -fdx`
- `git branch -D` for branches with unmerged work
- `git rebase -i` that drops commits
- Force-pushing to protected branches or `main`/`master` ever

**Infrastructure:**
- `terraform destroy` / `terraform apply` against production
- `kubectl delete` for namespaces, persistent volumes, or production workloads
- Cloud provider destructive operations (DELETE on databases, S3 bucket deletion, etc.)

**Data / schemas:**
- Dropping tables, columns, indexes
- Truncating tables
- Running production data migrations
- Modifying production rows directly

**Secrets / access:**
- Rotating or revoking credentials, API keys, OAuth tokens
- Modifying IAM policies, RBAC roles, ACLs
- Publishing or rotating signing keys

**External / public:**
- Publishing packages to npm, PyPI, etc.
- Creating GitHub releases tagged for distribution
- Sending emails, Slack messages, or other external communications
- Closing GitHub issues / PRs that other people opened

For each category, the same rule: surface the proposed action, get explicit confirmation, then proceed. "Do it" in the original autonomous grant does NOT cover these — they're a separate decision per occurrence.

## Failure modes

| Failure | Skill behavior |
|---|---|
| Can't determine issue tracker | Default to local `ISSUES.md`; warn once at session start |
| `gh` not authenticated | Try `gh auth login` once; if user not present, fall back to local |
| Same blocker encountered multiple times | File ONE issue; add subsequent occurrences as comments on the existing issue |
| Critical blocker that makes continuation harmful | Stop, file the issue, and exit the autonomous mode with a clear "blocked: see issue #N" — do not assume your way past genuine impossibility |

## Integration with other skills

- **`/octo:critique`** — when shipping substantive code in autonomous mode, run critique on the changes before final commit. Address HIGH findings; file issues for MEDIUM if continuing is reasonable.
- **`/octo:defensibility-pass`** — if autonomous work produces an external-bound document, run defensibility-pass as part of the autonomous flow. Refuse to mark the session "shipped" if defensibility returns BLOCKED.
- **`/octo:provider list`** — verify your dispatch fleet at session start. If a key provider is disabled or missing, factor that into what skills you can call autonomously.
- **`/octo:review`** — for code changes, run review (background) in parallel with the next task. Findings come back; you address them or file issues.

## Why this exists

The user explicitly invoking autonomous mode is them telling you: "I trust you to use judgment, but I want full transparency on what you assumed and what's outstanding."

The protocol's key insight: **assumptions are fine; lost context is not.** Every assumption that becomes a file-an-issue-and-continue keeps the work moving AND keeps the user able to audit/redirect later. Every assumption that goes undocumented becomes invisible technical debt the user can't see.
