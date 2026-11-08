extends TestCase

## The dog a player chooses, on the server (server.gd on_set_dog): checked against DogSkins, kept on the
## player's dog, and sent with the creatures to everyone who sees that dog.

const SERVER_SCRIPT := "res://server/server.gd"


func _server() -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = server._new_player("ann", Vector2i(16, 16), {})
	server._players[2] = server._new_player("bob", Vector2i(17, 16), {})
	return server


## The dog record of player `owner` among the creatures `viewer` is sent.
func _sent_dog(server: Node, viewer: int, owner: int) -> Dictionary:
	for c in server._creatures_for(viewer):
		if c["kind"] == "dog" and c["owner"] == owner:
			return c
	return {}


func test_ids_and_validation() -> void:
	assert_eq(DogSkins.IDS, ["classic", "cyborg_a", "cyborg_b", "cyborg_c"] as Array[String])
	assert_eq(DogSkins.DEFAULT, "classic")
	for id in DogSkins.IDS:
		assert_eq(DogSkins.valid(id), id)
	for junk in ["", "cyborg_d", "CYBORG_A", 3, null, ["cyborg_a"], {"id": "cyborg_b"}]:
		assert_eq(DogSkins.valid(junk), DogSkins.DEFAULT, "junk %s" % [junk])
	assert_eq(DogSkins.cycle("classic", 1), "cyborg_a")
	assert_eq(DogSkins.cycle("cyborg_c", 1), "classic", "wraps forwards")
	assert_eq(DogSkins.cycle("classic", -1), "cyborg_c", "wraps backwards")
	assert_eq(DogSkins.cycle("nope", 1), "cyborg_a", "from the default")


func test_new_player_has_the_default_dog() -> void:
	var server := _server()
	assert_eq(server._players[1]["dog"]["skin"], DogSkins.DEFAULT)
	server.free()


## The client sends its dog before joining: it is worn from the first moment, the early copy dropped.
func test_dog_sent_before_joining_is_kept_on_join() -> void:
	var server := _server()
	server.on_set_dog(5, "cyborg_b")
	assert_eq(server._early_dogs.get(5), "cyborg_b")
	var p: Dictionary = server._new_player("cid", Vector2i(16, 17), {}, {}, [], server._early_dogs.get(5))
	assert_eq(p["dog"]["skin"], "cyborg_b")
	server.free()


func test_change_after_joining_is_kept() -> void:
	var server := _server()
	server.on_set_dog(1, "cyborg_c")
	assert_eq(server._players[1]["dog"]["skin"], "cyborg_c")
	assert_eq(server._players[2]["dog"]["skin"], DogSkins.DEFAULT, "only that player's dog")
	server.free()


## An unknown dog, or anything that is not a dog id, gives the default dog (also before joining).
func test_unknown_dog_gives_the_default() -> void:
	var server := _server()
	server.on_set_dog(1, "cyborg_a")
	for junk in ["golden_dog", 42, null, ["cyborg_b"]]:
		server.on_set_dog(1, "cyborg_a")
		server.on_set_dog(1, junk)
		assert_eq(server._players[1]["dog"]["skin"], DogSkins.DEFAULT, "junk %s" % [junk])
	server.on_set_dog(6, "wolf")
	assert_eq(server._early_dogs.get(6), DogSkins.DEFAULT)
	assert_eq(server._new_player("dee", Vector2i(16, 17), {}, {}, [], "wolf")["dog"]["skin"], DogSkins.DEFAULT)
	server.free()


## Others see the right dog: the creatures they are sent carry its id; the default dog sends none.
func test_creatures_carry_the_chosen_dog() -> void:
	var server := _server()
	assert_false(_sent_dog(server, 2, 1).has("skin"), "the default dog adds nothing")
	server.on_set_dog(1, "cyborg_b")
	assert_eq(_sent_dog(server, 2, 1).get("skin"), "cyborg_b", "seen by the other player")
	assert_eq(_sent_dog(server, 1, 1).get("skin"), "cyborg_b", "and by its owner")
	assert_false(_sent_dog(server, 1, 2).has("skin"), "the other dog stays the default")
	server.on_set_dog(1, "classic")
	assert_false(_sent_dog(server, 2, 1).has("skin"), "back to the default")
	server.free()


## Peers that never join cannot pile up dogs on the server.
func test_early_dogs_are_bounded_and_dropped_on_disconnect() -> void:
	var server := _server()
	for peer in range(100, 100 + server.MAX_EARLY_LOOKS + 20):
		server.on_set_dog(peer, "cyborg_a")
	assert_eq(server._early_dogs.size(), server.MAX_EARLY_LOOKS)
	server._on_peer_disconnected(100)
	assert_false(server._early_dogs.has(100), "dropped on disconnect")
	server.free()


## The RPC exists on both sides with the handler the server implements.
func test_set_dog_rpc_reaches_the_server() -> void:
	var net_src := FileAccess.get_file_as_string("res://shared/net.gd")
	assert_true(net_src.contains("func set_dog(") and net_src.contains("\"on_set_dog\""))
	var server := _server()
	assert_true(server.has_method("on_set_dog"))
	server.free()
