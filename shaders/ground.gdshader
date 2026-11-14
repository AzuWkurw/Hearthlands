// Ground shader: draws the baked map chunks and makes open water shimmer.
// A shader is a small program that runs on the graphics card once for every pixel drawn, so effects
// like this cost almost nothing on the main processor.
// The chunk baker stores open water with alpha 0.5 and land with alpha 1.0; this shader reads that
// alpha as "how much water is here", animates those pixels, and always outputs a solid pixel.
shader_type canvas_item;

// Turned off by the "Animations" option, which leaves the water still.
uniform bool animate = true;
// How cloudy it is where you look (0 clear sky .. 1 overcast): shadows of clouds drift over the land.
uniform float clouds = 0.3;
// Which way and how fast the clouds drift, in tiles a second.
uniform vec2 drift = vec2(0.35, 0.12);
// Hills: the light and shade of the slopes, one pixel a tile (0.5 flat, lighter where the ground faces
// the light from the upper left, darker where it faces away), smoothed between tiles. Done here instead
// of baked into the chunks, so baking is quicker at every zoom.
uniform sampler2D relief_map : filter_linear, repeat_disable;
uniform bool use_relief = false;
uniform vec2 map_size = vec2(1.0, 1.0);
// With raised ground the chunks are drawn lifted; lift_map holds each tile corner's lift (in tiles / 4)
// so the flat map position under a pixel can be found again.
uniform sampler2D lift_map : filter_linear, repeat_disable;
uniform bool raised = false;

// Position of the pixel on the map, in tiles, handed from the vertex step to the pixel step.
varying vec2 world;

void vertex() {
	// VERTEX is the corner position in the drawing's own units, which the map view sets to tiles.
	world = VERTEX;
}

// A repeatable pseudo-random number between 0 and 1 for each whole grid cell.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise: blends the random values of the four surrounding grid cells.
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	// COLOR arrives already holding the texture's colour times the colour the drawing asked for
	// (white for chunks, dark for the background rectangle).
	vec4 c = COLOR;
	// 1.0 for open water (alpha 0.5), fading to 0.0 on land (alpha 1.0) and along soft shorelines.
	float water = clamp((1.0 - c.a) * 2.0, 0.0, 1.0);
	// the shore: where land and water meet, foam washes in and out
	float shore = clamp(1.0 - abs(water * 2.0 - 1.0) * 1.6, 0.0, 1.0);
	if (animate && shore > 0.0) {
		float wash = 0.5 + 0.5 * sin(TIME * 1.4 + world.x * 1.3 + world.y * 1.1);
		float lace = noise(world * 7.0 + vec2(TIME * 0.4, 0.0));
		c.rgb = mix(c.rgb, vec3(0.93, 0.96, 0.97), shore * wash * smoothstep(0.35, 0.75, lace) * 0.55);
	}
	if (animate && water > 0.0) {
		float t = TIME;
		// Wobble where the colour is read from, so the water surface seems to ripple.
		vec2 wobble = vec2(sin(world.y * 3.0 + t * 1.3), cos(world.x * 2.6 + t * 1.1)) * 0.0022 * water;
		vec4 c2 = texture(TEXTURE, UV + wobble);
		c.rgb = mix(c.rgb, c2.rgb, water);
		// Two noise patterns drifting in different directions; where both are high, light glints.
		float n = noise(world * 4.5 + vec2(t * 0.35, t * 0.22)) * noise(world * 6.3 - vec2(t * 0.28, -t * 0.31));
		c.rgb += vec3(0.22, 0.26, 0.28) * smoothstep(0.5, 0.8, n) * water;
		// A slow swell that brightens and darkens wide patches of water.
		c.rgb *= 1.0 + 0.05 * sin(t * 0.9 + world.x * 0.7 + world.y * 0.5) * water;
	}
	// hills, on land only
	if (use_relief) {
		vec2 p = world;
		if (raised) {
			for (int k = 0; k < 3; k++) {
				p.y = world.y + texture(lift_map, (p + 0.5) / (map_size + 1.0)).r * 4.0;
			}
		}
		float rv = texture(relief_map, p / map_size).r * 2.0 - 1.0;
		float land = 1.0 - water;
		if (rv > 0.0) {
			c.rgb = mix(c.rgb, vec3(1.0, 1.0, 0.92), rv * 0.49 * land);
		} else {
			c.rgb = mix(c.rgb, vec3(0.0), -rv * 0.647 * land);
		}
	}
	// cloud shadows: big soft patches drifting with the wind (more of them on a cloudy day)
	if (clouds > 0.01) {
		vec2 p = world * 0.055 - drift * TIME * 0.055;
		float n = noise(p) * 0.65 + noise(p * 2.3 + 7.1) * 0.35;
		float cover = smoothstep(0.78 - clouds * 0.45, 0.95 - clouds * 0.35, n);
		c.rgb *= 1.0 - (0.07 + 0.15 * clouds) * cover;
	}
	COLOR = vec4(c.rgb, 1.0);
}
