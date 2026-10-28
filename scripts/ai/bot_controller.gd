class_name BotController
extends Node
## Behaviour-tree driven bot for the Elves (LimboAI).
##
## The tree is built in code and mirrors the three rules of the prototype:
##
##   Sequence "Elf turn"
##   ├── Recruit                     (BTRecruitTask)
##   └── Selector "Attack or advance"
##       ├── Attack                  (BTAttackTask, fails when no battle)
##       └── Advance                 (BTAdvanceTask)
##
## The tasks only orchestrate; the decision logic stays in this class and uses
## the same Game.recruit()/Game.move() calls as the player, so the bot can
## never break the rules the player is bound by.
##
## bot_faction and auto_play are exported so the same script can drive the
## player side headlessly for balance simulations (see AI_CONTEXT.md).

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
		turn_manager.finish_bot_turn()


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
	tree.description = "Elf turn: recruit, then attack if possible, otherwise advance."

	var root := BTSequence.new()
	root.set_custom_name("Elf turn")
	root.add_child(BTRecruitTask.new())

	var military := BTSelector.new()
	military.set_custom_name("Attack or advance")
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
		var result := game.recruit(bot_faction, province.id, choice, 1)
		if not result.get("ok", false):
			break


## The capital recruits while it is held, otherwise the first owned province.
func _recruitment_province() -> ProvinceData:
	var capital := game.map_state.capital_of(bot_faction)
	if capital != null and capital.is_owned_by(bot_faction):
		return capital

	var owned := game.map_state.provinces_owned_by(bot_faction)
	if owned.is_empty():
		return null
	return owned[0]


# --- Rule 2: attack -------------------------------------------------------

## Returns the number of battles fought this turn.
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


func _execute_attacks(ignore_odds: bool) -> int:
	var battles := 0
	var acted := true
	while acted and battles < MAX_BATTLES_PER_TURN:
		acted = false
		for province in game.map_state.provinces_owned_by(bot_faction):
			if province.total_troops() <= 0:
				continue
			var target := best_attack_target(province, ignore_odds)
			if target == null:
				continue
			var result := game.move(bot_faction, province.id, target.id, province.garrison.duplicate())
			if result.get("ok", false):
				battles += 1
				acted = true
				break
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
	var enemy_faction := _enemy_faction()
	var enemy_capital := game.map_state.capital_of(enemy_faction)
	var use_capital := enemy_capital != null and enemy_capital.is_owned_by(enemy_faction)

	for province in game.map_state.provinces_owned_by(bot_faction):
		if province.total_troops() <= 0:
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
			continue

		# Never walk into a defended enemy province; rule 2 decides battles.
		if step.total_troops() > 0 and not step.is_owned_by(bot_faction):
			continue

		game.move(bot_faction, province.id, step.id, sending)


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
				if step != null and step.is_owned_by(bot_faction):
					return step
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
