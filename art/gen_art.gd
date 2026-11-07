## Generates the game's pixel art. Deterministic: same script, same PNGs.
## Usage: godot --headless --path . -s res://art/gen_art.gd   (or: make art)
extends SceneTree

## Color ramps, dark to light, hue-shifted: shadows lean cool, highlights warm (see docs/art-guide.md).
const GRASS := ["1b3a2f", "24502f", "306a32", "438a37", "62a83c", "8cc84a", "bde46a"]
const DIRT := ["3f2a26", "5e3d2e", "7f5537", "a06f43", "be8b55", "d9a96f", "efcf98"]
const WATER := ["0f2547", "15365f", "1b4c7c", "22669b", "3285b6", "53a9d1", "93d8ec", "e8fbff"]
const STONE := ["4a3a36", "6e5c52", "958274", "bba997", "e0d4c0"]
const SAND := ["5a4436", "7e6244", "a6844f", "c9a65f", "e2c47c", "f2dfa4", "fdf3cf"]
const DRY := ["3a3424", "5a5129", "7f722f", "a6953d", "c6b154", "dfcb76", "f1e5a6"]
const FOREST := ["101f1c", "17301f", "1f4224", "2b5628", "3d6c2e", "5b8a3a"]
const SKIN := ["6b3d33", "a8634a", "d18f68", "efb98d", "fdd9b0"]
const HAIR := ["24150f", "3e2416", "5c3620", "7f4e2c", "a5703e"]
const TUNIC := ["3a1630", "62203b", "922f46", "c24450", "e7695d", "f79c80"]
const PANTS := ["171628", "25233d", "363458", "4c4a74"]
const BOOTS := ["1f1410", "3d2619", "5c3b24", "7d5534"]
const GOLD := ["7a4a17", "c08a2c", "f0c94e", "fff2a8"]
const FLOWERS := ["f6f1e4", "f7d65a", "f39bb8", "b9a6f2", "f78f5e"]
const OUTLINE := "16101c"
const EYE_WHITE := "f4f1ea"
const EYE := "203a6b"
const SHADOW := Color(0.05, 0.03, 0.1, 0.38)

const SPRITE := Vector2i(64, 96)
const LIGHT := Vector3(-0.55, -0.65, 0.52)  ## from the top left, towards the viewer


func _initialize() -> void:
	_player().save_png("res://assets/player.png")
	DirAccess.make_dir_recursive_absolute("res://assets/decals")
	for id in DECALS:
		_decal(id).save_png("res://assets/decals/%s.png" % id)
	print("art: wrote assets/player.png and assets/decals/*.png (tiles and objects come from the PixelLab kit)")
	quit()


func _c(ramp: Array, i: int) -> Color:
	return Color.html(ramp[clampi(i, 0, ramp.size() - 1)])


## Deterministic hash in [0, 1).
func _hash(x: int, y: int, seed: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h % 100000) / 100000.0


## Lambert brightness in [0, 1] of a sphere-like surface at normalized offset n.
func _lum(n: Vector2) -> float:
	var z := sqrt(maxf(0.0, 1.0 - n.length_squared()))
	var normal := Vector3(n.x, n.y, z).normalized()
	return clampf(0.18 + 0.9 * maxf(0.0, normal.dot(LIGHT.normalized())), 0.0, 1.0)


# --- Decals ------------------------------------------------------------------
# Small flat details drawn over the ground (data/decals/<id>.json), centred on their position.
# Provisional, like the objects.

const DECALS := {"tuft": Vector2i(40, 28), "pebble": Vector2i(30, 16), "flowers": Vector2i(36, 22),
	"leaves": Vector2i(36, 20)}


func _decal(id: String) -> Image:
	var size: Vector2i = DECALS[id]
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var o := Vector2i.ZERO
	match id:
		"tuft":
			# a clump: dark base, blades fanning out, light tips
			for x in range(6, size.x - 6):
				_px(img, o, x, size.y - 1, Color(SHADOW, 0.6))
				_px(img, o, x, size.y - 2, _c(GRASS, 1))
			for k in 13:
				var x := 6 + k * 2
				var tall := 10 + int(_hash(k, 0, 81) * 14) - absi(k - 6)
				var lean := (k - 6) / 2
				for j in tall:
					var shade := 1 + int(float(j) / tall * 5.0)
					var px := clampi(x + (lean * j) / maxi(tall / 2, 1), 0, size.x - 1)
					_px(img, o, px, size.y - 3 - j, _c(GRASS, shade))
		"pebble":
			_blob(img, o, 9, 8, 7, 5, STONE, 2.2)
			_blob(img, o, 21, 9, 5, 4, STONE, 2.2, -0.05)
			_blob(img, o, 15, 12, 3, 2.5, STONE, 2.2, -0.1)
			for x in range(3, size.x - 3):
				if img.get_pixel(x, size.y - 2).a == 0.0:
					_px(img, o, x, size.y - 2, Color(SHADOW, 0.5))
		"flowers":
			for k in 5:
				var x := 4 + int(_hash(k, 0, 83) * (size.x - 8))
				var y := 4 + int(_hash(k, 1, 83) * (size.y - 10))
				var petal := Color.html(FLOWERS[k % FLOWERS.size()])
				for j in 4:
					_px(img, o, x, y + 2 + j, _c(GRASS, 2 + j % 2))  # stem
				_px(img, o, x + 1, y + 4, _c(GRASS, 4))  # leaf
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if absi(dx) + absi(dy) > 0:
							_px(img, o, x + dx, y + dy, petal)
				_px(img, o, x - 1, y + 2, _c(GRASS, 1))
				_px(img, o, x, y, _c(GOLD, 2))
		"leaves":
			for k in 9:
				var x := 2 + int(_hash(k, 0, 82) * (size.x - 6))
				var y := 2 + int(_hash(k, 1, 82) * (size.y - 5))
				var col := _c(DIRT, 3 + k % 3) if k % 4 else _c(GOLD, 1)
				for p in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, -1)]:
					_px(img, o, x + p.x, y + p.y, col)
				_px(img, o, x + 1, y + 1, _c(DIRT, 1))
				_px(img, o, x + 2, y + 1, _c(DIRT, 1))
	return img


# --- Characters --------------------------------------------------------------


## Poses, one per row of player.png: standing, then a walk cycle of two steps (WalkAnim.WALK_FRAMES).
## Facing the camera or away: l, r = how far each leg is lifted (px, negative = reaching forward,
## nearer the viewer), arm = arm swing. Side view: fx, bx = front and back leg moved forward (px),
## fl, bl = front and back foot lifted, arm = front arm swing. bob = body raised (passing frames).
const POSES := [
	{"l": 0, "r": 0, "arm": 0, "fx": 0, "bx": 0, "fl": 0, "bl": 0, "bob": 0},  # standing
	{"l": -2, "r": 2, "arm": 3, "fx": 6, "bx": -5, "fl": 0, "bl": 2, "bob": 0},  # left foot forward
	{"l": 0, "r": 5, "arm": 1, "fx": 1, "bx": 1, "fl": 0, "bl": 5, "bob": 1},  # right leg passes
	{"l": 2, "r": -2, "arm": -3, "fx": -5, "bx": 6, "fl": 2, "bl": 0, "bob": 0},  # right foot forward
	{"l": 5, "r": 0, "arm": -1, "fx": -1, "bx": -1, "fl": 5, "bl": 0, "bob": 1},  # left leg passes
]


func _player() -> Image:
	# 4 directions (columns: down, left, right, up) x POSES (rows)
	var img := Image.create_empty(SPRITE.x * 4, SPRITE.y * POSES.size(), false, Image.FORMAT_RGBA8)
	for row in POSES.size():
		for dir in [0, 1, 3]:
			_draw_char(img, Vector2i(dir * SPRITE.x, row * SPRITE.y), dir, POSES[row])
		_mirror(img, Vector2i(SPRITE.x, row * SPRITE.y), Vector2i(2 * SPRITE.x, row * SPRITE.y))
	return img


## Right-facing frames are the left-facing ones mirrored.
func _mirror(img: Image, from: Vector2i, to: Vector2i) -> void:
	for y in SPRITE.y:
		for x in SPRITE.x:
			img.set_pixel(to.x + SPRITE.x - 1 - x, to.y + y, img.get_pixel(from.x + x, from.y + y))


## Shaded blob: a superellipse (p = 2 ellipse, larger = boxier) lit like a dome.
func _blob(img: Image, o: Vector2i, cx: float, cy: float, rx: float, ry: float, ramp: Array,
		p := 2.0, bias := 0.0) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var n := Vector2((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
			if pow(absf(n.x), p) + pow(absf(n.y), p) > 1.0:
				continue
			var lum := _lum(n.limit_length(0.98)) + bias
			img.set_pixel(o.x + x, o.y + y, _c(ramp, int(lum * (ramp.size() - 1.1))))


## Vertical cylinder (limbs): lit from the left.
func _limb(img: Image, o: Vector2i, x0: int, y0: int, w: int, h: int, ramp: Array, bias := 0.0) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var nx := (x + 0.5 - x0) / w * 2.0 - 1.0
			var lum := _lum(Vector2(nx * 0.95, -0.1)) + bias
			img.set_pixel(o.x + x, o.y + y, _c(ramp, int(lum * (ramp.size() - 1.1))))


func _px(img: Image, o: Vector2i, x: int, y: int, col: Color) -> void:
	img.set_pixel(o.x + x, o.y + y, col)


func _draw_char(img: Image, o: Vector2i, dir: int, pose: Dictionary) -> void:
	if dir == 1:
		_draw_side(img, o, pose)
	else:
		_draw_front_back(img, o, dir == 3, pose)
	_outline(img, o)
	_shadow(img, o)


func _draw_front_back(img: Image, o: Vector2i, back: bool, pose: Dictionary) -> void:
	var bob: int = pose["bob"]
	var l: int = pose["l"]
	var r: int = pose["r"]
	var arm: int = pose["arm"]
	# legs and boots: a lifted leg is shorter, a leg reaching forward a little longer
	_limb(img, o, 23, 64, 8, 20 - l, PANTS)
	_limb(img, o, 33, 64, 8, 20 - r, PANTS, -0.1)
	_blob(img, o, 27, 85 - l, 5.5, 4, BOOTS, 3.0)
	_blob(img, o, 37, 85 - r, 5.5, 4, BOOTS, 3.0, -0.1)
	# arms swing opposite to the legs, behind the torso edges
	_limb(img, o, 12, 43 - bob + arm, 7, 17, TUNIC, 0.05)
	_limb(img, o, 45, 46 - bob - arm, 7, 17, TUNIC, -0.15)
	_blob(img, o, 15.5, 62 - bob + arm, 3.6, 3.4, SKIN)
	_blob(img, o, 48.5, 65 - bob - arm, 3.6, 3.4, SKIN, 2.0, -0.1)
	# torso with a hem, belt and buckle
	_blob(img, o, 32, 53 - bob, 14, 15, TUNIC, 3.5)
	for x in range(19, 46):
		_px(img, o, x, 59 - bob, _c(BOOTS, 1))
		_px(img, o, x, 60 - bob, _c(BOOTS, 2))
		_px(img, o, x, 61 - bob, _c(BOOTS, 1))
	if not back:
		_blob(img, o, 32, 60.5 - bob, 3, 2.5, GOLD, 4.0)
		for y in range(41, 49):  # collar opening
			for x in range(32 - (49 - y) / 2, 32 + (49 - y) / 2):
				_px(img, o, x, y - bob, _c(TUNIC, 1))
	# neck and head
	_limb(img, o, 28, 35 - bob, 8, 6, SKIN, -0.2)
	_blob(img, o, 32, 25 - bob, 13.5, 13, SKIN, 2.0, 0.34)
	# hair: a cap with a jagged fringe in front, a full mop at the back
	_blob(img, o, 32, 18 - bob, 15, 10, HAIR, 2.2, 0.1)
	if back:
		_blob(img, o, 32, 25 - bob, 14.5, 13, HAIR, 2.4, 0.05)
		for x in range(20, 45):
			if (x / 3) % 2 == 0:
				_px(img, o, x, 38 - bob, _c(HAIR, 1))
		return
	for x in range(18, 47):
		var drop := 20 + int((x / 3) % 2) * 2 + (2 if x < 22 or x > 42 else 0)
		for y in range(12, drop):
			var n := Vector2((x + 0.5 - 32) / 15.0, (y + 0.5 - 18) / 12.0)
			if n.length_squared() <= 1.0:
				_px(img, o, x, y - bob, _c(HAIR, int((_lum(n) + 0.1) * 4.6)))
	_eye(img, o, 25, 25 - bob)
	_eye(img, o, 36, 25 - bob)
	for x in range(30, 35):  # mouth
		_px(img, o, x, 32 - bob, _c(SKIN, 1))
	_px(img, o, 30, 31 - bob, _c(SKIN, 2))
	_px(img, o, 34, 31 - bob, _c(SKIN, 2))
	for x in [21, 22, 41, 42]:  # cheeks
		_px(img, o, x, 30 - bob, Color.html(TUNIC[4]).lerp(Color.html(SKIN[3]), 0.5))


## A 4x4 eye: white, iris, pupil and a catch-light.
func _eye(img: Image, o: Vector2i, x: int, y: int) -> void:
	for dy in 4:
		for dx in 4:
			_px(img, o, x + dx, y + dy, Color.html(EYE_WHITE))
	for dy in range(0, 4):
		for dx in range(1, 4):
			_px(img, o, x + dx, y + dy, Color.html(EYE))
	_px(img, o, x + 2, y + 2, Color.html(OUTLINE))
	_px(img, o, x + 2, y + 3, Color.html(OUTLINE))
	_px(img, o, x + 1, y + 1, Color.html(EYE_WHITE))
	for dx in 4:  # brow
		_px(img, o, x + dx, y - 2, _c(HAIR, 1))


func _draw_side(img: Image, o: Vector2i, pose: Dictionary) -> void:
	var bob: int = pose["bob"]
	var fx: int = pose["fx"]
	var bx: int = pose["bx"]
	var arm: int = pose["arm"]
	# facing left (forward = towards smaller x). back leg and arm first, darker
	_limb(img, o, 30 - bx, 64, 8, 20 - pose["bl"], PANTS, -0.2)
	_blob(img, o, 32 - bx, 85 - pose["bl"], 6, 4, BOOTS, 3.0, -0.15)
	_limb(img, o, 36 - arm, 43 - bob, 7, 16, TUNIC, -0.25)
	# torso
	_blob(img, o, 33, 53 - bob, 11, 15, TUNIC, 3.5)
	for x in range(23, 44):
		_px(img, o, x, 59 - bob, _c(BOOTS, 1))
		_px(img, o, x, 60 - bob, _c(BOOTS, 2))
		_px(img, o, x, 61 - bob, _c(BOOTS, 1))
	_blob(img, o, 24.5, 60.5 - bob, 2.2, 2.5, GOLD, 4.0)
	# front leg, and the front arm swinging opposite to it
	_limb(img, o, 26 - fx, 64, 8, 20 - pose["fl"], PANTS)
	_blob(img, o, 28 - fx, 85 - pose["fl"], 6.5, 4, BOOTS, 3.0)
	_limb(img, o, 30 + arm, 43 - bob, 7, 16, TUNIC, 0.1)
	_blob(img, o, 33.5 + arm, 61 - bob, 3.6, 3.4, SKIN)
	# neck, head, nose
	_limb(img, o, 29, 35 - bob, 8, 6, SKIN, -0.2)
	_blob(img, o, 31, 25 - bob, 12.5, 13, SKIN, 2.0, 0.34)
	_blob(img, o, 18.5, 27 - bob, 2.2, 2, SKIN, 2.0, 0.1)
	# hair over the top and down the back, an ear in front of it
	_blob(img, o, 33, 18 - bob, 14, 10, HAIR, 2.2, 0.1)
	_blob(img, o, 39, 26 - bob, 8, 12, HAIR, 2.6, -0.05)
	for x in range(18, 30):
		var drop := 20 + int((x / 3) % 2) * 2
		for y in range(12, drop):
			var n := Vector2((x + 0.5 - 33) / 14.0, (y + 0.5 - 18) / 12.0)
			if n.length_squared() <= 1.0:
				_px(img, o, x, y - bob, _c(HAIR, int((_lum(n) + 0.1) * 4.6)))
	_blob(img, o, 35, 27 - bob, 2.6, 3.4, SKIN, 2.0, -0.05)
	_px(img, o, 35, 27 - bob, _c(SKIN, 1))
	# one eye looking left
	for dy in 4:
		for dx in 3:
			_px(img, o, 21 + dx, 25 - bob + dy, Color.html(EYE_WHITE) if dx == 2 else Color.html(EYE))
	_px(img, o, 21, 27 - bob, Color.html(OUTLINE))
	_px(img, o, 21, 28 - bob, Color.html(OUTLINE))
	_px(img, o, 22, 26 - bob, Color.html(EYE_WHITE))
	for dx in 4:
		_px(img, o, 20 + dx, 23 - bob, _c(HAIR, 1))
	for x in range(20, 24):
		_px(img, o, x, 32 - bob, _c(SKIN, 1))
	_px(img, o, 25, 30 - bob, Color.html(TUNIC[4]).lerp(Color.html(SKIN[3]), 0.5))


## A 1 px outline around the figure, tinted by the color it borders.
func _outline(img: Image, o: Vector2i) -> void:
	var edge := {}
	for y in SPRITE.y:
		for x in SPRITE.x:
			if img.get_pixel(o.x + x, o.y + y).a > 0.0:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + n
				if p.x < 0 or p.y < 0 or p.x >= SPRITE.x or p.y >= SPRITE.y:
					continue
				var inner := img.get_pixel(o.x + p.x, o.y + p.y)
				if inner.a > 0.0:
					edge[Vector2i(x, y)] = Color.html(OUTLINE).lerp(inner, 0.18)
					break
	for p in edge:
		img.set_pixel(o.x + p.x, o.y + p.y, edge[p])


## A soft translucent ground shadow under the feet.
func _shadow(img: Image, o: Vector2i) -> void:
	for y in range(84, 95):
		for x in range(10, 54):
			var n := Vector2((x + 0.5 - 32.0) / 21.0, (y + 0.5 - 90.0) / 4.5)
			if n.length_squared() <= 1.0 and img.get_pixel(o.x + x, o.y + y).a == 0.0:
				img.set_pixel(o.x + x, o.y + y, SHADOW)
