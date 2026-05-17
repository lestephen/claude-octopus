---
command: critique
description: "Adversarial multi-LLM review of any user-specified scope — code, docs, designs, technology choices, approaches"
skill: skill-critique
argument-hint: '<target> [--scope-type code-change|design-doc|technology-choice|approach|architecture|decision] [--audience internal-skeptic|customer|expert-peer|competitor] [--angles list,of,angles]'
---

# Critique

Multi-LLM adversarial review of an arbitrary user-specified scope. Each provider attacks from a different angle; synthesis surfaces the top objections by severity × confidence.

This is the catch-all adversarial-review entry point. Use it when:

- You want challenge of a technology/design/approach choice (not defect-hunting code)
- The scope isn't a fit for `/octo:review` (which is code-defect-focused) or `/octo:argument-strength` (which is prose-only)
- You want one adversarial pass beyond what `/octo:review` would catch

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:critique`, you MUST execute the multi-LLM critique workflow defined in `skill-critique`.** You are PROHIBITED from:

- ❌ Doing a single-provider critique pass under the banner of "multi-LLM"
- ❌ Softening provider critiques in synthesis to spare the author
- ❌ Substituting Agent subagents (Claude under the hood) for the genuine multi-provider dispatch
- ❌ Declaring "looks solid" when at least one reviewer raised a HIGH-severity objection
- ❌ Skipping the validation gate

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST dispatch to at least 2 distinct external providers via `skill-lib-multi-review-doc`. You are PROHIBITED from:**

- ❌ Running with only Claude
- ❌ Re-writing reviewer prompts to be less adversarial than the skill specifies

If fewer than 2 providers are available, refuse with the message in the skill.

---

### Execution

1. Follow the `skill-critique` instructions (Steps 1-7) exactly.
2. STEP 1: Provider check.
3. STEP 2: Auto-detect scope_type from the user's target (file path, PR ref, design doc, technology choice, approach description). If ambiguous, ask ONE clarifying question via AskUserQuestion before dispatching. If detected scope is `prose`, refuse and route to `/octo:argument-strength`.
4. STEP 3: Pick 3 reviewer angles per scope type from the skill's angle table. Assign Codex / Gemini / Claude to the angles.
5. STEP 4: Invoke `skill-lib-multi-review-doc` with the reviewer list + synthesis prompt.
6. STEP 5: Validation gate (library skill enforces).
7. STEP 6: Present page-1 verdict (≤30 lines) + top 3 actions + link to full synthesis.
8. STEP 7: Save outputs.

### Post-Completion

After presenting the verdict, ask one of:

- If `STRONG`: "No revisions needed for critique. Want me to escalate to `/octo:defensibility-pass` if this is going external?"
- If `DEFENSIBLE WITH FIXES`: "Apply the listed mitigations, or walk through them one at a time?"
- If `LOAD-BEARING WEAKNESSES`: "These are the changes that matter most. Want me to draft revised versions, or revise manually first?"
- If `NEEDS REDESIGN`: "The critique suggests the current approach is unsound. Want to run `/octo:debate` to consider alternatives, or pause to think?"

DO NOT end the session silently — always offer the next step.
