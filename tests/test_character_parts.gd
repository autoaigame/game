extends TestCase

## Character parts (shared/character_parts.gd): the data in data/character/, the look a player sends, how
## a part hides another.


func _look(pairs: Array) -> Array:
	var out := []
	for p in pairs:
		var cs: Array = CharacterParts.part(p[0]).get("colors", ["none"])
		out.append({"id": p[0], "color": cs[p[1]] if p[1] is int and p[1] >= 0 and p[1] < cs.size() else str(p[1])})
	return out


func _ids(look: Array) -> Array:
	return look.map(func(e): return e["id"])


## Every record follows the standard (CharacterParts.check_record): none was dropped while loading.
func test_every_part_file_is_loaded() -> void:
	var files := DirAccess.get_files_at(CharacterParts.DATA_DIR.path_join("parts"))
	var n := 0
	for f in files:
		if f.ends_with(".json"):
			n += 1
			assert_true(f.trim_suffix(".json") in CharacterParts.part_ids(), f)
	assert_eq(CharacterParts.part_ids().size(), n)


func test_check_record_explains_mistakes() -> void:
	var good := {"id": "hat_test", "slot": "hat", "kind": "rigid", "glb": "res://assets/character/parts/hat_cap.glb",
			"bone": "DEF-head", "hides": ["scalp"], "colors": ["khaki"]}
	assert_eq(CharacterParts.check_record(good, "hat_test.json"), "")
	assert_true(CharacterParts.check_record(good, "other.json") != "", "id is the file name")
	for change in [{"slot": "crown"}, {"kind": "glued"}, {"glb": "res://nothing.glb"}, {"bone": ""},
			{"colors": []}, {"colors": ["gold"]}, {"hides": ["soul"]}, {"kind": "body"}]:
		var bad := good.duplicate()
		bad.merge(change, true)
		assert_true(CharacterParts.check_record(bad, "hat_test.json") != "", "%s" % change)


func test_every_part_names_a_known_slot_and_existing_glb() -> void:
	var slots := CharacterParts.slot_ids()
	assert_true(CharacterParts.part_ids().size() >= 10, "parts loaded: %s" % [CharacterParts.part_ids()])
	for id in CharacterParts.part_ids():
		var p := CharacterParts.part(id)
		assert_true(p["slot"] in slots, "%s: slot %s" % [id, p["slot"]])
		assert_true(ResourceLoader.exists(p["glb"]), "%s: %s" % [id, p["glb"]])
		assert_true(p["colors"].size() >= 1, "%s has colours" % id)
		if p["kind"] == "rigid":
			assert_true(p["bone"] != "", "%s: rigid needs a bone" % id)


func test_default_look_is_valid_and_has_the_body() -> void:
	var look := CharacterParts.default_look()
	assert_eq(CharacterParts.validate(look), "")
	assert_true("body_standard" in _ids(look))


func test_validate_accepts_a_good_look() -> void:
	assert_eq(CharacterParts.validate(_look([["body_standard", 1], ["hat_cap", 2], ["top_tshirt", 0], ["bottom_shorts", 1]])), "")


func test_validate_rejects_unknown_id() -> void:
	assert_true(CharacterParts.validate(_look([["body_standard", 0], ["crown_of_doom", 0]])) != "")


func test_validate_rejects_two_parts_in_one_slot() -> void:
	assert_true(CharacterParts.validate(_look([["body_standard", 0], ["hat_cap", 0], ["hat_beanie", 0]])) != "")


func test_validate_rejects_a_colour_the_part_does_not_allow() -> void:
	var base := _look([["body_standard", 0], ["top_tshirt", 0], ["bottom_jeans", 0]])
	assert_eq(CharacterParts.validate(base), "")
	assert_true(CharacterParts.validate(base + [{"id": "hat_cap", "color": "skin_light"}]) != "", "a skin ramp on a cap")
	assert_true(CharacterParts.validate(base + [{"id": "hat_cap", "color": "gold"}]) != "", "unknown ramp")


func test_validate_rejects_missing_required_slot() -> void:
	assert_true(CharacterParts.validate(_look([["hat_cap", 0]])) != "", "no body")
	assert_true(CharacterParts.validate(_look([["body_standard", 0], ["top_tshirt", 0]])) != "", "no trousers")


func test_validate_rejects_bad_shapes() -> void:
	assert_true(CharacterParts.validate("body_standard") != "")
	assert_true(CharacterParts.validate([42]) != "")
	assert_true(CharacterParts.validate([{"id": "body_standard"}]) != "", "no colour")
	assert_true(CharacterParts.validate([{"id": "body_standard", "color": 0}]) != "", "colour not a name")
	assert_true(CharacterParts.validate([{"id": "body_standard", "color": "skin_light", "extra": 1}]) != "")
	var many := _look([["body_standard", 0]])
	for i in 40:
		many.append({"id": "hat_cap", "color": 0})
	assert_true(CharacterParts.validate(many) != "", "too long")


## A saved look, or one from a newer client, is repaired without failing: unknown parts dropped,
## unknown colours back to the part's first, empty required slots back to their default.
func test_normalize_repairs_a_look() -> void:
	var raw: Variant = JSON.parse_string('[{"id":"body_standard","color":"skin_dark"},{"id":"gone","color":"khaki"},{"id":"hat_cap","color":"gold"}]')
	var look := CharacterParts.normalize(raw)
	assert_eq(look, [{"id": "body_standard", "color": "skin_dark"}, {"id": "hat_cap", "color": "khaki"},
			{"id": "top_tshirt", "color": "grey"}, {"id": "bottom_jeans", "color": "faded_denim"}])
	assert_eq(CharacterParts.validate(look), "")
	assert_eq(CharacterParts.normalize("junk"), _look([["body_standard", 0], ["top_tshirt", 0], ["bottom_jeans", 0]]))


func test_a_hat_hides_short_hair_entirely() -> void:
	var r := CharacterParts.resolve(_look([["body_standard", 0], ["hair_short", 0], ["hat_cap", 0]]))
	var shown: Array = r["parts"].map(func(e): return e["id"])
	assert_true("hat_cap" in shown)
	assert_false("hair_short" in shown)


## Long hair has a mesh for under a hat: only the back stays.
func test_a_hat_swaps_long_hair_for_its_back() -> void:
	var r := CharacterParts.resolve(_look([["body_standard", 0], ["hair_long", 0], ["hat_beanie", 0]]))
	var hair: Array = r["parts"].filter(func(e): return e["id"] == "hair_long")
	assert_eq(hair.size(), 1)
	assert_eq(hair[0]["glb"], "res://assets/character/parts/hair_long_under.glb")
	var bare := CharacterParts.resolve(_look([["body_standard", 0], ["hair_long", 0]]))
	var hair2: Array = bare["parts"].filter(func(e): return e["id"] == "hair_long")
	assert_eq(hair2[0]["glb"], "res://assets/character/parts/hair_long.glb")


## Garments hide the skin regions under them, so the body never pokes through.
func test_garments_hide_body_regions() -> void:
	var r := CharacterParts.resolve(_look([["body_standard", 0], ["top_tshirt", 0], ["feet_boots", 0]]))
	var hidden: Dictionary = r["hidden"]
	assert_true(hidden.has("torso") and hidden.has("arms_upper") and hidden.has("feet"))
	assert_false(hidden.has("arms_lower"), "a t-shirt leaves the forearms bare")
	assert_false(hidden.has("head"))


## A part is drawn in the second colour of its ramp, a palette colour.
func test_resolve_gives_the_ramp_colour() -> void:
	var r := CharacterParts.resolve(_look([["body_standard", 1]]))
	assert_eq(r["parts"][0]["color"], Color.html("9a6d56"))
	var pal := Character3D.palette()
	for name in CharacterParts.ramp_names():
		for c in CharacterParts.ramp(name)["colours"]:
			assert_true(c in pal, "%s: %s in the palette" % [name, c.to_html(false)])


## Hiding is not transitive: hair hidden by a hat no longer hides the back of the head.
func test_a_part_not_drawn_hides_nothing() -> void:
	var r := CharacterParts.resolve(_look([["body_standard", 0], ["hair_short", 0], ["hat_cap", 0]]))
	assert_true(r["hidden"].has("scalp"), "the cap hides the scalp")
	assert_false(r["hidden"].has("nape"), "the hidden short hair does not hide the nape")
	var long := CharacterParts.resolve(_look([["body_standard", 0], ["hair_long", 0], ["hat_cap", 0]]))
	assert_true(long["hidden"].has("nape"), "long hair under a cap still covers the nape")


func test_cycle_part_goes_through_none_for_optional_slots() -> void:
	var look := _look([["body_standard", 0], ["top_tshirt", 0], ["bottom_jeans", 0]])
	var seen := []
	for i in CharacterParts.parts_for("hat").size() + 1:
		look = CharacterParts.cycle_part(look, "hat", 1)
		var hat: Array = look.filter(func(e): return CharacterParts.part(e["id"])["slot"] == "hat")
		seen.append(hat[0]["id"] if hat.size() > 0 else "")
		assert_eq(CharacterParts.validate(look), "")
	assert_true("" in seen and "hat_cap" in seen and "hat_beanie" in seen, "%s" % [seen])
	assert_eq(seen[-1], "", "back to no hat after a full turn")


func test_cycle_part_never_removes_a_required_slot() -> void:
	var look := _look([["body_standard", 0]])
	var seen := {}
	for i in 3:
		look = CharacterParts.cycle_part(look, "body", 1)
		var bodies: Array = look.filter(func(e): return CharacterParts.part(e["id"])["slot"] == "body")
		assert_eq(bodies.size(), 1, "always a body")
		seen[bodies[0]["id"]] = true
	assert_eq(seen.size(), 3, "the three body shapes in turn: %s" % [seen.keys()])


func test_cycle_color_wraps() -> void:
	var look := _look([["body_standard", 0], ["hat_cap", 0]])
	var cs: Array = CharacterParts.part("hat_cap")["colors"]
	look = CharacterParts.cycle_color(look, "hat", -1)
	assert_eq(look[1]["color"], cs[-1])
	look = CharacterParts.cycle_color(look, "hat", 1)
	assert_eq(look[1]["color"], cs[0])
	assert_eq(CharacterParts.cycle_color(look, "beard", 1), look, "empty slot: nothing to recolour")
