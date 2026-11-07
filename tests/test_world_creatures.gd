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


## A dug hole is drawn (it is not an empty node).
func test_hole_mark_is_drawn() -> void:
	var view := _view()
	view.client.marks_received.emit([{"id": 4, "kind": "hole", "pos": Vector2(1, 1), "left": 100.0}])
	var node: MarkView = view._marks[4]["node"]
	assert_eq(node.kind, "hole")
	assert_true(MarkView.KINDS.has("hole") and MarkView.KINDS.has("pee") and MarkView.KINDS.has("fire") \
			and MarkView.KINDS.has("carcass_rabbit") and MarkView.KINDS.has("carcass_pheasant"), "kinds drawn")
	view.free()


## Wild animals are drawn as AnimalView (not the dog sprite) and bob as they hop.
func test_wild_animals_are_drawn_and_hop() -> void:
	var view := _view()
	view.client.creatures_received.emit([{"id": -1, "kind": "rabbit", "owner": 0, "pos": Vector2(2, 2), "state": "idle"},
			{"id": -2, "kind": "pheasant", "owner": 0, "pos": Vector2(5, 2), "state": "idle"}])
	var rabbit: Node2D = view._creatures[-1]["node"]
	assert_true(rabbit is AnimalView, "rabbit drawn as an animal")
	assert_eq((rabbit as AnimalView).kind, "rabbit")
	assert_true(AnimalView.KINDS.has("rabbit") and AnimalView.KINDS.has("pheasant"))
	view.client.creatures_received.emit([{"id": -1, "kind": "rabbit", "owner": 0, "pos": Vector2(4, 2), "state": "hop"}])
	var highest := 0.0
	for i in 30:
		view._animate_creatures(1.0 / 60.0)
		highest = maxf(highest, (rabbit as AnimalView).hop)
	assert_true(highest > 0.3, "hops while moving: %f" % highest)
	assert_false(view._creatures.has(-2), "pheasant gone")
	view.free()


## A dog running faster than a player (a hunt: 9 cells per second) is drawn gliding with it, close
## behind, instead of lagging until it jumps several cells ahead at once.
func test_fast_dog_glides_without_jumping() -> void:
	var view := _view()
	var pos := Vector2(0, 0)
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": pos}])
	var node: Node2D = view._creatures[1]["node"]
	var biggest_jump := 0.0
	var frames_per_update := 60 / Protocol.TICK_HZ
	for tick in 2 * Protocol.TICK_HZ:
		pos += Vector2(9.0 / Protocol.TICK_HZ, 0)
		view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": pos, "state": "hunt"}])
		for f in frames_per_update:
			var before: Vector2 = view._creatures[1]["shown"]
			view._animate_creatures(1.0 / 60.0)
			biggest_jump = maxf(biggest_jump, before.distance_to(view._creatures[1]["shown"]))
	assert_true(biggest_jump < 0.5, "no jump: biggest step drawn in a frame %f cells" % biggest_jump)
	assert_true(pos.distance_to(view._creatures[1]["shown"]) < 1.5, "close behind")
	assert_true(node.position.distance_to(IsoLayer.cell_to_local(view._creatures[1]["shown"])) < 0.01)


## A dog bringing back its catch is drawn with it in its mouth, until it hands it over.
func test_dog_carries_its_catch() -> void:
	var view := _view()
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": Vector2(5, 5), "state": "fetch",
			"carry": "rabbit"}])
	var node: Node2D = view._creatures[1]["node"]
	var carried: MarkView = node.get_node_or_null("Carry")
	assert_true(carried != null, "drawn in its mouth")
	assert_eq(carried.kind, "carcass_rabbit")
	assert_true(carried.position.x > 0.0 and carried.position.y < 0.0, "at its head, which faces right")
	view.client.creatures_received.emit([{"id": 1, "kind": "dog", "owner": 1, "pos": Vector2(5, 5), "state": "idle"}])
	assert_true(node.get_node_or_null("Carry") == null or node.get_node("Carry").is_queued_for_deletion(), "handed over")
	view.free()
