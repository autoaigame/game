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
const TILE := Vector2i(32, 16)
const SPRITE := Vector2i(16, 24)


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


func _in_diamond(x: int, y: int) -> bool:
	var dx := absf(x + 0.5 - TILE.x / 2.0) / (TILE.x / 2.0)
	var dy := absf(y + 0.5 - TILE.y / 2.0) / (TILE.y / 2.0)
	return dx + dy <= 1.0


func _tiles() -> Image:
	# atlas: grass, path, water (MapData.TILE_* order)
	var img := Image.create_empty(TILE.x * 3, TILE.y, false, Image.FORMAT_RGBA8)
	var looks := [[7, 6, 8], [3, 2, 4], [10, 9, 11]]  # base, dark speckle, light speckle
	for t in 3:
		for y in TILE.y:
			for x in TILE.x:
				if not _in_diamond(x, y):
					continue
				var n := _noise(x, y, t + 1)
				var c: int = looks[t][0]
				if n < 0.12:
					c = looks[t][1]
				elif n > 0.9:
					c = looks[t][2]
				if t == 2 and (x + y * 3) % 11 == 0 and y > 3 and y < 12:
					c = 11  # water glints
				img.set_pixel(t * TILE.x + x, y, PALETTE[c])
	return img


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


func _draw_char(img: Image, o: Vector2i, dir: int, frame: int) -> void:
	_rect(img, o, 4, 22, 8, 2, 1)                     # shadow
	var step := 1 if frame == 1 else 0
	_rect(img, o, 5, 17, 2, 5 - step, 1)              # legs
	_rect(img, o, 9, 17, 2, 4 + step, 1)
	_rect(img, o, 4, 10, 8, 8, 12)                     # tunic
	_rect(img, o, 4, 16, 8, 1, 2)                      # belt
	_rect(img, o, 4, 3, 8, 7, 4)                       # head
	_rect(img, o, 4, 2, 8, 3, 2)                       # hair
	match dir:
		0:  # facing down: two eyes
			_rect(img, o, 6, 6, 1, 1, 0)
			_rect(img, o, 9, 6, 1, 1, 0)
		1:  # left
			_rect(img, o, 5, 6, 1, 1, 0)
			_rect(img, o, 9, 3, 3, 4, 2)
		2:  # right
			_rect(img, o, 10, 6, 1, 1, 0)
			_rect(img, o, 4, 3, 3, 4, 2)
		3:  # up: hair covers the head
			_rect(img, o, 4, 3, 8, 6, 2)
