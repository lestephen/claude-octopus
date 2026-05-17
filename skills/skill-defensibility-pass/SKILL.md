---
name: skill-defensibility-pass
description: "Hostile-review gate before a document goes external — independent recompute, methodology audit, internal-terms scrub via multi-LLM"
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Defensibility Pass

A publish-ready gate for documents that are going outside your organization — to a customer, supplier, regulator, end-user, or opposing party in a dispute. Runs three coordinated passes via the library skills, each from a different angle, and synthesizes a pass/fail with what must change before send.

The premise: when a single LLM reviews your own draft, it tends to agree with you because the draft is internally coherent. Three independent providers reviewing under three different lenses surface what would land if a hostile expert read the same document. Empirically, three providers running adversarially catch issues that any single one (including the human author) miss.

## When to use this skill

- Before sending a technical report, evaluation memo, or analysis to an external party
- Before publishing a paper, white-paper, or external-facing analysis
- Before forwarding a document that may be entered into a contract, dispute, or regulatory record
- Any time the cost of a defect being found by the recipient is materially higher than the cost of finding it first

## When NOT to use this skill

- Internal-only working documents (overkill; use `skill-argument-strength` for a lighter critique)
- Personal notes, drafts not yet ready for review (premature; the draft must be argument-complete first)
- Documents whose primary purpose is decision-making among collaborators (use `/octo:debate` instead)
- Code (use `/octo:review` or `flow-deliver`)

## What "defensibility" means here

A document is **defensible** when:

1. **Every quantitative claim recomputes from the cited source within tolerance** — Pass A
2. **Every assumption is stated or detectable from context, and the methodology chain holds together** — Pass B
3. **No internal-only terms, project codenames, repository paths, or wording that leaks strategy appear in the output** — Pass C

A defensibility-passing document does not mean the underlying conclusions are correct; it means the document holds up to a hostile reader who has only the document itself to work with.

## ⚠️ MANDATORY: Visual Indicators Protocol

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Defensibility Pass`

Then output the provider banner:

```
✅ Deliver Phase (KM): Hostile-review gate before external send

Passes:
🔴 Pass A - Independent recompute (Codex + Gemini)
🟡 Pass B - Methodology audit (Codex + Gemini)
🟣 Pass C - Internal-terms scrub + banned-phrase lint (Gemini + Claude)
🔵 Synthesis (Claude) - Pass/fail verdict with what must change
```

## ⚠️ MANDATORY COMPLIANCE — DO NOT SKIP

You are PROHIBITED from:

- Running only one or two of the three passes
- Substituting "I read the document carefully and didn't see issues" for the multi-LLM library-skill calls
- Treating the synthesis as pass when any pass returned `FAIL` or `UNSUPPORTED`
- Skipping Pass C because the document "looks clean" — the lint is what catches the cases the human author cannot see
- Declaring the document defensible when the project profile (banned terms, internal codenames) was not loaded

If a library skill failure prevents one of the passes from running, the overall verdict defaults to `BLOCKED` with the reason recorded. Surface the failure to the user; do not synthesize around it.

## Input contract

Direct invocation:

| Input | Description |
|---|---|
| `doc_path` | The document to gate (markdown source, not a built artifact) |
| `audience` (optional) | One of `customer`, `supplier`, `regulator`, `counterparty`, `public`. Tunes Pass B/C wording. Default: `customer` |
| `source_data_dir` (optional) | Directory containing the source data the document's quantitative claims draw from. Required for Pass A to run; if absent, Pass A is reported as `SKIPPED — no source_data_dir`. |
| `profile_path` (optional) | Path to project profile YAML with `banned_terms`, `internal_codenames`, `audience_rules`. Default search via `scripts/lib/load-octo-profile.sh` — see "Profile loading" section below for the canonical location and full search order. If nothing found, the skill returns `BLOCKED-INFRASTRUCTURE` per G3 hardening. |

## Profile loading

**lestephen.22 (G4 + C1):** Profile loading is now centralized in `scripts/lib/load-octo-profile.sh`. Source the helper and call `octo_load_profile`:

```bash
source "${HOME}/.claude-octopus/plugin/scripts/lib/load-octo-profile.sh"
octo_load_profile
# Now $OCTO_PROFILE_PATH and $OCTO_PROFILE_STATUS are set
echo "$(octo_profile_status_line)"
```

`$OCTO_PROFILE_STATUS` is one of:
- `loaded` — profile found and parses as valid YAML, no placeholders detected
- `template` — profile found but contains `<PLACEHOLDER` strings (user hasn't filled it in)
- `malformed` — profile found but doesn't parse
- `missing` — no profile found in any search path

Search order (first valid match wins, defined in the helper):

1. `$OCTOPUS_KW_PROFILE` env var
2. `./.octopus/profile.yaml` (project-local)
3. `$HOME/.claude-octopus/config/profile.yaml` (**canonical** user-global)
4. `$HOME/.config/octopus/profile.yaml` (XDG-style user-global, supported for XDG-preferring users)
5. Plugin-installed profiles (`~/.claude/plugins/cache/*/eki-kw/profiles/default.yaml`, etc.)

**Canonical recommended location:** `$HOME/.claude-octopus/config/profile.yaml`. This is also the higher-precedence path — a stale XDG profile cannot mask the canonical one.

**Malformed-profile behavior:** if the highest-priority match is malformed (doesn't parse as YAML), the loader STOPS with `OCTO_PROFILE_STATUS=malformed` and `OCTO_PROFILE_PATH` set to the malformed file. It does NOT silently fall through to a lower-priority profile — that would mask a broken active profile and use the wrong rules.

A loaded profile is expected to have this shape (use bare keys you find; missing keys default to empty):

```yaml
audiences:
  customer:
    tone: "strictly neutral; objective engineering record"
    banned_phrases: ["allegedly", "demonstrably fails"]
  supplier:
    tone: "declarative; let data carry the position"
    banned_phrases: ["bad faith", "fabricated"]
banned_terms:
  - "<internal-project-code-1>"
  - "<internal-infra-name-1>"
internal_codenames:
  - "<codename-1>"
  - "<codename-2>"
banned_wording:
  - { pattern: "—", reason: "no em-dash (project style)" }
  - { pattern: "~", reason: "use 'approximately' instead of tilde" }
  - { pattern: "significantly\\s", reason: "use 'materially' unless statistical test stated" }
```

**lestephen.20 (G3):** If no profile loads, the skill **refuses to produce a "defensible" verdict** — the verdict ceiling is `BLOCKED-INFRASTRUCTURE` with the reason `"profile not loaded; defensibility requires project-specific banned terms / audience matrix"`. This is hardened to match the MANDATORY COMPLIANCE rule at line 66 ("Declaring the document defensible when the project profile was not loaded" is prohibited).

Defensibility without project rules is theater — generic Pass C cannot enforce EKI's or your project's specific banned terms, internal codenames, or audience tone matrix. Surface the missing profile clearly so the user installs one and re-runs.

## Steps

### STEP 1: Load profile + preflight

- Load profile per the order above
- Confirm `doc_path` exists, is non-empty, and is text (markdown)
- Confirm `source_data_dir` exists if provided

### STEP 2: Provider check (MANDATORY)

@skills/blocks/provider-check.md

Defensibility requires at least 2 distinct external providers (Codex AND Gemini, or Codex AND a third). If only one external provider is available, the skill proceeds but downgrades the verdict ceiling to `BLOCKED-INFRASTRUCTURE` — defensibility cannot be claimed from a single-provider review.

### STEP 3: Pass A — Independent recompute of quantitative claims

If `source_data_dir` is not provided: skip Pass A, record it as `SKIPPED — no source_data_dir`, and continue. Pass A skipping does not block the gate if the document makes no quantitative claims (the synthesis will note this).

Otherwise:

1. Extract quantitative claims from the document. Use this prompt against the host (Claude):

   > Read `$doc_path` and list every numerical or quantitative claim that names a specific value (percentage, count, ratio, range, threshold crossing, time window with magnitude). For each, output: `{quote, computed_value, suspected_source_files}`. Skip stylistic numbers (section numbers, page counts, figure numbers).

2. For each extracted claim, invoke `skill-lib-independent-recompute` with:
   - `claim` = the verbatim quote
   - `source_paths` = the suspected source files (intersect with files actually present in `source_data_dir`)
   - `methodology_hint` = the surrounding paragraph or methodology section from the doc
   - `providers` = `["codex", "gemini"]` (skip Claude — it's reviewing its own author's voice)

3. Collect per-claim verdicts. Pass A overall verdict:
   - `PASS` — every claim either `CORROBORATED` or `CLAIM MATCHES SOME`
   - `WARN` — at least one `CLAIM MATCHES SOME` with diverging methodology
   - `FAIL` — any `CLAIM UNSUPPORTED` or `PROVIDERS DISAGREE` on a non-trivial claim

### STEP 4: Pass B — Methodology audit

Invoke `skill-lib-multi-review-doc` with:

- `doc_path` = the document
- `reviewers`:
  - `{agent_type: codex, perspective_label: methodology-chain, prompt: "For every conclusion in this document, walk backward through the stated evidence and assumptions. Flag: (a) any conclusion that uses a step not present in the document, (b) any assumption stated only in a methodology section but not re-stated where it is load-bearing for the conclusion, (c) any methodology choice that the document does not justify (e.g., 'we used X' without 'because Y'). Quote specific sentences."}`
  - `{agent_type: gemini, perspective_label: assumption-registry, prompt: "List every assumption the document makes — both stated and implicit. For each, flag whether it is in the Limitations / Assumptions section, in a footnote, or only inferable from context. Flag any implicit assumption that, if challenged, would change a conclusion."}`
- `synthesis_prompt` = `"Identify the strongest methodology objections a hostile expert would raise. For each, name (i) the conclusion at risk and (ii) the minimum change to the document that would close the gap."`

Pass B verdict from synthesis:
- `PASS` — synthesis identifies only nice-to-have improvements
- `WARN` — synthesis identifies missing assumption statements or methodology gaps but the conclusions still stand on the evidence
- `FAIL` — synthesis identifies a load-bearing step not supported by the document

### STEP 5: Pass C — Internal-terms scrub + banned-phrase lint

This is two sub-passes: deterministic lint (cheap, runs first) and multi-LLM wording check (runs only on what lint missed).

#### Pass C.1 — Deterministic lint

For each entry in profile `banned_terms` + `internal_codenames` + `banned_wording.pattern`:

```bash
matches=$(grep -nE "<pattern>" "$doc_path" || true)
[[ -n "$matches" ]] && echo "VIOLATION: $pattern in:" && echo "$matches"
```

Any match here is a hard fail — automatic terms that must not appear.

#### Pass C.2 — Multi-LLM wording check

Invoke `skill-lib-multi-review-doc` with:

- `doc_path` = the document
- `reviewers`:
  - `{agent_type: gemini, perspective_label: leakage-scan, prompt: "Read this document as if you were a competitor or opposing party. Identify any wording that reveals: (a) internal strategy or motivation, (b) the existence of an internal investigation, (c) a relationship or dispute that is not the subject of this document, (d) tooling/infrastructure that should not be disclosed (database names, repo paths, internal service names). Quote specific sentences. If the audience is '<audience>', additionally flag wording that violates the audience-specific tone rules from the profile: <audience tone>."}`
  - `{agent_type: claude, perspective_label: tone-consistency, prompt: "Check the document for tone consistency under the audience='<audience>' rules. Specifically: flag any sentence that allegations bad faith, characterizes motive, or makes claims beyond what the data demonstrates — these are tone violations for the '<audience>' audience. Quote each."}`
- `synthesis_prompt` = `"Combine the lint hits, the leakage-scan findings, and the tone-consistency findings into a single list of wording that must change before send."`

Pass C verdict:
- `PASS` — no lint hits, no leakage findings, no tone violations
- `WARN` — lint clean, only minor wording suggestions
- `FAIL` — any lint hit OR any leakage finding OR any clear tone violation

### STEP 6: Synthesis

Aggregate the three pass verdicts into the overall gate:

| Pass A | Pass B | Pass C | Gate |
|---|---|---|---|
| PASS | PASS | PASS | **DEFENSIBLE — READY TO SEND** |
| PASS | PASS | WARN | **DEFENSIBLE WITH MINOR EDITS** (list wording changes) |
| PASS | WARN | PASS | **DEFENSIBLE WITH ASSUMPTION CLARIFICATIONS** (list what to add) |
| any FAIL | * | * | **BLOCKED** (do not send; list what must change) |
| * | any FAIL | * | **BLOCKED** |
| * | * | any FAIL | **BLOCKED** |
| any SKIPPED (other than Pass A with no claims) | * | * | **BLOCKED-INFRASTRUCTURE** |
| **no profile loaded** | * | * | **BLOCKED-INFRASTRUCTURE** (G3: harden — defensibility requires project profile) |

**lestephen.20 (F1):** `OUTPUT_DIR` for the report below is **the directory returned by the library skills you invoked** (extract `$(dirname "$SYNTHESIS_PATH")` from the `SYNTHESIS:` line each library skill prints). Do NOT reuse the `$OUTPUT_DIR` name from inside the library's bash — it's not in scope here.

```bash
OUTPUT_DIR=$(dirname "$PASS_B_SYNTHESIS_PATH")  # or any of the pass synthesis paths
```

Write the synthesis to `$OUTPUT_DIR/defensibility-report.md`:

```markdown
# Defensibility Pass — Report

**Document:** <doc_path>
**Audience:** <audience>
**Profile used:** <profile_path or "none — generic fallback">
**Run at:** <timestamp>

## Gate: <verdict>

<2-3 sentence summary>

## Pass A — Independent recompute: <verdict>

<per-claim verdicts table; link to per-claim synthesis files>

## Pass B — Methodology audit: <verdict>

<top objections from synthesis; link to full synthesis file>

## Pass C — Internal-terms scrub: <verdict>

### Lint hits (Pass C.1)
<deterministic violations>

### Wording findings (Pass C.2)
<from synthesis; link to full file>

## What to change before send

<numbered, actionable; only items that block or warn; not nice-to-haves>
```

### STEP 7: Return to user

```
GATE:    <DEFENSIBLE | DEFENSIBLE WITH MINOR EDITS | DEFENSIBLE WITH ASSUMPTION CLARIFICATIONS | BLOCKED | BLOCKED-INFRASTRUCTURE>
REPORT:  <path-to-defensibility-report.md>
TOP CHANGES:
  1. <first must-change item>
  2. <second>
  ...
```

If `BLOCKED`, do not present a recommendation to send. The user should remediate and re-run.

## Failure modes

| Failure | Skill behavior |
|---|---|
| Only Claude available (no Codex, no Gemini) | Refuse with `❌ Defensibility requires multi-LLM diversity. Install codex + gemini CLIs and re-run.` |
| Profile fails to load AND no fallback found | **Verdict: `BLOCKED-INFRASTRUCTURE`** (lestephen.20 G3: hardened). Surface the missing profile location + the user's setup instruction (`ln -s <yourrepo>/profile.yaml ~/.claude-octopus/config/profile.yaml`). Do NOT proceed with generic prompts — defensibility without project rules is theater. |
| Document has no quantitative claims | Pass A reports `SKIPPED — no claims`, does not block |
| `source_data_dir` missing | Pass A reports `SKIPPED — no source_data_dir`, verdict ceiling drops to `BLOCKED-INFRASTRUCTURE` if document had claims |

## Integration notes

This skill is the canonical pre-send gate for external documents. Consumer plugins (e.g., `eki-kw:do` router) should dispatch here when the user says "is this ready to send" or "review before I send to <party>".

The skill leans entirely on the three library skills (`skill-lib-multi-review-doc`, `skill-lib-multi-inspect-figure` — figures are NOT inspected by this skill; that's a separate call — and `skill-lib-independent-recompute`). If you need to extend defensibility with a new pass (e.g., citation-validity check), add a new library skill rather than inlining the dispatch logic here.
