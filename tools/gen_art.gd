## Generates the game's pixel art. Deterministic: same script, same PNGs.
## Usage: godot --headless --path . -s res://tools/gen_art.gd   (or: make art)
extends SceneTree

## Our own 16-color palette (see docs/art-guide.md).
const PALETTE := [
	Color8(0x14, 0x12, 0x1c), Color8(0x3a, 0x2e, 0x4a), Color8(0x6b, 0x4a, 0x3a), Color8(0xa8, 0x76, 0x4a),
	Color8(0xe0, 0xb0, 0x7a), Color8(0xf4, 0xe6, 0xc8), Color8(0x2f, 0x5d, 0x3a), Color8(0x4f, 0x8f, 0x45),
	Color8(0x8f, 0xc4, 0x5a), Color8(0x1f, 0x3f, 0x6e), Color8(0x35, 0x74, 0xb0), Color8(0x7c, 0xc0, 0xe4),
	Color8(0x9a, 0x2f, 0x3a), Color8(0xd8, 0x5a, 0x4a), Color8(0xe8, 0xc4, 0x4a), Color8(0x8a, 0x8a, 0x9a),
]
const TILE := Vector2i(128, 64)
const SPRITE := Vector2i(64, 96)


func _initialize() -> void:
	_tiles().save_png("res://assets/tiles.png")
	_player().save_png("res://assets/player.png")
	print("art: wrote assets/tiles.png and assets/player.png")
	quit()


## Deterministic per-pixel noise in [0, 1).
func _noise(x: int, y: int, seed: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 1000) / 1000.0


## Blocky value noise: the same value over cell x cell blocks, for patches.
func _patch(x: int, y: int, seed: int, cell: int) -> float:
	return _noise(x / cell, y / cell, seed)


## Distance from the tile centre in diamond units: 0 at the centre, 1 on the border.
func _diamond(x: int, y: int) -> float:
	var dx := absf(x + 0.5 - TILE.x / 2.0) / (TILE.x / 2.0)
	var dy := absf(y + 0.5 - TILE.y / 2.0) / (TILE.y / 2.0)
	return dx + dy


func _tiles() -> Image:
	# atlas: grass, path, water (MapData.TILE_* order)
	var img := Image.create_empty(TILE.x * 3, TILE.y, false, Image.FORMAT_RGBA8)
	for t in 3:
		var o := Vector2i(t * TILE.x, 0)
		for y in TILE.y:
			for x in TILE.x:
				var d := _diamond(x, y)
				if d > 1.0:
					continue
				var c: int
				match t:
					0: c = _grass_px(x, y)
					1: c = _path_px(x, y)
					_: c = _water_px(x, y)
				# a darker rim on the lower edges gives the tiles some depth
				if d > 0.955 and y >= TILE.y / 2:
					c = [6, 2, 9][t]
				img.set_pixel(o.x + x, o.y + y, PALETTE[c])
		match t:
			0: _grass_details(img, o)
			1: _path_details(img, o)
			_: _water_details(img, o)
	return img


func _grass_px(x: int, y: int) -> int:
	var p := _patch(x, y, 11, 6)
	var n := _noise(x, y, 1)
	if p < 0.18:
		return 6 if n < 0.6 else 7
	if p > 0.85:
		return 8 if n < 0.5 else 7
	if n < 0.08:
		return 6
	if n > 0.95:
		return 8
	return 7


func _path_px(x: int, y: int) -> int:
	var p := _patch(x, y, 12, 5)
	var n := _noise(x, y, 2)
	if p < 0.2:
		return 2 if n < 0.5 else 3
	if p > 0.82:
		return 4 if n < 0.5 else 3
	if n < 0.07:
		return 2
	if n > 0.94:
		return 4
	return 3


func _water_px(x: int, y: int) -> int:
	# deep diagonal bands, wobbling with coarse noise
	var band := (x + y * 2 + int(_patch(x, y, 13, 4) * 8)) % 24
	var n := _noise(x, y, 3)
	if band < 5:
		return 9 if n < 0.9 else 10
	if n < 0.03:
		return 9
	return 10


## Sets a pixel only where it lies well inside the tile diamond.
func _put(img: Image, o: Vector2i, x: int, y: int, c: int) -> void:
	if x < 0 or y < 0 or x >= TILE.x or y >= TILE.y or _diamond(x, y) > 0.93:
		return
	img.set_pixel(o.x + x, o.y + y, PALETTE[c])


func _grass_details(img: Image, o: Vector2i) -> void:
	# tufts: small V-shaped blades, light tip over a dark root
	for i in 26:
		var x := int(_noise(i, 0, 21) * TILE.x)
		var y := int(_noise(i, 1, 21) * TILE.y)
		_put(img, o, x, y + 2, 6)
		_put(img, o, x, y + 1, 7)
		_put(img, o, x, y, 8)
		_put(img, o, x - 1, y + 1, 8)
		_put(img, o, x + 1, y + 1, 8)
		_put(img, o, x - 2, y, 8)
		_put(img, o, x + 2, y, 8)
	# a few flowers
	for i in 4:
		var x := int(_noise(i, 0, 22) * TILE.x)
		var y := int(_noise(i, 1, 22) * TILE.y)
		var petal: int = [14, 5, 13, 14][i]
		_put(img, o, x, y - 1, petal)
		_put(img, o, x - 1, y, petal)
		_put(img, o, x + 1, y, petal)
		_put(img, o, x, y + 1, petal)
		_put(img, o, x, y, 4)


func _path_details(img: Image, o: Vector2i) -> void:
	# pebbles: rounded 4x3 stones with a light top and a shadow below
	for i in 14:
		var x := int(_noise(i, 0, 31) * TILE.x)
		var y := int(_noise(i, 1, 31) * TILE.y)
		var stone: int = 15 if i % 3 == 0 else 4
		for sx in range(-1, 3):
			_put(img, o, x + sx, y + 2, 2)
		for sy in 2:
			for sx in range(-1, 3):
				_put(img, o, x + sx, y + sy, stone)
		_put(img, o, x, y - 1, stone)
		_put(img, o, x + 1, y - 1, stone)
		_put(img, o, x, y, 5)
	# wheel ruts along the tile's long axis
	for x in range(20, TILE.x - 20):
		if _noise(x, 0, 32) < 0.7:
			_put(img, o, x, TILE.y / 2 - 7 + (x % 2), 2)
			_put(img, o, x, TILE.y / 2 + 7 - (x % 2), 2)


func _water_details(img: Image, o: Vector2i) -> void:
	# short wave crests: a light arc over a mid-blue shadow
	for i in 18:
		var x := int(_noise(i, 0, 41) * TILE.x)
		var y := int(_noise(i, 1, 41) * TILE.y)
		var w := 4 + int(_noise(i, 2, 41) * 6)
		for k in w:
			var lift := 1 if k > 0 and k < w - 1 else 0
			_put(img, o, x + k, y - lift, 11)
			_put(img, o, x + k, y + 1 - lift, 10)
	# sparkles
	for i in 6:
		var x := int(_noise(i, 0, 42) * TILE.x)
		var y := int(_noise(i, 1, 42) * TILE.y)
		_put(img, o, x, y, 5)
		_put(img, o, x + 1, y, 11)
		_put(img, o, x, y + 1, 11)


func _player() -> Image:
	# 4 directions (columns: down, left, right, up) x 2 walk frames (rows)
	var img := Image.create_empty(SPRITE.x * 4, SPRITE.y * 2, false, Image.FORMAT_RGBA8)
	for dir in 4:
		for frame in 2:
			_draw_char(img, Vector2i(dir * SPRITE.x, frame * SPRITE.y), dir, frame)
	return img


func _rect(img: Image, o: Vector2i, x0: int, y0: int, w: int, h: int, c: int) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			img.set_pixel(o.x + x, o.y + y, PALETTE[c])


## Filled ellipse centred on (cx, cy) with radii (rx, ry).
func _ellipse(img: Image, o: Vector2i, cx: float, cy: float, rx: float, ry: float, c: int) -> void:
	for y in range(int(cy - ry), int(cy + ry) + 1):
		for x in range(int(cx - rx), int(cx + rx) + 1):
			var nx := (x + 0.5 - cx) / rx
			var ny := (y + 0.5 - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(o.x + x, o.y + y, PALETTE[c])


## Darkest palette color around every opaque pixel of the frame: a 1 px outline.
func _outline(img: Image, o: Vector2i) -> void:
	var edge: Array[Vector2i] = []
	for y in SPRITE.y:
		for x in SPRITE.x:
			if img.get_pixel(o.x + x, o.y + y).a > 0.0:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + n
				if p.x < 0 or p.y < 0 or p.x >= SPRITE.x or p.y >= SPRITE.y:
					continue
				if img.get_pixel(o.x + p.x, o.y + p.y).a > 0.0:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		img.set_pixel(o.x + p.x, o.y + p.y, PALETTE[0])


func _draw_char(img: Image, o: Vector2i, dir: int, frame: int) -> void:
	var step := 3 if frame == 1 else 0
	var side := dir == 1 or dir == 2
	var flip := dir == 2  # right = mirrored left
	# legs and boots (the walk frame lifts one leg)
	var la := 22 if not side else 25
	var lb := 34 if not side else 31
	_rect(img, o, la, 66, 8, 20 - step, 1)
	_rect(img, o, la, 82 - step, 8, 6, 2)
	_rect(img, o, la, 82 - step, 8, 1, 3)
	_rect(img, o, lb, 66, 8, 18 + step, 1)
	_rect(img, o, lb, 82 + step, 8, 6, 2)
	_rect(img, o, lb, 82 + step, 8, 1, 3)
	# tunic, shaded on one side, with a hem
	_rect(img, o, 18, 40, 28, 28, 12)
	_rect(img, o, 16, 58, 32, 10, 12)
	_rect(img, o, 40 if not flip else 18, 42, 6, 26, 13 if dir == 3 else 12)
	_rect(img, o, 18 if not flip else 40, 42, 4, 26, 13)
	_rect(img, o, 16, 66, 32, 2, 2)
	# belt with a buckle (hidden from behind)
	_rect(img, o, 18, 56, 28, 4, 2)
	if dir != 3:
		var bx := 30 if not side else (22 if dir == 1 else 38)
		_rect(img, o, bx, 56, 4, 4, 14)
		_rect(img, o, bx + 1, 57, 2, 2, 3)
	# arms swing with the walk frame
	if side:
		var ax := 28
		_rect(img, o, ax, 42 + step, 8, 18, 13)
		_rect(img, o, ax + (7 if dir == 1 else 0), 42 + step, 1, 18, 2)
		_rect(img, o, ax + 1, 60 + step, 6, 5, 4)
	else:
		_rect(img, o, 11, 42 + step, 7, 18, 12)
		_rect(img, o, 12, 60 + step, 5, 5, 4)
		_rect(img, o, 46, 42 - step + 3, 7, 18, 12)
		_rect(img, o, 47, 60 - step + 3, 5, 5, 4)
	# neck and head
	_rect(img, o, 27, 36, 10, 5, 3)
	_ellipse(img, o, 32, 24, 14, 14, 4)
	_rect(img, o, 20, 32, 24, 4, 4)
	# hair
	_ellipse(img, o, 32, 15, 15, 8, 2)
	_rect(img, o, 18, 13, 28, 6, 2)
	_rect(img, o, 22, 9, 20, 2, 3)  # highlight
	match dir:
		0:  # facing down: eyes, brows, mouth, cheeks, fringe
			_rect(img, o, 18, 18, 28, 3, 2)
			_rect(img, o, 23, 24, 5, 5, 5)
			_rect(img, o, 36, 24, 5, 5, 5)
			_rect(img, o, 25, 25, 3, 4, 0)
			_rect(img, o, 36, 25, 3, 4, 0)
			_rect(img, o, 23, 22, 5, 1, 2)
			_rect(img, o, 36, 22, 5, 1, 2)
			_rect(img, o, 21, 30, 4, 2, 13)
			_rect(img, o, 39, 30, 4, 2, 13)
			_rect(img, o, 29, 32, 6, 1, 2)
		1, 2:  # side: one eye, nose, hair down the back
			var fx := func(x: int, w: int) -> int: return x if not flip else SPRITE.x - x - w
			_rect(img, o, fx.call(18, 10), 18, 10, 3, 2)
			_rect(img, o, fx.call(22, 5), 24, 5, 5, 5)
			_rect(img, o, fx.call(22, 3), 25, 3, 4, 0)
			_rect(img, o, fx.call(22, 5), 22, 5, 1, 2)
			_rect(img, o, fx.call(17, 3), 27, 3, 3, 4)
			_rect(img, o, fx.call(20, 4), 32, 4, 1, 2)
			_rect(img, o, fx.call(34, 13), 13, 13, 20, 2)
			_rect(img, o, fx.call(36, 5), 24, 5, 7, 4)  # ear
			_rect(img, o, fx.call(37, 2), 26, 2, 3, 3)
		3:  # up: hair covers the head
			_ellipse(img, o, 32, 22, 14, 13, 2)
			_rect(img, o, 22, 12, 20, 2, 3)
	_outline(img, o)
	# soft ground shadow, drawn last under the feet
	for y in range(86, 94):
		for x in range(12, 52):
			var nx := (x + 0.5 - 32.0) / 20.0
			var ny := (y + 0.5 - 90.0) / 4.0
			if nx * nx + ny * ny <= 1.0 and img.get_pixel(o.x + x, o.y + y).a == 0.0:
				img.set_pixel(o.x + x, o.y + y, PALETTE[1])
