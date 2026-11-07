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


## Row 0 is standing; rows 1..WALK_FRAMES are one walk cycle: two steps (left foot, then right foot).
func test_walk_cycle_plays_every_frame_over_two_steps() -> void:
	var per_frame := WalkAnim.STRIDE_CELLS * 2.0 / WalkAnim.WALK_FRAMES
	for i in WalkAnim.WALK_FRAMES:
		assert_eq(WalkAnim.walk_row(per_frame * (i + 0.5)), 1 + i, "frame %d" % i)
	assert_eq(WalkAnim.walk_row(0.0), 1)
	assert_eq(WalkAnim.walk_row(WalkAnim.STRIDE_CELLS * 2.0), 1, "the cycle starts over")


func test_walk_cycle_has_more_than_two_frames() -> void:
	assert_true(WalkAnim.WALK_FRAMES >= 4, "WALK_FRAMES = %d" % WalkAnim.WALK_FRAMES)


func test_bob_only_while_walking() -> void:
	assert_eq(WalkAnim.bob(WalkAnim.STRIDE_CELLS * 0.5, false), 0.0)
	assert_almost(WalkAnim.bob(0.0, true), 0.0, 0.001)
	assert_almost(WalkAnim.bob(WalkAnim.STRIDE_CELLS * 0.5, true), -WalkAnim.BOB_PX, 0.001)
	assert_almost(WalkAnim.bob(WalkAnim.STRIDE_CELLS, true), 0.0, 0.001)


## Screen movement of the held keys, through the real projection.
func _key_screen_delta(up: bool, down: bool, left: bool, right: bool) -> Vector2:
	var d := Vector2(KeyMove.direction(up, down, left, right))
	return IsoLayer.cell_to_local(d) - IsoLayer.cell_to_local(Vector2.ZERO)


## Each key or pair of keys faces its own screen direction, in the PixelLab order.
func test_facing_eight_screen_directions() -> void:
	var cases := [
		[[false, true, false, false], "south"], [[false, true, false, true], "south-east"],
		[[false, false, false, true], "east"], [[true, false, false, true], "north-east"],
		[[true, false, false, false], "north"], [[true, false, true, false], "north-west"],
		[[false, false, true, false], "west"], [[false, true, true, false], "south-west"],
	]
	for c in cases:
		var k: Array = c[0]
		var f := WalkAnim.facing(_key_screen_delta(k[0], k[1], k[2], k[3]))
		assert_eq(WalkAnim.FACINGS[f], c[1], "keys %s" % [k])


func test_facing_names_follow_pixellab() -> void:
	assert_eq(WalkAnim.FACINGS, ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"])


## Drawn positions land a hair either side of the held direction: the facing never flickers, whatever
## it was before (a neighbouring facing switches at once).
func test_facing_steady_along_every_key_direction() -> void:
	var wobbles := [Vector2.ZERO, Vector2(0.01, 0), Vector2(0, -0.01), Vector2(-0.01, 0), Vector2(0, 0.01)]
	for k in [[true, false, false, false], [false, true, false, false], [false, false, true, false],
			[false, false, false, true], [true, false, true, false], [true, false, false, true],
			[false, true, true, false], [false, true, false, true]]:
		var delta := _key_screen_delta(k[0], k[1], k[2], k[3]) * 0.05
		var want := WalkAnim.facing(delta)
		for prev in [-1, want, (want + 1) % 8, (want + 7) % 8]:
			var f: int = prev
			for wobble in wobbles:
				f = WalkAnim.facing(delta + wobble, f)
				assert_eq(f, want, "keys %s, before %d, wobble %s" % [k, prev, wobble])


## Screen delta at angle deg, measured on the 2:1 view as if it were flat (grid axes at 45 degrees).
static func _at(deg: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)) / 2.0)


## Past a sector edge (22.5 degrees from east), the facing holds a few degrees more, then turns.
func test_facing_hysteresis() -> void:
	var east := WalkAnim.FACINGS.find("east")
	var north_east := WalkAnim.FACINGS.find("north-east")
	assert_eq(WalkAnim.facing(_at(27.5)), north_east, "fresh start: nearest sector")
	assert_eq(WalkAnim.facing(_at(27.5), east), east, "holds just past the edge")
	assert_eq(WalkAnim.facing(_at(42.5), east), north_east, "turns well past it")
	assert_eq(WalkAnim.facing(_at(17.5), north_east), north_east, "holds on the way back too")
	assert_eq(WalkAnim.facing(_at(2.5), north_east), east, "and turns back well past it")


func test_facing_keeps_the_previous_one_when_still() -> void:
	assert_eq(WalkAnim.facing(Vector2.ZERO, 5), 5)
	assert_eq(WalkAnim.facing(Vector2.ZERO), 0, "south before any move")


## The sheet in assets/player.png has fewer columns than facings: each facing maps to one it has.
func test_sheet_columns_match_player_png() -> void:
	var tex: Texture2D = load("res://assets/player.png")
	assert_eq(WalkAnim.SHEET_COLUMNS, tex.get_width() / WalkAnim.FRAME_SIZE.x)
	assert_eq(WalkAnim.FACING_COLUMN.size(), WalkAnim.FACINGS.size())
	for f in WalkAnim.FACINGS.size():
		var col := WalkAnim.sheet_column(f)
		assert_true(col >= 0 and col < WalkAnim.SHEET_COLUMNS, "%s -> column %d" % [WalkAnim.FACINGS[f], col])


## The 4-column sheet: 0 down, 1 left, 2 right, 3 up; diagonals show the back going up, the front going down.
func test_four_column_sheet_mapping() -> void:
	var want := {"south": 0, "south-east": 0, "east": 2, "north-east": 3, "north": 3, "north-west": 3,
			"west": 1, "south-west": 0}
	for name in want:
		assert_eq(WalkAnim.sheet_column(WalkAnim.FACINGS.find(name)), want[name], name)


## The sprite stands on the player's position: its feet (FOOT_PX above the frame's bottom) on the
## cell, horizontally centred, whatever the frame size.
func test_sprite_feet_on_the_position() -> void:
	var o := WalkAnim.sprite_offset()
	assert_eq(o.x, -WalkAnim.FRAME_SIZE.x / 2.0)
	assert_eq(o.y + WalkAnim.FRAME_SIZE.y - WalkAnim.FOOT_PX, 0.0)


## The name sits just above the head, centred.
func test_name_above_the_head() -> void:
	var r := WalkAnim.name_rect()
	assert_almost(r.position.x + r.size.x / 2.0, 0.0, 0.01)
	assert_true(r.end.y <= -WalkAnim.HEAD_PX, "name bottom %f, head %d" % [r.end.y, WalkAnim.HEAD_PX])
	assert_true(r.end.y >= -WalkAnim.HEAD_PX - 24, "name too far above the head")
