extends TestCase

## Clicking a bush walks to it, then asks the server to gather (client/world_view.gd).


class FakeClient:
	extends Node
	signal welcomed(cell: Vector2i)
	signal snapshot_received(players: Array)
	signal creatures_received(creatures: Array)
	signal marks_received(marks: Array)
	var my_peer_id := 1
	var gathered: Array = []

	func request_move(_cell: Vector2i) -> void:
		pass

	func request_stop() -> void:
		pass

	func request_gather(cell: Vector2i) -> void:
		gathered.append(cell)


func _view() -> Node2D:
	var view: Node2D = load("res://client/world_view.gd").new()
	view.client = FakeClient.new()
	view.add_child(view.client)
	view._ready()
	return view


func test_gathers_once_when_reached() -> void:
	var view := _view()
	var bush := Vector2i(10, 10)
	view._gather_at = bush
	view._my_pos = Vector2(14, 10)
	view._gather_if_reached()
	assert_eq(view.client.gathered, [], "still walking")
	view._my_pos = Vector2(10, 11)
	view._gather_if_reached()
	assert_eq(view.client.gathered, [bush])
	view._gather_if_reached()
	assert_eq(view.client.gathered, [bush], "only once")
	view.free()
