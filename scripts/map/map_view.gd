class_name MapView
extends Node2D
## Renders the procedurally generated continent and owns input and selection.
##
## Layers, bottom to top: terrain shader (relief, biomes, sea), province views
## (ownership tint, border, icons), overlay (rivers, march routes, orders).
## Game rules stay out of this node.
##
## The map is fitted to the window at zoom 1, then the player can pan with the
## middle mouse button and zoom with the wheel. Input is converted back into
## world space through this node's transform, so province hit-testing keeps
## matching the painted land at every zoom level.

signal province_clicked(province_id: String)
signal province_selected(province_id: String)

const PROVINCE_SCENE := preload("res://scenes/map/province.tscn")
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/pixel_water.gdshader")
const PLAYER := Balance.PLAYER_FACTION
const WORLD_SIZE := Vector2(1152, 648)
const DEEP_SEA := Color(0.03, 0.10, 0.20)
## Palette for the pixel-water layer: deep matches the backdrop, the rest are
## teal steps towards pale crest and foam.
const WATER_MID := Color(0.071, 0.353, 0.478)
const WATER_LIGHT := Color(0.180, 0.561, 0.659)
const WATER_CREST := Color(0.804, 0.918, 0.949)
const WATER_SHALLOW := Color(0.310, 0.710, 0.769)
const WATER_FOAM := Color(0.910, 0.969, 0.980)
const COAST_FADE_PX := 200.0
const ROAD_ACTIVE_COLOR := Color(1.0, 0.86, 0.35, 0.80)
const ARROW_HEAD := 13.0
const ARROW_TRIM := 36.0
const BADGE_RADIUS := 9.5
## View controls. Zoom 1 fits the whole world; higher values inspect the map.
const MIN_ZOOM := 1.0
const MAX_ZOOM := 4.0
const ZOOM_STEP := 1.2
const FOCUS_ZOOM := 1.55
## Below this zoom only cities keep their names, so a fitted map stays readable.
const LABEL_ZOOM := 1.35
## Recruit orders sit to the left of the army shield and stack upwards, clear
## of the castle plate and of the province name below.
const RECRUIT_BADGE_OFFSET := Vector2(-28, 4)
const RECRUIT_BADGE_STEP := -20.0
## Arrows leave from just above the army shield, not from under the name.
const ARROW_ANCHOR := Vector2(0, -4)

var state: MapState
var selected_province_id: String = ""
## Provinces the player may march into while a move is armed.
var _march_targets: PackedStringArray = PackedStringArray()
var _march_origin_id := ""
## Order currently hovered in the HUD list, so its arrow can light up.
var _hovered_order: Dictionary = {}

var game: GameState
var turn_manager: Node
var _settings: GameSettings
## Last graphics preset pushed to the shaders, so unrelated Settings changes
## (language, fullscreen) do not rebuild the map or reset the camera.
var _last_quality := -1

var _views: Dictionary = {}
var _hovered_province_id: String = ""
var _overlay: Node2D
var _terrain: ColorRect
var _water: ColorRect
var _base_scale := Vector2.ONE
## Current zoom relative to the fitted view (1.0 = whole world visible).
var _zoom := 1.0
## Screen-space offset of the map origin.
var _pan := Vector2.ZERO
var _panning := false
## Last zoom pushed to the province labels, so LOD only updates on change.
var _last_label_zoom := -1.0
## Last view_zoom pushed to the water shader; avoids setting the same uniform
## every frame while polling a Camera2D zoom (Camera2D has no zoom signal).
var _last_water_zoom := -1.0
var _focus_tween: Tween
## Clickable badge rectangles (world space) for queued player orders.
var _order_hits: Array = []


func _process(_delta: float) -> void:
	# Camera2D exposes no zoom-changed signal; polling is cheap and keeps the
	# pixel size correct even when a future camera script animates its zoom.
	_update_water_zoom()
	_update_label_detail()


func _ready() -> void:
	# The map fills the window at every resolution; the HUD lives in its own
	# CanvasLayer and is unaffected by this transform.
	get_viewport().size_changed.connect(_fit_world)
	_fit_world()

	# Rivers, march hints and order arrows live on a node above the province views.
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	# Above every province view (selected ones reach z_index 3) so a queued
	# arrow is never hidden by a bright selection border.
	_overlay.z_index = 4
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	game = get_node_or_null("/root/Game") as GameState
	turn_manager = get_node_or_null("/root/TurnManager")
	_settings = get_node_or_null("/root/Settings") as GameSettings
	if game == null or turn_manager == null:
		push_error("MapView: Game/TurnManager autoloads are missing")
		return

	game.state_changed.connect(_on_state_changed)
	game.orders_changed.connect(_on_orders_changed)
	turn_manager.phase_changed.connect(_on_phase_changed)
	if _settings != null:
		_last_quality = _settings.graphics_quality
		_settings.changed.connect(_on_settings_changed)

	if not game.is_started():
		turn_manager.start_game()

	state = game.map_state
	# The state carries the real world size, so fit again now that it is known.
	_fit_world()
	_build_terrain()
	# start_game() may already have emitted state_changed, which builds the
	# views through _rebuild_views(); never build the province set twice.
	if _views.is_empty():
		_build_views()
	_redraw_overlay()
	_log_map_summary()

	var capital := state.capital_of(Balance.PLAYER_FACTION)
	if capital != null:
		select_province(capital.id)


## Fit the whole world to the window at zoom 1. The map is then panned with
## the middle mouse button and zoomed with the wheel.
func _fit_world() -> void:
	var area := get_viewport().get_visible_rect().size
	if area.x < 2.0 or area.y < 2.0:
		return
	_cancel_focus_tween()
	_base_scale = area / _world_size()
	_zoom = MIN_ZOOM
	_pan = Vector2.ZERO
	_apply_view()


## World size in pixels, read from the generated map and falling back to the
## fixed MVP size before a game exists.
func _world_size() -> Vector2:
	if state != null and state.grid_size.x > 0 and state.grid_size.y > 0 and state.cell_size > 0:
		return Vector2(state.grid_size) * float(state.cell_size)
	return WORLD_SIZE


## Apply the current zoom and pan to the node transform, then refresh the
## view-dependent effects (water pixel size and label level of detail).
func _apply_view() -> void:
	scale = _base_scale * _zoom
	position = _pan
	_update_water_zoom()
	_update_label_detail()


## Zoom relative to the fitted view, derived from the actual node scale so a
## tween that writes `scale` directly stays consistent.
func _current_zoom() -> float:
	if _base_scale.x <= 0.0:
		return 1.0
	return scale.x / _base_scale.x


## Keep the map covering the viewport: the origin may not move past an edge,
## and a map smaller than the window is centred.
func _clamp_pan(candidate: Vector2, view_scale: Vector2) -> Vector2:
	var area := get_viewport().get_visible_rect().size
	var map_size := _world_size() * view_scale
	var result := candidate
	if map_size.x <= area.x:
		result.x = (area.x - map_size.x) * 0.5
	else:
		result.x = clampf(candidate.x, area.x - map_size.x, 0.0)
	if map_size.y <= area.y:
		result.y = (area.y - map_size.y) * 0.5
	else:
		result.y = clampf(candidate.y, area.y - map_size.y, 0.0)
	return result


## Cancel the battle-report focus animation, if one is running.
func _cancel_focus_tween() -> void:
	if _focus_tween != null:
		_focus_tween.kill()
		_focus_tween = null


## Read the transform back into the logical zoom/pan state after a tween or a
## direct scale/position change.
func _sync_view_state() -> void:
	_zoom = clampf(_current_zoom(), MIN_ZOOM, MAX_ZOOM)
	_pan = position


## Zoom towards a viewport point, keeping the world point under the cursor in
## place. The new pan is clamped so no background strip shows.
func _zoom_at(screen_point: Vector2, target_zoom: float) -> void:
	var world_point := to_local(screen_point)
	_zoom = clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
	var view_scale := _base_scale * _zoom
	_pan = _clamp_pan(screen_point - world_point * view_scale, view_scale)
	_apply_view()


## The overlay is created in _ready(), but the HUD is a child of this node and
## its _ready() runs first. A menu-started game already has map_state by then,
## so HUD refreshes can reach here before the overlay exists.
func _redraw_overlay() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			_pan += motion.relative
			_pan = _clamp_pan(_pan, scale)
			position = _pan
			get_viewport().set_input_as_handled()
		else:
			_update_hover(to_local(motion.position))
	elif event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_MIDDLE:
			if button_event.pressed:
				_cancel_focus_tween()
				_sync_view_state()
				_panning = true
			else:
				_panning = false
			get_viewport().set_input_as_handled()
			return
		if button_event.pressed and button_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_cancel_focus_tween()
			_sync_view_state()
			var factor := ZOOM_STEP if button_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
			_zoom_at(button_event.position, _zoom * factor)
			get_viewport().set_input_as_handled()
			return
		if button_event.pressed and button_event.button_index == MOUSE_BUTTON_LEFT:
			var world_point := to_local(button_event.position)
			if _try_cancel_badge(world_point):
				get_viewport().set_input_as_handled()
				return
			var province_id := province_at(button_event.position)
			if not province_id.is_empty():
				province_clicked.emit(province_id)
				get_viewport().set_input_as_handled()


## Province id under a viewport-space point, or "" over the sea.
## Resolved from the generator's label grid, so it matches the painted land.
func province_at(point: Vector2) -> String:
	return state.province_id_at(to_local(point))


func select_province(province_id: String) -> void:
	if state == null or not state.has_province(province_id):
		return

	selected_province_id = province_id
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		view.set_selected(view_id == province_id)
	province_selected.emit(province_id)
	_redraw_overlay()
	_log_selection(province_id)


func get_view(province_id: String) -> ProvinceView:
	var view: ProvinceView = _views.get(province_id, null)
	return view


## Gold borders on the provinces the armed army can reach. Passing an empty
## list clears the highlight; the HUD calls this when march mode starts/ends.
func set_march_targets(province_ids: PackedStringArray, origin_id: String = "") -> void:
	_march_targets = province_ids.duplicate()
	_march_origin_id = origin_id
	var active := not _march_targets.is_empty()
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		var valid := _march_targets.has(view_id)
		view.set_march_mode(active, valid)
	_redraw_overlay()


## Highlights the arrow and both provinces of an order hovered in the list.
func set_hovered_order(order: Dictionary) -> void:
	_hovered_order = order.duplicate(true) if not order.is_empty() else {}
	var key := _order_key(_hovered_order)
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		var involved := not key.is_empty() and _view_in_order(view_id)
		view.set_order_highlight(involved)
	_redraw_overlay()


## Camera focus used by the battle report: a short zoom onto the province that
## eases back to the full-map view.
func focus_province(province_id: String) -> void:
	if state == null:
		return
	var province := state.get_province(province_id)
	if province == null:
		return
	select_province(province_id)

	var area := get_viewport().get_visible_rect().size
	if area.x < 2.0 or area.y < 2.0:
		return
	_cancel_focus_tween()

	var target_scale := _base_scale * FOCUS_ZOOM
	var target_pos := Vector2(area.x * 0.5, area.y * 0.45) - province.map_position * target_scale
	target_pos = _clamp_pan(target_pos, target_scale)
	_focus_tween = create_tween()
	_focus_tween.tween_property(self, "scale", target_scale, 0.30) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.parallel().tween_property(self, "position", target_pos, 0.30) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_interval(0.65)
	_focus_tween.tween_property(self, "scale", _base_scale, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.parallel().tween_property(self, "position", Vector2.ZERO, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.finished.connect(_sync_view_state)


func refresh_all() -> void:
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		view.refresh()
	_redraw_overlay()


## The terrain is one world-sized rectangle painted by a shader that reads the
## generator's elevation/moisture image; the MapView transform stretches it to
## the window. A second, transparent-over-land rectangle paints pixel water on
## top using the same field image (its alpha holds distance from the coast).
func _build_terrain() -> void:
	var world_size := _world_size()
	var quality := _graphics_quality()

	if _terrain == null:
		_terrain = ColorRect.new()
		_terrain.name = "Terrain"
		_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_terrain.z_index = -2
		add_child(_terrain)
		move_child(_terrain, 0)
	_terrain.size = world_size

	if WATER_SHADER != null and _water == null:
		_water = ColorRect.new()
		_water.name = "Water"
		_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_water.z_index = -1
		add_child(_water)
		move_child(_water, 1)
	if _water != null:
		_water.size = world_size
		# The animated water pass is the second full-screen shader. Low hides it
		# and lets the terrain shader's flat sea show instead.
		_water.visible = quality > GameSettings.QUALITY_LOW

	if state == null or state.field_image == null:
		return

	# Both shaders sample the exact same pixels, so one texture is enough.
	var field_texture := ImageTexture.create_from_image(state.field_image)
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("field", field_texture)
	material.set_shader_parameter("grid_size", Vector2(state.grid_size))
	material.set_shader_parameter("world_size", world_size)
	material.set_shader_parameter("quality", quality)
	_terrain.material = material

	if _water != null and _water.visible:
		var water_material := ShaderMaterial.new()
		water_material.shader = WATER_SHADER
		water_material.set_shader_parameter("field", field_texture)
		water_material.set_shader_parameter("world_size", world_size)
		water_material.set_shader_parameter("sea_level", WorldGenerator.SEA_LEVEL)
		water_material.set_shader_parameter("depth_range", COAST_FADE_PX)
		water_material.set_shader_parameter("seed", float(state.map_seed & 0xFFFF))
		water_material.set_shader_parameter("quality", quality)
		water_material.set_shader_parameter("color_deep", DEEP_SEA)
		water_material.set_shader_parameter("color_mid", WATER_MID)
		water_material.set_shader_parameter("color_light", WATER_LIGHT)
		water_material.set_shader_parameter("color_crest", WATER_CREST)
		water_material.set_shader_parameter("color_shallow", WATER_SHALLOW)
		water_material.set_shader_parameter("color_foam", WATER_FOAM)
		_water.material = water_material
		_update_water_zoom()

	# The stretched map covers the window, so this only shows through during the
	# camera focus animation; keep it the same deep blue as the open sea.
	var backdrop := get_node_or_null("Background/Fill") as ColorRect
	if backdrop != null:
		backdrop.color = DEEP_SEA


## Keeps one water pixel the same size on screen when the view scale or a
## Camera2D's zoom changes. The map itself is world-anchored, so water never
## slides relative to the coast.
func _update_water_zoom() -> void:
	var zoom := scale.x
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		zoom *= camera.zoom.x
	zoom = maxf(zoom, 0.05)
	if is_equal_approx(zoom, _last_water_zoom):
		return
	_last_water_zoom = zoom
	if _water != null and _water.material != null:
		(_water.material as ShaderMaterial).set_shader_parameter("view_zoom", zoom)


## Cities keep their names at every zoom; open land only shows them once the
## player has zoomed in enough to read them without clutter.
func _update_label_detail() -> void:
	var zoom := _current_zoom()
	if is_equal_approx(zoom, _last_label_zoom):
		return
	_last_label_zoom = zoom
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		if is_instance_valid(view):
			view.set_view_zoom(zoom)


func _build_views() -> void:
	for province in state.provinces:
		var view: ProvinceView = PROVINCE_SCENE.instantiate()
		add_child(view)
		view.setup(province)
		view.set_view_zoom(_current_zoom())
		# Keep an armed march visible across a state rebuild.
		var valid := _march_targets.has(province.id)
		view.set_march_mode(not _march_targets.is_empty(), valid)
		_views[province.id] = view


func _rebuild_views() -> void:
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		if is_instance_valid(view):
			view.queue_free()
	_views.clear()
	_hovered_province_id = ""
	selected_province_id = ""
	_build_terrain()
	_build_views()
	_redraw_overlay()


func _on_state_changed() -> void:
	if game.map_state == null:
		return
	if state != game.map_state:
		state = game.map_state
		_fit_world()
		_rebuild_views()
	else:
		refresh_all()


func _on_phase_changed(_phase: int) -> void:
	refresh_all()


func _on_orders_changed() -> void:
	_redraw_overlay()


## Current graphics preset; High when Settings is unavailable (a bare MapView
## scene opened directly in the editor, for example).
func _graphics_quality() -> int:
	if _settings == null:
		return GameSettings.QUALITY_HIGH
	return _settings.graphics_quality


## A preset change also changes the window's content scale, so re-fit the view
## and rebuild the shader layers. Language/fullscreen changes are ignored here.
func _on_settings_changed() -> void:
	if _settings == null or _settings.graphics_quality == _last_quality:
		return
	_last_quality = _settings.graphics_quality
	_fit_world()
	_build_terrain()
	_redraw_overlay()


func _update_hover(world_point: Vector2) -> void:
	var province_id := state.province_id_at(world_point)
	if province_id == _hovered_province_id:
		return

	if not _hovered_province_id.is_empty():
		var previous: ProvinceView = _views.get(_hovered_province_id, null)
		if previous != null:
			previous.set_hovered(false)

	_hovered_province_id = province_id
	if not province_id.is_empty():
		var view: ProvinceView = _views.get(province_id, null)
		if view != null:
			view.set_hovered(true)


# --- Overlay -------------------------------------------------------------

## Rivers, queued orders and march routes, drawn above the provinces.
func _draw_overlay() -> void:
	if state == null or _overlay == null:
		return

	for river_index in state.rivers.size():
		var river := state.rivers[river_index]
		if river.size() < 2:
			continue
		var width := state.river_widths[river_index] if river_index < state.river_widths.size() else 2.0
		_overlay.draw_polyline(river, Color(0.03, 0.10, 0.16, 0.30), width * 1.55, true)
		_overlay.draw_polyline(river, Color(0.22, 0.45, 0.66, 0.90), width, true)
		_overlay.draw_polyline(river, Color(0.55, 0.75, 0.90, 0.26), maxf(width * 0.26, 0.6), true)

	_draw_queued_orders()
	_draw_march_hints()


## One curved arrow per queued march, with a troop-count badge at its middle.
## Recruits get a small badge on the province instead. Only the player's badges
## are clickable (the bot's orders cannot be cancelled from here).
func _draw_queued_orders() -> void:
	_order_hits.clear()
	if game == null:
		return

	var recruit_slots: Dictionary = {}
	for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
		var base_color := UiStyle.faction_color(faction)
		var orders := game.queued_orders_for(faction)
		for index in orders.size():
			var order: Dictionary = orders[index]
			var highlighted := _order_key(order) == _order_key(_hovered_order)
			var color := Color(base_color)
			color.a = 1.0 if highlighted else 0.86

			if String(order.get("type", "")) == "move":
				var from_province := state.get_province(String(order.get("from_id", "")))
				var to_province := state.get_province(String(order.get("to_id", "")))
				if from_province == null or to_province == null:
					continue
				var badge := _draw_arrow(
					from_province.map_position + ARROW_ANCHOR,
					to_province.map_position + ARROW_ANCHOR,
					color, highlighted
				)
				var count := CombatResolver.troop_count(order.get("units", {}))
				var rect := _draw_badge(badge, count, color, highlighted, BADGE_RADIUS)
				if faction == PLAYER and not rect.size.is_zero_approx():
					_order_hits.append({"rect": rect.grow(4.0), "index": index})
			elif String(order.get("type", "")) == "recruit":
				var province := state.get_province(String(order.get("province_id", "")))
				if province == null:
					continue
				# Recruits queued in the same province stack upwards instead of
				# hiding each other.
				var slot := int(recruit_slots.get(province.id, 0))
				recruit_slots[province.id] = slot + 1
				var point := province.map_position + RECRUIT_BADGE_OFFSET \
					+ Vector2(0, RECRUIT_BADGE_STEP * slot)
				var count := int(order.get("count", 1))
				var rect := _draw_badge(point, count, color, highlighted, BADGE_RADIUS - 1.0)
				if faction == PLAYER and not rect.size.is_zero_approx():
					_order_hits.append({"rect": rect.grow(4.0), "index": index})


func _draw_march_hints() -> void:
	if _march_origin_id.is_empty() or _march_targets.is_empty():
		return
	var origin := state.get_province(_march_origin_id)
	if origin == null:
		return

	for target_id: String in _march_targets:
		var target := state.get_province(target_id)
		if target == null:
			continue
		var direction := (target.map_position - origin.map_position).normalized()
		var from_point := origin.map_position + direction * 30.0
		var to_point := target.map_position - direction * 30.0
		if from_point.distance_to(to_point) > 12.0:
			_overlay.draw_dashed_line(from_point, to_point, ROAD_ACTIVE_COLOR, 2.4, 7.0, true)


## Quadratic curve between two provinces, trimmed so it does not cover the
## banners, with a triangular head. Returns the curve's midpoint for the badge.
func _draw_arrow(from_point: Vector2, to_point: Vector2, color: Color, highlighted: bool) -> Vector2:
	var delta := to_point - from_point
	if delta.length() < 1.0:
		return from_point

	var direction := delta.normalized()
	var side := direction.rotated(PI * 0.5)
	var span := delta.length()
	# Adjacent provinces are close together: a wide bow and a short trim keep
	# the curve visible instead of collapsing into a stub over the border.
	var bow := clampf(span * 0.30, 22.0, 70.0)
	var trim := clampf(span * 0.18, 18.0, ARROW_TRIM)
	var control := (from_point + to_point) * 0.5 + side * bow

	var points := PackedVector2Array()
	var steps := 24
	for step in steps + 1:
		var t := float(step) / float(steps)
		points.append(_bezier(from_point, control, to_point, t))

	var midpoint := _bezier(from_point, control, to_point, 0.5)

	var start_index := 0
	while start_index < points.size() - 3 and points[start_index].distance_to(from_point) < trim:
		start_index += 1
	var end_index := points.size() - 1
	while end_index > start_index + 2 and points[end_index].distance_to(to_point) < trim:
		end_index -= 1
	if end_index - start_index < 3:
		return midpoint

	var visible := points.slice(start_index, end_index + 1)
	var width := 5.6 if highlighted else 4.2

	_overlay.draw_polyline(visible, Color(0.02, 0.03, 0.05, 0.90), width + 3.0, true)
	_overlay.draw_polyline(visible, color, width, true)
	# A pale core keeps the arrow readable where the faction colour is close to
	# the province border colour.
	_overlay.draw_polyline(visible, color.lerp(Color.WHITE, 0.45), maxf(width * 0.32, 1.0), true)

	var tip := visible[visible.size() - 1]
	var tangent := (tip - visible[visible.size() - 2]).normalized()
	var head_side := tangent.rotated(PI * 0.5)
	_overlay.draw_colored_polygon(PackedVector2Array([
		tip + tangent * 2.0,
		tip - tangent * ARROW_HEAD + head_side * 6.5,
		tip - tangent * ARROW_HEAD - head_side * 6.5,
	]), color)
	return midpoint


func _draw_badge(center: Vector2, count: int, color: Color, highlighted: bool, radius: float) -> Rect2:
	_overlay.draw_circle(center, radius + 2.0, Color(0.02, 0.03, 0.05, 0.90))
	_overlay.draw_circle(center, radius, Color(0.06, 0.08, 0.13, 0.97))
	_overlay.draw_arc(center, radius, 0.0, TAU, 24, color, 2.0 if not highlighted else 2.8, true)

	var font := ThemeDB.fallback_font
	var font_size := 11
	var text := str(count)
	var text_width := font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x
	_overlay.draw_string(
		font,
		center + Vector2(-text_width * 0.5, font_size * 0.36),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)
	return Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)


func _try_cancel_badge(world_point: Vector2) -> bool:
	if game == null:
		return false
	for hit in _order_hits:
		var rect: Rect2 = hit["rect"]
		if rect.has_point(world_point):
			game.cancel_order(PLAYER, int(hit["index"]))
			return true
	return false


func _order_key(order: Dictionary) -> String:
	if order.is_empty():
		return ""
	return "%s:%s:%s:%s" % [
		String(order.get("type", "")),
		String(order.get("from_id", "")),
		String(order.get("to_id", "")),
		String(order.get("province_id", "")),
	]


func _view_in_order(province_id: String) -> bool:
	return province_id == String(_hovered_order.get("from_id", "")) \
		or province_id == String(_hovered_order.get("to_id", "")) \
		or province_id == String(_hovered_order.get("province_id", ""))


static func _bezier(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	var inverse := 1.0 - t
	return a * (inverse * inverse) + control * (2.0 * inverse * t) + b * (t * t)


# --- Diagnostics ---------------------------------------------------------

func _edge_count() -> int:
	var total := 0
	for province in state.provinces:
		total += province.neighbors.size()
	return int(total / 2.0)


func _log_map_summary() -> void:
	print("[map] seed %d: %d provinces, %d edges, %d rivers" % [
		state.map_seed, state.province_count(), _edge_count(), state.rivers.size(),
	])
	for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
		var owned := state.provinces_owned_by(faction)
		var troops := 0
		for province in owned:
			troops += province.total_troops()
		print("[map] %s owns %d provinces with %d troops" % [
			Balance.faction_name(faction), owned.size(), troops,
		])


func _log_selection(province_id: String) -> void:
	var province := state.get_province(province_id)
	if province == null:
		return

	var neighbor_labels: PackedStringArray = PackedStringArray()
	for neighbor_id: String in province.neighbors:
		var neighbor := state.get_province(neighbor_id)
		if neighbor != null:
			neighbor_labels.append("%s (%s)" % [
				neighbor.display_name, Balance.faction_name(neighbor.owner_faction),
			])

	print("[map] selected %s | %s | %s | %s | %d troops [%s] | capital=%s | neighbours: %s" % [
		province.display_name,
		province.territory_type,
		Balance.faction_name(province.owner_faction),
		Balance.terrain_name(province.terrain),
		province.total_troops(),
		province.garrison_summary(),
		str(province.is_capital),
		", ".join(neighbor_labels),
	])
