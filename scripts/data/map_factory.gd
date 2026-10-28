class_name MapFactory
extends RefCounted
## Builds the prototype's fixed seven province map.
##
## The layout is data: edit PROVINCE_DEFS to reshape the map. IDs are stable
## and used by saves, so renaming one invalidates old saves.

static func create_default_map() -> MapState:
	var state := MapState.new()
	state.provinces.clear()

	for definition: Dictionary in _province_defs():
		var province := ProvinceData.new()
		province.id = String(definition["id"])
		province.display_name = String(definition["name"])
		province.terrain = int(definition["terrain"])
		province.owner_faction = int(definition["owner"])
		province.is_capital = bool(definition.get("capital", false))
		province.capital_of = province.owner_faction if province.is_capital else Balance.Faction.NEUTRAL
		province.map_position = definition["position"]
		province.resource_type = Balance.terrain_resource(province.terrain)
		province.resource_per_turn = Balance.FACTION_RESOURCE_PER_TURN

		for neighbor_id: String in definition["neighbors"]:
			province.neighbors.append(neighbor_id)

		state.provinces.append(province)

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

		for province in state.provinces:
			if province.is_owned_by(faction) and not province.is_capital:
				province.add_units(unit_id, Balance.SECOND_PROVINCE_STARTING_TROOPS)
				break


static func _province_defs() -> Array[Dictionary]:
	return [
		{
			"id": "aldermere",
			"name": "Aldermere",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.HUMANS,
			"capital": true,
			"position": Vector2(200, 300),
			"neighbors": ["stonewatch", "verdant_reach"],
		},
		{
			"id": "stonewatch",
			"name": "Stonewatch",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.HUMANS,
			"capital": false,
			"position": Vector2(300, 130),
			"neighbors": ["aldermere", "iron_pass"],
		},
		{
			"id": "verdant_reach",
			"name": "Verdant Reach",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.NEUTRAL,
			"capital": false,
			"position": Vector2(470, 300),
			"neighbors": ["aldermere", "silverglen", "iron_pass"],
		},
		{
			"id": "iron_pass",
			"name": "Iron Pass",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.NEUTRAL,
			"capital": false,
			"position": Vector2(600, 165),
			"neighbors": ["stonewatch", "verdant_reach", "thornvale"],
		},
		{
			"id": "thornvale",
			"name": "Thornvale",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.NEUTRAL,
			"capital": false,
			"position": Vector2(700, 400),
			"neighbors": ["iron_pass", "silverglen", "ysolde"],
		},
		{
			"id": "silverglen",
			"name": "Silverglen",
			"terrain": Balance.Terrain.PLAINS,
			"owner": Balance.Faction.ELVES,
			"capital": false,
			"position": Vector2(840, 290),
			"neighbors": ["verdant_reach", "thornvale", "ysolde"],
		},
		{
			"id": "ysolde",
			"name": "Ysolde",
			"terrain": Balance.Terrain.MOUNTAINS,
			"owner": Balance.Faction.ELVES,
			"capital": true,
			"position": Vector2(940, 430),
			"neighbors": ["silverglen", "thornvale"],
		},
	]
