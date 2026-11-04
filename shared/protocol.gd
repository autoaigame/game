## Constants and rules shared by client and server.
class_name Protocol
extends RefCounted

const DEFAULT_PORT := 9000
const TICK_HZ := 15
const SPEED_CELLS_PER_S := 4.0
const NAME_MAX_LEN := 16

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
