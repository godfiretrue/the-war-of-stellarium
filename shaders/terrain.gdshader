shader_type canvas_item;
// Procedural terrain painter.
// field.r = elevation, field.g = moisture, field.b = temperature.
// Relief comes from hill-shading the elevation with an extra ridged detail
// layer; biome colours mix moisture (dry/wet) with temperature (cold/warm), so
// the north of the continent is taiga/tundra and the south turns dry and warm.

uniform sampler2D field : filter_linear, repeat_disable;
uniform vec2 grid_size = vec2(288.0, 162.0);
uniform vec2 world_size = vec2(1152.0, 648.0);
uniform float sea_level = 0.40;
uniform vec3 sun = vec3(-0.62, -0.72, 0.48);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 px = uv * world_size;
	vec2 t = 1.0 / grid_size;

	vec3 sample_field = texture(field, uv).rgb;
	float e = sample_field.r;
	float m = sample_field.g;
	float temp = sample_field.b;

	// Smoothed gradient over a 2-texel stencil, so the source grid does not
	// show up as creases in the lighting.
	float k = 2.0;
	float e_l = texture(field, uv - vec2(t.x * k, 0.0)).r;
	float e_r = texture(field, uv + vec2(t.x * k, 0.0)).r;
	float e_u = texture(field, uv - vec2(0.0, t.y * k)).r;
	float e_d = texture(field, uv + vec2(0.0, t.y * k)).r;
	vec2 grad = vec2(e_r - e_l, e_d - e_u) / (2.0 * k);

	float detail = fbm(px * 0.09);
	float broad = fbm(px * 0.018 + 3.7);
	float region = fbm(px * 0.032 + 7.1);
	// Two scales of broken rock: ridges get lumpy faces, not smooth slopes.
	float crag = (fbm(px * 0.55 + 11.0) - 0.5) * 0.12 + (fbm(px * 0.23 + 5.0) - 0.5) * 0.10;
	// Larger-scale patchiness: bare rock does not cover a slope evenly, and
	// gullies cut darker lines down the flanks.
	float rocky = fbm(px * 0.13 + 17.0) * 0.6 + fbm(px * 0.42 + 31.0) * 0.4;
	float gullies = smoothstep(0.42, 0.78, fbm(px * 0.16 + 41.0));

	float steep = clamp(length(grad) * 78.0, 0.0, 1.0);
	vec2 broken = vec2(crag, crag * 0.7) * (0.55 + steep);
	vec3 n = normalize(vec3(-(grad * 62.0 + broken), 1.0));
	float shade = dot(n, normalize(sun));

	vec3 col;
	if (e < sea_level) {
		float depth = clamp((sea_level - e) / 0.30, 0.0, 1.0);
		vec3 shallow = vec3(0.15, 0.40, 0.48);
		vec3 deep = vec3(0.03, 0.09, 0.18);
		col = mix(shallow, deep, pow(depth, 0.55));
		col += (fbm(px * 0.045) - 0.5) * 0.05;
		// Cold northern water reads greyer and harder.
		col = mix(col, vec3(0.22, 0.31, 0.38), smoothstep(0.34, 0.14, temp) * 0.40);
		// The water layer above owns the shoreline foam and shallow shelf, so
		// this fallback sea stays flat instead of drawing a second coast.
	} else {
		// Biome from moisture and temperature, broken up with noise so the
		// edges between biomes are not geometric.
		float mm = m + (broad - 0.5) * 0.26 + (detail - 0.5) * 0.08;
		float cold = smoothstep(0.46, 0.18, temp);
		float hot = smoothstep(0.58, 0.84, temp);
		float dry = smoothstep(0.42, 0.22, mm);

		vec3 grass = vec3(0.40, 0.50, 0.26);
		vec3 lush = vec3(0.29, 0.44, 0.21);
		vec3 savanna = vec3(0.60, 0.55, 0.32);
		vec3 sand = vec3(0.72, 0.65, 0.46);
		vec3 tundra = vec3(0.44, 0.46, 0.42);
		vec3 forest = vec3(0.12, 0.24, 0.13);
		vec3 taiga = vec3(0.08, 0.16, 0.12);

		vec3 low = mix(grass, lush, smoothstep(0.34, 0.62, mm));
		low = mix(low, savanna, hot * 0.55);
		low = mix(low, sand, dry * 0.70);
		low = mix(low, tundra, cold * 0.85);
		// Regional tint: keeps big plains from reading as one flat colour.
		low *= 0.92 + 0.16 * region;

		float forest_weight = smoothstep(0.50, 0.68, mm) * smoothstep(0.16, 0.28, temp);
		float canopy = fbm(px * 0.42);
		vec3 woods = mix(forest, taiga, cold) * (0.62 + 0.66 * canopy);
		low = mix(low, woods, forest_weight);

		vec3 hills = mix(vec3(0.40, 0.36, 0.26), vec3(0.38, 0.37, 0.34), cold);
		vec3 rock = mix(vec3(0.40, 0.38, 0.36), vec3(0.58, 0.55, 0.51), detail);

		col = mix(low, hills, smoothstep(0.58, 0.76, e));
		// Rock coverage is patchy, so ranges read as broken stone and grass
		// rather than one painted band. The crag term varies the stone itself,
		// so faces are not one flat grey.
		vec3 stone = rock * (1.0 + crag * 1.4);
		col = mix(col, stone, smoothstep(0.72, 0.94, e) * (0.70 + 0.45 * rocky));
		// Steep faces show bare rock even at lower altitude, and scree fans
		// collect on the gentler flanks.
		col = mix(col, stone * 0.90, steep * 0.55 * smoothstep(0.56, 0.78, e));
		col = mix(col, vec3(0.62, 0.59, 0.55), steep * 0.18 * smoothstep(0.66, 0.88, e) * detail);
		// Gullies darken the flanks and give the slope a direction.
		col *= 1.0 - smoothstep(0.68, 0.90, e) * 0.16 * gullies;

		// The snow line drops towards the cold north. The threshold is broken
		// up with noise so snow sits in patches on the crests instead of
		// drawing a continuous white line along the ridge.
		float snow_line = smoothstep(0.96, 1.06, e + (0.34 - temp) * 0.16 + (rocky - 0.5) * 0.12);
		col = mix(col, vec3(0.95, 0.96, 0.98), snow_line * (1.0 - steep * 0.35));

		// Narrow beach and a darker shore band right at the waterline.
		float shore = smoothstep(0.020, 0.0, e - sea_level);
		col = mix(col, vec3(0.74, 0.68, 0.48), shore * 0.65);
		col *= 1.0 - smoothstep(0.030, 0.0, e - sea_level) * 0.10;

		// Fine grain so large areas do not look flat.
		col *= 0.93 + 0.14 * detail;
	}

	float lit = clamp(0.62 + 0.70 * shade, 0.48, 1.25);
	if (e < sea_level) {
		lit = 1.0;
	}
	COLOR = vec4(col * lit, 1.0);
}
