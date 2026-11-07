# Game invariants

Rules that must hold whatever the change. Tests and audits check changes against them. Changing one is a game-design decision: open an issue first.

1. **The server is authoritative.** Clients send intentions (`join`, `move_to`, `stop`). Only the server changes positions and broadcasts them (`snapshot`). A client never decides where any player is.
2. **Nobody stands on a non-walkable cell.** Spawn, saved positions, and every movement step (`Protocol.step_towards`) stay on cells where `MapData.is_walkable` is true.
3. **Movement never overshoots.** A player moves at most `Protocol.SPEED_CELLS_PER_S` cells per second and stops exactly on its target, or earlier where it stands when its client sends `stop`.
4. **One online player per name.** A second join with a name already online is rejected. Names follow `Protocol.validate_name`.
5. **Positions survive a disconnect.** A player who leaves, even abruptly, comes back at the cell where they were. Saves happen on disconnect and periodically.
6. **The web build contains no server code.** `server/` and `addons/godot-sqlite/` are excluded from the Web export; client code never loads them.
7. **Shared code is deterministic.** `shared/` uses no wall clock, no randomness without a fixed seed, and no network. The world is a pure function of the world seed and the cell coordinates: a cell is the same whichever chunk asks, on the server and in every client.
