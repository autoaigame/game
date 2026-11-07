// Flat lighting for a 3D character (client/character_3d.gd), snapped to the palette right in the 3D
// render, so the snapping only runs when the model's viewport re-renders. Lambert light plus ambient, cut
// into toon_levels flat bands; each surface stays on palette colours of its own hue.
// The output is not a colour but a code read by client/pixel_3d.gdshader: red = palette index,
// green = surface (material) id, blue = depth. The 2D pass turns it back into the palette colour and
// draws the outline and the inner lines from it.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo = vec4(1.0);  // sRGB, as in the glTF material; converted below, whatever the renderer
uniform vec3 light_dir = vec3(-0.64, 0.77, 0.0);  // towards the light, world space
uniform float ambient = 0.85;
uniform float sun = 0.45;
uniform int toon_levels = 3;  // 0: smooth light; n >= 2: the light in n flat bands
uniform float hue_lock = 30.0;  // palette colours of another hue than the surface's cost this much more
uniform int material_id = 0;  // 0..15, for the inner lines
uniform float depth_near = 6.0;  // view distance (m) coded as blue 0 ...
uniform float depth_far = 10.0;  // ... and as blue 1

uniform vec3 palette[64];  // data/palette.json (Character3D.palette_uniform)
uniform int palette_size = 40;

vec3 to_srgb(vec3 c) {
	return mix(12.92 * c, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 l = normalize(light_dir);
	float lambert = max(dot(n, l), 0.0);
	if (toon_levels >= 2) {
		float k = min(floor(lambert * float(toon_levels)), float(toon_levels - 1));
		lambert = k / float(toon_levels - 1);
	}
	vec3 base = albedo.rgb;
	float light = ambient + sun * lambert;
	vec3 rgb = to_srgb(to_linear(base) * light);
	// The surface's hue (chromaticity of its unlit colour): lit or shaded, skin stays skin instead of
	// turning sand or grey.
	vec3 hue = base / max(base.r + base.g + base.b, 1e-4);
	float best = 1e9;
	int pick = 0;
	for (int i = 0; i < palette_size; i++) {
		vec3 d = palette[i] - rgb;
		// Weighted RGB distance ("redmean"), close enough to perceptual for a small palette.
		float r = (palette[i].r + rgb.r) * 0.5;
		float e = (2.0 + r) * d.r * d.r + 4.0 * d.g * d.g + (3.0 - r) * d.b * d.b;
		vec3 dh = palette[i] / max(palette[i].r + palette[i].g + palette[i].b, 1e-4) - hue;
		e += hue_lock * dot(dh, dh);
		if (e < best) {
			best = e;
			pick = i;
		}
	}
	float depth = clamp((-VERTEX.z - depth_near) / (depth_far - depth_near), 0.0, 1.0);
	// Codes centred in their steps, so a rounding of a unit or two on the way does not change them.
	ALBEDO = vec3((float(pick) * 4.0 + 2.0) / 255.0, (float(material_id) * 16.0 + 8.0) / 255.0, depth);
}
