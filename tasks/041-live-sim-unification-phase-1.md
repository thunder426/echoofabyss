---
id: "041"
title: Live/sim unification — Phase 1 (rules code addresses state)
status: active
area: combat
priority: normal
started: 2026-09-23
finished:
---

## Description

Execute Phase 1 of `design/refactors/LIVE_SIM_UNIFICATION_PLAN.md` in the plan's order (1.1 → 1.3 → 1.4 → 1.2 → 1.5): add the presenter seam and lint L3/L4, hoist enemy-side and player resource/deck/hand state onto CombatState, move the gameplay-only scene/SimState method pairs onto CombatState, rewrite the rules code to address a typed `state` (presentation only through a nullable `presenter`), and put RelicRuntime on state. One commit per green step; `tools/run_checks.sh` gates every step.

## Work log

- 2026-09-23: opened. Reviewed Phase 0 (0.605–0.614) against the plan — no defects found; baseline `tools/run_checks.sh` green: lint 0, 797/797, LiveSmoke OK.
- 2026-09-23: 1.1 — `CombatState._scene_facade` → `presenter` (null in sim); `_get_scene_facade()` kept (presenter-or-self). `tools/lint/presentation_allowlist.txt` + lint L3/L4, computed but not enforced until 1.2 (baseline L3 477, L4 163 — the 1.2 work list). **Deviation:** a third route besides `state.` / `presenter.`: `[facade]` for the 8 CombatScene overrides whose live body is still VFX-bound (`_apply_void_mark`, `_corrupt_minion`, `_deal_void_bolt_damage`, `_deal_enemy_void_bolt_damage`, `_fire_ritual`, `_sacrifice_minion`, `_summon_token`, `_summon_token_at_slot`) — routing them to `state` would drop the projectile/sigil/ritual VFX or change B13 timing; they stay on the facade (scene live, state in sim) until Phase 3.0, and L3 requires each to be a func on both classes. L4 is receiver-based (object handles only) — a blanket `.get("` ban would hit Dictionary reads. Pack Instinct's ATK-label hold moved from the handler into `_spawn_pack_instinct_buff_vfx(minion, old_atk)`.
- 2026-09-23: 1.3 — CombatState now owns turn_number, is_player_turn, both sides' resources, decks, hands, graveyards, enemy_limited_cards, attack_cancelled and enemy_play_target, with side-agnostic accessors (hand_of/deck_of/graveyard_of/traps_of/environment_of/essence_of/…) and mutators (draw_cards, add_to_hand, remove_from_hand, send_to_graveyard, setup_deck, gain/spend/grow/convert, can_afford, refill_resources) + signals resources_changed/card_drawn/card_generated. TurnManager and EnemyAI are façades (forwarding properties; TurnManager relays the player-side signals). SimState lost the hoisted vars, draw helpers and owner helpers; SimTurnManager is a façade; SimEnemyAgent's duck-type block is gone. `_current_turn` retired in favour of `turn_number` (live never set `_current_turn`: graveyard stamps were 0 live and F15's `_sovereign_transition_turn` was always 0). `digest_text` moved to CombatState. EffectResolver/ConditionResolver/TargetResolver/HardcodedEffects/CombatHandlers/CombatSetup/RelicEffects: no `enemy_ai`/`turn_manager` left (gate 0). `EnemyHeroPanel.update` takes the state (10 call sites, not 14). PhaseTransition reads/writes typed state. `tools/lint/l1_allow.txt` emptied. Behaviour changes (live is the spec; sim moves): player draw into a full hand burns in sim; generated player cards fire ON_PLAYER_CARD_DRAWN in sim (fire moved from the scene's hand-display callbacks into state); sim now has a turn flag, so `enemy_turn`/`player_turn` conditions and Soul Rune's opponent-turn gate work there; sim P2 transition clears the enemy spell-tax penalty. Live: opening maxima no longer count as a growth choice (backing fields). +6 probes (809). **Caught by the balance batch, not the suite:** deleting SimEnemyAgent's duck properties made `CombatAgent.effective_minion_essence_cost`'s `get("essence_cost_discounts")` return null → F2 lost corrupted_death (+10–40 pts player win rate). Replaced the duck-typing with typed virtuals `_essence_cost_discounts()` / `_minion_essence_cost_aura()` + a mutation-checked probe. **Balance:** `BalanceSimBatch --runs 100 --seed 7` (Acts 1+2) vs pre-1.3: identical except F6 Swarm/Scout's Lantern 93→92% (draw-burn on Lantern's draw 2).

## Summary

_(filled in at /task-done)_
