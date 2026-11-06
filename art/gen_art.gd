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

const TILE := IsoLayer.TILE_SIZE  ## tile size and atlas layout live in client/iso_layer.gd
const SPRITE := Vector2i(64, 96)
const LIGHT := Vector3(-0.55, -0.65, 0.52)  ## from the top left, towards the viewer
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


func _initialize() -> void:
	_tiles().save_png(IsoLayer.TILES_ATLAS)
	_player().save_png("res://assets/player.png")
	DirAccess.make_dir_recursive_absolute("res://assets/objects")
	for id in OBJECTS:
		_object(id).save_png("res://assets/objects/%s.png" % id)
	print("art: wrote assets/tiles.png, assets/player.png and assets/objects/*.png")
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
	var h := (x * 374761393 + y * 668265263 + (seed + _salt * 7919) * 1442695041) & 0x7fffffff
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


## Ground types, one atlas row each, in the order of the "atlas" field of data/tiles/*.json.
const GROUNDS := ["deep_water", "shallow_water", "sand", "grass", "dry_grass", "forest_floor", "packed_dirt"]
## Each row has one tile per corner mask (DualGrid): NW << 3 | NE << 2 | SW << 1 | SE, where on screen
## NW is the top corner, NE the right one, SW the left one and SE the bottom one. Then the other
## variants of the full tile (data/tiles "full_variants"), see IsoLayer.atlas_column().
const MASKS := IsoLayer.MASK_COLUMNS
## Variants keep variant 0's texels this close to the tile edge (lattice units), and their own beyond
## VARIANT_EDGE_IN, with dithering in between, so any two variants join seamlessly.
const VARIANT_EDGE_OUT := 0.03
const VARIANT_EDGE_IN := 0.13

## Shifts every hash seed, so each variant gets its own texture and details.
var _salt := 0
## How a ground's edge looks: rim ramp and steps (dark side, lit side), and what it casts outside
## (a translucent shadow on the bottom-right side, foam all around, or nothing).
const EDGES := {
	"deep_water": {"ramp": WATER, "dark": 0, "lit": 2, "outer": "none"},
	"shallow_water": {"ramp": WATER, "dark": 2, "lit": 6, "outer": "none"},
	"sand": {"ramp": SAND, "dark": 2, "lit": 6, "outer": "foam"},
	"grass": {"ramp": GRASS, "dark": 1, "lit": 5, "outer": "shadow"},
	"dry_grass": {"ramp": DRY, "dark": 2, "lit": 6, "outer": "shadow"},
	"forest_floor": {"ramp": FOREST, "dark": 0, "lit": 4, "outer": "shadow"},
	"packed_dirt": {"ramp": DIRT, "dark": 1, "lit": 5, "outer": "shadow"},
}


func _tiles() -> Image:
	var img := Image.create_empty(TILE.x * IsoLayer.ATLAS_COLUMNS, TILE.y * GROUNDS.size(), false,
			Image.FORMAT_RGBA8)
	for row in GROUNDS.size():
		var full := _ground(GROUNDS[row], row)
		for mask in MASKS:
			_cut(img, full, Vector2i(mask * TILE.x, row * TILE.y), mask, GROUNDS[row], 60 + row * 5)
		var tile := WorldData.tile(WorldData.tile_index(GROUNDS[row]))
		for v in range(1, tile["full_variants"]):
			_salt = v
			var own := _ground(GROUNDS[row], row)
			_salt = 0
			var col := IsoLayer.atlas_column(MASKS - 1, v)
			_blend_variant(img, full, own, Vector2i(col * TILE.x, row * TILE.y))
	return img


## A full tile variant: `own` inside, `base` (variant 0) along the edges, dithered in between.
func _blend_variant(img: Image, base: Image, own: Image, o: Vector2i) -> void:
	for y in TILE.y:
		for x in TILE.x:
			if not _inside(x, y):
				continue
			var l := _lattice(x + 0.5, y + 0.5)
			var edge := 0.5 - maxf(absf(l.x), absf(l.y))
			var w := clampf((edge - VARIANT_EDGE_OUT) / (VARIANT_EDGE_IN - VARIANT_EDGE_OUT), 0.0, 1.0)
			var b: float = (BAYER[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0
			img.set_pixel(o.x + x, o.y + y, own.get_pixel(x, y) if w > b else base.get_pixel(x, y))


## The whole diamond of one ground, seamless with copies of itself.
func _ground(kind: String, row: int) -> Image:
	var img := Image.create_empty(TILE.x, TILE.y, false, Image.FORMAT_RGBA8)
	var o := Vector2i.ZERO
	for y in TILE.y:
		for x in TILE.x:
			if not _inside(x, y):
				continue
			var v := _fbm(x, y, 10 + row * 7 + _salt * 101)
			var col: Color
			match kind:
				"deep_water": col = _c(WATER, _pick(WATER, v * 1.3 - 0.15, x, y, 0, 2))
				"shallow_water": col = _c(WATER, _pick(WATER, v * 1.3 - 0.15, x, y, 3, 5))
				"sand": col = _c(SAND, _pick(SAND, v * 1.3 - 0.15, x, y, 3, 5))
				"grass": col = _c(GRASS, _pick(GRASS, v * 1.25 - 0.12, x, y, 1, 4))
				"dry_grass": col = _c(DRY, _pick(DRY, v * 1.25 - 0.12, x, y, 2, 4))
				"forest_floor": col = _c(FOREST, _pick(FOREST, v * 1.3 - 0.15, x, y, 1, 3))
				"packed_dirt": col = _c(DIRT, _pick(DIRT, v * 1.2 - 0.1, x, y, 2, 5))
			img.set_pixel(x, y, col)
	match kind:
		"deep_water": _water_details(img, o, -2)
		"shallow_water": _water_details(img, o, 0)
		"sand": _sand_details(img, o)
		"grass": _grass_details(img, o)
		"dry_grass": _dry_details(img, o)
		"forest_floor": _forest_details(img, o)
		"packed_dirt": _path_details(img, o)
	return img


## Copies the part of `full` that a corner mask keeps into the atlas at `o`. The kept area comes
## from the 4 corner values interpolated over the diamond, with a periodic noise for a ragged edge:
## on a tile edge it depends only on the two corners of that edge, and the noise is periodic over
## the tile lattice, so neighbouring tiles always meet. Edge texels get a rim, lit on the top left.
func _cut(img: Image, full: Image, o: Vector2i, mask: int, kind: String, seed: int) -> void:
	# corner values on screen: top (NW), right (NE), bottom (SE), left (SW)
	var c := [float((mask >> 3) & 1), float((mask >> 2) & 1), float(mask & 1), float((mask >> 1) & 1)]
	var edge: Dictionary = EDGES[kind]
	for y in TILE.y:
		for x in TILE.x:
			if not _inside(x, y):
				continue
			var l := _lattice(x + 0.5, y + 0.5)
			var u := l.x + 0.5  # 0 at the top/left corners' side, 1 at the right/bottom side
			var w := l.y + 0.5  # 0 at the top/right side, 1 at the left/bottom side
			# corners: top (0, 0), right (1, 0), bottom (1, 1), left (0, 1)
			var value := lerpf(lerpf(c[0], c[1], u), lerpf(c[3], c[2], u), w)
			var noise := (_vnoise(x, y, 4, seed) - 0.5) * 0.24 + (_vnoise(x, y, 12, seed + 1) - 0.5) * 0.1
			var e := value - 0.5 + noise
			# outward normal of the kept area, on screen: lattice (a, b) -> screen (a - b, a + b)
			var ga := lerpf(c[1] - c[0], c[2] - c[3], w)
			var gb := lerpf(c[3] - c[0], c[2] - c[1], u)
			var facing_light := (ga - gb) + (ga + gb) > 0.0  # normal . (-1, -1) > 0
			if e > 0.0:
				var col := full.get_pixel(x, y)
				if e < 0.05 and mask != 15:
					col = _c(edge["ramp"], edge["lit"] if facing_light else edge["dark"])
				img.set_pixel(o.x + x, o.y + y, col)
			elif e > -0.06 and mask != 0:
				var b: float = (BAYER[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0
				match edge["outer"]:
					"shadow":
						if not facing_light:
							img.set_pixel(o.x + x, o.y + y, SHADOW)
					"foam":
						if b < 0.75 + e * 8.0:
							img.set_pixel(o.x + x, o.y + y, Color(_c(WATER, 7), 0.85))


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


## shift: tone offset of the crests (deep water: darker crests, fewer, no sparkles).
func _water_details(img: Image, o: Vector2i, shift: int) -> void:
	# wave crests: light arcs over a dark trough
	for i in 30 + shift * 6:
		var x := int(_hash(i, 0, 41) * TILE.x)
		var y := int(_hash(i, 1, 41) * TILE.y)
		var w := 5 + int(_hash(i, 2, 41) * 9)
		var tone := (5 if _hash(i, 3, 41) < 0.65 else 6) + shift
		for k in w:
			var t := float(k) / (w - 1)
			var lift := roundi(sin(t * PI) * 1.6)
			_put(img, o, x + k, y - lift, _c(WATER, tone if t > 0.15 and t < 0.85 else tone - 1))
			_put(img, o, x + k, y - lift + 1, _c(WATER, maxi(0, 1 + shift / 2)))
	if shift < 0:
		return
	# sparkles: a bright core with a soft cross
	for i in 5:
		var x := int(_hash(i, 0, 42) * TILE.x)
		var y := int(_hash(i, 1, 42) * TILE.y)
		for p in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_put(img, o, x + p.x, y + p.y, _c(WATER, 6))
		_put(img, o, x, y, _c(WATER, 7))


func _sand_details(img: Image, o: Vector2i) -> void:
	# grains: dark and light specks
	for i in 120:
		var x := int(_hash(i, 0, 51) * TILE.x)
		var y := int(_hash(i, 1, 51) * TILE.y)
		_put(img, o, x, y, _c(SAND, 2 if i % 3 else 6))
	# ripples left by the wind: short light strokes over a shadow
	for i in 9:
		var x := int(_hash(i, 0, 52) * TILE.x)
		var y := int(_hash(i, 1, 52) * TILE.y)
		var w := 6 + int(_hash(i, 2, 52) * 8)
		for k in w:
			_put(img, o, x + k, y + (k / 4), _c(SAND, 5))
			_put(img, o, x + k, y + (k / 4) + 1, _c(SAND, 2))
	# small shells and pebbles
	for i in 4:
		var x := int(_hash(i, 0, 53) * TILE.x)
		var y := int(_hash(i, 1, 53) * TILE.y)
		_put(img, o, x, y, _c(STONE, 4))
		_put(img, o, x + 1, y, _c(STONE, 3))
		_put(img, o, x, y + 1, _c(SAND, 1))
		_put(img, o, x + 1, y + 1, _c(SAND, 1))


func _dry_details(img: Image, o: Vector2i) -> void:
	# tufts: straw-coloured blades with pale tips, leaning more than green grass
	for i in 120:
		var x := int(_hash(i, 0, 61) * TILE.x)
		var y := int(_hash(i, 1, 61) * TILE.y)
		var tall := 3 + int(_hash(i, 2, 61) * 4)
		var lean := int(_hash(i, 3, 61) * 5) - 2
		var tone := 3 + int(_hash(i, 4, 61) * 3)
		for k in tall:
			var shade := tone - 2 + int(float(k) / tall * 3.0)
			_put(img, o, x + (lean * k) / 3, y - k, _c(DRY, shade))
	# bare earth showing through
	for i in 5:
		var cx := int(_hash(i, 0, 62) * TILE.x)
		var cy := int(_hash(i, 1, 62) * TILE.y)
		for k in 7:
			var x := cx + int(_hash(i, 10 + k, 62) * 6) - 3
			var y := cy + int(_hash(i, 20 + k, 62) * 3) - 1
			_put(img, o, x, y, _c(DIRT, 3 if k % 2 else 4))


func _forest_details(img: Image, o: Vector2i) -> void:
	# fallen leaves in autumn browns and golds
	for i in 70:
		var x := int(_hash(i, 0, 71) * TILE.x)
		var y := int(_hash(i, 1, 71) * TILE.y)
		var col := _c(DIRT, 2 + int(_hash(i, 2, 71) * 3)) if i % 4 else _c(GOLD, 1)
		_put(img, o, x, y, col)
		_put(img, o, x + 1, y, col)
		_put(img, o, x, y + 1, _c(FOREST, 0))
	# moss cushions: a lit top over a dark base
	for i in 6:
		var x := int(_hash(i, 0, 72) * TILE.x)
		var y := int(_hash(i, 1, 72) * TILE.y)
		for dx in range(-2, 3):
			_put(img, o, x + dx, y + 1, _c(FOREST, 1))
			_put(img, o, x + dx, y, _c(FOREST, 4 if dx < 1 else 3))
		_put(img, o, x - 1, y - 1, _c(FOREST, 5))
		_put(img, o, x, y - 1, _c(FOREST, 4))
	# twigs
	for i in 5:
		var x := int(_hash(i, 0, 73) * TILE.x)
		var y := int(_hash(i, 1, 73) * TILE.y)
		var w := 4 + int(_hash(i, 2, 73) * 5)
		for k in w:
			_put(img, o, x + k, y + (k / 3 if i % 2 else -k / 3), _c(DIRT, 1))


## Lambert brightness in [0, 1] of a sphere-like surface at normalized offset n.
func _lum(n: Vector2) -> float:
	var z := sqrt(maxf(0.0, 1.0 - n.length_squared()))
	var normal := Vector3(n.x, n.y, z).normalized()
	return clampf(0.18 + 0.9 * maxf(0.0, normal.dot(LIGHT.normalized())), 0.0, 1.0)


# --- Objects -----------------------------------------------------------------
# Provisional sprites (PixelLab sprites may replace them: data/objects/<id>.json names each file).
# The object's cell centre is IsoLayer.OBJECT_FOOT_PX above the bottom edge, horizontally centred.

const OBJECTS := {"oak": Vector2i(96, 128), "pine": Vector2i(64, 128), "rock": Vector2i(48, 40),
	"bush": Vector2i(48, 40), "stone_wall": Vector2i(64, 64), "standing_stone": Vector2i(32, 64),
	"campfire": Vector2i(48, 40)}
const OBJECT_FOOT := IsoLayer.OBJECT_FOOT_PX


func _object(id: String) -> Image:
	var size: Vector2i = OBJECTS[id]
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var o := Vector2i.ZERO
	var cx := size.x / 2.0
	var foot := size.y - OBJECT_FOOT
	match id:
		"oak":
			_limb(img, o, int(cx) - 5, foot - 44, 10, 46, DIRT)
			for b in [[-16, -60, 22, 18], [16, -62, 22, 18], [0, -84, 28, 22], [-10, -72, 24, 20], [10, -74, 24, 20]]:
				_blob(img, o, cx + b[0], foot + b[1], b[2], b[3], GRASS, 2.0, -0.05)
		"pine":
			_limb(img, o, int(cx) - 3, foot - 24, 6, 26, DIRT)
			for k in 4:
				var top := foot - 30 - k * 22
				for y in 30:
					var half := (y + 4) * (0.9 - k * 0.12)
					for x in range(int(cx - half), int(cx + half)):
						var n := Vector2((x + 0.5 - cx) / maxf(half, 1.0), 0.2)
						_px(img, o, x, top + y, _c(FOREST, int(_lum(n) * 5.0) + 1))
		"rock":
			_blob(img, o, cx, foot - 10, 18, 13, STONE, 2.6)
			_blob(img, o, cx + 9, foot - 4, 10, 7, STONE, 2.4, -0.1)
		"stone_wall":
			# a low wall block on a 48 x 24 base: lit top face, darker front faces, brick lines
			var top_c := foot - 26.0
			var base_c := foot - 4.0
			for y in size.y:
				for x in size.x:
					var dx := absf(x + 0.5 - cx) / 24.0
					if dx > 1.0:
						continue
					var half := 12.0 * (1.0 - dx)
					var yy := y + 0.5
					var face := -1
					if yy >= top_c - half and yy <= top_c + half:
						face = 4
					elif yy > top_c + half and yy <= base_c + half:
						face = 3 if x < cx else 2
					if face < 0:
						continue
					var brick := 1 if face < 4 and ((y % 7 == 0) or ((x + (y / 7) * 5) % 10 == 0)) else 0
					_px(img, o, x, y, _c(STONE, face - brick))
		"standing_stone":
			_blob(img, o, cx, foot - 26, 10, 28, STONE, 3.0)
			for y in range(foot - 44, foot - 10, 7):
				_px(img, o, int(cx) - 2, y, _c(GRASS, 3))  # moss
		"campfire":
			for k in 6:
				var a := k * TAU / 6.0
				_blob(img, o, cx + cos(a) * 14.0, foot - 6 + sin(a) * 6.0, 4, 3, STONE)
			_limb(img, o, int(cx) - 8, foot - 9, 16, 3, DIRT)
			_blob(img, o, cx, foot - 16, 6, 10, GOLD, 2.0, 0.2)
			_blob(img, o, cx, foot - 13, 4, 6, TUNIC, 2.0, 0.3)
		"bush":
			for b in [[-8, -10, 12, 10], [8, -10, 12, 10], [0, -16, 13, 11]]:
				_blob(img, o, cx + b[0], foot + b[1], b[2], b[3], GRASS, 2.0, 0.05)
			for k in 5:
				_px(img, o, int(cx) - 10 + k * 5, foot - 12 - (k % 2) * 6, _c(TUNIC, 4))
	_object_outline(img)
	for y in range(foot - 5, foot + 6):
		for x in size.x:
			var n := Vector2((x + 0.5 - cx) / (size.x * 0.42), (y + 0.5 - foot) / 5.0)
			if n.length_squared() <= 1.0 and img.get_pixel(x, y).a == 0.0:
				img.set_pixel(x, y, SHADOW)
	return img


func _object_outline(img: Image) -> void:
	var edge := {}
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + n
				if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height() \
						and img.get_pixelv(p).a > 0.0:
					edge[Vector2i(x, y)] = Color.html(OUTLINE).lerp(img.get_pixelv(p), 0.18)
					break
	for p in edge:
		img.set_pixelv(p, edge[p])


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
