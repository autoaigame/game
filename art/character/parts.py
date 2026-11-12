# The character parts in assets/character/parts/, built on the base body. Run by art/character/body.py
# in the same Blender session, before the body is split into its regions, so every part sees the exact
# rest pose and skin weights of the body:
#
#   blender -b --python art/character/body.py -- <AnimationLibrary_Godot_Standard.glb> <repo root>
#
# Globals given by body.py: me (the body mesh, one material per region, one shape key per body shape), rig,
# ROOT, REGIONS, SCALP, lin, MORPH_RIG (per body shape: bone heads and scales, see add_morph_keys).
#
# Two kinds of part (data/character/parts/<id>.json says which):
# - skinned parts (tops, trousers, boots): the rig and one mesh weighted to it, deformed by the body's
#   skeleton in game. They are copies of the body's own faces of the regions they cover, pushed out along
#   the normals, so they follow it exactly. Godot binds them to the body's bones by name;
# - rigid parts (hats, hair, beards, bag): one plain mesh in the space of the bone it hangs from, origin at
#   the bone's head, axes of the model (glTF: +Y up, the model faces +Z). The game puts it on a
#   BoneAttachment3D of that bone.
# Sizes are fractions of the head's height (HS) or relative to bones, never absolute heights, so a part
# follows the body's proportions. Body shapes: a skinned part gets the body's shape keys (morph_<id>) by
# transfer_morphs(), so it follows every body shape; a rigid part follows its bone (a hat scales with the
# head). Material names starting with "main" take the colour the player
# chooses; the others keep theirs.
import math, os, sys
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import part_kit as K  # the tools every part script uses, on this body
from part_kit import material, bone_head, extract, in_regions, transfer_morphs, prim, join, to_bone_space, export, tris

K.setup(me, rig, ROOT, MORPH_RIG, SCALP)
src, faces, HEAD, HS, RIM = K.src, K.faces, K.HEAD, K.HS, K.RIM



def is_hair(i, b, c, r):
    return r in ("scalp", "nape")


def is_beard(i, b, c, r):
    rel = c - HEAD
    return r == "head" and rel.z < 0.30 * HS and rel.z > 0.02 * HS and rel.y < -0.12 * HS


def is_goatee(i, b, c, r):
    return is_beard(i, b, c, r) and abs(c.x) < 0.16 * HS and (c - HEAD).z < 0.24 * HS


def is_bowl(i, b, c, r):
    """Hair down the sides and back to the ears, the face left clear."""
    rel = c - HEAD
    return r in ("scalp", "nape") or (r == "head" and rel.z > 0.50 * HS and rel.y > -0.22 * HS)


def is_crest(i, b, c, r):
    return r == "scalp" and abs(c.x) < 0.16 * HS


report = {}

# ---- skinned garments ------------------------------------------------------------------------------
SPINE_Y = bone_head("DEF-spine.002").y


def open_jacket(i, b, c, r):
    """Torso and arms, open down the front over what is worn under it."""
    if r == "torso" and abs(c.x) < 0.075 and c.y < SPINE_Y - 0.04:
        return False
    return r in ("torso", "arms_upper", "arms_lower")


garments = {  # id: faces kept, height over the skin, colour, regions covered
    "top_tshirt": (in_regions("torso", "arms_upper"), 0.016, "a39b86", ("torso", "arms_upper")),
    "jacket_field": (open_jacket, 0.030, "8f8a63", ("torso", "arms_upper", "arms_lower")),
    "bottom_jeans": (in_regions("hips", "legs_upper", "legs_lower"), 0.014, "455466", ("hips", "legs_upper", "legs_lower")),
    "bottom_shorts": (in_regions("hips", "legs_upper"), 0.012, "6e6948", ("hips", "legs_upper")),
    "feet_boots": (in_regions("feet"), 0.017, "51433a", ("feet",)),
}
for gid, (keep, off, col, covered) in garments.items():
    o = extract(gid, keep, off, [material("main." + gid, col)])
    transfer_morphs(o, covered)
    export(gid + ".glb", [rig, o])
    report[gid] = tris(o)


# ---- rigid head parts ------------------------------------------------------------------------------
def head_part(pid, objs):
    o = join(objs, pid)
    to_bone_space(o, "DEF-head")
    export(pid + ".glb", [o])
    report[pid] = tris(o)
    return o


def back_of_head_slab(top):
    """Long hair hanging down the back of the head, from `top` to the base of the neck."""
    low = bone_head("DEF-neck").z - 0.05 * HS
    return prim("box", (0.62 * HS, 0.16 * HS, top - low), (0, HEAD.y + 0.36 * HS, (top + low) / 2), hair_m,
            bevel=0.05 * HS)


hair_m = material("main.hair", "3a2f27")
head_part("hair_short", [extract("hs", is_hair, 0.012, [hair_m])])
head_part("hair_bowl", [extract("hb", is_bowl, 0.018, [hair_m])])
head_part("hair_crest", [extract("hc", is_crest, 0.05, [hair_m])])
bun_at = (0, HEAD.y + 0.56 * HS, HEAD.z + 0.80 * HS)
head_part("hair_bun", [extract("hn", is_hair, 0.012, [hair_m]), prim("sphere", (0.2 * HS, 0.18 * HS, 0.2 * HS), bun_at, hair_m, segments=12)])
head_part("hair_long", [extract("hl", is_hair, 0.014, [hair_m]), back_of_head_slab(HEAD.z + 0.70 * HS)])
head_part("hair_long_under", [back_of_head_slab(RIM - 0.01)])  # what hair_long keeps under a hat
beard_m = material("main.beard", "3a2f27")
head_part("beard_full", [extract("bf", is_beard, 0.014, [beard_m])])
head_part("beard_short", [extract("bs", is_beard, 0.007, [beard_m])])
head_part("beard_goatee", [extract("bg", is_goatee, 0.012, [beard_m])])

# Hat domes are sized on the skull itself (part_kit.skull_dome). tests/test_character_head_parts.gd checks
# the result in game.
cx, cy, dome = K.skull_dome()
cap_m = material("main.cap", "6e6948")
head_part("hat_cap", [prim("sphere", dome, (cx, cy, RIM), cap_m, cut_below=RIM),
        prim("box", (dome.x * 1.05, dome.y * 0.75, 0.014), (cx, cy - dome.y - dome.y * 0.3, RIM + 0.008), cap_m,
                rot=(math.radians(-8), 0, 0), bevel=0.004)])
beanie_m = material("main.beanie", "6b5a4c")
head_part("hat_beanie", [prim("sphere", dome + Vector((0.006, 0.006, 0.08 * HS)), (cx, cy, RIM), beanie_m, cut_below=RIM),
        prim("cyl", (max(dome.x, dome.y) + 0.01, 0, 0.13 * HS), (cx, cy, RIM + 0.05 * HS), beanie_m, caps=False)])

# ---- bag on the upper spine -------------------------------------------------------------------------
bag_m = material("main.bag", "2f3a46")
strap_m = material("fixed.strap", "6b5a4c")
roll_m = material("fixed.roll", "8f8a63")
s3 = bone_head("DEF-spine.003")
back = max(v.co.y for v in src.vertices if abs(v.co.x) < 0.05 and abs(v.co.z - s3.z) < 0.05)
bag = join([prim("box", (0.40, 0.22, 0.48), (0, back + 0.12, s3.z - 0.06), bag_m, bevel=0.03),
        prim("box", (0.30, 0.06, 0.18), (0, back + 0.25, s3.z - 0.14), strap_m, bevel=0.015),
        prim("cyl", (0.075, 0, 0.44), (0, back + 0.13, s3.z + 0.17), roll_m, rot=(0, math.pi / 2, 0), segments=12)],
        "back_bag")
bag.matrix_world = Matrix.Identity(4)
bag.data.transform(Matrix.Translation(-s3))
export("back_bag.glb", [bag])
report["back_bag"] = tris(bag)
print("## parts", report)
