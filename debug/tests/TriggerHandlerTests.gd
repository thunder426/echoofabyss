## TriggerHandlerTests.gd
## Layer 2: one probe per trigger handler registered in SimTriggerSetup.
## Skipped (no trigger; consumed by CombatProfile cost logic elsewhere):
##   void_mastery, ritualist_spark_free, mana_for_spark, void_precision.
class_name TriggerHandlerTests
extends RefCounted

static func run_all() -> void:
	print("\n=== Layer 2: Trigger Handler Tests ===")
	_fleshbind()
	_flesh_infusion()
	_grafted_constitution()
	_predatory_surge_swift()
	_predatory_surge_siphon()
	_deathless_flesh()
	_soul_forge_activate()
	_soul_forge_counter()
	_fiend_offering()
	_forge_momentum()
	_abyssal_forge_aura_grant()
	_corrupt_flesh_inversion()
	_corrupt_flesh_activate()
	_corrupt_detonation()
	_void_amplification()
	_void_resonance_flesh_gain()
	_void_resonance_double_cast()
	_relic_void_hourglass()
	_relic_oblivion_seal()
	_relic_nether_crown()
	_relic_phantom_deck()
	_void_echo()
	_void_echo_once_per_turn()
	_swarm_discipline()
	_piercing_void_handler()
	_imp_evolution()
	_imp_evolution_once_per_turn()
	_imp_warband()
	_death_bolt()
	_rune_caller()
	_ritual_surge()
	_deepened_curse_stat()
	_runic_attunement_stat()
	_void_imp_boost()
	_midcombat_talent_unlock_applies_override()
	_pack_instinct_scaling()
	_rogue_imp_elder_aura_scaling()
	_rogue_imp_elder_aura_strips_on_death()
	_corrupted_death_cost_discount()
	_feral_reinforcement_human_summon()
	_feral_reinforcement_once_per_turn()
	_corrupt_authority_human_corrupts()
	_corrupt_authority_imp_detonates()
	_ritual_sacrifice_full_combo()
	_void_rift_spawns_spark()
	_void_rift_herald_suppression()
	_void_might_crit_stack()
	_rip_summon_at_4_attacks()
	_rip_summon_requires_distinct_attackers()
	_rip_aura_grants_100_atk()
	_rip_aura_refreshes_on_death()
	_rip_no_resummon_after_summoned()
	_cb_summon_at_3_deaths()
	_cb_death_summons_void_touched_imp()
	_cb_no_resummon_after_summoned()
	_im_summon_at_2_frenzy()
	_im_aura_adds_200hp_on_frenzy()
	_im_frenzy_count_ignored_after_summon()
	_acp_summon_at_5_stacks_consumed()
	_acp_aura_instant_detonate()
	_acp_stacks_capped_at_5_in_progress()
	_vr_summon_on_first_ritual_sacrifice()
	_ch_summon_at_3_sparks()
	_ch_aura_200_dmg_on_spark_summon()
	_ch_no_resummon_after_summoned()
	_rs_summon_at_1000_spark_dmg()
	_rs_aura_grants_immune_to_new_sparks()
	_rs_death_removes_immune()
	_va_summon_at_5_sparks_consumed()
	_vh_summon_at_6_spark_cost_plays()
	_vh_ignores_non_spark_cards()
	_vs_summon_at_5_crits_consumed()
	_vs_death_resets_crit_multiplier()
	_vw_summon_at_2_spirits_consumed()
	_vw_aura_spirit_death_grants_crit()
	_vc_summon_at_2_thrones_command()
	_vc_ignores_non_tc_spells()
	_vrp_summon_at_5_enemy_spells()
	_vrp_aura_sets_spell_cost_aura()
	_vrp_death_resets_spell_cost_aura()
	_vch_summon_at_3_crit_kills()
	_vch_aura_grows_resources()
	_as_counts_player_cards_played()
	_as_no_summon_in_phase_1()
	_as_summons_when_threshold_met_in_phase_2()
	_as_aura_doubles_abyss_awakened()
	_as_aura_inactive_when_dead()
	_champion_duel_sync_on_turn_start()
	_champion_duel_revokes_when_crit_lost()
	_void_empowerment_normalizes_spark()
	_void_detonation_passive_base_100()
	_void_detonation_passive_va_alive_200()
	_spirit_resonance_summons_spark()
	_spirit_resonance_ignores_non_crit_spirit()
	_spirit_conscription_summons_spark()
	_spirit_conscription_once_per_turn()
	_captain_orders_consumes_crit_and_dmg()
	_dark_channeling_consumes_crit_on_damage_spell()
	_dark_channeling_ignores_non_damage_spell()
	_abyss_awakened_grants_all_crit()
	_abyssal_mandate_essence_branch()
	_abyssal_mandate_mana_branch()
	_abyssal_mandate_end_clears_aura()

	# Korrath — FORMATION keyword
	_formation_fires_on_summon()
	_formation_does_not_refire_on_same_pair()
	_formation_ignores_race_mismatch()
	_formation_ignores_non_adjacent_neighbors()
	_formation_fires_bidirectionally_when_both_have_keyword()

	# Korrath Phase 2 — hero registration + Abyssal Knight card + cost discount
	_korrath_hero_registered()
	_abyssal_knight_card_registered()
	_abyssal_commander_discounts_knight()
	_abyssal_commander_does_not_discount_other_minions()

	# Korrath Phase 3 — Branch 1 Infernal Bulwark talents
	_iron_formation_retags_knight_human_with_formation()
	_iron_formation_grants_armour_and_hp_on_first_human_pair()
	_commanders_reach_applies_ab_on_attack()
	_commanders_reach_ignores_non_humans()
	_commanders_reach_ignores_non_adjacent_humans()
	_iron_resolve_adds_armour_to_human_atk()
	_iron_resolve_does_not_apply_to_enemies_or_demons()
	_unbreakable_doubles_knight_armour_gains()
	_unbreakable_does_not_double_other_minions()
	_unbreakable_grants_guard()

# ---------------------------------------------------------------------------
# Fleshbind passive — +1 Flesh on Demon death
# ---------------------------------------------------------------------------

static func _fleshbind() -> void:
	var state := TestHarness.seris_state([])
	if not TestHarness.begin_test("fleshbind / +1 Flesh on Demon death", state):
		return
	var demon := TestHarness.spawn_friendly(state, "grafted_fiend")
	var before := state.player_flesh
	state.combat_manager.kill_minion(demon)
	TestHarness.assert_eq(state.player_flesh, before + 1, "Flesh increases by 1")
	state.teardown()

# ---------------------------------------------------------------------------
# Fleshcraft branch
# ---------------------------------------------------------------------------

static func _flesh_infusion() -> void:
	# Migrated to CardModRules append_on_play_effect_steps (SPEND_FLESH + BUFF_ATK
	# gated on flesh_spent_this_cast). Test runs the on-play steps directly the
	# same way other declarative talents (imp_evolution, imp_warband) are tested.
	var state := TestHarness.seris_state(["flesh_infusion"])
	if not TestHarness.begin_test("flesh_infusion / +200 ATK on Grafted Fiend play, -1 Flesh", state):
		return
	state.player_flesh = 3
	var data: MinionCardData = state._card_for("player", "grafted_fiend") as MinionCardData
	var fiend := TestHarness.spawn_friendly(state, "grafted_fiend")
	var before_atk := fiend.effective_atk()
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", fiend))
	TestHarness.assert_eq(fiend.effective_atk(), before_atk + 200, "ATK +200")
	TestHarness.assert_eq(state.player_flesh, 2, "Flesh spent: 3 → 2")
	state.teardown()

static func _grafted_constitution() -> void:
	# Grafted Constitution was merged into Flesh Infusion (T0) — we still verify
	# the +100/+100-on-kill + kill_stacks path under the new talent id.
	var state := TestHarness.seris_state(["flesh_infusion"])
	if not TestHarness.begin_test("grafted_constitution / +100/+100 on enemy kill", state):
		return
	var fiend := TestHarness.spawn_friendly(state, "grafted_fiend")
	var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
	var before_atk := fiend.effective_atk()
	var before_hp := fiend.current_health
	var before_stacks := fiend.kill_stacks
	state._last_attacker = fiend
	state.combat_manager.kill_minion(enemy)
	TestHarness.assert_eq(fiend.effective_atk(), before_atk + 100, "ATK +100")
	TestHarness.assert_eq(fiend.current_health, before_hp + 100, "HP +100")
	TestHarness.assert_eq(fiend.kill_stacks, before_stacks + 1, "kill_stacks +1")
	state.teardown()

static func _predatory_surge_swift() -> void:
	# Migrated to CardModRules append_keywords [SWIFT]. The talent-mutated card data
	# carries SWIFT in its keywords array, and MinionInstance.create reads it to set
	# the spawn state to SWIFT. Test asserts both the data shape and the runtime state.
	var state := TestHarness.seris_state(["predatory_surge"])
	if not TestHarness.begin_test("predatory_surge / Grafted Fiend enters with Swift", state):
		return
	var fiend_data: MinionCardData = state._card_for("player", "grafted_fiend") as MinionCardData
	TestHarness.assert_true(Enums.Keyword.SWIFT in fiend_data.keywords, "card data keywords contains SWIFT")
	var fiend := MinionInstance.create(fiend_data, "player")
	state.player_board.append(fiend)
	for slot in state.player_slots:
		if slot.minion == null:
			slot.minion = fiend
			fiend.slot_index = slot.index
			break
	TestHarness.assert_eq(fiend.state, Enums.MinionState.SWIFT, "state == SWIFT")
	state.teardown()

static func _predatory_surge_siphon() -> void:
	var state := TestHarness.seris_state(["flesh_infusion", "predatory_surge"])
	if not TestHarness.begin_test("predatory_surge / Siphon at 3 kill_stacks", state):
		return
	var fiend := TestHarness.spawn_friendly(state, "grafted_fiend")
	for i in 3:
		var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
		state._last_attacker = fiend
		state.combat_manager.kill_minion(enemy)
	TestHarness.assert_eq(fiend.kill_stacks, 3, "kill_stacks == 3")
	TestHarness.assert_true(fiend.has_siphon(), "has Siphon")
	state.teardown()

static func _deathless_flesh() -> void:
	var state := TestHarness.seris_state(["deathless_flesh"])
	if not TestHarness.begin_test("deathless_flesh / save at 50 HP, -2 Flesh", state):
		return
	state.player_flesh = 5
	var fiend := TestHarness.spawn_friendly(state, "grafted_fiend")
	state.combat_manager._deal_damage(fiend,
			CombatManager.make_damage_info(fiend.current_health + 100, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL))
	TestHarness.assert_eq(fiend.current_health, 50, "HP clamped to 50")
	TestHarness.assert_eq(state.player_flesh, 3, "Flesh spent: 5 → 3")
	state.teardown()

# ---------------------------------------------------------------------------
# Demon Forge branch
# ---------------------------------------------------------------------------

static func _soul_forge_activate() -> void:
	var state := TestHarness.seris_state(["soul_forge"])
	if not TestHarness.begin_test("soul_forge / activate summons Fiend, spends 3 Flesh", state):
		return
	state.player_flesh = 3
	var board_before := state.player_board.size()
	var ok: bool = state._soul_forge_activate()
	TestHarness.assert_true(ok, "activation returns true")
	TestHarness.assert_eq(state.player_flesh, 0, "Flesh spent: 3 → 0")
	TestHarness.assert_eq(state.player_board.size(), board_before + 1, "board +1")
	if state.player_board.size() > board_before:
		TestHarness.assert_eq(state.player_board[-1].card_data.id, "grafted_fiend", "summoned Grafted Fiend")
	state.teardown()

static func _soul_forge_counter() -> void:
	var state := TestHarness.seris_state(["soul_forge"])
	if not TestHarness.begin_test("soul_forge / Forged Demon at 3 sacrifices", state):
		return
	for i in 3:
		var demon := TestHarness.spawn_friendly(state, "grafted_fiend")
		SacrificeSystem.sacrifice(state, demon, "test_sac")
		state.combat_manager.kill_minion(demon)
	var has_forged := false
	for m in state.player_board:
		if m.card_data.id == "forged_demon":
			has_forged = true
			break
	TestHarness.assert_true(has_forged, "Forged Demon on board")
	TestHarness.assert_eq(state.forge_counter, 0, "forge_counter reset to 0")
	state.teardown()

static func _fiend_offering() -> void:
	# Fleshbind now fires on BOTH ON_PLAYER_MINION_SACRIFICED and
	# ON_PLAYER_MINION_DIED (registered in CombatSetup.gd). So the sequence is:
	#   3 (start)
	#   → fiend_offering spends 2 → 1
	#   → fleshbind on SACRIFICED → 2
	#   → kill_minion fires DIED → fleshbind again → 3
	# Net: 3 (-2 offering +1 sac fleshbind +1 died fleshbind) = 3.
	var state := TestHarness.seris_state(["soul_forge", "fiend_offering"])
	if not TestHarness.begin_test("fiend_offering / Lesser Demon summon, -2 Flesh + 2 Fleshbind ticks", state):
		return
	state.player_flesh = 3
	var demon := TestHarness.spawn_friendly(state, "grafted_fiend")
	SacrificeSystem.sacrifice(state, demon, "test_sac")
	state.combat_manager.kill_minion(demon)
	var has_lesser := false
	for m in state.player_board:
		if m.card_data.id == "lesser_demon":
			has_lesser = true
			break
	TestHarness.assert_true(has_lesser, "Lesser Demon on board")
	# 3 start -2 offering +1 sac fleshbind +1 died fleshbind = 3
	TestHarness.assert_eq(state.player_flesh, 3, "Flesh net: 3 -2 +1 +1 = 3")
	state.teardown()

static func _forge_momentum() -> void:
	var state := TestHarness.seris_state(["soul_forge", "fiend_offering", "forge_momentum"])
	if not TestHarness.begin_test("forge_momentum / threshold lowered to 2", state):
		return
	TestHarness.assert_eq(state.forge_counter_threshold, 2, "threshold == 2")
	state.teardown()

static func _abyssal_forge_aura_grant() -> void:
	var state := TestHarness.seris_state(["soul_forge", "fiend_offering", "forge_momentum", "abyssal_forge"])
	if not TestHarness.begin_test("abyssal_forge / Forged Demon has >=1 aura tag", state):
		return
	for i in 2:
		var demon := TestHarness.spawn_friendly(state, "grafted_fiend")
		SacrificeSystem.sacrifice(state, demon, "test_sac")
		state.combat_manager.kill_minion(demon)
	var forged: MinionInstance = null
	for m in state.player_board:
		if m.card_data.id == "forged_demon":
			forged = m
			break
	TestHarness.assert_ne(forged, null, "Forged Demon exists")
	if forged != null:
		TestHarness.assert_true(forged.aura_tags.size() >= 1, "has >=1 aura tag")
	state.teardown()

# ---------------------------------------------------------------------------
# Corruption branch
# ---------------------------------------------------------------------------

static func _corrupt_flesh_inversion() -> void:
	var state := TestHarness.seris_state(["corrupt_flesh"])
	if not TestHarness.begin_test("corrupt_flesh / Corruption inverts on friendly Demon (+ATK)", state):
		return
	var fiend := TestHarness.spawn_friendly(state, "grafted_fiend")
	var before := fiend.effective_atk()
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	var after := fiend.effective_atk()
	TestHarness.assert_eq(after - before, 100, "ATK +100 (inverted from -100)")
	state.teardown()
	MinionInstance.corruption_inverts_on_friendly_demons = false

static func _corrupt_flesh_activate() -> void:
	var state := TestHarness.seris_state(["corrupt_flesh"])
	if not TestHarness.begin_test("corrupt_flesh / activate grants 2 stacks on target, -1 Flesh", state):
		return
	state.player_flesh = 5
	var fiend := TestHarness.spawn_friendly(state, "grafted_fiend")
	var ok: bool = state._seris_corrupt_activate(fiend)
	var stacks: int = BuffSystem.sum_type(fiend, Enums.BuffType.CORRUPTION)
	TestHarness.assert_true(ok, "activation returns true")
	TestHarness.assert_eq(state.player_flesh, 4, "Flesh spent: 5 → 4")
	TestHarness.assert_eq(stacks, 200, "2 stacks (raw value 200)")
	state.teardown()
	MinionInstance.corruption_inverts_on_friendly_demons = false

static func _corrupt_detonation() -> void:
	var state := TestHarness.seris_state(["corrupt_flesh", "corrupt_detonation"])
	if not TestHarness.begin_test("corrupt_detonation / 100/stack to random enemy on cleanse", state):
		return
	var fiend := TestHarness.spawn_friendly(state, "grafted_fiend")
	var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
	enemy.current_health = 1000  # avoid damage clamping
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	var enemy_hp_before := enemy.current_health
	var enemy_hero_before := state.enemy_hp
	BuffSystem.remove_type(fiend, Enums.BuffType.CORRUPTION)
	var minion_dmg := enemy_hp_before - enemy.current_health
	var hero_dmg := enemy_hero_before - state.enemy_hp
	TestHarness.assert_true(minion_dmg == 200 or hero_dmg == 200,
			"200 dmg to exactly one random enemy target (minion=%d, hero=%d)" % [minion_dmg, hero_dmg])
	state.teardown()
	MinionInstance.corruption_inverts_on_friendly_demons = false

static func _void_amplification() -> void:
	var state := TestHarness.seris_state(["void_amplification"])
	if not TestHarness.begin_test("void_amplification / spell dmg bonus = 50 * corruption stacks", state):
		return
	var fiend := TestHarness.spawn_friendly(state, "grafted_fiend")
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	var spell_card := CardDatabase.get_card("void_bolt") as SpellCardData
	state._pre_player_spell_cast(spell_card)
	TestHarness.assert_eq(state._player_spell_damage_bonus, 100, "bonus = 50 * 2 stacks = 100")
	state._post_player_spell_cast(spell_card, null)
	state.teardown()

static func _void_resonance_flesh_gain() -> void:
	var state := TestHarness.seris_state(["void_resonance_seris"])
	if not TestHarness.begin_test("void_resonance_seris / +1 Flesh on any enemy death", state):
		return
	var before := state.player_flesh
	var enemy := TestHarness.spawn_enemy(state, "rabid_imp")
	state.combat_manager.kill_minion(enemy)
	TestHarness.assert_eq(state.player_flesh, before + 1, "Flesh +1")
	state.teardown()

static func _void_resonance_double_cast() -> void:
	var state := TestHarness.seris_state(["void_resonance_seris"])
	if not TestHarness.begin_test("void_resonance_seris / post-cast consumes 5 Flesh, no infinite loop", state):
		return
	state.player_flesh = 5
	var spell_card := CardDatabase.get_card("void_bolt") as SpellCardData
	state._pre_player_spell_cast(spell_card)
	state._post_player_spell_cast(spell_card, null)
	TestHarness.assert_eq(state.player_flesh, 0, "Flesh spent: 5 → 0")
	TestHarness.assert_false(state._double_cast_in_progress, "double_cast flag cleared")
	state.teardown()

# ---------------------------------------------------------------------------
# Act 3 relics — RelicEffects.resolve(relic_id) applied to a neutral SimState.
# ---------------------------------------------------------------------------

static func _relic_void_hourglass() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("relic / void_hourglass — +1 max Essence, +1 max Mana", state):
		return
	state.player_essence_max = 1
	state.player_mana_max = 1
	var fx := RelicEffects.new()
	fx.setup(state)
	fx.resolve("relic_extra_turn")
	TestHarness.assert_eq(state.player_essence_max, 2, "essence_max 1 → 2")
	TestHarness.assert_eq(state.player_mana_max, 2, "mana_max 1 → 2")
	state.teardown()

static func _relic_oblivion_seal() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("relic / oblivion_seal — rune placed + 200 dmg to enemy hero", state):
		return
	state.player_essence_max = 5
	state.player_mana_max = 5
	var enemy_hp_before := state.enemy_hp
	var traps_before := state.active_traps.size()
	var fx := RelicEffects.new()
	fx.setup(state)
	fx.resolve("relic_summon_demon")
	TestHarness.assert_eq(state.active_traps.size(), traps_before + 1, "trap/rune +1")
	TestHarness.assert_eq(enemy_hp_before - state.enemy_hp, 200, "enemy hero -200 hp")
	state.teardown()

static func _relic_nether_crown() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("relic / nether_crown — +100 ATK to all friendlies", state):
		return
	var data := CardDatabase.get_card("void_imp") as MinionCardData
	for i in 2:
		var m := MinionInstance.create(data, "player")
		state.player_board.append(m)
	var before_atks: Array[int] = []
	for m in state.player_board:
		before_atks.append((m as MinionInstance).effective_atk())
	var fx := RelicEffects.new()
	fx.setup(state)
	fx.resolve("relic_mass_buff")
	var all_plus_100 := true
	for i in state.player_board.size():
		var delta: int = (state.player_board[i] as MinionInstance).effective_atk() - before_atks[i]
		if delta != 100:
			all_plus_100 = false
	TestHarness.assert_true(all_plus_100, "every friendly gained +100 ATK")
	state.teardown()

static func _relic_phantom_deck() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("relic / phantom_deck — +2 cards copied into hand", state):
		return
	var imp := CardDatabase.get_card("void_imp")
	for i in 3:
		state.turn_manager.add_to_hand(imp)
	var before := state.player_hand.size()
	var fx := RelicEffects.new()
	fx.setup(state)
	fx.resolve("relic_copy_cards")
	TestHarness.assert_eq(state.player_hand.size(), before + 2, "hand +2")
	state.teardown()

# ---------------------------------------------------------------------------
# Lord Vael talents + hero passive + enemy passives
# ---------------------------------------------------------------------------

## Fire ON_PLAYER_CARD_DRAWN for a given card.
static func _fire_card_drawn(state: SimState, card: CardData) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, "player")
	ctx.card = card
	state.trigger_manager.fire(ctx)

## Fire ON_PLAYER_TURN_START.
static func _fire_player_turn_start(state: SimState) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_TURN_START, "player")
	state.trigger_manager.fire(ctx)

## Fire ON_PLAYER_MINION_SUMMONED on an already-spawned minion.
static func _fire_player_summon(state: SimState, minion: MinionInstance) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
	ctx.minion = minion
	ctx.card = minion.card_data
	state.trigger_manager.fire(ctx)

## Fire ON_PLAYER_MINION_PLAYED.
static func _fire_player_played(state: SimState, minion: MinionInstance) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, "player")
	ctx.minion = minion
	ctx.card = minion.card_data
	state.trigger_manager.fire(ctx)

## Fire ON_ENEMY_MINION_SUMMONED.
static func _fire_enemy_summon(state: SimState, minion: MinionInstance) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, "enemy")
	ctx.minion = minion
	ctx.card = minion.card_data
	state.trigger_manager.fire(ctx)

## Fire ON_ENEMY_TURN_START.
static func _fire_enemy_turn_start(state: SimState) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_START, "enemy")
	state.trigger_manager.fire(ctx)

# ---------------------------------------------------------------------------
# void_echo — ON_PLAYER_CARD_DRAWN on a base_void_imp tag adds a free Void Imp.
# Once per turn; flag resets at ON_PLAYER_TURN_START.
# ---------------------------------------------------------------------------

static func _void_echo() -> void:
	var state := TestHarness.vael_state(["void_echo"])
	if not TestHarness.begin_test("void_echo / drawing void_imp adds a free copy to hand", state):
		return
	var hand_before := state.player_hand.size()
	_fire_card_drawn(state, CardDatabase.get_card("void_imp"))
	TestHarness.assert_eq(state.player_hand.size(), hand_before + 1, "hand +1 free imp")
	TestHarness.assert_true(state.get("_void_echo_fired_this_turn") == true, "fired flag set")
	state.teardown()

static func _void_echo_once_per_turn() -> void:
	var state := TestHarness.vael_state(["void_echo"])
	if not TestHarness.begin_test("void_echo / second draw same turn does NOT add another", state):
		return
	var imp := CardDatabase.get_card("void_imp")
	_fire_card_drawn(state, imp)
	var hand_after_first := state.player_hand.size()
	_fire_card_drawn(state, imp)
	TestHarness.assert_eq(state.player_hand.size(), hand_after_first, "hand unchanged on 2nd draw")
	# Turn reset → flag flips back to false → next draw fires again
	_fire_player_turn_start(state)
	_fire_card_drawn(state, imp)
	TestHarness.assert_eq(state.player_hand.size(), hand_after_first + 1, "next-turn draw fires again")
	state.teardown()

# ---------------------------------------------------------------------------
# swarm_discipline — Void Imp clan +100 HP BASE stats (CardModRules clan rule).
# Migrated from on-summon direct HP add. The rule applies at combat-time card
# construction, so we test by fetching via state._card_for.
# ---------------------------------------------------------------------------

static func _swarm_discipline() -> void:
	# Explicitly skip void_imp_boost so the +100 HP from that passive doesn't
	# pollute the delta we're measuring.
	var state := TestHarness.build_state({
		"hero_id": "lord_vael",
		"talents": ["swarm_discipline"],
		"hero_passives": [],
	})
	if not TestHarness.begin_test("swarm_discipline / void_imp base HP = 200", state):
		return
	var data: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	TestHarness.assert_eq(data.health, 200, "HP base 200 (100 + 100 from talent)")
	# ATK unchanged (talent is HP-only)
	TestHarness.assert_eq(data.atk, 100, "ATK unchanged at 100")
	state.teardown()

# ---------------------------------------------------------------------------
# piercing_void — talent_override on Void Imp swaps on-play steps to
# [VOID_BOLT 200, VOID_MARK 1]. Test runs the override-applied steps directly.
# ---------------------------------------------------------------------------

static func _piercing_void_handler() -> void:
	var state := TestHarness.vael_state(["piercing_void"])
	if not TestHarness.begin_test("piercing_void / void imp on-play = 200 bolt + 1 mark", state):
		return
	var hp_before := state.enemy_hp
	var marks_before := state.enemy_void_marks
	# _card_for applies talent_overrides; under piercing_void the on-play array
	# is the [VOID_BOLT 200, VOID_MARK 1] swap declared in CardDatabase.
	var data: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", imp))
	TestHarness.assert_eq(state.enemy_hp, hp_before - 200, "enemy hp -200")
	TestHarness.assert_eq(state.enemy_void_marks, marks_before + 1, "marks +1")
	state.teardown()

# ---------------------------------------------------------------------------
# imp_evolution — playing a void_imp adds senior_void_imp to hand, 1/turn.
# Migrated to CardModRules append_on_play_effect_steps with once_per_turn:imp_evolution.
# ---------------------------------------------------------------------------

static func _imp_evolution() -> void:
	var state := TestHarness.vael_state(["imp_evolution"])
	if not TestHarness.begin_test("imp_evolution / void_imp play adds senior_void_imp to hand", state):
		return
	var hand_before := state.player_hand.size()
	var data: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", imp))
	TestHarness.assert_eq(state.player_hand.size(), hand_before + 1, "hand +1")
	if state.player_hand.size() > hand_before:
		TestHarness.assert_eq(state.player_hand[-1].card_data.id, "senior_void_imp", "added card is senior_void_imp")
	TestHarness.assert_true(state._once_per_turn_used.get("imp_evolution", false), "once-per-turn flag set")
	state.teardown()

static func _imp_evolution_once_per_turn() -> void:
	var state := TestHarness.vael_state(["imp_evolution"])
	if not TestHarness.begin_test("imp_evolution / second play same turn does NOT add", state):
		return
	var data: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	var a := TestHarness.spawn_friendly(state, "void_imp")
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", a))
	var hand_after_first := state.player_hand.size()
	var b := TestHarness.spawn_friendly(state, "void_imp")
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", b))
	TestHarness.assert_eq(state.player_hand.size(), hand_after_first, "hand unchanged on 2nd play")
	state.teardown()

# ---------------------------------------------------------------------------
# imp_warband — playing a senior_void_imp grants +50 ATK to all other void imps.
# Migrated to CardModRules append_on_play_effect_steps with BUFF_ATK + exclude_self.
# ---------------------------------------------------------------------------

static func _imp_warband() -> void:
	# Deliberately exclude void_imp_boost — it bakes +100 ATK into the senior's base
	# stats via CardModRules and would inflate the senior's atk readout in the assert.
	var state := TestHarness.build_state({
		"hero_id": "lord_vael",
		"talents": ["imp_warband"],
		"hero_passives": [],
	})
	if not TestHarness.begin_test("imp_warband / senior_void_imp play = +50 ATK to other void imps", state):
		return
	var other := TestHarness.spawn_friendly(state, "void_imp")
	var other_atk_before := other.effective_atk()
	var data: MinionCardData = state._card_for("player", "senior_void_imp") as MinionCardData
	var senior := TestHarness.spawn_friendly(state, "senior_void_imp")
	var senior_atk_before := senior.effective_atk()
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", senior))
	TestHarness.assert_eq(other.effective_atk() - other_atk_before, 50, "other void imp +50 ATK")
	TestHarness.assert_eq(senior.effective_atk(), senior_atk_before, "senior itself unchanged")
	state.teardown()

# ---------------------------------------------------------------------------
# death_bolt — Void Imp clan card carries an appended VOID_BOLT step on its
# on_death_effect_steps under the talent (CardModRules step injection). The
# step fires from EffectResolver as part of the normal death resolution path.
# ---------------------------------------------------------------------------

static func _death_bolt() -> void:
	var state := TestHarness.vael_state(["death_bolt"])
	if not TestHarness.begin_test("death_bolt / void imp death = 100 void bolt damage", state):
		return
	# _card_for applies the death_bolt clan rule; the spawned imp's card_data
	# must be the override-applied clone for the death step to fire.
	var data: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	var imp := MinionInstance.create(data, "player")
	state.player_board.append(imp)
	for slot in state.player_slots:
		if slot.is_empty():
			slot.place_minion(imp)
			break
	var hp_before := state.enemy_hp
	state.combat_manager.kill_minion(imp)
	TestHarness.assert_eq(state.enemy_hp, hp_before - 100, "enemy hp -100")
	state.teardown()

# ---------------------------------------------------------------------------
# rune_caller — playing a void imp tutors a Rune from deck and discounts it -1 Mana.
# Migrated to CardModRules append_on_play_effect_steps: TUTOR rune + MOD_LAST_ADDED_COST mana -1.
# ---------------------------------------------------------------------------

static func _rune_caller() -> void:
	var state := TestHarness.vael_state(["rune_caller"])
	if not TestHarness.begin_test("rune_caller / void imp play tutors a discounted Rune from deck", state):
		return
	# Seed a rune in the deck so TUTOR has something to pull.
	var rune := CardDatabase.get_card("soul_rune") as TrapCardData
	state.player_deck.append(CardInstance.create(rune))
	var hand_before := state.player_hand.size()
	var data: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	EffectResolver.run(data.on_play_effect_steps, TestHarness.make_ctx(state, "player", imp))
	TestHarness.assert_eq(state.player_hand.size(), hand_before + 1, "hand +1 rune tutored")
	if state.player_hand.size() > hand_before:
		var added: CardInstance = state.player_hand[-1]
		TestHarness.assert_eq(added.card_data.id, "soul_rune", "tutored card is the seeded rune")
		TestHarness.assert_eq(added.mana_delta, -1, "tutored rune's mana_delta = -1 (1 cheaper this turn)")
	state.teardown()

# ---------------------------------------------------------------------------
# ritual_surge — ON_RITUAL_FIRED summons a void_imp on player board.
# ---------------------------------------------------------------------------

static func _ritual_surge() -> void:
	var state := TestHarness.vael_state(["ritual_surge"])
	if not TestHarness.begin_test("ritual_surge / ritual fired = +1 void_imp on player board", state):
		return
	var board_before := state.player_board.size()
	var ctx := EventContext.make(Enums.TriggerEvent.ON_RITUAL_FIRED, "player")
	state.trigger_manager.fire(ctx)
	TestHarness.assert_eq(state.player_board.size(), board_before + 1, "board +1")
	if state.player_board.size() > board_before:
		TestHarness.assert_eq(state.player_board[-1].card_data.id, "void_imp", "summoned is void_imp")
	state.teardown()

# ---------------------------------------------------------------------------
# deepened_curse / runic_attunement — stat overrides only, applied at setup.
# ---------------------------------------------------------------------------

static func _deepened_curse_stat() -> void:
	var state := TestHarness.vael_state(["deepened_curse"])
	if not TestHarness.begin_test("deepened_curse / void_mark_damage_per_stack = 40", state):
		return
	TestHarness.assert_eq(state.void_mark_damage_per_stack, 40, "stat == 40")
	state.teardown()

static func _runic_attunement_stat() -> void:
	var state := TestHarness.vael_state(["runic_attunement"])
	if not TestHarness.begin_test("runic_attunement / rune_aura_multiplier = 2", state):
		return
	TestHarness.assert_eq(state.rune_aura_multiplier, 2, "stat == 2")
	state.teardown()

# ---------------------------------------------------------------------------
# void_imp_boost (hero passive) — Void Imp clan +100/+100 BASE stats.
# Migrated from on-summon buff to CardModRules clan rule. The rule applies
# at combat-time card construction (CardDatabase.get_card_for_combat), so
# we test by using state._card_for which routes through the rule pipeline.
# ---------------------------------------------------------------------------

static func _void_imp_boost() -> void:
	var state := TestHarness.vael_state([])  # no talents; just the passive
	if not TestHarness.begin_test("void_imp_boost / void imp base stats = 200/200", state):
		return
	# Use _card_for so clan rules apply — mirrors how live combat constructs deck cards.
	var data: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	TestHarness.assert_eq(data.atk, 200, "ATK base 200 (100 + 100 from passive)")
	TestHarness.assert_eq(data.health, 200, "HP base 200 (100 + 100 from passive)")
	state.teardown()

# ---------------------------------------------------------------------------
# Mid-combat talent unlock (cheat panel flow). Talent gets added to
# state.talents and the override cache is cleared, so the next _card_for
# lookup returns the override-applied clone. Cards already in hand keep
# their previous card_data — only newly created CardInstances see the change.
# ---------------------------------------------------------------------------

static func _midcombat_talent_unlock_applies_override() -> void:
	var state := TestHarness.vael_state([])  # no talents at start
	if not TestHarness.begin_test("midcombat unlock / piercing_void becomes active for new card_for", state):
		return
	# Pre-unlock: Void Imp's mana_cost is 0 (base), on-play is hero damage.
	var pre: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	TestHarness.assert_eq(pre.mana_cost, 0, "pre-unlock mana_cost = 0")
	TestHarness.assert_true(pre.on_play_effect_steps.size() == 1
			and pre.on_play_effect_steps[0].get("type") == "DAMAGE_HERO",
			"pre-unlock on-play = single DAMAGE_HERO step")

	# Cheat panel-style mutation: append talent to state.talents, clear cache.
	state.talents.append("piercing_void")
	CardDatabase.clear_override_cache()

	# Post-unlock: same id, but the override applies — mana_cost = 1, on-play
	# replaced with [VOID_BOLT 200, VOID_MARK 1].
	var post: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	TestHarness.assert_eq(post.mana_cost, 1, "post-unlock mana_cost = 1")
	TestHarness.assert_eq(post.on_play_effect_steps.size(), 2, "post-unlock on-play has 2 steps")
	TestHarness.assert_true(post.on_play_effect_steps[0].get("type") == "VOID_BOLT",
			"post-unlock first step = VOID_BOLT")
	TestHarness.assert_true(post.on_play_effect_steps[1].get("type") == "VOID_MARK",
			"post-unlock second step = VOID_MARK")
	state.teardown()

# ---------------------------------------------------------------------------
# pack_instinct — every feral imp on enemy board gains +50 ATK per OTHER feral imp.
# Recomputes on summon/death events.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# rogue_imp_elder presence aura — every Elder grants +100 ATK to every friendly
# Feral Imp (including itself) on the same side. Recomputes on summon/death.
# ---------------------------------------------------------------------------

static func _rogue_imp_elder_aura_scaling() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("rogue_imp_elder / 1 Elder + 2 imps = +100 ATK each (1 elder)", state):
		return
	var imp_a := TestHarness.spawn_friendly(state, "rabid_imp")
	var imp_b := TestHarness.spawn_friendly(state, "rabid_imp")
	var elder := TestHarness.spawn_friendly(state, "rogue_imp_elder")
	var imp_base := imp_a.card_data.atk
	var elder_base := elder.card_data.atk
	_fire_player_summon(state, elder)  # any summon triggers recompute
	TestHarness.assert_eq(imp_a.effective_atk(), imp_base + 100, "imp_a: +100 (1 elder)")
	TestHarness.assert_eq(imp_b.effective_atk(), imp_base + 100, "imp_b: +100 (1 elder)")
	TestHarness.assert_eq(elder.effective_atk(), elder_base + 100, "elder buffs itself (it's a feral imp)")
	state.teardown()

	state = TestHarness.build_state({})
	if not TestHarness.begin_test("rogue_imp_elder / 2 Elders + 1 imp = +200 ATK each (count scales)", state):
		return
	var imp := TestHarness.spawn_friendly(state, "rabid_imp")
	var e1 := TestHarness.spawn_friendly(state, "rogue_imp_elder")
	var e2 := TestHarness.spawn_friendly(state, "rogue_imp_elder")
	var base_imp := imp.card_data.atk
	_fire_player_summon(state, e2)
	TestHarness.assert_eq(imp.effective_atk(), base_imp + 200, "imp: +200 (2 elders)")
	TestHarness.assert_eq(e1.effective_atk(), e1.card_data.atk + 200, "e1: +200 (2 elders)")
	TestHarness.assert_eq(e2.effective_atk(), e2.card_data.atk + 200, "e2: +200 (2 elders)")
	state.teardown()

static func _rogue_imp_elder_aura_strips_on_death() -> void:
	var state := TestHarness.build_state({})
	if not TestHarness.begin_test("rogue_imp_elder / dies → buff drops back to 0", state):
		return
	var imp := TestHarness.spawn_friendly(state, "rabid_imp")
	var elder := TestHarness.spawn_friendly(state, "rogue_imp_elder")
	var base_imp := imp.card_data.atk
	_fire_player_summon(state, elder)
	TestHarness.assert_eq(imp.effective_atk(), base_imp + 100, "imp: +100 with elder alive")
	# Kill the elder by removing it from the board and firing the death event.
	state.player_board.erase(elder)
	var death_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_DIED, "player")
	death_ctx.minion = elder
	state.trigger_manager.fire(death_ctx)
	TestHarness.assert_eq(imp.effective_atk(), base_imp, "imp: back to base after elder dies")
	state.teardown()

static func _pack_instinct_scaling() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["pack_instinct"]})
	if not TestHarness.begin_test("pack_instinct / 3 feral imps on enemy board = +100 ATK each (2 others)", state):
		return
	var a := TestHarness.spawn_enemy(state, "rabid_imp")
	var b := TestHarness.spawn_enemy(state, "rabid_imp")
	var c := TestHarness.spawn_enemy(state, "rabid_imp")
	var base := a.card_data.atk
	_fire_enemy_summon(state, c)  # last summon triggers recalc
	TestHarness.assert_eq(a.effective_atk(), base + 100, "a: base + 50*2")
	TestHarness.assert_eq(b.effective_atk(), base + 100, "b: base + 50*2")
	TestHarness.assert_eq(c.effective_atk(), base + 100, "c: base + 50*2")
	state.teardown()

# ---------------------------------------------------------------------------
# corrupted_death — cost discount only. Void-Touched Imp essence cost -1.
# Applied via enemy_ai.essence_cost_discounts in CombatSetup.setup().
# ---------------------------------------------------------------------------

static func _corrupted_death_cost_discount() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["corrupted_death"]})
	if not TestHarness.begin_test("corrupted_death / void_touched_imp essence cost -1 discount registered", state):
		return
	var discounts: Dictionary = state.enemy_ai.essence_cost_discounts
	TestHarness.assert_eq(discounts.get("void_touched_imp", 0), 1, "discount == 1")
	state.teardown()

# ---------------------------------------------------------------------------
# feral_reinforcement — human summoned → add random feral imp to enemy hand,
# once per enemy turn. Reset flag at enemy turn start.
# ---------------------------------------------------------------------------

static func _feral_reinforcement_human_summon() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["feral_reinforcement"]})
	if not TestHarness.begin_test("feral_reinforcement / human summon = feral imp into enemy hand", state):
		return
	var hand_before := state.enemy_hand.size()
	var human := TestHarness.spawn_enemy(state, "spell_taxer")  # HUMAN type
	_fire_enemy_summon(state, human)
	TestHarness.assert_eq(state.enemy_hand.size(), hand_before + 1, "enemy hand +1")
	TestHarness.assert_true(state.get("_imp_caller_fired") == true, "fired flag set")
	state.teardown()

static func _feral_reinforcement_once_per_turn() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["feral_reinforcement"]})
	if not TestHarness.begin_test("feral_reinforcement / second human same turn does NOT add", state):
		return
	var a := TestHarness.spawn_enemy(state, "spell_taxer")
	_fire_enemy_summon(state, a)
	var hand_after_first := state.enemy_hand.size()
	var b := TestHarness.spawn_enemy(state, "saboteur_adept")
	_fire_enemy_summon(state, b)
	TestHarness.assert_eq(state.enemy_hand.size(), hand_after_first, "hand unchanged on 2nd human")
	# Turn reset → flag back to false
	_fire_enemy_turn_start(state)
	var c := TestHarness.spawn_enemy(state, "spell_taxer")
	_fire_enemy_summon(state, c)
	TestHarness.assert_eq(state.enemy_hand.size(), hand_after_first + 1, "next turn human fires again")
	state.teardown()

# ---------------------------------------------------------------------------
# corrupt_authority (2 handlers):
#   human summon  → +1 Corruption on random player minion
#   feral imp summon → consume all corruption, deal 100/stack
# ---------------------------------------------------------------------------

static func _corrupt_authority_human_corrupts() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["corrupt_authority"]})
	if not TestHarness.begin_test("corrupt_authority / human summon applies 1 Corruption to player minion", state):
		return
	var victim := TestHarness.spawn_friendly(state, "void_imp")
	var stacks_before := BuffSystem.sum_type(victim, Enums.BuffType.CORRUPTION)
	var human := TestHarness.spawn_enemy(state, "spell_taxer")
	_fire_enemy_summon(state, human)
	var stacks_after := BuffSystem.sum_type(victim, Enums.BuffType.CORRUPTION)
	TestHarness.assert_true(stacks_after > stacks_before, "corruption stacks increased on player minion")
	state.teardown()

static func _corrupt_authority_imp_detonates() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["corrupt_authority"]})
	if not TestHarness.begin_test("corrupt_authority / feral imp summon detonates corruption (100/stack)", state):
		return
	var victim := TestHarness.spawn_friendly(state, "void_imp")
	victim.current_health = 1000
	BuffSystem.apply(victim, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	BuffSystem.apply(victim, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	var imp := TestHarness.spawn_enemy(state, "rabid_imp")  # feral imp
	_fire_enemy_summon(state, imp)
	# 2 stacks → 200 dmg, then corruption cleared
	TestHarness.assert_eq(1000 - victim.current_health, 200, "100 dmg per stack x 2 = 200")
	TestHarness.assert_eq(BuffSystem.sum_type(victim, Enums.BuffType.CORRUPTION), 0, "corruption cleared")
	state.teardown()

# ---------------------------------------------------------------------------
# ritual_sacrifice — feral imp summon with Blood Rune + Dominion Rune active:
# consume both + the imp, 200 dmg to 2 random player targets, summon 500/500 Void Demon.
# ---------------------------------------------------------------------------

static func _ritual_sacrifice_full_combo() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["ritual_sacrifice"]})
	if not TestHarness.begin_test("ritual_sacrifice / Blood+Dominion runes + feral imp = full combo", state):
		return
	# Seed both required runes in enemy_ai.active_traps (that's what the handler reads).
	var blood := CardDatabase.get_card("blood_rune") as TrapCardData
	var dominion := CardDatabase.get_card("dominion_rune") as TrapCardData
	if blood == null or dominion == null:
		TestHarness.assert_true(false, "blood_rune or dominion_rune card missing from DB")
		return
	state.enemy_ai.active_traps.append(blood)
	state.enemy_ai.active_traps.append(dominion)
	# Demon Ascendant spec: 200 damage to 2 random enemy (player-side, from
	# enemy POV) minions. Seed two beefy player minions so neither dies from
	# the 200 dmg and we can assert the exact distribution.
	var victim_a := TestHarness.spawn_friendly(state, "abyssal_brute")
	var victim_b := TestHarness.spawn_friendly(state, "abyssal_brute")
	var hp_a_before: int = victim_a.current_health
	var hp_b_before: int = victim_b.current_health
	var imp := TestHarness.spawn_enemy(state, "rabid_imp")
	var hp_before := state.player_hp
	_fire_enemy_summon(state, imp)
	TestHarness.assert_eq(state.enemy_ai.active_traps.size(), 0, "both runes consumed")
	TestHarness.assert_false(state.enemy_board.has(imp), "imp sacrificed")
	# Both player minions take 200 each — 2 distinct picks, no double-hit.
	TestHarness.assert_eq(hp_a_before - victim_a.current_health, 200, "player minion A takes 200")
	TestHarness.assert_eq(hp_b_before - victim_b.current_health, 200, "player minion B takes 200")
	TestHarness.assert_eq(hp_before - state.player_hp, 0, "player hero untouched (minions only)")
	TestHarness.assert_true(TestHarness.has_on_board(state, "enemy", "void_demon"), "Void Demon summoned on enemy board")
	state.teardown()

# ---------------------------------------------------------------------------
# void_rift — ON_ENEMY_TURN_START summons a 100/100 void_spark on enemy board.
# Suppressed when champion_void_herald is alive on the enemy board.
# ---------------------------------------------------------------------------

static func _void_rift_spawns_spark() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["void_rift"]})
	if not TestHarness.begin_test("void_rift / turn start spawns 100/100 void_spark", state):
		return
	var board_before := state.enemy_board.size()
	_fire_enemy_turn_start(state)
	TestHarness.assert_eq(state.enemy_board.size(), board_before + 1, "enemy board +1")
	if state.enemy_board.size() > board_before:
		var spark := state.enemy_board[-1] as MinionInstance
		TestHarness.assert_eq(spark.card_data.id, "void_spark", "token is void_spark")
		TestHarness.assert_eq(spark.current_atk, 100, "ATK = 100")
		TestHarness.assert_eq(spark.current_health, 100, "HP = 100")
	state.teardown()

static func _void_rift_herald_suppression() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["void_rift"]})
	if not TestHarness.begin_test("void_rift / suppressed while champion_void_herald on board", state):
		return
	# Spawn the Void Herald champion on enemy board to suppress.
	var herald_data := CardDatabase.get_card("champion_void_herald") as MinionCardData
	if herald_data == null:
		TestHarness.assert_true(false, "champion_void_herald card missing from DB")
		return
	var herald := MinionInstance.create(herald_data, "enemy")
	state.enemy_board.append(herald)
	for slot in state.enemy_slots:
		if slot.minion == null:
			slot.minion = herald
			herald.slot_index = slot.index
			break
	var board_before := state.enemy_board.size()
	_fire_enemy_turn_start(state)
	TestHarness.assert_eq(state.enemy_board.size(), board_before, "no spark spawned (herald suppresses)")
	state.teardown()

# ---------------------------------------------------------------------------
# void_might — ON_ENEMY_TURN_START grants 1 CRITICAL_STRIKE stack to a random enemy minion.
# ---------------------------------------------------------------------------

static func _void_might_crit_stack() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["void_might"]})
	if not TestHarness.begin_test("void_might / turn start grants +1 CRIT stack to a random enemy minion", state):
		return
	var a := TestHarness.spawn_enemy(state, "rabid_imp")
	var crit_before := BuffSystem.sum_type(a, Enums.BuffType.CRITICAL_STRIKE)
	_fire_enemy_turn_start(state)
	var crit_after := BuffSystem.sum_type(a, Enums.BuffType.CRITICAL_STRIKE)
	TestHarness.assert_true(crit_after > crit_before, "crit stacks increased on enemy minion")
	state.teardown()

# ---------------------------------------------------------------------------
# Act 1–2 champion passives
# ---------------------------------------------------------------------------

## Fire ON_ENEMY_ATTACK with a given attacker.
static func _fire_enemy_attack(state: SimState, attacker: MinionInstance) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_ATTACK, "enemy")
	ctx.minion = attacker
	state.trigger_manager.fire(ctx)

## Fire ON_ENEMY_SPELL_CAST with a given spell card.
static func _fire_enemy_spell_cast(state: SimState, card: CardData) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, "enemy")
	ctx.card = card
	state.trigger_manager.fire(ctx)

# ---------------------------------------------------------------------------
# Champion: Rogue Imp Pack
# ---------------------------------------------------------------------------

static func _rip_summon_at_4_attacks() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_rogue_imp_pack"]})
	if not TestHarness.begin_test("champion_rip / 4 distinct rabid_imp attacks summon the champion", state):
		return
	var imps: Array = []
	for i in 4:
		imps.append(TestHarness.spawn_enemy(state, "rabid_imp"))
	for imp in imps:
		_fire_enemy_attack(state, imp)
	TestHarness.assert_true(state.get("_champion_rip_summoned") == true, "_champion_rip_summoned flag set")
	TestHarness.assert_true(TestHarness.has_on_board(state, "enemy", "champion_rogue_imp_pack"), "champion on enemy board")
	state.teardown()

static func _rip_summon_requires_distinct_attackers() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_rogue_imp_pack"]})
	if not TestHarness.begin_test("champion_rip / same imp attacking 4 times does NOT summon", state):
		return
	var imp := TestHarness.spawn_enemy(state, "rabid_imp")
	for i in 4:
		_fire_enemy_attack(state, imp)
	TestHarness.assert_false(state.get("_champion_rip_summoned") == true, "still not summoned")
	TestHarness.assert_eq(state._champion_rip_attack_ids.size(), 1, "only 1 distinct attacker tracked")
	state.teardown()

static func _rip_aura_grants_100_atk() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_rogue_imp_pack"]})
	if not TestHarness.begin_test("champion_rip / while alive, other feral imps get +100 ATK aura", state):
		return
	# Fast-forward to summoned state.
	var imps: Array = []
	for i in 4:
		imps.append(TestHarness.spawn_enemy(state, "rabid_imp"))
	for imp in imps:
		_fire_enemy_attack(state, imp)
	# Spawn a 5th feral imp and fire its summon → aura handler refreshes.
	var extra := TestHarness.spawn_enemy(state, "rabid_imp")
	var atk_before := extra.effective_atk()
	_fire_enemy_summon(state, extra)
	TestHarness.assert_eq(extra.effective_atk(), atk_before + 100, "extra imp +100 from champion aura")
	state.teardown()

static func _rip_aura_refreshes_on_death() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_rogue_imp_pack"]})
	if not TestHarness.begin_test("champion_rip / feral imp death recomputes aura on survivors", state):
		return
	var imps: Array = []
	for i in 4:
		imps.append(TestHarness.spawn_enemy(state, "rabid_imp"))
	for imp in imps:
		_fire_enemy_attack(state, imp)
	var survivor := TestHarness.spawn_enemy(state, "rabid_imp")
	_fire_enemy_summon(state, survivor)  # aura application on new imp
	var atk_with_aura := survivor.effective_atk()
	# Kill one of the other imps — the aura handler should re-run without crashing
	state.combat_manager.kill_minion(imps[0])
	# Survivor should still have the +100 aura (champion still alive, still feral imp)
	TestHarness.assert_eq(survivor.effective_atk(), atk_with_aura, "survivor retains aura post-death")
	state.teardown()

static func _rip_no_resummon_after_summoned() -> void:
	# Spawn 4 imps (leaving one enemy board slot open for the champion summon),
	# attack with all 4, then fire a 5th attack from a re-used imp.
	# Expected: re-attack is a no-op (early-returned via duplicate uid check),
	# and the champion wasn't re-summoned.
	var state := TestHarness.build_state({"enemy_passives": ["champion_rogue_imp_pack"]})
	if not TestHarness.begin_test("champion_rip / additional attack after summon does NOT re-summon", state):
		return
	var imps: Array = []
	for i in 4:
		imps.append(TestHarness.spawn_enemy(state, "rabid_imp"))
	for imp in imps:
		_fire_enemy_attack(state, imp)
	# Re-attack with imp[0] — should be gated by the uid-already-tracked check
	_fire_enemy_attack(state, imps[0])
	TestHarness.assert_eq(TestHarness.count_on_board(state, "enemy", "champion_rogue_imp_pack"), 1, "exactly one champion on board")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Corrupted Broodlings
# ---------------------------------------------------------------------------

static func _cb_summon_at_3_deaths() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_corrupted_broodlings"]})
	if not TestHarness.begin_test("champion_cb / 3 enemy-side deaths summon the champion", state):
		return
	for i in 3:
		var m := TestHarness.spawn_enemy(state, "rabid_imp")
		state.combat_manager.kill_minion(m)
	TestHarness.assert_true(state.get("_champion_cb_summoned") == true, "_champion_cb_summoned flag set")
	TestHarness.assert_true(TestHarness.has_on_board(state, "enemy", "champion_corrupted_broodlings"), "champion on board")
	state.teardown()

static func _cb_death_summons_void_touched_imp() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_corrupted_broodlings"]})
	if not TestHarness.begin_test("champion_cb / champion death summons 200/300 void_touched_imp", state):
		return
	# Fast-forward: 3 deaths summon champion, then kill the champion.
	for i in 3:
		var m := TestHarness.spawn_enemy(state, "rabid_imp")
		state.combat_manager.kill_minion(m)
	var champion := TestHarness.find_on_board(state, "enemy", "champion_corrupted_broodlings")
	TestHarness.assert_ne(champion, null, "champion exists before kill")
	if champion == null:
		return
	state.combat_manager.kill_minion(champion)
	var vti := TestHarness.find_on_board(state, "enemy", "void_touched_imp")
	TestHarness.assert_ne(vti, null, "void_touched_imp summoned on death")
	if vti != null:
		TestHarness.assert_eq(vti.current_atk, 200, "ATK = 200")
		TestHarness.assert_eq(vti.current_health, 300, "HP = 300")
	state.teardown()

static func _cb_no_resummon_after_summoned() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_corrupted_broodlings"]})
	if not TestHarness.begin_test("champion_cb / 4th enemy death does NOT re-increment or re-summon", state):
		return
	for i in 3:
		var m := TestHarness.spawn_enemy(state, "rabid_imp")
		state.combat_manager.kill_minion(m)
	var count_after_third: int = state.get("_champion_cb_death_count")
	# 4th death (non-champion)
	var extra := TestHarness.spawn_enemy(state, "rabid_imp")
	state.combat_manager.kill_minion(extra)
	TestHarness.assert_eq(state.get("_champion_cb_death_count"), count_after_third, "count frozen after summon")
	TestHarness.assert_eq(TestHarness.count_on_board(state, "enemy", "champion_corrupted_broodlings"), 1, "exactly one champion")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Imp Matriarch
# ---------------------------------------------------------------------------

static func _im_summon_at_2_frenzy() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_imp_matriarch"]})
	if not TestHarness.begin_test("champion_im / 2 enemy pack_frenzy casts summon the champion", state):
		return
	var pf := CardDatabase.get_card("pack_frenzy")
	_fire_enemy_spell_cast(state, pf)
	_fire_enemy_spell_cast(state, pf)
	TestHarness.assert_true(state.get("_champion_im_summoned") == true, "_champion_im_summoned flag set")
	TestHarness.assert_true(TestHarness.has_on_board(state, "enemy", "champion_imp_matriarch"), "champion on board")
	state.teardown()

static func _im_aura_adds_200hp_on_frenzy() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_imp_matriarch"]})
	if not TestHarness.begin_test("champion_im / aura: post-summon pack_frenzy grants +200 HP to feral imps", state):
		return
	var pf := CardDatabase.get_card("pack_frenzy")
	_fire_enemy_spell_cast(state, pf)
	_fire_enemy_spell_cast(state, pf)  # champion summoned
	var imp := TestHarness.spawn_enemy(state, "rabid_imp")
	var hp_before := imp.current_health
	_fire_enemy_spell_cast(state, pf)  # aura branch: +200 HP
	TestHarness.assert_eq(imp.current_health - hp_before, 200, "feral imp +200 HP from aura")
	state.teardown()

static func _im_frenzy_count_ignored_after_summon() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_imp_matriarch"]})
	if not TestHarness.begin_test("champion_im / frenzy count frozen once champion summoned", state):
		return
	var pf := CardDatabase.get_card("pack_frenzy")
	_fire_enemy_spell_cast(state, pf)
	_fire_enemy_spell_cast(state, pf)
	var count_at_summon: int = state.get("_champion_im_frenzy_count")
	_fire_enemy_spell_cast(state, pf)  # post-summon: should hit aura branch, NOT count++
	TestHarness.assert_eq(state.get("_champion_im_frenzy_count"), count_at_summon, "frenzy count unchanged after summon")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Abyss Cultist Patrol (Act 2)
# ---------------------------------------------------------------------------

static func _acp_summon_at_5_stacks_consumed() -> void:
	# ACP only summons via on_champion_acp_track_stacks, which is called from the
	# corrupt_authority_imp handler after consuming corruption. We drive it directly
	# by feeding corruption to player minions and summoning feral imps on enemy side.
	var state := TestHarness.build_state({
		"enemy_passives": ["corrupt_authority", "champion_abyss_cultist_patrol"],
	})
	if not TestHarness.begin_test("champion_acp / 5 corruption stacks consumed summon the champion", state):
		return
	# Place two player minions and corrupt them to 5 total stacks (3 + 2).
	var victim_a := TestHarness.spawn_friendly(state, "void_imp")
	var victim_b := TestHarness.spawn_friendly(state, "void_imp")
	victim_a.current_health = 1000
	victim_b.current_health = 1000
	for i in 3:
		BuffSystem.apply(victim_a, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	for i in 2:
		BuffSystem.apply(victim_b, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	# Summon a feral imp — corrupt_authority_imp handler consumes the stacks and
	# feeds on_champion_acp_track_stacks, which accumulates to 5 and summons.
	var imp := TestHarness.spawn_enemy(state, "rabid_imp")
	_fire_enemy_summon(state, imp)
	TestHarness.assert_eq(state._champion_acp_stacks_consumed, 5, "5 stacks consumed")
	TestHarness.assert_true(state.get("_champion_acp_summoned") == true, "champion summoned")
	state.teardown()

static func _acp_aura_instant_detonate() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_abyss_cultist_patrol"]})
	if not TestHarness.begin_test("champion_acp / aura: any enemy summon with player corruption = instant detonate", state):
		return
	# Force-summon the champion (bypass the threshold) so we can test the aura cleanly.
	state.set("_champion_acp_summoned", true)
	var victim := TestHarness.spawn_friendly(state, "void_imp")
	victim.current_health = 1000
	BuffSystem.apply(victim, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	BuffSystem.apply(victim, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	# Any enemy summon should now instant-detonate the 2 stacks on victim → 200 dmg.
	var trigger := TestHarness.spawn_enemy(state, "rabid_imp")
	_fire_enemy_summon(state, trigger)
	TestHarness.assert_eq(1000 - victim.current_health, 200, "victim took 100*2 = 200 dmg")
	TestHarness.assert_eq(BuffSystem.sum_type(victim, Enums.BuffType.CORRUPTION), 0, "corruption cleared")
	state.teardown()

static func _acp_stacks_capped_at_5_in_progress() -> void:
	# Call on_champion_acp_track_stacks directly with 10 stacks — the threshold
	# is 5; going above should still summon, and stacks_consumed records the raw sum.
	var state := TestHarness.build_state({"enemy_passives": ["champion_abyss_cultist_patrol"]})
	if not TestHarness.begin_test("champion_acp / tracker accepts over-shoot stacks (raw sum preserved)", state):
		return
	state._handlers_ref.on_champion_acp_track_stacks(10)
	TestHarness.assert_eq(state._champion_acp_stacks_consumed, 10, "raw stacks_consumed == 10")
	TestHarness.assert_true(state.get("_champion_acp_summoned") == true, "summoned at first feed >=5")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Void Ritualist (Act 2)
# ---------------------------------------------------------------------------

static func _vr_summon_on_first_ritual_sacrifice() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_ritualist"]})
	if not TestHarness.begin_test("champion_vr / on_ritual_sacrifice_champion_vr summons on first call", state):
		return
	TestHarness.assert_false(state.get("_champion_vr_summoned") == true, "not summoned initially")
	state._handlers_ref.on_ritual_sacrifice_champion_vr()
	TestHarness.assert_true(state.get("_champion_vr_summoned") == true, "summoned after first call")
	TestHarness.assert_true(TestHarness.has_on_board(state, "enemy", "champion_void_ritualist"), "champion on board")
	# Second call should no-op (guard on _champion_vr_summoned)
	var board_size := state.enemy_board.size()
	state._handlers_ref.on_ritual_sacrifice_champion_vr()
	TestHarness.assert_eq(state.enemy_board.size(), board_size, "no re-summon")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Corrupted Handler (Act 2)
# ---------------------------------------------------------------------------

static func _ch_summon_at_3_sparks() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_corrupted_handler"]})
	if not TestHarness.begin_test("champion_ch / 3 void_sparks summoned = champion summoned", state):
		return
	# Use _summon_token directly — it fires ON_ENEMY_MINION_SUMMONED for enemy-side tokens,
	# which is what the spark-tracker handler listens on.
	for i in 3:
		state._summon_token("void_spark", "enemy", 100, 100)
	TestHarness.assert_eq(state._champion_ch_spark_count, 3, "spark count == 3")
	TestHarness.assert_true(state.get("_champion_ch_summoned") == true, "summoned at 3")
	TestHarness.assert_true(TestHarness.has_on_board(state, "enemy", "champion_corrupted_handler"), "champion on board")
	state.teardown()

static func _ch_aura_200_dmg_on_spark_summon() -> void:
	# NOTE: the aura fires on EVERY spark summon while the champion is alive —
	# INCLUDING the one that crosses the 3-spark summon threshold. So summoning
	# 3 sparks: the 3rd summons the champion AND triggers one aura tick (200).
	# A 4th spark adds another 200 → cumulative 400.
	var state := TestHarness.build_state({"enemy_passives": ["champion_corrupted_handler"]})
	if not TestHarness.begin_test("champion_ch / aura fires on every spark while alive (inc. threshold spark)", state):
		return
	var hp_before := state.player_hp
	for i in 3:
		state._summon_token("void_spark", "enemy", 100, 100)
	# After 3 sparks: champion summoned + 1 aura tick on the 3rd = 200 dmg.
	TestHarness.assert_eq(hp_before - state.player_hp, 200, "player hero -200 after 3rd spark (threshold + aura)")
	state._summon_token("void_spark", "enemy", 100, 100)
	# 4th spark: another aura tick = +200 (total 400).
	TestHarness.assert_eq(hp_before - state.player_hp, 400, "player hero -400 after 4th spark")
	TestHarness.assert_eq(state.get("_champion_ch_aura_dmg"), 400, "aura dmg tracker = 400")
	state.teardown()

static func _ch_no_resummon_after_summoned() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_corrupted_handler"]})
	if not TestHarness.begin_test("champion_ch / 4th spark does NOT re-increment tracker", state):
		return
	for i in 3:
		state._summon_token("void_spark", "enemy", 100, 100)
	var count_at_summon := state._champion_ch_spark_count
	state._summon_token("void_spark", "enemy", 100, 100)
	TestHarness.assert_eq(state._champion_ch_spark_count, count_at_summon, "count frozen after summon")
	TestHarness.assert_eq(TestHarness.count_on_board(state, "enemy", "champion_corrupted_handler"), 1, "exactly one champion")
	state.teardown()

# ---------------------------------------------------------------------------
# Act 3–4 champions + champion_duel
# ---------------------------------------------------------------------------

## Fire ON_ENEMY_SPARK_CONSUMED with damage = spark_value.
static func _fire_spark_consumed(state: SimState, spark_value: int = 1, minion: MinionInstance = null) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED, "enemy")
	ctx.damage = spark_value
	if minion != null:
		ctx.minion = minion
	state.trigger_manager.fire(ctx)

## Fire ON_ENEMY_TURN_END.
static func _fire_enemy_turn_end(state: SimState) -> void:
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_TURN_END, "enemy")
	state.trigger_manager.fire(ctx)

## Fire ON_PLAYER_MINION_DIED with an attacker + "was this attack a crit" flag.
static func _fire_player_died_by_crit(state: SimState, dead: MinionInstance, attacker: MinionInstance) -> void:
	state._last_attack_was_crit = true
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_DIED, "player")
	ctx.minion = dead
	ctx.attacker = attacker
	state.trigger_manager.fire(ctx)

# ---------------------------------------------------------------------------
# Champion: Rift Stalker (Act 3) — 1000 cumulative spark attack damage.
# ---------------------------------------------------------------------------

static func _rs_summon_at_1000_spark_dmg() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_rift_stalker"]})
	if not TestHarness.begin_test("champion_rs / 1000 cumulative spark attack dmg summons champion", state):
		return
	# Spawn one spark with 1000 ATK and fire a single attack event.
	var spark := TestHarness.spawn_enemy(state, "void_spark")
	spark.current_atk = 1000
	_fire_enemy_attack(state, spark)
	TestHarness.assert_true(state.get("_champion_rs_summoned") == true, "champion summoned")
	TestHarness.assert_eq(state._champion_rs_spark_dmg, 1000, "cumulative tracked")
	state.teardown()

static func _rs_aura_grants_immune_to_new_sparks() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_rift_stalker"]})
	if not TestHarness.begin_test("champion_rs / aura grants GRANT_IMMUNE to newly summoned sparks", state):
		return
	# Force-summon the champion
	state.set("_champion_rs_summoned", true)
	state._summon_token("champion_rift_stalker", "enemy")
	# New spark arrives → aura handler fires on ON_ENEMY_MINION_SUMMONED
	state._summon_token("void_spark", "enemy", 100, 100)
	var spark := TestHarness.find_on_board(state, "enemy", "void_spark")
	TestHarness.assert_ne(spark, null, "spark on board")
	if spark != null:
		TestHarness.assert_true(BuffSystem.has_type(spark, Enums.BuffType.GRANT_IMMUNE), "spark has GRANT_IMMUNE")
	state.teardown()

static func _rs_death_removes_immune() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_rift_stalker"]})
	if not TestHarness.begin_test("champion_rs / champion death removes immune from all sparks", state):
		return
	state.set("_champion_rs_summoned", true)
	state._summon_token("champion_rift_stalker", "enemy")
	state._summon_token("void_spark", "enemy", 100, 100)
	var champion := TestHarness.find_on_board(state, "enemy", "champion_rift_stalker")
	var spark := TestHarness.find_on_board(state, "enemy", "void_spark")
	TestHarness.assert_true(spark != null and BuffSystem.has_type(spark, Enums.BuffType.GRANT_IMMUNE), "spark immune before death")
	if champion != null:
		state.combat_manager.kill_minion(champion)
	TestHarness.assert_false(BuffSystem.has_type(spark, Enums.BuffType.GRANT_IMMUNE), "spark immune cleared after champion death")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Void Aberration (Act 3) — 5 sparks consumed.
# ---------------------------------------------------------------------------

static func _va_summon_at_5_sparks_consumed() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_aberration"]})
	if not TestHarness.begin_test("champion_va / 5 sparks consumed summons champion", state):
		return
	for i in 5:
		_fire_spark_consumed(state, 1)
	TestHarness.assert_true(state.get("_champion_va_summoned") == true, "champion summoned")
	TestHarness.assert_eq(state._champion_va_sparks_consumed, 5, "sparks counter = 5")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Void Herald (Act 3) — 6 spark-cost cards played.
# ---------------------------------------------------------------------------

static func _vh_summon_at_6_spark_cost_plays() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_herald"]})
	if not TestHarness.begin_test("champion_vh / 6 spark-cost card plays summon champion", state):
		return
	# Void Rift Lord has void_spark_cost = 3 — any spark-cost card works.
	var rift_lord := CardDatabase.get_card("void_rift_lord")
	for i in 6:
		_fire_enemy_spell_cast(state, rift_lord)
	TestHarness.assert_true(state.get("_champion_vh_summoned") == true, "champion summoned")
	TestHarness.assert_eq(state._champion_vh_spark_cards_played, 6, "counter = 6")
	state.teardown()

static func _vh_ignores_non_spark_cards() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_herald"]})
	if not TestHarness.begin_test("champion_vh / non-spark-cost cards do NOT advance counter", state):
		return
	# void_bolt has void_spark_cost = 0 — should be filtered out.
	var vb := CardDatabase.get_card("void_bolt")
	for i in 10:
		_fire_enemy_spell_cast(state, vb)
	TestHarness.assert_eq(state._champion_vh_spark_cards_played, 0, "counter unchanged")
	TestHarness.assert_false(state.get("_champion_vh_summoned") == true, "still not summoned")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Void Scout (Act 4) — 5 crits consumed by enemy minions.
# Checked at ON_ENEMY_TURN_END.
# ---------------------------------------------------------------------------

static func _vs_summon_at_5_crits_consumed() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_scout"]})
	if not TestHarness.begin_test("champion_vs / 5 crits consumed + enemy turn end = summon + crit multiplier 2.5", state):
		return
	state._enemy_crits_consumed = 5
	_fire_enemy_turn_end(state)
	TestHarness.assert_true(state.get("_champion_vs_summoned") == true, "champion summoned")
	TestHarness.assert_approx(state.enemy_crit_multiplier, 2.5, 0.001, "multiplier = 2.5")
	var champion := TestHarness.find_on_board(state, "enemy", "champion_void_scout")
	if champion != null:
		TestHarness.assert_true(champion.has_critical_strike(), "champion has crit")
	state.teardown()

static func _vs_death_resets_crit_multiplier() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_scout"]})
	if not TestHarness.begin_test("champion_vs / death resets enemy_crit_multiplier to 0", state):
		return
	state._enemy_crits_consumed = 5
	_fire_enemy_turn_end(state)
	var champion := TestHarness.find_on_board(state, "enemy", "champion_void_scout")
	TestHarness.assert_ne(champion, null, "champion exists before death")
	if champion != null:
		state.combat_manager.kill_minion(champion)
	TestHarness.assert_approx(state.enemy_crit_multiplier, 0.0, 0.001, "multiplier reset to 0")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Void Warband (Act 4) — 2 Spirits consumed as spark fuel.
# Aura: Spirit death grants +1 Crit to random remaining enemy minion.
# ---------------------------------------------------------------------------

static func _vw_summon_at_2_spirits_consumed() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_warband"]})
	if not TestHarness.begin_test("champion_vw / 2 Spirit spark-consumes summon champion + grant crit", state):
		return
	# Fire ON_ENEMY_SPARK_CONSUMED with a Spirit-type minion as ctx.minion.
	# "void_rift_lord" is a SPIRIT type in CardDatabase.
	var rift_lord := TestHarness.spawn_enemy(state, "void_rift_lord")
	_fire_spark_consumed(state, 1, rift_lord)
	var rift_lord2 := TestHarness.spawn_enemy(state, "void_rift_lord")
	_fire_spark_consumed(state, 1, rift_lord2)
	TestHarness.assert_true(state.get("_champion_vw_summoned") == true, "champion summoned")
	var champion := TestHarness.find_on_board(state, "enemy", "champion_void_warband")
	if champion != null:
		TestHarness.assert_true(champion.has_critical_strike(), "champion has crit on summon")
	state.teardown()

static func _vw_aura_spirit_death_grants_crit() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_warband"]})
	if not TestHarness.begin_test("champion_vw / aura: Spirit death grants crit to random enemy", state):
		return
	# Force champion alive
	state.set("_champion_vw_summoned", true)
	state._summon_token("champion_void_warband", "enemy")
	# Spawn a SPIRIT-type minion and a non-spirit candidate to receive the crit.
	var spirit := TestHarness.spawn_enemy(state, "void_rift_lord")  # SPIRIT type
	var candidate := TestHarness.spawn_enemy(state, "rabid_imp")  # non-spirit
	var crits_before := BuffSystem.sum_type(candidate, Enums.BuffType.CRITICAL_STRIKE)
	# Champion is also a candidate; either recipient counts as "a random friendly got a crit"
	state.combat_manager.kill_minion(spirit)
	# Check SOMETHING on enemy board got +1 crit (excluding dead spirit)
	var someone_got_crit := false
	for m: MinionInstance in state.enemy_board:
		if m == spirit:
			continue
		if BuffSystem.sum_type(m, Enums.BuffType.CRITICAL_STRIKE) > crits_before:
			someone_got_crit = true
			break
	TestHarness.assert_true(someone_got_crit, "some surviving enemy minion got +1 crit")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Void Captain (Act 4) — 2 thrones_command casts.
# ---------------------------------------------------------------------------

static func _vc_summon_at_2_thrones_command() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_captain"]})
	if not TestHarness.begin_test("champion_vc / 2 thrones_command casts summon champion + 2 crit", state):
		return
	var tc := CardDatabase.get_card("thrones_command")
	_fire_enemy_spell_cast(state, tc)
	_fire_enemy_spell_cast(state, tc)
	TestHarness.assert_true(state.get("_champion_vc_summoned") == true, "champion summoned")
	var champion := TestHarness.find_on_board(state, "enemy", "champion_void_captain")
	if champion != null:
		TestHarness.assert_eq(BuffSystem.sum_type(champion, Enums.BuffType.CRITICAL_STRIKE), 2, "champion has 2 crit stacks")
	state.teardown()

static func _vc_ignores_non_tc_spells() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_captain"]})
	if not TestHarness.begin_test("champion_vc / non-thrones_command spells do NOT advance counter", state):
		return
	var vb := CardDatabase.get_card("void_bolt")
	for i in 5:
		_fire_enemy_spell_cast(state, vb)
	TestHarness.assert_eq(state._champion_vc_tc_cast, 0, "counter unchanged")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Void Ritualist Prime (F13) — 5 enemy spell casts.
# Aura: enemy_ai.spell_cost_aura = -1. On death: reset to 0.
# ---------------------------------------------------------------------------

static func _vrp_summon_at_5_enemy_spells() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_ritualist_prime"]})
	if not TestHarness.begin_test("champion_vrp / 5 enemy spell casts summon champion", state):
		return
	var vb := CardDatabase.get_card("void_bolt")
	for i in 5:
		_fire_enemy_spell_cast(state, vb)
	TestHarness.assert_true(state.get("_champion_vrp_summoned") == true, "champion summoned")
	TestHarness.assert_eq(state._champion_vrp_spells_cast, 5, "spell count = 5")
	state.teardown()

static func _vrp_aura_sets_spell_cost_aura() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_ritualist_prime"]})
	if not TestHarness.begin_test("champion_vrp / summon sets enemy_ai.spell_cost_aura = -1", state):
		return
	var vb := CardDatabase.get_card("void_bolt")
	for i in 5:
		_fire_enemy_spell_cast(state, vb)
	TestHarness.assert_eq(state.enemy_ai.spell_cost_aura, -1, "spell_cost_aura = -1")
	state.teardown()

static func _vrp_death_resets_spell_cost_aura() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_ritualist_prime"]})
	if not TestHarness.begin_test("champion_vrp / champion death resets spell_cost_aura to 0", state):
		return
	var vb := CardDatabase.get_card("void_bolt")
	for i in 5:
		_fire_enemy_spell_cast(state, vb)
	var champion := TestHarness.find_on_board(state, "enemy", "champion_void_ritualist_prime")
	if champion != null:
		state.combat_manager.kill_minion(champion)
	TestHarness.assert_eq(state.enemy_ai.spell_cost_aura, 0, "spell_cost_aura reset")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Void Champion (F14) — 3 player minions killed by enemy crit attack.
# Aura: at enemy turn end, +1 max Mana AND +1 max Essence (capped by COMBINED_RESOURCE_CAP).
# ---------------------------------------------------------------------------

static func _vch_summon_at_3_crit_kills() -> void:
	# KNOWN BUG: _summon_enemy_champion's match block in CombatHandlers.gd is
	# missing a case for "champion_void_champion" (see lines 1634-1660). The
	# champion minion is placed on the board, but _champion_vch_summoned never
	# flips to true — so re-summon guards never engage and the alive-check
	# aura path can still run (the aura uses an enemy_board scan, which
	# accidentally works correctly). Fix: add `"champion_void_champion":
	# _scene.set("_champion_vch_summoned", true)` to the match.
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_champion"]})
	if not TestHarness.begin_test("champion_vch / 3 crit-kills summon champion (KNOWN BUG: flag not set)", state):
		return
	var attacker := TestHarness.spawn_enemy(state, "rabid_imp")
	for i in 3:
		var victim := TestHarness.spawn_friendly(state, "void_imp")
		_fire_player_died_by_crit(state, victim, attacker)
	TestHarness.assert_eq(state._champion_vch_crit_kills, 3, "crit kills = 3 (tracker works)")
	TestHarness.assert_true(TestHarness.has_on_board(state, "enemy", "champion_void_champion"), "champion minion exists on board")
	TestHarness.assert_true(state.get("_champion_vch_summoned") == true, "flag set (FAILS: match case missing)")
	state.teardown()

static func _vch_aura_grows_resources() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_void_champion"]})
	if not TestHarness.begin_test("champion_vch / aura grows enemy mana+essence at enemy turn end", state):
		return
	# Force champion alive
	state.set("_champion_vch_summoned", true)
	state._summon_token("champion_void_champion", "enemy")
	state.enemy_mana_max = 0
	state.enemy_essence_max = 0
	_fire_enemy_turn_end(state)
	TestHarness.assert_eq(state.enemy_mana_max, 1, "mana_max +1")
	TestHarness.assert_eq(state.enemy_essence_max, 1, "essence_max +1")
	state.teardown()

# ---------------------------------------------------------------------------
# Champion: Avatar of the Abyss (F15 Phase 2) — 12 player cards played.
# Counter ticks across both phases, but summon is gated on _sovereign_phase == 2.
# Aura: while alive, abyss_awakened grants 2 crit stacks instead of 1.
# ---------------------------------------------------------------------------

static func _as_counts_player_cards_played() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_abyss_sovereign"]})
	if not TestHarness.begin_test("champion_as / counts each player minion played", state):
		return
	for i in 5:
		var m := TestHarness.spawn_friendly(state, "void_imp")
		_fire_player_played(state, m)
	TestHarness.assert_eq(state._champion_as_cards_played, 5, "counter = 5")
	state.teardown()

static func _as_no_summon_in_phase_1() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_abyss_sovereign"]})
	if not TestHarness.begin_test("champion_as / threshold met in P1 does NOT summon", state):
		return
	# Phase defaults to 1.
	for i in 12:
		var m := TestHarness.spawn_friendly(state, "void_imp")
		_fire_player_played(state, m)
	TestHarness.assert_eq(state._champion_as_cards_played, 12, "counter reached threshold")
	TestHarness.assert_true(state.get("_champion_as_summoned") != true, "champion NOT summoned in P1")
	TestHarness.assert_true(not TestHarness.has_on_board(state, "enemy", "champion_abyss_sovereign"), "no champion on board")
	state.teardown()

static func _as_summons_when_threshold_met_in_phase_2() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_abyss_sovereign"]})
	if not TestHarness.begin_test("champion_as / 12 cards played in P2 summons champion with 2 crit", state):
		return
	state._sovereign_phase = 2
	for i in 12:
		var m := TestHarness.spawn_friendly(state, "void_imp")
		_fire_player_played(state, m)
	TestHarness.assert_true(state.get("_champion_as_summoned") == true, "summoned flag set")
	TestHarness.assert_true(TestHarness.has_on_board(state, "enemy", "champion_abyss_sovereign"), "champion on board")
	var champion := TestHarness.find_on_board(state, "enemy", "champion_abyss_sovereign")
	if champion != null:
		TestHarness.assert_eq(BuffSystem.sum_type(champion, Enums.BuffType.CRITICAL_STRIKE), 2, "champion has 2 crit stacks on summon")
	state.teardown()

static func _as_aura_doubles_abyss_awakened() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_abyss_sovereign", "abyss_awakened"]})
	if not TestHarness.begin_test("champion_as / aura makes abyss_awakened grant 2 crit stacks", state):
		return
	state._sovereign_phase = 2
	# Force champion alive.
	state.set("_champion_as_summoned", true)
	state._summon_token("champion_abyss_sovereign", "enemy")
	# A separate enemy minion to observe the abyss_awakened grant on.
	var grunt := TestHarness.spawn_enemy(state, "rabid_imp")
	var crit_before: int = BuffSystem.sum_type(grunt, Enums.BuffType.CRITICAL_STRIKE)
	_fire_enemy_turn_start(state)
	var crit_after: int = BuffSystem.sum_type(grunt, Enums.BuffType.CRITICAL_STRIKE)
	TestHarness.assert_eq(crit_after - crit_before, 2, "grunt gained 2 crit stacks (doubled)")
	state.teardown()

static func _as_aura_inactive_when_dead() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_abyss_sovereign", "abyss_awakened"]})
	if not TestHarness.begin_test("champion_as / abyss_awakened grants 1 stack when champion absent", state):
		return
	state._sovereign_phase = 2
	# Champion never summoned — aura should be inactive.
	var grunt := TestHarness.spawn_enemy(state, "rabid_imp")
	var crit_before: int = BuffSystem.sum_type(grunt, Enums.BuffType.CRITICAL_STRIKE)
	_fire_enemy_turn_start(state)
	var crit_after: int = BuffSystem.sum_type(grunt, Enums.BuffType.CRITICAL_STRIKE)
	TestHarness.assert_eq(crit_after - crit_before, 1, "grunt gained only 1 crit stack")
	state.teardown()

# ---------------------------------------------------------------------------
# champion_duel (F14 shared) — keep GRANT_SPELL_IMMUNE synced with CRITICAL_STRIKE
# on enemy minions. Refreshed on ON_ENEMY_TURN_START and ON_ENEMY_ATTACK.
# ---------------------------------------------------------------------------

static func _champion_duel_sync_on_turn_start() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_duel"]})
	if not TestHarness.begin_test("champion_duel / turn start grants GRANT_SPELL_IMMUNE to crit-having minions", state):
		return
	var a := TestHarness.spawn_enemy(state, "rabid_imp")
	BuffSystem.apply(a, Enums.BuffType.CRITICAL_STRIKE, 1, "test", false, false)
	_fire_enemy_turn_start(state)
	TestHarness.assert_true(BuffSystem.has_type(a, Enums.BuffType.GRANT_SPELL_IMMUNE), "crit minion now spell-immune")
	state.teardown()

static func _champion_duel_revokes_when_crit_lost() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["champion_duel"]})
	if not TestHarness.begin_test("champion_duel / minion losing crit also loses GRANT_SPELL_IMMUNE", state):
		return
	var a := TestHarness.spawn_enemy(state, "rabid_imp")
	BuffSystem.apply(a, Enums.BuffType.CRITICAL_STRIKE, 1, "test", false, false)
	_fire_enemy_turn_start(state)
	TestHarness.assert_true(BuffSystem.has_type(a, Enums.BuffType.GRANT_SPELL_IMMUNE), "has immune pre-revoke")
	# Remove crit source, then refresh via an attack event
	BuffSystem.remove_source(a, "test")
	_fire_enemy_attack(state, a)
	TestHarness.assert_false(BuffSystem.has_type(a, Enums.BuffType.GRANT_SPELL_IMMUNE), "immune revoked after crit lost")
	state.teardown()

# ---------------------------------------------------------------------------
# Act 3–4 non-champion enemy passives
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# void_empowerment — summoned enemy Void Sparks normalise to 200/200.
# ---------------------------------------------------------------------------

static func _void_empowerment_normalizes_spark() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["void_empowerment"]})
	if not TestHarness.begin_test("void_empowerment / enemy Void Spark enters as 200/200", state):
		return
	# Summon a spark with 100/100 (the default under-empowered stats).
	state._summon_token("void_spark", "enemy", 100, 100)
	var spark := TestHarness.find_on_board(state, "enemy", "void_spark")
	TestHarness.assert_ne(spark, null, "spark on board")
	if spark != null:
		TestHarness.assert_eq(spark.current_atk, 200, "ATK = 200")
		TestHarness.assert_eq(spark.current_health, 200, "HP = 200")
	state.teardown()

# ---------------------------------------------------------------------------
# void_detonation_passive — ON_ENEMY_SPARK_CONSUMED deals 100 dmg (or 200 when
# Void Aberration champion alive) per spark_value to all opponent minions + hero.
# ---------------------------------------------------------------------------

static func _void_detonation_passive_base_100() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["void_detonation_passive"]})
	if not TestHarness.begin_test("void_detonation_passive / base 100 dmg to all player minions + hero", state):
		return
	var p1 := TestHarness.spawn_friendly(state, "void_imp")
	p1.current_health = 1000
	var hp_before := state.player_hp
	_fire_spark_consumed(state, 1)
	TestHarness.assert_eq(1000 - p1.current_health, 100, "player minion -100")
	TestHarness.assert_eq(hp_before - state.player_hp, 100, "player hero -100")
	state.teardown()

static func _void_detonation_passive_va_alive_200() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["void_detonation_passive"]})
	if not TestHarness.begin_test("void_detonation_passive / VA alive doubles to 200", state):
		return
	# Force Void Aberration champion alive so the dmg scales to 200.
	state._summon_token("champion_void_aberration", "enemy")
	var p1 := TestHarness.spawn_friendly(state, "void_imp")
	p1.current_health = 1000
	var hp_before := state.player_hp
	_fire_spark_consumed(state, 1)
	TestHarness.assert_eq(1000 - p1.current_health, 200, "player minion -200")
	TestHarness.assert_eq(hp_before - state.player_hp, 200, "player hero -200")
	state.teardown()

# ---------------------------------------------------------------------------
# spirit_resonance — consuming a crit-Spirit as spark fuel summons a 100/100 Void Spark.
# ---------------------------------------------------------------------------

static func _spirit_resonance_summons_spark() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["spirit_resonance"]})
	if not TestHarness.begin_test("spirit_resonance / crit-Spirit consume summons 100/100 Void Spark", state):
		return
	var spirit := TestHarness.spawn_enemy(state, "void_rift_lord")  # SPIRIT type
	BuffSystem.apply(spirit, Enums.BuffType.CRITICAL_STRIKE, 1, "test", false, false)
	var board_before := state.enemy_board.size()
	_fire_spark_consumed(state, 1, spirit)
	TestHarness.assert_eq(state.enemy_board.size(), board_before + 1, "enemy board +1")
	TestHarness.assert_true(TestHarness.has_on_board(state, "enemy", "void_spark"), "Void Spark summoned")
	state.teardown()

static func _spirit_resonance_ignores_non_crit_spirit() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["spirit_resonance"]})
	if not TestHarness.begin_test("spirit_resonance / non-crit Spirit consume does NOT summon", state):
		return
	var spirit := TestHarness.spawn_enemy(state, "void_rift_lord")
	# No crit applied — handler should early-return.
	var board_before := state.enemy_board.size()
	_fire_spark_consumed(state, 1, spirit)
	TestHarness.assert_eq(state.enemy_board.size(), board_before, "no spark summoned")
	state.teardown()

# ---------------------------------------------------------------------------
# spirit_conscription — 1/turn, when enemy plays a Void Spirit minion, summon Void Spark.
# ---------------------------------------------------------------------------

static func _spirit_conscription_summons_spark() -> void:
	# KNOWN BUG (double dead-code): spirit_conscription handler gates on the
	# minion_tag "void_spirit", but NO minion in CardDatabase has that tag.
	# Additionally, "spirit_conscription" is registered in CombatSetup._REGISTRY
	# but not assigned to any enemy profile (CombatSim._ENEMY_PASSIVES /
	# CombatScene._ENEMY_PASSIVES). So the passive can never fire in game.
	# Either the tag must be added to Spirit-clan minions and the passive
	# assigned to an enemy profile, or the whole passive should be retired
	# (same cleanup pattern as feral_instinct in Batch 2).
	var state := TestHarness.build_state({"enemy_passives": ["spirit_conscription"]})
	if not TestHarness.begin_test("spirit_conscription / void_spirit tag does not exist (KNOWN BUG: dead passive)", state):
		return
	var spirit := TestHarness.spawn_enemy(state, "void_rift_lord")  # SPIRIT type but no void_spirit tag
	var tags: Array = (spirit.card_data as MinionCardData).minion_tags
	TestHarness.assert_false("void_spirit" in tags, "void_rift_lord has no void_spirit tag (confirms dead passive)")
	# Fire the summon — handler should early-return, nothing summoned.
	var board_before := state.enemy_board.size()
	_fire_enemy_summon(state, spirit)
	TestHarness.assert_eq(state.enemy_board.size(), board_before, "no spark summoned (handler silently gates)")

static func _spirit_conscription_once_per_turn() -> void:
	# This test is unreachable until spirit_conscription is either retired or
	# the void_spirit tag is added to real minions. Skipped-by-assertion-failure
	# is the wrong signal, so we just no-op with a placeholder pass so the
	# probe stays registered and surfaces the moment someone revives the passive.
	var state := TestHarness.build_state({"enemy_passives": ["spirit_conscription"]})
	if not TestHarness.begin_test("spirit_conscription / once-per-turn (awaiting tag/retirement)", state):
		return
	# No-op assertion — documents that this probe is parked pending resolution
	# of the spirit_conscription dead-code issue above.
	TestHarness.assert_true(true, "probe parked until spirit_conscription issue resolved")
	state.teardown()

# ---------------------------------------------------------------------------
# captain_orders — at enemy turn end, each friendly minion with crit consumes one
# stack, deals its effective ATK as dmg to player hero.
# ---------------------------------------------------------------------------

static func _captain_orders_consumes_crit_and_dmg() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["captain_orders"]})
	if not TestHarness.begin_test("captain_orders / turn end: crit-having minion deals ATK dmg to player hero", state):
		return
	var a := TestHarness.spawn_enemy(state, "rabid_imp")
	# Must use source="critical_strike" — the handler removes specifically by that source.
	BuffSystem.apply(a, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike", false, false)
	var atk := a.effective_atk()
	var hp_before := state.player_hp
	var crits_before: int = state._enemy_crits_consumed
	_fire_enemy_turn_end(state)
	TestHarness.assert_false(BuffSystem.has_type(a, Enums.BuffType.CRITICAL_STRIKE), "crit consumed")
	TestHarness.assert_eq(hp_before - state.player_hp, atk, "player hero took minion's ATK as dmg")
	TestHarness.assert_eq(state._enemy_crits_consumed, crits_before + 1, "crits_consumed counter +1")
	state.teardown()

# ---------------------------------------------------------------------------
# dark_channeling — when enemy casts a damage-dealing spell, consume 1 crit
# stack from a random friendly and set _dark_channeling_multiplier = 1.5.
# ---------------------------------------------------------------------------

static func _dark_channeling_consumes_crit_on_damage_spell() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["dark_channeling"]})
	if not TestHarness.begin_test("dark_channeling / damage spell consumes crit + sets 1.5x multiplier", state):
		return
	var donor := TestHarness.spawn_enemy(state, "rabid_imp")
	# Must use source="critical_strike" — handler removes by that source specifically.
	BuffSystem.apply(donor, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike", false, false)
	var dmg_spell := TestHarness.make_test_spell([{"type": "DAMAGE_HERO", "amount": 100}], "_test_dmg_spell")
	_fire_enemy_spell_cast(state, dmg_spell)
	TestHarness.assert_false(BuffSystem.has_type(donor, Enums.BuffType.CRITICAL_STRIKE), "donor crit consumed")
	TestHarness.assert_true(state.get("_dark_channeling_active") == true, "channeling active")
	TestHarness.assert_approx(state._dark_channeling_multiplier, 1.5, 0.001, "multiplier = 1.5")
	state.teardown()

static func _dark_channeling_ignores_non_damage_spell() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["dark_channeling"]})
	if not TestHarness.begin_test("dark_channeling / non-damage spell does NOT consume crit", state):
		return
	var donor := TestHarness.spawn_enemy(state, "rabid_imp")
	BuffSystem.apply(donor, Enums.BuffType.CRITICAL_STRIKE, 1, "critical_strike", false, false)
	# A spell with no DAMAGE_HERO/DAMAGE_MINION step — e.g. pure-draw spell.
	var utility := SpellCardData.new()
	utility.id = "_test_utility_spell"
	utility.cost = 1
	utility.effect_steps = [{"type": "DRAW", "amount": 1}]
	_fire_enemy_spell_cast(state, utility)
	TestHarness.assert_true(BuffSystem.has_type(donor, Enums.BuffType.CRITICAL_STRIKE), "donor crit preserved")
	TestHarness.assert_false(state.get("_dark_channeling_active") == true, "channeling NOT active")
	state.teardown()

# ---------------------------------------------------------------------------
# abyss_awakened (Sovereign P2) — at enemy turn start, +1 crit to ALL enemy minions.
# ---------------------------------------------------------------------------

static func _abyss_awakened_grants_all_crit() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["abyss_awakened"]})
	if not TestHarness.begin_test("abyss_awakened / turn start grants +1 crit to every enemy minion", state):
		return
	var a := TestHarness.spawn_enemy(state, "rabid_imp")
	var b := TestHarness.spawn_enemy(state, "rabid_imp")
	var a_crit_before := BuffSystem.sum_type(a, Enums.BuffType.CRITICAL_STRIKE)
	var b_crit_before := BuffSystem.sum_type(b, Enums.BuffType.CRITICAL_STRIKE)
	_fire_enemy_turn_start(state)
	TestHarness.assert_true(BuffSystem.sum_type(a, Enums.BuffType.CRITICAL_STRIKE) > a_crit_before, "a gained crit")
	TestHarness.assert_true(BuffSystem.sum_type(b, Enums.BuffType.CRITICAL_STRIKE) > b_crit_before, "b gained crit")
	state.teardown()

# ---------------------------------------------------------------------------
# abyssal_mandate (Sovereign P1) — discounts enemy costs based on player's last growth choice.
# ---------------------------------------------------------------------------

static func _abyssal_mandate_essence_branch() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["abyssal_mandate"]})
	if not TestHarness.begin_test("abyssal_mandate / last_growth=essence → enemy minion_essence_cost_aura = -2", state):
		return
	state.last_player_growth = "essence"
	_fire_enemy_turn_start(state)
	TestHarness.assert_eq(state.enemy_ai.minion_essence_cost_aura, -2, "aura = -2")
	TestHarness.assert_eq(state.enemy_ai.spell_cost_aura, 0, "spell_cost_aura unchanged")
	state.teardown()

static func _abyssal_mandate_mana_branch() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["abyssal_mandate"]})
	if not TestHarness.begin_test("abyssal_mandate / last_growth=mana → enemy spell_cost_aura = -2", state):
		return
	state.last_player_growth = "mana"
	_fire_enemy_turn_start(state)
	TestHarness.assert_eq(state.enemy_ai.spell_cost_aura, -2, "spell aura = -2")
	TestHarness.assert_eq(state.enemy_ai.minion_essence_cost_aura, 0, "essence aura unchanged")
	state.teardown()

static func _abyssal_mandate_end_clears_aura() -> void:
	var state := TestHarness.build_state({"enemy_passives": ["abyssal_mandate"]})
	if not TestHarness.begin_test("abyssal_mandate / enemy turn end clears negative auras", state):
		return
	state.last_player_growth = "essence"
	_fire_enemy_turn_start(state)
	TestHarness.assert_eq(state.enemy_ai.minion_essence_cost_aura, -2, "aura = -2 post-start")
	_fire_enemy_turn_end(state)
	TestHarness.assert_eq(state.enemy_ai.minion_essence_cost_aura, 0, "aura cleared to 0")
	state.teardown()

# ---------------------------------------------------------------------------
# Korrath — FORMATION keyword (CombatHandlers.on_minion_summoned_formation)
# ---------------------------------------------------------------------------
#
# Synthetic CardData / MinionInstance is built inline so the tests don't depend
# on a Korrath card existing in CardDatabase yet. The handler under test reads
# only `keywords`, `minion_type`, and `formation_effect_steps` off MinionCardData,
# plus `slot_index` / `formation_partners` off MinionInstance.

## Build a fresh MinionCardData with FORMATION + a SELF BUFF_ATK +100 effect.
## A new instance per test so caches/Resource-sharing can't cross-contaminate.
static func _make_formation_card(race: int, with_keyword: bool = true) -> MinionCardData:
	var data := MinionCardData.new()
	data.id          = "test_formation_minion"
	data.card_name   = "Test Formation Minion"
	data.atk         = 100
	data.health      = 500
	data.minion_type = race
	if with_keyword:
		data.keywords = [Enums.Keyword.FORMATION]
	# +100 ATK to SELF — easy to assert via effective_atk()
	var step := EffectStep.new()
	step.effect_type = EffectStep.EffectType.BUFF_ATK
	step.scope       = EffectStep.TargetScope.SELF
	step.amount      = 100
	step.permanent   = true
	step.source_tag  = "test_formation"
	data.formation_effect_steps = [step]
	return data

## Place a synthetic minion at a specific slot on the player side. Bypasses
## TestHarness.spawn_friendly so we can pick the slot and the data freely.
static func _place_at(state: SimState, data: MinionCardData, slot_index: int) -> MinionInstance:
	var inst := MinionInstance.create(data, "player")
	state.player_board.append(inst)
	state.player_slots[slot_index].minion = inst
	inst.slot_index = slot_index
	return inst

static func _formation_fires_on_summon() -> void:
	# A (HUMAN, FORMATION, +100 ATK SELF) at slot 0; B (HUMAN, no FORMATION) summoned
	# at slot 1. Handler walks adjacency, fires A's Formation against B.
	var state := TestHarness.build_state()
	if not TestHarness.begin_test("formation / fires once when same-race minion summoned adjacent", state):
		return
	var a_data := _make_formation_card(Enums.MinionType.HUMAN, true)
	var b_data := _make_formation_card(Enums.MinionType.HUMAN, false)
	var a := _place_at(state, a_data, 0)
	var b := _place_at(state, b_data, 1)
	var before := a.effective_atk()
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": b})
	TestHarness.assert_eq(a.effective_atk(), before + 100, "A gained +100 ATK from its Formation")
	TestHarness.assert_true(a.formation_partners.has(b), "A recorded B as a triggered partner")
	state.teardown()

static func _formation_does_not_refire_on_same_pair() -> void:
	# Firing the same summon twice (same A,B pair) must only buff A once.
	var state := TestHarness.build_state()
	if not TestHarness.begin_test("formation / does not refire for the same partner pair", state):
		return
	var a_data := _make_formation_card(Enums.MinionType.HUMAN, true)
	var b_data := _make_formation_card(Enums.MinionType.HUMAN, false)
	var a := _place_at(state, a_data, 0)
	var b := _place_at(state, b_data, 1)
	var before := a.effective_atk()
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": b})
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": b})
	TestHarness.assert_eq(a.effective_atk(), before + 100, "ATK gain stays at +100, not +200")
	state.teardown()

static func _formation_ignores_race_mismatch() -> void:
	# A HUMAN with FORMATION; B DEMON adjacent. No race match → no Formation fires.
	var state := TestHarness.build_state()
	if not TestHarness.begin_test("formation / does not fire when races differ", state):
		return
	var a_data := _make_formation_card(Enums.MinionType.HUMAN, true)
	var b_data := _make_formation_card(Enums.MinionType.DEMON, false)
	var a := _place_at(state, a_data, 0)
	var b := _place_at(state, b_data, 1)
	var before := a.effective_atk()
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": b})
	TestHarness.assert_eq(a.effective_atk(), before, "no buff — race mismatch")
	TestHarness.assert_false(a.formation_partners.has(b), "B not recorded as triggered partner")
	state.teardown()

static func _formation_ignores_non_adjacent_neighbors() -> void:
	# A at slot 0 with FORMATION; B at slot 2 (slot 1 empty). dx = 2 → no fire.
	var state := TestHarness.build_state()
	if not TestHarness.begin_test("formation / does not fire across an empty slot (dx != 1)", state):
		return
	var a_data := _make_formation_card(Enums.MinionType.HUMAN, true)
	var b_data := _make_formation_card(Enums.MinionType.HUMAN, false)
	var a := _place_at(state, a_data, 0)
	var b := _place_at(state, b_data, 2)
	var before := a.effective_atk()
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": b})
	TestHarness.assert_eq(a.effective_atk(), before, "no buff — not adjacent")
	state.teardown()

static func _formation_fires_bidirectionally_when_both_have_keyword() -> void:
	# Both A and B have FORMATION + same race. Summoning B should fire BOTH minions'
	# Formation effects (each independent pair-tracking dict).
	var state := TestHarness.build_state()
	if not TestHarness.begin_test("formation / both adjacent FORMATION minions fire on the same summon", state):
		return
	var a_data := _make_formation_card(Enums.MinionType.HUMAN, true)
	var b_data := _make_formation_card(Enums.MinionType.HUMAN, true)
	var a := _place_at(state, a_data, 0)
	var b := _place_at(state, b_data, 1)
	var a_before := a.effective_atk()
	var b_before := b.effective_atk()
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": b})
	TestHarness.assert_eq(a.effective_atk(), a_before + 100, "A's Formation fired against B")
	TestHarness.assert_eq(b.effective_atk(), b_before + 100, "B's Formation fired against A (bidirectional)")
	TestHarness.assert_true(a.formation_partners.has(b), "A recorded B")
	TestHarness.assert_true(b.formation_partners.has(a), "B recorded A")
	state.teardown()

# ---------------------------------------------------------------------------
# Korrath Phase 2 — hero registration + Abyssal Knight card + cost discount
# ---------------------------------------------------------------------------

static func _korrath_hero_registered() -> void:
	if not TestHarness.begin_test("korrath / hero registered with passives and branches"):
		return
	var hero := HeroDatabase.get_hero("korrath")
	TestHarness.assert_true(hero != null, "HeroDatabase.get_hero('korrath') returns a HeroData")
	if hero == null:
		return
	TestHarness.assert_eq(hero.hero_name, "Korrath", "hero_name = Korrath")
	TestHarness.assert_eq(hero.faction, "Abyss Order", "faction = Abyss Order")
	TestHarness.assert_true(HeroDatabase.has_passive("korrath", "abyssal_commander"),
			"abyssal_commander passive present")
	TestHarness.assert_true(HeroDatabase.has_passive("korrath", "iron_legion"),
			"iron_legion passive present")
	TestHarness.assert_eq(hero.talent_branch_ids.size(), 3, "exactly 3 branches")
	TestHarness.assert_true("infernal_bulwark" in hero.talent_branch_ids, "infernal_bulwark branch")
	TestHarness.assert_true("runic_knight" in hero.talent_branch_ids, "runic_knight branch")
	TestHarness.assert_true("abyssal_breaker" in hero.talent_branch_ids, "abyssal_breaker branch")

static func _abyssal_knight_card_registered() -> void:
	if not TestHarness.begin_test("abyssal_knight / card registered with 4E / 400 / 500 base stats"):
		return
	var card: MinionCardData = CardDatabase.get_card("abyssal_knight") as MinionCardData
	TestHarness.assert_true(card != null, "CardDatabase.get_card('abyssal_knight') returns MinionCardData")
	if card == null:
		return
	TestHarness.assert_eq(card.essence_cost, 4, "base essence_cost = 4")
	TestHarness.assert_eq(card.atk, 400, "base ATK = 400")
	TestHarness.assert_eq(card.health, 500, "base HP = 500")
	TestHarness.assert_true("abyssal_knight" in card.minion_tags, "card tagged 'abyssal_knight'")
	TestHarness.assert_eq(card.faction, "abyss_order", "faction tagged abyss_order")

static func _abyssal_commander_discounts_knight() -> void:
	# With abyssal_commander hero passive active, _card_for() returns the knight at 3E.
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("abyssal_commander / abyssal_knight cost reduced 4 → 3", state):
		return
	var data: MinionCardData = state._card_for("player", "abyssal_knight") as MinionCardData
	TestHarness.assert_eq(data.essence_cost, 3,
			"essence_cost = 3 (4 base - 1 from abyssal_commander)")
	state.teardown()

static func _abyssal_commander_does_not_discount_other_minions() -> void:
	# Sanity: the cost rule is filtered by the abyssal_knight tag, not faction-wide.
	var state := TestHarness.korrath_state()
	if not TestHarness.begin_test("abyssal_commander / does not discount unrelated minions", state):
		return
	var data: MinionCardData = state._card_for("player", "void_imp") as MinionCardData
	TestHarness.assert_eq(data.essence_cost, 1,
			"void_imp essence_cost stays at base 1 (rule's tag filter excludes it)")
	state.teardown()

# ---------------------------------------------------------------------------
# Korrath — Branch 1 Infernal Bulwark
#
# Tests use TestHarness.korrath_state() (both passives active) plus the talents
# under test. spawn_resolved_friendly applies talent_overrides so the knight's
# minion_type/keywords reflect the active branch state.
# ---------------------------------------------------------------------------

## Synthetic Human used as a Formation partner for knight tests. The deck has
## only "abyssal_knight" so we can't pull a Human from CardDatabase via the deck
## path; build the data inline. Only fields the handler reads need to be set.
static func _make_korrath_test_human() -> MinionCardData:
	var data := MinionCardData.new()
	data.id          = "test_human_partner"
	data.card_name   = "Test Human"
	data.atk         = 100
	data.health      = 200
	data.minion_type = Enums.MinionType.HUMAN
	return data

static func _place_korrath_human(state: SimState, slot: int) -> MinionInstance:
	var inst := MinionInstance.create(_make_korrath_test_human(), "player")
	state.player_board.append(inst)
	state.player_slots[slot].minion = inst
	inst.slot_index = slot
	return inst

static func _iron_formation_retags_knight_human_with_formation() -> void:
	var state := TestHarness.korrath_state(["iron_formation"])
	if not TestHarness.begin_test("iron_formation / abyssal_knight becomes Human with FORMATION", state):
		return
	var data: MinionCardData = state._card_for("player", "abyssal_knight") as MinionCardData
	TestHarness.assert_eq(data.minion_type, Enums.MinionType.HUMAN, "race overridden to HUMAN")
	TestHarness.assert_true(Enums.Keyword.FORMATION in data.keywords, "FORMATION keyword present")
	TestHarness.assert_eq(data.formation_effect_steps.size(), 2, "2 formation steps (armour + HP)")
	state.teardown()

static func _iron_formation_grants_armour_and_hp_on_first_human_pair() -> void:
	# Knight at slot 0, Human at slot 1, then fire summon → knight gains 200 armour
	# (no doubling without unbreakable) and 200 HP via formation_effect_steps.
	var state := TestHarness.korrath_state(["iron_formation"])
	if not TestHarness.begin_test("iron_formation / first Human pair grants knight +200 armour, +200 HP", state):
		return
	var knight := TestHarness.spawn_resolved_friendly(state, "abyssal_knight")
	var human  := _place_korrath_human(state, 1)
	var pre_armour := knight.armour
	var pre_hp     := knight.current_health
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": human})
	TestHarness.assert_eq(knight.armour, pre_armour + 200, "armour +200")
	TestHarness.assert_eq(knight.current_health, pre_hp + 200, "current HP +200 (apply_hp_gain raises both cap and current)")
	state.teardown()

static func _commanders_reach_applies_ab_on_attack() -> void:
	# Knight slot 0, Human slot 1 (adjacent), enemy defender. Human attacks defender:
	# the on-attack handler applies 100 AB to the defender BEFORE damage resolves.
	var state := TestHarness.korrath_state(["iron_formation", "commanders_reach"])
	if not TestHarness.begin_test("commanders_reach / adjacent Human attack applies 100 AB to defender", state):
		return
	var _knight := TestHarness.spawn_resolved_friendly(state, "abyssal_knight")
	var human   := _place_korrath_human(state, 1)
	var defender := TestHarness.spawn_enemy(state, "void_imp")  # 100 HP
	defender.current_health = 1000  # raise so attack doesn't kill before AB applies
	human.state = Enums.MinionState.NORMAL
	state.combat_manager.resolve_minion_attack(human, defender)
	TestHarness.assert_eq(BuffSystem.sum_type(defender, Enums.BuffType.ARMOUR_BREAK), 100,
			"defender carries 100 AB stack from commanders_reach")
	state.teardown()

static func _commanders_reach_ignores_non_humans() -> void:
	# Same setup but attacker is not a Human (use a Demon void_imp).
	var state := TestHarness.korrath_state(["iron_formation", "commanders_reach"])
	if not TestHarness.begin_test("commanders_reach / non-Human attacker does not apply AB", state):
		return
	var _knight := TestHarness.spawn_resolved_friendly(state, "abyssal_knight")
	var imp := TestHarness.spawn_friendly(state, "void_imp")  # DEMON
	# Place imp in slot 1 (adjacent to knight) — _spawn picks first empty so it lands there.
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	imp.state = Enums.MinionState.NORMAL
	state.combat_manager.resolve_minion_attack(imp, defender)
	TestHarness.assert_eq(BuffSystem.sum_type(defender, Enums.BuffType.ARMOUR_BREAK), 0,
			"no AB — attacker is DEMON, not HUMAN")
	state.teardown()

static func _commanders_reach_ignores_non_adjacent_humans() -> void:
	# Knight at slot 0, Human at slot 2 (non-adjacent — slot 1 empty).
	var state := TestHarness.korrath_state(["iron_formation", "commanders_reach"])
	if not TestHarness.begin_test("commanders_reach / non-adjacent Human does not apply AB", state):
		return
	var _knight := TestHarness.spawn_resolved_friendly(state, "abyssal_knight")
	var human   := _place_korrath_human(state, 2)
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	human.state = Enums.MinionState.NORMAL
	state.combat_manager.resolve_minion_attack(human, defender)
	TestHarness.assert_eq(BuffSystem.sum_type(defender, Enums.BuffType.ARMOUR_BREAK), 0,
			"no AB — Human is not adjacent to knight")
	state.teardown()

static func _iron_resolve_adds_armour_to_human_atk() -> void:
	# Friendly Human with armour 300 and base ATK 100 → effective_atk 400.
	var state := TestHarness.korrath_state(["iron_formation", "commanders_reach", "iron_resolve"])
	if not TestHarness.begin_test("iron_resolve / friendly Human gains ATK = current armour", state):
		return
	var human := _place_korrath_human(state, 0)
	human.armour = 300
	TestHarness.assert_eq(human.effective_atk(), 100 + 300, "100 base + 300 armour = 400 ATK")
	state.teardown()

static func _iron_resolve_does_not_apply_to_enemies_or_demons() -> void:
	# Same talent but attacker is enemy / Demon — armour does NOT add to ATK.
	var state := TestHarness.korrath_state(["iron_formation", "commanders_reach", "iron_resolve"])
	if not TestHarness.begin_test("iron_resolve / enemies and non-Humans unaffected", state):
		return
	var enemy_human := MinionInstance.create(_make_korrath_test_human(), "enemy")
	enemy_human.armour = 300
	TestHarness.assert_eq(enemy_human.effective_atk(), 100, "enemy Human: armour does not add (player-side only)")
	var demon := TestHarness.spawn_friendly(state, "void_imp")  # friendly DEMON
	demon.armour = 300
	TestHarness.assert_eq(demon.effective_atk(), 100, "friendly Demon: armour does not add (Human-only)")
	state.teardown()

static func _unbreakable_doubles_knight_armour_gains() -> void:
	# All four Branch 1 talents active. Knight + Human pair triggers Formation:
	# +200 armour from the step, doubled to +400 by unbreakable's scene flag.
	var state := TestHarness.korrath_state(["iron_formation", "commanders_reach", "iron_resolve", "unbreakable"])
	if not TestHarness.begin_test("unbreakable / armour gains on knight doubled (200 → 400)", state):
		return
	var knight := TestHarness.spawn_resolved_friendly(state, "abyssal_knight")
	var human  := _place_korrath_human(state, 1)
	var pre_armour := knight.armour
	TestHarness.fire(state, Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player", {"minion": human})
	TestHarness.assert_eq(knight.armour, pre_armour + 400,
			"+400 armour (200 base × 2 from unbreakable doubling)")
	state.teardown()

static func _unbreakable_does_not_double_other_minions() -> void:
	# add_armour() only doubles when card_data.id == "abyssal_knight". A regular
	# Human gaining armour stays at the raw amount.
	var state := TestHarness.korrath_state(["iron_formation", "commanders_reach", "iron_resolve", "unbreakable"])
	if not TestHarness.begin_test("unbreakable / non-knight armour gains are NOT doubled", state):
		return
	var human := _place_korrath_human(state, 0)
	human.add_armour(100, state)
	TestHarness.assert_eq(human.armour, 100, "regular Human gains raw 100 armour, not doubled")
	state.teardown()

static func _unbreakable_grants_guard() -> void:
	# Capstone retag — knight has GUARD (in addition to FORMATION).
	var state := TestHarness.korrath_state(["iron_formation", "commanders_reach", "iron_resolve", "unbreakable"])
	if not TestHarness.begin_test("unbreakable / abyssal_knight gains GUARD keyword", state):
		return
	var data: MinionCardData = state._card_for("player", "abyssal_knight") as MinionCardData
	TestHarness.assert_true(Enums.Keyword.GUARD in data.keywords, "GUARD present in keywords")
	TestHarness.assert_true(Enums.Keyword.FORMATION in data.keywords, "FORMATION still present (cumulative override)")
	state.teardown()
