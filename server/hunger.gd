## Hunger: MAX when full, drops one point every SECONDS_PER_POINT, never below 0. At 0 the player
## walks at STARVING_SPEED times the normal speed. Pure functions (server only).
extends RefCounted

const MAX := 100.0
const SECONDS_PER_POINT := 30.0
const STARVING_SPEED := 0.6


static func tick(hunger: float, dt: float) -> float:
	return maxf(hunger - dt / SECONDS_PER_POINT, 0.0)


## Multiplier of the walking speed (1 unless starving).
static func speed_factor(hunger: float) -> float:
	return STARVING_SPEED if hunger <= 0.0 else 1.0


## Hunger after eating something worth `food` points, at most MAX.
static func fed(hunger: float, food: int) -> float:
	return minf(hunger + food, MAX)
