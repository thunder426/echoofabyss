## CombatManager.gd
## Handles all combat math: attacks and minion death.
## Does NOT know about visuals — it only changes MinionInstance data
## and emits signals. The scene listens to signals and updates the UI.
class_name CombatManager
extends RefCounted

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted after an attack resolves
signal attack_resolved(attacker: MinionInstance, defender: MinionInstance)

## Emitted when a minion's HP reaches 0 and it leaves the board
signal minion_vanished(minion: MinionInstance)

## Emitted when a hero takes damage. info carries amount + source + school + attacker + source_card.
## See design/DAMAGE_TYPE_SYSTEM.md for the DamageInfo shape.
signal hero_damaged(target: String, info: Dictionary)

## Emitted when a hero is healed ("player" or "enemy", amount)
signal hero_healed(target: String, amount: int)

# ---------------------------------------------------------------------------
# DamageInfo construction
# See design/DAMAGE_TYPE_SYSTEM.md.
# ---------------------------------------------------------------------------

## Build a DamageInfo dict — the canonical payload carried through every damage path.
## Stored as Dictionary (not a Resource) for lightness; fields are stable, validated by tests.
static func make_damage_info(
		amount: int,
		source: Enums.DamageSource,
		school: int = Enums.DamageSchool.NONE,
		attacker: MinionInstance = null,
		source_card: String = ""
) -> Dictionary:
	return {
		"amount": amount,
		"source": source,
		"school": school,
		"attacker": attacker,
		"source_card": source_card,
	}


# ---------------------------------------------------------------------------
# Main attack resolution
# ---------------------------------------------------------------------------

## Scene reference — set by CombatScene/SimState so we can read crit_multiplier.
var scene: Object = null

## Resolve a full attack between two minions (simultaneous damage).
## Effective damage dealt to the defender (post-Ethereal, 0 if Immune). NOT clamped
## to the defender's HP — overkill is preserved so the floating number reflects the
## strike's true magnitude rather than the bar's drop.
var last_attack_damage: int = 0
## Effective counter-damage dealt to the attacker. Same overkill semantics as above.
var last_counter_damage: int = 0
## HP delta on the defender for the last attack (pre_hp - post_hp, clamped to pre_hp).
## Used to reconstruct the HP-bar tween's starting value.
var last_attack_hp_delta: int = 0
## HP+shield delta on the attacker for the last counter. Used for the HP tween.
var last_counter_hp_delta: int = 0
## Post-armour damage from the last `_deal_damage` invocation (i.e. what entered the
## shield/HP pool after Korrath Armour reduction and Armour Break math). Pierce overkill
## reads this so it carries the *landed* damage to the enemy hero, not the raw atk value.
## Defaults to 0 between calls — callers must read it immediately after `_deal_damage`.
var last_post_armour_damage: int = 0

func resolve_minion_attack(attacker: MinionInstance, defender: MinionInstance) -> void:
	if scene != null:
		scene._last_attacker = attacker
	# Korrath — fire ON_PLAYER_ATTACK BEFORE damage resolves so handlers (e.g.
	# commanders_reach) can apply Armour Break to the defender in time to affect
	# this strike. Player-side only; ON_ENEMY_ATTACK is fired from CombatScene's
	# enemy attack input path, not here, to keep that side's existing wiring intact.
	if attacker.owner == "player" and scene != null and scene.get("trigger_manager") != null:
		var atk_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_ATTACK, "player")
		atk_ctx.minion = attacker
		atk_ctx.defender = defender
		scene.trigger_manager.fire(atk_ctx)
	var atk_damage := _apply_crit(attacker)

	# ETHEREAL: defender takes 50% reduced physical damage from minion attacks
	var ethereal_prevented := 0
	if defender.has_ethereal():
		ethereal_prevented = atk_damage / 2
		atk_damage -= ethereal_prevented

	var pre_hp := defender.current_health
	var pre_shield := defender.current_shield
	_deal_damage(defender, _attack_damage_info(atk_damage, attacker))
	var landed_damage: int = last_post_armour_damage
	last_attack_hp_delta = maxi(0, pre_hp - defender.current_health)
	# Effective damage = post-Ethereal amount that reached the body (0 if Immune).
	last_attack_damage = atk_damage if not defender.has_immune() else 0

	# PIERCE: excess kill damage carries through to the enemy hero. Uses post-armour
	# damage (the value that actually reached the defender's pool) so Korrath Armour
	# reduces both the kill damage AND the carry — armour is fully effective. School
	# inherits from the attacker so a Void minion's pierce overkill stays Void-flavored.
	if attacker.has_pierce() and defender.current_health <= 0:
		var total_effective_hp := pre_hp + pre_shield
		var excess := maxi(0, landed_damage - total_effective_hp)
		if excess > 0:
			var target_owner := "player" if defender.owner == "player" else "enemy"
			apply_hero_damage(target_owner, _attack_damage_info(excess, attacker))

	# Rift Warden siphon: if any friendly minion has rift_warden_siphon passive,
	# deal ETHEREAL prevented damage to the enemy hero
	if ethereal_prevented > 0:
		_rift_warden_siphon(defender, ethereal_prevented)

	# Counter-attack: attacker takes defender's ATK
	var counter_damage := defender.effective_atk()
	if attacker.has_ethereal():
		counter_damage -= counter_damage / 2
	var attacker_pre_hp := attacker.current_health
	var attacker_pre_shield := attacker.current_shield
	_deal_damage(attacker, _attack_damage_info(counter_damage, defender))
	last_counter_hp_delta = maxi(0, (attacker_pre_hp + attacker_pre_shield) - (attacker.current_health + attacker.current_shield))
	last_counter_damage = counter_damage if not attacker.has_immune() else 0

	if attacker.has_lifedrain() and atk_damage > 0:
		hero_healed.emit(attacker.owner, atk_damage)

	if attacker.has_siphon() and atk_damage > 0:
		_siphon_self_heal(attacker, atk_damage)

	attacker.attack_count += 1
	attacker.state = Enums.MinionState.EXHAUSTED
	_check_post_crit(attacker)
	attack_resolved.emit(attacker, defender)
	if scene != null:
		scene._last_attacker = null
		scene.set("_last_attack_was_crit", false)

## Resolve a minion attacking the enemy hero directly.
func resolve_minion_attack_hero(attacker: MinionInstance, target_owner: String) -> void:
	if scene != null:
		scene._last_attacker = attacker
	# Korrath — same on-attack trigger as minion-vs-minion. Defender encoded as a
	# string sentinel ("enemy_hero" / "player_hero") so handlers can branch on type.
	if attacker.owner == "player" and scene != null and scene.get("trigger_manager") != null:
		var atk_ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_ATTACK, "player")
		atk_ctx.minion = attacker
		atk_ctx.defender = "%s_hero" % target_owner
		scene.trigger_manager.fire(atk_ctx)
	var damage := _apply_crit(attacker)
	if damage > 0:
		apply_hero_damage(target_owner, _attack_damage_info(damage, attacker))
		if attacker.has_lifedrain():
			hero_healed.emit(attacker.owner, damage)
		if attacker.has_siphon():
			_siphon_self_heal(attacker, damage)
	attacker.attack_count += 1
	_check_post_crit(attacker)
	attacker.state = Enums.MinionState.EXHAUSTED
	if scene != null:
		scene._last_attacker = null
		scene.set("_last_attack_was_crit", false)

# ---------------------------------------------------------------------------
# Damage application
# ---------------------------------------------------------------------------

## Apply hero damage carrying full DamageInfo. All hero damage routes through here.
##
## Korrath — physical attacks (DamageSource.MINION) run through hero Armour and
## Armour Break math identical to the minion path; spells bypass entirely.
## `info.amount` is rewritten to the post-armour value before the signal fires
## so listeners (CombatScene/SimState) and downstream telemetry see the value
## that actually lands. PR1 (task 014): hero armour and AB are always 0/empty,
## so this is a no-op for behavior; PR2 wires the three Korrath handlers and
## the math becomes load-bearing.
func apply_hero_damage(target: String, info: Dictionary) -> void:
	var amount: int = info.get("amount", 0)
	if amount <= 0:
		return
	if scene != null and info.get("source", Enums.DamageSource.SPELL) == Enums.DamageSource.MINION:
		var hero: HeroState = scene.player_hero if target == "player" else scene.enemy_hero
		if hero != null:
			amount = _apply_armour_math(hero, amount)
			info["amount"] = amount
			if amount <= 0:
				return
	hero_damaged.emit(target, info)

## Korrath armour resolution shared by minion and hero damage paths. Returns the
## post-armour damage to apply. `target` is duck-typed on `armour: int` and
## `buffs: Array[BuffEntry]` (MinionInstance or HeroState).
##
## Two-bucket model: Armour reduces damage; ARMOUR_BREAK reduces effective armour
## first, with excess (AB > armour) becoming flat bonus damage. Branch 3 T0
## corrupting_presence emits a permanent AB stack at the moment a corruption
## stack is applied to an enemy target — that AB lives in BuffSystem like any
## other AB and naturally flows through this math; corruption stacks themselves
## are NOT read here. See design/KORRATH_HERO_DESIGN section "Armour".
##
## Floor only applies when armour math actually ran (target has armour OR AB
## stacks); a 50-ATK pawn vs an unarmoured untouched target still deals 50, not
## 100.
func _apply_armour_math(target: Object, damage: int) -> int:
	var armour: int = target.armour
	var armour_break: int = BuffSystem.sum_type(target, Enums.BuffType.ARMOUR_BREAK)
	if armour == 0 and armour_break == 0:
		return damage
	var effective_armour: int = maxi(0, armour - armour_break)
	var bonus: int = maxi(0, armour_break - armour)
	return maxi(100, damage - effective_armour + bonus)

## Reduce a minion's HP using a DamageInfo. Shield absorbs first. Emit minion_vanished
## if HP reaches 0. Source/school are stashed for downstream resistances and triggers.
func _deal_damage(minion: MinionInstance, info: Dictionary) -> void:
	last_post_armour_damage = 0
	var damage: int = info.get("amount", 0)
	if damage <= 0:
		return
	if minion.has_immune():
		if scene != null and scene.get("_immune_dmg_prevented") != null:
			scene._immune_dmg_prevented += damage
		return
	# Korrath — Armour math for physical attacks (DamageSource.MINION). Spells and
	# minion-emitted SPELL-source effects bypass armour entirely. corrupting_presence
	# emits its AB stack at corruption-apply time (see CombatState._corrupt_minion);
	# this path just runs the standard armour/AB math.
	var source: Enums.DamageSource = info.get("source", Enums.DamageSource.SPELL)
	if source == Enums.DamageSource.MINION:
		damage = _apply_armour_math(minion, damage)
	last_post_armour_damage = damage
	# Shield absorbs damage before HP
	if minion.current_shield > 0:
		var absorbed := mini(damage, minion.current_shield)
		minion.current_shield -= absorbed
		damage -= absorbed
	if damage > 0:
		minion.current_health -= damage
		if minion.current_health <= 0:
			if minion.has_deathless():
				BuffSystem.remove_type(minion, Enums.BuffType.GRANT_DEATHLESS)
				minion.current_health = 50
				return
			# Pre-death save hook — talents like Seris's deathless_flesh consume a
			# resource to prevent death. Scene returns true if the minion was saved
			# (and must restore HP to a non-zero value). has_method guard keeps sim
			# state safe when the hook isn't wired.
			if scene != null and scene.has_method("_try_save_from_death") and scene._try_save_from_death(minion):
				return
			minion.current_health = 0
			# F11 debug: track Behemoth/Bastion death cause
			if scene != null and minion.owner == "enemy":
				var id: String = minion.card_data.id
				if id == "void_behemoth" or id == "bastion_colossus":
					var key: String = "_vw_behemoth_lost" if id == "void_behemoth" else "_vw_bastion_lost"
					var dict = scene.get(key)
					if dict is Dictionary:
						var src: Enums.DamageSource = info.get("source", Enums.DamageSource.SPELL)
						var cause: String = "damage" if src == Enums.DamageSource.SPELL else "combat"
						dict[cause] = (dict[cause] as int) + 1
			minion_vanished.emit(minion)

## Apply damage to a minion using a DamageInfo. SPELL_IMMUNE blocks SPELL-source damage;
## ETHEREAL amplifies SPELL-source damage by 50%. Source-keyed (not school-keyed) so the
## existing keywords keep their meaning under the new model.
func apply_damage_to_minion(minion: MinionInstance, info: Dictionary) -> void:
	var source: Enums.DamageSource = info.get("source", Enums.DamageSource.SPELL)
	if source == Enums.DamageSource.SPELL:
		if minion.has_spell_immune():
			return
		if minion.has_ethereal():
			var amount: int = info.get("amount", 0)
			info = info.duplicate()
			info["amount"] = amount + amount / 2
	_deal_damage(minion, info)

## Build a DamageInfo for a minion basic attack (or counter-attack / pierce carry).
## Source = MINION. School comes from the attacker's MinionCardData.attack_damage_school
## — declarative on the card, override-friendly via talent_overrides. NONE on the
## card falls back to PHYSICAL (the historical default for basic attacks).
## Counters set attacker = the defender, since *that* minion's effective_atk drives
## the counter damage and its school should tag the counter.
func _attack_damage_info(amount: int, attacker: MinionInstance) -> Dictionary:
	var card_id: String = ""
	var school: Enums.DamageSchool = Enums.DamageSchool.PHYSICAL
	if attacker != null and attacker.card_data != null:
		card_id = attacker.card_data.id
		var declared: Enums.DamageSchool = (attacker.card_data as MinionCardData).attack_damage_school
		if declared != Enums.DamageSchool.NONE:
			school = declared
	return make_damage_info(amount, Enums.DamageSource.MINION, school, attacker, card_id)


## Instantly kill a minion, bypassing shield and health checks.
## Fires minion_vanished so On Death effects and board cleanup happen normally.
func kill_minion(minion: MinionInstance) -> void:
	if scene != null and scene.has_method("_try_save_from_death") and scene._try_save_from_death(minion):
		return
	minion.current_health = 0
	minion_vanished.emit(minion)

# ---------------------------------------------------------------------------
# Critical Strike
# ---------------------------------------------------------------------------

## If the attacker has CRITICAL_STRIKE stacks, consume one and return
## effective_atk multiplied by the scene's crit_multiplier (default 2.0).
## Otherwise return effective_atk unchanged.
func _apply_crit(attacker: MinionInstance) -> int:
	var base_dmg := attacker.effective_atk()
	if not BuffSystem.has_type(attacker, Enums.BuffType.CRITICAL_STRIKE):
		return base_dmg
	BuffSystem.remove_one_source(attacker, "critical_strike")
	# Track crit consumption for passives (void_precision, champion_void_scout)
	if scene != null:
		var key: String = "_enemy_crits_consumed" if attacker.owner == "enemy" else "_player_crits_consumed"
		var cur = scene.get(key)
		if cur != null:
			scene.set(key, (cur as int) + 1)
		# Store attacker for post-crit processing
		scene.set("_last_crit_attacker", attacker)
		# Flag this attack as a crit so death handlers can detect crit-kills.
		# Cleared by the death handler (or next attack if no kill occurred).
		scene.set("_last_attack_was_crit", true)
	var multiplier: float = 2.0
	if scene != null:
		# Check per-side multiplier first, fall back to global
		var side_key: String = "enemy_crit_multiplier" if attacker.owner == "enemy" else "player_crit_multiplier"
		var side_mult = scene.get(side_key)
		if side_mult != null and side_mult > 0.0:
			multiplier = side_mult
		elif scene.get("crit_multiplier") != null:
			multiplier = scene.get("crit_multiplier")
	return int(base_dmg * multiplier)

# ---------------------------------------------------------------------------
# Board helpers
# ---------------------------------------------------------------------------

## Check if any friendly minion of the defender has rift_warden_siphon passive.
## If so, deal the ETHEREAL-prevented damage to the enemy hero.
func _rift_warden_siphon(defender: MinionInstance, prevented: int) -> void:
	if scene == null:
		return
	var board: Array[MinionInstance]
	if defender.owner == "player":
		board = scene.get("player_board") as Array[MinionInstance]
	else:
		board = scene.get("enemy_board") as Array[MinionInstance]
	if board == null:
		return
	for m: MinionInstance in board:
		if (m.card_data as MinionCardData).passive_effect_id == "rift_warden_siphon":
			var target_owner := "player" if defender.owner == "enemy" else "enemy"
			# Rift Warden re-emits prevented damage as SPELL-source (passive ability).
			var info := make_damage_info(prevented, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, m, "rift_warden_siphon")
			apply_hero_damage(target_owner, info)
			return  # only one siphon per attack

## Siphon keyword — heal the attacker by 50% of damage dealt, clamped to max HP.
## Distinct from Lifedrain (which heals the hero). Damage dealt uses the post-Ethereal
## atk_damage value — i.e. what actually landed, not the raw attack stat.
func _siphon_self_heal(attacker: MinionInstance, damage_dealt: int) -> void:
	var heal := damage_dealt / 2
	if heal <= 0:
		return
	var hp_cap: int = attacker.card_data.health + BuffSystem.sum_type(attacker, Enums.BuffType.HP_BONUS)
	var before := attacker.current_health
	attacker.current_health = mini(attacker.current_health + heal, hp_cap)
	var healed := attacker.current_health - before
	if healed > 0 and scene != null and scene.has_method("_on_minion_siphon_healed"):
		scene._on_minion_siphon_healed(attacker, healed)

## Check if the last attack consumed a crit and run post-crit processing.
func _check_post_crit(attacker: MinionInstance) -> void:
	if scene == null:
		return
	if scene.get("_last_crit_attacker") != attacker:
		return
	scene.set("_last_crit_attacker", null)
	if attacker.current_health > 0:
		_post_crit(attacker)

## Post-crit processing: void_precision (+200 ATK), champion_void_captain aura,
## and champion crit tracking.  Called after attack resolves when a crit was consumed.
func _post_crit(attacker: MinionInstance) -> void:
	# void_precision: grant +200 ATK permanently after crit
	var passives = scene.get("_active_enemy_passives")
	if passives != null and "void_precision" in passives and attacker.owner == "enemy":
		BuffSystem.apply(attacker, Enums.BuffType.ATK_BONUS, 200, "void_precision", false, false)
	# Champion void_captain aura: on enemy crit consumed, deal 100 damage to
	# each of 2 random player targets (minions or hero).
	if attacker.owner == "enemy" and _champion_vc_is_alive():
		for i in 2:
			var targets: Array = []
			var player_board: Array[MinionInstance] = scene.get("player_board") as Array[MinionInstance]
			if player_board != null:
				for m: MinionInstance in player_board:
					if m.current_health > 0:
						targets.append(m)
			targets.append("hero")  # hero is always a valid target
			var pick: Variant = targets[randi() % targets.size()]
			if pick is MinionInstance:
				var m_info := make_damage_info(100, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, attacker, "champion_void_captain")
				apply_damage_to_minion(pick as MinionInstance, m_info)
			else:
				var h_info := make_damage_info(100, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, attacker, "champion_void_captain")
				apply_hero_damage("player", h_info)
	# Champion void_scout tracking is handled via _enemy_crits_consumed counter
	# (incremented in _apply_crit, checked by champion handler on turn events)

func _champion_vc_is_alive() -> bool:
	if scene == null:
		return false
	var board: Array[MinionInstance] = scene.get("enemy_board") as Array[MinionInstance]
	if board == null:
		return false
	for m: MinionInstance in board:
		if m.card_data.id == "champion_void_captain":
			return true
	return false

## Returns true if the board has any minion with Guard.
static func board_has_taunt(board: Array[MinionInstance]) -> bool:
	for minion in board:
		if minion.has_guard():
			return true
	return false

## Returns only the Guard minions from a board array.
static func get_taunt_minions(board: Array[MinionInstance]) -> Array[MinionInstance]:
	var taunts: Array[MinionInstance] = []
	for minion in board:
		if minion.has_guard():
			taunts.append(minion)
	return taunts
