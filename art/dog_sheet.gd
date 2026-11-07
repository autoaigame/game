## Draws the dog sprite sheet (assets/dog.png) pixel by pixel: a muted tan dog seen from the side,
## facing right (the game mirrors it to face left). Light from the top left, shading in steps, a
## translucent ground shadow, darker fur instead of a black outline. Layout in client/dog_anim.gd.
extends RefCounted

const FRAME := DogAnim.FRAME_SIZE
const GROUND := DogAnim.FRAME_SIZE.y - DogAnim.FOOT_PX

const FUR_HI := Color8(0xb9, 0x97, 0x6c)
const FUR := Color8(0x98, 0x76, 0x52)
const FUR_MID := Color8(0x7a, 0x5c, 0x3e)
const FUR_DK := Color8(0x58, 0x41, 0x2c)
const EDGE := Color8(0x45, 0x33, 0x23)
const NOSE := Color8(0x2a, 0x22, 0x1e)
const DIRT := Color8(0x6b, 0x55, 0x3d)
const SHADOW := Color(0, 0, 0, 0.27)
const LIGHT := Vector2(-0.6, -0.8)


## The whole sheet: DogAnim.COLUMNS frames per row, one row per DogAnim.ROWS entry.
static func sheet() -> Image:
	var img := Image.create(FRAME.x * DogAnim.COLUMNS, FRAME.y * DogAnim.ROWS.size(), false, Image.FORMAT_RGBA8)
	for r in DogAnim.ROWS.size():
		for f in DogAnim.COLUMNS:
			var frame := draw_frame(DogAnim.ROWS[r], f)
			img.blit_rect(frame, Rect2i(Vector2i.ZERO, FRAME), Vector2i(f * FRAME.x, r * FRAME.y))
	return img


## One frame of a pose (DogAnim.ROWS) at frame index f (0..3).
static func draw_frame(pose: String, f: int) -> Image:
	var img := Image.create(FRAME.x, FRAME.y, false, Image.FORMAT_RGBA8)
	var body := _body(img)
	match pose:
		"idle":
			_standing(body, f, 0.0, 0.0, 1.0 if f % 2 == 0 else 0.0, false, f)
		"walk":
			_standing(body, f, 3.5, 0.0, 0.0, false, f)
		"run":
			_standing(body, f, 6.5, 1.0, 0.0, false, f)
		"sit":
			_sitting(body, f)
		"sleep":
			_sleeping(body, f)
		"pee":
			_standing(body, f, 0.0, 0.0, 0.0, true, f)
		"dig":
			_digging(body, f)
	_finish(img, body)
	return img


# A frame is drawn as a mask of shade levels (0 = empty, then EDGE..FUR_HI), then coloured.
static func _body(img: Image) -> Dictionary:
	return {"img": img, "px": {}}


static func _put(b: Dictionary, p: Vector2i, c: Color) -> void:
	if p.x >= 0 and p.y >= 0 and p.x < FRAME.x and p.y < FRAME.y:
		b["px"][p] = c


## A filled ellipse shaded in steps by its surface facing the light.
static func _ellipse(b: Dictionary, center: Vector2, r: Vector2, dark := false) -> void:
	for y in range(floori(center.y - r.y), ceili(center.y + r.y) + 1):
		for x in range(floori(center.x - r.x), ceili(center.x + r.x) + 1):
			var n := Vector2((x + 0.5 - center.x) / r.x, (y + 0.5 - center.y) / r.y)
			if n.length_squared() > 1.0:
				continue
			var lit := -n.dot(LIGHT)
			var c := FUR if lit > -0.25 else FUR_MID
			if lit > 0.45:
				c = FUR_HI
			if dark:
				c = FUR_MID if c == FUR_HI else FUR_DK
			_put(b, Vector2i(x, y), c)


## A leg (or tail): a thick line from a to b.
static func _limb(b: Dictionary, a: Vector2, z: Vector2, width: float, c: Color) -> void:
	var steps := maxi(2, ceili(a.distance_to(z) * 2.0))
	for i in steps + 1:
		var p := a.lerp(z, float(i) / steps)
		for dy in range(-ceili(width / 2.0), ceili(width / 2.0) + 1):
			for dx in range(-ceili(width / 2.0), ceili(width / 2.0) + 1):
				if Vector2(dx, dy).length() <= width / 2.0:
					_put(b, Vector2i(roundi(p.x + dx), roundi(p.y + dy)), c)


static func _shadow(img: Image, cx: float, rx: float) -> void:
	for y in range(GROUND - 3, GROUND + 3):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var n := Vector2((x + 0.5 - cx) / rx, (y + 0.5 - GROUND) / 3.0)
			if n.length_squared() <= 1.0 and x >= 0 and x < FRAME.x:
				img.set_pixel(x, y, SHADOW)


static func _head(b: Dictionary, h: Vector2, eyes_open := true, ear_up := true) -> void:
	_ellipse(b, h, Vector2(6.5, 6.0))
	_ellipse(b, h + Vector2(6.5, 2.0), Vector2(4.5, 3.0))  # muzzle
	_put(b, Vector2i(roundi(h.x + 10.5), roundi(h.y + 1.0)), NOSE)
	_put(b, Vector2i(roundi(h.x + 10.5), roundi(h.y + 2.0)), NOSE)
	if eyes_open:
		_put(b, Vector2i(roundi(h.x + 2.5), roundi(h.y - 1.5)), NOSE)
	else:
		_put(b, Vector2i(roundi(h.x + 2.0), roundi(h.y - 1.0)), EDGE)
		_put(b, Vector2i(roundi(h.x + 3.0), roundi(h.y - 1.0)), EDGE)
	if ear_up:
		_ellipse(b, h + Vector2(-2.5, -5.0), Vector2(2.5, 4.0), true)
	else:
		_ellipse(b, h + Vector2(-3.0, -1.5), Vector2(3.5, 2.5), true)


## Standing on four legs: swing = leg swing in px, bob = body bounce, wag = tail lift, pee = back leg up.
static func _standing(b: Dictionary, f: int, swing: float, bob: float, wag: float, pee: bool, _i: int) -> void:
	var phase := f * PI / 2.0
	var cx := 30.0
	var cy := GROUND - 15.0 - (bob * absf(sin(phase)))
	_shadow(b["img"], cx + 2.0, 18.0)
	var hip := Vector2(cx - 10.0, cy + 3.0)
	var shoulder := Vector2(cx + 10.0, cy + 3.0)
	var s := sin(phase) * swing
	# far legs, darker
	_limb(b, hip + Vector2(2, 0), Vector2(hip.x + 2 - s, GROUND - 1), 3.0, FUR_DK)
	_limb(b, shoulder + Vector2(-2, 0), Vector2(shoulder.x - 2 + s, GROUND - 1), 3.0, FUR_DK)
	_ellipse(b, Vector2(cx, cy), Vector2(15.0, 7.0))
	# near legs
	if pee:
		_limb(b, hip, Vector2(hip.x - 9.0, cy + 1.0), 3.5, FUR_MID)  # back leg lifted out behind
		_limb(b, Vector2(hip.x - 9.0, cy + 1.0), Vector2(hip.x - 12.0, cy + 5.0), 3.0, FUR_MID)
	else:
		_limb(b, hip, Vector2(hip.x + s, GROUND - 1), 3.5, FUR_MID)
	_limb(b, shoulder, Vector2(shoulder.x - s, GROUND - 1), 3.5, FUR_MID)
	_limb(b, Vector2(cx - 14.0, cy - 3.0), Vector2(cx - 20.0, cy - 9.0 - wag * 2.0), 2.5, FUR)  # tail
	_head(b, Vector2(cx + 16.0, cy - 9.0 + (bob * 1.5 if swing > 5.0 else 0.0)))


static func _sitting(b: Dictionary, f: int) -> void:
	_shadow(b["img"], 31.0, 14.0)
	var wag := 1.0 if f % 2 == 0 else 0.0
	_limb(b, Vector2(18.0, GROUND - 4.0), Vector2(12.0, GROUND - 6.0 - wag * 2.0), 2.5, FUR)  # tail on the ground
	_ellipse(b, Vector2(24.0, GROUND - 7.0), Vector2(8.0, 6.5))  # haunch
	_ellipse(b, Vector2(29.0, GROUND - 15.0), Vector2(8.0, 10.0))  # chest, upright
	_limb(b, Vector2(33.0, GROUND - 10.0), Vector2(34.0, GROUND - 1), 3.5, FUR_MID)
	_limb(b, Vector2(30.0, GROUND - 10.0), Vector2(30.0, GROUND - 1), 3.0, FUR_DK)
	_head(b, Vector2(34.0, GROUND - 27.0 + (1.0 if f == 3 else 0.0)))


static func _sleeping(b: Dictionary, f: int) -> void:
	_shadow(b["img"], 31.0, 19.0)
	var breathe := 1.0 if f >= 2 else 0.0
	_limb(b, Vector2(16.0, GROUND - 4.0), Vector2(24.0, GROUND - 1.0), 2.5, FUR)  # tail curled in front
	_ellipse(b, Vector2(29.0, GROUND - 6.0 - breathe * 0.5), Vector2(16.0, 6.0 + breathe * 0.5))
	_limb(b, Vector2(38.0, GROUND - 3.0), Vector2(48.0, GROUND - 1.0), 3.0, FUR_MID)  # front paws
	_head(b, Vector2(43.0, GROUND - 7.0), false, false)


static func _digging(b: Dictionary, f: int) -> void:
	_shadow(b["img"], 32.0, 18.0)
	var cx := 29.0
	var cy := GROUND - 13.0
	var hip := Vector2(cx - 10.0, cy + 1.0)
	var shoulder := Vector2(cx + 10.0, cy + 5.0)
	var paw := 4.0 if f % 2 == 0 else -2.0
	_limb(b, hip + Vector2(2, 0), Vector2(hip.x + 2, GROUND - 1), 3.0, FUR_DK)
	_limb(b, shoulder + Vector2(-2, 0), Vector2(shoulder.x + 3 - paw, GROUND - 1), 3.0, FUR_DK)
	_ellipse(b, Vector2(cx, cy), Vector2(15.0, 7.0))
	_limb(b, hip, Vector2(hip.x, GROUND - 1), 3.5, FUR_MID)
	_limb(b, shoulder, Vector2(shoulder.x + paw, GROUND - 1), 3.5, FUR_MID)
	_limb(b, Vector2(cx - 14.0, cy - 3.0), Vector2(cx - 19.0, cy - 11.0), 2.5, FUR)  # tail up
	_head(b, Vector2(cx + 16.0, cy + 2.0))
	for i in 3:  # dirt thrown back between the legs
		var d := Vector2(cx - 4.0 - i * 4.0 - f, GROUND - 4.0 - ((i + f) % 3) * 3.0)
		_put(b, Vector2i(roundi(d.x), roundi(d.y)), DIRT)
		_put(b, Vector2i(roundi(d.x) + 1, roundi(d.y)), DIRT)


## Colours the mask into the image, darkening the outer pixels by one step (no black outline).
static func _finish(img: Image, b: Dictionary) -> void:
	var px: Dictionary = b["px"]
	for p: Vector2i in px:
		var c: Color = px[p]
		var edge := false
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not px.has(p + n):
				edge = true
		if edge and c != NOSE and c != DIRT:
			c = EDGE if c == FUR_DK or c == FUR_MID else FUR_DK
		img.set_pixel(p.x, p.y, c)
