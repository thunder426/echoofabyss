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
