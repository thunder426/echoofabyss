## FleshcraftPlayerProfile.gd
## Seris Fleshcraft-branch bot. Extends SerisPlayerProfile to override play
## ordering and target picking for the Fleshcraft deck.
##
## Key differences from generic Seris profile:
##   - Play cheap die-fodder Demons (Void Imp, Void Spawning) BEFORE Grafted
##     Fiends so Fleshbind banks Flesh before Flesh Infusion fires on the Fiend.
##   - Play Fiendish Pact only when it unlocks a Demon play that would otherwise
##     be unaffordable, or enables a second Demon play this turn.
##   - Dark Empowerment prefers highest-ATK Grafted Fiend (snowball the winner).
##   - Grafted Butcher sacrifice target: lowest-value non-Fiend Demon, preferring
##     EXHAUSTED minions so we don't waste a fresh minion's attack turn.
class_name FleshcraftPlayerProfile
extends SerisPlayerProfile

# ---------------------------------------------------------------------------
# Play phase
# ---------------------------------------------------------------------------

func play_phase() -> void:
	await _play_spells_by_id(["flux_siphon"])
	if not agent.is_alive(): return

	# Traps / Runes before minions so auras buff on-play.
	await _play_traps_pass()
	if not agent.is_alive(): return

	# Fiendish Pact — cast BEFORE minion plays if (and only if) it unlocks a
	# play we couldn't otherwise make. Gate lives in _maybe_fiendish_pact.
	await _maybe_fiendish_pact()
	if not agent.is_alive(): return

	# Flesh fuel first — cheap Demons (Void Imp, Void Spawning) die easily and
	# bank Flesh. Grafted Butcher goes after so its sacrifice has fodder.
	await _play_minions_by_id(["void_imp"])
	if not agent.is_alive(): return
	await _play_spells_by_id(["void_spawning"])
	if not agent.is_alive(): return

	# Grafted Fiends after Flesh is banked — Flesh Infusion (T0) spends 1 Flesh
	# for +200 ATK on entry. Need stock before the Fiend lands.
	await _play_minions_by_id(["grafted_fiend"])
	if not agent.is_alive(): return

	# Grafted Butcher last in the minion pack — only if AoE actually kills or
	# the enemy board is empty (play-for-body + face tempo). Against tanky /
	# on-death-swarm boards (F2 Corrupted Broodlings) the AoE trades our sac
	# target + whole-board chip (Void-Touched Imp backlash) for zero removal.
	if _butcher_is_worth_it():
		await _play_minions_by_id(["grafted_butcher"])
		if not agent.is_alive(): return

	# Remaining minions (Shadow Hound, Abyssal Brute).
	await _play_minions_pass()
	if not agent.is_alive(): return

	# Spells — Dark Empowerment targeting handled by pick_spell_target override.
	await _play_spells_pass()
	if not agent.is_alive(): return

	# Late catch-ups.
	await _play_minions_pass()

# ---------------------------------------------------------------------------
# Fiendish Pact gate
# ---------------------------------------------------------------------------

## Cast Fiendish Pact only when it enables a Demon play we can't make otherwise.
##   - SKIP if pending discount is already active (no stacking).
##   - SKIP if no Demons in hand (wasted draw).
##   - SKIP if every Demon in hand is already affordable AND we can't fit a
##     second Demon play this turn.
##   - CAST if any Demon in hand is unaffordable but becomes affordable at −2 E.
##   - CAST if we can afford one Demon now, and a second Demon becomes
##     affordable only after the discount (enables double-Fiend turns).
func _maybe_fiendish_pact() -> void:
	# Find a Pact in hand.
	var pact_inst: CardInstance = null
	for inst in agent.hand:
		if inst.card_data is SpellCardData and (inst.card_data as SpellCardData).id == "fiendish_pact":
			pact_inst = inst
			break
	if pact_inst == null:
		return
	var pact_cost: int = agent.effective_spell_cost(pact_inst.card_data as SpellCardData)
	if pact_cost > agent.mana:
		return
	# If pending already set, don't re-cast (can't stack).
	if agent.sim != null and int(agent.sim.get("_fiendish_pact_pending")) > 0:
		return

	# Collect Demons in hand.
	var demons: Array[MinionCardData] = []
	for inst in agent.hand:
		if inst.card_data is MinionCardData:
			var mc := inst.card_data as MinionCardData
			if mc.minion_type == Enums.MinionType.DEMON:
				demons.append(mc)
	if demons.is_empty():
		return

	# Simulate current affordability and "with −2 E" affordability.
	var essence_now: int = agent.essence
	var slots: int = agent.empty_slot_count()

	# Greedy pack: how many Demons can we play right now?
	var affordable_now: int = _count_affordable_demons(demons, essence_now, slots)
	# How many with the Pact discount active (applies to FIRST Demon played only)?
	var affordable_with_pact: int = _count_affordable_demons_with_discount(demons, essence_now, slots, 2)

	# Also spend 1 Mana to cast Pact — reduce mana available (doesn't affect
	# these Demons since they're 0-mana, but keep honest for future decks).
	# Pact-locked bodies gain net play iff affordable_with_pact > affordable_now.
	if affordable_with_pact > affordable_now:
		agent.mana -= pact_cost
		if not await agent.commit_play_spell(pact_inst, null):
			return

## Count playable Demons (slots + essence permitting) at current state.
func _count_affordable_demons(demons: Array[MinionCardData], essence: int, slots: int) -> int:
	var sorted := demons.duplicate()
	sorted.sort_custom(func(a: MinionCardData, b: MinionCardData) -> bool: return a.essence_cost < b.essence_cost)
	var played := 0
	var ess := essence
	for mc in sorted:
		if played >= slots:
			break
		if mc.essence_cost > ess:
			continue
		ess -= mc.essence_cost
		played += 1
	return played

## Count playable Demons if Pact discount (−N E) applies to the most expensive
## affordable-after-discount Demon first (maximises unlocked plays).
func _count_affordable_demons_with_discount(demons: Array[MinionCardData], essence: int, slots: int, discount: int) -> int:
	if demons.is_empty() or slots <= 0:
		return 0
	# Try applying discount to each Demon in turn, keep the best result.
	var best := 0
	for i in range(demons.size()):
		var played := 0
		var ess := essence
		# Play the discounted Demon first if affordable.
		var target: MinionCardData = demons[i]
		var target_cost: int = maxi(0, target.essence_cost - discount)
		if target_cost > ess or played >= slots:
			continue
		ess -= target_cost
		played += 1
		# Then pack the rest cheapest-first.
		var rest: Array[MinionCardData] = []
		for j in range(demons.size()):
			if j != i:
				rest.append(demons[j])
		rest.sort_custom(func(a: MinionCardData, b: MinionCardData) -> bool: return a.essence_cost < b.essence_cost)
		for mc in rest:
			if played >= slots:
				break
			if mc.essence_cost > ess:
				continue
			ess -= mc.essence_cost
			played += 1
		if played > best:
			best = played
	return best

# ---------------------------------------------------------------------------
# Target picking
# ---------------------------------------------------------------------------

## Grafted Butcher: sacrifice lowest-value friendly non-Fiend Demon, preferring
## EXHAUSTED (can't attack this turn anyway). Never sac a Grafted Fiend if
## anything else is available.
## Grafted Fiend: optional Grafting Ritual target (T1 talent). Pick smallest
## non-Fiend friendly Demon with stats ≤ 300/300 (don't downgrade buffed bodies).
## Dark Empowerment: handled in pick_spell_target (spell, not on-play).
func pick_on_play_target(mc: MinionCardData):
	if mc.id == "grafted_butcher":
		return _pick_butcher_sac_target()
	if mc.id == "grafted_fiend":
		return _pick_grafting_ritual_target()
	return super(mc)

## Grafting Ritual: pick the smallest friendly Demon to reroll into a fresh
## 300/300 Grafted Fiend. Skip Grafted Fiends (would lose kill stacks/buffs).
## Skip anything already bigger than 300/300 (downgrade = loss). Returns null
## if no worthwhile target — the Fiend still plays normally.
func _pick_grafting_ritual_target() -> MinionInstance:
	if agent.sim == null or not agent.sim._has_talent("grafting_ritual"):
		return null
	var best: MinionInstance = null
	var best_value: int = 9999
	for m in agent.friendly_board:
		var md := m.card_data as MinionCardData
		if md == null or md.minion_type != Enums.MinionType.DEMON:
			continue
		if "grafted_fiend" in md.minion_tags:
			continue
		if m.effective_atk() > 300 or m.current_health > 300:
			continue
		var value: int = m.effective_atk() + m.current_health
		if value < best_value:
			best_value = value
			best = m
	return best

func _pick_butcher_sac_target() -> MinionInstance:
	var pool: Array[MinionInstance] = agent.friendly_board
	if pool.is_empty():
		return null
	# Split: non-Fiend Demons first, then anything else, Fiends only as last resort.
	var non_fiend_demons: Array[MinionInstance] = []
	var non_demons: Array[MinionInstance] = []
	var fiends: Array[MinionInstance] = []
	for m in pool:
		var md := m.card_data as MinionCardData
		if md == null:
			continue
		if "grafted_fiend" in md.minion_tags:
			fiends.append(m)
		elif md.minion_type == Enums.MinionType.DEMON:
			non_fiend_demons.append(m)
		else:
			non_demons.append(m)

	var tiers: Array = [non_fiend_demons, non_demons, fiends]
	for tier in tiers:
		if tier.is_empty():
			continue
		# Prefer EXHAUSTED (can't attack anyway — zero-opportunity-cost sac).
		var exhausted: Array[MinionInstance] = []
		var can_attack: Array[MinionInstance] = []
		for m in tier:
			if m.state == Enums.MinionState.EXHAUSTED:
				exhausted.append(m)
			else:
				can_attack.append(m)
		var bucket := exhausted if not exhausted.is_empty() else can_attack
		# Within the bucket, pick lowest total stat (ATK + HP) — lowest-value body.
		var best: MinionInstance = bucket[0]
		for m in bucket:
			if _sac_value(m) < _sac_value(best):
				best = m
		return best
	return null

func _sac_value(m: MinionInstance) -> int:
	return m.effective_atk() + m.current_health

## Butcher is worth playing if:
##   - Enemy board is empty (pure body + face tempo — no AoE waste),
##   - OR AoE (200) kills at least one enemy minion (net removal),
##   - OR we have no friendly sac target (edge case — abort on sac anyway).
## Skip if enemy board is all tanky (200 AoE doesn't kill anything) AND we'd
## sacrifice a friendly for nothing.
func _butcher_is_worth_it() -> bool:
	if agent.friendly_board.is_empty():
		return false
	if agent.opponent_board.is_empty():
		return true
	const AOE_DMG: int = 200
	for m in agent.opponent_board:
		if m.current_health <= AOE_DMG:
			return true
	return false

## Dark Empowerment: prefer highest-ATK Grafted Fiend (snowball the already-
## scaled body). Fallback: highest-ATK friendly Demon. Final fallback: any.
func pick_spell_target(spell: SpellCardData):
	if spell.id == "dark_empowerment":
		var best: MinionInstance = null
		# Pass 1: Grafted Fiends only.
		for m in agent.friendly_board:
			var md := m.card_data as MinionCardData
			if md == null or not ("grafted_fiend" in md.minion_tags):
				continue
			if best == null or m.effective_atk() > best.effective_atk():
				best = m
		if best != null:
			return best
		# Pass 2: any friendly Demon.
		for m in agent.friendly_board:
			var md := m.card_data as MinionCardData
			if md == null or md.minion_type != Enums.MinionType.DEMON:
				continue
			if best == null or m.effective_atk() > best.effective_atk():
				best = m
		if best != null:
			return best
		# Pass 3: anything.
		for m in agent.friendly_board:
			if best == null or m.effective_atk() > best.effective_atk():
				best = m
		return best
	return super(spell)
