extends SceneTree
## Headless sweep over the world generator.
##
## Run from the project folder:
##   godot --headless --path . --script res://scripts/tools/worldgen_sweep.gd
##
## The generator is procedural, so a single hand-picked map proves nothing:
## this builds a few dozen worlds and checks the invariants the rest of the
## game relies on (21 provinces, the six anchors, connected graph, polygons,
## cities, rivers). Exits with code 1 on the first broken invariant.

const SEEDS := 24
const BASE_SEED := 90210


func _initialize() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var rivers_min := 1 << 30
	var rivers_max := 0
	var cities_min := 1 << 30
	var cities_max := 0
	var slowest := 0
	var terrain_counts := {}
	for terrain: int in Balance.TERRAIN_NAMES.keys():
		terrain_counts[terrain] = 0

	var generator := WorldGenerator.new()
	for index in SEEDS:
		var seed_value := BASE_SEED + index * 7919
		var started := Time.get_ticks_msec()
		var state := generator.build(seed_value)
		var elapsed := Time.get_ticks_msec() - started
		slowest = maxi(slowest, elapsed)

		if state == null:
			failures.append("seed %d: generator returned null" % seed_value)
			continue

		var context := "seed %d" % seed_value

		if state.province_count() != WorldGenerator.TARGET_PROVINCES:
			failures.append("%s: %d provinces" % [context, state.province_count()])

		for anchor in generator.anchors():
			if not state.has_province(String(anchor["id"])):
				failures.append("%s: missing anchor %s" % [context, anchor["id"]])
				continue
			var anchored := state.get_province(String(anchor["id"]))
			if anchored.terrain != int(anchor["terrain"]):
				failures.append("%s: anchor %s has terrain %d, expected %d" % [
					context, anchor["id"], anchored.terrain, int(anchor["terrain"]),
				])
			if bool(anchor.get("fortress", false)) and not anchored.is_fortress:
				failures.append("%s: anchor %s should be a fortress" % [
					context, anchor["id"],
				])

		var cities := 0
		for province in state.provinces:
			if not Balance.TERRAIN_NAMES.has(province.terrain):
				failures.append("%s: %s has invalid terrain %d" % [
					context, province.id, province.terrain,
				])
			else:
				terrain_counts[province.terrain] = int(terrain_counts[province.terrain]) + 1
			if province.is_fortress and not province.is_city:
				failures.append("%s: %s is a fortress but not a city" % [context, province.id])
			if province.is_city:
				cities += 1
			if province.polygon.size() < 3:
				failures.append("%s: %s has an empty polygon" % [context, province.id])
			if province.neighbors.is_empty():
				failures.append("%s: %s has no neighbours" % [context, province.id])
		cities_min = mini(cities_min, cities)
		cities_max = maxi(cities_max, cities)
		if cities != 10:
			failures.append("%s: %d cities, expected 10" % [context, cities])

		if not _is_connected(state):
			failures.append("%s: province graph is not connected" % context)

		var river_count := state.rivers.size()
		rivers_min = mini(rivers_min, river_count)
		rivers_max = maxi(rivers_max, river_count)
		if river_count < 6:
			failures.append("%s: only %d rivers" % [context, river_count])

		for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
			if state.provinces_owned_by(faction).size() < 3:
				failures.append("%s: %s owns too little land" % [
					context, Balance.faction_name(faction),
				])

	print("[sweep] %d worlds, rivers %d-%d, cities %d-%d, slowest %d ms" % [
		SEEDS, rivers_min, rivers_max, cities_min, cities_max, slowest,
	])
	var terrain_parts: PackedStringArray = PackedStringArray()
	for terrain: int in Balance.TERRAIN_NAMES.keys():
		terrain_parts.append("%s %d" % [
			Balance.terrain_name(terrain), int(terrain_counts[terrain]),
		])
	print("[sweep] terrain distribution: %s" % ", ".join(terrain_parts))
	if failures.is_empty():
		print("[sweep] OK")
		quit(0)
		return

	for failure in failures:
		printerr("[sweep] %s" % failure)
	quit(1)


## Every province must be reachable from the first one through land borders.
func _is_connected(state: MapState) -> bool:
	if state.provinces.is_empty():
		return false
	var seen := {state.provinces[0].id: true}
	var queue: Array[String] = [state.provinces[0].id]
	var head := 0
	while head < queue.size():
		var province := state.get_province(queue[head])
		head += 1
		if province == null:
			continue
		for neighbor_id: String in province.neighbors:
			if seen.has(neighbor_id):
				continue
			seen[neighbor_id] = true
			queue.append(neighbor_id)
	return seen.size() == state.provinces.size()
