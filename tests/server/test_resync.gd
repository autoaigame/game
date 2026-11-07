extends TestCase

## A client back from a pause (its browser tab was hidden, so it read nothing and dropped what did not
## fit its buffer) asks for a resync: the server sends a "resynced" marker (the client drops what came
## before it as stale), then again everything it only sends on a change (server/server.gd on_resync).

const SERVER_SCRIPT := "res://server/server.gd"


func _server() -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = server._new_player("ann", Vector2i(16, 16), {"hunger": 40.0}, {"berries": 3})
	server._players[2] = server._new_player("bob", Vector2i(17, 16), {})
	return server


func test_resync_sends_the_marker_then_everything() -> void:
	var server := _server()
	server.MARKS.add(server._marks, "fire", Vector2(20, 20), 60.0)
	server._status_to_send(server._players[1])  # the client was told its hunger already
	var msgs: Array = server._resync_messages(1)
	var methods: Array = msgs.map(func(m): return m[0])
	assert_eq(methods[0], "resynced", "the marker comes first, so the client keeps what follows")
	assert_eq(methods.count("resynced"), 1)
	assert_true(["marks", [server.MARKS.snapshot(server._marks)]] in msgs, "marks")
	assert_true(["status", [{"hunger": 40}]] in msgs, "status, even unchanged")
	assert_true(["inventory", [{"berries": 3}]] in msgs, "inventory")
	assert_true(["look", [2, server._players[2]["look"]]] in msgs, "what the others wear")
	assert_true(["look", [1, server._players[1]["look"]]] in msgs, "and itself")
	server.free()


func test_resync_of_an_unknown_peer_sends_nothing() -> void:
	var server := _server()
	assert_eq(server._resync_messages(9), [])
	server.free()
