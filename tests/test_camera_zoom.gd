extends TestCase


func test_default_is_the_base_zoom() -> void:
	assert_eq(CameraZoom.DEFAULT, IsoLayer.CAMERA_ZOOM)
	assert_true(CameraZoom.LEVELS.has(CameraZoom.DEFAULT), "default is one of the levels")


func test_wheel_up_zooms_in_one_level() -> void:
	assert_eq(CameraZoom.step(1.0, 1), 2.0)
	assert_eq(CameraZoom.step(2.0, 1), 3.0)


func test_wheel_down_zooms_out_one_level() -> void:
	assert_eq(CameraZoom.step(1.0, -1), 0.5)
	assert_eq(CameraZoom.step(3.0, -1), 2.0)


func test_zoom_stops_at_the_limits() -> void:
	var lo: float = CameraZoom.LEVELS[0]
	var hi: float = CameraZoom.LEVELS[-1]
	assert_eq(CameraZoom.step(hi, 1), hi)
	assert_eq(CameraZoom.step(lo, -1), lo)
	assert_eq(CameraZoom.step(1.0, 10), hi)
	assert_eq(CameraZoom.step(1.0, -10), lo)


## A zoom that is not a level (never set by the game) snaps to the nearest level first.
func test_unknown_zoom_snaps_to_nearest_level() -> void:
	assert_eq(CameraZoom.step(1.9, 0), 2.0)
	assert_eq(CameraZoom.step(1.9, 1), 3.0)


## Wheel notches map to steps; other buttons do not zoom.
func test_wheel_buttons() -> void:
	assert_eq(CameraZoom.wheel_steps(MOUSE_BUTTON_WHEEL_UP), 1)
	assert_eq(CameraZoom.wheel_steps(MOUSE_BUTTON_WHEEL_DOWN), -1)
	assert_eq(CameraZoom.wheel_steps(MOUSE_BUTTON_LEFT), 0)
	assert_eq(CameraZoom.wheel_steps(MOUSE_BUTTON_MIDDLE), 0)
