## Isometric tile layer setup shared by the view and the tests.
class_name IsoLayer
extends RefCounted

const TILE_SIZE := Vector2i(128, 64)


## A TileMapLayer with the game's isometric TileSet. texture = the tiles atlas (null in tests).
static func new_layer(texture: Texture2D) -> TileMapLayer:
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
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	return layer


## Local position of a (possibly fractional) cell position, consistent with map_to_local.
static func cell_to_local(pos: Vector2) -> Vector2:
	var half := Vector2(TILE_SIZE) / 2.0
	return Vector2((pos.x - pos.y) * half.x, (pos.x + pos.y) * half.y) + half
