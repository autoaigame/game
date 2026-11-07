extends TestCase


## Keys follow the screen, not the grid: in the 2:1 view a grid axis is a screen diagonal.
func test_single_keys_follow_the_screen() -> void:
	assert_eq(KeyMove.direction(true, false, false, false), Vector2i(-1, -1))
	assert_eq(KeyMove.direction(false, true, false, false), Vector2i(1, 1))
	assert_eq(KeyMove.direction(false, false, true, false), Vector2i(-1, 1))
	assert_eq(KeyMove.direction(false, false, false, true), Vector2i(1, -1))


## Checked against the real projection: each key moves the drawn player straight up, down, left or right.
func test_keys_move_straight_on_screen() -> void:
	var keys := {"up": [true, false, false, false], "down": [false, true, false, false],
			"left": [false, false, true, false], "right": [false, false, false, true]}
	var want := {"up": Vector2(0, -1), "down": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}
	for k in keys:
		var b: Array = keys[k]
		var d := Vector2(KeyMove.direction(b[0], b[1], b[2], b[3]))
		var screen := IsoLayer.cell_to_local(d) - IsoLayer.cell_to_local(Vector2.ZERO)
		assert_true(screen.normalized().is_equal_approx(want[k]), "%s moves %s on screen" % [k, screen])


func test_two_keys_make_a_grid_axis() -> void:
	assert_eq(KeyMove.direction(true, false, true, false), Vector2i(-1, 0))
	assert_eq(KeyMove.direction(true, false, false, true), Vector2i(0, -1))
	assert_eq(KeyMove.direction(false, true, true, false), Vector2i(0, 1))
	assert_eq(KeyMove.direction(false, true, false, true), Vector2i(1, 0))


func test_opposite_keys_cancel() -> void:
	assert_eq(KeyMove.direction(true, true, false, false), Vector2i.ZERO)
	assert_eq(KeyMove.direction(false, false, true, true), Vector2i.ZERO)
	assert_eq(KeyMove.direction(true, true, true, false), Vector2i(-1, 1))
	assert_eq(KeyMove.direction(true, true, true, true), Vector2i.ZERO)


func test_held_target_is_ahead_of_the_player() -> void:
	assert_eq(KeyMove.held_target(Vector2(16, 16), Vector2i(1, 0)), Vector2(16 + KeyMove.LOOKAHEAD, 16))
	assert_eq(KeyMove.held_target(Vector2(20, 20), Vector2i(-1, -1)),
			Vector2(20 - KeyMove.LOOKAHEAD, 20 - KeyMove.LOOKAHEAD))


## Along +x from the spawn, the first non-walkable cell (water) stops the target in front of it, on the
## last walkable cell.
func test_held_target_stops_at_water() -> void:
	var wall := MapData.spawn_cell()
	while MapData.is_walkable(wall):
		wall += Vector2i(1, 0)
	var last := wall - Vector2i(1, 0)
	assert_eq(Protocol.cell_of(KeyMove.held_target(Vector2(last), Vector2i(1, 0))), last)
	assert_eq(Protocol.cell_of(KeyMove.held_target(Vector2(last - Vector2i(1, 0)), Vector2i(1, 0))), last)


func test_diagonal_moves_both_axes() -> void:
	var start := Vector2(20, 20)
	var p := Protocol.step_towards(start, KeyMove.held_target(start, Vector2i(-1, -1)), 0.25)
	assert_true(p.x < start.x and p.y < start.y, "moved to %s" % p)


## Holding a key must not stop and start, even when the client sees the
## server a few ticks late (snapshot interval plus network delay).
func test_holding_a_key_never_stalls() -> void:
	const DELAY_TICKS := 4
	var dt := 1.0 / Protocol.TICK_HZ
	var dir := Vector2i(1, 0)
	var pos := Vector2(18, 16)
	var target := Protocol.cell_of(pos)
	var history: Array[Vector2] = []
	for i in 20:
		history.append(pos)
		var seen: Vector2 = history[maxi(0, history.size() - 1 - DELAY_TICKS)]
		target = KeyMove.held_target(seen, dir)
		var before := pos
		pos = Protocol.step_towards(pos, target, dt)
		assert_true(pos.x > before.x, "stalled at tick %d, pos %s, target %s" % [i, pos, target])


## A walkable cell where stepping along dir would pass between a walkable cell and a non-walkable
## one (or two): the corner of a water cell. The three cells before it along dir are clear.
func _corner_cell(dir: Vector2i) -> Vector2i:
	for r in 200:
		for c in _ring(MapData.spawn_cell(), r):
			if MapData.is_walkable(c + dir) and not _clear_step(c, dir) and MapData.is_walkable(c - dir * 3) \
					and _clear_step(c - dir * 3, dir) and _clear_step(c - dir * 2, dir) and _clear_step(c - dir, dir):
				return c
	assert_true(false, "no water corner near the spawn")
	return Vector2i.ZERO

## The cells at Chebyshev distance r from center (the square ring), in a fixed order.
static func _ring(center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) == r:
				out.append(center + Vector2i(dx, dy))
	return out



## The step from c to c + dir stays on walkable cells, and so do the two cells beside a diagonal.
static func _clear_step(c: Vector2i, dir: Vector2i) -> bool:
	return MapData.is_walkable(c + dir) and MapData.is_walkable(c + Vector2i(dir.x, 0)) \
			and MapData.is_walkable(c + Vector2i(0, dir.y))


## A held screen direction (a grid diagonal) never slips between two cells through a water corner:
## the target stops before it.
func test_diagonal_stops_at_a_water_corner() -> void:
	for dir in [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var c := _corner_cell(dir)
		assert_eq(Protocol.cell_of(KeyMove.held_target(Vector2(c), dir)), c, "dir %s at %s" % [dir, c])
		assert_eq(Protocol.cell_of(KeyMove.held_target(Vector2(c - dir * 3), dir)), c,
				"from three cells back, dir %s" % [dir])


## Holding a screen direction, the server walks the diagonal on walkable cells, never through a
## corner, and stops on the last cell before it.
func test_server_walks_a_held_diagonal_up_to_the_corner() -> void:
	var dir := Vector2i(1, 1)
	var corner := _corner_cell(dir)
	var pos := Vector2(corner - dir * 3)
	var dt := 1.0 / Protocol.TICK_HZ
	var cell := Protocol.cell_of(pos)
	for i in 30:
		pos = Protocol.step_towards(pos, KeyMove.held_target(pos, dir), dt)
		var now := Protocol.cell_of(pos)
		assert_true(MapData.is_walkable(now), "on water at %s" % now)
		if now.x != cell.x and now.y != cell.y:
			assert_true(MapData.is_walkable(Vector2i(now.x, cell.y)) and MapData.is_walkable(Vector2i(cell.x, now.y)),
					"cut a corner from %s to %s" % [cell, now])
		cell = now
	assert_eq(Protocol.cell_of(pos), corner, "stops on the corner cell")


## Holding a screen key (a grid diagonal) keeps moving too.
func test_holding_a_screen_key_never_stalls() -> void:
	const DELAY_TICKS := 4
	var dt := 1.0 / Protocol.TICK_HZ
	var dir := KeyMove.direction(false, false, false, true)
	var pos := Vector2(20, 20)
	var history: Array[Vector2] = []
	for i in 20:
		history.append(pos)
		var seen: Vector2 = history[maxi(0, history.size() - 1 - DELAY_TICKS)]
		var before := pos
		pos = Protocol.step_towards(pos, KeyMove.held_target(seen, dir), dt)
		assert_true(pos.x > before.x and pos.y < before.y, "stalled at tick %d, pos %s" % [i, pos])


## Plays a held key for `ticks` server ticks: the client aims from the position it saw DELAY_TICKS
## ago, the server steps towards that target. Returns every position the server reached.
static func _hold(start: Vector2, dir: Vector2i, ticks: int) -> Array[Vector2]:
	const DELAY_TICKS := 4
	var dt := 1.0 / Protocol.TICK_HZ
	var pos := start
	var seen: Array[Vector2] = []
	var out: Array[Vector2] = []
	for i in ticks:
		seen.append(pos)
		var target := KeyMove.held_target(seen[maxi(0, seen.size() - 1 - DELAY_TICKS)], dir)
		pos = Protocol.step_towards(pos, target, dt)
		out.append(pos)
	return out


## On screen, how far p has drifted sideways from the straight line through start along dir, in pixels.
static func _sideways_px(start: Vector2, p: Vector2, dir: Vector2i) -> float:
	var along := (IsoLayer.cell_to_local(Vector2(dir)) - IsoLayer.cell_to_local(Vector2.ZERO)).normalized()
	var moved := IsoLayer.cell_to_local(p) - IsoLayer.cell_to_local(start)
	return absf(along.cross(moved))


## Holding a key from a position that is not a cell center (after a stop or a click) walks a straight
## line on screen: the camera follows the player, so any sideways zigzag shakes the whole view.
func test_held_key_walks_straight_from_an_off_center_start() -> void:
	var start := Vector2(MapData.spawn_cell()) + Vector2(0.4, -0.1)
	var keys := {"up": [true, false, false, false], "down": [false, true, false, false],
			"left": [false, false, true, false], "right": [false, false, false, true]}
	for k in keys:
		var b: Array = keys[k]
		var dir := KeyMove.direction(b[0], b[1], b[2], b[3])
		var path := _hold(start, dir, 45)
		assert_true(path[-1].distance_to(start) > 1.0, "%s barely moved: %s" % [k, path[-1]])
		var worst := 0.0
		for p in path:
			worst = maxf(worst, _sideways_px(start, p, dir))
		assert_true(worst < 0.05, "%s drifts %.2f px sideways" % [k, worst])


## Along +x from an off-center start, the held key still stops on the last walkable cell before the
## water, at its edge rather than a cell short.
func test_held_key_from_off_center_stops_at_the_water_edge() -> void:
	var row := MapData.spawn_cell()
	var wall := row
	while MapData.is_walkable(wall):
		wall += Vector2i(1, 0)
	var start := Vector2(row) + Vector2(0.3, 0.3)
	var path := _hold(start, Vector2i(1, 0), 15 * 30)
	for p in path:
		assert_true(MapData.is_walkable(Protocol.cell_of(p)), "on water at %s" % p)
	var end := path[-1]
	assert_eq(Protocol.cell_of(end), wall - Vector2i(1, 0))
	assert_true(end.x > wall.x - 0.65, "stopped short at %s, water at %s" % [end, wall])
	assert_almost(end.y, start.y)


## From off-center, a held diagonal stays on walkable cells and never slips through a water corner.
func test_held_diagonal_from_off_center_never_cuts_a_corner() -> void:
	for dir in [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var corner := _corner_cell(dir)
		for offset in [Vector2(0.2, -0.2), Vector2(-0.3, 0.1), Vector2(0.45, 0.0)]:
			var pos: Vector2 = Vector2(corner - dir * 3) + offset
			var cell := Protocol.cell_of(pos)
			for p in _hold(pos, dir, 45):
				var now := Protocol.cell_of(p)
				assert_true(MapData.is_walkable(now), "dir %s: on water at %s" % [dir, p])
				if now.x != cell.x and now.y != cell.y:
					assert_true(MapData.is_walkable(Vector2i(now.x, cell.y)) and MapData.is_walkable(Vector2i(cell.x, now.y)),
							"dir %s: cut a corner from %s to %s" % [dir, cell, now])
				cell = now


## Near the water the target is where the line meets the water's edge, whatever point of the line the
## player stands on, so it stays the same as the player walks up and the client does not resend it.
func test_target_at_the_water_does_not_move_while_walking_up() -> void:
	var wall := MapData.spawn_cell()
	while MapData.is_walkable(wall):
		wall += Vector2i(1, 0)
	var first := KeyMove.held_target(Vector2(wall) + Vector2(-2.93, 0.2), Vector2i(1, 0))
	for back in [2.71, 2.03, 1.37, 0.88, 0.62]:
		var t := KeyMove.held_target(Vector2(wall) + Vector2(-back, 0.2), Vector2i(1, 0))
		assert_true(t.is_equal_approx(first), "from %.2f back: %s, before %s" % [back, t, first])
