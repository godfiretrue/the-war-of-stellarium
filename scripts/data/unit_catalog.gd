class_name UnitCatalog
extends RefCounted
## Builds and caches UnitType instances from Balance.UNIT_DEFS.
##
## The catalog is the single place that turns tuning data into UnitType
## objects, so every system sees the same stats.

static var _cache: Dictionary = {}


static func get_unit(unit_id: String) -> UnitType:
	_ensure_cache()
	var unit: UnitType = _cache.get(unit_id, null)
	if unit == null:
		push_warning("UnitCatalog: unknown unit id '%s'" % unit_id)
	return unit


static func has_unit(unit_id: String) -> bool:
	_ensure_cache()
	return _cache.has(unit_id)


static func all_unit_ids() -> Array[String]:
	_ensure_cache()
	var ids: Array[String] = []
	for key: String in _cache.keys():
		ids.append(key)
	ids.sort()
	return ids


static func units_for_faction(faction: int) -> Array[String]:
	_ensure_cache()
	var ids: Array[String] = []
	for unit_id: String in _cache.keys():
		var unit: UnitType = _cache[unit_id]
		if unit.faction == faction:
			ids.append(unit_id)
	# Cheapest first: that is the order the HUD shows recruit buttons in.
	ids.sort_custom(func(a: String, b: String) -> bool:
		var unit_a: UnitType = _cache[a]
		var unit_b: UnitType = _cache[b]
		if unit_a.gold_cost == unit_b.gold_cost:
			return a < b
		return unit_a.gold_cost < unit_b.gold_cost
	)
	return ids


static func _ensure_cache() -> void:
	if not _cache.is_empty():
		return
	for unit_id: String in Balance.UNIT_DEFS.keys():
		var data: Dictionary = Balance.UNIT_DEFS[unit_id]
		var unit := UnitType.new()
		unit.id = unit_id
		unit.display_name = String(data.get("display_name", unit_id))
		unit.faction = int(data.get("faction", Balance.Faction.NEUTRAL))
		unit.attack = int(data.get("attack", 0))
		unit.defense = int(data.get("defense", 0))
		unit.gold_cost = int(data.get("gold_cost", 0))
		unit.manpower_cost = int(data.get("manpower_cost", 0))
		unit.upkeep = int(data.get("upkeep", 0))
		_cache[unit_id] = unit
