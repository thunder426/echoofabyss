## MinionInstance.gd
## The runtime state of a minion currently on the board.
## CardData (MinionCardData) is the static definition — MinionInstance is the live version.
##
## All stat modifications and keyword grants go through BuffSystem.
## Do NOT write to MinionInstance buff-related fields directly from outside this file.
class_name MinionInstance
extends RefCounted

# Who owns this minion
var owner: String = "player"  # "player" or "enemy"

# Original card definition — never modified
var card_data: MinionCardData

# ---------------------------------------------------------------------------
# Base stats — set once at creation, NEVER mutated directly after that.
# All ATK modifications go through BuffSystem (ATK_BONUS, TEMP_ATK, CORRUPTION).
# ---------------------------------------------------------------------------
var current_atk: int = 0

# Current HP — reduced by damage, increased by heals and HP buffs.
# HP changes are applied directly (not tracked in BuffSystem — not reversible).
var current_health: int = 0

# Current shield HP — absorbs damage before HP; regenerated each turn if regen keyword present.
var current_shield: int = 0

# ---------------------------------------------------------------------------
# Buff list — managed exclusively by BuffSystem
# ---------------------------------------------------------------------------
## Array[BuffEntry] — all active buffs and debuffs on this minion.
var buffs: Array = []

# ---------------------------------------------------------------------------
# Board state
# ---------------------------------------------------------------------------
var state: Enums.MinionState = Enums.MinionState.EXHAUSTED

# Which board slot index this minion occupies (0–4)
var slot_index: int = -1

# ---------------------------------------------------------------------------
# Initialise from a CardData definition
# ---------------------------------------------------------------------------

static func create(data: MinionCardData, owner_id: String) -> MinionInstance:
	var instance := MinionInstance.new()
	instance.card_data    = data
	instance.owner        = owner_id
	instance.current_atk    = data.atk
	instance.current_health = data.health
	instance.current_shield = data.shield_max
	# Minions are exhausted (cannot attack) on the turn they are summoned
	# unless they have the Rush keyword
	if Enums.Keyword.RUSH in data.keywords:
		instance.state = Enums.MinionState.NORMAL
	else:
		instance.state = Enums.MinionState.EXHAUSTED
	return instance

# ---------------------------------------------------------------------------
# Stat helpers — read-only computed properties
# ---------------------------------------------------------------------------

## Total ATK including all buff/debuff entries. Floor is 0.
func effective_atk() -> int:
	var atk := current_atk
	atk += BuffSystem.sum_type(self, Enums.BuffType.ATK_BONUS)
	atk += BuffSystem.sum_type(self, Enums.BuffType.TEMP_ATK)
	atk -= BuffSystem.sum_type(self, Enums.BuffType.CORRUPTION)
	return maxi(0, atk)

## Maximum shield this minion can have (base + SHIELD_BONUS buffs).
func shield_cap() -> int:
	return card_data.shield_max + BuffSystem.sum_type(self, Enums.BuffType.SHIELD_BONUS)

## True if this minion can be selected as an attacker.
func can_attack() -> bool:
	return state == Enums.MinionState.NORMAL and effective_atk() > 0

## True if this minion has Taunt (base keyword or granted at runtime).
func has_taunt() -> bool:
	return BuffSystem.has_type(self, Enums.BuffType.GRANT_TAUNT) \
		or Enums.Keyword.TAUNT in card_data.keywords

## True if this minion has Lifedrain (base keyword or granted at runtime).
func has_lifedrain() -> bool:
	return BuffSystem.has_type(self, Enums.BuffType.GRANT_LIFEDRAIN) \
		or Enums.Keyword.LIFEDRAIN in card_data.keywords

## True if this minion has any shield capacity.
func has_shield() -> bool:
	return shield_cap() > 0

# ---------------------------------------------------------------------------
# Turn lifecycle
# ---------------------------------------------------------------------------

## Called at the start of the owner's turn.
## Expires temporary buffs, un-exhausts the minion, and regenerates shield.
func on_turn_start() -> void:
	BuffSystem.expire_temp(self)
	if state == Enums.MinionState.EXHAUSTED:
		state = Enums.MinionState.NORMAL
	var regen := _shield_regen_amount()
	var cap   := shield_cap()
	if regen > 0 and current_shield < cap:
		current_shield = mini(current_shield + regen, cap)

## How much shield this minion regenerates per turn (0 = no regen).
## Uses the ×100 stat scale — REGEN_1 = 100, REGEN_2 = 200.
func _shield_regen_amount() -> int:
	if Enums.Keyword.SHIELD_REGEN_2 in card_data.keywords:
		return 200
	if Enums.Keyword.SHIELD_REGEN_1 in card_data.keywords:
		return 100
	return 0

# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------

## Returns a readable summary for debug purposes.
func debug_label() -> String:
	var base := "%s [ATK:%s HP:%s]" % [card_data.card_name, str(effective_atk()), str(current_health)]
	if current_shield > 0:
		base += " S:%s" % str(current_shield)
	if BuffSystem.has_type(self, Enums.BuffType.CORRUPTION):
		base += " Corrupt:%s" % str(BuffSystem.sum_type(self, Enums.BuffType.CORRUPTION))
	return base
