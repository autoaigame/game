# Exports a part modelled by hand in Blender to assets/character/parts/<id>.glb.
#
#   make part ID=<id> BLEND=1      (saves build/parts/<id>.blend: the body, its rig, the starter part)
#   ... model the object named <id> in Blender, on the body, in the rest pose, and save ...
#   blender -b build/parts/<id>.blend --python art/character/export_part.py -- <id>
#
# Reads the part's record (data/character/parts/<id>.json). A rigid part is moved into the space of its
# bone. A skinned part keeps its weights, or takes the body's under it (Data Transfer) if it has none, then
# gets the body-shape keys (part_kit.transfer_morphs). Keep a copy of your changes in the part's script
# (art/character/parts/<id>.py) or describe them in ASSETS.toml: the .blend is not committed.
import json, os, sys
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import part_kit as K
from new_part import GARMENT_COVERS

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ID = sys.argv[sys.argv.index("--") + 1]
with open(os.path.join(ROOT, "data/character/parts", ID + ".json")) as f:
    rec = json.load(f)
body = bpy.data.objects["body"]
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
K.setup(body, rig, ROOT, K._morph_rig(rig, ROOT))
part = bpy.data.objects[ID]
bpy.context.view_layer.objects.active = part
if part.data.shape_keys:
    part.shape_key_clear()
if rec["kind"] == "rigid":
    print("## part", ID, K.export_rigid(ID, [part], rec["bone"]), "triangles")
elif rec["kind"] == "skinned":
    if not part.vertex_groups:  # weights from the body under it
        dt = part.modifiers.new("weights", "DATA_TRANSFER")
        dt.object = body
        dt.use_vert_data = True
        dt.data_types_verts = {"VGROUP_WEIGHTS"}
        dt.vert_mapping = "POLYINTERP_VNORPROJ"  # along the normal, the way extract() pushes faces out
        bpy.ops.object.datalayout_transfer(modifier="weights")
        bpy.ops.object.modifier_apply(modifier="weights")
    if not any(m.type == "ARMATURE" for m in part.modifiers):
        part.modifiers.new("rig", "ARMATURE").object = rig
    part.parent = rig
    print("## part", ID, K.export_skinned(ID, part, GARMENT_COVERS[rec["slot"]]), "triangles")
else:
    sys.exit("%s is a %s part: nothing to export from Blender" % (ID, rec["kind"]))
