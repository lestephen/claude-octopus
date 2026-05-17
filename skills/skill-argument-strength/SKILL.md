---
name: skill-argument-strength
description: "Adversarial prose review — three providers red-team your draft from different angles to find what would land if a hostile reader pushed back"
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Argument Strength

Multi-LLM adversarial review of a written argument. Each provider takes a different angle of attack on the draft; the synthesis surfaces which objections actually land and what to change to absorb them.

This is `/octo:debate` for prose. Where `/octo:debate` resolves a decision among collaborators, this skill stress-tests a draft for survival in the wild — when a coworker, opposing party, or skeptical reviewer reads it and pushes back, which of their pushbacks will the document not absorb?

## When to use this skill

- A coworker or you have drafted a memo, position document, or analysis, and someone has said (or might say) "I'm worried we're laying out our argument in a weak way"
- Before sharing a draft with a reviewer who is known to push back hard
- After a first internal review where reviewers said "looks fine" but you suspect they read it sympathetically
- Before sending a document where you cannot revise after delivery (regulatory filing, formal letter, published paper)

## When NOT to use this skill

- The document is going outside the org and the question is whether it's defensible (use `skill-defensibility-pass` — broader and stricter)
- You need to verify quantitative claims (use `skill-lib-independent-recompute`)
- You need to decide between multiple options (use `/octo:debate`)
- The draft is incomplete — argument strength testing only works on argument-complete drafts

## What this skill is testing

It tests argument *strength*, which is different from argument *correctness*. A correct argument can still be weak:

| Correct | Strong |
|---|---|
| Every claim is true | Claims survive the strongest reasonable attack |
| Evidence is sound | Evidence is presented in the order that pre-empts the natural objection |
| Methodology is valid | Methodology choices are justified, not just stated |
| Logic chains hold | Reader cannot easily construct a competing chain from the same evidence |

The skill surfaces the gap between correct-and-weak and correct-and-strong.

## ⚠️ MANDATORY: Visual Indicators Protocol

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Argument Strength Review`

Then output the provider banner:

```
✅ Deliver Phase (KM): Adversarial prose review

Red teams:
🔴 Codex CLI - Technical / logical attack
🟡 Gemini CLI - Structural / framing attack
🔵 Claude - Audience-reception attack + synthesis
```

If a provider is unavailable, mark it `(unavailable - skipping)`. Continue with whichever is available. **Refuse** if fewer than 2 providers are available — a single red-team is the author talking to themselves in a different voice.

## ⚠️ MANDATORY COMPLIANCE — DO NOT SKIP

You are PROHIBITED from:

- Doing a single-provider "I'll critique your draft" pass
- Softening provider critiques in synthesis to spare the author's feelings — the value of this skill is exactly the harsh feedback
- Substituting Agent subagents (which use Claude under the hood) for the genuine multi-provider call
- Treating an absence of objections as a strong result; absence usually means the provider read sympathetically and you should re-prompt with a sharper adversarial frame

## Input contract

| Input | Description |
|---|---|
| `doc_path` | The draft to stress-test |
| `audience` (optional) | Who will receive this. Default: `internal-skeptic`. Other values: `customer`, `supplier`, `regulator`, `counterparty`, `expert-peer`, `public` |
| `claim_to_protect` (optional) | One-sentence summary of the conclusion the document is meant to land. If omitted, providers infer it from the document and report back what they think the claim is — this itself surfaces argument-structure problems (the author and the readers disagree on what the document concludes) |
| `known_counterarguments` (optional) | Counterarguments you already know the audience holds — providers use these as starting points and then go further |

## Steps

### STEP 1: Provider check (MANDATORY)

@skills/blocks/provider-check.md

Require at least 2 distinct providers. Refuse with `❌ Argument-strength review requires multi-LLM diversity. Need at least 2 of: codex, gemini, claude (host).` if not satisfied.

### STEP 2: Determine the claim under defense

If the caller provided `claim_to_protect`, use it verbatim.

Otherwise, dispatch a quick host-only pass to extract the apparent thesis:

> Read `$doc_path`. In one sentence, state the single most important conclusion the document is asking the reader to accept. If you cannot identify a single most-important conclusion, list the top 2-3.

Surface the extracted claim to the user before continuing — if the author meant a different conclusion than the document conveys, the review will be against the wrong claim. Ask whether to proceed.

### STEP 3: Invoke `skill-lib-multi-review-doc` with adversarial reviewers

Invoke `skill-lib-multi-review-doc` with:

- `doc_path` = the draft
- `reviewers`:

  - `{agent_type: codex, perspective_label: technical-attack, prompt: |
      You are reading this document as a skeptical technical expert who disagrees with the conclusion.

      The author wants to land this claim: <claim_to_protect>

      <if known_counterarguments was provided: "Known starting points the audience holds:\n<known_counterarguments>\n\nGo further than these.">

      Your job: identify the strongest TECHNICAL objections that would land on this document. For each:
      1. State the objection in the voice of the hostile reader (1-2 sentences).
      2. Quote the specific sentence(s) in the document that opens the door to this objection.
      3. Score the objection: HIGH (likely to derail acceptance), MEDIUM (will require addressing in a follow-up), LOW (audible but probably ignorable).
      4. Suggest the minimum revision that would absorb the objection without conceding the claim.

      Focus on: missing evidence, weak inferential steps, alternative explanations the document does not rule out, methodology choices that look arbitrary, places where the document protests too much.
    }`

  - `{agent_type: gemini, perspective_label: structural-attack, prompt: |
      You are reading this document as a skeptical reader who is looking for places where the argument STRUCTURE leaks.

      The author wants to land this claim: <claim_to_protect>

      Your job: identify the strongest STRUCTURAL objections. For each:
      1. State the objection (the reader's complaint about how the argument is laid out).
      2. Quote the structural element at fault — could be a section order, a heading that gives away the position, a topic sentence that overstates, evidence that comes after the claim it should support, a methodology section that buries an assumption that should be load-bearing.
      3. Score: HIGH / MEDIUM / LOW (likelihood that this structural choice causes the reader to lose trust before reaching the conclusion).
      4. Suggest the minimum reordering / re-titling / re-paragraphing that would close the gap.

      Focus on: argument ordering, claim-evidence proximity, headings that telegraph or undercut, sentence-level hedging that signals weakness, places where the document tells the reader what to think rather than showing.
    }`

  - `{agent_type: claude, perspective_label: audience-reception, prompt: |
      You are reading this document as the specific audience: <audience>.

      The author wants you to accept this claim: <claim_to_protect>

      Your job: describe how this specific audience would receive the document on first read. For each significant reaction:
      1. Quote what triggered the reaction.
      2. State the reaction in the audience's voice (1-2 sentences) — both positive and negative.
      3. Score: HIGH (reaction changes whether they accept the claim), MEDIUM (reaction is recorded but doesn't change disposition), LOW (background noise).
      4. For NEGATIVE reactions, suggest the minimum revision that would prevent the reaction without diluting the claim.

      Be specific to the audience type. A "supplier" reads differently than a "regulator" who reads differently than an "internal-skeptic". Frame the reactions in their voice and incentives, not in a neutral reviewer voice.
    }`

- `synthesis_prompt` = |
    Across the three red-team reviews, identify the objections that ANY two providers raised against the same sentence or paragraph — those are the high-confidence weak points. For each:

    1. Quote the offending sentence/paragraph
    2. Summarize the objection in one sentence
    3. Score the objection severity (max severity reported across providers)
    4. List the minimum revisions suggested by the providers; if they conflict, surface the conflict and let the user pick

    Then list the high-severity SINGLE-PROVIDER objections separately — these are lower-confidence but might still be load-bearing (different providers attack from different angles, so a single-provider HIGH may still matter).

    End with: TOP 3 REVISIONS THE DOCUMENT NEEDS BEFORE SHARE, prioritized by severity-by-confidence.

### STEP 4: Validation gate (MANDATORY)

`skill-lib-multi-review-doc` enforces its own validation gate. If it returns failure, surface the failure here — do not attempt a degraded synthesis.

### STEP 5: Present results

Open with a one-line verdict:

| Top-3 revisions all LOW | "ARGUMENT IS STRONG — minor polish optional" |
| Top-3 includes any MEDIUM | "ARGUMENT IS DEFENSIBLE — apply listed revisions to strengthen" |
| Top-3 includes any HIGH | "ARGUMENT HAS LOAD-BEARING WEAKNESSES — revise before sharing with <audience>" |

Then surface:

- Claim that was tested (verbatim)
- Audience that was simulated
- Providers run / skipped
- Top 3 revisions, each with the offending quote + severity + suggested revision + which providers agreed
- Link to full synthesis file
- Link to individual per-provider files (for the author who wants to see the raw attacks)

### STEP 6: Save outputs

**lestephen.20 (F1):** Extract `OUTPUT_DIR` from the library skill's returned `SYNTHESIS:` line; do NOT reuse an `$OUTPUT_DIR` variable from your own bash (the library's `OUTPUT_DIR` is local to its bash blocks and is not in scope here).

```bash
OUTPUT_DIR=$(dirname "$SYNTHESIS_PATH")  # parse SYNTHESIS_PATH out of the library skill's STDOUT
```

Then write the page-1 verdict to that directory:

- `$OUTPUT_DIR/argument-strength-report.md` — the page-1 verdict the user reads
- `$OUTPUT_DIR/synthesis.md` — the library-skill synthesis (objection table; written by the library)
- `$OUTPUT_DIR/<agent>-<task_id>.md` — raw per-provider red-team output (written by the library)

## Failure modes

| Failure | Skill behavior |
|---|---|
| Only host (Claude) available | Refuse — single-provider red-team isn't adversarial |
| Provider returned only sympathetic feedback (no objections) | Re-dispatch that provider once with a sharper adversarial frame; if still no objections, surface as `provider read sympathetically; treat as missing perspective` |
| Provider extracted a different `claim_to_protect` than the user expected | Pause and confirm with user before continuing — wrong claim test is worse than no test |

## Integration notes

- This skill is **separate from** `skill-defensibility-pass`. Defensibility tests whether the document survives a hostile expert on the technical record; argument-strength tests whether the prose survives a skeptical reader on the argument structure. A document can pass one and fail the other.
- Use this skill iteratively: after applying revisions, re-run to see if new weak points surfaced.
- Pair with `skill-defensibility-pass` for external-bound documents: argument-strength first (cheap, fast, sentence-level), then defensibility-pass (slower, full gate).
