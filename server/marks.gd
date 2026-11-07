## Short-lived marks on the ground that clients draw (pee spots, holes). Pure functions on a marks
## record, run by the server (server only: the web build never loads this file). Not saved.
extends RefCounted

## At most this many marks at once; adding more drops the oldest.
const MAX_MARKS := 200


static func new_marks() -> Dictionary:
	return {"next_id": 1, "items": []}


## Adds a mark of `kind` at `pos` (cells) for `ttl` seconds.
static func add(marks: Dictionary, kind: String, pos: Vector2, ttl: float) -> void:
	var items: Array = marks["items"]
	items.append({"id": marks["next_id"], "kind": kind, "pos": pos, "left": ttl})
	marks["next_id"] += 1
	while items.size() > MAX_MARKS:
		items.pop_front()


## Ages every mark by `dt` and removes the expired ones; true if any was removed.
static func tick(marks: Dictionary, dt: float) -> bool:
	var kept: Array = []
	for m in marks["items"]:
		m["left"] -= dt
		if m["left"] > 0.0:
			kept.append(m)
	var changed: bool = kept.size() != marks["items"].size()
	marks["items"] = kept
	return changed


## What clients get: [{id, kind, pos, left (seconds)}, ...], oldest first.
static func snapshot(marks: Dictionary) -> Array:
	var out: Array = []
	for m in marks["items"]:
		out.append(m.duplicate())
	return out
