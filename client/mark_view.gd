## A short-lived mark on the ground (a pee spot, a dug hole), drawn flat over the ground and its decals,
## under objects and creatures. The view fades it out over its last FADE_S seconds.
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

const KINDS: Array[String] = ["pee", "hole"]  ## the kinds _draw knows

var kind := ""


func _init() -> void:
	z_index = Z


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


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, color)
