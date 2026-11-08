// Flat lighting for a 3D character (client/character_3d.gd), in the palette right in the 3D render, so it
// only runs when the model's viewport re-renders. The light is cut into toon_levels flat bands.
// - A surface with a ramp (ramp_len > 0: a part in the colour the player chose) takes ramp[band + shade]:
//   every colour comes from the ramp, so the output is in the palette by construction and the surface
//   never changes hue. On the head, a face texture and a beard texture (index textures: red = zone * 64,
//   green = (shade + 2) * 50) pick the zone and shade of each texel: zone 0 the surface's own ramp (the
//   skin), 1 the face's or the beard's colour, 2 the eyes.
// - A surface without a ramp (fixed colours) takes the nearest palette colour to its lit colour, among
//   those of its own hue (hue_lock).
// The output is not a colour but a code read by client/pixel_3d.gdshader: red = palette index (as
// Character3D.red_code), green = surface (material) id, blue = depth. The 2D pass turns it back into the
// palette colour and draws the outline and the inner lines from it.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo = vec4(1.0);  // sRGB, as in the glTF material; converted below, whatever the renderer
uniform vec3 light_dir = vec3(-0.64, 0.77, 0.0);  // towards the light, world space
uniform float ambient = 0.85;
uniform float sun = 0.45;
uniform int toon_levels = 3;  // 0: smooth light; n >= 2: the light in n flat bands
uniform float hue_lock = 30.0;  // palette colours of another hue than the surface's cost this much more
uniform int material_id = 0;  // 0..15, for the inner lines
uniform int red_base = 56;  // red code of palette index 0 (Character3D.RED_BASE)
uniform int red_step = 3;  // red codes between two indices (Character3D.RED_STEP)
uniform float depth_near = 6.0;  // view distance (m) coded as blue 0 ...
uniform float depth_far = 10.0;  // ... and as blue 1

uniform vec3 palette[64];  // data/palette.json (Character3D.palette_uniform)
uniform int palette_size = 40;

// Ramps as palette indices, dark to light; zone 0 is the surface's own.
uniform int ramp[8];
uniform int ramp_len = 0;
uniform int face_ramp[8];  // zone 1 of the face texture: the face's colour (brows)
uniform int face_ramp_len = 0;
uniform int beard_ramp[8];  // zone 1 of the beard texture: the beard's colour
uniform int beard_ramp_len = 0;
uniform int eye_ramp[8];  // zone 2: the eyes
uniform int eye_ramp_len = 0;
uniform bool use_face = false;
uniform sampler2D face_tex : filter_nearest;
uniform bool use_beard = false;
uniform sampler2D beard_tex : filter_nearest;
uniform vec4 face_rect = vec4(12.0, 6.0, 24.0, 16.0);  // texels of the head texture
uniform vec2 head_tex = vec2(48.0, 22.0);

vec3 to_srgb(vec3 c) {
	return mix(12.92 * c, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

int ramp_at(int zone, int band, int shade) {
	int len = zone == 1 ? face_ramp_len : (zone == 3 ? beard_ramp_len : (zone == 2 ? eye_ramp_len : ramp_len));
	int i = clamp(band + shade, 0, max(len - 1, 0));
	if (zone == 1) return face_ramp[i];
	if (zone == 3) return beard_ramp[i];
	if (zone == 2) return eye_ramp[i];
	return ramp[i];
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 l = normalize(light_dir);
	float lambert = max(dot(n, l), 0.0);
	int levels = max(toon_levels, 2);
	int band = int(min(floor(lambert * float(levels)), float(levels - 1)));
	if (toon_levels >= 2) {
		lambert = float(band) / float(levels - 1);
	}
	int pick = 0;
	if (ramp_len > 0) {
		int zone = 0;
		int shade = 0;
		vec2 t = floor(UV * head_tex) - face_rect.xy;
		if ((use_face || use_beard) && t.x >= 0.0 && t.y >= 0.0 && t.x < face_rect.z && t.y < face_rect.w) {
			vec2 fuv = (t + 0.5) / face_rect.zw;
			if (use_face) {
				vec4 f = texture(face_tex, fuv);
				if (f.a > 0.5) {
					zone = int(round(f.r * 255.0 / 64.0));
					shade = int(round(f.g * 255.0 / 50.0)) - 2;
				}
			}
			if (use_beard) {
				vec4 b = texture(beard_tex, fuv);
				if (b.a > 0.5) {
					zone = int(round(b.r * 255.0 / 64.0));
					zone = zone == 1 ? 3 : zone;  // the beard's own colour
					shade = int(round(b.g * 255.0 / 50.0)) - 2;
				}
			}
		}
		// Three bands of a ramp: shade, plain, full light.
		pick = ramp_at(zone, band * 2 / max(levels - 1, 1), shade);
	} else {
		vec3 base = albedo.rgb;
		vec3 rgb = to_srgb(to_linear(base) * (ambient + sun * lambert));
		// The surface's hue (chromaticity of its unlit colour): lit or shaded, it stays on its hue.
		vec3 hue = base / max(base.r + base.g + base.b, 1e-4);
		float best = 1e9;
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
	}
	float depth = clamp((-VERTEX.z - depth_near) / (depth_far - depth_near), 0.0, 1.0);
	// Codes centred in their steps, so a rounding of a unit on the way does not change them.
	ALBEDO = vec3(float(red_base + pick * red_step + red_step / 2) / 255.0, (float(material_id) * 16.0 + 8.0) / 255.0, depth);
}
