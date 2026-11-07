## Isometric tile layer setup shared by the view and the tests.
class_name IsoLayer
extends RefCounted

## Tile size and atlas layout: the one place to change them (art/gen_art.gd reads them too).
const TILE_SIZE := Vector2i(96, 48)
## Ground atlas: one row per ground (data/tiles "atlas"). Columns 0-15: one per DualGrid corner mask
## (column 15 = full tile, variant 0). Columns 16 and up: the other variants of the full tile.
const TILES_ATLAS := "res://assets/tiles.png"
const MASK_COLUMNS := 16
const MAX_FULL_VARIANTS := 17  ## data/tiles "full_variants" at most
const ATLAS_COLUMNS := MASK_COLUMNS + MAX_FULL_VARIANTS - 1
## Camera zoom: screen pixels per texel. An integer, so every texel covers the same number of pixels.
const CAMERA_ZOOM := 1.0


static var _tile_sets := {}  ## texture -> TileSet, shared by every layer drawing that texture


## A TileMapLayer with the game's isometric TileSet. texture = the tiles atlas (null in tests). Layers
## of the same texture share one TileSet: building one creates a tile per atlas cell, too slow per chunk.
static func new_layer(texture: Texture2D) -> TileMapLayer:
	var layer := TileMapLayer.new()
	if texture != null and _tile_sets.has(texture):
		layer.tile_set = _tile_sets[texture]
		return layer
	layer.tile_set = _new_tile_set(texture)
	if texture != null:
		_tile_sets[texture] = layer.tile_set
	return layer


static func _new_tile_set(texture: Texture2D) -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = TILE_SIZE
	if texture != null:
		var src := TileSetAtlasSource.new()
		src.texture = texture
		src.texture_region_size = TILE_SIZE
		for row in int(texture.get_height() / TILE_SIZE.y):
			for col in int(texture.get_width() / TILE_SIZE.x):
				src.create_tile(Vector2i(col, row))
		ts.add_source(src, 0)
	return ts


## Atlas column of a corner mask; for the full mask (15), of one of its variants.
static func atlas_column(mask: int, variant: int) -> int:
	if mask != MASK_COLUMNS - 1 or variant == 0:
		return mask
	return MASK_COLUMNS + variant - 1


## Corner mask drawn by an atlas column.
static func mask_of_column(column: int) -> int:
	return mini(column, MASK_COLUMNS - 1)


## Local position of a (possibly fractional) cell position, consistent with map_to_local.
static func cell_to_local(pos: Vector2) -> Vector2:
	var half := Vector2(TILE_SIZE) / 2.0
	return Vector2((pos.x - pos.y) * half.x, (pos.x + pos.y) * half.y) + half
