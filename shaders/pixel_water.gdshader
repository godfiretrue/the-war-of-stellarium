// Adapted from "Pixel Water" by Francisco Cidade (https://fcidade.com), CC0.
// The original draws its own coastline from noise; this version reads the real
// continent from the generator field and paints only the sea, so the foam
// follows the generated coast exactly and the land stays fully visible.
shader_type canvas_item;

uniform sampler2D field : filter_linear, repeat_disable;
uniform vec2 world_size = vec2(1152.0, 648.0);
uniform float sea_level = 0.40;
uniform float depth_range = 200.0;
/// Screen pixels per world pixel (view scale x camera zoom). Keeps one big
/// pixel the same on screen at every zoom level.
uniform float view_zoom = 1.0;

// Size of one big pixel, in screen pixels.
uniform int pixel_size : hint_range(1, 16, 1) = 4;
// Seed: any number gives a different pattern.
uniform float seed : hint_range(0.0, 100.0, 0.0) = 3.0;
// Animation speed, in loops per second. The animation repeats exactly after 1 / speed seconds.
uniform float speed : hint_range(0.0, 1.0, 0.005) = 0.125;
// Size of the waves (higher = more, smaller waves).
uniform float scale : hint_range(0.5, 8.0, 0.1) = 2.0;
// Direction the water flows, in radians (0 = right, 1.57 = down).
uniform float flow_angle : hint_range(-3.14, 3.14, 0.01) = 0.5;
// How much the waves bend the pattern (0 = straight ripples).
uniform float turbulence : hint_range(0.0, 2.0, 0.01) = 0.8;
// Brightness balance: negative = darker, deeper water; positive = lighter, shallower water.
uniform float depth : hint_range(-0.5, 0.5, 0.01) = 0.0;
// Amount of white crests on top of the waves (0 = none).
uniform float crest_amount : hint_range(0.0, 1.0, 0.01) = 0.5;
// Width of the foam band along the coast (0 = no foam).
uniform float foam_width : hint_range(0.0, 1.0, 0.01) = 0.5;
// Width of the lighter shallow water along the coast.
uniform float shallow_width : hint_range(0.0, 1.0, 0.01) = 0.5;
// Height of the long swells that roll across the open water (0 = none).
uniform float swell : hint_range(0.0, 1.0, 0.01) = 0.5;
// Cloud shadows drifting over everything (0 = none).
uniform float cloud_shadow : hint_range(0.0, 1.0, 0.01) = 0.5;
// Amount of tiny glints that flash on the water (0 = none).
uniform float sparkle_amount : hint_range(0.0, 1.0, 0.01) = 0.5;

// Water colors, from darkest to lightest. The deep color matches MapView.DEEP_SEA.
uniform vec4 color_deep : source_color = vec4(0.055, 0.145, 0.260, 1.0);
uniform vec4 color_mid : source_color = vec4(0.071, 0.353, 0.478, 1.0);
uniform vec4 color_light : source_color = vec4(0.180, 0.561, 0.659, 1.0);
uniform vec4 color_crest : source_color = vec4(0.804, 0.918, 0.949, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.310, 0.710, 0.769, 1.0);
uniform vec4 color_foam : source_color = vec4(0.910, 0.969, 0.980, 1.0);

// 4x4 Bayer matrix as a 0..1 threshold for a pixel cell.
float bayer4(vec2 c) {
	int x = int(mod(c.x, 4.0));
	int y = int(mod(c.y, 4.0));
	int idx = y * 4 + x;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[idx]) + 0.5) / 16.0;
}

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030) + seed * 0.013);
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Noise that drifts along `dir` and repeats exactly: two copies of the pattern,
// one a full cycle behind the other, fade into each other as the phase goes 0..1.
float flow_noise(vec2 p, vec2 dir, float phase) {
	float f = fract(phase);
	float a = noise(p - dir * f);
	float b = noise(p - dir * (f - 1.0));
	return mix(a, b, f);
}

void fragment() {
	vec4 f = texture(field, UV);
	// Transparent over land: the terrain shader below owns every land pixel.
	// Godot's fragment stage has no early return, so the water body is an else.
	if (f.r >= sea_level) {
		COLOR = vec4(0.0);
	} else {
	// World-space pixel grid. Quantising in world coordinates keeps the pattern
	// anchored while the camera moves; px keeps each block one screen pixel.
	vec2 world_px = UV * world_size;
	float px = float(pixel_size) / max(view_zoom, 0.05);
	vec2 cell = floor(world_px / px);
	vec2 pos = (cell + 0.5) * px / 128.0 * scale;
	float phase = TIME * speed;
	vec2 dir = vec2(cos(flow_angle), sin(flow_angle));

	// First layer bends the second one, so the waves look pushed around.
	float warp = flow_noise(pos * 0.5 + 5.0, dir, phase) - 0.5;
	vec2 bent = pos + vec2(warp, -warp) * turbulence * 1.5;
	// Big soft shapes pick the shade of the water.
	float h = flow_noise(bent * 0.8, dir, phase) * 0.75
		+ flow_noise(bent * 1.7 + 9.0, dir * 2.0, phase) * 0.25;
	// Long swells: wide bands of lighter and darker water rolling along the flow.
	h += swell * 0.09 * sin(dot(pos, dir) * 4.0 - phase * 6.2831853 + warp * 4.0);
	h += depth;

	// Smooth blends instead of hard threshold bands: the big open-water areas
	// at the screen edges no longer turn into flat near-black wedges.
	vec3 col = mix(color_deep.rgb, color_mid.rgb, smoothstep(0.34, 0.54, h));
	col = mix(col, color_light.rgb, smoothstep(0.54, 0.70, h));

	// f.a is the sea-cell distance to the nearest land, normalised over
	// depth_range pixels. Rescale it to the original shader's 0..0.12 coast band
	// so its foam/shallow thresholds keep their meaning at any depth_range.
	float d = f.a * (depth_range / 200.0) * 0.12;
	float bayer = bayer4(cell);
	float dd = d * 8.0 / max(shallow_width, 0.05) + (bayer - 0.5) * 0.12;
	vec3 shore_col = dd < 0.12 ? color_shallow.rgb
		: (dd < 0.30 ? color_light.rgb : (dd < 0.55 ? color_mid.rgb : color_deep.rgb));
	col = dd < 0.30 ? shore_col : col;

	// Lapping waves: foam lines travelling from open water towards the coast.
	float wave_pos = fract(d * 24.0 / max(foam_width, 0.05) * 0.5 - phase * 2.0 + f.a * 0.6);
	float thin = clamp(d / 0.05, 0.35, 1.0);
	float lap = step(wave_pos, 0.17 * thin) * step(d, 0.04) * step(0.006, d);
	col = lap > 0.5 ? color_foam.rgb : col;
	// Solid foam right at the shore, breathing with the phase.
	float breathe = 0.5 + 0.5 * sin(phase * 6.2831853 + f.a * 6.0);
	float foam_w = (0.0020 + 0.0030 * breathe) * foam_width * 2.0;
	col = d < foam_w ? color_foam.rgb : col;

	// Crest lines in the open water only.
	float line = step(abs(flow_noise(bent * 1.6 + 21.0, dir * 3.0, phase) - 0.5),
			0.035 * crest_amount * 2.0) * step(0.45, h);
	col = dd > 0.55 ? mix(col, color_crest.rgb, line) : col;

	// Cloud shadows: a big slow noise; where it is high, water drops a shade.
	float cs = flow_noise(pos * 0.28 + 60.0, dir * 0.5, phase);
	float shade = step(mix(0.85, 0.45, cloud_shadow), cs);
	col = mix(col, col * vec3(0.88, 0.91, 0.96), shade);

	// Sparkles: single pixels that flash for a moment and are gone.
	if (sparkle_amount > 0.0) {
		float t = fract(phase * 3.0 + hash(cell));
		float on = step(hash(cell + 17.0), 0.004 * sparkle_amount * 2.0) * step(t, 0.12);
		col = mix(col, color_foam.rgb, on);
	}
	COLOR = vec4(col, 1.0);
	}
}
