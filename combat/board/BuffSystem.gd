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
# Signal bus — lazy-initialized Object that holds user signals.
# Static class can't declare signals directly, so we route through an Object.
# CombatScene connects to `buff_applied` on _ready to drive BuffApplyVFX.
# Signature: buff_applied(minion, buff_type, atk_delta, hp_delta, source_tag)
# ---------------------------------------------------------------------------

static var _bus: Object = null

static func bus() -> Object:
	if _bus == null:
		_bus = Object.new()
		_bus.add_user_signal("buff_applied", [
			{"name": "minion",     "type": TYPE_OBJECT},
			{"name": "buff_type",  "type": TYPE_INT},
			{"name": "atk_delta",  "type": TYPE_INT},
			{"name": "hp_delta",   "type": TYPE_INT},
			{"name": "source_tag", "type": TYPE_STRING},
		])
	return _bus

# ---------------------------------------------------------------------------
# Core API
# ---------------------------------------------------------------------------

## Apply a buff or debuff to a minion.
## source   — identifies who applied this (for targeted removal, e.g. "dominion_rune").
## is_temp  — if true, the entry is cleared by expire_temp at the start of the owner's turn.
## emit_vfx — if true, fire the `buff_applied` signal on the bus when stats actually change.
##            Aura reapplication and silent/setup grants should pass false to keep the
##            board quiet (auras re-run constantly; setup grants are invisible).
static func apply(minion: MinionInstance, type: int, amount: int,
		source: String = "", is_temp: bool = false, emit_vfx: bool = true) -> void:
	var pre_atk: int = 0
	var pre_hp_cap: int = 0
	var pre_shield_cap: int = 0
	if emit_vfx and minion != null:
		pre_atk        = minion.effective_atk()
		pre_hp_cap     = minion.card_data.health + sum_type(minion, Enums.BuffType.HP_BONUS)
		pre_shield_cap = minion.shield_cap()

	var entry := BuffEntry.new()
	entry.type    = type
	entry.amount  = amount
	entry.source  = source
	entry.is_temp = is_temp
	minion.buffs.append(entry)

	if not emit_vfx or minion == null:
		return
	var post_atk: int = minion.effective_atk()
	var post_hp_cap: int = minion.card_data.health + sum_type(minion, Enums.BuffType.HP_BONUS)
	var post_shield_cap: int = minion.shield_cap()
	var atk_delta: int = post_atk - pre_atk
	var hp_delta:  int = (post_hp_cap - pre_hp_cap) + (post_shield_cap - pre_shield_cap)
	if atk_delta == 0 and hp_delta == 0:
		return  # dedupe: aura reapply or no-op grant — don't flash
	bus().emit_signal("buff_applied", minion, type, atk_delta, hp_delta, source)

## Direct HP increase that still participates in buff VFX.
## HP is mutated on `current_health` directly (not a BuffEntry), so callers that
## want the generic "minion got buffed" VFX to show an HP pulse must route
## through here rather than incrementing `current_health` themselves.
static func apply_hp_gain(minion: MinionInstance, amount: int,
		source: String = "", emit_vfx: bool = true) -> void:
	if minion == null or amount == 0:
		return
	minion.current_health += amount
	if emit_vfx:
		bus().emit_signal("buff_applied", minion, Enums.BuffType.HP_BONUS, 0, amount, source)

## Remove all buff entries that were applied by the named source.
## Used for aura cleanup (e.g. Dominion Rune removed from board).
static func remove_source(minion: MinionInstance, source: String) -> void:
	minion.buffs = minion.buffs.filter(func(e: BuffEntry) -> bool: return e.source != source)
	_clamp_shield(minion)

## Remove only the FIRST buff entry matching the named source.
## Used when one instance of a stackable aura is removed (e.g. one of two Dominion Runes
## consumed by a ritual) so other instances' buffs are preserved.
static func remove_one_source(minion: MinionInstance, source: String) -> void:
	for i in minion.buffs.size():
		if (minion.buffs[i] as BuffEntry).source == source:
			minion.buffs.remove_at(i)
			break
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
