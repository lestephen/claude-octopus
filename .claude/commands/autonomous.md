---
command: autonomous
description: "Work autonomously through a task — file issues for blockers at discovery time, continue past with documented assumptions"
skill: skill-autonomous-mode
argument-hint: '<task description>'
---

# Autonomous

Explicit autonomy grant. Use when you want a batch of work done without being asked to confirm every choice.

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user invokes `/octo:autonomous`, follow `skill-autonomous-mode` exactly. You are PROHIBITED from:**

- ❌ Halting to ask a question that you could resolve via judgment + an issue
- ❌ Batching issues to file at end-of-session (file at discovery time — context is fresh now, gone later)
- ❌ Continuing past a blocker silently (always emit the `⚠️ Filed issue #N` line)
- ❌ Performing irreversible destructive actions without explicit confirmation, even in autonomous mode
- ❌ Filing issues without a concrete "What I'd suggest" section

### EXECUTION

1. Follow `skill-autonomous-mode` Steps 1-7.
2. Start with `TaskCreate` for major work items so the user can see scope.
3. Select issue tracker (gh / azdo / local ISSUES.md) once, reuse for the session.
4. For each blocker: file issue with full context immediately, document the workaround assumption in scrollback, continue.
5. End with the structured summary (Shipped / Issues filed / Encoded assumptions / Explicitly deferred).

### Post-Completion

The end-of-session summary IS the post-completion. Do not also ask "what next?" — the summary should make the next step obvious.

If the autonomous batch revealed substantial new scope (issues that warrant a follow-up session), explicitly suggest one: "Want me to address #N + #M in a follow-up `/octo:autonomous` session?"
