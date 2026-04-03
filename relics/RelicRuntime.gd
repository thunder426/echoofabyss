## RelicRuntime.gd
## Tracks relic state during a single combat: charges remaining, cooldown timers,
## and activation constraints (1 relic per turn).
##
## Created at combat start from GameManager.player_relics.
## Each relic entry stores its RelicData + mutable combat state.
class_name RelicRuntime
extends RefCounted

## Per-relic combat state.
class RelicState:
	var data: RelicData
	var charges_remaining: int
	var cooldown_remaining: int  ## 0 = ready to use; >0 = turns until available
	var bonus_charges: int       ## Extra charges from "+1 charge" upgrades

	func _init(relic: RelicData, bonus: int = 0) -> void:
		data = relic
		bonus_charges = bonus
		charges_remaining = relic.charges + bonus
		cooldown_remaining = relic.cooldown  # Must wait before first use

## All relics the player has for this combat.
var relics: Array[RelicState] = []

## Whether a relic has been activated this turn (1 per turn limit).
var activated_this_turn: bool = false

## Total activations this combat (for tracking).
var total_activations: int = 0

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Build runtime state from player's relic IDs and any bonus charges.
## bonus_charges: Dictionary mapping relic_id → extra charges (from upgrade picks).
func setup(relic_ids: Array, bonus_charges: Dictionary = {}) -> void:
	relics.clear()
	for id in relic_ids:
		var data: RelicData = RelicDatabase.get_relic(id as String)
		if data == null:
			continue
		var bonus: int = bonus_charges.get(id, 0) as int
		relics.append(RelicState.new(data, bonus))

# ---------------------------------------------------------------------------
# Turn lifecycle
# ---------------------------------------------------------------------------

## Called at the start of each player turn. Ticks down cooldowns and resets
## the once-per-turn activation flag.
func on_turn_start() -> void:
	activated_this_turn = false
	for rs in relics:
		if rs.cooldown_remaining > 0:
			rs.cooldown_remaining -= 1

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

## Returns true if the relic at the given index can be activated right now.
func can_activate(index: int) -> bool:
	if activated_this_turn:
		return false
	if index < 0 or index >= relics.size():
		return false
	var rs: RelicState = relics[index]
	return rs.charges_remaining > 0 and rs.cooldown_remaining <= 0

## Returns the RelicState at the given index, or null.
func get_state(index: int) -> RelicState:
	if index < 0 or index >= relics.size():
		return null
	return relics[index]

## Returns the index of a relic by ID, or -1 if not found.
func find_by_id(id: String) -> int:
	for i in relics.size():
		if relics[i].data.id == id:
			return i
	return -1

# ---------------------------------------------------------------------------
# Activation
# ---------------------------------------------------------------------------

## Consume a charge and start cooldown. Returns the effect_id to execute,
## or "" if activation failed.
func activate(index: int) -> String:
	if not can_activate(index):
		return ""
	var rs: RelicState = relics[index]
	rs.charges_remaining -= 1
	rs.cooldown_remaining = rs.data.cooldown
	activated_this_turn = true
	total_activations += 1
	return rs.data.effect_id

## Undo a previous activate() — restore the charge, clear cooldown, and
## reset the once-per-turn flag so the player can use a relic again.
func refund(index: int) -> void:
	if index < 0 or index >= relics.size():
		return
	var rs: RelicState = relics[index]
	rs.charges_remaining += 1
	rs.cooldown_remaining = 0
	activated_this_turn = false
	total_activations -= 1
