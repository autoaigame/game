## Smooth camera zoom for the mouse wheel. Pure functions, so tests can check them.
class_name CameraZoom
extends RefCounted

## Screen pixels per texel. MIN is the floor: the view then reaches about 21 cells from the player,
## inside the chunks the view keeps loaded, so the edge of the world never shows.
const MIN := 0.5
const MAX := 2.0
const DEFAULT := IsoLayer.CAMERA_ZOOM
const NOTCH := 1.15  ## one wheel notch scales the target zoom by this
const RATE := 15.0  ## per second: how fast the zoom closes the gap to its target
const SNAP := 0.001  ## relative gap under which the zoom lands on the target


## The target zoom after `steps` wheel notches (positive zooms in, fractions allowed), within the limits.
static func target_after(target: float, steps: float) -> float:
	return clampf(target * pow(NOTCH, steps), MIN, MAX)


## The zoom shown after `dt` seconds of gliding from `zoom` toward `target`. It moves in log space,
## so zooming in and out feel alike, and never passes the target.
static func approach(zoom: float, target: float, dt: float) -> float:
	var k := 1.0 - exp(-RATE * dt)
	var z := exp(lerpf(log(zoom), log(target), k))
	if absf(z - target) <= SNAP * target:
		return target
	return z


## Wheel notches for a mouse button event: up zooms in, down zooms out, other buttons do nothing.
## `factor` is the event's scroll amount: a fraction of a notch on fine wheels, 0 when the platform
## does not report it (a full notch).
static func wheel_steps(button: MouseButton, factor: float) -> float:
	var notch := factor if factor > 0.0 else 1.0
	match button:
		MOUSE_BUTTON_WHEEL_UP:
			return notch
		MOUSE_BUTTON_WHEEL_DOWN:
			return -notch
	return 0.0
