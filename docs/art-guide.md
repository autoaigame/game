# Art guide

- **Style:** isometric pixel art, nearest-neighbour filtering, no anti-aliasing, no gradients.
- **Palette:** the 16 colors in `PALETTE` at the top of `tools/gen_art.gd`. Use only these.
- **Tiles:** 32×16 px diamonds (2:1), one row per atlas in `assets/tiles.png`. The atlas order matches the `MapData.TILE_*` constants.
- **Characters:** 16×24 px frames, feet at the bottom, centered. `assets/player.png` has 4 columns (facing down, left, right, up) and 2 rows (walk frames).
- **Format:** PNG, RGBA, no metadata you would not want public.
- **Generated art:** prefer extending `tools/gen_art.gd` (regenerate with `make art`). Images from other tools are fine with a full `ASSETS.toml` entry.
