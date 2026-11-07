## Items (res://data/items/*.json), read once. Shared: the server keeps inventories by item id, the
## client shows names and colours. Ids are never renamed: saved inventories refer to them.
class_name ItemData
extends RefCounted

static var _items: Array[Dictionary] = []  ## sorted by id
static var _by_id := {}


## Item records, sorted by id: {id, name, food (hunger points restored when eaten, 0 if not food),
## color: Color (its icon)}.
static func items() -> Array[Dictionary]:
	_ensure()
	return _items


## The record of an item id, or {}.
static func item(id: String) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


static func _ensure() -> void:
	if not _items.is_empty():
		return
	for rec in WorldData.read_folder("items"):
		var c: Array = rec.get("color", [128, 128, 128])
		var it := {"id": String(rec["id"]), "name": String(rec.get("name", rec["id"])), "food": int(rec.get("food", 0)),
				"color": Color8(int(c[0]), int(c[1]), int(c[2]))}
		_items.append(it)
		_by_id[it["id"]] = it
