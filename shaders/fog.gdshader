shader_type canvas_item;
// Fog veil over one province polygon. Unknown land is fully opaque so terrain
// relief (including peaks) cannot leak through; remembered land is a denser,
// ordered-dither veil that keeps the shape of the terrain readable without
// revealing live troop information. The pattern is world-anchored and quantized
// to the map's 4 px pixels, so it reads as pixel-art mist rather than static.

// 0 = visible (no fog), 1 = explored but unseen, 2 = unexplored.
uniform int fog_mode : hint_range(0, 2, 1) = 2;
uniform vec4 fog_base : source_color = vec4(0.035, 0.040, 0.075, 1.0);
uniform vec2 world_origin = vec2(0.0);
uniform float pixel_size = 4.0;

varying vec2 v_world_cell;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Smooth two-dimensional value noise. Two octaves below give soft cloud banks
// instead of the isolated white specks a per-cell hash produced.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Interleaved gradient noise: fine, evenly spread dither without the harsh
// checkerboard of a random per-pixel threshold.
float ordered_dither(vec2 cell) {
	return fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	// VERTEX is the province-local polygon position. Offsetting by the
	// province's world position anchors the mist to the map, so zoom and pan
	// never make it slide across the terrain.
	v_world_cell = (VERTEX + world_origin) / max(pixel_size, 1.0);
}

void fragment() {
	if (fog_mode == 0) {
		COLOR = vec4(0.0);
	} else {
		vec2 cell = floor(v_world_cell);
		float haze = value_noise(cell / 7.0) * 0.65 + value_noise(cell / 2.6) * 0.35;
		float grain = ordered_dither(cell);
		if (fog_mode == 2) {
			vec3 deep = fog_base.rgb * 0.16;
			vec3 mist = fog_base.rgb * 1.45;
			vec3 col = mix(deep, mist, smoothstep(0.18, 0.82, haze));
			col += fog_base.rgb * 0.35 * smoothstep(0.88, 0.99, grain) * (0.35 + haze);
			COLOR = vec4(col, 1.0);
		} else {
			float veil = clamp(0.60 + (haze - 0.5) * 0.34 + (grain - 0.5) * 0.10, 0.42, 0.84);
			vec3 col = mix(fog_base.rgb * 0.45, fog_base.rgb * 1.10, haze);
			COLOR = vec4(col, veil);
		}
	}
}
