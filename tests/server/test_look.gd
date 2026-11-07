extends TestCase

## What players wear, on the server (server.gd on_set_look): checked against data/character, sent to
## everyone when it changes, never in the snapshots.

const SERVER_SCRIPT := "res://server/server.gd"


func _jacket_look(body_colour: String) -> Array:
	return [{"id": "body_standard", "color": body_colour}, {"id": "face_adult", "color": "hair_brown"},
			{"id": "top_tshirt", "color": "grey"},
			{"id": "bottom_jeans", "color": "workwear_blue"}]


func _server() -> Node:
	var server: Node = load(SERVER_SCRIPT).new()
	server._players[1] = server._new_player("ann", Vector2i(16, 16), {})
	server._players[2] = server._new_player("bob", Vector2i(17, 16), {})
	return server


func _sent(server: Node) -> Array:
	var out := []
	server.look_sent.connect(func(to: int, who: int, look: Array): out.append([to, who, look]))
	return out


func test_new_player_wears_the_default_look() -> void:
	var server := _server()
	assert_eq(server._players[1]["look"], CharacterParts.default_look())
	server.free()


## A look sent before joining is worn from the first moment; an invalid one gives the default.
func test_look_sent_before_joining_is_worn_on_join() -> void:
	var server := _server()
	var look := _jacket_look("skin_dark")
	server.on_set_look(5, look)
	assert_eq(server._early_looks.get(5), look)
	var p: Dictionary = server._new_player("cid", Vector2i(16, 17), {}, {}, server._early_looks.get(5, []))
	assert_eq(p["look"], look)
	assert_eq(server._new_player("dee", Vector2i(16, 17), {}, {}, [{"id": "golden_crown", "color": "gold"}])["look"],
			CharacterParts.default_look())
	server.free()


func test_valid_change_is_kept_and_sent_to_everyone_once() -> void:
	var server := _server()
	var sent := _sent(server)
	var look := _jacket_look("skin_medium") + [{"id": "hat_cap", "color": "brown"}]
	server.on_set_look(1, look)
	assert_eq(server._players[1]["look"], look)
	assert_eq(sent.size(), 2, "to both players")
	assert_eq(sent.map(func(s): return s[0]).filter(func(to): return to in [1, 2]).size(), 2)
	for s in sent:
		assert_eq(s[1], 1)
		assert_eq(s[2], look)
	server.on_set_look(1, look.duplicate(true))
	assert_eq(sent.size(), 2, "the same look again: nothing sent")
	server.free()


func test_invalid_look_is_refused_and_the_old_one_stays() -> void:
	var server := _server()
	var good := _jacket_look("skin_light") + [{"id": "hat_beanie", "color": "olive"}]
	server.on_set_look(1, good)
	var sent := _sent(server)
	server.on_set_look(1, _jacket_look("skin_light") + [{"id": "golden_crown", "color": "khaki"}])
	server.on_set_look(1, _jacket_look("rainbow"))
	server.on_set_look(1, "not a list")
	assert_eq(server._players[1]["look"], good)
	assert_eq(sent.size(), 0, "refusals are not sent")
	server.free()


## The server keeps its own copy: a client cannot change it afterwards through a shared reference.
func test_kept_look_is_a_copy() -> void:
	var server := _server()
	var look := _jacket_look("skin_light")
	server.on_set_look(1, look)
	look[0]["color"] = "skin_dark"
	assert_eq(server._players[1]["look"][0]["color"], "skin_light")
	server.free()


## Snapshots stay small: positions and names only, every tick.
func test_snapshots_do_not_carry_looks() -> void:
	var src := FileAccess.get_file_as_string(SERVER_SCRIPT)
	var at := src.find("func _snapshot_for(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_true(at >= 0 and body.contains("snap"), "found the snapshot code")
	assert_false(body.contains("look"), "the snapshot is built without the look")


## Peers that never join cannot pile up looks on the server.
func test_early_looks_are_bounded() -> void:
	var server := _server()
	for peer in range(100, 100 + server.MAX_EARLY_LOOKS + 20):
		server.on_set_look(peer, _jacket_look("skin_light"))
	assert_eq(server._early_looks.size(), server.MAX_EARLY_LOOKS)
	server._on_peer_disconnected(100)
	assert_false(server._early_looks.has(100), "dropped on disconnect")
	server.free()
