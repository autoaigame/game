## A dog drawn with simple shapes until the dog sprite sheet exists. Faces right; the view mirrors it.
class_name DogPlaceholder
extends Node2D

const FUR := Color8(0x8a, 0x6a, 0x4a)
const FUR_DARK := Color8(0x5e, 0x46, 0x30)
const SHADOW := Color(0, 0, 0, 0.25)


func _draw() -> void:
	_ellipse(Vector2(0, 0), Vector2(20, 7), SHADOW)
	draw_line(Vector2(-10, -8), Vector2(-11, 0), FUR_DARK, 3.0)  # back legs
	draw_line(Vector2(-6, -8), Vector2(-6, 0), FUR_DARK, 3.0)
	draw_line(Vector2(7, -8), Vector2(7, 0), FUR_DARK, 3.0)  # front legs
	draw_line(Vector2(11, -8), Vector2(12, 0), FUR_DARK, 3.0)
	_ellipse(Vector2(0, -14), Vector2(15, 8), FUR)  # body
	draw_line(Vector2(-14, -17), Vector2(-21, -26), FUR, 3.0)  # tail
	_ellipse(Vector2(16, -24), Vector2(8, 7), FUR)  # head
	_ellipse(Vector2(23, -21), Vector2(4, 3), FUR_DARK)  # muzzle
	_ellipse(Vector2(12, -29), Vector2(3, 5), FUR_DARK)  # ear
	draw_circle(Vector2(18, -26), 1.2, Color.BLACK)  # eye


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, color)
