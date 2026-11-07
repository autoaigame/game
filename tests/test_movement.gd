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


## A walkable cell c where c + dir is walkable but a cell beside that diagonal step is not: the corner
## of a water cell. The first one found in rings around the spawn, or null.
static func _water_corner(dir: Vector2i) -> Variant:
	for r in 200:
		for c in _ring(MapData.spawn_cell(), r):
			if MapData.is_walkable(c) and MapData.is_walkable(c + dir) \
					and not (MapData.is_walkable(c + Vector2i(dir.x, 0)) and MapData.is_walkable(c + Vector2i(0, dir.y))):
				return c
	return null

## The cells at Chebyshev distance r from center (the square ring), in a fixed order.
static func _ring(center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) == r:
				out.append(center + Vector2i(dx, dy))
	return out



## A click (move_to) on the far side of a water corner: the straight line crosses the corner point, but
## the player stops on its side of it instead of slipping between the cells, on every diagonal.
func test_never_cuts_a_water_corner() -> void:
	for dir in [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var c: Variant = _water_corner(dir)
		assert_true(c != null, "no water corner near the spawn for %s" % dir)
		var p := Protocol.step_towards(Vector2(c), c + dir, 10.0)
		assert_eq(Protocol.cell_of(p), c, "dir %s from %s ended at %s" % [dir, c, p])


## Starting a few cells back on a clear diagonal, the click still walks up to the corner and stops there.
func test_walks_a_clear_diagonal_up_to_a_water_corner() -> void:
	var dir := Vector2i(1, 1)
	var c := Vector2i.ZERO
	var found := false
	for r in 200:
		for cell in _ring(MapData.spawn_cell(), r):
			if found or not (MapData.is_walkable(cell + dir) and not (MapData.is_walkable(cell + Vector2i(1, 0)) \
					and MapData.is_walkable(cell + Vector2i(0, 1)))):
				continue
			var clear := true
			for k in range(1, 4):
				var b := cell - dir * k
				if not (MapData.is_walkable(b) and MapData.is_walkable(b + Vector2i(1, 0)) and MapData.is_walkable(b + Vector2i(0, 1))):
					clear = false
			if clear:
				c = cell
				found = true
		if found:
			break
	assert_true(found, "no clear diagonal up to a water corner near the spawn")
	var p := Protocol.step_towards(Vector2(c - dir * 3), c + dir * 2, 10.0)
	assert_eq(Protocol.cell_of(p), c, "walked from %s, ended at %s" % [c - dir * 3, p])
