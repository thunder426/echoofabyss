---
id: "079"
title: Delete CARD_LIBRARY.md; CardDatabase.gd is the card source of truth
status: done
area: content
priority: normal
started: 2026-10-02
finished: 2026-10-02
---

## Description

From the 2026-09-25 architecture review, roadmap item D6, replaced by owner decision Q6 (`design/refactors/ARCHITECTURE_ROADMAP.md` §D). Groomed in task 056 pass 1; re-verified 2026-10-01 at `404b51c`. Line numbers are from that commit.

### Two files claim to be the source of truth

- `CLAUDE.md:38`: "1. Define card data in `CARD_LIBRARY.md` (source of truth)."
- `design/master_doc/CARD_LIBRARY.md:5`: "This file is the **single source of truth** for all card data."
- `design/master_doc/ARCHITECTURE.md:340` (invariant #10): "**Card data lives in CardDatabase.gd.** Single source of truth. Never duplicate card stats elsewhere."

### CARD_LIBRARY.md is stale and unread

- It has one commit, `3fac2c6` (Version 0.592, 2026-04-28, the design-folder import). Its header says "Last updated: 2026-04-25" (:3).
- It is missing 25 of CardDatabase's 191 card ids (24 names):
  - all 20 Korrath cards;
  - the 4 Korrath tokens: `order_footman`, `rank_and_file_h`, `rank_and_file_d`, `iron_footman` (CardDatabase.gd:34-40);
  - Avatar of the Abyss (`champion_abyss_sovereign`).
  - `grep -c 'Avatar\|Korrath\|Abyssal Knight\|Order Footman' design/master_doc/CARD_LIBRARY.md` → 0.
- Where both have a card, the stats agree (86 minions compared, 0 ATK/HP differences). The only data mismatch: §1 (:36-38) puts Senior Void Imp, Runic Void Imp and Void Imp Wizard in `abyss_core`, but `_card_pools` (CardDatabase.gd:3459) has no entry for them. They are talent-granted.
- Its texts lag the code. Task 068 (champion text) and task 065 (Energy Conversion, CARD_LIBRARY.md:270) both skip this file because this task deletes it.
- Nothing reads it. No tool, test or lint names it: `git grep CARD_LIBRARY -- tools debug combat cards shared` finds nothing.

### What points at it

- `CLAUDE.md:11` lists it as a master design doc.
- `CLAUDE.md:38`, step 1 of "Adding New Cards" (quoted above).
- `design/master_doc/CARD_DESCRIPTION_STYLE.md:3`: "All card descriptions in `CARD_LIBRARY.md` and `CardDatabase.gd` must follow these rules:".
- `design/CARD_POOL_ARCHITECTORE.md:135`, `:139`, `:152-155`: five "(CARD_LIBRARY.md § N)" pointers in §6 "Current Pool Inventory (as of v0.6)".
- `design/refactors/ARCHITECTURE_ROADMAP.md`: §C's "adding a 4th hero" file list (:116), §D's problem bullet (:148), direction 7 (:164), the D6 candidate (:167), the §D Decisions line (:169) and the Q6 row in §12.
- Checked and clean: DESIGN_DOCUMENT.md, ARCHITECTURE.md, design/TESTING.md, `.claude/commands/*`, `.claude/skills/*`. Old task files mention it too; they are history and stay as they are.

### What is worth keeping

The owner named the token notes (§10, :386-401). Checked against the code, they are partly wrong:
- **Void Spark.** The library says Soul Anchor summons a "300/300 Void Spark". The relic text and the code say 200/300: RelicDatabase.gd:89 "Summon a 200/300 Void Spark and grant it Guard.", RelicEffects.gd:53 `state._summon_token("void_spark", "player", 200, 300)`. The log line at RelicEffects.gd:60 still says "300/300". Soul Rune scales with the rune-aura multiplier, as the library says: HardcodedEffects.gd:241-242 `100 * mult`. Flesh Rune summons a 300/300 spark (CardDatabase.gd:1102).
- **Void Demon.** The base is 200/200 (CardDatabase.gd:30) and every summon overrides it: Void Spawning and Bound Offering 100/100 (:490-491, :1295-1296), Void Summoning 300/300, or 400/400 with a friendly Human (:1573-1574), and the Demon Ascendant ritual 500/500 (:2406). The library lists only the last two.
- **Lesser Demon.** Summoned by the Seris Fiend Offering talent when a Grafted Fiend is sacrificed and 2 Flesh is paid (CombatState.gd:739-742).
- **Forged Demon.** Summoned by the Soul Forge counter (`_summon_forged_demon`, CombatState.gd:711-723). With the Abyssal Forge talent it gets one random aura, or all three for 5 Flesh (:700-707).
- "Void Imp is not a separate token; summon effects reuse `void_imp`" (:398) is still true. The Guardian Spirit note (:400) is history and can go.

The rest of the file needs no move:
- The strict sacrifice rule (§5e notes, :200-206: sacrifice fires ON LEAVE and ON_*_MINION_SACRIFICED, never ON DEATH) is already in code comments: SacrificeSystem.gd:44-46 and CombatState.gd:905.
- The "Spell Graveyard Notes" (:235-244) describe the old layout (`CombatScene._player_graveyard`, `SimState`). Today the graveyard is `CombatState.player_graveyard` / `enemy_graveyard` (CombatState.gd:1395, :1400). They are obsolete.
- The per-card notes in the pool sections (:134, :161, :180, :225) describe what each card's code does.

Two stale comments sit next to the token table: CardDatabase.gd:2080 says the tokens are "Defined compactly via _TOKEN_DEFS at the bottom of this file", and :2394 says "below". `_TOKEN_DEFS` is at the top (:28). Only the append loop is at the bottom (:3649-3651).

## Decision (owner, 2026-10-01)

Q6: "CardDatabase.gd is the source of truth; delete CARD_LIBRARY.md." Move the few useful token notes into comments next to the token definitions in CardDatabase.gd, and fix the references in CLAUDE.md, CARD_DESCRIPTION_STYLE.md and CARD_POOL_ARCHITECTORE.md. Design intent stays in the hero and faction design docs; browsing is the Collection's job (Q5). **No sync test.** Card text that disagrees with the code inside CardDatabase is task 068's job.

## Proposed fix

1. **Token notes.** Above `_TOKEN_DEFS` (its header comment is CardDatabase.gd:21-27), add a short comment block per token: who summons it and at what stats. Write it from the code, using the corrected facts above, not the library text.
   - Prefer naming the stat overrides, which aren't obvious from the table, over an exhaustive list of summoners. `git grep '"void_spark"'` finds the summoners.
   - Keep the "Void Imp isn't a token; summons reuse `void_imp`" line.
   - Fix the two stale location comments at :2080 and :2394.
   - Optional, one line: fix the Soul Anchor log text at RelicEffects.gd:60 ("300/300" → "200/300"). It is log-only.
2. **Delete** `design/master_doc/CARD_LIBRARY.md` (`git rm`).
3. **CLAUDE.md:**
   - :11: drop `CARD_LIBRARY.md` from the master design docs list.
   - :38, step 1 of "Adding New Cards": "Design the card in its hero or faction design doc (e.g. `design/SERIS_HERO_DESIGN.md`). `cards/data/CardDatabase.gd` is the source of truth for card data; there is no separate card table." Step 2 stays as it is.
   - :12: add `design/KORRATH_HERO_DESIGN` to the feature design docs. It is the only hero design doc missing, and step 1 now sends readers to those docs. Renaming it to `.md` is optional. If you rename it, update its 7 comment references (`git grep -n KORRATH_HERO_DESIGN`).
4. **CARD_DESCRIPTION_STYLE.md:3:** "All card descriptions in `cards/data/CardDatabase.gd` (and the design-doc drafts they come from) must follow these rules:".
5. **CARD_POOL_ARCHITECTORE.md §6:**
   - Drop the five "(CARD_LIBRARY.md § N)" suffixes (:135, :139, :152-155).
   - Add one line under the §6 heading: pool membership lives in `_card_pools` in `cards/data/CardDatabase.gd`.
   - Don't hand-copy card lists into it. The inventory is stale beyond the pointers: `seris_core`, `seris_common`, `korrath_core`, `korrath_common` and the three Seris branch pools are still marked "to be designed", but they all have cards in `_card_pools`. Removing those markers is enough. Task 100 (roadmap C1) owns the pool model.
6. **Roadmap:** the §C :116 file list, §D :148, :164, :167 and :169, and the Q6 row should say the file is deleted and CardDatabase.gd is the truth. Task 056's grooming pass may already have rewritten some of these. `grep -n CARD_LIBRARY design/refactors/ARCHITECTURE_ROADMAP.md` at task start shows what's left.
7. ARCHITECTURE.md needs no change: invariant #10 already says this.

## Verification

- `git grep -n CARD_LIBRARY -- . ':!tasks'` lists only the roadmap's record of the decision (the Q6 row and the grooming log), if anything.
- `git grep -n '§ [0-9]' design/CARD_POOL_ARCHITECTORE.md` shows no dangling section pointers.
- The new token comments match the code. Check each stat named in the comment against its `_summon_token` call or SUMMON step.
- `tools/run_checks.sh` green. The only code edits are comments in CardDatabase.gd (plus the optional log string), so the import and lint steps are the ones that matter.
- Behaviour-neutral: the seeded balance fingerprint (`BalanceSimBatch -- --act 1 --runs 200 --seed 7`, before and after) diffs empty (design/TESTING.md "Refactor / extraction work"). One act is enough: no rule changes.

## Related

- Related: task 068 — fixes champion card text and tooltips in code, and skips CARD_LIBRARY.md §11 because this task deletes it.
- Related: task 065 — fixes Energy Conversion and skips CARD_LIBRARY.md:270 for the same reason.
- Related: task 100 (roadmap C1) — the Collection shows every hero's cards (Q5b). That is the browsing view that replaces the library. C1 also owns the pool model that CARD_POOL_ARCHITECTORE.md describes.
- Related: task 104 (roadmap D1) — content checks run against CardDatabase only. Per Q6 there is no doc-sync check.
- Related: task 102 (roadmap C3) — splits CardDatabase per pool. The token comments move with `_TOKEN_DEFS`.
- Related: task 105 (roadmap D2), task 106 (roadmap D3) — also edit CLAUDE.md's "Adding New Cards" list (105: steps are validated at load; 106: drop DAMAGE_ANY from step 6, :43). Whichever lands later rebases.

## Work log

- 2026-10-01: filed by task 056 (grooming pass 1) from roadmap item D6, replaced by owner decision Q6. Re-checked at `404b51c`.
  - Every reference was confirmed by grep.
  - The library's token notes were checked against the code. Soul Anchor is 200/300, not 300/300. Void Demon has two more summoners at 100/100.
  - The rules notes (sacrifice vs death, spell graveyard) were checked. Both are either already in code comments or obsolete, so nothing beyond the token notes moves.
- 2026-10-02: implemented.
  - Token notes above `_TOKEN_DEFS`, written from the code at `06a2689`: Void Spark 100/100 from most summoners, Soul Rune 100/100 × the rune-aura multiplier, Flesh Rune 300/300, Soul Anchor 200/300 + Guard; Void Demon never at its 200/200 base (Void Spawning / Bound Offering 100/100, Void Summoning 300/300 or 400/400 with a Human, Demon Ascendant and, found while checking, the enemy `ritual_sacrifice` passive 500/500); Lesser Demon (Fiend Offering) and Forged Demon (Soul Forge, Abyssal Forge auras); Void Imp isn't a token. Fixed the two stale location comments and the Soul Anchor log text (300/300 → 200/300).
  - `git rm` CARD_LIBRARY.md. CLAUDE.md: dropped it from the master docs, step 1 of "Adding New Cards" points at the hero / faction design docs, and `design/KORRATH_HERO_DESIGN` joins the feature docs (not renamed). CARD_DESCRIPTION_STYLE.md:3 reworded. CARD_POOL_ARCHITECTORE.md §6: a pointer to `_card_pools`, the five `CARD_LIBRARY.md § N` suffixes dropped, "to be designed" removed where `_card_pools` has cards (korrath_core / common, seris_core / common, the three Seris branch pools, named by id), kept on korrath_runic_knight and korrath_abyssal_breaker. Roadmap lines annotated as resolved rather than rewritten.
  - Verification: `git grep CARD_LIBRARY -- . ':!tasks'` hits only the roadmap's and the implementation order's records; no dangling `§` pointers. Gate green (1125 tests, LiveSmoke OK, Parity 24/24); Act 1 fingerprint identical to `06a2689`.
- 2026-10-02: closed.

## Summary

Deleted CARD_LIBRARY.md; CardDatabase.gd is the only card source of truth, as ARCHITECTURE.md invariant #10 already said. The library's useful token notes, corrected against the code, now sit above `_TOKEN_DEFS`; CLAUDE.md, CARD_DESCRIPTION_STYLE.md, CARD_POOL_ARCHITECTORE.md and the roadmap no longer point at it. Behaviour-neutral (comments plus one log string).
