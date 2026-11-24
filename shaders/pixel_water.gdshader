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
uniform float scale : hint_range(0.5, 8.0, 0.1) = 1.7;
// Direction the water flows, in radians (0 = right, 1.57 = down).
uniform float flow_angle : hint_range(-3.14, 3.14, 0.01) = 0.5;
// How much the waves bend the pattern (0 = straight ripples).
uniform float turbulence : hint_range(0.0, 2.0, 0.01) = 1.0;
// Brightness balance: negative = darker, deeper water; positive = lighter, shallower water.
uniform float depth : hint_range(-0.5, 0.5, 0.01) = 0.0;
// Amount of white crests on top of the waves (0 = none).
uniform float crest_amount : hint_range(0.0, 1.0, 0.01) = 0.35;
// Width of the foam band along the coast (0 = no foam).
uniform float foam_width : hint_range(0.0, 1.0, 0.01) = 0.55;
// Height of the long swells that roll across the open water (0 = none).
uniform float swell : hint_range(0.0, 1.0, 0.01) = 0.7;
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
	// The big colour shapes sample continuous world pixels. Sampling the
	// quantised cell position instead gave every water block one flat shade,
	// which reads as large pale/dark squares when the camera is zoomed out.
	vec2 smooth_pos = world_px / 128.0 * scale;
	float phase = TIME * speed;
	vec2 dir = vec2(cos(flow_angle), sin(flow_angle));

	// First layer bends the second one, so the waves look pushed around.
	float warp = flow_noise(smooth_pos * 0.5 + 5.0, dir, phase) - 0.5;
	vec2 bent = smooth_pos + vec2(warp, -warp) * turbulence * 1.5;
	// Big soft shapes pick the shade of the water.
	float h = flow_noise(bent * 0.8, dir, phase) * 0.75
		+ flow_noise(bent * 1.7 + 9.0, dir * 2.0, phase) * 0.25;
	// Long swells: wide bands of lighter and darker water rolling along the flow.
	h += swell * 0.09 * sin(dot(smooth_pos, dir) * 4.0 - phase * 6.2831853 + warp * 4.0);
	h += depth;

	// Smooth blends instead of hard threshold bands: the big open-water areas
	// at the screen edges no longer turn into flat near-black wedges.
	vec3 col = mix(color_deep.rgb, color_mid.rgb, smoothstep(0.30, 0.52, h));
	col = mix(col, color_light.rgb, smoothstep(0.58, 0.76, h));

	// f.a is the sea-cell distance to the nearest land, normalised over
	// depth_range pixels. The shelf is a narrow, soft tint that hugs the coast:
	// no bright cyan ring and no stack of quantised bands.
	float coast = clamp(f.a * (200.0 / max(depth_range, 1.0)), 0.0, 1.0);
	float coast_noise = flow_noise(smooth_pos * 1.35 + 37.0, dir, phase) - 0.5;
	float shore = 1.0 - smoothstep(0.0, 0.07, coast);
	float band = clamp(shore + coast_noise * 0.04, 0.0, 1.0);
	vec3 coast_col = mix(color_mid.rgb, color_light.rgb, smoothstep(0.15, 0.80, band));
	col = mix(col, coast_col, smoothstep(0.05, 0.45, band) * 0.55);

	// Foam is a thin, sparse waterline fleck. A higher frequency than the waves
	// keeps it from merging into a solid white border around every province.
	float foam_band = 1.0 - smoothstep(0.0, 0.012, coast);
	float foam_noise = flow_noise(smooth_pos * 5.0 + 51.0, dir, phase * 1.3);
	float foam = foam_band * smoothstep(0.72, 0.92, foam_noise) * foam_width;
	col = mix(col, color_foam.rgb, foam * 0.22);

	// Lapping waves: faint broken lines rolling in from open water.
	float wave_pos = fract(coast * 36.0 - phase * 1.4 + coast_noise * 0.8);
	float lap_band = 1.0 - smoothstep(0.0, 0.055, coast);
	float lap = smoothstep(0.18, 0.0, wave_pos) * lap_band;
	lap *= smoothstep(0.50, 0.80, flow_noise(smooth_pos * 3.0 + 7.0, dir, phase * 1.1));
	col = mix(col, color_foam.rgb, lap * 0.12);

	// Fine detail only appears once the camera is close enough for it to read.
	// At the fitted view one water cell is many screen pixels wide, so crests
	// and glints would become isolated white blocks instead of waves.
	float zoom_detail = smoothstep(0.9, 1.6, view_zoom);

	// Crest lines in open water only. A smooth ridge keeps them as thin waves
	// instead of hard-edged white blocks when a water cell covers many pixels.
	float ridge = 1.0 - smoothstep(0.0,
			0.020 + 0.045 * crest_amount,
			abs(flow_noise(bent * 1.6 + 21.0, dir * 3.0, phase) - 0.5));
	float line = ridge * step(0.50, h);
	col = coast > 0.40 ? mix(col, color_crest.rgb, line * 0.22 * crest_amount * zoom_detail) : col;

	// Cloud shadows: a big slow noise sampled in continuous world space, with
	// a soft band and low contrast so it never becomes blocky at any zoom.
	float cs = flow_noise(smooth_pos * 0.28 + 60.0, dir * 0.5, phase);
	float shadow_edge = mix(0.85, 0.45, cloud_shadow);
	float shade = smoothstep(shadow_edge - 0.09, shadow_edge + 0.09, cs);
	col = mix(col, col * vec3(0.94, 0.96, 0.98), shade * cloud_shadow);

	// Sparkles: single pixels that flash for a moment and are gone.
	if (sparkle_amount > 0.0) {
		float t = fract(phase * 3.0 + hash(cell));
		float on = step(hash(cell + 17.0), 0.004 * sparkle_amount * 2.0) * step(t, 0.12);
		col = mix(col, color_foam.rgb, on * 0.35 * zoom_detail);
	}
	COLOR = vec4(col, 1.0);
	}
}
