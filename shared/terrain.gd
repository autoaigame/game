## Natural terrain of the infinite world: altitude, moisture, rivers and biomes, from data/biomes.json.
## Pure functions of world cell coordinates and the world seed (never a per-chunk seed), so any cell
## gives the same answer whichever chunk asks, on the server and in the browser. Not cached:
## MapData caches by chunk.
class_name Terrain
extends RefCounted

const _FIELD_ALTITUDE := 1
const _FIELD_MOISTURE := 2
const _FIELD_RIVER := 3

## Settings read once from WorldData.gen(); plain fields because this runs for every cell.
static var _is_set_up := false
static var _alt := {}  ## {seed, scale, octaves, stretch, curve: PackedFloat64Array x0,y0,x1,y1...}
static var _moist := {}
static var _river := {}
static var _meadow_r := 0.0
static var _meadow_blend := 1.0
static var _meadow_alt := 0.5
static var _meadow_moist := 0.5
static var _table: Array = []
static var _bi := {}  ## biome id -> index


## Altitude in [0, 1]: low-frequency fBm stretched, then shaped by the data's piecewise curve,
## mixed towards the meadow altitude near the origin.
static func altitude(x: int, y: int) -> float:
	_setup()
	return lerpf(_meadow_alt, _curve(_field(_alt, x, y)), meadow_t(x, y))


## Moisture in [0, 1], independent of altitude (its own seed).
static func moisture(x: int, y: int) -> float:
	_setup()
	return lerpf(_meadow_moist, _field(_moist, x, y), meadow_t(x, y))


## 0 inside the starting meadow around the origin, rising smoothly to 1 at its outer edge.
static func meadow_t(x: int, y: int) -> float:
	_setup()
	return smoothstep(_meadow_r, _meadow_r + _meadow_blend, sqrt(float(x * x + y * y)))


## Biome index (WorldData.biomes()) of a cell.
static func biome(x: int, y: int) -> int:
	_setup()
	var t := meadow_t(x, y)
	var alt := lerpf(_meadow_alt, _curve(_field(_alt, x, y)), t)
	var moist := lerpf(_meadow_moist, _field(_moist, x, y), t)
	var id := _table_biome(alt, moist)
	if id != "deep_water" and id != "shallow_water" and alt < _river["max_altitude"] and t > 0.0:
		var k: float = clampf((_river["max_altitude"] - alt) / _river["fade"], 0.0, 1.0) * t
		var d := absf(_field(_river, x, y) - 0.5)
		if d < _river["deep_width"] * k:
			id = "deep_water"
		elif d < _river["width"] * k:
			id = "river"
		elif d < _river["bank_width"] * k and id != "forest":
			id = "beach"
	return _bi[id]


static func _table_biome(alt: float, moist: float) -> String:
	for row in _table:
		if alt <= row[0] or row == _table.back():
			var cols: Array = row[1]
			for col in cols:
				if moist <= col[0] or col == cols.back():
					return col[1]
	return ""


## fBm of one field at a cell, stretched around 0.5 (fBm rarely leaves 0.25..0.75).
static func _field(f: Dictionary, x: int, y: int) -> float:
	var s: float = f["scale"]
	var v := WorldNoise.fbm(f["seed"], x / s, y / s, f["octaves"])
	return clampf((v - 0.5) * f["stretch"] + 0.5, 0.0, 1.0)


## The altitude curve: piecewise linear through the data's [x, y] points.
static func _curve(v: float) -> float:
	var c: PackedFloat64Array = _alt["curve"]
	for i in range(2, c.size(), 2):
		if v <= c[i]:
			var t := (v - c[i - 2]) / maxf(c[i] - c[i - 2], 1e-9)
			return lerpf(c[i - 1], c[i + 1], clampf(t, 0.0, 1.0))
	return c[c.size() - 1]


static func _setup() -> void:
	if _is_set_up:
		return
	_is_set_up = true
	var g := WorldData.gen()
	var world_seed := int(g["seed"])
	_alt = _field_settings(world_seed, _FIELD_ALTITUDE, g["altitude"])
	var curve := PackedFloat64Array()
	for p in g["altitude"]["curve"]:
		curve.append(float(p[0]))
		curve.append(float(p[1]))
	_alt["curve"] = curve
	_moist = _field_settings(world_seed, _FIELD_MOISTURE, g["moisture"])
	_river = _field_settings(world_seed, _FIELD_RIVER, g["rivers"])
	for k in ["width", "deep_width", "bank_width", "max_altitude", "fade"]:
		_river[k] = float(g["rivers"][k])
	var m: Dictionary = g["meadow"]
	_meadow_r = float(m["radius"])
	_meadow_blend = float(m["blend"])
	_meadow_alt = float(m["altitude"])
	_meadow_moist = float(m["moisture"])
	# table rows: [max_altitude, [[max_moisture, biome id], ...]]
	for row in g["table"]:
		var cols: Array = []
		if row.has("biome"):
			cols.append([1.0, String(row["biome"])])
		else:
			for col in row["by_moisture"]:
				cols.append([float(col["max_moisture"]), String(col["biome"])])
		_table.append([float(row["max_altitude"]), cols])
	for b in WorldData.biomes():
		_bi[b["id"]] = WorldData.biome_index(b["id"])


static func _field_settings(world_seed: int, field: int, d: Dictionary) -> Dictionary:
	return {"seed": WorldNoise.hash2(world_seed, field, 0), "scale": float(d["scale"]),
			"octaves": int(d["octaves"]), "stretch": float(d.get("stretch", 2.0))}
