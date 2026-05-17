# Fork patches over upstream `nyldn/claude-octopus`

This fork carries 27 commits on top of `upstream/main` (currently at
upstream `v9.38.0`). Patches are maintained on the `lestephen-patches`
branch and released as `v9.38.0-lestephen.N` tags. Current tag:
`v9.38.0-lestephen.19`.

Each patch in this document is structured for **upstream PR
submission**: bug description, repro, root cause, fix, and a
ready-to-paste PR title and body. The `patches/` directory contains
the same commits as `git format-patch` mbox files so an upstream
maintainer can `git am patches/000N-*.patch` to apply individually.

## Fork version

Manifest version fields across `package.json`,
`.claude-plugin/{plugin,marketplace}.json`,
`.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json`, and
`.factory-plugin/{plugin,marketplace}.json` carry the full fork suffix
(e.g., `9.38.0-lestephen.10`) so installed copies report which patch
level they are on. Use `scripts/bump-fork.sh patch` to increment
across all manifests at once; see `scripts/bump-fork.sh --help`.

## Patch index

| # | SHA | Type | Subject | Upstream-PR-ready |
|---|-----|------|---------|-------------------|
| 1 | `6982bca` | feat | Codex `OCTOPUS_CODEX_APPROVAL` env var | Yes — opt-in feature |
| 2 | `fc95650` | fix  | Preserve user's PWD across orchestrate.sh | **Yes — clear bug** |
| 3 | `1c34462` | feat | `PROJECT_ROOT` fallback for plugin-dir cwd | Yes — belt-and-suspenders for #2 |
| 4 | `0944f9d` | feat | Gemini `--include-directories ${PROJECT_ROOT}` | Yes — conservative enhancement |
| 5 | `62d985e` | fix  | Prevent self-referential symlink in `/octo:doctor` | **Yes — small obvious fix** |
| 6 | `6d577b1` | fix  | Doctor: accept skill dirs, not just files | **Yes — small obvious fix** |
| 7 | `2e74c52` | chore | Rename patch series comment | No — fork-only naming |
| 8 | `be5596b` | fix  | Doctor: silent exit on `((counter++))` from 0 | **Yes — trivially correct** |
| 9 | `c301321` | docs | Add `FORK_PATCHES.md` and `patches/`  | No — fork-only documentation |
| 10 | `80cf27f` | fix | Doctor: replace bogus `claude agents` check with enabledPlugins + plugin validate | **Yes — clear bug with documented fix** |
| 11 | `eff1cd5` | docs | Update `FORK_PATCHES.md` for v9.38.0-lestephen.5 | No — fork-only documentation |
| 12 | `a59f241` | fix | Setup: `check_first_run` recognizes codex/gemini alternate auth | **Yes — clear bug, mirrors existing doctor logic** |
| 13 | `5ab8c3b` | chore | Remove dead `SUPPORTS_AGENTS_CLI` flag | Bundle with #10 — depends on it |
| 14 | `b623468` | docs | Update `FORK_PATCHES.md` and patches/ for v9.38.0-lestephen.6 | No — fork-only documentation |
| 15 | `3a8aa7f` | feat | Tangle: checkpoint-streaming subtasks (bound loss to last checkpoint, not full run) | Yes — substantial but self-contained |
| 16 | `7cf78b6` | fix  | Tangle: checkpoint counter scans running streams + anchors markers | Bundle with #15 — fixes counter from #15 |
| 17 | `0f34024` | fix  | Tangle: kill subprocess tree on EXIT/SIGTERM/SIGINT | **Yes — clear bug, independent of #15/#16** |
| 18 | `706203c` | chore | Fork versioning: encode `-lestephen.N` in manifests, add `bump-fork.sh`, doctor display | No — fork-only convention |
| 19 | `035d36f` | feat  | Knowledge-work Phase 1: skill-defensibility-pass, skill-argument-strength + 3 library skills (multi-review-doc, multi-inspect-figure, independent-recompute) | Plausible — universal multi-LLM skills; discuss adversarial-review framing with maintainer first |
| 20 | `30297db` | fix   | Library skills: correct probe-single call signature (prompt is `$2` not `$4`) and output file pattern (`<agent>-<task_id>.md`) | Bundle with #19 — fixes the same code path |
| 21 | `965b2d6` | feat  | Slash command shortcuts for new skills (`/defensibility`, `/argument-strength`); command count 48→50 across manifests | Bundle with #19 — surfaces the new skills as first-class commands |
| 22 | `4bc0a7f` | fix   | Cross-provider safety for bare-provider routing in `resolve_octopus_model` — fixes #1 (codex routed to perplexity via `roles.researcher`) | **Yes — clear bug, completes the v9.17.1 patch** |
| 23 | `51d2756` | feat  | Provider enable/disable: persistent denylist in `providers.json.disabled[]` (user + project scope) + `OCTO_DISABLED_PROVIDERS` env + `/octo:provider` subcommand + doctor surface | **Yes — additive UX improvement; existing OCTO_ALLOWED_PROVIDERS preserved** |
| 24 | `8975c3b` | docs  | Use `/octo:provider` as canonical (not bare `/provider`) in command markdown + README + FORK_PATCHES, matching `/octo:setup` and `/octo:doctor` convention | Bundle with #23 — doc-only |
| 25 | `79b3dd9` | fix   | `orchestrate.sh debate` actually dispatches multi-LLM debate via `grapple_debate` instead of erroring on a non-existent submodule — fixes the "AI Debate Hub not found" error backgrounded debate calls hit | **Yes — clear bug fix, removes dead submodule dep** |
| 26 | _pending_ | feat  | `skill-critique` + `/octo:critique` slash command — adversarial multi-LLM review of arbitrary scope (code, design docs, technology choices, approaches) | Plausible — fills the gap between `/octo:review` (code defects), `/octo:argument-strength` (prose), and `/octo:debate` (N options) |
| 27 | _pending_ | feat  | `/octo:review` scope flags (`--scope`, `--base`, `--wait`, `--background`) ported from `/codex:review`; size-sniffing + foreground/background recommendation | **Yes — direct port of well-tested codex pattern** |

**Highest-value upstream PR candidates: #5, #6, #8, #10, #12, #17** — small,
obviously correct, no behavior change for end users. #2 and #4 are
clear bug fixes/enhancements but touch user-visible workflow paths
so warrant more discussion. #1, #3, and #15 are feature additions and
should be discussed with the maintainer before opening a PR.

> Note on numbering: the # column matches the order in `patches/`
> (`git format-patch upstream/main..lestephen-patches`). Sections
> below mirror this. Throughout the release notes and release tags,
> patches are sometimes referenced by their semantic order (e.g.
> "Patch #9" in the v9.38.0-lestephen.5 release notes refers to the
> *code* patch shipped in that release — commit `80cf27f`, listed as
> row #10 here because of the intervening docs commit).

---

## Patch 1 — `feat(codex): OCTOPUS_CODEX_APPROVAL env var for headless approval policy`

**Commit:** `6982bca`
**Files:** `scripts/lib/dispatch.sh` (+21 / -4)

### Bug

Users with `approval_policy = "on-request"` set in `~/.codex/config.toml`
(the Codex CLI default for interactive use) hit indefinite hangs when
`orchestrate.sh tangle` / `develop` invoke `codex exec` headlessly —
Codex emits an approval prompt but there's nobody to answer in headless
mode, and `codex exec` waits forever.

### Repro

```bash
# In ~/.codex/config.toml
approval_policy = "on-request"

# Then any headless orchestrate run hangs:
bash scripts/orchestrate.sh tangle "..."  # never returns
```

### Fix

Inject `-c approval_policy=${OCTOPUS_CODEX_APPROVAL:-never}` into every
`codex exec` line emitted by `lib/dispatch.sh::get_command_line`. Default
`never` preserves headless safety. Users can override per-shell with
`OCTOPUS_CODEX_APPROVAL=on-request` when interactive approval is
desired without touching their global config.

Valid values: `never` (default), `on-request`, `on-failure`,
`unattended`. Invalid values fall back to `never` with an ERROR log.

### Suggested upstream PR title

> `feat(codex): inject approval_policy into headless codex exec to prevent hangs`

### Suggested upstream PR body

> When users have `approval_policy = "on-request"` in their global
> Codex config, headless `orchestrate.sh tangle` / `develop` invocations
> hang indefinitely waiting for an approval prompt that has nobody to
> answer.
>
> This PR adds a `OCTOPUS_CODEX_APPROVAL` env var (default `never`)
> that gets injected as `-c approval_policy=<value>` into every
> headless `codex exec` line. Default behaviour is unchanged for users
> who already have a headless-safe global config; it's a safety net
> for users with the more common interactive default.
>
> Tested by setting `approval_policy = "on-request"` globally and
> running a tangle workflow with and without the env var set.

---

## Patch 2 — `fix(commands): preserve user's PWD across orchestrate.sh invocations`

**Commit:** `fc95650`
**Files:** `.claude/commands/{embrace,discover,doctor}.md` — 14 invocations across 3 files

### Bug

The `embrace.md`, `discover.md`, and `doctor.md` command markdown files
instructed Claude Code to:

```bash
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh ...
```

This pinned the orchestrator's `PROJECT_ROOT` to the plugin install
dir, because `orchestrate.sh` captures `PROJECT_ROOT=${PWD}` at startup.

Downstream, `scripts/lib/spawn.sh` does `cd "$PROJECT_ROOT"` before
each agent invocation. Gemini CLI then auto-detected its workspace as
the plugin dir, refused writes to `/home/sle/source/<project>/...` as
`outside workspace`, and tangle phase aborted at the quality gate.

### Repro

1. Open a shell in any project (e.g. `cd ~/source/myproject`).
2. Trigger `/octo:embrace` in Claude Code. The command runs
   `cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh embrace ...`.
3. Develop phase spawns Gemini; Gemini refuses to write to the project
   with `path outside workspace`. Tangle phase fails the quality gate.

### Fix

Switch every invocation to an absolute path so the user's project
directory remains `$PWD` throughout:

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" ...
```

### Suggested upstream PR title

> `fix(commands): use absolute orchestrate.sh path to preserve caller PWD`

### Suggested upstream PR body

> The embrace/discover/doctor command markdowns currently `cd` into
> the plugin install dir before invoking `orchestrate.sh`. Because
> `orchestrate.sh` captures `PROJECT_ROOT=$PWD` at startup and
> `spawn.sh` later `cd`s into `$PROJECT_ROOT` before each agent runs,
> this pins the agents to the plugin dir instead of the user's project.
>
> The visible symptom is Gemini CLI refusing writes with "path outside
> workspace" during develop/tangle. (Codex doesn't have a workspace
> concept so it's unaffected.)
>
> This PR drops the `cd` and switches to an absolute path. 14
> invocations across 3 files.

---

## Patch 3 — `feat(orchestrate): PROJECT_ROOT fallback when cwd is a plugin install dir`

**Commit:** `1c34462`
**Files:** `scripts/orchestrate.sh` (+12 / -1)

### Bug

`orchestrate.sh` captured `PROJECT_ROOT=${PWD}` unconditionally. Any
caller that `cd`s into the plugin dir (whether the bundled `.claude`
command files, a user shortcut, or a future contribution) breaks
downstream agent spawning — see Patch 2 for the full failure mode.

### Fix

Defense in depth on top of Patch 2: even if a future caller forgets
and re-introduces the `cd`-pattern, `PROJECT_ROOT` now detects
plugin-cache paths (`/.claude/plugins/cache/`, `.claude-octopus/plugin`)
and falls back to `$OLDPWD`. Adds an explicit `OCTOPUS_PROJECT_DIR`
env var override for callers that want to be fully unambiguous.

### Suggested upstream PR title

> `feat(orchestrate): fall back to OLDPWD when PROJECT_ROOT lands in plugin dir`

### Suggested upstream PR body

> Belt-and-suspenders for the .claude command fix (Patch 2). Even if
> a caller forgets and re-introduces the `cd plugin_dir` pattern,
> `PROJECT_ROOT` detection now recognises plugin-install paths and
> falls back to `$OLDPWD`. Adds explicit `OCTOPUS_PROJECT_DIR`
> override for callers that want to be unambiguous.
>
> Safe to ship independently of #2.

---

## Patch 4 — `feat(gemini): pin workspace via --include-directories ${PROJECT_ROOT}`

**Commit:** `0944f9d`
**Files:** `scripts/lib/dispatch.sh` (+19 / -3)

### Bug

Gemini CLI in headless mode auto-detects its workspace from the
process cwd. If `PROJECT_ROOT` detection misfires (see Patch 2 / 3),
Gemini refuses writes to the actual project as "outside workspace."

### Fix

Append `--include-directories ${PROJECT_ROOT}` to the Gemini flag set
when headless mode is active (`--approval-mode yolo` present). This
guarantees Gemini sees the project as part of its workspace
regardless of cwd, and is a no-op for interactive mode where Gemini's
own workspace detection applies.

Together with Patches 2 and 3, this forms a three-layer defense
against the Gemini workspace-pinning bug class:
- Layer 1 (Patch 2): commands don't change cwd, so PROJECT_ROOT is right.
- Layer 2 (Patch 3): even if cwd is wrong, PROJECT_ROOT falls back.
- Layer 3 (this patch): even if PROJECT_ROOT is wrong, Gemini still sees the project.

### Suggested upstream PR title

> `feat(gemini): explicitly pin Gemini workspace to PROJECT_ROOT in headless mode`

### Suggested upstream PR body

> Third layer of defense for the Gemini "outside workspace" failure
> mode (see also PRs for fix-commands-pwd and fall-back-projectroot).
>
> Even if upstream cwd or PROJECT_ROOT detection fails for a
> yet-unknown caller shape, explicitly passing
> `--include-directories ${PROJECT_ROOT}` guarantees Gemini's headless
> workspace includes the actual project dir.
>
> Only injected when `--approval-mode yolo` is present (i.e. headless
> orchestration), so interactive Gemini sessions retain their default
> workspace detection.

---

## Patch 5 — `fix(commands): prevent self-referential symlink in /octo:doctor resolver`

**Commit:** `62d985e`
**Files:** `.claude/commands/doctor.md` (small)

### Bug

The `/octo:doctor` plugin-root resolver overwrote
`~/.claude-octopus/plugin` with a symlink pointing to itself when
`OCTO_PLUGIN_ROOT` was already that symlink path. The resulting loop
broke the link and caused `too many levels of symbolic links` on
subsequent runs.

### Repro

```bash
# Healthy initial state
$ readlink -f ~/.claude-octopus/plugin
/home/user/.claude/plugins/cache/.../9.38.0

# Run /octo:doctor (which executes the resolver)
$ /octo:doctor

# Subsequent run:
$ readlink -f ~/.claude-octopus/plugin
# too many levels of symbolic links
```

### Fix

Resolve canonical paths via `readlink -f` and skip `ln -sfn` if source
and destination already point to the same target:

```bash
OCTO_PLUGIN_REAL="$(readlink -f "$OCTO_PLUGIN_ROOT" 2>/dev/null || echo "$OCTO_PLUGIN_ROOT")"
OCTO_LINK_REAL="$(readlink -f "${HOME}/.claude-octopus/plugin" 2>/dev/null || echo "")"
if [[ "$OCTO_PLUGIN_REAL" != "$OCTO_LINK_REAL" ]]; then
  ln -sfn "$OCTO_PLUGIN_REAL" "${HOME}/.claude-octopus/plugin" 2>/dev/null || true
fi
```

### Suggested upstream PR title

> `fix(doctor): canonicalise paths before re-creating ~/.claude-octopus/plugin symlink`

### Suggested upstream PR body

> The plugin-root resolver embedded in `.claude/commands/doctor.md`
> unconditionally `ln -sfn`s `~/.claude-octopus/plugin` to whatever it
> resolved `OCTO_PLUGIN_ROOT` to. If that variable was already the
> symlink path itself, the result is a symlink pointing to itself,
> producing `too many levels of symbolic links` on the next invocation.
>
> This PR canonicalises both source and destination via `readlink -f`
> and skips the `ln` when they already match. Idempotent.

---

## Patch 6 — `fix(doctor): accept skill directories, not just regular files`

**Commit:** `6d577b1`
**Files:** `scripts/lib/doctor.sh` (small)

### Bug

`doctor_check_skills` tested skill paths with `[[ ! -f "$resolved" ]]`,
which is false for directories. Since skills in the current layout are
directories containing `SKILL.md` (not single `.md` files), every
declared skill produced a false-positive `Skill file missing` failure
— 51 of them on a healthy install.

### Repro

```bash
$ bash scripts/orchestrate.sh doctor skills
# Skill file missing: brainstorming
# Skill file missing: code-review
# ... 49 more
```

Yet:

```bash
$ ls .claude/skills/brainstorming/SKILL.md
.claude/skills/brainstorming/SKILL.md
```

### Fix

Accept either a directory or a regular file at the resolved path:

```bash
if [[ ! -d "$resolved" && ! -f "$resolved" ]]; then
    # ...flag as missing
fi
```

### Suggested upstream PR title

> `fix(doctor): accept skill directories in doctor_check_skills`

### Suggested upstream PR body

> `doctor_check_skills` only checks `-f`, but the current skill layout
> uses directories containing `SKILL.md`. This produces 51
> false-positive "Skill file missing" failures on a healthy install.
>
> Accept either `-d` (directory) or `-f` (regular file) at the resolved
> path.

---

## Patch 7 — `chore: rename patch series 'petrics' -> 'lestephen' in code comment`

**Commit:** `2e74c52`

**Not for upstream.** Fork-internal naming cleanup after re-tagging
the patch series from `v9.38.0-petrics.*` to `v9.38.0-lestephen.*`.

---

## Patch 8 — `fix(doctor): prevent silent exit when recent_failures starts at 0`

**Commit:** `be5596b`
**Files:** `scripts/lib/doctor.sh` (1 line)

### Bug

In `doctor_check_recurrence`, the line:

```bash
((recent_failures++))
```

returns exit status 1 on the **first** increment because Bash
post-increment returns the *pre*-increment value, and `((0))` is
arithmetically false (exit 1). Under `set -eo pipefail` (set at the
top of `orchestrate.sh`), this silently terminates `do_doctor` before
any diagnostic output is rendered.

The symmetric counter on line 259 already had `|| true`; line 1397 was
missed.

### Repro

```bash
# On any install with at least one quality-gate failure in last 48h:
$ bash scripts/orchestrate.sh doctor

# Output:
🐙 First time? Run the configuration wizard to get started:
   ./scripts/orchestrate.sh octopus-configure
SUCCESS: State file already exists and is valid
# (script exits here; no doctor output ever appears)
```

### Fix

```diff
-                    ((recent_failures++))
+                    ((recent_failures++)) || true
```

### Suggested upstream PR title

> `fix(doctor): guard ((counter++)) from set -e termination at line 1397`

### Suggested upstream PR body

> `doctor_check_recurrence` increments `recent_failures` with bare
> `((recent_failures++))`. Bash post-increment returns the
> *pre*-increment value, so the first increment (from 0) returns
> exit 1, which under `set -eo pipefail` silently aborts `do_doctor`
> before any output is rendered.
>
> The symmetric counter at `scripts/lib/doctor.sh:259` already has the
> `|| true` guard; this PR applies the same fix at line 1397.
>
> Reproducer: any install with `quality-gate` decisions logged in the
> last 48h hits this. After the patch, `/octo:doctor` produces its
> full 12-category report instead of exiting silently.

---

## Patch 9 — `docs: add FORK_PATCHES.md and patches/ for upstream PR submission`

**Commit:** `c301321`

**Not for upstream.** This document itself plus the `patches/` directory
were added in this commit to make individual patches easy to submit to
upstream. Fork-only by definition.

---

## Patch 10 — `fix(doctor): replace nonexistent 'claude agents list' check with enabledPlugins + plugin validate`

**Commit:** `80cf27f`
**Files:** `scripts/lib/doctor.sh` (+68 / -13)

### Bug

`doctor_check_agents` invokes `claude agents` and parses the output to
report "N agents registered." The check was based on a
`claude agents list` subcommand that has never existed in Claude Code.
The orchestrate.sh:300 comment confirms the original intent:

```bash
SUPPORTS_AGENTS_CLI=false              # v8.19: Claude Code v2.1.50+ (claude agents list command)
```

What `claude agents` actually does:
- **CC v2.1.139+:** opens the Agent View TUI for managing background
  sessions (`claude --bg` dispatch, peek, attach, etc.) — unrelated
  to plugin-declared subagents. Takes over the terminal, no parseable
  output. Per [the docs](https://code.claude.com/docs/en/agent-view).
- **Legacy / Bedrock / Vertex / Foundry:** prints a subagent count
  and exits. Per the same docs (troubleshooting section), this
  fallback indicates "agent view is unavailable in your environment"
  — i.e. an outdated CC or non-Anthropic-API install.

### Repro

```bash
# Inside any CC session, /octo:doctor:
[agents]
  ✓ 63 agent definitions found
  ✓ 10 agents with worktree isolation
  ⚠ Claude agents CLI returned no data  ← guaranteed false-positive
  ✓ Claude Code v2.1.143 — multi-agent stable
```

Shell-side on modern CC, the check is worse — it opens the TUI in a
subprocess and hangs until the parent times out.

### Fix

Replace with two stable checks that directly answer "will my agents
load at session start?":

**`agents-enabled`** — parse user's `~/.claude/settings.json` and
`settings.local.json` for `enabledPlugins["octo@*"]` entries with
`jq`:
- `pass` if any `octo@<marketplace>` is enabled
- `warn` if all `octo@*` entries are explicitly disabled
- `info` if no `octo@*` entries exist (manual/dev install)

**`agents-validate`** — gated on CC v2.1.77+ (when
`claude plugin validate` shipped). Runs the schema validator against
`$PLUGIN_DIR` and reports pass/warn based on exit code. Catches
broken agent YAML that CC would silently skip at session start.

### Suggested upstream PR title

> `fix(doctor): replace nonexistent 'claude agents list' check with enabledPlugins + plugin validate`

### Suggested upstream PR body

> `doctor_check_agents` invokes `claude agents` expecting a
> `claude agents list` subcommand. That subcommand has never existed.
> In modern Claude Code (v2.1.139+) `claude agents` opens the Agent
> View TUI for managing background sessions — unrelated to
> plugin-declared subagents, and produces no parseable output. On
> Bedrock/Vertex/Foundry it falls back to printing subagents and
> exiting (per the official docs, this fallback signals "agent view
> unavailable in your environment").
>
> Net effect: every `/octo:doctor` run inside a CC session produces a
> guaranteed false-positive warn ("Claude agents CLI returned no
> data"), and shell-side runs on modern CC hang the TUI in a
> subprocess.
>
> The pass-message text ("N agents registered") suggests the original
> intent was to verify Claude Code's runtime actually loaded the
> agents declared in `agents/config.yaml`. This PR keeps that intent
> with two stable, correct checks:
>
> 1. `agents-enabled` — parses user's `settings.json` `enabledPlugins`
>    map for `octo@*` entries and reports pass/warn/info based on
>    whether any are enabled.
> 2. `agents-validate` — gated on CC v2.1.77+, runs
>    `claude plugin validate "$PLUGIN_DIR"` and reports pass/warn
>    based on exit code. Catches broken agent YAML that CC would
>    silently skip.
>
> Sample healthy output:
>
> ```
> [agents]
>   ✓ 63 agent definitions found
>   ✓ 10 agents with worktree isolation
>   ✓ octo plugin enabled in CC: octo@lestephen-octo
>   ✓ claude plugin validate: no schema errors in agents/, commands/, hooks.json
>   ✓ Claude Code v2.1.143 — multi-agent stable
> ```

---

## Patch 11 — `docs: update FORK_PATCHES.md and patches/ for v9.38.0-lestephen.5`

**Commit:** `eff1cd5`

**Not for upstream.** Documentation refresh for the previous release.

---

## Patch 12 — `fix(setup): recognize codex auth.json and gemini OAuth in check_first_run`

**Commit:** `a59f241`
**Files:** `scripts/lib/config-display.sh` (+17 / -3)

### Bug

`check_first_run` in `scripts/lib/config-display.sh` gates the
"🐙 First time? Run the configuration wizard to get started:" hint on
the presence of `OPENAI_API_KEY` and `GEMINI_API_KEY` env vars
exclusively. The hint fires on every `orchestrate.sh` invocation for
users who authenticated via:

- **`codex login`** — stores credentials in `~/.codex/auth.json`, not
  `OPENAI_API_KEY`
- **Interactive Gemini OAuth** — stores credentials in
  `~/.gemini/oauth_creds.json`, not `GEMINI_API_KEY`

Both of these are common and well-supported auth methods that
`doctor_check_auth` at `lib/doctor.sh:347,360` already correctly
recognizes (it reports `✓ Codex authenticated via auth.json` and
`✓ Gemini authenticated`). Only `check_first_run` was env-var-only.

### Repro

```bash
# Set up Codex via the recommended interactive flow:
codex login   # stores ~/.codex/auth.json, doesn't set OPENAI_API_KEY

# Run any octo workflow:
bash scripts/orchestrate.sh doctor

# Output begins with:
🐙 First time? Run the configuration wizard to get started:
   ./scripts/orchestrate.sh octopus-configure
SUCCESS: State file already exists and is valid
[Claude Octopus Doctor]
...

# The "First time?" hint appears every single run, despite the user
# being correctly authenticated and doctor reporting healthy.
```

### Fix

Mirror `doctor_check_auth`'s detection: accept `~/.codex/auth.json` OR
`OPENAI_API_KEY` for Codex; accept any of `GEMINI_API_KEY` /
`GOOGLE_API_KEY` / `~/.gemini/oauth_creds.json` for Gemini.

```bash
local codex_authed=false
if [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -f "$HOME/.codex/auth.json" ]]; then
    codex_authed=true
fi
local gemini_authed=false
if [[ -n "${GEMINI_API_KEY:-}" ]] || \
   [[ -n "${GOOGLE_API_KEY:-}" ]] || \
   [[ -f "$HOME/.gemini/oauth_creds.json" ]]; then
    gemini_authed=true
fi
```

### Suggested upstream PR title

> `fix(setup): check_first_run should recognize codex auth.json and gemini OAuth`

### Suggested upstream PR body

> `check_first_run` in `scripts/lib/config-display.sh` only recognizes
> `OPENAI_API_KEY` and `GEMINI_API_KEY` env vars as valid auth, so the
> "🐙 First time?" hint persistently fires for users who authenticated
> via `codex login` (stores `~/.codex/auth.json`) or interactive
> Gemini OAuth (stores `~/.gemini/oauth_creds.json`) — the most common
> setup methods.
>
> `doctor_check_auth` at `lib/doctor.sh:347,360` already has the
> correct multi-method detection. This PR mirrors that logic in
> `check_first_run`, so the hint only fires when something is
> genuinely missing.

---

## Patch 13 — `chore: remove dead SUPPORTS_AGENTS_CLI flag`

**Commit:** `5ab8c3b`
**Files:** `scripts/orchestrate.sh` (-1), `scripts/lib/providers.sh` (-2 +1)

### Background

After Patch #10 replaced the bogus `claude agents` doctor check, the
`SUPPORTS_AGENTS_CLI` flag is unused. It was originally set in
`providers.sh` (for CC v2.1.50+), declared in `orchestrate.sh` with
the incorrect comment `# claude agents list command` (no such
subcommand has ever existed), and logged in providers.sh's
feature-summary line.

### Fix

Remove all three references. No behavior change.

### Upstream PR strategy

Bundle with Patch #10 when submitting upstream — depends on Patch #10
removing the consumer.

---

## Patch 14 — `docs: update FORK_PATCHES.md and patches/ for v9.38.0-lestephen.6`

**Commit:** `b623468`

**Not for upstream.** Documentation refresh for the previous release
(adds Patches #11–13 sections and regenerates `patches/`).

---

## Patch 15 — `feat(tangle): checkpoint-streaming subtasks to make timeout bound loss, not scope`

**Commit:** `3a8aa7f`
**Files:** `scripts/helpers/checkpoint-counter.sh` (+71 new), `scripts/lib/workflows.sh` (+302 / -20)

### Bug

Tangle subtasks ran for up to 600s total elapsed and then got
SIGKILL'd; the entire run was lost because providers (Codex
especially) tend to draft full implementations in their response
stream and `apply_patch` only at the very end. A timeout mid-generation
discarded everything.

Symptom seen in `v9.38.0-lestephen.6` PR-2 tangle: both Codex subtasks
ran 600s, generated substantial draft code in their response streams,
never reached `apply_patch`, got SIGKILL'd, quality gate aborted at
0%.

### Fix

Three coordinated changes that reframe the timeout from "budget for
the entire task" to "budget for not making progress":

1. **Checkpoint protocol header** prepended to each tangle subtask
   prompt. The model is required to work in micro-steps: one
   `apply_patch` per micro-step, followed by `### CHECKPOINT: <desc>`
   on its own line.
2. **Checkpoint-aware wait loop** in `tangle_develop`. A subtask is
   killed on (a) no first checkpoint within
   `OCTOPUS_TANGLE_FIRST_CHECKPOINT_TIMEOUT` (default 240s), (b) idle
   between checkpoints exceeding `OCTOPUS_TANGLE_IDLE_TIMEOUT` (default
   120s), or (c) hard ceiling `OCTOPUS_TANGLE_HARD_CEILING` (default
   1800s). Legacy `OCTOPUS_TANGLE_DEADLINE` honored as backward-compat
   hard ceiling.
3. **Resume-on-timeout** for subtasks killed with completed
   checkpoints. The orchestrator re-spawns the same provider with a
   `RESUME` header listing completed checkpoints; the model picks up
   from where it left off. Bounded by `OCTOPUS_TANGLE_MAX_RESUMES`
   (default 2) and `OCTOPUS_TANGLE_RESUME_CEILING` (default 900s).

Toggle off with `OCTOPUS_TANGLE_CHECKPOINTS=false` (falls back to
legacy total-elapsed behavior).

### Upstream PR strategy

Substantial but self-contained: new env-var contract, new helper,
extended wait loop, optional via toggle. Worth a discussion-first PR
with the maintainer rather than a drop-in patch.

---

## Patch 16 — `fix(tangle): checkpoint counter scans running streams + anchors markers`

**Commit:** `7cf78b6`
**Files:** `scripts/helpers/checkpoint-counter.sh` (+43 / -25), `scripts/lib/workflows.sh` (+6 / -5)

### Bug

Two bugs discovered live during `v9.38.0-lestephen.7` PR-2 tangle test,
both in `checkpoint-counter.sh` introduced by Patch #14:

1. **Wrong scan target.** The counter scanned only
   `$RESULTS_DIR/$agent-$task_id.md` which is the FINAL assembled
   output — it doesn't exist until spawn completion. During execution,
   provider output lives in `.tmp-$task_id.err` (stderr is Codex's
   main output channel).
2. **Prompt markers double-counted.** The protocol header that gets
   prepended to every subtask contains indented example markers like
   `    ### CHECKPOINT: added structlog dep`. `grep -F` matched anywhere
   on a line, so every prompt example registered as a 'completed'
   checkpoint immediately on spawn — wrongly switching the wait loop to
   the idle (120s) timeout instead of the first-checkpoint (240s)
   timeout, and later causing resume to inherit phantom completion
   state.

### Fix

- Counter signature changed from `<result_file> <state_file>` to
  `<results_dir> <task_id> <state_file>`. Scans all of
  `.tmp-$task_id.err`, `.tmp-$task_id.out`, `*-$task_id.md`,
  `.raw-$task_id.out` — sums across whatever exists. Idempotent and
  safe to call when no files yet exist.
- `grep -F` → `grep -E '^### CHECKPOINT:'`. Anchored to start of line
  so the prompt's indented examples (5–7 leading spaces) cannot match.
  Codex's narrative output emits markers at column 0, so real
  checkpoints still register correctly.
- `workflows.sh` updated to pass the new signature in both main and
  resume wait loops.

Validated against artifacts from the aborted `lestephen.7` PR-2 run:
the new counter correctly identified 24 real Codex-emitted checkpoints
across 4 subtasks, none of the prompt examples.

### Upstream PR strategy

Bundle with #15 — fixes the counter introduced there.

---

## Patch 17 — `fix(tangle): kill subprocess tree on EXIT/SIGTERM/SIGINT`

**Commit:** `0f34024`
**Files:** `scripts/lib/workflows.sh` (+70 / -4)

### Bug

When `TaskStop` or Ctrl-C interrupted `tangle_develop`, the
`orchestrate.sh` wrapper bash died but its spawned subtree (typically
4+ levels deep: `spawn_agent` bash → `timeout` → `env` → `node` →
codex rust binary) orphaned to init and kept running. The orphaned
codex processes continued modifying files in the project workspace
until their own internal timeout, racing any subsequent
`/octo:develop` invocation on the same prompt and corrupting
working-tree state.

Discovered live during `v9.38.0-lestephen.8` PR-2 validation: after
`TaskStop` returned 'Successfully stopped task', 6 codex/orchestrate
processes remained alive for ~45 minutes; one of them introduced a
UUID-format change in `tests/test_logging.py` that broke its own test
after the working tree had been verified clean.

### Fix

Three coordinated changes in `workflows.sh`:

1. **`_tangle_kill_tree` helper** — recursive descendant walker.
   `pkill -P` only kills direct children; this walks via `pgrep -P`
   to find grandchildren, great-grandchildren, etc. before
   `SIGKILL`'ing the parent.
2. **`_tangle_cleanup_all` trap handler** — iterates
   `_TANGLE_TRACKED_PIDS` and kills each subtree. Idempotent; safe to
   fire multiple times.
3. **trap registration in `tangle_develop`** — installs cleanup on
   `EXIT`, `SIGTERM`, `SIGINT` before the spawn loop; clears it after
   the wait loop and before `ink_deliver` runs (different cleanup
   needs). Tracks both initial spawn PIDs and resume PIDs.
4. **`_tangle_kill_subtask` updated** — uses the new tree-walker
   instead of just `pkill -P`, so per-subtask kills (idle timeout,
   hard ceiling) also reach grandchildren.

Validated with a multi-level subshell smoke test: SIGTERM to outer
shell fires the trap, `_tangle_cleanup_all` walks the bash → timeout
→ sleep chain, all three levels die before the parent process exits.

### Suggested upstream PR title

> `fix(tangle): kill subprocess tree on EXIT/SIGTERM/SIGINT to prevent orphaned codex processes`

### Suggested upstream PR body

> When `TaskStop` or Ctrl-C interrupts `tangle_develop`, the
> orchestrate.sh wrapper bash dies but its spawned subtree (spawn_agent
> bash → `timeout` → `env` → `node` → codex binary) orphans to init and
> keeps running. Orphaned codex processes then race subsequent develop
> invocations and corrupt working-tree state.
>
> This PR adds `_tangle_kill_tree` (recursive descendant walker via
> `pgrep -P`) and registers a cleanup trap on `EXIT/SIGTERM/SIGINT` in
> `tangle_develop` so the entire process tree dies with the parent.
> `_tangle_kill_subtask` is also updated to use the new walker so
> per-subtask kills (idle timeout, hard ceiling) reach grandchildren.

---

## Patch 18 — `chore(fork): encode lestephen suffix in manifest versions; add bump-fork.sh; doctor display`

**Commit:** `706203c`

**Not for upstream.** Fork-only versioning convention.

### Background

Before this patch, all seven manifest version fields (`package.json`,
`.claude-plugin/{plugin,marketplace}.json`,
`.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json`,
`.factory-plugin/{plugin,marketplace}.json`) carried the bare upstream
version (`9.38.0`) while git tags carried the fork suffix
(`v9.38.0-lestephen.N`). Installed copies on different machines all
reported `9.38.0` regardless of patch level, making it impossible to
tell which fork patches were actually deployed.

### Fix

- All seven manifest `version` fields now carry the fork suffix:
  `9.38.0-lestephen.10`.
- Stale `v9.38.0 — ...` and `v9.38.0 - ...` prefixes stripped from
  description fields; the `version` field is the single source of
  truth.
- `prepublishOnly` regex in `package.json` loosened to allow SemVer
  pre-release suffix:
  `^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?$`.
- New `scripts/bump-fork.sh` with two modes:
  - `bump-fork.sh patch` — increments `-lestephen.N → N+1` across all
    seven manifests.
  - `bump-fork.sh merge-upstream <X.Y.Z>` — resets to
    `<X.Y.Z>-lestephen.1` after pulling a new upstream release.
- `/octo:doctor` and `/octo:setup` surface `Fork version:
  9.38.0-lestephen.N (upstream: 9.38.0)` so installed copies declare
  their patch level at a glance.

### Versioning convention

| Trigger | New version |
|---------|-------------|
| New fork patch | `<upstream>-lestephen.<N+1>` |
| Merge upstream release | `<new-upstream>-lestephen.1` |

Tags follow `v<version>` (e.g., `v9.38.0-lestephen.10`).

---

## Patch 19 — `feat(km): defensibility-pass + argument-strength skills, with 3 library primitives for multi-LLM dispatch`

**Commit:** `035d36f`
**Files:** 5 new skill directories under `skills/`, plugin.json registrations, skill-count updates across adapter manifests

### Background

The plugin's existing knowledge-work (`/octo:km`) mode is a context-switch
flag that swaps in PRD / marketing / UX personas. That shape fits SaaS
PM work but does not fit engineering-consulting knowledge work, which
needs adversarial review primitives: independent verification of
quantitative claims, multi-perspective red-teaming of prose arguments,
and defensibility gating before external send. This patch ships the
public-facing portion of a larger plan to make `/octo:km` actually
useful for that kind of work.

This is the first material expansion of `/octo:km`. The private
counterpart (the `eki-kw` plugin distributed via private Azure DevOps
marketplace) will consume the library skills introduced here.

### What's added

Two end-user skills:

- **`skill-defensibility-pass`** — a publish-ready gate for documents
  going outside the org. Runs three passes via library skills:
  (A) independent recompute of every quantitative claim using
  `lib-independent-recompute`, (B) methodology audit via
  `lib-multi-review-doc` with codex + gemini reviewers, (C) internal-terms
  scrub + audience-tone lint via deterministic grep + `lib-multi-review-doc`
  with gemini + claude reviewers. Synthesizes a single pass/fail with
  what must change before send. Loads optional project profile YAML
  for banned-terms / internal-codenames / audience-tone rules; falls
  back to generic prompts when profile is absent.

- **`skill-argument-strength`** — adversarial prose review for drafts.
  Three providers red-team a draft from different angles (technical
  attack, structural attack, audience-reception attack). Synthesis
  surfaces high-confidence objections (raised by 2+ providers) and
  recommends minimum revisions. This is `/octo:debate` for prose:
  where `/octo:debate` resolves a decision among collaborators, this
  skill stress-tests a draft for survival when shared.

Three library skills meant to be invoked from other skills/plugins:

- **`skill-lib-multi-review-doc`** — generic primitive for fanning a
  document to N providers with per-reviewer prompts and synthesizing.
  Validation gate enforced. Consumer skills supply the reviewer
  prompts; this skill handles dispatch + synthesis.

- **`skill-lib-multi-inspect-figure`** — generic primitive for
  inspecting a rendered figure with multiple vision-capable providers.
  Skips non-vision providers. Writes inspection-log.jsonl for
  graduating recurring issue classes into deterministic lint.

- **`skill-lib-independent-recompute`** — generic primitive for
  recomputing a quantitative claim from source data using one or more
  providers. Returns a verdict: `CORROBORATED`, `CLAIM MATCHES SOME`,
  `CLAIM UNSUPPORTED`, or `PROVIDERS DISAGREE`. The last verdict is
  the most informative for defensibility work — it surfaces
  methodology ambiguity the document failed to anchor.

### Design choices worth noting

- All five skills follow the existing octopus conventions: codex-host
  adapter block, MANDATORY COMPLIANCE section, provider check via
  `skills/blocks/provider-check.md`, visual-indicator banner, validation
  gate that confirms synthesis files exist before claiming success.
- The library skills are intentionally lower-level than `/octo:review`
  or `flow-deliver`. They are meant to be composed by other skills
  (including third-party plugins). Their input contracts are explicit
  so consumers can call them without re-implementing the orchestration.
- `skill-defensibility-pass` and `skill-argument-strength` are
  fork-additions specifically because they showcase what claude-octopus
  is for: adversarial multi-provider review surfaces issues that any
  single model misses. Single-LLM utilities (intake-converter,
  report-discipline, publication-figures lint without vision-AI) are
  intentionally OUT of scope here and belong in a separate plugin.

### Upstream PR strategy

Plausible PR candidate, but discuss with maintainer first. The skills
are universal in their mechanics (no project-specific content) but the
adversarial-review framing is a notable expansion of the `/octo:km`
positioning. A maintainer may prefer a different namespace or
naming convention. The library skills (`lib-*`) are the more
straightforwardly upstream-mergeable subset; the end-user skills
(`defensibility-pass`, `argument-strength`) carry more opinion about
what knowledge-work should look like.

---

## Patch 20 — `fix(km-lib): correct probe-single call signature and output file pattern in library skills`

**Commit:** `30297db`
**Files:** `skills/skill-lib-multi-review-doc/SKILL.md`, `skills/skill-lib-multi-inspect-figure/SKILL.md`, `skills/skill-lib-independent-recompute/SKILL.md`

### Bug

The three library skills introduced in Patch #19 documented the
`orchestrate.sh probe-single` call signature incorrectly:

1. The reviewer prompt was passed as `$4` (`original_prompt`) — that
   slot is metadata only; the model never sees it. The actual prompt
   the model receives is `$2` (the "perspective" slot, named
   historically — it's the prompt body that goes through
   `apply_persona`).
2. The validation gates searched for files matching
   `probe-synthesis-${label}-*.md` or `${label}-*.md`. The actual file
   pattern written by `probe_single_agent` at
   `scripts/lib/workflows.sh:128` is `<agent_type>-<task_id>.md`.
   Validation gates would have reported `VALIDATION FAILED` for every
   successful dispatch.

### Discovery

Surfaced live during a 2-provider smoke test against the Patch #19
library skills. Codex was dispatched with the perspective slot set to
literally "test-perspective"; the file written was
`codex-smoke-codex-1779003440.md` (matching the actual pattern) and
the model received "test-perspective" as its prompt (matching the
actual perspective-as-prompt semantics).

### Fix

In all three library skill prose files:

- Restructured the dispatch code-block to pass the reviewer prompt in
  the perspective slot (`$2`), with a note explaining the historical
  naming.
- Restructured the validation-gate code-block to compute
  `${OUTPUT_DIR}/${agent_type}-${task_id}.md` from the dispatch-time
  state instead of globbing on a wrong pattern.
- Added inline comments referencing `scripts/lib/workflows.sh:128` so
  the next maintainer doesn't repeat the misreading.

### Upstream PR strategy

Bundle with Patch #19 — same code path. If Patches #19/20 are pursued
as an upstream PR, squash these two into a single feature commit.

---

## Patch 21 — `feat(km): slash-command shortcuts for defensibility and argument-strength`

**Commit:** `965b2d6`
**Files:** `.claude/commands/defensibility.md` (new), `.claude/commands/argument-strength.md` (new), `.claude-plugin/plugin.json` (commands list), 6 manifest files (command count 48→50)

### Background

Patch #19 introduced two end-user skills — `skill-defensibility-pass`
and `skill-argument-strength` — and registered them in `plugin.json`.
However, end users invoke octopus skills primarily through slash
commands (`/defensibility`, `/argument-strength`, `/debate`, etc.),
which require a separate `.claude/commands/<name>.md` shortcut file
per existing convention (see `debate.md`, `review.md`, `security.md`).
Patch #19 missed creating these shortcuts, leaving the new skills
discoverable only via `/octo:skill-defensibility-pass` and
`/octo:skill-argument-strength` — discoverable but un-ergonomic.

### Fix

- New `.claude/commands/defensibility.md` with MANDATORY COMPLIANCE
  + EXECUTION MECHANISM blocks mirroring `debate.md` style. Routes to
  `skill-defensibility-pass`.
- New `.claude/commands/argument-strength.md` with the same pattern.
- Updated `commands[]` array in `.claude-plugin/plugin.json`.
- Bumped command count `48 → 50` across all 6 user-facing strings
  (`marketplace.json` description, `codex-plugin/plugin.json`
  longDescription, `factory-plugin/{plugin,marketplace}.json`
  descriptions, `README.md`, `.claude-plugin/README.md`).

### Upstream PR strategy

Bundle with #19 — these are the user-facing wrappers for the skills
that patch introduced.

---

## Patch 22 — `fix(routing): cross-provider safety for bare-provider routing in resolve_octopus_model`

**Commit:** `4bc0a7f`
**Files:** `scripts/lib/model-resolver.sh` (+18 / -2)

### Bug

`resolve_octopus_model` in `scripts/lib/model-resolver.sh` has two
branches for the Tier 3 (phase/role routing) result:

- **Colon form** (`"codex:spark"`): cross-provider safety check at
  line 130 — added in v9.17.1 (#235 item 3) — skips the route when
  the prefixed provider differs from the current resolution target.
- **Bare form** (`"perplexity"`): no safety check; the bare value
  was assigned directly to `resolved_model`.

When `providers.json` contains `"routing.roles.researcher": "perplexity"`
(a bare provider name) and the caller resolves for a different
provider (e.g. `agent_type=codex` with the default `role=researcher`),
the bare branch assigned `resolved_model="perplexity"`. Codex CLI was
then invoked with `--model perplexity`, which it cannot use, and
produced empty output. The result file's `## Status` was `FAILED`
but the file existed — so library-skill validation gates that checked
only for file existence + non-empty saw a header'd file and reported
success while the dispatch had silently failed.

### Discovery

Surfaced during dogfood of `/octo:argument-strength` at v9.38.0-lestephen.13
(GitHub issue #1). Codex reviewer produced 0 useful content;
investigation traced the routing chain through `probe_single_agent`
→ `get_agent_model` → `resolve_octopus_model` → Tier 3 bare-branch.

### Fix

Mirror the v9.17.1 cross-provider safety into the bare branch. When
the bare routed value matches a known provider name:

- Different provider than the resolution target → skip the route
  (fall through to Tier 4 capability map / Tier 6 default).
- Same provider as the resolution target → also skip (so we don't
  assign the provider name as a literal model name) and fall through
  to capability/default resolution. This also fixes a latent issue
  where `provider=perplexity, role=researcher` would have resolved to
  `model=perplexity` instead of `model=sonar-pro`.

When the bare routed value does NOT match a known provider name,
treat it as a literal model name (preserves existing behavior for
configurations that legitimately use bare model identifiers).

Verified with three trace runs:

- `provider=codex, role=researcher` → resolves to `gpt-5.5` (was: `perplexity`)
- `provider=perplexity, role=researcher` → resolves to `sonar-pro` (was: `perplexity`)
- `provider=gemini, role=verifier` (colon-form route to `codex:spark`) → unchanged, resolves to `gemini-3.1-pro-preview` per v9.17.1 behavior

### Suggested upstream PR title

> `fix(model-resolver): cross-provider safety for bare-provider routing (completes v9.17.1)`

### Suggested upstream PR body

> v9.17.1 added cross-provider safety to the colon-form routing in
> `resolve_octopus_model` (skips the route when `provider:capability`
> targets a different provider than the resolution target). The
> bare-provider form (`"perplexity"` instead of `"perplexity:default"`)
> was missed and had no safety check.
>
> When `providers.json` has `routing.roles.researcher: "perplexity"`,
> any role-routed call resolving for a different provider (codex,
> gemini, etc.) would silently get `model=perplexity` assigned — a
> string the target provider's CLI cannot use. This produced empty
> output with `Status: FAILED`, but downstream validation gates
> checking only for file existence would not catch it.
>
> This PR adds the same cross-provider skip to the bare-form branch,
> plus a same-provider fall-through (so `provider=perplexity,
> role=researcher` resolves to `sonar-pro` via the default rather
> than the literal string `"perplexity"`).
>
> Closes the routing-side of any library-skill multi-provider dispatch
> that relies on `probe_single_agent`.

---

## Patch 23 — `feat(provider): persistent enable/disable for providers with project + user scope, env override, doctor surface, /octo:provider command`

**Commit:** `51d2756`
**Files:** `scripts/lib/provider-allowlist.sh` (+89 / -1), `scripts/lib/provider-config.sh` (new +148), `scripts/orchestrate.sh` (+72, new `provider` subcommand), `scripts/lib/doctor.sh` (+18), `.claude/commands/provider.md` (new), `.claude-plugin/plugin.json` (+1), `README.md` (+25), 5 user-facing manifest strings (50→51 commands)

### Background

The fork previously had a single provider-filter mechanism — the
session-scoped `OCTO_ALLOWED_PROVIDERS` env var (allowlist). To disable
one provider (e.g., "I've tried Copilot and don't find it useful, never
dispatch to it"), users had to list every OTHER provider explicitly in
the env var, which is awkward and breaks when new providers are added
upstream. The mechanism was also undocumented and not surfaced in
`/octo:doctor`.

### Fix

Three composable provider-control mechanisms (A+B+C), all merged into
a single effective deny check. Precedence: env > project > user.

**A. Persistent denylist in `providers.json`:**

```json
{
  "version": "3.0",
  "disabled": ["copilot"]
}
```

Two scopes:
- User: `~/.claude-octopus/config/providers.json` (default)
- Project: `./.octopus/providers.json` (write with `--project` flag; commits with the repo)

**B. New `OCTO_DISABLED_PROVIDERS` env var:** space/comma-separated denylist for session-scoped exclusions (e.g., "Gemini is having an outage, skip it for this session").

**C. Surfacing + UX:**
- New `/octo:provider` slash command with `list`, `disable`, `enable`, `status`, `--help` subcommands.
- `/octo:doctor --verbose` now shows one line per disabled provider with source ("env (OCTO_DISABLED_PROVIDERS)", "project (./.octopus/providers.json)", "user (...)").
- README section explaining all three mechanisms and precedence.

### Behavior

A provider is OK to use iff:
- Not in any denylist source (env / project / user)
- AND if `OCTO_ALLOWED_PROVIDERS` is set, in the allowlist

Backward compatibility: `OCTO_ALLOWED_PROVIDERS` semantics unchanged — if set, it remains the source of truth for what's allowed. The new denylist is additive: a provider in BOTH the allowlist AND the denylist is denied (denylist trumps).

### Implementation notes

- `octo_provider_disabled <name>` returns 0 if disabled by any source.
- `octo_disabled_set` echoes the merged set (deduplicated, normalized).
- `octo_provider_disabled_source <name>` returns the human-readable source(s) for `/octo:doctor` transparency.
- `octo_provider_allowed` now calls `octo_provider_disabled` first and returns 1 (not allowed) if so.
- Config mutations are JSON-aware (jq required) and idempotent.
- File scope flag uses standard `--project` / `--user` (default `--user`).

### Upstream PR strategy

Plausible upstream PR — the feature is additive, doesn't change defaults, and `OCTO_ALLOWED_PROVIDERS` semantics are preserved. The `.disabled[]` field in `providers.json` is a new key that doesn't conflict with existing keys. Worth a discussion-first PR with the maintainer to align on:

- Whether `disabled[]` should be `providers_disabled[]` or namespaced differently.
- Whether `/octo:provider` is the right namespace (matches `/octo:setup`, `/octo:doctor` etc. for plugin-management commands).
- Whether to migrate `OCTO_ALLOWED_PROVIDERS` to a config-file representation alongside the env var.

---

## Patch 24 — `docs: use /octo:provider as canonical, matching /octo:setup and /octo:doctor convention`

**Commit:** `8975c3b`

**Not for upstream.** Doc-only fix bundled with patch #23.

Patch #23 introduced the new `provider` slash command but the docs in
`.claude/commands/provider.md`, `README.md`, and `FORK_PATCHES.md`
referred to it as bare `/provider`. The existing plugin-management
slash commands (`/octo:setup`, `/octo:doctor`, etc.) consistently use
the `/octo:` namespace prefix in their docs even though Claude Code
auto-registers commands in both bare and namespaced forms. This patch
updates all 20 doc references to use `/octo:provider` for consistency
with that convention.

No code change; bare `/provider` continues to work because Claude
Code's plugin namespacing registers both forms automatically.

---

## Patch 25 — `fix(debate): bash subcommand actually dispatches via grapple_debate; removes dead submodule check`

**Commit:** `79b3dd9`
**Files:** `scripts/orchestrate.sh` (~70 lines, +/-)

### Bug

`bash orchestrate.sh debate "..."` errored with:

```
ERROR: AI Debate Hub not found. Please initialize the submodule:
  git submodule update --init --recursive
AI Debate Hub by wolverin0: https://github.com/wolverin0/claude-skills
```

despite the fork containing no submodule (`.gitmodules` does not exist; `.dependencies/claude-skills/` does not exist). The submodule was the v7.4 integration with `wolverin0/claude-skills` that has since been superseded by the in-tree `skill-debate/SKILL.md` skill (for the slash command path) and `lib/debate.sh::grapple_debate` (for the bash subcommand path).

The `debate|deliberate|consensus)` case branch in `orchestrate.sh` was never updated when the submodule went away — it kept the submodule guard, kept the `log INFO "🗣️ AI Debate Hub (by wolverin0)"` informational text, and never actually called any debate dispatcher. The branch was effectively dead.

### Discovery

Surfaced in a real `cfd-report-automation` session (2026-05-17): Claude was running a discover/grasp workflow, decided to background-dispatch an adversarial debate against a consensus B+D hybrid, and called `bash orchestrate.sh -t 600 debate "Adversarial stress-test of..."`. The submodule check fired and the debate never ran.

### Fix

Replace the `debate|deliberate|consensus)` case branch with a real dispatcher mirroring the existing `grapple)` branch:

- `source "${SCRIPT_DIR}/lib/debate.sh"` to bring in `grapple_debate`
- `--help` prints a real usage block
- No-args errors helpfully and points at `--help`
- Parse `-r|--rounds`, `--principles`, `--mode` (same surface as `grapple`)
- `grapple_debate "$@" "$principles" "$rounds" "$debate_mode"` does the actual dispatch

`debate`, `deliberate`, and `consensus` are now functional aliases of `grapple`. The submodule check is gone. Backgrounded debate dispatch from agentic flows works.

### Verification

```
$ bash scripts/orchestrate.sh debate --help
# Prints real usage block — no submodule warning

$ bash scripts/orchestrate.sh debate
ERROR: Missing prompt for debate
Usage: orchestrate.sh debate [OPTIONS] <prompt>
Run 'orchestrate.sh debate --help' for full options

$ bash scripts/orchestrate.sh debate "test" 2>&1 | grep -c submodule
0
```

The `/octo:debate` slash command path was already working (routes to skill-debate, not the bash subcommand) and is unchanged by this patch.

### Suggested upstream PR title

> `fix(debate): bash subcommand actually dispatches via grapple_debate; removes dead submodule check`

### Suggested upstream PR body

> The `debate`/`deliberate`/`consensus` subcommand in `orchestrate.sh` checked for a non-existent submodule at `.dependencies/claude-skills/` (a v7.4 wolverin0/claude-skills integration that's no longer part of the install) and emitted informational text only — the actual debate ran only via the `/octo:debate` slash command in the foreground.
>
> That left `bash orchestrate.sh debate "..."` as a dead path for any agentic workflow that wanted to background a debate. This is a real use case: discover/grasp flows backgrounding adversarial stress-tests of consensus.
>
> This PR makes `debate`/`deliberate`/`consensus` a functional alias of `grapple` (which has been the working in-tree multi-LLM debate dispatcher all along), with the same flag surface. The submodule check is removed. The `/octo:debate` slash command path is unchanged.

---

## Patch 26 — `feat(critique): skill-critique + /octo:critique slash command for adversarial multi-LLM review of arbitrary scope`

**Commit:** _pending_
**Files:** `skills/skill-critique/SKILL.md` (new), `skills/skill-critique/agents/openai.yaml` (new), `.claude/commands/critique.md` (new), `.claude-plugin/plugin.json` (registrations), 6 manifest strings (51→52 commands, 58→59 skills)

### Background

The existing review skills cover specific cases but leave a gap:

- `/octo:review` — code defect / security / perf focused
- `/octo:argument-strength` — prose-only argument structure
- `/octo:debate` — picks between N pre-specified options
- `/octo:defensibility-pass` — external-send hostile-review gate (3 coordinated passes)

Open-ended "I made this choice / built this thing — would a hostile expert tear it apart?" had no home. Users hit it with technology choices, architecture proposals, ADRs, RFCs, and general approaches.

### What's added

`skill-critique` — adversarial multi-LLM review of arbitrary user-specified scope. Uses `skill-lib-multi-review-doc` as the dispatcher; picks adversarial angles per scope type:

| Scope type | Default angles |
|---|---|
| `code-change` | Technical correctness, architectural fit, maintainability |
| `design-doc` | Conceptual coherence, alternatives-rejected, operational failure modes |
| `technology-choice` | Cost (financial + cognitive + operational), fit + exit cost, alternatives |
| `approach` | Assumption-challenge, what-if-X-changes, simplest-alternative |
| `architecture` | Coupling/cohesion, failure modes / blast radius, 2-year evolution path |
| `decision` | Reversibility / sunk cost, evidence quality, stakeholder impact / dissent |
| `prose` | Refuse and route to `/octo:argument-strength` (specialized) |

Each provider attacks from one angle; synthesis surfaces objections by severity × confidence (objections raised by 2+ providers carry higher weight than single-provider HIGHs). Output verdicts: `STRONG` / `DEFENSIBLE WITH FIXES` / `LOAD-BEARING WEAKNESSES` / `NEEDS REDESIGN`.

`/octo:critique` slash command shortcut routes to the skill with the standard MANDATORY COMPLIANCE / EXECUTION MECHANISM framing.

### Upstream PR strategy

Plausible. The skill mechanics are universal; the angle table is the only opinionated content. Worth a discussion-first PR — the maintainer may prefer different default angles or a different positioning relative to `/octo:debate` and `/octo:review`.

---

## Patch 27 — `feat(review): port /codex:review scope flags (--scope, --base, --wait, --background) with size sniffing`

**Commit:** _pending_
**Files:** `.claude/commands/review.md` (+~70 lines of flag parsing + size estimation prose)

### Background

`/octo:review` previously required full interactive Q&A through AskUserQuestion to determine target scope. `/codex:review` solved the same problem with flag-driven scope (`--scope auto|working-tree|branch`, `--base <ref>`, `--wait|--background`) and auto-recommends background execution for large reviews based on size estimation (`git status / git diff --shortstat`).

When a caller (human or agentic flow) already knows what they want to review, the Q&A is friction. When the caller doesn't know, the size estimate + recommendation is more useful than a flat Q&A.

### What's added

Ported the codex pattern to `/octo:review`:

- **Step 0**: parse flags from `$ARGUMENTS` — `--scope`, `--base`, `--wait`, `--background`. Remaining words become focus-area hints.
- **Step 0.5**: size estimation per scope (`git status --short`, `git diff --shortstat` variants, `gh pr diff --name-only` for PR scope). Then `AskUserQuestion` once with foreground/background recommendation. Skipped if `--wait` or `--background` was supplied.
- **Step 1**: skip the "What should be reviewed?" question when `--scope` was set. Other questions (focus, provenance, publish) unchanged.
- **Step 3**: honor `EXEC_MODE` — `run_in_background: true` when background was chosen.

The remaining Q&A surface (focus, provenance, publish) is octopus-specific and richer than codex; it's preserved.

### What this does NOT change

- `skill-code-review` (the underlying skill) is unchanged. The scope is passed through as the existing `target` field in the JSON profile.
- Existing `/octo:review` invocations without flags continue to work as before — full Q&A.
- Headless/autonomous mode (`AUTONOMY_MODE=autonomous` or pipeline context) still skips all Q&A and auto-infers, as before.

### Upstream PR strategy

Strong upstream PR candidate. The pattern is borrowed directly from codex's well-tested slash command; it's additive (default behavior unchanged when no flags supplied); the scope flags improve agentic-flow ergonomics (background dispatch is critical for long reviews backgrounded by `/octo:embrace` etc.).

---

## Applying these patches

To apply the entire series to a fresh `upstream/main` checkout:

```bash
git remote add lestephen https://github.com/lestephen/claude-octopus.git
git fetch lestephen
git checkout -b lestephen-patches lestephen/lestephen-patches
```

Or apply individual patches via `git am`:

```bash
# From a clone of nyldn/claude-octopus on main:
git am path/to/lestephen/claude-octopus/patches/0005-fix-commands-prevent-self-referential-symlink-in-oct.patch
```

The `patches/` directory in this fork contains all 27 patches as mbox
files numbered in chronological order. The convention is that each
new patch is regenerated alongside the *next* fork-docs commit (so
the patches/ directory always lags HEAD by one commit at most). After
making a new patch commit, run:

```bash
rm -f patches/*.patch
git format-patch --no-stat upstream/main..HEAD -o patches/
```

Then commit the regenerated `patches/` directory on the next docs
refresh.

## Updating this document

When a new patch is added to `lestephen-patches`:

1. Add a row to the patch index table above.
2. Add a numbered section with bug / repro / fix / suggested PR text.
3. Regenerate `patches/`:
   ```bash
   rm -f patches/*.patch
   git format-patch --no-stat upstream/main..lestephen-patches -o patches/
   ```
4. Commit `FORK_PATCHES.md` and `patches/` together.
