## A small wild animal (server/wildlife.gd), drawn with shapes: a rabbit or a pheasant. It bobs as it
## hops, faster when it flees. Faces right; the world view flips it with scale.x. Display only.
class_name AnimalView
extends Node2D

const KINDS: Array[String] = ["rabbit", "pheasant"]  ## the kinds _draw knows
const HOP_PX := 4.0
const HOPS_PER_CELL := 1.5
const SHADOW := Color(0, 0, 0, 0.22)
const FUR := Color8(0x8a, 0x76, 0x60)
const FUR_DARK := Color8(0x6a, 0x58, 0x46)
const FUR_LIGHT := Color8(0xe8, 0xe0, 0xd2)
const EAR_IN := Color8(0xc9, 0x9a, 0x8a)
const EYE := Color8(0x1a, 0x14, 0x10)
const PLUMAGE := Color8(0xa8, 0x5c, 0x2c)
const PLUMAGE_DARK := Color8(0x6e, 0x3a, 0x1c)
const NECK := Color8(0x2f, 0x5e, 0x4a)
const WATTLE := Color8(0xc0, 0x30, 0x2a)
const BEAK := Color8(0xd8, 0xc0, 0x80)

var kind := ""
var hop := 0.0  ## how high it is in its hop, 0..1


## Updates its pose from how far it has moved in all (cells) and whether it moves now.
func set_motion(walked: float, moving: bool) -> void:
	var h := absf(sin(walked * HOPS_PER_CELL * PI)) if moving else 0.0
	if h != hop:
		hop = h
		queue_redraw()


func _draw() -> void:
	_ellipse(Vector2(0, 0), Vector2(8, 3), SHADOW)
	var up := Vector2(0, -hop * HOP_PX)
	match kind:
		"rabbit":
			_ellipse(up + Vector2(-1, -5), Vector2(7, 5), FUR)  # body
			_ellipse(up + Vector2(-7, -6), Vector2(2.5, 2.5), FUR_LIGHT)  # tail
			_ellipse(up + Vector2(5, -9), Vector2(3.5, 3), FUR)  # head
			_ellipse(up + Vector2(3, -15), Vector2(1.3, 4), FUR_DARK)  # ears
			_ellipse(up + Vector2(5, -15), Vector2(1.3, 4), FUR)
			_ellipse(up + Vector2(5, -15), Vector2(0.6, 2.8), EAR_IN)
			draw_rect(Rect2(up + Vector2(6, -10), Vector2(1, 1)), EYE)
			_ellipse(up + Vector2(-3, -1.5), Vector2(3, 1.5), FUR_DARK)  # hind foot
		"pheasant":
			draw_line(up + Vector2(-5, -6), up + Vector2(-14, -10), PLUMAGE_DARK, 2)  # tail
			_ellipse(up + Vector2(-1, -6), Vector2(6, 4.5), PLUMAGE)  # body
			_ellipse(up + Vector2(-2, -7), Vector2(3, 2), PLUMAGE_DARK)  # wing
			draw_line(up + Vector2(3, -8), up + Vector2(5, -13), NECK, 2.5)  # neck
			_ellipse(up + Vector2(5.5, -14), Vector2(2.2, 2), NECK)  # head
			_ellipse(up + Vector2(6, -13.5), Vector2(1, 1.2), WATTLE)
			draw_line(up + Vector2(7.5, -14), up + Vector2(9, -13.5), BEAK, 1)
			draw_line(Vector2(-1, -2) + up, Vector2(-1, 0), PLUMAGE_DARK, 1)  # legs
			draw_line(Vector2(1, -2) + up, Vector2(1, 0), PLUMAGE_DARK, 1)


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, color)
