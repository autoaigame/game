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


## The walk rows (WALK_FIRST_ROW onwards) play one cycle, two steps, every WALK_CYCLE_CELLS walked.
func test_walk_cycle_plays_every_frame_by_distance() -> void:
	var per_frame := WalkAnim.WALK_CYCLE_CELLS / WalkAnim.WALK_FRAMES
	for i in WalkAnim.WALK_FRAMES:
		assert_eq(WalkAnim.walk_row(per_frame * (i + 0.5)), WalkAnim.WALK_FIRST_ROW + i, "frame %d" % i)
	assert_eq(WalkAnim.walk_row(0.0), WalkAnim.WALK_FIRST_ROW)
	assert_eq(WalkAnim.walk_row(WalkAnim.WALK_CYCLE_CELLS), WalkAnim.WALK_FIRST_ROW, "the cycle starts over")


## Standing still, the idle rows (0..IDLE_FRAMES-1) play in time, looping.
func test_idle_plays_in_time() -> void:
	var per_frame := 1.0 / WalkAnim.IDLE_FPS
	for i in WalkAnim.IDLE_FRAMES:
		assert_eq(WalkAnim.idle_row(per_frame * (i + 0.5)), i, "frame %d" % i)
	assert_eq(WalkAnim.idle_row(per_frame * WalkAnim.IDLE_FRAMES), 0, "loops")


func test_sheet_rows_are_idle_then_walk() -> void:
	assert_eq(WalkAnim.IDLE_FRAMES, 4)
	assert_eq(WalkAnim.WALK_FRAMES, 6)
	assert_eq(WalkAnim.WALK_FIRST_ROW, WalkAnim.IDLE_FRAMES)
	assert_eq(WalkAnim.SHEET_ROWS, WalkAnim.IDLE_FRAMES + WalkAnim.WALK_FRAMES)


## The 8-column sheet is in FACINGS order: each facing draws its own column.
func test_eight_column_sheet() -> void:
	assert_eq(WalkAnim.SHEET_COLUMNS, 8)
	for f in 8:
		assert_eq(WalkAnim.sheet_column(f), f)


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


## Draws a player walking in a straight line for walk_s seconds, then standing: the server ticks at
## Protocol.TICK_HZ, each snapshot arrives 30 ms late give or take jitter_s (seeded), frames at 60 fps.
## Returns one entry per frame: [time in s, sheet frame, drawn position in cells].
static func _draw_walk(jitter_s: float, walk_s: float, total_s: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var dir := Vector2(1, -1).normalized()
	var tick := 1.0 / Protocol.TICK_HZ
	var arrivals := []
	var t := 0.0
	while t < total_s:
		var p := dir * Protocol.SPEED_CELLS_PER_S * minf(t, walk_s)
		arrivals.append([t + 0.03 + rng.randf_range(-jitter_s, jitter_s), p])
		t += tick
	arrivals.sort_custom(func(a, b): return a[0] < b[0])
	var w := {"server": Vector2.ZERO, "shown": Vector2.ZERO, "walked": 0.0, "facing": -1, "still": 0.0}
	var frames := []
	var next := 0
	for f in int(total_s * 60.0):
		var now := f / 60.0
		while next < arrivals.size() and arrivals[next][0] <= now:
			w["server"] = arrivals[next][1]
			next += 1
		var fc := WalkAnim.animate(w, 1.0 / 60.0)
		frames.append([now, fc, w["shown"]])
	return frames


## While walking steadily, every frame shows a walk frame: the drawn player catching up with a snapshot
## and waiting for the next must not flash the standing pose.
func test_walking_never_flashes_the_idle_pose() -> void:
	for jitter in [0.0, 0.015, 0.03]:
		for fr in _draw_walk(jitter, 2.0, 3.0):
			if fr[0] > 0.15 and fr[0] < 2.0:
				assert_true(fr[1].y >= WalkAnim.WALK_FIRST_ROW, "jitter %s: idle row %d at %.3f s" % [jitter, fr[1].y, fr[0]])


## Once the player has stopped, it stands (idle rows) instead of walking on the spot.
func test_stops_walking_after_stopping() -> void:
	for fr in _draw_walk(0.015, 1.0, 2.0):
		if fr[0] > 1.5:
			assert_true(fr[1].y < WalkAnim.IDLE_FRAMES, "walk row %d at %.3f s" % [fr[1].y, fr[0]])


## While walking steadily, the drawn player glides at an even speed: no frame stands still (a 15 Hz
## stop-and-go reads as a stutter), none rushes ahead, and it stays close behind the server.
func test_walking_speed_on_screen_is_even() -> void:
	var nominal := Protocol.SPEED_CELLS_PER_S / 60.0
	for jitter in [0.0, 0.015, 0.03]:
		var frames := _draw_walk(jitter, 4.0, 4.0)
		for i in range(1, frames.size()):
			if frames[i][0] < 0.5:
				continue
			var speed: float = (frames[i][2] - frames[i - 1][2]).length() / nominal
			assert_true(speed > 0.6 and speed < 1.3, "jitter %s: %.2fx the walking speed at %.3f s" % [jitter, speed, frames[i][0]])
			var real: Vector2 = Vector2(1, -1).normalized() * Protocol.SPEED_CELLS_PER_S * frames[i][0]
			var behind: float = (real - frames[i][2]).length()
			assert_true(behind < 0.6, "jitter %s: %.2f cells behind at %.3f s" % [jitter, behind, frames[i][0]])
