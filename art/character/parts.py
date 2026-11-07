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
import bpy, bmesh, math, os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

OUT = os.path.join(ROOT, "assets/character/parts")
os.makedirs(OUT, exist_ok=True)

rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.location, pb.rotation_quaternion, pb.scale = (0, 0, 0), (1, 0, 0, 0), (1, 1, 1)
    pb.rotation_euler = (0, 0, 0)
bpy.context.scene.frame_set(0)
bones = rig.data.bones
src = me.data


def material(name, hexstr):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = lin(hexstr)
    bsdf.inputs["Roughness"].default_value = 1.0
    m.diffuse_color = lin(hexstr)
    return m


def bone_head(name):
    return rig.matrix_world @ bones[name].head_local


groups = {g.index: g.name for g in me.vertex_groups}
HEAD = bone_head("DEF-head")
HEAD_TOP = max(v.co.z for v in src.vertices
        if max(v.groups, key=lambda g: g.weight, default=None) is not None
        and groups[max(v.groups, key=lambda g: g.weight).group] == "DEF-head")
HS = HEAD_TOP - HEAD.z  # head height above its bone
RIM = HEAD.z + SCALP * HS  # a hat's rim: the scalp's lower edge


def face_bone(poly):
    w = {}
    for vi in poly.vertices:
        for g in src.vertices[vi].groups:
            w[groups[g.group]] = w.get(groups[g.group], 0.0) + g.weight
    return max(w, key=w.get) if w else "DEF-spine.003"


# Each face: index, dominant bone, centre, region (from the body's material).
faces = [(p.index, face_bone(p), p.center.copy(), src.materials[p.material_index].name) for p in src.polygons]
normals = [v.normal.copy() for v in src.vertices]  # of the whole mesh: no seams where a cut stops


def in_regions(*names):
    return lambda i, b, c, r: r in names


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


def extract(name, keep, offset, mats, mat_of=None):
    """A copy of the body with only the faces keep(i, bone, centre, region), pushed `offset` metres along
    the normals; weights and armature modifier kept."""
    o = me.copy()
    o.data = src.copy()
    o.name = o.data.name = name
    bpy.context.scene.collection.objects.link(o)
    mesh = o.data
    for v in mesh.vertices:
        v.co += normals[v.index] * offset
    mesh.materials.clear()
    for m in mats:
        mesh.materials.append(m)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    drop = []
    for i, b, c, r in faces:
        if keep(i, b, c, r):
            bm.faces[i].material_index = mat_of(i, b, c, r) if mat_of else 0
        else:
            drop.append(bm.faces[i])
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    o.shape_key_clear()  # the body's keys came with the copy; skinned parts get theirs by transfer_morphs
    return o


def _carry(vgroups, names, mr):
    """(C, H) of a vertex for a body shape: at rest the game moves it to C (x + k) + H (add_morph_keys)."""
    ws = sorted(((g.weight, names[g.group]) for g in vgroups if g.weight > 0), reverse=True)[:4]
    tot = sum(w for w, _ in ws)
    C = sum(w / tot * float(mr["cum"][n]) for w, n in ws)
    H = Vector((0, 0, 0))
    for w, n in ws:
        H += w / tot * (Vector(mr["heads"][n].tolist()) - float(mr["cum"][n]) * Vector(mr["base"][n].tolist()))
    return C, H


def transfer_morphs(o, regions=None):
    """Gives a skinned part the body's shape keys (morph_<id>), so it follows every body shape. Each vertex
    of the part is tied to the point of the body straight under it at rest (a ray in along its normal onto
    a face turned the same way, or the nearest point): in a body shape, the vertex goes where that point
    goes, plus its own height over the body, scaled like the body there; its shape key is solved with its
    own bone weights, like the body's (add_morph_keys). regions: the body regions the part covers (the
    ties stay on them; at a fold the ray could land on a neighbour). Works for any part modelled over the
    body, not only the ones cut from it, like Blender's Data Transfer with a projection."""
    keys = me.data.shape_keys.key_blocks[1:] if me.data.shape_keys else []
    if not keys:
        return
    names = {g.index: g.name for g in me.vertex_groups}
    onames = {g.index: g.name for g in o.vertex_groups}
    tris = [t.vertices[:] for t in _body_tris()
            if regions is None or src.materials[t.material_index].name in regions]
    base = [v.co.copy() for v in src.vertices]
    bvh = BVHTree.FromPolygons(base, tris)
    shaped = {}  # body shape -> (body vertices where the game puts them at rest, their C)
    for k in keys:
        mr = MORPH_RIG[k.name[len("morph_"):]]
        pos, cs = [], []
        for v in src.vertices:
            C, H = _carry(v.groups, names, mr)
            pos.append(C * k.data[v.index].co + H)
            cs.append(C)
        shaped[k.name] = (pos, cs)
    o.data.update()
    o.shape_key_add(name="Basis", from_mix=False)
    new = [o.shape_key_add(name=k.name, from_mix=False) for k in keys]
    for v in o.data.vertices:
        loc, nrm, ti, _ = bvh.ray_cast(v.co, -v.normal, 0.05)
        if loc is None or nrm.dot(v.normal) < 0.5:
            loc, _, ti, _ = bvh.find_nearest(v.co)
        a, b, c = tris[ti]
        w = barycentric(loc, base[a], base[b], base[c])
        for k, nk in zip(keys, new):
            pos, cs = shaped[k.name]
            at = w[0] * pos[a] + w[1] * pos[b] + w[2] * pos[c]
            scale = w[0] * cs[a] + w[1] * cs[b] + w[2] * cs[c]
            target = at + scale * (v.co - loc)
            C, H = _carry(v.groups, onames, MORPH_RIG[k.name[len("morph_"):]])
            nk.data[v.index].co = (target - H) / C


_tris_cache = []


def _body_tris():
    if not _tris_cache:
        src.calc_loop_triangles()
        _tris_cache.extend(src.loop_triangles)
    return _tris_cache


def barycentric(p, a, b, c):
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
    d20, d21 = v2.dot(v0), v2.dot(v1)
    den = d00 * d11 - d01 * d01
    if abs(den) < 1e-12:
        return (1.0, 0.0, 0.0)
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    return (1.0 - v - w, v, w)


def to_bone_space(o, bone):
    """Makes o a plain mesh in the space of `bone`: origin at its head, model axes."""
    o.parent = None
    o.modifiers.clear()
    o.vertex_groups.clear()
    o.matrix_world = rig.matrix_world.copy()
    bpy.context.view_layer.update()
    o.data.transform(o.matrix_world)
    o.data.transform(Matrix.Translation(-bone_head(bone)))
    o.matrix_world = Matrix.Identity(4)
    return o


def prim(kind, size, loc, mat, rot=(0, 0, 0), bevel=0.0, cut_below=None, segments=16, caps=True):
    if kind == "box":
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=segments, radius=size[0], depth=size[2], location=loc,
                rotation=rot, end_fill_type="NGON" if caps else "NOTHING")
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=segments // 2, radius=1.0, location=loc)
    o = bpy.context.active_object
    o.scale = size if kind != "cyl" else (1, 1, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        b = o.modifiers.new("b", "BEVEL")
        b.width, b.segments = bevel, 2
        bpy.ops.object.modifier_apply(modifier="b")
    if cut_below is not None:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if (o.matrix_world @ v.co).z < cut_below], context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
    o.data.materials.append(mat)
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for p in objs:
        p.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.name = o.data.name = name
    return o


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, path), export_format="GLB", use_selection=True,
            export_animations=False, export_apply=False, export_extras=False, export_yup=True,
            export_morph_normal=False)  # like the body's: the shape keys keep the base normals


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


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

# Hat domes are sized on the skull itself: an ellipsoid centred at the rim, through the skull's extents
# above the rim, grown until every skull vertex above the rim is inside, plus a margin (covers the facets
# of the 16-segment sphere). tests/test_character_head_parts.gd checks the result in game.
skull = [src.vertices[vi].co.copy() for i, b, c, r in faces if r in ("scalp", "nape", "head")
        for vi in src.polygons[i].vertices]
skull = [v for v in skull if v.z > RIM]
cx = (min(v.x for v in skull) + max(v.x for v in skull)) / 2
cy = (min(v.y for v in skull) + max(v.y for v in skull)) / 2
r = Vector((max(abs(v.x - cx) for v in skull), max(abs(v.y - cy) for v in skull), max(v.z for v in skull) - RIM))
grow = max(math.sqrt(((v.x - cx) / r.x) ** 2 + ((v.y - cy) / r.y) ** 2 + ((v.z - RIM) / r.z) ** 2) for v in skull)
dome = r * grow + Vector((0.012, 0.012, 0.012))
print("## skull above rim: centre", (round(cx, 3), round(cy, 3)), "radii", [round(x, 3) for x in r],
        "grow", round(grow, 3), "dome", [round(x, 3) for x in dome])
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
