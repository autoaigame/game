extends TestCase


## Stands in for client/client.gd: the signals and fields client/world_view.gd uses.
class FakeClient:
	extends Node
	signal welcomed(cell: Vector2i)
	signal snapshot_received(players: Array)
	signal creatures_received(creatures: Array)
	var my_peer_id := 1

	func request_move(_cell: Vector2i) -> void:
		pass

	func request_stop() -> void:
		pass


func _view() -> Node2D:
	var view: Node2D = load("res://client/world_view.gd").new()
	view.client = FakeClient.new()
	view.add_child(view.client)
	view._ready()
	return view


func _camera(view: Node2D) -> Camera2D:
	for c in view.get_children():
		if c is Camera2D:
			return c
	return null


## Camera smoothing makes the camera trail the walking player, showing more behind than ahead.
func test_camera_does_not_trail() -> void:
	var view := _view()
	var cam := _camera(view)
	assert_true(cam != null, "the view has a camera")
	assert_false(cam.position_smoothing_enabled, "no smoothing: the camera never lags behind")
	assert_false(cam.drag_horizontal_enabled or cam.drag_vertical_enabled, "no drag margins")
	view.free()


## While walking, the camera is placed exactly on the drawn player every frame.
func test_camera_stays_on_my_player_while_walking() -> void:
	var view := _view()
	var cam := _camera(view)
	view.client.snapshot_received.emit([{"id": 1, "name": "me", "pos": Vector2(0, 0)}])
	view.client.snapshot_received.emit([{"id": 1, "name": "me", "pos": Vector2(3, 0)}])
	for i in 5:
		view._animate_actors(1.0 / 60.0)
		assert_eq(cam.position, (view._actors[1] as Node2D).position)
	view.free()
