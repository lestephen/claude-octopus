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
3. **Cross-model consensus required** — see "Consensus before action" section below. Specific action classes require ≥2 providers to agree before the action proceeds.
4. **Explicit user intent unambiguously requires their input** — e.g., the user previously said "ask me before X"; the user's task explicitly asks "should we…?"

For everything else (clarifying questions about implementation choices, "do you want option A or B" questions when one is reasonable, "should I add tests" etc.), autonomous mode SUPPRESSES the halt and proceeds with judgment + an issue if non-obvious.

## Consensus before action (lestephen.25+, closes GH #15)

**Background.** Autonomous mode previously trusted single-LLM judgment (usually the host Claude or one critique pass) for everything between halts. That trust failed in lestephen.23: I shipped a wrong "Gemini/Claude headless CLIs don't see images" matrix because the host model concluded from one failed test, never re-tested, and the dogfood critique was single-LLM (codex) framed leadingly. The fork ships `/octo:critique` precisely to catch what single-model judgment misses — and autonomous mode was bypassing that tool for the work it was built for.

**Rule.** In autonomous mode, the following action classes MUST pass cross-model consensus before the action is taken. Triggers are objective; there is no "I judge this doesn't qualify" interpretation gate.

### Consensus-required actions (objective trigger list)

| # | Trigger | Why mechanical |
|---|---------|----------------|
| 1 | Any `git commit` that touches code OR config OR schema OR manifest (see "code vs. trivial" below) | Code/config commits encode decisions that survive the session |
| 2 | Any `git push` to a shared remote | External visibility; harder to retract |
| 3 | Declaring a deliverable "shipped" / "complete" / "ready" to the user | Status claim the user will rely on |
| 4 | **Writing or editing a matrix / table / contract / capability statement / behavioral claim about any external system into ANY artifact** (code, docs, issue body, commit message, PR description, README, skill prose, scratchpad — file type does NOT exempt) | Exactly the v.23 failure mode; this trigger overrides the docs-only exemption below |
| 5 | Picking one of N approaches when ≥2 alternatives have been named in the conversation, OR when the change touches >1 file's public interface, OR when a new dependency / framework / cross-cutting pattern is introduced | Concrete signals; not "I think this is significant" |
| 6 | Closing a tracked issue as "done" or marking work-item "resolved" | Same as #3 — status claim |
| 7 | Acting on a single-LLM critique finding (apply OR dismiss) | Single-LLM critique can be wrong both ways |
| 8 | Merging a PR, creating a git tag, creating a GitHub release, publishing a package (npm/PyPI/etc.), deploying, modifying CI/CD config (`.github/workflows`, `.gitlab-ci.yml`, etc.), modifying IaC (Terraform/CloudFormation/Pulumi/Kubernetes manifests), modifying Dockerfile, modifying lockfile (only when intentional) | Release-grade actions create downstream reliance |
| 9 | Filing an issue whose body itself contains a capability/matrix/contract claim (trigger #4 applies to issue bodies too) | Issue bodies become reference material; #4 doesn't get bypassed by writing into the tracker |

**"Code" vs. trivial-content for trigger #1.** Treat the following as code: source files in any language (`.sh|.py|.ts|.tsx|.js|.jsx|.go|.rs|.java|.cpp|.c|.h|.swift|.kt|.rb|.php|.lua|.zig|.scala|.elm|.ex|.exs`), config (`.yaml|.yml|.toml|.json|.jsonc|.ini|.conf|.env`-templates), schema (`.sql|.proto|.graphql|.openapi.*|.json-schema`), build/deploy (`Dockerfile|Makefile|*.mk|.github/workflows/*|.gitlab-ci.yml|terraform/*|*.tf`), and manifests (`package.json|Cargo.toml|pyproject.toml|go.mod|requirements*.txt|plugin.json|marketplace.json|.claude-plugin/*`). Trivial-content exempt: typo-only fixes to documentation prose, version-bump-only commits in manifests (`x.y.z → x.y.z+1` with no other changes), CHANGELOG/RELEASE-notes entries, scratchpad / local-issues updates.

**The matrix/contract trigger (#4) fires regardless of file type.** A docs-only commit that adds "Gemini headless CLI cannot attach images" to a markdown file IS consensus-required. The docs-only exemption applies to trigger #1 (which is about generic code commits), not to trigger #4 (which is specifically about externally-verifiable behavioral claims wherever they appear).

### Mechanism

- **"Did I do this right?"** → `/octo:critique` (multi-LLM adversarial, ≥2 providers, the existing critique skill)
- **"Which of N approaches?"** → `/octo:debate` (structured N-way deliberation)

These are the existing fork tools. Autonomous mode now MUST use them at the trigger points above.

### Consensus definition

| Outcome | Meaning | Action |
|---------|---------|--------|
| ≥2 providers agree the action is sound, no SEV-1 from ANY, no majority SEV-2 | Consensus | Proceed |
| ≥2 providers raise SEV-2 (majority concern below blocking threshold) | Soft consensus failure | Address the SEV-2 findings, then re-dispatch; do NOT proceed citing "no SEV-1" alone |
| Exactly one provider raises SEV-1, the other(s) clean | Split | **Adjudication path:** re-dispatch the action to a third provider (if available) with the lone SEV-1 verbatim included so it can specifically assess the concern. If 2-of-3 then agree the concern is invalid, proceed with the dissenting SEV-1 documented in the appropriate per-action-class artifact: commit message for triggers #1/#4/#5/#7, PR description for trigger #2, issue comment for triggers #3/#6/#9, deployment log / release notes for trigger #8. If still split, file issue + halt + surface. |
| ≥2 providers raise SEV-1 (independent of each other) | Consensus failure | File issue with each SEV-1 verbatim, halt the action, surface to user |
| Single provider available (no quorum possible) | Cannot reach consensus | Autonomous mode DEGRADES to "information work + issue-filing only" for ALL consensus-required action classes (1-9, not just commit/push/ship). Document the degradation in scrollback. |
| 2 providers attempted but 1 dispatch failed (transient) | Not consensus | Re-dispatch the failed leg before counting votes. A failed dispatch is not a passing vote. |
| All providers find SEV-1 | Definitely wrong | File issue, halt, surface |

**Quoting requirement (partial mitigation of SEV-1b on host-model judgment).** Before declaring consensus reached, the host model MUST quote the verbatim severity-line outputs from each provider in scrollback (e.g. `Codex: NO BLOCKING FINDINGS`, `Gemini: SEV-2 ...`). Paraphrasing or summarizing the consensus result is forbidden — the user must be able to audit the literal provider outputs that the gate decision was based on. The lib-multi-dispatch.sh `dispatch.json` artifact is the canonical record; cite its path.

**Honest limit of this rule (acknowledged SEV-1b).** The quoting requirement provides *auditability* (user can after-the-fact verify the model's claim), not *enforcement* (the same host model still decides which lines to quote, whether they constitute consensus, and proceeds). A determined or anchored host model could still hallucinate "consensus reached" while quoting selectively. Fully machine-checkable enforcement requires a non-model layer — a hook or wrapper script that parses `dispatch.json`, applies the consensus definition table mechanically, and fails closed (refuses the action) on its own. That's tracked as a follow-up; the prose rule is the necessary precursor (defines the contract that the enforcement layer will check). Until the enforcement layer ships, the user MUST audit consensus declarations in scrollback rather than trusting them.

### Failure modes

| Failure | Skill behavior |
|---|---|
| Multi-LLM dispatch unavailable (e.g., codex auth broken AND gemini offline) | Autonomous mode degrades; document the degradation in scrollback; only trivial-content edits (typo, version bump, CHANGELOG) proceed |
| Critique returns "looks fine" from one provider, dispatch fails from another | NOT consensus (a failed dispatch is not a passing vote). Halt and re-dispatch the failed leg. |
| Critique is itself the action (e.g. user explicitly invoked /octo:critique) | Recursion guard — don't run consensus check on the consensus check; the critique IS the consensus |
| The same action keeps failing consensus after 3 dispatches | Halt for user input; this is a signal the work needs human direction |
| Provider CLIs route through the same backend (e.g. both wrap GPT-4 via OpenRouter) | Not actually independent. Consensus prompt MUST go through dispatch.sh with distinct `agent_type` values that map to distinct provider families (codex+gemini, codex+claude, gemini+claude). Two wrappers around the same backend do not count. |
| Reviewers see stale context (e.g. diff hash drifts during dispatch) | Include a content snapshot identifier in the consensus prompt — for diffs, `git diff HEAD | sha256sum` first ~16 chars; for files, the file's mtime+size. Reviewers must echo the identifier in their response so a context mismatch is detectable. |
| User invoked autonomous mode and only 1 provider is up | Degraded mode is honored — but autonomous mode itself REMAINS active; only the consensus-required actions block. User can override by leaving autonomous mode and re-invoking with the missing provider restored. |

### What this DOESN'T do

Every exemption below is qualified: **trigger #4 (matrix/contract/capability claim about external system behavior) ALWAYS applies regardless of artifact type**. If the content you're writing makes a verifiable claim about how some external system behaves, no exemption rescues you from consensus.

- Doesn't gate exploratory reads, greps, file inspection — those are information work, not actions.
- Doesn't gate scratchpad / local-notes / planning-document edits inside `~/.claude/scratchpad/` — **unless** the content hits trigger #4 (a capability/matrix claim drafted in scratchpad before commit IS consensus-required, because the scratchpad draft is the source the committed version copies from).
- Doesn't gate updates to the user's TaskCreate/TaskUpdate progress markers (that's session state, not an artifact).
- Doesn't gate filing routine issues (blocker-found-and-continue pattern) — **unless** the issue body hits trigger #9 (capability/matrix claim in the body itself).
- Doesn't gate typo-only doc fixes — **unless** the "typo fix" is actually editing a behavioral claim, which is trigger #4.
- Doesn't gate CHANGELOG / RELEASE-notes entries summarizing already-shipped work — **unless** the entry itself encodes a new behavioral/capability claim (e.g. "Now supports X" where X is a new verifiable behavior), which is trigger #4.
- Doesn't gate version-bump-only manifest commits (literally one line `x.y.z → x.y.z+1`).

### Why this rule, not "verify capability claims"

Earlier wording (GH #15 v1) said "verify capability claims with multi-LLM". That was too narrow and interpretive — "what counts as a capability claim?" is a debate, and a debatable gate is a skippable gate. The action-class trigger list above is mechanical: ask `git status` if uncertain, check what file types are staged, done. No judgment about whether something "counts."

### Cost acknowledgement

Multi-LLM critique on every code commit IS expensive. The user invoking autonomous mode is accepting that cost in exchange for correctness. There is intentionally no "small diff skip" exemption — small diffs were how lestephen.23 shipped the wrong matrix (one 5-line change to the skill banner). Cost is a separate problem; correctness comes first.

## ⚠️ MANDATORY COMPLIANCE — DO NOT SKIP

You are PROHIBITED from:

- **Halting work to ask the user a question that you could reasonably resolve via judgment + an issue.** The whole point of autonomy is to keep moving.
- **Bypassing safety/compliance gates** (defensibility-BLOCKED, security HIGH findings, ship critical issues). See precedence section above — these always halt.
- **Bypassing the consensus-before-action gate** (see "Consensus before action" section). Single-LLM judgment is NOT sufficient for the action classes listed there, even if the action seems obvious. The lestephen.23 wrong-matrix shipped because single-LLM judgment seemed obviously right.
- **Framing consensus-check prompts leadingly.** Prompts like "Already verified X works; find OTHER bugs" anchor reviewers and waste the consensus check. State the action to be checked neutrally; let providers reach their own conclusions.
- **Substituting two Claude subagents for multi-LLM consensus.** The point is provider diversity. Two Claude agents are one perspective with two names. The consensus check MUST dispatch to ≥2 distinct provider CLIs.
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
