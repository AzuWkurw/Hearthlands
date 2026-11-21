// Map shader: everything the map view draws itself (buildings, people, trees, fields...) passes
// through here. It only touches corners that are marked to sway: the tops of trees and of crops
// in the fields bend in the wind, each a little out of step with its neighbours.
// A corner is marked by the alpha of its colour, just short of fully solid (254 or 253 of 255).
// (They were 3 and 5 of 255 before build 48.2: a see-through layer fading in, like the night's veil at
// dusk, passed through those values and was turned solid, covering the whole map. Anything drawn
// almost solid that happens to match now is made solid, which looks the same.)
//   SWAY_TREE  - the top of a tree: bends a lot, slowly
//   SWAY_CROP  - the tip of a crop: bends a little, quickly, in waves running across the field
// The marked corners get their alpha set back to 1. Every other corner and every pixel is drawn
// exactly as without this shader.
// The fog of war is marked too, by the exact colour FOG_TAG: its picture holds one pixel a tile, and
// smoothed straight it showed the tiles' steps along the edge of what you can see. Here its edge is
// wavered by slow noise so it reads as a bank of mist, and the unexplored land under it drifts with
// faint lighter cloud instead of lying flat black.
shader_type canvas_item;

uniform bool animate = true;
// How hard the wind blows: 1 normal, about 2.5 in a storm, 0.3 on a still day.
uniform float wind = 1.0;

const float SWAY_TREE = 0.9960784;   // 254 / 255 (mesh colours are stored as 8 bits a channel)
const float SWAY_CROP = 0.9921569;   // 253 / 255
const vec3 FOG_TAG = vec3(0.2, 0.4, 0.6);   // MapView.FOG_TAG

// 1 for the fog of war, 0 for everything else
varying float fog;
// where the pixel lies on the map, in tiles
varying vec2 at;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	float a = COLOR.a;
	at = VERTEX;
	fog = 0.0;
	if (a > 0.99 && distance(COLOR.rgb, FOG_TAG) < 0.01) {
		fog = 1.0;
		COLOR = vec4(1.0);
	}
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

void fragment() {
	if (fog > 0.5) {
		float t = animate ? TIME : 0.0;
		vec2 tiles = vec2(textureSize(TEXTURE, 0));
		// read the fog a little off to the side, by an amount that wanders smoothly over the map:
		// the straight steps between tiles become a ragged, slowly breathing edge
		vec2 warp = (vec2(noise(at * 0.22 + vec2(t * 0.02, 0.0)), noise(at * 0.22 + vec2(5.2, 1.3) - vec2(0.0, t * 0.015))) - 0.5) * 4.0;
		warp += (vec2(noise(at * 0.8 + vec2(t * 0.05, 0.0)), noise(at * 0.8 + vec2(2.9, 7.7) - vec2(0.0, t * 0.04))) - 0.5) * 1.6;
		warp += (vec2(noise(at * 2.3 + 9.1), noise(at * 2.3 + 3.7)) - 0.5) * 0.5;
		vec4 f = texture(TEXTURE, UV + warp / tiles);
		// faint cloud drifting over the land nobody has seen yet
		float mist = noise(at * 0.3 + vec2(t * 0.03, t * 0.012)) * 0.6 + noise(at * 1.1 - vec2(t * 0.05, 0.0)) * 0.4;
		// (it thins out towards the map's edge, so the mist doesn't end in a straight line there)
		vec2 edge = min(UV, 1.0 - UV) * tiles;
		float deep = smoothstep(0.55, 1.0, f.a) * smoothstep(0.0, 8.0, min(edge.x, edge.y));
		vec3 col = mix(f.rgb, vec3(0.13, 0.15, 0.18), mist * deep * 0.8);
		// a pale rim where the mist thins out at the edge of what you can see
		col += vec3(0.05, 0.06, 0.07) * smoothstep(0.35, 0.6, f.a) * (1.0 - smoothstep(0.75, 0.95, f.a));
		COLOR = vec4(col, f.a);
	}
}
