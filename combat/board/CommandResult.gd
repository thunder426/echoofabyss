## CommandResult.gd
## Outcome of a CombatState command (LIVE_SIM_UNIFICATION_PLAN.md 2A.1).
##   ok == false — refused: validation failed and nothing changed. `reason` says why
##                 ("not_your_turn", "cost", "guard", ...).
##   ok == true  — accepted. A non-empty `reason` means it resolved without its
##                 normal effect ("countered", "cancelled", "attacker_gone").
class_name CommandResult
extends RefCounted

var ok: bool = false
var reason: String = ""

static func accepted(why: String = "") -> CommandResult:
	var r := CommandResult.new()
	r.ok = true
	r.reason = why
	return r

static func refused(why: String) -> CommandResult:
	var r := CommandResult.new()
	r.ok = false
	r.reason = why
	return r
