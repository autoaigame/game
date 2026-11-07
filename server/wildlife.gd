## Small wild animals (server only). Species are data (res://data/animals/*.json). They appear out of
## sight around players, in their biomes, and go when nobody is near. Calm, they hop about their home
## cell and rest; when a threat (a player or a dog) comes within their flee radius they run away from
## it, faster than they walk, and calm down once it is far. Movement keeps invariant 2 (walkable cells).
##
## A wild record: {next_id (negative: dogs use peer ids), animals: id -> animal, rng, spawn_in}.
## An animal: {kind, pos, home: Vector2, state: idle | hop | flee, goal: Variant, rest}.
extends RefCounted

const PER_PLAYER := 5  ## animals kept around each player
const SPAWN_MIN := 14.0  ## out of sight, but not far
const SPAWN_MAX := 24.0
const DESPAWN := 40.0  ## gone when no player is this close
const SPAWN_EVERY := 1.5
const WANDER_RADIUS := 3
const REST_MIN_S := 1.0
const REST_MAX_S := 4.0
const CALM_FACTOR := 1.6  ## calm once every threat is this many flee radii away
const FLEE_STEP := 3.0  ## cells ahead it aims for when fleeing

static var _species := {}


## Species by id: {id, name, biomes: Array of biome indices, walk_speed, flee_speed, flee_radius}.
static func species() -> Dictionary:
	if _species.is_empty():
		for rec in WorldData.read_folder("animals"):
			var biomes := []
			for b in rec["biomes"]:
				var i := WorldData.biome_index(b)
				if i < 0:
					push_error("data: animal %s names unknown biome %s" % [rec["id"], b])
				biomes.append(i)
			_species[String(rec["id"])] = {"id": String(rec["id"]), "name": String(rec["name"]), "biomes": biomes,
					"walk_speed": float(rec["walk_speed"]), "flee_speed": float(rec["flee_speed"]),
					"flee_radius": float(rec["flee_radius"])}
	return _species


static func new_wild(seed_value := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {"next_id": -1, "animals": {}, "rng": rng, "spawn_in": 0.0}


## Whether an animal of `kind` may stand on `cell`: walkable, no object, in one of its biomes.
static func can_live(kind: String, cell: Vector2i) -> bool:
	var sp: Dictionary = species().get(kind, {})
	return not sp.is_empty() and MapData.is_walkable(cell) and MapData.object_at(cell) == "" \
			and Terrain.biome(cell.x, cell.y) in sp["biomes"]


## Adds an animal; returns its id.
static func add(wild: Dictionary, kind: String, pos: Vector2) -> int:
	var id: int = wild["next_id"]
	wild["next_id"] = id - 1
	wild["animals"][id] = {"kind": kind, "pos": pos, "home": pos, "state": "idle", "goal": null,
			"rest": (wild["rng"] as RandomNumberGenerator).randf_range(REST_MIN_S, REST_MAX_S)}
	return id


## Removes animals no player is near, and now and then adds one out of sight of a player who has
## fewer than PER_PLAYER around.
static func populate(wild: Dictionary, players: Array, dt: float) -> void:
	var animals: Dictionary = wild["animals"]
	for id in animals.keys():
		if not players.any(func(p): return (p as Vector2).distance_to(animals[id]["pos"]) <= DESPAWN):
			animals.erase(id)
	wild["spawn_in"] -= dt
	if wild["spawn_in"] > 0.0:
		return
	wild["spawn_in"] = SPAWN_EVERY
	var rng: RandomNumberGenerator = wild["rng"]
	for p in players:
		var near := animals.values().filter(func(a): return (a["pos"] as Vector2).distance_to(p) <= SPAWN_MAX).size()
		if near >= PER_PLAYER:
			continue
		var kinds := species().keys()
		kinds.sort()
		var kind: String = kinds[rng.randi() % kinds.size()]
		for attempt in 8:
			var at := Protocol.cell_of((p as Vector2) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(SPAWN_MIN, SPAWN_MAX))
			var d := Vector2(at).distance_to(p)
			if d >= SPAWN_MIN and d <= SPAWN_MAX and can_live(kind, at):
				add(wild, kind, Vector2(at))
				break


## Moves every animal: flee from the nearest threat in range, else wander about home.
static func update(wild: Dictionary, threats: Array, dt: float) -> void:
	for id in wild["animals"]:
		_update_one(wild["animals"][id], threats, wild["rng"], dt)


## The animals within `radius` of `pos`, as creatures for clients: {id, kind, owner: 0, pos, state}.
static func snapshot_near(wild: Dictionary, pos: Vector2, radius: float) -> Array:
	var out := []
	for id in wild["animals"]:
		var a: Dictionary = wild["animals"][id]
		if pos.distance_to(a["pos"]) <= radius:
			out.append({"id": id, "kind": a["kind"], "owner": 0, "pos": a["pos"], "state": a["state"]})
	return out


static func _update_one(a: Dictionary, threats: Array, rng: RandomNumberGenerator, dt: float) -> void:
	var sp: Dictionary = species()[a["kind"]]
	var nearest: Variant = null
	for t in threats:
		if nearest == null or (t as Vector2).distance_to(a["pos"]) < (nearest as Vector2).distance_to(a["pos"]):
			nearest = t
	var gap: float = INF if nearest == null else (nearest as Vector2).distance_to(a["pos"])
	if gap <= sp["flee_radius"] or (a["state"] == "flee" and gap <= sp["flee_radius"] * CALM_FACTOR):
		a["state"] = "flee"
		var goal: Variant = _away(a["pos"], nearest)
		if goal != null:
			a["pos"] = _step(a["pos"], goal, sp["flee_speed"], dt)
		a["home"] = a["pos"]
		a["goal"] = null
		return
	if a["state"] == "flee":
		a["state"] = "idle"
		a["rest"] = rng.randf_range(REST_MIN_S, REST_MAX_S)
	if a["state"] == "hop":
		a["pos"] = _step(a["pos"], a["goal"], sp["walk_speed"], dt)
		if (a["pos"] as Vector2).distance_to(Vector2(a["goal"])) < 0.05:
			a["state"] = "idle"
			a["rest"] = rng.randf_range(REST_MIN_S, REST_MAX_S)
		return
	a["rest"] -= dt
	if a["rest"] > 0.0:
		return
	var home := Protocol.cell_of(a["home"])
	var goal := home + Vector2i(rng.randi_range(-WANDER_RADIUS, WANDER_RADIUS), rng.randi_range(-WANDER_RADIUS, WANDER_RADIUS))
	if can_live(a["kind"], goal):
		a["state"] = "hop"
		a["goal"] = goal
	else:
		a["rest"] = REST_MIN_S


## A walkable cell about FLEE_STEP cells away from `threat`, trying straight away first, then turning.
static func _away(pos: Vector2, threat: Vector2) -> Variant:
	var dir := (pos - threat).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var cell := Protocol.cell_of(pos + dir.rotated(turn) * FLEE_STEP)
		if MapData.is_walkable(cell):
			return cell
	return null


static func _step(pos: Vector2, goal: Vector2i, speed: float, dt: float) -> Vector2:
	return Protocol.step_towards(pos, goal, dt * speed / Protocol.SPEED_CELLS_PER_S)
