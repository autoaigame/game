extends TestCase

## How the drawn player goes from standing to walking and back, and how it turns. Display only: the
## server still decides every position (docs/invariants.md, rule 1).

const DT := 1.0 / 60.0


## Drives one player through a list of [seconds, direction in cells per second] legs, the server
## position moving at that speed (no network delay), drawn at 60 fps. Returns one entry per frame:
## [sheet frame, facing shown].
static func _play(legs: Array, w: Dictionary = {}) -> Array:
	if w.is_empty():
		w = WalkAnim.new_state(Vector2(10, 10))
	var out := []
	for leg in legs:
		var v: Vector2 = leg[1]
		for f in int(round(leg[0] / DT)):
			w["server"] += v * DT
			var fc := WalkAnim.animate(w, DT)
			out.append([fc, w["facing"]])
	return out


static func _is_walk(fc: Vector2i) -> bool:
	return fc.y >= WalkAnim.WALK_FIRST_ROW


static func _walk_frame(fc: Vector2i) -> int:
	return fc.y - WalkAnim.WALK_FIRST_ROW


static func _east() -> Vector2:
	return Vector2(1, -1).normalized() * Protocol.SPEED_CELLS_PER_S  # the D key: screen east


static func _north() -> Vector2:
	return Vector2(-1, -1).normalized() * Protocol.SPEED_CELLS_PER_S  # the W key: screen north


## A new player stands (idle rows) at once instead of walking on the spot.
func test_a_new_player_stands() -> void:
	var w := WalkAnim.new_state(Vector2(3, 4))
	assert_false(_is_walk(WalkAnim.animate(w, DT)))
	assert_eq(w["shown"], Vector2(3, 4))


## However far the last walk went, a new walk starts from the feet-together pose, then steps on.
func test_walk_starts_on_a_rest_frame() -> void:
	for walk_s in [0.1, 0.17, 0.23, 0.3, 0.41]:
		var w := WalkAnim.new_state(Vector2(10, 10))
		_play([[walk_s, _east()], [1.0, Vector2.ZERO]], w)
		var frames := _play([[0.5, _east()]], w)
		var first := -1
		for fr in frames:
			if _is_walk(fr[0]):
				first = _walk_frame(fr[0])
				break
		assert_true(first in WalkAnim.REST_FRAMES, "after %s s: first walk frame %d" % [walk_s, first])


## On stopping, the step in progress finishes (walk frames keep going forwards) and the idle rows
## only come after a feet-together frame: never straight from a stride.
func test_stop_finishes_the_step_before_standing() -> void:
	var cases := []
	for walk_s in [0.1, 0.17, 0.23, 0.3, 0.41, 0.5]:
		cases.append([walk_s, _east()])
	for walk_s in [0.05, 0.08, 0.11, 0.14, 0.2, 0.29]:
		cases.append([walk_s, Vector2(1, 0) * Protocol.SPEED_CELLS_PER_S])  # north-east: the longest cycle
	for c in cases:
		var walk_s: float = c[0]
		var frames := _play([[walk_s, c[1]], [1.0, Vector2.ZERO]])
		var last_walk := -1
		var idle_at := -1
		for i in frames.size():
			var fc: Vector2i = frames[i][0]
			if _is_walk(fc):
				assert_eq(idle_at, -1, "after %s s: walked again after standing" % walk_s)
				if last_walk >= 0:
					var step := posmod(_walk_frame(fc) - last_walk, WalkAnim.WALK_FRAMES)
					assert_true(step <= 1, "after %s s: frame %d -> %d" % [walk_s, last_walk, _walk_frame(fc)])
				last_walk = _walk_frame(fc)
			elif idle_at == -1 and last_walk >= 0:
				idle_at = i
				assert_true(last_walk in WalkAnim.REST_FRAMES, "after %s s: idle after stride frame %d" % [walk_s, last_walk])
				assert_eq(fc.y, 0, "idle starts on its first frame")
		assert_true(idle_at > 0, "after %s s: never stood" % walk_s)
		var stopped := int(round(walk_s / DT))
		assert_true((idle_at - stopped) * DT <= WalkAnim.STOP_GRACE_S + 0.2,
				"after %s s: stood %.2f s after stopping" % [walk_s, (idle_at - stopped) * DT])


## Turning keeps the walk going: no frame is skipped or replayed.
func test_turning_keeps_the_walk_phase() -> void:
	var frames := _play([[0.3, _east()], [0.3, _north()]])
	for i in range(10, frames.size()):
		assert_true(_is_walk(frames[i][0]), "frame %d stood" % i)
		var step := posmod(_walk_frame(frames[i][0]) - _walk_frame(frames[i - 1][0]), WalkAnim.WALK_FRAMES)
		assert_true(step <= 1, "frame %d: %d -> %d" % [i, _walk_frame(frames[i - 1][0]), _walk_frame(frames[i][0])])


## A half-turn goes through the facings in between, one sector at a time, past the side facing the
## camera when east turns to west, and ends on the new direction.
func test_half_turn_goes_through_the_facings_in_between() -> void:
	var frames := _play([[0.4, _east()], [0.5, -_east()]])
	var seen := []
	for i in range(1, frames.size()):
		var a: int = frames[i - 1][1]
		var b: int = frames[i][1]
		var d := posmod(b - a, 8)
		assert_true(d == 0 or d == 1 or d == 7, "facing jumped %s -> %s" % [WalkAnim.FACINGS[a], WalkAnim.FACINGS[b]])
		if b != a:
			seen.append(WalkAnim.FACINGS[b])
	assert_eq(seen, ["south-east", "south", "south-west", "west"])


## The half-turn is quick: the new facing is reached within TURN_STEP_S per sector.
func test_half_turn_takes_turn_step_per_sector() -> void:
	var frames := _play([[0.4, _east()], [0.5, -_east()]])
	var turned := -1
	for i in range(int(round(0.4 / DT)), frames.size()):
		if WalkAnim.FACINGS[frames[i][1]] == "west":
			turned = i - int(round(0.4 / DT))
			break
	assert_true(turned >= 0, "never faced west")
	assert_true(turned * DT <= 3 * WalkAnim.TURN_STEP_S + 2 * DT, "took %.3f s" % (turned * DT))
	assert_true(turned * DT >= 2 * WalkAnim.TURN_STEP_S, "too fast to see: %.3f s" % (turned * DT))


## A one-sector turn shows at once: the facing shown is never one sector off the heading.
func test_a_one_sector_turn_is_immediate() -> void:
	var ne := (_east() + _north()).normalized() * Protocol.SPEED_CELLS_PER_S
	var w := WalkAnim.new_state(Vector2(10, 10))
	var seen := {}
	for leg in [[0.3, _east()], [0.3, ne], [0.3, _north()]]:
		for f in int(round(leg[0] / DT)):
			w["server"] += leg[1] * DT
			WalkAnim.animate(w, DT)
			assert_eq(w["facing"], w["heading"])
			seen[WalkAnim.FACINGS[w["facing"]]] = true
	assert_eq(seen.keys(), ["east", "north-east", "north"])


## Walking one cycle length of a facing plays exactly one cycle: the stride matches the ground.
func test_one_cycle_per_cycle_length_of_each_facing() -> void:
	for f in WalkAnim.FACINGS.size():
		var deg := -90.0 + 45.0 * f
		var screen := Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)) / 2.0)
		# cell direction whose screen movement is that facing
		var cell := Vector2(screen.x / 48.0 + screen.y / 24.0, screen.y / 24.0 - screen.x / 48.0).normalized()
		var w := WalkAnim.new_state(Vector2(10, 10))
		var cycle: float = WalkAnim.CYCLE_CELLS[f]
		var steps := 200
		for i in steps:
			w["server"] = Vector2(10, 10) + cell * cycle * (i + 1) / steps
			w["shown"] = w["server"] - cell * cycle / steps
			WalkAnim.animate(w, DT)
		assert_eq(WalkAnim.FACINGS[w["facing"]], WalkAnim.FACINGS[f])
		var off: float = fposmod(w["phase"] + 0.5, 1.0) - 0.5
		assert_almost(off, 0.0, 0.01, "%s: phase %f after one cycle" % [WalkAnim.FACINGS[f], w["phase"]])


## The cycle lengths come from the stride measured on assets/player.png (two steps per cycle), at
## most 10 % longer so the feet barely slide, and are the same for mirrored facings.
func test_cycle_lengths_follow_the_measured_stride() -> void:
	var measured := [0.79, 1.35, 1.04, 1.17, 0.71, 1.26, 0.99, 1.24]  # S SE E NE N NW W SW, see ASSETS.toml
	for f in 8:
		var c: float = WalkAnim.CYCLE_CELLS[f]
		var m: float = measured[f]
		assert_true(c >= m * 0.95 and c <= m * 1.25, "%s: %.2f for a measured %.2f" % [WalkAnim.FACINGS[f], c, m])
	for pair in [[1, 7], [2, 6], [3, 5], [1, 3], [0, 4]]:
		assert_almost(WalkAnim.CYCLE_CELLS[pair[0]], WalkAnim.CYCLE_CELLS[pair[1]], 0.001)


## Every stop starts the idle rows from their first frame, the second one too.
func test_each_stop_starts_the_idle_from_its_first_frame() -> void:
	var w := WalkAnim.new_state(Vector2(10, 10))
	for n in 3:
		var frames := _play([[0.3 + 0.07 * n, _east()], [0.9 + 0.11 * n, Vector2.ZERO]], w)
		var first_idle := -1
		for fr in frames:
			if not _is_walk(fr[0]):
				first_idle = fr[0].y
				break
		assert_eq(first_idle, 0, "stop %d" % n)


## Even once the stop is sure, the walk goes on until a feet-together frame (a long cycle or a slow
## walk can take longer than STOP_GRACE_S to finish its step).
func test_never_stands_mid_stride() -> void:
	var w := WalkAnim.new_state(Vector2(10, 10))
	w["heading"] = 3
	w["facing"] = 3
	w["phase"] = 1.01 / WalkAnim.WALK_FRAMES  # frame 1: one foot forward
	w["still"] = WalkAnim.STOP_GRACE_S
	var fc := WalkAnim.animate(w, DT)
	assert_eq(fc.y, WalkAnim.WALK_FIRST_ROW + 1)
	for i in 20:
		fc = WalkAnim.animate(w, DT)
	assert_false(_is_walk(fc), "stands once the step is done")
