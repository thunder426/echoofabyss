## Pacer.gd
## What a StateAgent waits on between actions (LIVE_SIM_UNIFICATION_PLAN.md
## 2A.5). The base pacer returns at once — sim and tests. Phase 3.4 adds a
## LivePacer that waits for the presenter to go idle plus the action delay.
class_name Pacer
extends RefCounted

func after_action(_kind: String) -> void:
	pass
