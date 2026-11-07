## A short-lived mark on the ground (a pee spot, a dug hole, a campfire, a caught animal), drawn over the ground and its
## decals, under objects and creatures; a fire flickers. The view fades it out over its last FADE_S seconds.
class_name MarkView
extends Node2D

const FADE_S := 10.0
const Z := ChunkView.DECALS_Z + 1
const WET := Color(0.18, 0.16, 0.08, 0.35)
const WET_EDGE := Color(0.18, 0.16, 0.08, 0.18)
const SOIL := Color8(0x6b, 0x55, 0x3d)
const SOIL_LIGHT := Color8(0x86, 0x6c, 0x4e)
const HOLE := Color8(0x2e, 0x24, 0x1a)
const HOLE_IN := Color8(0x45, 0x36, 0x27)

const STONE := Color8(0x7d, 0x78, 0x6e)
const STONE_DARK := Color8(0x55, 0x51, 0x4a)
const LOG := Color8(0x5a, 0x40, 0x2a)
const FLAME_OUT := Color8(0xd9, 0x6a, 0x2a)
const FLAME_MID := Color8(0xf0, 0xa8, 0x3a)
const FLAME_IN := Color8(0xfb, 0xe0, 0x8a)
const FLICKER_HZ := 8.0

const KINDS: Array[String] = ["pee", "hole", "fire", "carcass_rabbit", "carcass_pheasant"]  ## the kinds _draw knows

var kind := ""
var _t := 0.0


func _init() -> void:
	z_index = Z


func _process(delta: float) -> void:
	if kind == "fire":
		_t += delta
		queue_redraw()


func _draw() -> void:
	match kind:
		"pee":
			_ellipse(Vector2.ZERO, Vector2(11, 5), WET_EDGE)
			_ellipse(Vector2(-1, 0), Vector2(8, 3.5), WET)
		"hole":
			_ellipse(Vector2(0, 1), Vector2(14, 6), SOIL)  # thrown soil around it
			_ellipse(Vector2(-3, -1), Vector2(6, 2), SOIL_LIGHT)
			_ellipse(Vector2(0, 0), Vector2(9, 4), HOLE)
			_ellipse(Vector2(1, 1), Vector2(6, 2.5), HOLE_IN)
		"fire":
			_draw_fire()
		"carcass_rabbit":  # lying on its side
			_ellipse(Vector2(0, 1), Vector2(9, 3), Color(0, 0, 0, 0.22))
			_ellipse(Vector2(-1, -2), Vector2(7, 3.5), AnimalView.FUR)
			_ellipse(Vector2(5, -3), Vector2(3, 2.5), AnimalView.FUR)
			_ellipse(Vector2(9, -2), Vector2(3.5, 1.2), AnimalView.FUR_DARK)  # ears flat
			_ellipse(Vector2(-7, -2), Vector2(2, 2), AnimalView.FUR_LIGHT)
		"carcass_pheasant":
			_ellipse(Vector2(0, 1), Vector2(9, 3), Color(0, 0, 0, 0.22))
			draw_line(Vector2(-4, -1), Vector2(-13, 1), AnimalView.PLUMAGE_DARK, 2)
			_ellipse(Vector2(0, -2), Vector2(6, 3.5), AnimalView.PLUMAGE)
			_ellipse(Vector2(7, -1), Vector2(2.2, 1.8), AnimalView.NECK)


func _draw_fire() -> void:
	for i in 8:  # a ring of stones
		var a := TAU * i / 8.0
		_ellipse(Vector2(cos(a) * 11, sin(a) * 5 + 1), Vector2(3, 2), STONE_DARK if i % 2 else STONE)
	draw_line(Vector2(-7, 2), Vector2(6, -1), LOG, 3)
	draw_line(Vector2(-6, -1), Vector2(7, 2), LOG, 3)
	var f := floori(_t * FLICKER_HZ)
	var h := 12.0 + (f % 3) * 2.0  # flame height steps
	var lean := float((f % 4) - 1.5)
	_flame(Vector2(0, 0), 6.0, h, lean, FLAME_OUT)
	_flame(Vector2(0, 0), 4.0, h * 0.7, lean * 0.6, FLAME_MID)
	_flame(Vector2(0, 0), 2.0, h * 0.4, lean * 0.3, FLAME_IN)


func _flame(base: Vector2, half_w: float, h: float, lean: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([base + Vector2(-half_w, 0), base + Vector2(-half_w * 0.5, -h * 0.5),
			base + Vector2(lean, -h), base + Vector2(half_w * 0.5, -h * 0.5), base + Vector2(half_w, 0)]), color)


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, color)
