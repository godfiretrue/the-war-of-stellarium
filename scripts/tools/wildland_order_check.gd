extends SceneTree
## Headless regression check for orders issued from a wildland corridor.
##
## A corridor follows the owner of its influencing city, but an army standing
## in it must still be able to march on and hide an ambush. Only its own units
## may be committed when both factions share the corridor.
##
##   godot --headless --path . --script res://scripts/tools/wildland_order_check.gd


var game: GameState
var turn_manager: Node


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _fail(message: String) -> void:
	printerr("[wildland] FAIL: %s" % message)
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

	var humans := Balance.Faction.HUMANS
	var elves := Balance.Faction.ELVES
	var capital := game.map_state.capital_of(humans)
	if capital == null:
		_fail("no human capital")
		return
	var corridor: ProvinceData = null
	for neighbor in game.map_state.neighbors_of(capital.id):
		if neighbor.is_wildland():
			corridor = neighbor
			break
	if corridor == null:
		_fail("capital has no wildland neighbour")
		return

	# March in, resolve, then leave the corridor under enemy influence.
	var unit_id: String = capital.garrison.keys()[0]
	var inbound := game.queue_move(humans, capital.id, corridor.id, {unit_id: 1})
	if not bool(inbound.get("ok", false)):
		_fail("could not march into the wildland: %s" % String(inbound.get("reason", "")))
		return
	turn_manager.end_player_turn()
	turn_manager.finish_bot_planning()
	corridor = game.map_state.get_province(corridor.id)
	if corridor.troops_of(humans) <= 0:
		_fail("army did not arrive in the wildland")
		return
	corridor.owner_faction = elves
	if corridor.is_owned_by(humans):
		_fail("test setup: corridor should follow the enemy city")
		return

	# Mixed garrisons are possible in a corridor; only our units are ours to move.
	_merge_test_units(corridor, humans, elves)
	if not corridor.can_order_from(humans):
		_fail("occupied wildland is not commandable")
		return
	if corridor.troops_of(humans) != 2 or corridor.troops_of(elves) != 1:
		_fail("faction-scoped troop counts are wrong")
		return
	if corridor.troops_of_type(humans, "elf_riflemen") != 0 \
			or corridor.troops_of_type(humans, "human_swordsmen") != 2:
		_fail("faction-scoped unit counts are wrong")
		return

	var exit_id := ""
	for neighbor in game.map_state.neighbors_of(corridor.id):
		if neighbor.id != capital.id:
			exit_id = neighbor.id
			break
	if exit_id.is_empty():
		exit_id = capital.id

	var march := game.queue_move(humans, corridor.id, exit_id, {"human_swordsmen": 1})
	if not bool(march.get("ok", false)):
		_fail("could not march out of the wildland: %s" % String(march.get("reason", "")))
		return
	game.clear_orders()

	var stolen := game.queue_move(humans, corridor.id, exit_id, {"elf_riflemen": 1})
	if bool(stolen.get("ok", false)):
		_fail("player marched enemy units out of the wildland")
		return
	game.clear_orders()

	var ambush := game.queue_ambush(humans, corridor.id)
	if not bool(ambush.get("ok", false)):
		_fail("could not ambush in the wildland: %s" % String(ambush.get("reason", "")))
		return
	game.clear_orders()

	print("[wildland] OK: march out, own-unit filtering and ambush in a hostile corridor")
	quit(0)


func _merge_test_units(corridor: ProvinceData, humans: int, elves: int) -> void:
	corridor.garrison.clear()
	corridor.garrison["human_swordsmen"] = 2
	corridor.garrison["elf_riflemen"] = 1
	corridor.ambush = false
	var human_unit := UnitCatalog.get_unit("human_swordsmen")
	var elf_unit := UnitCatalog.get_unit("elf_riflemen")
	if human_unit == null or human_unit.faction != humans:
		_fail("missing human test unit")
	if elf_unit == null or elf_unit.faction != elves:
		_fail("missing elf test unit")
