---
name: test-change
description: Write and check tests for a change to game logic. Use when adding a mechanic, fixing a game bug, or changing rules, simulation or save code.
---

# Test a change

A test only counts if it can fail. Agent-written tests often restate the fix, so check that yours would catch the bug.

## Steps

1. Read `docs/invariants.md` and note the rules your change touches.
2. Write the test first and run it. Check that it fails for the expected reason. If it passes already, the test or your understanding is wrong.
3. Make the change. Run the test until it passes.
4. Mutate your fix: undo the key line or flip the condition, and run the test. It must fail. Restore the fix and do not commit the mutation.
5. Run `make check`.

## What to test

- Prefer checking game state at a given tick over checking the code's internal calls.
- For a rule that needs a situation, inject the state directly and run the fewest ticks that show the result. Do not rely on an agent playing freely.
- Server logic: call `Protocol`/`MapData` functions directly with a fixed `dt`; see `tests/test_movement.gd`.
- Fix the seed and the time step. Do not use the wall clock or the network in a test.
- Test the edge the rule creates: zero, the maximum, two entities on the same tick, a save loaded afterwards.

## Tiers

| Tier | Command | When |
|---|---|---|
| Unit and state | `make test` | Every change |
| Smoke | `make smoke` | Every change |
| Scenario | add a step to `tools/smoke.sh` (admin-only: propose it in the PR description) | The change affects a whole play sequence |

Run what you can. List in "Not verified" any tier you skipped, and why. Do not write "tested" without a command and its result.

## Existing tests

If an existing test fails, assume your change broke something. Change the test only when the rule really changed, and list it in the PR under "Existing tests changed", since voters see that list.

## Gotchas

Added when a mistake is confirmed on a real PR.
