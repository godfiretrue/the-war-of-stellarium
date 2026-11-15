class_name MapFactory
extends RefCounted
## Builds the Stellarium continental world map.
##
## Features 18 contiguous provinces forming a complete fantasy continent:
## - Western Realm (Humans): Aldermere Capital, Stonewatch Keep, and 4 rural/frontier territories.
## - Central Borderlands (Neutral): Iron Pass Fortress, Oakhaven Town, and 4 wild valleys/forests.
## - Eastern Realm (Elves): Ysolde Capital, Silverglen, Dawnwatch Spire, and 3 sacred groves/ridges.
##
## Seamless Voronoi polygon generation ensures all territories touch at shared borders (Total War style).

static func create_default_map() -> MapState:
	var state := MapState.new()
	state.provinces.clear()

	var defs := _province_defs()
	for definition: Dictionary in defs:
		var province := ProvinceData.new()
		province.id = String(definition["id"])
		province.display_name = String(definition["name"])
		province.terrain = int(definition["terrain"])
		province.owner_faction = int(definition["owner"])
		province.is_capital = bool(definition.get("capital", false))
		province.is_city = bool(definition.get("is_city", true))
		province.territory_type = String(definition.get("type", "Territory"))
		province.capital_of = province.owner_faction if province.is_capital else Balance.Faction.NEUTRAL
		province.map_position = definition["position"]
		province.resource_type = Balance.terrain_resource(province.terrain)
		province.resource_per_turn = Balance.FACTION_RESOURCE_PER_TURN

		for neighbor_id: String in definition["neighbors"]:
			province.neighbors.append(neighbor_id)

		state.provinces.append(province)

	# Generate contiguous tiling polygons (Voronoi partitioning of the continent)
	compute_contiguous_polygons(state.provinces)
	state.coastline = organic_coastline()

	_apply_starting_armies(state)

	for problem: String in state.validate():
		push_error("MapFactory: %s" % problem)

	return state


static func _apply_starting_armies(state: MapState) -> void:
	for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
		var unit_id := String(Balance.STARTING_UNIT[faction])

		var capital := state.capital_of(faction)
		if capital != null:
			capital.add_units(unit_id, Balance.CAPITAL_STARTING_TROOPS)

		# Second starting army goes to the faction's primary secondary city/fortress
		for province in state.provinces:
			if province.is_owned_by(faction) and province.is_city and not province.is_capital:
				province.add_units(unit_id, Balance.SECOND_PROVINCE_STARTING_TROOPS)
				break


# --- Contiguous Continental Polygon Generation ---------------------------

static func compute_contiguous_polygons(provinces: Array[ProvinceData]) -> void:
	var continent := _continent_outline()

	for i in provinces.size():
		var p_i := provinces[i]
		var poly := continent

		for j in provinces.size():
			if i == j:
				continue
			var p_j := provinces[j]
			var mid := (p_i.map_position + p_j.map_position) * 0.5
			var norm := (p_j.map_position - p_i.map_position).normalized()
			poly = _clip_polygon_halfplane(poly, mid, norm)

		# Roughen borders and coast. The warp is a function of position only,
		# so two provinces sharing a border still share it exactly.
		poly = organic_polygon(poly, continent)

		# Store polygon in local coordinates relative to province.map_position
		var local_poly := PackedVector2Array()
		for pt in poly:
			local_poly.append(pt - p_i.map_position)
		p_i.polygon = local_poly


## Continental perimeter boundary of Stellarium (before roughening).
static func _continent_outline() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(120, 50),
		Vector2(330, 38),
		Vector2(500, 52),
		Vector2(690, 40),
		Vector2(850, 55),
		Vector2(1040, 90),
		Vector2(1075, 240),
		Vector2(1040, 420),
		Vector2(880, 490),
		Vector2(700, 480),
		Vector2(550, 505),
		Vector2(400, 485),
		Vector2(250, 495),
		Vector2(80, 430),
		Vector2(50, 270),
		Vector2(70, 140),
	])


static func organic_coastline() -> PackedVector2Array:
	var continent := _continent_outline()
	return organic_polygon(continent, continent)


const WARP_STEP := 12.0


## Subdivides every edge and displaces each point with smooth noise.
## Points lying on the continent outline get an extra, larger displacement
## (bays and headlands).
static func organic_polygon(poly: PackedVector2Array, continent: PackedVector2Array) -> PackedVector2Array:
	var broad := FastNoiseLite.new()
	broad.seed = 11
	broad.frequency = 0.018
	var fine := FastNoiseLite.new()
	fine.seed = 23
	fine.frequency = 0.07
	var coast := FastNoiseLite.new()
	coast.seed = 5
	coast.frequency = 0.010

	var result := PackedVector2Array()
	var count := poly.size()
	for index in count:
		var a := poly[index]
		var b := poly[(index + 1) % count]
		var steps := maxi(int(ceil(a.distance_to(b) / WARP_STEP)), 1)
		for step in steps:
			var point := a.lerp(b, float(step) / float(steps))
			result.append(_warp_point(point, continent, broad, fine, coast))
	return result


static func _warp_point(point: Vector2, continent: PackedVector2Array, broad: FastNoiseLite, fine: FastNoiseLite, coast: FastNoiseLite) -> Vector2:
	var offset := Vector2(
		broad.get_noise_2d(point.x, point.y) * 8.0 + fine.get_noise_2d(point.x, point.y) * 2.5,
		broad.get_noise_2d(point.x + 713.0, point.y + 291.0) * 8.0 + fine.get_noise_2d(point.x + 713.0, point.y + 291.0) * 2.5,
	)
	if _distance_to_outline(point, continent) < 0.75:
		offset += Vector2(
			coast.get_noise_2d(point.x, point.y) * 15.0,
			coast.get_noise_2d(point.x + 401.0, point.y + 977.0) * 15.0,
		)
	return point + offset


static func _distance_to_outline(point: Vector2, outline: PackedVector2Array) -> float:
	var best := INF
	var count := outline.size()
	for index in count:
		var closest := Geometry2D.get_closest_point_to_segment(point, outline[index], outline[(index + 1) % count])
		best = minf(best, point.distance_to(closest))
	return best


static func _clip_polygon_halfplane(poly: PackedVector2Array, plane_point: Vector2, plane_normal: Vector2) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	var output := PackedVector2Array()
	var prev_pt := poly[poly.size() - 1]
	var prev_inside := (prev_pt - plane_point).dot(plane_normal) <= 0.0

	for pt in poly:
		var curr_inside := (pt - plane_point).dot(plane_normal) <= 0.0
		if curr_inside:
			if not prev_inside:
				var dir := pt - prev_pt
				var denom := dir.dot(plane_normal)
				if absf(denom) > 0.0001:
					var t := (plane_point - prev_pt).dot(plane_normal) / denom
					output.append(prev_pt + dir * t)
			output.append(pt)
		elif prev_inside:
			var dir := pt - prev_pt
			var denom := dir.dot(plane_normal)
			if absf(denom) > 0.0001:
				var t := (plane_point - prev_pt).dot(plane_normal) / denom
				output.append(prev_pt + dir * t)
		prev_pt = pt
		prev_inside = curr_inside
	return output


# --- Province Definitions ------------------------------------------------

static func _province_defs() -> Array[Dictionary]:
	return [
		# --- Western Realm (Humans) ---
		{
			"id": "gryphon_roost",
			"name": "Gryphon Roost",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.HUMANS,
			"capital": false,
			"is_city": false,
			"type": "Highlands",
			"position": Vector2(160, 130),
			"neighbors": ["stonewatch", "sunwell_marches", "whisperwoods"],
		},
		{
			"id": "stonewatch",
			"name": "Stonewatch",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.HUMANS,
			"capital": false,
			"is_city": true,
			"type": "Fortress",
			"position": Vector2(320, 130),
			"neighbors": ["gryphon_roost", "sunwell_marches", "iron_pass", "whisperwoods"],
		},
		{
			"id": "aldermere",
			"name": "Aldermere",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.HUMANS,
			"capital": true,
			"is_city": true,
			"type": "Capital Port",
			"position": Vector2(160, 270),
			"neighbors": ["sunwell_marches", "aether_plains", "southmere_coast"],
		},
		{
			"id": "sunwell_marches",
			"name": "Sunwell Marches",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.HUMANS,
			"capital": false,
			"is_city": false,
			"type": "Farmlands",
			"position": Vector2(320, 270),
			"neighbors": ["aldermere", "stonewatch", "gryphon_roost", "aether_plains", "verdant_reach"],
		},
		{
			"id": "southmere_coast",
			"name": "Southmere Coast",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.HUMANS,
			"capital": false,
			"is_city": false,
			"type": "Coastline",
			"position": Vector2(160, 410),
			"neighbors": ["aldermere", "aether_plains", "thornvale_basin"],
		},
		{
			"id": "aether_plains",
			"name": "Aether Plains",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.HUMANS,
			"capital": false,
			"is_city": false,
			"type": "Frontier",
			"position": Vector2(320, 410),
			"neighbors": ["aldermere", "sunwell_marches", "southmere_coast", "verdant_reach", "thornvale_basin"],
		},

		# --- Central Borderlands (Neutral) ---
		{
			"id": "whisperwoods",
			"name": "The Whisperwoods",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.NEUTRAL,
			"capital": false,
			"is_city": false,
			"type": "Deep Forest",
			"position": Vector2(480, 120),
			"neighbors": ["gryphon_roost", "stonewatch", "iron_pass", "dawnwatch_spire", "ruins_of_eldoria"],
		},
		{
			"id": "iron_pass",
			"name": "Iron Pass",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.NEUTRAL,
			"capital": false,
			"is_city": true,
			"type": "Fortress Pass",
			"position": Vector2(480, 230),
			"neighbors": ["stonewatch", "whisperwoods", "verdant_reach", "ruins_of_eldoria"],
		},
		{
			"id": "verdant_reach",
			"name": "Verdant Reach",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.NEUTRAL,
			"capital": false,
			"is_city": false,
			"type": "Crossroads",
			"position": Vector2(480, 340),
			"neighbors": ["sunwell_marches", "aether_plains", "iron_pass", "thornvale_basin", "oakhaven"],
		},
		{
			"id": "thornvale_basin",
			"name": "Thornvale Basin",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.NEUTRAL,
			"capital": false,
			"is_city": false,
			"type": "Wild Valley",
			"position": Vector2(480, 440),
			"neighbors": ["southmere_coast", "aether_plains", "verdant_reach", "oakhaven", "cinderwood_shore"],
		},
		{
			"id": "ruins_of_eldoria",
			"name": "Ruins of Eldoria",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.NEUTRAL,
			"capital": false,
			"is_city": false,
			"type": "Ancient Ruins",
			"position": Vector2(650, 160),
			"neighbors": ["whisperwoods", "iron_pass", "dawnwatch_spire", "moonlit_ridge", "oakhaven", "starlight_vale"],
		},
		{
			"id": "oakhaven",
			"name": "Oakhaven",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.NEUTRAL,
			"capital": false,
			"is_city": true,
			"type": "River Town",
			"position": Vector2(650, 340),
			"neighbors": ["verdant_reach", "thornvale_basin", "ruins_of_eldoria", "silverglen", "starlight_vale", "cinderwood_shore"],
		},

		# --- Eastern Realm (Elves) ---
		{
			"id": "dawnwatch_spire",
			"name": "Dawnwatch Spire",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.ELVES,
			"capital": false,
			"is_city": true,
			"type": "Elven Spire",
			"position": Vector2(810, 120),
			"neighbors": ["whisperwoods", "ruins_of_eldoria", "moonlit_ridge"],
		},
		{
			"id": "moonlit_ridge",
			"name": "Moonlit Ridge",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.ELVES,
			"capital": false,
			"is_city": false,
			"type": "Iron Ridge",
			"position": Vector2(950, 140),
			"neighbors": ["dawnwatch_spire", "ruins_of_eldoria", "starlight_vale", "ysolde"],
		},
		{
			"id": "starlight_vale",
			"name": "Starlight Vale",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.ELVES,
			"capital": false,
			"is_city": false,
			"type": "Sacred Glade",
			"position": Vector2(810, 250),
			"neighbors": ["ruins_of_eldoria", "oakhaven", "moonlit_ridge", "silverglen", "ysolde"],
		},
		{
			"id": "ysolde",
			"name": "Ysolde",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.ELVES,
			"capital": true,
			"is_city": true,
			"type": "Capital Citadel",
			"position": Vector2(960, 270),
			"neighbors": ["moonlit_ridge", "starlight_vale", "silverglen", "cinderwood_shore"],
		},
		{
			"id": "silverglen",
			"name": "Silverglen",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.ELVES,
			"capital": false,
			"is_city": true,
			"type": "Garden City",
			"position": Vector2(810, 400),
			"neighbors": ["oakhaven", "starlight_vale", "ysolde", "cinderwood_shore"],
		},
		{
			"id": "cinderwood_shore",
			"name": "Cinderwood Shore",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.ELVES,
			"capital": false,
			"is_city": false,
			"type": "Forest Coast",
			"position": Vector2(960, 420),
			"neighbors": ["thornvale_basin", "oakhaven", "silverglen", "ysolde"],
		},
	]
