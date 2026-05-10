## HeroState.gd
## Per-side hero data: HP, max HP, Armour, and a buff/debuff container compatible
## with BuffSystem (which duck-types on `buffs`). Lives on CombatState as
## `player_hero` and `enemy_hero`. Symmetric for player/enemy — neither side has
## any hero-specific fields the other lacks.
##
## Today the Armour field is wired up; AB lives as BuffEntry instances on `buffs`
## via BuffSystem.apply(hero, ARMOUR_BREAK, ...). PR2 (task 007 phase 4-6) wires
## the three Korrath handlers and ships UI badges that read these fields.
class_name HeroState
extends RefCounted

## Identifies which side this hero belongs to ("player" or "enemy"). Set once at
## construction so BuffSystem / armour math don't have to be told the side.
var side: String = ""

## Current HP. CombatState's `player_hp` / `enemy_hp` properties forward through
## here so the existing hp_changed signal contract is preserved at one site.
var hp: int = 0

## Max HP. CombatState's `player_hp_max` / `enemy_hp_max` properties forward here.
var hp_max: int = 0

## Korrath — current Armour. Reduces incoming MINION-source damage; spells bypass.
## Mirrors MinionInstance.armour. Mutated only via add_armour() so future doubling
## or per-hero modifiers can plug in at a single site (parallel to MinionInstance).
var armour: int = 0

## Buff/debuff container. BuffSystem.apply / sum_type / count_type / cleanse all
## read this via duck-typing. ARMOUR_BREAK lives here once PR2 lands.
var buffs: Array[BuffEntry] = []

static func create(side_id: String, max_hp: int) -> HeroState:
	var h := HeroState.new()
	h.side = side_id
	h.hp_max = max_hp
	h.hp = max_hp
	return h

## Central armour mutator. All hero armour gains/losses go through this so any
## future hero-specific doubling (a future "armoured boss" relic, etc.) plugs in
## at one site. Negative amounts are allowed (stripping); armour floors at 0.
func add_armour(amount: int) -> void:
	armour = maxi(0, armour + amount)
