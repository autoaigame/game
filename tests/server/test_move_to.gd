extends TestCase

const SERVER_SCRIPT := "res://server/server.gd"


func _server_with_player() -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = {"name": "ann", "pos": Vector2(16, 16), "target": Vector2(16, 16), "stopped": false}
	return server


## A held key sends a point on its line, not a cell center: the server walks to that exact point.
func test_walks_to_a_point_between_cell_centers() -> void:
	var server := _server_with_player()
	server.on_move_to(1, Vector2(17.5, 16.25))
	server._move_players(5.0)
	assert_eq(server._players[1]["pos"], Vector2(17.5, 16.25))
	server.free()


func test_refuses_a_target_on_water() -> void:
	var wall := MapData.spawn_cell()
	while MapData.is_walkable(wall):
		wall += Vector2i(1, 0)
	var server := _server_with_player()
	server.on_move_to(1, Vector2(wall) + Vector2(0.2, 0.1))
	assert_eq(server._players[1]["target"], Vector2(16, 16))
	server.free()


func test_refuses_a_target_that_is_not_a_number() -> void:
	var server := _server_with_player()
	server.on_move_to(1, Vector2(NAN, 16))
	server.on_move_to(1, Vector2(INF, 16))
	assert_eq(server._players[1]["target"], Vector2(16, 16))
	server._move_players(1.0)
	assert_eq(server._players[1]["pos"], Vector2(16, 16))
	server.free()
