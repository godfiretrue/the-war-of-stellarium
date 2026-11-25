extends SceneTree
## Headless sweep over the world generator.
##
## Run from the project folder:
##   godot --headless --path . --script res://scripts/tools/worldgen_sweep.gd
##
## The generator is procedural, so a single hand-picked map proves nothing:
## this builds a few dozen worlds per world size and checks the invariants the
## rest of the game relies on (province target, the six anchors, connected
## graph, polygons, cities, rivers). Exits with code 1 on the first broken
## invariant.

const SEEDS := 24
const BASE_SEED := 90210
const SCALES := [1.0, 1.5, 2.0]


func _initialize() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var rivers_min := 1 << 30
	var rivers_max := 0
	var cities_min := 1 << 30
	var cities_max := 0
	var peaks_total := 0
	var highlands_total := 0
	var slowest := 0
	var terrain_counts := {}
	for terrain: int in Balance.TERRAIN_NAMES.keys():
		terrain_counts[terrain] = 0

	var generator := WorldGenerator.new()
	for index in SEEDS * SCALES.size():
		var scale: float = SCALES[index % SCALES.size()]
		var seed_value := BASE_SEED + (index / SCALES.size()) * 7919
		var started := Time.get_ticks_msec()
		var state := generator.build(seed_value, scale)
		var elapsed := Time.get_ticks_msec() - started
		slowest = maxi(slowest, elapsed)

		if state == null:
			failures.append("seed %d at %.1fx: generator returned null" % [seed_value, scale])
			continue

		var context := "seed %d at %.1fx" % [seed_value, scale]

		var expected_provinces := roundi(float(WorldGenerator.TARGET_PROVINCES) * scale * scale)
		if state.province_count() != expected_provinces:
			failures.append("%s: %d provinces, expected %d" % [
				context, state.province_count(), expected_provinces,
			])

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
		var peaks := 0
		var highlands := 0
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
			if province.is_impassable:
				peaks += 1
				if province.neighbors.size() > 0:
					failures.append("%s: peak %s still has neighbours" % [context, province.id])
			elif province.terrain == Balance.Terrain.HIGHLANDS:
				highlands += 1
			if province.polygon.size() < 3:
				failures.append("%s: %s has an empty polygon" % [context, province.id])
			if not province.is_impassable and province.neighbors.is_empty():
				failures.append("%s: %s has no neighbours" % [context, province.id])
		cities_min = mini(cities_min, cities)
		cities_max = maxi(cities_max, cities)
		peaks_total += peaks
		highlands_total += highlands
		if highlands == 0:
			failures.append("%s: no Highlands generated" % context)
		if peaks > Balance.PEAK_MAX_PROVINCES:
			failures.append("%s: %d impassable peaks, expected at most %d" % [
				context, peaks, Balance.PEAK_MAX_PROVINCES,
			])
		var town_target := 4 if scale <= 1.01 else roundi(8.0 * scale * scale)
		if cities != 6 + town_target:
			failures.append("%s: %d cities, expected %d" % [
				context, cities, 6 + town_target,
			])

		if not _is_connected(state):
			failures.append("%s: province graph is not connected" % context)

		var river_count := state.rivers.size()
		rivers_min = mini(rivers_min, river_count)
		rivers_max = maxi(rivers_max, river_count)
		if river_count < roundi(6.0 * scale * scale):
			failures.append("%s: only %d rivers" % [context, river_count])

		for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
			if state.provinces_owned_by(faction).size() < 3:
				failures.append("%s: %s owns too little land" % [
					context, Balance.faction_name(faction),
				])

	print("[sweep] %d worlds x %d sizes, rivers %d-%d, cities %d-%d, peaks %d, Highlands %d, slowest %d ms" % [
		SEEDS, SCALES.size(), rivers_min, rivers_max, cities_min, cities_max,
		peaks_total, highlands_total, slowest,
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


## Every passable province must be reachable. Impassable peaks are scenery and
## deliberately have no edges, so they are excluded from the connectivity count.
func _is_connected(state: MapState) -> bool:
	if state.provinces.is_empty():
		return false
	var start: ProvinceData = null
	var passable_count := 0
	for province in state.provinces:
		if not province.is_impassable:
			passable_count += 1
			if start == null:
				start = province
	if start == null:
		return false
	var seen := {start.id: true}
	var queue: Array[String] = [start.id]
	var head := 0
	while head < queue.size():
		var province := state.get_province(queue[head])
		head += 1
		if province == null:
			continue
		for neighbor in state.neighbors_of(province.id):
			if seen.has(neighbor.id):
				continue
			seen[neighbor.id] = true
			queue.append(neighbor.id)
	return seen.size() == passable_count
