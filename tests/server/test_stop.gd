extends TestCase

const SERVER_SCRIPT := "res://server/server.gd"


func _server_with_walker() -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = {"name": "ann", "pos": Vector2(16, 16), "target": Vector2i(20, 16), "stopped": false}
	return server


func test_stop_halts_where_the_player_is() -> void:
	var server := _server_with_walker()
	server._move_players(0.1)
	var at: Vector2 = server._players[1]["pos"]
	assert_true(at.x > 16.0 and at.x < 17.0, "walked to %s" % at)
	server.on_stop(1)
	server._move_players(0.5)
	assert_eq(server._players[1]["pos"], at)
	server.free()


func test_move_after_stop_walks_again() -> void:
	var server := _server_with_walker()
	server._move_players(0.1)
	server.on_stop(1)
	server.on_move_to(1, Vector2i(20, 16))
	var before: Vector2 = server._players[1]["pos"]
	server._move_players(0.1)
	assert_true(server._players[1]["pos"].x > before.x, "stayed at %s" % before)
	server.free()


func test_stop_from_unknown_peer_is_ignored() -> void:
	var server := _server_with_walker()
	server.on_stop(2)
	server._move_players(0.25)
	assert_almost(server._players[1]["pos"].x, 17.0)
	server.free()
