extends SceneTree
## Headless AI-vs-AI balance run for the simultaneous-turn model.
##
## Run from the project folder:
##   godot --headless --path . --script res://scripts/tools/balance_sim.gd
##
## Both sides use the real BotController planning code and the real
## GameState/TurnManager resolution path, so the numbers describe the shipped
## rules. Autosave is disabled so the player's save file is never touched.

const GAMES := 20
const BASE_SEED := 41000
const MAX_TURNS := 400

var game: GameState
var turn_manager: Node
var humans: BotController
var elves: BotController

var _turns: Array[int] = []
var _wins := {
	Balance.Faction.HUMANS: 0,
	Balance.Faction.ELVES: 0,
	Balance.Faction.NEUTRAL: 0,
}
var _unfinished := 0
var _queue_failures := 0
var _errors: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	# SceneTree._initialize runs before the root is active, so autoloads cannot
	# be resolved yet. Start one frame later, when the tree is live.
	process_frame.connect(_run_all, CONNECT_ONE_SHOT)


func _run_all() -> void:
	game = root.get_node_or_null("Game") as GameState
	if game == null:
		game = GameState.new()
		game.name = "Game"
		root.add_child(game)

	turn_manager = root.get_node_or_null("TurnManager")
	if turn_manager == null:
		turn_manager = load("res://scripts/core/turn_manager.gd").new()
		turn_manager.name = "TurnManager"
		root.add_child(turn_manager)

	humans = _make_bot(Balance.Faction.HUMANS)
	elves = _make_bot(Balance.Faction.ELVES)

	game.quiet = true
	turn_manager.autosave = false

	print("[sim] %d games, seeds %d..%d, max %d turns" % [
		GAMES, BASE_SEED, BASE_SEED + GAMES - 1, MAX_TURNS,
	])

	for index in GAMES:
		_run_game(BASE_SEED + index)

	_report()
	if not _errors.is_empty():
		for message: String in _errors:
			printerr("[sim] FAIL: %s" % message)
		quit(1)
		return
	quit(0)


func _make_bot(faction: int) -> BotController:
	var bot := BotController.new()
	bot.name = "Bot%d" % faction
	bot.bot_faction = faction
	bot.auto_play = false
	root.add_child(bot)
	return bot


func _run_game(seed_value: int) -> void:
	humans.stalemate_rounds = 0
	elves.stalemate_rounds = 0
	turn_manager.start_game(seed_value)

	if not turn_manager.is_player_planning():
		_errors.append("seed %d: game did not start in player planning" % seed_value)
		return

	var guard := 0
	while not turn_manager.game_over and guard < MAX_TURNS:
		guard += 1

		humans.play_turn()
		turn_manager.end_player_turn()

		elves.play_turn()
		turn_manager.finish_bot_planning()

		if game.has_queued_orders():
			_queue_failures += 1
			_errors.append("seed %d turn %d: orders survived resolution" % [
				seed_value, turn_manager.turn_number,
			])
			break

	var winner := _winner()
	if turn_manager.game_over:
		_turns.append(turn_manager.turn_number)
	else:
		_unfinished += 1

	_wins[winner] = int(_wins[winner]) + 1
	print("[sim] seed %d: %s in %d turns%s" % [
		seed_value,
		Balance.faction_name(winner),
		turn_manager.turn_number,
		"" if turn_manager.game_over else " (unfinished)",
	])


func _winner() -> int:
	if game.map_state.is_eliminated(Balance.Faction.HUMANS):
		return Balance.Faction.ELVES
	if game.map_state.is_eliminated(Balance.Faction.ELVES):
		return Balance.Faction.HUMANS
	var leading := game.map_state.winning_faction()
	return leading


func _report() -> void:
	var finished := _turns.size()
	var total := 0
	for turns: int in _turns:
		total += turns
	var average := float(total) / float(maxi(finished, 1))

	print("")
	print("[sim] results over %d games" % GAMES)
	for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES, Balance.Faction.NEUTRAL]:
		var wins := int(_wins[faction])
		print("[sim] %s: %d wins (%.0f%%)" % [
			Balance.faction_name(faction), wins, 100.0 * float(wins) / float(GAMES),
		])
	print("[sim] finished %d, unfinished %d, average %.1f turns" % [
		finished, _unfinished, average,
	])
	print("[sim] queue failures: %d" % _queue_failures)
