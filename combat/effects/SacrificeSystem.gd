## SacrificeSystem.gd
## Signal bus for sacrifice events — the shared channel every SACRIFICE
## call site emits on. CombatScene subscribes on _ready to drive SacrificeVFX.
##
## Sacrifice is not a plain death — it's a ritual consumption initiated by
## a card or minion effect (Abyssal Sacrifice, Blood Pact, Soul Shatter,
## Void Devourer). Plain deaths (combat, fatigue, consume-as-fuel) go
## through combat_manager.kill_minion directly and do not emit here.
##
## Signature: sacrifice_occurred(minion, source_tag)
##   minion      — the MinionInstance about to be killed (still on its slot
##                 at emit time, so VFX can locate the slot)
##   source_tag  — card id of the instigator ("abyssal_sacrifice",
##                 "blood_pact", "soul_shatter", "void_devourer")
class_name SacrificeSystem
extends RefCounted

static var _bus: Object = null

static func bus() -> Object:
	if _bus == null:
		_bus = Object.new()
		_bus.add_user_signal("sacrifice_occurred", [
			{"name": "minion",     "type": TYPE_OBJECT},
			{"name": "source_tag", "type": TYPE_STRING},
		])
	return _bus

## Fire from any site where a minion is being sacrificed. Call BEFORE the
## actual kill_minion so the VFX can snapshot the slot while the minion
## still occupies it.
static func emit(minion: MinionInstance, source_tag: String) -> void:
	if minion == null:
		return
	bus().emit_signal("sacrifice_occurred", minion, source_tag)

## Preferred entry point. Drives the full sacrifice flow:
##   1. VFX bus signal (sacrifice_occurred) so SacrificeVFX subscribers can react.
##   2. scene._on_demon_sacrificed for the Soul Forge / Fiend Offering tick.
##   3. scene._sacrifice_minion which handles ON LEAVE steps, the
##      ON_*_MINION_SACRIFICED trigger event, corruption removal, and silent
##      board removal.
##
## Strict rule: sacrifice does NOT fire ON_*_MINION_DIED, on_death_effect_steps,
## or any "killer credit" effect. Cards that need to react to sacrifice must use
## ON LEAVE (on_leave_effect_steps) or listen to ON_*_MINION_SACRIFICED directly.
static func sacrifice(scene: Object, minion: MinionInstance, source_tag: String) -> void:
	if minion == null:
		return
	bus().emit_signal("sacrifice_occurred", minion, source_tag)
	if scene != null and scene.has_method("_on_demon_sacrificed"):
		scene._on_demon_sacrificed(minion, source_tag)
	if scene != null and scene.has_method("_sacrifice_minion"):
		scene._sacrifice_minion(minion)
