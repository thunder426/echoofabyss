## BuffVfxRegistry.gd
## Optional per-source flavor preludes for BuffApplyVFX.
##
## The generic BuffApplyVFX handles the common buff language (surge, flash,
## stat pulse, chevrons, motes). Cards whose identity demands a different
## look (e.g. Abyss Order corruption instead of divine blessing) register a
## prelude factory here. The prelude runs *before* the common phases.
##
## A factory is:
##   Callable(slot: Control, atk_delta: int, hp_delta: int) -> Callable
## and returns the prelude itself:
##   Callable() -> void   # may await, runs to completion before common phases
##
## Registration is data-only — any code path that needs the registry can
## populate it at module load via a `_static_init` in the prelude VFX file.
class_name BuffVfxRegistry
extends RefCounted

static var _factories: Dictionary = {}  # source_tag (String) → Callable

## Register a prelude factory for a source tag. Call once at module load.
static func register(source_tag: String, factory: Callable) -> void:
	if source_tag == "":
		push_warning("BuffVfxRegistry.register: empty source_tag ignored")
		return
	_factories[source_tag] = factory

## Build a prelude Callable for the given source+slot+deltas.
## Returns an empty Callable when no factory is registered — callers pass
## this straight to BuffApplyVFX.create(), which treats empty as "no prelude".
static func build_prelude(source_tag: String, slot: Control,
		atk_delta: int, hp_delta: int) -> Callable:
	var factory: Callable = _factories.get(source_tag, Callable())
	if not factory.is_valid():
		return Callable()
	return factory.call(slot, atk_delta, hp_delta)
