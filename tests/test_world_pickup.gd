extends TestCase

## Clicking a caught animal walks to it, then asks the server to pick it up (client/world_view.gd).


class FakeClient:
	extends Node
	signal welcomed(cell: Vector2i)
	signal snapshot_received(players: Array)
	signal creatures_received(creatures: Array)
	signal marks_received(marks: Array)
	var my_peer_id := 1
	var picked: Array = []

	func request_move(_cell: Vector2i) -> void:
		pass

	func request_stop() -> void:
		pass

	func request_gather(_cell: Vector2i) -> void:
		pass

	func request_pick_up(id: int) -> void:
		picked.append(id)


func _view() -> Node2D:
	var view: Node2D = load("res://client/world_view.gd").new()
	view.client = FakeClient.new()
	view.add_child(view.client)
	view._ready()
	return view


func test_click_finds_a_carcass_not_a_hole() -> void:
	var view := _view()
	view.client.marks_received.emit([{"id": 3, "kind": "carcass_rabbit", "pos": Vector2(10.3, 10.2), "left": 60.0},
			{"id": 4, "kind": "hole", "pos": Vector2(20, 20), "left": 60.0}])
	assert_eq(view._carcass_at(Vector2i(10, 10)), 3)
	assert_eq(view._carcass_at(Vector2i(9, 9)), 3, "a click just above it on screen")
	assert_eq(view._carcass_at(Vector2i(20, 20)), -1, "holes are not picked up")
	assert_eq(view._carcass_at(Vector2i(14, 10)), -1)
	view.free()


func test_picks_up_once_when_reached() -> void:
	var view := _view()
	view.client.marks_received.emit([{"id": 3, "kind": "carcass_rabbit", "pos": Vector2(10, 10), "left": 60.0}])
	view._pick_up_id = 3
	view._my_pos = Vector2(15, 10)
	view._errand_if_reached()
	assert_eq(view.client.picked, [])
	view._my_pos = Vector2(10, 11)
	view._errand_if_reached()
	view._errand_if_reached()
	assert_eq(view.client.picked, [3])
	view.free()
