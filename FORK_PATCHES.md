# Fork patches over upstream `nyldn/claude-octopus`

This fork carries 18 commits on top of `upstream/main` (currently at
upstream `v9.38.0`). Patches are maintained on the `lestephen-patches`
branch and released as `v9.38.0-lestephen.N` tags. Current tag:
`v9.38.0-lestephen.10`.

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
| 18 | _pending_ | chore | Fork versioning: encode `-lestephen.N` in manifests, add `bump-fork.sh`, doctor display | No — fork-only convention |

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

**Commit:** _pending_

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

The `patches/` directory in this fork contains all 18 patches as mbox
files numbered in chronological order (patch 18 — the versioning
commit — is regenerated by `bump-fork.sh patch` after the bump
commit lands).

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
