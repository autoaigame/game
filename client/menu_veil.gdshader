// The world behind the start menu: darker and greyer, so the panel reads well over it.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float saturation = 0.35;
uniform float brightness = 0.5;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(g), c, saturation) * brightness, 1.0);
}
