# The base body of the 3D character: the Quaternius Universal Animation Library mannequin (CC0,
# https://opengameart.org/content/universal-animation-library) reshaped into a sturdy stylised adult (head
# a fifth of the height), on the source skeleton (same 53 bone names, hierarchy and bone orientations).
#
#   blender -b --python art/character/body.py -- <AnimationLibrary_Godot_Standard.glb> <repo root>
#
# Writes assets/character/body.glb (rig, mesh, clips idle, walk, jog, sprint) and
# assets/character/body_clips.json (what client/character_3d.gd reads), then runs art/character/parts.py
# (the character parts, on this body). See art/character/BODY.md.
#
# How the body is made, without touching the animations' rotations:
# - every bone gets a 3x3 shape matrix M (length along the bone, width/depth across it, or a uniform scale
#   for head, hands and feet); a bone's new head is where its parent's transform sends the old head, its
#   new tail is new head + M (old tail - old head). Bone directions and rolls never change, so the clips'
#   rotation keys (relative to the rest pose) still mean the same pose;
# - the mesh follows by linear blend skinning from the old rest to the new rest (the same weights);
# - the model is moved down so the soles touch z = 0; the head scale is solved so the head (top to chin)
#   is a fifth of the total height;
# - location keys (the hips' bob and sway) are scaled by the leg factor; the upper arms get a constant
#   outward offset (degrees) so thicker arms swing clear of the wider torso; the hips are lifted on the
#   poses where a sole would go below the ground.
# Then the mesh is cut along straight lines into one mesh per body region (so a garment can hide the
# skin it covers), each coloured with the default outfit in flat kit-palette colours, checked (feet on
# the ground, arms in the torso, legs in each other: printed) and exported.
import bpy, bmesh, json, math, os, re, sys
import numpy as np
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, ROOT = argv[0], argv[1]

CLIPS = {"Idle_Loop": "idle", "Walk_Loop": "walk", "Jog_Fwd_Loop": "jog", "Sprint_Loop": "sprint"}

# Proportions. head: head height (top of the skull to the chin) over total height. Lengths are factors
# of the source bones; thick: across limbs; torso/hips: (width, depth); hands/feet: uniform scales;
# clavicle: shoulder bone length (shoulder width); arm_out: outward offset of the upper arms, degrees.
BODY = dict(head=1 / 5, legs=0.8, spine=0.9, neck=0.65, clavicle=1.06, arms=0.9, arm_thick=1.05,
        leg_thick=1.06, torso=(1.08, 1.04), hips=(1.06, 1.02), hands=1.12, feet=1.1, feet_len=1.0, arm_out=5.0)

# Body shapes (morphologies). BODY ("standard") is the rest pose every part is modelled on; the others are
# made from it in game, on the same skeleton and rest pose: bones moved and scaled (morphs.json) plus one
# shape key per body shape ("morph_<id>") on the body and on every skinned part, so clothes follow.
MORPHS = {
    "stocky": dict(head=1 / 4, legs=0.62, spine=0.82, neck=0.45, clavicle=1.15, arms=0.78, arm_thick=1.35,
            leg_thick=1.35, torso=(1.3, 1.2), hips=(1.3, 1.2), hands=1.45, feet=1.3, feet_len=1.0, arm_out=9.0),
    "lean": dict(head=1 / 6, legs=0.88, spine=0.95, neck=0.8, clavicle=0.98, arms=0.96, arm_thick=0.92,
            leg_thick=0.93, torso=(0.94, 0.92), hips=(0.93, 0.92), hands=1.05, feet=1.1, feet_len=1.0, arm_out=3.0),
}

# Body regions, top to bottom, and the default outfit: flat colours of the kit palette (sRGB). A region
# is one mesh of the glb, named "body_<region>", with one material named after the region.
REGIONS = ["head", "scalp", "nape", "torso", "arms_upper", "arms_lower", "hands", "hips", "legs_upper", "legs_lower",
        "feet"]
OUTFIT = {"head": "c09576", "scalp": "3a2f27", "nape": "3a2f27", "torso": "8f8a63", "arms_upper": "8f8a63",
        "arms_lower": "8f8a63", "hands": "c09576", "hips": "455466", "legs_upper": "455466",
        "legs_lower": "455466", "feet": "51433a"}
# Height of the scalp's lower edge (a hat's rim) above the head bone, as a fraction of the head's height.
SCALP = 0.62


def lin(hexstr):
    c = [int(hexstr[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1.0]


def fcurves(act):
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out += list(cb.fcurves)
    return out


def load():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    for o in list(bpy.data.objects):
        if o.name not in ("Mannequin", "Rig"):
            bpy.data.objects.remove(o)
    for a in list(bpy.data.actions):
        if a.name not in CLIPS:
            bpy.data.actions.remove(a)
    for a in bpy.data.actions:
        a.name = CLIPS[a.name]
        a.use_fake_user = True
    rig = bpy.data.objects["Rig"]
    rig.animation_data.action = None
    return bpy.data.objects["Mannequin"], rig


def shape(b, p, head_s):
    """Shape matrix of bone b (armature space) for variant parameters p."""
    n = b.name
    d = (b.tail_local - b.head_local).normalized()
    D = np.outer(d, d)
    P = np.eye(3) - D

    def along(length, across):
        if isinstance(across, tuple):  # (width = world x, depth = world y), the rest across stays
            A = np.diag([across[0], across[1], 1.0])
            return length * D + P @ A @ P
        return length * D + across * P

    if n == "root":
        return np.eye(3)
    if n.startswith(("DEF-hand", "DEF-f_", "DEF-thumb")):
        return p["hands"] * np.eye(3)
    if n.startswith(("DEF-foot", "DEF-toe")):
        # Feet: bigger across (width, height) than along; long feet would dig their toes into the ground
        # on the push-off of shortened legs (same ankle angles, a longer lever).
        return along(p["feet_len"], p["feet"])
    if n == "DEF-head":
        return head_s * np.eye(3)
    if n == "DEF-neck":
        return along(p["neck"], (p["torso"][0] * 0.9, p["torso"][1] * 0.9))
    if n.startswith("DEF-spine"):
        return along(p["spine"], p["torso"])
    if n == "DEF-hips":
        return along(p["spine"], p["hips"])
    if n.startswith("DEF-shoulder"):
        return along(p["clavicle"], p["arm_thick"])
    if n.startswith(("DEF-upper_arm", "DEF-forearm")):
        return along(p["arms"], p["arm_thick"])
    if n.startswith(("DEF-thigh", "DEF-shin")):
        return along(p["legs"], p["leg_thick"])
    raise ValueError(n)


def transforms(rig, p, head_s):
    """Per bone: (old head, new head, M) so that T(x) = new_head + M (x - old_head)."""
    T = {}
    for b in rig.data.bones:  # parents come before children in this list
        M = shape(b, p, head_s)
        oh = np.array(b.head_local)
        if b.parent is None:
            nh = oh.copy()
        else:
            ph, pnh, pM = T[b.parent.name]
            nh = pnh + pM @ (oh - ph)
        T[b.name] = (oh, nh, M)
    return T


def skin(me, T):
    """Old rest positions -> new rest positions, by the mesh's own weights."""
    names = {g.index: g.name for g in me.vertex_groups}
    co = np.array([v.co for v in me.data.vertices])
    out = np.zeros_like(co)
    for i, v in enumerate(me.data.vertices):
        acc = np.zeros(3)
        tot = 0.0
        for g in v.groups:
            if g.weight <= 0.0 or names[g.group] not in T:
                continue
            oh, nh, M = T[names[g.group]]
            acc += g.weight * (nh + M @ (co[i] - oh))
            tot += g.weight
        out[i] = acc / tot if tot > 0 else co[i]
    return out


def dominant(me):
    names = {g.index: g.name for g in me.vertex_groups}
    dom = []
    for v in me.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        dom.append(names[best.group] if best else "root")
    return dom


def build(vid, p):
    me, rig = load()
    bones = rig.data.bones
    dom = dominant(me)
    co0 = np.array([v.co for v in me.data.vertices])
    head_idx = [i for i, n in enumerate(dom) if n == "DEF-head"]
    top0 = co0[:, 2].max()

    def solve(head_s):
        T = transforms(rig, p, head_s)
        new = skin(me, T)
        dz = -new[:, 2].min()
        return T, new, dz

    head_s = 1.0
    if p["head"] is not None:
        # height(s) = joint + s * above, head(s) = s * (top - chin), both measured on the s = 1 body.
        T, new, dz = solve(1.0)
        j = T["DEF-head"][1][2] + dz
        hz = new[head_idx, 2] + dz
        above, hh = hz.max() - j, hz.max() - hz.min()
        r = p["head"]
        head_s = r * j / (hh - r * above)
    T, new, dz = solve(head_s)
    new[:, 2] += dz
    for v, c in zip(me.data.vertices, new):
        v.co = c
    me.data.update()

    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    rolls = {}
    for eb in rig.data.edit_bones:
        oh, nh, M = T[eb.name]
        ot = np.array(eb.tail)
        nt = nh + M @ (ot - oh)
        shift = np.array([0, 0, dz if eb.name != "root" else 0.0])
        rolls[eb.name] = eb.roll
        eb.head = Vector(nh + shift)
        eb.tail = Vector(nt + shift)
        eb.roll = rolls[eb.name]
    bpy.ops.object.mode_set(mode="OBJECT")

    for act in bpy.data.actions:
        for fc in fcurves(act):
            if fc.data_path.endswith(".location"):
                for k in fc.keyframe_points:
                    k.co.y *= p["legs"]
                    k.handle_left.y *= p["legs"]
                    k.handle_right.y *= p["legs"]
            fc.update()
        if p["arm_out"]:
            for side, sgn in (("L", -1.0), ("R", 1.0)):
                bn = "DEF-upper_arm." + side
                Rb = rig.data.bones[bn].matrix_local.to_3x3()
                Rw = Matrix.Rotation(math.radians(sgn * p["arm_out"]), 3, "Y")
                off = (Rb.inverted() @ Rw @ Rb).to_quaternion()
                path = 'pose.bones["%s"].rotation_quaternion' % bn
                cs = sorted([fc for fc in fcurves(act) if fc.data_path == path], key=lambda f: f.array_index)
                if len(cs) != 4:
                    continue
                for ki in range(len(cs[0].keyframe_points)):
                    q = Quaternion([cs[i].keyframe_points[ki].co.y for i in range(4)])
                    q2 = off @ q
                    for i in range(4):
                        kp = cs[i].keyframe_points[ki]
                        kp.co.y = q2[i]
                        kp.handle_left.y = q2[i]
                        kp.handle_right.y = q2[i]
                for fc in cs:
                    fc.update()
    return me, rig, head_s, dom


def plant(me, rig, dom):
    """Lifts the body (hips location keys) on the poses where a sole goes below the ground: big feet on
    short legs push their toes into it at the push-off. Never pulls a body down (running has flights)."""
    scene = bpy.context.scene
    feet = [i for i, n in enumerate(dom) if n.startswith(("DEF-foot", "DEF-toe"))]
    hips = rig.data.bones["DEF-hips"]
    to_local = (rig.matrix_world.to_3x3() @ hips.matrix_local.to_3x3()).inverted()
    lifts = {}
    for act in bpy.data.actions:
        rig.animation_data.action = act
        if act.slots:
            rig.animation_data.action_slot = act.slots[0]
        path = 'pose.bones["DEF-hips"].location'
        cs = sorted([fc for fc in fcurves(act) if fc.data_path == path], key=lambda f: f.array_index)
        worst = 0.0
        frames = [k.co.x for k in cs[0].keyframe_points]
        need = []
        for ki, f in enumerate(frames):
            scene.frame_set(int(round(f)))
            ev = me.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = min((ev.matrix_world @ ev.data.vertices[i].co).z for i in feet)
            need.append(max(0.0, -m))
        for ki, lift in enumerate(need):
            if lift <= 0.0:
                continue
            d = to_local @ Vector((0.0, 0.0, lift))
            for i in range(3):
                kp = cs[i].keyframe_points[ki]
                kp.co.y += d[i]
                kp.handle_left.y += d[i]
                kp.handle_right.y += d[i]
            worst = max(worst, lift)
        for fc in cs:
            fc.update()
        lifts[act.name] = round(worst, 4)
    rig.animation_data.action = None
    return lifts


def morph_capture(p):
    """Builds a body shape from the source and returns what the base needs to reach it: the reshaped rest
    positions of the mesh's vertices (same order as the base's), each bone's new head, and the uniform
    scales of the head, hands and feet."""
    me, rig, head_s, dom = build("morph", p)
    co = np.array([v.co for v in me.data.vertices])
    heads = {b.name: np.array(b.head_local) for b in rig.data.bones}
    return {"co": co, "heads": heads, "head_s": head_s, "hands": p["hands"], "feet": p["feet"],
            "arm_out": p["arm_out"], "height": float(co[:, 2].max())}


def bone_scales(m, base_head_s):
    """Uniform scale of each bone of a body shape relative to the base (children inherit it in game)."""
    s = {}
    for side in "LR":
        s["DEF-hand." + side] = m["hands"] / BODY["hands"]
        s["DEF-foot." + side] = m["feet"] / BODY["feet"]
    s["DEF-head"] = m["head_s"] / base_head_s
    return s


MORPH_RIG = {}  ## body shape -> {"base": bone heads, "heads": its bone heads, "cum": scales}, for parts.py


def add_morph_keys(me, rig, base_head_s, captured):
    """One shape key per body shape (first as a point attribute, see keys_from_attributes): where each
    vertex must start so that the game's bone changes (heads
    moved, head, hands and feet scaled) carry it onto the reshaped body. With linear blend skinning at rest
    a bone b moves x to head'_b + c_b (x - head_b) (c_b: its scale times its parents'), so a vertex with
    weights w lands at C (x + k) + H, C = sum w_b c_b, H = sum w_b (head'_b - c_b head_b); solved for k.
    Returns morphs.json's data, in glTF axes (+Y up, facing +Z)."""
    names = {g.index: g.name for g in me.vertex_groups}
    bones = rig.data.bones
    base_heads = {b.name: np.array(b.head_local) for b in bones}
    co = np.array([v.co for v in me.data.vertices])
    # The game keeps the 4 strongest weights, normalized (glTF).
    weights = []
    for v in me.data.vertices:
        ws = sorted(((g.weight, names[g.group]) for g in v.groups if g.weight > 0), reverse=True)[:4]
        tot = sum(w for w, _ in ws)
        weights.append([(w / tot, n) for w, n in ws])
    gl = lambda a: [round(float(a[0]), 5), round(float(a[2]), 5), round(float(-a[1]), 5)]
    out = {}
    for mid, m in captured.items():
        sc = bone_scales(m, base_head_s)
        cum = {}
        for b in bones:  # parents before children
            cum[b.name] = sc.get(b.name, 1.0) * (cum[b.parent.name] if b.parent else 1.0)
        MORPH_RIG[mid] = {"base": base_heads, "heads": m["heads"], "cum": cum}
        # Kept as a point attribute until the mesh is cut into regions: cutting interpolates attributes
        # on the new vertices, but not shape keys.
        attr = me.data.attributes.new("morph_" + mid, "FLOAT_VECTOR", "POINT")
        for i, ws in enumerate(weights):
            C = sum(w * cum[n] for w, n in ws)
            H = sum((w * (m["heads"][n] - cum[n] * base_heads[n]) for w, n in ws), np.zeros(3))
            attr.data[i].vector = Vector((m["co"][i] - H) / C)
        out[mid] = {"height_m": round(m["height"], 4),
                "stride_scale": round(float(m["heads"]["DEF-thigh.L"][2] / base_heads["DEF-thigh.L"][2]), 4),
                "arm_out_deg": round(m["arm_out"] - BODY["arm_out"], 2),
                "heads": {n: gl(h) for n, h in m["heads"].items()},
                "scales": {n: round(v, 5) for n, v in sc.items() if abs(v - 1.0) > 1e-6}}
    return out


def keys_from_attributes(me):
    """The morph_<id> point attributes become shape keys of the same name."""
    names = [a.name for a in me.data.attributes if a.name.startswith("morph_")]
    me.shape_key_add(name="Basis", from_mix=False)
    for n in sorted(names):
        key = me.shape_key_add(name=n, from_mix=False)
        attr = me.data.attributes[n]
        for i in range(len(me.data.vertices)):
            key.data[i].co = attr.data[i].vector
        me.data.attributes.remove(me.data.attributes[n])


def cut_regions(me, rig, dom):
    """Cuts the mesh along straight planes of the rest pose (clean edges for clothes to cover) and gives
    each face the material of its region. The bone decides only which part of the body a face is on
    (head, arm, trunk or legs); the planes decide the rest."""
    mesh = me.data
    mesh.materials.clear()
    for r in REGIONS:
        m = bpy.data.materials.new(r)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = lin(OUTFIT[r])
        bsdf.inputs["Roughness"].default_value = 1.0
        m.diffuse_color = lin(OUTFIT[r])
        mesh.materials.append(m)
    bones = rig.data.bones
    hb = bones["DEF-head"]
    head_top = max(v.co.z for v, n in zip(mesh.vertices, dom) if n == "DEF-head")
    head_j = hb.head_local
    hs = head_top - head_j.z
    waist = bones["DEF-spine.001"].head_local.z
    th = bones["DEF-thigh.L"]
    hem = th.head_local.z + 0.5 * (th.tail_local.z - th.head_local.z)
    knee = bones["DEF-shin.L"].head_local.z
    shoe = bones["DEF-foot.L"].head_local.z + 0.25 * (bones["DEF-shin.L"].head_local.z - bones["DEF-foot.L"].head_local.z)
    ua = bones["DEF-upper_arm.L"]
    sleeve = ua.head_local.x + 0.45 * (ua.tail_local.x - ua.head_local.x)
    # Cut first, so the region edges are straight lines, not the sawtooth of the source triangles (the
    # new vertices get interpolated weights).
    bm = bmesh.new()
    bm.from_mesh(mesh)
    planes = [((0, 0, waist), (0, 0, 1)), ((0, 0, hem), (0, 0, 1)), ((0, 0, knee), (0, 0, 1)),
            ((0, 0, shoe), (0, 0, 1)), ((sleeve, 0, 0), (1, 0, 0)), ((-sleeve, 0, 0), (1, 0, 0))]
    for co, no in planes:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    dom = dominant(me)
    groups = {g.index: g.name for g in me.vertex_groups}
    for poly in mesh.polygons:
        w = {}
        for vi in poly.vertices:
            for g in mesh.vertices[vi].groups:
                w[groups[g.group]] = w.get(groups[g.group], 0.0) + g.weight
        bn = max(w, key=w.get) if w else "DEF-spine.003"
        c = poly.center
        if bn in ("DEF-head", "DEF-neck"):
            rel = c - head_j
            # Scalp: the top of the skull, above SCALP of the head (a hat's rim); nape: the back of the
            # head below it (the model faces -y). Hair covers both, a hat the scalp.
            if bn == "DEF-head" and rel.z > SCALP * hs:
                r = "scalp"
            elif bn == "DEF-head" and rel.y > 0.08 * hs and rel.z > 0.05 * hs:
                r = "nape"
            else:
                r = "head"
        elif bn.startswith(("DEF-hand", "DEF-f_", "DEF-thumb")):
            r = "hands"
        elif bn.startswith(("DEF-shoulder", "DEF-upper_arm", "DEF-forearm")):
            r = "torso" if bn.startswith("DEF-shoulder") and abs(c.x) < sleeve * 0.6 else (
                    "arms_upper" if abs(c.x) < sleeve else "arms_lower")
        elif c.z > waist:
            r = "torso"
        elif c.z > hem:
            r = "hips"
        elif c.z > knee:
            r = "legs_upper"
        elif c.z > shoe:
            r = "legs_lower"
        else:
            r = "feet"
        poly.material_index = REGIONS.index(r)
    unweighted = sum(1 for v in mesh.vertices if not any(g.weight > 0 for g in v.groups))
    assert unweighted == 0, unweighted
    return dom


def split_regions(me):
    """One object per region (body_<region>), each with its region's material only."""
    bpy.ops.object.select_all(action="DESELECT")
    me.select_set(True)
    bpy.context.view_layer.objects.active = me
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    out = []
    for o in bpy.context.selected_objects:
        used = {p.material_index for p in o.data.polygons}
        assert len(used) == 1, used
        m = o.data.materials[used.pop()]
        o.data.materials.clear()
        o.data.materials.append(m)
        o.name = o.data.name = "body_" + m.name
        out.append(o)
    assert sorted(o.name for o in out) == sorted("body_" + r for r in REGIONS), [o.name for o in out]
    return out


def measure(me, rig, dom):
    scene = bpy.context.scene
    fps = scene.render.fps
    clips, checks = {}, {}
    idx = lambda pred: [i for i, n in enumerate(dom) if pred(n)]
    feet = {s: idx(lambda n, s=s: n in ("DEF-foot." + s, "DEF-toe." + s)) for s in "LR"}
    arms = {s: idx(lambda n, s=s: n.endswith("." + s) and n.startswith(("DEF-forearm", "DEF-hand", "DEF-f_", "DEF-thumb")))
            for s in "LR"}
    lower = {s: idx(lambda n, s=s: n in ("DEF-shin." + s, "DEF-foot." + s, "DEF-toe." + s)) for s in "LR"}
    legv = {s: set(idx(lambda n, s=s: n in ("DEF-thigh." + s, "DEF-shin." + s, "DEF-foot." + s, "DEF-toe." + s)))
            for s in "LR"}
    polys = [list(p.vertices) for p in me.data.polygons]
    arm_all = {s: set(idx(lambda n, s=s: n.endswith("." + s) and n.startswith(("DEF-shoulder", "DEF-upper_arm",
            "DEF-forearm", "DEF-hand", "DEF-f_", "DEF-thumb")))) for s in "LR"}
    body_p = {s: [p for p in polys if not any(v in arm_all[s] for v in p)] for s in "LR"}
    leg_p = {s: [p for p in polys if all(v in legv[s] for v in p)] for s in "LR"}

    def hits(bvh, o, d):
        k = 0
        while k < 50:
            loc, _, _, _ = bvh.ray_cast(o, d)
            if loc is None:
                return k
            k += 1
            o = loc + d * 1e-4
        return k

    RAYS = [Vector(v).normalized() for v in ((0.3, 0.2, 1.0), (-0.2, 1.0, 0.3), (1.0, -0.3, -0.2))]

    def inside(co, pts, tri):
        """Deepest point of pts inside the surface tri: odd ray crossings in at least 2 of 3 directions
        (the part's mesh is open where it joins the body), depth = distance to the surface."""
        bvh = BVHTree.FromPolygons(co, tri)
        deep = []
        for i in pts:
            o = Vector(co[i])
            if sum(hits(bvh, o, d) % 2 for d in RAYS) >= 2:
                _, _, _, dist = bvh.find_nearest(o)
                if dist > 0.01:
                    deep.append(dist)
        # A lone vertex is a ray glitch at a seam or a fingertip grazing; a pose counts from 5 vertices
        # more than 1 cm in, and its depth is their median.
        return sorted(deep)[len(deep) // 2] if len(deep) >= 5 else 0.0

    for name in CLIPS.values():
        act = bpy.data.actions[name]
        rig.animation_data.action = act
        if act.slots:
            rig.animation_data.action_slot = act.slots[0]
        f0, f1 = act.frame_range
        n = 240
        samples = []
        for i in range(n):
            f = f0 + (f1 - f0) * i / n
            scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
            samples.append({s: rig.matrix_world @ rig.pose.bones["DEF-foot.%s" % s].head for s in "LR"})
        hips_y = (rig.matrix_world @ rig.pose.bones["DEF-hips"].head).y
        dur = (f1 - f0) / fps
        entry = {"duration_s": round(dur, 4)}
        if name != "idle":
            travel, mids, lands = 0.0, {}, {}
            for side in "LR":
                for i in range(n):
                    a, b = samples[i - 1][side], samples[i][side]
                    if b.y > a.y:
                        travel += b.y - a.y
                    if a.y < hips_y <= b.y and side not in mids:
                        mids[side] = i / n
                    # The foot lands where it stops swinging forward (-y) and starts moving back with
                    # the ground: its front-most point.
                    c = samples[(i + 1) % n][side]
                    if b.y <= a.y and c.y > b.y and side not in lands:
                        lands[side] = i / n
            entry.update({"ground_speed_m_s": round(travel / dur, 4), "stride_m": round(travel, 4),
                    "left_mid_stance": round(mids["L"], 4), "right_mid_stance": round(mids["R"], 4),
                    "left_contact": round(lands["L"], 4), "right_contact": round(lands["R"], 4)})
        clips[name] = entry
        # Checks on the deformed mesh, 24 poses per loop.
        low, high, arm_in, leg_in = [], [], 0.0, 0.0
        arm_frames = leg_frames = 0
        dg = bpy.context.evaluated_depsgraph_get()
        for i in range(24):
            f = f0 + (f1 - f0) * i / 24
            scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
            ev = me.evaluated_get(dg)
            co = [ev.matrix_world @ v.co for v in ev.data.vertices]
            co = [tuple(c) for c in co]
            zs = {s: min(co[j][2] for j in feet[s]) for s in "LR"}
            low.append(min(zs.values()))
            a = max(inside(co, arms[s], body_p[s]) for s in "LR")
            l = max(inside(co, lower[s], leg_p["R" if s == "L" else "L"]) for s in "LR")
            arm_in = max(arm_in, a)
            leg_in = max(leg_in, l)
            arm_frames += a > 0.0
            leg_frames += l > 0.0
        checks[name] = {"sole_min_m": round(min(low), 4), "sole_max_m": round(max(low), 4),
                "arm_in_torso_max_m": round(arm_in, 4), "arm_in_torso_poses": "%d/24" % arm_frames,
                "leg_in_leg_max_m": round(leg_in, 4), "leg_in_leg_poses": "%d/24" % leg_frames}
    rig.animation_data.action = bpy.data.actions["idle"]
    scene.frame_set(0)
    return clips, checks


def rest_check(rig, ref):
    """Largest angle (degrees) between a bone's rest orientation here and in the source rig."""
    worst = 0.0
    for b in rig.data.bones:
        q0 = ref[b.name]
        q1 = b.matrix_local.to_quaternion()
        a = math.degrees(q0.rotation_difference(q1).angle)
        worst = max(worst, min(a, 360.0 - a))
    return worst


_, rig0 = load()
ref = {b.name: b.matrix_local.to_quaternion() for b in rig0.data.bones}
captured = {mid: morph_capture(p) for mid, p in MORPHS.items()}
me, rig, head_s, dom = build("body", BODY)
morphs = add_morph_keys(me, rig, head_s, captured)
lifts = plant(me, rig, dom)
dom = cut_regions(me, rig, dom)
keys_from_attributes(me)
co = [v.co for v in me.data.vertices]
height = max(c.z for c in co)
hz = [c.z for c, n in zip(co, dom) if n == "DEF-head"]
clips, checks = measure(me, rig, dom)
print("## body", json.dumps({"head_scale": round(head_s, 4), "height_m": round(height, 4),
        "head_fraction": round((max(hz) - min(hz)) / height, 4),
        "rest_orientation_change_deg": round(rest_check(rig, ref), 4), "checks": checks, "plant_lift_max_m": lifts,
        "verts": len(me.data.vertices), "tris": sum(len(p.vertices) - 2 for p in me.data.polygons)}))
# The character parts, built on this body before it is split (art/character/parts.py).
parts_py = os.path.join(os.path.dirname(os.path.abspath(__file__)), "parts.py")
if os.path.exists(parts_py):
    import runpy
    runpy.run_path(parts_py, init_globals={"me": me, "rig": rig, "ROOT": ROOT, "REGIONS": REGIONS,
            "SCALP": SCALP, "lin": lin, "MORPH_RIG": MORPH_RIG})
    rig.animation_data.action = None
parts = split_regions(me)
out = os.path.join(ROOT, "assets/character")
os.makedirs(out, exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
for o in parts + [rig]:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "body.glb"), export_format="GLB", use_selection=True,
        export_animation_mode="ACTIONS", export_force_sampling=True, export_frame_step=1,
        export_apply=False, export_extras=False, export_yup=True,
        export_morph_normal=False)  # the keys are not the final shapes (the bones move too): keep the base normals
with open(os.path.join(ROOT, "data/character/morphs.json"), "w") as f:
    text = json.dumps({"comment": "Written by art/character/body.py. Per body shape: the rest heads of the "
            "bones (skeleton space, metres) and the scales of the head, hands and feet the game gives the base "
            "skeleton, the extra outward turn of the upper arms, how much longer the stride is, and the "
            "height. The body and every skinned part carry a shape key morph_<id>.", "morphs": morphs},
            indent="\t", sort_keys=True)
    f.write(re.sub(r"\[\s+([-0-9.]+),\s+([-0-9.]+),\s+([-0-9.]+)\s+\]", r"[\1, \2, \3]", text) + "\n")
with open(os.path.join(out, "body_clips.json"), "w") as f:
    json.dump({"height_m": round(height, 4), "forward": "+z", "clips": clips}, f, indent=1, sort_keys=True)
    f.write("\n")
