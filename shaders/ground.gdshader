// Ground shader: draws the baked map chunks and makes open water shimmer.
// A shader is a small program that runs on the graphics card once for every pixel drawn, so effects
// like this cost almost nothing on the main processor.
// The chunk baker stores open water with alpha 0.5 and land with alpha 1.0; this shader reads that
// alpha as "how much water is here", animates those pixels, and always outputs a solid pixel.
shader_type canvas_item;

// Turned off by the "Animations" option, which leaves the water still.
uniform bool animate = true;

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
	COLOR = vec4(c.rgb, 1.0);
}
