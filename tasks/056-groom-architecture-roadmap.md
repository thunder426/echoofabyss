---
id: "056"
title: Groom the architecture roadmap into tasks
status: backlog
area: architecture
priority: normal
started:
finished:
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
