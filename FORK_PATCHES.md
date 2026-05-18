# Fork patches over upstream `nyldn/claude-octopus`

This fork carries 55 commits on top of `upstream/main` (currently at
upstream `v9.38.0`). Patches are maintained on the `lestephen-patches`
branch and released as `v9.38.0-lestephen.N` tags. Current tag:
`v9.38.0-lestephen.47`.

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
| 26 | `2befccf` | feat  | `skill-critique` + `/octo:critique` slash command — adversarial multi-LLM review of arbitrary scope (code, design docs, technology choices, approaches) | Plausible — fills the gap between `/octo:review` (code defects), `/octo:argument-strength` (prose), and `/octo:debate` (N options) |
| 27 | `229646a` | feat  | `/octo:review` scope flags (`--scope`, `--base`, `--wait`, `--background`) ported from `/codex:review`; size-sniffing + foreground/background recommendation | **Yes — direct port of well-tested codex pattern** |
| 28 | `ca0d2bc` | fix   | PR 1 ship-blockers from dogfood audit: F1 dispatch-guard (provider disable now enforced), F2/F3 debate prompt corruption + mode validation, F6/F7/F10/F11 bump-fork + provider-config atomicity / flock / name validation, G2 critique bundle → temp file, G3 defensibility-pass hardening | **Yes — bundle of clear bug fixes** |
| 29 | `5c18769` | refactor | PR 2 architectural: C5 real-bash `lib-multi-dispatch.sh` helper + interface_version on lib-* skills; C1 consolidate profile loading into `lib/load-octo-profile.sh`; misc audit fixes (F5 jq hyphen keys, F8 status allowlist message, F9 doctor source-aware remediation, F13 recompute compute_status field, C3 status exit codes, C7 multi-arg disable, C8 critique verdict.json) | Plausible — architectural improvement worth maintainer discussion |
| 30 | `86a3a9a` | feat+fix | PR 3 deferred + autonomous-mode: new `skill-autonomous-mode` + `/octo:autonomous` for self-paced session control with file-issue-on-blocker protocol; F4 model-resolver bare agent_type recursion; C6 `--resume` in lib-multi-dispatch; docs/UX (G4 canonical profile path, G5 cross-skill routing table, G6 argument-hint frontmatter); +10 fixes from self-critique dogfood (autonomous mode precedence vs other skills' halts, destructive-action exemption expansion, malformed-profile no-fallthrough, etc.). 3 deferred items filed as GH #8/#9/#10. F12 image attachment filed as #7. | Plausible — substantive new skill + several fixes |
| 31 | `474afbc` | feat  | Spike: F12 + #11 unified — `--image <path>` primitive in `orchestrate.sh probe-single` + `lib-multi-dispatch.sh` (codex `-i` confirmed end-to-end, others degrade gracefully with explicit result-header warning); `skill-lib-multi-inspect-figure` bumped to interface_version 2 to use the new attachment path (closes GH #7); review profile gains optional `reference` field with mockup-context preamble auto-injected into all reviewer prompts when set + new `/octo:visual-review <ref>` shortcut (closes GH #11 cheapest leg — full Playwright/deltaE visual-diff specialist deferred to follow-up); plus dogfood-discovered `--min-output-size` flag for one-word vision answers | **Yes — additive plumbing + closes 2 GH issues** |
| 32 | `25bf7c4` | fix   | Correct lestephen.23 vision matrix after user pushback — retest revealed claude `--print` and gemini headless both see images via path-reference in prompt body (path-mentioned absolute or `@file`). Drop the "you cannot see pixels" prompt prepend (which was actively misleading Sonnet/Gemini); replace with a universal "Attached images" block appended to the prompt body for ALL providers. codex `-i` splice stays as belt-and-suspenders. Updates the matrix in `skill-lib-multi-inspect-figure`, `/octo:visual-review` banner, and `review.sh` mockup-preamble. Commit message includes a candid process retrospective on how a single failed gemini test entrenched the wrong claim through .23. | **Yes — clear correction of wrong claim shipped one patch earlier** |
| 33 | `2eae104` | feat  | Autonomous-mode consensus-before-action gate (closes GH #15) — 9 objective action classes (commit/push/ship/matrix-encode/approach-pick/issue-close/critique-act/release-grade/issue-body-claim) require consensus from ≥2 distinct provider CLIs (no SEV-1 from any, no majority SEV-2; adjudication path for splits). Developed THROUGH 3 rounds of its own multi-LLM consensus check — iterations 1 and 2 caught real contradictions (docs-exemption-vs-matrix-trigger contradicting itself; quoting-as-enforcement vs auditability), v3 passed NO BLOCKING from both providers. Honest acknowledgement that prose-rule alone is honor-system; machine-enforcement layer tracked as GH #16. Residual SEV-2s in GH #17. | **Yes — meta-improvement; the v.23 wrong-matrix would not have shipped under this rule** |
| 34 | `4629815` | docs+chore | Fork identity / labeling — replace upstream README with fork-first `README.md` (move upstream verbatim to `UPSTREAM_README.md`); `author` switches `nyldn → lestephen` with `contributors: [nyldn (upstream)]` added across all 7 manifests; `repository` + `homepage` switch from `nyldn/claude-octopus` to `lestephen/claude-octopus`; per-host `description` fields rewritten to start with "Fork of nyldn/claude-octopus —" and name the differentiators; GitHub repo description updated + stale `r/ClaudeOctopus` homepage removed via gh CLI. Resolves the routing-bugs-to-upstream class of issue (tools reading installed plugin metadata were filing fork-specific bugs at upstream). Plugin name unchanged (still `octo`) — drop-in plugin-compatible with upstream. | No — fork-only identity changes |
| 35 | `5a1883e` | feat  | Machine-enforced consensus gate (closes GH #16). `bin/octo-consensus check <dispatch.json>` parses lib-multi-dispatch output mechanically, applies the consensus-definition table from skill-autonomous-mode v.25 as code, exits 0 (ALLOW) or 1-6 (BLOCK with specific code: HARD/SOFT BLOCK, SPLIT, NO QUORUM/DIVERSITY, PARSE ERROR). Until now the gate was honor-system; with this it has teeth. Dogfooded via 6 rounds of its own protocol — each round caught real findings (SEV-3+ dropped as unparseable; ANSI strip incomplete; diversity-bypass-via-unparseable; awk word-boundary is backspace; OSC ANSI leak; empty-section fallback contamination). 5 in-tree unit tests + 15 fixture-suite manual tests pass. Bundles a rule tightening: skill-autonomous-mode adds a 3-substantive-rounds cap (after 3 rounds of address-and-redispatch, halt for user input even if each round caught different findings). | **Yes — keystone enforcement layer; the .25 rule has teeth now** |
| 36 | `27d9bdd` | feat  | Extend --image plumbing to review fleet (closes GH #14) + inject reference_preamble into all review rounds (closes GH #13). Centralizes per-provider image-attach into new `scripts/lib/image-attach.sh` (nameref API) used by probe_single_agent, spawn_agent, and run_agent_sync — all three handle images identically. `review_run` exports OCTO_AGENT_IMAGES=$reference (realpath -m for robust absolution) with RETURN-trap restore so env doesn't leak. Round 2 verifier_prompt + Round 3 debate_prompt + Round 3 synthesis_prompt now include the mockup-context preamble with explicit "do not downgrade visual-divergence findings solely because the diff lacks evidence" guidance — prevents visual-unverified findings from being filtered in downstream rounds. Dogfooded via 3 consensus rounds; gemini SEV-2 dissent documented + filed as GH #19. | **Yes — closes 2 GH issues** |
| 37 | `ae913ad` | fix   | Tighten consensus rule triggers (closes GH #17). Replaces subjective wording in 6 triggers with mechanical predicates: #2 (host-position URL extraction handles named-remote + URL-arg, no substring bypass), #3 (regex with stem matching for ship/complet/ready-to-X/closes-#N inflections), #5 (drop speculative "would need to adopt"; concrete grep+manifest checks on dirty tree), #8 (drop lockfile exception — ANY lockfile change triggers), #9 (drop semantic "What I'd suggest"; deferral-keyword regex), adjudication path (define "different family" via consensus-gate.sh family-map). Dogfooded via 3-round consensus check — v1 had 2 SEV-1 + 6 SEV-2, v2 had 1 SEV-1 + 4 SEV-2, v3 reached NO BLOCKING from both providers. | Plausible — consensus-rule prose hygiene |
| 38 | `ce93c21` | feat  | Quick-wins triple-patch (closes GH #10 + #6 + #9). #10: standardize argument-hint to POSIX flags-first across 4 commands (critique, defensibility, argument-strength, visual-review); add `.claude/COMMAND_CONVENTIONS.md`. #6: add STEP 4b2 to /octo:setup wizard — per-provider Enable/Disable prompt persisted via existing `orchestrate.sh provider disable` subcommand. #9: implement Path A interface_version enforcement — `--required-lib-interface N` + `--check-lib-skill <name>` flags in lib-multi-dispatch.sh read SKILL.md frontmatter and refuse dispatch on version mismatch; opt-in for consumers; skill-lib-multi-inspect-figure pinned to v2 as canonical example. Dogfooded via 2-round consensus; v2 NO BLOCKING from both providers. | **Yes — closes 3 GH issues; small, well-scoped** |
| 39 | `61df883` | fix   | `--resume` content-hash check (closes GH #8). Adds per-reviewer fingerprint (sha256 of agent_type + doc-file-bytes + prompt + image-paths-and-byte-hashes, 16 chars) to dispatch.json. On --resume, label match is necessary but NOT sufficient — fingerprint must also match before reusing prior output. Mismatch logs "🔁 re-dispatch (fingerprint differs: prior=X current=Y)" with reasoning. Pre-lestephen.31 dispatch.json files without the field always re-dispatch (sentinel). Bundled fix to gemini SEV-1 JSON injection: dispatch.json now built via jq -n --arg/--argjson (not printf, which couldn't escape quotes/backslashes in labels). Bundled fix to gemini SEV-2s: image-paths use printf %s (not %b — no escape interpretation), doc fingerprint hashes file bytes (not $(cat)-stripped), resume reader consumes jq -c JSON-per-line + jq -r per-field. Validated: same-input skips, changed-doc re-dispatches, embedded-quote labels preserved. v2 consensus: claude NO BLOCKING + gemini 3 SEV-2 minority (filed as GH #20). | **Yes — closes 1 GH issue + corrects JSON-injection bug** |
| 40 | `11e07ad` | fix   | Profile-loading schema validation + rc-contract backcompat (closes GH #4). Adds `octo_validate_profile` to `scripts/lib/load-octo-profile.sh` checking required keys (`audiences` non-empty object, `banned_terms` array, `internal_codenames` array) after YAML parse passes. New `incomplete` status + `OCTO_PROFILE_MISSING_KEYS` lists missing keys; loader stops at incomplete file (same rationale as malformed branch). New `unvalidated` status when no validator installed. Return-code policy preserves backward-compat: rc=0 for loaded/unvalidated/template/missing, rc=1 only for malformed/incomplete (actively broken). Per consensus v1 SEV-2 (both providers): also fixed yq-vs-python validator inconsistency (yq branch now uses explicit type+length predicates matching python). | **Yes — closes 1 GH issue + improves backward-compat for `set -e` callers** |
| 41 | `062cbba` | feat  | Visual-review tooling (GH #11 expensive-leg per team feedback). Ships standalone tools so reviewers don't have to eyeball: `scripts/helpers/sample_pixel.py` (Pillow-based, hex/rgb from coords); `scripts/helpers/delta_e.py` (pure-stdlib CIE76/CIE94/CIEDE2000 — default CIE76 threshold 5.0 matches petrics' test_palette_assertion.py); `scripts/helpers/render_diff.sh` (project-supplied screenshot wrapper, stdout/stderr strictly separated). review.sh preamble rewritten with TOOLS YOU SHOULD CALL block (concrete commands, paths printf %q-quoted), WHEN TO CALL mechanical-trigger list (per-color-hex-literal in diff), WHAT TO FLAG categories (`visual-divergence` for verified-coord, `visual-coord-unverified` for guessed-coord, `visual-token-comment-mismatch`, `rendered-divergence`). New `visual.delta_e_threshold` + `visual.render_script` profile fields. End-to-end validated: original Phase 4 canvas bug (`#1b2227` vs `#0e1a24`) measures deltaE=5.83 — would have been flagged. 3-round consensus: v1 SEV-1 + 5 SEV-2, v2 1 shared SEV-2 (missed %q for plugin_dir), v3 NO BLOCKING from both. Dedicated visual-diff specialist agent deferred to follow-up. | **Yes — closes the structural failure mode petrics surfaced** |
| 42 | `7d32e9d` | fix+ci | README install instructions corrected + marketplace-update CI. User reported `/plugin install <repo-url>` was wrong (this repo is plugin SOURCE not marketplace; correct path uses separate `lestephen/claude-octopus-marketplace` with `/plugin marketplace add … && /plugin install octo@lestephen-octo`), and the `git clone … ~/.claude-octopus/plugin` form failed against pre-existing dirs. README rewritten with correct marketplace flow + dev workflow (clone outside, rmdir empty pre-existing, ln -sfn) + "Note the names" callout clarifying the three distinct names (repo / marketplace.name / plugin.name). NEW `.github/workflows/update-marketplace.yml` auto-bumps the marketplace pin on every `v*-lestephen.*` tag push (jq-updates source.ref + version + description; idempotent; validates tag shape). Requires `MARKETPLACE_UPDATE_TOKEN` secret (workflow header documents). 2-round consensus: v1 2 SEV-2 (symlink-into-empty-dir creates nested link; gemini false alarm on marketplace names), v2 NO BLOCKING from both. | No — fork-only install path |
| 43 | `01b3907` | fix   | Petrics dogfood findings on GH #11 reopen (5/5 agents structurally caught the regression, but found these). SEV-1: `target=branch` silently produced empty diff (false negative — fell through to pathspec arm in review_collect_diff). New `branch` arm resolves effective base (`profile.base` > `origin/HEAD`'s branch > `origin/main` > `main` > unresolvable); computes `git diff <merge-base>..HEAD`. Fail-loud sentinels `BRANCH_BASE_UNRESOLVED` / `BRANCH_MERGEBASE_UNRESOLVED:<base>` detected in review_run → structured error JSON + rc=1. review_run now also parses `base` from profile (was set by /octo:visual-review but never read). Polish: spawn_agent's `# Prompt:` header was dumping the full multi-KB preamble inline; now prompts >200 chars write to sibling `.prompt.md` and inline header gets preview + pointer (single-line safety with `↩` newline-marker per gemini v1 SEV-2). Polish: `sample_pixel.py` gains `--patch SIZE` (odd values only, rejects evens) for N×N averaged sampling — addresses petrics' single-pixel-vs-3×3 inconsistency. v1 consensus: claude NO BLOCKING, gemini 2 SEV-2 minority (fixed in v2 anyway). | **Yes — clear bug + dogfood polish** |
| 44 | `eb5986f` | fix   | README dev-install rewrite. User flagged that `~/.claude-octopus/plugin` is the plugin's OWN internal self-resolution path (used by `bin/octo-consensus`, `setup.md`, etc.) — NOT a Claude Code discovery path. Claude Code installs to `~/.claude/plugins/cache/lestephen-octo/octo/<base-ver>/`. New 5-step workflow: (1) /plugin install via marketplace first so Claude Code creates its cache dir; (2) git clone outside the cache; (3) resolve actual install path via `jq` query on `installed_plugins.json` with `sort_by(.lastUpdated) | last | .installPath` (deterministic across multi-version caches); (4) rm -rf cached install + symlink to working tree; (5) ALSO symlink the self-resolution path with explicit symlink/empty-dir/non-empty-dir trichotomy. `set -euo pipefail` + all paths use `$HOME` with explicit quotes (gemini SEV-2: tilde fails on home with spaces). Gotchas section: /plugin update clobbers, version subdir is BASE not fork suffix, both symlinks needed. 3-round consensus: v1/v2 caught real findings, v3 NO BLOCKING from both providers. | No — fork-only install path |
| 45 | `371ba3b` | feat  | Wrap dev-install dance in `scripts/dev-install.sh`. User feedback: the 5-step manual bash snippet from .36 was silly. New script handles the full workflow idempotently: verifies prerequisite, resolves install path via jq, clones if not present (refuses non-git pre-existing path), replaces cached install with symlink to working tree (symlink/real-dir trichotomy + already-correct no-op), symlinks self-resolution path. Status lines + ✓ final + /plugin update warning. README dev section drops from a 60-line bash block to two commands. Consensus v1: claude NO BLOCKING + gemini 1 SEV-2 (multi-version glob in README would pass extra paths as args to bash; fixed with `ls -t \| head -1` to pick most-recent). | No — fork-only install path |
| 46 | `a883d04` | feat  | PRODUCT SEMANTICS + PRE-EXISTING STATE PASS preamble blocks (closes GH #22). Petrics PR-25 dogfood found 9 structural/product-design issues that shipped past prior reviews — the .33 preamble was narrow on code-internal correctness. Two new blocks: (a) PRODUCT SEMANTICS asks 4 questions of every visible label/value/affordance: WHAT DOES THIS MEAN in 2s (Mood:50% example); IS THIS AFFORDANCE REDUNDANT (physical+on-screen button example); DOES RENDERED PROPORTION MATCH (gated on `visual.render_script`); WHAT PRE-EXISTING STATE contradicts the reference (gated on new `visual.preexisting_pass` flag, default false per petrics' explicit ask). Each maps to a distinct finding category; CATEGORY DISTINCTION block is built dynamically — only lists categories whose questions are active in this dispatch, no orphan categories. (b) PRE-EXISTING STATE PASS sampling methodology when preexisting_pass=true. 3-round consensus: v1 + v2 caught real asymmetry bugs (Q3 gated but Q4 wasn't), v3 NO BLOCKING from both. | **Yes — addresses structural failure mode petrics flagged** |
| 47 | `0f011bf` | fix   | Configurable per-call timeouts in /octo:debate + /octo:define (closes GH #12). User reported `-t 600` to orchestrate.sh ignored: claude-sonnet killed at 90s (needed 123s), codex would need 244s. Hardcoded literals in `grapple_debate` (13 sites: 90/120/150) + `grasp_define` (6 sites: 120/180) replaced with env-var-resolved locals. Resolution: per-round env (e.g. OCTOPUS_DEBATE_CRITIQUE_TIMEOUT) > master env (OCTOPUS_DEBATE_TIMEOUT / OCTOPUS_GRASP_TIMEOUT) > -t flag global (\$TIMEOUT) > new default 300s. New default matches petrics' measured wall-clock + ~25% headroom. DEBUG log at function entry shows effective values. Single-round consensus: both providers NO BLOCKING. | **Yes — clear bug + small additive UX** |
| 48 | `fe54a38` | fix   | /octo:setup preflight bugs from Windows MINGW64 clean-install transcript (6m 22s total, ~5 min on per-provider step). Replaces slow multi-path `find` traversal with O(1) jq lookup of Claude Code's `installed_plugins.json` (tries both `octo@lestephen-octo` and `octo@nyldn-plugins` marketplace keys, picks latest by `lastUpdated`). Strategy-2 narrow-glob fallback covers Linux/MINGW64 + macOS `Library/Application Support` + Windows `LOCALAPPDATA` + XDG roots — addresses gemini v1 SEV-2 (Strategy-2 missed non-Linux platforms). v3 swaps `sort -V` for `ls -t` mtime selection (gemini v2 SEV-2: `sort -V` is GNU-only and broke on macOS BSD sort; full-path sort let directory names dominate over version numbers). Two follow-ups filed: GH #23 (`check_first_run` hint inside the wizard), GH #24 (detect-providers OAuth recognition for the Codex/Gemini "not authenticated" mismatch in the transcript). 2-round consensus: v1 + v2 caught real findings, v3 lands the portability fix. | No — fork-only install path |
| 49 | `8089012` | fix   | Wizard-internal noise + auth-detection mismatches (closes GH #23 + GH #24). #23: `check_first_run` in `config-display.sh` honors new `OCTOPUS_SETUP_IN_PROGRESS=1` env var to suppress the "🐙 First time?" hint when invoked from inside `/octo:setup`; wizard exports it before every `orchestrate.sh` subcall. #24: three real auth-detection bugs. (a) `setup.md`'s initial scan claimed `codex_auth:ok` based on `codex --version` alone (just proves the binary runs); rewritten to mirror `detect-providers`' OAuth-file + env-var logic. (b) `setup.md` had NO gemini auth check at all in the initial scan — added one with the same logic. (c) `preflight.sh:192,194` `A && B \|\| C && D \|\| E` ternary captured BOTH "oauth" AND "api-key" when OAuth file existed (classic bash precedence: `B` returns rc=0, `D` then runs because chain rc is 0), corrupting `.provider-cache` with a stray `api-key` line; replaced with explicit if/elif/else. Plus: `cmd_detect_providers`' live gemini echo now accepts `GOOGLE_API_KEY` (gemini-cli's second supported env var) — was a divergence from cache-write + `check_first_run`. | No — fork-only wizard polish |
| 50 | `504e0b0` | test  | Frontmatter & command-routing lint (closes GH #3 parts 1+3). Extends `scripts/validate-plugin-assembly.py` with three new checks: (a) skill `name:` must match its parent directory name — catches the lestephen.12 class of bug (smoke test discovered file living under one slug while name field pointed at another); (b) command `command:` field must match the file stem — catches `/octo:foo` routing to a phantom command; (c) command `skill:` field must point to an existing `skills/<name>/` directory — catches silent route-to-nothing typos. Plus a soft 250-char cap on `description:` for both skills and commands (current max is 149, so 250 gives growth room while flagging novella drift). Wired into `make test-smoke` as a dependency, so PRs gate on it via `.github/workflows/test.yml`. Negative tests confirmed all 4 checks fire. Library-skill provider-mock integration tests + orchestrate-subcommand cross-walk + file-reference resolver (the heavier #3 part 2) filed as GH #25. | Plausible — pure additive lint, no behavior change |
| 51 | `21d1754` | fix   | Trap + awk hardening from lestephen.28 consensus dissent (closes GH #19). (a) `review.sh`: extracts the OCTO_AGENT_IMAGES restoration into an idempotent helper (`_review_restore_octo_agent_images`); installs the `RETURN` trap BEFORE the export so a `set -e` failure between export and trap-install can't bypass cleanup (closes claude SEV-3); also calls the helper explicitly at the end of `review_run` as belt-and-suspenders against a nested function's RETURN trap clobbering ours (closes gemini SEV-2 #1). Signal-interrupt cleanup is moot — env var is exported into orchestrate.sh's own process and dies with it. (b) `spawn.sh`: awk previously returned rc=0 even when `## Output` line wasn't matched, silently dropping the image note; added `END { if (!inserted) exit 1 }` so match failure reliably triggers the append-at-EOF fallback (closes gemini SEV-2 #2). Verified empirically: prior awk dropped the note silently; new awk returns rc=1 on missing header. | Plausible — defensive hardening of recent change |
| 52 | `5ccf985` | fix   | `--resume` dispatch hygiene (closes GH #20). Three gemini SEV-2 dissents from .31 consensus addressed: (1) DOC fingerprint switched from `sha256sum "$DOC_PATH"` (file bytes) to `printf '%s' "$DOC_CONTENT" \| sha256sum` (what the model sees). v2 chose byte-hash to avoid false-negatives on trailing-whitespace-different docs; v3 dissent flagged this as over-dispatch because $(cat) strips trailing newlines from the actual prompt. Correct invariant: fingerprint should equal "model-equivalent input," not "file bytes." (2) PRIOR_SUCCESS_LABELS round-trip verified empirically — both read (`jq -r '.label'`) and write (`jq -r '.[$i].perspective_label'`) strip trailing newlines identically, so labels with internal newlines round-trip cleanly; no code change needed, only an inline comment documenting the verification. (3) `_reviewers_array` build switched from O(N^2) `jq --argjson existing` accumulation to slurp-at-end pattern (write JSONL to temp file, `jq -s` once). Closes ARG_MAX scalability concern for large reviewer fleets. | Plausible — internal-only hygiene |
| 53 | `3745979` | feat  | Project format-standard injection in `/octo:argument-strength` (closes GH #2). Dogfood at lestephen.13 found 3-of-5 gemini structural-attack objections conflicted with the project's `docs/report-format-standard.md` — reviewer was applying generic-good-writing principles instead of the project's mandated section sequence. New STEP 2b walks up from `$doc_path` looking for a format standard at canonical paths (`docs/report-format-standard.md`, `docs/format-standard.md`, `docs/templates/report-format.md`, `.octo/report-format-standard.md`, `<root>/report-format-standard.md`), stopping at the git root. If found, the path is injected as a conditional block into the structural-attack reviewer's prompt with explicit "do NOT propose changes that violate the standard's section sequencing/heading conventions/placement rules; focus structural critique on argument flow WITHIN sections." Smaller one-line guards added to technical-attack and audience-reception reviewers so they defer structural revisions to the briefed reviewer. Detection is optional — no standard found = no constraint added, prior behavior preserved. Smoke-tested both code paths (no-standard repo + fixture with standard). | Plausible — generic skill, no fork-only assumption |
| 54 | `c577cbc` | feat  | Vision-provider capability tags (closes GH #5). `check-providers.sh` output format extended from `<name>:available` to `<name>:available:<caps>` where caps is a comma-separated capability list. New `_octo_provider_caps` function maps each provider to `text` or `text,vision` based on the lestephen.24 vision-matrix retest (codex/claude/gemini verified vision-capable via this dispatch path; copilot/qwen/opencode/cursor-agent/perplexity/ollama/openrouter conservatively text-only until verified). `OCTO_PROVIDER_VISION=name1,name2` env-var override promotes additional providers to vision without editing the map. `skill-lib-multi-inspect-figure` STEP 1 now mechanically filters via `grep ',vision' \| cut -d: -f1` instead of relying on the model to know the vision matrix. Backward compat: existing consumers grepping `:available` still match (substring of `:available:text`). Replaces prose-only matrix in inspect-figure with a deterministic filter, so future provider-vision changes are picked up automatically. | Plausible — additive output-format extension |
| 55 | `f92694f` | feat  | Instruction-fidelity preamble (closes GH #26). Petrics PR-25 failure mode: user said "the pet... is smaller than the grounding mockup" (implying make it LARGER); implementer agent shipped `scale: 0.6 → 0.4` (made it SMALLER). The review fleet saw the diff but not the originating instruction, so couldn't catch the inversion. Fix: new `review_collect_intent` helper returns commit messages (for `target=branch`, via `git log base..HEAD --format=%B`, capped at 8000 chars) or PR title+body (for `target=<N>`, via `gh pr view`). Empty for staged/working-tree/pathspec where no durable intent exists. The collected intent is injected into Round-1 `agent_prompt_base` AND Round-2 verifier_prompt (mirrors GH #13 lesson — Round 2 must see the same context or it drops findings as "unsupported by diff"). New preamble block names the directional-claim pattern with the petrics worked example; new category `instruction-inversion` severity 'normal'; explicit no-flag list (subjective improve/polish/refactor; aspirational language; split-commit series). Smoke-tested: collector works against this repo's git history. | Plausible — narrow generic capability, no fork assumption |

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

**Commit:** `2befccf`
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

**Commit:** `229646a`
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

## Patch 28 — `fix: PR 1 ship-blockers from dogfood audit (provider dispatch guard, debate args, bump-fork atomicity, critique bundle, defensibility hardening)`

**Commit:** _pending_

Bundle of five ship-blocker fixes surfaced by running `/octo:critique` against the lestephen.10-.19 patch series. The audit (with codex + gemini + claude/host reviewers) found 20+ new issues; this patch ships the HIGH-severity ones.

### F1: `/octo:provider disable` is now enforced on dispatch paths

`scripts/lib/provider-allowlist.sh` (+57 lines), `scripts/lib/workflows.sh` (+12 in `probe_single_agent`), `scripts/lib/agent-sync.sh` (+12 in `run_agent_sync`), `scripts/orchestrate.sh` (+6 — source allowlist globally).

Before: `provider list` correctly showed `copilot: disabled` but the dispatch paths (`probe_single_agent`, `run_agent_sync`) didn't consult `octo_provider_allowed`. The compliance feature lied.

After: new shared helper `octo_provider_dispatch_guard <agent_type>` consults env denylist + project config + user config + OCTO_ALLOWED_PROVIDERS allowlist. Both dispatch entry points call it before model resolution; if blocked, dispatch returns code 2 with a clear log line referencing the disable source. Also exposes `octo_provider_for_agent_type` as a shared helper for the family mapping that was previously duplicated across 4+ files.

### F2 + F3: Debate prompt arg corruption + mode validation

`scripts/orchestrate.sh` — both `debate|deliberate|consensus)` and `grapple)` case branches.

Before: `grapple_debate "$@" "$principles" "$rounds" "$debate_mode"` — multi-word prompts got expanded into separate positional args; `debate redis vs memcached` became `prompt=redis principles=vs rounds=memcached`. Silent argument corruption.

After: `prompt="$*"` captures the remainder; pass as a single string. Plus `--mode` validation: `cross-critique` and `independent` (alias `blinded`) are accepted and normalized; `adversarial` and `collaborative` (advertised in help but not implemented) now error explicitly with the available list. Help text updated to match.

### F6 + F7 + F10 + F11: bump-fork.sh atomicity + provider-config lock + name validation

`scripts/bump-fork.sh` — rewrote `set_version_everywhere` as two-stage (read+plan all targets into tempfiles; if all succeed, atomic-rename each into place; otherwise roll back). Smoke-tested: corrupting `.codex-plugin/plugin.json` mid-flight rolls back all manifests to the prior version instead of leaving mixed state. Plus `flock` around mutating commands (`patch`, `merge-upstream`, `set`) so concurrent invocations can't both compute `N+1` from `N` (lost-increment race).

`scripts/lib/provider-config.sh` — added `_provider_validate_name` (rejects names with whitespace, newlines, semicolons, anything outside `^[a-z0-9][a-z0-9-]{0,31}$`). Added `_provider_config_with_lock` wrapping disable/enable in flock so concurrent runs on different providers can't last-writer-wins one of them away.

### G2: skill-critique writes bundle to temp file before passing to lib

`skills/skill-critique/SKILL.md` STEP 4 + STEP 7. Critique was telling executors to construct an in-memory "bundle" and pass it as `doc_path`, but `lib-multi-review-doc` validates `[[ ! -f "$doc_path" ]]` and would refuse the string. Now writes the bundle to `mktemp` first, passes that path, and cleans up after copying the bundle into the output dir as `scope-bundle.md` for audit trail.

Also fixed in critique, defensibility-pass, argument-strength: the `$OUTPUT_DIR` drift (Gemini F1). The variable is local to library skill bash and not in scope when parent skills try to use it. Parents now extract `$(dirname "$SYNTHESIS_PATH")` from the library skill's returned `SYNTHESIS:` line.

### G3: defensibility-pass hardened — no profile → BLOCKED-INFRASTRUCTURE

`skills/skill-defensibility-pass/SKILL.md` STEP 5 + verdict mapping + Failure modes.

Before: MANDATORY COMPLIANCE forbade "defensible" verdicts without a profile; Step 6 mapping permitted `DEFENSIBLE WITH MINOR EDITS` without one. Contradiction. Behavior was non-deterministic on the highest-stakes skill we ship.

After: hardened. No profile loaded → verdict ceiling `BLOCKED-INFRASTRUCTURE` with a clear setup instruction. Defensibility without project rules is theater; generic Pass C can't enforce EKI's banned terms or audience matrix.

### Verification

- F1 smoke test: `bash orchestrate.sh probe-single copilot ...` now logs `Dispatch blocked: provider 'copilot' is disabled. Source: user (...). Re-enable via: scripts/orchestrate.sh provider enable copilot`
- F2 smoke test: parsing redis-vs-memcached as args produces `prompt=[redis vs memcached]` not `principles=vs rounds=memcached`
- F3 smoke test: `--mode adversarial` errors; `--mode independent` normalizes to `blinded`
- F10 smoke test: corrupting one manifest mid-bump rolls back all others
- F7 smoke test: `provider_config_disable "codex;rm -rf /"` rejected with validation error

### Upstream PR strategy

Strong upstream PR candidate. All five fixes are clear bugs in the new code path; behavior change is from "broken or non-deterministic" → "correct". F1 (dispatch enforcement) is the most impactful for any user who has tried `OCTO_ALLOWED_PROVIDERS`.

---

## Patch 29 — `refactor: PR 2 architectural improvements (real-bash dispatch helper, consolidated profile loader, misc audit fixes)`

**Commit:** _pending_

PR 2 from the dogfood-audit recommendations. Architectural improvements that pay for themselves: testable real-bash dispatch (instead of skill-prose pseudocode), single profile loader (was three drifting implementations), and the remaining MEDIUM/LOW audit findings.

### C5: `scripts/helpers/lib-multi-dispatch.sh` — real bash dispatcher

Replaces the pseudocode-in-skill-prose pattern that the `skill-lib-*` skills previously used. Takes `--doc-path`, `--reviewers <json-file>`, `--output-dir`, `--min-reviewers`; dispatches parallel `probe-single` calls; enforces a **strong validation gate** (file exists + non-empty + `## Status: SUCCESS` + `## Output` body ≥ 50 chars — closes audit issue #1 about the file-size-only gate); writes `dispatch.json` summary + `synthesis-input.md` for consumer skills.

Distinct exit codes:
- `0` — success
- `2` — usage / preflight failure
- `3` — dispatch infrastructure (orchestrate.sh missing)
- `4` — partial / insufficient reviewers passed validation

Consumer skills (`skill-lib-multi-review-doc`) updated to call this helper; pseudocode v1 path preserved for older callers but marked obsolete.

### C2: `interface_version` frontmatter on all `skill-lib-*` skills

Bumped to `interface_version: 2` for `skill-lib-multi-review-doc` (matches the helper-driven path). `skill-lib-multi-inspect-figure` and `skill-lib-independent-recompute` pinned at `interface_version: 1` with notes describing what would bump them. Consumer skills should pin to a major version so silent interface drift breaks loudly.

### C1: `scripts/lib/load-octo-profile.sh` — single profile loader

Consolidates three previously-independent profile-loading implementations into one. Exports `OCTO_PROFILE_PATH` and `OCTO_PROFILE_STATUS` (`loaded` | `template` | `missing` | `malformed`). `octo_profile_status_line` renders a single-line status for skill prose / doctor output.

Search order (first match wins):

1. `$OCTOPUS_KW_PROFILE`
2. `./.octopus/profile.yaml`
3. `$HOME/.config/octopus/profile.yaml`
4. `$HOME/.claude-octopus/config/profile.yaml`
5. plugin-installed `eki-kw/profiles/default.yaml`
6. any installed `profiles/default.yaml`

### Misc audit fixes batched

- **F5**: jq lookups with hyphenated provider names (e.g. `cursor-agent`) now use `--arg` instead of `${provider}` interpolation. Previously `.providers.cursor-agent` parsed as subtraction, silently dropping the config.
- **F8**: `/octo:provider status` now distinguishes `BLOCKED by OCTO_ALLOWED_PROVIDERS` from `not disabled (allowed)`. Was reporting "allowed" when an env allowlist excluded the provider.
- **F9**: `/octo:doctor` per-disabled-provider hint now branches on source — env disables suggest unsetting the env var; project disables append `--project`; user disables get the default `provider enable` form.
- **F13**: `skill-lib-independent-recompute` provider prompt now requires a final JSON `Machine-readable summary` block with `compute_status` and `computed_value` fields. The aggregator was expecting this field but the prompt never asked for it.
- **C3**: `bump-fork.sh status` exit-code semantics documented — `0` consistent, `1` drift detected, `2+` script error. CI / pre-push hooks can now distinguish.
- **C7**: `provider disable codex gemini` now actually disables both. Previously silently dropped everything after the first arg.
- **C8**: `/octo:critique` now writes a machine-readable `verdict.json` alongside the prose `critique-report.md`. Agentic consumers can branch on outcome without regex-parsing prose.

### What this patch does NOT close

Items deferred to follow-up issues / future patches:

- **C4** (doctor + provider list format inconsistency) — both still render their own way; alignment is a UX-only nice-to-have
- **C6** (no resume after partial reviewer failure) — the helper has the substrate (`dispatch.json`) but no `--resume` flag yet
- **F4** (model-resolver bare-value still treats some strings as literal model names) — needs deeper refactor of `resolve_provider_to_agent`
- **F12** (figure inspection sends text path instead of image bytes) — needs provider-specific multimodal payload work; bigger than a patch
- **G4 / G5 / G6 / G7** (Gemini's UX/naming nits) — bikeshed; settle once the ship-blockers and architectural items are stable

### Upstream PR strategy

Plausible upstream PR. The real-bash dispatch helper is genuinely useful for any skill that wants multi-LLM fan-out and not all consumers will be in the lestephen fork. The profile loader is similar — third-party plugins benefit. The misc fixes are clear bugs in PR-1 code or in v9.17.1 / v9.38.0 / lestephen.15 code. Worth a discussion-first PR for the architectural items (C5 + C2 + C1); misc fixes can land as a separate small PR.

---

## Patch 30 — `feat+fix: autonomous-mode skill + deferred audit items (F4 / C6 / G4 / G5 / G6) + dogfood-critique fixes`

**Commit:** _pending_

Bundles the PR 3 batch: the deferred items from the prior dogfood audit, a new behavioral protocol skill for autonomous sessions, and the fixes from running `/octo:critique` on this patch before commit. Total: 14 fixes + 1 new skill, 4 GH issues filed for items deferred.

### New: `skill-autonomous-mode` + `/octo:autonomous`

Codifies the "work autonomously, file issues for blockers at discovery time" protocol. When the user grants explicit autonomy ("work autonomously" / `/octo:autonomous <task>`), the skill instructs Claude to:

- Make reasonable judgment calls without confirming each one
- File a GH issue (or local `ISSUES.md` if no remote) the moment a blocker requires user input — at discovery time, not batched at session end
- Continue past blockers with documented assumptions
- Skip irreversible destructive actions even under autonomy (expanded list: filesystem deletion, git history rewrites, infra destruction, schema drops, secret rotation, public publishes)
- End with a structured summary (Shipped / Issues filed / Encoded assumptions / Explicitly deferred)

Includes explicit precedence vs other skills' MANDATORY COMPLIANCE rules: autonomous overrides "ask user" halts EXCEPT for safety/compliance gates (defensibility-BLOCKED, security HIGH, ship critical) and explicit destructive actions.

### F4: model-resolver bare agent_type recursion

`scripts/lib/model-resolver.sh` — when role/phase routing returned a bare value matching an `agent_type` shape (e.g., `gemini-fast`, `claude-opus`), the existing code treated it as a literal model name. Now uses `octo_provider_for_agent_type` to detect the case and recurse via `resolve_octopus_model` for same-provider matches; skip for cross-provider. Sources `provider-allowlist.sh` from BASH_SOURCE-relative path first (works in test harnesses + dev checkouts), then falls back to installed path.

### C6: `--resume` flag in lib-multi-dispatch.sh

After a partial-failure dispatch, `--resume` reads the prior `dispatch.json`, skips reviewers that succeeded (re-records their outputs), and re-dispatches only the failures. Recovers from transient provider outages without re-running everything.

(Known limitation: identity by `perspective_label` only. Changing the doc/prompt between runs while keeping the label silently merges stale output. Tracked as GH #8.)

### G4: canonical profile path + malformed-profile semantics

`scripts/lib/load-octo-profile.sh` reordered so `$HOME/.claude-octopus/config/profile.yaml` takes precedence over the XDG path (matches the documented canonical recommendation). Malformed high-priority profiles now STOP iteration (`OCTO_PROFILE_STATUS=malformed`) rather than silently falling through to lower-priority defaults. YAML validation gracefully skips when PyYAML isn't installed.

### G5: cross-skill routing table cleanup

`skill-debate` removed cannibalizing examples (`/debate Review the auth flow in src/auth.ts` was actively confusing). Added explicit routing table covering 7 commands: debate / review / critique / argument-strength / defensibility / debug / security.

### G6: argument-hint frontmatter on new commands

`.claude/commands/{defensibility,argument-strength,critique}.md` now declare flag grammar in `argument-hint` frontmatter. Matches `/octo:review`'s pattern. (Inconsistent flag ordering between POSIX-first and target-first across new commands is a known wart — GH #10.)

### Misc dogfood fixes (10 items from `/octo:critique` on this patch)

- Autonomous mode trigger phrases tightened — no longer activates on bare "do it" / "proceed" (codex F6)
- Destructive-action exemption list expanded — covers infra destruction, secret rotation, public publishes (codex F7)
- Debate routing table fixed: `/octo:defensibility-pass` → `/octo:defensibility` (codex F8)
- Profile install hint everywhere updated to point at canonical path (gemini F4)
- `/octo:provider status` distinguishes BLOCKED-by-allowlist from disabled (already in PR 2; reverified)
- Routing table extended to include `/octo:debug` and `/octo:security` (gemini F2)
- Model-resolver helper-sourcing prefers BASH_SOURCE over installed path (codex F1)
- Profile YAML validation no longer requires PyYAML (codex F4)
- Defensibility-pass docs updated to match new canonical-first precedence (gemini F4)
- Skill prose `interface_version` properly preserved on three lib-* skills

### Deferred to GH issues (filed at discovery)

- **#7** F12: `lib-multi-inspect-figure` sends image path as text, not pixels. Needs `probe-single --image` passthrough + per-provider attachment mechanics. Out-of-scope for this patch.
- **#8** `--resume` identity is label-only; needs input-fingerprint to detect stale outputs.
- **#9** `interface_version` is dead text; needs runtime enforcement or honest relabeling as semantic-only.
- **#10** `argument-hint` flag ordering inconsistent (POSIX-first vs target-first); needs a convention decision.

### Upstream PR strategy

Mixed. `skill-autonomous-mode` is a behavioral protocol that maintainers may want to design differently. The deferred-item fixes (F4, C6, G4, G5, G6) are clear improvements that should land cleanly upstream. The misc dogfood fixes are bug fixes in already-merged code paths.

Worth opening this as **two PRs upstream**:
- A small one with the bug fixes
- A discussion-first one for `skill-autonomous-mode` and the architectural-protocol implications

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

The `patches/` directory in this fork contains all 30 patches as mbox
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
