---
name: add-character-part
description: Add a piece of the player character, such as a hat, a hairstyle, a beard, a face, a top, a jacket, trousers, shoes or a bag, or change one. Use when a contribution touches data/character/, assets/character/ or art/character/, with or without Blender's interface.
---

# Add a character part

The character is a 3D model drawn as pixel art, built from parts on one skeleton. The standard is
`docs/character-parts.md`. Read it first; this skill is the order of the steps.

## 1. Choose the slot

- Slots and their kinds are in `docs/character-parts.md` (Slots). One part fills one slot.
- Search the open PRs for a close part (`gh pr list -R autoaigame/game --state open`). Duplicates get closed.
- A new slot, a new body shape, a change to the skeleton, the body (`art/character/body.py`) or the
  palette breaks every part: open an issue instead.

## 2. Start from a part that passes

```
python3 art/character/new_part.py <slot> <id> <github-login>          # beard as a texture: add --flat
```

- `<id>` starts with the slot (`hat_straw`, `top_hoodie`). It is never renamed or reused.
- It writes the part's source (`art/character/parts/<id>.py`, or `art/character/faces/<id>.txt` for a face
  or a flat beard), its record `data/character/parts/<id>.json` and its `ASSETS.toml` entry.
- Build it once and check it before you change anything: `make part ID=<id>`, then `make check-part ID=<id>`.

## 3. Make it

Volumes (hair, beards, hats, clothes, bags) need Blender 5.2, run headless (`blender -b`); pass
`BLENDER=/path/to/blender` to `make` if it is not on your PATH.

- By script, the way for an AI agent and the easiest to review: edit `art/character/parts/<id>.py`.
  The tools are in `art/character/part_kit.py`; the repository's own parts in `art/character/parts.py`
  are examples. Rebuild with `make part ID=<id>`.
- By hand: `make part ID=<id> BLEND=1` saves `build/parts/<id>.blend` (the body, its rig, your part,
  the game's camera). Model the object named `<id>` on the body, save, then
  `blender -b build/parts/<id>.blend --python art/character/export_part.py -- <id>`. Describe what you did
  in the `ASSETS.toml` entry; the `.blend` is not committed.
- Faces and flat beards: edit the grid `art/character/faces/<id>.txt` (16 lines of 24 keys, the keys
  are `KEYS` in `art/character/faces.py`), then `make part ID=<id>`.

Rules (details in `docs/character-parts.md`):

- Model on the base body in its rest pose. Never move or rename a bone. Sizes come from the head
  (`K.HS`) and the bones, not fixed heights, so the part fits every body shape.
- Simple volumes with clear edges. The head is 100 px tall on screen: under 3 cm does not show.
- Stay under the slot's triangle budget (`triangles` in `data/character/slots.json`).
- Materials named `main…` take the player's colour. Any other material keeps its own colour, which must
  be in `data/palette.json`. No texture on a mesh, no gradient, no baked shadow.
- A skinned part keeps the body's weights; its export adds the body-shape keys. Hats sit on the skull
  dome (`K.skull_dome`). Over another garment, sit further out (top 16 mm, jacket 30 mm).
- Faces are index textures: eyes at least 2 texels wide, four or five zone and shade pairs at most.
- A generated model or texture is allowed with a complete `ASSETS.toml` entry (tool, prompt, every
  retouch), but it usually has to be redone as simple volumes and weighted by script.

## 4. Fill the record and the entry

- Record: `name` (shown to players, in French for now), `colors` (ramps of `data/character/ramps.json`,
  the first is the default), `hides` and `covers` (regions in `data/character/slots.json`).
- `ASSETS.toml`: `new_part.py` wrote the entry. Keep `license = "CC0-1.0"`: a character part is CC0 or
  is not accepted. Write in `tool` the Blender version and how the part is made.

## 5. Check

1. `make check-part ID=<id>`. Fix every `FAIL` line: it names the file, the rule and, for numbers, by how
   much. It checks the record, the `ASSETS.toml` entry and licence, PNG metadata, the glb (one mesh,
   skin, body bones, shape keys, no animation), the triangle budget, palette colours, and that nothing
   pokes through a hat or a garment on every body shape in motion.
2. Open `build/parts/<id>_sheet_x3.png`: every body shape from the front, three-quarters, the side, the
   back and running. An agent reads the image: it is the only view you have. Look for holes, skin
   through clothes, a part floating or too small to read.
3. Without a display, the sheet needs a virtual one: `xvfb-run make check-part ID=<id>` on Linux.
4. Look at it in the game too: the start menu's editor turns it; C opens the editor in game.
5. `make check`.

## 6. Open the PR

Follow `contribute`. Commit the source, the record, the `.glb` or `.png` with its `.import`, and the
`ASSETS.toml` entry; nothing under `build/`.

- Title: `feat(character): add <what>`.
- "What changes for the player": the part, its slot, its colours. Attach the sheet.
- On your PR, the `character` check runs `make check-part` for each part you changed and keeps the sheets
  as an artifact linked from its summary, for voters.
- "Not verified": what you could not look at (in game, on a real GPU, a body shape).

## Gotchas

Added when a mistake is confirmed on a real PR.
