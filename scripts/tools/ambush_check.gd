extends SceneTree

var game: GameState
var turn_manager: Node


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _fail(message: String) -> void:
	printerr("[ambush] FAIL: %s" % message)
	quit(1)


func _run() -> void:
	game = root.get_node_or_null("Game") as GameState
	turn_manager = root.get_node_or_null("TurnManager")
	if game == null or turn_manager == null:
		_fail("autoloads missing")
		return
	game.quiet = true
	turn_manager.autosave = false
	turn_manager.start_game(24680, 1.0)

	var capital := game.map_state.capital_of(Balance.Faction.HUMANS)
	if capital == null:
		_fail("no human capital")
		return
	var queued := game.queue_ambush(Balance.Faction.HUMANS, capital.id)
	if not bool(queued.get("ok", false)):
		_fail("queue_ambush refused: %s" % String(queued.get("reason", "")))
		return
	if game.is_province_visible(Balance.Faction.HUMANS, capital.id) != true:
		_fail("player cannot see own ambush")
		return
	if game.is_province_visible(Balance.Faction.ELVES, capital.id) != false:
		_fail("enemy can see queued ambush")
		return

	# Same army, same seed: only the ambush flag differs.
	var plain := ProvinceData.new()
	plain.terrain = Balance.Terrain.HIGHLANDS
	plain.is_city = true
	plain.garrison = {"elf_riflemen": 4}
	var hidden := ProvinceData.new()
	hidden.terrain = Balance.Terrain.HIGHLANDS
	hidden.is_city = true
	hidden.garrison = {"elf_riflemen": 4}
	hidden.ambush = true
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 1234
	var plain_result := CombatResolver.resolve({"human_swordsmen": 8}, plain, 0, seed_rng)
	seed_rng.seed = 1234
	var hidden_result := CombatResolver.resolve({"human_swordsmen": 8}, hidden, 0, seed_rng)
	if not bool(hidden_result.get("ambush", false)) or bool(plain_result.get("ambush", false)):
		_fail("ambush flag missing from battle result")
		return
	if float(hidden_result["defender_power"]) <= float(plain_result["defender_power"]):
		_fail("ambush did not raise defence power")
		return
	if int(hidden_result["attacker_losses"]) <= int(plain_result["attacker_losses"]):
		_fail("ambush did not raise attacker losses")
		return

	# The ambush becomes active once both sides commit.
	turn_manager.end_player_turn()
	turn_manager.finish_bot_planning()
	if not capital.ambush:
		_fail("ambush did not become active after resolution")
		return

	# Marching out next turn ends the ambush at resolution.
	var neighbor := game.map_state.neighbors_of(capital.id)[0]
	var move := game.queue_move(Balance.Faction.HUMANS, capital.id, neighbor.id, {
		"human_swordsmen": 1,
	})
	if not bool(move.get("ok", false)):
		_fail("marching from an ambush was refused: %s" % String(move.get("reason", "")))
		return
	turn_manager.end_player_turn()
	turn_manager.finish_bot_planning()
	if capital.ambush:
		_fail("ambush survived a march out of the province")
		return

	print("[ambush] OK: hidden from enemy, surprise bonus applied, march consumes ambush")
	quit(0)
