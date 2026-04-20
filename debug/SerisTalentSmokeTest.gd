## SerisTalentSmokeTest.gd
## Direct unit-style probes for each Seris talent. Bypasses the AI profile
## to exercise the mechanic deterministically, then asserts observable
## state changes on the sim. Reports PASS/FAIL per talent.
##
## Usage: Godot --headless --path <proj> res://debug/SerisTalentSmokeTest.tscn
##
## Each probe:
##   1. Builds a minimal SimState via CombatSim.run()'s setup path
##   2. Manually places minions / triggers events via SimState methods
##   3. Checks the observable effect (Flesh count, ATK, HP, stacks, etc.)
##   4. Prints PASS / FAIL with the delta
##
## This is NOT a balance test. It verifies that each talent's code path
## actually mutates state when its trigger fires.
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== Seris Talent Smoke Test ===\n")
	_test_fleshbind()
	_test_flesh_infusion()
	_test_grafted_constitution()
	_test_predatory_surge_swift()
	_test_predatory_surge_siphon()
	_test_deathless_flesh()
	_test_soul_forge_activate()
	_test_soul_forge_counter()
	_test_fiend_offering()
	_test_forge_momentum()
	_test_abyssal_forge_aura_grant()
	_test_corrupt_flesh_inversion()
	_test_corrupt_flesh_activate()
	_test_corrupt_detonation()
	_test_void_amplification()
	_test_void_resonance_flesh_gain()
	_test_void_resonance_double_cast()
	print("\n=== %d passed, %d failed ===" % [_pass_count, _fail_count])
	get_tree().quit(_fail_count)

# ---------------------------------------------------------------------------
# State builder
# ---------------------------------------------------------------------------

## Build a SimState configured for a Seris run with the given talents active.
## Goes through CombatSim.run-style setup so triggers and buses are wired.
func _build_state(talents: Array[String]) -> SimState:
	var state := SimState.new()
	state.player_hero_id = "seris"
	state.talents = talents
	state.hero_passives = ["fleshbind", "grafted_affinity"]
	state.enemy_passives = []
	# Dummy decks — we manipulate board directly
	state.setup(["void_imp"], ["rabid_imp"], 3000, 2000)
	# Wire triggers exactly like a real sim run
	var ts := SimTriggerSetup.new()
	ts.setup(state)
	return state

func _spawn_friendly_demon(state: SimState, id: String = "grafted_fiend") -> MinionInstance:
	var data: MinionCardData = CardDatabase.get_card(id) as MinionCardData
	var inst := MinionInstance.create(data, "player")
	state.player_board.append(inst)
	for slot in state.player_slots:
		if slot.minion == null:
			slot.minion = inst
			inst.slot_index = slot.index
			break
	return inst

func _spawn_enemy(state: SimState, id: String = "rabid_imp") -> MinionInstance:
	var data: MinionCardData = CardDatabase.get_card(id) as MinionCardData
	var inst := MinionInstance.create(data, "enemy")
	state.enemy_board.append(inst)
	for slot in state.enemy_slots:
		if slot.minion == null:
			slot.minion = inst
			inst.slot_index = slot.index
			break
	return inst

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass_count += 1
		print("  PASS  %s %s" % [name, detail])
	else:
		_fail_count += 1
		print("  FAIL  %s %s" % [name, detail])

# ---------------------------------------------------------------------------
# Fleshbind passive
# ---------------------------------------------------------------------------

func _test_fleshbind() -> void:
	var state := _build_state([])
	var demon := _spawn_friendly_demon(state, "grafted_fiend")
	var before: int = state.player_flesh
	state.combat_manager.kill_minion(demon)
	_check("fleshbind: +1 Flesh on Demon death",
		state.player_flesh == before + 1,
		"(%d → %d)" % [before, state.player_flesh])
	state.teardown()

# ---------------------------------------------------------------------------
# Fleshcraft
# ---------------------------------------------------------------------------

func _test_flesh_infusion() -> void:
	var state := _build_state(["flesh_infusion"])
	state.player_flesh = 3
	var fiend := _spawn_friendly_demon(state, "grafted_fiend")
	var before_atk: int = fiend.effective_atk()
	# Fire ON_PLAYER_MINION_PLAYED directly — the handler listens here
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED, "player")
	ctx.minion = fiend
	ctx.card = fiend.card_data
	state.trigger_manager.fire(ctx)
	var after_atk: int = fiend.effective_atk()
	_check("flesh_infusion: +200 ATK on Grafted Fiend play",
		after_atk == before_atk + 200 and state.player_flesh == 2,
		"(ATK %d → %d, Flesh 3 → %d)" % [before_atk, after_atk, state.player_flesh])
	state.teardown()

func _test_grafted_constitution() -> void:
	var state := _build_state(["grafted_constitution"])
	var fiend := _spawn_friendly_demon(state, "grafted_fiend")
	var enemy := _spawn_enemy(state, "rabid_imp")
	var before_atk: int = fiend.effective_atk()
	var before_hp: int = fiend.current_health
	var before_stacks: int = fiend.kill_stacks
	# Simulate: enemy killed, attacker = fiend
	state._last_attacker = fiend
	state.combat_manager.kill_minion(enemy)
	var after_atk: int = fiend.effective_atk()
	var after_hp: int = fiend.current_health
	_check("grafted_constitution: +100/+100 on enemy kill",
		after_atk == before_atk + 100 and after_hp == before_hp + 100 and fiend.kill_stacks == before_stacks + 1,
		"(ATK %d → %d, HP %d → %d, stacks %d → %d)" % [before_atk, after_atk, before_hp, after_hp, before_stacks, fiend.kill_stacks])
	state.teardown()

func _test_predatory_surge_swift() -> void:
	var state := _build_state(["predatory_surge"])
	var fiend_data: MinionCardData = CardDatabase.get_card("grafted_fiend") as MinionCardData
	var fiend := MinionInstance.create(fiend_data, "player")
	state.player_board.append(fiend)
	for slot in state.player_slots:
		if slot.minion == null:
			slot.minion = fiend
			fiend.slot_index = slot.index
			break
	# Fire ON_PLAYER_MINION_SUMMONED — predatory_surge handler upgrades EXHAUSTED → SWIFT
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
	ctx.minion = fiend
	ctx.card = fiend_data
	state.trigger_manager.fire(ctx)
	_check("predatory_surge: Grafted Fiend enters with Swift",
		fiend.state == Enums.MinionState.SWIFT,
		"(state=%d, expected %d)" % [fiend.state, Enums.MinionState.SWIFT])
	state.teardown()

func _test_predatory_surge_siphon() -> void:
	var state := _build_state(["grafted_constitution", "predatory_surge"])
	var fiend := _spawn_friendly_demon(state, "grafted_fiend")
	# Rack up 3 kills
	for i in 3:
		var enemy := _spawn_enemy(state, "rabid_imp")
		state._last_attacker = fiend
		state.combat_manager.kill_minion(enemy)
	_check("predatory_surge: Siphon at 3 kill_stacks",
		fiend.has_siphon() and fiend.kill_stacks == 3,
		"(stacks=%d, has_siphon=%s)" % [fiend.kill_stacks, str(fiend.has_siphon())])
	state.teardown()

func _test_deathless_flesh() -> void:
	var state := _build_state(["deathless_flesh"])
	state.player_flesh = 5
	var fiend := _spawn_friendly_demon(state, "grafted_fiend")
	# Damage to death — hook should save
	state.combat_manager._deal_damage(fiend, fiend.current_health + 100, Enums.DamageType.PHYSICAL)
	_check("deathless_flesh: Fiend saved (HP=50, Flesh -2)",
		fiend.current_health == 50 and state.player_flesh == 3,
		"(HP=%d, Flesh=%d)" % [fiend.current_health, state.player_flesh])
	state.teardown()

# ---------------------------------------------------------------------------
# Demon Forge
# ---------------------------------------------------------------------------

func _test_soul_forge_activate() -> void:
	var state := _build_state(["soul_forge"])
	state.player_flesh = 3
	var board_before: int = state.player_board.size()
	var ok: bool = state._soul_forge_activate()
	_check("soul_forge activated: +Fiend, -3 Flesh",
		ok and state.player_flesh == 0 and state.player_board.size() == board_before + 1 \
			and state.player_board[-1].card_data.id == "grafted_fiend",
		"(flesh=%d, board+%d, top=%s)" % [state.player_flesh, state.player_board.size() - board_before, state.player_board[-1].card_data.id])
	state.teardown()

func _test_soul_forge_counter() -> void:
	var state := _build_state(["soul_forge"])
	# Sacrifice 3 Demons — should trigger Forged Demon summon at threshold
	for i in 3:
		var demon := _spawn_friendly_demon(state, "grafted_fiend")
		SacrificeSystem.sacrifice(state, demon, "test_sac")
		state.combat_manager.kill_minion(demon)
	var has_forged := false
	for m in state.player_board:
		if m.card_data.id == "forged_demon":
			has_forged = true
			break
	_check("soul_forge: Forged Demon at threshold (3 sacs)",
		has_forged and state.forge_counter == 0,
		"(forge_counter=%d, has_forged=%s, board=%d)" % [state.forge_counter, str(has_forged), state.player_board.size()])
	state.teardown()

func _test_fiend_offering() -> void:
	var state := _build_state(["soul_forge", "fiend_offering"])
	state.player_flesh = 3  # enough for Fiend Offering's 2
	var demon := _spawn_friendly_demon(state, "grafted_fiend")
	SacrificeSystem.sacrifice(state, demon, "test_sac")
	state.combat_manager.kill_minion(demon)
	# Expected flesh flow: 3 start → -2 fiend_offering → 1 → +1 Fleshbind (demon died) → 2
	var has_lesser := false
	for m in state.player_board:
		if m.card_data.id == "lesser_demon":
			has_lesser = true
			break
	_check("fiend_offering: Lesser Demon summoned (-2 Flesh, +1 Fleshbind)",
		has_lesser and state.player_flesh == 2,
		"(flesh=%d, has_lesser=%s)" % [state.player_flesh, str(has_lesser)])
	state.teardown()

func _test_forge_momentum() -> void:
	var state := _build_state(["soul_forge", "fiend_offering", "forge_momentum"])
	_check("forge_momentum: threshold = 2",
		state.forge_counter_threshold == 2,
		"(threshold=%d)" % state.forge_counter_threshold)
	state.teardown()

func _test_abyssal_forge_aura_grant() -> void:
	var state := _build_state(["soul_forge", "fiend_offering", "forge_momentum", "abyssal_forge"])
	# Sacrifice 2 Demons → threshold → Forged Demon + aura
	for i in 2:
		var demon := _spawn_friendly_demon(state, "grafted_fiend")
		SacrificeSystem.sacrifice(state, demon, "test_sac")
		state.combat_manager.kill_minion(demon)
	var forged: MinionInstance = null
	for m in state.player_board:
		if m.card_data.id == "forged_demon":
			forged = m
			break
	_check("abyssal_forge: Forged Demon has >=1 aura tag",
		forged != null and forged.aura_tags.size() >= 1,
		"(auras=%s)" % (str(forged.aura_tags) if forged else "no forged"))
	state.teardown()

# ---------------------------------------------------------------------------
# Corruption Engine
# ---------------------------------------------------------------------------

func _test_corrupt_flesh_inversion() -> void:
	var state := _build_state(["corrupt_flesh"])
	var fiend := _spawn_friendly_demon(state, "grafted_fiend")
	var before: int = fiend.effective_atk()
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	var after: int = fiend.effective_atk()
	_check("corrupt_flesh: inversion on friendly Demon (+100 instead of -100)",
		after == before + 100,
		"(ATK %d → %d, delta=%d)" % [before, after, after - before])
	# Reset global
	state.teardown()
	MinionInstance.corruption_inverts_on_friendly_demons = false

func _test_corrupt_flesh_activate() -> void:
	var state := _build_state(["corrupt_flesh"])
	state.player_flesh = 5
	var fiend := _spawn_friendly_demon(state, "grafted_fiend")
	var ok: bool = state._seris_corrupt_activate(fiend)
	var stacks: int = BuffSystem.sum_type(fiend, Enums.BuffType.CORRUPTION)
	_check("corrupt_flesh activate: 2 stacks on Grafted Fiend, -1 Flesh",
		ok and state.player_flesh == 4 and stacks == 200,
		"(flesh=%d, stacks_raw=%d)" % [state.player_flesh, stacks])
	state.teardown()
	MinionInstance.corruption_inverts_on_friendly_demons = false

func _test_corrupt_detonation() -> void:
	var state := _build_state(["corrupt_flesh", "corrupt_detonation"])
	var fiend := _spawn_friendly_demon(state, "grafted_fiend")
	# Pump enemy HP so damage clamping doesn't mask the delta
	var enemy := _spawn_enemy(state, "rabid_imp")
	enemy.current_health = 1000
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	var enemy_hp_before: int = enemy.current_health
	var enemy_hero_before: int = state.enemy_hp
	# Remove corruption — should detonate for 200 damage to a random enemy
	BuffSystem.remove_type(fiend, Enums.BuffType.CORRUPTION)
	var minion_dmg: int = enemy_hp_before - enemy.current_health
	var hero_dmg: int = enemy_hero_before - state.enemy_hp
	_check("corrupt_detonation: 100/stack to random enemy (minion OR hero)",
		minion_dmg == 200 or hero_dmg == 200,
		"(minion dmg=%d, hero dmg=%d)" % [minion_dmg, hero_dmg])
	state.teardown()
	MinionInstance.corruption_inverts_on_friendly_demons = false

func _test_void_amplification() -> void:
	var state := _build_state(["void_amplification"])
	var fiend := _spawn_friendly_demon(state, "grafted_fiend")
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	BuffSystem.apply(fiend, Enums.BuffType.CORRUPTION, 100, "test", false, false)
	# Simulate a spell cast cycle
	var spell_card: SpellCardData = CardDatabase.get_card("void_bolt") as SpellCardData
	state._pre_player_spell_cast(spell_card)
	_check("void_amplification: bonus = 50 * 2 stacks = 100",
		state._player_spell_damage_bonus == 100,
		"(bonus=%d)" % state._player_spell_damage_bonus)
	state._post_player_spell_cast(spell_card, null)
	state.teardown()

func _test_void_resonance_flesh_gain() -> void:
	var state := _build_state(["void_resonance_seris"])
	var before: int = state.player_flesh
	var enemy := _spawn_enemy(state, "rabid_imp")
	state.combat_manager.kill_minion(enemy)
	_check("void_resonance_seris: +1 Flesh on any enemy death",
		state.player_flesh == before + 1,
		"(flesh %d → %d)" % [before, state.player_flesh])
	state.teardown()

func _test_void_resonance_double_cast() -> void:
	# This probes the flag path. Because EffectResolver.run is complex and
	# requires a full effect chain, we just verify that Flesh is consumed and
	# the double-cast flag is cleanly set/cleared (no crash, no infinite loop).
	var state := _build_state(["void_resonance_seris"])
	state.player_flesh = 5
	var spell_card: SpellCardData = CardDatabase.get_card("void_bolt") as SpellCardData
	state._pre_player_spell_cast(spell_card)
	state._post_player_spell_cast(spell_card, null)
	_check("void_resonance_seris: Flesh>=5 triggers post-cast consume (Flesh 5 → 0)",
		state.player_flesh == 0 and not state._double_cast_in_progress,
		"(flesh=%d, dbl=%s)" % [state.player_flesh, str(state._double_cast_in_progress)])
	state.teardown()
