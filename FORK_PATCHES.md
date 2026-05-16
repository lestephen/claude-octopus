# Fork patches over upstream `nyldn/claude-octopus`

This fork carries 8 commits on top of `upstream/main` (currently at
upstream `v9.38.0`). Patches are maintained on the `lestephen-patches`
branch and released as `v9.38.0-lestephen.N` tags.

Each patch in this document is structured for **upstream PR
submission**: bug description, repro, root cause, fix, and a
ready-to-paste PR title and body. The `patches/` directory contains
the same commits as `git format-patch` mbox files so an upstream
maintainer can `git am patches/000N-*.patch` to apply individually.

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

**Highest-value upstream PR candidates: #5, #6, #8** — small, obviously
correct, no behavior change for end users. #2 and #4 are clear bug
fixes/enhancements but touch user-visible workflow paths so warrant
more discussion. #1 and #3 are feature additions and should be
discussed with the maintainer before opening a PR.

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

The `patches/` directory in this fork contains all 8 patches as mbox
files numbered in chronological order.

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
