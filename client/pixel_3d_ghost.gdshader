// The silhouette of a 3D character where something else covers it (a tree in front).
// A second copy of the model's render, drawn after everything (top_level): it keeps only the model's
// pixels where the screen shows something else, as a flat see-through colour. A ground shadow drawn over
// the model still counts as the model.
shader_type canvas_item;

uniform vec4 silhouette_color : source_color = vec4(0.8275, 0.8000, 0.7176, 0.45);
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

#include "res://client/pixel_3d.gdshaderinc"

void fragment() {
	vec4 col = model_colour(TEXTURE, UV, TEXTURE_PIXEL_SIZE);
	if (col.a == 0.0) {
		discard;
	}
	vec3 seen = texture(screen_tex, SCREEN_UV).rgb;
	vec3 shaded = mix(col.rgb, vec3(20.0, 22.0, 16.0) / 255.0, 97.0 / 255.0);
	if (distance(seen, col.rgb) < 0.03 || distance(seen, shaded) < 0.03) {
		discard;
	}
	COLOR = silhouette_color;
}
