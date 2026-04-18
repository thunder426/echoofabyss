## SacrificeVfxRegistry.gd
## Optional per-source flavor preludes for SacrificeVFX.
##
## The generic SacrificeVFX plays the shared ritual language (rune sigil,
## drain, shatter into motes). Cards whose identity demands a different
## look (e.g. Blood Pact wants a blood-crimson sigil instead of the default
## abyssal purple) register a prelude factory here. The prelude runs
## *before* the common phases.
##
## A factory is:
##   Callable(slot: Control, minion: MinionInstance) -> Callable
## and returns the prelude itself:
##   Callable() -> void   # may await, runs to completion before common phases
##
## Registration is data-only — any per-card prelude file populates it at
## module load via a `_static_init`.
class_name SacrificeVfxRegistry
extends RefCounted

static var _factories: Dictionary = {}  # source_tag (String) → Callable

## Register a prelude factory for a source tag. Call once at module load.
static func register(source_tag: String, factory: Callable) -> void:
	if source_tag == "":
		push_warning("SacrificeVfxRegistry.register: empty source_tag ignored")
		return
	_factories[source_tag] = factory

## Build a prelude Callable for the given source+slot+minion.
## Returns an empty Callable when no factory is registered — callers pass
## this straight to SacrificeVFX.create(), which treats empty as "no prelude".
static func build_prelude(source_tag: String, slot: Control,
		minion: MinionInstance) -> Callable:
	var factory: Callable = _factories.get(source_tag, Callable())
	if not factory.is_valid():
		return Callable()
	return factory.call(slot, minion)
