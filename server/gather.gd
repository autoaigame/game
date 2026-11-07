## What can be gathered from world objects (server only). A gathered object gives nothing until it
## regrows. Reach is Protocol.GATHER_REACH (the client walks that close before asking).
extends RefCounted

const REACH := Protocol.GATHER_REACH
## object id -> {item, min, max (how many per gathering), regrow_s}
const RULES := {
	"bush": {"item": "berries", "min": 1, "max": 3, "regrow_s": 120.0},
}
