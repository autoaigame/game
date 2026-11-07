# Shared tools to make a 3D model from scratch in Blender, by script only: no imported mesh, skeleton or
# animation. Used by the model scripts in this folder (art/models/zombie.py is the complete example):
#
#   blender -b --python art/models/<model>.py -- <repo root>
#
# - Frame: metres, Blender Z up, the model faces -Y (glTF and Godot +Z after export), its left is +X. The
#   origin is on the ground between the feet.
# - Skeleton: make_armature() from a table of (name, parent, head, tail); every bone with roll 0.
# - Mesh: a Builder of simple volumes (tubes with a rounded section along a bone, boxes), each owned by
#   one bone and one material. Clothes are the same tubes a little wider, with a jagged hem.
# - Weights: mixed round each joint by position (skin): every volume that reaches a joint gets the same
#   weights there, so overlapping volumes bend together. Blender's automatic weights (bone heat) gave each
#   separate volume its own bone, and the joints opened (joint_gaps measures it).
# - Poses: a Poser holds rotations in armature axes (each applied in its parent's frame, so a parent's
#   rotation carries its children), aims a bone at a direction, solves a leg or an arm with two-bone IK,
#   and writes the pose as Blender keyframes. Animations are functions of time sampled on every frame.
# - Checks, on the deformed mesh: soles against the ground, how far a planted foot slides, volumes
#   going through each other, and cracks opening at the joints.
import bpy, math, json, os
from mathutils import Vector, Matrix, Quaternion

FPS = 30


def lin(hexstr):
    """sRGB hex to linear RGBA (Blender's base colour; the glTF material stores it as is)."""
    c = [int(hexstr[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1.0]


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def material(name, hexstr):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = lin(hexstr)
    bsdf.inputs["Roughness"].default_value = 1.0
    m.diffuse_color = lin(hexstr)
    return m


def make_armature(name, bones):
    """An armature from [(bone, parent or None, head, tail)], parents first. Bones named 'root' do not
    deform (no weights)."""
    arm = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, parent, head, tail in bones:
        eb = arm.edit_bones.new(bname)
        eb.head, eb.tail, eb.roll = Vector(head), Vector(tail), 0.0
        eb.use_deform = bname != "root"
        if parent:
            eb.parent = arm.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return rig


def _frame(axis):
    """Two unit vectors across an axis: 'side' (closest to +X) and 'front' (closest to -Y)."""
    a = axis.normalized()
    ref = Vector((1, 0, 0)) if abs(a.x) < 0.9 else Vector((0, -1, 0))
    side = (ref - a * ref.dot(a)).normalized()
    front = a.cross(side).normalized()
    if front.dot(Vector((0, -1, 0))) + front.dot(Vector((0, 0, 1))) * 0.01 < 0:
        front = -front
    return side, front


class Builder:
    """Simple volumes gathered into one mesh. Each vertex remembers its owner bone and its volume."""

    def __init__(self):
        self.verts, self.faces, self.mats, self.owner = [], [], [], []
        self.fixed = []  # per vertex: True when it follows its bone alone (balls), not the joint blend
        self.volume = []  # per vertex: the index of its volume (one tube or box)
        self.volumes = []  # per volume: {"bone", "faces" (vertex index tuples), "closed"}
        self.materials = []  # names, in material index order
        self.girth = {}  # bone name prefix -> factor on the width and depth of its tubes

    def _girth(self, bone):
        for prefix, f in self.girth.items():
            if bone.startswith(prefix):
                return f
        return 1.0

    def _mat(self, name):
        if name not in self.materials:
            self.materials.append(name)
        return self.materials.index(name)

    def _start(self, bone, closed, ball=False):
        self.volumes.append({"bone": bone, "faces": [], "closed": closed, "ball": ball})

    def _face(self, f, mi):
        self.faces.append(f)
        self.mats.append(mi)
        self.volumes[-1]["faces"].append(f)

    def _add(self, co, bone, fixed=False):
        self.fixed.append(fixed)
        self.volume.append(len(self.volumes) - 1)
        self.verts.append(tuple(co))
        self.owner.append(bone)
        return len(self.verts) - 1

    def tube(self, a, b, sections, bone, mat, n=8, square=0.55, hem=None, cap=(True, True),
            shift=(0.0, 0.0), ring_gap=None):
        """A tube from a to b. sections: [(t, width, depth)] along it (t 0..1; width across 'side', depth
        across 'front'). square: 0 = round section, 1 = square; ring_gap: see below. hem(i, n, end) -> offset along the axis
        (metres) of the end ring's vertex i (end 0 or 1): jagged torn edges. shift: (side, front) offset
        of the whole tube, metres."""
        a, b = Vector(a), Vector(b)
        axis = b - a
        side, front = _frame(axis)
        off = side * shift[0] + front * shift[1]
        mi = self._mat(mat)
        g = self._girth(bone)
        self._start(bone, cap[0] and cap[1])
        # ring_gap: a ring at least every that many metres, for a tube that crosses a joint's blend zone
        # (a long flat face there tilts as one piece and lets what is inside poke out).
        dense = [sections[0]]
        for (t0, w0, d0), (t1, w1, d1) in zip(sections, sections[1:]):
            k = max(1, math.ceil(axis.length * (t1 - t0) / ring_gap)) if ring_gap else 1
            for i in range(1, k + 1):
                f = i / k
                dense.append((t0 + (t1 - t0) * f, w0 + (w1 - w0) * f, d0 + (d1 - d0) * f))
        sections = dense
        rings = []
        for k, (t, w, d) in enumerate(sections):
            w, d = w * g, d * g
            ring = []
            for i in range(n):
                ang = 2 * math.pi * (i + 0.5) / n
                c, s = math.cos(ang), math.sin(ang)
                # Superellipse between a circle and a square.
                e = 2.0 / (1.0 + 3.0 * square)
                x = math.copysign(abs(c) ** e, c) * w / 2
                y = math.copysign(abs(s) ** e, s) * d / 2
                along = 0.0
                if hem and k in (0, len(sections) - 1):
                    along = hem(i, n, 0 if k == 0 else 1)
                p = a + axis * t + axis.normalized() * along + side * x + front * y + off
                ring.append(self._add(p, bone))
            rings.append(ring)
        for r0, r1 in zip(rings, rings[1:]):
            for i in range(n):
                j = (i + 1) % n
                self._face((r0[i], r0[j], r1[j], r1[i]), mi)
        if cap[0]:
            self._face(tuple(reversed(rings[0])), mi)
        if cap[1]:
            self._face(tuple(rings[-1]), mi)

    def box(self, center, size, bone, mat, rot=None):
        """An axis-aligned box (size x, y, z), optionally rotated (a Matrix) around its centre."""
        c = Vector(center)
        mi = self._mat(mat)
        self._start(bone, True)
        idx = []
        for z in (-1, 1):
            for y in (-1, 1):
                for x in (-1, 1):
                    v = Vector((x * size[0] / 2, y * size[1] / 2, z * size[2] / 2))
                    if rot is not None:
                        v = rot @ v
                    idx.append(self._add(c + v, bone))
        for f in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
            self._face(tuple(idx[i] for i in f), mi)

    def ball(self, center, radius, bone, mat, n=8, rings=5):
        """A sphere centred on the head of `bone` (a joint), following that bone alone: it turns about its
        own centre, so it stays in place however far the joint bends and fills the gap between the
        volumes on either side (shoulder, hip, elbow, knee)."""
        c = Vector(center)
        mi = self._mat(mat)
        self._start(bone, True, ball=True)
        top = self._add(c + Vector((0, 0, radius)), bone, True)
        grid = []
        for k in range(1, rings):
            lat = math.pi * k / rings
            ring = []
            for i in range(n):
                lon = 2 * math.pi * (i + 0.5) / n
                ring.append(self._add(c + radius * Vector((math.sin(lat) * math.cos(lon), math.sin(lat) * math.sin(lon),
                        math.cos(lat))), bone, True))
            grid.append(ring)
        bottom = self._add(c - Vector((0, 0, radius)), bone, True)
        for i in range(n):
            j = (i + 1) % n
            self._face((top, grid[0][j], grid[0][i]), mi)
            self._face((bottom, grid[-1][i], grid[-1][j]), mi)
            for r0, r1 in zip(grid, grid[1:]):
                self._face((r0[i], r0[j], r1[j], r1[i]), mi)

    def sit_on_ground(self, prefix):
        """Moves the volumes of the bones starting with prefix (the feet) up or down so their lowest point
        is on the ground (z = 0): their size depends on the girth, the ankle height does not."""
        idx = [i for i, o in enumerate(self.owner) if o.startswith(prefix)]
        dz = -min(self.verts[i][2] for i in idx)
        for i in idx:
            x, y, z = self.verts[i]
            self.verts[i] = (x, y, z + dz)
        return dz

    def build(self, name, palette):
        """The mesh object; palette: material name -> sRGB hex."""
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        for m in self.materials:
            me.materials.append(material(m, palette[m]))
        for p, mi in zip(me.polygons, self.mats):
            p.material_index = mi
            p.use_smooth = False
        # Outward normals: every volume is closed, so Blender can make them consistent.
        obj = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        return obj


def joint_reach(rig, b, name):
    """Radius of the limb at bone `name`'s head: the farthest of its own vertices from its axis, within
    10 cm of the head along it."""
    bone = rig.data.bones[name]
    h, d = bone.head_local, (bone.tail_local - bone.head_local).normalized()
    best = 0.0
    for co, o in zip(b.verts, b.owner):
        if o == name:
            v = Vector(co) - h
            s = v.dot(d)
            if -0.1 <= s <= 0.1:
                best = max(best, (v - d * s).length)
    return best


def skin(obj, rig, b, blend=0.05):
    """Weights mixed round every joint, the same for every volume there, so two volumes that overlap at a
    joint bend as one and never open a crack. A vertex owned by bone B: near B's head (within `blend`
    metres along B, scaled down for short bones), it goes from B's parent to B along a smoothstep; near the
    head of each child C, from B to C likewise. Only the vertices close to the joint's axis (within the
    limb's radius, fading out to 1.6 times it) blend, so the pelvis does not follow a thigh. At most 4
    bones per vertex, normalised. Returns how many vertices have more than one bone."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_NAME")
    bones = rig.data.bones
    vg = {g.name: g for g in obj.vertex_groups}
    for bn in bones:
        if bn.use_deform and bn.name not in vg:
            vg[bn.name] = obj.vertex_groups.new(name=bn.name)
    reach = {bn.name: joint_reach(rig, b, bn.name) for bn in bones if bn.use_deform}

    def side(name, co):
        """How far co is past the head of bone `name` (0 before, 1 after, smooth in between) and how close
        to its axis (1 inside the limb, 0 away from it)."""
        bn = bones[name]
        parent = bn.parent
        r = blend * min(1.0, bn.length / 0.2, (parent.length / 0.2) if parent else 1.0)
        h, d = bn.head_local, (bn.tail_local - bn.head_local).normalized()
        v = co - h
        s = v.dot(d)
        radial = (v - d * s).length
        R = max(reach[name], 0.02)
        near = min(max((1.6 * R - radial) / (0.6 * R), 0.0), 1.0)
        return ease((s + r) / (2 * r)), near

    blended = 0
    for v in obj.data.vertices:
        co = Vector(b.verts[v.index])
        own = bones[b.owner[v.index]]
        w = {own.name: 1.0}
        if b.fixed[v.index]:
            vg[own.name].add([v.index], 1.0, "REPLACE")
            continue
        if own.parent and own.parent.use_deform:
            past, near = side(own.name, co)
            c = past * near + (1.0 - near)
            w = {own.name: c, own.parent.name: 1.0 - c}
        kids = {}
        for ch in own.children:
            if ch.use_deform:
                past, near = side(ch.name, co)
                if past * near > 0.0:
                    kids[ch.name] = past * near
        total = sum(kids.values())
        if total > 0.0:
            keep = 1.0 - min(total, 1.0)
            w = {k: x * keep for k, x in w.items()}
            for k, x in kids.items():
                w[k] = w.get(k, 0.0) + x / max(total, 1.0)
        w = dict(sorted(((k, x) for k, x in w.items() if x > 1e-3), key=lambda kv: -kv[1])[:4])
        t = sum(w.values())
        for k, x in w.items():
            vg[k].add([v.index], x / t, "REPLACE")
        blended += len(w) > 1
    return blended


def axis_angle(axis, deg):
    return Quaternion(Vector(axis), math.radians(deg))


class Poser:
    """Poses in armature axes. A pose is {bone: Quaternion} (missing = no rotation) plus an offset of
    one bone (the hips) in armature space. A bone's rotation turns it around its head, in the frame its
    parents left it in: q[b] = rotation of the bone's rest orientation, before the parents' rotations."""

    def __init__(self, rig, mover="DEF-hips"):
        self.rig = rig
        self.mover = mover
        self.bones = {b.name: b for b in rig.data.bones}
        self.order = [b.name for b in rig.data.bones]  # parents first
        self.rest_head = {n: b.head_local.copy() for n, b in self.bones.items()}
        self.rest_tail = {n: b.tail_local.copy() for n, b in self.bones.items()}
        self.rest_rot = {n: b.matrix_local.to_quaternion() for n, b in self.bones.items()}
        self.parent = {n: (b.parent.name if b.parent else None) for n, b in self.bones.items()}

    def new(self):
        return {"q": {}, "off": Vector((0, 0, 0))}

    def chain(self, st, b):
        """World (armature) rotation that bone b has turned through, its parents' included."""
        q = Quaternion()
        path = []
        while b:
            path.append(b)
            b = self.parent[b]
        for n in reversed(path):
            q = q @ st["q"].get(n, Quaternion())
        return q

    def head(self, st, b):
        p = self.parent[b]
        if p is None:
            return self.rest_head[b] + (st["off"] if b == self.mover else Vector())
        h = self.head(st, p) + self.chain(st, p) @ (self.rest_head[b] - self.rest_head[p])
        return h + (st["off"] if b == self.mover else Vector())

    def tail(self, st, b):
        return self.head(st, b) + self.chain(st, b) @ (self.rest_tail[b] - self.rest_head[b])

    def length(self, b):
        return (self.rest_tail[b] - self.rest_head[b]).length

    def set_world(self, st, b, qw):
        """Gives bone b this world rotation (from its rest orientation), whatever its parents do."""
        p = self.parent[b]
        qp = self.chain(st, p) if p else Quaternion()
        st["q"][b] = qp.inverted() @ qw

    def aim(self, st, b, direction, twist=Quaternion()):
        """Points bone b along a world direction (the shortest turn from its rest direction)."""
        rest = (self.rest_tail[b] - self.rest_head[b]).normalized()
        self.set_world(st, b, rest.rotation_difference(Vector(direction).normalized()) @ twist)

    def ik(self, st, upper, lower, target, pole):
        """Two-bone IK: the end of `lower` on target (or as close as the bones reach), the middle joint
        bent towards the pole direction. Returns how far the target was out of reach (metres)."""
        h = self.head(st, upper)
        l1, l2 = self.length(upper), self.length(lower)
        t = Vector(target)
        d_vec = t - h
        d = d_vec.length
        miss = max(0.0, d - (l1 + l2) * 0.999)
        d = min(max(d, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.999)
        u = d_vec.normalized()
        pole = Vector(pole)
        w = (pole - u * pole.dot(u)).normalized()
        a = math.acos(max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
        knee = h + (u * math.cos(a) + w * math.sin(a)) * l1
        self.aim(st, upper, knee - h)
        self.aim(st, lower, h + u * d - knee)
        return miss

    def write(self, st, frame):
        """Keys every bone's rotation (and the mover's location) at a frame."""
        for n in self.order:
            pb = self.rig.pose.bones[n]
            r = self.rest_rot[n]
            q = st["q"].get(n, Quaternion())
            pb.rotation_quaternion = r.inverted() @ q @ r
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if n == self.mover:
                p = self.parent[n]
                qp = self.chain(st, p) if p else Quaternion()
                pb.location = r.inverted() @ (qp.inverted() @ st["off"])
                pb.keyframe_insert("location", frame=frame)


def bake(rig, poser, name, frames, pose_at, loop=True):
    """An action named `name`: pose_at(t) for t = frame / frames on every frame (0..frames; the last equals
    the first when the clip loops). Linear keys, so the curve between frames is the sampled function."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    for f in range(frames + 1):
        t = (f % frames) / frames if loop else f / frames
        poser.write(pose_at(t), f)
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    for k in fc.keyframe_points:
                        k.interpolation = "LINEAR"
    return act


def use_action(rig, act):
    rig.animation_data.action = act
    if act.slots:
        rig.animation_data.action_slot = act.slots[0]


def ease(x):
    """Smoothstep: 0 to 1 with zero speed at both ends."""
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def keys(points, t):
    """A curve through [(t, value)], eased between the points (each point is a stop)."""
    if t <= points[0][0]:
        return points[0][1]
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if t <= t1:
            return v0 + (v1 - v0) * ease((t - t0) / (t1 - t0))
    return points[-1][1]


def wave(t, phase=0.0, harmonic=1):
    """sin over a loop: t and phase in cycles."""
    return math.sin(2 * math.pi * (harmonic * t - phase))


def evaluated_points(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    return [ev.matrix_world @ v.co for v in ev.data.vertices]


def measure(obj, rig, act, samples, vert_sets, ground_speed=0.0, stance=None):
    """On the deformed mesh, `samples` poses of the action: the lowest point of each vertex set (soles)
    and, where stance(side, t) says a foot is planted, how far it slides from moving back at
    ground_speed (metres per second, along +Y). Returns {sole_min_m, sole_max_m, slide_max_m}."""
    use_action(rig, act)
    scene = bpy.context.scene
    f0, f1 = act.frame_range
    dur = (f1 - f0) / FPS
    lows, prev, slide = [], {}, 0.0
    for i in range(samples + 1):
        t = i / samples
        f = f0 + (f1 - f0) * t
        scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        co = evaluated_points(obj)
        low = []
        for side, vs in vert_sets.items():
            pts = [co[j] for j in vs]
            low.append(min(p.z for p in pts))
            c = sum((p for p in pts), Vector()) / len(pts)
            if stance and side in prev and stance(side, t) and stance(side, prev[side][0]):
                dt = (t - prev[side][0]) * dur
                moved = c - prev[side][1]
                slide = max(slide, (moved - Vector((0, ground_speed * dt, 0))).length)
            prev[side] = (t, c)
        lows.append(min(low))
    return {"sole_min_m": round(min(lows), 4), "sole_max_m": round(max(lows), 4), "slide_max_m": round(slide, 4)}


def lowest_point(obj, rig, act, frame):
    use_action(rig, act)
    bpy.context.scene.frame_set(frame)
    return min(p.z for p in evaluated_points(obj))


def export(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
            export_animation_mode="ACTIONS", export_force_sampling=True, export_frame_step=1,
            export_apply=False, export_extras=False, export_yup=True, export_morph=False)


RAYS = [Vector(v).normalized() for v in ((0.3, 0.2, 1.0), (-0.2, 1.0, 0.3), (1.0, -0.3, -0.2))]


def _hits(bvh, o, d):
    k = 0
    while k < 50:
        loc, _, _, _ = bvh.ray_cast(o, d)
        if loc is None:
            return k
        k += 1
        o = loc + d * 1e-4
    return k


def _inside(bvh, o):
    """Odd ray crossings in at least 2 of 3 directions."""
    return sum(_hits(bvh, o, d) % 2 for d in RAYS) >= 2


def joint_gaps(obj, rig, act, samples, b, limit=0.007):
    """Cracks at the joints. For each pair of volumes on either side of a joint (one owned by a bone, the
    other by its parent), the vertices of each that sit inside the other in the rest pose (their overlap)
    must stay inside it, or be covered by some other volume, in every pose: a vertex that comes out
    uncovered opens a notch as wide as its distance to the other volume. Returns {child bone: {"max_m",
    "poses"}} over `samples` poses of the action, poses counting where a notch is wider than `limit`
    (half a pixel at game size). With JOINT_DEBUG=1 in the environment, prints each notch: the two
    volumes (bone, material), the vertex's rest position and the width."""
    from mathutils.bvhtree import BVHTree
    bones = rig.data.bones
    vols = b.volumes
    vverts = [sorted({i for f in v["faces"] for i in f}) for v in vols]
    rest = [Vector(c) for c in b.verts]
    pairs = []  # (joint bone, volume a, volume b)
    for ia, va in enumerate(vols):
        for ib, vb in enumerate(vols):
            pa = bones[va["bone"]].parent
            if ia != ib and vb["closed"] and pa is not None and pa.name == vb["bone"] and pa.use_deform:
                # A ball turns on itself: its surface slides out of the other volume without opening a gap.
                if not va["ball"]:
                    pairs.append((va["bone"], ia, ib))
                if va["closed"] and not vb["ball"]:
                    pairs.append((va["bone"], ib, ia))

    def trees(co):
        return [BVHTree.FromPolygons(co, [list(f) for f in v["faces"]]) if v["closed"] else None for v in vols]

    rest_trees = trees(rest)
    overlap = {}
    for j, ia, ib in pairs:
        o = [i for i in vverts[ia] if _inside(rest_trees[ib], rest[i])]
        if o:
            overlap[(j, ia, ib)] = o
    out = {j: {"max_m": 0.0, "poses": 0} for j, _, _ in overlap}
    use_action(rig, act)
    scene = bpy.context.scene
    f0, f1 = act.frame_range
    for s in range(samples):
        f = f0 + (f1 - f0) * s / samples
        scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        co = evaluated_points(obj)
        tr = trees(co)
        boxes = [(Vector([min(co[i][k] for i in vv) for k in range(3)]), Vector([max(co[i][k] for i in vv) for k in range(3)]))
                for vv in vverts]
        worst = {}
        for (j, ia, ib), verts in overlap.items():
            for i in verts:
                p = co[i]
                if _inside(tr[ib], p):
                    continue
                if any(t is not None and k not in (ia, ib) and all(boxes[k][0][a] <= p[a] <= boxes[k][1][a] for a in range(3))
                        and _inside(t, p) for k, t in enumerate(tr)):
                    continue  # covered by another volume (a sleeve, the shirt)
                dist = tr[ib].find_nearest(p)[3]
                if os.environ.get("JOINT_DEBUG") and dist > limit:
                    print("gap", act.name, j, vols[ia]["bone"], b.materials[b.mats[b.faces.index(vols[ia]["faces"][0])]],
                            "->", vols[ib]["bone"], b.materials[b.mats[b.faces.index(vols[ib]["faces"][0])]],
                            "rest", tuple(round(x, 3) for x in rest[i]), "gap", round(dist, 3))
                worst[j] = max(worst.get(j, 0.0), dist)
        for j, w in worst.items():
            out[j]["max_m"] = round(max(out[j]["max_m"], w), 4)
            out[j]["poses"] += w > limit
    return out


def crossings(obj, rig, act, samples, pairs):
    """Volumes going through each other: for each pair name -> (moving vertex indices, polygons of the
    other volume), the deepest moving vertex inside that volume (odd ray crossings in 2 of 3 directions,
    depth = distance to its surface) over `samples` poses, and in how many poses one is more than 1 cm in.
    Returns {name: {"max_m", "poses"}}."""
    from mathutils.bvhtree import BVHTree
    use_action(rig, act)
    scene = bpy.context.scene
    f0, f1 = act.frame_range
    out = {name: {"max_m": 0.0, "poses": 0} for name in pairs}
    for i in range(samples):
        f = f0 + (f1 - f0) * i / samples
        scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        co = [tuple(p) for p in evaluated_points(obj)]
        for name, (moving, polys) in pairs.items():
            bvh = BVHTree.FromPolygons(co, polys)
            deep = 0.0
            for j in moving:
                o = Vector(co[j])
                if _inside(bvh, o):
                    deep = max(deep, bvh.find_nearest(o)[3])
            out[name]["max_m"] = round(max(out[name]["max_m"], deep), 4)
            out[name]["poses"] += deep > 0.01
    return out


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")
