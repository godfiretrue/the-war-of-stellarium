class_name ProvinceData
extends Resource
## One territory on the map: ownership, garrison, terrain and neighbours.
##
## This is pure data. It never stores node references, so it can be saved,
## duplicated and handed to the AI without leaking scene state.

@export var id: String = ""
@export var display_name: String = ""
@export var terrain: int = Balance.Terrain.PLAINS
@export var owner_faction: int = Balance.Faction.NEUTRAL
@export var is_capital: bool = false
@export var capital_of: int = Balance.Faction.NEUTRAL
@export var neighbors: PackedStringArray = PackedStringArray()
@export var resource_type: String = ""
@export var resource_per_turn: int = 0
@export var map_position: Vector2 = Vector2.ZERO

## unit_id -> troop count
@export var garrison: Dictionary = {}


func is_neutral() -> bool:
	return owner_faction == Balance.Faction.NEUTRAL


func is_owned_by(faction: int) -> bool:
	return owner_faction == faction


func total_troops() -> int:
	var total := 0
	for unit_id: String in garrison.keys():
		total += int(garrison[unit_id])
	return total


## Raw offensive strength of the garrison, before terrain and randomness.
func attack_power() -> float:
	var power := 0.0
	for unit_id: String in garrison.keys():
		var count := int(garrison[unit_id])
		if count <= 0:
			continue
		var unit := UnitCatalog.get_unit(unit_id)
		if unit != null:
			power += float(unit.attack) * float(count)
	return power


## Defensive strength of the garrison, including the terrain multiplier.
func defense_power() -> float:
	var power := 0.0
	for unit_id: String in garrison.keys():
		var count := int(garrison[unit_id])
		if count <= 0:
			continue
		var unit := UnitCatalog.get_unit(unit_id)
		if unit != null:
			power += float(unit.defense) * float(count)
	return power * Balance.terrain_defense(terrain)


func add_units(unit_id: String, count: int) -> void:
	if count <= 0:
		return
	garrison[unit_id] = int(garrison.get(unit_id, 0)) + count


## Removes up to count troops of one type and returns how many were removed.
func remove_units(unit_id: String, count: int) -> int:
	var current := int(garrison.get(unit_id, 0))
	var removed: int = mini(current, count)
	if removed <= 0:
		return 0
	var left := current - removed
	if left <= 0:
		garrison.erase(unit_id)
	else:
		garrison[unit_id] = left
	return removed


## Removes up to count troops, spread over the garrison, and returns the
## removed troops as a unit_id -> count dictionary (used by combat losses).
func remove_troops(total_losses: int) -> Dictionary:
	var removed: Dictionary = {}
	var remaining: int = maxi(total_losses, 0)
	for unit_id: String in garrison.keys():
		if remaining <= 0:
			break
		var taken := remove_units(unit_id, remaining)
		if taken > 0:
			removed[unit_id] = taken
			remaining -= taken
	return removed


func clear_garrison() -> void:
	garrison.clear()


func garrison_summary() -> String:
	if garrison.is_empty():
		return "empty"
	var parts: PackedStringArray = PackedStringArray()
	for unit_id: String in garrison.keys():
		var count := int(garrison[unit_id])
		if count <= 0:
			continue
		var unit := UnitCatalog.get_unit(unit_id)
		var label := unit.display_name if unit != null else unit_id
		parts.append("%d %s" % [count, label])
	return ", ".join(parts)


func neighbor_ids() -> Array[String]:
	var ids: Array[String] = []
	for neighbor_id: String in neighbors:
		ids.append(neighbor_id)
	return ids
