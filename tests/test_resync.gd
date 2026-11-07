extends TestCase

## Back from a pause (a hidden browser tab runs no frames), the client drops the stale updates it
## buffered, asks the server for a resync, and shows updates again from the server's "resynced"
## marker on (client/client.gd).


func _client() -> Node:
	var c: Node = load("res://client/client.gd").new()
	c.my_peer_id = 5
	return c


func test_a_long_frame_gap_is_a_pause() -> void:
	var c := _client()
	assert_false(c.paused_between(1000, 1000 + c.PAUSE_GAP_MS - 1))
	assert_true(c.paused_between(1000, 1000 + c.PAUSE_GAP_MS + 1))
	assert_false(c.paused_between(0, 50000), "no frame before: not a pause")
	c.free()


func test_stale_updates_are_dropped_until_resynced() -> void:
	var c := _client()
	var asked := [0]
	c.send_resync = func(): asked[0] += 1
	var got := []
	c.snapshot_received.connect(func(p): got.append("snapshot"))
	c.creatures_received.connect(func(p): got.append("creatures"))
	c.marks_received.connect(func(p): got.append("marks"))
	c.status_received.connect(func(p): got.append("status"))
	c.inventory_received.connect(func(p): got.append("inventory"))
	c.notice_received.connect(func(k, a): got.append("notice"))
	c.look_received.connect(func(i, l): got.append("look"))
	c.begin_resync()
	assert_eq(asked[0], 1, "asks the server")
	c.on_snapshot([])
	c.on_creatures([])
	c.on_marks([])
	c.on_status({"hunger": 3})
	c.on_inventory({})
	c.on_notice("hunt", {})
	c.on_look(2, [])
	assert_eq(got, [], "stale: dropped")
	c.on_resynced()
	c.on_snapshot([])
	c.on_inventory({})
	assert_eq(got, ["snapshot", "inventory"], "fresh again")
	c.free()


## If the marker never comes (lost connection, old server), updates show again after a while.
func test_resync_gives_up_after_a_while() -> void:
	var c := _client()
	c.send_resync = func(): pass
	var got := []
	c.snapshot_received.connect(func(p): got.append(1))
	c.begin_resync()
	c.tick_resync(c.RESYNC_TIMEOUT_S - 0.1)
	c.on_snapshot([])
	assert_eq(got, [])
	c.tick_resync(0.2)
	c.on_snapshot([])
	assert_eq(got, [1])
	c.free()


## Before joining there is nothing to resync.
func test_no_resync_before_joining() -> void:
	var c := _client()
	c.my_peer_id = 0
	var asked := [0]
	c.send_resync = func(): asked[0] += 1
	c.begin_resync()
	assert_eq(asked[0], 0)
	c.free()


## The receive buffer holds about a minute of updates, so a short alt-tab drops nothing.
func test_receive_buffer_is_large() -> void:
	var peer: WebSocketMultiplayerPeer = load("res://client/client.gd").new_peer()
	assert_true(peer.inbound_buffer_size >= 1 << 20, "%d bytes" % peer.inbound_buffer_size)
	assert_true(peer.max_queued_packets >= 4096)
