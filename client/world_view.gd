## Draws the isometric map and the players; turns clicks and WASD into move requests, the mouse wheel into zoom.
extends Node2D

var _tiles_tex: Texture2D = load(IsoLayer.TILES_ATLAS)
const PLAYER_TEX := preload("res://assets/player.png")
const DOG_TEX := preload("res://assets/dog.png")

var client: Node  ## client/client.gd
var _layer: TileMapLayer
var _streamer := ChunkStreamer.new(2, 3, 1)
var _builder: ChunkBuilder
var _clock := ChunkBuilder.WallClock.new()
var _chunk_nodes := {}  ## chunk -> Node2D
var _actors := {}  ## peer_id -> Node2D
## creature id -> {node, server, shown (cells), pose (from the server, "idle" if none), walked (cells), t (s in pose)}
var _creatures := {}
var _marks := {}  ## mark id -> {node: MarkView, left: seconds}
var _walk := {}  ## peer_id -> {server, shown: Vector2 in cells, walked: float in cells, facing: WalkAnim.FACINGS index, still: s}
var _camera := Camera2D.new()
var _my_pos := Vector2.ZERO  ## my position in the last snapshot, in cells
var _key_dir := Vector2i.ZERO  ## direction of the held keys at the last frame
var _gather_at: Variant = null  ## the bush the player walks to, to gather from it
var _key_target := Vector2.ZERO  ## last target sent for the held keys
var _zoom_target := CameraZoom.DEFAULT  ## the zoom the camera glides to (mouse wheel)
var _drift_t := 0.0  ## seconds of slow camera drift behind the start menu
const DRIFT_CELLS := 2.0  ## radius of the drift around the spawn, in cells
const DRIFT_PERIOD_S := 60.0


func _ready() -> void:
	y_sort_enabled = true
	_builder = ChunkBuilder.new(_streamer, _tiles_tex)
	_layer = IsoLayer.new_layer(null)  # empty: only converts mouse positions to cells
	add_child(_layer)
	_camera.zoom = Vector2(CameraZoom.DEFAULT, CameraZoom.DEFAULT)
	_camera.position_smoothing_enabled = false  # locked on the player: smoothing made it trail behind
	add_child(_camera)
	_camera.position = IsoLayer.cell_to_local(Vector2(MapData.spawn_cell()))
	client.snapshot_received.connect(_on_snapshot)
	client.creatures_received.connect(_on_creatures)
	client.marks_received.connect(_on_marks)
	client.welcomed.connect(func(cell: Vector2i): _my_pos = Vector2(cell))


func _on_snapshot(players: Array) -> void:
	var seen := {}
	for p in players:
		var id: int = p["id"]
		seen[id] = true
		var actor: Node2D = _actors.get(id)
		if actor == null:
			actor = _make_actor(p["name"], id == client.my_peer_id)
			_actors[id] = actor
			add_child(actor)
			_walk[id] = {"server": p["pos"], "shown": p["pos"], "walked": 0.0, "facing": -1, "still": 0.0}
			actor.position = IsoLayer.cell_to_local(p["pos"])
		_walk[id]["server"] = p["pos"]  # drawn there smoothly by _animate_actors
		if id == client.my_peer_id:
			_my_pos = p["pos"]
	for id in _actors.keys():
		if not seen.has(id):
			_actors[id].queue_free()
			_actors.erase(id)
			_walk.erase(id)


func _on_creatures(list: Array) -> void:
	var seen := {}
	for c in list:
		var id: int = c["id"]
		seen[id] = true
		if not _creatures.has(id):
			var node := _make_creature(c["kind"])
			node.position = IsoLayer.cell_to_local(c["pos"])
			add_child(node)
			_creatures[id] = {"node": node, "server": c["pos"], "shown": c["pos"], "pose": "idle", "walked": 0.0, "t": 0.0}
		var pose: String = c.get("state", "idle")
		if pose != _creatures[id]["pose"]:
			_creatures[id]["pose"] = pose
			_creatures[id]["t"] = 0.0
		_creatures[id]["server"] = c["pos"]
	for id in _creatures.keys():
		if not seen.has(id):
			_creatures[id]["node"].queue_free()
			_creatures.erase(id)


func _on_marks(list: Array) -> void:
	var seen := {}
	for m in list:
		var id: int = m["id"]
		seen[id] = true
		if not _marks.has(id):
			var node := MarkView.new()
			node.kind = m["kind"]
			node.position = IsoLayer.cell_to_local(m["pos"])
			add_child(node)
			_marks[id] = {"node": node}
		_marks[id]["left"] = float(m["left"])
	for id in _marks.keys():
		if not seen.has(id):
			_marks[id]["node"].queue_free()
			_marks.erase(id)
	_age_marks(0.0)


## Marks fade out over their last seconds (the server removes them when they expire).
func _age_marks(dt: float) -> void:
	for id in _marks:
		var m: Dictionary = _marks[id]
		m["left"] = maxf(m["left"] - dt, 0.0)
		(m["node"] as Node2D).modulate.a = clampf(m["left"] / MarkView.FADE_S, 0.0, 1.0)


func _make_creature(kind: String) -> Node2D:
	if kind != "dog":
		var animal := AnimalView.new()
		animal.kind = kind
		return animal
	var node := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = DOG_TEX
	sprite.hframes = DogAnim.COLUMNS
	sprite.vframes = DogAnim.ROWS.size()
	sprite.centered = false
	sprite.offset = DogAnim.sprite_offset()
	node.add_child(sprite)
	return node


## Draws every creature between updates, gliding like players and facing where it walks (display only).
func _animate_creatures(dt: float) -> void:
	for id in _creatures:
		var c: Dictionary = _creatures[id]
		var before: Vector2 = c["shown"]
		c["shown"] = WalkAnim.follow(before, c["server"], dt)
		var node: Node2D = c["node"]
		node.position = IsoLayer.cell_to_local(c["shown"])
		var screen_dx := IsoLayer.cell_to_local(c["shown"]).x - IsoLayer.cell_to_local(before).x
		if absf(screen_dx) > 0.01:
			node.scale.x = -1.0 if screen_dx < 0.0 else 1.0
		var moved: float = (c["shown"] - before).length()
		c["walked"] += moved
		c["t"] += dt
		if node is AnimalView:
			(node as AnimalView).set_motion(c["walked"], moved > 0.0005)
			continue
		var speed := moved / dt if dt > 0.0 else 0.0
		(node.get_node("Sprite") as Sprite2D).frame_coords = DogAnim.frame(c["pose"], moved > 0.0005, speed, c["walked"], c["t"])


## Draws every player between snapshots and animates its walk (display only).
func _animate_actors(dt: float) -> void:
	for id in _actors:
		var w: Dictionary = _walk[id]
		var actor: Node2D = _actors[id]
		var sprite: Sprite2D = actor.get_node("Sprite")
		sprite.frame_coords = WalkAnim.animate(w, dt)
		var pos := IsoLayer.cell_to_local(w["shown"])
		actor.position = pos
		if id == client.my_peer_id:
			_camera.position = pos


## Builds the chunks around the player (or the spawn before joining) within a time budget per frame,
## and frees far ones.
func _stream_chunks() -> void:
	var at := Protocol.cell_of(_my_pos) if client.my_peer_id != 0 else MapData.spawn_cell()
	var freed := _streamer.update(at)
	_builder.drop(freed)
	for c in freed:
		if _chunk_nodes.has(c):
			_chunk_nodes[c].queue_free()
			_chunk_nodes.erase(c)
	for built in _builder.run(ChunkBuilder.BUDGET_USEC, _clock):
		_chunk_nodes[built[0]] = built[1]
		add_child(built[1])


## Before joining, the camera circles slowly around the spawn behind the menu (display only).
func _drift_camera(delta: float) -> void:
	_drift_t += delta
	var a := TAU * _drift_t / DRIFT_PERIOD_S
	_camera.position = IsoLayer.cell_to_local(Vector2(MapData.spawn_cell()) + DRIFT_CELLS * Vector2(cos(a), sin(a)))


func _make_actor(player_name: String, is_me: bool) -> Node2D:
	var actor := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = PLAYER_TEX
	sprite.hframes = WalkAnim.SHEET_COLUMNS
	sprite.vframes = WalkAnim.SHEET_ROWS
	sprite.centered = false
	sprite.offset = WalkAnim.sprite_offset()
	actor.add_child(sprite)
	var label := Label.new()
	label.text = player_name
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE if not is_me else Color8(0xe8, 0xc4, 0x4a))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var r := WalkAnim.name_rect()
	label.size = r.size
	label.position = r.position
	actor.add_child(label)
	return actor


func _unhandled_input(event: InputEvent) -> void:
	if client.my_peer_id == 0:
		return
	if event is InputEventMouseButton and event.pressed:
		var steps := CameraZoom.wheel_steps(event.button_index, event.factor)
		if steps != 0.0:
			_zoom_target = CameraZoom.target_after(_zoom_target, steps)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _layer.local_to_map(_layer.get_local_mouse_position())
		_gather_at = Interact.gatherable_at(cell)
		client.request_move(Vector2(Interact.walk_target(_gather_at)) if _gather_at != null else Vector2(cell))


## Asks the server to gather once the player has walked up to the bush they clicked.
func _gather_if_reached() -> void:
	if _gather_at != null and Interact.reached(_my_pos, _gather_at):
		client.request_gather(_gather_at)
		_gather_at = null


func _process(delta: float) -> void:
	_animate_actors(delta)
	_animate_creatures(delta)
	_age_marks(delta)
	var z := CameraZoom.approach(_camera.zoom.x, _zoom_target, delta)
	_camera.zoom = Vector2(z, z)
	_stream_chunks()
	if client.my_peer_id == 0:
		_drift_camera(delta)
		return
	_gather_if_reached()
	var dir := KeyMove.direction(
			Input.is_physical_key_pressed(KEY_W), Input.is_physical_key_pressed(KEY_S),
			Input.is_physical_key_pressed(KEY_A), Input.is_physical_key_pressed(KEY_D))
	if dir == Vector2i.ZERO:
		if _key_dir != Vector2i.ZERO:
			client.request_stop()
		_key_dir = dir
		return
	_gather_at = null
	var target := KeyMove.held_target(_my_pos, dir)
	if dir != _key_dir or not target.is_equal_approx(_key_target):
		client.request_move(target)
	_key_dir = dir
	_key_target = target
