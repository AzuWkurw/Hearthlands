// Map shader: everything the map view draws itself (buildings, people, trees, fields...) passes
// through here. It only touches corners that are marked to sway: the tops of trees and of crops
// in the fields bend in the wind, each a little out of step with its neighbours.
// A corner is marked by the alpha of its colour, a value nothing else on the map is drawn with:
//   SWAY_TREE  - the top of a tree: bends a lot, slowly
//   SWAY_CROP  - the tip of a crop: bends a little, quickly, in waves running across the field
// The marked corners get their alpha set back to 1. Every other corner and every pixel is drawn
// exactly as without this shader (the pixel step is left to Godot).
shader_type canvas_item;

uniform bool animate = true;
// How hard the wind blows: 1 normal, about 2.5 in a storm, 0.3 on a still day.
uniform float wind = 1.0;

const float SWAY_TREE = 0.0117647;   // 3 / 255 (mesh colours are stored as 8 bits a channel)
const float SWAY_CROP = 0.0196078;   // 5 / 255

void vertex() {
	float a = COLOR.a;
	if (abs(a - SWAY_TREE) < 0.0018) {
		COLOR.a = 1.0;
		if (animate) {
			// VERTEX is in tiles here (the map view draws in tile units)
			float ph = VERTEX.x * 0.63 + VERTEX.y * 0.41;
			float gust = 0.6 + 0.4 * sin(TIME * 0.31 + VERTEX.x * 0.05);
			float s = sin(TIME * 1.15 + ph) * 0.045 + sin(TIME * 2.3 + ph * 1.7) * 0.015;
			VERTEX.x += s * wind * gust;
		}
	} else if (abs(a - SWAY_CROP) < 0.0018) {
		COLOR.a = 1.0;
		if (animate) {
			// a wave of wind running across the fields from the west
			float wave = sin(TIME * 2.2 - VERTEX.x * 1.6 + VERTEX.y * 0.4);
			VERTEX.x += (wave * 0.035 + sin(TIME * 5.3 + VERTEX.x * 9.0) * 0.008) * wind;
			VERTEX.y += abs(wave) * 0.012 * wind;
		}
	}
}
