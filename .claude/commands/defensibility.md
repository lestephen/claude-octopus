---
command: defensibility
description: "Hostile-review gate before a document goes external — independent recompute, methodology audit, internal-terms scrub"
skill: skill-defensibility-pass
argument-hint: '[--audience customer|supplier|regulator|counterparty|public] [--source-data-dir <dir>] [--profile <path>] <doc-path>'
---

# Defensibility Pass

Publish-ready gate for documents going outside your organization. Three coordinated multi-LLM passes — independent recompute, methodology audit, internal-terms scrub — produce a pass/fail with what must change before send.

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/defensibility`, you MUST execute the three-pass workflow defined in `skill-defensibility-pass`.** You are PROHIBITED from:

- ❌ Skipping any of the three passes
- ❌ Substituting "I read it carefully and didn't see issues" for the multi-LLM library-skill calls
- ❌ Treating the synthesis as PASS when any individual pass returned FAIL or UNSUPPORTED
- ❌ Declaring the document defensible when the project profile (banned terms, internal codenames) was not loaded

If a library skill failure prevents a pass from running, the overall verdict defaults to `BLOCKED` with the reason recorded — surface the failure to the user; do not synthesize around it.

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST dispatch to multiple external providers (Codex + Gemini at minimum) via the library skills (`skill-lib-multi-review-doc`, `skill-lib-independent-recompute`). You are PROHIBITED from:**

- ❌ Running the passes with only Claude
- ❌ Using a single Agent subagent instead of multi-provider dispatch
- ❌ Skipping the validation gates that confirm per-reviewer outputs were actually written

The whole point of `defensibility-pass` is that no single reviewer (human or LLM) catches what a hostile expert would — multi-provider diversity is the mechanism.

---

### Execution

1. Follow the `skill-defensibility-pass` instructions (Steps 1-7) exactly.
2. STEP 1: Load profile + preflight (validate doc_path, optional source_data_dir).
3. STEP 2: Provider check — require at least 2 distinct external providers.
4. STEP 3: Pass A (independent recompute) — invoke `skill-lib-independent-recompute` per quantitative claim.
5. STEP 4: Pass B (methodology audit) — invoke `skill-lib-multi-review-doc` with codex + gemini reviewers.
6. STEP 5: Pass C (internal-terms scrub) — deterministic lint + `skill-lib-multi-review-doc` with gemini + claude.
7. STEP 6: Synthesize gate verdict per the verdict-mapping table.
8. STEP 7: Return GATE + report path + top changes.

### Post-Completion

After producing the gate verdict, ask the user one of:

- If `DEFENSIBLE`: "Ready to send. Want me to also run `/eki-kw:audience` with the final target audience as a final scrub, or is this sufficient?"
- If `DEFENSIBLE WITH MINOR EDITS`: "Want me to apply the listed wording changes (one-pass edit) before re-running the gate?"
- If `BLOCKED`: "Top blockers are listed above. Want me to walk through them one at a time, or pause for you to address them manually?"

DO NOT end the session silently after presenting the verdict — always offer the next step.
