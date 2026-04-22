## AbyssSovereignProfile.gd
## AI profile for the Abyss Sovereign — the final boss (Act 4, Fight 15), Phase 1.
##
## Passives: void_might + abyssal_mandate + dark_channeling.
##   - void_might: grant 1 random friendly minion +1 Critical Strike each turn.
##   - abyssal_mandate: the player's resource growth choice echoes back as a
##     discount. Grow Essence → enemy minions cost -2 E this turn. Grow Mana
##     → enemy spells cost -2 M this turn.
##   - dark_channeling: when a damage spell is cast, consume 1 crit from a
##     random friendly minion to deal 1.5x spell damage.
##
## Strategy:
##   - Lean into whichever mandate discount is live. If essence-discount is
##     active, prioritise emptying minions from hand (the discount doesn't
##     carry over). If mana-discount is active, prioritise spells.
##   - dark_channeling still wants ≥1 crit on board when casting a damage
##     spell so the 1.5x triggers — hold void_bolt only until at least one
##     friendly minion has crit.
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
# Spell hold: void_bolt waits for dark_channeling to fire meaningfully
# ---------------------------------------------------------------------------

## Hold void_bolt until at least one friendly minion has crit so dark_channeling
## consumes something and applies the 1.5x multiplier. Without crits on board
## dark_channeling no-ops and the spell is cast at base damage.
func can_cast_spell(spell: SpellCardData) -> bool:
	if not super.can_cast_spell(spell):
		return false
	if spell.id == "void_bolt" and _board_crit_count() < 1:
		return false
	return true

func _board_crit_count() -> int:
	var count := 0
	for m: MinionInstance in agent.friendly_board:
		if m.has_critical_strike():
			count += 1
	return count
