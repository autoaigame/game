## Draws the isometric map and the players; turns clicks and WASD into move requests.
extends Node2D

const TILES_TEX := preload("res://assets/tiles.png")
const PLAYER_TEX := preload("res://assets/player.png")

var client: Node  ## client/client.gd
var _layer: TileMapLayer
var _actors := {}  ## peer_id -> Node2D
var _camera := Camera2D.new()
var _my_pos := Vector2.ZERO  ## my position in the last snapshot, in cells
var _key_dir := Vector2i.ZERO  ## direction of the held keys at the last frame
var _key_target := Vector2i.ZERO  ## last target sent for the held keys


func _ready() -> void:
	y_sort_enabled = true
	_layer = IsoLayer.new_layer(TILES_TEX)
	_layer.z_index = -1
	add_child(_layer)
	for y in MapData.SIZE.y:
		for x in MapData.SIZE.x:
			_layer.set_cell(Vector2i(x, y), 0, Vector2i(MapData.tile_at(Vector2i(x, y)), 0))
	_camera.zoom = Vector2(3, 3)
	_camera.position_smoothing_enabled = true
	add_child(_camera)
	_camera.position = IsoLayer.cell_to_local(Vector2(MapData.spawn_cell()))
	client.snapshot_received.connect(_on_snapshot)


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
		var target := IsoLayer.cell_to_local(p["pos"])
		var sprite: Sprite2D = actor.get_node("Sprite")
		var delta := target - actor.position
		if delta.length() > 0.5:
			sprite.frame_coords = Vector2i(_dir_column(delta), (sprite.frame_coords.y + 1) % 2)
		actor.position = target
		if id == client.my_peer_id:
			_my_pos = p["pos"]
			_camera.position = target
	for id in _actors.keys():
		if not seen.has(id):
			_actors[id].queue_free()
			_actors.erase(id)


func _make_actor(player_name: String, is_me: bool) -> Node2D:
	var actor := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = PLAYER_TEX
	sprite.hframes = 4
	sprite.vframes = 2
	sprite.offset = Vector2(0, -10)
	actor.add_child(sprite)
	var label := Label.new()
	label.text = player_name
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color.WHITE if not is_me else Color8(0xe8, 0xc4, 0x4a))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 10)
	label.position = Vector2(-40, -36)
	actor.add_child(label)
	return actor


## Sprite column from screen movement: 0 down, 1 left, 2 right, 3 up.
func _dir_column(delta: Vector2) -> int:
	if absf(delta.x) > absf(delta.y) * 2.0:
		return 1 if delta.x < 0 else 2
	return 3 if delta.y < 0 else 0


func _unhandled_input(event: InputEvent) -> void:
	if client.my_peer_id == 0:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		client.request_move(_layer.local_to_map(_layer.get_local_mouse_position()))


func _process(_delta: float) -> void:
	if client.my_peer_id == 0:
		return
	var dir := KeyMove.direction(
			Input.is_physical_key_pressed(KEY_W), Input.is_physical_key_pressed(KEY_S),
			Input.is_physical_key_pressed(KEY_A), Input.is_physical_key_pressed(KEY_D))
	if dir == Vector2i.ZERO:
		if _key_dir != Vector2i.ZERO:
			client.request_move(KeyMove.release_target(_my_pos, _key_dir))
		_key_dir = dir
		return
	var target := KeyMove.held_target(_my_pos, dir)
	if dir != _key_dir or target != _key_target:
		client.request_move(target)
	_key_dir = dir
	_key_target = target
