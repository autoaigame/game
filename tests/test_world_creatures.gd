extends TestCase

## The world view draws the creatures the server sends (client/world_view.gd).


class FakeClient:
	extends Node
	signal welcomed(cell: Vector2i)
	signal snapshot_received(players: Array)
	signal creatures_received(creatures: Array)
	signal marks_received(marks: Array)
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


func test_creature_appears_moves_and_goes() -> void:
	var view := _view()
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": Vector2(2, 3)}])
	var node: Node2D = view._creatures[1]["node"]
	assert_true(node.get_parent() == view, "drawn in the world")
	assert_eq(node.position, IsoLayer.cell_to_local(Vector2(2, 3)))
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": Vector2(4, 3)}])
	for i in 60:
		view._animate_creatures(1.0 / 60.0)
	assert_true(node.position.distance_to(IsoLayer.cell_to_local(Vector2(4, 3))) < 1.0, "glided to its new cell")
	view.client.creatures_received.emit([])
	assert_false(view._creatures.has(1), "gone when the server no longer sends it")
	assert_true(node.is_queued_for_deletion())
	view.free()


## Faces where it walks: drawn mirrored when walking left on screen.
func test_creature_faces_its_way() -> void:
	var view := _view()
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": Vector2(5, 5)}])
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": Vector2(4, 6)}])  # left on screen
	view._animate_creatures(0.1)
	var node: Node2D = view._creatures[1]["node"]
	assert_true(node.scale.x < 0.0, "faces left")
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": Vector2(6, 4)}])  # right
	for i in 30:
		view._animate_creatures(0.1)
	assert_true(node.scale.x > 0.0, "faces right")
	view.free()


## The dog is drawn from its sprite sheet, and walks while it moves.
func test_dog_uses_its_sprite_sheet() -> void:
	var view := _view()
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": Vector2(5, 5)}])
	var sprite: Sprite2D = view._creatures[1]["node"].get_node("Sprite")
	assert_eq(sprite.texture.resource_path, "res://assets/dog.png")
	assert_eq(sprite.frame_coords.y, DogAnim.row_of("idle"))
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": Vector2(7, 5)}])
	view._animate_creatures(0.1)
	assert_true(sprite.frame_coords.y in [DogAnim.row_of("walk"), DogAnim.row_of("run")], "walking")
	view.free()


## Marks on the ground are drawn flat, fade out at the end, and go when the server drops them.
func test_marks_drawn_fade_and_go() -> void:
	var view := _view()
	view.client.marks_received.emit([{"id": 9, "kind": "pee", "pos": Vector2(3, 3), "left": 60.0}])
	var node: Node2D = view._marks[9]["node"]
	assert_eq(node.position, IsoLayer.cell_to_local(Vector2(3, 3)))
	assert_true(node.z_index < 0, "flat on the ground, under creatures")
	assert_eq(node.modulate.a, 1.0)
	view._age_marks(60.0 - MarkView.FADE_S / 2.0)
	assert_almost(node.modulate.a, 0.5)
	view.client.marks_received.emit([])
	assert_false(view._marks.has(9))
	view.free()
