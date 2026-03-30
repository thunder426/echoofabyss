## RelicEffects.gd
## Executes relic activated effects. Works with both CombatScene (live) and
## SimState (headless) via duck-typing — same pattern as HardcodedEffects.
class_name RelicEffects
extends RefCounted

var _scene: Object

func setup(scene: Object) -> void:
	_scene = scene

## Execute a relic effect by its effect_id. Returns true if the effect fired.
func resolve(effect_id: String) -> bool:
	match effect_id:
		# ── Act 1 ────────────────────────────────────────────────────────────
		"relic_draw_2":
			_scene.turn_manager.draw_card()
			_scene.turn_manager.draw_card()
			_log("  Relic: Scout's Lantern — drew 2 cards.")
			return true

		"relic_add_void_imp":
			var imp_data: CardData = CardDatabase.get_card("void_imp")
			if imp_data:
				_scene.turn_manager.add_to_hand(imp_data)
				_log("  Relic: Imp Talisman — added a Void Imp to hand.")
			return true

		"relic_refill_mana":
			var tm = _scene.turn_manager
			tm.mana = mini(tm.mana + 2, tm.mana_max)
			tm.resources_changed.emit(tm.essence, tm.essence_max, tm.mana, tm.mana_max)
			_log("  Relic: Mana Shard — gained +2 Mana (now %d/%d)." % [tm.mana, tm.mana_max])
			return true

		"relic_hero_immune":
			_scene.set("_relic_hero_immune", true)
			_log("  Relic: Bone Shield — hero immune to damage this turn.")
			return true

		# ── Act 2 ────────────────────────────────────────────────────────────
		"relic_cast_plague":
			# Apply 1 Corruption to all enemies + 100 AoE damage
			for m in (_scene._opponent_board("player") as Array).duplicate():
				_scene._corrupt_minion(m)
			for m in (_scene._opponent_board("player") as Array).duplicate():
				_scene.combat_manager.apply_spell_damage(m, 100)
			_log("  Relic: Void Lens — Abyssal Plague cast!")
			return true

		"relic_summon_guardian":
			_scene._summon_token("relic_guardian", "player", 300, 300)
			# Grant Guard to the summoned token
			var board: Array = _scene.player_board
			if not board.is_empty():
				var guardian: MinionInstance = board[board.size() - 1]
				BuffSystem.apply(guardian, Enums.BuffType.GRANT_GUARD, 1, "relic_guardian")
				_scene._refresh_slot_for(guardian)
			_log("  Relic: Soul Anchor — summoned a 300/300 Guardian with Guard!")
			return true

		"relic_cost_reduction":
			_scene.set("_relic_cost_reduction", 2)
			_log("  Relic: Dark Mirror — next card costs 2 less.")
			return true

		"relic_execute":
			# Deal 500 damage to the highest-ATK enemy minion
			var target: MinionInstance = _pick_highest_atk_enemy()
			if target:
				_scene.combat_manager.apply_spell_damage(target, 500)
				_log("  Relic: Blood Chalice — dealt 500 damage to %s." % target.card_data.card_name)
			else:
				_log("  Relic: Blood Chalice — no target.")
			return true

		# ── Act 3 ────────────────────────────────────────────────────────────
		"relic_extra_turn":
			_scene.set("_relic_extra_turn", true)
			_log("  Relic: Void Hourglass — extra turn granted!")
			return true

		"relic_summon_demon":
			_scene._summon_token("void_demon", "player", 500, 500)
			# Grant Lifedrain
			var board: Array = _scene.player_board
			if not board.is_empty():
				var demon: MinionInstance = board[board.size() - 1]
				BuffSystem.apply(demon, Enums.BuffType.GRANT_LIFEDRAIN, 1, "relic_demon")
				_scene._refresh_slot_for(demon)
			_log("  Relic: Oblivion Seal — summoned a 500/500 Void Demon with Lifedrain!")
			return true

		"relic_mass_buff":
			for m in (_scene.player_board as Array):
				BuffSystem.apply(m, Enums.BuffType.TEMP_ATK, 200, "relic_crown")
				_scene._refresh_slot_for(m)
			_log("  Relic: Nether Crown — all friendly minions +200 ATK this turn!")
			return true

		"relic_copy_cards":
			# Add copies of 3 highest-cost cards from deck to hand
			var deck: Array = _scene.turn_manager.player_deck.duplicate()
			deck.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
				var ac: int = a.card_data.cost if not (a.card_data is MinionCardData) else (a.card_data as MinionCardData).essence_cost + (a.card_data as MinionCardData).mana_cost
				var bc: int = b.card_data.cost if not (b.card_data is MinionCardData) else (b.card_data as MinionCardData).essence_cost + (b.card_data as MinionCardData).mana_cost
				return ac > bc)
			var added := 0
			for inst in deck:
				if added >= 3:
					break
				_scene.turn_manager.add_to_hand(inst.card_data)
				added += 1
			_log("  Relic: Phantom Deck — added %d cards to hand." % added)
			return true

	return false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _pick_highest_atk_enemy() -> MinionInstance:
	var board: Array = _scene._opponent_board("player")
	if board.is_empty():
		return null
	var best: MinionInstance = board[0]
	for m in board:
		if (m as MinionInstance).effective_atk() > best.effective_atk():
			best = m
	return best

func _log(msg: String) -> void:
	if _scene.has_method("_log"):
		_scene._log(msg, 1)  # _LOG_PLAYER = 1
