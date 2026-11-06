## Home-made integer hash and gradient noise for world generation. Pure functions of
## (seed, world coordinates): no Godot hash(), no RandomNumberGenerator, no FastNoiseLite, so the
## values never change with the engine version and are the same on the server and in the browser.
## Every world is built from these numbers: changing them changes every world (see the golden test).
class_name WorldNoise
extends RefCounted

const MASK32 := 0xFFFFFFFF
const _DIAG := 0.70710678118654752  ## 1/sqrt(2): diagonal gradients have length 1
## 8 unit gradients, picked by the low 3 bits of a hash.
const _GRAD_X := [1.0, -1.0, 0.0, 0.0, _DIAG, -_DIAG, _DIAG, -_DIAG]
const _GRAD_Y := [0.0, 0.0, 1.0, -1.0, _DIAG, _DIAG, -_DIAG, -_DIAG]


## a * b modulo 2^32 for 32-bit a and b, split in 16-bit halves so no 64-bit product overflows.
static func mul32(a: int, b: int) -> int:
	var lo := a * (b & 0xFFFF)
	var hi := ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & MASK32


## Avalanche of a 32-bit value (the murmur3 finalizer).
static func mix32(h: int) -> int:
	h &= MASK32
	h ^= h >> 16
	h = mul32(h, 0x85EBCA6B)
	h ^= h >> 13
	h = mul32(h, 0xC2B2AE35)
	h ^= h >> 16
	return h


## 32-bit hash of (seed, x, y). Negative and large coordinates are fine (two's complement low bits).
static func hash2(seed: int, x: int, y: int) -> int:
	var h := mix32((seed & MASK32) ^ 0x9E3779B9)
	h = mix32(h ^ mul32(x & MASK32, 0x27D4EB2F))
	h = mix32(h ^ mul32(y & MASK32, 0x165667B1))
	return h


## 32-bit hash of (seed, x, y, z), e.g. z = an object type or a field number.
static func hash3(seed: int, x: int, y: int, z: int) -> int:
	return mix32(hash2(seed, x, y) ^ mul32(z & MASK32, 0xD3A2646C))


## A hash as a float in [0, 1).
static func unit(h: int) -> float:
	return float(h & MASK32) / 4294967296.0


## Gradient noise in [0, 1], continuous, one feature per unit of x and y.
static func noise(seed: int, x: float, y: float) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	var u := fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
	var v := fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)
	var n00 := _dot_grad(seed, ix, iy, fx, fy)
	var n10 := _dot_grad(seed, ix + 1, iy, fx - 1.0, fy)
	var n01 := _dot_grad(seed, ix, iy + 1, fx, fy - 1.0)
	var n11 := _dot_grad(seed, ix + 1, iy + 1, fx - 1.0, fy - 1.0)
	var a := n00 + (n10 - n00) * u
	var b := n01 + (n11 - n01) * u
	# 2D gradient noise with unit gradients stays within +-1/sqrt(2)
	return clampf((a + (b - a) * v) * _DIAG + 0.5, 0.0, 1.0)


## Fractal noise in [0, 1]: octaves of doubling frequency and halving amplitude. Each octave has its
## own seed and offset so their lattices never line up. x, y are in units of the first octave.
static func fbm(seed: int, x: float, y: float, octaves: int) -> float:
	var sum := 0.0
	var amp := 1.0
	var total := 0.0
	var freq := 1.0
	for o in octaves:
		var s := hash2(seed, o, 0x0C7A7E)
		var ox := unit(hash2(s, 1, 0)) * 256.0
		var oy := unit(hash2(s, 2, 0)) * 256.0
		sum += noise(s, x * freq + ox, y * freq + oy) * amp
		total += amp
		amp *= 0.5
		freq *= 2.0
	return sum / total


static func _dot_grad(seed: int, ix: int, iy: int, dx: float, dy: float) -> float:
	var g := hash2(seed, ix, iy) & 7
	return _GRAD_X[g] * dx + _GRAD_Y[g] * dy
