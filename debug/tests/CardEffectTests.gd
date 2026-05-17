## CardEffectTests.gd
## Layer 1: per-card effect probes. One function per card/scenario, exercising
## effect_steps through the appropriate entry point:
##   - Spells  → EffectResolver.run(spell.effect_steps, ctx)
##   - Minions → EffectResolver.run(minion.on_play_effect_steps, ctx)
##   - Raw deltas on SimState are asserted inline.
##
## "KNOWN BUG" markers denote probes that intentionally fail on first run to
## surface implementation gaps.
##
## Skipped (sim cannot cover):
##   - void_devourer (SimState._resolve_void_devourer_sacrifice is a no-op stub)
##   - soul_shatter no-valid-target gate (play-gate lives in UI, not sim)
class_name CardEffectTests
extends RefCounted

static func run_all() -> void:
	print("\n=== Layer 1: Card Effect Tests ===")
	_void_bolt_base()
	_void_bolt_symmetric()
	_void_bolt_piercing()

	_soul_shatter_base()
	_soul_shatter_high_hp_sac()
	_grafted_butcher_aoe()
	_grafted_butcher_no_target()
	_fiendish_pact_player()
	_fiendish_pact_enemy_symmetric()  # KNOWN BUG
	_trapbreaker_rogue()
	_spell_taxer()
	_saboteur_adept()
	_void_detonation_base()
	_void_detonation_with_marks()
	_void_detonation_enemy_symmetric()  # KNOWN BUG
	_smoke_veil()
	_silence_trap()
	_runic_blast_under_2_runes()
	_runic_blast_2_plus_runes()
	_runic_blast_distinct_targets()  # KNOWN BUG
	_runic_echo_own_runes_only()
	_void_rift_lord_enemy_cast()
	_void_rift_lord_player_symmetric()  # KNOWN BUG
	_frenzied_imp_scaling()
	_void_screech_under_3_imps()
	_void_screech_3_plus_imps()
	_brood_call_summons_feral()
	_pack_frenzy_buff()
	_pack_frenzy_ancient_frenzy_lifedrain()

	_void_imp_on_play()
	_senior_void_imp_on_play()
	_runic_void_imp_on_play()
	_void_imp_wizard_on_play()
	_shadow_hound_scaling()
	_dark_empowerment_demon()
	_dark_empowerment_human()
	_abyssal_sacrifice_draws_2()
	_abyssal_plague_aoe()
	_void_summoning_no_human()
	_void_summoning_with_human()
	_void_spawning_2_demons()
	_flesh_rend_base()
	_flesh_rend_doubled()
	_flesh_harvester_gains_flesh()
	_ravenous_fiend_on_death_flesh()
	_feast_of_flesh_combo()
	_mend_the_flesh_no_flesh()
	_mend_the_flesh_with_flesh()
	_flesh_eruption_no_flesh()
	_flesh_eruption_with_flesh()
	_gorged_fiend_scaling()
	_flesh_stitched_horror_with_flesh()

	# Korrath core pool (task 023)
	_squire_of_the_order_discounts_knights_in_hand()
	_squire_of_the_order_no_knights_in_hand_is_noop()
	_order_conscript_adds_footman_to_hand()
	_quartermaster_buffs_new_friendly_summon_armour()
	_quartermaster_does_not_self_buff()
	_quartermaster_stacks_with_two_sources()
	_shatterstrike_deals_physical_to_minion()

	# Rally the Ranks (task 038)
	_rally_human_target_spawns_two_human_tokens()
	_rally_demon_target_spawns_two_demon_tokens()
	_rally_dual_tag_target_with_human_choice()
	_rally_dual_tag_target_with_demon_choice()
	_rally_edge_slot_target_only_right_spawns()
	_rally_both_adjacent_occupied_zero_tokens()
	_rally_one_adjacent_occupied_one_token()
	_rally_no_race_in_extra_data_zero_tokens()
	_rally_sim_race_heuristic()

# ---------------------------------------------------------------------------
# Voidbolt (kept from scaffold phase)
# ---------------------------------------------------------------------------

static func _void_bolt_base() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_bolt / base 500 dmg to enemy hero", state):
		return
	var hp_before := state.enemy_hp
	var spell := CardDatabase.get_card("void_bolt") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state.enemy_hp, hp_before - 500, "enemy hp down by 500")
	TestHarness.assert_eq(state.enemy_void_marks, 0, "no void mark without piercing_void talent")

static func _void_bolt_symmetric() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_bolt / symmetric — enemy cast hits player hero", state):
		return
	var hp_before := state.player_hp
	var spell := CardDatabase.get_card("void_bolt") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "enemy"))
	TestHarness.assert_eq(state.player_hp, hp_before - 500, "player hp down by 500")

static func _void_bolt_piercing() -> void:
	var state := TestHarness.build_state({"talents": ["piercing_void"]})
	if not TestHarness.begin_test("void_bolt / piercing_void applies 1 void mark", state):
		return
	# _card_for applies talent_overrides; under piercing_void, Void Bolt's
	# effect_steps are swapped to include the VOID_MARK step.
	var spell := state._card_for("player", "void_bolt") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state.enemy_void_marks, 1, "void_marks == 1 with piercing_void")

# ---------------------------------------------------------------------------
# soul_shatter — spell, 3 mana
# Sacrifice a friendly Demon. AoE to all enemy minions:
#   - 300 damage if the sacrifice had >= 300 HP
#   - 200 damage otherwise
# (Cast without a valid target should be gated by the UI — not testable in sim.)
# ---------------------------------------------------------------------------

static func _soul_shatter_base() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("soul_shatter / 200 AoE when sac has <300 HP", state):
		return
	var sac := TestHarness.spawn_friendly(state, "void_imp")  # Demon
	sac.current_health = 100  # force <300 HP path
	var e1 := TestHarness.spawn_enemy(state, "rabid_imp")
	var e2 := TestHarness.spawn_enemy(state, "rabid_imp")
	e1.current_health = 1000  # avoid clamping below 0
	e2.current_health = 1000
	var spell := CardDatabase.get_card("soul_shatter") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, sac)
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(1000 - e1.current_health, 200, "enemy1 took 200")
	TestHarness.assert_eq(1000 - e2.current_health, 200, "enemy2 took 200")
	TestHarness.assert_false(state.player_board.has(sac), "sac removed from board")

static func _soul_shatter_high_hp_sac() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("soul_shatter / 300 AoE when sac has >=300 HP", state):
		return
	var sac := TestHarness.spawn_friendly(state, "grafted_fiend")  # base HP varies; force it
	sac.current_health = 400
	var e1 := TestHarness.spawn_enemy(state, "rabid_imp")
	e1.current_health = 1000  # avoid clamping
	var spell := CardDatabase.get_card("soul_shatter") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, sac)
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(1000 - e1.current_health, 300, "enemy took 300 (high-HP sac)")

# ---------------------------------------------------------------------------
# grafted_butcher — minion, 2 essence (2/1)
# ON PLAY: sacrifice chosen friendly minion (other), 200 AoE to enemy minions.
# ---------------------------------------------------------------------------

static func _grafted_butcher_aoe() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("grafted_butcher / sacrifices target, 200 AoE to enemies", state):
		return
	var butcher := TestHarness.spawn_friendly(state, "grafted_butcher")
	var sac := TestHarness.spawn_friendly(state, "void_imp")
	var e1 := TestHarness.spawn_enemy(state, "rabid_imp")
	e1.current_health = 1000
	var butcher_data := butcher.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "player", butcher, sac)
	EffectResolver.run(butcher_data.on_play_effect_steps, ctx)
	TestHarness.assert_false(state.player_board.has(sac), "sac removed")
	TestHarness.assert_eq(1000 - e1.current_health, 200, "enemy took 200")

static func _grafted_butcher_no_target() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("grafted_butcher / fizzles with no target", state):
		return
	var butcher := TestHarness.spawn_friendly(state, "grafted_butcher")
	var e1 := TestHarness.spawn_enemy(state, "rabid_imp")
	var e1_hp := e1.current_health
	var butcher_data := butcher.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "player", butcher, null)
	EffectResolver.run(butcher_data.on_play_effect_steps, ctx)
	TestHarness.assert_eq(e1.current_health, e1_hp, "enemy unharmed (no sac, no AoE)")

# ---------------------------------------------------------------------------
# fiendish_pact — spell, 1 mana
# "Draw a card" (DRAW step) + "Next Demon costs 2 less Essence this turn."
# Should be symmetric: enemy cast should arm discount on enemy side.
# Current code early-returns for non-player owners → KNOWN BUG.
# ---------------------------------------------------------------------------

static func _fiendish_pact_player() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("fiendish_pact / player cast arms 2-essence discount", state):
		return
	var spell := CardDatabase.get_card("fiendish_pact") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state._fiendish_pact_pending, 2, "_fiendish_pact_pending == 2")

static func _fiendish_pact_enemy_symmetric() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("fiendish_pact / enemy cast arms discount on enemy side", state):
		return
	var spell := CardDatabase.get_card("fiendish_pact") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "enemy"))
	TestHarness.assert_eq(state._fiendish_pact_pending, 0, "player-side flag untouched")
	TestHarness.assert_eq(state._enemy_fiendish_pact_pending, 2, "_enemy_fiendish_pact_pending == 2")

# ---------------------------------------------------------------------------
# trapbreaker_rogue — minion, 2 essence (2.5/2)
# ON PLAY: destroy a random enemy trap.
# ---------------------------------------------------------------------------

static func _trapbreaker_rogue() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("trapbreaker_rogue / destroys a random enemy trap", state):
		return
	# Seed two enemy traps
	var trap1 := CardDatabase.get_card("smoke_veil") as TrapCardData
	var trap2 := CardDatabase.get_card("silence_trap") as TrapCardData
	state.enemy_active_traps.append(trap1)
	state.enemy_active_traps.append(trap2)
	var rogue := TestHarness.spawn_friendly(state, "trapbreaker_rogue")
	var rogue_data := rogue.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "player", rogue)
	EffectResolver.run(rogue_data.on_play_effect_steps, ctx)
	TestHarness.assert_eq(state.enemy_active_traps.size(), 1, "enemy traps down to 1")

# ---------------------------------------------------------------------------
# spell_taxer — minion, 3 essence (2.5/3)
# ON PLAY: opponent spells cost +1 Mana next turn. Additive.
# ---------------------------------------------------------------------------

static func _spell_taxer() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("spell_taxer / opponent spells +1 mana next turn", state):
		return
	var taxer := TestHarness.spawn_friendly(state, "spell_taxer")
	var taxer_data := taxer.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "player", taxer)
	EffectResolver.run(taxer_data.on_play_effect_steps, ctx)
	TestHarness.assert_eq(state._spell_tax_for_enemy_turn, 1, "enemy turn tax == 1")

# ---------------------------------------------------------------------------
# saboteur_adept — minion, 3 essence (3/3)
# ON PLAY: opponent traps cannot trigger this turn.
# ---------------------------------------------------------------------------

static func _saboteur_adept() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("saboteur_adept / opponent traps blocked this turn", state):
		return
	var adept := TestHarness.spawn_friendly(state, "saboteur_adept")
	var adept_data := adept.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "player", adept)
	EffectResolver.run(adept_data.on_play_effect_steps, ctx)
	TestHarness.assert_true(state._enemy_traps_blocked, "_enemy_traps_blocked = true")

# ---------------------------------------------------------------------------
# void_detonation — spell, 4 mana
# Deal 500 Void Bolt damage to enemy hero. +50 per Void Mark on enemy hero
# (Void Bolt pipeline adds another void_mark_damage_per_stack * marks on top).
# Enemy cast should scale with marks on PLAYER hero (symmetric) — KNOWN BUG:
# current code hardcodes marks=0 when owner != "player", and no player_void_marks
# field exists on SimState yet.
# ---------------------------------------------------------------------------

static func _void_detonation_base() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_detonation / base 500 dmg, no marks", state):
		return
	var hp_before := state.enemy_hp
	var spell := CardDatabase.get_card("void_detonation") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(hp_before - state.enemy_hp, 500, "enemy hp -500")

static func _void_detonation_with_marks() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_detonation / 2 marks → 500 + 100 base + 50*2 bolt bonus", state):
		return
	# Base: 500 + 50 * marks → 500 + 100 = 600
	# Void Bolt adds: void_mark_damage_per_stack (25) * marks (2) = 50 on top
	# Total: 650 (with default 25/stack)
	state.enemy_void_marks = 2
	var hp_before := state.enemy_hp
	var spell := CardDatabase.get_card("void_detonation") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	var dmg := hp_before - state.enemy_hp
	TestHarness.assert_eq(dmg, 650, "500 + 50*2 + 25*2 = 650")

static func _void_detonation_enemy_symmetric() -> void:
	# KNOWN BUGS (enemy cast):
	#   1. HardcodedEffects._void_detonation hardcodes marks=0 when owner != "player".
	#   2. _deal_void_bolt_damage unconditionally damages the "enemy" hero — so when
	#      enemy casts Void Detonation, it hits ITS OWN hero, not the player's.
	#   3. No player_void_marks field exists yet, so there's nowhere to read from.
	# This probe asserts the player hero takes 500 (base) on enemy cast, which will
	# fail until the hero-side target and mark-side plumbing are made symmetric.
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_detonation / enemy cast hits PLAYER hero (KNOWN BUG: self-hits, no player marks)", state):
		return
	var hp_before := state.player_hp
	var spell := CardDatabase.get_card("void_detonation") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "enemy"))
	TestHarness.assert_eq(hp_before - state.player_hp, 500, "player hero takes 500 (base)")

# ---------------------------------------------------------------------------
# smoke_veil — trap, 2 mana, trigger = ON_ENEMY_ATTACK
# Cancels the triggering attack. Exhausts all minions on the attacker's side.
# Increments _smoke_veil_fires; sums prevented ATK into _smoke_veil_damage_prevented.
# ---------------------------------------------------------------------------

static func _smoke_veil() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("smoke_veil / exhausts attacker board, tracks prevented dmg", state):
		return
	var a := TestHarness.spawn_enemy(state, "rabid_imp")
	var b := TestHarness.spawn_enemy(state, "rabid_imp")
	# make them attack-ready
	a.state = Enums.MinionState.NORMAL
	b.state = Enums.MinionState.NORMAL
	a.attack_count = 0
	b.attack_count = 0
	var expected_prev := a.effective_atk() + b.effective_atk()
	var fires_before := state._smoke_veil_fires
	var prev_before := state._smoke_veil_damage_prevented
	var trap := CardDatabase.get_card("smoke_veil") as TrapCardData
	EffectResolver.run(trap.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(a.state, Enums.MinionState.EXHAUSTED, "a exhausted")
	TestHarness.assert_eq(b.state, Enums.MinionState.EXHAUSTED, "b exhausted")
	TestHarness.assert_eq(state._smoke_veil_fires, fires_before + 1, "fires +1")
	TestHarness.assert_eq(state._smoke_veil_damage_prevented, prev_before + expected_prev, "prevented summed")

# ---------------------------------------------------------------------------
# silence_trap — trap, 2 mana, trigger = ON_ENEMY_SPELL_CAST
# Sets _spell_cancelled flag on the scene, to be read by the spell-cast pipeline.
# ---------------------------------------------------------------------------

static func _silence_trap() -> void:
	# KNOWN BUG: HardcodedEffects calls _scene.set("_spell_cancelled", true) but
	# _spell_cancelled is not a declared field on SimState. GDScript's set() on a
	# non-existent property is a silent no-op, so enemy spells never get cancelled
	# in sim. (Live CombatScene may or may not have the field — unverified.)
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("silence_trap / sets spell-cancel flag (KNOWN BUG: field missing on SimState)", state):
		return
	var trap := CardDatabase.get_card("silence_trap") as TrapCardData
	EffectResolver.run(trap.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state.get("_spell_cancelled"), true, "_spell_cancelled == true")

# ---------------------------------------------------------------------------
# runic_blast — spell, 2 mana
# If caster has 2+ Runes: 200 AoE to all opponent minions.
# Else: 200 damage to 2 random opponent minions.
# KNOWN BUG: in the 2-random mode, same minion can be picked twice. Should be distinct.
# ---------------------------------------------------------------------------

static func _runic_blast_under_2_runes() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("runic_blast / <2 runes: 200 to 2 random enemies", state):
		return
	var e1 := TestHarness.spawn_enemy(state, "rabid_imp")
	var e2 := TestHarness.spawn_enemy(state, "rabid_imp")
	e1.current_health = 1000
	e2.current_health = 1000
	var spell := CardDatabase.get_card("runic_blast") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	var total := (1000 - e1.current_health) + (1000 - e2.current_health)
	TestHarness.assert_eq(total, 400, "total damage = 2 * 200 = 400")

static func _runic_blast_2_plus_runes() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("runic_blast / 2+ runes: 200 AoE to all enemies", state):
		return
	# Put 2 runes in player's traps
	var rune1 := CardDatabase.get_card("soul_rune") as TrapCardData
	var rune2 := CardDatabase.get_card("dominion_rune") as TrapCardData
	state.active_traps.append(rune1)
	state.active_traps.append(rune2)
	var enemies: Array = []
	for i in 3:
		var e := TestHarness.spawn_enemy(state, "rabid_imp")
		e.current_health = 1000
		enemies.append(e)
	var spell := CardDatabase.get_card("runic_blast") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	for e in enemies:
		TestHarness.assert_eq(1000 - e.current_health, 200, "enemy took 200 (AoE)")

static func _runic_blast_distinct_targets() -> void:
	# KNOWN BUG: with exactly 2 minions and <2 runes, both picks can hit the same
	# minion. Run repeatedly; if any iteration deals 400 to one and 0 to the other,
	# the distinct-target rule is violated.
	if not TestHarness.begin_test("runic_blast / <2 runes: 2 random picks should be DISTINCT (KNOWN BUG)", null):
		return
	var seen_duplicate := false
	for trial in 10:
		var state := TestHarness.build_state({})
		var e1 := TestHarness.spawn_enemy(state, "rabid_imp")
		var e2 := TestHarness.spawn_enemy(state, "rabid_imp")
		e1.current_health = 1000
		e2.current_health = 1000
		var spell := CardDatabase.get_card("runic_blast") as SpellCardData
		EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
		var dmg1 := 1000 - e1.current_health
		var dmg2 := 1000 - e2.current_health
		if dmg1 == 400 or dmg2 == 400:
			seen_duplicate = true
			break
		state.teardown()
	TestHarness.assert_false(seen_duplicate, "no trial picked the same minion twice over 10 runs")

# ---------------------------------------------------------------------------
# runic_echo — spell, 2 mana
# Copy each of OWNER's runes (not opponent's) into owner's hand.
# ---------------------------------------------------------------------------

static func _runic_echo_own_runes_only() -> void:
	# KNOWN BUG: HardcodedEffects._runic_echo calls _add_to_owner_hand → SimState
	# calls turn_manager.add_instance_to_hand(inst), which doesn't exist on
	# SimTurnManager (only add_to_hand(CardData) does). Copy silently drops.
	# Probe asserts the intended behavior (hand +1) and will fail until either
	# add_instance_to_hand is added to SimTurnManager, or _runic_echo is rewritten
	# to use the existing API.
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("runic_echo / copies own runes only (KNOWN BUG: sim path drops the copy)", state):
		return
	var own_rune := CardDatabase.get_card("soul_rune") as TrapCardData
	var enemy_rune := CardDatabase.get_card("dominion_rune") as TrapCardData
	state.active_traps.append(own_rune)
	state.enemy_active_traps.append(enemy_rune)
	var hand_before := state.player_hand.size()
	var spell := CardDatabase.get_card("runic_echo") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state.player_hand.size(), hand_before + 1, "hand +1 (only own rune copied)")

# ---------------------------------------------------------------------------
# void_rift_lord — minion, 4 essence + 3 sparks (4/6 Spirit)
# ON PLAY: set opponent's mana to 0 next turn.
# Enemy cast sets _void_mana_drain_pending (drains player). Player cast should
# drain enemy — KNOWN BUG: current code only fires when opponent == "player".
# ---------------------------------------------------------------------------

static func _void_rift_lord_enemy_cast() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_rift_lord / enemy cast arms player mana drain", state):
		return
	var lord := TestHarness.spawn_enemy(state, "void_rift_lord")
	var lord_data := lord.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "enemy", lord)
	EffectResolver.run(lord_data.on_play_effect_steps, ctx)
	TestHarness.assert_eq(state.get("_void_mana_drain_pending"), true, "player mana drain pending")

static func _void_rift_lord_player_symmetric() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_rift_lord / player cast drains enemy mana next turn", state):
		return
	var lord := TestHarness.spawn_friendly(state, "void_rift_lord")
	var lord_data := lord.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "player", lord)
	EffectResolver.run(lord_data.on_play_effect_steps, ctx)
	TestHarness.assert_eq(state.get("_enemy_void_mana_drain_pending"), true, "enemy mana drain pending")

# ---------------------------------------------------------------------------
# frenzied_imp — minion, 3 essence (3/3 Demon, Feral Imp tag)
# ON PLAY: deal 100 damage to a random enemy minion, +100 per OTHER friendly feral imp.
# ---------------------------------------------------------------------------

static func _frenzied_imp_scaling() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("frenzied_imp / 100 + 100*other_feral_count to one enemy", state):
		return
	TestHarness.spawn_friendly(state, "rabid_imp")  # feral imp
	TestHarness.spawn_friendly(state, "rabid_imp")  # feral imp
	var source := TestHarness.spawn_friendly(state, "frenzied_imp")  # feral imp, source
	var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
	enemy.current_health = 1000
	var source_data := source.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "player", source)
	EffectResolver.run(source_data.on_play_effect_steps, ctx)
	# 2 other feral imps → 100 + 2*100 = 300
	TestHarness.assert_eq(1000 - enemy.current_health, 300, "damage = 100 + 2*100 = 300")

# ---------------------------------------------------------------------------
# void_screech — spell, 1 mana
# 250 damage to enemy hero. 350 if caster has 3+ Feral Imps on board.
# ---------------------------------------------------------------------------

static func _void_screech_under_3_imps() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_screech / <3 feral imps: 250 to enemy hero", state):
		return
	TestHarness.spawn_friendly(state, "rabid_imp")
	TestHarness.spawn_friendly(state, "rabid_imp")
	var hp_before := state.enemy_hp
	var spell := CardDatabase.get_card("void_screech") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(hp_before - state.enemy_hp, 250, "250 dmg")

static func _void_screech_3_plus_imps() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_screech / 3+ feral imps: 350 to enemy hero", state):
		return
	for i in 3:
		TestHarness.spawn_friendly(state, "rabid_imp")
	var hp_before := state.enemy_hp
	var spell := CardDatabase.get_card("void_screech") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(hp_before - state.enemy_hp, 350, "350 dmg")

# ---------------------------------------------------------------------------
# brood_call — spell, 2 mana
# Summons a random feral imp token to the caster's side. No on-play triggers.
# Pool: rabid_imp, brood_imp, imp_brawler, void_touched_imp, frenzied_imp,
#       matriarchs_broodling, rogue_imp_elder.
# ---------------------------------------------------------------------------

static func _brood_call_summons_feral() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("brood_call / summons one feral imp to caster side", state):
		return
	var before := state.player_board.size()
	var spell := CardDatabase.get_card("brood_call") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state.player_board.size(), before + 1, "player board +1")
	if state.player_board.size() > before:
		var summoned := state.player_board[-1] as MinionInstance
		var pool := ["rabid_imp", "brood_imp", "imp_brawler", "void_touched_imp",
				"frenzied_imp", "matriarchs_broodling", "rogue_imp_elder"]
		TestHarness.assert_true(summoned.card_data.id in pool, "summoned id is in feral pool (got %s)" % summoned.card_data.id)

# ---------------------------------------------------------------------------
# pack_frenzy — spell, 3 mana
# All friendly Feral Imps: +250 TEMP_ATK (clears at turn end). EXHAUSTED → SWIFT.
# Rider (undocumented in card text): +LIFEDRAIN if ancient_frenzy passive is active.
# ---------------------------------------------------------------------------

static func _pack_frenzy_buff() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("pack_frenzy / +250 temp ATK to all feral imps", state):
		return
	var imp := TestHarness.spawn_friendly(state, "rabid_imp")
	var atk_before := imp.effective_atk()
	imp.state = Enums.MinionState.EXHAUSTED
	imp.attack_count = 0
	var spell := CardDatabase.get_card("pack_frenzy") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(imp.effective_atk() - atk_before, 250, "+250 ATK")
	TestHarness.assert_eq(imp.state, Enums.MinionState.SWIFT, "exhausted → swift")

static func _pack_frenzy_ancient_frenzy_lifedrain() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["ancient_frenzy"]})
	if not TestHarness.begin_test("pack_frenzy / ancient_frenzy active → grants LIFEDRAIN rider", state):
		return
	# ancient_frenzy is an enemy passive; per the HardcodedEffects code it reads
	# `_active_enemy_passives`. The sim's SimTriggerSetup wires enemy passives
	# through a different mechanism — seed it directly for this probe.
	state.set("_active_enemy_passives", ["ancient_frenzy"])
	var imp := TestHarness.spawn_enemy(state, "rabid_imp")
	var spell := CardDatabase.get_card("pack_frenzy") as SpellCardData
	# Enemy casts Pack Frenzy so the ancient_frenzy check matters
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "enemy"))
	TestHarness.assert_true(imp.has_lifedrain(), "imp has LIFEDRAIN rider")

# ---------------------------------------------------------------------------
# void_imp — minion, 1 essence (1/1 Demon)
# ON PLAY: deal 100 to enemy hero (default).
# Under piercing_void talent, the entire on_play_effect_steps array is replaced
# via talent_overrides with [VOID_BOLT 200, VOID_MARK 1] — see _void_imp_piercing.
# ---------------------------------------------------------------------------

static func _void_imp_on_play() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_imp / on-play 100 dmg to enemy hero (no piercing_void)", state):
		return
	var hp_before := state.enemy_hp
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	var data := imp.card_data as MinionCardData
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", imp))
	TestHarness.assert_eq(hp_before - state.enemy_hp, 100, "enemy hp -100")

static func _senior_void_imp_on_play() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("senior_void_imp / on-play 100 dmg to enemy hero", state):
		return
	var hp_before := state.enemy_hp
	var sv := TestHarness.spawn_friendly(state, "senior_void_imp")
	var data := sv.card_data as MinionCardData
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", sv))
	TestHarness.assert_eq(hp_before - state.enemy_hp, 100, "enemy hp -100")

# ---------------------------------------------------------------------------
# runic_void_imp — DAMAGE_MINION 300 to chosen enemy minion.
# ---------------------------------------------------------------------------

static func _runic_void_imp_on_play() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("runic_void_imp / on-play 300 dmg to chosen enemy minion", state):
		return
	var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
	enemy.current_health = 1000
	var imp := TestHarness.spawn_friendly(state, "runic_void_imp")
	var data := imp.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "player", imp, enemy)
	EffectResolver.run(data.on_play_effect_steps, ctx)
	TestHarness.assert_eq(1000 - enemy.current_health, 300, "enemy minion -300")

# ---------------------------------------------------------------------------
# void_imp_wizard — VOID_BOLT 300 + VOID_MARK 1.
# ---------------------------------------------------------------------------

static func _void_imp_wizard_on_play() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_imp_wizard / on-play 300 void bolt + 1 void mark", state):
		return
	var hp_before := state.enemy_hp
	var marks_before := state.enemy_void_marks
	var wiz := TestHarness.spawn_friendly(state, "void_imp_wizard")
	var data := wiz.card_data as MinionCardData
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", wiz))
	# Base 300 + 25/stack * 0 marks (initial) = 300. Then mark applies post-damage.
	TestHarness.assert_eq(hp_before - state.enemy_hp, 300, "enemy hp -300")
	TestHarness.assert_eq(state.enemy_void_marks, marks_before + 1, "void marks +1")

# ---------------------------------------------------------------------------
# shadow_hound — BUFF_ATK +100 per OTHER friendly demon (excl. self).
# ---------------------------------------------------------------------------

static func _shadow_hound_scaling() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("shadow_hound / +100 ATK per other friendly demon", state):
		return
	# Seed 2 other friendly demons + the hound itself = 3 total demons.
	TestHarness.spawn_friendly(state, "void_imp")
	TestHarness.spawn_friendly(state, "void_imp")
	var hound := TestHarness.spawn_friendly(state, "shadow_hound")
	var atk_before := hound.effective_atk()
	var data := hound.card_data as MinionCardData
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", hound))
	TestHarness.assert_eq(hound.effective_atk() - atk_before, 200, "hound +200 ATK (2 other demons)")

# ---------------------------------------------------------------------------
# dark_empowerment — BUFF_ATK 150 always + BUFF_HP 150 if target is_demon.
# ---------------------------------------------------------------------------

static func _dark_empowerment_demon() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("dark_empowerment / demon target gets +150/+150", state):
		return
	var demon := TestHarness.spawn_friendly(state, "void_imp")  # Demon
	var atk_before := demon.effective_atk()
	var hp_before := demon.current_health
	var spell := CardDatabase.get_card("dark_empowerment") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, demon)
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(demon.effective_atk() - atk_before, 150, "demon +150 ATK")
	TestHarness.assert_eq(demon.current_health - hp_before, 150, "demon +150 HP")

static func _dark_empowerment_human() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("dark_empowerment / human target gets +150 ATK only (no HP)", state):
		return
	var human := TestHarness.spawn_friendly(state, "spell_taxer")  # Human
	var atk_before := human.effective_atk()
	var hp_before := human.current_health
	var spell := CardDatabase.get_card("dark_empowerment") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, human)
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(human.effective_atk() - atk_before, 150, "human +150 ATK")
	TestHarness.assert_eq(human.current_health, hp_before, "human HP unchanged (not a demon)")

# ---------------------------------------------------------------------------
# abyssal_sacrifice — SACRIFICE chosen friendly + DRAW 2.
# ---------------------------------------------------------------------------

static func _abyssal_sacrifice_draws_2() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("abyssal_sacrifice / sac + draw 2", state):
		return
	# Seed deck with 2 cards so DRAW 2 has something to pull.
	var imp := CardDatabase.get_card("void_imp")
	state.player_deck.append(CardInstance.create(imp))
	state.player_deck.append(CardInstance.create(imp))
	var sac := TestHarness.spawn_friendly(state, "void_imp")
	var hand_before := state.player_hand.size()
	var spell := CardDatabase.get_card("abyssal_sacrifice") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, sac)
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_false(state.player_board.has(sac), "sac removed")
	TestHarness.assert_eq(state.player_hand.size(), hand_before + 2, "hand +2 from draw")

# ---------------------------------------------------------------------------
# abyssal_plague — CORRUPTION + 100 dmg to all enemy minions.
# ---------------------------------------------------------------------------

static func _abyssal_plague_aoe() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("abyssal_plague / corrupts + 100 dmg to all enemy minions", state):
		return
	var e1 := TestHarness.spawn_enemy(state, "rabid_imp")
	var e2 := TestHarness.spawn_enemy(state, "rabid_imp")
	e1.current_health = 1000
	e2.current_health = 1000
	var spell := CardDatabase.get_card("abyssal_plague") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(1000 - e1.current_health, 100, "e1 -100")
	TestHarness.assert_eq(1000 - e2.current_health, 100, "e2 -100")
	TestHarness.assert_true(BuffSystem.has_type(e1, Enums.BuffType.CORRUPTION), "e1 corrupted")
	TestHarness.assert_true(BuffSystem.has_type(e2, Enums.BuffType.CORRUPTION), "e2 corrupted")

# ---------------------------------------------------------------------------
# void_summoning — SUMMON 300/300 demon, OR 400/400 if friendly Human present.
# ---------------------------------------------------------------------------

static func _void_summoning_no_human() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_summoning / no friendly human → summon 300/300", state):
		return
	var board_before := state.player_board.size()
	var spell := CardDatabase.get_card("void_summoning") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state.player_board.size(), board_before + 1, "+1 minion summoned")
	if state.player_board.size() > board_before:
		var demon := state.player_board[-1] as MinionInstance
		TestHarness.assert_eq(demon.current_atk, 300, "summoned ATK = 300")
		TestHarness.assert_eq(demon.current_health, 300, "summoned HP = 300")

static func _void_summoning_with_human() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_summoning / friendly human present → summon 400/400", state):
		return
	TestHarness.spawn_friendly(state, "spell_taxer")  # Human
	var board_size_before := state.player_board.size()
	var spell := CardDatabase.get_card("void_summoning") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state.player_board.size(), board_size_before + 1, "+1 demon summoned")
	if state.player_board.size() > board_size_before:
		var demon := state.player_board[-1] as MinionInstance
		TestHarness.assert_eq(demon.current_atk, 400, "summoned ATK = 400")
		TestHarness.assert_eq(demon.current_health, 400, "summoned HP = 400")

# ---------------------------------------------------------------------------
# void_spawning — 2x SUMMON 100/100 void_demon.
# ---------------------------------------------------------------------------

static func _void_spawning_2_demons() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("void_spawning / summons 2 void_demon tokens", state):
		return
	var board_before := state.player_board.size()
	var spell := CardDatabase.get_card("void_spawning") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state.player_board.size(), board_before + 2, "+2 minions")

# ---------------------------------------------------------------------------
# flesh_rend — DAMAGE_MINION 300 to chosen target, +300 if flesh >= 3.
# ---------------------------------------------------------------------------

static func _flesh_rend_base() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("flesh_rend / 300 dmg base when flesh < 3", state):
		return
	state.player_flesh = 2  # below threshold
	var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
	enemy.current_health = 1000
	var spell := CardDatabase.get_card("flesh_rend") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, enemy)
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(1000 - enemy.current_health, 300, "enemy -300 (base)")

static func _flesh_rend_doubled() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("flesh_rend / 600 dmg when flesh >= 3", state):
		return
	state.player_flesh = 3
	var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
	enemy.current_health = 1000
	var spell := CardDatabase.get_card("flesh_rend") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, enemy)
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(1000 - enemy.current_health, 600, "enemy -600 (doubled)")

# ---------------------------------------------------------------------------
# flesh_harvester — ON PLAY: GAIN_FLESH 1.
# ---------------------------------------------------------------------------

static func _flesh_harvester_gains_flesh() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("flesh_harvester / on-play +1 Flesh", state):
		return
	state.player_flesh = 0
	var harv := TestHarness.spawn_friendly(state, "flesh_harvester")
	var data := harv.card_data as MinionCardData
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", harv))
	TestHarness.assert_eq(state.player_flesh, 1, "Flesh +1")

# ---------------------------------------------------------------------------
# ravenous_fiend — ON DEATH: GAIN_FLESH 2.
# ---------------------------------------------------------------------------

static func _ravenous_fiend_on_death_flesh() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("ravenous_fiend / on-death +2 Flesh (capped)", state):
		return
	state.player_flesh = 0
	var rf := TestHarness.spawn_friendly(state, "ravenous_fiend")
	# kill_minion fires on-death effect via the death-handler chain. Fleshbind
	# also fires (+1) since rf is a Demon; total expected: 0 +2 (on-death) +1 (fleshbind) = 3.
	state.combat_manager.kill_minion(rf)
	TestHarness.assert_eq(state.player_flesh, 3, "Flesh +3 (2 on-death + 1 fleshbind)")

# ---------------------------------------------------------------------------
# feast_of_flesh — SACRIFICE friendly demon + GAIN_FLESH 2 + DRAW 1.
# ---------------------------------------------------------------------------

static func _feast_of_flesh_combo() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("feast_of_flesh / sac + 2 flesh + draw 1", state):
		return
	state.player_flesh = 0
	# Seed deck for draw
	state.player_deck.append(CardInstance.create(CardDatabase.get_card("void_imp")))
	var sac := TestHarness.spawn_friendly(state, "void_imp")
	var hand_before := state.player_hand.size()
	var spell := CardDatabase.get_card("feast_of_flesh") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, sac)
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_false(state.player_board.has(sac), "sac removed")
	# Sacrifice fires fleshbind (per the recent CombatSetup edit) → +1, then GAIN_FLESH +2 → 3
	TestHarness.assert_eq(state.player_flesh, 3, "Flesh +1 (sac fleshbind) +2 (gain) = 3")
	TestHarness.assert_eq(state.player_hand.size(), hand_before + 1, "hand +1 from draw")

# ---------------------------------------------------------------------------
# mend_the_flesh — HEAL 200 base, +150 if 1 Flesh spent.
# ---------------------------------------------------------------------------

static func _mend_the_flesh_no_flesh() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("mend_the_flesh / no flesh → heal 0 (spend fails, no heal triggers)", state):
		return
	state.player_flesh = 0
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	imp.current_health = 50  # damaged
	var hp_before := imp.current_health
	var spell := CardDatabase.get_card("mend_the_flesh") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	# SPEND_FLESH 1 fails (0 < 1). bonus_conditions ["flesh_spent_this_cast"] is
	# false → bonus_amount NOT applied. But the BASE amount=200 still applies
	# because the step's `conditions` is empty. Expected: heal 200.
	TestHarness.assert_eq(imp.current_health - hp_before, 50, "imp healed 50 (capped at 100 base HP)")

static func _mend_the_flesh_with_flesh() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("mend_the_flesh / 1 flesh → heal 350, spend 1", state):
		return
	state.player_flesh = 1
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	imp.current_health = 50
	var spell := CardDatabase.get_card("mend_the_flesh") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(state.player_flesh, 0, "1 flesh spent")
	# Base HP = 100 (void_imp). 50 + 350 healing = 400 capped to 100.
	TestHarness.assert_eq(imp.current_health, 100, "imp HP capped at base 100")

# ---------------------------------------------------------------------------
# flesh_eruption — DAMAGE_MINION 250 + DAMAGE_HERO 250 to all enemies.
# +150 each if 2 Flesh spent.
# ---------------------------------------------------------------------------

static func _flesh_eruption_no_flesh() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("flesh_eruption / no flesh → 250 to enemies + hero", state):
		return
	state.player_flesh = 1  # below threshold
	var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
	enemy.current_health = 1000
	var hp_before := state.enemy_hp
	var spell := CardDatabase.get_card("flesh_eruption") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(1000 - enemy.current_health, 250, "enemy minion -250")
	TestHarness.assert_eq(hp_before - state.enemy_hp, 250, "enemy hero -250")
	TestHarness.assert_eq(state.player_flesh, 1, "no flesh spent (insufficient)")

static func _flesh_eruption_with_flesh() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("flesh_eruption / 2 flesh → 400 to enemies + hero", state):
		return
	state.player_flesh = 2
	var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
	enemy.current_health = 1000
	var hp_before := state.enemy_hp
	var spell := CardDatabase.get_card("flesh_eruption") as SpellCardData
	EffectResolver.run(spell.effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(1000 - enemy.current_health, 400, "enemy minion -400 (boosted)")
	TestHarness.assert_eq(hp_before - state.enemy_hp, 400, "enemy hero -400 (boosted)")
	TestHarness.assert_eq(state.player_flesh, 0, "2 flesh spent")

# ---------------------------------------------------------------------------
# gorged_fiend — SPEND_FLESH_UP_TO 3, then BUFF_ATK +150 * spent + BUFF_HP +150 * spent.
# ---------------------------------------------------------------------------

static func _gorged_fiend_scaling() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("gorged_fiend / 2 flesh available → +300/+300 (spend 2)", state):
		return
	state.player_flesh = 2
	var fiend := TestHarness.spawn_friendly(state, "gorged_fiend")
	var atk_before := fiend.effective_atk()
	var hp_before := fiend.current_health
	var data := fiend.card_data as MinionCardData
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", fiend))
	TestHarness.assert_eq(state.player_flesh, 0, "2 flesh spent (up-to 3 = 2 actual)")
	TestHarness.assert_eq(fiend.effective_atk() - atk_before, 300, "ATK +150 * 2 = +300")
	TestHarness.assert_eq(fiend.current_health - hp_before, 300, "HP +150 * 2 = +300")

# ---------------------------------------------------------------------------
# flesh_stitched_horror — SPEND_FLESH 2 (all-or-nothing), gate GUARD + +300 HP.
# ---------------------------------------------------------------------------

static func _flesh_stitched_horror_with_flesh() -> void:
	var state := TestHarness.seris_state()
	if not TestHarness.begin_test("flesh_stitched_horror / 2 flesh → GUARD + +300 HP", state):
		return
	state.player_flesh = 2
	var horror := TestHarness.spawn_friendly(state, "flesh_stitched_horror")
	var hp_before := horror.current_health
	var data := horror.card_data as MinionCardData
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", horror))
	TestHarness.assert_eq(state.player_flesh, 0, "2 flesh spent")
	TestHarness.assert_eq(horror.current_health - hp_before, 300, "HP +300")
	TestHarness.assert_true(horror.has_guard(), "GUARD granted")

# ---------------------------------------------------------------------------
# Korrath Core Pool (task 023)
# ---------------------------------------------------------------------------
# Cards: squire_of_the_order (FORMATION → knight cost -2 in hand),
# order_conscript (ADD_CARD order_footman), quartermaster (+100 Armour aura via
# on_friendly_summon_aura_steps dispatcher), shatterstrike (400 PHYSICAL spell).
# Rally the Ranks lives under task 038 along with its infra prerequisites.

## Squire's Formation runs the HARDCODED step that decrements essence_delta on every
## Abyssal Knight currently in the caster's hand. Seed two knights + one non-knight,
## fire the steps, expect -2 on the knights and 0 on the non-knight.
static func _squire_of_the_order_discounts_knights_in_hand() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("squire_of_the_order / formation discounts all Abyssal Knights in hand by 2", state):
		return
	var k1 := CardInstance.create(CardDatabase.get_card("abyssal_knight"))
	var k2 := CardInstance.create(CardDatabase.get_card("abyssal_knight"))
	var other := CardInstance.create(CardDatabase.get_card("void_imp"))
	state.player_hand.append(k1)
	state.player_hand.append(k2)
	state.player_hand.append(other)
	var squire_data := CardDatabase.get_card("squire_of_the_order") as MinionCardData
	EffectResolver.run(squire_data.formation_effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(k1.essence_delta, -2, "first Knight discount = -2")
	TestHarness.assert_eq(k2.essence_delta, -2, "second Knight discount = -2")
	TestHarness.assert_eq(other.essence_delta, 0, "non-Knight unaffected")

## No knights in hand → handler runs but mutates nothing.
static func _squire_of_the_order_no_knights_in_hand_is_noop() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("squire_of_the_order / formation with no Knights in hand is a clean no-op", state):
		return
	var other := CardInstance.create(CardDatabase.get_card("void_imp"))
	state.player_hand.append(other)
	var hand_size_before: int = state.player_hand.size()
	var squire_data := CardDatabase.get_card("squire_of_the_order") as MinionCardData
	EffectResolver.run(squire_data.formation_effect_steps, TestHarness.make_ctx(state, "player"))
	TestHarness.assert_eq(other.essence_delta, 0, "non-Knight still 0")
	TestHarness.assert_eq(state.player_hand.size(), hand_size_before, "hand size unchanged")

## Order Conscript ON_PLAY: ADD_CARD pushes an order_footman CardInstance into hand.
static func _order_conscript_adds_footman_to_hand() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("order_conscript / ON PLAY adds an Order Footman to hand", state):
		return
	var conscript := TestHarness.spawn_friendly(state, "order_conscript")
	var data := conscript.card_data as MinionCardData
	var before := state.player_hand.size()
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", conscript))
	TestHarness.assert_eq(state.player_hand.size(), before + 1, "hand grew by 1")
	var added: CardInstance = state.player_hand[state.player_hand.size() - 1]
	TestHarness.assert_eq(added.card_data.id, "order_footman", "added card is order_footman")
	TestHarness.assert_eq((added.card_data as MinionCardData).essence_cost, 1, "footman costs 1 Essence")

## Quartermaster aura dispatcher: fire ON_PLAYER_MINION_SUMMONED with a new minion,
## expect that minion to gain +100 Armour. Pre-place the new minion and the
## Quartermaster on the board, then fire the trigger event manually.
static func _quartermaster_buffs_new_friendly_summon_armour() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("quartermaster / on-friendly-summon aura grants +100 Armour to new minion", state):
		return
	var qm := TestHarness.spawn_friendly(state, "quartermaster")
	var newcomer := TestHarness.spawn_friendly(state, "void_imp")
	var armour_before: int = newcomer.armour
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": newcomer})
	TestHarness.assert_eq(newcomer.armour - armour_before, 100, "newcomer gained +100 Armour")
	TestHarness.assert_eq(qm.armour, 0, "Quartermaster itself unaffected")

## "Does not self-buff": Quartermaster's own summon event should NOT trigger its aura on itself.
## Sim the moment of Quartermaster's own summon by firing the event with qm as ctx.minion;
## the dispatcher must skip the source when src == summoned.
static func _quartermaster_does_not_self_buff() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("quartermaster / does not self-buff at its own summon event", state):
		return
	var qm := TestHarness.spawn_friendly(state, "quartermaster")
	var armour_before: int = qm.armour
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": qm})
	TestHarness.assert_eq(qm.armour, armour_before, "self-summon adds no Armour to self")

## Two Quartermasters on the same side should stack: +200 Armour per friendly summon.
static func _quartermaster_stacks_with_two_sources() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("quartermaster / two on board stack to +200 Armour per summon", state):
		return
	var qm1 := TestHarness.spawn_friendly(state, "quartermaster")
	var qm2 := TestHarness.spawn_friendly(state, "quartermaster")
	var newcomer := TestHarness.spawn_friendly(state, "void_imp")
	var armour_before: int = newcomer.armour
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": newcomer})
	TestHarness.assert_eq(newcomer.armour - armour_before, 200, "stacks to +200 from two Quartermasters")
	TestHarness.assert_eq(qm1.armour, 0, "qm1 unaffected")
	TestHarness.assert_eq(qm2.armour, 0, "qm2 unaffected")

## Shatterstrike: 400 PHYSICAL to a chosen enemy minion. Pick a target with 0 armour
## and 1000 HP so the raw 400 lands cleanly; armour math is tested separately.
static func _shatterstrike_deals_physical_to_minion() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("shatterstrike / 400 PHYSICAL to a chosen enemy minion", state):
		return
	var target := TestHarness.spawn_enemy(state, "rabid_imp")
	target.current_health = 1000
	var spell := CardDatabase.get_card("shatterstrike") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, target)
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(1000 - target.current_health, 400, "target took 400 PHYSICAL")

# ---------------------------------------------------------------------------
# Rally the Ranks (task 038)
# ---------------------------------------------------------------------------
# 2M spell. Target a friendly Human OR Demon; summon up to 2 race-matched
# rank_and_file tokens (200/100) into the slots adjacent to the target. Dual-tag
# targets need a race pick at cast time (modal in live, heuristic in sim) which
# arrives via ctx.extra_cast_data["rally_race"]. Adjacent slots that are
# occupied or off-board silently fizzle ("up to 2" semantics).

## Single-tag Human target in the middle slot → 2 Human tokens flanking.
static func _rally_human_target_spawns_two_human_tokens() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("rally_the_ranks / Human target → 2 rank_and_file_h flanking", state):
		return
	var target := TestHarness.spawn_friendly_at(state, "order_conscript", 2)  # Human
	var spell := CardDatabase.get_card("rally_the_ranks") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, target, {"rally_race": "human"})
	EffectResolver.run(spell.effect_steps, ctx)
	var left: MinionInstance = state.player_slots[1].minion
	var right: MinionInstance = state.player_slots[3].minion
	TestHarness.assert_true(left != null and left.card_data.id == "rank_and_file_h", "left slot has rank_and_file_h")
	TestHarness.assert_true(right != null and right.card_data.id == "rank_and_file_h", "right slot has rank_and_file_h")

## Single-tag Demon target → 2 Demon tokens flanking.
static func _rally_demon_target_spawns_two_demon_tokens() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("rally_the_ranks / Demon target → 2 rank_and_file_d flanking", state):
		return
	var target := TestHarness.spawn_friendly_at(state, "void_imp", 2)  # Demon
	var spell := CardDatabase.get_card("rally_the_ranks") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, target, {"rally_race": "demon"})
	EffectResolver.run(spell.effect_steps, ctx)
	var left: MinionInstance = state.player_slots[1].minion
	var right: MinionInstance = state.player_slots[3].minion
	TestHarness.assert_true(left != null and left.card_data.id == "rank_and_file_d", "left slot has rank_and_file_d")
	TestHarness.assert_true(right != null and right.card_data.id == "rank_and_file_d", "right slot has rank_and_file_d")

## Dual-tag target (Squire of the Order — Human+Demon) with race=human → Human tokens.
static func _rally_dual_tag_target_with_human_choice() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("rally_the_ranks / dual-tag target + rally_race=human → 2 rank_and_file_h", state):
		return
	var target := TestHarness.spawn_friendly_at(state, "squire_of_the_order", 2)  # Human+Demon
	var spell := CardDatabase.get_card("rally_the_ranks") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, target, {"rally_race": "human"})
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(state.player_slots[1].minion.card_data.id, "rank_and_file_h", "left = rank_and_file_h")
	TestHarness.assert_eq(state.player_slots[3].minion.card_data.id, "rank_and_file_h", "right = rank_and_file_h")

## Dual-tag target with race=demon → Demon tokens.
static func _rally_dual_tag_target_with_demon_choice() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("rally_the_ranks / dual-tag target + rally_race=demon → 2 rank_and_file_d", state):
		return
	var target := TestHarness.spawn_friendly_at(state, "squire_of_the_order", 2)
	var spell := CardDatabase.get_card("rally_the_ranks") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, target, {"rally_race": "demon"})
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(state.player_slots[1].minion.card_data.id, "rank_and_file_d", "left = rank_and_file_d")
	TestHarness.assert_eq(state.player_slots[3].minion.card_data.id, "rank_and_file_d", "right = rank_and_file_d")

## Edge-slot target (slot 0) → only right token spawns; left is off-board.
static func _rally_edge_slot_target_only_right_spawns() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("rally_the_ranks / edge slot (0) → only right token spawns", state):
		return
	var target := TestHarness.spawn_friendly_at(state, "order_conscript", 0)
	var spell := CardDatabase.get_card("rally_the_ranks") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, target, {"rally_race": "human"})
	EffectResolver.run(spell.effect_steps, ctx)
	var right: MinionInstance = state.player_slots[1].minion
	TestHarness.assert_true(right != null and right.card_data.id == "rank_and_file_h", "right (slot 1) has rank_and_file_h")
	# Confirm no token leaked into any other slot
	var token_count := 0
	for s in state.player_slots:
		if s.minion != null and s.minion.card_data.id == "rank_and_file_h":
			token_count += 1
	TestHarness.assert_eq(token_count, 1, "exactly 1 token spawned at edge")

## Both adjacent slots occupied → 0 tokens spawn, no crash.
static func _rally_both_adjacent_occupied_zero_tokens() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("rally_the_ranks / both adjacent slots occupied → 0 tokens spawn", state):
		return
	var target := TestHarness.spawn_friendly_at(state, "order_conscript", 2)
	var blocker_left := TestHarness.spawn_friendly_at(state, "void_imp", 1)
	var blocker_right := TestHarness.spawn_friendly_at(state, "void_imp", 3)
	var spell := CardDatabase.get_card("rally_the_ranks") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, target, {"rally_race": "human"})
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(state.player_slots[1].minion, blocker_left, "left blocker untouched")
	TestHarness.assert_eq(state.player_slots[3].minion, blocker_right, "right blocker untouched")
	var token_count := 0
	for s in state.player_slots:
		if s.minion != null and s.minion.card_data.id == "rank_and_file_h":
			token_count += 1
	TestHarness.assert_eq(token_count, 0, "no rank_and_file_h spawned")

## One adjacent slot occupied → 1 token spawns in the free slot.
static func _rally_one_adjacent_occupied_one_token() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("rally_the_ranks / one adjacent slot occupied → 1 token in free slot", state):
		return
	var target := TestHarness.spawn_friendly_at(state, "order_conscript", 2)
	var blocker_left := TestHarness.spawn_friendly_at(state, "void_imp", 1)
	var spell := CardDatabase.get_card("rally_the_ranks") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, target, {"rally_race": "human"})
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(state.player_slots[1].minion, blocker_left, "left blocker untouched")
	TestHarness.assert_eq(state.player_slots[3].minion.card_data.id, "rank_and_file_h", "right has rank_and_file_h")

## No race in extra_cast_data → all 4 conditional SUMMON steps fail their gate → 0 tokens.
static func _rally_no_race_in_extra_data_zero_tokens() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("rally_the_ranks / no rally_race in extra_cast_data → 0 tokens spawn", state):
		return
	var target := TestHarness.spawn_friendly_at(state, "order_conscript", 2)
	var spell := CardDatabase.get_card("rally_the_ranks") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player", null, target, {})  # empty extra_cast_data
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_true(state.player_slots[1].is_empty(), "left slot still empty")
	TestHarness.assert_true(state.player_slots[3].is_empty(), "right slot still empty")

## Sim race-pick heuristic: more Humans → "human"; more Demons (or tie) → "demon".
static func _rally_sim_race_heuristic() -> void:
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("rally_the_ranks / sim heuristic picks dominant race (tie → demon)", state):
		return
	# Empty board → tie 0/0 → "demon"
	TestHarness.assert_eq(state._rally_pick_race_for("player"), "demon", "empty board → demon (tie)")
	# Seed 2 Humans, 1 Demon → "human"
	TestHarness.spawn_friendly(state, "order_conscript")  # Human
	TestHarness.spawn_friendly(state, "order_conscript")  # Human
	TestHarness.spawn_friendly(state, "void_imp")         # Demon
	TestHarness.assert_eq(state._rally_pick_race_for("player"), "human", "2H/1D → human")
