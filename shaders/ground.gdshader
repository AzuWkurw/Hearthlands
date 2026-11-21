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
// Seasons and climates (the "Seasons, biomes and weather" feature): season_mask holds where each of the
// four climates lies, one per channel, one pixel a tile; ice_mask the frozen taiga water. Each climate
// gets its tint, the autumn and early-summer colours and its snow. Laid on here, not drawn over the map,
// so it lines up with raised ground and blends the same with every renderer.
uniform bool use_season = false;
uniform sampler2D season_mask : filter_linear, repeat_disable;
uniform sampler2D ice_mask : filter_linear, repeat_disable;
uniform vec4 tint0 = vec4(0.0);
uniform vec4 tint1 = vec4(0.0);
uniform vec4 tint2 = vec4(0.0);
uniform vec4 tint3 = vec4(0.0);
uniform vec4 autumn_col = vec4(0.0);
uniform vec4 green_col = vec4(0.0);
uniform vec4 snow_amt = vec4(0.0);
uniform vec4 ice_col = vec4(0.0);

// The coast: how far each tile is from the shoreline, one pixel a tile, smoothed between tiles
// (128 + 20 a tile: more out to sea, less inland; see MapView._make_coast_map). Gives the light
// shallow water along the shore, the swell rolling in towards the beach and the dark wet sand.
uniform sampler2D coast_map : filter_linear, repeat_disable;
uniform bool use_coast = false;

// Tiles along each side of a chunk (MapChunks.CH).
uniform float chunk_tiles = 16.0;

// Position of the pixel on the map, in tiles, handed from the vertex step to the pixel step.
varying vec2 world;
// The same on the flat map, worked out from what the drawing hands over (see vertex()), or -1 when
// the drawing did not say (the dark background beyond the map edge).
varying vec2 flat_pos;

void vertex() {
	// VERTEX is the corner position in the drawing's own units, which the map view sets to tiles.
	world = VERTEX;
	// The renderers do not agree on VERTEX: with Vulkan it can start again at each chunk, which cut
	// the cloud shadows (and hills and season tints) into squares. So the map view tells the shader
	// where each picture lies, in the colour it draws it with (blue 0.75: a chunk, its number in red
	// and green; blue 0.5: a part of the minimap picture), and the place comes from the picture's own
	// UV, which every renderer hands over the same way.
	flat_pos = vec2(-1.0);
	if (COLOR.a > 0.99 && abs(COLOR.b - 0.75) < 0.02) {
		flat_pos = floor(COLOR.rg * 64.0 + 0.5) * chunk_tiles + UV * chunk_tiles;
		COLOR = vec4(1.0);
	} else if (COLOR.a > 0.99 && abs(COLOR.b - 0.5) < 0.02 && COLOR.r > 0.99) {
		flat_pos = UV * map_size;
		COLOR = vec4(1.0);
	}
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
	// where on the flat map this pixel lies (raised ground is drawn lifted)
	vec2 p = world;
	bool on_map = flat_pos.x >= 0.0;
	if (on_map) {
		p = flat_pos;
	} else if (raised && (use_relief || use_season)) {
		for (int k = 0; k < 3; k++) {
			p.y = world.y + texture(lift_map, (p + 0.5) / (map_size + 1.0)).r * 4.0;
		}
	}
	// the coast: shallow water lighter and greener, the swell running in, wet sand at the water's edge
	if (use_coast && on_map) {
		// tiles from the shoreline: above 0 out at sea, below 0 inland
		float sd = (texture(coast_map, p / map_size).r * 255.0 - 128.0) / 20.0;
		if (water > 0.0) {
			float shallow = 1.0 - smoothstep(0.25, 2.6, sd);
			vec3 lagoon = c.rgb * vec3(0.8, 1.1, 1.04) + vec3(0.05, 0.12, 0.1);
			c.rgb = mix(c.rgb, lagoon, shallow * 0.6 * water);
			if (animate) {
				// long low waves running in towards the shore, broken up along it so they come in sets
				float wobble = noise(p * 0.7) * 2.4;
				float crest = sin(sd * 4.2 + TIME * 1.1 + wobble);
				float sets = smoothstep(0.35, 0.75, noise(p * 0.9 + vec2(TIME * 0.06, -TIME * 0.04)));
				float reach = smoothstep(0.3, 0.75, sd) * (1.0 - smoothstep(1.4, 2.4, sd));
				c.rgb += vec3(0.16, 0.2, 0.2) * smoothstep(0.82, 0.99, crest) * sets * reach * water;
			}
		} else if (sd > -0.75) {
			// sand and earth the waves have just wetted: darker towards the water, the line moving with the wash
			float wash = animate ? 0.5 + 0.5 * sin(TIME * 1.4 + p.x * 1.3 + p.y * 1.1) : 0.5;
			float wet = smoothstep(-0.75, -0.2 + 0.15 * wash, sd);
			c.rgb *= 1.0 - 0.16 * wet;
		}
	}
	// hills, on land only (and nothing of it beyond the map edge): the slopes facing the sun warm,
	// the slopes facing away in a cool blue shade rather than plain dark, as in late afternoon light
	if (use_relief && on_map) {
		float rv = texture(relief_map, p / map_size).r * 2.0 - 1.0;
		float land = 1.0 - water;
		if (rv > 0.0) {
			c.rgb = mix(c.rgb, vec3(1.0, 0.97, 0.84), rv * 0.49 * land);
		} else {
			c.rgb = mix(c.rgb, vec3(0.03, 0.05, 0.12), -rv * 0.647 * land);
		}
	}
	// climates and seasons, on land (the ice on the taiga's water)
	if (use_season && on_map) {
		vec4 m = texture(season_mask, p / map_size);
		float land = 1.0 - water;
		vec4 tints[4] = vec4[4](tint0, tint1, tint2, tint3);
		for (int k = 0; k < 4; k++) {
			float mk = m[k] * land;
			if (mk > 0.0) {
				c.rgb = mix(c.rgb, tints[k].rgb, tints[k].a * mk);
				c.rgb = mix(c.rgb, autumn_col.rgb, autumn_col.a * mk);
				c.rgb = mix(c.rgb, green_col.rgb, green_col.a * mk);
				c.rgb = mix(c.rgb, vec3(0.95, 0.97, 1.0), snow_amt[k] * mk);
			}
		}
		if (ice_col.a > 0.0) {
			c.rgb = mix(c.rgb, ice_col.rgb, ice_col.a * texture(ice_mask, p / map_size).r);
		}
	}
	// cloud shadows: big soft patches drifting with the wind (more of them on a cloudy day)
	if (clouds > 0.01 && on_map) {
		vec2 cp = p * 0.055 - drift * TIME * 0.055;
		float n = noise(cp) * 0.65 + noise(cp * 2.3 + 7.1) * 0.35;
		float cover = smoothstep(0.78 - clouds * 0.45, 0.95 - clouds * 0.35, n);
		// a little bluer than plain dark: the shade is lit by the open sky
		c.rgb *= vec3(1.0) - (0.07 + 0.15 * clouds) * cover * vec3(1.0, 0.94, 0.8);
	}
	COLOR = vec4(c.rgb, 1.0);
}
