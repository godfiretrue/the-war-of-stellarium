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
@export var is_city: bool = false
## A fortress is a role on top of the terrain: it adds a flat defence bonus and
## costs gold every turn. Generated from the seed, never stored in a save.
@export var is_fortress: bool = false
## The highest mountain provinces are impassable: worldgen removes every edge
## touching them, so no order can march into or out of a peak.
@export var is_impassable: bool = false
## True while this province's garrison lies in ambush. Hidden from enemy
## intelligence until an enemy army enters or the order is cancelled.
@export var ambush: bool = false
@export var territory_type: String = "Wilderness"
@export var capital_of: int = Balance.Faction.NEUTRAL
@export var neighbors: PackedStringArray = PackedStringArray()
@export var resource_type: String = ""
@export var resource_per_turn: int = 0
@export var map_position: Vector2 = Vector2.ZERO
@export var polygon: PackedVector2Array = PackedVector2Array()

## unit_id -> troop count
@export var garrison: Dictionary = {}

## Defensive militia raised in this province. It never marches, adds no
## upkeep and is lost when the province changes hands.
@export var home_guard: int = 0

## Turns of conquest unrest left: while positive the province produces no
## income and cannot recruit. Set on capture, counted down each resolution.
@export var unrest_turns: int = 0


func is_neutral() -> bool:
	return owner_faction == Balance.Faction.NEUTRAL


## Important positions can hide a garrison: cities, fortresses, and defensive
## ground (Highlands, mountains and forests). Peaks are unreachable anyway.
func is_ambush_ground() -> bool:
	if is_impassable:
		return false
	return is_city or is_fortress or Balance.can_ambush_terrain(terrain)


## An ambush needs troops to hide and a position worth hiding them in.
func can_ambush() -> bool:
	return not ambush and is_ambush_ground() and total_troops() > 0


func is_owned_by(faction: int) -> bool:
	return owner_faction == faction


func total_troops() -> int:
	var total := 0
	for unit_id: String in garrison.keys():
		total += int(garrison[unit_id])
	return total


## Militia cap for this province: capitals hold a larger levy.
func home_guard_cap() -> int:
	if not Balance.HOME_GUARD_ENABLED:
		return 0
	return Balance.HOME_GUARD_CAPITAL_MAX if is_capital else Balance.HOME_GUARD_MAX


## Everything that defends the province: mobile garrison plus militia. Only the
## garrison can leave, so movement rules keep using total_troops().
func defence_troops() -> int:
	if not Balance.HOME_GUARD_ENABLED:
		return total_troops()
	return total_troops() + maxi(home_guard, 0)


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


## Base gold and manpower this province produces per turn, before the faction
## modifiers and the capital-loss penalty (both applied by GameState).
func base_income() -> Dictionary:
	var income := Balance.terrain_income(terrain)
	if is_capital:
		income["gold"] = int(income["gold"]) + Balance.CAPITAL_GOLD_BONUS
		income["manpower"] = int(income["manpower"]) + Balance.CAPITAL_MANPOWER_BONUS
	return income


## Defensive strength of the garrison and the militia before any terrain,
## fortress or siege modifier. Combat uses this so both sides go through the
## same multiplier path.
func raw_defense_power() -> float:
	var power := 0.0
	for unit_id: String in garrison.keys():
		var count := int(garrison[unit_id])
		if count <= 0:
			continue
		var unit := UnitCatalog.get_unit(unit_id)
		if unit != null:
			power += float(unit.defense) * float(count)
	if Balance.HOME_GUARD_ENABLED:
		power += float(maxi(home_guard, 0)) * Balance.HOME_GUARD_DEFENSE
	return power


## Defensive strength of the garrison and the militia, including the terrain
## and fortress multipliers.
func defense_power() -> float:
	return raw_defense_power() * Balance.defense_multiplier(terrain, is_fortress)


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
