# Implementation Order — backlog tasks 047–143

**Status:** proposed order, 2026-10-01. Tick the boxes as tasks land, and re-run the ordering after any grooming pass that adds or drops tasks.
**Scope:** the 96 open backlog tasks: 047–055 (from the 2026-09-25 architecture review) and 057–143 (filed by grooming pass 1, task 056). 046 and 056 are done.
**Source:** three independent orderings were merged into this one: player-facing risk and value; the critical path to the owner's goals (PvP symmetry, AI look-ahead); and grouping by hot file to avoid churn. It was checked by script: every open task appears once, every "Depends on" lands earlier, 052 follows 047, and 054 sits next to 055.
**Companions:** [ARCHITECTURE_ROADMAP.md](ARCHITECTURE_ROADMAP.md) (the why behind each workstream, §12 owner decisions and open questions) and the task files in [`tasks/`](../../tasks/).

---

## How to work through it

1. **Phases are ordered, and so are the tickets inside a phase.** You can run the parallel lanes below side by side; everything else goes in order.
2. **One behaviour change per commit.** A fix that changes gameplay records its BalanceSimBatch delta in its task summary. A behaviour-neutral change must leave the seeded fingerprint unchanged: run `BalanceSimBatch -- --act <N> --runs 200 --seed 7` before and after, and the diff must be empty (design/TESTING.md, "Refactor / extraction work"). Parity has no stored digests, so it is not a neutrality check.
3. **Chain the seeded runs.** One commit's "after" run is the next commit's "before" run. BalanceSimBatch defaults to Acts 1–2; ask for Acts 3–4 explicitly whenever a task touches fights 7–15.
4. **Retune checkpoint after P3.** P1–P3 move the balance in both directions: 066 and 064 make enemies weaker, while 062, 063, 067 and 072 make them stronger. Retune once, as its own commit, before P4. Every later behaviour-neutral task compares against that post-retune fingerprint. 129 steps 9–10, 131 phase b and 086 phases 4–5 change behaviour again, so they may need a second, smaller retune.
5. **`tools/run_checks.sh` stays green on every commit**, as CLAUDE.md requires.
6. **Back up first:**
   - copy the `user://encounter_decks.json` file now; it is the only copy of the enemy decks until 047 lands;
   - back up `user://` before 052's save migration runs on this machine.

## At a glance

| Phase | Theme | Tickets, in order |
|---|---|---|
| P1 | Lock the baseline and clear dead weight | 080 → 047 → 079 → 081 → 054 → 055 → 073 |
| P2 | Combat bugs every run hits (attack, death, champions) | 057 → 059 → 060 → 061 → 066 → 067 |
| P3 | Rules-path bugs, Act 4 boss AI, symmetry audit | 050 → 058 → 143 → 064 → 062 → 063 → 065 → 072 → 082 |
| P4 | Run, save and shop bugs (meta lane) | 074 → 075 → 124 → 128 → 052 → 077 → 078 → 076 |
| P5 | Display bugs: the view follows the journal (E1, E7) | 069 → 071 → 068 → 070 → 113 |
| P6 | Free each fight and widen what Parity sees | 132 → 049 → 137 → 141 → 051 → 133 → 135 |
| P7 | Presenter guard, release gate, lint hardening, AI probes | 048 → 053 → 140 → 139 → 120 |
| P8 | Content validation and ratchets | 104 → 106 → 105 → 088 → 087 → 111 |
| P9 | Look-ahead engine core (F1, F2, I6, I2, I1, I3) | 114 → 115 → 116 → 134 → 130 → 129 → 131 |
| P10 | Presentation reads only the journal (E2, E3, E6, C5, H5, H6) | 109 → 110 → 112 → 136 → 103 → 126 → 127 |
| P11 | Hero, pool and run data model (C, H) | 100 → 101 → 138 → 123 → 102 → 125 |
| P12 | Side model foundation, with B pre-work (B1, B2a, A1, A2, A6) | 094 → 095 → 083 → 084 → 085 |
| P13 | Side-neutral triggers and per-side mechanics (PvP-ready engine) | 089 → 086 → 090 → 091 → 097 → 098 → 092 → 093 → 096 |
| P14 | AI consolidation and the extensibility tail (G, B7, D4, D7, J6) | 117 → 118 → 119 → 121 → 122 → 099 → 108 → 107 → 142 |

The high-priority combat bugs land in P2–P3, and the high-priority meta and display bugs (074, 077, 070) in P4–P5. Every high-priority task lands by ticket 59 (129), roughly 54% of the estimated effort. The engine is PvP-ready at ticket 87 (end of P13). The last AI look-ahead prerequisite, 122, lands at ticket 92.

---

## Phases

### P1 — Lock the baseline and clear dead weight

**Goal.** Commit the enemy decks so every later balance delta can be reproduced. Delete dead code and docs that later fixes would otherwise have to edit, and correct the sim's player bots before any gameplay delta is measured.

**Tickets:** 080 → 049 (pulled forward from P6) → 047 → 079 → 081 → 054 → 055 → 073

1. [x] **[080](../../tasks/080-delete-unreachable-mapscene-dead-gamemanager-resource.md)** Delete the unreachable MapScene and the dead GameManager resource fields; fix ARCHITECTURE.md's scene flow · *normal, S*  
   It goes first because it removes two of 047's EncounterDecks readers (MapScene.gd:63/:136) and drops MapScene's ACT_SIZES/BOSS_INDICES reads from 124's site list. Keep last_boss_unlocks, which 078 reads.
2. [x] **[047](../../tasks/047-enemy-decks-into-repo.md)** Move enemy decks from user:// into the repo · *high, M*  
   Afterwards, capture the seeded Acts 1-4 fingerprint (BalanceSimBatch --runs 200 --seed 7).
3. [x] **[079](../../tasks/079-delete-card-library-md-carddatabase-gd.md)** Delete CARD_LIBRARY.md; CardDatabase.gd is the card source of truth · *normal, S*  
   Removes the CLAUDE.md pointer that would send 065 and 068 to the stale file.
4. [x] **[081](../../tasks/081-delete-unreachable-passive-content-spirit-conscription.md)** Delete unreachable passive content (spirit_conscription, champion_duel, dead passive arm, stale AI hardcoded-id check) · *low, S*  
   Hard prerequisite of 104. It removes the dead arm, tooltip entries and header that 062, 068 and 072 would otherwise edit, and four probes 137 would otherwise move.
5. [x] **[054](../../tasks/054-handler-log-type-constants.md)** Fix CombatHandlers log-type constants (off by one vs CombatLog.LogType) · *normal, S*  
   Same session as 055.
6. [x] **[055](../../tasks/055-rules-code-gamemanager-leak-stale-comments.md)** Remove the GameManager read from CombatHandlers; fix stale Phase-4 comments · *normal, S*  
   Hard prerequisite of 086, 089 and 103.
7. [ ] **[073](../../tasks/073-player-sim-bots-side-blind-reserved.md)** Player sim bots — side-blind reserved champion slot, and a Void Execution rule that checks a tag no card has · *normal, S*  
   Two commits. Commit 1, the Void Execution tag fix, is neutral. Commit 2, the side-blind reserved slot, moves the swarm, voidbolt_burst and death_circle rows in every act; record that delta.

> **Notes.** 049 was pulled in after 080 (2026-10-02). Every sim fight leaked its CombatState: one `--act 2 --runs 200` reached 19 GB in 87 s, and four acts in parallel ran the dev Mac out of memory. After 049 an act peaks at ~78 MB. 049's fingerprint is identical except a corrected S.Corr `Clog` extra in Act 1, so the P1 chain starts from the post-049 runs. Everything except 073 is behaviour-neutral. 047's step 5 changes the variants that live play, Parity and LiveSmoke pick; BalanceSimBatch is unaffected because it runs every variant. Record which variants they now pick so a later Parity failure isn't misread. The fingerprint taken after 073 is the baseline for P2. Until 047 lands, keep a manual copy of the user:// deck file, because it is the only copy.


### P2 — Combat bugs every run hits (attack, death, champions)

**Goal.** Fix the bugs in the resolve_minion_attack / death path and the champion handlers. They are reachable in fights 1 and 2 of every run, and later refactors (114, 129, 131, 095) rebuild this code. One behaviour change per commit.

**Tickets:** 057 → 059 → 060 → 061 → 066 → 067

8. [ ] **[057](../../tasks/057-minion-that-dies-mid-attack-dies.md)** A minion that dies mid-attack dies twice (on-death effects and death triggers run again) · *high, S*  
   Delta Acts 1-4, mostly the F2 Seris rows. It adds the is_on_board guard that 110 and 131 build on, and settles the lines 114 later wraps.
9. [ ] **[059](../../tasks/059-matron-flesh-gains-flesh-own-death.md)** Matron of Flesh gains Flesh for its own death and for friendly deaths during its attack · *normal, S*  
   Same VTI trace as 057. Hard prerequisite of 129. Expect an empty fingerprint, since no sim deck holds Matron.
10. [ ] **[060](../../tasks/060-attacks-crit-flag-leaks-onto-damage.md)** An attack's crit flag leaks onto every damage event nested inside it (crit popups on non-crit hits) · *normal, S*  
   Journal payloads only, so neutral. Hard prerequisite of 129; it lands before 115 so the popups are right when 115 arrives.
11. [ ] **[061](../../tasks/061-deathless-save-leaves-minions-hp-label.md)** Deathless save leaves the minion's HP label at ≤0 · *normal, S*  
   Neutral. Hard prerequisite of 135 and 136; it lands before 097 moves _try_save_from_death.
12. [ ] **[066](../../tasks/066-champion-auras-keep-working-after-champion.md)** Champion auras keep working after the champion dies (F1 Rogue Imp Pack, F3 Imp Matriarch, F4 Abyss Cultist Patrol) · *high, S*  
   Delta Acts 1-2 (F1, F3, F4); the player's win rate rises. Hard prerequisite of 095.
13. [ ] **[067](../../tasks/067-f15-avatar-abyss-card-counter-resets.md)** F15 Avatar of the Abyss: its card counter resets to 0 at the phase 1 → 2 transition, against its documented intent · *normal, S*  
   Delta --act 4. Hard prerequisite of 095; it lands before 125, whose probe it feeds, and before 068's Avatar tooltip.

> **Notes.** Chain the seeded runs: one commit's 'after' run is the next commit's 'before' run. Owner defaults to confirm before starting: for 057, a defender or attacker that leaves the board during PRE means the attack is spent (no strike, no counter); for 067, the counter carries over into phase 2 (a grooming ruling, not an owner decision).


### P3 — Rules-path bugs, Act 4 boss AI, symmetry audit

**Goal.** Fix the remaining reachable rules bugs in EffectResolver / CombatState: the trap and environment API, the one-sided steps and the cost charging. Then the Act 4 AI. Close with the symmetry audit, so its enemy-content guard is in place before the owner retunes.

**Tickets:** 050 → 058 → 143 → 064 → 062 → 063 → 065 → 072 → 082

14. [ ] **[050](../../tasks/050-effectresolver-side-bugs.md)** Route trap / environment removal through one engine API (F15 leak, unjournaled destroy, owner lookup) · *high, M*  
   Fixes the F15 rune/ritual leak, the unjournaled environment destroy, Dark Covenant buffs that are never removed, and Cyclone destroying its own copy. Delta --act 4.
15. [ ] **[058](../../tasks/058-imp-talisman-three-latent-sites-bypass.md)** Imp Talisman (and three latent sites) bypass _card_for: Vael gets an un-boosted Void Imp · *high, S*  
   Right after 050, because both edit _korrath_place_random_rune and RelicEffects. Delta Acts 2-4 (Vael rows with Imp Talisman). Its lint lands as L21.
16. [ ] **[143](../../tasks/143-per-copy-cost-deltas-ignored-minions-spells.md)** Per-copy cost discounts are shown but not charged for minions and spells (Squire of the Order → Abyssal Knight) · *high, S*  
   Reachable with Korrath's Squire of the Order → Abyssal Knight. Expect an empty fingerprint because there is no Korrath preset, so the probe is the only cover. Must land before 085.
17. [ ] **[064](../../tasks/064-runic-attunement-player-talent-also-doubles.md)** Runic Attunement (player talent) also doubles the enemy's rune auras · *high, S*  
   Delta Act 2+ (death_circle; enemy runes in f4_b and f5_a). Fixed before 083 and 090 move the multiplier.
18. [ ] **[062](../../tasks/062-enemy-void-spawner-abyssal-tide-passives.md)** Enemy Void Spawner and Abyssal Tide passives never fire (legacy on-death board passives are player-only) · *high, S*  
   Rebases on 054 and 081. Delta Acts 1-2 (F3 f3_b, F6). Hard prerequisite of 089.
19. [ ] **[063](../../tasks/063-enemy-flux-siphon-does-nothing-convert.md)** Enemy Flux Siphon does nothing: CONVERT_RESOURCE runs only for the player · *high, S*  
   Delta Act 1 (f2_c). Hard prerequisite of 092.
20. [ ] **[065](../../tasks/065-energy-conversion-converts-essence-instead-up.md)** Energy Conversion converts all Essence instead of 'up to 3'; its hover preview shows no gain · *normal, S*  
   Same CONVERT_RESOURCE arm as 063: same session, separate commit. Expect an empty fingerprint (player-only).
21. [ ] **[072](../../tasks/072-f14-f15-boss-ai-aoe-spells.md)** F12/F14/F15 AI — spark spells held unless the player has 2+ minions, and F15's lethal check ignores Sovereign's Decree's spark cost · *high, S*  
   Two commits: --act 4 first, then Acts 1-4 for the shared lethal helper. It doesn't need 051: use agent.state.spark_cost_of(...) as the task says.
22. [ ] **[082](../../tasks/082-side-symmetry-audit-verdict-table-player.md)** Side-symmetry audit: verdict table for every player-only rules path, plus an enemy-content guard test · *high, S*  
   Landing it after 062-064 means its exception list starts empty.

> **Notes.** After 082, the owner retunes in one commit with its own delta. 066 and 064 made enemies weaker; 062, 063, 067 and 072 made them stronger. 082's guard catches any retune deck edit that pulls in a player-only path. The post-retune Acts 1-4 fingerprint is the reference for every behaviour-neutral task after this. BalanceSimBatch defaults to Acts 1-2, so request Acts 3-4 explicitly for 050, 058 and 072. Owner default to confirm for 065: overflow is kept as temporary excess. Open question with no task (next to 050 and 057): should 'destroy' (kill_minion, e.g. Death Trap) bypass Deathless?


### P4 — Run, save and shop bugs (meta lane)

**Goal.** Stop runs losing relics, talent points, shards, saved decks and unlocks, and bring the shop in line with QN2, QN3 and QN6. No combat, sim or AI files change, so the fingerprint can't move.

**Tickets:** 074 → 075 → 124 → 128 → 052 → 077 → 078 → 076

23. [ ] **[074](../../tasks/074-shop-buy-buttons-take-last-offers.md)** Shop: Buy buttons take the last offer's state after a purchase; Expand Core Unit at the 6-copy limit takes 3 shards and does nothing · *high, S*
24. [ ] **[075](../../tasks/075-shop-core-unit-services-give-seris.md)** Shop core-unit services give Seris and Korrath Vael's Void Imp · *normal, S*
25. [ ] **[124](../../tasks/124-derive-act-sizes-fight-count-boss.md)** Derive act sizes, fight count and boss indices from EncounterTable; every act boss shows the BOSS label · *normal, S*  
   Before 128 and 078, which use boss_indices(), and before 123.
26. [ ] **[128](../../tasks/128-shop-rules-follow-reward-system-design.md)** Shop rules follow REWARD_SYSTEM_DESIGN: weighted services, no Second Wind in the first shop, Max HP costs 4, first shop from run position · *normal, S*  
   Meta behaviour change; list the player-facing changes in its summary.
27. [ ] **[052](../../tasks/052-save-robustness.md)** Make saves versioned, atomic and complete · *high, L*  
   Fixes void_shards lost on every quit, the SavedDecks wipe and lost unlocks. Creates RunState and the MetaTests layer.
28. [ ] **[077](../../tasks/077-continuing-saved-run-skips-pending-card.md)** Continuing a saved run skips a pending card reward, shop or relic reward (and loses the act's talent point) · *high, S*  
   After 052, so resume_scene goes into RunState and the round-trip probe uses 052's save path. After 128, so a resumed shop isn't treated as the first.
29. [ ] **[078](../../tasks/078-show-cards-boss-kill-permanently-unlocked.md)** Show the cards a boss kill permanently unlocked · *normal, S*
30. [ ] **[076](../../tasks/076-talent-undo-last-choice-after-abyss.md)** Talent 'Undo Last Choice' after Abyss Convergence keeps its 2 Echo Runes; re-picking adds 2 more · *normal, S*  
   Before 100, which may delete the echo_rune gate.

> **Notes.** Back up the user:// saves before 052's v2 migration runs on the dev machine. Owner questions to answer before this phase: resuming a run re-rolls shop and reward offers for free (052/077; the combat seed raises the same question); the Act 1 boss can never unlock a card, and Nyx'ael's unlock isn't implemented (078 shows only what is unlocked).


### P5 — Display bugs: the view follows the journal (E1, E7)

**Goal.** Fix the panels that show post-turn state during playback (QN5: keep input responsive, make the UI correct). All behaviour-neutral.

**Tickets:** 069 → 071 → 068 → 070 → 113

31. [ ] **[069](../../tasks/069-max-mana-max-essence-growth-outside.md)** Max-mana / max-essence growth outside the turn flow is not journaled (pip bar, resource labels and end-turn buttons keep the old maximum) · *normal, S*  
   Hard prerequisite of 071 and 109; lands before 083 moves the max fields.
32. [ ] **[071](../../tasks/071-enemy-hero-panel-renders-view-never.md)** Enemy hero panel renders the view, never live state (HP, Void Marks, essence, mana, hand) · *normal, S*
33. [ ] **[068](../../tasks/068-champion-card-text-tooltips-match-code.md)** Champion card text and tooltips match the code; drop the Void Ritualist aura; add the missing Act 3–4 tooltips · *normal, S*  
   After 067, 079 and 081; right after 071, since both edit EnemyHeroPanel and the PHASE_TRANSITION branch.
34. [ ] **[070](../../tasks/070-rune-placement-vfx-trap-panels-follow.md)** Rune placement VFX and trap panels follow the journal (payload slot + trap snapshot) · *high, S*
35. [ ] **[113](../../tasks/113-target-highlights-agree-engine-when-view.md)** Target highlights agree with the engine when the view lags (input during playback) · *low, S*  
   Right after 070: once the trap panels render the view, Cyclone's lookup from panel index to live trap can pick the wrong trap.

> **Notes.** A non-empty fingerprint diff here means a bug. Owner question for 068: once the text is fixed, the Void Ritualist has no aura, although DESIGN_DOCUMENT.md:773 says every champion has an aura or keyword. Good point for a short grooming pass that files or drops the unowned findings in roadmap §12 before the refactor phases touch that code.


### P6 — Free each fight and widen what Parity sees

**Goal.** Behaviour-neutral engine hygiene: break the reference cycles, split the giant test file, retire stale sims, stop the AI writing state, and extend the digest and the view probe. All before any refactor leans on them.

**Tickets:** 132 → 049 → 137 → 141 → 051 → 133 → 135

36. [ ] **[132](../../tasks/132-delete-dead-signals-buses-14-unheard.md)** Delete dead signals and buses (14 unheard CombatState signals, BuffSystem buff_applied, SacrificeSystem bus, attack_resolved) · *low, S*  
   Shrinks 049's disconnect loop.
37. [x] **[049](../../tasks/049-combatstate-refcount-cycles.md)** Break CombatState reference cycles so each fight is freed · *high, M*  
   Starts the look-ahead path 049 → 130. **Landed early, in P1 (2026-10-02), right after 080:** the leak made the full-size fingerprints impossible on the 16 GB dev machine (see P1 notes).
38. [ ] **[137](../../tasks/137-tests-registration-lint-l15-split-triggerhandlertests.md)** Tests: registration lint (L15) and split TriggerHandlerTests by subsystem; refresh TESTING.md · *normal, M*  
   Before the ~80 later tasks add probes; it registers the MetaTests layer 052 created.
39. [ ] **[141](../../tasks/141-retire-stale-debug-sims-combatsim-run.md)** Retire the stale debug sims; CombatSim.run takes a config · *low, M*  
   Before 120 (so 120 needn't rename ScoredAITest), 094 (fewer run() readers) and 097 (which wants SimRunner's --hero flag).
40. [ ] **[051](../../tasks/051-ai-profiles-no-direct-state-writes.md)** Stop AI profiles writing CombatState outside cmd_* (and de-duplicate spark cost) · *normal, M*  
   The counter rows change by design; win rates must be byte-identical. Prerequisite of 094, 118, 122, 129 and 133.
41. [ ] **[133](../../tasks/133-extend-digest-text-state-parity-cant.md)** Extend digest_text to the state Parity can't see today · *normal, S*  
   Before 083, 084, 095, 097, 129 and 131.
42. [ ] **[135](../../tasks/135-idle-consistency-probe-board-slot-shows.md)** Idle-consistency probe: every board slot shows the engine's stats when the presenter is idle · *normal, S*  
   The 050 and 069 allowlist entries are already gone; it must be green before 129 and 131.

> **Notes.** All of these must leave the post-retune fingerprint empty (Acts 1-4). Because the bug phases come first, P2 and P3 add about 20 probes to TriggerHandlerTests, so re-derive 137's split line ranges when it lands.


### P7 — Presenter guard, release gate, lint hardening, AI probes

**Goal.** Add the remaining safety nets: a presenter that can't soft-lock, debug tools gated out of release builds, a hardened lint with one shared ratchet helper, and per-profile AI decision probes.

**Tickets:** 048 → 053 → 140 → 139 → 120

43. [ ] **[048](../../tasks/048-presenter-softlock-guard.md)** Stop the presenter from soft-locking combat on a stuck animation · *normal, L*  
   Not reachable today; it is the guard before E/F rewrites the _play paths. Prerequisite of 109, 110, 115, 140 and 142.
44. [ ] **[053](../../tasks/053-gate-debug-tools-in-release.md)** Gate the cheat panel and test config out of release builds · *high, M*  
   Needs the Godot 4.6 export templates installed. Before 140, 103, 112 and 142, which rebase on its CombatScene changes.
45. [ ] **[140](../../tasks/140-harden-engine-lint-l8-compound-writes.md)** Harden the engine lint: L8 compound writes and a derived file list incl. CombatScene; L10 widened; escaped quotes; L7/L6 gaps · *normal, S*  
   Write the shared per-file ratchet helper and fix strip_comment here, so L14-L19 take their baselines once.
46. [ ] **[139](../../tasks/139-ai-behaviour-tests-fixed-board-decision.md)** AI behaviour tests: one fixed-board decision probe per encounter profile · *normal, M*  
   Absorbs the 072 and 073 probes. Prerequisite of 117, 118, 119 and 121.
47. [ ] **[120](../../tasks/120-scored-ai-keep-boardevaluator-scoringweights-look.md)** Scored AI: keep BoardEvaluator + ScoringWeights for look-ahead, delete the rest · *normal, S*  
   After 139 (its BoardEvaluator test goes in that file) and 141. Leaves 105, 117, 118, 121 and 089 less code to port.

> **Notes.** All neutral. 048 step 3 (deadline plus generation guard) carries the design risk. If it is split out as 048b, 115 waits for 048b or carries the guards itself; 109, 110, 140 and 142 need only steps 1-2. If any build will be shared before this phase, pull 053 forward.


### P8 — Content validation and ratchets

**Goal.** Make typos and unknown ids fail at load or in tests, type every effect step, and set the side-literal and presentation ratchets before the refactors that lower them.

**Tickets:** 104 → 106 → 105 → 088 → 087 → 111

48. [ ] **[104](../../tasks/104-content-reference-check-contenttests-layer-lint.md)** Content-reference check — ContentTests layer + lint L14 for card-id literals and dispatch vocabularies · *high, M*  
   After 062, 073 and 140, so its allowlists start empty.
49. [ ] **[106](../../tasks/106-fail-loudly-unknown-condition-hardcoded-id.md)** Fail loudly on unknown condition / hardcoded id / multiplier key / passive id / handler; fix _validate_spell_damage_schools · *normal, S*
50. [ ] **[105](../../tasks/105-parse-effect-steps-once-load-strict.md)** Parse effect steps once at load with a strict validator; EffectStep everywhere · *normal, M*  
   Early, so 089, 096, 097, 098 and 107 write typed-step code once. Hard prerequisite of 107; never at the same time as 102.
51. [ ] **[088](../../tasks/088-triggerevent-hygiene-delete-dead-values-dead.md)** TriggerEvent hygiene: delete dead values and the dead TurnPhase enum, fix stale trigger comments, document trap vs rune conventions · *low, S*  
   Hard prerequisite of 086. Fixes the TriggerManager.gd header before 114 and 131 touch it.
52. [ ] **[087](../../tasks/087-lint-l16-side-literal-ratchet-rules.md)** Lint L16: side-literal ratchet in rules code, and no "player" parameter defaults · *normal, S*  
   Baseline taken after 050, 051, 054, 055 and 058, on 140's helper, and before 083 adds CombatSide.
53. [ ] **[111](../../tasks/111-lint-l17-presentation-reads-journal-ratcheted.md)** Lint L17: presentation reads the journal (ratcheted engine-read count in UI files) · *low, S*  
   Baseline after 069-071; 109 and 110 lower it.

> **Notes.** All neutral. Godot 4.6 prints push_error as 'ERROR:', not 'SCRIPT ERROR:' (checked 2026-10-02, task 047). run_checks.sh greps 'SCRIPT ERROR', so 104's and 106's fail-loud checks need a test that asserts on them, or the gate must grep 'ERROR:' too.


### P9 — Look-ahead engine core (F1, F2, I6, I2, I1, I3)

**Goal.** Stamp a cause on every journal event and have the presenter consume look-ahead events by cause (fixes the Void Bolt double popup and wrong lunge numbers). Then replace the side-channel fields with the typed resolution stack, and make triggers re-entrancy safe.

**Tickets:** 114 → 115 → 116 → 134 → 130 → 129 → 131

54. [ ] **[114](../../tasks/114-engine-resolution-stack-that-stamps-cause.md)** Engine: a Resolution stack that stamps a cause on every journal event (digest-neutral) · *high, M*  
   Digest-neutral; after 057, 060 and 088.
55. [ ] **[115](../../tasks/115-presenter-consumes-look-ahead-events-cause.md)** Presenter consumes look-ahead events by cause; fixes the Void Bolt double popup and the wrong attack-lunge numbers · *high, M*  
   Player-visible display fix.
56. [ ] **[116](../../tasks/116-presenter-classify-event-kind-warn-unknown.md)** Presenter: classify every event kind; warn on unknown VFX names and unclassified kinds · *low, S*  
   With or after 115, in the same match statements.
57. [ ] **[134](../../tasks/134-typed-engine-structs-damageinfo-costplan-typed.md)** Typed engine structs: DamageInfo, CostPlan, typed buff containers · *normal, M*  
   Neutral.
58. [ ] **[130](../../tasks/130-per-state-talent-flags-per-state.md)** Per-state talent flags and a per-state corruption-removed channel (no MinionInstance statics, no global bus subscription) · *high, S*  
   After 134, so it uses the Buffable base. Gives 090, 097, 098 and 110 a per-state home.
59. [ ] **[129](../../tasks/129-resolution-context-replace-side-channel-fields.md)** Resolution context: replace the side-channel fields with the typed resolution stack · *high, M*  
   Three commits: steps 1-8 neutral; step 9 kill credit (delta); step 10 Dark Channeling scope (delta --act 4: F13, F15). Before 086, which then uses cancel_open and play_target, and before 092.
60. [ ] **[131](../../tasks/131-iteration-re-entrancy-safety-trigger-depth.md)** Iteration and re-entrancy safety: trigger depth guard, skip handlers unregistered mid-fire, board snapshots, minion zone · *normal, M*

> **Notes.** Owner rulings needed before 129 step 9 (kill credit for counter-kills and nested kills), 129 step 10 (Dark Channeling scope) and 131 phase b (does the phase-2 Sovereign keep phase-1 hero debuffs? plus the abort default). The neutral commits can land without them, so a late ruling doesn't block 086.


### P10 — Presentation reads only the journal (E2, E3, E6, C5, H5, H6)

**Goal.** Move the remaining widgets and slot visuals onto journal payloads, take UI prompts off the gameplay log, cut journal noise, and split the enemy panel.

**Tickets:** 109 → 110 → 112 → 136 → 103 → 126 → 127

61. [ ] **[109](../../tasks/109-player-resource-widgets-korrath-badges-counter.md)** Player resource widgets, Korrath badges, counter warning and environment panel render journal payloads; ViewState cleanup · *normal, M*  
   Lowers L17. Before 085 and 097, which keep its payloads.
62. [ ] **[110](../../tasks/110-boardslot-status-visuals-keywords-shield-corruption.md)** BoardSlot status visuals (keywords, shield, corruption, crit, armour, READY) from the journal snapshot · *normal, M*  
   After 130 and 131, so it uses their flag and zone; its attacker MINION_STATS_CHANGED must not confuse 115's matcher.
63. [ ] **[112](../../tasks/112-ui-prompts-refusals-go-ui-only.md)** UI prompts and refusals go to a UI-only log channel; attack narration moves into the engine · *low, S*  
   After 113 and 140.
64. [ ] **[136](../../tasks/136-cut-journal-noise-no-op-presence.md)** Cut journal noise: no-op presence-aura recompute, and measure the sim's LOG cost · *low, S*  
   After 110's E3b step 1 and 112's narration log, once 135 runs with no slot allowlist entries.
65. [ ] **[103](../../tasks/103-combat-ui-reads-hero-talent-enemy.md)** Combat UI reads hero / talent / enemy display info from the fight (state / CombatConfig), not GameManager · *normal, S*  
   Before 090 and 127.
66. [ ] **[126](../../tasks/126-move-shared-textured-button-style-global.md)** Move the shared textured button style into global_theme.tres; delete the 5 _make_btn_style copies · *low, S*
67. [ ] **[127](../../tasks/127-split-enemyheropanel-concern-share-hero-hp.md)** Split EnemyHeroPanel by concern; share the hero HP bar and Korrath badges with PlayerHeroPanel · *low, M*

> **Notes.** Display only, so fingerprint diffs are empty. The phase serialises on CombatPresenter's _play paths and BoardSlot.


### P11 — Hero, pool and run data model (C, H)

**Goal.** Turn hero, branch, pool and deck rules into data, pin the run layer with MetaTests, then extract RunService. Roadmap §11 puts this before the side model and before the next hero (e.g. Korrath B2/B3, tasks 026/027) is designed.

**Tickets:** 100 → 101 → 138 → 123 → 102 → 125

68. [ ] **[100](../../tasks/100-hero-branch-pool-table-branchdata-herodatabase.md)** One hero/branch/pool table: BranchData + HeroDatabase pool queries; delete the pool-mapping copies; Collection shows every hero · *normal, M*  
   Meta behaviour change; note it in the summary.
69. [ ] **[101](../../tasks/101-herodata-carries-deck-rules-core-unit.md)** HeroData carries deck rules: core unit, extra-copy rules, base pools, hero skills; one copy-cap rule for deck builder / shop / reward · *normal, S*  
   Before 097, which can validate against HeroData.skills.
70. [ ] **[138](../../tasks/138-metatests-run-progression-boss-unlocks-talents.md)** MetaTests: run progression, boss unlocks, talents, relic offers; then reward/shop pools and deck-builder rules · *normal, M*  
   Before 123, so its static pool builders are moved, not rewritten.
71. [ ] **[123](../../tasks/123-runservice-run-rules-victory-defeat-bookkeeping.md)** RunService: run rules (victory/defeat bookkeeping, rewards, relics, shop purchases) out of UI scenes into a headless-testable service · *normal, L*
72. [ ] **[102](../../tasks/102-declare-pool-act-gate-card-split.md)** Declare pool and act gate on the card; split CardDatabase per pool · *low, M*  
   Nothing else may edit CardDatabase while it is in flight; the Acts 1-4 fingerprint must be empty.
73. [ ] **[125](../../tasks/125-phasetransition-reads-phase-2-spec-encountertable.md)** PhaseTransition reads its phase-2 spec from EncounterTable instead of the profile id and constants · *normal, S*  
   Updates 050's and 067's F15 probes; the Act 4 fingerprint must be empty.

> **Notes.** Except for 102 and 125, nothing here touches combat files, so this phase can be swapped with P12-P13 or interleaved. If PvP is scheduled before the next hero, swap them: no hard dependency breaks, and only 101 → 097 (a nice-to-have) is lost.


### P12 — Side model foundation, with B pre-work (B1, B2a, A1, A2, A6)

**Goal.** Shrink CombatState first, then introduce Side constants and SideState for hand, deck, resources, traps, environment, board, hero and per-turn counters. Every step is behaviour-neutral.

**Tickets:** 094 → 095 → 083 → 084 → 085

74. [ ] **[094](../../tasks/094-move-balance-diagnostic-counters-off-combatstate.md)** Move balance-diagnostic counters off CombatState into one sim-side counter sink · *normal, M*  
   Before 085 would move the crit-consumed counters, and before 097 and 099.
75. [ ] **[095](../../tasks/095-consolidate-15-enemy-champions-state-shared.md)** Consolidate the 15 enemy champions' state and shared helpers (ChampionTracker), no behaviour change · *normal, M*  
   Writes the digest champion line from the tracker (133 has landed). Before 085 renames enemy_crit_multiplier, and before 096 and 122.
76. [ ] **[083](../../tasks/083-side-constants-sidestate-part-1-hand.md)** Side constants + SideState, part 1: hand, deck, graveyard, essence/mana behind state.side(s) · *normal, M*  
   Its soft prerequisites are all in: 049, 050, 054, 055, 064, 069, 133 and 087.
77. [ ] **[084](../../tasks/084-sidestate-part-2-traps-environment-board.md)** SideState part 2: traps, environment, board, slots and hero; per-copy TrapInstance · *normal, M*  
   Keeps 070's snapshots and 133's digest identical; if the board forwarders slow the sim by more than about 3%, alias the arrays instead.
78. [ ] **[085](../../tasks/085-sidestate-part-3-per-side-turn.md)** SideState part 3: per-side turn counters and cost modifiers · *low, S*

> **Notes.** Each task leaves the Acts 1-4 fingerprint and the extended digest_text byte-identical, and lowers the L16 baseline in its own commit.


### P13 — Side-neutral triggers and per-side mechanics (PvP-ready engine)

**Goal.** Owner Q1 and Q2: triggers, talents, relics, Seris and Korrath state, Void Marks, rituals and champions work for either side. One mechanic per commit.

**Tickets:** 089 → 086 → 090 → 091 → 097 → 098 → 092 → 093 → 096

79. [ ] **[089](../../tasks/089-retire-legacy-passive-effect-id-dispatch.md)** Retire legacy passive_effect_id dispatch; make the card-driven board-passive dispatchers side-neutral · *normal, M*  
   Before 086 phase 2, which then migrates its registrations one to one; coordinate handler_order.txt.
80. [ ] **[086](../../tasks/086-side-neutral-trigger-events-triggerkind-ctx.md)** Side-neutral trigger events (TriggerKind + ctx.owner), with a compatibility shim · *normal, L*  
   Phases 1-3 neutral; phases 4-5 are latent behaviour changes built on 129's cancel_open and play_target, each with its own delta.
81. [ ] **[090](../../tasks/090-per-side-talents-hero-passives-enemy.md)** Per-side talents and hero passives (+ an enemy hero id) · *normal, M*  
   Its temporary PLAYER_SIDE_ONLY_UNTIL_MODULES list is emptied by 097 and 098; switches 103's empty_slot_bg.
82. [ ] **[091](../../tasks/091-per-side-relics.md)** Per-side relics · *low, S*  
   Before 093 (Oblivion Seal's ON_RUNE_PLACED).
83. [ ] **[097](../../tasks/097-extract-seris-per-side-serismodule-flesh.md)** Extract Seris into a per-side SerisModule (Flesh, Forge, skills, deathless save); hero skills dispatched from the hero · *normal, M*  
   After 057, 059, 061, 101, 129, 130 and 141; carries their fixes.
84. [ ] **[098](../../tasks/098-extract-korrath-talent-state-per-side.md)** Extract Korrath talent state into a per-side KorrathModule · *low, S*  
   Keeps 058's _card_for fix.
85. [ ] **[092](../../tasks/092-per-side-void-marks-remaining-player.md)** Per-side Void Marks and the remaining player-gated EffectResolver steps · *normal, S*
86. [ ] **[093](../../tasks/093-per-side-rituals-rune-events-env.md)** Per-side rituals and rune events (environment rituals, ON_RUNE_PLACED / ON_RITUAL_FIRED for either side) · *normal, M*  
   Any fingerprint movement means a listener reacts to enemy runes.
87. [ ] **[096](../../tasks/096-champions-as-data-spec-table-reactive.md)** Champions as a data spec table with a reactive aura column; small modules for ACP and VC · *normal, M*  
   After 086 phase 3, so its event columns are written as TriggerKinds and need no migration later.

> **Notes.** Run 086 as five sub-commits. If it stalls, 090, 092 and 093 stall with it, so land phases 1-3 as soon as they are green. Each per-side task records its seeded Acts 1-4 delta (expected empty with today's content) and lowers L16. After 096 the engine is PvP-ready (position 87 of 96).


### P14 — AI consolidation and the extensibility tail (G, B7, D4, D7, J6)

**Goal.** Consolidate the AI into synchronous, side-aware profiles (the profile half of look-ahead, Q7b). Then publish the engine API, finish parameterised conditions and the effect registry, and type the VFX wiring.

**Tickets:** 117 → 118 → 119 → 121 → 122 → 099 → 108 → 107 → 142

88. [ ] **[117](../../tasks/117-ai-resource-growth-as-data-generic.md)** AI resource growth as data: one generic grow_resources, no literal 11 · *normal, M*
89. [ ] **[118](../../tasks/118-ai-toolkit-copy-shared-profile-helpers.md)** AI toolkit: one copy of the shared profile helpers · *normal, M*
90. [ ] **[119](../../tasks/119-flatten-ai-profile-inheritance-encounter-profiles.md)** Flatten AI profile inheritance: encounter profiles extend CombatProfile or an archetype base · *normal, M*
91. [ ] **[121](../../tasks/121-synchronous-ai-profiles-guard-against-real.md)** Synchronous AI profiles: guard against real awaits now, then strip the ~360 no-op awaits · *normal, M*  
   Shares the L6 rule function from 140.
92. [ ] **[122](../../tasks/122-ai-profiles-read-game-only-through.md)** AI profiles read the game only through a side-aware CombatAgent API (lint L18) · *normal, M*  
   Late on purpose: its API wraps the per-side data from 090, 091, 095, 097 and 101, and absorbs 073's and 095's agent methods. It ports the Void Herald 'alive' flag unchanged.
93. [ ] **[099](../../tasks/099-public-engine-api-members-used-outside.md)** Public engine API for members used outside CombatState, with a ratchet lint on state._x (L19) · *low, M*  
   Shares the counting helper with 122.
94. [ ] **[108](../../tasks/108-parameterised-conditions-declared-condition-table.md)** Parameterised conditions with a declared condition table · *low, S*  
   After 092 and 097, so the Void Mark and Flesh conditions are already per side.
95. [ ] **[107](../../tasks/107-effect-handler-registry-effecttype-handler-migrated.md)** Effect handler registry — EffectType → handler, migrated one family at a time · *low, L*  
   After 083, 084, 092, 097 and 129, so each arm moves once.
96. [ ] **[142](../../tasks/142-vfx-wiring-table-per-dispatch-typed.md)** VFX wiring: one table per dispatch, typed CombatScene handles, delete the scene forwarders · *low, L*  
   Last, after 053, 115, 116, 127, 140 and 099.

> **Notes.** Every task here is behaviour-neutral: the Acts 1-4 fingerprint stays empty, and 139's probes stay green for 117-122. After 122 every look-ahead prerequisite the owner named is in (position 92). If look-ahead work is scheduled before PvP, pull 117, 118, 119 and 121 to right after P9; they share no files with A. 122 can follow, accepting that its API is extended later.


---

## Parallel lanes

- **Combat-rules spine: strictly serial.** 047 → 073 (P1) → P2 → P3 → retune → the behaviour commits of 129 and 131 (P9) → P12 → P13. Never run two spine tasks in parallel sessions: `TriggerManager.fire`, `resolve_minion_attack` and the CombatState / CombatHandlers lines collide.
- **Meta lane: can't move the fingerprint.** P4 (074 → 075 → 124 → 128 → 052 → 077 → 078 → 076), then P11 (100 → 101 → 138 → 123, then 102). Interleave it anywhere after 047, for example while a batch run is going. Entry rules:
  - 052 after 047;
  - 101 after 075;
  - 138 and 123 after 052.
- **Presentation lane:** P5 (070 after 050) → 048 → 140 → 111 → 115 / 116 (after 114) → P10 → 142. It is serial within itself, because 048, 109, 110, 115 and 116 all edit `CombatPresenter`'s `_play` paths. It can run beside the spine once 050 and 069 are in.
- **AI lane:** 139 → 120, then 117 / 118 → 119 / 121, any time after 047, 051 and 139. Pull it ahead of P10 if look-ahead work starts first. Hold 122 until 090, 091, 095, 097 and 101 land.
- **Tooling and content lane:** 079 / 081 → 104 → 106 → 105, then 087 / 111 after 140. 102 and 142 go last, when nothing else in flight edits CardDatabase.gd or CombatScene.gd. Don't land two new lint rules at once; both edit `lint_engine.py`.
- **B pre-work:** 094 (after 051) and 095 (after 066 / 067) need nothing from workstream A, so they can start once P6 is in.
- **AI look-ahead prerequisites (owner Q7b):** 049 → 130; 114 → 134 → 129; 120; 118 → 121; 122 after the per-side work.

## Decisions to make before a phase starts

Each task records a default; confirm or override it before its phase.

| Before | Decision | Default in the task |
|---|---|---|
| P2 | 057: the defender (or attacker) leaves the board during PRE | The attack is spent: no strike, no counter |
| P2 | 067: the Avatar's card counter at the phase change | It carries over into phase 2 (a grooming ruling, not yet yours) |
| P3 | 065: Energy Conversion overflow | Kept as temporary excess (DESIGN_DOCUMENT.md:151), not capped at `mana_max` |
| P4 | Should "destroy" (`kill_minion`, e.g. Death Trap) bypass Deathless? | No task yet |
| P4 | The Act 1 boss can never unlock a card; Nyx'ael's unlock isn't implemented | No task yet |
| P4 | Resuming a run re-rolls shop / reward offers and the combat seed for free | No task yet (052, 077, 123 touch it) |
| P5 | 068 leaves the Void Ritualist with no aura, but DESIGN_DOCUMENT.md:773 says champions have one | Text follows the code (QN1) |
| P9 | 129 step 9 (kill credit for counter-kills and nested kills) and step 10 (Dark Channeling scope) | Recorded in 129; its neutral commits don't wait for this |
| P9 | 131 phase b: does the phase-2 Sovereign keep phase-1 hero debuffs? | Recorded in 131 |

**Lint rule numbers (proposed).** Freeze L12–L21 as reserved ids instead of "take the next free number": renumbering would ripple through about ten task files and two docs. The landing order is then:

| Order | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Rule | L13 | L21 | L12 | L15 | L14 | L16 | L17 | L20 | L18 | L19 |
| Task | 050 | 058 | 051 | 137 | 104 | 087 | 111 | 131 | 122 | 099 |

## Risks and fragile points

- **Weak cover.** There is no Korrath preset, and no sim deck holds Matron or Energy Conversion. For 143, 059, 065 and 057's Korrath half, the new probes are the only real check; an empty fingerprint proves little.
- **Tooling assumptions:**
  - Godot 4.6 prints `push_error` as `ERROR:` (checked 2026-10-02), so run_checks.sh's `SCRIPT ERROR` grep misses the negative probes of 104 and 106 unless a test asserts on them.
  - 048's step 3 may split out as 048b; 115 then waits for it or carries its guards.
  - 053 needs the 4.6 export templates installed. Pull it earlier if any build will be shared.
- **Fragile order points:**
  - 050's `place_trap` must also cover Voidshaped Acolyte's PLACE_RUNE_ON_OPPONENT and journal Korrath's rune append, or 070's panels stay partly stale until 084 or 093.
  - 137's test split is keyed to today's TriggerHandlerTests line ranges, which P2–P3 shift.
  - 089 and 086 both rewrite `handler_order.txt`.
  - 105's strict validator may reject live content, so land it with 104 green and never alongside 102.
- **Merge-conflict hotspots** (the serial order avoids them; parallel sessions would hit them):

  | Hotspot | Tasks |
  |---|---|
  | `resolve_minion_attack` | 057, 114, 129, 131, 110 |
  | `TriggerManager.fire` | 114, 131, 086 |
  | CombatHandlers handler and log lines | 054, 055, 062, 089, 086 |
  | CombatPresenter `_play` | 048, 115, 116, 109, 110 |
  | EnemyHeroPanel | 071, 068, 103, 127 |
  | ShopScene | 074, 075, 128, 100, 123 |
  | `lint_engine.py` | nine new rules |
  | CLAUDE.md "Adding New Cards" | 079, 105, 106, 102 |
- **Unowned findings.** Run a short grooming pass after P5 to file or drop them, before the refactors touch that code:
  - a draw into a full hand burns the card with no event or log;
  - Void Herald's "alive" flag stays true after its death;
  - merging the three spell-cast paths has no owner (082 row 20);
  - the CorruptedHandler play order;
  - roadmap I6's `p.get(k, 0)` payload defaults.

## Option: PvP sooner

PvP readiness arrives at ticket 87, because roadmap §11 puts presentation (P10) and hero / pool data (P11) first. Moving P10 and P11 after P13 breaks no hard dependency and brings the PvP-ready engine forward to about ticket 74. The cost is three small conveniences: 101 gives 097 its `HeroData.skills`, 103 helps 090, and 109 helps 085. Without them, those tasks do a little more work.

## Change log

| Date | Change |
|---|---|
| 2026-10-01 | First version, from the post-grooming ordering analysis (three lenses, merged and checked by script). |
| 2026-10-02 | 049 pulled forward from P6 into P1 (after 080): the sim leak made the full-size fingerprints impossible. Checked: `push_error` prints `ERROR:`, not `SCRIPT ERROR:` (the P8 / Risks question), so run_checks.sh's grep misses it; a test must assert it. |
