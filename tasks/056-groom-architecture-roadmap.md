---
id: "056"
title: Groom the architecture roadmap into tasks
status: done
area: architecture
priority: normal
started: 2026-09-30
finished: 2026-10-01
---

## Description

Review `design/refactors/ARCHITECTURE_ROADMAP.md` (the longer-term structural items from the 2026-09-25 architecture review, workstreams A–J) and turn it into concrete, sized backlog tasks. The doc is **ungroomed**: most of its evidence comes from review agents and has not been re-checked by hand. Only items marked **(verified)** were.

Whoever picks this up should run it as a **recurring grooming task**. Each pass grooms part of the doc, logs the result in the doc's section 13 (grooming log), and leaves this task open (or opens a fresh grooming task) until every workstream is filed or dropped.

When to run a pass:
- after tasks 047–055 land (they change some of the evidence: leaks, statics, side bugs, save format),
- before designing the next hero or faction (workstreams C and D decide how cheap that is),
- whenever the roadmap is more than about a month stale.

## Procedure (per pass)

1. **Re-verify.** For each item being groomed, check the evidence against the current code: the quoted code, the counts and whether the problem still exists. Mark it **(verified <date>)** in the doc, or strike it with a note if it's gone.
2. **Owner decisions.** Bring the relevant questions from the doc's section 12 (Q1–Q8) to the owner. Record the answers in the doc. Don't file tasks whose scope depends on an unanswered question; file the audit or decision task instead (e.g. A0).
3. **Split.** Turn each candidate task (A0, A1, …, J6) that's ready into a backlog task with `/task-start`, or write the file directly with `status: backlog` if not starting it now. Each task needs:
   - problem, evidence (file:line, quoted code), consequence,
   - proposed fix steps,
   - verification: `tools/run_checks.sh` green, and Parity byte-identical or a recorded BalanceSimBatch delta,
   - dependencies on other task ids.
   Keep the doc's size labels (S/M/L) as a guide; split anything L into phases, like LIVE_SIM_UNIFICATION_PLAN did.
4. **Straight-to-task bugs.** Items the doc flags as probable bugs should become their own small tasks immediately once verified:
   - E1: rune placement VFX hits the wrong slot; `on_state_void_marks_changed` pushes live enemy HP.
   - I7: the deathless-save label stays ≤0; the champion log message is hardcoded.
   - Section A's enemy-side turn-start effects, if A0 confirms them as bugs.
   - The `PhaseTransition` trap/env cleanup concern, if task 050 didn't already settle it.
5. **Update the doc.** In each groomed item write "→ task NNN", add a row to the grooming log (date, items re-verified, tasks created, items dropped), and bump the doc's status line.
6. **Keep ARCHITECTURE.md honest.** Invariant #2 ("symmetric handlers") overstates the current code. Once A0 exists, either add a caveat pointing to the audit or tighten the wording.

## Suggested first pass

- Re-verify and file **D1** (content-lint test), **C1** (BranchData + `active_pools()`), **A0** (symmetry audit), **I2** (statics per state) and **J1** (test auto-discovery + auto-teardown). They're cheap, have few dependencies and make everything after them safer.
- Ask the owner Q1, Q2, Q5 and Q7.

## Done when

Every item in workstreams A–J is either linked to a task, explicitly dropped with a reason, or deferred behind a named owner decision. The doc's grooming log records it.

## Work log

- 2026-09-25: opened alongside `design/refactors/ARCHITECTURE_ROADMAP.md`. Short-term fixes from the same review are tasks 047–055.
- 2026-09-30 → 2026-10-01: pass 1, covering every workstream (A–J).
  - Re-verified each workstream at `404b51c` with 12 unit agents (A and D split in two). Adversarial re-checks finished for A-paths and C; the other 10 hit the session limit, so the task writers re-checked every line they cite instead.
  - The owner answered Q1–Q8, and QN1–QN6 raised by the verification (roadmap §12). Q6 was revised after evidence: delete CARD_LIBRARY.md.
  - Filed 87 backlog tasks, 057–143, from one plan (ids, merges, dependencies; no cycles). A mechanical check of every file passed: frontmatter, sections, dependency references. Two consistency-critic agents (resumed after a pause at the owner's request) then cross-checked every file: 60 in-place fixes (overlapping scope narrowed, cross-references, conflicts with 092/108, missing Related lines, a wrong probe expectation). Their open items are in roadmap §12 under "Open questions and unowned findings after pass 1". Filed one more reachable bug from them: task 143 (per-copy cost discounts shown but not charged; Squire of the Order → Abyssal Knight). Corrected QN6: the act bosses are fights 3, 6, 9 and 15, not 12.
  - ARCHITECTURE.md: invariants #2–#3 now record the owner's symmetry ruling plus a "not yet true" caveat pointing at task 082 (procedure step 6). The CombatHandlers / HardcodedEffects rows no longer claim full symmetry, and the D6 file-split note now points at roadmap B5 (deferred).
  - Roadmap: status, a task map per section, evidence corrections, new §11 order, QN table, grooming-log row. §11's gate no longer cites "Parity byte-identical" (Parity stores no golden digests); the neutrality check is the seeded BalanceSimBatch fingerprint diff.
- 2026-10-01: closed.

## Summary

Pass 1 groomed all of ARCHITECTURE_ROADMAP.md (A–J) into 87 backlog tasks, 057–143, re-verified at `404b51c`. Every candidate is now filed, merged (C3/D5/D8 → 102, C4 → 100, G6 → 104, …), deferred with a reason (A7 integer Side enum, B5 CommandProcessor, H5b theme consolidation) or dropped (H6c; D6 replaced by deleting CARD_LIBRARY.md). The owner's decisions shaped the tasks: PvP planned and no mechanic one-sided (A1–A3 in full plus 4 per-side mechanic tasks), AI look-ahead planned (049 → 130, 114 → 134 → 129 move up), champions as a spec table (13/15 fit), CardDatabase.gd as the card source of truth.
Follow-ups: start with the straight-to-task bugs (057–078 and 143; high: 057, 058, 062–064, 066, 070, 072, 074, 077, 143). The open owner questions are listed in roadmap §12. Re-run a grooming pass for the deferred items once 047–055 land. 082 (A0) has one unowned row (merging the three spell-cast paths).
