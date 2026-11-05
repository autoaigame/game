# Art guide

- **Style:** isometric pixel art in full color, nearest-neighbour filtering, no anti-aliasing. Shade in steps, never with smooth gradients; ordered dithering between steps is fine.
- **Colors:** each material has a ramp, dark to light, at the top of `art/gen_art.gd`. Ramps shift hue: shadows lean cool, highlights warm. Reuse a ramp, or add one for a new material.
- **Light:** comes from the top left. Characters get a 1 px dark outline and a translucent ground shadow.
- **Tiles:** 128×64 px diamonds (2:1), one row per atlas in `assets/tiles.png`. The atlas order matches the `MapData.TILE_*` constants. A tile must join seamlessly with copies of itself: make textures periodic over the tile lattice (see `_lattice` and `_wrap` in `art/gen_art.gd`).
- **Characters:** 64×96 px frames, feet at the bottom, centered. `assets/player.png` has 4 columns (facing down, left, right, up) and 5 rows: standing, then a walk cycle of 4 frames over two steps (`WalkAnim.WALK_FRAMES`; poses in `POSES` in `art/gen_art.gd`).
- **Scale:** the camera shows art at 1 texel per screen pixel (zoom 1). Draw details at this size; do not upscale smaller art.
- **Format:** PNG, RGBA, no metadata you would not want public.
- **Generated art:** prefer extending `art/gen_art.gd` (regenerate with `make art`). Images from other tools are fine with a full `ASSETS.toml` entry.
