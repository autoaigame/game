extends TestCase

## A tree drawn in front of my player fades where it covers the body, then comes back once I have
## passed; meanwhile my silhouette is not drawn (client/world_view.gd). Scenes built by hand, so the
## world seed does not matter.

const TestTreeScale := preload("res://tests/test_tree_scale.gd")


## Stands in for client/client.gd: the signals and fields client/world_view.gd uses.
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


## A view with me standing on `me`, and one chunk node holding a hand-made tree on each of `trees`.
func _view(me: Vector2, trees: Array) -> Node2D:
	var view: Node2D = load("res://client/world_view.gd").new()
	view.client = FakeClient.new()
	view.add_child(view.client)
	view._ready()
	view.client.snapshot_received.emit([{"id": 1, "name": "me", "pos": me}])
	var node := Node2D.new()
	for c in trees:
		node.add_child(TestTreeScale.hand_tree(IsoLayer.cell_to_local(c), ChunkView.TREE_SCALE))
	view.add_child(node)
	view._chunk_nodes[MapData.chunk_of(Protocol.cell_of(me))] = node
	return view


func _tree(view: Node2D, i: int) -> Sprite2D:
	return view._chunk_nodes.values()[0].get_child(i)


func _ghost_on(view: Node2D) -> bool:
	return (view._actors[1].get_node("Model3D") as Character3D).silhouette


func _run(view: Node2D, seconds: float) -> void:
	for i in int(seconds * 60.0):
		view._fade_trees(1.0 / 60.0)


## A tree one cell south of me (drawn after me) covers my body and fades; one a cell north (drawn
## before me) never does.
func test_only_the_tree_in_front_fades() -> void:
	var view := _view(Vector2(4, 4), [Vector2(5, 5), Vector2(3, 3)])
	_run(view, 1.0)
	assert_almost(_tree(view, 0).modulate.a, ChunkView.TREE_FADE_ALPHA, 0.0001, "the tree in front fades")
	assert_eq(_tree(view, 1).modulate.a, 1.0, "the tree behind stays opaque")
	view.free()


## Once I have walked past (now south of the tree), it comes back to opaque.
func test_the_tree_comes_back_once_passed() -> void:
	var view := _view(Vector2(4, 4), [Vector2(5, 5)])
	_run(view, 1.0)
	assert_true(_tree(view, 0).modulate.a < 1.0, "faded while in front")
	view.client.snapshot_received.emit([{"id": 1, "name": "me", "pos": Vector2(7, 7)}])
	(view._actors[1] as Node2D).position = IsoLayer.cell_to_local(Vector2(7, 7))
	_run(view, 1.0)
	assert_eq(_tree(view, 0).modulate.a, 1.0, "opaque again")
	view.free()


## A tree in front but off to the side, not covering my body, stays opaque.
func test_a_tree_aside_stays_opaque() -> void:
	var view := _view(Vector2(4, 4), [Vector2(6, 4)])
	_run(view, 1.0)
	assert_eq(_tree(view, 0).modulate.a, 1.0)
	view.free()


## A tree covering only my arm (the right edge of its opaque part on my left side) still fades.
func test_a_tree_over_an_arm_fades() -> void:
	var view := _view(Vector2(4, 4), [])
	var feet := IsoLayer.cell_to_local(Vector2(4, 4))
	var t := TestTreeScale.hand_tree(feet + Vector2(-15 - 9 * ChunkView.TREE_SCALE, 10), ChunkView.TREE_SCALE)
	view._chunk_nodes.values()[0].add_child(t)
	assert_false(ChunkView.hides(t, feet + Vector2(0, -50)), "the middle of my body is clear")
	_run(view, 1.0)
	assert_true(t.modulate.a < 1.0, "fades for the arm")
	view.free()


## While the trees in front are faded my silhouette is off (it would wash out the player seen through
## them); it stays on until they are faded enough, and comes back once no tree covers me.
func test_no_silhouette_through_a_faded_tree() -> void:
	var view := _view(Vector2(4, 4), [Vector2(5, 5)])
	_run(view, 1.0 / 60.0)
	assert_true(_ghost_on(view), "still on while the tree is almost opaque")
	_run(view, 0.5)
	assert_false(_ghost_on(view), "off behind the faded tree")
	view.client.snapshot_received.emit([{"id": 1, "name": "me", "pos": Vector2(7, 7)}])
	(view._actors[1] as Node2D).position = IsoLayer.cell_to_local(Vector2(7, 7))
	_run(view, 1.0 / 60.0)
	assert_true(_ghost_on(view), "back once passed")
	view.free()


## show_silhouette() hides and shows the drawn silhouette sprite (built by _ready, which needs the
## renderer: stood in for by a plain sprite).
func test_show_silhouette_on_a_drawn_model() -> void:
	var model := Character3D.new()
	model._ghost = Sprite2D.new()
	model.add_child(model._ghost)
	model.show_silhouette(false)
	assert_false(model._ghost.visible)
	model.show_silhouette(true)
	assert_true(model._ghost.visible)
	model.free()
