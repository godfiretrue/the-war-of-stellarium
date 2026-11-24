extends SceneTree
## Windowed check for the graphics presets.
##
## It drives the real main menu into a campaign, then cycles
## Low -> Medium -> High -> Low and verifies that each preset reapplies the
## render mode and rebuilds the map shaders without a crash. Run it WITHOUT
## --headless (the whole point is the real renderer):
##
##   godot --path . --resolution 800x450 --script res://scripts/tools/graphics_check.gd
##
## It restores the player's previous preset before quitting.

const TIMEOUT_MS := 20000


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("run this check without --headless")
		return

	var error := change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		_fail("cannot load main menu: %d" % error)
		return

	await process_frame
	var menu := current_scene
	if menu == null or not menu.has_method("_on_new_game"):
		_fail("main menu did not become the current scene")
		return
	menu._on_new_game()

	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.scene_file_path.ends_with("map.tscn"):
			break
	if current_scene == null or not current_scene.scene_file_path.ends_with("map.tscn"):
		_fail("map scene never loaded")
		return

	var settings := get_root().get_node_or_null("Settings") as GameSettings
	if settings == null:
		_fail("Settings autoload is missing")
		return

	var map := current_scene
	if map.state == null:
		_fail("map has no state")
		return

	print("[graphics] adapter: %s" % RenderingServer.get_video_adapter_name())
	print("[graphics] detected preset: %d" % settings.graphics_quality)

	var original := settings.graphics_quality
	for preset: int in [
		GameSettings.QUALITY_LOW,
		GameSettings.QUALITY_MEDIUM,
		GameSettings.QUALITY_HIGH,
		GameSettings.QUALITY_LOW,
	]:
		settings.set_quality(preset)
		for _i in 6:
			await process_frame
		if settings.graphics_quality != preset:
			_fail("preset %d was not applied" % preset)
			return
		var expected_mode := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS \
			if preset == GameSettings.QUALITY_HIGH else Window.CONTENT_SCALE_MODE_VIEWPORT
		if get_root().content_scale_mode != expected_mode:
			_fail("preset %d did not set the content scale mode" % preset)
			return
		if map.state == null:
			_fail("preset %d cleared the map state" % preset)
			return
		var water: ColorRect = map._water
		if water != null and water.visible != (preset > GameSettings.QUALITY_LOW):
			_fail("preset %d did not update the water layer" % preset)
			return
		print("[graphics] preset %d OK" % preset)

	settings.set_quality(original)
	for _i in 3:
		await process_frame

	await _check_panel(settings, original)

	print("[graphics] OK: presets rebuild cleanly, restored preset %d" % original)
	quit(0)


## Drives the real settings panel: picks every preset through the OptionButton
## and switches language, which is the path that rebuilds the item list from
## inside the control's own signal.
func _check_panel(settings: GameSettings, original_quality: int) -> void:
	var scene := load("res://scenes/ui/settings_panel.tscn") as PackedScene
	if scene == null:
		_fail("cannot load the settings panel")
		return
	var panel := scene.instantiate() as SettingsPanel
	if panel == null:
		_fail("settings panel scene is not a SettingsPanel")
		return
	get_root().add_child(panel)
	panel.open()
	await process_frame

	var option := panel.get_node(
		"Center/Panel/Column/QualityRow/QualityOption"
	) as OptionButton
	if option.item_count != 3:
		_fail("panel lists %d presets instead of 3" % option.item_count)
		return

	for index in option.item_count:
		option.select(index)
		option.item_selected.emit(index)
		for _i in 3:
			await process_frame
		if settings.graphics_quality != option.get_item_id(index):
			_fail("panel item %d did not set its preset" % index)
			return

	var original_language := settings.language
	var other := "en" if original_language == "pt" else "pt"
	settings.set_language(other)
	await process_frame
	if option.item_count != 3:
		_fail("language change duplicated the preset list")
		return
	var expected := "Low" if other == "en" else "Baixa"
	if option.get_item_text(0) != expected:
		_fail("preset labels did not retranslate (got '%s')" % option.get_item_text(0))
		return
	settings.set_language(original_language)
	settings.set_quality(original_quality)
	print("[graphics] panel OK: 3 presets, retranslate and reentrancy clean")
	panel.queue_free()


func _fail(message: String) -> void:
	printerr("[graphics] FAIL: %s" % message)
	quit(1)
