extends TestCase


func test_moves_at_speed() -> void:
	var p := Protocol.step_towards(Vector2(16, 16), Vector2i(20, 16), 0.25)
	assert_almost(p.x, 17.0, 0.01)
	assert_almost(p.y, 16.0, 0.01)


func test_never_overshoots() -> void:
	var p := Protocol.step_towards(Vector2(16, 16), Vector2i(17, 16), 5.0)
	assert_eq(p, Vector2(17, 16))


## Walks from the spawn towards the first non-walkable cell along +x, far away: stops just before it.
func test_stops_before_water() -> void:
	var start := MapData.spawn_cell()
	var wall := start
	while MapData.is_walkable(wall):
		wall += Vector2i(1, 0)
	var p := Protocol.step_towards(Vector2(start), wall + Vector2i(5, 0), 1000.0)
	var cell := Protocol.cell_of(p)
	assert_true(MapData.is_walkable(cell), "ended on %s" % cell)
	assert_eq(cell, wall - Vector2i(1, 0))


func test_cell_of_rounds() -> void:
	assert_eq(Protocol.cell_of(Vector2(3.4, 5.6)), Vector2i(3, 6))
