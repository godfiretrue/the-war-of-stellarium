class_name WorldGenerator
extends RefCounted
## Procedural continent generator.
##
## Pipeline (all driven by one integer seed, so a save only stores the seed):
##   1. elevation + moisture fields from layered noise: an elliptical continent
##      with warped coast, mountain belts (ridged noise masked by a low
##      frequency "tectonic" noise) and rainfall that falls off inland;
##   2. a few guaranteed "anchor" provinces bend the terrain around them
##      (capitals, fortresses) so the story-critical places always exist;
##   3. only the biggest landmass is kept, rivers run downhill from the
##      highlands to the sea;
##   4. provinces grow from seed points with a geodesic flood (Dijkstra) where
##      mountains and rivers are expensive to cross, so borders follow ridges
##      and rivers instead of straight lines;
##   5. each province is classified from its own cells (mountain, forest, coast,
##      river valley...), named, linked to its neighbours and handed out to the
##      two factions;
##   6. contours are traced for tint/border drawing and the elevation/moisture
##      field is packed into an image for the terrain shader.

const CELL := 4
const GRID_W := 288
const GRID_H := 162
const SEA_LEVEL := 0.40
const MOUNTAIN_LEVEL := 0.70
const TARGET_PROVINCES := 21
const MIN_SEED_DISTANCE := 88.0
const MAX_ATTEMPTS := 12
## How many upstream cells must drain through a cell before it becomes a river.
const RIVER_MIN_DRAINAGE := 140
## Height added per flood step, so filled basins keep a downhill gradient.
const FILL_EPSILON := 0.00002
## Sea-cell distance to the coast is normalised over this many world pixels
## into the field image's alpha channel (for the pixel-water foam shader).
const COAST_FADE_PX := 200.0
## 5x5 Gaussian used to soften the coast-distance alpha after the BFS. The
## distance field is quantised to CELL-sized steps, which otherwise show as a
## staircase along the shoreline.
const COAST_BLUR_KERNEL := [
	[1, 4, 6, 4, 1],
	[4, 16, 24, 16, 4],
	[6, 24, 36, 24, 6],
	[4, 16, 24, 16, 4],
	[1, 4, 6, 4, 1],
]

const NAME_PREFIXES := [
	"Thorn", "Silver", "Ash", "Raven", "Gold", "Frost", "Oak", "Stone", "Mist", "Ember",
	"Wolf", "Hollow", "Dusk", "Crown", "Iron", "Gale", "Briar", "Amber", "Cinder", "Elder",
	"Fen", "Grey", "Hawk", "Lark", "Moon", "Night", "Pine", "Red", "Sun", "Willow",
]
const SUFFIX_PLAINS := ["vale", "reach", "march", "heath", "field", "ford", "wold"]
const SUFFIX_FOREST := ["wood", "weald", "glade", "thicket", "holt"]
const SUFFIX_MOUNTAIN := ["crag", "fell", "peak", "tor", "spine", "ridge"]
const SUFFIX_COAST := ["shore", "strand", "mere", "haven", "bay"]

var _seed: int = 0
var _rng := RandomNumberGenerator.new()
var _anchors: Array[Dictionary] = []
var _spine_phase: float = 0.0

## World size for this build. build() sets these from the requested scale, so
## every field, table and image below works on the real dimensions instead of
## the 1x reference grid.
var _grid_w: int = GRID_W
var _grid_h: int = GRID_H
var _world_w: float = GRID_W * CELL
var _world_h: float = GRID_H * CELL
var _scale: float = 1.0
var _target_provinces: int = TARGET_PROVINCES
var _river_min_drainage: int = RIVER_MIN_DRAINAGE

var _elev := PackedFloat32Array()
var _moist := PackedFloat32Array()
var _temp := PackedFloat32Array()
var _river := PackedByteArray()
var _label := PackedInt32Array()
var _seed_cells := PackedInt32Array()
var _rivers: Array[PackedVector2Array] = []
var _river_widths: Array[float] = []

## Depression-filled surface, downhill direction and flow accumulation.
## Rebuilt for every world, used by the river network.
var _filled := PackedFloat32Array()
var _flow := PackedInt32Array()
var _drain := PackedInt32Array()

## Mountain strength per cell (0..1) stamped by the range chains.
var _mount := PackedFloat32Array()

## Precomputed neighbour indices (-1 when off-grid). Order of the 8-table:
## row above (left, mid, right), same row (left, right), row below (l, m, r);
## so indices 0, 2, 5 and 7 are the diagonals.
## Reused between builds of the same size instead of paying ~0.5 s per world.
static var _nbr4 := PackedInt32Array()
static var _nbr8 := PackedInt32Array()
static var _nbr_dims := Vector2i.ZERO


func build(world_seed: int, world_scale: float = 1.0) -> MapState:
	var started := Time.get_ticks_msec()
	_scale = clampf(world_scale, 1.0, 2.0)
	_grid_w = roundi(GRID_W * _scale)
	_grid_h = roundi(GRID_H * _scale)
	_world_w = float(_grid_w * CELL)
	_world_h = float(_grid_h * CELL)
	# Province and city density follow the area, so provinces stay the same
	# physical size while the continent grows.
	_target_provinces = roundi(TARGET_PROVINCES * _scale * _scale)
	_river_min_drainage = roundi(RIVER_MIN_DRAINAGE * _scale * _scale)
	_ensure_neighbor_tables()
	for attempt in MAX_ATTEMPTS:
		var state := _try_build(world_seed + attempt * 7919)
		if state != null:
			state.map_seed = world_seed
			print("[worldgen] seed %d ready in %d ms (attempt %d)" % [world_seed, Time.get_ticks_msec() - started, attempt + 1])
			return state
	push_error("WorldGenerator: no valid continent for seed %d" % world_seed)
	return null


## The six guaranteed provinces of the world that was generated last.
func anchors() -> Array[Dictionary]:
	return _anchors


## Builds the shared neighbour tables once per grid size.
func _ensure_neighbor_tables() -> void:
	var dims := Vector2i(_grid_w, _grid_h)
	if _nbr_dims == dims and not _nbr4.is_empty():
		return
	_nbr_dims = dims
	var total := _grid_w * _grid_h
	_nbr4.resize(total * 4)
	_nbr8.resize(total * 8)
	for y in _grid_h:
		var row := y * _grid_w
		var row_up := row - _grid_w
		var row_down := row + _grid_w
		var has_up := y > 0
		var has_down := y < _grid_h - 1
		for x in _grid_w:
			var index := row + x
			var left := x > 0
			var right := x < _grid_w - 1

			var base8 := index * 8
			_nbr8[base8] = (row_up + x - 1) if has_up and left else -1
			_nbr8[base8 + 1] = (row_up + x) if has_up else -1
			_nbr8[base8 + 2] = (row_up + x + 1) if has_up and right else -1
			_nbr8[base8 + 3] = (row + x - 1) if left else -1
			_nbr8[base8 + 4] = (row + x + 1) if right else -1
			_nbr8[base8 + 5] = (row_down + x - 1) if has_down and left else -1
			_nbr8[base8 + 6] = (row_down + x) if has_down else -1
			_nbr8[base8 + 7] = (row_down + x + 1) if has_down and right else -1

			var base4 := index * 4
			_nbr4[base4] = (row_up + x) if has_up else -1
			_nbr4[base4 + 1] = (row + x - 1) if left else -1
			_nbr4[base4 + 2] = (row + x + 1) if right else -1
			_nbr4[base4 + 3] = (row_down + x) if has_down else -1


# --- Anchors ---------------------------------------------------------------

## The only hand-placed content: the places the story needs to exist.
func _make_anchors() -> Array[Dictionary]:
	var list: Array[Dictionary] = [
		{"id": "aldermere", "name": "Aldermere", "pos": _scaled_point(180, 300),
			"terrain": Balance.Terrain.COAST, "fortress": true,
			"owner": Balance.Faction.HUMANS, "capital": true, "type": "Capital Port"},
		{"id": "stonewatch", "name": "Stonewatch", "pos": _scaled_point(335, 150),
			"terrain": Balance.Terrain.MOUNTAINS, "fortress": true,
			"owner": Balance.Faction.HUMANS, "capital": false, "type": "Fortress"},
		{"id": "iron_pass", "name": "Iron Pass", "pos": _scaled_point(540, 255),
			"terrain": Balance.Terrain.MOUNTAINS, "fortress": true,
			"owner": Balance.Faction.NEUTRAL, "capital": false, "type": "Fortress Pass"},
		{"id": "oakhaven", "name": "Oakhaven", "pos": _scaled_point(700, 365),
			"terrain": Balance.Terrain.FOREST, "fortress": false,
			"owner": Balance.Faction.NEUTRAL, "capital": false, "type": "River Town"},
		{"id": "dawnwatch_spire", "name": "Dawnwatch Spire", "pos": _scaled_point(830, 135),
			"terrain": Balance.Terrain.MOUNTAINS, "fortress": true,
			"owner": Balance.Faction.ELVES, "capital": false, "type": "Elven Spire"},
		{"id": "ysolde", "name": "Ysolde", "pos": _scaled_point(960, 295),
			"terrain": Balance.Terrain.MOUNTAINS, "fortress": true,
			"owner": Balance.Faction.ELVES, "capital": true, "type": "Capital Citadel"},
	]
	return list


## Anchor coordinates are authored on the 1x reference world, so they scale
## with the continent instead of bunching up around the old centre.
func _scaled_point(x: float, y: float) -> Vector2:
	return Vector2(x, y) * _scale


# --- Pipeline --------------------------------------------------------------

func _try_build(world_seed: int) -> MapState:
	_seed = world_seed
	_rng.seed = world_seed
	_spine_phase = _rng.randf_range(0.0, TAU)
	_anchors = _make_anchors()
	_rivers.clear()

	_generate_fields()
	if not _keep_main_land():
		return null
	_trace_rivers()
	if not _grow_provinces():
		return null
	return _assemble_state()


func _noise(noise_seed: int, frequency: float, fractal: int, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	return noise


func _generate_fields() -> void:
	var warp := _noise(_seed + 1, 0.006, FastNoiseLite.FRACTAL_FBM, 2)
	var base := _noise(_seed + 2, 0.0075, FastNoiseLite.FRACTAL_FBM, 4)
	var grain := _noise(_seed + 3, 0.010, FastNoiseLite.FRACTAL_RIDGED, 3)
	var wet := _noise(_seed + 5, 0.008, FastNoiseLite.FRACTAL_FBM, 3)

	var total := _grid_w * _grid_h
	_elev.resize(total)
	_moist.resize(total)
	_temp.resize(total)
	_mount.resize(total)
	_mount.fill(0.0)

	# 1. Continental base: a warped elliptical landmass with gentle lowlands.
	for y in _grid_h:
		for x in _grid_w:
			var px := (float(x) + 0.5) * CELL
			var py := (float(y) + 0.5) * CELL
			var wx := px + warp.get_noise_2d(px, py) * 75.0
			var wy := py + warp.get_noise_2d(px + 517.0, py + 211.0) * 75.0
			# The continent keeps its proportions: the ellipse centre and radii
			# scale with the world, while the noise frequencies stay in pixels.
			var centre := Vector2(_world_w * 0.5, _world_h * 0.44)
			var nx := (wx - centre.x) / (575.0 * _scale)
			var ny := (wy - centre.y) / (240.0 * _scale)
			var dist := sqrt(nx * nx + ny * ny)
			var mask := clampf(1.0 - pow(dist, 3.0), 0.0, 1.0)
			# Fade to open sea under the top and bottom HUD bars; the coast is
			# pushed behind the bars so no foam line shows in the play area.
			mask *= smoothstep(20.0 * _scale, 80.0 * _scale, py) \
					* smoothstep(560.0 * _scale, 500.0 * _scale, py)

			var low := base.get_noise_2d(px, py) * 0.5 + 0.5
			var e := 0.18 + mask * 0.40 + (low - 0.5) * 0.24
			_elev[y * _grid_w + x] = e

	# 2. Mountain ranges as tapered chains of points. Ridged noise alone gives
	#    a field of short filaments; a chain gives one long crest with foothills
	#    and a proper rain shadow behind it.
	_build_ranges()
	_apply_ranges(grain)

	# 3. Plains and coast anchors stay low: ranges get a pass cut through them.
	_carve_anchor_passes()

	# 4. Moisture and temperature, in one west-to-east pass. Prevailing winds
	#    come off the western ocean: humidity dries inland and drops sharply
	#    after a mountain range, which produces the rain shadow.
	for y in _grid_h:
		var carried := 1.0
		var latitude := (float(y) + 0.5) / float(_grid_h)
		for x in _grid_w:
			var index := y * _grid_w + x
			var px := (float(x) + 0.5) * CELL
			var py := (float(y) + 0.5) * CELL

			if _elev[index] < SEA_LEVEL:
				carried = 1.0
				_moist[index] = 1.0
			else:
				carried = maxf(carried - 0.0026, 0.22)
				carried = maxf(carried - 0.055 * maxf(_elev[index] - 0.55, 0.0), 0.22)
				var noise_m := wet.get_noise_2d(px, py) * 0.5 + 0.5
				_moist[index] = clampf(0.20 + 1.02 * noise_m * carried, 0.0, 1.0)

			# Cold north, warm south, colder with altitude.
			var t := lerpf(0.22, 0.76, latitude)
			t -= 0.42 * smoothstep(0.55, 0.98, _elev[index])
			t += wet.get_noise_2d(px + 91.0, py + 37.0) * 0.05
			_temp[index] = clampf(t, 0.0, 1.0)


## Points of one mountain range, meandering around a base heading. Ranges are
## long and sinuous, so the map reads as geography instead of noise.
func _range_points(start: Vector2, angle: float, steps: int, step_len: float,
		wobble: float, jitter: float) -> Array:
	var points: Array = []
	var point := start
	for i in steps:
		points.append(point)
		var heading := angle + sin(float(i) * 0.42 + _spine_phase) * wobble \
				+ _rng.randf_range(-jitter, jitter) + float(i) * 0.012
		point += Vector2(cos(heading), sin(heading)) * step_len
		# Keep ranges on the map even with a long chain.
		point.x = clampf(point.x, 30.0, _world_w - 30.0)
		point.y = clampf(point.y, 40.0, _world_h - 38.0)
	points.append(point)
	return points


## Stamps one range into the mountain field: a chain of segments, each with a
## smooth cross-section, tapering to nothing at both ends.
@warning_ignore("integer_division")
func _add_range(points: Array, width: float, height: float) -> void:
	var segments := points.size() - 1
	if segments < 1:
		return
	for i in segments:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var along := float(i) / float(segments)
		var taper := smoothstep(0.0, 0.28, along) * smoothstep(1.0, 0.72, along)
		if taper <= 0.0:
			continue
		var reach := width * (0.80 + 0.30 * sin(float(i) * 1.7 + _spine_phase * 2.0))
		var min_x := maxi(int((minf(a.x, b.x) - reach) / CELL), 0)
		var max_x := mini(int((maxf(a.x, b.x) + reach) / CELL), _grid_w - 1)
		var min_y := maxi(int((minf(a.y, b.y) - reach) / CELL), 0)
		var max_y := mini(int((maxf(a.y, b.y) + reach) / CELL), _grid_h - 1)
		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				var point := Vector2((float(x) + 0.5) * CELL, (float(y) + 0.5) * CELL)
				var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
				var distance := point.distance_to(closest)
				if distance > reach:
					continue
				var profile := pow(clampf(1.0 - distance / reach, 0.0, 1.0), 1.25)
				var strength := smoothstep(0.0, 1.0, profile) * height * taper
				var index := y * _grid_w + x
				if strength > _mount[index]:
					_mount[index] = strength


## Layout of the ranges: one dominant spine, a secondary chain in the west and
## a small range through every mountain anchor.
func _build_ranges() -> void:
	var spine_start := Vector2(620.0, 90.0) * _scale
	var spine := _range_points(spine_start, deg_to_rad(96.0), 22, 26.0 * _scale, 0.85, 0.16)
	_add_range(spine, 48.0 * _scale, 0.46)

	var west_start := Vector2(250.0, 350.0) * _scale
	var west := _range_points(west_start, deg_to_rad(-22.0), 15, 31.0 * _scale, 0.55, 0.12)
	_add_range(west, 36.0 * _scale, 0.34)

	for anchor in _anchors:
		if int(anchor["terrain"]) != Balance.Terrain.MOUNTAINS:
			continue
		var center: Vector2 = anchor["pos"]
		var heading := _rng.randf_range(0.0, TAU)
		var points: Array = []
		for i in range(-4, 5):
			var t := float(i)
			var angle := heading + sin(t * 0.5 + _spine_phase) * 0.55
			points.append(center + Vector2(cos(angle), sin(angle)) * (t * 28.0 * _scale))
		_add_range(points, 42.0 * _scale, 0.38)


## Lifts the base terrain where the ranges were stamped. Two noise scales: a
## long one that makes some sections of a range tall and others saddle-shaped,
## and a fine one so crests are jagged instead of smooth sausages.
@warning_ignore("integer_division")
func _apply_ranges(grain: FastNoiseLite) -> void:
	var total := _grid_w * _grid_h
	for index in total:
		var strength := _mount[index]
		if strength <= 0.0:
			continue
		var px := (float(index % _grid_w) + 0.5) * CELL
		var py := (float(index / _grid_w) + 0.5) * CELL
		var along := grain.get_noise_2d(px * 0.30 + 91.0, py * 0.30 + 47.0) * 0.5 + 0.5
		var rough := 0.86 + 0.26 * clampf(grain.get_noise_2d(px, py) * 0.5 + 0.5, 0.0, 1.0)
		var crags := clampf(grain.get_noise_2d(px * 4.5 + 33.0, py * 4.5 + 71.0) * 0.5 + 0.5, 0.0, 1.0)
		# The crag layer is what the shader hill-shades into individual peaks.
		# It is centred on zero so it cuts gullies as well as raising peaks;
		# without it a range is a smooth grey sausage.
		_elev[index] += strength * (0.55 + 0.60 * along) * rough + strength * strength * 0.26 * (crags - 0.5)


## Plains and coastal anchors are guaranteed low ground: the terrain is pulled
## down around them, which also reads as a pass cut through a range.
func _carve_anchor_passes() -> void:
	var radius := 74.0
	for anchor in _anchors:
		if int(anchor["terrain"]) == Balance.Terrain.MOUNTAINS:
			continue
		var center: Vector2 = anchor["pos"]
		var min_x := maxi(int((center.x - radius) / CELL), 0)
		var max_x := mini(int((center.x + radius) / CELL), _grid_w - 1)
		var min_y := maxi(int((center.y - radius) / CELL), 0)
		var max_y := mini(int((center.y + radius) / CELL), _grid_h - 1)
		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				var point := Vector2((float(x) + 0.5) * CELL, (float(y) + 0.5) * CELL)
				var weight := smoothstep(radius, radius * 0.25, point.distance_to(center))
				if weight <= 0.0:
					continue
				var index := y * _grid_w + x
				_elev[index] = minf(_elev[index], lerpf(_elev[index], 0.50, weight))


func _cell_of(point: Vector2) -> int:
	var x := clampi(int(point.x / CELL), 0, _grid_w - 1)
	var y := clampi(int(point.y / CELL), 0, _grid_h - 1)
	return y * _grid_w + x


## Keeps the landmass that holds every anchor; everything else becomes sea.
func _keep_main_land() -> bool:
	var total := _grid_w * _grid_h
	var component := PackedInt32Array()
	component.resize(total)
	component.fill(-1)
	var next_id := 0

	for start in total:
		if component[start] != -1 or _elev[start] < SEA_LEVEL:
			continue
		var stack := PackedInt32Array([start])
		component[start] = next_id
		while not stack.is_empty():
			var current: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			for k in 4:
				var neighbor := _nbr4[current * 4 + k]
				if neighbor < 0:
					continue
				if component[neighbor] == -1 and _elev[neighbor] >= SEA_LEVEL:
					component[neighbor] = next_id
					stack.append(neighbor)
		next_id += 1

	var main_id := -2
	for anchor in _anchors:
		var cell := _cell_of(anchor["pos"])
		var id := component[cell]
		if id < 0:
			return false
		if main_id == -2:
			main_id = id
		elif id != main_id:
			return false

	for index in total:
		if _elev[index] >= SEA_LEVEL and component[index] != main_id:
			_elev[index] = SEA_LEVEL - 0.06
	return true


# --- Rivers ----------------------------------------------------------------

## Water runs along the depression-filled surface, so every land cell has a
## downhill direction that eventually reaches the sea. That is what turns the
## map from "one odd stream" into a real branching network: tributaries join
## the main stem instead of dying in the first pit.
func _trace_rivers() -> void:
	_priority_flood()
	_compute_drainage()

	var total := _grid_w * _grid_h
	_river.resize(total)
	_river.fill(0)
	for index in total:
		if _elev[index] >= SEA_LEVEL and _drain[index] >= _river_min_drainage:
			_river[index] = 1

	# Rivers make their banks greener.
	for index in total:
		if _river[index] == 0:
			continue
		for k in 8:
			var neighbor := _nbr8[index * 8 + k]
			if neighbor >= 0 and _elev[neighbor] >= SEA_LEVEL:
				_moist[neighbor] = minf(_moist[neighbor] + 0.06, 1.0)

	_extract_rivers()


## Priority flood: fills closed depressions up to their lowest outlet. Each step
## adds FILL_EPSILON to the propagating height, so the filled surface has a
## strictly descending gradient towards the sea even on a flat basin floor;
## that is what stops rivers from coiling around lakes.
@warning_ignore("integer_division")
func _priority_flood() -> void:
	var total := _grid_w * _grid_h
	var levels := 1025

	_filled.resize(total)
	var visited := PackedByteArray()
	visited.resize(total)
	visited.fill(0)

	var buckets: Array = []
	for _level in levels:
		buckets.append([])

	for index in total:
		if _elev[index] < SEA_LEVEL:
			_filled[index] = _elev[index]
			visited[index] = 1
			continue
		# Only coastal land is seeded; the flood reaches the rest of the
		# continent from there, so the ~30 000 sea cells are never popped.
		for k in 4:
			var neighbor := _nbr4[index * 4 + k]
			if neighbor >= 0 and _elev[neighbor] < SEA_LEVEL:
				visited[index] = 1
				_filled[index] = _elev[index]
				(buckets[0] as Array).append(index)
				break

	for level in levels:
		var bucket: Array = buckets[level]
		while not bucket.is_empty():
			var cell: int = bucket.pop_back()
			var base: float = _filled[cell] + FILL_EPSILON
			for k in 8:
				var neighbor := _nbr8[cell * 8 + k]
				if neighbor < 0 or visited[neighbor] == 1:
					continue
				visited[neighbor] = 1
				var height := maxf(_elev[neighbor], base)
				_filled[neighbor] = height
				var target := clampi(int(height * float(levels - 1)), 0, levels - 1)
				(buckets[target] as Array).append(neighbor)
		buckets[level] = []


## Steepest descent on the filled surface, plus flow accumulation. The gradient
## added by the flood makes every land cell point at a strictly lower neighbour,
## so the network is acyclic and can be summed high ground first.
func _compute_drainage() -> void:
	var total := _grid_w * _grid_h
	_flow.resize(total)
	_flow.fill(-1)
	_drain.resize(total)
	_drain.fill(0)

	var land: Array[int] = []
	for index in total:
		if _elev[index] < SEA_LEVEL:
			continue
		land.append(index)
		var best := -1
		var best_height := _filled[index]
		for k in 8:
			var neighbor := _nbr8[index * 8 + k]
			if neighbor < 0:
				continue
			var height := _filled[neighbor]
			if height < best_height:
				best = neighbor
				best_height = height
		_flow[index] = best

	land.sort_custom(func(a: int, b: int) -> bool: return _filled[a] > _filled[b])
	for cell in land:
		_drain[cell] += 1
		var downstream := _flow[cell]
		if downstream >= 0:
			_drain[downstream] += _drain[cell]


## Turns the river cells into chains that run between junctions. Each cell is
## drawn exactly once, so tributaries join a single stem instead of every
## source dragging its own path down the same valley.
func _extract_rivers() -> void:
	var total := _grid_w * _grid_h
	_rivers.clear()
	_river_widths.clear()

	# How many river neighbours feed each cell (capped: only 0/1/2 matter).
	var upstream := PackedByteArray()
	upstream.resize(total)
	upstream.fill(0)
	for index in total:
		if _river[index] == 0:
			continue
		var downstream := _flow[index]
		if downstream >= 0 and _river[downstream] == 1:
			upstream[downstream] = mini(upstream[downstream] + 1, 2)

	for index in total:
		if _river[index] == 0 or upstream[index] == 1:
			continue

		# Sources (0 upstream) and junctions (2+) start a chain; walk down to
		# the next junction or to the sea.
		var path: Array[int] = [index]
		var current := _flow[index]
		while current >= 0 and _river[current] == 1 and upstream[current] == 1:
			path.append(current)
			current = _flow[current]

		if current >= 0 and (_river[current] == 1 or _elev[current] < SEA_LEVEL):
			path.append(current)
		if path.size() < 4:
			continue

		var points := PackedVector2Array()
		for cell in path:
			points.append(_cell_point(cell))
		# The path follows grid neighbours, so it is a staircase; a couple of
		# moving-average passes remove the steps before the curve is smoothed.
		points = _smooth_path(points, 3)

		var outlet := path[path.size() - 1]
		var volume := _drain[outlet]
		var width := clampf(sqrt(float(volume) / (55.0 * _scale * _scale)), 0.9, 3.2)
		_rivers.append(_chaikin_open(points, 3))
		_river_widths.append(width)


## Moving average over the interior points; the ends stay put so separate
## chains still meet exactly at their junctions.
func _smooth_path(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	var current := points
	if current.size() < 3:
		return current
	for _pass in passes:
		var next := current.duplicate()
		for index in range(1, current.size() - 1):
			next[index] = (current[index - 1] + current[index] * 2.0 + current[index + 1]) * 0.25
		current = next
	return current


func _cell_point(index: int) -> Vector2:
	return Vector2(float(index % _grid_w) + 0.5, float(index / _grid_w) + 0.5) * float(CELL)


# --- Provinces -------------------------------------------------------------

func _grow_provinces() -> bool:
	var total := _grid_w * _grid_h
	_seed_cells = PackedInt32Array()

	for anchor in _anchors:
		var cell := _cell_of(anchor["pos"])
		if _elev[cell] < SEA_LEVEL:
			return false
		_seed_cells.append(cell)

	var tries := 0
	while _seed_cells.size() < _target_provinces and tries < roundi(8000.0 * _scale * _scale):
		tries += 1
		var candidate := _rng.randi_range(0, total - 1)
		if _elev[candidate] < SEA_LEVEL + 0.04:
			continue
		var point := _cell_point(candidate)
		var free := true
		for existing in _seed_cells:
			if _cell_point(existing).distance_to(point) < MIN_SEED_DISTANCE:
				free = false
				break
		if free:
			_seed_cells.append(candidate)

	if _seed_cells.size() < maxi(14, roundi(float(_target_provinces) * 0.67)):
		return false

	# Cost of entering a cell: mountains and rivers are expensive, so borders
	# settle on ridges and along rivers.
	var cost := PackedInt32Array()
	cost.resize(total)
	for index in total:
		if _elev[index] < SEA_LEVEL:
			cost[index] = -1
			continue
		var value := 10 + int(28.0 * clampf((_elev[index] - 0.62) / 0.2, 0.0, 1.0))
		if _river[index] == 1:
			value += 9
		value += _rng.randi_range(0, 4)
		cost[index] = value

	var multiplier := PackedFloat32Array()
	for index in _seed_cells.size():
		multiplier.append(1.0 if index < _anchors.size() else _rng.randf_range(0.85, 1.25))

	var distance := PackedInt32Array()
	distance.resize(total)
	distance.fill(0x7fffffff)
	_label.resize(total)
	_label.fill(-1)

	var buckets: Array[PackedInt32Array] = [PackedInt32Array()]
	for seed_index in _seed_cells.size():
		var cell := _seed_cells[seed_index]
		distance[cell] = 0
		_label[cell] = seed_index
		buckets[0].append(cell)

	var level := 0
	while level < buckets.size():
		var bucket: PackedInt32Array = buckets[level]
		for index in bucket:
			if distance[index] != level:
				continue
			var owner_label := _label[index]
			for k in 8:
				var neighbor := _nbr8[index * 8 + k]
				if neighbor < 0:
					continue
				var step_cost := cost[neighbor]
				if step_cost < 0:
					continue
				var diagonal := k == 0 or k == 2 or k == 5 or k == 7
				var step := float(step_cost) * (1.414 if diagonal else 1.0) * multiplier[owner_label]
				var new_distance := level + maxi(int(step), 1)
				if new_distance < distance[neighbor]:
					distance[neighbor] = new_distance
					_label[neighbor] = owner_label
					while buckets.size() <= new_distance:
						buckets.append(PackedInt32Array())
					buckets[new_distance].append(neighbor)
		buckets[level] = PackedInt32Array()
		level += 1

	for index in total:
		if _elev[index] >= SEA_LEVEL and _label[index] < 0:
			return false
	return true


func _assemble_state() -> MapState:
	var count := _seed_cells.size()
	var total := _grid_w * _grid_h

	# Per-province statistics and adjacency.
	# Plain Arrays: a nested PackedInt32Array fetched through `as` is a copy,
	# so appends to it would be silently lost.
	var cells_of: Array = []
	for _i in count:
		cells_of.append([])
	var sum_elev := PackedFloat32Array()
	var sum_moist := PackedFloat32Array()
	var mountain_cells := PackedInt32Array()
	var coast_cells := PackedInt32Array()
	var river_cells := PackedInt32Array()
	for _i in count:
		sum_elev.append(0.0)
		sum_moist.append(0.0)
		mountain_cells.append(0)
		coast_cells.append(0)
		river_cells.append(0)

	var edge_counts := PackedInt32Array()
	edge_counts.resize(count * count)
	edge_counts.fill(0)
	for index in total:
		var label := _label[index]
		if label < 0:
			continue
		(cells_of[label] as Array).append(index)
		sum_elev[label] += _elev[index]
		sum_moist[label] += _moist[index]
		if _elev[index] > MOUNTAIN_LEVEL:
			mountain_cells[label] += 1
		if _river[index] == 1:
			river_cells[label] += 1

		var is_coast := false
		for k in 4:
			var neighbor := _nbr4[index * 4 + k]
			if neighbor < 0:
				continue
			var other := _label[neighbor]
			if other < 0:
				is_coast = true
			elif other != label and neighbor > index:
				edge_counts[mini(label, other) * count + maxi(label, other)] += 1
		if is_coast:
			coast_cells[label] += 1

	var adjacency: Array = []
	for _i in count:
		adjacency.append([])
	for a in count:
		for b in range(a + 1, count):
			if edge_counts[a * count + b] >= 3:
				(adjacency[a] as Array).append(b)
				(adjacency[b] as Array).append(a)

	var centers := _visual_centers(count)

	# Classification, naming and cities.
	var used_names: Dictionary = {}
	for anchor in _anchors:
		used_names[String(anchor["name"])] = true

	var provinces: Array[ProvinceData] = []
	for index in count:
		var cell_count := maxi((cells_of[index] as Array).size(), 1)
		var mean_elev := sum_elev[index] / float(cell_count)
		var mean_moist := sum_moist[index] / float(cell_count)
		var mountain_fraction := float(mountain_cells[index]) / float(cell_count)
		var coast_fraction := float(coast_cells[index]) / float(cell_count)

		var province := ProvinceData.new()
		province.map_position = _cell_point(centers[index])
		province.resource_per_turn = Balance.FACTION_RESOURCE_PER_TURN

		# Coast is checked before forest: access to the sea matters more for
		# trade than rainfall, and it keeps a wet shoreline a port instead of
		# turning every coastal province into forest.
		var kind := "plains"
		if mountain_fraction > 0.30 or mean_elev > 0.72:
			kind = "mountain"
		elif coast_fraction > 0.28:
			kind = "coast"
		elif mean_moist > 0.58:
			kind = "forest"

		var terrain := Balance.Terrain.PLAINS
		match kind:
			"mountain":
				terrain = Balance.Terrain.MOUNTAINS
			"coast":
				terrain = Balance.Terrain.COAST
			"forest":
				terrain = Balance.Terrain.FOREST

		if index < _anchors.size():
			var anchor: Dictionary = _anchors[index]
			province.id = String(anchor["id"])
			province.display_name = String(anchor["name"])
			province.is_capital = bool(anchor["capital"])
			province.is_city = true
			province.is_fortress = bool(anchor.get("fortress", false))
			province.owner_faction = int(anchor["owner"])
			province.territory_type = String(anchor["type"])
			terrain = int(anchor["terrain"])
			if province.territory_type == "River Town" and river_cells[index] == 0:
				province.territory_type = "Market Town"
		else:
			province.owner_faction = Balance.Faction.NEUTRAL
			province.territory_type = _type_for(kind, coast_fraction, river_cells[index])
			province.display_name = _unique_name(kind, used_names)
			province.id = province.display_name.to_lower().replace(" ", "_")

		province.terrain = terrain
		province.resource_type = Balance.terrain_resource(province.terrain)
		province.capital_of = province.owner_faction if province.is_capital else Balance.Faction.NEUTRAL
		provinces.append(province)

	_designate_cities(provinces, adjacency, coast_cells, river_cells)
	_distribute_ownership(provinces, adjacency)

	for index in count:
		for neighbor_index: int in adjacency[index]:
			provinces[index].neighbors.append(provinces[neighbor_index].id)
		provinces[index].polygon = _province_polygon(provinces[index].map_position, cells_of[index])

	var state := MapState.new()
	state.provinces.clear()
	for province in provinces:
		state.provinces.append(province)
	state.grid_size = Vector2i(_grid_w, _grid_h)
	state.world_scale = _scale
	state.cell_size = CELL
	state.label_grid = _label.duplicate()
	var ids := PackedStringArray()
	for province in provinces:
		ids.append(province.id)
	state.label_ids = ids
	state.rivers = _rivers.duplicate()
	state.river_widths = PackedFloat32Array(_river_widths)
	state.field_image = _build_field_image()
	return state


## Cell farthest from the province border: a good place for the label.
func _visual_centers(count: int) -> PackedInt32Array:
	var total := _grid_w * _grid_h
	var depth := PackedInt32Array()
	depth.resize(total)
	depth.fill(-1)

	var queue := PackedInt32Array()
	for index in total:
		if _label[index] < 0:
			continue
		for k in 4:
			var neighbor := _nbr4[index * 4 + k]
			if neighbor >= 0 and _label[neighbor] != _label[index]:
				depth[index] = 0
				queue.append(index)
				break

	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for k in 4:
			var neighbor := _nbr4[current * 4 + k]
			if neighbor >= 0 and _label[neighbor] == _label[current] and depth[neighbor] < 0:
				depth[neighbor] = depth[current] + 1
				queue.append(neighbor)

	var centers := PackedInt32Array()
	var best_depth := PackedInt32Array()
	for _i in count:
		centers.append(_seed_cells[_i])
		best_depth.append(-1)
	for index in total:
		var label := _label[index]
		if label >= 0 and depth[index] > best_depth[label]:
			best_depth[label] = depth[index]
			centers[label] = index
	return centers


func _type_for(kind: String, coast_fraction: float, river_cells: int) -> String:
	match kind:
		"mountain":
			return "Highlands"
		"forest":
			return "Forest Coast" if coast_fraction > 0.20 else "Deep Forest"
		"coast":
			return "Coastline"
	return "River Valley" if river_cells > 5 else "Farmlands"


func _unique_name(kind: String, used: Dictionary) -> String:
	var suffixes: Array = SUFFIX_PLAINS
	match kind:
		"mountain":
			suffixes = SUFFIX_MOUNTAIN
		"forest":
			suffixes = SUFFIX_FOREST
		"coast":
			suffixes = SUFFIX_COAST
	for _try in 60:
		var candidate := String(NAME_PREFIXES[_rng.randi_range(0, NAME_PREFIXES.size() - 1)]) \
			+ String(suffixes[_rng.randi_range(0, suffixes.size() - 1)])
		if not used.has(candidate):
			used[candidate] = true
			return candidate
	var fallback := "Province%d" % used.size()
	used[fallback] = true
	return fallback


## Adds a handful of towns in good spots (flat, wet, coastal) on top of the
## anchors, keeping them apart from each other.
func _designate_cities(provinces: Array[ProvinceData], adjacency: Array, coast_cells: PackedInt32Array, river_cells: PackedInt32Array) -> void:
	var scored: Array[Dictionary] = []
	for index in provinces.size():
		if index < _anchors.size():
			continue
		var province := provinces[index]
		var score := _rng.randf() * 0.4
		match province.terrain:
			Balance.Terrain.PLAINS:
				score += 1.0
			Balance.Terrain.COAST:
				score += 0.8
			Balance.Terrain.FOREST:
				score += 0.5
			Balance.Terrain.MOUNTAINS:
				score += 0.2
		if river_cells[index] > 5:
			score += 0.5
		if coast_cells[index] > 8:
			score += 0.3
		scored.append({"index": index, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)

	var city_indices: Array[int] = []
	for index in _anchors.size():
		city_indices.append(index)

	var added := 0
	# Town count follows the land area, so a bigger continent gets more towns
	# without shrinking provinces: 4 at 1x, ~18 at 1.5x, 32 at 2x.
	var town_target := 4 if _scale <= 1.01 else roundi(8.0 * _scale * _scale)
	# First pass keeps towns apart; the relaxed pass fills the rest even when
	# the graph is too tight for that.
	for strict in [true, false]:
		if added >= town_target:
			break
		for entry in scored:
			if added >= town_target:
				break
			var index: int = entry["index"]
			if city_indices.has(index):
				continue
			var too_close := false
			if strict:
				for city in city_indices:
					if (adjacency[index] as Array).has(city):
						too_close = true
						break
			if too_close:
				continue
			_promote_city(provinces[index], river_cells[index], coast_cells[index])
			city_indices.append(index)
			added += 1


func _promote_city(province: ProvinceData, river_cells: int, coast_cells: int) -> void:
	province.is_city = true
	if province.terrain == Balance.Terrain.MOUNTAINS:
		province.is_fortress = true
		province.territory_type = "Fortress"
	elif province.terrain == Balance.Terrain.COAST:
		province.territory_type = "Port Town"
	elif river_cells > 5:
		province.territory_type = "River Town"
	elif coast_cells > 8:
		province.territory_type = "Port Town"
	else:
		province.territory_type = "Market Town"


## Gives each faction a connected block of provinces around its capital.
func _distribute_ownership(provinces: Array[ProvinceData], adjacency: Array) -> void:
	# Both sides start with about 30% of the world. The cap only exists to stop
	# a tiny map handing out everything, so it grows with the province count.
	var target := maxi(5, roundi(float(provinces.size()) * 0.3))
	var counts := {Balance.Faction.HUMANS: 0, Balance.Faction.ELVES: 0}
	for province in provinces:
		if counts.has(province.owner_faction):
			counts[province.owner_faction] = int(counts[province.owner_faction]) + 1

	var capitals := {}
	for index in provinces.size():
		if provinces[index].is_capital:
			capitals[provinces[index].owner_faction] = provinces[index].map_position

	var progress := true
	while progress:
		progress = false
		for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
			if int(counts[faction]) >= target:
				continue
			var best := -1
			var best_distance := INF
			for index in provinces.size():
				if provinces[index].owner_faction != Balance.Faction.NEUTRAL:
					continue
				var touches := false
				for neighbor_index: int in adjacency[index]:
					if provinces[neighbor_index].owner_faction == faction:
						touches = true
						break
				if not touches:
					continue
				var distance_to_capital := provinces[index].map_position.distance_to(capitals[faction])
				if distance_to_capital < best_distance:
					best_distance = distance_to_capital
					best = index
			if best >= 0:
				provinces[best].owner_faction = faction
				counts[faction] = int(counts[faction]) + 1
				progress = true


# --- Geometry --------------------------------------------------------------

## Outline of one province in coordinates local to its map position.
## Only the province's own cells are touched (its bounding box), never the
## whole grid, and thin 1-2 cell appendages are opened away first so borders
## do not end in needles.
@warning_ignore("integer_division")
func _province_polygon(origin: Vector2, cells: Array) -> PackedVector2Array:
	if cells.is_empty():
		return PackedVector2Array()

	var min_x := _grid_w
	var min_y := _grid_h
	var max_x := 0
	var max_y := 0
	for raw_cell in cells:
		var cell := int(raw_cell)
		var cx := cell % _grid_w
		var cy := cell / _grid_w
		min_x = mini(min_x, cx)
		min_y = mini(min_y, cy)
		max_x = maxi(max_x, cx)
		max_y = maxi(max_y, cy)

	var width := max_x - min_x + 1
	var height := max_y - min_y + 1
	var mask := PackedByteArray()
	mask.resize(width * height)
	mask.fill(0)
	for raw_cell in cells:
		var cell := int(raw_cell)
		var cx := cell % _grid_w - min_x
		var cy := cell / _grid_w - min_y
		mask[cy * width + cx] = 1

	mask = _open_mask(mask, width, height)

	var bitmap := BitMap.new()
	bitmap.create(Vector2i(width, height))
	for y in height:
		for x in width:
			if mask[y * width + x] == 1:
				bitmap.set_bitv(Vector2i(x, y), true)

	var outlines := bitmap.opaque_to_polygons(Rect2i(0, 0, width, height), 1.1)
	var best := PackedVector2Array()
	var best_area := 0.0
	for outline in outlines:
		var area := absf(_signed_area(outline))
		if area > best_area:
			best_area = area
			best = outline
	if best.size() < 3:
		return PackedVector2Array()

	var scaled := PackedVector2Array()
	for point in best:
		scaled.append((point + Vector2(min_x, min_y)) * float(CELL))

	var smooth := _chaikin_closed(scaled, 3)
	if Geometry2D.triangulate_polygon(smooth).is_empty():
		smooth = scaled

	var local := PackedVector2Array()
	for point in smooth:
		local.append(point - origin)
	return local


## Binary opening (erode then dilate with an 8-neighbour element): removes
## appendages up to two cells wide while leaving the province body untouched.
func _open_mask(mask: PackedByteArray, width: int, height: int) -> PackedByteArray:
	if width < 3 or height < 3:
		return mask

	var eroded := PackedByteArray()
	eroded.resize(width * height)
	eroded.fill(0)
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var index := y * width + x
			if mask[index] == 0:
				continue
			var keep := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if mask[(y + dy) * width + x + dx] == 0:
						keep = false
						break
				if not keep:
					break
			if keep:
				eroded[index] = 1

	var opened := PackedByteArray()
	opened.resize(width * height)
	opened.fill(0)
	var any := false
	for y in height:
		for x in width:
			if eroded[y * width + x] == 0:
				continue
			any = true
			for dy in range(-1, 2):
				var ny := y + dy
				if ny < 0 or ny >= height:
					continue
				for dx in range(-1, 2):
					var nx := x + dx
					if nx < 0 or nx >= width:
						continue
					var target := ny * width + nx
					if mask[target] == 1:
						opened[target] = 1

	# A province that is entirely a thin strip keeps its raw shape.
	if not any:
		return mask
	return opened


func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	var count := polygon.size()
	for index in count:
		var a := polygon[index]
		var b := polygon[(index + 1) % count]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


func _chaikin_closed(points: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var current := points
	for _i in iterations:
		if current.size() < 3:
			return current
		var next := PackedVector2Array()
		var count := current.size()
		for index in count:
			var a := current[index]
			var b := current[(index + 1) % count]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		current = next
	return current


func _chaikin_open(points: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var current := points
	for _i in iterations:
		if current.size() < 3:
			return current
		var next := PackedVector2Array([current[0]])
		for index in range(current.size() - 1):
			var a := current[index]
			var b := current[index + 1]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		next.append(current[current.size() - 1])
		current = next
	return current


## Elevation (R), moisture (G), temperature (B) and distance from the sea cell
## to the nearest land (A, normalised over COAST_FADE_PX) packed for the shaders.
## The alpha channel is filled by one multi-source BFS starting at every sea
## cell touching land, after _keep_main_land() has removed stray islands.
func _build_field_image() -> Image:
	var total := _grid_w * _grid_h
	var distances := PackedInt32Array()
	distances.resize(total)
	distances.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(total)
	var head := 0
	var tail := 0
	for index in total:
		if _elev[index] >= SEA_LEVEL:
			continue
		for side in 4:
			var neighbor: int = _nbr4[index * 4 + side]
			if neighbor < 0 or _elev[neighbor] < SEA_LEVEL or distances[neighbor] != -1:
				continue
			distances[neighbor] = 1
			queue[tail] = neighbor
			tail += 1
	var max_steps := int(ceil(COAST_FADE_PX / float(CELL)))
	while head < tail:
		var index: int = queue[head]
		head += 1
		if distances[index] >= max_steps:
			continue
		for side in 4:
			var neighbor: int = _nbr4[index * 4 + side]
			if neighbor < 0 or _elev[neighbor] >= SEA_LEVEL or distances[neighbor] != -1:
				continue
			distances[neighbor] = distances[index] + 1
			queue[tail] = neighbor
			tail += 1

	var floats := PackedFloat32Array()
	floats.resize(total * 4)
	for index in total:
		var base := index * 4
		floats[base] = _elev[index]
		floats[base + 1] = _moist[index]
		floats[base + 2] = _temp[index]
		var steps: int = distances[index]
		# Land keeps alpha 0 so the water shader stays transparent there. Sea
		# cells the BFS never reached are isolated pockets with no land neighbour;
		# they must read as fully offshore (alpha 1), not as zero-distance coast
		# (which paints a solid foam wedge over them).
		if _elev[index] >= SEA_LEVEL:
			floats[base + 3] = 0.0
		else:
			floats[base + 3] = minf(float(steps) * CELL / COAST_FADE_PX, 1.0) if steps > 0 else 1.0
	floats = _blur_coast_alpha(floats)
	return Image.create_from_data(_grid_w, _grid_h, false, Image.FORMAT_RGBAF, floats.to_byte_array())


## Softens the quantised coast-distance alpha with a sea-only Gaussian. Land
## texels are excluded from the weights, so the land mask stays exact and the
## first sea cell keeps its distance instead of being dragged towards zero.
func _blur_coast_alpha(floats: PackedFloat32Array) -> PackedFloat32Array:
	var total := _grid_w * _grid_h
	var alpha := PackedFloat32Array()
	alpha.resize(total)
	for index in total:
		alpha[index] = floats[index * 4 + 3]
	var smoothed := alpha.duplicate()
	for y in _grid_h:
		for x in _grid_w:
			var index := y * _grid_w + x
			if _elev[index] >= SEA_LEVEL or alpha[index] >= 0.5:
				continue
			var sum := 0.0
			var weight := 0.0
			for oy in range(-2, 3):
				var ny := y + oy
				if ny < 0 or ny >= _grid_h:
					continue
				for ox in range(-2, 3):
					var nx := x + ox
					if nx < 0 or nx >= _grid_w:
						continue
					var neighbor := ny * _grid_w + nx
					if _elev[neighbor] >= SEA_LEVEL:
						continue
					var w := float(COAST_BLUR_KERNEL[oy + 2][ox + 2])
					sum += alpha[neighbor] * w
					weight += w
			if weight > 0.0:
				smoothed[index] = sum / weight
	for index in total:
		floats[index * 4 + 3] = smoothed[index]
	return floats
