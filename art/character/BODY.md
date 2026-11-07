# Base body and skeleton

The 3D character (`client/character_3d.gd`) is one base body on one skeleton. Every character part is
modelled over this body and either skinned to this skeleton or attached to one of its bones. Built by
`art/character/body.py` from the Quaternius Universal Animation Library mannequin (CC0), reshaped into
a sturdy stylised adult (head a fifth of the height, thicker limbs).

## Frame

- Units: metres. Y up. The character faces **+Z** (glTF and Godot). Its left is +X.
- Origin: on the ground, between the feet (the `root` bone sits at the origin). The soles touch y = 0 in
  the rest pose and in `idle`.
- Height: 1.631 m (top of the head), the head from chin to top a fifth of it.
- In game, `Character3D` draws the top of the head 100 px above the feet (`HEAD_PX`), a little under the
  sprite's 105 px so the 3D body does not look heavier; at this height one metre is about 71 px and one
  map cell about 0.96 m.
- Rest pose: T-pose (arms along ±X). Clips are stored as rotations relative to this rest pose, plus the
  hips' location; no root motion (the loops stay in place).

## Bones

53 bones, the names and hierarchy of the source rig. Head positions of the rest pose, in metres, in the
frame above (bone directions and rolls are the source rig's). Fingers (`DEF-f_index|middle|ring|pinky.01-03.L/R`, `DEF-thumb.01-03.L/R`) hang
from `DEF-hand.*`.

| bone | parent | head (x, y, z) |
|---|---|---|
| `root` | — | 0.000, 0.000, 0.000 |
| `DEF-hips` | `root` | 0.000, 0.756, -0.050 |
| `DEF-spine.001` | `DEF-hips` | -0.000, 0.876, -0.019 |
| `DEF-spine.002` | `DEF-spine.001` | -0.000, 0.987, -0.005 |
| `DEF-spine.003` | `DEF-spine.002` | -0.000, 1.114, -0.009 |
| `DEF-neck` | `DEF-spine.003` | -0.000, 1.270, -0.014 |
| `DEF-head` | `DEF-neck` | -0.000, 1.322, -0.004 |
| `DEF-shoulder.L` | `DEF-spine.003` | 0.020, 1.243, 0.071 |
| `DEF-upper_arm.L` | `DEF-shoulder.L` | 0.204, 1.225, -0.074 |
| `DEF-forearm.L` | `DEF-upper_arm.L` | 0.451, 1.225, -0.078 |
| `DEF-hand.L` | `DEF-forearm.L` | 0.696, 1.225, -0.074 |
| `DEF-f_index.01.L` | `DEF-hand.L` | 0.831, 1.223, -0.040 |
| `DEF-f_index.02.L` | `DEF-f_index.01.L` | 0.876, 1.223, -0.040 |
| `DEF-f_index.03.L` | `DEF-f_index.02.L` | 0.915, 1.223, -0.040 |
| `DEF-f_middle.01.L` | `DEF-hand.L` | 0.832, 1.226, -0.068 |
| `DEF-f_middle.02.L` | `DEF-f_middle.01.L` | 0.880, 1.226, -0.071 |
| `DEF-f_middle.03.L` | `DEF-f_middle.02.L` | 0.918, 1.226, -0.072 |
| `DEF-f_pinky.01.L` | `DEF-hand.L` | 0.817, 1.223, -0.120 |
| `DEF-f_pinky.02.L` | `DEF-f_pinky.01.L` | 0.862, 1.223, -0.123 |
| `DEF-f_pinky.03.L` | `DEF-f_pinky.02.L` | 0.893, 1.223, -0.125 |
| `DEF-f_ring.01.L` | `DEF-hand.L` | 0.830, 1.225, -0.093 |
| `DEF-f_ring.02.L` | `DEF-f_ring.01.L` | 0.874, 1.225, -0.095 |
| `DEF-f_ring.03.L` | `DEF-f_ring.02.L` | 0.908, 1.225, -0.096 |
| `DEF-thumb.01.L` | `DEF-hand.L` | 0.727, 1.200, -0.037 |
| `DEF-thumb.02.L` | `DEF-thumb.01.L` | 0.765, 1.178, -0.017 |
| `DEF-thumb.03.L` | `DEF-thumb.02.L` | 0.809, 1.154, 0.006 |
| `DEF-shoulder.R` | `DEF-spine.003` | -0.020, 1.243, 0.071 |
| `DEF-upper_arm.R` | `DEF-shoulder.R` | -0.204, 1.225, -0.074 |
| `DEF-forearm.R` | `DEF-upper_arm.R` | -0.451, 1.225, -0.078 |
| `DEF-hand.R` | `DEF-forearm.R` | -0.696, 1.225, -0.074 |
| `DEF-f_index.01.R` | `DEF-hand.R` | -0.831, 1.223, -0.040 |
| `DEF-f_index.02.R` | `DEF-f_index.01.R` | -0.876, 1.223, -0.040 |
| `DEF-f_index.03.R` | `DEF-f_index.02.R` | -0.915, 1.223, -0.040 |
| `DEF-f_middle.01.R` | `DEF-hand.R` | -0.832, 1.226, -0.068 |
| `DEF-f_middle.02.R` | `DEF-f_middle.01.R` | -0.880, 1.226, -0.071 |
| `DEF-f_middle.03.R` | `DEF-f_middle.02.R` | -0.918, 1.226, -0.072 |
| `DEF-f_pinky.01.R` | `DEF-hand.R` | -0.817, 1.223, -0.120 |
| `DEF-f_pinky.02.R` | `DEF-f_pinky.01.R` | -0.862, 1.223, -0.123 |
| `DEF-f_pinky.03.R` | `DEF-f_pinky.02.R` | -0.893, 1.223, -0.125 |
| `DEF-f_ring.01.R` | `DEF-hand.R` | -0.830, 1.225, -0.093 |
| `DEF-f_ring.02.R` | `DEF-f_ring.01.R` | -0.874, 1.225, -0.095 |
| `DEF-f_ring.03.R` | `DEF-f_ring.02.R` | -0.908, 1.225, -0.096 |
| `DEF-thumb.01.R` | `DEF-hand.R` | -0.727, 1.200, -0.037 |
| `DEF-thumb.02.R` | `DEF-thumb.01.R` | -0.765, 1.178, -0.017 |
| `DEF-thumb.03.R` | `DEF-thumb.02.R` | -0.809, 1.154, 0.006 |
| `DEF-thigh.L` | `DEF-hips` | 0.094, 0.768, 0.002 |
| `DEF-shin.L` | `DEF-thigh.L` | 0.094, 0.448, -0.001 |
| `DEF-foot.L` | `DEF-shin.L` | 0.094, 0.106, -0.028 |
| `DEF-toe.L` | `DEF-foot.L` | 0.094, 0.017, 0.121 |
| `DEF-thigh.R` | `DEF-hips` | -0.094, 0.768, 0.002 |
| `DEF-shin.R` | `DEF-thigh.R` | -0.094, 0.448, -0.001 |
| `DEF-foot.R` | `DEF-shin.R` | -0.094, 0.106, -0.028 |
| `DEF-toe.R` | `DEF-foot.R` | -0.094, 0.017, 0.121 |

## Mesh and skinning

- About 8 800 vertices and 14 300 triangles, one vertex group per bone (`DEF-*`), at most 4 influences per vertex
  after glTF export.
- Cut along straight lines of the rest pose into one mesh per region, named `body_<region>`, each with
  one material named after the region: `head`, `scalp` (the top of the skull, what a hat covers), `nape`
  (the back of the head below it; hair covers both), `torso`, `arms_upper` (to 45 % of the upper arm, a short sleeve), `arms_lower`, `hands`,
  `hips` (waist to mid-thigh), `legs_upper` (to the knee), `legs_lower` (to a quarter up the shin, a
  boot top), `feet`. A garment can hide the regions it covers instead of fighting the skin.
- Default outfit, flat colours of the kit palette: skin `c09576` (head, hands), hair `3a2f27` (scalp, nape),
  jacket `8f8a63` (torso, arms), jeans `455466` (hips, legs), boots `51433a` (feet).
- Lighting and palette are applied in game (`client/pixel_3d_lit.gdshader`): 3 light bands, the colours
  of `data/palette.json`, 1 px outline.

## Clips

`idle`, `walk`, `jog`, `sprint` (from `Idle_Loop`, `Walk_Loop`, `Jog_Fwd_Loop`, `Sprint_Loop`), adapted to
the new proportions by the build script: hips location scaled by the leg factor, upper arms rotated
outwards (5°), hips lifted on the poses where a foot would dig into the ground (soles within 1.3 cm of the
ground in every gait). `assets/character/body_clips.json` has, per clip, its duration, ground speed and
stride (from the backward travel of the ankles), each foot's mid-stance and contact (where it lands: its
front-most point), as fractions of the clip. The game plays every gait on one shared phase (0 = left
mid-stance) and plays a footstep on each contact.

## Rebuilding

```
blender -b --python art/character/body.py -- <AnimationLibrary_Godot_Standard.glb> .
```

`AnimationLibrary_Godot_Standard.glb` is in the Universal Animation Library (Standard) download. The
script writes `assets/character/body.glb` and `assets/character/body_clips.json`, and prints its checks
(feet on the ground, arms in the torso and legs in each other, per clip). Proportions are the `BODY`
table at the top of the script.
