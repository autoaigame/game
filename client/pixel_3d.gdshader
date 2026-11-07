// Draws the SubViewport render of a 3D character (client/character_3d.gd). The render holds codes
// (client/pixel_3d_lit.gdshader): red = palette index, green = surface id, blue = depth. This pass turns
// them back into the kit palette colour, cuts the alpha at one half, and draws:
// - the 1 px outline around the model, in one dark colour;
// - inner lines, 1 px of a darker tone on the far side where two surfaces meet.
// The silhouette (parts hidden by a tree) is pixel_3d_ghost.gdshader: a shader that reads the screen makes
// Godot copy the screen before drawing it, so the model's own sprite must not use one.
shader_type canvas_item;

#include "res://client/pixel_3d.gdshaderinc"

void fragment() {
	COLOR = model_colour(TEXTURE, UV, TEXTURE_PIXEL_SIZE);
}
