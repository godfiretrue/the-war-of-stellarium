extends Control
## Celestial constellation title for "The War of Stellarium".
##
## Bold, radiant, and heroic star map typography:
## - "Juntar": Stars drift across the cosmic void and converge into place.
## - "Brilho": Prominent, luminescent stars with diamond-sharp cores,
##   multi-layered cyan and violet halos, and glowing constellation filaments.

# --- Letter Definitions --------------------------------------------------
const LETTERS := {
	"A": {
		"w": 0.84,
		"s": [
			[[0.0, 1.0], [0.42, 0.0], [0.84, 1.0]],
			[[0.18, 0.60], [0.66, 0.60]],
		]
	},
	"B": {
		"w": 0.76,
		"s": [
			[[0.0, 1.0], [0.0, 0.0], [0.52, 0.0], [0.76, 0.25], [0.52, 0.50], [0.0, 0.50]],
			[[0.52, 0.50], [0.76, 0.75], [0.52, 1.0], [0.0, 1.0]],
		]
	},
	"C": {
		"w": 0.76,
		"s": [
			[[0.74, 0.20], [0.44, 0.0], [0.0, 0.30], [0.0, 0.70], [0.44, 1.0], [0.74, 0.80]]
		]
	},
	"D": {
		"w": 0.78,
		"s": [
			[[0.0, 1.0], [0.0, 0.0], [0.48, 0.0], [0.78, 0.35], [0.78, 0.65], [0.48, 1.0], [0.0, 1.0]]
		]
	},
	"E": {
		"w": 0.72,
		"s": [
			[[0.72, 0.0], [0.0, 0.0], [0.0, 1.0], [0.72, 1.0]],
			[[0.0, 0.50], [0.48, 0.50]]
		]
	},
	"F": {
		"w": 0.72,
		"s": [
			[[0.72, 0.0], [0.0, 0.0], [0.0, 1.0]],
			[[0.0, 0.50], [0.48, 0.50]]
		]
	},
	"G": {
		"w": 0.80,
		"s": [
			[[0.74, 0.20], [0.44, 0.0], [0.0, 0.30], [0.0, 0.70], [0.44, 1.0], [0.78, 0.75], [0.78, 0.50], [0.48, 0.50]]
		]
	},
	"H": {
		"w": 0.76,
		"s": [
			[[0.0, 0.0], [0.0, 1.0]],
			[[0.76, 0.0], [0.76, 1.0]],
			[[0.0, 0.50], [0.76, 0.50]]
		]
	},
	"I": {
		"w": 0.28,
		"s": [
			[[0.14, 0.0], [0.14, 1.0]]
		]
	},
	"J": {
		"w": 0.56,
		"s": [
			[[0.56, 0.0], [0.56, 0.75], [0.32, 1.0], [0.0, 0.75]]
		]
	},
	"K": {
		"w": 0.76,
		"s": [
			[[0.0, 0.0], [0.0, 1.0]],
			[[0.76, 0.0], [0.0, 0.50], [0.76, 1.0]]
		]
	},
	"L": {
		"w": 0.66,
		"s": [
			[[0.0, 0.0], [0.0, 1.0], [0.66, 1.0]]
		]
	},
	"M": {
		"w": 0.90,
		"s": [
			[[0.0, 1.0], [0.0, 0.0], [0.45, 0.55], [0.90, 0.0], [0.90, 1.0]]
		]
	},
	"N": {
		"w": 0.76,
		"s": [
			[[0.0, 1.0], [0.0, 0.0], [0.76, 1.0], [0.76, 0.0]]
		]
	},
	"O": {
		"w": 0.80,
		"s": [
			[[0.40, 0.0], [0.80, 0.28], [0.80, 0.72], [0.40, 1.0], [0.0, 0.72], [0.0, 0.28], [0.40, 0.0]]
		]
	},
	"P": {
		"w": 0.72,
		"s": [
			[[0.0, 1.0], [0.0, 0.0], [0.52, 0.0], [0.72, 0.25], [0.52, 0.50], [0.0, 0.50]]
		]
	},
	"Q": {
		"w": 0.80,
		"s": [
			[[0.40, 0.0], [0.80, 0.28], [0.80, 0.72], [0.40, 1.0], [0.0, 0.72], [0.0, 0.28], [0.40, 0.0]],
			[[0.48, 0.70], [0.85, 1.05]]
		]
	},
	"R": {
		"w": 0.76,
		"s": [
			[[0.0, 1.0], [0.0, 0.0], [0.52, 0.0], [0.76, 0.25], [0.52, 0.50], [0.0, 0.50]],
			[[0.38, 0.50], [0.76, 1.0]]
		]
	},
	"S": {
		"w": 0.72,
		"s": [
			[[0.68, 0.15], [0.34, 0.0], [0.0, 0.25], [0.36, 0.50], [0.70, 0.75], [0.36, 1.0], [0.04, 0.85]]
		]
	},
	"T": {
		"w": 0.76,
		"s": [
			[[0.0, 0.0], [0.76, 0.0]],
			[[0.38, 0.0], [0.38, 1.0]]
		]
	},
	"U": {
		"w": 0.76,
		"s": [
			[[0.0, 0.0], [0.0, 0.75], [0.20, 1.0], [0.56, 1.0], [0.76, 0.75], [0.76, 0.0]]
		]
	},
	"V": {
		"w": 0.76,
		"s": [
			[[0.0, 0.0], [0.38, 1.0], [0.76, 0.0]]
		]
	},
	"W": {
		"w": 1.05,
		"s": [
			[[0.0, 0.0], [0.24, 1.0], [0.525, 0.38], [0.81, 1.0], [1.05, 0.0]]
		]
	},
	"X": {
		"w": 0.76,
		"s": [
			[[0.0, 0.0], [0.76, 1.0]],
			[[0.76, 0.0], [0.0, 1.0]]
		]
	},
	"Y": {
		"w": 0.76,
		"s": [
			[[0.0, 0.0], [0.38, 0.50], [0.76, 0.0]],
			[[0.38, 0.50], [0.38, 1.0]]
		]
	},
	"Z": {
		"w": 0.72,
		"s": [
			[[0.0, 0.0], [0.72, 0.0], [0.0, 1.0], [0.72, 1.0]]
		]
	},
	"-": {
		"w": 0.40,
		"s": [
			[[0.05, 0.50], [0.35, 0.50]]
		]
	}
}

# --- Layout & Aesthetic Tuning -------------------------------------------
const LETTER_GAP := 0.38
const WORD_GAP := 0.75
const LINE_STEP := 1.58
const PAD := 24.0

# Cosmic Palette (deep space radiance)
const CORE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const DIAMOND_BLUE := Color(0.86, 0.94, 1.0, 1.0)
const NEBULA_CYAN := Color(0.38, 0.72, 1.0, 1.0)
const NEBULA_VIOLET := Color(0.52, 0.38, 0.92, 1.0)
const STELLAR_GOLD := Color(1.0, 0.92, 0.74, 1.0)

## Increased height so it commands presence as an epic game title!
@export var lines: PackedStringArray = PackedStringArray(["THE FINAL WAR", "OF STELLARIUM"])
@export var letter_height: float = 48.0
@export var intro_seconds: float = 2.2
@export var start_delay: float = 0.3
@export var seed_value: int = 42

# Internal state
var _segments: Array[Dictionary] = []
var _stars: Array[Dictionary] = []
var _stardust: Array[Dictionary] = []
var _natural: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _material: CanvasItemMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = CanvasItemMaterial.new()
	_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = _material
	_build()
	update_minimum_size()


func _get_minimum_size() -> Vector2:
	return _natural + Vector2(PAD * 2.0, PAD * 2.0)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# --- Constellation Builder -----------------------------------------------

func _build() -> void:
	_segments.clear()
	_stars.clear()
	_stardust.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var raw_segments: Array[Dictionary] = []
	var height := letter_height
	var max_width := 0.0

	for line_idx in lines.size():
		var text := lines[line_idx].to_upper()
		var cursor := 0.0
		var top := float(line_idx) * height * LINE_STEP

		for char_idx in text.length():
			var char_str := text.substr(char_idx, 1)
			if char_str == " ":
				cursor += height * WORD_GAP
				continue
			if not LETTERS.has(char_str):
				continue

			var glyph: Dictionary = LETTERS[char_str]
			var glyph_w: float = float(glyph["w"]) * height

			for stroke: Array in glyph["s"]:
				for pt_idx in range(stroke.size() - 1):
					var pt_a := _calc_point(stroke[pt_idx], cursor, top, height)
					var pt_b := _calc_point(stroke[pt_idx + 1], cursor, top, height)
					raw_segments.append({
						"a": pt_a,
						"b": pt_b,
						"line_idx": line_idx,
					})

			cursor += glyph_w + height * LETTER_GAP
		max_width = maxf(max_width, cursor - height * LETTER_GAP)

	_natural = Vector2(max_width, height + float(maxi(lines.size() - 1, 0)) * height * LINE_STEP)

	# Build deduplicated star registry
	var star_map: Dictionary = {}
	for seg_idx in raw_segments.size():
		var raw: Dictionary = raw_segments[seg_idx]
		var line_idx: int = int(raw["line_idx"])

		var seg_entry := {
			"a_idx": -1,
			"b_idx": -1,
			"phase": rng.randf() * TAU,
			"pulse_speed": rng.randf_range(0.9, 1.8),
		}

		for key_name in ["a", "b"]:
			var pt: Vector2 = raw[key_name]
			var grid_key := Vector2i(roundi(pt.x * 2.0), roundi(pt.y * 2.0))

			if star_map.has(grid_key):
				var s_idx: int = int(star_map[grid_key])
				var existing: Dictionary = _stars[s_idx]
				existing["degree"] = int(existing["degree"]) + 1
				if key_name == "a":
					seg_entry["a_idx"] = s_idx
				else:
					seg_entry["b_idx"] = s_idx
			else:
				var s_idx := _stars.size()
				star_map[grid_key] = s_idx
				if key_name == "a":
					seg_entry["a_idx"] = s_idx
				else:
					seg_entry["b_idx"] = s_idx

				# Staggered convergence ("juntar")
				var norm_x := clampf(pt.x / maxf(_natural.x, 1.0), 0.0, 1.0)
				var arrive_delay := float(line_idx) * 0.35 + norm_x * 1.15 + rng.randf_range(-0.08, 0.08)
				arrive_delay = maxf(0.0, arrive_delay)

				# Scattered cosmic starting position
				var scatter_angle := rng.randf() * TAU
				var scatter_dist := rng.randf_range(80.0, 240.0)
				var scatter_pos := pt + Vector2(cos(scatter_angle), sin(scatter_angle)) * scatter_dist

				# Star color palette
				var tint_val := rng.randf()
				var star_color := DIAMOND_BLUE
				if tint_val < 0.18:
					star_color = STELLAR_GOLD
				elif tint_val > 0.80:
					star_color = CORE_COLOR

				_stars.append({
					"target_pos": pt,
					"scatter_pos": scatter_pos,
					"current_pos": scatter_pos,
					"degree": 1,
					"arrive_delay": arrive_delay,
					"flight_duration": rng.randf_range(0.85, 1.25),
					"phase": rng.randf() * TAU,
					"twinkle_speed": rng.randf_range(1.4, 2.8),
					"flare_phase": rng.randf() * TAU,
					"is_alpha": false,
					"color": star_color,
					"size": 2.8,
				})

		_segments.append(seg_entry)

	# Designate a balanced set of ~7 Alpha stars across both lines
	var alpha_candidates: Array[int] = []
	for s_idx in _stars.size():
		var star: Dictionary = _stars[s_idx]
		var pt: Vector2 = star["target_pos"]
		if int(star["degree"]) >= 3 or pt.y < height * 0.12 or pt.y > height * 0.88:
			alpha_candidates.append(s_idx)

	alpha_candidates.shuffle()
	var alpha_count := mini(7, alpha_candidates.size())
	for i in alpha_count:
		var s_idx := alpha_candidates[i]
		_stars[s_idx]["is_alpha"] = true
		_stars[s_idx]["size"] = 4.2

	# Ambient celestial stardust
	for _i in 28:
		_stardust.append({
			"origin": Vector2(rng.randf_range(-15.0, _natural.x + 15.0), rng.randf_range(-15.0, _natural.y + 15.0)),
			"drift": Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-4.0, 4.0)),
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.5, 1.4),
			"size": rng.randf_range(0.8, 1.6),
			"color": Color(NEBULA_CYAN, rng.randf_range(0.18, 0.40)),
		})


func _calc_point(coord: Array, x_offset: float, y_offset: float, height: float) -> Vector2:
	return Vector2(
		x_offset + float(coord[0]) * height,
		y_offset + float(coord[1]) * height
	)


# --- Celestial Drawing ---------------------------------------------------

func _draw() -> void:
	if _stars.is_empty():
		return

	var fit := 1.0
	var available := size.x - PAD * 2.0
	if available > 0.0 and available < _natural.x:
		fit = available / _natural.x
	draw_set_transform(Vector2(PAD, PAD), 0.0, Vector2(fit, fit))

	var current_t := maxf(0.0, _time - start_delay)

	# 1. Update star positions ("Juntar" mechanic)
	for star in _stars:
		var delay: float = float(star["arrive_delay"])
		var flight: float = float(star["flight_duration"])
		var flight_progress := clampf((current_t - delay) / flight, 0.0, 1.0)

		# Smooth cubic ease-out
		var ease_t := 1.0 - pow(1.0 - flight_progress, 3.0)
		var s_pos: Vector2 = star["scatter_pos"]
		var t_pos: Vector2 = star["target_pos"]
		star["current_pos"] = s_pos.lerp(t_pos, ease_t)
		star["arrival_factor"] = ease_t

		# Arrival twinkle
		var time_since_arr := current_t - (delay + flight)
		var flash := 0.0
		if time_since_arr >= 0.0 and time_since_arr < 0.40:
			var flash_t := time_since_arr / 0.40
			flash = sin(flash_t * PI) * 0.9
		star["flash"] = flash

	# 2. Ambient stardust
	for dust in _stardust:
		var pulse := 0.4 + 0.6 * sin(_time * float(dust["speed"]) + float(dust["phase"]))
		var pos: Vector2 = dust["origin"] + dust["drift"] * sin(_time * 0.35 + float(dust["phase"]))
		var c: Color = dust["color"]
		c.a *= pulse
		draw_circle(pos, float(dust["size"]), c)

	# 3. Glowing Constellation Lines (filaments)
	for seg in _segments:
		var idx_a: int = int(seg["a_idx"])
		var idx_b: int = int(seg["b_idx"])
		var star_a: Dictionary = _stars[idx_a]
		var star_b: Dictionary = _stars[idx_b]

		var arr_a: float = float(star_a["arrival_factor"])
		var arr_b: float = float(star_b["arrival_factor"])
		var line_reveal := minf(arr_a, arr_b)
		if line_reveal <= 0.01:
			continue

		var pos_a: Vector2 = star_a["current_pos"]
		var pos_b: Vector2 = star_b["current_pos"]

		var shimmer := 0.72 + 0.18 * sin(_time * 1.6 + float(seg["phase"]))
		var alpha_mult := line_reveal * shimmer

		# Outer soft glowing aura
		draw_line(pos_a, pos_b, Color(NEBULA_CYAN, 0.08 * alpha_mult), 5.5, true)
		# Mid-tier luminous filament
		draw_line(pos_a, pos_b, Color(NEBULA_CYAN, 0.36 * alpha_mult), 2.0, true)
		# Core bright white filament
		draw_line(pos_a, pos_b, Color(CORE_COLOR, 0.85 * alpha_mult), 1.1, true)

		# Traveling light pulse along the line
		var pulse_prog := fposmod(_time * float(seg["pulse_speed"]) * 0.32 + float(seg["phase"]), 1.0)
		var pulse_pos := pos_a.lerp(pos_b, pulse_prog)
		var pulse_alpha := sin(pulse_prog * PI) * alpha_mult
		draw_circle(pulse_pos, 2.6, Color(CORE_COLOR, 0.55 * pulse_alpha))
		draw_circle(pulse_pos, 5.0, Color(NEBULA_CYAN, 0.20 * pulse_alpha))

	# 4. Constellation Stars: radiant cores + halos
	for star in _stars:
		var arr: float = float(star["arrival_factor"])
		if arr <= 0.01:
			continue

		var pos: Vector2 = star["current_pos"]
		var base_sz: float = float(star["size"])
		var flash: float = float(star["flash"])
		var is_alpha: bool = bool(star["is_alpha"])
		var col: Color = star["color"]

		# Multi-frequency twinkle
		var tw := sin(_time * float(star["twinkle_speed"]) + float(star["phase"]))
		var twinkle := 0.80 + 0.20 * tw

		# Rare subtle flare
		var flare_raw := maxf(0.0, sin(_time * 0.40 + float(star["flare_phase"])))
		var flare := pow(flare_raw, 20.0) * 0.7

		var intensity := (twinkle + flare + flash) * arr
		var radius := base_sz * (1.0 + flare * 0.25)

		# Outer deep violet aura
		draw_circle(pos, radius * 4.5, Color(NEBULA_VIOLET, 0.05 * intensity))
		# Mid cyan bloom halo
		draw_circle(pos, radius * 2.8, Color(NEBULA_CYAN, 0.12 * intensity))
		# Inner vibrant bloom
		draw_circle(pos, radius * 1.5, Color(col, 0.30 * intensity))
		# Radiant white star core
		draw_circle(pos, radius * 0.85, Color(CORE_COLOR, clampf(intensity, 0.0, 1.0)))

		# Crystalline Diffraction Spikes on Alpha stars
		if is_alpha or flare > 0.28:
			var spike_scale := 1.0 + flare * 1.4
			var spike_len := radius * (2.8 * spike_scale)
			var glint_col := Color(CORE_COLOR, clampf(0.55 * intensity, 0.0, 1.0))
			var spike_w := 1.1

			# 4-Point cross
			_draw_diamond_ray(pos, spike_len, spike_w, 0.0, glint_col)
			_draw_diamond_ray(pos, spike_len, spike_w, PI * 0.5, glint_col)

			# Subtle secondary diagonal glint on Alpha stars
			if is_alpha:
				var sec_len := spike_len * 0.50
				var sec_col := Color(col, clampf(0.30 * intensity, 0.0, 1.0))
				_draw_diamond_ray(pos, sec_len, spike_w * 0.75, PI * 0.25, sec_col)
				_draw_diamond_ray(pos, sec_len, spike_w * 0.75, PI * 0.75, sec_col)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws a crystalline tapered diamond ray in additive mode
func _draw_diamond_ray(center: Vector2, length: float, half_width: float, angle: float, color: Color) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	var ortho := Vector2(-dir.y, dir.x)

	var tip_a := center + dir * length
	var tip_b := center - dir * length
	var side_a := center + ortho * half_width
	var side_b := center - ortho * half_width

	var pts := PackedVector2Array([tip_a, side_a, tip_b, side_b])
	var colors := PackedColorArray([
		Color(color, 0.0),
		color,
		Color(color, 0.0),
		color
	])
	draw_polygon(pts, colors)
