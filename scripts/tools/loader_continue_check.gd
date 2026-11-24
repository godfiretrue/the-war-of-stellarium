extends SceneTree
## Headless integration check for the threaded Continue path.
##
## Creates a save, returns to the main menu and loads it through the real
## loading flow. The player's existing save is backed up and restored, so the
## check is safe to run on a working machine.
##
##   godot --headless --path . --script res://scripts/tools/loader_continue_check.gd

const TIMEOUT_MS := 20000
const TEST_SEED := 24680
const TEST_TURN := 3
const TEST_GOLD := 777
const BACKUP_PATH := "user://savegame.loader_check_backup.json"


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var game := get_root().get_node_or_null("Game") as GameState
	var turn_manager := get_root().get_node_or_null("TurnManager")
	if game == null or turn_manager == null:
		_fail("autoloads missing")
		return

	_backup_save()

	turn_manager.start_game(TEST_SEED)
	game.gold[Balance.Faction.HUMANS] = TEST_GOLD
	if not SaveSystem.save_game(game, TEST_TURN):
		_fail("could not create test save")
		return

	var error := change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		_fail("cannot load main menu: %d" % error)
		return
	await process_frame

	var menu := current_scene
	if menu == null or not menu.has_method("_on_continue"):
		_fail("main menu did not become the current scene")
		return
	menu._on_continue()

	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.scene_file_path.ends_with("map.tscn"):
			break

	if current_scene == null or not current_scene.scene_file_path.ends_with("map.tscn"):
		_fail("map scene never loaded")
		return
	for _i in 5:
		await process_frame

	if game.map_state == null or game.map_state.province_count() <= 0:
		_fail("map was not restored")
		return
	var expected_provinces := roundi(
		float(WorldGenerator.TARGET_PROVINCES) * MapFactory.DEFAULT_WORLD_SCALE
		* MapFactory.DEFAULT_WORLD_SCALE
	)
	if not is_equal_approx(game.map_state.world_scale, MapFactory.DEFAULT_WORLD_SCALE):
		_fail("expected world scale %.1f, got %.1f" % [
			MapFactory.DEFAULT_WORLD_SCALE, game.map_state.world_scale,
		])
		return
	if game.map_state.province_count() != expected_provinces:
		_fail("expected %d provinces, got %d" % [
			expected_provinces, game.map_state.province_count(),
		])
		return
	if turn_manager.turn_number != TEST_TURN:
		_fail("expected turn %d, got %d" % [TEST_TURN, turn_manager.turn_number])
		return
	if game.get_gold(Balance.Faction.HUMANS) != TEST_GOLD:
		_fail("saved stockpile was not applied")
		return

	_restore_save()
	print("[loader] Continue OK: turn %d, stockpile and map restored" % TEST_TURN)
	quit(0)


func _backup_save() -> void:
	if FileAccess.file_exists(SaveSystem.SAVE_PATH):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SaveSystem.SAVE_PATH),
			ProjectSettings.globalize_path(BACKUP_PATH))


func _restore_save() -> void:
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(BACKUP_PATH),
			ProjectSettings.globalize_path(SaveSystem.SAVE_PATH))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	else:
		SaveSystem.delete_save()


func _fail(message: String) -> void:
	_restore_save()
	printerr("[loader] FAIL: %s" % message)
	quit(1)
