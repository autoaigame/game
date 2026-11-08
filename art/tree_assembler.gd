## Assembles the tree sprites (assets/objects/<species>_<n>.png) from PixelLab pieces
## (art/trees/pieces/: bare winter skeletons, foliage tufts, fir needle pieces), offline.
##
## assemble(seed, species) is a pure function of an integer seed: it picks a skeleton and whether it
## is mirrored, then lays foliage tufts at the ends of its twigs. Part of them goes behind the
## trunk, a shade or two darker. Every tuft is first brought to the same mean brightness as the others,
## then lit by its place in the crown (lighter at the top left, darker at the bottom right), so no
## tuft stands out from its neighbours. Firs are needle branches hung along the whorls of a bare
## spruce skeleton, wide at the bottom and narrowing smoothly to the top. fir_dead is a bare spruce
## left as it is.
## Every pixel is one of the kit's 40 colours (data/palette.json), opaque or fully transparent; the
## ground shadow is drawn by art/object_shadows.gd with the radii this script gives each sprite.
## Randomness comes from an integer hash (WorldNoise), never from randi() or RandomNumberGenerator,
## so the same seed gives the same PNG on every machine.
##
## Usage: godot --headless --path . -s res://art/tree_assembler.gd
## It writes the PNGs, the sprite list of data/objects/<id>.json, and prints the shadow radii to
## copy into art/object_shadows.gd (RADII).
extends SceneTree

const SHADOWS := preload("res://art/object_shadows.gd")
const PIECES := "res://art/trees/pieces/"
const OUT := "res://assets/objects/"
## Room around the assembled tree before it is cropped (tufts hang past the skeleton, the shadow
## past the foot).
const PAD := 48

## Each data/objects id and the file prefix of its sprites.
const SPECIES := {
	"oak": {
		"data": "oak",
		## Sprites drawn: <species>_00.png and on, seeds 0, 1, ...
		"variants": 18,
		"skeletons": ["oak_bare_256", "oak_bare2_256", "oak_bare3_256", "oak_bare4_256", "oak_bare5_256"],
		"tufts": ["tuft_00", "tuft_04", "tuft_05", "tuft_00", "tuft_05", "tuft_06"],
		"tufts_min": 24, "tufts_max": 30, "spacing": 20,
		## Mean ramp position (0 dark, 1 light) every tuft is brought to.
		"level": 0.4,
		## Tufts sit on twig ends in the top part of the skeleton (this fraction of its height).
		"crown": 0.62,
		## Tuft centre relative to the twig end, in tuft heights (oak: centred on it).
		"hang": 0.5,
		"back_percent": 35,
		## Shades darker for the tufts behind the trunk.
		"back_steps": 2,
		"shadow": 0.19,
	},
	"birch": {
		"data": "birch",
		"variants": 18,
		"skeletons": ["birch_bare_256", "birch_bare2_256", "birch_bare3_256", "birch_bare4_256"],
		"tufts": ["tuft_08", "tuft_09", "tuft_11", "tuft_08", "tuft_09", "tuft_11", "tuft_10"],
		"tufts_min": 18, "tufts_max": 24, "spacing": 16,
		"level": 0.55,
		"crown": 0.7,
		"hang": 0.25,
		"back_percent": 35,
		"back_steps": 1,
		"shadow": 0.19,
	},
	"fir": {
		"data": "pine",
		"variants": 18,
		"skeletons": ["fir_bare_256", "fir_bare2_256", "fir_bare4_256", "fir_bare5_256"],
		## Needle branches pointing left (mirrored for the right side), the spire, and clumps for the
		## middle of the crown.
		"branches": ["fir_branch_0", "fir_branch_1", "tuft_12", "tuft_13", "tuft_14"],
		"spires": ["fir_spire_0", "fir_spire_1"],
		"clumps": ["tuft_15"],
		"crown": 0.9,
		"level": 0.38,
		"back_steps": 1,
		"shadow": 0.21,
	},
	## A dead spruce, bare: one sprite among the pines.
	"fir_dead": {
		"data": "pine",
		"variants": 1,
		"skeletons": ["fir_bare3_256"],
		"bare": true,
		"crown": 0.9,
		"shadow": 0.21,
	},
}

static var _ramps := {}  ## colour (0xRRGGBB) -> [ramp (Array of colours), index]
static var _pieces := {}  ## name -> Image
static var _shifted := {}  ## [name, steps, flipped, level] -> Image
static var _skeletons := {}  ## name -> {tips, foot, top}


func _initialize() -> void:
	var radii_lines := []
	var lists := {}  ## data id -> sprites, in SPECIES order
	for species in SPECIES:
		var data: String = SPECIES[species]["data"]
		if not lists.has(data):
			lists[data] = []
		for n in int(SPECIES[species]["variants"]):
			var t := assemble(n, species)
			var name := "%s_%02d.png" % [species, n]
			var img: Image = t["image"]
			var err := img.save_png(OUT + name)
			if err != OK:
				push_error("tree_assembler: cannot write %s (%s)" % [name, error_string(err)])
				quit(1)
				return
			lists[data].append({"file": OUT + name, "anchor": t["anchor"]})
			radii_lines.append('\t"%s": Vector2(%s, %s),' % [name, t["radii"].x, t["radii"].y])
	for data in lists:
		_write_sprites(data, lists[data])
	print("tree_assembler: wrote %d sprites; RADII for art/object_shadows.gd:" % radii_lines.size())
	for l in radii_lines:
		print(l)
	quit(0)


## The species and seed of an assembled sprite's file name ("fir_dead_00.png" -> ["fir_dead", 0]), or
## [] for a file the assembler does not draw.
static func parse_name(file: String) -> Array:
	var base := file.get_file().get_basename()
	var i := base.rfind("_")
	var n := base.substr(i + 1)
	if i < 0 or not SPECIES.has(base.substr(0, i)) or n.length() != 2 or not n.is_valid_int():
		return []
	return [base.substr(0, i), int(n)]


## The tree for (seed, species): {image (RGBA8, its ground shadow drawn), anchor (Vector2i, the foot
## of the trunk), radii (Vector2, of the shadow)}.
static func assemble(seed: int, species: String) -> Dictionary:
	var spec: Dictionary = SPECIES[species]
	var rng := Rng.new(seed, WorldNoise.hash_text(species))
	if spec.has("branches"):
		return _assemble_fir(seed, spec, rng)
	var skel_names: Array = spec["skeletons"]
	var skel_name: String = skel_names[seed % skel_names.size()]
	var mirror := (seed / skel_names.size()) % 2 == 1
	var info := _skeleton(skel_name, spec["crown"])
	var skel := _piece(skel_name, 0, mirror)
	var w := skel.get_width()
	var tips: Array = info["tips"]
	var foot: Vector2i = info["foot"]
	if mirror:
		foot.x = w - 1 - foot.x
		var flipped := []
		for p in tips:
			flipped.append(Vector2i(w - 1 - p.x, p.y))
		tips = flipped

	var canvas := Image.create(w + 2 * PAD, skel.get_height() + 2 * PAD, false, Image.FORMAT_RGBA8)
	var off := Vector2i(PAD, PAD)
	if spec.get("bare", false):
		canvas.blend_rect(skel, Rect2i(Vector2i.ZERO, skel.get_size()), off)
		return _finish(canvas, off + foot, spec["shadow"])
	var crown := _crown_box(tips)
	var n: int = rng.between(spec["tufts_min"], spec["tufts_max"])
	var points := _pick_points(rng, tips, n, spec["spacing"])
	var back := []
	var front := []
	var tufts: Array = spec["tufts"]
	for p in points:
		var tuft_name: String = tufts[rng.next() % tufts.size()]
		var flip := rng.next() & 1 == 1
		var is_back := rng.next() % 100 < int(spec["back_percent"])
		var steps := _light_steps(p, crown) - (int(spec["back_steps"]) if is_back else 0)
		var t := _piece(tuft_name, steps, flip, spec["level"])
		var pos: Vector2i = off + p - Vector2i(t.get_width() / 2 + rng.between(-4, 4), int(t.get_height() * float(spec["hang"])))
		(back if is_back else front).append([p.y, pos, t])
	back.sort_custom(func(a, b): return a[0] < b[0])
	front.sort_custom(func(a, b): return a[0] < b[0])
	for e in back:
		canvas.blend_rect(e[2], Rect2i(Vector2i.ZERO, e[2].get_size()), e[1])
	canvas.blend_rect(skel, Rect2i(Vector2i.ZERO, skel.get_size()), off)
	for e in front:
		canvas.blend_rect(e[2], Rect2i(Vector2i.ZERO, e[2].get_size()), e[1])
	return _finish(canvas, off + foot, spec["shadow"])


## A fir: a bare spruce skeleton dressed in needle branches, whorl after whorl from the bottom of
## the crown to the spire. The length of the branches follows one smooth cone (with a little noise)
## instead of a few stacked tiers, so the outline does not climb in steps. Branches behind the trunk
## are a shade darker, the right side (away from the light) darker than the left, the lowest whorls
## darker than the rest.
static func _assemble_fir(seed: int, spec: Dictionary, rng: Rng) -> Dictionary:
	var skel_names: Array = spec["skeletons"]
	var skel_name: String = skel_names[seed % skel_names.size()]
	var mirror := (seed / skel_names.size()) % 2 == 1
	var info := _skeleton(skel_name, spec["crown"])
	var skel := _piece(skel_name, 0, mirror)
	var w := skel.get_width()
	var foot: Vector2i = info["foot"]
	var top: Vector2i = info["top"]
	if mirror:
		foot.x = w - 1 - foot.x
		top.x = w - 1 - top.x
	var canvas := Image.create(w + 2 * PAD, skel.get_height() + 2 * PAD, false, Image.FORMAT_RGBA8)
	var off := Vector2i(PAD, PAD)
	var height := foot.y - top.y
	# bare trunk under the crown, widest radius, and how the cone bulges
	var bottom := foot.y - int(height * (0.1 + 0.1 * rng.unit()))
	var r_max := height * (0.27 + 0.07 * rng.unit())
	var bulge := 0.8 + 0.3 * rng.unit()
	var level: float = spec["level"]
	var back := []
	var front := []
	var y := bottom
	while y > top.y + 14:
		var t := float(y - top.y) / float(bottom - top.y)  # 0 at the top, 1 at the bottom of the crown
		var r := r_max * (0.06 + 0.94 * pow(t, bulge))
		var x := _axis(top, foot, y)
		for side in [-1, 1]:
			# a missing branch now and then: gaps show the trunk and break the outline
			if t > 0.2 and rng.next() % 100 < 22:
				continue
			var length := r * (0.85 + 0.25 * rng.unit())
			var piece := _branch_for(spec["branches"], length, rng)
			var is_back := rng.next() % 100 < 30
			var steps := (1 if side < 0 and t < 0.6 else 0 if side < 0 else -1) - (int(spec["back_steps"]) if is_back else 0) - (1 if t > 0.8 else 0)
			var img := _piece(piece, steps, side > 0, level)
			var att := _attach(piece, side > 0)
			var reach := mini(int(length), img.get_width())
			# only the outer `reach` px (and a few past the axis): the outer end lands `reach` px from it
			var keep := mini(reach + 3, img.get_width())
			img = img.get_region(Rect2i(0, 0, keep, img.get_height()) if side < 0 \
					else Rect2i(img.get_width() - keep, 0, keep, img.get_height()))
			var px := x - reach if side < 0 else x + reach - keep
			var pos := Vector2i(px, y - att.y + rng.between(-2, 2))
			(back if is_back else front).append([y, off + pos, img])
		# a clump over the trunk now and then, so the crown is not hollow
		if rng.next() % 100 < 25 and t > 0.15:
			var c: String = spec["clumps"][rng.next() % (spec["clumps"] as Array).size()]
			var ci := _piece(c, -1, rng.next() & 1 == 1, level)
			front.append([y, off + Vector2i(x - ci.get_width() / 2 + rng.between(-6, 6), y - ci.get_height() / 2), ci])
		y -= int(lerpf(7.0, 15.0, t)) + rng.between(0, 4)
	var sp: String = spec["spires"][rng.next() % (spec["spires"] as Array).size()]
	var spire := _piece(sp, 0, rng.next() & 1 == 1, level)
	var spire_pos := off + Vector2i(top.x - spire.get_width() / 2, top.y - 4)
	# from the bottom up: each whorl's drooping tips cover the base of the one below
	back.sort_custom(func(a, b): return a[0] > b[0])
	front.sort_custom(func(a, b): return a[0] > b[0])
	for e in back:
		canvas.blend_rect(e[2], Rect2i(Vector2i.ZERO, e[2].get_size()), e[1])
	canvas.blend_rect(skel, Rect2i(Vector2i.ZERO, skel.get_size()), off)
	for e in front:
		canvas.blend_rect(e[2], Rect2i(Vector2i.ZERO, e[2].get_size()), e[1])
	canvas.blend_rect(spire, Rect2i(Vector2i.ZERO, spire.get_size()), spire_pos)
	return _finish(canvas, off + foot, spec["shadow"])


## The x of the trunk at row y: on the line from the foot to the top of the skeleton.
static func _axis(top: Vector2i, foot: Vector2i, y: int) -> int:
	return roundi(lerpf(foot.x, top.x, float(foot.y - y) / float(maxi(foot.y - top.y, 1))))


## A branch piece about `length` px long: the shortest one at least that long, else the longest,
## sometimes the next one up so equal lengths do not always get the same branch.
static func _branch_for(names: Array, length: float, rng: Rng) -> String:
	var sorted := names.duplicate()
	sorted.sort_custom(func(a, b): return _piece(a, 0, false).get_width() < _piece(b, 0, false).get_width())
	var i := sorted.size() - 1
	for k in sorted.size():
		if _piece(sorted[k], 0, false).get_width() >= length:
			i = k
			break
	if rng.next() % 3 == 0:
		i = mini(i + 1, sorted.size() - 1)
	return sorted[i]


## Where a branch piece joins the trunk: its inner end (the right edge of a branch pointing left,
## the left edge once mirrored), at the mean height of its opaque pixels there.
static func _attach(name: String, flipped: bool) -> Vector2i:
	var img := _piece(name, 0, false)
	var w := img.get_width()
	var sum := 0
	var n := 0
	for x in range(w - 4, w):
		for y in img.get_height():
			if img.get_pixel(x, y).a8 == 255:
				sum += y
				n += 1
	var ay := sum / maxi(n, 1)
	return Vector2i(0 if flipped else w - 1, ay)


## The shadow, then the canvas cropped to what is drawn.
static func _finish(canvas: Image, anchor: Vector2i, shadow_factor: float) -> Dictionary:
	var used := canvas.get_used_rect()
	var rx := floorf(shadow_factor * used.size.x) + 0.5
	var radii := Vector2(rx, floorf(rx * 0.36) + 0.5)
	var baked: Image = SHADOWS.rebake(canvas, Vector2(anchor), radii)
	used = baked.get_used_rect()
	return {"image": baked.get_region(used), "anchor": anchor - used.position, "radii": radii}


## Shade steps for a tuft at p from its place in the crown: +1 at the top left, down to -2 at the
## bottom right.
static func _light_steps(p: Vector2i, crown: Rect2) -> int:
	var c := crown.get_center()
	var h := crown.size / 2.0
	var s := -(0.6 * (p.x - c.x) / maxf(h.x, 1.0) + 0.8 * (p.y - c.y) / maxf(h.y, 1.0))
	return clampi(roundi(s * 1.1), -2, 1)


static func _crown_box(tips: Array) -> Rect2:
	var r := Rect2(Vector2(tips[0]), Vector2.ZERO)
	for p in tips:
		r = r.expand(Vector2(p))
	return r


## n points among the twig ends, at least min_d apart (fewer if they do not fit).
static func _pick_points(rng: Rng, tips: Array, n: int, min_d: int) -> Array:
	var chosen := []
	var tries := 0
	while chosen.size() < n and tries < n * 40:
		tries += 1
		var p: Vector2i = tips[rng.next() % tips.size()]
		var ok := true
		for q in chosen:
			if (p - q).length_squared() < min_d * min_d:
				ok = false
				break
		if ok:
			chosen.append(p)
	return chosen


## Twig ends of a skeleton (opaque pixels with few opaque neighbours, in the top `crown` of its
## height), the top of the skeleton, and the foot of its trunk: the column of the trunk (just
## above the roots) nearest its middle whose bark runs down unbroken to the lowest roots, at the
## bottom of that bark.
static func _skeleton(name: String, crown: float) -> Dictionary:
	if _skeletons.has(name):
		return _skeletons[name]
	var img := _piece(name, 0, false)
	var w := img.get_width()
	var h := img.get_height()
	var r := 3
	# summed-area table of opacity, to count the opaque pixels of each 7 x 7 window
	var sat := PackedInt32Array()
	sat.resize((w + 1) * (h + 1))
	var top := h
	var bot := -1
	for y in h:
		var row := 0
		for x in w:
			var o := 1 if img.get_pixel(x, y).a8 == 255 else 0
			if o == 1:
				top = mini(top, y)
				bot = maxi(bot, y)
			row += o
			sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row
	var tips := []
	var limit := top + (bot - top) * crown
	for y in h:
		if y >= limit:
			break
		for x in w:
			if img.get_pixel(x, y).a8 != 255:
				continue
			var x0 := maxi(x - r, 0)
			var y0 := maxi(y - r, 0)
			var x1 := mini(x + r + 1, w)
			var y1 := mini(y + r + 1, h)
			var cnt := sat[y1 * (w + 1) + x1] - sat[y0 * (w + 1) + x1] - sat[y1 * (w + 1) + x0] + sat[y0 * (w + 1) + x0]
			if cnt <= 14:
				tips.append(Vector2i(x, y))
	var fy := int(bot - (bot - top) * 0.12)
	var xs := []
	for x in w:
		if img.get_pixel(x, fy).a8 == 255:
			xs.append(x)
	# the trunk column nearest its middle whose bark runs down unbroken to the roots' level
	var mid: int = xs[xs.size() / 2]
	var foot := Vector2i(mid, bot - 5)
	var best := w
	for x in xs:
		var y := fy
		while y + 1 <= bot and img.get_pixel(x, y + 1).a8 == 255:
			y += 1
		if y >= bot - 6 and absi(x - mid) < best:
			best = absi(x - mid)
			foot = Vector2i(x, mini(y, bot - 2))
	var top_x := 0
	for x in w:
		if img.get_pixel(x, top).a8 == 255:
			top_x = x
			break
	_skeletons[name] = {"tips": tips, "foot": foot, "top": Vector2i(top_x, top)}
	return _skeletons[name]


## A piece, `steps` shades lighter (or darker if negative) along its colours' ramps, mirrored or not.
## level >= 0: first brought to that mean brightness (tufts).
static func _piece(name: String, steps: int, flipped: bool, level := -1.0) -> Image:
	var key := [name, steps, flipped, level]
	if _shifted.has(key):
		return _shifted[key]
	if not _pieces.has(name):
		_pieces[name] = _load(name)
	var img: Image = (_pieces[name] as Image).duplicate()
	if level >= 0.0:
		steps += _norm_steps(name, level)
	if steps != 0:
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a8 == 255:
					img.set_pixel(x, y, shade(c, steps))
	if flipped:
		img.flip_x()
	_shifted[key] = img
	return img


## A tuft's own correction, so all the tufts of a species share one mean brightness: the steps that
## bring the mean ramp position of its pixels (0 dark, 1 light) to `level`.
static func _norm_steps(name: String, level: float) -> int:
	var img: Image = _pieces[name]
	var sum := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 != 255:
				continue
			var e: Array = ramps()[c.to_rgba32() >> 8]
			sum += float(e[1]) / float((e[0] as Array).size() - 1)
			n += 1
	if n == 0:
		return 0
	return clampi(roundi((level - sum / n) * 4.0), -2, 2)


## A kit colour `steps` shades along its ramp (clamped at the ends of the ramp).
static func shade(c: Color, steps: int) -> Color:
	var e: Array = ramps()[c.to_rgba32() >> 8]
	var ramp: Array = e[0]
	return ramp[clampi(int(e[1]) + steps, 0, ramp.size() - 1)]


## The kit's 40 colours (the first ten ramps of data/palette.json): 0xRRGGBB -> [ramp, index].
static func ramps() -> Dictionary:
	if _ramps.is_empty():
		var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/palette.json"))
		var names: Array = p["ramps"].keys()
		for k in 10:
			var ramp := []
			for hex in p["ramps"][names[k]]:
				ramp.append(Color.html(hex))
			for i in ramp.size():
				_ramps[(ramp[i] as Color).to_rgba32() >> 8] = [ramp, i]
	return _ramps


## A piece from art/trees/pieces (not imported: .gdignore), alpha made binary. Fir branches, spires
## and clumps are cropped to what they draw, so their width is their length.
static func _load(name: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(PIECES + name + ".png"))
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c, 1.0) if c.a8 >= 128 else Color(0, 0, 0, 0))
	for spec in SPECIES.values():
		for k in ["branches", "spires", "clumps"]:
			if name in spec.get(k, []):
				return img.get_region(img.get_used_rect())
	return img


## Rewrites the "sprites" list of data/objects/<id>.json: the assembled sprites, then the sprites
## listed there that the assembler does not draw (the young trees). The rest of the file stays as is.
static func _write_sprites(id: String, sprites: Array) -> void:
	var path := "res://data/objects/%s.json" % id
	var text := FileAccess.get_file_as_string(path)
	var o: Dictionary = JSON.parse_string(text)
	for sp in o["sprites"]:
		if parse_name(sp["file"]).is_empty():
			sprites.append({"file": sp["file"], "anchor": Vector2i(sp["anchor_px"][0], sp["anchor_px"][1])})
	var start := text.find("\t\"sprites\": [")
	var end := text.find("\n\t],\n", start)
	var lines := []
	for s in sprites:
		lines.append("\t\t{\n\t\t\t\"file\": \"%s\",\n\t\t\t\"anchor_px\": [\n\t\t\t\t%d,\n\t\t\t\t%d\n\t\t\t]\n\t\t}" % [s["file"], s["anchor"].x, s["anchor"].y])
	text = text.substr(0, start) + "\t\"sprites\": [\n" + ",\n".join(lines) + text.substr(end)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)


## Integer-hash random numbers: the k-th number of (seed, salt) is WorldNoise.hash3(seed, salt, k).
class Rng:
	var seed: int
	var salt: int
	var k := 0

	func _init(s: int, sa: int) -> void:
		seed = s
		salt = sa

	func next() -> int:
		k += 1
		return WorldNoise.hash3(seed, salt, k, 0x7EE5)

	## An integer in [a, b].
	func between(a: int, b: int) -> int:
		return a + next() % (b - a + 1)

	## A float in [0, 1).
	func unit() -> float:
		return WorldNoise.unit(next())
