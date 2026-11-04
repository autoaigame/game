extends TestCase


func test_moves_at_speed() -> void:
	var p := Protocol.step_towards(Vector2(16, 16), Vector2i(20, 16), 0.25)
	assert_almost(p.x, 17.0, 0.01)
	assert_almost(p.y, 16.0, 0.01)


func test_never_overshoots() -> void:
	var p := Protocol.step_towards(Vector2(16, 16), Vector2i(17, 16), 5.0)
	assert_eq(p, Vector2(17, 16))


func test_stops_before_water() -> void:
	# Column 16 is path down to row 1; row 0 is the water border.
	var p := Protocol.step_towards(Vector2(16, 16), Vector2i(16, 0), 10.0)
	var cell := Protocol.cell_of(p)
	assert_true(MapData.is_walkable(cell), "ended on %s" % cell)
	assert_eq(cell, Vector2i(16, 1))


func test_cell_of_rounds() -> void:
	assert_eq(Protocol.cell_of(Vector2(3.4, 5.6)), Vector2i(3, 6))
