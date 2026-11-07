## Draws the isometric map and the players; turns clicks and WASD into move requests.
extends Node2D

var _tiles_tex: Texture2D = load(IsoLayer.TILES_ATLAS)
const PLAYER_TEX := preload("res://assets/player.png")
const SPRITE_OFFSET_Y := -40.0

var client: Node  ## client/client.gd
var _layer: TileMapLayer
var _streamer := ChunkStreamer.new(2, 3, 1)
var _chunk_nodes := {}  ## chunk -> Node2D
var _actors := {}  ## peer_id -> Node2D
var _walk := {}  ## peer_id -> {server, shown: Vector2 in cells, walked: float in cells}
var _camera := Camera2D.new()
var _my_pos := Vector2.ZERO  ## my position in the last snapshot, in cells
var _key_dir := Vector2i.ZERO  ## direction of the held keys at the last frame
var _key_target := Vector2i.ZERO  ## last target sent for the held keys


func _ready() -> void:
	y_sort_enabled = true
	_layer = IsoLayer.new_layer(null)  # empty: only converts mouse positions to cells
	add_child(_layer)
	_camera.zoom = Vector2(IsoLayer.CAMERA_ZOOM, IsoLayer.CAMERA_ZOOM)
	_camera.position_smoothing_enabled = true
	add_child(_camera)
	_camera.position = IsoLayer.cell_to_local(Vector2(MapData.spawn_cell()))
	client.snapshot_received.connect(_on_snapshot)
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
			_walk[id] = {"server": p["pos"], "shown": p["pos"], "walked": 0.0}
			actor.position = IsoLayer.cell_to_local(p["pos"])
		_walk[id]["server"] = p["pos"]  # drawn there smoothly by _animate_actors
		if id == client.my_peer_id:
			_my_pos = p["pos"]
	for id in _actors.keys():
		if not seen.has(id):
			_actors[id].queue_free()
			_actors.erase(id)
			_walk.erase(id)


## Draws every player between snapshots and animates its walk (display only).
func _animate_actors(dt: float) -> void:
	for id in _actors:
		var w: Dictionary = _walk[id]
		var before: Vector2 = w["shown"]
		w["shown"] = WalkAnim.follow(before, w["server"], dt)
		var moved: float = (w["shown"] - before).length()
		var walking := moved > 0.0
		if walking:
			w["walked"] += moved
		var actor: Node2D = _actors[id]
		var pos := IsoLayer.cell_to_local(w["shown"])
		var sprite: Sprite2D = actor.get_node("Sprite")
		var column := sprite.frame_coords.x
		if walking:
			column = WalkAnim.facing(pos - actor.position)
		sprite.frame_coords = Vector2i(column, WalkAnim.walk_row(w["walked"]) if walking else 0)
		sprite.offset.y = SPRITE_OFFSET_Y + WalkAnim.bob(w["walked"], walking)
		actor.position = pos
		if id == client.my_peer_id:
			_camera.position = pos


## Builds the chunks around the player (or the spawn before joining), a few per frame, and frees far ones.
func _stream_chunks() -> void:
	var at := Protocol.cell_of(_my_pos) if client.my_peer_id != 0 else MapData.spawn_cell()
	for c in _streamer.update(at):
		if _chunk_nodes.has(c):
			_chunk_nodes[c].queue_free()
			_chunk_nodes.erase(c)
	for c in _streamer.take_builds():
		var node := ChunkView.build(c, _tiles_tex)
		_chunk_nodes[c] = node
		add_child(node)


func _make_actor(player_name: String, is_me: bool) -> Node2D:
	var actor := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = PLAYER_TEX
	sprite.hframes = 4
	sprite.vframes = 1 + WalkAnim.WALK_FRAMES
	sprite.offset = Vector2(0, SPRITE_OFFSET_Y)
	actor.add_child(sprite)
	var label := Label.new()
	label.text = player_name
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE if not is_me else Color8(0xe8, 0xc4, 0x4a))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(320, 40)
	label.position = Vector2(-160, -144)
	actor.add_child(label)
	return actor


func _unhandled_input(event: InputEvent) -> void:
	if client.my_peer_id == 0:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		client.request_move(_layer.local_to_map(_layer.get_local_mouse_position()))


func _process(delta: float) -> void:
	_animate_actors(delta)
	_stream_chunks()
	if client.my_peer_id == 0:
		return
	var dir := KeyMove.direction(
			Input.is_physical_key_pressed(KEY_W), Input.is_physical_key_pressed(KEY_S),
			Input.is_physical_key_pressed(KEY_A), Input.is_physical_key_pressed(KEY_D))
	if dir == Vector2i.ZERO:
		if _key_dir != Vector2i.ZERO:
			client.request_stop()
		_key_dir = dir
		return
	var target := KeyMove.held_target(_my_pos, dir)
	if dir != _key_dir or target != _key_target:
		client.request_move(target)
	_key_dir = dir
	_key_target = target
