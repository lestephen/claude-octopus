# 🐙 claude-octopus (lestephen fork)

Friendly fork of [`nyldn/claude-octopus`](https://github.com/nyldn/claude-octopus) that ships bug fixes, knowledge-work skills, and an autonomous-mode consensus gate on top of the upstream multi-LLM orchestration plugin.

**Use this fork if you want:**
- The upstream functionality, plus the additions below
- An autonomous-mode protocol that requires cross-model consensus before consequential actions (closes the class of bug where a single LLM ships a wrong claim)
- A multi-LLM critique skill scoped beyond `/octo:review`'s code-defect focus
- Adversarial defensibility/argument-strength passes for documents going to external audiences (engineering consulting use case)
- A dogfood-style `--image` primitive that actually delivers pixels to vision-capable provider CLIs (codex, claude `--print`, gemini headless)

**Use upstream if:**
- You only need the original feature set and prefer to track `nyldn/claude-octopus` directly
- You don't want a fork's `lestephen.N` version suffix in your manifest

---

## 📥 Install

This fork is plugin-compatible drop-in with upstream — same `octo` plugin name, same `/octo:*` command namespace.

### Recommended — install via the fork's marketplace

The fork has a dedicated marketplace repo ([lestephen/claude-octopus-marketplace](https://github.com/lestephen/claude-octopus-marketplace)) that pins the install to a specific fork tag. Inside Claude Code:

```
/plugin marketplace add lestephen/claude-octopus-marketplace
/plugin install octo@lestephen-octo
```

Note the names — they're different on purpose:
- `lestephen/claude-octopus-marketplace` is the GitHub **repo** Claude Code clones to register the marketplace.
- `lestephen-octo` is the marketplace's self-declared `name` (from its `.claude-plugin/marketplace.json`). Claude Code references it by that name in `octo@lestephen-octo`.
- `octo` is the plugin name (matches upstream — drop-in compatible).

The marketplace pin updates automatically on every fork release via CI (see `.github/workflows/update-marketplace.yml`), so `octo@lestephen-octo` always tracks the latest `v9.38.0-lestephen.N` tag.

### Development install (this repo is the source, not a marketplace)

This repo itself is the plugin source, NOT a Claude Code marketplace. If you want to develop against a local checkout (and have your changes reflected immediately without re-publishing), clone outside the plugin path and symlink in:

```bash
# Clone the source outside the plugin path
mkdir -p ~/source
git clone https://github.com/lestephen/claude-octopus ~/source/claude-octopus

# Remove any pre-existing plugin dir (incl. empty one /octo:setup may have
# created), then symlink. `rmdir` is safe — it only deletes EMPTY dirs;
# if something non-empty is there, deal with it manually before continuing.
mkdir -p ~/.claude-octopus
rmdir ~/.claude-octopus/plugin 2>/dev/null || true
ln -sfn ~/source/claude-octopus ~/.claude-octopus/plugin
```

(The `rmdir` step matters: without it, `ln -s` into an existing directory creates a nested symlink at `~/.claude-octopus/plugin/claude-octopus → …` instead of replacing the dir. `ln -sfn` then forces overwrite if the target is a non-directory symlink. `git clone <repo> ~/.claude-octopus/plugin` directly fails because that path already exists for the same reason.)

After either install path, run `/octo:setup` (inherited from upstream) for the guided provider/auth wizard.

---

## ⚙️ What this fork adds over upstream

The full per-patch history is in [`FORK_PATCHES.md`](./FORK_PATCHES.md) (33 patches at time of writing). Highlights:

### Knowledge-work skills (engineering consulting / RCA reports)
- **`/octo:defensibility`** — hostile-review gate before a document goes external. Three coordinated passes (independent recompute, methodology audit, internal-terms scrub) produce a pass/fail with what must change before send.
- **`/octo:argument-strength`** — adversarial prose review. Three providers red-team your draft from different angles to find what would land if a hostile reader pushed back.
- **`/octo:critique`** — multi-LLM adversarial review of arbitrary scope (code, design docs, technology choices, approaches). Fills the gap between `/octo:review` (code defects), `/octo:argument-strength` (prose only), and `/octo:debate` (N alternatives).
- **Library skills** (`skill-lib-multi-review-doc`, `skill-lib-multi-inspect-figure`, `skill-lib-independent-recompute`) callable from other plugins.

### Autonomous mode + consensus gate
- **`/octo:autonomous`** + `skill-autonomous-mode` — codified self-paced session control with file-issue-on-blocker protocol.
- **Consensus before action** (lestephen.25) — in autonomous mode, 9 objective action classes (commit, push, ship, matrix-encode, approach-pick, issue-close, critique-act, release-grade, issue-body-claim) require multi-LLM consensus from ≥2 distinct provider CLIs before proceeding. Developed through 3 rounds of its own consensus check.

### Vision dispatch primitive
- **`--image <path>`** in `orchestrate.sh probe-single` and `lib-multi-dispatch.sh`. Delivers pixel data to codex `-i`, claude `--print`, and gemini headless (confirmed end-to-end Red/Green/Blue/Cyan/Orange/Purple/Yellow tests).
- **`/octo:visual-review <ref>`** — thin shortcut around `/octo:review` that injects a `reference` artifact (mockup PNG, screenshot, PDF spec) into the review profile so reviewers ground tokens against the source-of-truth.

### Provider control + safety fixes
- **`/octo:provider`** — persistent enable/disable for providers (user + project scope) with allowlist enforcement at dispatch time.
- **Cross-provider safety in model resolution** — fixes bug where bare `agent_type` (e.g. `codex`) could be routed to a wrong provider via `roles.researcher`.
- **`bump-fork.sh`** — atomic version bumps across all 7 manifest files (`package.json`, four `.*-plugin/plugin.json`, two `marketplace.json`).
- **Multi-LLM dispatch gate** — `lib-multi-dispatch.sh` enforces ≥2 reviewers passed strong validation (Status: SUCCESS + Output ≥ N chars; `--min-output-size` tunable for single-word vision answers) before allowing synthesis.

### Bug fixes (selected — full list in `FORK_PATCHES.md`)
- `orchestrate.sh debate` actually dispatches multi-LLM debate via `grapple_debate` (was erroring on a non-existent submodule path)
- Tangle subprocess tree killed on EXIT/SIGTERM/SIGINT (was leaking processes)
- Tangle checkpoint counter scans running streams + anchors markers (was racing)
- Provider dispatch guard enforced at the orchestrator boundary (was logging "blocked" but still dispatching)
- Profile-loading consolidated to single canonical path with fail-stop on malformed

---

## 📋 Fork conventions

**Branch:** `lestephen-patches`. Released as `v9.38.0-lestephen.N` tags.

**Versioning:** Upstream tag prefix (`9.38.0`) + `-lestephen.N` suffix. Bump with `scripts/bump-fork.sh patch`. On upstream merge, `bump-fork.sh merge-upstream X.Y.Z` resets to `X.Y.Z-lestephen.1`.

**Patch documentation:** Every commit on the fork branch gets a row in `FORK_PATCHES.md` with rationale, files touched, and an "Upstream-PR-ready" assessment. Patches marked **"Yes — clear bug"** are candidates to PR back to upstream; the rest are fork-scoped or pending discussion with the upstream maintainer.

**Issue tracker:** [github.com/lestephen/claude-octopus/issues](https://github.com/lestephen/claude-octopus/issues). Bugs in the fork-specific code go here; bugs in unchanged upstream code should go to [nyldn/claude-octopus/issues](https://github.com/nyldn/claude-octopus/issues).

---

## 📄 Upstream documentation

The full upstream README — feature catalog, command reference, provider setup, architecture diagrams, etc. — is preserved verbatim at [`UPSTREAM_README.md`](./UPSTREAM_README.md). Everything documented there applies to this fork unless `FORK_PATCHES.md` explicitly notes a divergence.

---

## ⚠️ Caveats

- **Manifest collision with upstream.** Both this fork and upstream use plugin name `octo`. Installing both via `/plugin install` will use whichever was installed last. Pick one.
- **`v9.38.0-lestephen.N` suffix in your manifest.** Tools that parse plugin versions will see this fork suffix. Most tools handle SemVer pre-release suffixes correctly; if yours doesn't, that's a tool bug.
- **Some skills carry proprietary-aware guardrails.** Defensibility / argument-strength / critique are designed for engineering-consulting contexts (RCA reports, supplier negotiations, etc.) and assume an internal-terms profile (`profile.yaml`) is loaded. They refuse to operate without one when checking documents headed external. See `skill-defensibility-pass` SKILL.md for setup.

---

## 🆘 Filing issues

- **Fork-specific bugs** (regressions in patches #18-#33, the new skills, the consensus gate, autonomous mode): [open here](https://github.com/lestephen/claude-octopus/issues/new).
- **Upstream bugs** (anything reproducible on `nyldn/claude-octopus` `main`): [open at upstream](https://github.com/nyldn/claude-octopus/issues/new).
- If unsure, file at upstream first — easier to escalate down than back up.

---

## 📄 License

Inherits upstream license (see `LICENSE` if present, otherwise refer to [nyldn/claude-octopus](https://github.com/nyldn/claude-octopus)).
