extends TestCase


func test_default_is_the_base_zoom() -> void:
	assert_eq(CameraZoom.DEFAULT, IsoLayer.CAMERA_ZOOM)
	assert_true(CameraZoom.MIN < CameraZoom.DEFAULT and CameraZoom.DEFAULT < CameraZoom.MAX, "default between the limits")


func test_limits() -> void:
	assert_eq(CameraZoom.MIN, 0.5)
	assert_eq(CameraZoom.MAX, 2.0)


## Each notch scales the target by the same factor, so zooming feels even at every zoom.
func test_notch_scales_the_target() -> void:
	assert_true(is_equal_approx(CameraZoom.target_after(1.0, 1), CameraZoom.NOTCH), "one notch in")
	assert_true(is_equal_approx(CameraZoom.target_after(1.0, -1), 1.0 / CameraZoom.NOTCH), "one notch out")
	assert_true(is_equal_approx(CameraZoom.target_after(CameraZoom.target_after(1.0, 1), -1), 1.0), "in then out")
	assert_true(CameraZoom.NOTCH > 1.0 and CameraZoom.NOTCH < 1.3, "a notch is a small step")


func test_target_stops_at_the_limits() -> void:
	assert_eq(CameraZoom.target_after(1.0, 50), CameraZoom.MAX)
	assert_eq(CameraZoom.target_after(1.0, -50), CameraZoom.MIN)
	assert_eq(CameraZoom.target_after(CameraZoom.MAX, 1), CameraZoom.MAX)
	assert_eq(CameraZoom.target_after(CameraZoom.MIN, -1), CameraZoom.MIN)


## The camera glides: part of the way each frame, never past the target, there within half a second.
func test_zoom_glides_to_the_target() -> void:
	var z := CameraZoom.approach(1.0, 2.0, 1.0 / 60.0)
	assert_true(z > 1.0 and z < 1.2, "one frame moves a little: %s" % z)
	z = 1.0
	for i in 30:
		var next := CameraZoom.approach(z, 2.0, 1.0 / 60.0)
		assert_true(next >= z and next <= 2.0, "moves toward the target without overshooting")
		z = next
	assert_eq(z, 2.0)
	z = 2.0
	for i in 30:
		z = CameraZoom.approach(z, 0.5, 1.0 / 60.0)
	assert_eq(z, 0.5)


func test_no_time_no_move() -> void:
	assert_eq(CameraZoom.approach(1.0, 2.0, 0.0), 1.0)
	assert_eq(CameraZoom.approach(1.5, 1.5, 1.0 / 60.0), 1.5)


## A long frame (a hitch) lands on the target instead of jumping past it.
func test_long_frame_does_not_overshoot() -> void:
	assert_eq(CameraZoom.approach(1.0, 2.0, 5.0), 2.0)


## Wheel notches map to steps; other buttons do not zoom. Fine wheels (trackpads) send a fraction of a notch.
func test_wheel_steps() -> void:
	assert_eq(CameraZoom.wheel_steps(MOUSE_BUTTON_WHEEL_UP, 0.0), 1.0)
	assert_eq(CameraZoom.wheel_steps(MOUSE_BUTTON_WHEEL_DOWN, 0.0), -1.0)
	assert_eq(CameraZoom.wheel_steps(MOUSE_BUTTON_WHEEL_UP, 0.25), 0.25)
	assert_eq(CameraZoom.wheel_steps(MOUSE_BUTTON_LEFT, 1.0), 0.0)
	assert_eq(CameraZoom.wheel_steps(MOUSE_BUTTON_MIDDLE, 1.0), 0.0)
