// Slow change of the ground's brightness and hue over the world, so wide areas of one ground do not
// look flat. Multiplies each texel by a value from a low-frequency noise of its world position (snapped
// to the texel), so the pixel art stays crisp. Settings: data/biomes.json "ground_tint" (ChunkView).
shader_type canvas_item;

uniform float amount = 0.06; // largest relative change of brightness
uniform float warmth = 0.5; // how much lighter areas also turn warmer (and darker ones cooler)
uniform float scale_px = 5120.0; // size of one feature, in world pixels
uniform vec2 offset = vec2(0.0); // from the world seed

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Integer hash of a lattice point, in [0, 1].
float lattice(ivec2 p) {
	uint h = (uint(p.x) * 668265263u) ^ (uint(p.y) * 374761393u);
	h ^= h >> 15u;
	h *= 739982445u;
	h ^= h >> 12u;
	return float(h & 65535u) / 65535.0;
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	ivec2 c = ivec2(i);
	float a = lattice(c);
	float b = lattice(c + ivec2(1, 0));
	float d = lattice(c + ivec2(0, 1));
	float e = lattice(c + ivec2(1, 1));
	return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

void fragment() {
	vec2 p = floor(world_pos) / scale_px + offset;
	float n = value_noise(p) * 0.65 + value_noise(p * 2.03 + vec2(17.0, 31.0)) * 0.35;
	float t = (n * 2.0 - 1.0) * amount;
	COLOR.rgb *= vec3(1.0 + t * (1.0 + 0.5 * warmth), 1.0 + t, 1.0 + t * (1.0 - warmth));
}
