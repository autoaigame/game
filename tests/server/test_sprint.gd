extends TestCase

## Sprint (server/server.gd on_sprint): a player who holds Shift asks to sprint; the server moves them at
## Protocol.SPRINT_FACTOR times the walking speed, never faster, whatever the client sends.

const SERVER_SCRIPT := "res://server/server.gd"
const HUNGER := preload("res://server/hunger.gd")


func _server_with_walker() -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = server._new_player("ann", Vector2i(16, 16), {})
	server.on_move_to(1, Vector2(26, 16))
	return server


func _walked(server: Node, dt: float) -> float:
	var before: Vector2 = server._players[1]["pos"]
	server._move_players(dt)
	return before.distance_to(server._players[1]["pos"])


func test_sprint_moves_faster_and_walking_again_slows_down() -> void:
	var server := _server_with_walker()
	assert_almost(_walked(server, 0.25), Protocol.SPEED_CELLS_PER_S * 0.25, 0.0001, "walks before sprinting")
	server.on_sprint(1, true)
	assert_almost(_walked(server, 0.25), Protocol.SPEED_CELLS_PER_S * Protocol.SPRINT_FACTOR * 0.25, 0.0001,
			"sprints")
	server.on_sprint(1, false)
	assert_almost(_walked(server, 0.25), Protocol.SPEED_CELLS_PER_S * 0.25, 0.0001, "walks again")
	server.free()


## Asking again does not stack: one tick at most SPEED_CELLS_PER_S * SPRINT_FACTOR * dt.
func test_sprint_never_goes_past_its_speed() -> void:
	var server := _server_with_walker()
	for i in 10:
		server.on_sprint(1, true)
	var dt := 1.0 / Protocol.TICK_HZ
	for i in 6:
		assert_true(_walked(server, dt) <= Protocol.SPEED_CELLS_PER_S * Protocol.SPRINT_FACTOR * dt + 0.0001,
				"tick %d within the sprint speed" % i)
	server.free()


## Anything but a bool is refused (a client could send any Variant).
func test_sprint_refuses_what_is_not_a_bool() -> void:
	var server := _server_with_walker()
	for bad in [1, 2.5, "yes", Vector2(9, 9), null, [true]]:
		server.on_sprint(1, bad)
	assert_almost(_walked(server, 0.25), Protocol.SPEED_CELLS_PER_S * 0.25, 0.0001, "still walking")
	server.free()


func test_sprint_from_unknown_peer_is_ignored() -> void:
	var server := _server_with_walker()
	server.on_sprint(2, true)
	assert_almost(_walked(server, 0.25), Protocol.SPEED_CELLS_PER_S * 0.25, 0.0001)
	assert_false(server._players.has(2))
	server.free()


## Sprinting never overshoots the target (invariant 3) and does not move a stopped player.
func test_sprint_stops_on_target_and_when_stopped() -> void:
	var server := _server_with_walker()
	server.on_sprint(1, true)
	server.on_move_to(1, Vector2(17, 16))
	server._move_players(5.0)
	assert_eq(server._players[1]["pos"], Vector2(17, 16))
	server.on_move_to(1, Vector2(20, 16))
	server.on_stop(1)
	assert_almost(_walked(server, 0.5), 0.0, 0.0001, "stopped")
	server.free()


## A starving player sprints slower too: the hunger factor still applies.
func test_starving_sprint_is_slowed() -> void:
	var server := _server_with_walker()
	server._players[1]["hunger"] = 0.0
	server.on_sprint(1, true)
	var want := Protocol.SPEED_CELLS_PER_S * Protocol.SPRINT_FACTOR * HUNGER.STARVING_SPEED * 0.25
	assert_almost(_walked(server, 0.25), want, 0.0001)
	server.free()


## A player who joins (or comes back) walks until they ask to sprint.
func test_a_new_player_walks() -> void:
	var server: Node = load(SERVER_SCRIPT).new()
	assert_false(server._new_player("bob", Vector2i(16, 16), {})["sprint"])
	server.free()
