## Camera zoom levels for the mouse wheel. Pure functions, so tests can check them.
class_name CameraZoom
extends RefCounted

## Screen pixels per texel, smallest first. 0.5 is the floor: the view then reaches about 21 cells
## from the player, inside the chunks the view keeps loaded, so the edge of the world never shows.
const LEVELS: Array[float] = [0.5, 1.0, 2.0, 3.0]
const DEFAULT := IsoLayer.CAMERA_ZOOM


## The level `steps` notches away from `zoom` (positive zooms in), held at the first and last level.
static func step(zoom: float, steps: int) -> float:
	var at := 0
	for i in LEVELS.size():
		if absf(LEVELS[i] - zoom) < absf(LEVELS[at] - zoom):
			at = i
	return LEVELS[clampi(at + steps, 0, LEVELS.size() - 1)]


## Zoom steps for a mouse button: wheel up zooms in, wheel down zooms out, other buttons do nothing.
static func wheel_steps(button: MouseButton) -> int:
	match button:
		MOUSE_BUTTON_WHEEL_UP:
			return 1
		MOUSE_BUTTON_WHEEL_DOWN:
			return -1
	return 0
