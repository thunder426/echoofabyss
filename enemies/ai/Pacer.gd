## Pacer.gd
## What a StateAgent waits on between actions (LIVE_SIM_UNIFICATION_PLAN.md
## 2A.5). The base pacer returns at once — every driver uses it: sim, tests and
## the live enemy (whose actions the presenter paces as it plays the journal).
## A pacer that really waits made profile loops misbehave on resume (task 045).
class_name Pacer
extends RefCounted

func after_action(_kind: String) -> void:
	pass
