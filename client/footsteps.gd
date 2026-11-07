## Footsteps, the pure part: a step's sounds by the ground under the feet (res://data/sounds.json). The
## steps themselves come from the feet of the drawn 3D walk (Character3D.step). Client display only.
class_name Footsteps
extends RefCounted

const DATA := "res://data/sounds.json"
const SOUND_DIR := "res://assets/sounds/steps"


static func sound_path(sound: String) -> String:
	return SOUND_DIR.path_join(sound + ".ogg")


## {tile index: [sound names]} from data/sounds.json "footsteps".
static func load_table(path := DATA) -> Dictionary:
	var out := {}
	var rec := read_data(path)
	var steps: Dictionary = rec.get("footsteps", {})
	for g in steps:
		var t := WorldData.tile_index(g)
		if t < 0:
			push_error("sounds.json: unknown ground %s" % g)
			continue
		out[t] = Array(steps[g])
	return out


static func read_data(path := DATA) -> Dictionary:
	var rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not rec is Dictionary:
		push_error("cannot read %s" % path)
		return {}
	return rec


## A variant index in [0, count), never `last` when there is a choice.
static func pick_variant(rng: RandomNumberGenerator, count: int, last: int) -> int:
	if count <= 1:
		return 0
	var v := rng.randi_range(0, count - 2)
	return v + 1 if last >= 0 and v >= last else v
