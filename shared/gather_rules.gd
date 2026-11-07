## What can be gathered from world objects. Shared: the server applies it, the client knows what a
## click on an object means. A gathered object gives nothing until it regrows.
class_name GatherRules
extends RefCounted

## object id -> {item, min, max (how many per gathering), regrow_s, empty (the notice while regrowing)}
const RULES := {
	"bush": {"item": "berries", "min": 1, "max": 3, "regrow_s": 120.0, "empty": "bush_empty"},
	"oak": {"item": "sticks", "min": 1, "max": 2, "regrow_s": 180.0, "empty": "tree_empty"},
	"birch": {"item": "sticks", "min": 1, "max": 2, "regrow_s": 180.0, "empty": "tree_empty"},
	"pine": {"item": "sticks", "min": 1, "max": 2, "regrow_s": 180.0, "empty": "tree_empty"},
}
