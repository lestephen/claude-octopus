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
| 1 | Any `git commit` that touches code OR config OR schema OR manifest (see "code vs. trivial" below for the explicit file-extension list) | Code/config commits encode decisions that survive the session |
| 2 | Any `git push <target>` where `<target>` (named remote OR URL passed directly) is NOT a local-only URL. Local-only is defined by HOST POSITION only — substring matches don't count (lestephen.29 v3 fix to claude SEV-1: `.*localhost` matched URLs like `https://evil.com/?ref=localhost`). Mechanical extraction: `url=$(if git remote get-url "$target" 2>/dev/null; then :; else echo "$target"; fi)` resolves both forms (named remote → URL; URL-arg → URL). Then extract host: `host=$(echo "$url" \| sed -E 's\|^[a-z]+://([^@]+@)?([^:/]+).*\|\\2\|; s\|^/.*\|LOCAL\|; s\|^\\./.*\|LOCAL\|; s\|^file:.*\|LOCAL\|')`. Consensus-EXEMPT iff `host` ∈ {`LOCAL`, `localhost`, `127.0.0.1`, `[::1]`, `::1`}. Anything else (any hostname, public or private/enterprise) → consensus required. | External visibility; harder to retract |
| 3 | Outputting status-claim words in user-facing scrollback, commit messages, PR descriptions, or release notes. Regex (extended POSIX, case-insensitive, with stem matching to catch tense/inflection — lestephen.29 v3 fix to claude SEV-2): `\\b(ship(ped\|ping\|s)?\|complet(e\|ed\|ing\|es)\|ready (to merge\|for review\|to ship\|to land)\|done\|merged\|landed\|(clos\|fix\|resolv)(e\|ed\|es\|ing) #?[0-9]+)\\b`. Over-triggers on benign uses ("the test is done") — that's intentional; mechanical = some false-positives in exchange for no false-negatives. | Status claim the user will rely on |
| 4 | **Writing or editing a matrix / table / contract / capability statement / behavioral claim about any system or tool not in this repo's source tree (external API, third-party CLI, model provider, OS, network protocol, etc.) into ANY artifact** (code, docs, issue body, commit message, PR description, README, skill prose, scratchpad — file type does NOT exempt) | Exactly the v.23 failure mode; this trigger overrides the docs-only exemption below |
| 5 | Picking one of N approaches when ANY of: (a) ≥2 alternatives have been explicitly named in the conversation (count the alternatives mentioned by either party in the last 20 turns), OR (b) the change adds/removes a function/class/type/CLI flag that already has references in the diff base — concrete check: run on UNSTAGED dirty tree BEFORE staging (lestephen.29 v3 fix to claude SEV-2 HEAD-timing): for each added symbol named SYM, `git grep -F "SYM" -- '*.sh' '*.py' '*.ts' '*.tsx' '*.js' '*.jsx' '*.go' '*.rs' '*.java' '*.md'` (each extension as its own pathspec — brace expansion doesn't work in git-grep pathspecs, lestephen.29 v3 fix to claude SEV-2) returns ≥1 match outside the changing file, OR (c) the change introduces a new dependency: `git diff -- 'package.json' 'Cargo.toml' 'pyproject.toml' 'go.mod' 'requirements*.txt' 'Pipfile' 'uv.lock'` shows at least one added top-level dependency entry. (Clause (d) "adds a pattern that >2 files would need to adopt" — DROPPED per both providers SEV-1: speculative/non-mechanical.) | Concrete signals: explicit count + grep + dependency-manifest diff |
| 6 | Closing a tracked issue as "done" or marking work-item "resolved" (any `gh issue close`, `az boards work-item update --state Resolved`, Jira transition to Done, Linear status=Done, etc.) | Same as #3 — status claim |
| 7 | Acting on a single-LLM critique finding (apply OR dismiss) | Single-LLM critique can be wrong both ways |
| 8 | Release-grade actions: merging a PR (`gh pr merge`, GitLab "Merge" click), creating a git tag (`git tag` for any name not starting with `_local-`), creating a GitHub release (`gh release create`), publishing a package (`npm publish`, `cargo publish`, `python -m twine upload`, `gh workflow run publish*`, etc.), deploying (any command containing the word `deploy`, `kubectl apply`, `terraform apply`, `helm upgrade`, etc.), modifying CI/CD config (`.github/workflows/**`, `.gitlab-ci.yml`, `.circleci/**`, `azure-pipelines.yml`, `.buildkite/**`), modifying IaC (`*.tf`, `*.tfvars`, CloudFormation YAML, Pulumi files, `k8s/**.yaml`, Kustomize, Helm charts), modifying `Dockerfile`/`Containerfile`/`*.dockerfile`, OR modifying ANY lockfile (`package-lock.json`/`yarn.lock`/`Cargo.lock`/`poetry.lock`/`Pipfile.lock`/`uv.lock`). (Lockfile-exception clause DROPPED in lestephen.29 per claude SEV-1: "i.e." inverted intent — a top-level dep bump legitimately produces transitive entries absent from the manifest diff, so the original clause would have tripped every routine dep change.) | Release-grade actions create downstream reliance |
| 9 | Filing an issue whose body contains ANY of: (a) a capability/matrix/contract claim (trigger #4 applies to issue bodies), (b) an approach selection between named alternatives (trigger #5 applies), OR (c) a literal substring matching `won't fix`, `wontfix`, `deferred to`, `accepted risk`, `risk accepted`, `do not implement`, `won't implement` (case-insensitive) — these are risk-acceptance/deferral keywords. (Clause (d) "What I'd suggest section" — DROPPED in lestephen.29 per gemini SEV-2: required semantic analysis of section content.) | Issue bodies become reference material; the deferral-keyword check is mechanical |

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
| Majority of parseable providers raise SEV-2 (formula: `providers_with_sev2 * 2 > parseable_providers`, machine-enforced by `octo-consensus`) | Soft consensus failure | Address the SEV-2 findings, then re-dispatch; do NOT proceed citing "no SEV-1" alone. **2-provider dispatch note (lestephen.29 closes GH #17 #2):** with only 2 reviewers, "majority" requires BOTH (2*2=4 > 2). A single SEV-2 in 2-provider mode is minority and the gate proceeds — that's by design (allowing minority dissent prevents one provider's idiosyncrasies from blocking everything), but consider re-dispatching with a 3rd provider when stakes are high. |
| Exactly one provider raises SEV-1, the other(s) clean | Split | **Adjudication path (lestephen.29 fix to GH #17 anchoring + provider-diversity concerns):** dispatch the action to a third provider with a FRESH prompt — only the action under review, no mention of the prior SEV-1. "Third provider" means an `agent_type` whose family (per the `_octo_consensus_provider_family` function in `scripts/lib/consensus-gate.sh`) is distinct from BOTH the dissenter's family AND the cleaner's family — concrete: if dissent was from `codex-mini` (codex family) and cleaner from `claude-sonnet` (claude family), valid third-providers are `gemini*`, `qwen*`, `cursor-agent*`, `perplexity*`, `copilot*`, `ollama*`, `opencode*`, `openrouter*` (any non-codex, non-claude family). The third provider must reach its own independent verdict. If the third reviewer raises SEV-1 (same concern or different), it's now 2-of-3 with SEV-1 → HARD BLOCK regardless of overlap. If the third is clean (NO BLOCKING or only SEV-3+), the original dissent is presented to the user with the third's independent clean read as counter-evidence — user decides ship-with-documented-dissent vs. halt. Do NOT auto-proceed on "2 of 3 say clean" if those 2 saw different evidence than the 3rd. |
| ≥2 providers raise SEV-1 (independent of each other) | Consensus failure | File issue with each SEV-1 verbatim, halt the action, surface to user |
| Single provider available (no quorum possible) | Cannot reach consensus | Autonomous mode DEGRADES to "information work + issue-filing only" for ALL consensus-required action classes (1-9, not just commit/push/ship). Document the degradation in scrollback. |
| 2 providers attempted but 1 dispatch failed (transient) | Not consensus | Re-dispatch the failed leg before counting votes. A failed dispatch is not a passing vote. |
| All providers find SEV-1 | Definitely wrong | File issue, halt, surface |

**Machine enforcement (lestephen.27+, closes the SEV-1b acknowledged below).** The consensus check is now enforced by `bin/octo-consensus` (delegating to `scripts/lib/consensus-gate.sh`), which parses `lib-multi-dispatch.sh`'s `dispatch.json` mechanically, applies the consensus-definition table from this section as code, and exits non-zero on BLOCK. The host model MUST invoke it like this:

```bash
# After dispatching critique via lib-multi-dispatch.sh:
$PLUGIN_DIR/bin/octo-consensus check \
    "$OUTPUT_DIR/dispatch.json" \
    "<short action description>"
# Exit 0 → ALLOW (proceed); 1 → HARD BLOCK (≥2 SEV-1); 2 → SOFT BLOCK (≥2 SEV-2);
# 3 → SPLIT (adjudicate); 4 → NO QUORUM / NO DIVERSITY; 5 → PARSE ERROR.
```

The gate enforces:
- ≥2 successful reviewers (quorum)
- ≥2 distinct provider families (codex+codex-mini is NOT diversity; gate maps `qwen`/`cursor-agent` to gemini family because they fork gemini CLI)
- Severity-line grammar: `^SEV-[1-5]: <name> — <why>` or `^NO BLOCKING FINDINGS` (anchored, in the result file's `## Output` section). Reviewers who emit findings in any other format count as **unparseable** and don't contribute votes — this is intentional, it prevents the "host model decides what the prose means" failure mode.
- Consensus definition: ALLOW iff ≥2 parseable providers, no SEV-1 from any, no majority SEV-2.

**Quoting requirement (additional auditability layer).** Even with the machine gate, the host model SHOULD quote the verbatim severity-line outputs and the gate verdict block to scrollback so the user can audit without re-running. Cite the `dispatch.json` path.

**Honest residual limit.** `octo-consensus` enforces the gate at the point of invocation, but a host model could still skip invoking the gate entirely. Hooking the gate into git pre-commit / CI / wrapper-around-`/octo:autonomous` is the next layer (tracked in GH #16's follow-ups). For now, the autonomous-mode protocol REQUIRES invoking `octo-consensus check ...` before each consensus-required action class; the MANDATORY COMPLIANCE rule below makes skipping a violation.

### Failure modes

| Failure | Skill behavior |
|---|---|
| Multi-LLM dispatch unavailable (e.g., codex auth broken AND gemini offline) | Autonomous mode degrades; document the degradation in scrollback; only trivial-content edits (typo, version bump, CHANGELOG) proceed |
| Critique returns "looks fine" from one provider, dispatch fails from another | NOT consensus (a failed dispatch is not a passing vote). Halt and re-dispatch the failed leg. |
| Critique is itself the action (e.g. user explicitly invoked /octo:critique) | Recursion guard — don't run consensus check on the consensus check; the critique IS the consensus |
| The same action keeps failing consensus after 3 dispatches | Halt for user input; this is a signal the work needs human direction |
| **3 substantive critique rounds** (each round addressing the previous round's findings, even if findings are different each time) | **Halt for user input** (lestephen.27 tightening, after GH #16 hit 6 rounds). Each round costs time + tokens; if 3 rounds haven't reached consensus, escalate the decision: ship-with-documented-residual-risk vs. keep iterating vs. abandon. Present the iteration history (each round's verdicts) so the user can decide. |
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
- **Skipping `bin/octo-consensus check` after dispatching the critique.** Dispatching multi-LLM critique without then running `octo-consensus check $dispatch_json` defeats the gate — you've spent the tokens but not enforced the check. Invoke the gate, quote its verdict block in scrollback, and respect its exit code.
- **Re-running the gate until it ALLOWs without addressing the findings.** If `octo-consensus` returns BLOCK, the next dispatch must be on a *modified* action that addresses the findings, not the same action with the hope that one of the providers will be in a different mood. Quote the previous BLOCK verdict in the next dispatch's prompt so reviewers know what was already raised.
- **Running more than 3 substantive critique rounds without surfacing to the user** (lestephen.27 cap, after GH #16's 6-round dogfood). Each round is expensive in tokens and time. Address findings in iteration 1 → re-dispatch → address in iteration 2 → re-dispatch → if iteration 3 STILL has SEV-1, present the round history to the user and let them choose ship/iterate/abandon. Even if every round's findings are different (legitimate progress), the cap fires — long iteration loops often signal a code area too edge-case-heavy for prose-rule gating and need user direction.
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
