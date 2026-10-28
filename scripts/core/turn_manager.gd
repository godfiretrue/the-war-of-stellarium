extends Node
## Turn phase machine, autoloaded as "TurnManager".
##
## Phases: PLAYER_TURN -> BOT_TURN -> RESOLUTION -> NEXT_TURN -> PLAYER_TURN.
## Systems listen to the signals instead of calling each other: the bot reacts
## to turn_started(), the HUD to phase_changed(), the map to state_changed().
##
## The BOT_TURN phase ends when the bot calls finish_bot_turn(), which keeps
## this script free of AI code.
##
## The Game singleton is resolved through the tree (not by bare name) so the
## script also compiles in editors whose autoload cache is stale.

signal turn_started(faction: int)
signal turn_ended(faction: int)
signal phase_changed(phase: int)
signal resolution_finished(summary: Dictionary)
signal game_finished(winner: int)

enum Phase { PLAYER_TURN, BOT_TURN, RESOLUTION, NEXT_TURN, GAME_OVER }

const PLAYER_FACTION := Balance.Faction.HUMANS
const BOT_FACTION := Balance.Faction.ELVES

var phase: int = Phase.NEXT_TURN
var current_faction: int = PLAYER_FACTION
var turn_number: int = 1
var game_over: bool = false
var last_resolution: Dictionary = {}

var game: GameState


func _ready() -> void:
	game = get_node_or_null("/root/Game") as GameState


func start_game() -> void:
	if game == null:
		_ready()
	game_over = false
	turn_number = 1
	last_resolution = {}
	game.start_new_game()
	_begin_player_turn()


## Starts a fresh game from a loaded save. The map state is already restored;
## this only resets the turn loop and announces the player's turn.
func resume_game(saved_turn: int) -> void:
	if game == null:
		_ready()
	game_over = false
	turn_number = maxi(saved_turn, 1)
	last_resolution = {}
	_begin_player_turn()


func end_player_turn() -> void:
	if game_over or phase != Phase.PLAYER_TURN:
		return
	turn_ended.emit(current_faction)
	_start_bot_turn()


## Called by the bot when it has finished all of its actions for this turn.
func finish_bot_turn() -> void:
	if game_over or phase != Phase.BOT_TURN:
		return
	turn_ended.emit(current_faction)
	_resolve()


func _log(message: String) -> void:
	if game != null and game.quiet:
		return
	print(message)


func is_player_turn() -> bool:
	return not game_over and phase == Phase.PLAYER_TURN


func phase_name() -> String:
	match phase:
		Phase.PLAYER_TURN:
			return "Player turn"
		Phase.BOT_TURN:
			return "Elves turn"
		Phase.RESOLUTION:
			return "Resolution"
		Phase.NEXT_TURN:
			return "Next turn"
		Phase.GAME_OVER:
			return "Game over"
	return "Unknown"


## Compact phase label for the top bar.
func phase_short_name() -> String:
	match phase:
		Phase.PLAYER_TURN:
			return "Player"
		Phase.BOT_TURN:
			return "Elves"
		Phase.RESOLUTION:
			return "Resolution"
		Phase.NEXT_TURN:
			return "Next"
		Phase.GAME_OVER:
			return "Over"
	return "?"


func _begin_player_turn() -> void:
	current_faction = PLAYER_FACTION
	phase = Phase.PLAYER_TURN
	phase_changed.emit(phase)
	_log("[turn] turn %d — %s" % [turn_number, phase_name()])
	turn_started.emit(current_faction)


func _start_bot_turn() -> void:
	current_faction = BOT_FACTION
	phase = Phase.BOT_TURN
	phase_changed.emit(phase)
	_log("[turn] turn %d — %s" % [turn_number, phase_name()])
	turn_started.emit(current_faction)


func _resolve() -> void:
	phase = Phase.RESOLUTION
	phase_changed.emit(phase)

	game.clear_acted_provinces()

	var summary := {"turn": turn_number, "income": {}, "upkeep": {}}
	for faction: int in [PLAYER_FACTION, BOT_FACTION]:
		var income := game.apply_income(faction)
		var upkeep := game.apply_upkeep(faction)
		summary["income"][faction] = income
		summary["upkeep"][faction] = upkeep
		_log("[turn] %s income +%d gold +%d manpower, upkeep -%d gold" % [
			Balance.faction_name(faction),
			int(income["gold"]), int(income["manpower"]), upkeep,
		])

	last_resolution = summary
	resolution_finished.emit(summary)

	if _check_game_over():
		return

	phase = Phase.NEXT_TURN
	phase_changed.emit(phase)
	turn_number += 1
	SaveSystem.save_game(game, turn_number)
	_begin_player_turn()


func _check_game_over() -> bool:
	if game.map_state == null:
		return false

	var winner: int = Balance.Faction.NEUTRAL
	if game.map_state.is_eliminated(PLAYER_FACTION):
		winner = BOT_FACTION
	elif game.map_state.is_eliminated(BOT_FACTION):
		winner = PLAYER_FACTION
	elif game.map_state.winning_faction() != Balance.Faction.NEUTRAL:
		winner = game.map_state.winning_faction()

	if winner == Balance.Faction.NEUTRAL:
		return false

	game_over = true
	phase = Phase.GAME_OVER
	phase_changed.emit(phase)
	_log("[turn] game over — winner: %s" % Balance.faction_name(winner))
	game_finished.emit(winner)
	return true
