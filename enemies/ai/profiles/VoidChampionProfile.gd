## VoidChampionProfile.gd
## AI profile for the Void Champion encounter (Act 4, Fight 14).
##
## Passive: void_might (shared) + champion_duel (enemy minions with any
## Critical Strike stacks are granted SPELL_IMMUNE; when a crit is consumed,
## immunity is removed). This makes crit both an offensive AND defensive tool.
##
## Strategy: Spread crits across the board for maximum spell immunity coverage.
## Throne's Command (mass crit) is the top spark priority — it grants
## spell immunity to the entire board. Herald targets the highest-HP
## friendly WITHOUT crit, ensuring new minions get protection first.
## Bastion Colossus is exceptionally strong here: 600/800 Guard that
## self-grants 2 crit stacks = instant spell immunity on summon.
##
## Play order:
##   1. Regular spirits + heralds (crits via herald spread protection)
##   2. Regular mana spells
##   3. Spark-cost spells (Throne's Command = mass spell immunity)
##   4. Spark-cost minions (Bastion Colossus self-crits)
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7
class_name VoidChampionProfile
extends VoidScoutProfile

## Throne's Command = mass crit = mass spell immunity. Highest priority.
func _spark_spell_priority(id: String) -> int:
	match id:
		"thrones_command":   return 5
		"rift_collapse":     return 3
		"void_pulse":        return 2
	return 0

# ---------------------------------------------------------------------------
# Herald targeting: spread crit for spell immunity coverage
# ---------------------------------------------------------------------------

func pick_on_play_target(mc: MinionCardData):
	if mc.id == "sovereigns_herald":
		return _pick_champion_crit_target()
	return super.pick_on_play_target(mc)

## Target the highest-HP friendly minion WITHOUT crit (needs spell immunity).
## If all minions already have crit, fall back to highest ATK (extra stacks).
func _pick_champion_crit_target() -> MinionInstance:
	var best: MinionInstance = null
	for m: MinionInstance in agent.friendly_board:
		if m.has_critical_strike():
			continue
		if best == null or m.current_health > best.current_health:
			best = m
	if best != null:
		return best
	# All have crit — stack on highest ATK for more attack charges
	return _pick_highest_atk_friendly()
