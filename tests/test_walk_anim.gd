extends TestCase

## The client draws players between server snapshots (15 per second) and animates
## their walk by distance. Display only: positions still come from the server.


func test_follow_moves_at_catch_up_speed() -> void:
	var dt := 0.1
	var p := WalkAnim.follow(Vector2(10, 10), Vector2(12, 10), dt)
	assert_almost(p.x, 10.0 + Protocol.SPEED_CELLS_PER_S * WalkAnim.CATCH_UP * dt, 0.001)
	assert_almost(p.y, 10.0, 0.001)


func test_follow_draws_positions_between_snapshots() -> void:
	# One snapshot apart at full speed: several frames show in-between positions.
	var server := Vector2(10, 10) + Vector2(Protocol.SPEED_CELLS_PER_S / Protocol.TICK_HZ, 0)
	var shown := Vector2(10, 10)
	var xs := []
	for i in 4:
		shown = WalkAnim.follow(shown, server, 1.0 / 60.0)
		xs.append(shown.x)
	assert_true(xs[0] > 10.0 and xs[0] < server.x, "first frame in between: " + str(xs))
	assert_true(xs[1] > xs[0], "keeps moving: " + str(xs))


func test_follow_never_overshoots() -> void:
	assert_eq(WalkAnim.follow(Vector2(10, 10), Vector2(10.2, 10), 1.0), Vector2(10.2, 10))


func test_follow_snaps_on_a_jump() -> void:
	# Spawn, reconnect or a lost stretch of snapshots: no slow slide across the map.
	var far := Vector2(10, 10) + Vector2(WalkAnim.SNAP_CELLS + 0.5, 0)
	assert_eq(WalkAnim.follow(Vector2(10, 10), far, 1.0 / 60.0), far)


func test_follow_still_when_there() -> void:
	assert_eq(WalkAnim.follow(Vector2(3, 4), Vector2(3, 4), 1.0 / 60.0), Vector2(3, 4))


func test_walk_frame_changes_each_stride() -> void:
	assert_eq(WalkAnim.walk_row(0.0), 0)
	assert_eq(WalkAnim.walk_row(WalkAnim.STRIDE_CELLS * 0.99), 0)
	assert_eq(WalkAnim.walk_row(WalkAnim.STRIDE_CELLS), 1)
	assert_eq(WalkAnim.walk_row(WalkAnim.STRIDE_CELLS * 2.0), 0)


func test_bob_only_while_walking() -> void:
	assert_eq(WalkAnim.bob(WalkAnim.STRIDE_CELLS * 0.5, false), 0.0)
	assert_almost(WalkAnim.bob(0.0, true), 0.0, 0.001)
	assert_almost(WalkAnim.bob(WalkAnim.STRIDE_CELLS * 0.5, true), -WalkAnim.BOB_PX, 0.001)
	assert_almost(WalkAnim.bob(WalkAnim.STRIDE_CELLS, true), 0.0, 0.001)


func test_facing_steady_along_a_grid_axis() -> void:
	# One key held (D) moves exactly diagonally on screen; drawn positions land a hair either side.
	var axis := IsoLayer.cell_to_local(Vector2(1, 0)) - IsoLayer.cell_to_local(Vector2(0, 0))
	for wobble in [Vector2.ZERO, Vector2(0.01, 0), Vector2(0, -0.01), Vector2(-0.01, 0)]:
		assert_eq(WalkAnim.facing(axis + wobble), 0, "wobble %s" % [wobble])


func test_facing_four_directions() -> void:
	assert_eq(WalkAnim.facing(Vector2(0, 40)), 0)  # down
	assert_eq(WalkAnim.facing(Vector2(-100, 0)), 1)  # left
	assert_eq(WalkAnim.facing(Vector2(100, 0)), 2)  # right
	assert_eq(WalkAnim.facing(Vector2(0, -40)), 3)  # up
	assert_eq(WalkAnim.facing(Vector2(-64, -32)), 3, "A key: up-left on screen shows the back")
