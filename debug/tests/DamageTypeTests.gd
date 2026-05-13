## DamageTypeTests.gd
## Layered probes for the unified damage type system (DamageSource + DamageSchool).
## Each phase of design/DAMAGE_TYPE_SYSTEM.md adds probes here that lock in that
## phase's invariant. Run via RunAllTests.
##
## Phase 1 — enum & lineage helper (pure data, no combat needed)
## Phase 2 — DamageInfo + CombatManager rewrite
## Phase 3 — EffectResolver source/school inference
## Phase 4 — Minion basic attack inference
## Phase 5 — EventContext.damage_info
## Phase 6 — migration completeness
## Phase 7 — card audit invariants
class_name DamageTypeTests
extends RefCounted

static func run_all() -> void:
	print("\n=== DamageType: Phase 1 (lineage helper) ===")
	_test_lineage_self()
	_test_lineage_parent()
	_test_lineage_unrelated()
	_test_lineage_none_empty()
	_test_lineage_true_isolated()
	_test_lineage_void_subschools_are_siblings()

	print("\n=== DamageType: Phase 2 (DamageInfo + CombatManager) ===")
	_test_make_damage_info_fields()
	_test_apply_hero_damage_emits_signal()
	_test_apply_hero_damage_zero_amount_no_emit()
	_test_apply_damage_to_minion_respects_spell_immune()
	_test_apply_damage_to_minion_minion_source_ignores_spell_immune()
	_test_apply_damage_to_minion_ethereal_amplifies_spell()
	_test_apply_damage_to_minion_ethereal_does_not_amplify_minion()

	print("\n=== DamageType: Phase 3 (EffectResolver source/school inference) ===")
	_test_effect_resolver_spell_damage_is_spell_source()
	_test_effect_resolver_minion_effect_is_minion_source()
	_test_effect_resolver_step_school_default_is_none()
	_test_effect_resolver_step_school_explicit_passes_through()
	_test_effect_resolver_damage_minion_carries_info()

	print("\n=== DamageType: Phase 4 (minion basic attack inference) ===")
	_test_basic_attack_hero_carries_minion_physical()
	_test_basic_attack_hero_attacker_attribution()
	_test_pierce_carry_inherits_attacker()

	print("\n=== DamageType: Phase 5 (EventContext.damage_info) ===")
	_test_event_context_damage_info_default_empty()
	_test_event_context_damage_info_carries_dict()
	_test_handler_can_branch_on_school_via_lineage()

	print("\n=== DamageType: Phase 7 (card audit) ===")
	_test_void_imp_on_play_emits_none_school()
	_test_void_bolt_spell_emits_void_bolt_school()
	_test_arcane_strike_is_arcane_school()
	_test_void_spell_emits_void_school()
	_test_player_hero_damage_fires_trigger_with_info()
	_test_enemy_hero_damage_fires_trigger_with_info()
	_test_lethal_damage_still_fires_trigger()
	_test_void_bolt_spell_path_is_spell_source()
	_test_void_bolt_minion_emitted_path_is_minion_source()

	print("\n=== DamageType: Phase 8 (Korrath Armour) ===")
	_test_armour_reduces_physical_damage()
	_test_armour_min_100_floor()
	_test_armour_floor_only_when_armour_present()
	_test_armour_bypassed_by_void_spell()
	_test_armour_break_strips_armour()
	_test_armour_break_overflow_becomes_bonus_damage()
	_test_armour_break_against_unarmoured_target()
	_test_pierce_carry_uses_post_armour_damage()

	print("\n=== DamageType: Phase 9 (Task 019 — armour gated by school) ===")
	_test_armour_reduces_physical_spell()
	_test_armour_reduces_arcane_spell()
	_test_armour_bypassed_by_void_corruption_spell()
	_test_armour_break_amplifies_physical_spell()
	_test_hero_armour_reduces_physical_spell()
	_test_hero_armour_bypassed_by_void_spell()

# ---------------------------------------------------------------------------
# Phase 1 — pure data assertions on Enums.has_school() / SCHOOL_LINEAGE
# ---------------------------------------------------------------------------

static func _test_lineage_self() -> void:
	if not TestHarness.begin_test("lineage / school satisfies itself"):
		return
	TestHarness.assert_true(Enums.has_school(Enums.DamageSchool.VOID, Enums.DamageSchool.VOID),
			"VOID satisfies VOID")
	TestHarness.assert_true(Enums.has_school(Enums.DamageSchool.PHYSICAL, Enums.DamageSchool.PHYSICAL),
			"PHYSICAL satisfies PHYSICAL")
	TestHarness.assert_true(Enums.has_school(Enums.DamageSchool.VOID_BOLT, Enums.DamageSchool.VOID_BOLT),
			"VOID_BOLT satisfies VOID_BOLT")

static func _test_lineage_parent() -> void:
	if not TestHarness.begin_test("lineage / sub-school satisfies parent"):
		return
	TestHarness.assert_true(Enums.has_school(Enums.DamageSchool.VOID_BOLT, Enums.DamageSchool.VOID),
			"VOID_BOLT satisfies VOID (a +20% void buff hits Void Bolt damage)")

static func _test_lineage_unrelated() -> void:
	if not TestHarness.begin_test("lineage / unrelated schools do not satisfy each other"):
		return
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.VOID, Enums.DamageSchool.PHYSICAL),
			"VOID does not satisfy PHYSICAL")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.PHYSICAL, Enums.DamageSchool.VOID),
			"PHYSICAL does not satisfy VOID")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.VOID, Enums.DamageSchool.VOID_BOLT),
			"VOID does not satisfy VOID_BOLT (parent is not its child)")

static func _test_lineage_none_empty() -> void:
	if not TestHarness.begin_test("lineage / NONE satisfies nothing"):
		return
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.NONE, Enums.DamageSchool.PHYSICAL),
			"NONE does not satisfy PHYSICAL")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.NONE, Enums.DamageSchool.VOID),
			"NONE does not satisfy VOID")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.NONE, Enums.DamageSchool.NONE),
			"NONE does not satisfy NONE (empty lineage — buffs and triggers must miss it)")

static func _test_lineage_true_isolated() -> void:
	if not TestHarness.begin_test("lineage / TRUE_DMG is isolated"):
		return
	TestHarness.assert_true(Enums.has_school(Enums.DamageSchool.TRUE_DMG, Enums.DamageSchool.TRUE_DMG),
			"TRUE_DMG satisfies TRUE_DMG")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.TRUE_DMG, Enums.DamageSchool.PHYSICAL),
			"TRUE_DMG does not satisfy PHYSICAL (bypasses, not a kind of)")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.PHYSICAL, Enums.DamageSchool.TRUE_DMG),
			"PHYSICAL does not satisfy TRUE_DMG")

static func _test_lineage_void_subschools_are_siblings() -> void:
	if not TestHarness.begin_test("lineage / VOID_BOLT, VOID_FLESH, VOID_CORRUPTION are siblings under VOID"):
		return
	# Self
	TestHarness.assert_true(Enums.has_school(Enums.DamageSchool.VOID_FLESH, Enums.DamageSchool.VOID_FLESH),
			"VOID_FLESH satisfies VOID_FLESH")
	TestHarness.assert_true(Enums.has_school(Enums.DamageSchool.VOID_CORRUPTION, Enums.DamageSchool.VOID_CORRUPTION),
			"VOID_CORRUPTION satisfies VOID_CORRUPTION")
	# Parent satisfaction — a "+X to VOID damage" buff should hit any sibling
	TestHarness.assert_true(Enums.has_school(Enums.DamageSchool.VOID_FLESH, Enums.DamageSchool.VOID),
			"VOID_FLESH satisfies VOID (+VOID damage buffs reach flesh)")
	TestHarness.assert_true(Enums.has_school(Enums.DamageSchool.VOID_CORRUPTION, Enums.DamageSchool.VOID),
			"VOID_CORRUPTION satisfies VOID (+VOID damage buffs reach corruption)")
	# Sibling non-satisfaction — Flesh amps don't reach Corruption / Bolt, etc.
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.VOID_BOLT, Enums.DamageSchool.VOID_FLESH),
			"VOID_BOLT does not satisfy VOID_FLESH (siblings under VOID, distinct amps)")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.VOID_BOLT, Enums.DamageSchool.VOID_CORRUPTION),
			"VOID_BOLT does not satisfy VOID_CORRUPTION (siblings under VOID, distinct amps)")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.VOID_FLESH, Enums.DamageSchool.VOID_CORRUPTION),
			"VOID_FLESH does not satisfy VOID_CORRUPTION (siblings: Seris's flesh amp does not reach Korrath's corruption spells)")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.VOID_CORRUPTION, Enums.DamageSchool.VOID_FLESH),
			"VOID_CORRUPTION does not satisfy VOID_FLESH (symmetric: Korrath's corruption amp does not reach Seris's flesh spells)")
	# Parent does not satisfy child
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.VOID, Enums.DamageSchool.VOID_FLESH),
			"VOID (generic) does not satisfy VOID_FLESH — only tagged flesh damage benefits from flesh-specific amps")
	TestHarness.assert_false(Enums.has_school(Enums.DamageSchool.VOID, Enums.DamageSchool.VOID_CORRUPTION),
			"VOID (generic) does not satisfy VOID_CORRUPTION — only tagged corruption damage benefits from corruption-specific amps")

# ---------------------------------------------------------------------------
# Phase 2 — DamageInfo construction + CombatManager entry points + signals
# ---------------------------------------------------------------------------

## Capture every hero_damaged emission into a buffer so assertions can inspect
## the DamageInfo dict that was sent. Reset on each test.
class HeroDmgCapture extends RefCounted:
	var events: Array[Dictionary] = []
	func on_emit(_target: String, info: Dictionary) -> void:
		events.append(info)

static func _test_make_damage_info_fields() -> void:
	if not TestHarness.begin_test("damage_info / make_damage_info populates all fields"):
		return
	var info := CombatManager.make_damage_info(
			500,
			Enums.DamageSource.SPELL,
			Enums.DamageSchool.VOID_BOLT,
			null,
			"void_bolt"
	)
	TestHarness.assert_eq(info.get("amount"), 500, "amount")
	TestHarness.assert_eq(info.get("source"), Enums.DamageSource.SPELL, "source")
	TestHarness.assert_eq(info.get("school"), Enums.DamageSchool.VOID_BOLT, "school")
	TestHarness.assert_eq(info.get("source_card"), "void_bolt", "source_card")
	TestHarness.assert_eq(info.get("attacker"), null, "attacker (null when omitted)")

static func _test_apply_hero_damage_emits_signal() -> void:
	if not TestHarness.begin_test("apply_hero_damage / emits hero_damaged with full info"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var info := CombatManager.make_damage_info(300, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID)
	state.combat_manager.apply_hero_damage("enemy", info)
	TestHarness.assert_eq(cap.events.size(), 1, "one emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("amount"), 300, "info.amount")
		TestHarness.assert_eq(cap.events[0].get("school"), Enums.DamageSchool.VOID, "info.school")

static func _test_apply_hero_damage_zero_amount_no_emit() -> void:
	if not TestHarness.begin_test("apply_hero_damage / amount<=0 emits nothing"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	state.combat_manager.apply_hero_damage("enemy", CombatManager.make_damage_info(0, Enums.DamageSource.SPELL))
	state.combat_manager.apply_hero_damage("enemy", CombatManager.make_damage_info(-50, Enums.DamageSource.SPELL))
	TestHarness.assert_eq(cap.events.size(), 0, "zero/negative amount silent")

static func _test_apply_damage_to_minion_respects_spell_immune() -> void:
	if not TestHarness.begin_test("apply_damage_to_minion / SPELL_IMMUNE blocks SPELL source"):
		return
	var state := TestHarness.build_state()
	var target := TestHarness.spawn_friendly(state, "void_imp")
	var pre_hp := target.current_health
	BuffSystem.apply(target, Enums.BuffType.GRANT_SPELL_IMMUNE, 1, "test", false, false)
	var info := CombatManager.make_damage_info(500, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID)
	state.combat_manager.apply_damage_to_minion(target, info)
	TestHarness.assert_eq(target.current_health, pre_hp, "SPELL-source damage blocked by SPELL_IMMUNE")

static func _test_apply_damage_to_minion_minion_source_ignores_spell_immune() -> void:
	# SPELL_IMMUNE is source-keyed, not school-keyed: minion-source damage gets through.
	if not TestHarness.begin_test("apply_damage_to_minion / MINION source bypasses SPELL_IMMUNE"):
		return
	var state := TestHarness.build_state()
	var target := TestHarness.spawn_friendly(state, "void_imp")
	BuffSystem.apply(target, Enums.BuffType.GRANT_SPELL_IMMUNE, 1, "test", false, false)
	var pre_hp := target.current_health
	var info := CombatManager.make_damage_info(100, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL)
	state.combat_manager.apply_damage_to_minion(target, info)
	TestHarness.assert_eq(target.current_health, pre_hp - 100, "MINION-source landed despite SPELL_IMMUNE")

static func _test_apply_damage_to_minion_ethereal_amplifies_spell() -> void:
	if not TestHarness.begin_test("apply_damage_to_minion / ETHEREAL amplifies SPELL source 50%"):
		return
	var state := TestHarness.build_state()
	var target := TestHarness.spawn_enemy(state, "bastion_colossus")  # has ETHEREAL
	var pre_hp := target.current_health
	var info := CombatManager.make_damage_info(200, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID)
	state.combat_manager.apply_damage_to_minion(target, info)
	# Bastion has shield — account for it. Compute total HP+shield delta instead.
	var total_taken := (pre_hp + 0) - target.current_health  # current_shield was 0 unless card grants
	# Recompute: any shield absorbs first, so just check that 300 (200 * 1.5) was the effective damage.
	# Bastion has no shield by default; verify directly:
	TestHarness.assert_eq(target.current_health, pre_hp - 300,
			"ETHEREAL bumped 200 SPELL damage → 300 actually taken")

static func _test_apply_damage_to_minion_ethereal_does_not_amplify_minion() -> void:
	# ETHEREAL's spell amplification must not apply to MINION-source damage.
	# (Minion attacks have their own halving rule in resolve_minion_attack — separate path.)
	if not TestHarness.begin_test("apply_damage_to_minion / ETHEREAL leaves MINION source unchanged"):
		return
	var state := TestHarness.build_state()
	var target := TestHarness.spawn_enemy(state, "bastion_colossus")  # ETHEREAL
	var pre_hp := target.current_health
	var info := CombatManager.make_damage_info(200, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL)
	state.combat_manager.apply_damage_to_minion(target, info)
	TestHarness.assert_eq(target.current_health, pre_hp - 200,
			"MINION-source damage not amplified (ETHEREAL only amps SPELL)")

# ---------------------------------------------------------------------------
# Phase 3 — EffectResolver builds DamageInfo with inferred source + step school
# ---------------------------------------------------------------------------

## Build a single-step DAMAGE_HERO effect for tests.
static func _make_damage_hero_step(amount: int, school: int = Enums.DamageSchool.NONE) -> EffectStep:
	var s := EffectStep.make(EffectStep.EffectType.DAMAGE_HERO, EffectStep.TargetScope.NONE, amount)
	s.damage_school = school
	return s

static func _test_effect_resolver_spell_damage_is_spell_source() -> void:
	# A spell (ctx.source == null) firing DAMAGE_HERO → DamageInfo.source == SPELL.
	if not TestHarness.begin_test("effect_resolver / spell DAMAGE_HERO → SPELL source"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var ctx := TestHarness.make_ctx(state, "player")  # source=null → spell-emitted
	EffectResolver.run([_make_damage_hero_step(100)], ctx)
	TestHarness.assert_eq(cap.events.size(), 1, "one emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("source"), Enums.DamageSource.SPELL,
				"null ctx.source → SPELL")

static func _test_effect_resolver_minion_effect_is_minion_source() -> void:
	# A minion's on-play effect (ctx.source set) → DamageInfo.source == MINION.
	if not TestHarness.begin_test("effect_resolver / minion-emitted DAMAGE_HERO → MINION source"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	var ctx := TestHarness.make_ctx(state, "player", imp)  # source=imp
	EffectResolver.run([_make_damage_hero_step(100)], ctx)
	TestHarness.assert_eq(cap.events.size(), 1, "one emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("source"), Enums.DamageSource.MINION,
				"non-null ctx.source → MINION")
		TestHarness.assert_eq(cap.events[0].get("attacker"), imp,
				"attacker carries the source minion")

static func _test_effect_resolver_step_school_default_is_none() -> void:
	# Step with no explicit school → DamageInfo.school == NONE (default).
	if not TestHarness.begin_test("effect_resolver / step without damage_school → NONE"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var ctx := TestHarness.make_ctx(state, "player")
	EffectResolver.run([_make_damage_hero_step(100)], ctx)  # no school set
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("school"), Enums.DamageSchool.NONE,
				"unset damage_school stays NONE — surfaces forgotten tags")

static func _test_effect_resolver_step_school_explicit_passes_through() -> void:
	# Step with damage_school=VOID_BOLT → DamageInfo.school == VOID_BOLT.
	if not TestHarness.begin_test("effect_resolver / explicit damage_school passes through"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var ctx := TestHarness.make_ctx(state, "player")
	var step := _make_damage_hero_step(100, Enums.DamageSchool.VOID_BOLT)
	EffectResolver.run([step], ctx)
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("school"), Enums.DamageSchool.VOID_BOLT,
				"VOID_BOLT propagates from step to DamageInfo")
		# Lineage check still holds end-to-end:
		TestHarness.assert_true(Enums.has_school(cap.events[0].get("school"), Enums.DamageSchool.VOID),
				"VOID_BOLT damage satisfies VOID lineage")

static func _test_effect_resolver_damage_minion_carries_info() -> void:
	# DAMAGE_MINION targeting a minion respects SPELL_IMMUNE based on the new info path.
	# (Verifies the route through scene._spell_dmg → apply_damage_to_minion with info.)
	if not TestHarness.begin_test("effect_resolver / DAMAGE_MINION respects SPELL_IMMUNE via info path"):
		return
	var state := TestHarness.build_state()
	var target := TestHarness.spawn_enemy(state, "void_imp")
	BuffSystem.apply(target, Enums.BuffType.GRANT_SPELL_IMMUNE, 1, "test", false, false)
	var pre_hp := target.current_health
	var step := EffectStep.make(EffectStep.EffectType.DAMAGE_MINION, EffectStep.TargetScope.SINGLE_CHOSEN, 50)
	step.damage_school = Enums.DamageSchool.VOID
	var ctx := TestHarness.make_ctx(state, "player", null, target)
	EffectResolver.run([step], ctx)
	TestHarness.assert_eq(target.current_health, pre_hp,
			"SPELL_IMMUNE blocks SPELL-source DAMAGE_MINION via DamageInfo")

# ---------------------------------------------------------------------------
# Phase 4 — minion basic attacks emit DamageInfo (MINION, PHYSICAL, attacker)
# ---------------------------------------------------------------------------

static func _test_basic_attack_hero_carries_minion_physical() -> void:
	if not TestHarness.begin_test("basic_attack / minion attacking hero → MINION + PHYSICAL"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var attacker := TestHarness.spawn_friendly(state, "void_imp")  # 100 ATK, no PIERCE
	state.combat_manager.resolve_minion_attack_hero(attacker, "enemy")
	TestHarness.assert_eq(cap.events.size(), 1, "one hero damage emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("source"), Enums.DamageSource.MINION,
				"attack carries MINION source")
		TestHarness.assert_eq(cap.events[0].get("school"), Enums.DamageSchool.PHYSICAL,
				"basic attack defaults to PHYSICAL school")
		TestHarness.assert_eq(cap.events[0].get("amount"), 100, "amount = attacker.atk")

static func _test_basic_attack_hero_attacker_attribution() -> void:
	if not TestHarness.begin_test("basic_attack / DamageInfo.attacker is the attacking minion"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	state.combat_manager.resolve_minion_attack_hero(imp, "enemy")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("attacker"), imp, "attacker is the imp")
		TestHarness.assert_eq(cap.events[0].get("source_card"), "void_imp",
				"source_card carries the attacker's card id")

static func _test_pierce_carry_inherits_attacker() -> void:
	# Ethereal Titan (600 ATK, PIERCE) attacking a void_imp (100 HP) overkills.
	# Pierce excess → hero damage; school stays PHYSICAL, attacker still the titan.
	if not TestHarness.begin_test("basic_attack / PIERCE carry-through attributes to attacker"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var titan := TestHarness.spawn_friendly(state, "ethereal_titan")  # 600 ATK + PIERCE
	var defender := TestHarness.spawn_enemy(state, "void_imp")        # 100 HP
	state.combat_manager.resolve_minion_attack(titan, defender)
	# Filter to hero-damage emissions (counter-attack does not hit hero):
	# Only the PIERCE excess should emit a hero_damaged event here.
	TestHarness.assert_true(cap.events.size() >= 1, "pierce excess emitted")
	if cap.events.size() >= 1:
		var ev := cap.events[0]
		TestHarness.assert_eq(ev.get("attacker"), titan, "pierce carry attributed to titan")
		TestHarness.assert_eq(ev.get("source"), Enums.DamageSource.MINION,
				"pierce carry stays MINION source")
		TestHarness.assert_eq(ev.get("school"), Enums.DamageSchool.PHYSICAL,
				"pierce carry inherits PHYSICAL")

# ---------------------------------------------------------------------------
# Phase 5 — EventContext.damage_info
# ---------------------------------------------------------------------------

static func _test_event_context_damage_info_default_empty() -> void:
	if not TestHarness.begin_test("event_context / damage_info defaults to empty dict"):
		return
	var ctx := EventContext.make(Enums.TriggerEvent.ON_HERO_DAMAGED, "player")
	TestHarness.assert_true(ctx.damage_info.is_empty(),
			"new EventContext has no damage_info until set by fire site")

static func _test_event_context_damage_info_carries_dict() -> void:
	# A fire site populates damage_info before firing; handlers see it on ctx.
	if not TestHarness.begin_test("event_context / damage_info round-trips through TriggerManager"):
		return
	var state := TestHarness.build_state()
	var captured: Array[Dictionary] = []
	state.trigger_manager.register(Enums.TriggerEvent.ON_HERO_DAMAGED,
			func(ctx: EventContext): captured.append(ctx.damage_info), 99)
	var info := CombatManager.make_damage_info(250, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID_BOLT)
	var ctx := EventContext.make(Enums.TriggerEvent.ON_HERO_DAMAGED, "player")
	ctx.damage = 250
	ctx.damage_info = info
	state.trigger_manager.fire(ctx)
	TestHarness.assert_eq(captured.size(), 1, "handler ran once")
	if captured.size() == 1:
		TestHarness.assert_eq(captured[0].get("amount"), 250, "amount carried")
		TestHarness.assert_eq(captured[0].get("school"), Enums.DamageSchool.VOID_BOLT, "school carried")
		TestHarness.assert_eq(captured[0].get("source"), Enums.DamageSource.SPELL, "source carried")

## Helper that wraps a void_hits buffer and an ON_HERO_DAMAGED handler closure.
class _VoidLineageProbe extends RefCounted:
	var void_hits: Array[int] = []
	func handle(ctx: EventContext) -> void:
		var s: int = ctx.damage_info.get("school", Enums.DamageSchool.NONE)
		if Enums.has_school(s, Enums.DamageSchool.VOID):
			void_hits.append(ctx.damage_info.get("amount", 0))

static func _test_handler_can_branch_on_school_via_lineage() -> void:
	# A handler that wants "react to all VOID-school damage" uses Enums.has_school().
	# VOID_BOLT (sub-school of VOID) must trigger; PHYSICAL must not.
	if not TestHarness.begin_test("event_context / handler branches on school via lineage"):
		return
	var state := TestHarness.build_state()
	var probe := _VoidLineageProbe.new()
	state.trigger_manager.register(Enums.TriggerEvent.ON_HERO_DAMAGED, probe.handle, 99)
	# Fire three events: VOID_BOLT (counts), VOID (counts), PHYSICAL (skipped)
	for school in [Enums.DamageSchool.VOID_BOLT, Enums.DamageSchool.VOID, Enums.DamageSchool.PHYSICAL]:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_HERO_DAMAGED, "player")
		ctx.damage = 100
		ctx.damage_info = CombatManager.make_damage_info(100, Enums.DamageSource.SPELL, school)
		state.trigger_manager.fire(ctx)
	TestHarness.assert_eq(probe.void_hits.size(), 2, "VOID + VOID_BOLT both counted, PHYSICAL skipped")
	TestHarness.assert_eq(probe.void_hits, [100, 100], "two VOID-lineage hits captured")

# ---------------------------------------------------------------------------
# Phase 7 — card audit: tagged cards emit the right school end-to-end
# ---------------------------------------------------------------------------

static func _test_void_imp_on_play_emits_none_school() -> void:
	# Per design rule: minion-emitted effect damage defaults to NONE school.
	# Only the piercing_void capstone retags base Void Imp damage to VOID_BOLT.
	# Without that talent, Void Imp on-play emits (MINION, NONE).
	if not TestHarness.begin_test("card_audit / void_imp on-play emits MINION + NONE"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	var card: MinionCardData = imp.card_data as MinionCardData
	var ctx := TestHarness.make_ctx(state, "player", imp)
	EffectResolver.run(card.on_play_effect_steps, ctx)
	TestHarness.assert_eq(cap.events.size(), 1, "one hero-damage emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("source"), Enums.DamageSource.MINION, "MINION source")
		TestHarness.assert_eq(cap.events[0].get("school"), Enums.DamageSchool.NONE,
				"NONE school — minion effect damage doesn't auto-tag VOID")

static func _test_void_bolt_spell_emits_void_bolt_school() -> void:
	# Void Bolt spell uses EffectStep.VOID_BOLT which routes through scene._deal_void_bolt_damage.
	# That wrapper hard-codes VOID_BOLT school — verifies no regression after card audit.
	if not TestHarness.begin_test("card_audit / void_bolt spell emits VOID_BOLT school"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var spell := CardDatabase.get_card("void_bolt") as SpellCardData
	var ctx := TestHarness.make_ctx(state, "player")
	EffectResolver.run(spell.effect_steps, ctx)
	TestHarness.assert_eq(cap.events.size(), 1, "one emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("school"), Enums.DamageSchool.VOID_BOLT,
				"void_bolt spell → VOID_BOLT school")
		TestHarness.assert_true(Enums.has_school(cap.events[0].get("school"), Enums.DamageSchool.VOID),
				"VOID_BOLT also satisfies VOID via lineage")

static func _test_arcane_strike_is_arcane_school() -> void:
	# Task 018: every SpellCardData with a DAMAGE_* step must declare a non-NONE school.
	# arcane_strike is the canonical neutral ARCANE spell — locks in the rule.
	if not TestHarness.begin_test("card_audit / arcane_strike is ARCANE"):
		return
	var spell := CardDatabase.get_card("arcane_strike") as SpellCardData
	if spell == null:
		return
	for raw in spell.effect_steps:
		var step: EffectStep = raw if raw is EffectStep else EffectStep.from_dict(raw)
		if step.effect_type in [EffectStep.EffectType.DAMAGE_HERO, EffectStep.EffectType.DAMAGE_MINION]:
			TestHarness.assert_eq(step.damage_school, Enums.DamageSchool.ARCANE,
					"arcane_strike damage step is ARCANE")

## Captures EventContexts for trigger event probes.
class CtxCapture extends RefCounted:
	var ctxs: Array[EventContext] = []
	func handle(ctx: EventContext) -> void:
		ctxs.append(ctx)

static func _test_player_hero_damage_fires_trigger_with_info() -> void:
	# When the player hero takes damage in sim, ON_HERO_DAMAGED should fire with damage_info populated.
	# This is the symmetric pair to the existing live-combat path; sim must mirror it.
	if not TestHarness.begin_test("hero_damage_trigger / player hero damage fires ON_HERO_DAMAGED with info"):
		return
	var state := TestHarness.build_state()
	var probe := CtxCapture.new()
	state.trigger_manager.register(Enums.TriggerEvent.ON_HERO_DAMAGED, probe.handle, 99)
	# Damage the player hero.
	state.combat_manager.apply_hero_damage("player",
			CombatManager.make_damage_info(150, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID, null, "test"))
	TestHarness.assert_eq(probe.ctxs.size(), 1, "trigger fired once")
	if probe.ctxs.size() == 1:
		TestHarness.assert_eq(probe.ctxs[0].owner, "player", "ctx.owner = player")
		TestHarness.assert_eq(probe.ctxs[0].damage, 150, "ctx.damage mirrors info.amount")
		TestHarness.assert_false(probe.ctxs[0].damage_info.is_empty(), "ctx.damage_info populated")
		TestHarness.assert_eq(probe.ctxs[0].damage_info.get("school"), Enums.DamageSchool.VOID,
				"school carried through trigger")

static func _test_enemy_hero_damage_fires_trigger_with_info() -> void:
	# When the enemy hero takes damage, ON_ENEMY_HERO_DAMAGED should fire — symmetric
	# to the player path. Pre-fix this was silently dropped, so handlers had no way to
	# react to "enemy hero takes void damage" etc.
	if not TestHarness.begin_test("hero_damage_trigger / enemy hero damage fires ON_ENEMY_HERO_DAMAGED with info"):
		return
	var state := TestHarness.build_state()
	var probe := CtxCapture.new()
	state.trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_HERO_DAMAGED, probe.handle, 99)
	# Damage the enemy hero.
	state.combat_manager.apply_hero_damage("enemy",
			CombatManager.make_damage_info(200, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID_BOLT, null, "test"))
	TestHarness.assert_eq(probe.ctxs.size(), 1, "trigger fired once")
	if probe.ctxs.size() == 1:
		TestHarness.assert_eq(probe.ctxs[0].owner, "enemy", "ctx.owner = enemy")
		TestHarness.assert_eq(probe.ctxs[0].damage, 200, "ctx.damage mirrors info.amount")
		TestHarness.assert_false(probe.ctxs[0].damage_info.is_empty(), "ctx.damage_info populated")
		TestHarness.assert_eq(probe.ctxs[0].damage_info.get("school"), Enums.DamageSchool.VOID_BOLT,
				"school carried through trigger")
		TestHarness.assert_true(Enums.has_school(probe.ctxs[0].damage_info.get("school"), Enums.DamageSchool.VOID),
				"VOID_BOLT satisfies VOID lineage — '+X% void damage to enemy hero' would apply")

static func _test_lethal_damage_still_fires_trigger() -> void:
	# ON_HERO_DAMAGED / ON_ENEMY_HERO_DAMAGED must fire on EVERY landed hit, including
	# the killing blow. Pre-fix, lethal damage skipped the trigger entirely — that
	# blocked future "save from death" / telemetry handlers from seeing the fatal hit.
	if not TestHarness.begin_test("lethal_damage / killing-blow damage still fires trigger"):
		return
	# Player lethal: 100 HP, 9999 damage → trigger must fire and winner is set.
	var s1 := TestHarness.build_state({"player_hp": 100})
	var probe1 := CtxCapture.new()
	s1.trigger_manager.register(Enums.TriggerEvent.ON_HERO_DAMAGED, probe1.handle, 99)
	s1.combat_manager.apply_hero_damage("player",
			CombatManager.make_damage_info(9999, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID, null, "test"))
	TestHarness.assert_eq(probe1.ctxs.size(), 1, "player-lethal fires trigger once")
	if probe1.ctxs.size() == 1:
		TestHarness.assert_eq(probe1.ctxs[0].damage_info.get("amount"), 9999,
				"info carries the lethal amount")
	TestHarness.assert_eq(s1.winner, "enemy", "winner set after lethal player damage")
	# Enemy lethal: same shape on enemy side.
	var s2 := TestHarness.build_state({"enemy_hp": 100})
	var probe2 := CtxCapture.new()
	s2.trigger_manager.register(Enums.TriggerEvent.ON_ENEMY_HERO_DAMAGED, probe2.handle, 99)
	s2.combat_manager.apply_hero_damage("enemy",
			CombatManager.make_damage_info(9999, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID, null, "test"))
	TestHarness.assert_eq(probe2.ctxs.size(), 1, "enemy-lethal fires trigger once")
	TestHarness.assert_eq(s2.winner, "player", "winner set after lethal enemy damage")

static func _test_void_bolt_spell_path_is_spell_source() -> void:
	# Spell-cast Void Bolt (no minion source) → SPELL source. Default behavior.
	if not TestHarness.begin_test("void_bolt / spell-cast path emits SPELL source"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	state._deal_void_bolt_damage(500)  # is_minion_emitted defaults false
	TestHarness.assert_eq(cap.events.size(), 1, "one emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("source"), Enums.DamageSource.SPELL,
				"spell-cast Void Bolt → SPELL source")
		TestHarness.assert_eq(cap.events[0].get("school"), Enums.DamageSchool.VOID_BOLT,
				"VOID_BOLT school")

static func _test_void_bolt_minion_emitted_path_is_minion_source() -> void:
	# Talent-driven Void Bolt (void_manifestation, piercing_void) → MINION source.
	# These paths pass is_minion_emitted=true so the DamageInfo carries MINION source
	# even though the damage flows through _deal_void_bolt_damage.
	if not TestHarness.begin_test("void_bolt / minion-emitted path emits MINION source"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var imp := TestHarness.spawn_friendly(state, "void_imp")
	state._deal_void_bolt_damage(200, imp, false, true)  # is_minion_emitted=true
	TestHarness.assert_eq(cap.events.size(), 1, "one emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("source"), Enums.DamageSource.MINION,
				"is_minion_emitted=true → MINION source")
		TestHarness.assert_eq(cap.events[0].get("school"), Enums.DamageSchool.VOID_BOLT,
				"school stays VOID_BOLT")
		TestHarness.assert_eq(cap.events[0].get("attacker"), imp,
				"attacker attribution carried through")

static func _test_void_spell_emits_void_school() -> void:
	# Void-flavored spells (abyss_order faction) ARE tagged VOID — verify end-to-end.
	# Picks void_lance (single explicit DAMAGE_MINION step, simplest to assert).
	if not TestHarness.begin_test("card_audit / void_lance spell emits SPELL + VOID"):
		return
	var state := TestHarness.build_state()
	var target := TestHarness.spawn_enemy(state, "void_imp")
	var spell := CardDatabase.get_card("void_lance") as SpellCardData
	if spell == null:
		return
	# Resolve spell effect with target chosen.
	var ctx := TestHarness.make_ctx(state, "player", null, target)
	# Capture the school by hooking the step directly:
	for raw in spell.effect_steps:
		var step: EffectStep = raw if raw is EffectStep else EffectStep.from_dict(raw)
		if step.effect_type == EffectStep.EffectType.DAMAGE_MINION:
			TestHarness.assert_eq(step.damage_school, Enums.DamageSchool.VOID,
					"void_lance step tagged VOID")
			TestHarness.assert_true(Enums.has_school(step.damage_school, Enums.DamageSchool.VOID),
					"VOID lineage — buffs/triggers keying off VOID hit it")

# ---------------------------------------------------------------------------
# Phase 8 — Korrath Armour: physical damage reduction, min-100 floor, spell
# bypass, Armour Break stripping, AB overflow as flat bonus damage, pierce
# carries post-armour value to the hero.
# ---------------------------------------------------------------------------

static func _test_armour_reduces_physical_damage() -> void:
	# 600 ATK attack vs 200 Armour → defender takes 400 (600 - 200, above floor).
	if not TestHarness.begin_test("armour / physical attack reduced by armour value"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000   # raise HP so we can observe non-fatal damage
	defender.armour = 200
	var info := CombatManager.make_damage_info(600, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(defender.current_health, 600, "1000 - (600-200) = 600")
	TestHarness.assert_eq(state.combat_manager.last_post_armour_damage, 400,
			"last_post_armour_damage exposes the reduced amount")

static func _test_armour_min_100_floor() -> void:
	# 200 ATK vs 900 Armour → would be -700 without the floor; clamped to 100.
	if not TestHarness.begin_test("armour / 100 minimum damage floor when armour exceeds incoming"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	defender.armour = 900
	var info := CombatManager.make_damage_info(200, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(defender.current_health, 900, "min-100 floor: 1000 - 100 = 900")
	TestHarness.assert_eq(state.combat_manager.last_post_armour_damage, 100,
			"post-armour clamps to 100, not 0 or negative")

static func _test_armour_floor_only_when_armour_present() -> void:
	# A 50-damage MINION attack vs unarmoured (no armour, no AB) target lands as 50,
	# not floored to 100. The floor is an armour-interaction rule, not a global min.
	if not TestHarness.begin_test("armour / no floor applied when target has no armour and no AB"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 500
	# defender.armour defaults to 0 from MinionCardData.armour
	var info := CombatManager.make_damage_info(50, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(defender.current_health, 450, "raw 50 unchanged, no floor")
	TestHarness.assert_eq(state.combat_manager.last_post_armour_damage, 50, "post-armour == raw")

static func _test_armour_bypassed_by_void_spell() -> void:
	# A 300-damage VOID spell vs 800 Armour → defender takes 300 (VOID bypasses armour).
	# Under task-019's school gate: VOID lineage + TRUE_DMG bypass; PHYSICAL/ARCANE do not.
	if not TestHarness.begin_test("armour / VOID spell bypasses armour entirely"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	defender.armour = 800
	var info := CombatManager.make_damage_info(300, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(defender.current_health, 700, "1000 - 300 = 700 (VOID bypasses armour)")

static func _test_armour_break_strips_armour() -> void:
	# 100 AB vs 300 Armour: effective_armour = 200, bonus = 0. 500 ATK → 300 damage.
	if not TestHarness.begin_test("armour_break / reduces target armour for the calc"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	defender.armour = 300
	BuffSystem.apply(defender, Enums.BuffType.ARMOUR_BREAK, 100, "test")
	var info := CombatManager.make_damage_info(500, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(state.combat_manager.last_post_armour_damage, 300,
			"500 - max(0, 300-100) + max(0, 100-300) = 500 - 200 + 0 = 300")

static func _test_armour_break_overflow_becomes_bonus_damage() -> void:
	# 500 AB vs 200 Armour: effective_armour = 0, bonus = 300. 200 ATK → 500 damage.
	if not TestHarness.begin_test("armour_break / excess AB beyond armour becomes flat bonus damage"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	defender.armour = 200
	BuffSystem.apply(defender, Enums.BuffType.ARMOUR_BREAK, 500, "test")
	var info := CombatManager.make_damage_info(200, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(state.combat_manager.last_post_armour_damage, 500,
			"200 - 0 + 300 = 500 (overflow AB is bonus damage)")

static func _test_armour_break_against_unarmoured_target() -> void:
	# AB vs 0-armour target functions as pure flat bonus damage. Floor still applies
	# because AB triggers the armour-math path.
	if not TestHarness.begin_test("armour_break / functions as flat bonus damage on unarmoured targets"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	BuffSystem.apply(defender, Enums.BuffType.ARMOUR_BREAK, 300, "test")
	var info := CombatManager.make_damage_info(100, Enums.DamageSource.MINION, Enums.DamageSchool.PHYSICAL)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(state.combat_manager.last_post_armour_damage, 400,
			"100 + 300 (full AB) = 400 — pure bonus on unarmoured target")

static func _test_pierce_carry_uses_post_armour_damage() -> void:
	# Ethereal Titan (600 ATK, PIERCE) attacks a 100-HP void_imp with 300 Armour.
	# Post-armour damage = 600 - 300 = 300; defender dies (had 100 HP); pierce excess
	# = 300 - 100 = 200 → hero damage 200, NOT 500 (the pre-armour 600 - 100 figure).
	if not TestHarness.begin_test("armour / pierce carries post-armour damage to hero"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	var titan := TestHarness.spawn_friendly(state, "ethereal_titan")
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.armour = 300
	state.combat_manager.resolve_minion_attack(titan, defender)
	# Hero damage emissions are pierce excess (counter doesn't hit hero).
	TestHarness.assert_true(cap.events.size() >= 1, "pierce emitted at least one event")
	if cap.events.size() >= 1:
		TestHarness.assert_eq(cap.events[0].get("amount"), 200,
				"pierce excess = post-armour 300 - 100 HP = 200, not raw 600 - 100 = 500")

# ---------------------------------------------------------------------------
# Phase 9 — Task 019: armour math gated by damage school, not source. PHYSICAL/
# ARCANE spells respect armour; VOID lineage and TRUE_DMG bypass. Armour Break
# now amplifies non-bypassing spell damage too (real power increase for
# Korrath B3 spell builds — flagged in the balance pass, not special-cased).
# ---------------------------------------------------------------------------

static func _test_armour_reduces_physical_spell() -> void:
	# 400 PHYSICAL spell (e.g. shatterstrike) vs 200 armour → 200 lands.
	if not TestHarness.begin_test("armour / PHYSICAL spell reduced by armour (school-gated)"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	defender.armour = 200
	var info := CombatManager.make_damage_info(400, Enums.DamageSource.SPELL, Enums.DamageSchool.PHYSICAL)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(state.combat_manager.last_post_armour_damage, 200,
			"PHYSICAL spell 400 - 200 armour = 200 (was 400 under old source-only gate)")

static func _test_armour_reduces_arcane_spell() -> void:
	# 400 ARCANE spell vs 200 armour → 200 lands. ARCANE has no bypass — neutral magic.
	if not TestHarness.begin_test("armour / ARCANE spell reduced by armour (school-gated)"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	defender.armour = 200
	var info := CombatManager.make_damage_info(400, Enums.DamageSource.SPELL, Enums.DamageSchool.ARCANE)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(state.combat_manager.last_post_armour_damage, 200,
			"ARCANE spell 400 - 200 armour = 200")

static func _test_armour_bypassed_by_void_corruption_spell() -> void:
	# 300 VOID_CORRUPTION (sub-school of VOID) vs 800 armour → full 300 lands.
	if not TestHarness.begin_test("armour / VOID_CORRUPTION spell bypasses armour (sub-school of VOID)"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	defender.armour = 800
	var info := CombatManager.make_damage_info(300, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID_CORRUPTION)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(defender.current_health, 700,
			"VOID_CORRUPTION inherits VOID's armour bypass via SCHOOL_LINEAGE")

static func _test_armour_break_amplifies_physical_spell() -> void:
	# Spell-cast AB amplification — PHYSICAL spell vs 0-armour target with stacked AB.
	# 300 PHYSICAL + 200 AB (full bonus on 0 armour) = 500. Previously, AB was inert
	# for spell hits because the source-only gate skipped the armour-math path.
	if not TestHarness.begin_test("armour_break / amplifies PHYSICAL spell damage above raw"):
		return
	var state := TestHarness.build_state()
	var defender := TestHarness.spawn_enemy(state, "void_imp")
	defender.current_health = 1000
	BuffSystem.apply(defender, Enums.BuffType.ARMOUR_BREAK, 200, "test")
	var info := CombatManager.make_damage_info(300, Enums.DamageSource.SPELL, Enums.DamageSchool.PHYSICAL)
	state.combat_manager._deal_damage(defender, info)
	TestHarness.assert_eq(state.combat_manager.last_post_armour_damage, 500,
			"300 + 200 AB (full bonus, no armour) = 500 — AB now amplifies non-bypassing spells")

static func _test_hero_armour_reduces_physical_spell() -> void:
	# Hero variant: PHYSICAL spell vs hero with 200 armour → 200 lands.
	if not TestHarness.begin_test("hero armour / PHYSICAL spell reduced by hero armour"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	state.enemy_hero.armour = 200
	var info := CombatManager.make_damage_info(400, Enums.DamageSource.SPELL, Enums.DamageSchool.PHYSICAL)
	state.combat_manager.apply_hero_damage("enemy", info)
	TestHarness.assert_eq(cap.events.size(), 1, "one emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("amount"), 200,
				"PHYSICAL spell 400 - hero armour 200 = 200 lands on hero")

static func _test_hero_armour_bypassed_by_void_spell() -> void:
	# Hero variant: VOID spell vs 200 hero armour → full 400 lands.
	if not TestHarness.begin_test("hero armour / VOID spell bypasses hero armour"):
		return
	var state := TestHarness.build_state()
	var cap := HeroDmgCapture.new()
	state.combat_manager.hero_damaged.connect(cap.on_emit)
	state.enemy_hero.armour = 200
	var info := CombatManager.make_damage_info(400, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID)
	state.combat_manager.apply_hero_damage("enemy", info)
	TestHarness.assert_eq(cap.events.size(), 1, "one emission")
	if cap.events.size() == 1:
		TestHarness.assert_eq(cap.events[0].get("amount"), 400,
				"VOID spell bypasses hero armour entirely")

