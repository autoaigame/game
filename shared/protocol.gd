## Constants and rules shared by client and server.
class_name Protocol
extends RefCounted

const DEFAULT_PORT := 9000
const TICK_HZ := 15
const SPEED_CELLS_PER_S := 4.0
const NAME_MAX_LEN := 16
## A player gathers from a bush at most this far from its cell, in cells.
const GATHER_REACH := 1.6

static var _name_re: RegEx


## Returns "" if the name is valid, otherwise a message for the player.
static func validate_name(player_name: String) -> String:
	if _name_re == null:
		_name_re = RegEx.create_from_string("^[A-Za-z0-9_-]+$")
	if player_name.is_empty():
		return "Name is empty."
	if player_name.length() > NAME_MAX_LEN:
		return "Name is longer than %d characters." % NAME_MAX_LEN
	if _name_re.search(player_name) == null:
		return "Use only letters, digits, _ and -."
	return ""


## Cell under a position (positions are in cell units).
static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))


## Moves pos towards target (any point, not only a cell center) at SPEED_CELLS_PER_S for dt seconds,
## in small sub-steps, stopping at the last position whose cell is walkable. A sub-step that changes cell diagonally also
## needs both cells beside it walkable, so nobody slips through the corner of a water cell. Never
## overshoots the target.
static func step_towards(pos: Vector2, target: Vector2, dt: float) -> Vector2:
	const SUBSTEP := 0.1
	var goal := target
	var budget := SPEED_CELLS_PER_S * dt
	while budget > 0.0:
		var to_goal := goal - pos
		var dist := to_goal.length()
		if dist <= 0.0001:
			return goal
		var step := minf(minf(budget, SUBSTEP), dist)
		var next := pos + to_goal / dist * step
		if not can_enter(cell_of(pos), cell_of(next)):
			return pos
		pos = goal if is_equal_approx(step, dist) else next
		budget -= step
	return pos


## Whether a sub-step may go from cell `from` into cell `to` (equal or neighbours).
static func can_enter(from: Vector2i, to: Vector2i) -> bool:
	if not MapData.is_walkable(to):
		return false
	if from.x != to.x and from.y != to.y:
		return MapData.is_walkable(Vector2i(to.x, from.y)) and MapData.is_walkable(Vector2i(from.x, to.y))
	return true
