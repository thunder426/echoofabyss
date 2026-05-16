## BuffSystem.gd
## Centralized, data-driven buff/debuff engine for MinionInstance and HeroState.
##
## All stat modifications and keyword grants on minions flow through here.
## Call sites never touch MinionInstance buff fields directly.
##
## `target` is duck-typed on `buffs: Array[BuffEntry]` so HeroState targets work
## via the same API. Stat-shaped reads (effective_atk, card_data.health, shield)
## are minion-only and gated by `is MinionInstance` checks. Hero-side AB lands
## via apply(hero, ARMOUR_BREAK, ...) once PR2 (task 007 phase 4-6) wires it.
##
## Usage:
##   BuffSystem.apply(target, Enums.BuffType.ATK_BONUS, 100, "soul_leech")
##   BuffSystem.remove_source(target, "dominion_rune")
##   BuffSystem.dispel(target)          # remove all buffs (Purge spell)
##   BuffSystem.cleanse(target)         # remove all debuffs (Cleanse effect)
##   BuffSystem.expire_temp(target)     # called at start of owner's turn
##   BuffSystem.sum_type(target, type)  # total numeric value for a buff type
##   BuffSystem.has_type(target, type)  # true if at least one entry of that type
class_name BuffSystem
extends RefCounted

# ---------------------------------------------------------------------------
# Categorisation helpers (used by dispel / cleanse)
# ---------------------------------------------------------------------------

## Buff types that count as debuffs — removed by Cleanse, kept by Dispel.
const DEBUFF_TYPES: Array[int] = [
	Enums.BuffType.CORRUPTION,
	Enums.BuffType.ARMOUR_BREAK,
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
		# Fired when Corruption stacks are stripped from a minion by any means
		# (Purge, Cleanse, targeted removal). Seris Corrupt Detonation listens here.
		# Deaths are handled scene-side (snapshot on vanish).
		_bus.add_user_signal("corruption_removed", [
			{"name": "minion", "type": TYPE_OBJECT},
			{"name": "stacks", "type": TYPE_INT},
		])
	return _bus

## Helper — snapshot corruption stacks on a target, emit corruption_removed if >0.
## Callers pass the pre-removal stack count; post-removal check is their responsibility
## (this only reports; it does not mutate the target).
static func _emit_corruption_removed(target: Object, stacks_removed: int) -> void:
	if stacks_removed <= 0 or target == null:
		return
	bus().emit_signal("corruption_removed", target, stacks_removed)

# ---------------------------------------------------------------------------
# Core API
# ---------------------------------------------------------------------------

## Apply a buff or debuff to a minion or hero.
## target   — MinionInstance or HeroState (duck-typed on `buffs`).
## source   — identifies who applied this (for targeted removal, e.g. "dominion_rune").
## is_temp  — if true, the entry is cleared by expire_temp at the start of the owner's turn.
## emit_vfx — if true, fire the `buff_applied` signal on the bus when stats actually change.
##            Aura reapplication and silent/setup grants should pass false to keep the
##            board quiet (auras re-run constantly; setup grants are invisible).
##            Hero targets never emit (no minion-shaped delta to flash; PR2 may add a
##            hero-specific buff_applied path if/when AB needs a badge tween).
static func apply(target: Object, type: int, amount: int,
		source: String = "", is_temp: bool = false, emit_vfx: bool = true) -> void:
	if target == null:
		return
	var minion: MinionInstance = target as MinionInstance
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
	target.buffs.append(entry)

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

## Permanent HP buff: raises the minion's max HP by `amount` (via an HP_BONUS
## buff entry, summed by callers that compute the cap) AND bumps current_health
## by the same amount so the minion stays at full at the new cap.
static func apply_hp_gain(minion: MinionInstance, amount: int,
		source: String = "", emit_vfx: bool = true) -> void:
	if minion == null or amount == 0:
		return
	apply(minion, Enums.BuffType.HP_BONUS, amount, source, false, emit_vfx)
	minion.current_health += amount

## Remove all buff entries that were applied by the named source.
## Used for aura cleanup (e.g. Dominion Rune removed from board).
static func remove_source(target: Object, source: String) -> void:
	if target == null:
		return
	var pre_corruption: int = count_type(target, Enums.BuffType.CORRUPTION)
	target.buffs = target.buffs.filter(func(e: BuffEntry) -> bool: return e.source != source)
	_clamp_shield(target)
	_emit_corruption_removed(target, pre_corruption - count_type(target, Enums.BuffType.CORRUPTION))

## Remove only the FIRST buff entry matching the named source.
## Used when one instance of a stackable aura is removed (e.g. one of two Dominion Runes
## consumed by a ritual) so other instances' buffs are preserved.
static func remove_one_source(target: Object, source: String) -> void:
	if target == null:
		return
	var pre_corruption: int = count_type(target, Enums.BuffType.CORRUPTION)
	for i in target.buffs.size():
		if (target.buffs[i] as BuffEntry).source == source:
			target.buffs.remove_at(i)
			break
	_clamp_shield(target)
	_emit_corruption_removed(target, pre_corruption - count_type(target, Enums.BuffType.CORRUPTION))

## Remove all entries of a specific buff type.
static func remove_type(target: Object, type: int) -> void:
	if target == null:
		return
	var pre_corruption: int = 0
	if type == Enums.BuffType.CORRUPTION:
		pre_corruption = count_type(target, Enums.BuffType.CORRUPTION)
	target.buffs = target.buffs.filter(func(e: BuffEntry) -> bool: return e.type != type)
	_clamp_shield(target)
	if type == Enums.BuffType.CORRUPTION:
		_emit_corruption_removed(target, pre_corruption)

## Remove all buff entries (non-debuffs) — used by Purge / Dispel spells.
## Debuff entries (CORRUPTION) are preserved.
static func dispel(target: Object) -> void:
	if target == null:
		return
	target.buffs = target.buffs.filter(func(e: BuffEntry) -> bool: return e.type in DEBUFF_TYPES)
	_clamp_shield(target)

## Remove all debuff entries — used by Cleanse effects.
## Buff entries are preserved.
static func cleanse(target: Object) -> void:
	if target == null:
		return
	var pre_corruption: int = count_type(target, Enums.BuffType.CORRUPTION)
	target.buffs = target.buffs.filter(func(e: BuffEntry) -> bool: return not (e.type in DEBUFF_TYPES))
	_emit_corruption_removed(target, pre_corruption)

## Remove all runtime buff and debuff entries except SHIELD_BONUS — used by Purge effects.
## Shield is treated as a base stat and is not stripped.
static func purge_all(target: Object) -> void:
	if target == null:
		return
	var pre_corruption: int = count_type(target, Enums.BuffType.CORRUPTION)
	target.buffs = target.buffs.filter(func(e: BuffEntry) -> bool: return e.type == Enums.BuffType.SHIELD_BONUS)
	_emit_corruption_removed(target, pre_corruption)

## Expire all temporary buff entries — call at the start of the owner's turn.
static func expire_temp(target: Object) -> void:
	if target == null:
		return
	target.buffs = target.buffs.filter(func(e: BuffEntry) -> bool: return not e.is_temp)

# ---------------------------------------------------------------------------
# Query API
# ---------------------------------------------------------------------------

## Sum of all amounts for a given buff type. Returns 0 if no entries exist.
static func sum_type(target: Object, type: int) -> int:
	if target == null:
		return 0
	var total: int = 0
	for e: BuffEntry in target.buffs:
		if e.type == type:
			total += e.amount
	return total

## Count of buff entries of a given type — useful for talents that care about
## "how many stacks" rather than "total amount applied" (e.g. Seris's
## corrupt_detonation / void_amplification which scale per-stack, not per-amount).
static func count_type(target: Object, type: int) -> int:
	if target == null:
		return 0
	var count: int = 0
	for e: BuffEntry in target.buffs:
		if e.type == type:
			count += 1
	return count

## Signed net Armour for a target. Positive = effective Armour reducing incoming
## damage; negative = Armour debt (AB exceeds Armour) acting as flat bonus damage
## on physical hits. Derived: `armour stat - sum(ARMOUR_BREAK stacks)`. Target is
## duck-typed on `armour: int` and `buffs: Array[BuffEntry]` (MinionInstance or
## HeroState). See design/KORRATH_HERO_DESIGN §2.
static func net_armour(target: Object) -> int:
	if target == null:
		return 0
	return int(target.armour) - sum_type(target, Enums.BuffType.ARMOUR_BREAK)

## True if the target has at least one buff entry of the given type.
static func has_type(target: Object, type: int) -> bool:
	if target == null:
		return false
	for e: BuffEntry in target.buffs:
		if e.type == type:
			return true
	return false

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Clamp current_shield to the shield cap after a SHIELD_BONUS buff is removed.
## Minion-only — heroes have no shield concept today. No-op for hero targets.
static func _clamp_shield(target: Object) -> void:
	var minion: MinionInstance = target as MinionInstance
	if minion == null:
		return
	var cap := minion.shield_cap()
	if minion.current_shield > cap:
		minion.current_shield = cap
