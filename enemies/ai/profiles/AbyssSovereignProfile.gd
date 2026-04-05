## AbyssSovereignProfile.gd
## AI profile for the Abyss Sovereign — the final boss (Act 4, Fight 15).
##
## Passives: void_might + void_precision + dark_channeling.
##   - void_might: grant 1 random friendly minion +1 Critical Strike each turn.
##   - void_precision: when a crit is consumed during an attack, that minion
##     gains +200 ATK permanently (snowball engine).
##   - dark_channeling: when a damage spell is cast, consume 1 crit from a
##     random friendly minion to deal 1.5x spell damage.
##
## Strategy: The triple-passive engine makes minions grow via void_precision
## every time they land a crit attack. Crits consumed by dark_channeling
## are crits that DON'T trigger void_precision, so the AI holds damage
## spells (void_bolt) until there are surplus crits on the board (≥2
## minions with crit). Herald targets the highest-ATK minion to maximise
## the void_precision snowball (crit attack = 2x damage + 200 permanent ATK).
##
## Play order:
##   1. Regular spirits + heralds (crit distribution for precision engine)
##   2. Regular mana spells (void_bolt held until surplus crits available)
##   3. Spark-cost spells (Sovereign's Decree amplified by channeling)
##   4. Spark-cost minions (Bastion Colossus self-crits for engine)
##
## Resource growth:
##   Essence to 5 → Mana to 3 → Essence to 7
class_name AbyssSovereignProfile
extends VoidScoutProfile

## Sovereign's Decree is high priority — hero damage + corruption at 1.5x.
func _spark_spell_priority(id: String) -> int:
	match id:
		"sovereigns_decree": return 4
		"rift_collapse":     return 3
		"void_pulse":        return 2
	return 0

# ---------------------------------------------------------------------------
# Spell hold: void_bolt waits for dark_channeling value
# ---------------------------------------------------------------------------

## Hold void_bolt until ≥2 friendly minions have crit. This ensures the crit
## consumed by dark_channeling (1.5x) doesn't cannibalize the void_precision
## engine — at least one critted minion still attacks and grows this turn.
func can_cast_spell(spell: SpellCardData) -> bool:
	if not super.can_cast_spell(spell):
		return false
	if spell.id == "void_bolt" and _board_crit_count() < 2:
		return false
	return true

func _board_crit_count() -> int:
	var count := 0
	for m: MinionInstance in agent.friendly_board:
		if m.has_critical_strike():
			count += 1
	return count
