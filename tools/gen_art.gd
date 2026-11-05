## Generates the game's pixel art. Deterministic: same script, same PNGs.
## Usage: godot --headless --path . -s res://tools/gen_art.gd   (or: make art)
extends SceneTree

## Color ramps, dark to light, hue-shifted: shadows lean cool, highlights warm (see docs/art-guide.md).
const GRASS := ["1b3a2f", "24502f", "306a32", "438a37", "62a83c", "8cc84a", "bde46a"]
const DIRT := ["3f2a26", "5e3d2e", "7f5537", "a06f43", "be8b55", "d9a96f", "efcf98"]
const WATER := ["0f2547", "15365f", "1b4c7c", "22669b", "3285b6", "53a9d1", "93d8ec", "e8fbff"]
const STONE := ["4a3a36", "6e5c52", "958274", "bba997", "e0d4c0"]
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

const TILE := Vector2i(128, 64)
const SPRITE := Vector2i(64, 96)
const LIGHT := Vector3(-0.55, -0.65, 0.52)  ## from the top left, towards the viewer
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


func _initialize() -> void:
	_tiles().save_png("res://assets/tiles.png")
	_player().save_png("res://assets/player.png")
	print("art: wrote assets/tiles.png and assets/player.png")
	quit()


func _c(ramp: Array, i: int) -> Color:
	return Color.html(ramp[clampi(i, 0, ramp.size() - 1)])


## Ramp index for a value in [0, 1], with 4x4 ordered dithering between steps.
func _pick(ramp: Array, v: float, x: int, y: int, lo := 0, hi := -1) -> int:
	if hi < 0:
		hi = ramp.size() - 1
	var d: float = (BAYER[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0 - 0.5
	return clampi(int(floor(lerpf(lo, hi + 1, clampf(v, 0.0, 0.999)) + d * 0.9)), lo, hi)


## Deterministic hash in [0, 1).
func _hash(x: int, y: int, seed: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h % 100000) / 100000.0


# --- Tiles -------------------------------------------------------------------
# Tiles sit on a lattice: neighbours are offset by (64, 32) and (-64, 32). In
# lattice coordinates (a, b) both offsets are steps of 1, so anything periodic in
# (a, b) joins seamlessly from one tile to the next, whatever the neighbours are.


func _lattice(x: float, y: float) -> Vector2:
	var dx := (x - TILE.x / 2.0) / TILE.x
	var dy := (y - TILE.y / 2.0) / TILE.y
	return Vector2(dx + dy, dy - dx)


## The texel of this tile that shows the lattice point of (x, y), or (-1, -1) if
## the shift would not land inside the tile (cannot happen for the diamond domain).
func _wrap(x: int, y: int) -> Vector2i:
	var l := _lattice(x + 0.5, y + 0.5)
	var na := roundi(l.x)
	var nb := roundi(l.y)
	return Vector2i(x - (na - nb) * TILE.x / 2, y - (na + nb) * TILE.y / 2)


func _inside(x: int, y: int) -> bool:
	var l := _lattice(x + 0.5, y + 0.5)
	return absf(l.x) < 0.5 and absf(l.y) < 0.5


## Smooth value noise, periodic over one tile in lattice space. cells = grid per tile.
func _vnoise(x: int, y: int, cells: int, seed: int) -> float:
	var l := _lattice(x + 0.5, y + 0.5) * cells
	var i := Vector2i(floori(l.x), floori(l.y))
	var f := l - Vector2(i)
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var v00 := _hash(posmod(i.x, cells), posmod(i.y, cells), seed)
	var v10 := _hash(posmod(i.x + 1, cells), posmod(i.y, cells), seed)
	var v01 := _hash(posmod(i.x, cells), posmod(i.y + 1, cells), seed)
	var v11 := _hash(posmod(i.x + 1, cells), posmod(i.y + 1, cells), seed)
	return lerpf(lerpf(v00, v10, f.x), lerpf(v01, v11, f.x), f.y)


func _fbm(x: int, y: int, seed: int) -> float:
	return (0.5 * _vnoise(x, y, 3, seed) + 0.3 * _vnoise(x, y, 6, seed + 1)
			+ 0.2 * _vnoise(x, y, 12, seed + 2))


## Draws one texel at any position, wrapped onto this tile so details cross edges seamlessly.
func _put(img: Image, o: Vector2i, x: int, y: int, col: Color) -> void:
	var p := _wrap(x, y)
	if p.x < 0 or p.y < 0 or p.x >= TILE.x or p.y >= TILE.y:
		return
	img.set_pixel(o.x + p.x, o.y + p.y, col)


func _tiles() -> Image:
	# atlas: grass, path, water (MapData.TILE_* order)
	var img := Image.create_empty(TILE.x * 3, TILE.y, false, Image.FORMAT_RGBA8)
	for t in 3:
		var o := Vector2i(t * TILE.x, 0)
		for y in TILE.y:
			for x in TILE.x:
				if not _inside(x, y):
					continue
				var v := _fbm(x, y, 10 + t * 7)
				var col: Color
				match t:
					0: col = _c(GRASS, _pick(GRASS, v * 1.25 - 0.12, x, y, 1, 4))
					1: col = _c(DIRT, _pick(DIRT, v * 1.2 - 0.1, x, y, 2, 5))
					_: col = _c(WATER, _pick(WATER, v * 1.3 - 0.15, x, y, 1, 4))
				img.set_pixel(o.x + x, o.y + y, col)
		match t:
			0: _grass_details(img, o)
			1: _path_details(img, o)
			_: _water_details(img, o)
	return img


func _grass_details(img: Image, o: Vector2i) -> void:
	# blades: 3 to 6 px strokes, dark root to light tip, leaning a little
	for i in 170:
		var x := int(_hash(i, 0, 21) * TILE.x)
		var y := int(_hash(i, 1, 21) * TILE.y)
		var tall := 3 + int(_hash(i, 2, 21) * 4)
		var lean := int(_hash(i, 3, 21) * 3) - 1
		var tone := 3 + int(_hash(i, 4, 21) * 3)
		for k in tall:
			var shade := tone - 2 + int(float(k) / tall * 3.0)
			_put(img, o, x + (lean * k) / 3, y - k, _c(GRASS, shade))
	# clover clumps: a dark ring with light leaves
	for i in 3:
		var x := int(_hash(i, 0, 23) * TILE.x)
		var y := int(_hash(i, 1, 23) * TILE.y)
		for p in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
			_put(img, o, x + p.x, y + p.y + 1, _c(GRASS, 1))
			_put(img, o, x + p.x, y + p.y, _c(GRASS, 5))
		_put(img, o, x, y - 1, _c(GRASS, 6))
	# flower clusters
	for i in 2:
		var cx := int(_hash(i, 0, 22) * TILE.x)
		var cy := int(_hash(i, 1, 22) * TILE.y)
		var petal := Color.html(FLOWERS[int(_hash(i, 2, 22) * FLOWERS.size())])
		for j in 2 + int(_hash(i, 3, 22) * 3):
			var x := cx + int(_hash(i, 10 + j, 22) * 9) - 4
			var y := cy + int(_hash(i, 20 + j, 22) * 5) - 2
			_put(img, o, x, y + 2, _c(GRASS, 1))  # stem shadow
			_put(img, o, x, y + 1, _c(GRASS, 3))
			for p in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
				_put(img, o, x + p.x, y + p.y, petal)
			_put(img, o, x, y, _c(GOLD, 2) if petal != _c(GOLD, 2) else Color.html(FLOWERS[0]))


func _path_details(img: Image, o: Vector2i) -> void:
	# fine grit
	for i in 90:
		var x := int(_hash(i, 0, 33) * TILE.x)
		var y := int(_hash(i, 1, 33) * TILE.y)
		_put(img, o, x, y, _c(DIRT, 1 if i % 3 else 6))
	# pebbles: shaded little domes with a shadow on the bottom right
	for i in 11:
		var cx := _hash(i, 0, 31) * TILE.x
		var cy := _hash(i, 1, 31) * TILE.y
		var rx := 1.2 + _hash(i, 2, 31) * 2.0
		var ry := rx * (0.55 + _hash(i, 3, 31) * 0.2)
		for y in range(int(cy - ry) - 1, int(cy + ry) + 3):
			for x in range(int(cx - rx) - 1, int(cx + rx) + 3):
				var n := Vector2((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
				var s := Vector2((x - 0.5 - cx) / rx, (y - 1.0 - cy) / ry)
				if n.length_squared() <= 1.0:
					var lum := _lum(n)
					_put(img, o, x, y, _c(STONE, int(lum * 4.6)))
				elif s.length_squared() <= 1.0:
					_put(img, o, x, y, _c(DIRT, 1))


func _water_details(img: Image, o: Vector2i) -> void:
	# wave crests: light arcs over a dark trough
	for i in 30:
		var x := int(_hash(i, 0, 41) * TILE.x)
		var y := int(_hash(i, 1, 41) * TILE.y)
		var w := 5 + int(_hash(i, 2, 41) * 9)
		var tone := 5 if _hash(i, 3, 41) < 0.65 else 6
		for k in w:
			var t := float(k) / (w - 1)
			var lift := roundi(sin(t * PI) * 1.6)
			_put(img, o, x + k, y - lift, _c(WATER, tone if t > 0.15 and t < 0.85 else tone - 1))
			_put(img, o, x + k, y - lift + 1, _c(WATER, 1))
	# sparkles: a bright core with a soft cross
	for i in 5:
		var x := int(_hash(i, 0, 42) * TILE.x)
		var y := int(_hash(i, 1, 42) * TILE.y)
		for p in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_put(img, o, x + p.x, y + p.y, _c(WATER, 6))
		_put(img, o, x, y, _c(WATER, 7))


## Lambert brightness in [0, 1] of a sphere-like surface at normalized offset n.
func _lum(n: Vector2) -> float:
	var z := sqrt(maxf(0.0, 1.0 - n.length_squared()))
	var normal := Vector3(n.x, n.y, z).normalized()
	return clampf(0.18 + 0.9 * maxf(0.0, normal.dot(LIGHT.normalized())), 0.0, 1.0)


# --- Characters --------------------------------------------------------------


func _player() -> Image:
	# 4 directions (columns: down, left, right, up) x 2 walk frames (rows)
	var img := Image.create_empty(SPRITE.x * 4, SPRITE.y * 2, false, Image.FORMAT_RGBA8)
	for frame in 2:
		for dir in [0, 1, 3]:
			_draw_char(img, Vector2i(dir * SPRITE.x, frame * SPRITE.y), dir, frame)
		_mirror(img, Vector2i(SPRITE.x, frame * SPRITE.y), Vector2i(2 * SPRITE.x, frame * SPRITE.y))
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


func _draw_char(img: Image, o: Vector2i, dir: int, frame: int) -> void:
	var step := 4 if frame == 1 else 0
	var bob := 1 if frame == 1 else 0
	if dir == 1:
		_draw_side(img, o, step, bob)
	else:
		_draw_front_back(img, o, dir == 3, step, bob)
	_outline(img, o)
	_shadow(img, o)


func _draw_front_back(img: Image, o: Vector2i, back: bool, step: int, bob: int) -> void:
	# legs and boots: in the walk frame one leg lifts
	_limb(img, o, 23, 64, 8, 20 - step, PANTS)
	_limb(img, o, 33, 64, 8, 20, PANTS, -0.1)
	_blob(img, o, 27, 85 - step, 5.5, 4, BOOTS, 3.0)
	_blob(img, o, 37, 85, 5.5, 4, BOOTS, 3.0, -0.1)
	# arms swing opposite to the legs, behind the torso edges
	_limb(img, o, 12, 43 - bob + step, 7, 17, TUNIC, 0.05)
	_limb(img, o, 45, 43 - bob - step + 3, 7, 17, TUNIC, -0.15)
	_blob(img, o, 15.5, 62 - bob + step, 3.6, 3.4, SKIN)
	_blob(img, o, 48.5, 65 - bob - step, 3.6, 3.4, SKIN, 2.0, -0.1)
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


func _draw_side(img: Image, o: Vector2i, step: int, bob: int) -> void:
	# facing left. back leg and arm first, darker
	_limb(img, o, 30, 64, 8, 20, PANTS, -0.2)
	_blob(img, o, 32 + step, 85, 6, 4, BOOTS, 3.0, -0.15)
	_limb(img, o, 36, 43 - bob, 7, 16, TUNIC, -0.25)
	# torso
	_blob(img, o, 33, 53 - bob, 11, 15, TUNIC, 3.5)
	for x in range(23, 44):
		_px(img, o, x, 59 - bob, _c(BOOTS, 1))
		_px(img, o, x, 60 - bob, _c(BOOTS, 2))
		_px(img, o, x, 61 - bob, _c(BOOTS, 1))
	_blob(img, o, 24.5, 60.5 - bob, 2.2, 2.5, GOLD, 4.0)
	# front leg strides forward in the walk frame
	_limb(img, o, 26 - step, 64, 8, 20, PANTS)
	_blob(img, o, 28 - step, 85, 6.5, 4, BOOTS, 3.0)
	# front arm swings
	_limb(img, o, 30 + step / 3, 43 - bob, 7, 16, TUNIC, 0.1)
	_blob(img, o, 33.5 + step / 3, 61 - bob, 3.6, 3.4, SKIN)
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
