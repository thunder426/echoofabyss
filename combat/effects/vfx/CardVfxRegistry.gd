## CardVfxRegistry.gd
## Single dispatch table for card-id-keyed VFX hooks.
##
## Before this file: CombatScene.gd held three sites with `if card.id == "..."`
## chains for token-summon sigils, on-summon aura pulses, and an enemy
## summon-reveal extra (Corrupted Death). Each new card meant editing
## CombatScene. With this registry, CombatScene calls the dispatchers below
## and adding a new card-VFX is a single edit here.
##
## Usage from CombatScene:
##   CardVfxRegistry.play_summon_aura_pulse(vfx_controller, card, slot)
##   if CardVfxRegistry.try_play_token_summon(vfx_bridge, id, inst, data, slot, owner):
##       return  # bridge handled placement + triggers
##   CardVfxRegistry.play_enemy_summon_reveal_extra(vfx_controller, minion, slot, _active_enemy_passives)
##
## Adding a card VFX: add a new branch to the relevant `match` below. No edits
## to CombatScene, VfxController, or CombatVFXBridge required.
##
## Notes
## - Spell VFX dispatch lives in VfxController.gd (separate concern: spells
##   need freeze/await/cleanup wrappers around the VFX, all owned by the
##   controller). This registry only covers minion-side hooks.
## - Methods are static so callers don't need to allocate.
class_name CardVfxRegistry
extends RefCounted

## On-summon aura pulse — one-shot halo advertising "I project an aura".
## Strictly on-summon (not on aura refresh). Card-id gated.
static func play_summon_aura_pulse(controller: VfxController, card: CardData, slot: BoardSlot) -> void:
	if controller == null or card == null or slot == null:
		return
	match card.id:
		"rogue_imp_elder":
			controller.spawn(AuraBreathingPulseVFX.create(slot))
		"champion_abyss_cultist_patrol":
			# Same VFX used when the aura triggers on-detonation — playing it
			# on summon teaches the player what to watch for before the first trigger.
			controller.spawn(ChampionAuraCorruptionPulseVFX.create(slot))

## Token-summon sigil dispatcher. Returns true if a registered card-id
## handler took over (bridge will place the minion + fire ON_*_MINION_SUMMONED
## itself via _reveal_after_sigil); false to fall through to the default
## "place_minion + fire trigger" path in the caller.
static func try_play_token_summon(vfx_bridge: CombatVFXBridge, card_id: String,
		instance: MinionInstance, data: MinionCardData, slot: BoardSlot, owner: String) -> bool:
	if vfx_bridge == null:
		return false
	match card_id:
		"void_spark":
			vfx_bridge.summon_spark_with_sigil(instance, data, slot, owner)
			return true
		"void_demon":
			vfx_bridge.summon_demon_with_sigil(instance, data, slot, owner)
			return true
		"brood_imp":
			vfx_bridge.summon_brood_imp_with_sigil(instance, data, slot, owner)
			return true
	return false

## Extra VFX layered on top of the standard enemy-summon reveal. Used for
## passive-gated cosmetics (e.g. Corrupted Death imps get a void wisp on
## landing). active_passives is the scene's _active_enemy_passives array.
static func play_enemy_summon_reveal_extra(controller: VfxController,
		minion: MinionInstance, slot: BoardSlot, active_passives: Array) -> void:
	if controller == null or minion == null or slot == null or minion.card_data == null:
		return
	match minion.card_data.id:
		"void_touched_imp":
			if "corrupted_death" in active_passives:
				controller.spawn(CorruptedDeathSummonVFX.create(slot))
