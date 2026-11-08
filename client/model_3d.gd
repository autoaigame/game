## A 3D model rendered as pixel art: the model alone in a small SubViewport, one texel per screen pixel,
## seen by an orthographic camera at the game's 2:1 angle, lit in flat bands and snapped to the palette
## (client/pixel_3d_lit.gdshader), then drawn as a Sprite2D that adds a 1 px outline
## (client/pixel_3d.gdshader), with a ground shadow and a see-through silhouette where something covers
## it (client/pixel_3d_ghost.gdshader). The model never moves inside its viewport (the Sprite2D moves, on
## whole pixels), so walking never shimmers; only turning and the animation change texels.
## Every model shares one scale: metres in the glTF, HEAD_PX for the top of the player body's head.
## A subclass builds the model (_build_model) and poses it (_animate); Character3D draws players and
## Dog3D the cyborg dogs. Display only: positions come from the server (docs/invariants.md, rule 1).
class_name Model3D
extends Node2D

const PALETTE_JSON := "res://data/palette.json"
## The player body's clips: its height sets the scale of every model.
const SCALE_CLIPS := "res://assets/character/body_clips.json"
const SHADER := "res://client/pixel_3d.gdshader"
const GHOST_SHADER := "res://client/pixel_3d_ghost.gdshader"
const LIT_SHADER := "res://client/pixel_3d_lit.gdshader"
## Most palette colours the shaders take (uniform array size).
const MAX_COLOURS := 64
## The render codes a palette index in red (red_code); the 2D pass reads it back (red_index). The
## Compatibility renderer gives every red under 56 back lower (8 comes back 2, 18 comes back 14: an
## approximate sRGB round trip), so the codes start at 56, where it gives them back unchanged.
const RED_BASE := 56
const RED_STEP := 3
## Default viewport size in texels, and where the feet stand in it (a subclass may set others).
const VIEW_SIZE := Vector2i(112, 128)
const FOOT_PX := 14
## Screen height of the top of the player body's head: a little under WalkAnim.HEAD_PX (the name sits
## above that), so the body does not look heavier than the former sprite.
const HEAD_PX := 100.0
## Camera elevation of the game's 2:1 view: asin(1/2).
const ELEVATION_DEG := 30.0
## Turning speed, degrees per second.
const TURN_DEG_S := 540.0

## Look of the render. Light in TOON_LEVELS flat bands; the shaded side at AMBIENT of the colour, the lit
## side at AMBIENT + SUN; HUE_LOCK keeps each surface on palette colours of its own hue (without it, skin
## falls on sand or grey-green: the palette has few skin tones).
const TOON_LEVELS := 3
const AMBIENT := 0.7
const SUN := 0.6
const HUE_LOCK := 30.0
## Light from the screen's left and a little from the front (world space, towards the light): the side
## facing the camera is lit.
const LIGHT_DIR := Vector3(-0.17, 0.766, 0.62)
## Ground shadow: an ellipse like the objects' shadows, pushed away from the top-left light.
const SHADOW_SIZE := Vector2(38.0, 14.0)
const SHADOW_SHIFT := Vector2(5.0, 2.0)
const SHADOW_COLOR := Color8(20, 22, 16, 97)  ## the objects' shadow colour and opacity

static var _palette := PackedColorArray()
static var _dark_of := PackedInt32Array()
static var _scale_height := 0.0

var view_size := VIEW_SIZE
var foot_px := FOOT_PX
var shadow_size := SHADOW_SIZE
var px_per_m := 0.0  ## texels per metre: the player body's head lands HEAD_PX above the feet
var cell_m := 0.0  ## metres per game cell at that scale
var yaw := PI / 4.0  ## facing, radians around +Y (0 = towards +Z = cell +y; PI/4 faces the camera)
var target_yaw := PI / 4.0

var viewport: SubViewport
var sprite: Sprite2D
var camera: Camera3D
var _pivot: Node3D
var _model: Node3D
var _materials: Array[ShaderMaterial] = []
var _shadow: Polygon2D
var silhouette := true  ## whether _ghost is drawn (show_silhouette)
var _ghost: Sprite2D  ## silhouette copy drawn above the world, where a tree hides the model


## Height (m) of the player body, the reference of the shared scale.
static func scale_height() -> float:
	if _scale_height == 0.0:
		_scale_height = float(JSON.parse_string(FileAccess.get_file_as_string(SCALE_CLIPS))["height_m"])
	return _scale_height


## Texels per metre of every model.
static func world_px_per_m() -> float:
	return HEAD_PX / (scale_height() * cos(deg_to_rad(ELEVATION_DEG)))


## The palette (data/palette.json), every ramp in file order: the colours the 3D render may use.
static func palette() -> PackedColorArray:
	if _palette.is_empty():
		var rec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_JSON))
		for ramp in rec["ramps"]:
			for hex in rec["ramps"][ramp]:
				_palette.append(Color.html(hex))
	return _palette


## Yaw (radians around +Y) of a movement in cells: cell x is 3D +X, cell y is 3D +Z, the model faces +Z.
static func yaw_of(cell_delta: Vector2) -> float:
	return atan2(cell_delta.x, cell_delta.y)


## Next yaw towards a target at most max_step radians, the short way; a half-turn turns through the side
## facing the camera (yaw PI/4, towards cell (+1, +1)).
static func turn_towards(from: float, to: float, max_step: float) -> float:
	var d := angle_difference(from, to)
	if absf(absf(d) - PI) < 0.01:
		var to_cam := angle_difference(from, PI / 4.0)
		d = absf(d) * (1.0 if to_cam >= 0.0 else -1.0)
	if absf(d) <= max_step:
		return wrapf(from + d, -PI, PI)
	return wrapf(from + signf(d) * max_step, -PI, PI)


## For each palette colour, a darker one of a close hue (inner lines): the nearest palette colour to the
## colour scaled by 0.62, among the darker ones (itself when none is darker).
static func dark_of() -> PackedInt32Array:
	if not _dark_of.is_empty():
		return _dark_of
	var pal := palette()
	for i in pal.size():
		var c := pal[i]
		var target := Color(c.r * 0.62, c.g * 0.62, c.b * 0.62)
		var best := i
		var best_e := INF
		for j in pal.size():
			if pal[j].get_luminance() >= c.get_luminance() - 0.02:
				continue
			var e := redmean(pal[j], target)
			if e < best_e:
				best_e = e
				best = j
		_dark_of.append(best)
	return _dark_of


## Weighted RGB distance, close enough to perceptual for a small palette.
static func redmean(a: Color, b: Color) -> float:
	var r := (a.r + b.r) * 0.5
	return (2.0 + r) * pow(a.r - b.r, 2) + 4.0 * pow(a.g - b.g, 2) + (3.0 - r) * pow(a.b - b.b, 2)


## The red byte pixel_3d_lit.gdshader writes for a palette index: the middle of its step.
static func red_code(index: int) -> int:
	return RED_BASE + index * RED_STEP + RED_STEP / 2


## The palette index pixel_3d.gdshaderinc reads from a red byte of the render.
static func red_index(red: float) -> int:
	return clampi(floori((red - RED_BASE) / RED_STEP), 0, MAX_COLOURS - 1)


## The palette as shader uniforms: colours padded to MAX_COLOURS, and its size.
static func palette_uniform() -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in palette():
		out.append(Vector3(c.r, c.g, c.b))
	out.resize(MAX_COLOURS)
	return out


static func _dark_uniform() -> PackedInt32Array:
	var out := dark_of().duplicate()
	out.resize(MAX_COLOURS)
	return out


func _init() -> void:
	px_per_m = world_px_per_m()
	cell_m = Vector2(IsoLayer.TILE_SIZE).x / (sqrt(2.0) * px_per_m)


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = view_size
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	# No lights: pixel_3d_lit.gdshader lights each surface itself. The environment keeps the output as
	# written (linear tonemap): without one, colours come out lighter.
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(env)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = view_size.y / px_per_m
	camera.near = 0.1
	camera.far = 20.0
	var el := deg_to_rad(ELEVATION_DEG)
	var back := Vector3(cos(el) / sqrt(2.0), sin(el), cos(el) / sqrt(2.0))
	camera.look_at_from_position(back * 8.0, Vector3.ZERO, Vector3.UP)
	camera.v_offset = (view_size.y / 2.0 - foot_px) / px_per_m
	viewport.add_child(camera)
	_pivot = Node3D.new()
	viewport.add_child(_pivot)
	_build_model()
	sprite = _view_sprite(SHADER)
	_shadow = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * shadow_size.x / 2.0, sin(a) * shadow_size.y / 2.0).round())
	_shadow.polygon = pts
	_shadow.color = SHADOW_COLOR
	_shadow.position = SHADOW_SHIFT
	add_child(_shadow)
	add_child(sprite)
	# The silhouette is drawn after everything else (top_level, outside the y-sorting), placed by place().
	_ghost = _view_sprite(GHOST_SHADER)
	_ghost.top_level = true
	_ghost.visible = silhouette
	add_child(_ghost)
	_pose()


func _view_sprite(shader_path: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = viewport.get_texture()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.centered = false
	s.offset = Vector2(-view_size.x / 2.0, foot_px - view_size.y)
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	mat.set_shader_parameter("palette", palette_uniform())
	mat.set_shader_parameter("dark_of", _dark_uniform())
	mat.set_shader_parameter("red_base", RED_BASE)
	mat.set_shader_parameter("red_step", RED_STEP)
	s.material = mat
	return s


## Builds _model under _pivot (and calls _matte on it). Subclasses override it.
func _build_model() -> void:
	pass


## Poses the model for this frame (bones, blend). Subclasses override it.
func _animate() -> void:
	pass


## Each surface drawn by pixel_3d_lit.gdshader, in its own glTF colour; _decorate may add more (ramps,
## face textures).
func _matte(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(s)
			if m == null:
				m = mi.mesh.surface_get_material(s)
			var c: Color = m.albedo_color if m is BaseMaterial3D else Color.WHITE
			var sm := lit_material(c)
			_decorate(sm, mi, m)
			mi.set_surface_override_material(s, sm)


## Extra shader settings of a surface (sm) from its mesh and source material. Subclasses override it.
func _decorate(_sm: ShaderMaterial, _mi: MeshInstance3D, _m: Material) -> void:
	pass


## A material of pixel_3d_lit.gdshader in a colour (sRGB, as in the glTF material), with the render look.
func lit_material(colour: Color) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load(LIT_SHADER)
	sm.set_shader_parameter("albedo", colour)
	sm.set_shader_parameter("material_id", _materials.size() % 16)
	sm.set_shader_parameter("red_base", RED_BASE)
	sm.set_shader_parameter("red_step", RED_STEP)
	sm.set_shader_parameter("palette", palette_uniform())
	sm.set_shader_parameter("palette_size", palette().size())
	sm.set_shader_parameter("toon_levels", TOON_LEVELS)
	sm.set_shader_parameter("hue_lock", HUE_LOCK)
	sm.set_shader_parameter("ambient", AMBIENT)
	sm.set_shader_parameter("sun", SUN)
	sm.set_shader_parameter("light_dir", LIGHT_DIR.normalized())
	_materials.append(sm)
	return sm


## Faces this way at once (no turn).
func face(y: float) -> void:
	yaw = y
	target_yaw = y
	_pose()


## Turns towards target_yaw at TURN_DEG_S for dt seconds.
func turn(dt: float) -> void:
	yaw = turn_towards(yaw, target_yaw, deg_to_rad(TURN_DEG_S) * dt)


## Whether the silhouette is drawn where something covers the model. Off while the tree in front is
## faded (client/world_view.gd): the model shows through it, and the silhouette would wash it out.
func show_silhouette(on: bool) -> void:
	silhouette = on
	if _ghost != null:
		_ghost.visible = on


## Puts the feet at canvas_pos, snapped to whole screen pixels: parent_pos is where the parent node is,
## camera_pos the 2D camera's position (at zoom 1 a whole number of pixels from the screen).
func place(canvas_pos: Vector2, parent_pos := Vector2.ZERO, camera_pos := Vector2.ZERO) -> void:
	position = camera_pos + (canvas_pos - camera_pos).round() - parent_pos
	if _ghost != null and is_inside_tree():
		var p := get_parent()
		_ghost.global_position = p.get_global_transform() * position if p is Node2D else position


## Facing, the subclass's pose, and one new render of the viewport.
func _pose() -> void:
	if _model == null:
		return
	_pivot.rotation.y = yaw
	_animate()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
