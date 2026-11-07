extends TestCase

## Each player is sent only the players and creatures near them (server/server.gd).

const SERVER_SCRIPT := "res://server/server.gd"


func _server() -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	var s := MapData.spawn_cell()
	server._players[1] = server._new_player("ann", s, {})
	server._players[2] = server._new_player("bob", s + Vector2i(5, 0), {})
	server._players[3] = server._new_player("cat", s + Vector2i(Protocol.INTEREST_RADIUS + 10, 0), {})
	return server


func _ids(list: Array) -> Array:
	var out := list.map(func(e): return e["id"])
	out.sort()
	return out


func test_players_far_away_are_not_sent() -> void:
	var server := _server()
	assert_eq(_ids(server._snapshot_for(1)), [1, 2])
	assert_eq(_ids(server._snapshot_for(3)), [3], "always sees itself")
	server.free()


func test_creatures_far_away_are_not_sent() -> void:
	var server := _server()
	assert_eq(_ids(server._creatures_for(1)), [1, 2])
	assert_eq(_ids(server._creatures_for(3)), [3])
	server.free()


func test_radius_covers_the_widest_view() -> void:
	assert_true(Protocol.INTEREST_RADIUS >= 30, "the view reaches about 21 cells when zoomed out")
