---
name: skill-critique
description: "Adversarial multi-LLM review of any user-specified scope — code, docs, designs, technology choices, approaches. Different attack angles per provider."
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Critique

Multi-LLM adversarial review of an arbitrary user-specified scope. Each provider attacks from a different angle; synthesis surfaces the top objections by severity × confidence.

This skill fills a gap between the other review skills:

| Skill | What it does | Doesn't do |
|---|---|---|
| `/octo:review` | Finds code defects, security issues, perf problems in git changes | Doesn't challenge the *approach* — assumes the implementation is the right one to defect-hunt |
| `/octo:argument-strength` | Red-team a prose draft for structural weakness | Code, designs, technology choices, approaches |
| `/octo:debate` | Pick between N pre-specified options | Open-ended "is this choice defensible at all?" |
| `/octo:defensibility-pass` | External-send hostile-review gate (3 coordinated passes) | Internal design decisions; lighter-weight than the full gate |
| **`/octo:critique` (this)** | Adversarial challenge of any user-specified scope from N angles | — |

## When to use this skill

- You made a technology choice and want to know what a hostile expert would tear apart
- You wrote code or a design doc and want challenge — not "find my typos" but "is this the right approach?"
- You're about to merge a PR and want one adversarial pass beyond `/octo:review`'s defect-hunt
- You're evaluating someone else's design and want multi-perspective stress test
- You have a decision summary and want to know what assumptions it depends on that could break

## When NOT to use this skill

- The scope is purely prose-argument structure → use `/octo:argument-strength` (faster, more targeted to that lens)
- The scope is code AND you want defect detection rather than design challenge → use `/octo:review` (catches what defect-hunting is supposed to catch)
- The scope is "pick between N options" → use `/octo:debate` (different shape; commits to one)
- The scope is going outside your org and you want the full gate (recompute + methodology + scrub) → use `/octo:defensibility-pass`

## ⚠️ MANDATORY: Visual Indicators Protocol

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-LLM Critique`

Then output the provider banner:

```
🐙 Critique: <one-line description of what's being critiqued>

Attack angles:
🔴 Codex CLI - <angle 1>
🟡 Gemini CLI - <angle 2>
🔵 Claude - <angle 3 + synthesis>
```

Pick angles per the **Angle selection** section below.

## ⚠️ MANDATORY COMPLIANCE — DO NOT SKIP

You are PROHIBITED from:

- Running a single-provider critique pass under the banner of "multi-LLM"
- Softening provider critiques in synthesis to spare the author — the value is exactly the harsh feedback
- Substituting Agent subagents (Claude under the hood) for the genuine multi-provider dispatch
- Declaring "the work looks solid" when at least one reviewer raised a HIGH-severity objection
- Treating an absence of objections as a strong result — usually means a reviewer read sympathetically; re-prompt with sharper adversarial frame if all three came back clean

If fewer than 2 distinct providers are available, refuse:
> `❌ Critique requires multi-LLM diversity. Need at least 2 of: codex, gemini, claude (host).`

## Input contract

| Input | Description |
|---|---|
| `target` | What to critique. Free-form. Examples: a file path, a directory, a branch/PR reference, a verbatim design choice ("we picked Redis over Memcached for session storage"), a doc + the conclusion-under-test |
| `scope_type` (optional, auto-detected) | One of: `code-change`, `design-doc`, `technology-choice`, `approach`, `architecture`, `decision`, `prose`. The skill auto-detects; user can override. |
| `angles` (optional) | Specific attack angles to use. Defaults are picked per scope_type — see below |
| `audience` (optional) | Threads through to provider prompts. Default: `internal-skeptic`. Other: `customer`, `regulator`, `expert-peer`, `competitor` |
| `severity_threshold` (optional) | Only surface objections at this severity or higher. Default: MEDIUM |

## Angle selection (defaults per scope type)

The skill picks 3 adversarial angles per critique. Different scope types get different default angles. The user can override with explicit `angles=...`.

| Scope type | Default angles |
|---|---|
| `code-change` (git diff, PR, file edit) | (1) Technical correctness + edge cases, (2) Architectural fit + alternatives, (3) Maintainability + 2am-debugging |
| `design-doc` (architecture proposal, ADR, RFC) | (1) Conceptual coherence + load-bearing assumptions, (2) Alternatives-they-rejected + why those would have caught things this doesn't, (3) Operational/real-world failure modes |
| `technology-choice` (library, framework, infra pick) | (1) Cost (financial + cognitive + operational), (2) Fit for actual use case + exit cost when wrong, (3) Alternatives + opportunity cost |
| `approach` ("we plan to do X") | (1) Assumption-challenge (what does this depend on being true?), (2) What-if-X-changes (what dimension is most likely to invalidate it?), (3) Simplest-alternative (could a dumber thing work and what would we lose?) |
| `architecture` (component layout, system design) | (1) Coupling/cohesion + change-cost, (2) Failure modes + blast radius, (3) Evolution path — what does this look like in 2 years? |
| `decision` (committed-to but not implemented) | (1) Reversibility + sunk cost, (2) Evidence quality — what's known vs assumed?, (3) Stakeholder impact + dissent |
| `prose` (memo, brief, position doc) | Defer to `/octo:argument-strength` — that's its specialty. Refuse and route. |

If `scope_type` cannot be auto-detected (target is ambiguous), the skill asks ONE clarifying question via AskUserQuestion before dispatching.

## Steps

### STEP 1: Provider check (MANDATORY)

@skills/blocks/provider-check.md

### STEP 2: Identify scope_type + extract content

Auto-detection rules (apply in order; first match wins):

1. Target looks like `PR #N` or `pr#N` → fetch via `gh pr diff <N>` → `scope_type=code-change`
2. Target is a path ending in `.md/.rst/.txt` AND is in a `docs/` / `adr/` / `rfc/` style location → `scope_type=design-doc`
3. Target is a path AND `git diff` against base reveals changes → `scope_type=code-change`
4. Target is a path AND is a plain markdown that reads as a memo → `scope_type=prose` → refuse and route to `/octo:argument-strength`
5. Target is text like "we decided to use X" / "I'm planning to do Y" → `scope_type=approach` or `decision`
6. Target names a specific library/framework/database → `scope_type=technology-choice`
7. Otherwise → ask user via AskUserQuestion

Extract content:
- Code change: `git diff <base>...<target>` or `gh pr diff <N>` — limit to 200KB; if larger, ask user to narrow
- Design doc: full file contents
- Approach/decision/technology-choice: capture the user's verbatim description plus any cited source files

### STEP 3: Pick reviewer angles + assign providers

From the angles table, pick the default 3 for the detected scope_type (or honor user-supplied `angles=...`). Assign providers:

- Codex → angle 1 (technical/concrete)
- Gemini → angle 2 (structural/ecosystem)
- Claude (host) → angle 3 (audience-reception / synthesis-adjacent)

If only 2 providers are available, drop angle 3 and proceed with 2. Mark the synthesis as "2-provider" so caller knows.

### STEP 4: Dispatch via `skill-lib-multi-review-doc`

Construct a `reviewers` list and a `synthesis_prompt`, then invoke `skill-lib-multi-review-doc`:

- `doc_path` = a constructed bundle: scope description + extracted content + the detected scope_type label
- `reviewers`: one entry per angle. Each `prompt` follows this template:

  ```
  You are critiquing the following <scope_type> from a hostile-but-fair adversarial perspective.

  ATTACK ANGLE: <angle name>
  ANGLE FRAME: <expanded description of what to look for under this angle>

  AUDIENCE for this critique output: <audience>

  Your job:
  1. State the strongest objections under this angle. Quote specific elements of the scope content.
  2. Score each objection: HIGH (changes the recommendation), MEDIUM (needs a follow-up), LOW (background noise).
  3. For each HIGH or MEDIUM objection, propose the minimum mitigation OR state explicitly that the only mitigation is to abandon/redesign.
  4. NEVER sugar-coat. If the scope has no objections under this angle, say so explicitly — but check yourself first ("did I read this too sympathetically?").

  Format each objection as:
  OBJECTION <n>: <one-line headline>
    Quote: <specific element from scope>
    Why it matters: <1-2 sentences>
    Severity: HIGH | MEDIUM | LOW
    Mitigation: <minimum change to absorb, or "redesign required">
  ```

- `synthesis_prompt`:

  ```
  Synthesize the three reviewer outputs into:

  1. Objections raised by 2+ providers (high-confidence) — list with max-severity score across providers
  2. HIGH-severity SINGLE-provider objections (lower confidence but possibly load-bearing) — separately listed
  3. Top 3 actions the author should take, ordered by severity × confidence
  4. Overall verdict: STRONG | DEFENSIBLE WITH FIXES | LOAD-BEARING WEAKNESSES | NEEDS REDESIGN
  ```

### STEP 5: Validation gate

`skill-lib-multi-review-doc` enforces its own validation gate (per-reviewer output files exist + non-empty). If it returns failure, surface it — do not synthesize partial results.

### STEP 6: Present results

Open with the one-line verdict + top 3 actions. Then surface:

- Scope critiqued (one line, verbatim from user)
- Detected scope_type (with note if user-overridden)
- Audience simulated
- Providers run / skipped
- Top 3 actions, each with: offending quote + severity + suggested mitigation + which providers agreed
- Path to full synthesis file (from the library skill)
- Path to per-provider raw outputs (preserved by the library skill)

Cap the page-1 verdict at ~30 lines. The full synthesis is in the file for users who want detail.

### STEP 7: Save outputs

Write a one-page summary alongside the library skill's outputs:

- `$OUTPUT_DIR/critique-report.md` — the page-1 verdict
- `$OUTPUT_DIR/synthesis.md` — library skill synthesis (objection table)
- `$OUTPUT_DIR/per-provider/*.md` — raw per-provider critiques

## Failure modes

| Failure | Skill behavior |
|---|---|
| Only host (Claude) available | Refuse — single-provider critique isn't adversarial |
| Scope target is unreadable / unresolvable | Surface the error, ask user to clarify |
| Auto-detection picks `prose` | Refuse and route to `/octo:argument-strength` — that skill is the right shape |
| Scope > 200KB content | Ask user to narrow before dispatching (cost + provider context limits) |
| All providers come back with no objections | Re-dispatch one provider with sharper adversarial frame; if still nothing, surface as `provider read sympathetically` warning |

## Integration

- Called directly via `/octo:critique <target>`
- Called from agentic flows that want to challenge a consensus or design before committing
- Pair with `/octo:debate` when the critique surfaces multiple competing approaches — critique identifies the weakness, debate resolves between alternatives
- Pair with `/octo:defensibility-pass` for external-bound documents — critique first (cheap, fast, sentence-level), then defensibility-pass (slower, full gate)

## Iterative use

After applying the suggested mitigations, re-run `/octo:critique` to see if new weak points surfaced. This is normal for substantive changes — the first critique catches the obvious, the second catches what the obvious-fix introduced.

If a critique cycle goes more than 3 rounds without convergence, that's a signal the scope itself may be unsound and a `/octo:debate` to consider alternatives may be the better move.
