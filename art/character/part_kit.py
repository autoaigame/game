# Tools to build character parts in Blender, on the base body. Used two ways:
#
# - by art/character/parts.py, inside the Blender session of art/character/body.py (the parts of the
#   repository, made with the body): setup(me, rig, ...) with the body being built;
# - by a part's own script, art/character/parts/<id>.py (a new part, without rebuilding the body):
#   load_body(root) reads assets/character/body.glb and data/character/morphs.json, then calls setup.
#
# Blender axes: metres, Z up, the model faces -Y. glTF and Godot: +Y up, facing +Z (the exporter converts).
# Sizes are fractions of the head's height (HS) or relative to bones, never absolute heights.
# Material names starting with "main" take the colour the player chooses; the others keep their own, which
# must be a palette colour (data/palette.json). See docs/character-parts.md.
import json, math, os
import bpy, bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

# Same values as art/character/body.py.
SCALP = 0.72  # a hat's rim above the head bone, as a fraction of the head's height
REGIONS = ["head", "scalp", "nape", "torso", "arms_upper", "arms_lower", "hands", "hips", "legs_upper", "legs_lower",
        "feet"]

me = rig = src = bones = None
ROOT = OUT = ""
MORPH_RIG = {}
HEAD = HEAD_TOP = HS = RIM = None
groups, faces, normals = {}, [], []
_tris_cache = []


def lin(hexstr):
    """sRGB hex (no #) to the linear RGBA Blender stores."""
    c = [int(hexstr[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1.0]


def setup(body, armature, root, morph_rig, scalp=SCALP):
    """body: the body as one mesh, one material per region (named after it), its shape keys morph_<id>;
    armature: its rig, in the rest pose."""
    global me, rig, src, bones, ROOT, OUT, MORPH_RIG, HEAD, HEAD_TOP, HS, RIM, groups, faces, normals
    me, rig, src, bones = body, armature, body.data, armature.data.bones
    ROOT, MORPH_RIG = root, morph_rig
    OUT = os.path.join(ROOT, "assets/character/parts")
    os.makedirs(OUT, exist_ok=True)
    rig.animation_data_create()
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.location, pb.rotation_quaternion, pb.scale = (0, 0, 0), (1, 0, 0, 0), (1, 1, 1)
        pb.rotation_euler = (0, 0, 0)
    bpy.context.scene.frame_set(0)
    groups = {g.index: g.name for g in me.vertex_groups}
    HEAD = bone_head("DEF-head")
    HEAD_TOP = max(v.co.z for v in src.vertices
            if max(v.groups, key=lambda g: g.weight, default=None) is not None
            and groups[max(v.groups, key=lambda g: g.weight).group] == "DEF-head")
    HS = HEAD_TOP - HEAD.z  # head height above its bone
    RIM = HEAD.z + scalp * HS  # a hat's rim: the scalp's lower edge
    # Each face: index, dominant bone, centre, region (from the body's material).
    faces = [(p.index, face_bone(p), p.center.copy(), src.materials[p.material_index].name) for p in src.polygons]
    normals = [v.normal.copy() for v in src.vertices]  # of the whole mesh: no seams where a cut stops
    _tris_cache.clear()


def load_body(root):
    """Reads the base body from assets/character/body.glb (its regions joined back into one mesh) and the
    body shapes from data/character/morphs.json, then setup(). For a part's own script."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(root, "assets/character/body.glb"))
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    regions = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith("body_")]
    for o in regions:
        o.data.materials[0].name = "glb_" + o.name  # frees the region's name
        m = o.data.materials[0].copy()
        m.name = o.name[len("body_"):]
        o.data.materials.clear()
        o.data.materials.append(m)
    for o in bpy.context.scene.objects:  # the clips are not needed: keep only the rest pose
        if o.animation_data:
            o.animation_data.action = None
    for k, o in enumerate(regions):  # which region each vertex came from, for weld_seams
        a = o.data.attributes.new("kit_region", "INT", "POINT")
        for v in a.data:
            v.value = k
    bpy.ops.object.select_all(action="DESELECT")
    for o in regions:
        o.select_set(True)
    bpy.context.view_layer.objects.active = regions[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = body.data.name = "body"
    weld_seams(body.data)
    setup(body, arm, root, _morph_rig(arm, root))
    return body, arm


def weld_seams(mesh):
    """Welds back what the glb split: the cuts between regions and the texture seams (same place, same
    normal). Vertices the body always had apart (sharp edges: same place, other normal) stay apart, so a
    part made here matches one made with the body by art/character/body.py."""
    from mathutils.kdtree import KDTree
    region = mesh.attributes["kit_region"].data
    nrm = [None] * len(mesh.vertices)
    cn = mesh.corner_normals
    for li, loop in enumerate(mesh.loops):
        if nrm[loop.vertex_index] is None:
            nrm[loop.vertex_index] = Vector(cn[li].vector)
    kd = KDTree(len(mesh.vertices))
    for v in mesh.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    parent = list(range(len(mesh.vertices)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for v in mesh.vertices:
        for _, j, _ in kd.find_range(v.co, 1e-5):
            if j <= v.index:
                continue
            other_region = region[j].value != region[v.index].value
            if other_region or nrm[j].dot(nrm[v.index]) > 0.999:
                parent[find(j)] = find(v.index)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bmesh.ops.weld_verts(bm, targetmap={bm.verts[i]: bm.verts[find(i)] for i in range(len(parent)) if find(i) != i})
    bm.to_mesh(mesh)
    bm.free()
    mesh.attributes.remove(mesh.attributes["kit_region"])
    mesh.update()


def _morph_rig(arm, root):
    """Per body shape {"base", "heads", "cum"} as art/character/body.py makes it, from morphs.json (glTF
    axes) and the rig."""
    with open(os.path.join(root, "data/character/morphs.json")) as f:
        morphs = json.load(f)["morphs"]
    bs = arm.data.bones
    base = {b.name: Vector(b.head_local) for b in bs}
    out = {}
    for mid, m in morphs.items():
        heads = {n: Vector((h[0], -h[2], h[1])) for n, h in m["heads"].items()}
        cum = {}

        def walk(b):
            cum[b.name] = float(m["scales"].get(b.name, 1.0)) * (cum[b.parent.name] if b.parent else 1.0)
            for c in b.children:
                walk(c)
        for b in bs:
            if b.parent is None:
                walk(b)
        out[mid] = {"base": base, "heads": {n: heads.get(n, base[n]) for n in base}, "cum": cum}
    return out


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


def face_bone(poly):
    w = {}
    for vi in poly.vertices:
        for g in src.vertices[vi].groups:
            w[groups[g.group]] = w.get(groups[g.group], 0.0) + g.weight
    return max(w, key=w.get) if w else "DEF-spine.003"


def in_regions(*names):
    """A face filter for extract(): the faces of these body regions."""
    return lambda i, b, c, r: r in names


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
        H += w / tot * (Vector(tuple(mr["heads"][n])) - float(mr["cum"][n]) * Vector(tuple(mr["base"][n])))
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
    """A box, a cylinder ("cyl", size = (radius, _, depth)) or an ellipsoid ("sphere", size = radii), at
    `loc` in the body's space, with one material."""
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


def export_skinned(pid, o, regions):
    """A skinned part: the body's shape keys, then <id>.glb with the rig."""
    transfer_morphs(o, regions)
    export(pid + ".glb", [rig, o])
    return tris(o)


def export_rigid(pid, objs, bone):
    """A rigid part: the objects joined, moved into the space of `bone`, then <id>.glb."""
    o = join(objs, pid)
    to_bone_space(o, bone)
    export(pid + ".glb", [o])
    return tris(o)


def skull_dome(margin=0.012):
    """(cx, cy, radii): an ellipsoid centred at (cx, cy, RIM), through the skull's extents above the rim,
    grown until every skull vertex above the rim is inside, plus `margin` (covers the facets of a
    16-segment sphere). The base of a hat: tests/test_character_head_parts.gd checks it on every body
    shape and in motion."""
    skull = [src.vertices[vi].co.copy() for i, b, c, r in faces if r in ("scalp", "nape", "head")
            for vi in src.polygons[i].vertices]
    skull = [v for v in skull if v.z > RIM]
    cx = (min(v.x for v in skull) + max(v.x for v in skull)) / 2
    cy = (min(v.y for v in skull) + max(v.y for v in skull)) / 2
    r = Vector((max(abs(v.x - cx) for v in skull), max(abs(v.y - cy) for v in skull), max(v.z for v in skull) - RIM))
    grow = max(math.sqrt(((v.x - cx) / r.x) ** 2 + ((v.y - cy) / r.y) ** 2 + ((v.z - RIM) / r.z) ** 2) for v in skull)
    dome = r * grow + Vector((margin, margin, margin))
    print("## skull above rim: centre", (round(cx, 3), round(cy, 3)), "radii", [round(x, 3) for x in r],
            "grow", round(grow, 3), "dome", [round(x, 3) for x in dome])
    return cx, cy, dome


def save_blend(path, part):
    """Saves the scene (the body, its rig, `part`) for modelling by hand, with the game's camera: Z up, the
    model faces -Y, orthographic, 30 degrees above, 45 degrees around. Edit the object named after the part,
    keep its name, then export it with art/character/export_part.py."""
    cam = bpy.data.objects.new("game_camera", bpy.data.cameras.new("game_camera"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.4
    bpy.context.scene.collection.objects.link(cam)
    el, az = math.radians(30), math.radians(45)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam.location = Vector((0, 0, 0.9)) + 6 * d
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    me.hide_select = True  # the body is a reference: never exported with a part
    part.select_set(True)
    bpy.context.view_layer.objects.active = part
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    open(os.path.join(os.path.dirname(os.path.abspath(path)), ".gdignore"), "a").close()  # Godot must not import .blend files
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(path))
    print("## saved", path)
