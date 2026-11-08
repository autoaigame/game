// Shared by pixel_3d.gdshader and pixel_3d_ghost.gdshader: decoding the 3D render's codes, the outline
// and the inner lines. See pixel_3d.gdshader.
uniform vec4 outline_color : source_color = vec4(0.180, 0.157, 0.133, 1.0);
uniform int red_base = 56;  // red code of palette index 0 (Character3D.RED_BASE, Character3D.red_index)
uniform int red_step = 3;
uniform int dark_of[64];  // palette index -> a darker palette index of a close hue (Character3D.dark_of)

uniform vec3 palette[64];  // data/palette.json (Character3D.palette_uniform)

struct Px { bool on; int idx; int mat; float depth; };

Px read(sampler2D tex, vec2 uv) {
	vec4 c = texture(tex, uv);
	Px p;
	p.on = c.a >= 0.5 && uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0;
	vec3 v = c.rgb / max(c.a, 1e-4) * 255.0;  // the transparent background premultiplies the edges
	p.idx = clamp(int(floor((v.r - float(red_base)) / float(red_step))), 0, 63);
	p.mat = int(floor(v.g / 16.0));
	p.depth = c.b / max(c.a, 1e-4);
	return p;
}

// Whether p gets an inner line against its neighbour q: p is the far one where two surfaces meet (ties go
// to the higher surface id).
bool line_against(Px p, Px q) {
	if (!q.on || p.mat == q.mat) return false;
	float d = p.depth - q.depth;
	return d > 0.004 || (abs(d) <= 0.004 && p.mat > q.mat);
}

// The colour of this texel of the render: palette colour, outline or nothing (alpha 0).
vec4 model_colour(sampler2D tex, vec2 uv, vec2 px) {
	Px p = read(tex, uv);
	Px n[4];
	n[0] = read(tex, uv + vec2(px.x, 0.0));
	n[1] = read(tex, uv - vec2(px.x, 0.0));
	n[2] = read(tex, uv + vec2(0.0, px.y));
	n[3] = read(tex, uv - vec2(0.0, px.y));
	vec4 col = vec4(0.0);
	if (!p.on) {
		for (int i = 0; i < 4; i++) {
			if (n[i].on) col = outline_color;
		}
	} else {
		int idx = p.idx;
		for (int i = 0; i < 4; i++) {
			if (line_against(p, n[i])) idx = dark_of[p.idx];
		}
		col = vec4(palette[idx], 1.0);
	}
	return col;
}
