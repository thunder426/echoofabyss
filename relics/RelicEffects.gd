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
				_scene._spell_dmg(m, 100)
			_log("  Relic: Void Lens — Abyssal Plague cast!")
			return true

		"relic_summon_guardian":
			_scene._summon_token("void_spark", "player", 200, 300)
			# Grant Guard to the summoned token
			var board: Array = _scene.player_board
			if not board.is_empty():
				var spark: MinionInstance = board[board.size() - 1]
				BuffSystem.apply(spark, Enums.BuffType.GRANT_GUARD, 1, "relic_guardian", false, false)
				_scene._refresh_slot_for(spark)
			_log("  Relic: Soul Anchor — summoned a 300/300 Void Spark with Guard!")
			return true

		"relic_cost_reduction":
			_scene.set("_relic_cost_reduction", 2)
			_log("  Relic: Dark Mirror — next card costs 2 Essence and 2 Mana less.")
			return true

		"relic_execute":
			# Deal 500 damage to the highest-ATK enemy minion, or enemy hero if no minions
			var target: MinionInstance = _pick_highest_atk_enemy()
			if target:
				_scene.combat_manager.apply_spell_damage(target, 500)
				_log("  Relic: Blood Chalice — dealt 500 damage to %s." % target.card_data.card_name)
			else:
				_scene.combat_manager.apply_hero_damage("enemy", 500, Enums.DamageType.SPELL)
				_log("  Relic: Blood Chalice — dealt 500 damage to enemy hero.")
			return true

		# ── Act 3 ────────────────────────────────────────────────────────────
		# Rebalanced to roughly Act-2 power — these were previously game-swinging.
		"relic_extra_turn":
			# Void Hourglass — +1 max Essence and +1 max Mana, respecting the combined cap.
			_scene.turn_manager.grow_essence_max(1)
			_scene.turn_manager.grow_mana_max(1)
			_log("  Relic: Void Hourglass — +1 max Essence and +1 max Mana.")
			return true

		"relic_summon_demon":
			# Oblivion Seal — place a random Rune on the battlefield AND deal 200 damage to a random enemy.
			_relic_place_random_rune()
			_relic_damage_random_enemy(200)
			_log("  Relic: Oblivion Seal — rune placed; 200 damage to random enemy.")
			return true

		"relic_mass_buff":
			# Nether Crown — permanent +100 ATK to all friendlies (was temporary +200).
			for m in (_scene.player_board as Array):
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "relic_crown", false, false)
				_scene._refresh_slot_for(m)
			_log("  Relic: Nether Crown — all friendly minions +100 ATK permanently.")
			return true

		"relic_copy_cards":
			# Phantom Deck — copy 2 random cards from hand back into hand.
			var hand: Array = (_scene.turn_manager.player_hand as Array).duplicate()
			if hand.is_empty():
				_log("  Relic: Phantom Deck — hand empty, no copies.")
				return true
			hand.shuffle()
			var added := 0
			for inst in hand:
				if added >= 2:
					break
				_scene.turn_manager.add_to_hand((inst as CardInstance).card_data)
				added += 1
			_log("  Relic: Phantom Deck — copied %d random cards from hand." % added)
			return true

	return false

# ---------------------------------------------------------------------------
# Act 3 helpers
# ---------------------------------------------------------------------------

## Pick a random player-available rune card id and place it on the player's trap slots.
## Silently skips if trap slots are full. Works in both live and sim — live routes through
## active_traps + _apply_rune_aura; sim uses the same field + sim-specific rune-aura path.
const _RELIC_RUNE_POOL: Array[String] = ["void_rune", "blood_rune", "dominion_rune", "shadow_rune"]
func _relic_place_random_rune() -> void:
	var rune_id: String = _RELIC_RUNE_POOL[randi() % _RELIC_RUNE_POOL.size()]
	var rune_card: CardData = CardDatabase.get_card(rune_id)
	if rune_card == null or not (rune_card is TrapCardData):
		return
	var rune := rune_card as TrapCardData
	var active: Array = _scene.active_traps
	# Live scene enforces trap-slot cap via trap_slot_panels; sim uses a fixed cap too.
	# Use scene.get to avoid a hard dependency on either shape.
	var cap: int = 3
	if _scene.get("trap_slot_panels") != null:
		cap = (_scene.trap_slot_panels as Array).size()
	if active.size() >= cap:
		return
	active.append(rune)
	# Wire the rune's aura so it actually fires on its trigger event.
	if _scene.has_method("_apply_rune_aura"):
		_scene._apply_rune_aura(rune)
	# Live scene has a UI refresh; sim no-ops.
	if _scene.has_method("_update_trap_display"):
		_scene._update_trap_display()
	# Fire ON_RUNE_PLACED so ritual checks see the new rune.
	if _scene.trigger_manager != null:
		var rune_ctx := EventContext.make(Enums.TriggerEvent.ON_RUNE_PLACED, "player")
		rune_ctx.card = rune
		_scene.trigger_manager.fire(rune_ctx)

## Damage a random enemy target (minion or hero, mixed pool).
func _relic_damage_random_enemy(amount: int) -> void:
	var pool: Array = []
	for m in (_scene.enemy_board as Array):
		if (m as MinionInstance).current_health > 0:
			pool.append(m)
	pool.append("enemy_hero")
	var pick = pool[randi() % pool.size()]
	if pick is MinionInstance:
		if _scene.has_method("_spell_dmg"):
			_scene._spell_dmg(pick, amount)
		else:
			_scene.combat_manager.apply_spell_damage(pick, amount)
	else:
		_scene.combat_manager.apply_hero_damage("enemy", amount, Enums.DamageType.SPELL)

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
