extends TestCase

## The world map (client/world_map.gd, client/map_view.gd): what the player has explored, kept in the
## browser, drawn as a minimap and a big map in the game's isometric orientation.

const DIR := "user://test_world_map"


func _generated_cell() -> Vector2i:
	var s := MapData.spawn_cell()
	for y in range(-2, 3):
		for x in range(-2, 3):
			MapData.tile_at(s + Vector2i(x, y) * MapData.CHUNK)  # generates the chunks around the spawn
	return s


func test_reveal_marks_the_cells_around_the_player() -> void:
	var at := _generated_cell()
	var map := WorldMap.new()
	assert_false(map.is_explored(at))
	map.reveal(at, 5)
	assert_true(map.is_explored(at))
	assert_true(map.is_explored(at + Vector2i(5, 0)))
	assert_true(map.is_explored(at + Vector2i(3, -3)))
	assert_false(map.is_explored(at + Vector2i(6, 0)), "outside the radius")
	assert_false(map.is_explored(at + Vector2i(4, 4)), "a disc, not a square")


func test_reveal_skips_chunks_not_generated_yet() -> void:
	var far := Vector2i(900000, 900000)
	assert_false(MapData.is_generated(MapData.chunk_of(far)))
	var map := WorldMap.new()
	map.reveal(far, 3)
	assert_false(map.is_explored(far))
	assert_false(MapData.is_generated(MapData.chunk_of(far)), "the map never generates a chunk itself")


func test_explored_cells_have_the_colour_of_what_is_there() -> void:
	var at := _generated_cell()
	var map := WorldMap.new()
	map.reveal(at, 8)
	for y in range(-8, 9):
		for x in range(-8, 9):
			var c := at + Vector2i(x, y)
			if map.is_explored(c):
				assert_eq(map.color_at(c), WorldMap.color_of(c))
	assert_eq(map.color_at(at + Vector2i(50, 50)), Color(0, 0, 0, 0), "unexplored is transparent")


func test_every_ground_and_blocking_object_has_a_colour() -> void:
	var seen := {}
	for t in WorldData.tiles():
		assert_true(WorldMap.GROUND_COLORS.has(t["id"]), "ground %s" % t["id"])
		seen[WorldMap.GROUND_COLORS[t["id"]]] = true
	for o in WorldData.objects():
		if o.get("blocks", false):
			assert_true(WorldMap.OBJECT_COLORS.has(o["id"]), "object %s" % o["id"])
	assert_true(WorldMap.GROUND_COLORS["deep_water"] != WorldMap.GROUND_COLORS["grass"])


func test_chunk_image_shows_explored_cells_only() -> void:
	var at := _generated_cell()
	var map := WorldMap.new()
	map.reveal(at, 2)
	var c := MapData.chunk_of(at)
	var img := map.chunk_image(c)
	assert_eq(img.get_size(), Vector2i(MapData.CHUNK, MapData.CHUNK))
	var local := at - c * MapData.CHUNK
	assert_eq(img.get_pixelv(local), WorldMap.color_of(at))
	var opaque := 0
	for y in MapData.CHUNK:
		for x in MapData.CHUNK:
			if img.get_pixel(x, y).a > 0.0:
				opaque += 1
	assert_true(opaque <= 13, "only the revealed disc (13 cells at most in this chunk)")


func test_reveal_reports_the_chunks_it_changed() -> void:
	var at := _generated_cell()
	var map := WorldMap.new()
	var changed := map.reveal(at, 2)
	assert_true(MapData.chunk_of(at) in changed)
	assert_eq(map.reveal(at, 2), [], "nothing new the second time")


func test_saved_map_loads_back() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + "/map.bin"
	var at := _generated_cell()
	var map := WorldMap.new()
	map.reveal(at, 6)
	assert_true(map.save(path))
	var back := WorldMap.new()
	assert_true(back.load(path))
	assert_eq(back.chunk_count(), map.chunk_count())
	assert_true(back.is_explored(at + Vector2i(6, 0)))
	assert_false(back.is_explored(at + Vector2i(7, 0)))
	DirAccess.remove_absolute(path)


func test_missing_or_broken_file_gives_an_empty_map() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var map := WorldMap.new()
	assert_false(map.load(DIR + "/none.bin"))
	assert_eq(map.chunk_count(), 0)
	var path := DIR + "/broken.bin"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not a map")
	f.close()
	assert_false(map.load(path))
	assert_eq(map.chunk_count(), 0)
	DirAccess.remove_absolute(path)


func test_one_file_per_player_name() -> void:
	assert_eq(WorldMap.path_for("ann"), "user://map_ann.bin")
	assert_true(WorldMap.path_for("ann") != WorldMap.path_for("bob"))


## The map is drawn like the game: +x goes right and down, +y goes left and down, half as tall as wide.
func test_projection_matches_the_isometric_view() -> void:
	var size := Vector2(200, 200)
	var center := Vector2(10, 10)
	assert_eq(MapView.to_screen(center, center, 4.0, size), size / 2)
	var right := MapView.to_screen(center + Vector2(1, 0), center, 4.0, size) - size / 2
	var left := MapView.to_screen(center + Vector2(0, 1), center, 4.0, size) - size / 2
	var game_right := IsoLayer.cell_to_local(Vector2(1, 0)) - IsoLayer.cell_to_local(Vector2.ZERO)
	var game_left := IsoLayer.cell_to_local(Vector2(0, 1)) - IsoLayer.cell_to_local(Vector2.ZERO)
	assert_almost(right.angle(), game_right.angle(), 0.001)
	assert_almost(left.angle(), game_left.angle(), 0.001)
	var p := Vector2(13.5, 7.25)
	var back := MapView.to_cell(MapView.to_screen(p, center, 4.0, size), center, 4.0, size)
	assert_almost(back.x, p.x, 0.001)
	assert_almost(back.y, p.y, 0.001)


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	return e


## The mouse wheel over a map zooms that map, within its limits.
func test_wheel_zooms_the_map() -> void:
	var view := MapView.new(WorldMap.new(), 1.0, 8.0, 2.0)
	view._gui_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	assert_true(view.zoom > 2.0)
	for i in 50:
		view._gui_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	assert_eq(view.zoom, 8.0)
	for i in 80:
		view._gui_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	assert_eq(view.zoom, 1.0)
	view.free()
