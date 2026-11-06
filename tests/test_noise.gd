extends TestCase

## WorldNoise: home-made integer hash and gradient noise (shared, deterministic).


func test_hash_is_32_bit_and_stable() -> void:
	for c in [Vector2i(0, 0), Vector2i(-1, -1), Vector2i(100000, -100000), Vector2i(7, 3)]:
		var h := WorldNoise.hash2(42, c.x, c.y)
		assert_true(h >= 0 and h <= 0xFFFFFFFF, "hash out of 32 bits at %s: %d" % [c, h])
		assert_eq(WorldNoise.hash2(42, c.x, c.y), h, "same input, same hash")


func test_hash_depends_on_every_input() -> void:
	var base := WorldNoise.hash3(1, 2, 3, 4)
	assert_true(WorldNoise.hash3(2, 2, 3, 4) != base, "seed")
	assert_true(WorldNoise.hash3(1, 3, 3, 4) != base, "x")
	assert_true(WorldNoise.hash3(1, 2, 4, 4) != base, "y")
	assert_true(WorldNoise.hash3(1, 2, 3, 5) != base, "z")
	assert_true(WorldNoise.hash2(1, 2, 3) != WorldNoise.hash2(1, 3, 2), "x and y are not symmetric")


## Roughly uniform: the mean of many unit hashes is near 0.5 and both halves are hit.
func test_unit_hash_is_spread() -> void:
	var sum := 0.0
	var low := 0
	for i in 2000:
		var u := WorldNoise.unit(WorldNoise.hash2(9, i, -i * 3))
		assert_true(u >= 0.0 and u < 1.0)
		sum += u
		if u < 0.5:
			low += 1
	assert_almost(sum / 2000.0, 0.5, 0.03)
	assert_true(low > 900 and low < 1100, "low half: %d" % low)


func test_noise_in_unit_range() -> void:
	for i in 500:
		var x := (i * 37 % 1000) * 0.173 - 80.0
		var y := (i * 91 % 1000) * 0.311 - 150.0
		var n := WorldNoise.noise(5, x, y)
		assert_true(n >= 0.0 and n <= 1.0, "noise %f at %f,%f" % [n, x, y])
		var f := WorldNoise.fbm(5, x, y, 5)
		assert_true(f >= 0.0 and f <= 1.0, "fbm %f at %f,%f" % [f, x, y])


## Continuous: a tiny step changes the value a little, including across lattice lines.
func test_noise_is_continuous() -> void:
	for x in [-2.0, -0.001, 0.0, 3.999, 4.0, 100000.0]:
		var a := WorldNoise.noise(3, x, 1.5)
		var b := WorldNoise.noise(3, x + 0.001, 1.5)
		assert_true(absf(a - b) < 0.01, "jump at x=%f: %f -> %f" % [x, a, b])


## Not flat: values vary over a few lattice cells.
func test_noise_varies() -> void:
	var lo := 1.0
	var hi := 0.0
	for i in 200:
		var n := WorldNoise.fbm(11, i * 0.37, i * 0.21, 4)
		lo = minf(lo, n)
		hi = maxf(hi, n)
	assert_true(hi - lo > 0.3, "range %f..%f" % [lo, hi])


func test_seed_changes_noise() -> void:
	var same := 0
	for i in 50:
		if is_equal_approx(WorldNoise.noise(1, i * 0.7, 0.3), WorldNoise.noise(2, i * 0.7, 0.3)):
			same += 1
	assert_true(same < 5, "%d equal values for two seeds" % same)


## Golden values: any change here changes every world. Update only on purpose, and say so in the PR.
func test_golden_hashes() -> void:
	assert_eq(WorldNoise.hash2(0, 0, 0), GOLDEN_HASH[0])
	assert_eq(WorldNoise.hash2(1, -1, -1), GOLDEN_HASH[1])
	assert_eq(WorldNoise.hash2(12345, 100000, -100000), GOLDEN_HASH[2])
	assert_eq(WorldNoise.hash3(7, -3, 5, 2), GOLDEN_HASH[3])


func test_golden_noise() -> void:
	assert_almost(WorldNoise.noise(0, 0.5, 0.5), GOLDEN_NOISE[0], 1e-9)
	assert_almost(WorldNoise.noise(1, -12.25, -7.75), GOLDEN_NOISE[1], 1e-9)
	assert_almost(WorldNoise.noise(12345, 100000.3, -100000.6), GOLDEN_NOISE[2], 1e-9)
	assert_almost(WorldNoise.fbm(99, 0.01, 0.02, 5), GOLDEN_NOISE[3], 1e-9)
	assert_almost(WorldNoise.fbm(99, -2500.4, 100000.7, 5), GOLDEN_NOISE[4], 1e-9)


const GOLDEN_HASH := [1680814304, 1911167787, 4287040602, 3766745228]
const GOLDEN_NOISE := [0.463388347648318, 0.575340645422408, 0.450780012257420, 0.407389550058943,
		0.506383006102961]
