class_name GameState
extends Node
## Authoritative game data: the map plus every faction's stockpiles.
##
## Autoloaded as "Game". Views read through getters; systems mutate through
## the action methods. Nothing here touches nodes or scenes, so the whole
## game can be saved or simulated headlessly.

signal state_changed
signal battle_resolved(result: Dictionary)

var map_state: MapState
var gold: Dictionary = {}
var manpower: Dictionary = {}
var faction_resources: Dictionary = {}
var last_battle: Dictionary = {}

## Provinces that already attacked this round; one attack per province per
## round keeps battles decisive instead of grinding a defender down in a turn.
var acted_provinces: Dictionary = {}

## When true, actions and turns do not print. Used by headless balance runs.
var quiet: bool = false


func factions() -> Array[int]:
	return [Balance.Faction.HUMANS, Balance.Faction.ELVES]


func is_started() -> bool:
	return map_state != null


func start_new_game() -> void:
	map_state = MapFactory.create_default_map()
	gold.clear()
	manpower.clear()
	faction_resources.clear()
	last_battle.clear()
	acted_provinces.clear()

	for faction: int in factions():
		gold[faction] = Balance.STARTING_GOLD
		manpower[faction] = Balance.STARTING_MANPOWER
		faction_resources[faction] = {"aether": 0, "iron": 0}

	state_changed.emit()


# --- Stockpiles ----------------------------------------------------------

func get_gold(faction: int) -> int:
	return int(gold.get(faction, 0))


func get_manpower(faction: int) -> int:
	return int(manpower.get(faction, 0))


func get_resource(faction: int, key: String) -> int:
	var stock: Dictionary = faction_resources.get(faction, {})
	return int(stock.get(key, 0))


## The single faction resource this faction banks (Humans: Aether, Elves: Iron).
func faction_resource_key(faction: int) -> String:
	if faction == Balance.Faction.HUMANS:
		return Balance.terrain_resource(Balance.Terrain.PLAINS)
	if faction == Balance.Faction.ELVES:
		return Balance.terrain_resource(Balance.Terrain.MOUNTAINS)
	return ""


# --- Economy -------------------------------------------------------------

## What this faction would gain at the next resolution step.
func income_for(faction: int) -> Dictionary:
	var gold_income := 0
	var manpower_income := 0
	var resource_key := faction_resource_key(faction)
	var resource_income := 0

	if map_state != null:
		for province in map_state.provinces_owned_by(faction):
			gold_income += Balance.PROVINCE_GOLD_INCOME
			manpower_income += Balance.PROVINCE_MANPOWER_INCOME
			if province.is_capital:
				gold_income += Balance.CAPITAL_GOLD_BONUS
				manpower_income += Balance.CAPITAL_MANPOWER_BONUS
			if province.resource_type == resource_key:
				resource_income += province.resource_per_turn

	gold_income = int(round(gold_income * Balance.modifier(faction, "gold", 1.0)))
	manpower_income = int(round(manpower_income * Balance.modifier(faction, "manpower", 1.0)))

	var resources := {}
	if not resource_key.is_empty():
		resources[resource_key] = resource_income

	return {
		"gold": gold_income,
		"manpower": manpower_income,
		"resources": resources,
	}


## Gold due per turn for one province's garrison.
## upkeep = average unit cost / divisor * troops ^ exponent
func province_upkeep(province: ProvinceData) -> int:
	var troops := province.total_troops()
	if troops <= 0:
		return 0

	var cost_sum := 0
	for unit_id: String in province.garrison.keys():
		var unit := UnitCatalog.get_unit(unit_id)
		if unit == null:
			continue
		cost_sum += unit.gold_cost * int(province.garrison[unit_id])

	var average_cost := float(cost_sum) / float(troops)
	var growth := pow(float(troops), Balance.UPKEEP_EXPONENT)
	return int(ceil(average_cost / Balance.UPKEEP_COST_DIVISOR * growth))


func upkeep_for(faction: int) -> int:
	var total := 0
	if map_state == null:
		return 0
	for province in map_state.provinces_owned_by(faction):
		total += province_upkeep(province)
	return total


func apply_income(faction: int) -> Dictionary:
	var income := income_for(faction)
	gold[faction] = get_gold(faction) + int(income["gold"])
	manpower[faction] = get_manpower(faction) + int(income["manpower"])

	var resources: Dictionary = income["resources"]
	for key: String in resources.keys():
		var stock: Dictionary = faction_resources.get(faction, {})
		stock[key] = int(stock.get(key, 0)) + int(resources[key])
		faction_resources[faction] = stock

	state_changed.emit()
	return income


## Pays as much upkeep as the treasury allows. Prototype rule: debt is not
## modelled, unpaid upkeep is simply not charged.
func apply_upkeep(faction: int) -> int:
	var due := upkeep_for(faction)
	var available := get_gold(faction)
	var paid: int = mini(due, available)
	gold[faction] = available - paid
	state_changed.emit()
	return paid


## Called by the turn manager between rounds.
func clear_acted_provinces() -> void:
	acted_provinces.clear()


func can_afford(faction: int, gold_cost: int, manpower_cost: int) -> bool:
	return get_gold(faction) >= gold_cost and get_manpower(faction) >= manpower_cost


func spend(faction: int, gold_cost: int, manpower_cost: int) -> bool:
	if not can_afford(faction, gold_cost, manpower_cost):
		return false
	gold[faction] = get_gold(faction) - gold_cost
	manpower[faction] = get_manpower(faction) - manpower_cost
	state_changed.emit()
	return true


# --- Actions (shared by the player and the bot) --------------------------

## Recruits units into an owned province. Returns {ok, reason, ...}.
func recruit(faction: int, province_id: String, unit_id: String, count: int = 1) -> Dictionary:
	if map_state == null:
		return _fail("no game in progress")

	var province := map_state.get_province(province_id)
	if province == null:
		return _fail("unknown province")
	if not province.is_owned_by(faction):
		return _fail("%s is not yours" % province.display_name)

	var unit := UnitCatalog.get_unit(unit_id)
	if unit == null:
		return _fail("unknown unit")
	if unit.faction != faction:
		return _fail("%s cannot recruit %s" % [Balance.faction_name(faction), unit.display_name])
	if count <= 0:
		return _fail("recruit count must be positive")

	var costs := unit.costs_for(faction)
	var total_gold := int(costs["gold"]) * count
	var total_manpower := int(costs["manpower"]) * count
	if not can_afford(faction, total_gold, total_manpower):
		return _fail("need %d gold and %d manpower" % [total_gold, total_manpower])

	spend(faction, total_gold, total_manpower)
	province.add_units(unit_id, count)
	state_changed.emit()
	_log("[action] %s recruits %d %s in %s (-%dg, -%dmp)" % [
		Balance.faction_name(faction), count, unit.display_name, province.display_name,
		total_gold, total_manpower,
	])
	return {
		"ok": true,
		"kind": "recruit",
		"province": province_id,
		"unit_id": unit_id,
		"count": count,
		"gold": total_gold,
		"manpower": total_manpower,
	}


## Moves troops between adjacent provinces, resolving combat when the target
## is held by the enemy. moves is unit_id -> count.
func move(faction: int, from_id: String, to_id: String, moves: Dictionary) -> Dictionary:
	if map_state == null:
		return _fail("no game in progress")

	var origin := map_state.get_province(from_id)
	var target := map_state.get_province(to_id)
	if origin == null or target == null:
		return _fail("unknown province")
	if not origin.is_owned_by(faction):
		return _fail("%s is not yours" % origin.display_name)
	if from_id == to_id:
		return _fail("origin and target are the same province")
	if not map_state.are_adjacent(from_id, to_id):
		return _fail("%s does not border %s" % [origin.display_name, target.display_name])

	var moving: Dictionary = {}
	var moving_total := 0
	for unit_id: String in moves.keys():
		var count := int(moves[unit_id])
		if count <= 0:
			continue
		if int(origin.garrison.get(unit_id, 0)) < count:
			return _fail("not enough %s in %s" % [unit_id, origin.display_name])
		moving[unit_id] = count
		moving_total += count

	if moving_total <= 0:
		return _fail("no troops selected")

	var hostile := not target.is_owned_by(faction) and target.total_troops() > 0
	if hostile and acted_provinces.has(from_id):
		return _fail("%s has already attacked this round" % origin.display_name)

	for unit_id: String in moving.keys():
		origin.remove_units(unit_id, int(moving[unit_id]))

	# Friendly province, or any province with no garrison: a plain march.
	if not hostile:
		if not target.is_owned_by(faction):
			target.owner_faction = faction
		for unit_id: String in moving.keys():
			target.add_units(unit_id, int(moving[unit_id]))
		state_changed.emit()
		_log("[action] %s moves %d troops %s -> %s" % [
			Balance.faction_name(faction), moving_total, origin.display_name, target.display_name,
		])
		return {
			"ok": true,
			"kind": "move",
			"from": from_id,
			"to": to_id,
			"troops": moving_total,
		}

	# Defended province: battle.
	var result := CombatResolver.resolve(moving, target, faction)
	result["from"] = from_id
	result["to"] = to_id

	var survivors: Dictionary = result["attacker_survivors"]
	if bool(result["captured"]):
		target.owner_faction = faction
		for unit_id: String in survivors.keys():
			target.add_units(unit_id, int(survivors[unit_id]))
	else:
		for unit_id: String in survivors.keys():
			origin.add_units(unit_id, int(survivors[unit_id]))

	last_battle = result
	acted_provinces[from_id] = true
	state_changed.emit()
	battle_resolved.emit(result)
	_log("[battle] %s -> %s: attack %.1f vs defence %.1f | losses %d/%d | %s" % [
		origin.display_name, target.display_name,
		float(result["attacker_power"]), float(result["defender_power"]),
		int(result["attacker_losses"]), int(result["defender_losses"]),
		"CAPTURED" if bool(result["captured"]) else "held",
	])
	return result


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _log(message: String) -> void:
	if not quiet:
		print(message)
