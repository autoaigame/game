extends TestCase

## Small wild animals (server/wildlife.gd): they live near players in their biomes, wander, and flee
## from players and dogs.

const WILD := preload("res://server/wildlife.gd")
const SERVER_SCRIPT := "res://server/server.gd"


func _cell_of_biome(id: String, walkable := true) -> Vector2i:
	var want := WorldData.biome_index(id)
	var s := MapData.spawn_cell()
	for r in 400:
		for dx in range(-r, r + 1, 3):
			for dy in [-r, r]:
				var c := s + Vector2i(dx, dy)
				if Terrain.biome(c.x, c.y) == want and (not walkable or (MapData.is_walkable(c) and MapData.object_at(c) == "")):
					return c
	return s


func _open_grass() -> Vector2i:
	return _cell_of_biome("grassland")


func _animal_at(wild: Dictionary, kind: String, cell: Vector2i) -> int:
	return WILD.add(wild, kind, Vector2(cell))


func test_species_are_data() -> void:
	var ids := WILD.species().keys()
	assert_true(ids.has("rabbit") and ids.has("pheasant"), "species: %s" % [ids])
	for id in ids:
		var sp: Dictionary = WILD.species()[id]
		assert_true(sp["flee_speed"] > sp["walk_speed"], "%s runs when scared" % id)
		assert_true(sp["biomes"].size() > 0)
		for b in sp["biomes"]:
			assert_true(b >= 0, "%s: known biome" % id)


func test_lives_only_in_its_biomes_on_walkable_ground() -> void:
	assert_true(WILD.can_live("rabbit", _open_grass()))
	var water := _cell_of_biome("deep_water", false)
	assert_eq(Terrain.biome(water.x, water.y), WorldData.biome_index("deep_water"), "test needs water")
	assert_false(WILD.can_live("rabbit", water))
	assert_false(WILD.can_live("pheasant", _cell_of_biome("beach")))


func test_animals_appear_around_players() -> void:
	var wild := WILD.new_wild(3)
	var at := Vector2(_open_grass())
	for i in 120:
		WILD.populate(wild, [at], 0.5)
	var animals: Dictionary = wild["animals"]
	assert_true(animals.size() >= 2, "some animals: %d" % animals.size())
	assert_true(animals.size() <= WILD.PER_PLAYER, "not too many: %d" % animals.size())
	for id in animals:
		var a: Dictionary = animals[id]
		assert_true(id < 0, "animal ids are negative (dogs use peer ids)")
		var d: float = a["pos"].distance_to(at)
		assert_true(d >= WILD.SPAWN_MIN - 0.01 and d <= WILD.SPAWN_MAX + 0.01, "appeared out of sight: %f" % d)
		assert_true(WILD.can_live(a["kind"], Protocol.cell_of(a["pos"])), "in its biome")


func test_animals_far_from_everyone_go() -> void:
	var wild := WILD.new_wild(3)
	var at := _open_grass()
	var id := _animal_at(wild, "rabbit", at)
	WILD.populate(wild, [Vector2(at)], 0.1)
	assert_true(wild["animals"].has(id), "kept near a player")
	WILD.populate(wild, [Vector2(at) + Vector2(WILD.DESPAWN + 5, 0)], 0.1)
	assert_false(wild["animals"].has(id), "gone when nobody is near")


func test_flees_from_a_threat() -> void:
	var wild := WILD.new_wild(1)
	var at := _open_grass()
	var id := _animal_at(wild, "rabbit", at)
	var threat := Vector2(at) + Vector2(1.5, 0)
	var before: float = Vector2(at).distance_to(threat)
	for i in 3:
		WILD.update(wild, [threat], 1.0 / 15.0)
	assert_eq(wild["animals"][id]["state"], "flee")
	for i in 9:
		WILD.update(wild, [threat], 1.0 / 15.0)
	var a: Dictionary = wild["animals"][id]
	var gained: float = a["pos"].distance_to(threat) - before
	var sp: Dictionary = WILD.species()["rabbit"]
	assert_true(gained > 0.8 * (sp["walk_speed"] + sp["flee_speed"]) / 2.0, "ran away fast: %f in 0.8 s" % gained)


func test_calms_down_once_safe() -> void:
	var wild := WILD.new_wild(1)
	var at := _open_grass()
	var id := _animal_at(wild, "rabbit", at)
	var threat := Vector2(at) + Vector2(1.5, 0)
	WILD.update(wild, [threat], 0.1)
	assert_eq(wild["animals"][id]["state"], "flee")
	for i in 60:
		WILD.update(wild, [Vector2(at) + Vector2(60, 0)], 0.1)
	assert_true(wild["animals"][id]["state"] in ["idle", "hop"], "calm again")


func test_wanders_near_home_when_calm() -> void:
	var wild := WILD.new_wild(2)
	var at := _open_grass()
	var id := _animal_at(wild, "rabbit", at)
	var states := {}
	for i in 600:
		WILD.update(wild, [], 0.1)
		states[wild["animals"][id]["state"]] = true
	assert_true(states.has("hop") and states.has("idle"), "hops about and rests: %s" % [states.keys()])
	assert_true(wild["animals"][id]["pos"].distance_to(Vector2(at)) <= WILD.WANDER_RADIUS + 1.5, "near home")


func test_never_stands_on_blocked_ground() -> void:
	var wild := WILD.new_wild(5)
	var at := _cell_of_biome("forest")
	var id := _animal_at(wild, "pheasant", at)
	var chaser := Vector2(at)
	for i in 300:
		var a: Dictionary = wild["animals"][id]
		chaser = chaser.move_toward(a["pos"], 0.3)
		WILD.update(wild, [chaser], 0.1)
		assert_true(MapData.is_walkable(Protocol.cell_of(wild["animals"][id]["pos"])), "on walkable ground")


func test_server_sends_nearby_animals_and_they_flee_dogs() -> void:
	var server: Node = load(SERVER_SCRIPT).new()
	var at := _open_grass()
	server._players[1] = server._new_player("ann", at + Vector2i(10, 0), {})
	var id: int = _animal_at(server._wild, "rabbit", at)
	var kinds: Array = server._creatures_for(1).map(func(c): return c["kind"])
	assert_true(kinds.has("rabbit"), "sent: %s" % [kinds])
	assert_true(server._threats().has(server._players[1]["dog"]["pos"]), "dogs scare animals")
	assert_true(server._threats().has(server._players[1]["pos"]), "players scare animals")
	server.free()
