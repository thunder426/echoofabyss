## AbyssSovereignPhase2Profile.gd
## AI profile for the Abyss Sovereign — Phase 2. Assigned by the phase-transition
## logic (not by GameManager), replacing AbyssSovereignProfile when P1 dies.
##
## Passives (P2): void_might + abyss_awakened.
##   - void_might: grant 1 random friendly minion +1 Critical Strike each turn.
##   - abyss_awakened: at the start of the enemy turn, ALL friendly minions
##     gain +1 Critical Strike.
##
## Strategy: abyss_awakened blankets the board in crit every turn, so the
## Sovereign wants to stay wide. Spark-cost spells (Sovereign's Decree,
## Throne's Command) are the payoff — face damage and crit multiplication.
## There is no dark_channeling in P2, so void_bolt is played on curve with
## no hold condition.
class_name AbyssSovereignPhase2Profile
extends VoidScoutProfile

## Sovereign's Decree stays high priority — hero damage + corruption.
func _spark_spell_priority(id: String) -> int:
	match id:
		"sovereigns_decree": return 4
		"rift_collapse":     return 3
		"void_pulse":        return 2
	return 0
