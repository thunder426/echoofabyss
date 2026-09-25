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

## Emitted whenever a hero's Armour value changes. `side` is "player" or "enemy",
## `value` is the post-mutation armour amount. Live UI subscribes to refresh the
## hero panel armour badge; sim has no subscriber. Korrath only.
signal hero_armour_changed(side: String, value: int)

## Emitted whenever any buff entry on a hero is added or removed. `side` is the
## affected hero. Coalescing-style — listeners read whatever sums they need
## (e.g. ARMOUR_BREAK total via BuffSystem.sum_type) rather than parsing a
## per-buff payload. Live UI subscribes to refresh hero-panel debuff badges.
signal hero_buff_changed(side: String)

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
## including _player_spell_damage_bonus added inside _spell_dmg). `school`
## carries the damage_school from the originating EffectStep (NONE if the
## caller passed no info dict) — popup color reads from this.
signal spell_damage_dealt(target: MinionInstance, damage: int, school: int)

## Emitted after a minion has been removed from its side's board (post-erase).
## `slot_index` is the slot it occupied (or -1 if not found). External
## subscribers use this rather than CombatManager.minion_vanished so the data
## layer stays the source of truth. Live combat still subscribes to CombatManager
## directly for animation timing; this signal is for logic listeners.
signal minion_died(side: String, minion: MinionInstance, slot_index: int)

## Presentation seam (LIVE_SIM_UNIFICATION_PLAN.md 1.1). Live combat sets this
## to the CombatScene in _ready; sim and tests leave it null. Rules code reads
## and writes gameplay data on the state and calls presentation only through
## `presenter`, null-checked — the names it may call are listed in
## tools/lint/presentation_allowlist.txt ([presenter]) and checked by lint L3.
var presenter: Object = null

## Ordered journal of gameplay events (plan 3.1). Every mutation appends one
## through emit_event; the presenter (3.2) drains it one event at a time and
## plays one animation per event against a lagging ViewState. Sim ignores it.
var journal: Array[CombatEvent] = []

func emit_event(kind: int, side: String, payload: Dictionary = {}) -> CombatEvent:
	var ev := CombatEvent.make(kind, side, turn_number, payload)
	ev.seq = journal.size()
	journal.append(ev)
	return ev

## Self-alias so `<shell>.state` works on every shell — CombatScene composes a
## CombatState, SimState and bare test states are one.
var state: CombatState:
	get: return self

## Facade for `EffectContext.scene` and for the [facade] names in
## tools/lint/presentation_allowlist.txt: gameplay whose live version is still
## VFX-bound (Void Bolt projectile before damage, corruption popup capture,
## ritual VFX, sacrifice / token-summon animations). Returns the presenter in
## live and the state itself in sim/tests (SimState extends CombatState), so
## the same call resolves to CombatScene's VFX-rich override live and the pure
## body here otherwise. Phase 3.0 makes those bodies synchronous and this goes.
func _get_scene_facade() -> Object:
	return presenter if presenter != null else self

## Logging convenience — handlers, effects, and combat code call `state._log(msg)`
## without needing a scene reference or knowing whether a UI exists. Signal
## subscribers (CombatScene's _on_state_combat_log) forward to the visual log;
## sim has no subscriber so this is a no-op there.
func _log(msg: String, log_type: int = 1) -> void:  # default = CombatLog.LogType.PLAYER
	combat_log.emit(msg, log_type)
	emit_event(CombatEvent.Kind.LOG, "", {msg = msg, log_type = log_type})

## Refresh a minion's slot visual. Handlers and effects call
## `ctx.scene._refresh_slot_for(m)`; the scene's facade calls this method,
## which emits the signal. Live subscribers re-render; sim has no subscribers
## so the call is a no-op (replaces SimState's old `pass` duck-type stub).
func _refresh_slot_for(minion: MinionInstance) -> void:
	if minion != null:
		minion_stats_changed.emit(minion)
		emit_event(CombatEvent.Kind.MINION_STATS_CHANGED, minion.owner, {minion = minion, atk = minion.effective_atk(), hp = minion.current_health, shield = minion.current_shield})

## Trap/rune display refresh hook for a specific side ("player"/"enemy").
## Scene's `_update_trap_display_for(owner)` facade delegates here; subscribers
## call `trap_env_display.update_traps_for(side)`. Sim has no subscriber → no-op
## (replaces the old SimState pass-stub).
func _update_trap_display_for(owner: String) -> void:
	traps_changed.emit(owner)
	emit_event(CombatEvent.Kind.TRAPS_CHANGED, owner, {traps = traps_of(owner).duplicate()})

## Convenience: refresh the player-side trap display.
func _update_trap_display() -> void:
	_update_trap_display_for("player")

## Convenience: refresh the enemy-side trap display.
func _update_enemy_trap_display() -> void:
	_update_trap_display_for("enemy")

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

## True if `side` has at least one empty board slot.
func has_empty_slot(side: String) -> bool:
	for slot: SlotState in (player_slots if side == "player" else enemy_slots):
		if slot.is_empty():
			return true
	return false

## Count minions of a specific type on the friendly board.
func _count_type_on_board(type: int, owner: String) -> int:
	var count := 0
	for m in _friendly_board(owner):
		if ((m as MinionInstance).card_data as MinionCardData).is_race(type):
			count += 1
	return count

## Sim-side / AI helper for Rally the Ranks's dual-tag race choice. Returns
## "human" or "demon" based on which race the caster has more of on their own
## board (ties → "demon" since Abyss Order leans Demon). Used by sim AI when
## constructing extra_cast_data for commit_play_spell; live combat asks the
## player via ChoiceModal instead and does not call this.
func _rally_pick_race_for(owner: String) -> String:
	var humans: int = _count_type_on_board(Enums.MinionType.HUMAN, owner)
	var demons: int = _count_type_on_board(Enums.MinionType.DEMON, owner)
	if humans > demons:
		return "human"
	return "demon"

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

# ---------------------------------------------------------------------------
# Engine-owned RNG — every gameplay random goes through these so a seed
# reproduces a fight (lint L2). Cosmetic VFX randomness stays on the global RNG.
# Seeded by CombatSim.run (sim) and CombatScene._ready (live).
# ---------------------------------------------------------------------------

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var rng_seed: int = 0

func seed_rng(seed_value: int) -> void:
	rng_seed = seed_value
	rng.seed = seed_value

## Uniform index in [0, size). Caller guarantees size > 0.
func rng_index(size: int) -> int:
	return rng.randi() % size

## Uniform element of a non-empty array.
func rng_pick(arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()]

## In-place Fisher–Yates shuffle.
func rng_shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

## Uniform int in [lo, hi].
func rng_range(lo: int, hi: int) -> int:
	return rng.randi_range(lo, hi)

## Random minion from a board array, or null if empty.
func _find_random_minion(board: Array) -> MinionInstance:
	if board.is_empty():
		return null
	return rng_pick(board)

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
	if presenter != null:
		presenter._show_void_mark_applied()

## Korrath — add Armour to a hero. Routes through HeroState.add_armour for the
## central mutation point and emits hero_armour_changed for UI.
func add_hero_armour(side: String, amount: int) -> void:
	if amount == 0:
		return
	var hero: HeroState = player_hero if side == "player" else enemy_hero
	hero.add_armour(amount)
	hero_armour_changed.emit(side, hero.armour)
	emit_event(CombatEvent.Kind.ARMOUR_CHANGED, side, {value = hero.armour})

## Korrath — apply a buff/debuff entry to a hero. Wraps BuffSystem.apply (which
## duck-types on `buffs`) and emits hero_buff_changed so the panel-badge UI can
## refresh. Today this is the entry point for ARMOUR_BREAK on heroes
## (commanders_reach, path_of_shattering); future hero-side buffs flow through
## here too. `is_temp` and `emit_vfx` mirror BuffSystem.apply.
func apply_hero_buff(side: String, type: int, amount: int,
		source: String = "", is_temp: bool = false, emit_vfx: bool = false) -> void:
	var hero: HeroState = player_hero if side == "player" else enemy_hero
	BuffSystem.apply(hero, type, amount, source, is_temp, emit_vfx)
	hero_buff_changed.emit(side)
	emit_event(CombatEvent.Kind.HERO_BUFF_CHANGED, side, {})

## Remove rune aura handlers, auto-strip source_tag buffs declared in aura_effect_steps,
## then run any bespoke aura_on_remove_steps. Symmetric across scene/sim.
## `owner` defaults to "player" (scene caller).
func _remove_rune_aura(rune: TrapCardData, owner: String = "player") -> void:
	# Korrath B2 T1 (runic_absorption): every player-side rune destroy/consume —
	# overflow, ritual fire, Grand Ritual: Chaos, Runic Substitution, Cyclone-style
	# spells, etc. — grants an aura stack of this rune's id to a random friendly
	# Abyssal Knight. Stack is silently lost if no Knight is on board. Routed
	# through this single chokepoint so all current and future destroy paths
	# inherit the behavior without each site re-implementing the grant.
	if owner == "player" and rune != null and rune.is_rune \
			and "runic_absorption" in talents:
		_korrath_grant_absorbed_aura(rune.id)
	# Match on (rune_id, owner) — both sides can have the same rune_id active
	# at once (e.g. player + enemy both placed dominion_rune). Without the
	# owner check this used to remove the wrong side's handler entry, leaking
	# a stale aura that would buff future summons on the wrong board.
	for i in _rune_aura_handlers.size():
		var entry: Dictionary = _rune_aura_handlers[i]
		if entry.rune_id == rune.id and entry.get("owner", "player") == owner:
			for sub in entry.entries:
				trigger_manager.unregister(sub.event, sub.handler)
			_rune_aura_handlers.remove_at(i)
			break
	# Auto-cleanup: strip one layer of every source_tag declared in aura_effect_steps
	# from the SAME side this rune was on. One rune copy = one layer stripped,
	# mirroring the prior bespoke Dominion teardown. No-op for runes whose
	# aura steps don't carry a source_tag.
	#
	# Side-scoped: a rune only ever buffs its own side's minions (its trigger
	# fires for its own ON_*_MINION_SUMMONED), so its source_tag layers only
	# ever exist on its own board. Stripping from the other board would
	# remove a layer that came from the OTHER side's dominion when both
	# boards have the same rune active.
	var board_to_clean: Array = player_board if owner == "player" else enemy_board
	for tag in _harvest_aura_source_tags(rune):
		for m in board_to_clean:
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

## Register 2-rune ritual handlers for the given environment (when it is played).
func _register_env_rituals(env: EnvironmentCardData) -> void:
	for ritual in env.rituals:
		var r: RitualData = ritual
		var h := func(_ctx: EventContext): _handlers.on_env_ritual(r)
		_env_ritual_handlers.append(h)
		trigger_manager.register(Enums.TriggerEvent.ON_RUNE_PLACED, h, 5)
		trigger_manager.register(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, h, 5)

## Run the outgoing environment's on_replace_effect_steps (e.g. strip its
## persistent buffs) when a new environment replaces it. `owner` is the side
## whose environment is leaving.
func _unregister_env_aura(env: EnvironmentCardData, owner: String = "player") -> void:
	if not env.on_replace_effect_steps.is_empty():
		EffectResolver.run(env.on_replace_effect_steps, EffectContext.make(_get_scene_facade(), owner))

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
## per spend (one draw per spend event regardless of amount).
func _on_flesh_spent(_amount: int) -> void:
	var has_flesh_bond := false
	for m in player_board:
		if "flesh_bond" in m.aura_tags:
			has_flesh_bond = true
			break
	if not has_flesh_bond:
		return
	draw_cards("player", 1)
	_log("  Flesh Bond: drew a card.", 1)

## Seris Starter — Fiendish Pact discount peek for a single Demon play.
## Returns the Essence discount to subtract from this play's cost (0 if N/A).
## Does NOT consume the pending — call _consume_fiendish_pact_discount after pay.
func _peek_fiendish_pact_discount(mc: MinionCardData) -> int:
	if _fiendish_pact_pending <= 0:
		return 0
	if mc == null or not mc.is_race(Enums.MinionType.DEMON):
		return 0
	return mini(_fiendish_pact_pending, mc.essence_cost)

## Seris Starter — consume the Fiendish Pact pending discount after a Demon is
## played, and clear the display-only essence_delta on the Demons left in hand.
func _consume_fiendish_pact_discount() -> void:
	if _fiendish_pact_pending <= 0:
		return
	_fiendish_pact_pending = 0
	for inst in player_hand:
		if inst == null or inst.card_data == null:
			continue
		if inst.card_data is MinionCardData and (inst.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
			inst.essence_delta = 0
	if presenter != null:
		presenter._refresh_hand_spell_costs()

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
			if (m.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
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
## `target` is a MinionInstance, null, or a non-minion object (a TrapCardData /
## EnvironmentCardData for Cyclone), which goes to ctx.chosen_object.
func cast_player_targeted_spell(spell: SpellCardData, target, extra_cast_data: Dictionary = {}) -> void:
	var minion_target: MinionInstance = target if target is MinionInstance else null
	emit_event(CombatEvent.Kind.SPELL_CAST, "player", {spell = spell, target = target})
	_pre_player_spell_cast(spell)
	if not spell.effect_steps.is_empty():
		var ctx := EffectContext.make(_get_scene_facade(), "player")
		if target is MinionInstance or target == null:
			ctx.chosen_target = minion_target
		else:
			ctx.chosen_object = target
		ctx.source_card_id = spell.id
		ctx.extra_cast_data = extra_cast_data
		EffectResolver.run(spell.effect_steps, ctx)
	else:
		_resolve_spell_effect(spell.effect_id, minion_target)
	_post_player_spell_cast(spell, minion_target)
	emit_event(CombatEvent.Kind.SPELL_RESOLVED, "player", {spell = spell})

## Compose a player hero-targeted spell cast (the spell hits the enemy hero
## directly). Bypasses EffectResolver: damage is summed from DAMAGE_MINION
## steps with their conditions evaluated, plus _player_spell_damage_bonus.
## The first contributing step's damage_school wins. _post_player_spell_cast
## still runs so Void Resonance recast applies.
func cast_player_hero_spell(spell: SpellCardData) -> void:
	emit_event(CombatEvent.Kind.SPELL_CAST, "player", {spell = spell, target = "enemy_hero"})
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
	var bonus: int = _player_spell_damage_bonus if Enums.has_school(school, Enums.DamageSchool.VOID_FLESH) else 0
	var total: int = base_dmg + bonus
	_log("  %s: %d Void damage to enemy hero." % [spell.card_name, total], 1)  # PLAYER
	combat_manager.apply_hero_damage("enemy",
			CombatManager.make_damage_info(total, Enums.DamageSource.SPELL, school, null, spell.id))
	_post_player_spell_cast(spell, null)
	emit_event(CombatEvent.Kind.SPELL_RESOLVED, "player", {spell = spell})

## Entry point for EffectResolver HARDCODED steps — delegates to the
## HardcodedEffects resolver. Both scene and sim assign _hardcoded in their
## setup; this method works uniformly across both surfaces.
func _resolve_hardcoded(id: String, ctx: EffectContext) -> void:
	if _hardcoded == null:
		return
	_hardcoded.resolve(id, ctx)

## Generic token summon used by EffectResolver SUMMON steps, handlers, relics
## and sim profiles: the first empty slot of `owner`. Returns the instance, or
## null when the board is full or the card is unknown. One body for both
## shells (plan 3.0); the presenter hooks in _spawn_token_into_slot play the
## entrance animation.
func _summon_token(card_id: String, owner: String, token_atk: int = 0, token_hp: int = 0, token_shield: int = 0) -> MinionInstance:
	for s: SlotState in _friendly_slots(owner):
		if s.is_empty():
			return _spawn_token_into_slot(card_id, owner, s, token_atk, token_hp, token_shield)
	return null

## Slot-pinned variant: summon into a specific slot (e.g. Rally the Ranks's
## adjacent-to-target placement). Silently fizzles (returns null) if the slot
## is null, off-board, or already occupied — the "up to 2" semantics.
func _summon_token_at_slot(card_id: String, owner: String, slot: SlotState, token_atk: int = 0, token_hp: int = 0, token_shield: int = 0) -> MinionInstance:
	if slot == null or not slot.is_empty():
		return null
	return _spawn_token_into_slot(card_id, owner, slot, token_atk, token_hp, token_shield)

## Shared core: card lookup + stat overrides + place + emit + trigger fire.
## Synchronous on both shells. The presenter freezes the slot node before the
## placement when an entrance animation will reveal it (`_prepare_token_reveal`)
## and plays that animation after the triggers (`_play_token_summon`).
func _spawn_token_into_slot(card_id: String, owner: String, slot: SlotState, token_atk: int = 0, token_hp: int = 0, token_shield: int = 0) -> MinionInstance:
	# Combat-time lookup so clan rules / overrides apply to tokens summoned mid-fight.
	var base := _card_for(owner, card_id)
	if base == null or not (base is MinionCardData):
		return null
	var board := player_board if owner == "player" else enemy_board
	var mc := (base as MinionCardData).duplicate() as MinionCardData
	if token_atk > 0:    mc.atk        = token_atk
	if token_hp > 0:     mc.health     = token_hp
	if token_shield > 0: mc.shield_max = token_shield
	var instance := MinionInstance.create(mc, owner)
	board.append(instance)
	if presenter != null:
		presenter._prepare_token_reveal(instance, mc, owner, slot.index)
	slot.place(instance)
	minion_summoned.emit(owner, instance, slot.index)
	emit_event(CombatEvent.Kind.CHAMPION_SUMMONED if mc.is_champion else CombatEvent.Kind.TOKEN_SUMMONED, owner,
			{minion = instance, card = mc, slot = slot.index})
	_log("  %s summoned!" % mc.card_name, 1)  # PLAYER
	if trigger_manager != null:
		var event := Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED
		var ctx := EventContext.make(event, owner)
		ctx.minion = instance
		ctx.card   = mc
		trigger_manager.fire(ctx)
	if presenter != null:
		presenter._play_token_summon(instance, mc, slot.index)
	return instance

## Apply spell damage to a single minion target. Adds _player_spell_damage_bonus
## (Void Amplification — scaled per friendly Demon Corruption stack at cast
## time) to the call-site's amount, then routes through combat_manager to
## apply damage. Emits `spell_damage_dealt` so live combat can spawn the flash
## + damage popup; sim has no subscriber and so just applies the damage.
##
## Both callers pass the PRE-bonus damage; the bonus is added once here.
## The bonus only applies when the damage school satisfies VOID_FLESH —
## Void Amplification is a flesh-flavored amp (Seris cards are blood/flesh
## themed), so neutral/PHYSICAL/VOID/VOID_BOLT/VOID_CORRUPTION spells are
## unaffected even when the player has the talent active.
func _spell_dmg(target: MinionInstance, amount: int, info: Dictionary = {}) -> void:
	if target == null:
		return
	var school: int = Enums.DamageSchool.NONE
	if not info.is_empty() and info.has("school"):
		school = info["school"]
	var bonus: int = _player_spell_damage_bonus if Enums.has_school(school, Enums.DamageSchool.VOID_FLESH) else 0
	var total: int = amount + bonus
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
	spell_damage_dealt.emit(target, amount, school)
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
		var roll: String = rng_pick(_FORGED_DEMON_AURAS)
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
	if not (minion.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
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
	_debug_soul_forge_fires += 1
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
		# Track owner alongside rune_id so _remove_rune_aura can target the
		# correct side's handler when both boards have the same rune type
		# active simultaneously (e.g. mirror match-up of dominion_rune).
		_rune_aura_handlers.append({rune_id = rune.id, owner = owner, entries = entries})

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
	# The presenter snapshots the rune panels now (before consumption) and
	# plays the merge VFX fire-and-forget (plan 3.0).
	if presenter != null:
		presenter._on_ritual_firing(ritual)
	_player_ritual_count += 1
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
	_update_trap_display_for("player")
	_log("★ RITUAL — %s!" % ritual.ritual_name, 1)  # PLAYER
	emit_event(CombatEvent.Kind.RITUAL_FIRED, "player", {ritual = ritual, consumed = consumed_indices})
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
## Removes the minion from its board and frees its slot, then hands the
## presenter the death animation (same hook as a death).
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
	# Step 4 — remove from board and free the slot. The live view keeps a
	# frozen node's art until the death animation flushes it (plan 3.1a).
	_friendly_board(minion.owner).erase(minion)
	var sac_slot: SlotState = slot_for(minion)
	var sac_index: int = sac_slot.index if sac_slot != null else -1
	if sac_slot != null:
		sac_slot.clear()
	_log("  %s was sacrificed" % minion.card_data.card_name, 6)  # DEATH
	emit_event(CombatEvent.Kind.MINION_SACRIFICED, minion.owner, {minion = minion, slot = sac_index})
	if presenter != null:
		presenter._on_minion_vanished_visual(minion, sac_index)

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
	# The projectile is presentation (plan 3.0): it flies while the damage lands now.
	if presenter != null:
		presenter._fire_void_bolt_projectile(source_minion, from_rune)
	var bonus: int = enemy_void_marks * void_mark_damage_per_stack
	var total: int = base_damage + bonus
	# Korrath B3 T2 Path of Corruption — gated by school: Path of Corruption
	# only amplifies VOID_CORRUPTION-tagged damage. Void Bolt damage is
	# VOID_BOLT (sibling of VOID_CORRUPTION under VOID parent), so it does
	# NOT satisfy has_school(VOID_BOLT, VOID_CORRUPTION) → no amp. This branch
	# is kept for the post-damage corruption application below (the talent's
	# second half still fires on spell-cast Void Bolts). Minion-emitted Void
	# Bolts (void_manifestation talent retag) don't qualify as spells.
	var ruination_active: bool = (not is_minion_emitted) and _path_of_corruption_active
	if bonus > 0:
		_log("  Void Bolt: %d dmg (base %d + %d from %d marks)" % [total, base_damage, bonus, enemy_void_marks], 1)  # PLAYER
	else:
		_log("  Void Bolt: %d damage." % total, 1)
	var base_source: String = _pending_dmg_source
	if base_source.is_empty():
		base_source = "void_rune" if from_rune else "void_bolt_spell"
	emit_event(CombatEvent.Kind.VOID_BOLT, "player", {amount = total, source_minion = source_minion, from_rune = from_rune})
	_pending_dmg_source = base_source
	# Split log: base damage + mark bonus separately (sim diagnostic; live combat ignores).
	if dmg_log_enabled:
		dmg_log.append({turn = turn_number, amount = base_damage, source = base_source})
		if bonus > 0:
			dmg_log.append({turn = turn_number, amount = bonus, source = "void_mark"})
		_pending_dmg_source = "__logged__"  # signal _on_hero_damaged to skip logging
	var src: Enums.DamageSource = Enums.DamageSource.MINION if is_minion_emitted else Enums.DamageSource.SPELL
	combat_manager.apply_hero_damage("enemy",
			CombatManager.make_damage_info(total, src, Enums.DamageSchool.VOID_BOLT, source_minion, base_source))
	_void_bolt_total_dmg += total
	if ruination_active:
		_corrupt_hero("enemy")

## Apply enemy-cast Void Bolt damage to the player hero. Does not participate
## in Void Marks (those only apply to the enemy hero). The presenter fires the
## projectile; the damage lands now (plan 3.0).
func _deal_enemy_void_bolt_damage(base_damage: int, source_minion: MinionInstance = null, is_minion_emitted: bool = false) -> void:
	if presenter != null:
		presenter._fire_enemy_void_bolt_projectile(source_minion)
	_log("  Void Bolt: %d damage." % base_damage, 2)  # ENEMY
	emit_event(CombatEvent.Kind.VOID_BOLT, "enemy", {amount = base_damage, source_minion = source_minion, from_rune = false})
	var base_source: String = _pending_dmg_source
	if base_source.is_empty():
		base_source = "enemy_void_bolt"
	_pending_dmg_source = base_source
	if dmg_log_enabled:
		dmg_log.append({turn = turn_number, amount = base_damage, source = base_source})
		_pending_dmg_source = "__logged__"
	var src: Enums.DamageSource = Enums.DamageSource.MINION if is_minion_emitted else Enums.DamageSource.SPELL
	combat_manager.apply_hero_damage("player",
			CombatManager.make_damage_info(base_damage, src, Enums.DamageSchool.VOID_BOLT, source_minion, base_source))

## A trap fired: removed from its slot (unless reusable) and about to resolve.
signal trap_fired(owner: String, trap: TrapCardData, slot_index: int)

## The trap routes (plan 2A.2) — [event, owner of the traps it springs, priority].
## A trap springs when its `trigger` equals the event exactly (no mirroring).
## CombatSetup.setup registers these first so equal-priority handlers keep
## live's order. The player's ON_PLAYER_MINION_DIED route only springs during
## the enemy's turn.
const TRAP_ROUTES: Array = [
	[Enums.TriggerEvent.ON_PLAYER_MINION_DIED,     "player", 20],
	[Enums.TriggerEvent.ON_ENEMY_TURN_START,       "player", 30],
	[Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED,  "player", 30],
	[Enums.TriggerEvent.ON_ENEMY_SPELL_CAST,       "player", 30],
	[Enums.TriggerEvent.ON_ENEMY_ATTACK,           "player", 30],
	[Enums.TriggerEvent.ON_HERO_DAMAGED,           "player", 10],
	[Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "enemy",  35],
	[Enums.TriggerEvent.ON_PLAYER_SPELL_CAST,      "enemy",  35],
	[Enums.TriggerEvent.ON_PLAYER_TURN_START,      "enemy",  35],
]

## Trap route handler: springs `owner`'s traps for the event.
func _on_trap_route(ctx: EventContext, owner: String) -> void:
	if ctx.event_type == Enums.TriggerEvent.ON_PLAYER_MINION_DIED and is_player_turn:
		return  # friendly-death traps react to the enemy's kills only
	_fire_traps_for(owner, ctx.event_type, ctx.minion)

## Spring `owner`'s non-rune traps whose trigger is `trigger` (skipped while the
## side's traps are blocked by Saboteur Adept). Each is consumed (unless
## reusable) before it resolves, so a second trigger mid-resolution can't
## re-fire it. Each trap resolves inline on both shells (B12 fixed, plan 3.0);
## with a presenter its card animation is started first, fire-and-forget.
func _fire_traps_for(owner: String, trigger: int, triggering_minion: MinionInstance = null) -> void:
	if owner == "enemy" and _enemy_traps_blocked:
		return
	if owner == "player" and _player_traps_blocked:
		return
	var traps: Array[TrapCardData] = traps_of(owner)
	var matching: Array[TrapCardData] = []
	for trap: TrapCardData in traps:
		if not trap.is_rune and trap.trigger == trigger:
			matching.append(trap)
	var reveals: Array = []
	for trap: TrapCardData in matching:
		var slot_idx: int = traps.find(trap)
		if slot_idx < 0:
			continue  # removed by an earlier trap's resolution
		_log("⚡ %s%s triggered!" % [("Enemy " if owner == "enemy" else ""), trap.card_name], 5)  # TRAP
		if not trap.reusable:
			traps.erase(trap)
			_update_trap_display_for(owner)
		trap_fired.emit(owner, trap, slot_idx)
		emit_event(CombatEvent.Kind.TRAP_FIRED, owner, {trap = trap, slot = slot_idx})
		# Reveal first (fire-and-forget card animation), then resolve inline
		# (plan 3.0 / B12: the effect lands on the event that sprang it).
		if presenter != null:
			presenter.play_trap_reveals(owner, [{trap = trap, slot_index = slot_idx}])
		var ctx := EffectContext.make(_get_scene_facade(), owner)
		ctx.trigger_minion = triggering_minion
		EffectResolver.run(trap.effect_steps, ctx)

## Compose an enemy spell cast resolution. The pre/post-cast hooks (Seris
## Void Amplification / Void Resonance) are player-only and not invoked here.
## The trigger ON_ENEMY_SPELL_CAST fires before this method (Null Seal can
## cancel via _spell_cancelled; caller short-circuits in that case).
func cast_enemy_spell(spell: SpellCardData, chosen, extra_cast_data: Dictionary = {}) -> void:
	emit_event(CombatEvent.Kind.SPELL_CAST, "enemy", {spell = spell, target = chosen})
	if not spell.effect_steps.is_empty():
		var ectx := EffectContext.make(_get_scene_facade(), "enemy")
		ectx.source_card_id = spell.id
		ectx.extra_cast_data = extra_cast_data
		if chosen is MinionInstance:
			ectx.chosen_target = chosen
		else:
			ectx.chosen_object = chosen
		EffectResolver.run(spell.effect_steps, ectx)
	elif not spell.effect_id.is_empty():
		_resolve_spell_effect(spell.effect_id, null, "enemy")
	emit_event(CombatEvent.Kind.SPELL_RESOLVED, "enemy", {spell = spell})

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
	if not (target.card_data as MinionCardData).is_race(Enums.MinionType.DEMON):
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
	_debug_corrupt_flesh_fires += 1
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
## When Korrath B3 T0 corrupting_presence is active, also emits a one-shot
## permanent +100 ARMOUR_BREAK stack onto enemy targets — the AB is not coupled
## to the corruption stack after creation, so cleansing the corruption later
## leaves the AB intact (permanent armour reduction, per design).
## Logs and refreshes the slot via signals — live UI subscriber animates the
## refresh; sim has no subscribers so the call is data-only. Live combat
## additionally spawns CorruptionApplyVFX in the CombatScene wrapper.
func _corrupt_minion(target: MinionInstance) -> void:
	var penalty := 100
	BuffSystem.apply(target, Enums.BuffType.CORRUPTION, penalty, "corruption", false, false)
	_log("  %s is Corrupted! (−%d ATK)" % [target.card_data.card_name, penalty], 2)  # CombatLog.LogType.ENEMY = 2
	if _corrupting_presence_active and target.owner == "enemy":
		BuffSystem.apply(target, Enums.BuffType.ARMOUR_BREAK, 100, "corrupting_presence", false, false)
	_refresh_slot_for(target)
	emit_event(CombatEvent.Kind.CORRUPTION_APPLIED, target.owner, {minion = target, stacks = BuffSystem.count_type(target, Enums.BuffType.CORRUPTION)})
	if presenter != null:
		presenter._show_corruption_applied(target)

## Apply one Corruption stack to a hero. Mirror of _corrupt_minion for the hero
## debuff path (corrupting_strike against enemy hero, path_of_corruption spells
## targeting hero). Same corrupting_presence one-shot AB rule applies on the
## enemy hero. No ATK penalty (heroes have no ATK stat); corruption is read by
## path_of_corruption's spell-amp and its own future hooks.
func _corrupt_hero(side: String) -> void:
	apply_hero_buff(side, Enums.BuffType.CORRUPTION, 100, "corruption")
	if _corrupting_presence_active and side == "enemy":
		apply_hero_buff(side, Enums.BuffType.ARMOUR_BREAK, 100, "corrupting_presence")
	# Log type swaps by which side received the debuff: enemy-corrupted is good
	# news for the player (PLAYER), player-corrupted is bad (ENEMY).
	var hero_label: String = "You are" if side == "player" else "Enemy hero is"
	_log("  %s Corrupted!" % hero_label, 1 if side == "enemy" else 2)

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
	emit_event(CombatEvent.Kind.MINION_HEALED, minion.owner, {minion = minion, amount = healed, hp_before = before, hp_after = minion.current_health})
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
# Hero state — `player_hp` / `enemy_hp` / `player_hp_max` / `enemy_hp_max` are
# property forwarders onto `player_hero` / `enemy_hero` (HeroState). The backing
# HeroState carries hp/hp_max plus Korrath Armour and a buffs container that
# BuffSystem reads via duck-typing (PR2 wires AB on heroes). Writes to player_hp
# emit `hp_changed` automatically. Direct hero.hp writes bypass the signal and
# should NOT be used outside CombatState.
# ---------------------------------------------------------------------------

var player_hero: HeroState = HeroState.create("player", 0)
var enemy_hero:  HeroState = HeroState.create("enemy",  0)

var player_hp: int:
	get: return player_hero.hp
	set(v):
		if v == player_hero.hp:
			return
		var delta := v - player_hero.hp
		player_hero.hp = v
		hp_changed.emit("player", v, player_hero.hp_max, delta)
		emit_event(CombatEvent.Kind.HERO_HP_CHANGED, "player", {hp = v, hp_max = player_hero.hp_max, delta = delta})

var enemy_hp: int:
	get: return enemy_hero.hp
	set(v):
		if v == enemy_hero.hp:
			return
		var delta := v - enemy_hero.hp
		enemy_hero.hp = v
		hp_changed.emit("enemy", v, enemy_hero.hp_max, delta)
		emit_event(CombatEvent.Kind.HERO_HP_CHANGED, "enemy", {hp = v, hp_max = enemy_hero.hp_max, delta = delta})

## Player hero max HP — set by CombatScene._ready from GameManager.player_hp_max
## (varies with hero/talents). Sim sets this directly via SimState.setup() and
## currently leaves it at 0 since sim runs on absolute HP values; setup overrides.
var player_hp_max: int:
	get: return player_hero.hp_max
	set(v): player_hero.hp_max = v
var enemy_hp_max: int:
	get: return enemy_hero.hp_max
	set(v): enemy_hero.hp_max = v

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

## Engine-owned occupancy (plan 3.1a, D11): BOARD_MAX plain SlotStates per
## side, allocated here for both shells. The live slot Panels are views —
## `slot_changed` tells CombatScene which one to refresh.
var player_slots: Array[SlotState] = []
var enemy_slots:  Array[SlotState] = []

## A slot's occupant changed (`SlotState.place` / `clear`).
signal slot_changed(side: String, index: int)

func _init() -> void:
	_alloc_slots()

func _alloc_slots() -> void:
	player_slots.clear()
	enemy_slots.clear()
	for i in BOARD_MAX:
		var ps := SlotState.make("player", i)
		ps.changed.connect(_on_slot_state_changed)
		player_slots.append(ps)
		var es := SlotState.make("enemy", i)
		es.changed.connect(_on_slot_state_changed)
		enemy_slots.append(es)

func _on_slot_state_changed(slot: SlotState) -> void:
	slot_changed.emit(slot.side, slot.index)
	emit_event(CombatEvent.Kind.SLOT_CHANGED, slot.side, {slot = slot.index, minion = slot.minion})

## The slot at `index` on `side`, or null when off-board.
func slot_of(side: String, index: int) -> SlotState:
	var slots: Array[SlotState] = player_slots if side == "player" else enemy_slots
	if index < 0 or index >= slots.size():
		return null
	return slots[index]

## The slot `minion` occupies on its own side, or null when it is not on the board.
func slot_for(minion: MinionInstance) -> SlotState:
	if minion == null:
		return null
	for s: SlotState in (player_slots if minion.owner == "player" else enemy_slots):
		if s.minion == minion:
			return s
	return null

# ---------------------------------------------------------------------------
# Turn, resources, decks, hands, graveyards — both sides (plan 1.3). Live's
# TurnManager (player) and EnemyAI (enemy) forward their fields here; sim reads
# them directly. Mutators that live's UI shows (spend / gain / convert) emit
# `resources_changed`; TurnManager relays the player side to its own signal.
# ---------------------------------------------------------------------------

## (side, essence, essence_max, mana, mana_max) after a spend / gain / convert,
## or when a caller asks with emit_resources(). Live relays the player side.
signal resources_changed(side: String, essence: int, essence_max: int, mana: int, mana_max: int)
## A card moved deck → hand. Live relays the player side to the hand display.
signal card_drawn(side: String, inst: CardInstance)
## A card was created straight into a hand (not drawn). Live relays the player side.
signal card_generated(side: String, inst: CardInstance)

const HAND_MAX := 10
## essence_max + mana_max can never exceed this (both sides).
const COMBINED_RESOURCE_CAP := 11
## Absolute ceiling on current Essence — conversion can exceed essence_max up to this.
const ESSENCE_HARD_CAP := 10

## Round number, incremented at each player turn start (the opening round is 1).
## Stamps graveyard entries (resolved_on_turn) and the sim damage log.
var turn_number: int = 0
## True during the player's turn.
var is_player_turn: bool = true

var player_essence: int = 0
var _player_essence_max: int = 0
## Any increase records the choice for F15 abyssal_mandate (`last_player_growth`).
var player_essence_max: int:
	get: return _player_essence_max
	set(v):
		if v > _player_essence_max:
			last_player_growth = "essence"
		_player_essence_max = v
var player_mana: int = 0
var _player_mana_max: int = 0
var player_mana_max: int:
	get: return _player_mana_max
	set(v):
		if v > _player_mana_max:
			last_player_growth = "mana"
		_player_mana_max = v

var enemy_essence: int = 0
var enemy_essence_max: int = 0
var enemy_mana: int = 0
var enemy_mana_max: int = 0

var player_deck: Array[CardInstance] = []
var player_hand: Array[CardInstance] = []
## Every card the player played this combat, in play order (minions, spells,
## traps, runes, environments), each stamped with `resolved_on_turn`.
var player_graveyard: Array[CardInstance] = []
## The enemy deck never runs out: each draw puts a fresh copy back and reshuffles
## (except ids in enemy_limited_cards, which are drawn once per copy).
var enemy_deck: Array[CardInstance] = []
var enemy_hand: Array[CardInstance] = []
var enemy_graveyard: Array[CardInstance] = []
var enemy_limited_cards: Array[String] = []

## Set by Smoke Veil while an enemy attack is being declared; the attack
## executor checks it after firing ON_ENEMY_ATTACK and skips the attack.
var attack_cancelled: bool = false
## On-play target the enemy executor chose for the minion it is playing; read
## (and cleared) by the ON_ENEMY_MINION_PLAYED handler.
var enemy_play_target = null

func hand_of(side: String) -> Array[CardInstance]:
	return player_hand if side == "player" else enemy_hand

func deck_of(side: String) -> Array[CardInstance]:
	return player_deck if side == "player" else enemy_deck

func graveyard_of(side: String) -> Array[CardInstance]:
	return player_graveyard if side == "player" else enemy_graveyard

func traps_of(side: String) -> Array[TrapCardData]:
	return active_traps if side == "player" else enemy_active_traps

func environment_of(side: String) -> EnvironmentCardData:
	return active_environment if side == "player" else enemy_active_environment

func set_environment(side: String, env: EnvironmentCardData) -> void:
	if side == "player":
		active_environment = env
	else:
		enemy_active_environment = env
	emit_event(CombatEvent.Kind.ENVIRONMENT_CHANGED, side, {env = env})

func essence_of(side: String) -> int:
	return player_essence if side == "player" else enemy_essence

func mana_of(side: String) -> int:
	return player_mana if side == "player" else enemy_mana

func essence_max_of(side: String) -> int:
	return player_essence_max if side == "player" else enemy_essence_max

func mana_max_of(side: String) -> int:
	return player_mana_max if side == "player" else enemy_mana_max

func set_essence(side: String, v: int) -> void:
	if side == "player":
		player_essence = v
	else:
		enemy_essence = v

func set_mana(side: String, v: int) -> void:
	if side == "player":
		player_mana = v
	else:
		enemy_mana = v

func emit_resources(side: String) -> void:
	resources_changed.emit(side, essence_of(side), essence_max_of(side), mana_of(side), mana_max_of(side))
	emit_event(CombatEvent.Kind.RESOURCES_CHANGED, side, {essence = essence_of(side), essence_max = essence_max_of(side), mana = mana_of(side), mana_max = mana_max_of(side)})

## Start-of-turn refill to the maxima. Does not emit (the turn flow emits once
## after drawing).
func refill_resources(side: String) -> void:
	set_essence(side, essence_max_of(side))
	set_mana(side, mana_max_of(side))

func can_afford(side: String, essence_cost: int, mana_cost: int) -> bool:
	return essence_of(side) >= essence_cost and mana_of(side) >= mana_cost

func spend_essence(side: String, amount: int) -> bool:
	if essence_of(side) < amount:
		return false
	set_essence(side, essence_of(side) - amount)
	emit_resources(side)
	return true

func spend_mana(side: String, amount: int) -> bool:
	if mana_of(side) < amount:
		return false
	set_mana(side, mana_of(side) - amount)
	emit_resources(side)
	return true

## Bonus Essence this turn — not capped by essence_max (the next refill resets it).
func gain_essence(side: String, amount: int) -> void:
	set_essence(side, essence_of(side) + amount)
	emit_resources(side)

## Bonus Mana this turn, capped at mana_max.
func gain_mana(side: String, amount: int) -> void:
	set_mana(side, mini(mana_of(side) + amount, mana_max_of(side)))
	emit_resources(side)

## +amount Essence max, one at a time, stopping at the combined cap. No emit.
func grow_essence_max(side: String, amount: int = 1) -> void:
	for _i in amount:
		if essence_max_of(side) + mana_max_of(side) >= COMBINED_RESOURCE_CAP:
			break
		if side == "player":
			player_essence_max += 1
		else:
			enemy_essence_max += 1

## +amount Mana max, one at a time, stopping at the combined cap. No emit.
func grow_mana_max(side: String, amount: int = 1) -> void:
	for _i in amount:
		if essence_max_of(side) + mana_max_of(side) >= COMBINED_RESOURCE_CAP:
			break
		if side == "player":
			player_mana_max += 1
		else:
			enemy_mana_max += 1

## All current Essence into Mana, capped at mana_max (Energy Conversion).
func convert_essence_to_mana(side: String) -> void:
	var amount: int = essence_of(side)
	set_essence(side, 0)
	set_mana(side, mini(mana_of(side) + amount, mana_max_of(side)))
	emit_resources(side)

## Up to `max_convert` Mana (all if < 0) into Essence — ignores essence_max and
## the combined cap; only ESSENCE_HARD_CAP applies.
func convert_mana_to_essence(side: String, max_convert: int = -1) -> void:
	var amount: int = mana_of(side) if max_convert < 0 else mini(mana_of(side), max_convert)
	set_mana(side, mana_of(side) - amount)
	set_essence(side, mini(essence_of(side) + amount, ESSENCE_HARD_CAP))
	emit_resources(side)

## Stamp `resolved_on_turn` and append to the side's graveyard.
func send_to_graveyard(side: String, inst: CardInstance) -> void:
	inst.resolved_on_turn = turn_number
	graveyard_of(side).append(inst)

## A card leaves the hand to be played: erase it and send it to the graveyard.
func remove_from_hand(side: String, inst: CardInstance) -> void:
	hand_of(side).erase(inst)
	send_to_graveyard(side, inst)

## Build `side`'s deck from card ids (combat-time lookup, so overrides apply) and
## shuffle it on the engine RNG. Clears that side's hand and graveyard. The
## enemy draws its opening 5 here; the player's opening hand is drawn by the
## turn flow.
func setup_deck(side: String, card_ids: Array[String]) -> void:
	var deck: Array[CardInstance] = deck_of(side)
	deck.clear()
	hand_of(side).clear()
	graveyard_of(side).clear()
	for id in card_ids:
		var card: CardData = _card_for(side, id)
		if card != null:
			deck.append(CardInstance.create(card))
	rng_shuffle(deck)
	if side == "enemy":
		draw_cards("enemy", 5)

## Draw `count` cards. Player: finite deck; a draw into a full hand burns the
## card; each draw emits card_drawn and fires ON_PLAYER_CARD_DRAWN. Enemy: a full
## hand stops drawing; the drawn card is replaced in the deck by a fresh copy
## (unless limited) and the deck reshuffled.
func draw_cards(side: String, count: int = 1) -> void:
	for _i in count:
		if side == "player":
			if player_deck.is_empty():
				return
			var drawn: CardInstance = player_deck.pop_front()
			if player_hand.size() >= HAND_MAX:
				continue  # burned
			player_hand.append(drawn)
			card_drawn.emit("player", drawn)
			emit_event(CombatEvent.Kind.CARD_DRAWN, "player", {inst = drawn})
			_fire_card_drawn(drawn)
		else:
			if enemy_hand.size() >= HAND_MAX or enemy_deck.is_empty():
				return
			var inst: CardInstance = enemy_deck.pop_front()
			enemy_hand.append(inst)
			if inst.card_data.id not in enemy_limited_cards:
				enemy_deck.append(CardInstance.create(inst.card_data))
				rng_shuffle(enemy_deck)
			card_drawn.emit("enemy", inst)
			emit_event(CombatEvent.Kind.CARD_DRAWN, "enemy", {inst = inst})

## Put a card straight into `side`'s hand (a CardData gets a fresh instance).
## Silently burned when the hand is full. Player side emits card_generated and
## fires ON_PLAYER_CARD_DRAWN, like a draw. Returns the instance, or null if burned.
func add_to_hand(side: String, card: Variant) -> CardInstance:
	var inst: CardInstance = card if card is CardInstance else CardInstance.create(card as CardData)
	var hand: Array[CardInstance] = hand_of(side)
	if hand.size() >= HAND_MAX:
		return null
	hand.append(inst)
	card_generated.emit(side, inst)
	emit_event(CombatEvent.Kind.CARD_GENERATED, side, {inst = inst})
	if side == "player":
		_fire_card_drawn(inst)
	return inst

func _fire_card_drawn(inst: CardInstance) -> void:
	if trigger_manager == null:
		return
	var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_CARD_DRAWN, "player")
	ctx.card = inst.card_data
	trigger_manager.fire(ctx)

# ---------------------------------------------------------------------------
# Traps / environments / runes / void marks
# ---------------------------------------------------------------------------

## Player-side active traps & runes (shared pool, max 3 slots).
var active_traps: Array[TrapCardData] = []
## Player-side active global environment.
var active_environment: EnvironmentCardData = null

## Enemy-side mirror. Single source of truth for both live combat and sim —
## live's EnemyAI.active_traps / active_environment forward here.
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
		emit_event(CombatEvent.Kind.VOID_MARKS_CHANGED, "enemy", {value = v})

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
		emit_event(CombatEvent.Kind.FLESH_CHANGED, "player", {value = v, max = player_flesh_max})
var player_flesh_max: int = 5

## Seris — Fiendish Pact pending Essence discount. Set by the Fiendish Pact spell,
## consumed when the next Demon is played (capped at that card's essence_cost).
var _fiendish_pact_pending: int = 0
## Enemy-side counterpart — armed when an enemy casts Fiendish Pact, consumed
## when the enemy next plays a Demon. Cleared at enemy turn start.
var _enemy_fiendish_pact_pending: int = 0

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
		emit_event(CombatEvent.Kind.FORGE_CHANGED, "player", {value = v, threshold = forge_counter_threshold})
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
## Symmetric — when true, the enemy's current mana is set to 0 at the start of their next turn.
var _enemy_void_mana_drain_pending: bool = false

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

## Per-combat relic charges/cooldowns. Built by CombatScene._setup_relics (live)
## or CombatSim.run (sim); null when the player carries no relics in sim.
var relic_runtime: RelicRuntime = null

var _relic_hero_immune: bool = false   ## Bone Shield: ignore damage this turn
var _relic_cost_reduction: int = 0     ## Dark Mirror: reduce next card cost

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
## Korrath T3 Unbreakable — when true, MinionInstance.add_armour() doubles positive
## armour gains for the abyssal_knight card. Set via CombatSetup._REGISTRY stats when
## the unbreakable talent is unlocked.
var _armour_doubled_on_knight: bool = false

## Korrath B3 T0 Corrupting Presence — when true, CombatManager._deal_damage strips
## an additional 100 effective Armour per Corruption stack on enemy targets, ahead
## of Armour Break (corruption is treated as armour erosion, AB does its strip+overflow
## on the post-corruption value). No overflow conversion for corruption.
var _corrupting_presence_active: bool = false

## Korrath B3 T2 Path of Corruption — when true, EffectResolver's DAMAGE_MINION step
## (a) applies +100 spell damage per Corruption stack on the target before damage
## resolves and (b) applies 1 Corruption to the target after the hit. Both halves
## live inside the resolver so AOE spells naturally hit each target once.
var _path_of_corruption_active: bool = false

## Korrath B2 — five rune card IDs randomly placed by Runeforge Strike's
## on-attack rune generation. Order is irrelevant; randomness comes from `rng_pick()`.
const KORRATH_RUNE_IDS: Array[String] = [
	"void_rune", "blood_rune", "dominion_rune", "shadow_rune", "soul_rune",
]

## Trap / rune slots per side (the UI shows this many trap_slot_panels).
const TRAP_SLOTS_MAX: int = 3
## Maximum runes the player can have on board at once — Korrath B2 absorption.
const KORRATH_RUNE_BOARD_CAP: int = TRAP_SLOTS_MAX

## Korrath B2 T0 — place a random rune on the player's board. If the rune board
## is full and B2 T1 `runic_absorption` is unlocked, destroy a random existing rune
## to free a slot — the destruction routes through _remove_rune_aura and grants
## the absorbed aura automatically via the centralized T1 hook. If full and T1 is
## NOT unlocked, the new rune is silently dropped (board unchanged). Symmetric
## across scene/sim.
func _korrath_place_random_rune() -> void:
	if active_traps.size() >= KORRATH_RUNE_BOARD_CAP:
		if not ("runic_absorption" in talents):
			return  # board full, no T1 — drop the new rune
		var runes: Array = active_traps.filter(func(t): return (t as TrapCardData).is_rune)
		if runes.is_empty():
			return
		var victim: TrapCardData = rng_pick(runes)
		_remove_rune_aura(victim, "player")
		active_traps.erase(victim)
	var rune_id: String = rng_pick(KORRATH_RUNE_IDS)
	var rune: TrapCardData = CardDatabase.get_card(rune_id) as TrapCardData
	if rune == null:
		return
	active_traps.append(rune)
	_apply_rune_aura(rune, "player")
	if trigger_manager != null:
		var ctx := EventContext.make(Enums.TriggerEvent.ON_RUNE_PLACED, "player")
		ctx.card = rune
		trigger_manager.fire(ctx)

## Korrath B2 T1 — grant one absorbed-aura stack of `rune_id` to a random friendly
## Abyssal Knight. Stack is silently lost if no Knight is on board. Called from
## _remove_rune_aura on every player-side rune destruction/consumption when T1
## is unlocked. The aura tag (e.g. "void_rune") lives on the knight for X-counting
## in path_of_demons / path_of_humans.
func _korrath_grant_absorbed_aura(rune_id: String) -> void:
	var knights: Array = player_board.filter(
		func(m): return m != null and m.card_data != null and m.card_data.id == "abyssal_knight")
	if knights.is_empty():
		return
	var knight: MinionInstance = rng_pick(knights)
	knight.aura_tags.append(rune_id)

## Total absorbed-rune-aura stacks across all friendly Abyssal Knights on board.
## Used by path_of_demons / path_of_humans X-counting (X = active_rune_slots + this).
func _korrath_absorbed_aura_count() -> int:
	var count: int = 0
	for raw in player_board:
		var m: MinionInstance = raw as MinionInstance
		if m == null or m.card_data == null or m.card_data.id != "abyssal_knight":
			continue
		for tag in m.aura_tags:
			if tag in KORRATH_RUNE_IDS:
				count += 1
	return count
var _vw_death_crit_grants: int = 0
var _vw_behemoth_lost: Dictionary = {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}
var _vw_bastion_lost: Dictionary = {"consumed": 0, "damage": 0, "combat": 0, "survived": 0}
var _champion_vc_tc_cast: int = 0
var _champion_vc_summoned: bool = false
var _champion_vch_crit_kills: int = 0
var _champion_vch_summoned: bool = false
var _champion_vrp_spells_cast: int = 0
var _champion_vrp_summoned: bool = false
# F15 Abyss Sovereign — counts player cards played; threshold tuned so the
# champion lands in Phase 2 in the average run.
var _champion_as_cards_played: int = 0
var _champion_as_summoned: bool = false
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
## Seris button presses (Soul Forge / Corrupt Flesh) — BalanceSim behaviour reports.
var _debug_soul_forge_fires: int = 0
var _debug_corrupt_flesh_fires: int = 0
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
var _pending_dmg_source: String = ""

# ---------------------------------------------------------------------------
# CombatManager signal handlers — one body for both shells (plan 1.4). Both
# CombatScene and SimState connect combat_manager's minion_vanished /
# hero_damaged / hero_healed here; the presenter hooks play the animations.
# ---------------------------------------------------------------------------

## A minion left the board through death. Removes it from board + slot (the
## live view keeps a frozen node's art until the death animation flushes it),
## emits minion_died, then fires ON_CORRUPTION_REMOVED (stacks it held) and
## ON_*_MINION_DIED with the attacker.
func _on_minion_vanished(minion: MinionInstance) -> void:
	var dead_slot: SlotState = slot_for(minion)
	var dead_index: int = dead_slot.index if dead_slot != null else -1
	_friendly_board(minion.owner).erase(minion)
	if dead_slot != null:
		dead_slot.clear()
	minion_died.emit(minion.owner, minion, dead_index)
	emit_event(CombatEvent.Kind.MINION_DIED, minion.owner, {minion = minion, slot = dead_index, attacker = _last_attacker})
	_log("  %s died" % minion.card_data.card_name, 6)  # DEATH
	# On-death effects resolve inline in the death trigger (D3); the presenter
	# plays the death animation and on-death icon before what follows.
	if trigger_manager != null:
		var pre_corruption: int = BuffSystem.count_type(minion, Enums.BuffType.CORRUPTION)
		if pre_corruption > 0:
			var rm_ctx := EventContext.make(Enums.TriggerEvent.ON_CORRUPTION_REMOVED, minion.owner)
			rm_ctx.minion = minion
			rm_ctx.damage = pre_corruption
			trigger_manager.fire(rm_ctx)
		var event := Enums.TriggerEvent.ON_PLAYER_MINION_DIED if minion.owner == "player" \
			else Enums.TriggerEvent.ON_ENEMY_MINION_DIED
		var ctx := EventContext.make(event, minion.owner)
		ctx.minion = minion
		ctx.attacker = _last_attacker
		trigger_manager.fire(ctx)
	if presenter != null:
		presenter._on_minion_vanished_visual(minion, dead_index)

## A hero took damage. Bone Shield absorbs player damage. Fires ON_HERO_DAMAGED /
## ON_ENEMY_HERO_DAMAGED on every landed hit (lethal included). The first lethal
## hit sets `winner` — except on the F15 Sovereign's Phase 1, which transitions
## to Phase 2 instead. The presenter gets the outcome ("", "lethal", "transition").
func _on_hero_damaged(target: String, info: Dictionary) -> void:
	if _combat_ended:
		return
	var amount: int = info.get("amount", 0)
	var school: int = info.get("school", Enums.DamageSchool.NONE)
	var is_crit: bool = _last_attack_was_crit
	var outcome: String = ""
	var hp_before: int = player_hp if target == "player" else enemy_hp
	if target == "player":
		if _relic_hero_immune:
			_log("  Bone Shield absorbs %d damage!" % amount, 1)  # PLAYER
			return
		player_hp -= amount
		damage_dealt.emit(str(info.get("source_card", "")), "player", amount, school, is_crit)
		_log("  You take %d damage  (HP: %d)" % [amount, player_hp], 3)  # DAMAGE
		var pctx := EventContext.make(Enums.TriggerEvent.ON_HERO_DAMAGED, "player")
		pctx.damage = amount
		pctx.damage_info = info
		trigger_manager.fire(pctx)
		if player_hp <= 0 and winner.is_empty():
			outcome = "lethal"
			winner = "enemy"
	else:
		enemy_hp -= amount
		# Source label for the sim damage log: DamageInfo.source_card, else the
		# legacy _pending_dmg_source plumbing, else a generic label.
		var src_label: String = str(info.get("source_card", ""))
		if src_label.is_empty():
			var src: Enums.DamageSource = info.get("source", Enums.DamageSource.SPELL)
			src_label = _pending_dmg_source if not _pending_dmg_source.is_empty() \
				else ("minion_atk" if src == Enums.DamageSource.MINION else "spell_onplay")
		damage_dealt.emit(src_label, "enemy", amount, school, is_crit)
		_pending_dmg_source = ""
		_log("  Enemy takes %d damage  (HP: %d)" % [amount, enemy_hp], 3)  # DAMAGE
		var ectx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_HERO_DAMAGED, "enemy")
		ectx.damage = amount
		ectx.damage_info = info
		trigger_manager.fire(ectx)
		if enemy_hp <= 0 and winner.is_empty():
			# F15 Abyss Sovereign: intercept P1 death and transition to P2.
			if PhaseTransition.attempt(_get_scene_facade()):
				outcome = "transition"
			else:
				outcome = "lethal"
				winner = "player"
	emit_event(CombatEvent.Kind.DAMAGE_DEALT, target, {kind = "hero", amount = amount, hp_before = hp_before,
			hp_after = player_hp if target == "player" else enemy_hp, school = school, is_crit = is_crit,
			source_minion = info.get("attacker", null), source_card = str(info.get("source_card", ""))})
	if outcome == "transition":
		emit_event(CombatEvent.Kind.PHASE_TRANSITION, "enemy", {})
	elif outcome == "lethal":
		emit_event(CombatEvent.Kind.COMBAT_ENDED, target, {winner = winner})
	if presenter != null:
		presenter._on_hero_damaged_visual(target, amount, school, is_crit, outcome)

## A hero was healed — clamped to that hero's max HP.
func _on_hero_healed(target: String, amount: int) -> void:
	if target == "player":
		player_hp = mini(player_hp + amount, player_hp_max)
		_log("  You heal %d HP  (HP: %d)" % [amount, player_hp], 4)  # HEAL
	elif target == "enemy":
		enemy_hp = mini(enemy_hp + amount, enemy_hp_max)
		_log("  Enemy heals %d HP  (HP: %d)" % [amount, enemy_hp], 2)  # ENEMY
	else:
		return
	emit_event(CombatEvent.Kind.HERO_HEALED, target, {amount = amount, hp = player_hp if target == "player" else enemy_hp})
	if presenter != null:
		presenter._on_hero_healed_visual(target, amount)

# ---------------------------------------------------------------------------
# Gameplay helpers that lived on CombatScene / SimState (plan 1.4)
# ---------------------------------------------------------------------------

## Summon a 100/100 Void Spark on the player board (void_spark_on_friendly_death).
func _summon_void_spark() -> void:
	_summon_token("void_spark", "player")

## Void Devourer on-play: sacrifice the adjacent friendly minions, +300/+300 per sacrifice.
func _resolve_void_devourer_sacrifice(devourer: MinionInstance, owner: String = "player") -> void:
	var idx: int = devourer.slot_index
	var to_sacrifice: Array[MinionInstance] = []
	for m: MinionInstance in _friendly_board(owner):
		if m != devourer and (m.slot_index == idx - 1 or m.slot_index == idx + 1):
			to_sacrifice.append(m)
	var count: int = to_sacrifice.size()
	for m: MinionInstance in to_sacrifice:
		_log("  Void Devourer sacrifices %s!" % m.card_data.card_name, 1)
		SacrificeSystem.sacrifice(self, m, "void_devourer")
	if count > 0:
		BuffSystem.apply(devourer, Enums.BuffType.ATK_BONUS, count * 300, "void_devourer", false, false)
		devourer.current_health += count * 300
		_log("  Void Devourer grows to %d/%d!" % [devourer.effective_atk(), devourer.current_health], 1)
		_refresh_slot_for(devourer)

## Player champions (e.g. the Void Imp champion) auto-summon from hand or deck
## when their board condition is met. At most one per check.
func _check_champion_triggers() -> void:
	var all_cards: Array[CardInstance] = player_hand + player_deck
	for inst: CardInstance in all_cards:
		if not (inst.card_data is MinionCardData):
			continue
		var champion := inst.card_data as MinionCardData
		if not champion.is_champion:
			continue
		var already_on_board := false
		for m: MinionInstance in player_board:
			if m.card_data.id == champion.id:
				already_on_board = true
				break
		if already_on_board:
			continue
		if _check_champion_condition(champion):
			_summon_champion_card(champion, inst, inst in player_hand)
			return

func _check_champion_condition(champion: MinionCardData) -> bool:
	match champion.auto_summon_condition:
		"board_tag_count":
			var count := 0
			for m: MinionInstance in player_board:
				if _minion_has_tag(m, champion.auto_summon_tag):
					count += 1
			return count >= champion.auto_summon_threshold
	return false

## Place the champion card on the first empty player slot, free of cost.
func _summon_champion_card(card: MinionCardData, inst: CardInstance, from_hand: bool) -> void:
	for slot: SlotState in player_slots:
		if not slot.is_empty():
			continue
		var instance := MinionInstance.create(card, "player")
		instance.card_instance = inst
		player_board.append(instance)
		slot.place(instance)
		minion_summoned.emit("player", instance, slot.index)
		emit_event(CombatEvent.Kind.CHAMPION_SUMMONED, "player", {minion = instance, card = card, slot = slot.index, from_hand = from_hand})
		if from_hand:
			remove_from_hand("player", inst)
			if presenter != null:
				presenter._on_card_left_hand(inst)
		else:
			player_deck.erase(inst)
		_log("⚡ 3 Void Imps on board — %s emerges!" % card.card_name, 1)
		var ctx := EventContext.make(Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED, "player")
		ctx.minion = instance
		ctx.card   = card
		trigger_manager.fire(ctx)
		return

# ---------------------------------------------------------------------------
# Cost payment (plan 1.4). Profiles still deduct their own essence/mana until
# 2A.5 routes them through commands; live's play paths call these.
# ---------------------------------------------------------------------------

## Pay a card's Essence + Mana. The player's pending Dark Mirror relic discount
## reduces both costs first (and is consumed). Returns false (nothing spent) if
## the side can't afford it.
func pay_card_cost(side: String, essence_cost: int, mana_cost: int) -> bool:
	if side == "player" and _relic_cost_reduction > 0:
		var reduction: int = _relic_cost_reduction
		_relic_cost_reduction = 0
		var essence_reduction: int = mini(reduction, essence_cost)
		var mana_reduction: int = mini(reduction, mana_cost)
		essence_cost -= essence_reduction
		mana_cost -= mana_reduction
		if essence_reduction + mana_reduction > 0:
			_log("  Dark Mirror: cost reduced by %d Essence and %d Mana!" % [essence_reduction, mana_reduction], 1)
	if not can_afford(side, essence_cost, mana_cost):
		return false
	spend_essence(side, essence_cost)
	if mana_cost > 0:
		spend_mana(side, mana_cost)
	return true

## Total spark value on `side`'s board.
func available_sparks(side: String) -> int:
	var total := 0
	for m: MinionInstance in _friendly_board(side):
		total += (m.card_data as MinionCardData).spark_value
	return total

func can_afford_sparks(side: String, cost: int) -> bool:
	return cost <= 0 or available_sparks(side) >= cost

## Consume board minions to pay a spark cost: eligible fuel has spark_value <=
## cost, biggest first (fewest bodies). Void Spark tokens die (death triggers
## fire — Blood Rune etc.); other spark minions are consumed silently. Each
## consumption fires ON_*_SPARK_CONSUMED. Returns true if fully paid.
func pay_sparks(side: String, cost: int) -> bool:
	if cost <= 0:
		return true
	var board: Array[MinionInstance] = _friendly_board(side)
	var eligible: Array[MinionInstance] = []
	for m: MinionInstance in board:
		var sv: int = (m.card_data as MinionCardData).spark_value
		if sv > 0 and sv <= cost:
			eligible.append(m)
	eligible.sort_custom(func(a: MinionInstance, b: MinionInstance) -> bool:
		return (a.card_data as MinionCardData).spark_value > (b.card_data as MinionCardData).spark_value)
	var remaining := cost
	for m: MinionInstance in eligible:
		if remaining <= 0:
			break
		var sv: int = (m.card_data as MinionCardData).spark_value
		if m.card_data.id == "void_spark":
			combat_manager.kill_minion(m)
		else:
			board.erase(m)
			for slot: SlotState in _friendly_slots(side):
				if slot.minion == m:
					slot.clear()
					break
			_log("  %s consumed as spark fuel." % m.card_data.card_name)
			emit_event(CombatEvent.Kind.MINION_CONSUMED, side, {minion = m})
		if trigger_manager != null:
			var event := Enums.TriggerEvent.ON_PLAYER_SPARK_CONSUMED if side == "player" \
				else Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED
			var ctx := EventContext.make(event, side)
			ctx.minion = m
			ctx.damage = sv
			trigger_manager.fire(ctx)
		remaining -= sv
	return remaining <= 0

# ---------------------------------------------------------------------------
# State digest — canonical text snapshot for determinism / parity checks
# (LIVE_SIM_UNIFICATION_PLAN.md 0.5).
# ---------------------------------------------------------------------------

## Stable, newline-separated snapshot of everything gameplay-relevant. Two
## states with equal digests are the same game position.
func digest_text() -> String:
	var lines: PackedStringArray = []
	lines.append("turn %d winner %s" % [turn_number, winner])
	lines.append("hp %d/%d vs %d/%d" % [player_hp, player_hp_max, enemy_hp, enemy_hp_max])
	lines.append("res P %d/%d %d/%d  E %d/%d %d/%d" % [
		player_essence, player_essence_max, player_mana, player_mana_max,
		enemy_essence, enemy_essence_max, enemy_mana, enemy_mana_max])
	lines.append("marks %d flesh %d/%d forge %d/%d armour %d/%d" % [
		enemy_void_marks, player_flesh, player_flesh_max, forge_counter, forge_counter_threshold,
		player_hero.armour, enemy_hero.armour])
	lines.append("hero_buffs P %s E %s" % [_digest_buffs(player_hero.buffs), _digest_buffs(enemy_hero.buffs)])
	for side in ["player", "enemy"]:
		var slots: Array[SlotState] = player_slots if side == "player" else enemy_slots
		for slot: SlotState in slots:
			var m: MinionInstance = slot.minion
			if m == null:
				continue
			lines.append("%s[%d] %s atk %d hp %d arm %d st %d %s" % [
				side, slot.index, m.card_data.id, m.effective_atk(), m.current_health,
				m.armour, m.state, _digest_buffs(m.buffs)])
	lines.append("hand P %s" % ",".join(_digest_ids(player_hand)))
	lines.append("hand E %s" % ",".join(_digest_ids(enemy_hand)))
	lines.append("deck %d/%d grave %d/%d" % [player_deck.size(), enemy_deck.size(),
		player_graveyard.size(), enemy_graveyard.size()])
	var p_traps: PackedStringArray = []
	for t: TrapCardData in active_traps:
		p_traps.append(t.id)
	var e_traps: PackedStringArray = []
	for t: TrapCardData in enemy_active_traps:
		e_traps.append(t.id)
	lines.append("traps P %s E %s" % [",".join(p_traps), ",".join(e_traps)])
	lines.append("env P %s E %s" % [
		active_environment.id if active_environment != null else "-",
		enemy_active_environment.id if enemy_active_environment != null else "-"])
	if relic_runtime != null:
		var relic_parts: PackedStringArray = []
		for rs: RelicRuntime.RelicState in relic_runtime.relics:
			relic_parts.append("%s:%d/%d" % [rs.data.id, rs.charges_remaining, rs.cooldown_remaining])
		lines.append("relics %s" % ",".join(relic_parts))
	return "\n".join(lines)

func digest() -> int:
	return digest_text().hash()

static func _digest_ids(cards: Array[CardInstance]) -> PackedStringArray:
	var out: PackedStringArray = []
	for inst: CardInstance in cards:
		out.append(inst.card_data.id)
	return out

## Buff list as sorted "type:amount:source" tokens (order-insensitive).
static func _digest_buffs(buffs: Array) -> String:
	var out: PackedStringArray = []
	for e: BuffEntry in buffs:
		out.append("%d:%d:%s" % [e.type, e.amount, e.source])
	out.sort()
	return "[" + ",".join(out) + "]"

# ---------------------------------------------------------------------------
# Turn engine (LIVE_SIM_UNIFICATION_PLAN.md 2A.3) — one turn flow for both
# shells. Live's TurnManager is a façade that calls these and relays
# turn_started / turn_ended to the UI (which kicks off the live enemy turn);
# CombatSim reaches them through cmd_end_turn. No awaits: draw animations hang
# off card_drawn.
# ---------------------------------------------------------------------------

## A side's turn has begun — after its start-of-turn event resolved.
signal turn_started(side: String, turn: int)
## A side's turn has ended — after its end-of-turn event and cleanup.
signal turn_ended(side: String)

## Per-side resource growth run at that side's turn start:
## Callable(side: String, turn: int) -> void. Without a hook the enemy grows by
## the default curve and the player grows only by its end-of-turn choice.
var growth_hooks: Dictionary = {}
## The player's end-of-turn growth pick ("essence" / "mana"), applied when their
## next turn begins (D10).
var _pending_player_growth: String = ""

## Begin combat: both sides at 1 Essence / 1 Mana max (written to the backing
## fields — not a growth choice), then the player's first turn. Opening hands
## come from deck setup (enemy 5) and the shell (player 3).
func start_combat() -> void:
	turn_number = 0
	_player_essence_max = 1
	_player_mana_max = 1
	enemy_essence_max = 1
	enemy_mana_max = 1
	refill_resources("enemy")
	begin_turn("player")

## Start `side`'s turn. Player (D2, live's order): growth → refill → draw 1 →
## ready the board → spell tax, Void Rift Lord drain, relic / per-turn resets →
## ON_PLAYER_TURN_START. Enemy (D9, mirrored): growth → refill → spell tax →
## drain → draw 1 → ready the board → ON_ENEMY_TURN_START.
func begin_turn(side: String) -> void:
	is_player_turn = side == "player"
	if side == "player":
		turn_number += 1
	_log("── Turn %d  %s ──" % [turn_number, "Player" if side == "player" else "Enemy"], 0)  # TURN
	_grow_resources(side)
	refill_resources(side)
	if side == "player":
		draw_cards("player", 1)
		_ready_board(player_board)
		player_spell_cost_penalty = _spell_tax_for_player_turn
		_spell_tax_for_player_turn = 0
		if _void_mana_drain_pending:
			_void_mana_drain_pending = false
			player_mana = 0
			_log("  Void Rift Lord: your Mana has been drained to 0!", 2)  # ENEMY
		_relic_hero_immune = false
		_relic_cost_reduction = 0
		for inst: CardInstance in player_hand:
			inst.reset_deltas()
		_fiendish_pact_pending = 0
		_once_per_turn_used.clear()
		if relic_runtime != null:
			relic_runtime.on_turn_start()
	else:
		enemy_spell_cost_penalty = _spell_tax_for_enemy_turn
		_spell_tax_for_enemy_turn = 0
		_enemy_fiendish_pact_pending = 0
		if _enemy_void_mana_drain_pending:
			_enemy_void_mana_drain_pending = false
			enemy_mana = 0
			_log("  Void Rift Lord: enemy Mana has been drained to 0!", 1)  # PLAYER
		draw_cards("enemy", 1)
		_ready_board(enemy_board)
	emit_resources(side)
	if trigger_manager != null:
		trigger_manager.fire(EventContext.make(
				Enums.TriggerEvent.ON_PLAYER_TURN_START if side == "player" else Enums.TriggerEvent.ON_ENEMY_TURN_START, side))
	turn_started.emit(side, turn_number)
	emit_event(CombatEvent.Kind.TURN_STARTED, side, {turn = turn_number})

## End `side`'s turn: ON_*_TURN_END, then (unless combat ended) clear that
## turn's spell tax and the opponent's trap block.
func end_turn(side: String) -> void:
	if trigger_manager != null:
		trigger_manager.fire(EventContext.make(
				Enums.TriggerEvent.ON_PLAYER_TURN_END if side == "player" else Enums.TriggerEvent.ON_ENEMY_TURN_END, side))
	if winner.is_empty() and not _combat_ended:
		if side == "player":
			player_spell_cost_penalty = 0
			_enemy_traps_blocked = false
		else:
			enemy_spell_cost_penalty = 0
			_player_traps_blocked = false
	turn_ended.emit(side)
	emit_event(CombatEvent.Kind.TURN_ENDED, side, {})

## Record the player's end-of-turn growth pick: applied at their next turn
## start (D10), but recorded as the latest choice now (F15 Abyssal Mandate reads
## it during the enemy turn that follows).
func choose_player_growth(growth: String) -> void:
	if growth != "essence" and growth != "mana":
		return
	_pending_player_growth = growth
	last_player_growth = growth

func _grow_resources(side: String) -> void:
	if side == "player" and not _pending_player_growth.is_empty():
		if _pending_player_growth == "essence":
			grow_essence_max("player")
		else:
			grow_mana_max("player")
		_pending_player_growth = ""
		return
	var hook: Callable = growth_hooks.get(side, Callable())
	if hook.is_valid():
		hook.call(side, turn_number)
	elif side == "enemy":
		_default_growth("enemy", turn_number)

## Default curve: none on the first turn; otherwise +1 Mana when it lags
## Essence by more than 2, else +1 Essence (combined cap applies).
func _default_growth(side: String, turn: int) -> void:
	if turn <= 1:
		return
	if mana_max_of(side) < essence_max_of(side) - 2:
		grow_mana_max(side)
	else:
		grow_essence_max(side)

## Start-of-turn upkeep for a side's minions: exhausted → ready, and buffs that
## last "this turn" expire.
func _ready_board(board: Array[MinionInstance]) -> void:
	for minion: MinionInstance in board:
		minion.on_turn_start()
		BuffSystem.expire_temp(minion)

# ---------------------------------------------------------------------------
# Commands (LIVE_SIM_UNIFICATION_PLAN.md 2A.1) — the synchronous way into the
# rules engine, one set for both sides. Sim and tests drive combat through
# these; live input moves onto them in Phase 3.4. Every command validates
# before it mutates (a refused command changes nothing), pays its own costs,
# and records itself in command_log.
# ---------------------------------------------------------------------------

## Accepted commands in order: {turn, side, cmd, card_id, hand_index, slot,
## target, extra}. Targets and spark fuel are recorded by slot / hero sentinel
## so the log replays against a fresh state built from the same seed.
var command_log: Array[Dictionary] = []

## Relic effect resolver for cmd_activate_relic — built on first use.
var relic_effects: RelicEffects = null

## Play a minion from `side`'s hand into slot `slot_index`. `target` is the
## on-play target (MinionInstance, or a trap/environment for the enemy's
## non-minion picks). extra.spark_fuel: the minions to consume for a spark cost
## (default: the engine picks). Event order: place in slot →
## ON_*_MINION_PLAYED (not yet on the board array, so ALL_FRIENDLY on-play
## effects skip it) → join the board → minion_summoned → ON_*_MINION_SUMMONED.
func cmd_play_minion(side: String, inst: CardInstance, slot_index: int, target = null, extra: Dictionary = {}) -> CommandResult:
	var why: String = _check_card_play(side, inst)
	if why.is_empty() and not (inst.card_data is MinionCardData):
		why = "wrong_card_type"
	var slots: Array[SlotState] = player_slots if side == "player" else enemy_slots
	if why.is_empty() and (slot_index < 0 or slot_index >= slots.size()):
		why = "bad_slot"
	if why.is_empty() and not slots[slot_index].is_empty():
		why = "slot_occupied"
	var cost: Dictionary = {}
	if why.is_empty():
		cost = plan_cost(side, inst, extra)
		why = cost.get("why", "")
	if not why.is_empty():
		return CommandResult.refused(why)
	_log_command("play_minion", side, inst, slot_index, target, extra)
	var mc := inst.card_data as MinionCardData
	var fp_discount: int = _peek_fiendish_pact_discount(mc) if side == "player" else 0
	pay_planned_cost(side, cost)
	if fp_discount > 0:
		_log("  Fiendish Pact: %s costs %d less Essence." % [mc.card_name, fp_discount], 1)  # PLAYER
		_consume_fiendish_pact_discount()
	var slot: SlotState = slots[slot_index]
	if not slot.is_empty():
		# A spark-consumed trigger filled the slot while paying — take the next free one.
		slot = null
		for s: SlotState in slots:
			if s.is_empty():
				slot = s
				break
		if slot == null:
			remove_from_hand(side, inst)
			return CommandResult.accepted("board_full")
	remove_from_hand(side, inst)
	emit_event(CombatEvent.Kind.CARD_PLAYED, side, {inst = inst, card = mc})
	_log(("You play: %s" if side == "player" else "Enemy summons: %s") % mc.card_name,
			1 if side == "player" else 2)  # PLAYER / ENEMY
	if side == "enemy":
		if mc.id == "bastion_colossus":
			_vw_bastion_plays += 1
		elif mc.id == "void_behemoth":
			_vw_behemoth_plays += 1
	var instance := MinionInstance.create(mc, side)
	instance.card_instance = inst
	slot.place(instance)
	emit_event(CombatEvent.Kind.MINION_PLAYED, side, {minion = instance, card = mc, slot = slot.index, inst = inst, target = target})
	if side == "enemy":
		enemy_play_target = target  # read (and cleared) by the ON_ENEMY_MINION_PLAYED handler
	if trigger_manager != null:
		var played_ctx := EventContext.make(
				Enums.TriggerEvent.ON_PLAYER_MINION_PLAYED if side == "player" else Enums.TriggerEvent.ON_ENEMY_MINION_PLAYED, side)
		played_ctx.minion = instance
		played_ctx.card   = mc
		if target is MinionInstance:
			played_ctx.target = target
		trigger_manager.fire(played_ctx)
	_friendly_board(side).append(instance)
	minion_summoned.emit(side, instance, slot.index)
	if trigger_manager != null:
		var summon_ctx := EventContext.make(
				Enums.TriggerEvent.ON_PLAYER_MINION_SUMMONED if side == "player" else Enums.TriggerEvent.ON_ENEMY_MINION_SUMMONED, side)
		summon_ctx.minion = instance
		summon_ctx.card   = mc
		trigger_manager.fire(summon_ctx)
	return CommandResult.accepted()

## Cast a spell from `side`'s hand. `target`: MinionInstance, "enemy_hero" /
## "player_hero", a TrapCardData / EnvironmentCardData (Cyclone), or null.
## extra: pre-resolved cast choices (rally_race) plus optional spark_fuel.
## ON_*_SPELL_CAST fires before resolution (D8) so a counter / Silence Trap can
## cancel it; a Phase Disruptor counter stops it before the event.
func cmd_play_spell(side: String, inst: CardInstance, target = null, extra: Dictionary = {}) -> CommandResult:
	var why: String = _check_card_play(side, inst)
	if why.is_empty() and not (inst.card_data is SpellCardData):
		why = "wrong_card_type"
	if why.is_empty():
		why = _check_spell_target(inst.card_data as SpellCardData, target)
	var cost: Dictionary = {}
	if why.is_empty():
		cost = plan_cost(side, inst, extra)
		why = cost.get("why", "")
	if not why.is_empty():
		return CommandResult.refused(why)
	_log_command("play_spell", side, inst, -1, target, extra)
	var spell := inst.card_data as SpellCardData
	pay_planned_cost(side, cost)
	remove_from_hand(side, inst)
	emit_event(CombatEvent.Kind.CARD_PLAYED, side, {inst = inst, card = spell})
	_log(("You cast: %s" if side == "player" else "Enemy casts: %s") % spell.card_name,
			1 if side == "player" else 2)  # PLAYER / ENEMY
	# Phase Disruptor: the opponent countered this side's next spell.
	if side == "player" and _player_spell_counter > 0:
		_player_spell_counter -= 1
		_log("  Spell countered!", 2)  # ENEMY
		emit_event(CombatEvent.Kind.SPELL_COUNTERED, side, {spell = spell, reason = "countered"})
		return CommandResult.accepted("countered")
	if side == "enemy" and _enemy_spell_counter > 0:
		_enemy_spell_counter -= 1
		_log("  Spell countered!", 1)  # PLAYER
		emit_event(CombatEvent.Kind.SPELL_COUNTERED, side, {spell = spell, reason = "countered"})
		return CommandResult.accepted("countered")
	if trigger_manager != null:
		var cast_ctx := EventContext.make(
				Enums.TriggerEvent.ON_PLAYER_SPELL_CAST if side == "player" else Enums.TriggerEvent.ON_ENEMY_SPELL_CAST, side)
		cast_ctx.card = spell
		trigger_manager.fire(cast_ctx)
	if _spell_cancelled:
		_spell_cancelled = false
		emit_event(CombatEvent.Kind.SPELL_COUNTERED, side, {spell = spell, reason = "cancelled"})
		return CommandResult.accepted("cancelled")
	var cast_data: Dictionary = extra.duplicate()
	cast_data.erase("spark_fuel")
	cast_data.erase("sparks_prepaid")
	if side == "enemy":
		cast_enemy_spell(spell, target, cast_data)
	elif target is String and target == "enemy_hero":
		cast_player_hero_spell(spell)
	else:
		cast_player_targeted_spell(spell, target, cast_data)
	return CommandResult.accepted()

## Set a trap or place a rune from `side`'s hand. Refused when the side's trap
## slots are full or it already has the same non-rune trap set.
func cmd_play_trap(side: String, inst: CardInstance) -> CommandResult:
	var why: String = _check_card_play(side, inst)
	if why.is_empty() and not (inst.card_data is TrapCardData):
		why = "wrong_card_type"
	if why.is_empty():
		why = trap_placement_refusal(side, inst.card_data as TrapCardData)
	var traps: Array[TrapCardData] = traps_of(side)
	var cost: Dictionary = {}
	if why.is_empty():
		cost = plan_cost(side, inst, {})
		why = cost.get("why", "")
	if not why.is_empty():
		return CommandResult.refused(why)
	_log_command("play_trap", side, inst, -1, null, {})
	var trap := inst.card_data as TrapCardData
	pay_planned_cost(side, cost)
	remove_from_hand(side, inst)
	emit_event(CombatEvent.Kind.CARD_PLAYED, side, {inst = inst, card = trap})
	if side == "player":
		_log(("You place rune: %s" if trap.is_rune else "You set trap: %s") % trap.card_name, 1)  # PLAYER
	else:
		_log("Enemy places rune: %s" % trap.card_name if trap.is_rune else "Enemy sets a trap.", 2)  # ENEMY
	traps.append(trap)
	emit_event(CombatEvent.Kind.RUNE_PLACED if trap.is_rune else CombatEvent.Kind.TRAP_PLACED, side, {trap = trap, slot = traps.size() - 1})
	_update_trap_display_for(side)
	if trigger_manager == null:
		return CommandResult.accepted()
	var place_ctx := EventContext.make(
			Enums.TriggerEvent.ON_PLAYER_TRAP_PLACED if side == "player" else Enums.TriggerEvent.ON_ENEMY_TRAP_PLACED, side)
	place_ctx.card = trap
	trigger_manager.fire(place_ctx)
	if trap.is_rune:
		_apply_rune_aura(trap, side)
		# Rituals consume the player's runes only.
		if side == "player":
			var rune_ctx := EventContext.make(Enums.TriggerEvent.ON_RUNE_PLACED, "player")
			rune_ctx.card = trap
			trigger_manager.fire(rune_ctx)
	return CommandResult.accepted()

## Play an environment from `side`'s hand, replacing the side's current one:
## the outgoing environment runs its on_replace steps (and, for the player,
## drops its ritual handlers); the new one registers its rituals (player),
## fires ON_RITUAL_ENVIRONMENT_PLAYED, then runs on-enter and passive steps.
func cmd_play_environment(side: String, inst: CardInstance) -> CommandResult:
	var why: String = _check_card_play(side, inst)
	if why.is_empty() and not (inst.card_data is EnvironmentCardData):
		why = "wrong_card_type"
	var cost: Dictionary = {}
	if why.is_empty():
		cost = plan_cost(side, inst, {})
		why = cost.get("why", "")
	if not why.is_empty():
		return CommandResult.refused(why)
	_log_command("play_environment", side, inst, -1, null, {})
	var env := inst.card_data as EnvironmentCardData
	pay_planned_cost(side, cost)
	remove_from_hand(side, inst)
	emit_event(CombatEvent.Kind.CARD_PLAYED, side, {inst = inst, card = env})
	_log(("You play environment: %s" if side == "player" else "Enemy plays environment: %s") % env.card_name,
			1 if side == "player" else 2)  # PLAYER / ENEMY
	var prev: EnvironmentCardData = environment_of(side)
	if prev != null:
		if side == "player" and trigger_manager != null:
			_unregister_env_rituals()
		_unregister_env_aura(prev, side)
	set_environment(side, env)
	if side == "player":
		_update_environment_display()
		if trigger_manager != null:
			_register_env_rituals(env)
			if not env.rituals.is_empty():
				var env_ctx := EventContext.make(Enums.TriggerEvent.ON_RITUAL_ENVIRONMENT_PLAYED, "player")
				env_ctx.card = env
				trigger_manager.fire(env_ctx)
	if not env.on_enter_effect_steps.is_empty():
		EffectResolver.run(env.on_enter_effect_steps, EffectContext.make(_get_scene_facade(), side))
	if not env.passive_effect_steps.is_empty():
		EffectResolver.run(env.passive_effect_steps, EffectContext.make(_get_scene_facade(), side))
	return CommandResult.accepted()

## `attacker` (on `side`'s board) attacks the opposing minion `target`.
## Refused unless the attacker can attack and — when the opponent has a Guard
## up — the target is a Guard (B5: no silent redirect; pick a legal target).
## Enemy attacks fire ON_ENEMY_ATTACK first; a Smoke Veil there cancels it.
func cmd_attack(side: String, attacker: MinionInstance, target: MinionInstance) -> CommandResult:
	var why: String = _check_can_act(side)
	if why.is_empty() and (attacker == null or not _friendly_board(side).has(attacker)):
		why = "no_attacker"
	if why.is_empty() and (target == null or not _opponent_board(side).has(target)):
		why = "no_target"
	if why.is_empty() and not attacker.can_attack():
		why = "cannot_attack"
	if why.is_empty() and not target.has_guard() \
			and CombatManager.board_has_taunt(_opponent_board(side)):
		why = "guard"
	if not why.is_empty():
		return CommandResult.refused(why)
	_log_command("attack", side, null, attacker.slot_index, target, {})
	var pre: String = _fire_enemy_attack_declared(side, attacker)
	if not pre.is_empty():
		return CommandResult.accepted(pre)
	if not _opponent_board(side).has(target):
		return CommandResult.accepted("target_gone")
	combat_manager.resolve_minion_attack(attacker, target)
	return CommandResult.accepted()

## `attacker` attacks the opposing hero. Refused unless the attacker can attack
## the hero (not SWIFT-only) and the opponent has no Guard up.
func cmd_attack_hero(side: String, attacker: MinionInstance) -> CommandResult:
	var why: String = _check_can_act(side)
	if why.is_empty() and (attacker == null or not _friendly_board(side).has(attacker)):
		why = "no_attacker"
	if why.is_empty() and not attacker.can_attack_hero():
		why = "cannot_attack"
	if why.is_empty() and CombatManager.board_has_taunt(_opponent_board(side)):
		why = "guard"
	if not why.is_empty():
		return CommandResult.refused(why)
	_log_command("attack_hero", side, null, attacker.slot_index, "%s_hero" % _opponent_of(side), {})
	var pre: String = _fire_enemy_attack_declared(side, attacker)
	if not pre.is_empty():
		return CommandResult.accepted(pre)
	if side == "player":
		_pending_dmg_source = "%s_atk" % attacker.card_data.id
	combat_manager.resolve_minion_attack_hero(attacker, _opponent_of(side))
	return CommandResult.accepted()

## Remove a friendly minion as spark fuel: no death, no on-death effects.
## Fires ON_*_SPARK_CONSUMED when it carried spark value.
func cmd_consume_minion(side: String, minion: MinionInstance) -> CommandResult:
	var why: String = _check_can_act(side)
	if why.is_empty() and (minion == null or not _friendly_board(side).has(minion)):
		why = "no_minion"
	if not why.is_empty():
		return CommandResult.refused(why)
	_log_command("consume_minion", side, null, minion.slot_index, null, {})
	_consume_minion(side, minion)
	return CommandResult.accepted()

## Activate the player's relic at `index`. Blood Chalice ("relic_execute") needs
## a target: an enemy MinionInstance or "enemy_hero".
func cmd_activate_relic(index: int, target = null) -> CommandResult:
	var why: String = _check_can_act("player")
	if why.is_empty() and (relic_runtime == null or not relic_runtime.can_activate(index)):
		why = "unavailable"
	if why.is_empty() and relic_runtime.get_state(index).data.effect_id == "relic_execute":
		var on_minion: bool = target is MinionInstance and enemy_board.has(target)
		var on_hero: bool = target is String and target == "enemy_hero"
		if not (on_minion or on_hero):
			why = "no_target"
	if not why.is_empty():
		return CommandResult.refused(why)
	_log_command("activate_relic", "player", null, index, target, {})
	var effect_id: String = relic_runtime.activate(index)
	emit_event(CombatEvent.Kind.RELIC_ACTIVATED, "player", {index = index, effect_id = effect_id, target = target})
	if effect_id == "relic_execute":
		var info := CombatManager.make_damage_info(0, Enums.DamageSource.SPELL, Enums.DamageSchool.NONE, null, "relic_blood_chalice")
		if target is MinionInstance:
			var victim: MinionInstance = target
			_spell_dmg(victim, 500, info)
			_log("  Relic: Blood Chalice — dealt 500 damage to %s." % victim.card_data.card_name, 1)  # PLAYER
		else:
			info["amount"] = 500
			combat_manager.apply_hero_damage("enemy", info)
			_log("  Relic: Blood Chalice — dealt 500 damage to enemy hero.", 1)  # PLAYER
		return CommandResult.accepted()
	if relic_effects == null:
		relic_effects = RelicEffects.new()
		relic_effects.setup(_get_scene_facade())
	relic_effects.resolve(effect_id)
	return CommandResult.accepted()

## Hero activated abilities: "seris_corrupt" (target: a friendly minion) and
## "soul_forge". Refused when the ability isn't available (talent missing,
## already used this turn, not enough Flesh).
func cmd_hero_skill(side: String, skill_id: String, target = null) -> CommandResult:
	var why: String = _check_can_act(side)
	if why.is_empty() and side != "player":
		why = "no_skill"
	if why.is_empty() and skill_id == "seris_corrupt" and not (target is MinionInstance):
		why = "no_target"
	if why.is_empty() and not (skill_id in ["seris_corrupt", "soul_forge"]):
		why = "no_skill"
	if not why.is_empty():
		return CommandResult.refused(why)
	# Both bodies validate before they mutate, so a false return changed nothing.
	var done: bool = _seris_corrupt_apply(target) if skill_id == "seris_corrupt" else _soul_forge_activate()
	if not done:
		return CommandResult.refused("unavailable")
	_log_command("hero_skill", side, null, -1, target, {"skill": skill_id})
	emit_event(CombatEvent.Kind.HERO_SKILL, side, {skill = skill_id, target = target})
	return CommandResult.accepted()

## End `side`'s turn and begin the opponent's. `growth` ("essence" / "mana") is
## the player's resource pick, applied when their next turn starts (D10).
func cmd_end_turn(side: String, growth: String = "") -> CommandResult:
	var why: String = _check_can_act(side)
	if not why.is_empty():
		return CommandResult.refused(why)
	_log_command("end_turn", side, null, -1, null, {growth = growth} if not growth.is_empty() else {})
	if side == "player":
		choose_player_growth(growth)
	end_turn(side)
	if winner.is_empty() and not _combat_ended:
		begin_turn(_opponent_of(side))
	return CommandResult.accepted()

# -- Command helpers ---------------------------------------------------------

## "" if `side` may set `trap` now, else why not: all TRAP_SLOTS_MAX slots
## taken, or the same non-rune trap already set.
func trap_placement_refusal(side: String, trap: TrapCardData) -> String:
	var traps: Array[TrapCardData] = traps_of(side)
	if traps.size() >= TRAP_SLOTS_MAX:
		return "trap_slots_full"
	if not trap.is_rune:
		for existing: TrapCardData in traps:
			if not existing.is_rune and existing.id == trap.id:
				return "duplicate_trap"
	return ""

## "" when `side` may act now, else the refusal reason.
func _check_can_act(side: String) -> String:
	if not winner.is_empty() or _combat_ended:
		return "combat_over"
	if is_player_turn != (side == "player"):
		return "not_your_turn"
	return ""

func _check_card_play(side: String, inst: CardInstance) -> String:
	var why: String = _check_can_act(side)
	if why.is_empty() and (inst == null or not hand_of(side).has(inst)):
		why = "not_in_hand"
	return why

## A null target is allowed even for targeted spells: SINGLE_CHOSEN steps fall
## back to a random legal target (the AI path). A minion target must be on a board.
func _check_spell_target(_spell: SpellCardData, target) -> String:
	if target == null:
		return ""
	if target is MinionInstance:
		return "" if (player_board.has(target) or enemy_board.has(target)) else "no_target"
	return ""

## Essence / Mana a card costs `side` right now, before the Dark Mirror relic.
func card_cost(side: String, inst: CardInstance) -> Vector2i:
	var card: CardData = inst.card_data
	if card is MinionCardData:
		var mc := card as MinionCardData
		return Vector2i(minion_essence_cost(side, mc), maxi(0, mc.mana_cost))
	if card is SpellCardData:
		return Vector2i(0, spell_cost(side, card as SpellCardData))
	if card is TrapCardData:
		return Vector2i(0, inst.effective_cost())
	return Vector2i(0, maxi(0, card.cost))

## Minion Essence cost: the player's pending Fiendish Pact discount; the enemy's
## per-card discounts and flat minion aura (F2 corrupted_death, F15 mandate).
func minion_essence_cost(side: String, mc: MinionCardData) -> int:
	if side == "player":
		return maxi(0, mc.essence_cost - _peek_fiendish_pact_discount(mc))
	var cost: int = mc.essence_cost - (enemy_essence_cost_discounts.get(mc.id, 0) as int)
	return maxi(0, cost + enemy_minion_essence_cost_aura)

## Spell Mana cost: the player's board discount (mana_cost_discount auras) and
## spell tax; the enemy's tax, aura and per-card discounts.
func spell_cost(side: String, spell: SpellCardData) -> int:
	if side == "player":
		var discount: int = 0
		for m: MinionInstance in player_board:
			discount += (m.card_data as MinionCardData).mana_cost_discount
		return maxi(0, spell.cost - discount + player_spell_cost_penalty)
	return maxi(0, spell.cost + enemy_spell_cost_penalty + enemy_spell_cost_aura \
		- (enemy_spell_cost_discounts.get(spell.id, 0) as int))

## Spark cost after passives: a friendly Void Herald champion zeroes it; enemy
## encounter passives ritualist_spark_free (spells free), captain_orders
## (Throne's Command -1) and void_mastery (halved, min 1).
func spark_cost_of(side: String, card: CardData) -> int:
	var base: int = card.void_spark_cost
	if base <= 0:
		return 0
	for m: MinionInstance in _friendly_board(side):
		if m.card_data.id == "champion_void_herald":
			return 0
	if side != "enemy":
		return base
	if "ritualist_spark_free" in _active_enemy_passives and card is SpellCardData:
		return 0
	var cost: int = base
	if "captain_orders" in _active_enemy_passives and card.id == "thrones_command":
		cost = maxi(cost - 1, 0)
	if "void_mastery" in _active_enemy_passives:
		return maxi(ceili(float(cost) / 2.0), 1)
	return cost

## Work out how `side` pays for `inst`, without paying. Returns {why} on
## failure, else {essence, mana, sparks, fuel, auto_sparks}. The spark cost is
## met by, in order: extra.spark_fuel (minions to consume now), else
## extra.sparks_prepaid (spark value the caller already consumed as fuel — the
## AI agents' contract), else the engine's own pick (pay_sparks). Any shortfall
## is paid in Mana under the enemy mana_for_spark passive, else refused. The
## Dark Mirror relic discount is applied as pay_card_cost will.
func plan_cost(side: String, inst: CardInstance, extra: Dictionary) -> Dictionary:
	var base: Vector2i = card_cost(side, inst)
	var sparks: int = spark_cost_of(side, inst.card_data)
	var fuel: Array[MinionInstance] = []
	var extra_mana: int = 0
	var auto_sparks: bool = false
	if sparks > 0:
		if extra.has("spark_fuel"):
			var fuel_value: int = 0
			for raw in extra["spark_fuel"]:
				var m: MinionInstance = raw as MinionInstance
				if m == null or not _friendly_board(side).has(m) or fuel.has(m):
					return {why = "bad_fuel"}
				fuel.append(m)
				fuel_value += m.effective_spark_value(self)
			if fuel_value < sparks:
				if side == "enemy" and "mana_for_spark" in _active_enemy_passives:
					extra_mana = sparks - fuel_value
				else:
					return {why = "sparks"}
		elif extra.has("sparks_prepaid"):
			var prepaid: int = extra["sparks_prepaid"]
			if prepaid < sparks:
				if side == "enemy" and "mana_for_spark" in _active_enemy_passives:
					extra_mana = sparks - prepaid
				else:
					return {why = "sparks"}
		elif can_afford_sparks(side, sparks):
			auto_sparks = true
		else:
			return {why = "sparks"}
	var ess: int = base.x
	var mana: int = base.y + extra_mana
	if side == "player" and _relic_cost_reduction > 0:
		ess -= mini(_relic_cost_reduction, ess)
		mana -= mini(_relic_cost_reduction, mana)
	if not can_afford(side, ess, mana):
		return {why = "cost"}
	return {essence = base.x, mana = base.y + extra_mana, sparks = sparks, fuel = fuel, auto_sparks = auto_sparks}

## Pay a cost planned by plan_cost: spark fuel first, then Essence / Mana.
func pay_planned_cost(side: String, cost: Dictionary) -> void:
	if cost.get("auto_sparks", false):
		pay_sparks(side, cost["sparks"])
	else:
		for m: MinionInstance in cost.get("fuel", []):
			if _friendly_board(side).has(m):
				_consume_minion(side, m)
	pay_card_cost(side, cost.get("essence", 0), cost.get("mana", 0))

## Silent removal as spark fuel (cmd_consume_minion, caller-picked spark fuel).
func _consume_minion(side: String, minion: MinionInstance) -> void:
	var spark_val: int = minion.effective_spark_value(self)
	if minion.card_data.id == "void_behemoth":
		_vw_behemoth_lost["consumed"] += 1
	elif minion.card_data.id == "bastion_colossus":
		_vw_bastion_lost["consumed"] += 1
	_friendly_board(side).erase(minion)
	for slot: SlotState in _friendly_slots(side):
		if slot.minion == minion:
			slot.clear()
			break
	_log("  %s consumed as spark fuel." % minion.card_data.card_name, 1 if side == "player" else 2)
	emit_event(CombatEvent.Kind.MINION_CONSUMED, side, {minion = minion})
	# Effective value so spirit_resonance-boosted Spirits still count.
	if spark_val > 0 and trigger_manager != null:
		var ctx := EventContext.make(
				Enums.TriggerEvent.ON_PLAYER_SPARK_CONSUMED if side == "player" else Enums.TriggerEvent.ON_ENEMY_SPARK_CONSUMED, side)
		ctx.minion = minion
		ctx.damage = spark_val
		trigger_manager.fire(ctx)

## Enemy attacks announce themselves (ON_ENEMY_ATTACK) before resolving so a
## Smoke Veil can cancel them. Returns "" to proceed, else why it stopped.
func _fire_enemy_attack_declared(side: String, attacker: MinionInstance) -> String:
	if side != "enemy" or trigger_manager == null:
		return ""
	var ctx := EventContext.make(Enums.TriggerEvent.ON_ENEMY_ATTACK, "enemy")
	ctx.minion = attacker
	trigger_manager.fire(ctx)
	if attack_cancelled:
		attack_cancelled = false
		return "cancelled"
	if not enemy_board.has(attacker):
		return "attacker_gone"
	return ""

func _log_command(cmd: String, side: String, inst: CardInstance, slot: int, target, extra: Dictionary) -> void:
	var rec_extra: Dictionary = extra.duplicate()
	if rec_extra.has("spark_fuel"):
		var fuel_slots: Array[int] = []
		for raw in rec_extra["spark_fuel"]:
			var m: MinionInstance = raw as MinionInstance
			fuel_slots.append(m.slot_index if m != null else -1)
		rec_extra["spark_fuel"] = fuel_slots
	command_log.append({
		turn = turn_number, side = side, cmd = cmd,
		card_id = inst.card_data.id if inst != null else "",
		hand_index = hand_of(side).find(inst) if inst != null else -1,
		slot = slot, target = _encode_target(target), extra = rec_extra,
	})

## A command target as plain data: {kind: minion|hero|trap|env, side, slot}.
func _encode_target(target) -> Variant:
	if target == null:
		return null
	if target is MinionInstance:
		var m: MinionInstance = target
		return {kind = "minion", side = m.owner, slot = m.slot_index}
	if target is String:
		return {kind = "hero", side = "enemy" if target == "enemy_hero" else "player", slot = -1}
	if target is TrapCardData:
		var p_idx: int = active_traps.find(target)
		if p_idx >= 0:
			return {kind = "trap", side = "player", slot = p_idx}
		return {kind = "trap", side = "enemy", slot = enemy_active_traps.find(target)}
	if target is EnvironmentCardData:
		return {kind = "env", side = "player" if target == active_environment else "enemy", slot = -1}
	return {kind = "unknown", side = "", slot = -1}

# ---------------------------------------------------------------------------
# Sub-systems shared by scene and sim.
# ---------------------------------------------------------------------------

## Central event dispatcher. Live combat creates one in CombatScene._ready
## and assigns it here; sim creates one in SimTriggerSetup. Always non-null
## once setup completes.
var trigger_manager: TriggerManager = null

## Turn-manager: live combat assigns the scene-tree TurnManager (Node), sim a
## nothing (null). The façade forwards the turn/resource/deck fields above;
## rules code uses those directly (lint L3). Untyped so either fits.
var turn_manager = null

## Trigger handlers (CombatHandlers). Live creates them in CombatScene._setup_triggers,
## sim in SimTriggerSetup. Environment rituals and a few VFX callbacks call into them.
var _handlers: CombatHandlers = null

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
