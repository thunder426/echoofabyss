## ProfileRegistry.gd
## The one table of AI profiles (LIVE_SIM_UNIFICATION_PLAN.md 2A.5), namespaced
## by side — "default" is DefaultProfile for the enemy and DefaultPlayerProfile
## for the player. Live's EnemyAI and the sim's CombatSim both build from it.
class_name ProfileRegistry
extends RefCounted

const ENEMY: Dictionary = {
	"default":              preload("res://enemies/ai/profiles/DefaultProfile.gd"),
	"feral_pack":           preload("res://enemies/ai/profiles/FeralPackProfile.gd"),
	"feral_pack_screech":   preload("res://enemies/ai/profiles/FeralPackScreechProfile.gd"),
	"corrupted_brood":      preload("res://enemies/ai/profiles/CorruptedBroodProfile.gd"),
	"corrupted_brood_aggro": preload("res://enemies/ai/profiles/CorruptedBroodAggroProfile.gd"),
	"corrupted_brood_rune": preload("res://enemies/ai/profiles/CorruptedBroodRuneProfile.gd"),
	"matriarch":            preload("res://enemies/ai/profiles/MatriarchProfile.gd"),
	"matriarch_aggro":      preload("res://enemies/ai/profiles/MatriarchAggroProfile.gd"),
	"matriarch_sac":        preload("res://enemies/ai/profiles/MatriarchSacProfile.gd"),
	"cultist_patrol":       preload("res://enemies/ai/profiles/CultistPatrolProfile.gd"),
	"cultist_patrol_tempo": preload("res://enemies/ai/profiles/CultistPatrolTempoProfile.gd"),
	"void_ritualist":       preload("res://enemies/ai/profiles/VoidRitualistProfile.gd"),
	"corrupted_handler":    preload("res://enemies/ai/profiles/CorruptedHandlerProfile.gd"),
	"rift_stalker":         preload("res://enemies/ai/profiles/RiftStalkerProfile.gd"),
	"void_aberration":      preload("res://enemies/ai/profiles/VoidAberrationProfile.gd"),
	"void_herald":          preload("res://enemies/ai/profiles/VoidHeraldProfile.gd"),
	# Act 4 — Void Castle
	"void_scout":           preload("res://enemies/ai/profiles/VoidScoutProfile.gd"),
	"void_warband":         preload("res://enemies/ai/profiles/VoidWarbandProfile.gd"),
	"void_captain":         preload("res://enemies/ai/profiles/VoidCaptainProfile.gd"),
	"void_ritualist_prime": preload("res://enemies/ai/profiles/VoidRitualistPrimeProfile.gd"),
	"void_champion":        preload("res://enemies/ai/profiles/VoidChampionProfile.gd"),
	"abyss_sovereign":      preload("res://enemies/ai/profiles/AbyssSovereignProfile.gd"),
	"abyss_sovereign_p2":   preload("res://enemies/ai/profiles/AbyssSovereignPhase2Profile.gd"),
	# Scored variants
	"scored":               preload("res://enemies/ai/profiles/ScoredDefaultProfile.gd"),
	"scored_feral_pack":    preload("res://enemies/ai/profiles/ScoredFeralPackProfile.gd"),
	"scored_corrupted_brood": preload("res://enemies/ai/profiles/ScoredCorruptedBroodProfile.gd"),
	"scored_matriarch":     preload("res://enemies/ai/profiles/ScoredMatriarchProfile.gd"),
}

## Player-side profiles — the sim's stand-ins for the human player.
const PLAYER: Dictionary = {
	"default":    preload("res://enemies/ai/profiles/DefaultPlayerProfile.gd"),
	"swarm":      preload("res://enemies/ai/profiles/SwarmPlayerProfile.gd"),
	"spell_burn": preload("res://enemies/ai/profiles/SpellBurnPlayerProfile.gd"),
	"rune_tempo": preload("res://enemies/ai/profiles/RuneTempoPlayerProfile.gd"),
	"scored":     preload("res://enemies/ai/profiles/ScoredDefaultProfile.gd"),
	"seris":      preload("res://enemies/ai/profiles/SerisPlayerProfile.gd"),
	"fleshcraft": preload("res://enemies/ai/profiles/FleshcraftPlayerProfile.gd"),
	"korrath":    preload("res://enemies/ai/profiles/KorrathPlayerProfile.gd"),
}

static func has_profile(side: String, id: String) -> bool:
	return (ENEMY if side == "enemy" else PLAYER).has(id)

## A fresh profile for `side`; unknown ids fall back to that side's "default".
static func make(side: String, id: String) -> CombatProfile:
	var table: Dictionary = ENEMY if side == "enemy" else PLAYER
	var script: GDScript = table.get(id, table["default"])
	return script.new()
