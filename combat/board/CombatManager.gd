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

## Emitted when a hero takes damage ("player" or "enemy", amount, damage type)
signal hero_damaged(target: String, amount: int, type: Enums.DamageType)

## Emitted when a hero is healed ("player" or "enemy", amount)
signal hero_healed(target: String, amount: int)

# ---------------------------------------------------------------------------
# Main attack resolution
# ---------------------------------------------------------------------------

## Scene reference — set by CombatScene/SimState so we can read crit_multiplier.
var scene: Object = null

## Resolve a full attack between two minions (simultaneous damage).
## The actual HP damage dealt to the defender in the last attack (before death triggers).
var last_attack_damage: int = 0

func resolve_minion_attack(attacker: MinionInstance, defender: MinionInstance) -> void:
	if scene != null:
		scene._last_attacker = attacker
	var atk_damage := _apply_crit(attacker)

	# ETHEREAL: defender takes 50% reduced physical damage from minion attacks
	var ethereal_prevented := 0
	if defender.has_ethereal():
		ethereal_prevented = atk_damage / 2
		atk_damage -= ethereal_prevented

	var pre_hp := defender.current_health
	var pre_shield := defender.current_shield
	_deal_damage(defender, atk_damage, Enums.DamageType.PHYSICAL)
	last_attack_damage = maxi(0, pre_hp - defender.current_health)

	# PIERCE: excess kill damage carries through to the enemy hero
	if attacker.has_pierce() and defender.current_health <= 0:
		var total_effective_hp := pre_hp + pre_shield
		var excess := maxi(0, atk_damage - total_effective_hp)
		if excess > 0:
			var target_owner := "player" if defender.owner == "player" else "enemy"
			hero_damaged.emit(target_owner, excess, Enums.DamageType.PHYSICAL)

	# Rift Warden siphon: if any friendly minion has rift_warden_siphon passive,
	# deal ETHEREAL prevented damage to the enemy hero
	if ethereal_prevented > 0:
		_rift_warden_siphon(defender, ethereal_prevented)

	# Counter-attack: attacker takes defender's ATK
	var counter_damage := defender.effective_atk()
	if attacker.has_ethereal():
		counter_damage -= counter_damage / 2
	_deal_damage(attacker, counter_damage, Enums.DamageType.PHYSICAL)

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

## Resolve a minion attacking the enemy hero directly.
func resolve_minion_attack_hero(attacker: MinionInstance, target_owner: String) -> void:
	if scene != null:
		scene._last_attacker = attacker
	var damage := _apply_crit(attacker)
	if damage > 0:
		hero_damaged.emit(target_owner, damage, Enums.DamageType.PHYSICAL)
		if attacker.has_lifedrain():
			hero_healed.emit(attacker.owner, damage)
		if attacker.has_siphon():
			_siphon_self_heal(attacker, damage)
	attacker.attack_count += 1
	_check_post_crit(attacker)
	attacker.state = Enums.MinionState.EXHAUSTED
	if scene != null:
		scene._last_attacker = null

# ---------------------------------------------------------------------------
# Damage application
# ---------------------------------------------------------------------------

## Deliver typed damage to the opponent hero. All hero damage routes through here
## so that type is available to signal listeners (passives, triggers, future resistances).
func apply_hero_damage(target: String, amount: int, type: Enums.DamageType) -> void:
	if amount > 0:
		hero_damaged.emit(target, amount, type)

## Reduce a minion's HP, shield absorbs first. Emit minion_vanished if HP reaches 0.
## type is passed through for future use (spell shields, resistances, typed triggers).
func _deal_damage(minion: MinionInstance, damage: int, type: Enums.DamageType = Enums.DamageType.PHYSICAL) -> void:
	if damage <= 0:
		return
	if minion.has_immune():
		if scene != null and scene.get("_immune_dmg_prevented") != null:
			scene._immune_dmg_prevented += damage
		return
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
						var cause: String = "damage" if type == Enums.DamageType.SPELL else "combat"
						dict[cause] = (dict[cause] as int) + 1
			minion_vanished.emit(minion)

## Apply spell damage to a minion. Respects SPELL_IMMUNE.
## ETHEREAL: minion takes 50% increased spell damage.
func apply_spell_damage(minion: MinionInstance, damage: int) -> void:
	if minion.has_spell_immune():
		return
	if minion.has_ethereal():
		damage += damage / 2
	_deal_damage(minion, damage, Enums.DamageType.SPELL)

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

## Apply spell damage scaled by dark_channeling crit (1.5x).
## Called by the dark_channeling passive handler — NOT the normal spell path.
func apply_crit_spell_damage(minion: MinionInstance, damage: int, multiplier: float) -> void:
	if minion.has_spell_immune():
		return
	_deal_damage(minion, int(damage * multiplier), Enums.DamageType.SPELL)

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
			hero_damaged.emit(target_owner, prevented, Enums.DamageType.SPELL)
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
				apply_spell_damage(pick as MinionInstance, 100)
			else:
				hero_damaged.emit("player", 100, Enums.DamageType.SPELL)
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
