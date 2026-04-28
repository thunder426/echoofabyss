## CombatState.gd
## Pure data layer shared by live combat (CombatScene) and headless simulation
## (SimState extends this). Holds combat-scoped state with no Node references,
## no UI coupling, no awaits.
##
## Migration in progress — fields are being moved here from CombatScene.gd in
## batches. See design/refactors/COMBAT_STATE_MANIFEST.md for the full plan.
class_name CombatState
extends RefCounted

const BOARD_MAX := 5

# ---------------------------------------------------------------------------
# Signals — emitted by state mutations so live UI can subscribe without state
# needing any Node references. Sim doesn't subscribe; signals are no-ops there.
# ---------------------------------------------------------------------------

## Emitted whenever player or enemy HP changes. `delta` is signed (+heal, -dmg, 0 if just a max change).
signal hp_changed(side: String, new_hp: int, max_hp: int, delta: int)

## Emitted whenever void mark stacks on a hero change. `side` is "player" or "enemy".
## (Currently only enemy_void_marks is tracked; player-side stays at 0.)
signal void_marks_changed(side: String, value: int)

## Emitted on every landed damage hit. Drives sim's dmg_log diagnostic and live
## combat's damage popups. `source` is "player"/"enemy" — the side that dealt
## damage. `target` is the side or minion-instance-id receiving. `school` uses
## Enums.DamageSchool.
signal damage_dealt(source: String, target: String, amount: int, school: int, was_crit: bool)

## Emitted whenever combat-relevant text should be logged. Live subscribes and
## forwards to CombatLog UI. Sim subscribes (when dmg_log_enabled) for diagnostic
## capture. `log_type` is one of CombatLog.LogType (TURN / PLAYER / ENEMY / DAMAGE / HEAL / TRAP / DEATH).
signal combat_log(msg: String, log_type: int)

## Emitted whenever a minion's stats / state change in a way that should
## refresh its on-board visual (HP, ATK, buff icons, exhausted/swift state).
## Live subscriber re-renders the slot; sim has no subscriber.
signal minion_stats_changed(minion: MinionInstance)

## Emitted right after a minion is added to its side's board (post-append).
## Symmetric with `minion_died`. `slot_index` is the slot it was placed in
## (or -1 if not yet assigned at emit time — token spawns occasionally append
## before placing). Currently no UI subscriber (visual placement already
## happens at the call sites); used by sim profiles + future relic handlers
## that want a state-level chokepoint instead of TriggerManager events.
signal minion_summoned(side: String, minion: MinionInstance, slot_index: int)

## Emitted whenever Seris's Flesh counter mutates. Live subscriber refreshes
## the pip bar + player hero panel resource bar; sim has no subscriber.
signal flesh_changed(value: int, max_value: int)

## Emitted whenever Seris's Forge Counter mutates. Live subscriber refreshes
## the pip bar + player hero panel resource bar; sim has no subscriber.
signal forge_changed(value: int, threshold: int)

## Emitted whenever the trap/rune slots for a side change (placed, fired,
## expired, modified). Live subscriber re-renders the trap/rune slot panel for
## that side. `side` is "player" or "enemy".
signal traps_changed(side: String)

## Emitted whenever the active global environment changes. Live subscriber
## re-renders the environment card display. `env` may be null (cleared).
signal environment_changed(env: EnvironmentCardData)

## Emitted by `_spell_dmg` after damage is applied to a minion target. Live
## combat subscribes to spawn the damage popup + slot flash; sim has no
## subscriber. `damage` is the pre-bonus amount the call site passed (not
## including _player_spell_damage_bonus added inside _spell_dmg).
signal spell_damage_dealt(target: MinionInstance, damage: int)

## Emitted after a minion has been removed from its side's board (post-erase).
## `slot_index` is the slot it occupied (or -1 if not found). External
## subscribers use this rather than CombatManager.minion_vanished so the data
## layer stays the source of truth. Live combat still subscribes to CombatManager
## directly for animation timing; this signal is for logic listeners.
signal minion_died(side: String, minion: MinionInstance, slot_index: int)

## Scene facade for `EffectContext.scene`. CombatScene assigns itself here in
## _ready so EffectResolver and HardcodedEffects can route ctx.scene calls
## through scene's VFX-enriched wrappers (_deal_void_bolt_damage projectile,
## _corrupt_minion VFX, _fire_ritual rune-fire VFX, etc.). Sim leaves this null
## and `_get_scene_facade()` falls back to `self` — SimState extends CombatState
## and acts as its own scene facade (no VFX, just data).
##
## Why this exists: P4B inverted spell flow moved `cast_player_targeted_spell`
## from CombatScene to CombatState. The old code built EffectContext with
## `EffectContext.make(self, ...)` where self was CombatScene; the new state
## version's `self` is the bare data layer with no VFX wrappers. Without this
## facade, ctx.scene.X calls hit state's no-VFX versions and visuals silently
## drop (Void Bolt projectile, Void Rune fire, Corruption apply, etc.).
var _scene_facade: Object = null

## Returns the scene facade for EffectContext construction. Live combat returns
## CombatScene (set via `_scene_facade`); sim falls through to self (SimState).
func _get_scene_facade() -> Object:
	return _scene_facade if _scene_facade != null else self

## Logging convenience — handlers, effects, and combat code call `state._log(msg)`
## without needing a scene reference or knowing whether a UI exists. Signal
## subscribers (CombatScene's _on_state_combat_log) forward to the visual log;
## sim has no subscriber so this is a no-op there.
func _log(msg: String, log_type: int = 1) -> void:  # default = CombatLog.LogType.PLAYER
	combat_log.emit(msg, log_type)

## Refresh a minion's slot visual. Handlers and effects call
## `ctx.scene._refresh_slot_for(m)`; the scene's facade calls this method,
## which emits the signal. Live subscribers re-render; sim has no subscribers
## so the call is a no-op (replaces SimState's old `pass` duck-type stub).
func _refresh_slot_for(minion: MinionInstance) -> void:
	if minion != null:
		minion_stats_changed.emit(minion)

## Trap/rune display refresh hook for a specific side ("player"/"enemy").
## Scene's `_update_trap_display_for(owner)` facade delegates here; subscribers
## call `trap_env_display.update_traps_for(side)`. Sim has no subscriber → no-op
## (replaces the old SimState pass-stub).
func _update_trap_display_for(owner: String) -> void:
	traps_changed.emit(owner)

## Convenience: refresh the player-side trap display.
func _update_trap_display() -> void:
	traps_changed.emit("player")

## Convenience: refresh the enemy-side trap display.
func _update_enemy_trap_display() -> void:
	traps_changed.emit("enemy")

## Environment-card display refresh hook. Subscribers re-render the env panel.
func _update_environment_display() -> void:
	environment_changed.emit(active_environment)

# ---------------------------------------------------------------------------
# Owner-aware board helpers — pure data, no UI.
# ---------------------------------------------------------------------------

## Return the board belonging to the given owner ("player" or "enemy").
func _friendly_board(owner: String) -> Array[MinionInstance]:
	return player_board if owner == "player" else enemy_board

## Return the board belonging to the opponent of the given owner.
func _opponent_board(owner: String) -> Array[MinionInstance]:
	return enemy_board if owner == "player" else player_board

## Flip "player" ↔ "enemy".
func _opponent_of(owner: String) -> String:
	return "enemy" if owner == "player" else "player"

## Return the board slots belonging to the given owner.
func _friendly_slots(owner: String) -> Array:
	return player_slots if owner == "player" else enemy_slots

## Count minions of a specific type on the friendly board.
func _count_type_on_board(type: int, owner: String) -> int:
	var count := 0
	for m in _friendly_board(owner):
		if (m as MinionInstance).card_data.minion_type == type:
			count += 1
	return count

## True if the minion's card_data has the given tag.
func _minion_has_tag(m: MinionInstance, tag: String) -> bool:
	if m == null:
		return false
	if m.card_data is MinionCardData:
		return tag in (m.card_data as MinionCardData).minion_tags
	return false

## True if the CardData (from hand/deck/ctx.card) has the given tag.
## Returns false for non-minion cards.
func _card_has_tag(card: CardData, tag: String) -> bool:
	if card is MinionCardData:
		return tag in (card as MinionCardData).minion_tags
	return false

## Returns whether the player has the named talent active.
## Sim sets `talents` directly via CombatSim. Live combat populates `talents`
## from GameManager.unlocked_talents in CombatScene._ready.
func _has_talent(id: String) -> bool:
	return id in talents

## Side-aware lookup that applies talent_overrides + CardModRules for the
## relevant side. Use whenever combat code constructs new CardInstances mid-fight
## (token summons, copy-to-hand, draw helpers, deck/hand init). Static lookups
## (UI, deckbuilder, tests) keep using CardDatabase.get_card() directly.
##
## Player side reads `talents` and `hero_passives`. Enemy side reads
## `enemy_passives`. Each rule's `when` clause picks the right array.
func _card_for(side: String, id: String) -> CardData:
	return CardDatabase.get_card_for_combat(id, _card_ctx(side))

## Build the override-evaluation context for the given side. Centralized so the
## per-card and batch lookups produce identical ctx dicts (cache hits depend on it).
## Reads from both _active_enemy_passives (live) and enemy_passives (sim mirror) —
## whichever is populated. They're kept in sync so either source is valid.
func _card_ctx(side: String) -> Dictionary:
	var enemy: Array[String] = _active_enemy_passives if not _active_enemy_passives.is_empty() else enemy_passives
	return {
		"side":           side,
		"talents":        talents if side == "player" else [],
		"hero_passives":  hero_passives if side == "player" else [],
		"enemy_passives": enemy,
	}

## Random minion from a board array, or null if empty.
func _find_random_minion(board: Array) -> MinionInstance:
	if board.is_empty():
		return null
	return board[randi() % board.size()]

# ---------------------------------------------------------------------------
# Pure state mutators — no UI side effects.
# ---------------------------------------------------------------------------

## Add `amount` Void Mark stacks to the enemy hero. Property setter on
## enemy_void_marks emits void_marks_changed; live UI subscribes. Logs via
## the combat_log signal; scene's wrapper additionally spawns the apply VFX.
func _apply_void_mark(amount: int) -> void:
	if amount <= 0:
		return
	enemy_void_marks += amount
	_log("  Void Mark x%d applied! (total: %d)" % [amount, enemy_void_marks], 1)  # CombatLog.LogType.PLAYER = 1

## Remove rune aura handlers, auto-strip source_tag buffs declared in aura_effect_steps,
## then run any bespoke aura_on_remove_steps. Symmetric across scene/sim.
## `owner` defaults to "player" (scene caller).
func _remove_rune_aura(rune: TrapCardData, owner: String = "player") -> void:
	for i in _rune_aura_handlers.size():
		if _rune_aura_handlers[i].rune_id == rune.id:
			for entry in _rune_aura_handlers[i].entries:
				trigger_manager.unregister(entry.event, entry.handler)
			_rune_aura_handlers.remove_at(i)
			break
	# Auto-cleanup: strip one layer of every source_tag declared in aura_effect_steps
	# from both boards. One rune copy = one layer stripped, mirroring the prior bespoke
	# Dominion teardown. No-op for runes whose aura steps don't carry a source_tag.
	for tag in _harvest_aura_source_tags(rune):
		for m in player_board:
			BuffSystem.remove_one_source(m, tag)
			_refresh_slot_for(m)
		for m in enemy_board:
			BuffSystem.remove_one_source(m, tag)
			_refresh_slot_for(m)
	if not rune.aura_on_remove_steps.is_empty():
		var ctx := EffectContext.make(_get_scene_facade(), owner)
		EffectResolver.run(rune.aura_on_remove_steps, ctx)

## Collect distinct source_tag values from a rune's aura_effect_steps. Steps may be
## stored as Dictionaries (CardDatabase data form) or EffectStep objects.
func _harvest_aura_source_tags(rune: TrapCardData) -> Array[String]:
	var tags: Array[String] = []
	for step in rune.aura_effect_steps:
		var tag: String = ""
		if step is Dictionary:
			tag = step.get("source_tag", "")
		elif step is EffectStep:
			tag = (step as EffectStep).source_tag
		if tag != "" and not tags.has(tag):
			tags.append(tag)
	return tags

## Unregister all environment-ritual handlers (when env is replaced/cleared).
func _unregister_env_rituals() -> void:
	for h in _env_ritual_handlers:
		trigger_manager.unregister(Enums.TriggerEvent.ON_RUNE_PLACED, h)
		trigger_manager.unregister(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, h)
	_env_ritual_handlers.clear()

## Returns the runic_attunement-modified rune aura multiplier (1 default, 2 with talent).
func _rune_aura_multiplier() -> int:
	return rune_aura_multiplier

# ---------------------------------------------------------------------------
# Seris ability suite — pure logic mutators shared by scene & sim.
# ---------------------------------------------------------------------------

## Seris — Flesh gain primitive. Logs and clamps to player_flesh_max. Emits
## flesh_changed via the property setter. Live combat's Flesh.gd class also
## calls this path; sim calls it directly. Returns the amount actually gained.
func _gain_flesh(amount: int = 1) -> int:
	if amount <= 0:
		return 0
	var before: int = player_flesh
	player_flesh = min(player_flesh + amount, player_flesh_max)
	var gained := player_flesh - before
	if gained > 0:
		_log("  Flesh +%d (%d/%d)" % [gained, player_flesh, player_flesh_max], 1)
	return gained

## Seris — Flesh spend primitive. Returns true on success (sufficient Flesh).
## Logs, mutates state, fires _on_flesh_spent (which handles Flesh Bond card draw).
func _spend_flesh(amount: int) -> bool:
	if amount <= 0 or player_flesh < amount:
		return false
	player_flesh -= amount
	_log("  Flesh -%d (%d/%d)" % [amount, player_flesh, player_flesh_max], 1)
	_on_flesh_spent(amount)
	return true

## Seris — post-spend hook. Flesh Bond aura (Abyssal Forge talent) draws a card
## per spend (one draw per spend event regardless of amount). Runs on both
## scene and sim — both have access to a `turn_manager` that supports draw_card.
func _on_flesh_spent(_amount: int) -> void:
	var has_flesh_bond := false
	for m in player_board:
		if "flesh_bond" in m.aura_tags:
			has_flesh_bond = true
			break
	if not has_flesh_bond:
		return
	if turn_manager != null:
		turn_manager.draw_card()
		_log("  Flesh Bond: drew a card.", 1)

## Seris Starter — Fiendish Pact discount peek for a single Demon play.
## Returns the Essence discount to subtract from this play's cost (0 if N/A).
## Does NOT consume the pending — call _consume_fiendish_pact_discount after pay.
func _peek_fiendish_pact_discount(mc: MinionCardData) -> int:
	if _fiendish_pact_pending <= 0:
		return 0
	if mc == null or mc.minion_type != Enums.MinionType.DEMON:
		return 0
	return mini(_fiendish_pact_pending, mc.essence_cost)

## Seris — called at the start of each player spell cast. Computes the Void
## Amplification damage bonus from friendly-Demon Corruption stacks at this moment
## and stores it in _player_spell_damage_bonus. Re-entrant: only the outer cast
## (_spell_cast_depth==1) recomputes; nested recasts use the outer bonus.
func _pre_player_spell_cast(_spell: SpellCardData) -> void:
	_spell_cast_depth += 1
	if _spell_cast_depth > 1:
		return
	if _has_talent("void_amplification"):
		var total_stacks: int = 0
		for m in player_board:
			if (m.card_data as MinionCardData).minion_type == Enums.MinionType.DEMON:
				total_stacks += BuffSystem.count_type(m, Enums.BuffType.CORRUPTION)
		_player_spell_damage_bonus = total_stacks * 50
	else:
		_player_spell_damage_bonus = 0

## Legacy effect_id resolution path. No spell currently sets effect_id
## directly (all use declarative effect_steps), but the Void Resonance recast
## still falls back here for completeness.
func _resolve_spell_effect(effect_id: String, target: MinionInstance, owner: String = "player") -> void:
	if _hardcoded == null:
		return
	var ctx := EffectContext.make(_get_scene_facade(), owner)
	ctx.chosen_target = target
	_hardcoded.resolve(effect_id, ctx)

## Seris — called after a player spell's effect resolves. Handles the Void
## Resonance (Seris capstone) double-cast: if the player still has ≥5 Flesh
## AFTER any cost the spell itself deducted, consume all 5 and recursively
## resolve the spell's effect once more targeting the same minion.
func _post_player_spell_cast(spell: SpellCardData, target: MinionInstance) -> void:
	if _spell_cast_depth == 1 \
			and _has_talent("void_resonance_seris") \
			and player_flesh >= 5 \
			and not _double_cast_in_progress:
		_double_cast_in_progress = true
		if _spend_flesh(5):
			_log("  Void Resonance: recasting %s." % spell.card_name, 1)  # PLAYER
			# If the original target is dead / gone, per design the recast fizzles but Flesh is still spent.
			if target == null or (is_instance_valid(target) and target.current_health > 0):
				if not spell.effect_steps.is_empty():
					var ctx := EffectContext.make(_get_scene_facade(), "player")
					ctx.chosen_target = target
					ctx.source_card_id = spell.id
					EffectResolver.run(spell.effect_steps, ctx)
				else:
					_resolve_spell_effect(spell.effect_id, target)
		_double_cast_in_progress = false
	_spell_cast_depth = maxi(0, _spell_cast_depth - 1)
	if _spell_cast_depth == 0:
		_player_spell_damage_bonus = 0

## Compose the full player spell cast: pre-cast bookkeeping, effect resolution,
## post-cast bookkeeping (Void Resonance recast). Called by CombatScene's spell
## callsites at vfx impact_hit. `target` may be null for AoE / untargeted spells.
## The trigger fire (ON_PLAYER_SPELL_CAST) is left to the caller since live
## combat fires it at different points per callsite (inside resolve_damage for
## AoE; after VFX completes for targeted) — preserving existing timing.
func cast_player_targeted_spell(spell: SpellCardData, target: MinionInstance) -> void:
	_pre_player_spell_cast(spell)
	if not spell.effect_steps.is_empty():
		var ctx := EffectContext.make(_get_scene_facade(), "player")
		ctx.chosen_target = target
		ctx.source_card_id = spell.id
		EffectResolver.run(spell.effect_steps, ctx)
	else:
		_resolve_spell_effect(spell.effect_id, target)
	_post_player_spell_cast(spell, target)

## Compose a player hero-targeted spell cast (the spell hits the enemy hero
## directly). Bypasses EffectResolver: damage is summed from DAMAGE_MINION
## steps with their conditions evaluated, plus _player_spell_damage_bonus.
## The first contributing step's damage_school wins. _post_player_spell_cast
## still runs so Void Resonance recast applies.
func cast_player_hero_spell(spell: SpellCardData) -> void:
	_pre_player_spell_cast(spell)
	var base_dmg: int = 0
	var school: int = Enums.DamageSchool.NONE
	for step in spell.effect_steps:
		var s := EffectStep.from_dict(step) if step is Dictionary else step as EffectStep
		if s and s.effect_type == EffectStep.EffectType.DAMAGE_MINION:
			var ctx := EffectContext.make(_get_scene_facade(), "player")
			if ConditionResolver.check_all(s.conditions, ctx, null):
				base_dmg += s.amount
				if s.bonus_amount != 0 and not s.bonus_conditions.is_empty():
					if ConditionResolver.check_all(s.bonus_conditions, ctx, null):
						base_dmg += s.bonus_amount
				if school == Enums.DamageSchool.NONE:
					school = s.damage_school
	var total: int = base_dmg + _player_spell_damage_bonus
	_log("  %s: %d Void damage to enemy hero." % [spell.card_name, total], 1)  # PLAYER
	combat_manager.apply_hero_damage("enemy",
			CombatManager.make_damage_info(total, Enums.DamageSource.SPELL, school, null, spell.id))
	_post_player_spell_cast(spell, null)

## Entry point for EffectResolver HARDCODED steps — delegates to the
## HardcodedEffects resolver. Both scene and sim assign _hardcoded in their
## setup; this method works uniformly across both surfaces.
func _resolve_hardcoded(id: String, ctx: EffectContext) -> void:
	if _hardcoded == null:
		return
	_hardcoded.resolve(id, ctx)

## Optional VFX-aware summon delegate. Live combat assigns scene's VFX-rich
## `_summon_token` here in CombatScene._ready so EffectResolver SUMMON steps
## fired through state-created EffectContexts (e.g. cast_player_targeted_spell
## resolving a spell with effect_steps that include SUMMON) still get the
## proper sigil/champion VFX. Sim leaves it unset and falls through to pure
## logic in `_summon_token` below.
var _summon_delegate: Callable = Callable()

## Generic token summon used by EffectResolver SUMMON steps and by sim profiles.
## Routes through `_summon_delegate` when set (live combat with VFX); otherwise
## runs the pure-logic path (sim, headless tests).
func _summon_token(card_id: String, owner: String, token_atk: int = 0, token_hp: int = 0, token_shield: int = 0) -> void:
	if _summon_delegate.is_valid():
		_summon_delegate.call(card_id, owner, token_atk, token_hp, token_shield)
		return
	_summon_token_pure(card_id, owner, token_atk, token_hp, token_shield)

## Pure-logic summon: find an empty slot, instantiate the token (with optional
## stat overrides), append + place, emit `minion_summoned`, fire the
## ON_*_MINION_SUMMONED trigger. No VFX, no async. Sim calls this directly
## via inheritance; live combat reaches it only when scene's VFX-rich
## `_summon_token` is unavailable (shouldn't normally happen).
func _summon_token_pure(card_id: String, owner: String, token_atk: int = 0, token_hp: int = 0, token_shield: int = 0) -> void:
	# Combat-time lookup so clan rules / overrides apply to tokens summoned
	# mid-fight in sim. Mirrors CombatScene._summon_token's _card_for migration.
	var base := _card_for(owner, card_id)
	if base == null or not (base is MinionCardData):
		return
	var board := player_board if owner == "player" else enemy_board
	var slots := player_slots if owner == "player" else enemy_slots
	var slot: BoardSlot = null
	for s in slots:
		if s.is_empty():
			slot = s
			break
	if slot == null:
		return  # board full
	var mc := (base as MinionCardData).duplicate() as MinionCardData
	if token_atk > 0:    mc.atk        = token_atk
	if token_hp > 0:     mc.health     = token_hp
	if token_shield > 0: mc.shield_max = token_shield
	var instance := MinionInstance.create(mc, owner)
	board.append(instance)
	slot.place_minion(instance)
	minion_summoned.emit(owner, instance, slot.index)
	if trigger_manager != null:
		var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
		var ctx := EventContext.make(event, owner)
		ctx.minion = instance
		ctx.card   = mc
		trigger_manager.fire(ctx)

## Apply spell damage to a single minion target. Adds _player_spell_damage_bonus
## (Void Amplification — scaled per friendly Demon Corruption stack at cast
## time) to the call-site's amount, then routes through combat_manager to
## apply damage. Emits `spell_damage_dealt` so live combat can spawn the flash
## + damage popup; sim has no subscriber and so just applies the damage.
##
## Both callers pass the PRE-bonus damage; the bonus is added once here.
func _spell_dmg(target: MinionInstance, amount: int, info: Dictionary = {}) -> void:
	if target == null:
		return
	var total: int = amount + _player_spell_damage_bonus
	if info.is_empty():
		info = CombatManager.make_damage_info(total, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE)
	else:
		info = info.duplicate()
		info["amount"] = total
	# Emit BEFORE applying damage so the live subscriber can resolve the
	# minion's slot while it's still occupied. If we emit after, lethal hits
	# (and any kill chain that clears the slot) cause _find_slot_for(target)
	# to return null and the popup is silently dropped — matches the OLD
	# CombatScene._spell_dmg pattern of capturing the slot before damage.
	spell_damage_dealt.emit(target, amount)
	combat_manager.apply_damage_to_minion(target, info)

## Seris — tick the Forge Counter by `amount`. Logs the new value and returns
## true if the counter has reached threshold (caller is responsible for
## triggering the auto-summon and calling `_forge_counter_reset`). UI updates
## via the forge_changed signal that the property setter emits.
func _forge_counter_tick(amount: int = 1) -> bool:
	if amount <= 0:
		return false
	forge_counter += amount
	_log("  Forge Counter +%d (%d/%d)" % [amount, forge_counter, forge_counter_threshold], 1)  # PLAYER
	return forge_counter >= forge_counter_threshold

## Seris — reset the Forge Counter to 0 (after a Forged Demon auto-summon).
func _forge_counter_reset() -> void:
	forge_counter = 0

## Public Forge Counter gain for declarative GAIN_FORGE_COUNTER steps and any
## passive sources. Wraps tick + auto-summon + reset so callers don't repeat
## the threshold logic. No-op if Soul Forge is not active. Returns true if at
## least one Forged Demon was summoned this call.
func _gain_forge_counter(amount: int = 1) -> bool:
	if amount <= 0 or not _has_talent("soul_forge"):
		return false
	var summoned := false
	# Loop in case amount > threshold (e.g. Forgeborn Tyrant's +3 with threshold 2 → multi-summon).
	while amount > 0:
		var step := mini(amount, forge_counter_threshold)
		amount -= step
		if _forge_counter_tick(step):
			_log("  Soul Forge: threshold reached.", 1)
			_summon_forged_demon()
			_forge_counter_reset()
			summoned = true
	return summoned

## Seris/Abyssal Forge — auras that may be granted to a freshly-summoned
## Forged Demon. Default: one random aura. With ≥5 Flesh: spend all 5 and
## grant all three.
const _FORGED_DEMON_AURAS: Array[String] = ["void_growth", "void_pulse", "flesh_bond"]

## Grant Abyssal Forge auras to the given Forged Demon. With ≥5 Flesh:
## spend all 5 and grant all three; otherwise grant a single random aura.
func _grant_forged_demon_auras(forged: MinionInstance) -> void:
	if forged == null:
		return
	if player_flesh >= 5 and _spend_flesh(5):
		forged.aura_tags = _FORGED_DEMON_AURAS.duplicate()
		_log("  Abyssal Forge: Forged Demon granted all three auras.", 1)  # PLAYER
	else:
		var roll: String = _FORGED_DEMON_AURAS[randi() % _FORGED_DEMON_AURAS.size()]
		forged.aura_tags = [roll]
		_log("  Abyssal Forge: Forged Demon granted %s." % roll, 1)

## Summon a Forged Demon and, if Abyssal Forge is active, grant aura(s).
## Used by Soul Forge counter threshold + sim's _gain_forge_counter.
func _summon_forged_demon() -> void:
	_summon_token("forged_demon", "player")
	# Find the freshly summoned Forged Demon (last entry on the player board that matches).
	var forged: MinionInstance = null
	for i in range(player_board.size() - 1, -1, -1):
		var m: MinionInstance = player_board[i]
		if m.card_data.id == "forged_demon":
			forged = m
			break
	if forged == null:
		return  # board full; summon failed silently per design
	if _has_talent("abyssal_forge"):
		_grant_forged_demon_auras(forged)

## Seris — Soul Forge sacrifice tick. Called from CombatHandlers /
## SerisPlayerProfile when a friendly Demon is sacrificed. Handles two
## talent-gated reactions: Fiend Offering (sacrificed Grafted Fiend → spend
## 2 Flesh → Lesser Demon) and Soul Forge counter tick → auto-summon Forged
## Demon at threshold.
func _on_demon_sacrificed(minion: MinionInstance, _source_tag: String) -> void:
	if minion == null or minion.owner != "player":
		return
	if not (minion.card_data is MinionCardData):
		return
	if (minion.card_data as MinionCardData).minion_type != Enums.MinionType.DEMON:
		return
	# Fiend Offering — sacrificed a Grafted Fiend, spend 2 Flesh → Lesser Demon.
	# Auto-spends when affordable (no opt-out UI yet); board-full still consumes Flesh.
	if _has_talent("fiend_offering") and "grafted_fiend" in (minion.card_data as MinionCardData).minion_tags:
		if _spend_flesh(2):
			_log("  Fiend Offering: +1 Lesser Demon attempt.", 1)
			_summon_token("lesser_demon", "player")
	if not _has_talent("soul_forge"):
		return
	# Forge Counter ticks; at threshold auto-summon Forged Demon and reset.
	if _forge_counter_tick(1):
		_log("  Soul Forge: threshold reached.", 1)
		_summon_forged_demon()
		_forge_counter_reset()

## Seris — Soul Forge activated ability. Spend 3 Flesh → summon Grafted Fiend.
## Returns true if a summon attempt was made (Flesh was spent). No-op if the
## talent isn't active, the player can't afford it, or the board is full.
## (Board-full path consumes nothing — contrast with sacrifice auto-summons,
## where Flesh is still spent on board-full.)
func _soul_forge_activate() -> bool:
	if not _has_talent("soul_forge"):
		return false
	if player_flesh < 3:
		return false
	# Check for an empty slot before spending — active uses should not waste Flesh.
	var has_slot := false
	for slot in player_slots:
		if slot.is_empty():
			has_slot = true
			break
	if not has_slot:
		_log("  Soul Forge: board full — no fiend summoned.", 1)
		return false
	if not _spend_flesh(3):
		return false
	_log("  Soul Forge: summoning Grafted Fiend.", 1)
	_summon_token("grafted_fiend", "player")
	return true

## Register a rune's aura handlers with the trigger manager and run any
## on-place steps. Stores Array[{event, handler}] per rune in _rune_aura_handlers
## so _remove_rune_aura can unregister symmetrically. `owner` decides which
## TriggerEvent to subscribe to (mirror for enemy side).
func _apply_rune_aura(rune: TrapCardData, owner: String = "player") -> void:
	if trigger_manager == null:
		return
	var entries: Array = []
	# Primary handler — mirror trigger for enemy side
	if rune.aura_trigger >= 0 and not rune.aura_effect_steps.is_empty():
		var trigger: int = rune.aura_trigger if owner == "player" else Enums.mirror_trigger(rune.aura_trigger as Enums.TriggerEvent)
		var h := func(event_ctx: EventContext):
			var ctx := EffectContext.make(_get_scene_facade(), owner)
			ctx.trigger_minion = event_ctx.minion
			ctx.from_rune = true
			ctx.source_rune = rune
			EffectResolver.run(rune.aura_effect_steps, ctx)
		trigger_manager.register(trigger, h, 20)
		entries.append({event = trigger, handler = h})
		# Extra handler — same effect_steps, fires on a second event (e.g. sacrifice in
		# addition to death so Blood/Soul Rune react to ON LEAVE removals).
		if rune.aura_extra_trigger >= 0:
			var extra_trigger: int = rune.aura_extra_trigger if owner == "player" else Enums.mirror_trigger(rune.aura_extra_trigger as Enums.TriggerEvent)
			trigger_manager.register(extra_trigger, h, 20)
			entries.append({event = extra_trigger, handler = h})
	# Secondary handler (e.g. Soul Rune per-turn reset)
	if rune.aura_secondary_trigger >= 0 and not rune.aura_secondary_steps.is_empty():
		var sec_trigger: int = rune.aura_secondary_trigger if owner == "player" else Enums.mirror_trigger(rune.aura_secondary_trigger as Enums.TriggerEvent)
		var h2 := func(event_ctx: EventContext):
			var ctx := EffectContext.make(_get_scene_facade(), owner)
			ctx.trigger_minion = event_ctx.minion
			ctx.source_rune = rune
			EffectResolver.run(rune.aura_secondary_steps, ctx)
		trigger_manager.register(sec_trigger, h2, 20)
		entries.append({event = sec_trigger, handler = h2})
	# Auto-backfill: for ON_*_MINION_SUMMONED auras, run aura_effect_steps once for each
	# existing minion on the matching board, treating it as if it had just been summoned.
	# Subsumes the old per-rune aura_on_place_steps for the common "buff existing matches"
	# case (e.g. Dominion Rune). Runes that don't want this opt out via aura_backfill_on_place.
	if rune.aura_backfill_on_place \
			and rune.aura_trigger >= 0 \
			and not rune.aura_effect_steps.is_empty() \
			and _is_minion_summoned_trigger(rune.aura_trigger):
		# Walk whichever board the (mirrored) trigger reads from. For an
		# ON_PLAYER_MINION_SUMMONED rune that's the owner's own board; for an
		# ON_ENEMY_MINION_SUMMONED rune (e.g. Shadow Rune, were it opted in),
		# it's the opponent's board.
		var backfill_owner: String = owner
		if rune.aura_trigger == Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED:
			backfill_owner = _opponent_of(owner)
		for m in _friendly_board(backfill_owner):
			var ctx := EffectContext.make(_get_scene_facade(), owner)
			ctx.trigger_minion = m
			ctx.from_rune = true
			ctx.source_rune = rune
			EffectResolver.run(rune.aura_effect_steps, ctx)
	# Bespoke on-place steps — escape hatch for non-standard placement behavior.
	if not rune.aura_on_place_steps.is_empty():
		var ctx := EffectContext.make(_get_scene_facade(), owner)
		EffectResolver.run(rune.aura_on_place_steps, ctx)
	if not entries.is_empty():
		_rune_aura_handlers.append({rune_id = rune.id, entries = entries})

## True if the trigger fires on a minion entering the board (either side).
## Used to gate aura_backfill_on_place to triggers where backfill has clear semantics.
func _is_minion_summoned_trigger(trigger: int) -> bool:
	return trigger == Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED \
			or trigger == Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED

## Consume the required runes and cast the ritual effect. Exact rune type
## matches are consumed first; wildcard runes fill remaining gaps. Each rune
## instance is consumed at most once (tracked by index, removed in reverse).
## Emits `traps_changed` for "player" so live UI refreshes the slot panel.
func _fire_ritual(ritual: RitualData) -> void:
	var consumed_indices: Array[int] = []
	for req in ritual.required_runes:
		var found := false
		# Try exact match first
		for i in active_traps.size():
			if i in consumed_indices:
				continue
			var trap := active_traps[i] as TrapCardData
			if trap.is_rune and not trap.is_wildcard_rune and trap.rune_type == req:
				consumed_indices.append(i)
				found = true
				break
		# Fall back to wildcard rune
		if not found:
			for i in active_traps.size():
				if i in consumed_indices:
					continue
				var trap := active_traps[i] as TrapCardData
				if trap.is_rune and trap.is_wildcard_rune:
					consumed_indices.append(i)
					break
	# Remove consumed runes in reverse index order so earlier indices stay valid
	consumed_indices.sort()
	consumed_indices.reverse()
	for i in consumed_indices:
		var trap := active_traps[i] as TrapCardData
		_remove_rune_aura(trap)
		active_traps.remove_at(i)
	traps_changed.emit("player")
	_log("★ RITUAL — %s!" % ritual.ritual_name, 1)  # PLAYER
	var ritual_ctx := EffectContext.make(_get_scene_facade(), "player")
	EffectResolver.run(ritual.effect_steps, ritual_ctx)
	# Fire ON_RITUAL_FIRED so registry-based handlers (ritual_surge) can respond
	if trigger_manager != null:
		var fired_ctx := EventContext.make(Enums.TriggerEvent.ON_RITUAL_FIRED, "player")
		trigger_manager.fire(fired_ctx)

## Void Bolt damage per Void Mark stack. Modifiable by CombatSetup at start
## (deepened_curse talent doubles the per-stack damage to 40).
func _void_mark_damage_per_stack() -> int:
	return void_mark_damage_per_stack

## Sacrifice a minion: NOT death — fires ON_LEAVE steps, ON_CORRUPTION_REMOVED
## (if any stacks), and ON_*_MINION_SACRIFICED but NOT ON_*_MINION_DIED.
## Removes the minion from its board and clears its slot (unless the slot is
## frozen for an ongoing animation — scene's animation flow finishes the clear).
## Live combat's _sacrifice_minion wrapper captures the slot reference first
## and queues the death animation after this call returns.
func _sacrifice_minion(minion: MinionInstance) -> void:
	if minion == null:
		return
	# Step 1 — declarative ON LEAVE steps run while the minion is still on its slot.
	var card_data := minion.card_data as MinionCardData
	if card_data != null and not card_data.on_leave_effect_steps.is_empty():
		var leave_ctx := EffectContext.make(_get_scene_facade(), minion.owner)
		leave_ctx.source         = minion
		leave_ctx.source_card_id = card_data.id
		EffectResolver.run(card_data.on_leave_effect_steps, leave_ctx)
	# Step 2 — corruption removal still fires (Corrupt Detonation reads "by any means").
	if trigger_manager != null:
		var pre_corruption: int = BuffSystem.count_type(minion, Enums.BuffType.CORRUPTION)
		if pre_corruption > 0:
			var rm_ctx := EventContext.make(Enums.TriggerEvent.ON_CORRUPTION_REMOVED, minion.owner)
			rm_ctx.minion = minion
			rm_ctx.damage = pre_corruption
			trigger_manager.fire(rm_ctx)
		# Step 3 — sacrifice event for board-wide listeners.
		var sac_event := Enums.TriggerEvent.ON_PLAYER_MINION_SACRIFICED if minion.owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_SACRIFICED
		var sac_ctx := EventContext.make(sac_event, minion.owner)
		sac_ctx.minion = minion
		trigger_manager.fire(sac_ctx)
	# Step 4 — remove from board. Clear the slot unless it's frozen (live combat
	# leaves frozen slots intact so the death animation can play first).
	# Use slot.remove_minion() not `slot.minion = null` so the slot's visual
	# refreshes — a bare field assignment leaves the dead minion's art on the
	# board until something else triggers a redraw.
	if minion.owner == "player":
		player_board.erase(minion)
		for slot in player_slots:
			if slot.minion == minion:
				if not slot.freeze_visuals:
					slot.remove_minion()
				break
	else:
		enemy_board.erase(minion)
		for slot in enemy_slots:
			if slot.minion == minion:
				if not slot.freeze_visuals:
					slot.remove_minion()
				break
	_log("  %s was sacrificed" % minion.card_data.card_name, 6)  # DEATH

## Apply Void Bolt damage to the enemy hero, scaled by current Void Marks.
## CONVENTION: ALL Void Bolt damage in the game must go through this function
## so that talents like deepened_curse and future modifiers apply automatically.
## Void bolt passives fire automatically in _on_hero_damaged when type == VOID_BOLT.
## is_minion_emitted: caller asserts this Void Bolt is a minion attack/effect (e.g.
## void_manifestation talent retag of basic attack, piercing_void retag of on-play).
## Default false → SPELL source for spell-cast / triggered-passive paths.
##
## Live combat's _deal_void_bolt_damage wrapper fires + awaits the projectile
## VFX before calling this so damage syncs with bolt impact.
func _deal_void_bolt_damage(base_damage: int, source_minion: MinionInstance = null, from_rune: bool = false, is_minion_emitted: bool = false) -> void:
	var bonus: int = enemy_void_marks * void_mark_damage_per_stack
	var total: int = base_damage + bonus
	if bonus > 0:
		_log("  Void Bolt: %d dmg (base %d + %d from %d marks)" % [total, base_damage, bonus, enemy_void_marks], 1)  # PLAYER
	else:
		_log("  Void Bolt: %d damage." % total, 1)
	var base_source: String = _pending_dmg_source
	if base_source.is_empty():
		base_source = "void_rune" if from_rune else "void_bolt_spell"
	_pending_dmg_source = base_source
	# Split log: base damage + mark bonus separately (sim diagnostic; live combat ignores).
	if dmg_log_enabled:
		dmg_log.append({turn = _current_turn, amount = base_damage, source = base_source})
		if bonus > 0:
			dmg_log.append({turn = _current_turn, amount = bonus, source = "void_mark"})
		_pending_dmg_source = "__logged__"  # signal _on_hero_damaged to skip logging
	var src: Enums.DamageSource = Enums.DamageSource.MINION if is_minion_emitted else Enums.DamageSource.SPELL
	combat_manager.apply_hero_damage("enemy",
			CombatManager.make_damage_info(total, src, Enums.DamageSchool.VOID_BOLT, source_minion, base_source))
	_void_bolt_total_dmg += total

## Apply enemy-cast Void Bolt damage to the player hero. Does not participate
## in Void Marks (those only apply to the enemy hero). Live combat's wrapper
## fires + awaits the projectile VFX before calling this.
func _deal_enemy_void_bolt_damage(base_damage: int, source_minion: MinionInstance = null, is_minion_emitted: bool = false) -> void:
	_log("  Void Bolt: %d damage." % base_damage, 2)  # ENEMY
	var base_source: String = _pending_dmg_source
	if base_source.is_empty():
		base_source = "enemy_void_bolt"
	_pending_dmg_source = base_source
	if dmg_log_enabled:
		dmg_log.append({turn = _current_turn, amount = base_damage, source = base_source})
		_pending_dmg_source = "__logged__"
	var src: Enums.DamageSource = Enums.DamageSource.MINION if is_minion_emitted else Enums.DamageSource.SPELL
	combat_manager.apply_hero_damage("player",
			CombatManager.make_damage_info(base_damage, src, Enums.DamageSchool.VOID_BOLT, source_minion, base_source))

## Fire matching non-rune traps for the given trigger event (both player and
## enemy). Skips player traps when `_player_traps_blocked` is set (enemy-side
## relic / Phase Disruptor trap-block effects). Mirror-translates the trigger
## for enemy traps. Removes non-reusable traps after firing.
func _check_and_fire_traps(trigger: int, triggering_minion: MinionInstance = null) -> void:
	# Player traps
	if not _player_traps_blocked:
		for trap in active_traps.duplicate():
			if trap.is_rune:
				continue
			if trap.trigger != trigger:
				continue
			var ctx := EffectContext.make(_get_scene_facade(), "player")
			ctx.trigger_minion = triggering_minion
			EffectResolver.run(trap.effect_steps, ctx)
			if not trap.reusable:
				active_traps.erase(trap)
	# Enemy traps (mirror trigger: player events → enemy equivalents)
	var enemy_trigger: int = Enums.mirror_trigger(trigger as Enums.TriggerEvent)
	for trap in enemy_active_traps.duplicate():
		if trap.is_rune:
			continue
		if trap.trigger != enemy_trigger:
			continue
		var ctx := EffectContext.make(_get_scene_facade(), "enemy")
		ctx.trigger_minion = triggering_minion
		EffectResolver.run(trap.effect_steps, ctx)
		if not trap.reusable:
			enemy_active_traps.erase(trap)

## Compose an enemy spell cast resolution. The pre/post-cast hooks (Seris
## Void Amplification / Void Resonance) are player-only and not invoked here.
## The trigger ON_ENEMY_SPELL_CAST fires before this method (Null Seal can
## cancel via _spell_cancelled; caller short-circuits in that case).
func cast_enemy_spell(spell: SpellCardData, chosen) -> void:
	if not spell.effect_steps.is_empty():
		var ectx := EffectContext.make(_get_scene_facade(), "enemy")
		ectx.source_card_id = spell.id
		if chosen is MinionInstance:
			ectx.chosen_target = chosen
		else:
			ectx.chosen_object = chosen
		EffectResolver.run(spell.effect_steps, ectx)
	elif not spell.effect_id.is_empty():
		_resolve_spell_effect(spell.effect_id, null, "enemy")

## Seris — Corrupt Flesh core application. Pure logic shared by the scene
## (called from _seris_corrupt_apply_target after a valid click) and sim
## (called directly from SerisPlayerProfile). Returns true on success.
func _seris_corrupt_apply(target: MinionInstance) -> bool:
	if not _has_talent("corrupt_flesh"):
		return false
	if _seris_corrupt_used_this_turn:
		return false
	if player_flesh < 1:
		return false
	if target == null or target.owner != "player":
		return false
	if (target.card_data as MinionCardData).minion_type != Enums.MinionType.DEMON:
		return false
	# Note: scene's _spend_flesh path (Flesh.spend) logs and emits flesh_changed.
	# Sim mutates player_flesh directly via inherited setter — same emission.
	if player_flesh < 1:
		return false
	player_flesh -= 1
	var stacks: int = 2 if "grafted_fiend" in (target.card_data as MinionCardData).minion_tags else 1
	for _i in stacks:
		BuffSystem.apply(target, Enums.BuffType.CORRUPTION, 100, "corrupt_flesh", false, false)
	_seris_corrupt_used_this_turn = true
	_log("  Corrupt Flesh: %d Corruption stack(s) applied to %s." % [stacks, target.card_data.card_name], 1)
	_refresh_slot_for(target)
	return true

## Seris — reset the Corrupt Flesh 1/turn flag at player turn start.
func _seris_corrupt_reset_turn() -> void:
	_seris_corrupt_used_this_turn = false

## Seris — pre-death save. CombatManager asks "can this minion be saved?"
## Return true and set minion.current_health > 0 to save it. Currently only
## deathless_flesh + Grafted Fiend qualifies. Pure logic.
func _try_save_from_death(minion: MinionInstance) -> bool:
	if minion == null or minion.owner != "player":
		return false
	if _has_talent("deathless_flesh") \
			and minion.card_data is MinionCardData \
			and "grafted_fiend" in (minion.card_data as MinionCardData).minion_tags \
			and player_flesh >= 2:
		player_flesh -= 2
		minion.current_health = 50
		_log("  Deathless Flesh: %s saved (2 Flesh spent)." % minion.card_data.card_name, 1)
		return true
	return false

## Apply one Corruption stack to a minion (each stack reduces ATK by 100).
## Logs and refreshes the slot via signals — live UI subscriber animates the
## refresh; sim has no subscribers so the call is data-only. Live combat
## additionally spawns CorruptionApplyVFX in the CombatScene wrapper.
func _corrupt_minion(target: MinionInstance) -> void:
	var penalty := 100
	BuffSystem.apply(target, Enums.BuffType.CORRUPTION, penalty, "corruption", false, false)
	_log("  %s is Corrupted! (−%d ATK)" % [target.card_data.card_name, penalty], 2)  # CombatLog.LogType.ENEMY = 2
	_refresh_slot_for(target)

## Generic minion heal — restores HP up to the effective max (base + HP_BONUS
## buffs). No-op if amount ≤ 0 or minion is dead. Logs + refreshes via signals.
func _heal_minion(minion: MinionInstance, amount: int) -> void:
	if minion == null or amount <= 0 or minion.current_health <= 0:
		return
	var hp_cap: int = minion.card_data.health + BuffSystem.sum_type(minion, Enums.BuffType.HP_BONUS)
	var before := minion.current_health
	minion.current_health = mini(minion.current_health + amount, hp_cap)
	var healed := minion.current_health - before
	if healed <= 0:
		return
	var log_type: int = 1 if minion.owner == "player" else 2  # PLAYER / ENEMY
	_log("  %s healed for %d HP" % [minion.card_data.card_name, healed], log_type)
	_refresh_slot_for(minion)

## Restore a minion to its effective max HP (base + HP_BONUS buffs). No-op if
## already at max or dead. Logs + refreshes via signals.
func _heal_minion_full(minion: MinionInstance) -> void:
	if minion == null or minion.current_health <= 0:
		return
	var hp_cap: int = minion.card_data.health + BuffSystem.sum_type(minion, Enums.BuffType.HP_BONUS)
	if minion.current_health >= hp_cap:
		return
	var healed: int = hp_cap - minion.current_health
	minion.current_health = hp_cap
	var log_type: int = 1 if minion.owner == "player" else 2  # PLAYER / ENEMY
	_log("  %s healed to full (+%d HP)" % [minion.card_data.card_name, healed], log_type)
	_refresh_slot_for(minion)

## Seris/Fleshcraft — add kill stacks to a minion. Single entry point so both
## organic kills (on_enemy_died_grafted_constitution) and direct grants
## (Flesh Sacrament) run the talent reactions uniformly:
##   • flesh_infusion active → +100 ATK / +100 HP per stack
##   • predatory_surge active and kill_stacks ≥ 3 → grant SIPHON once
func _add_kill_stacks(minion: MinionInstance, count: int = 1) -> void:
	if minion == null or count <= 0:
		return
	minion.kill_stacks += count
	if _has_talent("flesh_infusion"):
		BuffSystem.apply(minion, Enums.BuffType.ATK_BONUS, 100 * count, "grafted_constitution", false, false)
		BuffSystem.apply_hp_gain(minion, 100 * count, "grafted_constitution", true)
		_log("  Grafted Constitution: %s +%d/+%d (kills: %d)." % [minion.card_data.card_name, 100 * count, 100 * count, minion.kill_stacks], 1)
	if _has_talent("predatory_surge") and minion.kill_stacks >= 3 \
			and not BuffSystem.has_type(minion, Enums.BuffType.GRANT_SIPHON):
		BuffSystem.apply(minion, Enums.BuffType.GRANT_SIPHON, 1, "predatory_surge", false, false)
		_log("  Predatory Surge: %s gains Siphon." % minion.card_data.card_name, 1)
	_refresh_slot_for(minion)

## Returns true if the rune board contains at least one of each required rune
## type. Wildcard runes (is_wildcard_rune = true) can substitute for any
## missing type. Exact matches consumed first, then wildcards fill gaps.
func _runes_satisfy(runes: Array, required: Array[int]) -> bool:
	var available: Array[int] = []
	var wildcards: int = 0
	for r in runes:
		var trap := r as TrapCardData
		if trap == null:
			continue
		if trap.is_wildcard_rune:
			wildcards += 1
		else:
			available.append(trap.rune_type)
	var remaining_wildcards := wildcards
	for req in required:
		if req in available:
			available.erase(req)
		elif remaining_wildcards > 0:
			remaining_wildcards -= 1
		else:
			return false
	return true

# ---------------------------------------------------------------------------
# Hero state — `player_hp` and `enemy_hp` are properties so writes emit
# `hp_changed` automatically. Direct backing-field writes (`_player_hp_value =`)
# bypass the signal and should NOT be used outside CombatState.
# ---------------------------------------------------------------------------

var _player_hp_value: int = 0
var player_hp: int:
	get: return _player_hp_value
	set(v):
		if v == _player_hp_value:
			return
		var delta := v - _player_hp_value
		_player_hp_value = v
		hp_changed.emit("player", v, player_hp_max, delta)

var _enemy_hp_value: int = 0
var enemy_hp: int:
	get: return _enemy_hp_value
	set(v):
		if v == _enemy_hp_value:
			return
		var delta := v - _enemy_hp_value
		_enemy_hp_value = v
		hp_changed.emit("enemy", v, enemy_hp_max, delta)

## Player hero max HP — set by CombatScene._ready from GameManager.player_hp_max
## (varies with hero/talents). Sim sets this directly via SimState.setup() and
## currently leaves it at 0 since sim runs on absolute HP values; setup overrides.
var player_hp_max: int = 0
var enemy_hp_max: int = 0

# ---------------------------------------------------------------------------
# Combat lifecycle
# ---------------------------------------------------------------------------

## Re-entrancy guard: set true the moment victory/defeat fires so subsequent
## damage/heal/spell resolutions are no-ops. Live uses this directly; sim uses
## `winner` and currently ignores `_combat_ended` (Phase 5 unifies them).
var _combat_ended: bool = false

## Sim end-of-combat result: "player", "enemy", "draw", or "" while running.
## Live combat populates this in Phase 5 cleanup; until then live continues to
## drive end-of-combat through scene-side game-over UI.
var winner: String = ""

# ---------------------------------------------------------------------------
# F15 Abyss Sovereign phase transition
# ---------------------------------------------------------------------------

## 1 = P1, 2 = P2. Flips to 2 via PhaseTransition when P1 HP hits 0. Non-F15
## fights leave this at 1.
var _sovereign_phase: int = 1
## Turn number at which the P1→P2 transition fired. 0 = never transitioned.
var _sovereign_transition_turn: int = 0

# ---------------------------------------------------------------------------
# Boards
# ---------------------------------------------------------------------------

var player_board: Array[MinionInstance] = []
var enemy_board:  Array[MinionInstance] = []

## Live combat binds these from the scene tree in CombatScene._find_nodes().
## Sim pre-allocates plain BoardSlot.new() in SimState.setup().
var player_slots: Array[BoardSlot] = []
var enemy_slots:  Array[BoardSlot] = []

# ---------------------------------------------------------------------------
# Traps / environments / runes / void marks
# ---------------------------------------------------------------------------

## Player-side active traps & runes (shared pool, max 3 slots).
var active_traps: Array[TrapCardData] = []
## Player-side active global environment.
var active_environment: EnvironmentCardData = null

## Enemy-side mirror. Single source of truth for both live combat and sim:
## live's EnemyAI.active_traps is now a property forwarder onto this field, so
## state mutations (sim's direct writes; live's `enemy_ai.active_traps.append`)
## both land here. enemy_active_environment still lives on EnemyAI on the live
## side — unify in a follow-up if needed.
var enemy_active_traps: Array[TrapCardData] = []
var enemy_active_environment: EnvironmentCardData = null

## Callables registered for the current environment's 2-rune rituals.
## Cleared and re-populated whenever the active environment changes.
var _env_ritual_handlers: Array[Callable] = []

## TriggerManager Callables registered per rune placement.
## Stored as an Array of {rune_id, entries} so two runes of the same type each
## get an independent entry and can be individually unregistered.
var _rune_aura_handlers: Array = []  # Array[{rune_id: String, entries: Array}]

## Void Mark stacks on the enemy hero (accumulate through the run). Property
## emits void_marks_changed on write so the enemy hero panel refreshes without
## scattered manual `_enemy_hero_panel.update(...)` calls at every increment.
var _enemy_void_marks_value: int = 0
var enemy_void_marks: int:
	get: return _enemy_void_marks_value
	set(v):
		if v == _enemy_void_marks_value:
			return
		_enemy_void_marks_value = v
		void_marks_changed.emit("enemy", v)

# ---------------------------------------------------------------------------
# Talent / hero state
# ---------------------------------------------------------------------------

## Active player talent IDs. Sim sets directly; live populates from
## GameManager.player_talents in Phase 4 (currently CombatScene reads
## GameManager directly inside `_has_talent`).
var talents: Array[String] = []

## Hero passive IDs for the current hero (e.g. dark_channeling_seris).
## Sim sets directly; live populates from GameManager.current_hero in Phase 4.
var hero_passives: Array[String] = []

## Hero id ("lord_vael", "seris"). Used by profiles to branch on hero-specific
## activated abilities (Seris's Forge / Corrupt buttons). Sim-only today.
var player_hero_id: String = "lord_vael"

## Seris — Flesh counter. Gains 1 per friendly Demon death (Fleshbind passive),
## capped at player_flesh_max. Resets each combat. Spent by Seris talent effects.
## Property emits `flesh_changed` on every write so the resource bar / pip bar
## refresh without scattered manual hooks.
var _player_flesh_value: int = 0
var player_flesh: int:
	get: return _player_flesh_value
	set(v):
		if v == _player_flesh_value:
			return
		_player_flesh_value = v
		flesh_changed.emit(v, player_flesh_max)
var player_flesh_max: int = 5

## Seris — Fiendish Pact pending Mana discount. Set by the Fiendish Pact spell,
## consumed when the next Demon is played (capped at that card's mana_cost).
var _fiendish_pact_pending: int = 0

## Seris — Forge Counter (Demon Forge branch). Incremented when a Demon is
## sacrificed; at threshold the Soul Forge talent auto-summons a Forged Demon
## and resets the counter. Threshold is set by CombatSetup from the talent
## registry (forge_momentum reduces it from 3 to 2). Property emits
## `forge_changed` on every write.
var _forge_counter_value: int = 0
var forge_counter: int:
	get: return _forge_counter_value
	set(v):
		if v == _forge_counter_value:
			return
		_forge_counter_value = v
		forge_changed.emit(v, forge_counter_threshold)
var forge_counter_threshold: int = 3

## Seris — Active spell-damage bonus during a player spell cast (sum of
## Corruption stacks across friendly Demons * 50 from void_amplification).
## Cleared after spell resolution. Read by `_spell_dmg`.
var _player_spell_damage_bonus: int = 0

## Generic once-per-turn gate dictionary. Keyed by an explicit flag_id (e.g.
## "imp_evolution") declared by the EffectStep that uses it. Reset at start of each
## player turn (only player-driven once_per_turn flags exist today).
## Read & consumed atomically by ConditionResolver "once_per_turn:<flag_id>" — the gate
## is consumed even if the gated step's body fails (e.g. ADD_CARD on a full hand).
var _once_per_turn_used: Dictionary = {}

## Vael — Void Imps summoned by Imp Overload that must die at end of player turn.
var _temp_imps: Array[MinionInstance] = []

# ---------------------------------------------------------------------------
# Cost penalties / spell counters / once-per-turn flags
# ---------------------------------------------------------------------------

## Pending spell tax applied at next turn start (set by Spell Taxer effect).
var _spell_tax_for_enemy_turn: int = 0
var _spell_tax_for_player_turn: int = 0

## Active player spell cost penalty this turn (applied at turn start, cleared at turn end).
var player_spell_cost_penalty: int = 0

## Enemy-side cost penalty (sim mirrors EnemyAI).
var enemy_spell_cost_penalty: int = 0
## Persistent flat mana-cost adjustment from an active aura (e.g. Void Ritualist
## Prime champion reduces by 1). Negative = discount. Not reset per turn.
var enemy_spell_cost_aura: int = 0
var enemy_spell_cost_discounts: Dictionary = {}
var enemy_essence_cost_discounts: Dictionary = {}
## Flat enemy minion essence-cost aura (F15 Abyssal Mandate). Negative = cheaper.
## Set when the player grows Essence; cleared at end of the following enemy turn.
var enemy_minion_essence_cost_aura: int = 0

## When true, enemy traps cannot trigger (set by Saboteur Adept, cleared at player turn end).
var _enemy_traps_blocked: bool = false
## When true, player traps cannot trigger (set by enemy Saboteur Adept, cleared at enemy turn end).
var _player_traps_blocked: bool = false

## Spell counter: when > 0, next spell cast by this side is cancelled and counter decrements.
var _player_spell_counter: int = 0
var _enemy_spell_counter: int = 0

## Set to true by Silence Trap to skip the enemy spell's effect resolution.
var _spell_cancelled: bool = false
## When true, the player's current mana is set to 0 at the start of their next turn (Void Rift Lord).
var _void_mana_drain_pending: bool = false

## Prevents Soul Rune from firing more than once per enemy turn.
var _soul_rune_fires_this_turn: int = 0
## Once-per-turn gate for feral_reinforcement passive (sim).
var _imp_caller_fired: bool = false

## Re-entrancy depth for nested player spell casts (used by void_resonance_seris).
var _spell_cast_depth: int = 0
## Guard so void_resonance_seris double-cast doesn't recursively trigger itself.
var _double_cast_in_progress: bool = false

## Round-robin index for void rune firing — picks which rune slot fires next.
var _void_rune_fire_index: int = 0

## Seris — Corrupt Flesh once-per-turn gate. Reset on ON_PLAYER_TURN_START.
var _seris_corrupt_used_this_turn: bool = false

## Live-only revive gate (Bone Phoenix etc). Sim doesn't model revives currently.
var _pending_revive: bool = false

## Most recent player resource-growth choice ("" | "essence" | "mana").
## Read by F15 abyssal_mandate passive.
var last_player_growth: String = ""

# ---------------------------------------------------------------------------
# Relic state flags (set by relic effects, consumed by combat logic)
# ---------------------------------------------------------------------------

var _relic_hero_immune: bool = false   ## Bone Shield: ignore damage this turn
var _relic_cost_reduction: int = 0     ## Dark Mirror: reduce next card cost
var _relic_extra_turn: bool = false    ## Void Hourglass: take extra turn

# ---------------------------------------------------------------------------
# Crit + Dark Channeling
# ---------------------------------------------------------------------------

var _vp_pre_crit_stacks: int = 0
var _spirit_conscription_fired: bool = false
var crit_multiplier: float = 2.0
var enemy_crit_multiplier: float = 0.0  ## Per-side override; 0 = use global
var _enemy_crits_consumed: int = 0
var _player_crits_consumed: int = 0
var _last_crit_attacker: MinionInstance = null
var _last_attack_was_crit: bool = false
## Set by CombatManager.resolve_minion_attack(_hero) for the duration of the
## attack; read by death-trigger firing so ctx.attacker can be populated.
var _last_attacker: MinionInstance = null
var _dark_channeling_active: bool = false
var _dark_channeling_multiplier: float = 1.0
var _dark_channeling_amp_count: int = 0
var _dark_channeling_amp_by_spell: Dictionary = {}  ## spell_id -> count
var _dark_channeling_dmg_by_spell: Dictionary = {}  ## spell_id -> extra damage from amp

# ---------------------------------------------------------------------------
# Passive-configurable stats — set by CombatSetup from the registry at combat start
# ---------------------------------------------------------------------------

var void_mark_damage_per_stack: int = 25  ## deepened_curse sets this to 40
var rune_aura_multiplier: int = 1         ## runic_attunement sets this to 2

## Active passive IDs for the current enemy encounter. Sim sets this directly;
## live populates from GameManager.current_enemy.passives in CombatScene._ready.
var _active_enemy_passives: Array[String] = []
## Sim-only mirror that some sim handlers read by the name `enemy_passives`.
## Kept in sync with `_active_enemy_passives` by SimTriggerSetup. Will collapse
## into a single field in Phase 5.
var enemy_passives: Array[String] = []

# ---------------------------------------------------------------------------
# Champion counters — every per-encounter trigger counter for Act 1–4 champions
# and supporting Void Warband tracking. Move-as-pure-data; live combat already
# populates these via scene.set(key, value) from CombatSetup.
# ---------------------------------------------------------------------------

var _champion_summon_count: int = 0
var _corruption_detonation_times: int = 0
var _ritual_invoke_times: int = 0
var _handler_spark_buff_times: int = 0
var _smoke_veil_fires: int = 0
var _smoke_veil_damage_prevented: int = 0
var _abyssal_plague_fires: int = 0
var _abyssal_plague_kills: int = 0
var _champion_rip_attack_ids: Array = []
var _champion_rip_summoned: bool = false
var _champion_cb_death_count: int = 0
var _champion_cb_summoned: bool = false
var _champion_im_frenzy_count: int = 0
var _champion_im_summoned: bool = false
# Act 2
var _champion_acp_stacks_consumed: int = 0
var _champion_acp_summoned: bool = false
var _champion_vr_summoned: bool = false
var _champion_ch_spark_count: int = 0
var _champion_ch_summoned: bool = false
var _champion_ch_aura_dmg: int = 0
# Act 3
var _champion_rs_spark_dmg: int = 0
var _champion_rs_summoned: bool = false
var _champion_va_sparks_consumed: int = 0
var _champion_va_summoned: bool = false
var _champion_vh_spark_cards_played: int = 0
var _champion_vh_summoned: bool = false
# Act 4
var _champion_vs_crits_consumed: int = 0
var _champion_vs_summoned: bool = false
var _champion_vw_spirits_consumed: int = 0
var _champion_vw_summoned: bool = false
var _vw_behemoth_plays: int = 0
var _vw_bastion_plays: int = 0
var _void_echo_fired_this_turn: bool = false
var _vw_death_crit_grants: int = 0
var _vw_behemoth_lost: Dictionary = {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}
var _vw_bastion_lost: Dictionary = {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}
var _champion_vc_tc_cast: int = 0
var _champion_vc_summoned: bool = false
var _champion_vch_crit_kills: int = 0
var _champion_vch_summoned: bool = false
var _champion_vrp_spells_cast: int = 0
var _champion_vrp_summoned: bool = false
# Sim-only Act 3/4 counters
var _rift_lord_plays: int = 0
var _hollow_sentinel_buffs: int = 0
var _immune_dmg_prevented: int = 0
var _rift_collapse_casts: int = 0
var _rift_collapse_kills: int = 0

# ---------------------------------------------------------------------------
# Diagnostic counters — sim collects these for end-of-run reports. Live combat
# also increments them but never reads (ignored). Always-on per Phase 0 decision.
# ---------------------------------------------------------------------------

var _ritual_sacrifice_count: int = 0
var _detonation_count: int = 0
var _player_ritual_count: int = 0
var _spark_spawned_count: int = 0
var _spark_transfer_count: int = 0
var _void_bolt_spell_casts: int = 0
var _void_bolt_total_dmg: int = 0
var _void_imp_dmg: int = 0

## Optional per-turn snapshot hook. Called at end of enemy turn with (state, turn).
var turn_snapshot_callback: Callable = Callable()

## Verbose damage log — populated when dmg_log_enabled = true.
## Each entry: { turn: int, amount: int, source: String }
var dmg_log_enabled: bool = false
var dmg_log: Array = []
var _current_turn: int = 0
var _pending_dmg_source: String = ""

# ---------------------------------------------------------------------------
# Sub-systems shared by scene and sim.
# ---------------------------------------------------------------------------

## Central event dispatcher. Live combat creates one in CombatScene._ready
## and assigns it here; sim creates one in SimTriggerSetup. Always non-null
## once setup completes.
var trigger_manager: TriggerManager = null

## Turn-manager facade: live combat assigns the scene-tree TurnManager (Node),
## sim assigns SimTurnManager (RefCounted). Untyped here so either fits — both
## expose the same surface (`draw_card()`, `add_instance_to_hand(inst)`, etc.).
## Used by CombatState methods that need to draw cards (e.g. Flesh Bond on
## _on_flesh_spent). Decks/hands themselves still live on TurnManager/SimState
## per the Phase 4 plan.
var turn_manager = null

## Hardcoded-effect resolver. Live combat creates one in CombatScene._ready
## and assigns it through the forwarding property; sim creates one in
## SimState.setup. Used by _resolve_spell_effect for legacy effect_id spells,
## and by EffectResolver via ctx.scene._resolve_hardcoded for HARDCODED steps.
var _hardcoded: HardcodedEffects = null

## Combat-manager instance — owns hero/minion damage application, attack
## resolution, and minion-vanished signaling. Live combat creates one in
## CombatScene._ready (forwarded through the property); sim creates one in
## SimState.setup. State methods that apply damage (e.g. cast_player_hero_spell)
## read combat_manager directly.
var combat_manager: CombatManager = null
