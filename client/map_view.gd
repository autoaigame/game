## Draws a WorldMap (client/world_map.gd) around `center`, in the game's isometric orientation: a cell is
## a diamond `zoom` px tall and twice as wide, so the map turns like the world on screen. Unexplored
## cells stay dark. Markers (players) are dots: me in gold, the others in white. The mouse wheel over
## the map zooms it (and not the camera). Used for the minimap and the big map (client/hud.gd).
class_name MapView
extends Control

const NOTCH := 1.25  ## one wheel notch scales the zoom by this
const FOG := Color8(0x1f, 0x22, 0x1a)
const ME := Color8(0xe8, 0xc4, 0x4a)
const OTHER := Color8(0xd3, 0xcc, 0xb7)
const RIM := Color8(0x1f, 0x22, 0x1a)
const DOT_PX := 3.5

var world_map: WorldMap
var min_zoom: float
var max_zoom: float
var zoom: float  ## screen px per cell (vertically; a cell is twice as wide)
var center := Vector2.ZERO  ## the cell at the middle of the view
var markers: Array = []  ## [{pos: Vector2 (cells), me: bool}]
var _textures := {}  ## chunk -> ImageTexture of world_map.chunk_image()


func _init(map: WorldMap, min_z: float, max_z: float, z: float) -> void:
	world_map = map
	min_zoom = min_z
	max_zoom = max_z
	zoom = z
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Screen position (in a view of `size`) of position `pos` (cells).
static func to_screen(pos: Vector2, at: Vector2, z: float, view_size: Vector2) -> Vector2:
	return view_size / 2.0 + _iso(pos - at) * z


## The position (cells) under screen point `p`: the inverse of to_screen.
static func to_cell(p: Vector2, at: Vector2, z: float, view_size: Vector2) -> Vector2:
	var v := (p - view_size / 2.0) / z
	return at + Vector2(v.y + v.x / 2.0, v.y - v.x / 2.0)


static func _iso(v: Vector2) -> Vector2:
	return Vector2(v.x - v.y, (v.x + v.y) / 2.0)


## The map's chunks `chunks` changed: their pictures are rebuilt on the next draw.
func refresh(chunks: Array) -> void:
	for c in chunks:
		_textures.erase(c)
	queue_redraw()


## Forgets every picture (a new map was loaded).
func refresh_all() -> void:
	_textures.clear()
	queue_redraw()


func set_view(at: Vector2, list: Array) -> void:
	if at == center and list == markers:
		return
	center = at
	markers = list
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var steps := CameraZoom.wheel_steps(event.button_index, event.factor)
	if steps == 0.0:
		return
	zoom = clampf(zoom * pow(NOTCH, steps), min_zoom, max_zoom)
	queue_redraw()
	accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FOG)
	# Cell space -> screen: x goes right-down, y left-down. A chunk picture's pixel (x, y) is the cell
	# whose centre is at (x, y), so it covers [x - 0.5, x + 0.5).
	var origin := to_screen(Vector2.ZERO, center, zoom, size)
	draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.5) * zoom, Vector2(-1.0, 0.5) * zoom, origin))
	var corners := [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in corners:
		var cell := to_cell(p, center, zoom, size)
		lo = lo.min(cell)
		hi = hi.max(cell)
	var c_lo := MapData.chunk_of(Vector2i(floori(lo.x), floori(lo.y)))
	var c_hi := MapData.chunk_of(Vector2i(ceili(hi.x), ceili(hi.y)))
	for cy in range(c_lo.y, c_hi.y + 1):
		for cx in range(c_lo.x, c_hi.x + 1):
			var c := Vector2i(cx, cy)
			if not world_map.has_chunk(c):
				continue
			var tex: ImageTexture = _textures.get(c)
			if tex == null:
				tex = ImageTexture.create_from_image(world_map.chunk_image(c))
				_textures[c] = tex
			draw_texture_rect(tex, Rect2(Vector2(c * MapData.CHUNK) - Vector2(0.5, 0.5),
					Vector2(MapData.CHUNK, MapData.CHUNK)), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for m in markers:
		if not m["me"]:
			_dot(m["pos"], OTHER)
	for m in markers:
		if m["me"]:
			_dot(m["pos"], ME)


func _dot(pos: Vector2, color: Color) -> void:
	var p := to_screen(pos, center, zoom, size)
	draw_circle(p, DOT_PX + 1.5, RIM)
	draw_circle(p, DOT_PX, color)
