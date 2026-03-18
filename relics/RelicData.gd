## RelicData.gd
## Static definition of a relic. Relics grant persistent passive effects for a run.
class_name RelicData
extends Resource

var id: String = ""
var relic_name: String = ""
var description: String = ""
var act: int = 1   ## Which act this relic is offered in (1, 2, or 3)
