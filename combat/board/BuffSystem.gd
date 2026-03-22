## BuffSystem.gd
## Centralized, data-driven buff/debuff engine for MinionInstance.
##
## All stat modifications and keyword grants on minions flow through here.
## Call sites never touch MinionInstance buff fields directly.
##
## Usage:
##   BuffSystem.apply(minion, Enums.BuffType.ATK_BONUS, 100, "soul_leech")
##   BuffSystem.remove_source(minion, "dominion_rune")
##   BuffSystem.dispel(minion)          # remove all buffs (Purge spell)
##   BuffSystem.cleanse(minion)         # remove all debuffs (Cleanse effect)
##   BuffSystem.expire_temp(minion)     # called at start of owner's turn
##   BuffSystem.sum_type(minion, type)  # total numeric value for a buff type
##   BuffSystem.has_type(minion, type)  # true if at least one entry of that type
class_name BuffSystem
extends RefCounted

# ---------------------------------------------------------------------------
# Categorisation helpers (used by dispel / cleanse)
# ---------------------------------------------------------------------------

## Buff types that count as debuffs — removed by Cleanse, kept by Dispel.
const DEBUFF_TYPES: Array[int] = [
	Enums.BuffType.CORRUPTION,
]

# ---------------------------------------------------------------------------
# Core API
# ---------------------------------------------------------------------------

## Apply a buff or debuff to a minion.
## source  — identifies who applied this (for targeted removal, e.g. "dominion_rune").
## is_temp — if true, the entry is cleared by expire_temp at the start of the owner's turn.
static func apply(minion: MinionInstance, type: int, amount: int,
		source: String = "", is_temp: bool = false) -> void:
	var entry := BuffEntry.new()
	entry.type    = type
	entry.amount  = amount
	entry.source  = source
	entry.is_temp = is_temp
	minion.buffs.append(entry)

## Remove all buff entries that were applied by the named source.
## Used for aura cleanup (e.g. Dominion Rune removed from board).
static func remove_source(minion: MinionInstance, source: String) -> void:
	minion.buffs = minion.buffs.filter(func(e: BuffEntry) -> bool: return e.source != source)
	_clamp_shield(minion)

## Remove all entries of a specific buff type.
static func remove_type(minion: MinionInstance, type: int) -> void:
	minion.buffs = minion.buffs.filter(func(e: BuffEntry) -> bool: return e.type != type)
	_clamp_shield(minion)

## Remove all buff entries (non-debuffs) — used by Purge / Dispel spells.
## Debuff entries (CORRUPTION) are preserved.
static func dispel(minion: MinionInstance) -> void:
	minion.buffs = minion.buffs.filter(func(e: BuffEntry) -> bool: return e.type in DEBUFF_TYPES)
	_clamp_shield(minion)

## Remove all debuff entries — used by Cleanse effects.
## Buff entries are preserved.
static func cleanse(minion: MinionInstance) -> void:
	minion.buffs = minion.buffs.filter(func(e: BuffEntry) -> bool: return not (e.type in DEBUFF_TYPES))

## Remove all runtime buff and debuff entries except SHIELD_BONUS — used by Purge effects.
## Shield is treated as a base stat and is not stripped.
static func purge_all(minion: MinionInstance) -> void:
	minion.buffs = minion.buffs.filter(func(e: BuffEntry) -> bool: return e.type == Enums.BuffType.SHIELD_BONUS)

## Expire all temporary buff entries — call at the start of the owner's turn.
static func expire_temp(minion: MinionInstance) -> void:
	minion.buffs = minion.buffs.filter(func(e: BuffEntry) -> bool: return not e.is_temp)

# ---------------------------------------------------------------------------
# Query API
# ---------------------------------------------------------------------------

## Sum of all amounts for a given buff type. Returns 0 if no entries exist.
static func sum_type(minion: MinionInstance, type: int) -> int:
	var total: int = 0
	for e: BuffEntry in minion.buffs:
		if e.type == type:
			total += e.amount
	return total

## True if the minion has at least one buff entry of the given type.
static func has_type(minion: MinionInstance, type: int) -> bool:
	for e: BuffEntry in minion.buffs:
		if e.type == type:
			return true
	return false

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Clamp current_shield to the shield cap after a SHIELD_BONUS buff is removed.
static func _clamp_shield(minion: MinionInstance) -> void:
	var cap := minion.shield_cap()
	if minion.current_shield > cap:
		minion.current_shield = cap
