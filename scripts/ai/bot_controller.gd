class_name BotController
extends Node
## Behaviour-tree driven bot for the Elves (LimboAI).
##
## The tree is a LimboAI resource at `res://data/ai/elf_turn_bt.tres`:
##
##   Sequence "Elf turn"
##   ├── Recruit                     (BTRecruitTask)
##   ├── Ambush                      (BTAmbushTask)
##   └── Sequence "Attack, then advance"
##       ├── Attack                  (BTAttackTask)
##       └── Advance                 (BTAdvanceTask)
##
## The resource is generated from build_behavior_tree() by
## scripts/tools/build_bot_tree.gd, so the tree shape has one definition. The
## script loads the resource at runtime and falls back to building the tree in
## code if it is missing (headless sims create bots without a scene).
##
## The tasks only orchestrate; the decision logic stays in this class and uses
## the same Game.queue_recruit()/Game.queue_move() calls as the player, so the
## bot can never break the rules the player is bound by and never sees the
## enemy's queued orders.
##
## bot_faction and auto_play are exported so the same script can drive either
## side headlessly for balance simulations (see AI_CONTEXT.md).

@export var bot_faction: int = Balance.Faction.ELVES
@export var auto_play: bool = true

var _doctrine: FactionDoctrine
var _doctrine_faction: int = Balance.Faction.NEUTRAL


## Fixed personality for this faction, cached until bot_faction changes.
func doctrine() -> FactionDoctrine:
	if _doctrine == null or _doctrine_faction != bot_faction:
		_doctrine = FactionDoctrine.for_faction(bot_faction)
		_doctrine_faction = bot_faction
	return _doctrine


const BASE_RECRUITS_PER_TURN := 3
const MAX_RECRUITS_PER_TURN := 18
const BASE_BATTLES_PER_TURN := 6
const MAX_BATTLES_PER_TURN := 40
## The reference map has 10 cities (six anchors plus four towns). Caps scale
## with city count, because wildlands are corridors rather than holdings.
const REFERENCE_CITIES := 10
const CAP_EXPONENT := 0.9
const ATTACK_SAFETY_MARGIN := 1.0
const IMPATIENCE_ROUNDS := 3
const BEHAVIOR_TREE_PATH := "res://data/ai/elf_turn_bt.tres"

var game: GameState
var turn_manager: Node

## Counts idle rounds; after IMPATIENCE_ROUNDS without a battle the bot
## attacks even at unfavourable odds instead of standing still forever.
var stalemate_rounds: int = 0

var _behavior_tree: BehaviorTree


func _ready() -> void:
	game = get_node_or_null("/root/Game") as GameState
	turn_manager = get_node_or_null("/root/TurnManager")
	if turn_manager == null:
		push_error("BotController: TurnManager autoload is missing")
		return
	if auto_play and not turn_manager.turn_started.is_connected(_on_turn_started):
		turn_manager.turn_started.connect(_on_turn_started)


func _on_turn_started(faction: int) -> void:
	if not auto_play or faction != bot_faction:
		return
	if game == null or not game.is_started():
		return

	play_turn()

	if bot_faction == Balance.PLAYER_FACTION:
		turn_manager.end_player_turn()
	else:
		turn_manager.finish_bot_planning()


# --- Behaviour tree -------------------------------------------------------

## Runs one full bot turn. The tree ticks once and completes, because every
## leaf resolves immediately (no RUNNING state in a turn-based game).
func play_turn() -> void:
	if game == null or game.map_state == null:
		return

	_log("[bot] %s turn %d — gold %d, manpower %d, provinces %d, troops %d" % [
		Balance.faction_name(bot_faction),
		turn_manager.turn_number,
		game.get_gold(bot_faction),
		game.get_manpower(bot_faction),
		game.map_state.controlled_province_count(bot_faction),
		total_troops(),
	])

	var tree := get_behavior_tree()

	var blackboard := Blackboard.new()
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	var instance: BTInstance = tree.instantiate(self, blackboard, self, scene_root)
	if instance == null:
		push_error("BotController: behaviour tree instantiation failed")
		return
	instance.update(0.0)


## The authored .tres is the tree the game actually runs. Building in code is
## only a fallback for bots created outside a scene (balance_sim) and the source
## used by the resource generator.
func get_behavior_tree() -> BehaviorTree:
	if _behavior_tree == null:
		_behavior_tree = load(BEHAVIOR_TREE_PATH) as BehaviorTree
		if _behavior_tree == null:
			push_warning("BotController: missing %s, building the tree in code" % BEHAVIOR_TREE_PATH)
			_behavior_tree = build_behavior_tree()
	return _behavior_tree


func build_behavior_tree() -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.description = "Elf turn: recruit, attack, then advance wherever ground is open."

	var root := BTSequence.new()
	root.set_custom_name("Elf turn")
	root.add_child(BTRecruitTask.new())
	# preload avoids depending on the editor's global class cache for the newly
	# extracted leaf, which a fresh headless process has not scanned yet.
	root.add_child(preload("res://scripts/ai/tasks/bt_ambush_task.gd").new())

	# Attack and advance both run every turn. Making them alternatives let one
	# available battle suppress all expansion, which produced fronts that never
	# moved and wars that never ended.
	var military := BTSequence.new()
	military.set_custom_name("Attack, then advance")
	military.add_child(BTAttackTask.new())
	military.add_child(BTAdvanceTask.new())
	root.add_child(military)

	tree.set_root_task(root)
	return tree


# --- Rule 1: recruit ------------------------------------------------------

func recruit_phase() -> void:
	var unit_ids := UnitCatalog.units_for_faction(bot_faction)
	if unit_ids.is_empty():
		return

	# On the reference-size map the capital absorbs every slot, which is the
	# behaviour the balance table was measured with. Larger maps spread the
	# same per-turn budget over several cities so reinforcements reach distant
	# fronts instead of marching from the capital.
	if game.map_state.city_count_total() <= REFERENCE_CITIES:
		_recruit_at_capital(unit_ids)
		return

	var cities := _recruitment_cities()
	if cities.is_empty():
		return

	# One unit per city per pass, so a large realm reinforces several fronts.
	var cap := _recruit_cap()
	var queued := 0
	var placed := true
	while queued < cap and placed:
		placed = false
		for province: ProvinceData in cities:
			if queued >= cap:
				break
			var choice := _affordable_unit(unit_ids)
			if choice.is_empty():
				return
			var result := game.queue_recruit(bot_faction, province.id, choice, 1)
			if result.get("ok", false):
				queued += 1
				placed = true


## Hides a small number of border armies when the front has stopped moving.
## Using ambush only under stalemate keeps a hidden army from freezing an
## otherwise advancing war, and every order still goes through GameState.
func ambush_phase() -> void:
	if game == null or game.map_state == null or stalemate_rounds < 1:
		return
	var aggression: float = Balance.difficulty_modifier(game.difficulty, "bot_ambush", 1.0)
	var base_cap: int = doctrine().ambush_cap if stalemate_rounds < IMPATIENCE_ROUNDS \
			else doctrine().ambush_cap + 1
	var cap: int = int(round(float(base_cap) * aggression))
	var placed := 0
	for province in _stacks():
		if placed >= cap:
			break
		# Wildlands are the best place to wait: an enemy marching through does
		# not expect an army in ground that cannot defend itself.
		if not province.can_ambush() or not _borders_enemy(province):
			continue
		if game.has_move_order(bot_faction, province.id):
			continue
		var result := game.queue_ambush(bot_faction, province.id)
		if result.get("ok", false):
			placed += 1


## Reference-size behaviour: all slots in one city. The capital recruits while
## it is held and settled, otherwise the first owned city that is not still in
## conquest unrest.
func _recruit_at_capital(unit_ids: Array) -> void:
	var province := _recruitment_province()
	if province == null:
		return

	for _slot in BASE_RECRUITS_PER_TURN:
		var choice := _affordable_unit(unit_ids)
		if choice.is_empty():
			return
		var result := game.queue_recruit(bot_faction, province.id, choice, 1)
		if not result.get("ok", false):
			return


func _recruitment_province() -> ProvinceData:
	var capital := game.map_state.capital_of(bot_faction)
	if capital != null and capital.is_owned_by(bot_faction) and capital.unrest_turns <= 0:
		return capital

	var owned := game.map_state.provinces_owned_by(bot_faction)
	for province in owned:
		if province.is_city and province.unrest_turns <= 0:
			return province
	return null


## Owned cities that can recruit, nearest to the enemy first so new units
## appear where they are needed instead of marching from the capital. Cities
## that border the enemy are skipped: recruiting straight onto the front line
## made every turn a free reinforcement and shortened wars drastically.
func _recruitment_cities() -> Array[ProvinceData]:
	var safe: Array[ProvinceData] = []
	var all: Array[ProvinceData] = []
	for province: ProvinceData in game.map_state.provinces_owned_by(bot_faction):
		if not province.is_city or province.unrest_turns > 0:
			continue
		all.append(province)
		if not _borders_enemy(province):
			safe.append(province)

	var cities := safe if not safe.is_empty() else all
	if cities.size() <= 1:
		return cities

	var goal := _nearest_enemy_province()
	if goal == null:
		return cities

	var map := game.map_state
	var distances: Dictionary = {goal.id: 0}
	var frontier: Array[String] = [goal.id]
	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		for neighbor: ProvinceData in map.neighbors_of(current):
			if distances.has(neighbor.id):
				continue
			distances[neighbor.id] = int(distances[current]) + 1
			frontier.append(neighbor.id)

	cities.sort_custom(func(a: ProvinceData, b: ProvinceData) -> bool:
		return int(distances.get(a.id, 9999)) < int(distances.get(b.id, 9999))
	)
	return cities


func _nearest_enemy_province() -> ProvinceData:
	var enemy := _enemy_faction()
	var capital := game.map_state.capital_of(enemy)
	if capital != null and capital.is_owned_by(enemy):
		return capital
	for province: ProvinceData in game.map_state.provinces_owned_by(enemy):
		return province
	return null


## Caps grow sublinearly with the number of cities. Linear growth snowballed
## on the large map; sqrt starved the fronts. The exponent in between keeps
## both factions' unit costs and incomes relevant on every map size.
func _recruit_cap() -> int:
	return _scaled_cap(BASE_RECRUITS_PER_TURN, MAX_RECRUITS_PER_TURN, "bot_recruit")


func _battle_cap() -> int:
	return _scaled_cap(BASE_BATTLES_PER_TURN, MAX_BATTLES_PER_TURN, "bot_battle")


## The ideal cap is rarely a whole number. Rounding it up every turn gave a
## Human snowball, rounding it down gave an Elve sweep, so grant the extra slot
## only on part of the turn cycle. On the reference map the ideal cap is an
## integer, so this changes nothing in the baseline balance run.
func _scaled_cap(base: int, limit: int, modifier_key: String) -> int:
	var cities := maxi(1, game.map_state.city_count_total())
	var exact := float(base) * pow(
		float(cities) / float(REFERENCE_CITIES), CAP_EXPONENT
	)
	exact *= Balance.difficulty_modifier(game.difficulty, modifier_key, 1.0)
	var cap := int(floor(exact))
	var turn := int(turn_manager.turn_number) if turn_manager != null else 0
	if exact - float(cap) > 0.0 and (turn % 5 == 1 or turn % 5 == 3):
		cap += 1
	return clampi(cap, base, limit)


## Most expensive unit the realm can still afford; buying the strongest unit
## first keeps the bot's army quality in line with its income.
func _affordable_unit(unit_ids: Array) -> String:
	var choice := ""
	var best_cost := -1
	for unit_id: String in unit_ids:
		var unit := UnitCatalog.get_unit(unit_id)
		if unit == null:
			continue
		var costs := game.recruit_costs(bot_faction, unit_id)
		if not game.can_afford(bot_faction, int(costs["gold"]), int(costs["manpower"])):
			continue
		var tied: bool = absf(float(unit.gold_cost) - float(best_cost)) <= doctrine().recruit_tie_break_gold
		if unit.gold_cost > best_cost or (
			tied and not doctrine().recruit_role_bias.is_empty()
			and unit.role == doctrine().recruit_role_bias
		):
			best_cost = maxi(best_cost, unit.gold_cost)
			choice = unit_id
	return choice


# --- Rule 2: attack -------------------------------------------------------

## Returns the number of attack orders queued this turn.
func attack_phase() -> int:
	var battles := _execute_attacks(false)
	if battles > 0:
		stalemate_rounds = 0
		return battles

	stalemate_rounds += 1
	if stalemate_rounds < IMPATIENCE_ROUNDS:
		return 0

	battles = _execute_attacks(true)
	if battles > 0:
		stalemate_rounds = 0
	return battles


## Queues at most one attack per owned province. A province that already has a
## march order is skipped, which is the bot's copy of the player's "one attack
## order per province" rule.
## Holdings plus wildlands where this faction has an army on the march.
func _stacks() -> Array[ProvinceData]:
	var result: Array[ProvinceData] = []
	for province in game.map_state.provinces:
		if province.is_owned_by(bot_faction) or (
				province.is_wildland() and province.has_troops_of(bot_faction)
			):
			result.append(province)
	return result


func _execute_attacks(ignore_odds: bool) -> int:
	var battles := 0
	var battle_cap := _battle_cap()
	for province in _stacks():
		if battles >= battle_cap:
			break
		if province.total_troops() <= 0:
			continue
		if game.has_move_order(bot_faction, province.id):
			continue
		# An attack keeps a token guard at home, but a stalled front goes all in:
		# withholding troops during a stalemate produced wars that never ended.
		var reserve: int = 0 if ignore_odds else Balance.GARRISON_INTERIOR + doctrine().attack_reserve_delta
		var sending := _withhold(province.garrison.duplicate(), reserve)
		if CombatResolver.troop_count(sending) <= 0:
			continue
		var target := best_attack_target(province, sending, ignore_odds)
		if target == null:
			continue
		var result := game.queue_move(bot_faction, province.id, target.id, sending)
		if result.get("ok", false):
			battles += 1
	return battles


func best_attack_target(
	province: ProvinceData,
	sending: Dictionary,
	ignore_odds: bool = false,
) -> ProvinceData:
	var best: ProvinceData = null
	var best_ratio := 0.0
	var attack := _units_attack_power(sending)

	for target in game.map_state.neighbors_of(province.id):
		if target.is_owned_by(bot_faction) or target.is_wildland():
			continue
		# Wildlands never fight, so spending an attack order on one is wasted.
		# Fog of war still applies to the cities and fortresses worth taking.
		if game.visible_troops(bot_faction, target) <= 0:
			continue
		var defense := maxf(game.visible_defense_power(bot_faction, target), 1.0)
		var ratio := attack / defense
		var margin: float = doctrine().attack_margin
		margin += Balance.difficulty_modifier(
			game.difficulty, "bot_attack_margin", 0.0
		)
		if target.is_fortress or target.terrain == Balance.Terrain.HIGHLANDS:
			margin += doctrine().fortress_margin_bonus
		if not ignore_odds and ratio < margin:
			continue
		if ratio > best_ratio:
			best_ratio = ratio
			best = target

	return best


# --- Rule 3: advance ------------------------------------------------------

func advance_phase() -> void:
	# Undefended ground first. Without this a province can spend every turn
	# shuffling its army toward the front while an empty enemy province sits
	# next door, and the war never ends.
	_expand_into_open_ground()

	var enemy_faction := _enemy_faction()
	var enemy_capital := game.map_state.capital_of(enemy_faction)
	var use_capital := enemy_capital != null and enemy_capital.is_owned_by(enemy_faction)

	for province in _stacks():
		if province.total_troops() <= 0:
			continue
		if game.has_move_order(bot_faction, province.id):
			continue

		var reserve := _minimum_garrison(province)
		var sending := _withhold(province.garrison.duplicate(), reserve)
		if CombatResolver.troop_count(sending) <= 0:
			continue

		var step: ProvinceData = null
		if use_capital and province.id != enemy_capital.id:
			step = _next_step_toward(province.id, enemy_capital.id)
		if step == null:
			step = _nearest_enemy_step(province.id)
		if step == null:
			# An enemy capital can fall while neutral ground remains. Without this
			# fallback the bot would stand still forever instead of taking it.
			step = _nearest_open_step(province.id)
		if step == null:
			continue

		# Never walk into a defended foreign province; rule 2 decides battles.
		if not _can_enter(step):
			continue
		# Two stacks must not trade places forever: if the step already marches
		# back here, leave this army in place for a turn.
		if _has_queued_move(bot_faction, step.id, province.id):
			continue

		game.queue_move(bot_faction, province.id, step.id, sending)


## Takes adjacent provinces that cannot defend themselves, preferring enemy
## land over neutral ground. Only visible board state is read.
func _expand_into_open_ground() -> void:
	for province in _stacks():
		if province.total_troops() <= 0:
			continue
		if game.has_move_order(bot_faction, province.id):
			continue

		var reserve := _minimum_garrison(province)
		var sending := _withhold(province.garrison.duplicate(), reserve)
		if CombatResolver.troop_count(sending) <= 0:
			continue

		var target := _best_open_neighbor(province)
		if target == null:
			continue
		game.queue_move(bot_faction, province.id, target.id, sending)


func _best_open_neighbor(province: ProvinceData) -> ProvinceData:
	var neutral_city: ProvinceData = null
	for target in game.map_state.neighbors_of(province.id):
		if target.is_owned_by(bot_faction) or target.is_wildland():
			continue
		if game.visible_troops(bot_faction, target) > 0:
			continue
		if not target.is_neutral():
			return target
		if neutral_city == null:
			neutral_city = target
	return neutral_city


## An army may enter friendly land or a province it believes undefended.
func _can_enter(province: ProvinceData) -> bool:
	return province.is_owned_by(bot_faction) \
		or game.visible_troops(bot_faction, province) <= 0


func _has_queued_move(faction: int, from_id: String, to_id: String) -> bool:
	for order in game.queued_orders_for(faction):
		if String(order.get("type", "")) != "move":
			continue
		if String(order.get("from_id", "")) == from_id and String(order.get("to_id", "")) == to_id:
			return true
	return false


## One graph step toward goal_id. Hostile garrisons are ignored here: the
## bot needs a direction even when the direct route is held. Rule 3 still
## refuses to walk into defended ground.
func _next_step_toward(from_id: String, goal_id: String) -> ProvinceData:
	var map := game.map_state
	var frontier: Array[String] = [from_id]
	var came_from: Dictionary = {from_id: ""}

	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		for neighbor in map.neighbors_of(current):
			if came_from.has(neighbor.id):
				continue
			came_from[neighbor.id] = current
			if neighbor.id == goal_id:
				frontier.clear()
				break
			frontier.append(neighbor.id)
		if came_from.has(goal_id):
			break

	if not came_from.has(goal_id):
		return null
	return _first_step(came_from, from_id, goal_id)


## Step toward the closest city owned by the enemy; wildlands are corridors.
func _nearest_enemy_step(from_id: String) -> ProvinceData:
	var map := game.map_state
	var frontier: Array[String] = [from_id]
	var came_from: Dictionary = {from_id: ""}

	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		for neighbor in map.neighbors_of(current):
			if came_from.has(neighbor.id):
				continue
			came_from[neighbor.id] = current
			if not neighbor.is_owned_by(bot_faction) and not neighbor.is_neutral() \
					and neighbor.is_city:
				var step := _first_step(came_from, from_id, neighbor.id)
				if step != null and _can_enter(step):
					return step
			frontier.append(neighbor.id)

	return null


## Nearest neutral city, walked through friendly land and wildlands. Returns
## the first step of the path, which may itself be a wildland corridor.
func _nearest_open_step(from_id: String) -> ProvinceData:
	var map := game.map_state
	var frontier: Array[String] = [from_id]
	var came_from: Dictionary = {from_id: ""}

	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		for neighbor in map.neighbors_of(current):
			if came_from.has(neighbor.id):
				continue
			came_from[neighbor.id] = current
			if neighbor.is_neutral() and neighbor.is_city \
					and game.visible_troops(bot_faction, neighbor) <= 0:
				return _first_step(came_from, from_id, neighbor.id)
			# Wildlands are corridors: path through them to reach a city that
			# is not adjacent to the current holding.
			if neighbor.is_owned_by(bot_faction) or (
					neighbor.is_neutral() and neighbor.is_wildland()
				):
				frontier.append(neighbor.id)

	return null


func _first_step(came_from: Dictionary, from_id: String, goal_id: String) -> ProvinceData:
	var step_id: String = goal_id
	while String(came_from.get(step_id, "")) != from_id:
		step_id = String(came_from.get(step_id, ""))
		if step_id.is_empty():
			return null
	return game.map_state.get_province(step_id)


func _withhold(units: Dictionary, amount: int) -> Dictionary:
	var kept := units.duplicate(true)
	var remaining: int = amount
	for unit_id: String in kept.keys():
		if remaining <= 0:
			break
		var count := int(kept[unit_id])
		var taken: int = mini(count, remaining)
		kept[unit_id] = count - taken
		remaining -= taken
		if int(kept[unit_id]) <= 0:
			kept.erase(unit_id)
	return kept


## Troops this province should keep when it marches. Capitals and provinces
## bordering the enemy hold more; interior provinces only a token force.
func _minimum_garrison(province: ProvinceData) -> int:
	if province.is_capital:
		return Balance.GARRISON_CAPITAL
	if _borders_enemy(province):
		return Balance.GARRISON_BORDER
	return Balance.GARRISON_INTERIOR


func _borders_enemy(province: ProvinceData) -> bool:
	var enemy := _enemy_faction()
	for neighbor in game.map_state.neighbors_of(province.id):
		if neighbor.is_owned_by(enemy):
			return true
	return false


## Attack power of a departing force, so odds are judged on what actually
## marches rather than on the garrison it leaves behind.
func _units_attack_power(units: Dictionary) -> float:
	var power := 0.0
	for unit_id: String in units.keys():
		var count := int(units[unit_id])
		if count <= 0:
			continue
		var unit := UnitCatalog.get_unit(unit_id)
		if unit != null:
			power += float(unit.attack) * float(count)
	return power


func _enemy_faction() -> int:
	return Balance.Faction.HUMANS if bot_faction == Balance.Faction.ELVES else Balance.Faction.ELVES


func total_troops() -> int:
	var total := 0
	for province in game.map_state.provinces_owned_by(bot_faction):
		total += province.total_troops()
	return total


func _log(message: String) -> void:
	if game != null and game.quiet:
		return
	print(message)
