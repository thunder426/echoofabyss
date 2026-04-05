## VoidRitualistPrimeProfile.gd
## AI profile for the Void Ritualist Prime encounter (Act 4, Fight 13).
##
## Passive: void_might (shared) + dark_channeling (when the enemy casts a
## damage spell, consume 1 Critical Strike from a random friendly minion
## to deal 1.5x spell damage).
##
## Strategy: Spell-heavy deck. Play spirits and heralds first to stack crits,
## then cast damage spells (void_bolt, arcane_strike, sovereigns_decree)
## which get amplified by dark_channeling. Minion-first order ensures crits
## are on the board before damage spells fire.
##
## Play order:
##   1. Regular spirits + heralds (crits via herald + void_might)
##   2. Regular mana spells (void_bolt, arcane_strike — amplified by channeling)
##   3. Spark-cost spells (Sovereign's Decree for hero damage + corruption)
##   4. Spark-cost minions
##
## Resource growth:
##   Essence to 4 → Mana to 3 → Essence to 6 → Mana to 4
##   (mana-heavier than other Act 4 profiles — deck is spell-focused)
class_name VoidRitualistPrimeProfile
extends VoidScoutProfile

## Sovereign's Decree is high priority: 300 hero damage + corruption, amplified
## to 450 by dark_channeling if a crit is available.
func _spark_spell_priority(id: String) -> int:
	match id:
		"sovereigns_decree": return 4
		"rift_collapse":     return 3
		"void_pulse":        return 2
	return 0

# ---------------------------------------------------------------------------
# Resource growth — mana-heavier for spell-focused deck
# ---------------------------------------------------------------------------

func setup_resource_growth(sim_state: Object) -> void:
	sim_state.enemy_growth_override = func(turn: int) -> void:
		_ritualist_prime_growth(sim_state, turn)

func _ritualist_prime_growth(state: Object, turn: int) -> void:
	if turn <= 1:
		return
	var e: int = state.enemy_essence_max
	var m: int = state.enemy_mana_max
	if e + m >= 11:
		return
	if e < 4:
		state.enemy_essence_max += 1
	elif m < 3:
		state.enemy_mana_max += 1
	elif e < 6:
		state.enemy_essence_max += 1
	elif m < 4:
		state.enemy_mana_max += 1
	else:
		state.enemy_essence_max += 1
