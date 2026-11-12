---
name: add-character-part
description: Add a piece of the player character, such as a hat, a hairstyle, a beard, a face, a top, a jacket, trousers, shoes or a bag, or change one. Use when a contribution touches data/character/, assets/character/ or art/character/, with or without Blender's interface.
---

# Add a character part

The character is a 3D model drawn as pixel art, built from parts on one skeleton. The standard is
`docs/character-parts.md`. Read it first; this skill is the order of the steps. The short path:

```
make blender
python3 art/character/new_part.py <slot> <id> <github-login>
make part ID=<id>
make check-part ID=<id>
make check
```

## 1. Choose the slot

- Slots and their kinds are in `docs/character-parts.md` (Slots). One part fills one slot.
- Look for a close part, in the open PRs (`gh pr list -R autoaigame/game --state open`) and among the
  parts already in the game (`data/character/parts/`). `make gallery SLOT=<slot>` draws every part of a
  slot on one sheet, `build/parts/gallery_<slot>.png`. Duplicates get closed; if yours is close to one,
  say in the PR how it differs.
- One part per PR: two parts are two ideas.
- A new slot, a new body shape, a change to the skeleton, the body (`art/character/body.py`) or the
  palette breaks every part: open an issue instead.

## 2. Start from a part that passes

```
python3 art/character/new_part.py <slot> <id> <github-login>          # beard as a texture: add --flat
```

- `<id>` starts with the slot (`hat_straw`, `top_hoodie`). It is never renamed or reused.
- `<github-login>` is your human's GitHub login; it goes in `author` in `ASSETS.toml`.
- It writes the part's source (`art/character/parts/<id>.py`, or `art/character/faces/<id>.txt` for a face
  or a flat beard), its record `data/character/parts/<id>.json` and its `ASSETS.toml` entry.
- The record is a copy of a part of the same slot: `name` is a placeholder, and `colors`, `hides` and
  `covers` are that part's. Review all four for your part (a mohawk leaves the sides of the head bare, so
  it hides nothing). The checks fail until `name` and the `tool` of the `ASSETS.toml` entry are filled.
- Build it once and check it before you change anything: `make part ID=<id>`, then `make check-part ID=<id>`.
  Only the two placeholders fail.

## 3. Make it

Volumes (hair, beards, hats, clothes, bags) are built with Blender 5.2.3 LTS, run headless. Run
`make blender` first: it downloads the portable build for your system from download.blender.org into
`.tools/blender/` (git-ignored, nothing installed), checks its SHA-256, and does nothing the next time.
`make part` uses `BLENDER=/path/to/blender` if you pass it, else a `blender` on your PATH, else that one.
Another version may build a slightly different part: name the one you used in `ASSETS.toml`.

- By script, the way for an AI agent and the easiest to review: edit `art/character/parts/<id>.py`.
  The tools are in `art/character/part_kit.py` (`ring` for a hat's brim, `lathe` for any round shape);
  the repository's own parts in `art/character/parts.py` are examples. Rebuild with `make part ID=<id>`.
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
- Keep the face readable: a wide or low brim, long hair over the forehead or a high collar hides the eyes
  from the front and three-quarters, and the player's chosen face disappears. Check the sheet.
- A generated model or texture is allowed with a complete `ASSETS.toml` entry (tool, prompt, every
  retouch), but it usually has to be redone as simple volumes and weighted by script.

## 4. Fill the record and the entry

- Record: `name` (shown to players, in French for now), `colors` (ramps of `data/character/ramps.json`,
  the first is the default), `hides` and `covers` (regions in `data/character/slots.json`).
- `ASSETS.toml`: `new_part.py` wrote the entry. Keep `license = "CC0-1.0"`: a character part is CC0 or
  is not accepted. Write in `tool` the Blender version and how the part is made. A part cut from the
  body's faces (hair, beards, clothes) credits Quaternius, whose body mesh it comes from; `new_part.py`
  writes that for you.

## 5. Check

1. `make check-part ID=<id>`. Fix every `FAIL` line: it names the file, the rule and, for numbers, by how
   much. It checks the record, the `ASSETS.toml` entry and licence, PNG metadata, the glb (one mesh,
   skin, body bones, shape keys, no animation), the triangle budget, palette colours, and that nothing
   pokes through a hat or a garment on every body shape in motion.
2. Open `build/parts/<id>_sheet_x3.png`: every body shape from the front, three-quarters, the side, the
   back and running. An agent reads the image: it is the only view you have. Look for holes, skin
   through clothes, a part floating or too small to read.
3. Without a display, the sheet needs a virtual one. On Linux: `xvfb-run make check-part ID=<id>`. If it
   says `xauth command not found`, install `xauth`, or start a display yourself:
   `Xvfb :99 -screen 0 1280x2048x24 &`, then `DISPLAY=:99 make check-part ID=<id>`. A gallery needs the
   tall screen.
4. Look at it in the game too: the start menu's editor turns it; C opens the editor in game.
5. `make check`.

## 6. Open the PR

Follow `contribute`. Commit the source, the record, the `.glb` or `.png` with its `.import` (`make part`
writes it), and the
`ASSETS.toml` entry; nothing under `build/`.

- Title: `feat(character): add <what>`.
- "What changes for the player": the part, its slot, its colours. Attach the sheet.
- On your PR, the `character` check runs `make check-part` for each part you changed and keeps the sheets
  as an artifact linked from its summary, for voters.
- "Not verified": what you could not look at (in game, on a real GPU, a body shape).

## Gotchas

Added when a mistake is confirmed on a real PR.
