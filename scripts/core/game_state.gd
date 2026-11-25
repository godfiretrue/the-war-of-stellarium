class_name GameState
extends Node
## Authoritative game data: the map plus every faction's stockpiles and the
## orders each faction has queued for the current turn.
##
## Autoloaded as "Game". Views read through getters; the turn manager calls
## queue_*() while both sides plan and resolve_turn() once, so no action is
## applied before both factions have committed. Nothing here touches nodes or
## scenes, so the whole game can be saved or simulated headlessly.

signal state_changed
signal orders_changed
signal battle_resolved(result: Dictionary)

var map_state: MapState
var gold: Dictionary = {}
var manpower: Dictionary = {}
var faction_resources: Dictionary = {}
var last_battle: Dictionary = {}

## faction -> turns of capital-loss penalty still to serve. Empty/0 means no
## penalty. Kept in the model so the HUD, bot and save all read one value.
var capital_penalty: Dictionary = {}

## faction -> {province_id: true}. Terrain the faction has ever seen; it stays
## drawn after the army moves on, but live troop counts only come from the
## current visibility set below.
var explored: Dictionary = {}

## faction -> Array of order dictionaries. Orders are data, never actions.
var queued_orders: Dictionary = {}

## When true, actions and turns do not print. Used by headless balance runs.
var quiet: bool = false


func factions() -> Array[int]:
	return [Balance.Faction.HUMANS, Balance.Faction.ELVES]


func is_started() -> bool:
	return map_state != null


# --- Fog of war ----------------------------------------------------------

## Live intelligence: own land and its neighbours. An enemy garrison lying in
## ambush is invisible even from an adjacent province, including while the
## ambush order is still only queued for this turn.
func is_province_visible(faction: int, province_id: String) -> bool:
	if map_state == null:
		return false
	var province := map_state.get_province(province_id)
	if province == null:
		return false
	if province.is_owned_by(faction):
		return true
	var adjacent := false
	for neighbor in map_state.neighbors_of(province_id):
		if neighbor.is_owned_by(faction):
			adjacent = true
			break
	if not adjacent:
		return false
	if province.ambush or _has_queued_ambush_against(faction, province_id):
		return false
	return true


func is_province_explored(faction: int, province_id: String) -> bool:
	if is_province_visible(faction, province_id):
		return true
	var seen: Dictionary = explored.get(faction, {})
	return seen.has(province_id)


## Records the terrain of everything currently in sight. Called after every
## resolution, so both factions remember the map but not each other's army.
func update_all_visibility() -> void:
	if map_state == null:
		return
	for faction: int in factions():
		var seen: Dictionary = explored.get(faction, {})
		for province in map_state.provinces:
			if _geometrically_visible(faction, province):
				seen[province.id] = true
		explored[faction] = seen


func _geometrically_visible(faction: int, province: ProvinceData) -> bool:
	if province.is_owned_by(faction):
		return true
	for neighbor in map_state.neighbors_of(province.id):
		if neighbor.is_owned_by(faction):
			return true
	return false


func _has_queued_ambush_against(viewer: int, province_id: String) -> bool:
	_ensure_queues()
	for faction: int in queued_orders.keys():
		if faction == viewer:
			continue
		for order in queued_orders[faction]:
			if String(order.get("type", "")) == "ambush" \
					and String(order.get("province_id", "")) == province_id:
				return true
	return false


## What this faction knows about a province's defence. Hidden armies read as
## zero: the enemy is entitled to act on the information it actually has.
func visible_troops(faction: int, province: ProvinceData) -> int:
	if province == null or not is_province_visible(faction, province.id):
		return 0
	return province.defence_troops()


func visible_defense_power(faction: int, province: ProvinceData) -> float:
	if province == null or not is_province_visible(faction, province.id):
		return 0.0
	return province.defense_power()


## Pass a seed to rebuild a specific world (used when loading a save);
## a negative seed rolls a new random continent.
func start_new_game(map_seed: int = -1, world_scale: float = MapFactory.DEFAULT_WORLD_SCALE) -> void:
	start_new_game_from_map(MapFactory.create_default_map(map_seed, world_scale))


## Starts a game from an already generated and finalized map. The loading
## screen generates the map on a worker thread and then hands it over here.
func start_new_game_from_map(state: MapState) -> void:
	map_state = state
	gold.clear()
	manpower.clear()
	faction_resources.clear()
	last_battle.clear()
	queued_orders.clear()
	capital_penalty.clear()
	explored.clear()

	for faction: int in factions():
		gold[faction] = Balance.STARTING_GOLD
		manpower[faction] = Balance.STARTING_MANPOWER
		faction_resources[faction] = {"aether": 0, "iron": 0}
		queued_orders[faction] = []
		explored[faction] = {}

	update_all_visibility()
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

## Turns of capital-loss penalty left for this faction, or 0.
func capital_penalty_turns(faction: int) -> int:
	if not Balance.CAPITAL_PENALTY_ENABLED:
		return 0
	return maxi(int(capital_penalty.get(faction, 0)), 0)


## Recruitment price for one unit right now, including the capital penalty.
## The HUD, the bot and queue_recruit() all read this so they never disagree.
func recruit_costs(faction: int, unit_id: String) -> Dictionary:
	var unit := UnitCatalog.get_unit(unit_id)
	if unit == null:
		return {"gold": 0, "manpower": 0}
	var costs := unit.costs_for(faction)
	var multiplier := 1.0
	if capital_penalty_turns(faction) > 0:
		multiplier += Balance.CAPITAL_RECRUIT_COST_PENALTY
	return {
		"gold": int(ceil(float(costs["gold"]) * multiplier)),
		"manpower": int(ceil(float(costs["manpower"]) * multiplier)),
	}


## What this faction would gain at the next resolution step.
func income_for(faction: int) -> Dictionary:
	var gold_income := 0
	var manpower_income := 0
	var resource_key := faction_resource_key(faction)
	var resource_income := 0

	if map_state != null:
		for province in map_state.provinces_owned_by(faction):
			if province.unrest_turns > 0:
				continue
			var base := province.base_income()
			gold_income += int(base["gold"])
			manpower_income += int(base["manpower"])
			if province.resource_type == resource_key:
				resource_income += province.resource_per_turn

	gold_income = int(round(gold_income * Balance.modifier(faction, "gold", 1.0)))
	manpower_income = int(round(manpower_income * Balance.modifier(faction, "manpower", 1.0)))

	# A lost capital taxes the whole realm for a few turns.
	if capital_penalty_turns(faction) > 0:
		var keep := 1.0 - Balance.CAPITAL_INCOME_PENALTY
		gold_income = int(round(float(gold_income) * keep))
		manpower_income = int(round(float(manpower_income) * keep))

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
		if province.is_fortress:
			total += Balance.FORTRESS_UPKEEP_GOLD
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


## End-of-turn bookkeeping that is neither income nor upkeep. Capital penalties
## and conquest unrest are advanced here too.
func advance_turn_state() -> void:
	regen_home_guards()
	decay_capital_penalties()
	decay_conquest_unrest()


## Every owned province raises HOME_GUARD_REGEN militia up to its cap. The levy
## costs no upkeep and is not part of the mobile garrison.
func regen_home_guards() -> void:
	if map_state == null:
		return
	for province in map_state.provinces:
		if not Balance.HOME_GUARD_ENABLED:
			province.home_guard = 0
			continue
		# Neutral fortresses keep the initial levy MapFactory gave them; other
		# neutral ground stays empty. Nothing regenerates for a neutral province.
		if province.is_neutral():
			if not province.is_fortress:
				province.home_guard = 0
			continue
		province.home_guard = mini(
			province.home_guard + Balance.HOME_GUARD_REGEN,
			province.home_guard_cap(),
		)


## Starts the temporary penalty for a faction whose capital changed hands.
## Called once per resolution, after the final owners are written.
func _apply_capital_losses(snapshot: Dictionary) -> void:
	if not Balance.CAPITAL_PENALTY_ENABLED:
		return
	for province in map_state.provinces:
		if not province.is_capital:
			continue
		var before := int(snapshot[province.id]["owner"])
		if before == Balance.Faction.NEUTRAL or before == province.owner_faction:
			continue
		capital_penalty[before] = Balance.CAPITAL_PENALTY_TURNS
		_log("[capital] %s loses %s; income and recruitment penalised for %d turns" % [
			Balance.faction_name(before), province.display_name, Balance.CAPITAL_PENALTY_TURNS,
		])


## Counts a penalty turn down at the end of each resolution.
func decay_capital_penalties() -> void:
	for faction: int in capital_penalty.keys():
		var left := int(capital_penalty[faction]) - 1
		capital_penalty[faction] = maxi(left, 0)


## Marks every province that changed hands this resolution as unsettled, so it
## pays no income and cannot recruit until it is pacified.
func _apply_conquest_unrest(snapshot: Dictionary) -> void:
	if not Balance.CONQUEST_UNREST_ENABLED:
		return
	for province in map_state.provinces:
		if int(snapshot[province.id]["owner"]) == province.owner_faction:
			continue
		province.unrest_turns = Balance.CONQUEST_UNREST_TURNS


## Counts unrest down after the income step, so a province captured this turn
## already misses its income before the counter drops.
func decay_conquest_unrest() -> void:
	if map_state == null:
		return
	for province in map_state.provinces:
		if province.is_neutral():
			province.unrest_turns = 0
			continue
		province.unrest_turns = maxi(province.unrest_turns - 1, 0)


func can_afford(faction: int, gold_cost: int, manpower_cost: int) -> bool:
	return get_gold(faction) >= gold_cost and get_manpower(faction) >= manpower_cost


func spend(faction: int, gold_cost: int, manpower_cost: int) -> bool:
	if not can_afford(faction, gold_cost, manpower_cost):
		return false
	gold[faction] = get_gold(faction) - gold_cost
	manpower[faction] = get_manpower(faction) - manpower_cost
	state_changed.emit()
	return true


# --- Orders (shared by the player and the bot) ---------------------------

## Queues a march/attack. Units are validated against the origin garrison
## minus anything already queued to leave it; nothing moves until resolution.
func queue_move(faction: int, from_id: String, to_id: String, units: Dictionary) -> Dictionary:
	if map_state == null:
		return _fail("no game in progress")

	var origin := map_state.get_province(from_id)
	var target := map_state.get_province(to_id)
	if origin == null or target == null:
		return _fail("unknown province")
	if not origin.is_owned_by(faction):
		return _fail("%s is not yours" % origin.display_name)
	if _has_queued_ambush(faction, from_id):
		return _fail("%s already has an ambush order this turn" % origin.display_name)
	if from_id == to_id:
		return _fail("origin and target are the same province")
	if not map_state.are_adjacent(from_id, to_id):
		return _fail("%s does not border %s" % [origin.display_name, target.display_name])

	var moving: Dictionary = {}
	var moving_total := 0
	for unit_id: String in units.keys():
		var count := int(units[unit_id])
		if count <= 0:
			continue
		if int(origin.garrison.get(unit_id, 0)) < count:
			return _fail("not enough %s in %s" % [unit_id, origin.display_name])
		moving[unit_id] = count
		moving_total += count

	if moving_total <= 0:
		return _fail("no troops selected")

	# Troops already committed to other orders from this province cannot leave
	# twice, even though the garrison itself is not mutated while planning.
	var committed := _queued_move_units(faction, from_id)
	for unit_id: String in moving.keys():
		if int(committed.get(unit_id, 0)) + int(moving[unit_id]) > int(origin.garrison.get(unit_id, 0)):
			return _fail("not enough %s in %s" % [unit_id, origin.display_name])

	var hostile := not target.is_owned_by(faction) and target.defence_troops() > 0
	if hostile and _queued_attack_count(faction, from_id) >= 1:
		return _fail("%s has already issued an attack order this turn" % origin.display_name)

	_ensure_queues()
	queued_orders[faction].append({
		"type": "move",
		"faction": faction,
		"from_id": from_id,
		"to_id": to_id,
		"units": moving.duplicate(true),
	})
	orders_changed.emit()
	_log("[order] %s queues %d troops %s -> %s (%s)" % [
		Balance.faction_name(faction), moving_total, origin.display_name, target.display_name,
		"attack" if hostile else "march",
	])
	return {
		"ok": true,
		"kind": "move",
		"from": from_id,
		"to": to_id,
		"troops": moving_total,
		"hostile": hostile,
	}


## Queues a recruitment. Gold and manpower are reserved immediately and
## refunded by cancel_order(); the units appear at the start of resolution.
func queue_recruit(faction: int, province_id: String, unit_id: String, count: int = 1) -> Dictionary:
	if map_state == null:
		return _fail("no game in progress")

	var province := map_state.get_province(province_id)
	if province == null:
		return _fail("unknown province")
	if not province.is_owned_by(faction):
		return _fail("%s is not yours" % province.display_name)
	if province.unrest_turns > 0:
		return _fail("%s is in unrest for %d more turns" % [province.display_name, province.unrest_turns])
	if _has_queued_ambush(faction, province_id):
		return _fail("%s already has an ambush order this turn" % province.display_name)
	if not province.is_city:
		return _fail("%s is an open corridor — recruitment is only allowed in cities and castles" % province.display_name)

	var unit := UnitCatalog.get_unit(unit_id)
	if unit == null:
		return _fail("unknown unit")
	if unit.faction != faction:
		return _fail("%s cannot recruit %s" % [Balance.faction_name(faction), unit.display_name])
	if count <= 0:
		return _fail("recruit count must be positive")

	var costs := recruit_costs(faction, unit_id)
	var total_gold := int(costs["gold"]) * count
	var total_manpower := int(costs["manpower"]) * count
	if not can_afford(faction, total_gold, total_manpower):
		return _fail("need %d gold and %d manpower" % [total_gold, total_manpower])

	if not spend(faction, total_gold, total_manpower):
		return _fail("need %d gold and %d manpower" % [total_gold, total_manpower])

	_ensure_queues()
	queued_orders[faction].append({
		"type": "recruit",
		"faction": faction,
		"province_id": province_id,
		"unit_id": unit_id,
		"count": count,
		"gold": total_gold,
		"manpower": total_manpower,
	})
	orders_changed.emit()
	_log("[order] %s queues %d %s in %s (-%dg, -%dmp)" % [
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


## Hides this province's whole garrison until an enemy army enters it. The
## order is queued like any other: the enemy never sees it, and it only becomes
## active when both sides have committed at resolution.
func queue_ambush(faction: int, province_id: String) -> Dictionary:
	if map_state == null:
		return _fail("no game in progress")
	var province := map_state.get_province(province_id)
	if province == null:
		return _fail("unknown province")
	if not province.is_owned_by(faction):
		return _fail("%s is not yours" % province.display_name)
	if not province.can_ambush():
		return _fail("%s cannot hide an army here" % province.display_name)
	if _has_queued_ambush(faction, province_id) or has_move_order(faction, province_id):
		return _fail("%s already has an order this turn" % province.display_name)
	_ensure_queues()
	for order in queued_orders[faction]:
		if String(order.get("type", "")) == "recruit" \
				and String(order.get("province_id", "")) == province_id:
			return _fail("%s already has an order this turn" % province.display_name)

	queued_orders[faction].append({
		"type": "ambush",
		"faction": faction,
		"province_id": province_id,
	})
	orders_changed.emit()
	_log("[order] %s queues ambush in %s" % [
		Balance.faction_name(faction), province.display_name,
	])
	return {
		"ok": true,
		"kind": "ambush",
		"province": province_id,
	}


## Removes one queued order by its index in that faction's queue. Recruits
## refund the reserved resources; moves simply stop reserving troops.
func cancel_order(faction: int, index: int) -> Dictionary:
	_ensure_queues()
	var queue: Array = queued_orders.get(faction, [])
	if index < 0 or index >= queue.size():
		return _fail("unknown order")

	var order: Dictionary = queue[index]
	if String(order.get("type", "")) == "recruit":
		# Refund exactly what was charged; a capital penalty or price change
		# must never turn a cancel into a profit or a loss.
		gold[faction] = get_gold(faction) + int(order.get("gold", 0))
		manpower[faction] = get_manpower(faction) + int(order.get("manpower", 0))

	queue.remove_at(index)
	orders_changed.emit()
	state_changed.emit()
	_log("[order] %s cancels %s" % [Balance.faction_name(faction), String(order.get("type", "order"))])
	return {"ok": true, "kind": "cancel", "order": order}


func queued_orders_for(faction: int) -> Array:
	_ensure_queues()
	var queue: Array = queued_orders.get(faction, [])
	return queue.duplicate(true)


func has_move_order(faction: int, from_id: String) -> bool:
	_ensure_queues()
	for order in queued_orders.get(faction, []):
		if String(order.get("type", "")) != "move":
			continue
		if String(order.get("from_id", "")) == from_id:
			return true
	return false


func has_ambush_order(faction: int, province_id: String) -> bool:
	return _has_queued_ambush(faction, province_id)


func has_recruit_order(faction: int, province_id: String) -> bool:
	_ensure_queues()
	for order in queued_orders.get(faction, []):
		if String(order.get("type", "")) == "recruit" \
				and String(order.get("province_id", "")) == province_id:
			return true
	return false


func has_queued_orders() -> bool:
	_ensure_queues()
	for faction: int in queued_orders.keys():
		var queue: Array = queued_orders[faction]
		if not queue.is_empty():
			return true
	return false


func clear_orders() -> void:
	_ensure_queues()
	for faction: int in queued_orders.keys():
		queued_orders[faction].clear()
	orders_changed.emit()


func _ensure_queues() -> void:
	for faction: int in factions():
		if not queued_orders.has(faction):
			queued_orders[faction] = []


func _queued_move_units(faction: int, from_id: String) -> Dictionary:
	_ensure_queues()
	var total: Dictionary = {}
	for order in queued_orders.get(faction, []):
		if String(order.get("type", "")) != "move":
			continue
		if String(order.get("from_id", "")) != from_id:
			continue
		_merge_units(total, order.get("units", {}))
	return total


func _has_queued_ambush(faction: int, province_id: String) -> bool:
	_ensure_queues()
	for order in queued_orders.get(faction, []):
		if String(order.get("type", "")) == "ambush" \
				and String(order.get("province_id", "")) == province_id:
			return true
	return false


func _queued_attack_count(faction: int, from_id: String) -> int:
	_ensure_queues()
	var count := 0
	for order in queued_orders.get(faction, []):
		if String(order.get("type", "")) != "move":
			continue
		if String(order.get("from_id", "")) != from_id:
			continue
		var target := map_state.get_province(String(order.get("to_id", "")))
		if target != null and not target.is_owned_by(faction) and target.defence_troops() > 0:
			count += 1
	return count


# --- Simultaneous resolution ---------------------------------------------

## Applies every queued order against a snapshot taken before any of them.
## Returns a summary with at least "battles", "recruits", "captures" and
## "marches". Ownership and garrisons are mutated only here.
func resolve_turn(turn_number: int = 1) -> Dictionary:
	var summary := {
		"turn": turn_number,
		"battles": [],
		"recruits": [],
		"captures": [],
		"marches": [],
	}
	if map_state == null:
		return summary

	_ensure_queues()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("stellarium:%d:%d" % [map_state.map_seed, turn_number])

	# 1. Snapshot owners, garrisons and militia before any order is applied.
	var snapshot: Dictionary = {}
	for province in map_state.provinces:
		snapshot[province.id] = {
			"owner": province.owner_faction,
			"garrison": province.garrison.duplicate(true),
			"home_guard": province.home_guard,
			"ambush": province.ambush,
		}

	# 2. Recruits appear first, so they can defend but cannot move: moves were
	# validated against the pre-recruit garrison and never list these units.
	for faction: int in _shuffled_factions(rng):
		for order in queued_orders.get(faction, []):
			if String(order.get("type", "")) != "recruit":
				continue
			var province := map_state.get_province(String(order.get("province_id", "")))
			if province == null:
				continue
			var unit_id := String(order.get("unit_id", ""))
			var count := int(order.get("count", 0))
			var snap: Dictionary = snapshot[province.id]
			var garrison: Dictionary = snap["garrison"]
			garrison[unit_id] = int(garrison.get(unit_id, 0)) + count
			summary["recruits"].append({
				"faction": faction,
				"province": province.id,
				"province_name": province.display_name,
				"unit_id": unit_id,
				"count": count,
			})
			_log("[resolve] %s recruits %d %s in %s" % [
				Balance.faction_name(faction), count, unit_id, province.display_name,
			])

	# 2b. Ambush orders become active before any battle but after the enemy has
	# already committed its moves, so nobody can react to a visible ambush.
	var ambush_orders: Dictionary = {}
	for faction in queued_orders.keys():
		for order in queued_orders[faction]:
			if String(order.get("type", "")) == "ambush":
				ambush_orders[String(order.get("province_id", ""))] = true

	# 3. Every army leaves its origin at once. `station` is the home garrison
	# after departures, and is the only defence any province can offer.
	var station: Dictionary = {}
	for province_id: String in snapshot.keys():
		var snap: Dictionary = snapshot[province_id]
		station[province_id] = (snap["garrison"] as Dictionary).duplicate(true)

	var moves: Array = []
	var departed: Dictionary = {}
	for faction: int in queued_orders.keys():
		for order in queued_orders.get(faction, []):
			if String(order.get("type", "")) != "move":
				continue
			var from_id := String(order.get("from_id", ""))
			var units: Dictionary = order.get("units", {}).duplicate(true)
			if not station.has(from_id):
				continue
			# Leaving the position ends the ambush: the hidden army is now on
			# the march and can no longer spring a trap in its old province.
			departed[from_id] = true
			var home: Dictionary = station[from_id]
			for unit_id: String in units.keys():
				var left := int(home.get(unit_id, 0)) - int(units[unit_id])
				if left <= 0:
					home.erase(unit_id)
				else:
					home[unit_id] = left
			moves.append({
				"faction": int(faction),
				"from": from_id,
				"to": String(order.get("to_id", "")),
				"units": units,
			})
			summary["marches"].append({
				"faction": int(faction),
				"from": from_id,
				"to": String(order.get("to_id", "")),
				"troops": CombatResolver.troop_count(units),
			})

	# 4. Results are accumulated here and written to the live provinces only at
	# the end, so no battle can overwrite another battle's outcome and returning
	# armies always land after every destination is known.
	var final_owner: Dictionary = {}
	var final_garrison: Dictionary = {}
	var final_home_guard: Dictionary = {}
	var final_ambush: Dictionary = {}
	for province_id: String in snapshot.keys():
		final_owner[province_id] = int(snapshot[province_id]["owner"])
		final_garrison[province_id] = (station[province_id] as Dictionary).duplicate(true)
		final_home_guard[province_id] = int(snapshot[province_id]["home_guard"])
		final_ambush[province_id] = (ambush_orders.has(province_id) \
			or bool(snapshot[province_id]["ambush"])) and not departed.has(province_id)
	var pending_returns: Array = []

	# 5. Swaps: A invades B's province while B invades A's. Both armies meet in
	# the field with no terrain, and every survivor returns to its own origin.
	var consumed: Dictionary = {}
	var swaps: Array = []
	for index in moves.size():
		if consumed.has(index):
			continue
		var entry: Dictionary = moves[index]
		var faction := int(entry["faction"])
		var from_id := String(entry["from"])
		var to_id := String(entry["to"])
		if not _is_hostile_move(entry, snapshot):
			continue

		var rival := -1
		for other_index in moves.size():
			if other_index == index or consumed.has(other_index):
				continue
			var other: Dictionary = moves[other_index]
			if int(other["faction"]) == faction:
				continue
			if String(other["from"]) != to_id or String(other["to"]) != from_id:
				continue
			rival = other_index
			break
		if rival < 0:
			continue

		var rival_faction := int(moves[rival]["faction"])
		var first_units: Dictionary = {}
		var second_units: Dictionary = {}
		var first_orders: Array = []
		var second_orders: Array = []
		for other_index in moves.size():
			if consumed.has(other_index):
				continue
			var other: Dictionary = moves[other_index]
			if int(other["faction"]) == faction and String(other["from"]) == from_id and String(other["to"]) == to_id:
				_merge_units(first_units, other["units"])
				first_orders.append(other)
				consumed[other_index] = true
			elif int(other["faction"]) == rival_faction and String(other["from"]) == to_id and String(other["to"]) == from_id:
				_merge_units(second_units, other["units"])
				second_orders.append(other)
				consumed[other_index] = true

		swaps.append({
			"first_faction": faction,
			"second_faction": rival_faction,
			"first_from": from_id,
			"second_from": to_id,
			"first_units": first_units,
			"second_units": second_units,
			"first_orders": first_orders,
			"second_orders": second_orders,
		})

	# 6. Group the remaining moves by destination and resolve destinations in a
	# seeded order, never faction order.
	var by_target: Dictionary = {}
	for index in moves.size():
		if consumed.has(index):
			continue
		var entry: Dictionary = moves[index]
		var to_id := String(entry["to"])
		if not by_target.has(to_id):
			by_target[to_id] = []
		by_target[to_id].append(entry)

	var targets: Array = by_target.keys()
	_shuffle(targets, rng)
	for target_id: String in targets:
		_resolve_destination(
			target_id, by_target[target_id], snapshot, station, rng, summary,
			final_owner, final_garrison, final_home_guard, final_ambush, pending_returns
		)

	# 7. Independent swap battles are also ordered by the seed, never by faction.
	_shuffle(swaps, rng)
	for swap: Dictionary in swaps:
		var first_faction := int(swap["first_faction"])
		var second_faction := int(swap["second_faction"])
		var first_from := String(swap["first_from"])
		var second_from := String(swap["second_from"])
		var result := _field_battle(
			swap["first_units"], swap["second_units"], first_faction, second_faction, rng
		)
		result["province_id"] = first_from
		var first_province := map_state.get_province(first_from)
		var second_province := map_state.get_province(second_from)
		result["province_name"] = first_province.display_name if first_province != null else first_from
		result["from_id"] = first_from
		result["to_id"] = second_from
		result["from_name"] = first_province.display_name if first_province != null else first_from
		result["to_name"] = second_province.display_name if second_province != null else second_from
		result["swap"] = true
		result["captured"] = false
		summary["battles"].append(result)
		last_battle = result
		battle_resolved.emit(result)
		_log("[battle] swap %s <-> %s: losses %d/%d, survivors return home" % [
			result["from_name"], result["to_name"],
			int(result["attacker_losses"]), int(result["defender_losses"]),
		])

		_pending_returns(result["survivors_a"], swap["first_orders"], first_faction, pending_returns, rng)
		_pending_returns(result["survivors_b"], swap["second_orders"], second_faction, pending_returns, rng)

	# 8. Survivors return home only if their faction still owns the origin after
	# every capture has been accounted for; otherwise they are lost.
	for entry_variant in pending_returns:
		var entry: Dictionary = entry_variant
		var origin := String(entry["origin"])
		if int(final_owner.get(origin, Balance.Faction.NEUTRAL)) != int(entry["faction"]):
			continue
		var home: Dictionary = final_garrison.get(origin, {})
		_merge_units(home, entry["units"])
		final_garrison[origin] = home

	for province in map_state.provinces:
		province.owner_faction = int(final_owner[province.id])
		province.garrison = (final_garrison[province.id] as Dictionary).duplicate(true)
		province.home_guard = int(final_home_guard.get(province.id, 0))
		province.ambush = bool(final_ambush.get(province.id, false))

	_apply_capital_losses(snapshot)
	_apply_conquest_unrest(snapshot)
	# Flares and hidden garrisons change with the board, so recompute what each
	# side can see before the next planning phase begins.
	update_all_visibility()

	clear_orders()
	state_changed.emit()
	return summary


func _resolve_destination(
	target_id: String,
	incoming_moves: Array,
	snapshot: Dictionary,
	station: Dictionary,
	rng: RandomNumberGenerator,
	summary: Dictionary,
	final_owner: Dictionary,
	final_garrison: Dictionary,
	final_home_guard: Dictionary,
	final_ambush: Dictionary,
	pending_returns: Array,
) -> void:
	var owner := int(snapshot[target_id]["owner"])
	var militia := int(snapshot[target_id]["home_guard"]) if Balance.HOME_GUARD_ENABLED else 0
	var incoming: Dictionary = {}
	var orders_by_faction: Dictionary = {}
	for entry_variant in incoming_moves:
		var entry: Dictionary = entry_variant
		var faction := int(entry["faction"])
		if not incoming.has(faction):
			incoming[faction] = {}
			orders_by_faction[faction] = []
		_merge_units(incoming[faction], entry["units"])
		orders_by_faction[faction].append(entry)

	# Defence is the snapshot station plus any friendly reinforcement arriving
	# this turn (rule 3c), plus the home guard that never leaves.
	var defence: Dictionary = (station[target_id] as Dictionary).duplicate(true)
	var friendly: Dictionary = incoming.get(owner, {}) if owner != Balance.Faction.NEUTRAL else {}
	if not friendly.is_empty():
		_merge_units(defence, friendly)
	var has_defence := not defence.is_empty() or militia > 0

	var attackers: Dictionary = {}
	for faction: int in incoming.keys():
		if faction == owner or faction == Balance.Faction.NEUTRAL:
			continue
		attackers[faction] = (incoming[faction] as Dictionary).duplicate(true)

	# No enemy army arrives: friendly reinforcement joins the garrison and a
	# neutral province with a single army is taken without a fight.
	if attackers.is_empty():
		if owner == Balance.Faction.NEUTRAL:
			if incoming.size() == 1:
				var only_faction: int = int(incoming.keys()[0])
				_arrival(target_id, incoming[only_faction], only_faction, summary, final_owner, final_garrison, final_home_guard, final_ambush)
			elif incoming.size() > 1:
				_resolve_contest(
					target_id, incoming, orders_by_faction, rng, summary,
					final_owner, final_garrison, final_home_guard, final_ambush, pending_returns
				)
		else:
			final_garrison[target_id] = defence
		return

	# Undefended (or the owner left and no militia): one attacker takes it, two
	# fight a field battle for it.
	if not has_defence:
		if attackers.size() == 1:
			var attacker_faction: int = int(attackers.keys()[0])
			_arrival(target_id, attackers[attacker_faction], attacker_faction, summary, final_owner, final_garrison, final_home_guard, final_ambush)
		else:
			_resolve_contest(
				target_id, attackers, orders_by_faction, rng, summary,
				final_owner, final_garrison, final_home_guard, final_ambush, pending_returns
			)
		return

	# Normal attack on a defended province: existing resolver and terrain rules.
	# Friendly reinforcements are already part of `defence`.
	if attackers.size() > 1:
		# With two factions this cannot happen, but seed the choice instead of
		# letting dictionary order decide.
		var attacker_ids: Array = attackers.keys()
		_shuffle(attacker_ids, rng)
		var first: int = int(attacker_ids[0])
		attackers = {first: attackers[first]}

	var attacker_faction: int = int(attackers.keys()[0])
	var attack_units: Dictionary = attackers[attacker_faction]
	var attacker_orders: Array = orders_by_faction.get(attacker_faction, [])

	var target := map_state.get_province(target_id)
	if target == null:
		return

	# Fight on a throwaway province: the live board is written only at the end.
	var battle_target := ProvinceData.new()
	battle_target.id = target.id
	battle_target.display_name = target.display_name
	battle_target.terrain = target.terrain
	battle_target.owner_faction = owner
	battle_target.garrison = defence.duplicate(true)
	battle_target.home_guard = militia
	battle_target.ambush = bool(final_ambush.get(target_id, false))
	var result := CombatResolver.resolve(attack_units.duplicate(true), battle_target, attacker_faction, rng)
	# A hidden army is revealed the moment it strikes, win or lose.
	final_ambush[target_id] = false
	result["from_id"] = String(attacker_orders[0]["from"]) if not attacker_orders.is_empty() else ""
	result["to_id"] = target_id
	result["from_name"] = _province_name(String(result["from_id"]))
	result["to_name"] = target.display_name
	result["field"] = false
	result["swap"] = false
	summary["battles"].append(result)
	last_battle = result
	battle_resolved.emit(result)
	_log("[battle] %s -> %s: attack %.1f vs defence %.1f | losses %d/%d | %s" % [
		result["from_name"], target.display_name,
		float(result["attacker_power"]), float(result["defender_power"]),
		int(result["attacker_losses"]), int(result["defender_losses"]),
		("AMBUSH! " if bool(result["ambush"]) else "")
			+ ("CAPTURED" if bool(result["captured"]) else "held"),
	])

	if bool(result["captured"]):
		final_owner[target_id] = attacker_faction
		final_garrison[target_id] = (result["attacker_survivors"] as Dictionary).duplicate(true)
		# The levy dies with the old owner; it never transfers.
		final_home_guard[target_id] = 0
	else:
		final_garrison[target_id] = battle_target.garrison.duplicate(true)
		final_home_guard[target_id] = battle_target.home_guard
		_pending_returns(result["attacker_survivors"], attacker_orders, attacker_faction, pending_returns, rng)


## Empty or undefended target with more than one army: field battle, winner by
## survivors then remaining power, then the seeded RNG.
func _resolve_contest(
	target_id: String,
	incoming: Dictionary,
	orders_by_faction: Dictionary,
	rng: RandomNumberGenerator,
	summary: Dictionary,
	final_owner: Dictionary,
	final_garrison: Dictionary,
	final_home_guard: Dictionary,
	final_ambush: Dictionary,
	pending_returns: Array,
) -> void:
	var factions_in: Array = incoming.keys()
	_shuffle(factions_in, rng)
	if factions_in.size() < 2:
		return
	var first: int = int(factions_in[0])
	var second: int = int(factions_in[1])
	var first_units: Dictionary = incoming[first]
	var second_units: Dictionary = incoming[second]
	var result := _field_battle(first_units, second_units, first, second, rng)
	result["province_id"] = target_id
	result["province_name"] = _province_name(target_id)
	result["from_id"] = _first_origin(orders_by_faction.get(first, []))
	result["to_id"] = _first_origin(orders_by_faction.get(second, []))
	result["from_name"] = _province_name(String(result["from_id"]))
	result["to_name"] = _province_name(String(result["to_id"]))
	result["swap"] = false
	var winner := _field_winner(first, result["survivors_a"], second, result["survivors_b"], rng)
	result["captured"] = winner != Balance.Faction.NEUTRAL
	summary["battles"].append(result)
	last_battle = result
	battle_resolved.emit(result)
	_log("[battle] contest for %s: %s vs %s | losses %d/%d | winner %s" % [
		result["province_name"], Balance.faction_name(first), Balance.faction_name(second),
		int(result["attacker_losses"]), int(result["defender_losses"]),
		Balance.faction_name(winner),
	])

	if winner == Balance.Faction.NEUTRAL:
		return
	if winner == first:
		final_owner[target_id] = first
		final_garrison[target_id] = (result["survivors_a"] as Dictionary).duplicate(true)
		final_home_guard[target_id] = 0
		final_ambush[target_id] = false
		_pending_returns(result["survivors_b"], orders_by_faction.get(second, []), second, pending_returns, rng)
	else:
		final_owner[target_id] = second
		final_garrison[target_id] = (result["survivors_b"] as Dictionary).duplicate(true)
		final_home_guard[target_id] = 0
		final_ambush[target_id] = false
		_pending_returns(result["survivors_a"], orders_by_faction.get(first, []), first, pending_returns, rng)


## Runs the existing combat formula with terrain forced to Plains. The
## attacker/defender roles are chosen by the seeded RNG, so neither faction has
## a structural advantage in a field battle.
func _field_battle(
	first_units: Dictionary,
	second_units: Dictionary,
	first_faction: int,
	second_faction: int,
	rng: RandomNumberGenerator,
) -> Dictionary:
	var first_is_attacker := rng.randf() < 0.5
	var attacker_units: Dictionary = first_units if first_is_attacker else second_units
	var defender_units: Dictionary = second_units if first_is_attacker else first_units
	var attacker_faction: int = first_faction if first_is_attacker else second_faction
	var defender_faction: int = second_faction if first_is_attacker else first_faction

	var dummy := ProvinceData.new()
	dummy.terrain = Balance.Terrain.PLAINS
	dummy.owner_faction = defender_faction
	dummy.garrison = defender_units.duplicate(true)

	var result := CombatResolver.resolve(attacker_units.duplicate(true), dummy, attacker_faction, rng)
	result["field"] = true
	if first_is_attacker:
		result["survivors_a"] = result["attacker_survivors"]
		result["survivors_b"] = result["defender_survivors"]
	else:
		result["survivors_a"] = result["defender_survivors"]
		result["survivors_b"] = result["attacker_survivors"]
	return result


func _field_winner(
	first_faction: int,
	first_units: Dictionary,
	second_faction: int,
	second_units: Dictionary,
	rng: RandomNumberGenerator,
) -> int:
	var first_troops := CombatResolver.troop_count(first_units)
	var second_troops := CombatResolver.troop_count(second_units)
	if first_troops == 0 and second_troops == 0:
		return Balance.Faction.NEUTRAL
	if first_troops != second_troops:
		return first_faction if first_troops > second_troops else second_faction

	var first_power := CombatResolver.attack_power_of(first_units)
	var second_power := CombatResolver.attack_power_of(second_units)
	if not is_equal_approx(first_power, second_power):
		return first_faction if first_power > second_power else second_faction
	return first_faction if rng.randf() < 0.5 else second_faction


## Adds an arriving army to a province's final state and transfers ownership
## when it was neutral or held by the enemy. Applied only at the end of
## resolution, never to the live board mid-battle.
func _arrival(
	province_id: String,
	units: Dictionary,
	faction: int,
	summary: Dictionary,
	final_owner: Dictionary,
	final_garrison: Dictionary,
	final_home_guard: Dictionary,
	final_ambush: Dictionary,
) -> void:
	var owner := int(final_owner.get(province_id, Balance.Faction.NEUTRAL))
	var garrison: Dictionary = (final_garrison.get(province_id, {}) as Dictionary).duplicate(true)
	_merge_units(garrison, units)
	final_garrison[province_id] = garrison
	if owner == faction:
		return
	final_owner[province_id] = faction
	# A captured province loses its levy and starts raising a new one next turn.
	final_home_guard[province_id] = 0
	final_ambush[province_id] = false
	summary["captures"].append({
		"faction": faction,
		"province": province_id,
		"province_name": _province_name(province_id),
	})
	_log("[resolve] %s takes %s" % [Balance.faction_name(faction), _province_name(province_id)])


## Splits survivors back to the origins of the orders that contributed them.
## Returns are queued, not applied: the caller writes them once every capture is
## known, so a soldier cannot come home to a province lost in the same turn.
func _pending_returns(
	survivors: Dictionary,
	orders: Array,
	faction: int,
	pending_returns: Array,
	rng: RandomNumberGenerator,
) -> void:
	if orders.is_empty():
		return
	var contributed: Dictionary = {}
	for entry_variant in orders:
		var entry: Dictionary = entry_variant
		_merge_units(contributed, entry["units"])

	var shuffled: Array = orders.duplicate()
	_shuffle(shuffled, rng)
	var per_origin: Dictionary = {}
	for entry_variant in shuffled:
		var entry: Dictionary = entry_variant
		per_origin[String(entry["from"])] = {}

	for unit_id: String in survivors.keys():
		var total_survivors := int(survivors[unit_id])
		if total_survivors <= 0:
			continue
		var total_contributed := int(contributed.get(unit_id, 0))
		if total_contributed <= 0:
			continue
		var shares: Array = []
		var assigned := 0
		for entry_variant in shuffled:
			var entry: Dictionary = entry_variant
			var share := int(floor(
				float(total_survivors) * float(int(entry["units"].get(unit_id, 0))) / float(total_contributed)
			))
			shares.append(share)
			assigned += share
		var leftover := total_survivors - assigned
		for i in shares.size():
			if leftover <= 0:
				break
			shares[i] = int(shares[i]) + 1
			leftover -= 1
		for i in shares.size():
			var share := int(shares[i])
			if share <= 0:
				continue
			var origin := String((shuffled[i] as Dictionary)["from"])
			var origin_units: Dictionary = per_origin[origin]
			origin_units[unit_id] = int(origin_units.get(unit_id, 0)) + share

	for origin: String in per_origin.keys():
		var units: Dictionary = per_origin[origin]
		if units.is_empty():
			continue
		pending_returns.append({"origin": origin, "faction": faction, "units": units})


func _is_hostile_move(entry: Dictionary, snapshot: Dictionary) -> bool:
	var target_owner := int(snapshot[String(entry["to"])]["owner"])
	return target_owner != int(entry["faction"]) and target_owner != Balance.Faction.NEUTRAL


func _merge_units(into: Dictionary, from: Dictionary) -> void:
	for unit_id: String in from.keys():
		var count := int(from[unit_id])
		if count <= 0:
			continue
		into[unit_id] = int(into.get(unit_id, 0)) + count


func _first_origin(orders: Array) -> String:
	if orders.is_empty():
		return ""
	return String(orders[0]["from"])


func _province_name(province_id: String) -> String:
	var province := map_state.get_province(province_id) if map_state != null else null
	return province.display_name if province != null else province_id


func _shuffled_factions(rng: RandomNumberGenerator) -> Array:
	var result: Array = factions()
	_shuffle(result, rng)
	return result


## Fisher-Yates with the resolution RNG, so conflict order is seeded and never
## derived from faction ids or dictionary order.
func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap_value: Variant = items[i]
		items[i] = items[j]
		items[j] = swap_value


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _log(message: String) -> void:
	if not quiet:
		print(message)
