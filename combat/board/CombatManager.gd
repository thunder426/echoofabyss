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

## Emitted when a hero takes damage ("player" or "enemy", amount)
signal hero_damaged(target: String, amount: int)

## Emitted when a hero is healed ("player" or "enemy", amount)
signal hero_healed(target: String, amount: int)

# ---------------------------------------------------------------------------
# Main attack resolution
# ---------------------------------------------------------------------------

## Resolve a full attack between two minions (simultaneous damage).
func resolve_minion_attack(attacker: MinionInstance, defender: MinionInstance) -> void:
	_deal_damage(defender, attacker.effective_atk())
	_deal_damage(attacker, defender.effective_atk())

	if attacker.has_lifedrain() and attacker.effective_atk() > 0:
		hero_healed.emit(attacker.owner, attacker.effective_atk())

	attacker.state = Enums.MinionState.EXHAUSTED
	attack_resolved.emit(attacker, defender)

## Resolve a minion attacking the enemy hero directly.
func resolve_minion_attack_hero(attacker: MinionInstance, target_owner: String) -> void:
	var damage := attacker.effective_atk()
	if damage > 0:
		hero_damaged.emit(target_owner, damage)
		if attacker.has_lifedrain():
			hero_healed.emit(attacker.owner, damage)
	attacker.state = Enums.MinionState.EXHAUSTED

# ---------------------------------------------------------------------------
# Damage application
# ---------------------------------------------------------------------------

## Reduce a minion's HP, shield absorbs first. Emit minion_vanished if HP reaches 0.
func _deal_damage(minion: MinionInstance, damage: int) -> void:
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

## Apply spell damage to a minion (same flow as combat damage).
func apply_spell_damage(minion: MinionInstance, damage: int) -> void:
	_deal_damage(minion, damage)

## Instantly kill a minion, bypassing shield and health checks.
## Fires minion_vanished so On Death effects and board cleanup happen normally.
func kill_minion(minion: MinionInstance) -> void:
	minion.current_health = 0
	minion_vanished.emit(minion)

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
