extends TestCase

## Body shapes (client/character_morph.gd, data/character/morphs.json): on the common skeleton and rest
## pose, the bones' changes and the shape keys together give each shape its height, feet on the ground.

const Pose := preload("res://tests/character_pose.gd")


## [lowest, highest] point of the body's skin at rest in a body shape (CPU skinning, shape keys included).
static func _extent(body: String) -> Vector2:
	var root := CharacterRig.build(Pose.look([[body, 0], ["top_tshirt", 0], ["bottom_jeans", 0]]))
	var sk := Pose.skeleton(root)
	sk.reset_bone_poses()
	CharacterMorph.new(sk, root.get_meta("morph")).apply(sk)
	var lo := INF
	var hi := -INF
	for mi in sk.get_children():
		if mi is MeshInstance3D and String(mi.name).begins_with("body_"):
			for p in Pose.skinned(mi, sk)["points"]:
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
	root.free()
	return Vector2(lo, hi)


func test_every_body_shape_has_its_height_and_stands_on_the_ground() -> void:
	var base: float = Character3D.clips()["height_m"]
	for body in CharacterParts.parts_for("body"):
		var morph: String = CharacterParts.part(body)["morph"]
		var want: float = base if morph == CharacterMorph.BASE else CharacterMorph.shapes()[morph]["height_m"]
		var e := _extent(body)
		assert_almost(e.y, want, 0.01, "%s: top of the head" % body)
		assert_almost(e.x, 0.0, 0.01, "%s: soles on the ground" % body)


## The three shapes really differ: stocky shorter with a bigger head, lean taller, both under the name.
func test_shapes_differ_and_stay_under_the_name() -> void:
	var std := _extent("body_standard").y
	assert_true(_extent("body_stocky").y < std - 0.1, "stocky is shorter")
	assert_true(_extent("body_lean").y > std + 0.03, "lean is taller")
	var px_per_m: float = Character3D.HEAD_PX / std
	for id in CharacterMorph.shapes():
		var top: float = CharacterMorph.shapes()[id]["height_m"] * px_per_m
		assert_true(top <= WalkAnim.HEAD_PX, "%s: head %.1f px above the feet, under the name" % [id, top])
	var stocky: Dictionary = CharacterMorph.shapes()["stocky"]
	assert_true(stocky["scales"]["DEF-head"] > 1.05, "stocky: a bigger head")


## A longer stride for longer legs, so the feet of every shape stay planted.
func test_stride_follows_the_legs() -> void:
	var lean: float = CharacterMorph.shapes()["lean"]["stride_scale"]
	var stocky: float = CharacterMorph.shapes()["stocky"]["stride_scale"]
	assert_true(lean > 1.0 and stocky < 1.0, "lean %.2f, stocky %.2f" % [lean, stocky])
	assert_almost(Character3D.advance_phase(0.0, 1.0, 0.1, lean), Character3D.advance_phase(0.0, 1.0, 0.1) / lean, 0.0001)


## Unknown or base shapes change nothing; the editor lists the base first.
func test_base_and_unknown_shapes_change_nothing() -> void:
	assert_eq(CharacterMorph.ids()[0], CharacterMorph.BASE)
	assert_true(CharacterMorph.exists("lean") and not CharacterMorph.exists("giant"))
	var root := CharacterRig.build(Pose.look([["body_standard", 0]]))
	var sk := Pose.skeleton(root)
	sk.reset_bone_poses()
	var before := sk.get_bone_pose(sk.find_bone("DEF-head"))
	CharacterMorph.new(sk, "giant").apply(sk)
	assert_eq(sk.get_bone_pose(sk.find_bone("DEF-head")), before)
	root.free()
