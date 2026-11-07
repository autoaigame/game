# Character parts

Players are drawn as a 3D model rendered as pixel art (`client/character_3d.gd`). The model is built
from interchangeable parts: a body (one of several body shapes) and a face, then hair, a beard, a hat, a
top, a jacket, a bottom, shoes and a bag. This page
is the standard a new part must follow. Anyone can add one by pull request, with or without an AI agent.

## In short

- One skeleton and one rest pose for everyone. Body shapes (standard, stocky, lean) are made from the base
  body in game, and every part follows them. A part never changes the skeleton.
- Three kinds of part: **rigid** parts (hair, beards, hats, bags) hang from one bone; **skinned** parts
  (tops, trousers, shoes) are weighted to the skeleton and bend with it; **texture** parts (faces, flat
  beards) are a small index texture drawn on the front of the head.
- A part is a `.glb` in `assets/character/parts/` (or a `.png` in `assets/character/faces/`) and a record
  in `data/character/parts/<id>.json`.
- Ids are strings, never renamed or reused: saved looks refer to them.
- Colours come from named ramps of the game's palette. The renderer keeps every pixel in the palette.
- Every part file is CC0, with an `ASSETS.toml` entry.
- `make check` loads every record and builds every part on the body; on every body shape, a hat must
  cover the head and a garment what it covers, in every sampled pose of every animation.

## The skeleton and the body

The body is `assets/character/body.glb`, made by `art/character/body.py` from the Quaternius Universal
Animation Library (CC0). `art/character/BODY.md` lists its 53 bones (Rigify names, `DEF-…`), their rest
positions and its animations (`idle`, `walk`, `jog`, `sprint`).

- Metres, +Y up, the character faces +Z (glTF and Godot). In Blender: Z up, facing −Y.
- Origin on the ground between the feet. Height 1.63 m; the head is a fifth of it.
- The game draws the top of the base body's head 100 px above the feet: about 71 px per metre. Details
  under about 3 cm (2 px) do not show.

The body is cut into **regions**, one mesh each: `head`, `scalp` (the top of the skull, under a hat's rim),
`nape` (the back of the head below it), `torso`, `arms_upper`, `arms_lower`, `hands`, `hips`, `legs_upper`,
`legs_lower`, `feet`. A part hides the regions it covers instead of fitting the skin to the millimetre.
Hair has two surface names of its own, `hair_top` and `hair_back`, that hats can hide. The list is in
`data/character/slots.json`; a record naming anything else is refused.

## Body shapes

The base body (`standard`) is the rest pose every part is modelled on. The other body shapes are built
from it in game, on the same skeleton and rest pose, so animations and parts work on all of them:

- the bones move and the head, hands and feet scale (`data/character/morphs.json`, written by
  `art/character/body.py`, applied by `client/character_morph.gd` after each animation update);
- the body and every skinned part take a shape key named `morph_<id>` (thickness, and the corrections that
  make the moved bones land on the reshaped body).

A rigid part follows its bone, so a hat grows with a bigger head. A skinned part needs the shape keys:
`art/character/parts.py` gives them to every skinned part (`transfer_morphs`: each vertex takes the move of
the body's surface straight under it). A part modelled by hand needs the same keys, with the same names;
running it through that function is the simple way.

| Body shape | Body part | Head | Height |
|---|---|---|---|
| `standard` | `body_standard` | a fifth | 1.63 m |
| `stocky` | `body_stocky` | a quarter | 1.48 m |
| `lean` | `body_lean` | a sixth | 1.69 m |

The body shape is part of the look: the body slot ("Silhouette" in the editor) holds one body part per
shape.

## Slots

| Slot | Kind | Required | Default |
|---|---|---|---|
| `body` | body | yes | `body_standard` |
| `face` | texture | yes | `face_adult` |
| `hair` | rigid on `DEF-head` | no | `hair_short` |
| `beard` | rigid on `DEF-head`, or texture | no | `beard_short` |
| `hat` | rigid on `DEF-head` | no | none |
| `top` | skinned | yes | `top_tshirt` |
| `jacket` | skinned, over the top | no | `jacket_field` |
| `bottom` | skinned | yes | `bottom_jeans` |
| `feet` | skinned | no | `feet_boots` |
| `back` | rigid on `DEF-spine.003` | no | `back_bag` |

A look wears at most one part per slot. Adding a slot changes `slots.json` and the editor; ask first in an
issue.

## The record

`data/character/parts/<id>.json`:

```json
{
	"id": "hat_cap",
	"slot": "hat",
	"name": "Casquette",
	"kind": "rigid",
	"glb": "res://assets/character/parts/hat_cap.glb",
	"bone": "DEF-head",
	"hides": ["scalp", "hair_top"],
	"colors": ["khaki", "workwear_blue", "brown"]
}
```

| Field | Rule |
|---|---|
| `id` | The file name, `[a-z0-9_]`, starting with the slot (`hat_…`). Unique, never renamed or reused. |
| `slot` | One of the slots above. |
| `name` | Shown to the player (French for now). |
| `kind` | `rigid`, `skinned`, `texture` (face and beard slots), or `body` (body slot only). |
| `morph` | Body parts only: the body shape (`standard` or one of `morphs.json`). |
| `glb` | The mesh (not for a texture part). |
| `texture` | Texture parts only: the index texture. |
| `bone` | Rigid parts only: the bone it hangs from. |
| `covers` | Hair surfaces it draws (`hair_top`, `hair_back`), so a hat can hide them. |
| `hides` | Regions and hair surfaces it hides while it is drawn. |
| `when_hidden` | Optional `{glb, covers, hides}`: what to draw when something hides what the part covers (long hair under a hat keeps its back). Without it, the part is not drawn then. |
| `colors` | Ramp names from `data/character/ramps.json` the player may choose; the first is the default. On a face, the colour of the brows. |

Hiding is not transitive: a part that is not drawn hides nothing.

## The mesh

- **Rigid part:** one plain mesh, no skin, no animation. Its origin is the head of its bone in the rest
  pose, with the model's axes (not the bone's): the game puts it on a `BoneAttachment3D` and undoes the
  bone's rest rotation.
- **Skinned part:** the skeleton and one mesh weighted to it, at most 4 bones per vertex, no animation, and
  the shape keys `morph_<id>` of every body shape. The game moves the mesh onto the body's skeleton and
  binds it by bone names. A garment worn over another (the jacket over the top) sits further out: the
  top is 16 mm off the skin, the jacket 30 mm.
- Materials: a material named `main…` takes the colour the player chooses; any other keeps its own colour,
  which must be a palette colour.
- Shapes: simple volumes with clear edges. At about 100 px, small details only add noise. Keep a part under
  its slot's budget: `triangles` in `data/character/slots.json` (2 000 for clothes, a few hundred for the
  head and the back).
- Flat colours per material: no texture on a mesh, no gradient, no baked shadow. No animation, camera or
  light in the file.
- Volume for what changes the silhouette (hair, full beards, hats); a texture for what stays flat (eyes,
  brows, mouth, scars, stubble, a moustache). No modelled nose or ears.

## Faces and flat beards

A face is a 24×16 PNG: the face zone of the head's texture (`FACE_RECT` in `art/character/body.py` and
`client/character_3d.gd`), about one texel per screen pixel at the front of the head. Its texels are
indices, not colours: red = zone × 64, green = (shade + 2) × 50, alpha 255; a transparent texel leaves
the skin. Zones: 0 the skin, 1 the part's own colour (brows on a face, the beard on a flat beard), 2 the
eyes. The shader draws the colour `ramp[band + shade]` of the zone's ramp, so one face works with every
skin and hair colour. Shade −2 is always the ramp's darkest colour, +2 always its lightest.

- Eyes at least 2 texels wide, with an empty row between brows and eyes.
- Four or five zone and shade pairs per face at most; at this size more is noise.
- No compression on import: the `.import` file of the PNG has `detect_3d/compress_to=0`.
- `art/character/faces.py` draws the faces and flat beards of the repository texel by texel (plain
  Python, no library); a new one can be added there or drawn by hand with the same encoding.

## Colours

`data/palette.json` holds the palette, `data/character/ramps.json` the named ramps: 3 or 4 palette colours
from dark to light. The light falls in three bands (shade, plain, full light); a surface takes
`ramp[band + shade]`, shade 0 on a mesh. Every pixel of a character is a palette colour, and a part keeps
its hue in shade and in light. A new ramp may use only palette colours, from dark to light.

The palette is the kit's 40 colours, which the world's art uses, and 12 colours for characters only
(`docs/art-guide.md`): skin tones from deep to fair and faded reds for hair and cloth. Adding a colour
changes the art direction: ask first in an issue.

## Building a part

The tools are in `art/character/part_kit.py` (Blender): the body, its regions and skin weights, copying
the body's faces out along the normals (`extract`), primitives, round shapes (`lathe`, `ring` for a
brim), the skull dome hats sit on, moving a rigid
part into its bone's space, the body-shape keys (`transfer_morphs`) and the export.

A new part starts from `art/character/new_part.py`, which writes a part of the slot that already passes
the checks, its record and its `ASSETS.toml` entry (the `add-character-part` skill has the steps):

```
python3 art/character/new_part.py <slot> <id> <github-login>
make part ID=<id>          # blender -b --python art/character/parts/<id>.py
make check-part ID=<id>
```

- A volume is a script, `art/character/parts/<id>.py`, that builds it on `assets/character/body.glb`.
  Reproducible and easy to review: the best path for an AI agent. Blender 5.2, headless.
- To model by hand, `make part ID=<id> BLEND=1` saves `build/parts/<id>.blend` with the body, the part and
  the game's camera; `art/character/export_part.py` exports the object named `<id>` from it.
- A face or a flat beard is a grid, `art/character/faces/<id>.txt`, drawn by `art/character/faces.py`.

The parts of the repository are made by `art/character/parts.py`, run by `art/character/body.py` in the
same Blender session as the body:

```
blender -b --python art/character/body.py -- <AnimationLibrary_Godot_Standard.glb> .
```

Garments are copies of the body's own faces of the regions they cover, pushed out along the normals.
Hats are sized on the skull. Sizes are fractions of the head or relative to bones, never absolute
heights. A part built on `body.glb` matches one built with the body within a few millimetres: the glb
splits the mesh at its regions and texture seams, and `part_kit.load_body` welds them back.

## Checks

`make check` runs, among others:

- `tests/test_character_parts.gd`: every record loads (`CharacterParts.check_record`), names a known
  slot, existing files, known regions and ramps; looks are validated and repaired.
- `tests/test_character_standard.gd` (rules in `tests/character_standard.gd`): every part's files have a
  CC0-1.0 `ASSETS.toml` entry, PNGs have no metadata chunk, a glb has one mesh, no animation, camera,
  light or texture, a rigid part no skin and no moved node, a skinned part one skin on the body's bones
  with at most 4 per vertex and every `morph_<id>` shape key, triangles within the slot's budget, and
  every colour not named `main…` in the palette. A record whose `name` still starts with `TODO`, or an
  entry still holding `new_part.py`'s placeholders (`<version>`, "say how it is made"), fails.
- `tests/test_character_rig.gd`: every part builds on the body, rigid parts hang from their bone,
  skinned parts bind to the body's bones by name, hidden regions are off.
- `tests/test_character_looks.gd`: faces and flat beards are exact index textures with eyes 2 texels
  wide; ramps are palette colours from dark to light.
- `tests/test_character_head_parts.gd`: on every body shape, no vertex of the head or of the hair a hat
  leaves drawn pokes through the hat, in 16 poses of the four animations. It casts rays from the middle
  of the hat's lowest level towards each vertex above it: a brim that droops lowers that level, and a
  disc across the head stops the rays, so a brim is a ring outside the crown (`part_kit.ring`).
- `tests/test_character_garments.gd`: on every body shape, the skin under a garment and a garment under
  another (a top under the jacket) stay under it, in 12 poses of the four animations. The layers come from
  the records: each skinned part over the regions it hides, the jacket over the top. Each garment is
  worn over the default outfit.

`make check-part ID=<id>` runs the same checks for one part, with a message per problem, then draws its
sheet in `build/parts/<id>_sheet.png` (and `_x3`, enlarged): every body shape from the front,
three-quarters, the side, the back and running, as the game draws it. On a pull request that touches
`data/character/`, `assets/character/` or `art/character/`, the `character` check does the same for each
part it adds or changes and keeps the sheets as an artifact, for voters. `make gallery SLOT=<slot>`
draws every part of a slot on the standard body, to compare a new part with the others.

Look at your part in the game before opening the pull request: the editor of the start menu shows it
turning, and C opens the editor in game, where you can run with it. Say in the PR what you checked.

## Licence and provenance

Every file under `assets/character/` and its source is CC0-1.0, with an `ASSETS.toml` entry (`add-content`
skill): made by you, made by a script, or third-party art that is already CC0 (Quaternius, Kenney…, with
its `source`). Generated art follows the usual rule: the tool, the prompt and every retouch.

## Network

A look is a list of `{"id", "color"}`, sent by the client before it joins and when it changes. The server
checks it against these same files (`CharacterParts.validate`) and refuses an invalid one; the old look
stays. It sends a look to every client only when it changes, never in the snapshots. A client that gets
an unknown part (newer data) draws its slot's default; a saved look with a part that was removed loses
that part, and a required slot falls back to its default.
