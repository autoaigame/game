## Footsteps, the pure part: a step each time a foot lands in the drawn walk (WalkAnim's contact frames),
## its sounds by the ground under the feet (res://data/sounds.json). Client display only.
class_name Footsteps
extends RefCounted

const DATA := "res://data/sounds.json"
const SOUND_DIR := "res://assets/sounds/steps"


static func sound_path(sound: String) -> String:
	return SOUND_DIR.path_join(sound + ".ogg")


## Footsteps this frame for a walker whose drawn walk phase went from phase_before to phase_after (w["phase"]
## before and after WalkAnim.animate): one per foot landing, on WalkAnim.CONTACT_FRAMES.
static func steps(phase_before: float, phase_after: float) -> int:
	return WalkAnim.contacts_between(phase_before, phase_after)


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
