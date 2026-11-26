extends SceneTree
## Headless integration check for the march forecast panel.
##
## Drives the real main menu into a campaign, opens march mode from the player's
## capital, hovers a neighbour and verifies the preview appears and clears.
##
##   godot --headless --path . --script res://scripts/tools/preview_hud_check.gd

const TIMEOUT_MS := 20000


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	# Headless defaults to a tiny window; force the 1152x648 layout we ship.
	get_root().size = Vector2i(1152, 648)
	await process_frame
	var error := change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		_fail("cannot load main menu")
		return
	await process_frame
	var menu := current_scene
	if menu == null or not menu.has_method("_on_new_game"):
		_fail("main menu did not load")
		return
	menu._on_new_game()

	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.scene_file_path.ends_with("map.tscn"):
			break
	for _i in 5:
		await process_frame

	var hud := current_scene.get_node_or_null("HUD") as GameHUD
	var game := get_root().get_node_or_null("Game") as GameState
	if hud == null or game == null or game.map_state == null:
		_fail("campaign HUD is missing")
		return

	var domination := hud.get_node_or_null(
		"Root/TopBar/TopMargin/TopRow/Domination") as Label
	var turn_badge := hud.get_node_or_null(
		"Root/TopBar/TopMargin/TopRow/TurnBadge") as Control
	if domination == null or turn_badge == null:
		_fail("domination progress label is missing")
		return
	if domination.text.is_empty() or not domination.text.contains("/"):
		_fail("domination progress text is empty")
		return
	if domination.get_global_rect().end.x > turn_badge.get_global_rect().position.x:
		_fail("domination label overlaps the turn badge")
		return

	var capital := game.map_state.capital_of(Balance.PLAYER_FACTION)
	if capital == null or capital.neighbors.is_empty():
		_fail("player capital has no neighbours")
		return
	hud._select(capital.id)
	hud._on_march_pressed()
	if hud.march_origin_id != capital.id:
		_fail("march mode did not open")
		return

	# A wildland has no defence, so its forecast is the single "free capture"
	# line rather than a power band. Use a held neighbour to test the band.
	var target_id := ""
	for neighbor_id: String in capital.neighbors:
		var neighbor := game.map_state.get_province(neighbor_id)
		if neighbor != null and not neighbor.is_wildland():
			target_id = neighbor_id
			break
	if target_id.is_empty():
		_fail("capital has no defended neighbour")
		return
	hud._on_map_hover(target_id)
	if not hud._preview_card.visible:
		_fail("preview did not appear for a neighbour")
		return
	if hud._preview_title.text.is_empty() or hud._preview_note.text.is_empty():
		_fail("preview text is empty")
		return
	var rect := hud._preview_card.get_global_rect()
	if rect.position.x < 300.0 or rect.end.x > 852.0 or rect.end.y > 456.0:
		_fail("preview panel overlaps a HUD card or map controls: %s" % rect)
		return

	hud._march_count.value = 1
	if not hud._preview_card.visible or hud._preview_band.text.is_empty():
		_fail("changing troop count did not refresh the preview")
		return

	hud._on_map_hover("nonexistent")
	if hud._preview_card.visible:
		_fail("preview stayed visible for a non-neighbour")
		return

	hud._cancel_march()
	if hud._preview_card.visible or hud._march_panel.visible:
		_fail("cancelling march did not clear the preview")
		return

	print("[preview] OK: forecast shown, refreshed and cleared")
	quit(0)


func _fail(message: String) -> void:
	printerr("[preview] FAIL: %s" % message)
	quit(1)
