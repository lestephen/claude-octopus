# Slash Command Conventions (lestephen fork)

Conventions for `.claude/commands/*.md` slash command frontmatter and prose. Goal: predictable shape across all 50+ commands so users (and tooling) can compose them without per-command surprises.

## argument-hint ordering — POSIX (flags first)

**Rule:** `argument-hint:` puts flags before positional arguments, matching POSIX convention and most existing fork commands.

**Examples:**
```yaml
# Good (POSIX flags-first):
argument-hint: '[--scope auto|branch|pr] [--wait|--background] <target>'
argument-hint: '[--audience customer|supplier] [--profile <path>] <doc-path>'

# Bad (target-first — fork pre-lestephen.29 inconsistency):
argument-hint: '<target> [--scope auto|branch|pr]'
```

**Why:** Internal consistency. `/octo:review` was already POSIX (`[--wait|--background] [--base <ref>] [--scope ...] [focus ...]`); the lestephen.18-23 additions (`/octo:critique`, `/octo:defensibility`, `/octo:argument-strength`, `/octo:visual-review`) drifted to target-first. lestephen.29 (GH #10) standardizes everything on POSIX.

**Exception:** Commands with a single positional and no flags (e.g. `/octo:autonomous '<task description>'`) don't need to think about ordering.

## description style

- Lead with a verb phrase or noun phrase, NOT "This command…" or "Use this to…"
- Mention the differentiator vs. similar commands (e.g. `/octo:review` vs `/review` vs `/ultrareview`)
- Keep under 120 chars where possible

## Frontmatter required fields

```yaml
---
command: <slug>            # matches the file basename (without .md)
description: <one-line>    # under 120 chars
skill: <skill-name>        # if the command delegates to a single skill
argument-hint: <see above>
---
```

## MANDATORY COMPLIANCE block

Every command that dispatches multi-LLM workflows MUST include a `MANDATORY COMPLIANCE — DO NOT SKIP` block that explicitly PROHIBITS:
- Substituting Claude-native tools for the multi-provider dispatch
- Skipping the provider check
- Single-Claude-subagent substitution for the full pipeline

See `/octo:review`, `/octo:critique`, `/octo:defensibility`, `/octo:argument-strength` for the canonical pattern.

## Autonomous-mode interaction

Commands that perform any of the 9 consensus-required action classes from `skill-autonomous-mode` (commit, push, ship, matrix-encode, approach-pick, issue-close, critique-act, release-grade, issue-body-claim) MUST either:
- Cite `bin/octo-consensus check` invocation in the command's execution steps, OR
- Explicitly note "autonomous-mode-exempt" with reasoning in the description

## Filing new commands

When adding `.claude/commands/<new>.md`:
1. Register in `.claude-plugin/plugin.json` `commands[]` array
2. Bump `version` in `.claude-plugin/plugin.json` (and use `scripts/bump-fork.sh patch` to sync the 7 manifests)
3. Add a FORK_PATCHES.md row if the command is fork-only
4. Add this CONVENTIONS file to your review when writing the command
