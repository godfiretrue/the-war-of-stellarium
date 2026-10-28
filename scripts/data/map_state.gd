class_name MapState
extends Resource
## The whole map: province graph plus the handful of globals the turn loop
## needs. Serializable and free of node references.

@export var provinces: Array[ProvinceData] = []
@export var turn_number: int = 1
@export var active_faction: int = Balance.Faction.HUMANS


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
	if province == null:
		return false
	return province.neighbors.has(to_id)


func neighbors_of(province_id: String) -> Array[ProvinceData]:
	var result: Array[ProvinceData] = []
	var province := get_province(province_id)
	if province == null:
		return result
	for neighbor_id: String in province.neighbors:
		var neighbor := get_province(neighbor_id)
		if neighbor != null:
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
	for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
		if controlled_province_count(faction) == provinces.size():
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
		for neighbor_id: String in province.neighbors:
			var neighbor := get_province(neighbor_id)
			if neighbor == null:
				problems.append("%s lists unknown neighbour '%s'" % [province.id, neighbor_id])
				continue
			if neighbor_id == province.id:
				problems.append("%s lists itself as a neighbour" % province.id)
				continue
			if not neighbor.neighbors.has(province.id):
				problems.append("asymmetric edge %s -> %s" % [province.id, neighbor_id])

	if capital_of(Balance.Faction.HUMANS) == null:
		problems.append("Humans have no capital")
	if capital_of(Balance.Faction.ELVES) == null:
		problems.append("Elves have no capital")

	return problems
