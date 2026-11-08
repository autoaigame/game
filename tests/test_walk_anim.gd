extends TestCase

## The client draws players between server snapshots (15 per second). Display only: positions still come
## from the server.


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


## The name sits just above the head, centred.
func test_name_above_the_head() -> void:
	var r := WalkAnim.name_rect()
	assert_almost(r.position.x + r.size.x / 2.0, 0.0, 0.01)
	assert_true(r.end.y <= -WalkAnim.HEAD_PX, "name bottom %f, head %d" % [r.end.y, WalkAnim.HEAD_PX])
	assert_true(r.end.y >= -WalkAnim.HEAD_PX - 24, "name too far above the head")


## Draws a player walking in a straight line for walk_s seconds, then standing: the server ticks at
## Protocol.TICK_HZ, each snapshot arrives 30 ms late give or take jitter_s (seeded), frames at 60 fps.
## Returns one entry per frame: [time in s, drawn position in cells]. `speed`: cells/s on the server; the
## drawn player follows its snapshots as client/world_view.gd does (WalkAnim.snapshot, WalkAnim.advance).
static func _draw_walk(jitter_s: float, walk_s: float, total_s: float, speed := Protocol.SPEED_CELLS_PER_S) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var dir := Vector2(1, -1).normalized()
	var tick := 1.0 / Protocol.TICK_HZ
	var arrivals := []
	var t := 0.0
	while t < total_s:
		var p := dir * speed * minf(t, walk_s)
		arrivals.append([t + 0.03 + rng.randf_range(-jitter_s, jitter_s), p])
		t += tick
	arrivals.sort_custom(func(a, b): return a[0] < b[0])
	var w := WalkAnim.walker(Vector2.ZERO)
	var frames := []
	var next := 0
	for f in int(total_s * 60.0):
		var now := f / 60.0
		while next < arrivals.size() and arrivals[next][0] <= now:
			WalkAnim.snapshot(w, arrivals[next][1])
			next += 1
		frames.append([now, WalkAnim.advance(w, 1.0 / 60.0)])
	return frames


## While walking steadily, the drawn player glides at an even speed: no frame stands still (a 15 Hz
## stop-and-go reads as a stutter), none rushes ahead, and it stays close behind the server.
func test_walking_speed_on_screen_is_even() -> void:
	var nominal := Protocol.SPEED_CELLS_PER_S / 60.0
	for jitter in [0.0, 0.015, 0.03]:
		var frames := _draw_walk(jitter, 4.0, 4.0)
		for i in range(1, frames.size()):
			if frames[i][0] < 0.5:
				continue
			var speed: float = (frames[i][1] - frames[i - 1][1]).length() / nominal
			assert_true(speed > 0.6 and speed < 1.3, "jitter %s: %.2fx the walking speed at %.3f s" % [jitter, speed, frames[i][0]])
			var real: Vector2 = Vector2(1, -1).normalized() * Protocol.SPEED_CELLS_PER_S * frames[i][0]
			var behind: float = (real - frames[i][1]).length()
			assert_true(behind < 0.6, "jitter %s: %.2f cells behind at %.3f s" % [jitter, behind, frames[i][0]])


## A sprinter (Shift held: Protocol.SPRINT_FACTOR times the walk) is drawn as evenly, close behind the
## server, and never falls so far behind that it jumps.
func test_sprinting_speed_on_screen_is_even() -> void:
	var speed := Protocol.SPEED_CELLS_PER_S * Protocol.SPRINT_FACTOR
	var nominal := speed / 60.0
	for jitter in [0.0, 0.015, 0.03]:
		var frames := _draw_walk(jitter, 4.0, 4.0, speed)
		for i in range(1, frames.size()):
			if frames[i][0] < 0.5:
				continue
			var step: float = (frames[i][1] - frames[i - 1][1]).length() / nominal
			assert_true(step > 0.6 and step < 1.3, "jitter %s: %.2fx the sprint speed at %.3f s" % [jitter, step, frames[i][0]])
			var real: Vector2 = Vector2(1, -1).normalized() * speed * frames[i][0]
			var behind: float = (real - frames[i][1]).length()
			assert_true(behind < 0.6 * Protocol.SPRINT_FACTOR, "jitter %s: %.2f cells behind at %.3f s" % [jitter, behind, frames[i][0]])
