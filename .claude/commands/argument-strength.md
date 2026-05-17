---
command: argument-strength
description: "Adversarial prose review — three providers red-team your draft from different angles to find what would land if a hostile reader pushed back"
skill: skill-argument-strength
---

# Argument Strength

Multi-LLM adversarial review of a written argument. Each provider takes a different angle of attack on the draft; synthesis surfaces which objections land and what to change to absorb them.

This is `/octo:debate` for prose. Where `debate` resolves a decision among collaborators, `argument-strength` stress-tests a draft for survival when shared with a skeptical reader.

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/argument-strength`, you MUST execute the multi-LLM red-team workflow defined in `skill-argument-strength`.** You are PROHIBITED from:

- ❌ Doing a single-provider critique pass
- ❌ Softening provider critiques in synthesis to spare the author's feelings — the value of this skill is exactly the harsh feedback
- ❌ Substituting Agent subagents (which use Claude under the hood) for the genuine multi-provider call
- ❌ Treating absence of objections as a strong result; absence usually means the provider read sympathetically and you should re-prompt with a sharper adversarial frame

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST dispatch to at least 2 distinct external providers via `skill-lib-multi-review-doc`. You are PROHIBITED from:**

- ❌ Running with only Claude
- ❌ Skipping the validation gate
- ❌ Re-writing the reviewer prompts to be less adversarial than the skill specifies

If fewer than 2 providers are available, refuse with `❌ Argument-strength review requires multi-LLM diversity. Need at least 2 of: codex, gemini, claude (host).`

---

### Execution

1. Follow the `skill-argument-strength` instructions (Steps 1-6) exactly.
2. STEP 1: Provider check.
3. STEP 2: Determine the claim under defense. If user did not supply `claim_to_protect`, extract it via a host-only pass and confirm with the user before continuing — wrong claim test is worse than no test.
4. STEP 3: Invoke `skill-lib-multi-review-doc` with the three adversarial reviewers (technical-attack, structural-attack, audience-reception).
5. STEP 4: Validation gate — library skill enforces this; surface its failure if it occurs.
6. STEP 5: Present results with one-line verdict + top 3 revisions + offending quotes + suggested rewrites.
7. STEP 6: Save outputs.

### Post-Completion

After presenting the verdict, ask one of:

- If `ARGUMENT IS STRONG`: "No revisions needed for argument strength. Want me to escalate to `/defensibility` if this is going outside the org, or `/eki-kw:audience` if you want a tone scrub for a specific audience?"
- If `DEFENSIBLE`: "Apply the listed revisions, or do you want me to walk through them one at a time?"
- If `LOAD-BEARING WEAKNESSES`: "These are the changes that matter most. Want me to make the edits in a copy, or do you want to revise manually first?"

DO NOT end the session silently — always offer the next step.
