extends SceneTree
## Headless integration check for the threaded loading path (New Game).
##
## Run from the project folder:
##   godot --headless --path . --script res://scripts/tools/loader_check.gd
##
## It drives the real main menu through New Game, waits for the worker thread
## and the scene change, then verifies that the campaign map arrived intact.

const TIMEOUT_MS := 20000


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var error := change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		_fail("cannot load main menu: %d" % error)
		return

	await process_frame
	var menu := current_scene
	if menu == null or not menu.has_method("_on_new_game"):
		_fail("main menu did not become the current scene")
		return

	# Drive the real New Game button and setup panel, not an internal shortcut:
	# pressing the button must open the panel, then Start must begin loading.
	var new_game: Button = menu.get_node("%NewGame") as Button
	var panel = menu.get_node("%NewGamePanel")
	new_game.pressed.emit()
	if panel == null or not panel.visible:
		_fail("New Game did not open the setup panel")
		return
	panel.confirmed.emit({
		"seed": -1,
		"world_scale": MapFactory.DEFAULT_WORLD_SCALE,
		"difficulty": Balance.Difficulty.NORMAL,
	})

	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.scene_file_path.ends_with("map.tscn"):
			break

	if current_scene == null or not current_scene.scene_file_path.ends_with("map.tscn"):
		_fail("map scene never loaded")
		return

	# The loading screen fades out a couple of frames after the scene change.
	for _i in 5:
		await process_frame

	var game := get_root().get_node_or_null("Game") as GameState
	if game == null or game.map_state == null:
		_fail("game state is missing after loading")
		return
	if not is_equal_approx(game.map_state.world_scale, MapFactory.DEFAULT_WORLD_SCALE):
		_fail("expected world scale %.1f, got %.1f" % [MapFactory.DEFAULT_WORLD_SCALE, game.map_state.world_scale])
		return
	var expected := roundi(float(WorldGenerator.TARGET_PROVINCES)
			* MapFactory.DEFAULT_WORLD_SCALE * MapFactory.DEFAULT_WORLD_SCALE)
	if game.map_state.province_count() != expected:
		_fail("expected %d provinces, got %d" % [expected, game.map_state.province_count()])
		return
	if game.map_state.grid_size != Vector2i(576, 324):
		_fail("expected a 576x324 grid, got %s" % game.map_state.grid_size)
		return
	for faction: int in game.factions():
		if game.map_state.provinces_owned_by(faction).is_empty():
			_fail("faction %d owns no provinces" % faction)
			return

	var loading_screen := get_root().get_node_or_null("LoadingScreen")
	if loading_screen != null and loading_screen.is_active():
		_fail("loading screen is still active after the map loaded")
		return

	print("[loader] OK: %d provinces, map scene ready" % game.map_state.province_count())
	quit(0)


func _fail(message: String) -> void:
	printerr("[loader] FAIL: %s" % message)
	quit(1)
