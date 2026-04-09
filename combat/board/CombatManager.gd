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
	var atk_damage := _apply_crit(attacker)
	var pre_hp := defender.current_health
	_deal_damage(defender, atk_damage, Enums.DamageType.PHYSICAL)
	last_attack_damage = maxi(0, pre_hp - defender.current_health)
	_deal_damage(attacker, defender.effective_atk(), Enums.DamageType.PHYSICAL)

	if attacker.has_lifedrain() and atk_damage > 0:
		hero_healed.emit(attacker.owner, atk_damage)

	attacker.attack_count += 1
	attacker.state = Enums.MinionState.EXHAUSTED
	attack_resolved.emit(attacker, defender)

## Resolve a minion attacking the enemy hero directly.
func resolve_minion_attack_hero(attacker: MinionInstance, target_owner: String) -> void:
	var damage := _apply_crit(attacker)
	if damage > 0:
		hero_damaged.emit(target_owner, damage, Enums.DamageType.PHYSICAL)
		if attacker.has_lifedrain():
			hero_healed.emit(attacker.owner, damage)
	attacker.attack_count += 1
	attacker.state = Enums.MinionState.EXHAUSTED

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
			minion.current_health = 0
			minion_vanished.emit(minion)

## Apply spell damage to a minion. Respects SPELL_IMMUNE.
func apply_spell_damage(minion: MinionInstance, damage: int) -> void:
	if minion.has_spell_immune():
		return
	_deal_damage(minion, damage, Enums.DamageType.SPELL)

## Instantly kill a minion, bypassing shield and health checks.
## Fires minion_vanished so On Death effects and board cleanup happen normally.
func kill_minion(minion: MinionInstance) -> void:
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
	var multiplier: float = 2.0
	if scene != null and scene.get("crit_multiplier") != null:
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
