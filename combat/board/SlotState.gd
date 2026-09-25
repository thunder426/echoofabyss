## Engine-owned board slot (LIVE_SIM_UNIFICATION_PLAN.md 3.1a, decision D11).
##
## Plain occupancy data — no Node, no visuals, no scene tree. `CombatState`
## allocates BOARD_MAX of these per side for both shells; the live `BoardSlot`
## Panel is a *view* of one of them that `CombatScene._on_slot_changed`
## refreshes (and, from Phase 3.2, the presenter refreshes on playback).
##
## Rules code reads `minion` / `is_empty()` and mutates only through `place` /
## `clear`, which emit `changed` so the view can follow.
class_name SlotState
extends RefCounted

signal changed(slot: SlotState)

var side: String = "player"
var index: int = 0
var minion: MinionInstance = null


static func make(p_side: String, p_index: int) -> SlotState:
	var s := SlotState.new()
	s.side = p_side
	s.index = p_index
	return s


func is_empty() -> bool:
	return minion == null


## Occupy the slot. Stamps the minion's `slot_index` (adjacency rules read it).
func place(m: MinionInstance) -> void:
	minion = m
	if m != null:
		m.slot_index = index
	changed.emit(self)


## Free the slot. The occupant's `slot_index` is left as-is — death handlers
## still read where it stood.
func clear() -> void:
	minion = null
	changed.emit(self)
