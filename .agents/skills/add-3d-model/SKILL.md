---
name: add-3d-model
description: Create a 3D model from scratch (mesh, skeleton, weights, animations) by script and draw it in the game's pixel-art render. Use when adding a creature, a character or an animated object as a 3D model.
---

# Add a 3D model

A model is a Blender script in `art/models/` that builds everything itself: no imported mesh, skeleton or animation. Anyone can rerun the script and get the same `.glb`. The game draws the model with `client/model_3d.gd`, the render the players already use.

The complete example is `art/models/zombie.py`. Its shared tools are in `art/models/rig_kit.py`. Read both before you start, and copy the zombie rather than starting from an empty file.

## Before you start

- A model that only shows on screen (a look, a demo, a decoration) needs no issue.
- A model that needs the server to know about it (a creature that moves, attacks or dies in the game) is a game mechanic. Open an issue first: the server decides every position, hit and death (`docs/invariants.md`).
- New colours in `data/palette.json` or changes to `client/model_3d.gd` and its shaders change every model. Open an issue for those too.

## Steps

1. Shape. Build the mesh with `Builder` from `rig_kit.py`: tubes with a rounded section along each bone, and boxes for details. Each volume belongs to one bone and one material. Keep the shapes big: at game size one metre is about 70 px, so anything under 3 cm is one pixel or less. Make limbs as thick as the player's (`GIRTH` in the zombie). Torn clothes are a wider tube with a jagged hem (`jag`).
2. Scale. Work in metres, facing -Y in Blender (+Z in Godot), feet on z = 0. Every model shares the player's scale, so a human-sized model is about 1.6 to 1.8 m tall. Put the feet on the ground with `Builder.sit_on_ground` after you change their size.
3. Colours. Use flat colours from `data/palette.json`, one material per colour. The render snaps light to palette colours of the same hue, so pick the base colour and let the render do the shading. Use different materials where you want an inner line between two parts.
4. Skeleton. Write a bone table and pass it to `make_armature`. Reuse the player's bone names (`DEF-hips`, `DEF-spine.001`, `DEF-head`, `DEF-thigh.L`...) for the bones a human-like model shares with it. The player's clips still will not fit: lengths and orientations differ.
5. Joints and weights. Separate volumes crack open at the joints when each follows its own bone. Call `skin`: it blends the weights round each joint by position, so every volume that reaches a joint gets the same weights there and bends with the others. Do not use Blender's automatic weights: bone heat gives each separate volume its own bone, and the joints open by several centimetres. At joints that bend far (shoulders, hips, elbows, knees), add a `ball` centred on the pivot, and end the volumes on either side inside it. Give a tube that crosses a joint's blend zone rings every few centimetres (`ring_gap`), or its flat faces tilt and let what is inside poke out. Keep hidden skin a little thinner than the cloth over it.
6. Animations. Write each clip as a function of time and bake it with `bake` on every frame. Use `Poser`: rotations in armature axes, `aim` for limbs, `ik` for legs on a foot path. A walk plants each foot for the stance part of the cycle and moves it back at exactly stride / duration. Swing it forward eased and lifted, and give the body and head a phase lag behind the hips. One-shot clips use eased keys (`keys`). Write down in the code what every curve does. Do not set keyframes by hand.
7. Export. Use `export` and `write_json`. Write a `<model>_clips.json` next to the `.glb` with each clip's duration, the walk's speed, stride and contacts, the time of any hit, and the checks below.
8. Draw it. Subclass `Model3D` like `client/zombie_3d.gd`: load the `.glb` in `_build_model`, call `_matte`, and blend the clips in `_animate` with an `AnimationTree` of time seeks. Advance the walk phase by speed / stride so the planted foot does not slide. Give the viewport room for the widest pose (`view_size`, `foot_px`). The model is sorted by where its feet stand, even lying down.
9. Add the `.glb` and the `.json` to `ASSETS.toml`, with origin `original`, licence and the script in `tool`.

Run the script with Blender 5.2: `blender -b --python art/models/zombie.py -- .` (about 3 s).

## Checks

- Measure on the deformed mesh in the script, and fail a test on them like `tests/test_zombie_3d.gd`: soles within 1 cm of the ground, planted feet sliding less than 2 cm, IK targets reached, no arm in the torso and no leg through the other (`measure`, `crossings`), and no crack at a joint wider than half a pixel in any pose of any clip (`joint_gaps`; run with `JOINT_DEBUG=1` to see which volumes open).
- Clips that bring a body to the ground go under it. Measure the lowest point on every frame and bake again with that lift, as `make_death` does.
- Render a sheet next to the player at game size: `godot --path . -s res://art/models/model_sheet.gd -- sheet <dir>`. Run it with a display. Without a GPU, start `Xvfb :97` and set `DISPLAY=:97`. Look at the front, 3/4, profile and back of every clip. Most mistakes only show here: a hanging limb swings backwards with a positive pitch, so check every arm and foot angle in profile.
- Look at the joints at ×6 on the sheet (elbows, shoulders, knees) in walk and attack poses: a notch of one pixel shows there before anywhere else.
- Budget: the zombie is 1172 vertices, 2120 triangles, 21 bones and a 315 KB `.glb`. Stay close to that for one creature.
- Run `make check`.

## Gotchas

Added when a mistake is confirmed on a real PR.
