class_name MapState
extends Resource
## The whole map: province graph plus the handful of globals the turn loop
## needs. Serializable and free of node references.

@export var provinces: Array[ProvinceData] = []
@export var turn_number: int = 1
@export var active_faction: int = Balance.Faction.HUMANS

## Render-only data produced by WorldGenerator (rebuilt from the seed, never
## saved): the seed itself is what saves store.
var map_seed: int = 0
## 1.0 is the reference world (21 provinces); 2.0 is the large campaign map.
## Saves store it so a world is always rebuilt at the size it was created.
var world_scale: float = 1.0
var rivers: Array[PackedVector2Array] = []
## Drawing width in pixels for each river, parallel to `rivers`.
var river_widths: PackedFloat32Array = PackedFloat32Array()
var field_image: Image
var grid_size: Vector2i = Vector2i.ZERO
var cell_size: int = 3
var label_grid: PackedInt32Array = PackedInt32Array()
var label_ids: PackedStringArray = PackedStringArray()


## Province under a world-space point, or "" over sea / off the map.
func province_id_at(point: Vector2) -> String:
	if label_grid.is_empty():
		return ""
	var cell_x := int(floor(point.x / float(cell_size)))
	var cell_y := int(floor(point.y / float(cell_size)))
	if cell_x < 0 or cell_y < 0 or cell_x >= grid_size.x or cell_y >= grid_size.y:
		return ""
	var label := label_grid[cell_y * grid_size.x + cell_x]
	if label < 0 or label >= label_ids.size():
		return ""
	return label_ids[label]


func province_count() -> int:
	return provinces.size()


func get_province(province_id: String) -> ProvinceData:
	for province in provinces:
		if province.id == province_id:
			return province
	return null


func has_province(province_id: String) -> bool:
	return get_province(province_id) != null


func are_adjacent(from_id: String, to_id: String) -> bool:
	var province := get_province(from_id)
	var target := get_province(to_id)
	if province == null or target == null:
		return false
	# Peaks have no edges after generation, but guard here too so a hand-edited
	# map can never sneak a march through one.
	if province.is_impassable or target.is_impassable:
		return false
	return province.neighbors.has(to_id)


func neighbors_of(province_id: String) -> Array[ProvinceData]:
	var result: Array[ProvinceData] = []
	var province := get_province(province_id)
	if province == null or province.is_impassable:
		return result
	for neighbor_id: String in province.neighbors:
		var neighbor := get_province(neighbor_id)
		if neighbor != null and not neighbor.is_impassable:
			result.append(neighbor)
	return result


func provinces_owned_by(faction: int) -> Array[ProvinceData]:
	var result: Array[ProvinceData] = []
	for province in provinces:
		if province.is_owned_by(faction):
			result.append(province)
	return result


func controlled_province_count(faction: int) -> int:
	var total := 0
	for province in provinces:
		if province.is_owned_by(faction):
			total += 1
	return total


## Impassable peaks are scenery: nobody can own them, so they are excluded from
## the victory threshold.
func passable_province_count() -> int:
	var total := 0
	for province in provinces:
		if not province.is_impassable:
			total += 1
	return total


func capital_of(faction: int) -> ProvinceData:
	for province in provinces:
		if province.is_capital and province.capital_of == faction:
			return province
	return null


func factions_with_provinces() -> Array[int]:
	var factions: Array[int] = []
	for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
		if controlled_province_count(faction) > 0:
			factions.append(faction)
	return factions


func is_eliminated(faction: int) -> bool:
	return controlled_province_count(faction) == 0


## Returns the faction that owns every province, or NEUTRAL when the game is
## still running.
func winning_faction() -> int:
	if provinces.is_empty():
		return Balance.Faction.NEUTRAL
	var target := passable_province_count()
	if target <= 0:
		return Balance.Faction.NEUTRAL
	for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
		if controlled_province_count(faction) == target:
			return faction
	return Balance.Faction.NEUTRAL


## Consistency check for the province graph. Returns human readable problems;
## an empty array means the graph is sound.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for province in provinces:
		if province.id.is_empty():
			problems.append("province with empty id")
			continue
		if seen.has(province.id):
			problems.append("duplicate province id '%s'" % province.id)
		seen[province.id] = true

	for province in provinces:
		if province.is_impassable and not province.neighbors.is_empty():
			problems.append("impassable peak %s still has neighbours" % province.id)
		for neighbor_id: String in province.neighbors:
			var neighbor := get_province(neighbor_id)
			if neighbor == null:
				problems.append("%s lists unknown neighbour '%s'" % [province.id, neighbor_id])
				continue
			if neighbor_id == province.id:
				problems.append("%s lists itself as a neighbour" % province.id)
				continue
			if neighbor.is_impassable:
				problems.append("%s borders impassable peak %s" % [province.id, neighbor_id])
			if not neighbor.neighbors.has(province.id):
				problems.append("asymmetric edge %s -> %s" % [province.id, neighbor_id])

	# Every passable province must still be reachable; a peak may be scenery,
	# but it must never split the playable continent in two.
	var passable: Array[ProvinceData] = []
	for province in provinces:
		if not province.is_impassable:
			passable.append(province)
	if not passable.is_empty():
		var reachable: Dictionary = {passable[0].id: true}
		var queue: Array[String] = [passable[0].id]
		var head := 0
		while head < queue.size():
			for neighbor in neighbors_of(queue[head]):
				if reachable.has(neighbor.id):
					continue
				reachable[neighbor.id] = true
				queue.append(neighbor.id)
			head += 1
		if reachable.size() != passable.size():
			problems.append("passable province graph is not connected")

	if capital_of(Balance.Faction.HUMANS) == null:
		problems.append("Humans have no capital")
	if capital_of(Balance.Faction.ELVES) == null:
		problems.append("Elves have no capital")

	return problems
