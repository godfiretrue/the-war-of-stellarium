shader_type canvas_item;
// Procedural terrain painter.
// field.r = elevation, field.g = moisture (one texel per 3x3 world pixels).
// Relief comes from hill-shading the elevation, biome colours from moisture.

uniform sampler2D field : filter_linear, repeat_disable;
uniform vec2 grid_size = vec2(384.0, 216.0);
uniform vec2 world_size = vec2(1152.0, 648.0);
uniform float sea_level = 0.40;
uniform float relief = 34.0;
uniform vec3 sun = vec3(-0.62, -0.72, 0.62);

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

float elev_at(vec2 uv) {
	return texture(field, uv).r;
}

void fragment() {
	vec2 uv = UV;
	vec2 px = uv * world_size;
	vec2 t = 1.0 / grid_size;

	vec2 sample_field = texture(field, uv).rg;
	float e = sample_field.r;
	float m = sample_field.g;

	// Smoothed gradient over a 2-texel stencil, so the 3px source grid does
	// not show up as creases in the lighting.
	float k = 2.0;
	float e_l = elev_at(uv - vec2(t.x * k, 0.0));
	float e_r = elev_at(uv + vec2(t.x * k, 0.0));
	float e_u = elev_at(uv - vec2(0.0, t.y * k));
	float e_d = elev_at(uv + vec2(0.0, t.y * k));
	vec2 grad = vec2(e_r - e_l, e_d - e_u) / (2.0 * k);
	vec3 n = normalize(vec3(-grad * relief, 1.0));
	float shade = dot(n, normalize(sun));
	float steep = clamp(length(grad) * 60.0, 0.0, 1.0);

	float detail = fbm(px * 0.09);
	float broad = fbm(px * 0.018 + 3.7);

	vec3 col;
	if (e < sea_level) {
		float depth = clamp((sea_level - e) / 0.30, 0.0, 1.0);
		vec3 shallow = vec3(0.17, 0.44, 0.52);
		vec3 deep = vec3(0.03, 0.10, 0.20);
		col = mix(shallow, deep, pow(depth, 0.55));
		col += (fbm(px * 0.045) - 0.5) * 0.05;
		float foam = smoothstep(0.035, 0.0, sea_level - e);
		col = mix(col, vec3(0.80, 0.92, 0.93), foam * 0.6);
	} else {
		// Biome from moisture, broken up with noise so edges are not straight.
		float mm = m + (broad - 0.5) * 0.35 + (detail - 0.5) * 0.12;
		vec3 dry = vec3(0.68, 0.63, 0.40);
		vec3 grass = vec3(0.40, 0.54, 0.25);
		vec3 forest = vec3(0.12, 0.28, 0.14);
		vec3 low = mix(dry, grass, smoothstep(0.28, 0.50, mm));
		float forest_weight = smoothstep(0.56, 0.70, mm);
		float canopy = fbm(px * 0.42);
		vec3 woods = forest * (0.70 + 0.65 * canopy);
		low = mix(low, woods, forest_weight);

		vec3 hills = vec3(0.46, 0.41, 0.30);
		vec3 rock = vec3(0.50, 0.47, 0.44);
		vec3 snow = vec3(0.95, 0.96, 0.98);

		col = mix(low, hills, smoothstep(0.60, 0.70, e));
		col = mix(col, rock, smoothstep(0.68, 0.80, e));
		// Steep faces show bare rock even at lower altitude.
		col = mix(col, rock * 0.80, steep * 0.55 * smoothstep(0.55, 0.70, e));
		float snow_line = smoothstep(0.86, 0.95, e + (detail - 0.5) * 0.10);
		col = mix(col, snow, snow_line * (1.0 - steep * 0.45));

		// Narrow sandy beach right at the waterline.
		float beach = smoothstep(0.022, 0.0, e - sea_level);
		col = mix(col, vec3(0.80, 0.74, 0.52), beach * 0.75);

		// Fine grain so large areas do not look flat.
		col *= 0.94 + 0.12 * detail;
	}

	float lit = clamp(0.52 + 0.78 * shade, 0.35, 1.35);
	if (e < sea_level) {
		lit = 1.0;
	}
	COLOR = vec4(col * lit, 1.0);
}
