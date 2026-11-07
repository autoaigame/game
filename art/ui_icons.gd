## Draws the bag's pixel art (run by `make art`): one ICON px icon per item (assets/items/<id>.png),
## the campfire and hunger icons (assets/ui/icon_fire.png, icon_hunger.png), and the 9-slice slot
## frames (assets/ui/slot.png, slot_selected.png). Same rules as the dog sheet: muted colours from
## the kit's palette, light from the top left, shading in flat steps, and a darker edge of the
## shape's own colour instead of a black outline.
extends RefCounted

const ICON := 32
const SLOT := 16  ## slot frames: 9-slice, SLOT_MARGIN px on each side
const SLOT_MARGIN := 5
const LIGHT := Vector2(-0.6, -0.8)

const BERRY := Color8(0x8c, 0x34, 0x46)
const LEAF := Color8(0x6b, 0x7a, 0x3e)
const STEM := Color8(0x5a, 0x40, 0x2a)
const RAW := Color8(0xb0, 0x48, 0x48)
const FAT := Color8(0xe0, 0xcf, 0xb4)
const COOKED := Color8(0x8a, 0x52, 0x2c)
const BONE := Color8(0xd8, 0xcf, 0xb8)
const WOOD := Color8(0x7a, 0x5c, 0x3a)
const STONE := Color8(0x7d, 0x78, 0x6e)
const FLAME_OUT := Color8(0xd9, 0x6a, 0x2a)
const FLAME_MID := Color8(0xf0, 0xa8, 0x3a)
const FLAME_IN := Color8(0xfb, 0xe0, 0x8a)
const SLOT_IN := Color8(0x2c, 0x31, 0x24)
const SLOT_SHADE := Color8(0x1f, 0x22, 0x1a)
const SLOT_LIT := Color8(0x4a, 0x50, 0x3b)
const SLOT_RIM := Color8(0x51, 0x43, 0x3a)
const SELECT := Color8(0xd3, 0xcc, 0xb7)
const SELECT_DIM := Color8(0xa3, 0x9b, 0x86)


## Every image this script draws: res:// path -> Image.
static func all() -> Dictionary:
	return {
		"res://assets/items/berries.png": berries(),
		"res://assets/items/raw_meat.png": raw_meat(),
		"res://assets/items/cooked_meat.png": cooked_meat(),
		"res://assets/items/sticks.png": sticks(),
		"res://assets/ui/icon_fire.png": fire(),
		"res://assets/ui/icon_hunger.png": cooked_meat(),
		"res://assets/ui/slot.png": slot(false),
		"res://assets/ui/slot_selected.png": slot(true),
	}


static func berries() -> Image:
	var px := {}
	_stroke(px, Vector2(17, 5), Vector2(15, 11), 1.6, STEM)
	_ball(px, Vector2(21, 6), Vector2(4.5, 2.5), LEAF)
	for c in [Vector2(11, 15), Vector2(19, 14), Vector2(15, 20), Vector2(23, 21), Vector2(9, 23), Vector2(17, 26)]:
		_ball(px, c, Vector2(4.6, 4.6), BERRY.darkened(0.5))  # each berry's own rim
		_ball(px, c, Vector2(3.7, 3.7), BERRY)
		px[Vector2i(roundi(c.x - 2), roundi(c.y - 2))] = BERRY.lightened(0.45)  # shine
	return _finish(px, ICON)


static func raw_meat() -> Image:
	var px := {}
	_ball(px, Vector2(16, 17), Vector2(12, 9), FAT)  # fat rim
	_ball(px, Vector2(15.5, 16.5), Vector2(10, 7.2), RAW)
	_stroke(px, Vector2(9, 15), Vector2(19, 19), 1.2, RAW.lightened(0.25))  # marbling
	_stroke(px, Vector2(13, 12), Vector2(20, 14), 1.0, RAW.lightened(0.25))
	_ball(px, Vector2(20, 18), Vector2(2.6, 2.6), BONE)
	return _finish(px, ICON)


static func cooked_meat() -> Image:
	var px := {}
	_stroke(px, Vector2(7, 25), Vector2(15, 17), 3.2, BONE)
	_ball(px, Vector2(6, 24), Vector2(2.6, 2.6), BONE)
	_ball(px, Vector2(8, 27), Vector2(2.6, 2.6), BONE)
	_ball(px, Vector2(19, 13), Vector2(9, 8), COOKED)
	_stroke(px, Vector2(15, 10), Vector2(19, 8), 1.0, COOKED.lightened(0.3))  # crisp highlight
	return _finish(px, ICON)


static func sticks() -> Image:
	var px := {}
	_stroke(px, Vector2(5, 24), Vector2(27, 9), 2.6, WOOD)
	_stroke(px, Vector2(6, 11), Vector2(26, 23), 2.6, WOOD.darkened(0.12))
	_stroke(px, Vector2(10, 27), Vector2(22, 5), 2.6, WOOD.lightened(0.1))
	_stroke(px, Vector2(18, 11), Vector2(21, 8), 1.2, LEAF)  # a twig's leaf
	return _finish(px, ICON)


static func fire() -> Image:
	var px := {}
	for i in 5:  # stones
		var a := PI * (0.1 + 0.2 * i)
		_ball(px, Vector2(16 + cos(a) * 11, 25 + sin(a) * 3), Vector2(3, 2.2), STONE)
	_stroke(px, Vector2(7, 25), Vector2(24, 21), 2.6, WOOD)
	_stroke(px, Vector2(8, 21), Vector2(25, 25), 2.6, WOOD.darkened(0.12))
	_flame(px, Vector2(16, 22), 7.0, 18.0, FLAME_OUT)
	_flame(px, Vector2(16, 22), 4.5, 12.0, FLAME_MID)
	_flame(px, Vector2(16, 22), 2.2, 6.0, FLAME_IN)
	return _finish(px, ICON)


## A recessed square: dark inside, shaded on its top-left edge (the light comes from the top left)
## and lit on its bottom-right one, in a 1 px wooden rim. Selected, the rim is light and doubled.
static func slot(selected: bool) -> Image:
	var img := Image.create(SLOT, SLOT, false, Image.FORMAT_RGBA8)
	img.fill(SELECT if selected else SLOT_RIM)
	if selected:
		img.fill_rect(Rect2i(1, 1, SLOT - 2, SLOT - 2), SELECT_DIM)
	img.fill_rect(Rect2i(2, 2, SLOT - 4, SLOT - 4), SLOT_LIT)
	img.fill_rect(Rect2i(2, 2, SLOT - 5, SLOT - 5), SLOT_SHADE)
	img.fill_rect(Rect2i(3, 3, SLOT - 6, SLOT - 6), SLOT_IN)
	return img


## A filled ellipse in three flat steps by how much its surface faces the light.
static func _ball(px: Dictionary, center: Vector2, r: Vector2, c: Color) -> void:
	for y in range(floori(center.y - r.y), ceili(center.y + r.y) + 1):
		for x in range(floori(center.x - r.x), ceili(center.x + r.x) + 1):
			var n := Vector2((x + 0.5 - center.x) / r.x, (y + 0.5 - center.y) / r.y)
			if n.length_squared() > 1.0:
				continue
			var lit := -n.dot(LIGHT)
			px[Vector2i(x, y)] = c.lightened(0.18) if lit > 0.45 else (c if lit > -0.3 else c.darkened(0.22))


## A thick line, lit along its upper side.
static func _stroke(px: Dictionary, a: Vector2, z: Vector2, width: float, c: Color) -> void:
	var steps := maxi(2, ceili(a.distance_to(z) * 2.0))
	var h := width / 2.0
	for i in steps + 1:
		var p := a.lerp(z, float(i) / steps)
		for dy in range(-ceili(h), ceili(h) + 1):
			for dx in range(-ceili(h), ceili(h) + 1):
				if Vector2(dx, dy).length() <= h:
					px[Vector2i(roundi(p.x + dx), roundi(p.y + dy))] = c.lightened(0.15) if dy < 0 else c


## A flame: a pointed drop standing on `base`, half_w wide each side and h high.
static func _flame(px: Dictionary, base: Vector2, half_w: float, h: float, c: Color) -> void:
	for y in range(floori(base.y - h), ceili(base.y) + 1):
		var t := (base.y - y) / h  # 0 at the base, 1 at the tip
		var w := half_w * (1.0 - t * t) * (0.7 + 0.6 * t * (1.0 - t))
		for x in range(floori(base.x - w), ceili(base.x + w) + 1):
			if absf(x + 0.5 - base.x) <= w:
				px[Vector2i(x, y)] = c


## The image of the drawn pixels, with a darker edge of each shape's own colour around it.
static func _finish(px: Dictionary, size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for p in px:
		if p.x >= 0 and p.y >= 0 and p.x < size and p.y < size:
			img.set_pixelv(p, px[p])
	var edge := {}
	for p in px:
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + n
			if not px.has(q) and not edge.has(q):
				edge[q] = (px[p] as Color).darkened(0.55)
	for q in edge:
		if q.x >= 0 and q.y >= 0 and q.x < size and q.y < size:
			img.set_pixelv(q, edge[q])
	return img
