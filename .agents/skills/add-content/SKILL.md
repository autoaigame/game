---
name: add-content
description: Add game content such as items, enemies, rooms, sprites or sounds through data files and assets. Use when a contribution adds or adjusts content without changing engine code.
---

# Add content

Content is data with a schema. It needs no engine code, which makes it the easiest kind of PR to review and vote on.

## Choose the path

- It fits the existing schemas: continue here.
- It needs a field or behavior that does not exist: this is a logic change, so open an issue and use `test-change`. Do not hack around the schema.
- It only changes numbers: use the type `balance` in the PR title.

## Data

1. Copy the closest existing entry and change it. For now the only content is the map in `shared/map_data.gd` (tile types are the `TILE_*` constants). Data files with schemas will come with the first content type that needs them.
2. Use a new, unique id. Never reuse or rename an existing id, since saves refer to it.
3. Run `make check`.
4. Say in the PR what the player will see, and when.

## Assets

1. Read `docs/art-guide.md` and follow its palette, size and format.
   The game's pixel art is drawn by `art/gen_art.gd`. To change or add sprites (new frames, tiles), extend it, run `make art`, and commit the script with the regenerated PNGs. Keep `tests/test_art.gd` true, or change it with the reason in the PR.
2. Add an entry to `ASSETS.toml` for each file. CI refuses a file without one:

```toml
[[asset]]
path = "assets/items/potion.png"
author = "github-login"
origin = "generated" # generated, original or third-party
tool = "name and version, if generated"
prompt = "the prompt, if generated"
license = "license of this file"
source = "URL, if third-party"
```

3. CI does not check assets automatically yet: check the format and size yourself against `docs/art-guide.md`, and that every new file has its `ASSETS.toml` entry.
4. Do not imitate a living artist or a known game, and do not submit anything you cannot license.

The declaration is on your honor, and CI cannot check it. If you do not know where a file came from, do not submit it.

## Gotchas

Added when a mistake is confirmed on a real PR.
