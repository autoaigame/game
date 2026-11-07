## Layered ambience, the pure part: which ambience the grounds around the player call for, how its
## layers fade, when and how its one-shot sounds play. Data in res://data/ambience/<id>.json:
## beds (loops at a volume) and events (one-shots from a list, at random intervals, gain, pan and pitch).
## Client display only: the server never sees it. client/sound_director.gd plays what this decides.
class_name AmbienceMix
extends RefCounted

const DATA_DIR := "res://data/ambience"
const SOUND_DIR := "res://assets/sounds/ambience"
## The grounds counted in this radius around the player, in cells.
const RADIUS_CELLS := 4
## Another ambience takes over only when it covers this much more of the disc than the current one.
const SWITCH_MARGIN := 0.15
const SILENT_DB := -80.0


static func sound_path(sound: String) -> String:
	return SOUND_DIR.path_join(sound + ".ogg")


## Every ambience, sorted by id: {id, name, grounds: {tile index: true}, debug_only, fade_s, beds: [{sound,
## volume_db}], events: [{sounds, interval_s: [min, max], volume_db, volume_jitter_db, pan, pitch}]}.
static func load_all(dir := DATA_DIR) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not rec is Dictionary or rec.get("id", "") != f.get_basename():
			push_error("ambience: %s must be an object with \"id\": \"%s\"" % [f, f.get_basename()])
			continue
		var grounds := {}
		for g in rec.get("grounds", []):
			var t := WorldData.tile_index(g)
			if t < 0:
				push_error("ambience %s: unknown ground %s" % [rec["id"], g])
			grounds[t] = true
		var events := []
		for e in rec.get("events", []):
			events.append({"sounds": Array(e["sounds"]), "interval_s": [float(e["interval_s"][0]), float(e["interval_s"][1])],
					"volume_db": float(e["volume_db"]), "volume_jitter_db": float(e.get("volume_jitter_db", 0.0)),
					"pan": float(e.get("pan", 0.0)), "pitch": float(e.get("pitch", 0.0))})
		var beds := []
		for b in rec.get("beds", []):
			beds.append({"sound": String(b["sound"]), "volume_db": float(b["volume_db"])})
		out.append({"id": String(rec["id"]), "name": String(rec.get("name", rec["id"])), "grounds": grounds,
				"debug_only": bool(rec.get("debug_only", false)), "fade_s": maxf(0.1, float(rec.get("fade_s", 3.0))),
				"beds": beds, "events": events})
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out


static func find(ambiences: Array, id: String) -> Dictionary:
	for a in ambiences:
		if a["id"] == id:
			return a
	return {}


## {tile index: number of cells} in the disc of `radius` cells around `center`.
static func ground_counts(center: Vector2i, radius: int = RADIUS_CELLS) -> Dictionary:
	var out := {}
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var t := MapData.tile_at(center + Vector2i(dx, dy))
			out[t] = out.get(t, 0) + 1
	return out


## Share of the counted cells whose ground the ambience lists.
static func score(ambience: Dictionary, counts: Dictionary) -> float:
	var total := 0
	var mine := 0
	for t in counts:
		total += counts[t]
		if ambience["grounds"].has(t):
			mine += counts[t]
	return float(mine) / total if total > 0 else 0.0


## Id of the ambience to play: the best-scoring one that is not debug-only, unless the current one is
## within SWITCH_MARGIN of it, or no ambience matches any counted ground (then the current, or the first).
static func choose(ambiences: Array, counts: Dictionary, current: String, margin := SWITCH_MARGIN) -> String:
	var best := ""
	var best_score := 0.0
	var current_score := -1.0
	var first := ""
	for a in ambiences:
		if a["debug_only"]:
			continue
		if first == "":
			first = a["id"]
		var s := score(a, counts)
		if a["id"] == current:
			current_score = s
		if s > best_score:
			best = a["id"]
			best_score = s
	if best == "":
		return current if current_score >= 0.0 else first
	if current_score >= 0.0 and best_score - current_score < margin:
		return current
	return best


## Weight (0..1) after dt seconds moving towards target, a full fade taking fade_s.
static func approach(weight: float, target: float, dt: float, fade_s: float) -> float:
	return move_toward(weight, target, dt / fade_s)


## Volume offset in dB of a layer at this fade weight (equal-power curve).
static func fade_db(weight: float) -> float:
	if weight <= 0.0:
		return SILENT_DB
	return maxf(SILENT_DB, linear_to_db(sin(weight * PI / 2.0)))


## Seconds until an event's next one-shot.
static func next_delay(rng: RandomNumberGenerator, event: Dictionary) -> float:
	return rng.randf_range(event["interval_s"][0], event["interval_s"][1])


## One one-shot of an event: {sound, volume_db, pan: -1 left..1 right, pitch: scale}. Never `last` again
## when the event has another sound.
static func roll(rng: RandomNumberGenerator, event: Dictionary, last := "") -> Dictionary:
	var sounds: Array = event["sounds"]
	var choices := sounds.filter(func(s): return s != last) if sounds.size() > 1 else sounds
	var j: float = event["volume_jitter_db"]
	var p: float = event["pan"]
	var q: float = event["pitch"]
	return {"sound": choices[rng.randi_range(0, choices.size() - 1)],
			"volume_db": event["volume_db"] + rng.randf_range(-j, j),
			"pan": rng.randf_range(-p, p), "pitch": 1.0 + rng.randf_range(-q, q)}

