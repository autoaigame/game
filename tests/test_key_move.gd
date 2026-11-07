extends TestCase


func test_single_keys() -> void:
	assert_eq(KeyMove.direction(true, false, false, false), Vector2i(0, -1))
	assert_eq(KeyMove.direction(false, true, false, false), Vector2i(0, 1))
	assert_eq(KeyMove.direction(false, false, true, false), Vector2i(-1, 0))
	assert_eq(KeyMove.direction(false, false, false, true), Vector2i(1, 0))


func test_two_keys_make_a_diagonal() -> void:
	assert_eq(KeyMove.direction(true, false, true, false), Vector2i(-1, -1))
	assert_eq(KeyMove.direction(true, false, false, true), Vector2i(1, -1))
	assert_eq(KeyMove.direction(false, true, true, false), Vector2i(-1, 1))
	assert_eq(KeyMove.direction(false, true, false, true), Vector2i(1, 1))


func test_opposite_keys_cancel() -> void:
	assert_eq(KeyMove.direction(true, true, false, false), Vector2i.ZERO)
	assert_eq(KeyMove.direction(true, true, true, false), Vector2i(-1, 0))


func test_held_target_is_ahead_of_the_player() -> void:
	assert_eq(KeyMove.held_target(Vector2(16, 16), Vector2i(1, 0)), Vector2i(16 + KeyMove.LOOKAHEAD, 16))
	assert_eq(KeyMove.held_target(Vector2(20, 20), Vector2i(-1, -1)),
			Vector2i(20 - KeyMove.LOOKAHEAD, 20 - KeyMove.LOOKAHEAD))


## Along +x from the spawn, the first non-walkable cell (water) stops the target in front of it.
func test_held_target_stops_at_water() -> void:
	var wall := MapData.spawn_cell()
	while MapData.is_walkable(wall):
		wall += Vector2i(1, 0)
	var last := wall - Vector2i(1, 0)
	assert_eq(KeyMove.held_target(Vector2(last), Vector2i(1, 0)), last)
	assert_eq(KeyMove.held_target(Vector2(last - Vector2i(1, 0)), Vector2i(1, 0)), last)


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
