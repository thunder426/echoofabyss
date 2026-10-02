## RelicEffects.gd
## Executes relic activated effects on the typed CombatState, like
## HardcodedEffects.
class_name RelicEffects
extends RefCounted

## The combat state — every gameplay read and write.
var state: CombatState

func setup(p_state: CombatState) -> void:
	state = p_state

## Execute a relic effect by its effect_id. Returns true if the effect fired.
func resolve(effect_id: String) -> bool:
	match effect_id:
		# ── Act 1 ────────────────────────────────────────────────────────────
		"relic_draw_2":
			state.draw_cards("player", 2)
			_log("  Relic: Scout's Lantern — drew 2 cards.")
			return true

		"relic_add_void_imp":
			var imp_data: CardData = CardDatabase.get_card("void_imp")
			if imp_data:
				state.add_to_hand("player", imp_data)
				_log("  Relic: Imp Talisman — added a Void Imp to hand.")
			return true

		"relic_refill_mana":
			var st: CombatState = state
			st.gain_mana("player", 2)
			_log("  Relic: Mana Shard — gained +2 Mana (now %d/%d)." % [st.player_mana, st.player_mana_max])
			return true

		"relic_hero_immune":
			state._relic_hero_immune = true
			_log("  Relic: Bone Shield — hero immune to damage this turn.")
			return true

		# ── Act 2 ────────────────────────────────────────────────────────────
		"relic_cast_plague":
			# Apply 1 Corruption to all enemies + 100 AoE damage. Mirror the
			# abyssal_plague spell's school (VOID) since this relic literally casts it.
			for m in (state._opponent_board("player") as Array).duplicate():
				state._corrupt_minion(m)
			var plague_info := CombatManager.make_damage_info(0, Enums.DamageSource.SPELL, Enums.DamageSchool.VOID, null, "relic_void_lens_plague")
			for m in (state._opponent_board("player") as Array).duplicate():
				state._spell_dmg(m, 100, plague_info)
			_log("  Relic: Void Lens — Abyssal Plague cast!")
			return true

		"relic_summon_guardian":
			state._summon_token("void_spark", "player", 200, 300)
			# Grant Guard to the summoned token
			var board: Array = state.player_board
			if not board.is_empty():
				var spark: MinionInstance = board[board.size() - 1]
				BuffSystem.apply(spark, Enums.BuffType.GRANT_GUARD, 1, "relic_guardian", false, false)
				state._refresh_slot_for(spark)
			_log("  Relic: Soul Anchor — summoned a 200/300 Void Spark with Guard!")
			return true

		"relic_cost_reduction":
			state._relic_cost_reduction = 2
			_log("  Relic: Dark Mirror — next card costs 2 Essence and 2 Mana less.")
			return true

		# relic_execute (Blood Chalice) takes a target: CombatState.cmd_activate_relic resolves it.

		# ── Act 3 ────────────────────────────────────────────────────────────
		# Rebalanced to roughly Act-2 power — these were previously game-swinging.
		"relic_extra_turn":
			# Void Hourglass — +1 max Essence and +1 max Mana, respecting the combined cap.
			state.grow_essence_max("player", 1)
			state.grow_mana_max("player", 1)
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
			for m in (state.player_board as Array):
				BuffSystem.apply(m, Enums.BuffType.ATK_BONUS, 100, "relic_crown", false, false)
				state._refresh_slot_for(m)
			_log("  Relic: Nether Crown — all friendly minions +100 ATK permanently.")
			return true

		"relic_copy_cards":
			# Phantom Deck — copy 2 random cards from hand back into hand.
			var hand: Array[CardInstance] = state.player_hand.duplicate()
			if hand.is_empty():
				_log("  Relic: Phantom Deck — hand empty, no copies.")
				return true
			state.rng_shuffle(hand)
			var added := 0
			for inst in hand:
				if added >= 2:
					break
				state.add_to_hand("player", (inst as CardInstance).card_data)
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
	var rune_id: String = state.rng_pick(_RELIC_RUNE_POOL)
	var rune_card: CardData = CardDatabase.get_card(rune_id)
	if rune_card == null or not (rune_card is TrapCardData):
		return
	var rune := rune_card as TrapCardData
	var active: Array = state.active_traps
	if active.size() >= CombatState.TRAP_SLOTS_MAX:
		return
	active.append(rune)
	# Wire the rune's aura so it actually fires on its trigger event.
	state._apply_rune_aura(rune)
	# Journals TRAPS_CHANGED (the presenter refreshes the rune slots).
	state._update_trap_display()
	# Fire ON_RUNE_PLACED so ritual checks see the new rune.
	if state.trigger_manager != null:
		var rune_ctx := EventContext.make(Enums.TriggerEvent.ON_RUNE_PLACED, "player")
		rune_ctx.card = rune
		state.trigger_manager.fire(rune_ctx)

## Damage a random enemy target (minion or hero, mixed pool).
func _relic_damage_random_enemy(amount: int) -> void:
	var pool: Array = []
	for m in (state.enemy_board as Array):
		if (m as MinionInstance).current_health > 0:
			pool.append(m)
	pool.append("enemy_hero")
	var pick: Variant = state.rng_pick(pool)
	var info := CombatManager.make_damage_info(amount, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "relic_random_zap")
	if pick is MinionInstance:
		state._spell_dmg(pick, amount, info)
	else:
		state.combat_manager.apply_hero_damage("enemy", info)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _log(msg: String) -> void:
	state._log(msg, Enums.LogType.PLAYER)
