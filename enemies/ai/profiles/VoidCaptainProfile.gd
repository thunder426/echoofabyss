## VoidCaptainProfile.gd
## AI profile for the Void Captain encounter (Act 4, Fight 12).
##
## Passive: void_might (shared) + captain_orders (crit multiplier = 2.5x
## instead of the default 2.0x, making every Critical Strike 25% deadlier).
##
## Strategy: Stack as many crits as possible on high-ATK minions.
## Throne's Command (mass crit) is the highest-priority spark spell —
## at 2.5x multiplier, a board-wide crit is devastating.
## Herald targets the highest-ATK friendly to maximise crit damage value.
##
## Play order:
##   1. Regular spirits + heralds (board presence + crit distribution)
##   2. Regular mana spells
##   3. Spark-cost spells (Throne's Command first, then AoE/draw)
##   4. Spark-cost minions (Bastion Colossus self-crits)
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7
class_name VoidCaptainProfile
extends VoidScoutProfile

## Throne's Command is highest priority — mass crit at 2.5x multiplier.
func _spark_spell_priority(id: String) -> int:
	match id:
		"thrones_command":   return 5
		"rift_collapse":     return 3
		"void_pulse":        return 2
	return 0
