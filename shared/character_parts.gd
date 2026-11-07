## Interchangeable character parts, read once from res://data/character/: slots.json (the slots, in editor
## order, and the region names), ramps.json (the named colours) and parts/<id>.json (one part each).
## Shared: the server checks every look a player sends against the same data the client draws it with.
## The standard for contributors is docs/character-parts.md.
##
## A look is an Array of {"id": String, "color": String}: at most one part per slot, the colour one of the
## part's "colors" (names of ramps.json). A part record: {id, slot, name, kind ("body", "skinned", "rigid"
## or "texture"), glb, bone (rigid only: the bone it hangs from), texture (texture only: an index texture
## drawn on the face zone of the head), regions (body only: its meshes body_<region>), morph (body only:
## its body shape, data/character/morphs.json), covers (regions it draws, for other parts to hide), hides
## (regions it hides), when_hidden ({glb,
## covers, hides}: what is drawn instead when something hides one of its regions; without it the part is
## not drawn), colors}.
class_name CharacterParts
extends RefCounted

const DATA_DIR := "res://data/character"
## Largest look a client may send, in characters of its JSON (a look is a few hundred).
const MAX_LOOK_CHARS := 2048

static var _loaded := false
static var _slots: Array[Dictionary] = []
static var _regions: Array[String] = []
static var _ramps := {}
static var _morphs := ["standard"]  ## name -> {name, colours: Array[Color]}
static var _parts := {}  ## id -> record
static var _ids: Array[String] = []  ## sorted


static func slots() -> Array[Dictionary]:
	_ensure()
	return _slots


static func slot_ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for s in _slots:
		out.append(s["id"])
	return out


static func slot(id: String) -> Dictionary:
	_ensure()
	for s in _slots:
		if s["id"] == id:
			return s
	return {}


## Names parts may cover or hide: the body's regions and the hair's surfaces.
static func regions() -> Array[String]:
	_ensure()
	return _regions


static func part_ids() -> Array[String]:
	_ensure()
	return _ids


## The part record, or {} for an unknown id.
static func part(id: String) -> Dictionary:
	_ensure()
	return _parts.get(id, {})


## The ramp {name, colours} of a colour name, or {} if unknown.
static func ramp(name: String) -> Dictionary:
	_ensure()
	return _ramps.get(name, {})


static func ramp_names() -> Array:
	_ensure()
	return _ramps.keys()


## Body shapes a body part can have: "standard" and those of data/character/morphs.json.
static func morph_ids() -> Array:
	_ensure()
	return _morphs


## The colour a part is drawn in with a ramp: its second colour (the first if it has one).
static func base_colour(ramp_name: String) -> Color:
	var cs: Array = ramp(ramp_name).get("colours", [])
	if cs.is_empty():
		return Color.MAGENTA
	return cs[mini(1, cs.size() - 1)]


## Ids of the parts of a slot, sorted.
static func parts_for(slot_id: String) -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for id in _ids:
		if _parts[id]["slot"] == slot_id:
			out.append(id)
	return out


## Each slot's default part, in its first colour.
static func default_look() -> Array:
	_ensure()
	var out := []
	for s in _slots:
		if s["default"] != "" and _parts.has(s["default"]):
			out.append({"id": s["default"], "color": _parts[s["default"]]["colors"][0]})
	return out


## "" if `look` is a valid look, otherwise why not (for logs, not shown to players).
static func validate(look: Variant) -> String:
	_ensure()
	if typeof(look) != TYPE_ARRAY:
		return "look is not a list"
	if look.size() > _slots.size():
		return "more parts than slots"
	if JSON.stringify(look).length() > MAX_LOOK_CHARS:
		return "look too long"
	var used := {}
	for e in look:
		if typeof(e) != TYPE_DICTIONARY or e.size() != 2 or not e.has("id") or not e.has("color"):
			return "entry is not {id, color}"
		if typeof(e["id"]) != TYPE_STRING or typeof(e["color"]) != TYPE_STRING:
			return "entry types"
		var p: Dictionary = _parts.get(e["id"], {})
		if p.is_empty():
			return "unknown part %s" % e["id"]
		if used.has(p["slot"]):
			return "two parts in slot %s" % p["slot"]
		used[p["slot"]] = true
		if not e["color"] in p["colors"]:
			return "colour %s not allowed for %s" % [e["color"], e["id"]]
	for s in _slots:
		if s["required"] and not used.has(s["id"]):
			return "missing required slot %s" % s["id"]
	return ""


## A valid look from anything (a saved look, an older client's, parts removed since): keeps what still
## makes sense, in slot order. An unknown part is dropped; an unknown colour becomes the part's first; a
## required slot left empty gets its default. Never fails: at worst the default look.
static func normalize(raw: Variant) -> Array:
	_ensure()
	var by_slot := {}
	if typeof(raw) == TYPE_ARRAY:
		for e in raw:
			if typeof(e) != TYPE_DICTIONARY or typeof(e.get("id")) != TYPE_STRING:
				continue
			var p: Dictionary = _parts.get(e["id"], {})
			if p.is_empty() or by_slot.has(p["slot"]):
				continue
			var c: Variant = e.get("color", "")
			by_slot[p["slot"]] = {"id": String(e["id"]), "color": c if c in p["colors"] else p["colors"][0]}
	var out := []
	for s in _slots:
		if by_slot.has(s["id"]):
			out.append(by_slot[s["id"]])
		elif s["required"] and _parts.has(s["default"]):
			out.append({"id": s["default"], "color": _parts[s["default"]]["colors"][0]})
	return out if validate(out) == "" else default_look()


## What to draw for a valid look: {"parts": [{id, slot, kind, glb, bone, texture, ramp, color: Color}] in
## slot order,
## "hidden": {region: true}}. A part whose covered regions are hidden is drawn with its when_hidden mesh if
## that one is clear, or not at all; a part not drawn hides nothing (hiding is not transitive).
static func resolve(look: Array) -> Dictionary:
	_ensure()
	var chosen := {}
	var all_hides := {}
	for e in look:
		var p: Dictionary = _parts.get(e["id"], {})
		if p.is_empty():
			continue
		chosen[p["slot"]] = e
		for r in p["hides"]:
			all_hides[r] = true
	var out := []
	var hidden := {}
	for s in _slots:
		if not chosen.has(s["id"]):
			continue
		var e: Dictionary = chosen[s["id"]]
		var p: Dictionary = _parts[e["id"]]
		var glb: String = p["glb"]
		var hides: Array = p["hides"]
		if _touches(p["covers"], all_hides):
			var alt: Dictionary = p["when_hidden"]
			if alt.is_empty() or _touches(alt["covers"], all_hides):
				continue
			glb = alt["glb"]
			hides = alt["hides"]
		for r in hides:
			hidden[r] = true
		out.append({"id": p["id"], "slot": p["slot"], "kind": p["kind"], "glb": glb, "bone": p["bone"],
				"morph": p["morph"], "texture": p["texture"], "ramp": e["color"], "color": base_colour(e["color"])})
	return {"parts": out, "hidden": hidden}


## The look with the next (step 1) or previous (-1) part in a slot; optional slots pass through "none".
static func cycle_part(look: Array, slot_id: String, step: int) -> Array:
	_ensure()
	var choices: Array = Array(parts_for(slot_id))
	if not slot(slot_id).get("required", true):
		choices.push_front("")
	if choices.is_empty():
		return look
	var current := ""
	var out := []
	for e in look:
		if _parts.get(e["id"], {}).get("slot", "") == slot_id:
			current = e["id"]
		else:
			out.append(e)
	var next: String = choices[posmod(choices.find(current) + step, choices.size())]
	if next != "":
		out.append({"id": next, "color": _parts[next]["colors"][0]})
	return _in_slot_order(out)


## The look with the part of a slot in its next (1) or previous (-1) allowed colour.
static func cycle_color(look: Array, slot_id: String, step: int) -> Array:
	_ensure()
	var out := []
	for e in look:
		var p: Dictionary = _parts.get(e["id"], {})
		if not p.is_empty() and p["slot"] == slot_id:
			var cs: Array = p["colors"]
			out.append({"id": e["id"], "color": cs[posmod(cs.find(e["color"]) + step, cs.size())]})
		else:
			out.append(e)
	return out


static func _in_slot_order(look: Array) -> Array:
	var order := slot_ids()
	var out := look.duplicate()
	out.sort_custom(func(a, b): return order.find(_parts[a["id"]]["slot"]) < order.find(_parts[b["id"]]["slot"]))
	return out


static func _touches(names: Array, hidden: Dictionary) -> bool:
	for r in names:
		if hidden.has(r):
			return true
	return false


static func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var sdata: Variant = _read(DATA_DIR.path_join("slots.json"))
	for s in sdata["slots"]:
		_slots.append({"id": String(s["id"]), "name": String(s["name"]), "required": bool(s.get("required", false)),
				"default": String(s.get("default", ""))})
	_regions.assign(sdata.get("regions", []))
	var mdata: Variant = _read(DATA_DIR.path_join("morphs.json"))
	if mdata is Dictionary:
		for m in mdata.get("morphs", {}):
			_morphs.append(String(m))
	var rdata: Variant = _read(DATA_DIR.path_join("ramps.json"))
	for name in rdata["ramps"]:
		var colours: Array[Color] = []
		for c in rdata["ramps"][name]["colours"]:
			colours.append(Color.html(c))
		_ramps[name] = {"name": String(rdata["ramps"][name].get("name", name)), "colours": colours}
	var dir := DATA_DIR.path_join("parts")
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var rec: Variant = _read(dir.path_join(f))
		var problem := check_record(rec, f)
		if problem != "":
			push_error("data: character part %s: %s" % [f, problem])
			continue
		var alt := {}
		if typeof(rec.get("when_hidden")) == TYPE_DICTIONARY:
			var w: Dictionary = rec["when_hidden"]
			alt = {"glb": String(w["glb"]), "covers": Array(w.get("covers", [])), "hides": Array(w.get("hides", []))}
		_parts[rec["id"]] = {"id": String(rec["id"]), "slot": String(rec["slot"]), "name": String(rec.get("name", rec["id"])),
				"kind": String(rec["kind"]), "glb": String(rec.get("glb", "")), "bone": String(rec.get("bone", "")),
				"texture": String(rec.get("texture", "")), "morph": String(rec.get("morph", "standard")),
				"regions": Array(rec.get("regions", [])), "covers": Array(rec.get("covers", [])),
				"hides": Array(rec.get("hides", [])), "when_hidden": alt, "colors": Array(rec["colors"])}
	_ids.assign(_parts.keys())
	_ids.sort()


## "" if a part record read from `file` follows the standard (docs/character-parts.md), otherwise why not.
static func check_record(rec: Variant, file: String) -> String:
	if typeof(rec) != TYPE_DICTIONARY:
		return "not a JSON object"
	var id: Variant = rec.get("id")
	if typeof(id) != TYPE_STRING or id + ".json" != file:
		return "id must be the file name"
	if not RegEx.create_from_string("^[a-z0-9_]+$").search(id):
		return "id must be lowercase letters, digits and _"
	if slot(String(rec.get("slot", ""))).is_empty():
		return "unknown slot %s" % rec.get("slot")
	var kind: Variant = rec.get("kind")
	if not kind in ["body", "skinned", "rigid", "texture"]:
		return "kind must be body, skinned, rigid or texture"
	if (kind == "body") != (rec["slot"] == "body"):
		return "only the body slot holds body parts"
	if rec["slot"] == "face" and kind != "texture":
		return "a face is a texture"
	if kind == "texture":
		if not rec["slot"] in ["face", "beard"]:
			return "only faces and beards can be textures"
		if typeof(rec.get("texture")) != TYPE_STRING or not ResourceLoader.exists(rec["texture"]):
			return "texture missing"
	elif typeof(rec.get("glb")) != TYPE_STRING or not ResourceLoader.exists(rec["glb"]):
		return "glb missing"
	if kind == "rigid" and (typeof(rec.get("bone")) != TYPE_STRING or rec["bone"] == ""):
		return "a rigid part needs a bone"
	if kind == "body" and not morph_ids().has(rec.get("morph", "standard")):
		return "unknown body shape %s" % rec.get("morph")
	var colors: Variant = rec.get("colors")
	if typeof(colors) != TYPE_ARRAY or colors.is_empty():
		return "no colours"
	for c in colors:
		if not _ramps.has(c):
			return "unknown colour %s" % c
	var names: Array = Array(rec.get("covers", [])) + Array(rec.get("hides", [])) + Array(rec.get("regions", []))
	if typeof(rec.get("when_hidden")) == TYPE_DICTIONARY:
		var w: Dictionary = rec["when_hidden"]
		if typeof(w.get("glb")) != TYPE_STRING or not ResourceLoader.exists(w["glb"]):
			return "when_hidden glb missing"
		names += Array(w.get("covers", [])) + Array(w.get("hides", []))
	for r in names:
		if not r in _regions:
			return "unknown region %s" % r
	return ""
