class_name BotController
extends Node
## Behaviour-tree driven bot for the Elves (LimboAI).
##
## The tree is built in code and mirrors the three rules of the prototype:
##
##   Sequence "Elf turn"
##   ├── Recruit                     (BTRecruitTask)
##   └── Sequence "Attack, then advance"
##       ├── Attack                  (BTAttackTask)
##       └── Advance                 (BTAdvanceTask)
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

const MAX_RECRUITS_PER_TURN := 3
const MAX_BATTLES_PER_TURN := 6
const ATTACK_SAFETY_MARGIN := 1.0
const IMPATIENCE_ROUNDS := 3
const CAPITAL_MIN_GARRISON := 2

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

	if _behavior_tree == null:
		_behavior_tree = build_behavior_tree()

	var blackboard := Blackboard.new()
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	var instance: BTInstance = _behavior_tree.instantiate(self, blackboard, self, scene_root)
	if instance == null:
		push_error("BotController: behaviour tree instantiation failed")
		return
	instance.update(0.0)


func build_behavior_tree() -> BehaviorTree:
	var tree := BehaviorTree.new()
	tree.description = "Elf turn: recruit, attack, then advance wherever ground is open."

	var root := BTSequence.new()
	root.set_custom_name("Elf turn")
	root.add_child(BTRecruitTask.new())

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
	var province := _recruitment_province()
	if province == null:
		return

	var unit_ids := UnitCatalog.units_for_faction(bot_faction)
	if unit_ids.is_empty():
		return

	for _slot in MAX_RECRUITS_PER_TURN:
		var choice := ""
		var best_cost := -1
		for unit_id: String in unit_ids:
			var unit := UnitCatalog.get_unit(unit_id)
			if unit == null:
				continue
			var costs := unit.costs_for(bot_faction)
			if not game.can_afford(bot_faction, int(costs["gold"]), int(costs["manpower"])):
				continue
			if unit.gold_cost > best_cost:
				best_cost = unit.gold_cost
				choice = unit_id

		if choice.is_empty():
			break
		var result := game.queue_recruit(bot_faction, province.id, choice, 1)
		if not result.get("ok", false):
			break


## The capital recruits while it is held, otherwise the first owned province.
func _recruitment_province() -> ProvinceData:
	var capital := game.map_state.capital_of(bot_faction)
	if capital != null and capital.is_owned_by(bot_faction):
		return capital

	var owned := game.map_state.provinces_owned_by(bot_faction)
	for province in owned:
		if province.is_city:
			return province
	return null


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
func _execute_attacks(ignore_odds: bool) -> int:
	var battles := 0
	for province in game.map_state.provinces_owned_by(bot_faction):
		if battles >= MAX_BATTLES_PER_TURN:
			break
		if province.total_troops() <= 0:
			continue
		if game.has_move_order(bot_faction, province.id):
			continue
		var target := best_attack_target(province, ignore_odds)
		if target == null:
			continue
		var result := game.queue_move(bot_faction, province.id, target.id, province.garrison.duplicate())
		if result.get("ok", false):
			battles += 1
	return battles


func best_attack_target(province: ProvinceData, ignore_odds: bool = false) -> ProvinceData:
	var best: ProvinceData = null
	var best_ratio := 0.0

	for target in game.map_state.neighbors_of(province.id):
		if target.is_owned_by(bot_faction):
			continue
		if target.total_troops() <= 0:
			continue
		var defense := maxf(target.defense_power(), 1.0)
		var ratio := province.attack_power() / defense
		if not ignore_odds and ratio < ATTACK_SAFETY_MARGIN:
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

	for province in game.map_state.provinces_owned_by(bot_faction):
		if province.total_troops() <= 0:
			continue
		if game.has_move_order(bot_faction, province.id):
			continue

		var reserve := CAPITAL_MIN_GARRISON if province.is_capital else 1
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
	for province in game.map_state.provinces_owned_by(bot_faction):
		if province.total_troops() <= 0:
			continue
		if game.has_move_order(bot_faction, province.id):
			continue

		var reserve := CAPITAL_MIN_GARRISON if province.is_capital else 1
		var sending := _withhold(province.garrison.duplicate(), reserve)
		if CombatResolver.troop_count(sending) <= 0:
			continue

		var target := _best_open_neighbor(province)
		if target == null:
			continue
		game.queue_move(bot_faction, province.id, target.id, sending)


func _best_open_neighbor(province: ProvinceData) -> ProvinceData:
	var neutral: ProvinceData = null
	for target in game.map_state.neighbors_of(province.id):
		if target.is_owned_by(bot_faction):
			continue
		if target.total_troops() > 0:
			continue
		if not target.is_neutral():
			return target
		if neutral == null:
			neutral = target
	return neutral


## An army may enter friendly land or an undefended province without fighting.
func _can_enter(province: ProvinceData) -> bool:
	return province.is_owned_by(bot_faction) or province.total_troops() <= 0


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


## Step toward the closest province owned by the enemy.
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
			if not neighbor.is_owned_by(bot_faction) and not neighbor.is_neutral():
				var step := _first_step(came_from, from_id, neighbor.id)
				if step != null and _can_enter(step):
					return step
			frontier.append(neighbor.id)

	return null


## Nearest neutral province, walked through friendly land. Returns the first
## step of the path, which may be a neutral province itself.
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
			if neighbor.is_neutral() and neighbor.total_troops() <= 0:
				return _first_step(came_from, from_id, neighbor.id)
			if neighbor.is_owned_by(bot_faction):
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
