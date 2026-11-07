# Starts a new character part that already passes the checks: a build script (or a face grid), its
# record and its ASSETS.toml entry, copied from the closest part of the slot. Plain Python, no Blender.
#
#   python3 art/character/new_part.py <slot> <id> <github-login> [--flat]
#
# <id> starts with the slot (hat_straw, top_hoodie...). --flat: a flat beard (a texture), not a volume.
# Then change what it writes, build it (make part ID=<id>) and check it (make check-part ID=<id>).
# The standard: docs/character-parts.md. Writes:
# - art/character/parts/<id>.py: a Blender script that builds the part on assets/character/body.glb
#   (volumes: hair, beard, hat, top, jacket, bottom, feet, back);
# - art/character/faces/<id>.txt: the part as a grid of texel keys, drawn by art/character/faces.py
#   (faces and flat beards);
# - data/character/parts/<id>.json, and an entry at the end of ASSETS.toml (CC0-1.0).
import json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# slot -> (part copied for its record, kind, starter build). Body shapes (slot body) change the skeleton:
# not a contribution of this kind, ask in an issue first.
STARTERS = {
    "hair": ("hair_short", "rigid", "hair"),
    "beard": ("beard_short", "rigid", "beard"),
    "hat": ("hat_beanie", "rigid", "hat"),
    "top": ("top_tshirt", "skinned", "garment"),
    "jacket": ("jacket_field", "skinned", "garment"),
    "bottom": ("bottom_jeans", "skinned", "garment"),
    "feet": ("feet_boots", "skinned", "garment"),
    "back": ("back_bag", "rigid", "back"),
    "face": ("face_adult", "texture", "grid"),
}
FLAT_BEARD = ("beard_stubble", "texture", "grid")
# Height over the skin of a garment, metres: what is worn over another sits further out.
GARMENT_OFFSET = {"top": 0.016, "jacket": 0.030, "bottom": 0.014, "feet": 0.017}
# Body regions a garment is made from (its record's "hides" may be fewer: an open jacket shows the top).
GARMENT_COVERS = {"top": ("torso", "arms_upper"), "jacket": ("torso", "arms_upper", "arms_lower"),
        "bottom": ("hips", "legs_upper", "legs_lower"), "feet": ("feet",)}
# Starters cut from the body's own faces (extract): the body mesh is Quaternius's (CC0), so the entry
# credits it like the repository's own parts cut from it (art/character/parts.py).
FROM_BODY = ("hair", "beard", "garment")
BODY_SOURCE = "https://opengameart.org/content/universal-animation-library"
USAGE = "usage: python3 art/character/new_part.py <slot> <id> <github-login> [--flat]"

HEADER = '''# {id}: a {slot} part ({kind}). Started by art/character/new_part.py from {ref}; change it freely.
#
#   make part ID={id}          (blender -b --python art/character/parts/{id}.py)
#   make part ID={id} BLEND=1  (also saves build/parts/{id}.blend, to model by hand; then
#                              blender -b build/parts/{id}.blend --python art/character/export_part.py -- {id})
#
# Builds assets/character/parts/{id}.glb on the base body (assets/character/body.glb). Blender axes: Z up,
# the model faces -Y. Sizes: fractions of the head's height K.HS, or relative to bones (K.bone_head).
# Tools: art/character/part_kit.py. Rules: docs/character-parts.md.
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import part_kit as K
from mathutils import Vector

ID = "{id}"
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
K.load_body(ROOT)
'''

FOOTER = '''
if "--blend" in sys.argv:  # to model by hand: the part in the body's space, before export
    part = K.join(PART, ID)
    K.save_blend(os.path.join(ROOT, "build/parts", ID + ".blend"), part)
    PART = [part]
if BONE:
    print("## part", ID, K.export_rigid(ID, PART, BONE), "triangles")
else:
    print("## part", ID, K.export_skinned(ID, PART[0], COVERS), "triangles")
'''

# Each build ends with PART (the objects of the part, in the body's space), BONE (a rigid part's bone) or
# COVERS (a skinned part's body regions).
BUILDS = {
    "hair": '''
# The body's scalp and nape faces, pushed out 15 mm. Faces are (index, bone, centre, region).
main = K.material("main.hair", "3a2f27")  # main...: the colour the player chooses
PART = [K.extract(ID, K.in_regions("scalp", "nape"), 0.015, [main])]
BONE = "DEF-head"
''',
    "beard": '''
# The body's chin and jaw faces, pushed out 10 mm.
def chin(i, b, c, r):
    rel = c - K.HEAD
    return r == "head" and 0.02 * K.HS < rel.z < 0.30 * K.HS and rel.y < -0.12 * K.HS


main = K.material("main.beard", "3a2f27")
PART = [K.extract(ID, chin, 0.010, [main])]
BONE = "DEF-head"
''',
    "hat": '''
# A dome on the skull above the rim (K.skull_dome: wide enough that no part of the head pokes through),
# and a band around its base. A brim goes at the rim, outside the head (a disc across the head cuts
# through it): K.ring(K.RIM, inner, outer, main, centre=(cx, cy)), inner = the band's radius. A wide brim
# hides the eyes.
cx, cy, dome = K.skull_dome()
main = K.material("main.hat", "6b5a4c")
PART = [K.prim("sphere", dome + Vector((0.006, 0.006, 0.10 * K.HS)), (cx, cy, K.RIM), main, cut_below=K.RIM),
        K.prim("cyl", (max(dome.x, dome.y) + 0.01, 0, 0.13 * K.HS), (cx, cy, K.RIM + 0.05 * K.HS), main, caps=False)]
BONE = "DEF-head"
''',
    "back": '''
# A box on the upper back, hanging from DEF-spine.003.
s3 = K.bone_head("DEF-spine.003")
back = max(v.co.y for v in K.src.vertices if abs(v.co.x) < 0.05 and abs(v.co.z - s3.z) < 0.05)
main = K.material("main.back", "2f3a46")
strap = K.material("fixed.strap", "6b5a4c")  # not main: keeps its colour, a palette colour
PART = [K.prim("box", (0.34, 0.18, 0.40), (0, back + 0.10, s3.z - 0.06), main, bevel=0.03),
        K.prim("box", (0.26, 0.05, 0.14), (0, back + 0.20, s3.z - 0.12), strap, bevel=0.012)]
BONE = "DEF-spine.003"
''',
    "garment": '''
# The body's faces of the regions it covers, pushed out along the normals, with the body's skin weights;
# the export gives it the body-shape keys, so it bends with the body and follows every body shape.
COVERS = {regions}
main = K.material("main.{slot}", "{colour}")
PART = [K.extract(ID, K.in_regions(*COVERS), {offset}, [main])]
BONE = ""
''',
}

GARMENT_COLOUR = {"top": "a39b86", "jacket": "8f8a63", "bottom": "455466", "feet": "51433a"}


def grid_of(ref):
    """The texels of an existing face as a grid of faces.py keys (one character per texel)."""
    sys.path.insert(0, os.path.join(ROOT, "art/character"))
    import faces
    every = dict(faces.faces())
    every.update(faces.beards())
    f = every[ref]
    rows = []
    for y in range(faces.H):
        rows.append("".join(f.px.get((x, y), ".") for x in range(faces.W)))
    return "\n".join(rows) + "\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flat = "--flat" in sys.argv
    if len(args) != 3:
        sys.exit(USAGE)
    slot, pid, author = args
    if slot not in STARTERS:
        sys.exit("unknown slot %s: one of %s (body shapes: ask in an issue)" % (slot, ", ".join(STARTERS)))
    if not re.fullmatch(r"[a-z0-9_]+", pid) or not pid.startswith(slot + "_"):
        sys.exit("the id is lowercase letters, digits and _, and starts with %s_" % slot)
    if flat and slot != "beard":
        sys.exit("--flat is for beards only")
    ref, kind, build = FLAT_BEARD if flat else STARTERS[slot]
    rec_path = os.path.join(ROOT, "data/character/parts", pid + ".json")
    if os.path.exists(rec_path):
        sys.exit("%s exists: ids are never reused" % os.path.relpath(rec_path, ROOT))
    with open(os.path.join(ROOT, "data/character/parts", ref + ".json")) as f:
        rec = json.load(f)
    rec["id"] = pid
    rec["name"] = "TODO: nom en français"
    rec.pop("when_hidden", None)
    written = []
    if kind == "texture":
        rec["texture"] = "res://assets/character/faces/%s.png" % pid
        asset = "assets/character/faces/%s.png" % pid
        src = os.path.join(ROOT, "art/character/faces", pid + ".txt")
        os.makedirs(os.path.dirname(src), exist_ok=True)
        with open(src, "w") as f:
            f.write(grid_of(ref))
        # Faces stay exact on import: same import settings as the face it was copied from.
        with open(os.path.join(ROOT, "assets/character/faces", ref + ".png.import")) as f:
            imp = f.read()
        imp = "\n".join(l for l in imp.split("\n") if not l.startswith(("uid=", "path=", "source_file=", "dest_files=")))
        with open(os.path.join(ROOT, asset + ".import"), "w") as f:
            f.write(imp)
        written += [src, os.path.join(ROOT, asset + ".import")]
        tool = "art/character/faces.py from art/character/faces/%s.txt: drawn texel by texel as an index texture (zone and shade per texel), 24x16" % pid
    else:
        rec["glb"] = "res://assets/character/parts/%s.glb" % pid
        asset = "assets/character/parts/%s.glb" % pid
        code = HEADER.format(id=pid, slot=slot, kind=kind, ref=ref)
        code += BUILDS[build].format(regions=GARMENT_COVERS.get(slot), slot=slot,
                colour=GARMENT_COLOUR.get(slot, ""), offset=GARMENT_OFFSET.get(slot, 0.0))
        code += FOOTER
        src = os.path.join(ROOT, "art/character/parts", pid + ".py")
        os.makedirs(os.path.dirname(src), exist_ok=True)
        with open(src, "w") as f:
            f.write(code)
        written.append(src)
        tool = "art/character/parts/%s.py (Blender <version>) on assets/character/body.glb: say how it is made" % pid
    with open(rec_path, "w") as f:
        f.write(json.dumps(rec, indent="\t", ensure_ascii=False) + "\n")
    written.append(rec_path)
    if build in FROM_BODY:
        who, origin, source = "Quaternius (the body mesh it is cut from); %s (the part)" % author, "third-party", BODY_SOURCE
    else:
        who, origin, source = author, "original", ""
    with open(os.path.join(ROOT, "ASSETS.toml"), "a") as f:
        f.write('\n[[asset]]\npath = "%s"\nauthor = "%s"\norigin = "%s"\ntool = "%s"\nprompt = ""\n'
                'license = "CC0-1.0"\nsource = "%s"\n' % (asset, who, origin, tool, source))
    for w in written:
        print("wrote", os.path.relpath(w, ROOT))
    print("added", asset, "to ASSETS.toml")
    print("copied from %s: review in %s" % (ref, os.path.relpath(rec_path, ROOT)))
    print("  name (a placeholder: the checks fail until you replace it), colors (ramps; the first is the default),")
    print("  hides and covers (what your part hides: %s hides %s)" % (ref, rec.get("hides", []) or "nothing"))
    print("and in ASSETS.toml, tool: the Blender version and how the part is made (the checks fail on the placeholders)")
    print("next: make part ID=%s, then make check-part ID=%s" % (pid, pid))


if __name__ == "__main__":
    main()
