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

const CELL := 3
const GRID_W := 384
const GRID_H := 216
const SEA_LEVEL := 0.40
const MOUNTAIN_LEVEL := 0.70
const TARGET_PROVINCES := 21
const MIN_SEED_DISTANCE := 88.0
const MAX_ATTEMPTS := 12

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

var _elev := PackedFloat32Array()
var _moist := PackedFloat32Array()
var _river := PackedByteArray()
var _label := PackedInt32Array()
var _seed_cells := PackedInt32Array()
var _rivers: Array[PackedVector2Array] = []

## Precomputed neighbour indices (-1 when off-grid). Order of the 8-table:
## row above (left, mid, right), same row (left, right), row below (l, m, r);
## so indices 0, 2, 5 and 7 are the diagonals.
var _nbr4 := PackedInt32Array()
var _nbr8 := PackedInt32Array()


func build(world_seed: int) -> MapState:
	var started := Time.get_ticks_msec()
	_build_neighbor_tables()
	for attempt in MAX_ATTEMPTS:
		var state := _try_build(world_seed + attempt * 7919)
		if state != null:
			state.map_seed = world_seed
			print("[worldgen] seed %d ready in %d ms (attempt %d)" % [world_seed, Time.get_ticks_msec() - started, attempt + 1])
			return state
	push_error("WorldGenerator: no valid continent for seed %d" % world_seed)
	return null


func _build_neighbor_tables() -> void:
	if not _nbr8.is_empty():
		return
	var total := GRID_W * GRID_H
	_nbr4.resize(total * 4)
	_nbr8.resize(total * 8)
	for y in GRID_H:
		for x in GRID_W:
			var index := y * GRID_W + x
			var k4 := 0
			var k8 := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := x + dx
					var ny := y + dy
					var value := -1
					if nx >= 0 and ny >= 0 and nx < GRID_W and ny < GRID_H:
						value = ny * GRID_W + nx
					_nbr8[index * 8 + k8] = value
					k8 += 1
					if dx == 0 or dy == 0:
						_nbr4[index * 4 + k4] = value
						k4 += 1


# --- Anchors ---------------------------------------------------------------

## The only hand-placed content: the places the story needs to exist.
func _make_anchors() -> Array[Dictionary]:
	var list: Array[Dictionary] = [
		{"id": "aldermere", "name": "Aldermere", "pos": Vector2(180, 300), "mountain": false,
			"owner": Balance.Faction.HUMANS, "capital": true, "type": "Capital Port"},
		{"id": "stonewatch", "name": "Stonewatch", "pos": Vector2(335, 150), "mountain": true,
			"owner": Balance.Faction.HUMANS, "capital": false, "type": "Fortress"},
		{"id": "iron_pass", "name": "Iron Pass", "pos": Vector2(540, 255), "mountain": true,
			"owner": Balance.Faction.NEUTRAL, "capital": false, "type": "Fortress Pass"},
		{"id": "oakhaven", "name": "Oakhaven", "pos": Vector2(700, 365), "mountain": false,
			"owner": Balance.Faction.NEUTRAL, "capital": false, "type": "River Town"},
		{"id": "dawnwatch_spire", "name": "Dawnwatch Spire", "pos": Vector2(830, 135), "mountain": true,
			"owner": Balance.Faction.ELVES, "capital": false, "type": "Elven Spire"},
		{"id": "ysolde", "name": "Ysolde", "pos": Vector2(960, 295), "mountain": true,
			"owner": Balance.Faction.ELVES, "capital": true, "type": "Capital Citadel"},
	]
	return list


# --- Pipeline --------------------------------------------------------------

func _try_build(world_seed: int) -> MapState:
	_seed = world_seed
	_rng.seed = world_seed
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
	var warp := _noise(_seed + 1, 0.006, FastNoiseLite.FRACTAL_FBM, 3)
	var base := _noise(_seed + 2, 0.0075, FastNoiseLite.FRACTAL_FBM, 5)
	var ridge := _noise(_seed + 3, 0.011, FastNoiseLite.FRACTAL_RIDGED, 4)
	var belt := _noise(_seed + 4, 0.0045, FastNoiseLite.FRACTAL_FBM, 2)
	var wet := _noise(_seed + 5, 0.008, FastNoiseLite.FRACTAL_FBM, 4)

	var total := GRID_W * GRID_H
	_elev.resize(total)
	_moist.resize(total)

	for y in GRID_H:
		for x in GRID_W:
			var px := (float(x) + 0.5) * CELL
			var py := (float(y) + 0.5) * CELL
			var wx := px + warp.get_noise_2d(px, py) * 75.0
			var wy := py + warp.get_noise_2d(px + 517.0, py + 211.0) * 75.0
			var nx := (wx - 576.0) / 575.0
			var ny := (wy - 286.0) / 240.0
			var dist := sqrt(nx * nx + ny * ny)
			var mask := clampf(1.0 - pow(dist, 3.0), 0.0, 1.0)
			# Keep open sea under the top and bottom HUD bars.
			mask *= smoothstep(46.0, 100.0, py) * smoothstep(526.0, 472.0, py)

			var low := base.get_noise_2d(px, py) * 0.5 + 0.5
			var crest := clampf(ridge.get_noise_2d(px, py) * 0.5 + 0.5, 0.0, 1.0)
			var tectonic := smoothstep(0.48, 0.72, belt.get_noise_2d(px, py) * 0.5 + 0.5)

			var e := 0.18 + mask * 0.42 + (low - 0.5) * 0.28
			e += pow(crest, 1.8) * tectonic * 0.46 * mask

			var m := 0.15 + 0.6 * (wet.get_noise_2d(px, py) * 0.5 + 0.5) + 0.3 * (1.0 - mask)
			m -= 0.22 * smoothstep(0.62, 0.82, e)

			var index := y * GRID_W + x
			_elev[index] = e
			_moist[index] = clampf(m, 0.0, 1.0)

	_apply_anchor_terrain(ridge)


## Bends the terrain around each anchor so it has the terrain it is meant to.
func _apply_anchor_terrain(ridge: FastNoiseLite) -> void:
	var radius := 82.0
	for anchor in _anchors:
		var center: Vector2 = anchor["pos"]
		var wants_mountain: bool = anchor["mountain"]
		var min_x := maxi(int((center.x - radius) / CELL), 0)
		var max_x := mini(int((center.x + radius) / CELL), GRID_W - 1)
		var min_y := maxi(int((center.y - radius) / CELL), 0)
		var max_y := mini(int((center.y + radius) / CELL), GRID_H - 1)
		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				var point := Vector2((float(x) + 0.5) * CELL, (float(y) + 0.5) * CELL)
				var weight := smoothstep(radius, radius * 0.35, point.distance_to(center))
				if weight <= 0.0:
					continue
				var index := y * GRID_W + x
				if wants_mountain:
					var crest := clampf(ridge.get_noise_2d(point.x, point.y) * 0.5 + 0.5, 0.0, 1.0)
					var target := 0.76 + 0.12 * crest
					_elev[index] = lerpf(_elev[index], target, weight * 0.9)
					_moist[index] = lerpf(_moist[index], 0.30, weight * 0.5)
				else:
					_elev[index] = lerpf(_elev[index], 0.54, weight * 0.85)
					_moist[index] = lerpf(_moist[index], 0.50, weight * 0.5)


func _cell_of(point: Vector2) -> int:
	var x := clampi(int(point.x / CELL), 0, GRID_W - 1)
	var y := clampi(int(point.y / CELL), 0, GRID_H - 1)
	return y * GRID_W + x


@warning_ignore("integer_division")
func _neighbors(index: int, diagonal: bool) -> Array[int]:
	var result: Array[int] = []
	var x := index % GRID_W
	var y := index / GRID_W
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if not diagonal and dx != 0 and dy != 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= GRID_W or ny >= GRID_H:
				continue
			result.append(ny * GRID_W + nx)
	return result


## Keeps the landmass that holds every anchor; everything else becomes sea.
func _keep_main_land() -> bool:
	var total := GRID_W * GRID_H
	var component := PackedInt32Array()
	component.resize(total)
	component.fill(-1)
	var next_id := 0

	for start in total:
		if component[start] != -1 or _elev[start] < SEA_LEVEL:
			continue
		var stack: Array[int] = [start]
		component[start] = next_id
		while not stack.is_empty():
			var current: int = stack.pop_back()
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

func _trace_rivers() -> void:
	var total := GRID_W * GRID_H
	_river.resize(total)
	_river.fill(0)

	var candidates: Array[int] = []
	for index in total:
		if _elev[index] > 0.68 and _elev[index] < 0.86:
			candidates.append(index)
	_shuffle(candidates)

	var sources: Array[int] = []
	for index in candidates:
		if sources.size() >= 9:
			break
		var point := _cell_point(index)
		var far_enough := true
		for other in sources:
			if _cell_point(other).distance_to(point) < 75.0:
				far_enough = false
				break
		if far_enough:
			sources.append(index)

	for source in sources:
		_trace_one_river(source)

	# Rivers make their banks greener.
	for index in total:
		if _river[index] == 0:
			continue
		for k in 8:
			var neighbor := _nbr8[index * 8 + k]
			if neighbor >= 0:
				_moist[neighbor] = minf(_moist[neighbor] + 0.05, 1.0)


func _trace_one_river(source: int) -> void:
	var path: Array[int] = []
	var visited: Dictionary = {}
	var current := source
	var rising := 0
	var reached := false

	for _step in 700:
		path.append(current)
		visited[current] = true
		if _elev[current] < SEA_LEVEL:
			reached = true
			break
		if _river[current] == 1 and path.size() > 1:
			reached = true
			break

		var best := -1
		var best_elev := 9.0
		for k in 8:
			var neighbor := _nbr8[current * 8 + k]
			if neighbor < 0 or visited.has(neighbor):
				continue
			if _elev[neighbor] < best_elev:
				best_elev = _elev[neighbor]
				best = neighbor
		if best == -1:
			break
		if best_elev > _elev[current]:
			rising += 1
			if rising > 3:
				break
		else:
			rising = 0
		current = best

	if not reached or path.size() < 35:
		return

	# Reject rivers that wander in circles instead of heading for the sea.
	var straight := _cell_point(path[0]).distance_to(_cell_point(path[path.size() - 1]))
	if straight * 1.8 < float(path.size()) * float(CELL):
		return

	var points := PackedVector2Array()
	for index in path:
		if _elev[index] >= SEA_LEVEL:
			_river[index] = 1
		points.append(_cell_point(index))
	_rivers.append(_chaikin_open(points, 2))


func _cell_point(index: int) -> Vector2:
	return Vector2(float(index % GRID_W) + 0.5, float(index / GRID_W) + 0.5) * float(CELL)


func _shuffle(values: Array[int]) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[other]
		values[other] = held


# --- Provinces -------------------------------------------------------------

func _grow_provinces() -> bool:
	var total := GRID_W * GRID_H
	_seed_cells = PackedInt32Array()

	for anchor in _anchors:
		var cell := _cell_of(anchor["pos"])
		if _elev[cell] < SEA_LEVEL:
			return false
		_seed_cells.append(cell)

	var tries := 0
	while _seed_cells.size() < TARGET_PROVINCES and tries < 8000:
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

	if _seed_cells.size() < 14:
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

	var buckets: Array = [[]]
	for seed_index in _seed_cells.size():
		var cell := _seed_cells[seed_index]
		distance[cell] = 0
		_label[cell] = seed_index
		(buckets[0] as Array).append(cell)

	var level := 0
	while level < buckets.size():
		var bucket: Array = buckets[level]
		for index: int in bucket:
			if distance[index] != level:
				continue
			var owner_label := _label[index]
			var x := index % GRID_W
			var y := index / GRID_W
			for neighbor in _neighbors(index, true):
				var step_cost := cost[neighbor]
				if step_cost < 0:
					continue
				var diagonal := (neighbor % GRID_W) != x and (neighbor / GRID_W) != y
				var step := float(step_cost) * (1.414 if diagonal else 1.0) * multiplier[owner_label]
				var new_distance := level + maxi(int(step), 1)
				if new_distance < distance[neighbor]:
					distance[neighbor] = new_distance
					_label[neighbor] = owner_label
					while buckets.size() <= new_distance:
						buckets.append([])
					(buckets[new_distance] as Array).append(neighbor)
		buckets[level] = []
		level += 1

	for index in total:
		if _elev[index] >= SEA_LEVEL and _label[index] < 0:
			return false
	return true


func _assemble_state() -> MapState:
	var count := _seed_cells.size()
	var total := GRID_W * GRID_H

	# Per-province statistics and adjacency.
	var cells_of: Array = []
	for _i in count:
		cells_of.append(PackedInt32Array())
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

	var edge_counts: Dictionary = {}
	for index in total:
		var label := _label[index]
		if label < 0:
			continue
		(cells_of[label] as PackedInt32Array).append(index)
		sum_elev[label] += _elev[index]
		sum_moist[label] += _moist[index]
		if _elev[index] > MOUNTAIN_LEVEL:
			mountain_cells[label] += 1
		if _river[index] == 1:
			river_cells[label] += 1

		var is_coast := false
		for neighbor in _neighbors(index, false):
			var other := _label[neighbor]
			if other < 0:
				is_coast = true
			elif other != label and neighbor > index:
				var key := "%d|%d" % [mini(label, other), maxi(label, other)]
				edge_counts[key] = int(edge_counts.get(key, 0)) + 1
		if is_coast:
			coast_cells[label] += 1

	var adjacency: Array = []
	for _i in count:
		adjacency.append([])
	for key: String in edge_counts.keys():
		if int(edge_counts[key]) < 3:
			continue
		var parts := key.split("|")
		var a := int(parts[0])
		var b := int(parts[1])
		(adjacency[a] as Array).append(b)
		(adjacency[b] as Array).append(a)

	var centers := _visual_centers(count)

	# Classification, naming and cities.
	var used_names: Dictionary = {}
	for anchor in _anchors:
		used_names[String(anchor["name"])] = true

	var provinces: Array[ProvinceData] = []
	for index in count:
		var cell_count := maxi((cells_of[index] as PackedInt32Array).size(), 1)
		var mean_elev := sum_elev[index] / float(cell_count)
		var mean_moist := sum_moist[index] / float(cell_count)
		var mountain_fraction := float(mountain_cells[index]) / float(cell_count)
		var coast_fraction := float(coast_cells[index]) / float(cell_count)

		var province := ProvinceData.new()
		province.map_position = _cell_point(centers[index])
		province.resource_per_turn = Balance.FACTION_RESOURCE_PER_TURN

		var kind := "plains"
		if mountain_fraction > 0.30 or mean_elev > 0.72:
			kind = "mountain"
		elif mean_moist > 0.60:
			kind = "forest"
		elif coast_fraction > 0.22:
			kind = "coast"

		if index < _anchors.size():
			var anchor: Dictionary = _anchors[index]
			province.id = String(anchor["id"])
			province.display_name = String(anchor["name"])
			province.is_capital = bool(anchor["capital"])
			province.is_city = true
			province.owner_faction = int(anchor["owner"])
			province.territory_type = String(anchor["type"])
			kind = "mountain" if bool(anchor["mountain"]) else "plains"
			if province.territory_type == "River Town" and river_cells[index] == 0:
				province.territory_type = "Market Town"
		else:
			province.owner_faction = Balance.Faction.NEUTRAL
			province.territory_type = _type_for(kind, coast_fraction, river_cells[index])
			province.display_name = _unique_name(kind, used_names)
			province.id = province.display_name.to_lower().replace(" ", "_")

		province.terrain = Balance.Terrain.MOUNTAINS if kind == "mountain" else Balance.Terrain.PLAINS
		province.resource_type = Balance.terrain_resource(province.terrain)
		province.capital_of = province.owner_faction if province.is_capital else Balance.Faction.NEUTRAL
		provinces.append(province)

	_designate_cities(provinces, adjacency, coast_cells, river_cells, cells_of)
	_distribute_ownership(provinces, adjacency)

	for index in count:
		for neighbor_index: int in adjacency[index]:
			provinces[index].neighbors.append(provinces[neighbor_index].id)
		provinces[index].polygon = _province_polygon(index, provinces[index].map_position)

	var state := MapState.new()
	state.provinces.clear()
	for province in provinces:
		state.provinces.append(province)
	state.grid_size = Vector2i(GRID_W, GRID_H)
	state.cell_size = CELL
	state.label_grid = _label.duplicate()
	var ids := PackedStringArray()
	for province in provinces:
		ids.append(province.id)
	state.label_ids = ids
	state.rivers = _rivers.duplicate()
	state.field_image = _build_field_image()
	return state


## Cell farthest from the province border: a good place for the label.
func _visual_centers(count: int) -> PackedInt32Array:
	var total := GRID_W * GRID_H
	var depth := PackedInt32Array()
	depth.resize(total)
	depth.fill(-1)

	var queue: Array[int] = []
	for index in total:
		if _label[index] < 0:
			continue
		for neighbor in _neighbors(index, false):
			if _label[neighbor] != _label[index]:
				depth[index] = 0
				queue.append(index)
				break

	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for neighbor in _neighbors(current, false):
			if _label[neighbor] == _label[current] and depth[neighbor] < 0:
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
func _designate_cities(provinces: Array[ProvinceData], adjacency: Array, coast_cells: PackedInt32Array, river_cells: PackedInt32Array, cells_of: Array) -> void:
	var scored: Array[Dictionary] = []
	for index in provinces.size():
		if index < _anchors.size():
			continue
		var province := provinces[index]
		var score := _rng.randf() * 0.4
		if province.terrain == Balance.Terrain.PLAINS:
			score += 1.0
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
	for entry in scored:
		if added >= 4:
			break
		var index: int = entry["index"]
		var too_close := false
		for city in city_indices:
			if city == index or (adjacency[index] as Array).has(city):
				too_close = true
				break
		if too_close:
			continue
		var province := provinces[index]
		province.is_city = true
		if province.terrain == Balance.Terrain.MOUNTAINS:
			province.territory_type = "Fortress"
		elif river_cells[index] > 5:
			province.territory_type = "River Town"
		elif coast_cells[index] > 8:
			province.territory_type = "Port Town"
		else:
			province.territory_type = "Market Town"
		city_indices.append(index)
		added += 1


## Gives each faction a connected block of provinces around its capital.
func _distribute_ownership(provinces: Array[ProvinceData], adjacency: Array) -> void:
	var target := clampi(int(round(float(provinces.size()) * 0.3)), 5, 8)
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
func _province_polygon(label: int, origin: Vector2) -> PackedVector2Array:
	var bitmap := BitMap.new()
	bitmap.create(Vector2i(GRID_W, GRID_H))
	for index in GRID_W * GRID_H:
		if _label[index] == label:
			bitmap.set_bitv(Vector2i(index % GRID_W, index / GRID_W), true)

	var outlines := bitmap.opaque_to_polygons(Rect2i(0, 0, GRID_W, GRID_H), 1.1)
	var best := PackedVector2Array()
	var best_area := 0.0
	for outline in outlines:
		var area := absf(_signed_area(outline))
		if area > best_area:
			best_area = area
			best = outline

	var scaled := PackedVector2Array()
	for point in best:
		scaled.append(point * float(CELL))

	var smooth := _chaikin_closed(scaled, 2)
	if Geometry2D.triangulate_polygon(smooth).is_empty():
		smooth = scaled

	var local := PackedVector2Array()
	for point in smooth:
		local.append(point - origin)
	return local


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


## Elevation (R) and moisture (G) packed for the terrain shader.
func _build_field_image() -> Image:
	var floats := PackedFloat32Array()
	floats.resize(GRID_W * GRID_H * 2)
	for index in GRID_W * GRID_H:
		floats[index * 2] = _elev[index]
		floats[index * 2 + 1] = _moist[index]
	return Image.create_from_data(GRID_W, GRID_H, false, Image.FORMAT_RGF, floats.to_byte_array())
