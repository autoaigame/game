## Hand-made places (data/places/*.json) dropped into the generated world. The world is cut into
## REGION x REGION regions; each region draws, from a hash of (world seed, region), at most one candidate
## place and a top-left corner inside the region, then keeps it only if the rules hold: allowed biomes
## and no water under the whole footprint, a small altitude range, away from the starting meadow, and
## no stronger candidate (higher hash) closer than min_distance. A footprint stays inside its region,
## so a chunk (16 cells, inside one 64-cell region) only looks at its own region, and a place across two
## chunks comes out whole on both sides. Pure functions of world coordinates; memoized per region.
class_name WorldPlaces
extends RefCounted

const REGION := 64
const _SALT := 0x91ACE5

static var _candidates := {}  ## region -> candidate Dictionary ({} = none)
static var _accepted := {}  ## region -> bool
static var _set_up := false


## The places whose footprint may touch `rect` (world cells), kept by the rules:
## [{index, origin, region}, ...] in region order.
static func places_in(rect: Rect2i) -> Array[Dictionary]:
	_setup()
	var out: Array[Dictionary] = []
	var r0 := _region_of(rect.position)
	var r1 := _region_of(rect.end - Vector2i.ONE)
	for ry in range(r0.y, r1.y + 1):
		for rx in range(r0.x, r1.x + 1):
			var r := Vector2i(rx, ry)
			if is_accepted(r):
				var c: Dictionary = candidate(r)
				var size: Vector2i = WorldData.places()[c["index"]]["size"]
				if Rect2i(c["origin"], size).intersects(rect):
					out.append(c)
	return out


## The candidate a region draws, before the distance rule: {} or {index, origin, region, priority,
## terrain_ok}. terrain_ok = biomes, water, altitude and meadow rules hold.
static func candidate(r: Vector2i) -> Dictionary:
	_setup()
	if _candidates.has(r):
		return _candidates[r]
	var c := {}
	var places := WorldData.places()
	if not places.is_empty():
		var h := WorldNoise.hash3(int(WorldData.gen()["seed"]), r.x, r.y, _SALT)
		var index := WorldNoise.mix32(h ^ 1) % places.size()
		var place: Dictionary = places[index]
		if WorldNoise.unit(h) < place["chance"]:
			var size: Vector2i = place["size"]
			var origin := r * REGION + Vector2i(
					WorldNoise.mix32(h ^ 2) % (REGION - size.x + 1), WorldNoise.mix32(h ^ 3) % (REGION - size.y + 1))
			c = {"index": index, "origin": origin, "region": r, "priority": h}
			c["terrain_ok"] = fits(place, origin)
	_candidates[r] = c
	return c


## Whether the region's candidate is kept: its terrain rules hold and no stronger candidate whose
## terrain rules hold lies closer than the larger of the two min_distance.
static func is_accepted(r: Vector2i) -> bool:
	if _accepted.has(r):
		return _accepted[r]
	var c := candidate(r)
	var ok: bool = not c.is_empty() and c["terrain_ok"]
	if ok:
		var places := WorldData.places()
		var me: Dictionary = places[c["index"]]
		var reach := ceili(_max_distance() / REGION) + 1
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if dx == 0 and dy == 0:
					continue
				var o := candidate(r + Vector2i(dx, dy))
				if o.is_empty() or not o["terrain_ok"] or not _stronger(o, c):
					continue
				var other: Dictionary = places[o["index"]]
				var limit := maxf(me["min_distance"], other["min_distance"])
				if _center(o).distance_to(_center(c)) < limit:
					ok = false
					break
			if not ok:
				break
	_accepted[r] = ok
	return ok


## Forgets the memo (tests use it to check that results do not depend on it).
static func clear_cache() -> void:
	_candidates.clear()
	_accepted.clear()


## Whether a place (WorldData.places() record) at `origin` meets its terrain rules: allowed biomes, no
## water, altitude range, off the starting meadow.
static func fits(place: Dictionary, origin: Vector2i) -> bool:
	var biomes := WorldData.biomes()
	var lo := 1.0
	var hi := 0.0
	for pc in place["cells"]:
		var cell: Vector2i = origin + pc[0]
		if Terrain.meadow_t(cell.x, cell.y) < 1.0:
			return false  # never on the starting meadow
		var b := Terrain.biome(cell.x, cell.y)
		if not place["biomes"].has(b) or not WorldData.tile(biomes[b]["tile"])["walkable"]:
			return false
		var alt := Terrain.altitude(cell.x, cell.y)
		lo = minf(lo, alt)
		hi = maxf(hi, alt)
		if hi - lo > place["max_altitude_range"]:
			return false
	return true


static func _stronger(a: Dictionary, b: Dictionary) -> bool:
	if a["priority"] != b["priority"]:
		return a["priority"] > b["priority"]
	var ra: Vector2i = a["region"]
	var rb: Vector2i = b["region"]
	return ra.y < rb.y or (ra.y == rb.y and ra.x < rb.x)


static func _center(c: Dictionary) -> Vector2:
	return Vector2(c["origin"]) + Vector2(WorldData.places()[c["index"]]["size"]) / 2.0


static func _max_distance() -> float:
	var d := 0.0
	for p in WorldData.places():
		d = maxf(d, p["min_distance"])
	return d


static func _region_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(REGION)), floori(cell.y / float(REGION)))


static func _setup() -> void:
	if _set_up:
		return
	_set_up = true
	for p in WorldData.places():
		var size: Vector2i = p["size"]
		if size.x > REGION or size.y > REGION:
			push_error("data: place %s is larger than a region" % p["id"])
