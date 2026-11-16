class_name MapView
extends Node2D
## Renders the procedurally generated continent and owns input and selection.
##
## Layers, bottom to top: terrain shader (relief, biomes, sea), province views
## (ownership tint, border, icons), overlay (rivers, march routes).
## Game rules stay out of this node.

signal province_clicked(province_id: String)
signal province_selected(province_id: String)

const PROVINCE_SCENE := preload("res://scenes/map/province.tscn")
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WORLD_SIZE := Vector2(1152, 648)
const DEEP_SEA := Color(0.03, 0.10, 0.20)
const ROAD_COLOR := Color(0.95, 0.95, 0.98, 0.28)
const ROAD_ACTIVE_COLOR := Color(1.0, 0.86, 0.35, 0.80)
const ROAD_WIDTH := 2.0

var state: MapState
var selected_province_id: String = ""

var game: GameState
var turn_manager: Node

var _views: Dictionary = {}
var _hovered_province_id: String = ""
var _overlay: Node2D
var _terrain: ColorRect


func _ready() -> void:
	# Rivers and march routes live on a node above the province views.
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.z_index = 1
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	game = get_node_or_null("/root/Game") as GameState
	turn_manager = get_node_or_null("/root/TurnManager")
	if game == null or turn_manager == null:
		push_error("MapView: Game/TurnManager autoloads are missing")
		return

	game.state_changed.connect(_on_state_changed)
	turn_manager.phase_changed.connect(_on_phase_changed)

	if not game.is_started():
		turn_manager.start_game()

	state = game.map_state
	_build_terrain()
	_build_views()
	_overlay.queue_redraw()
	_log_map_summary()

	var capital := state.capital_of(Balance.PLAYER_FACTION)
	if capital != null:
		select_province(capital.id)


func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return

	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.pressed and button_event.button_index == MOUSE_BUTTON_LEFT:
			var province_id := province_at(button_event.position)
			if not province_id.is_empty():
				province_clicked.emit(province_id)
				get_viewport().set_input_as_handled()


## Province id under a viewport-space point, or "" over the sea.
## Resolved from the generator's label grid, so it matches the painted land.
func province_at(point: Vector2) -> String:
	return state.province_id_at(point)


func select_province(province_id: String) -> void:
	if state == null or not state.has_province(province_id):
		return

	selected_province_id = province_id
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		view.set_selected(view_id == province_id)
	province_selected.emit(province_id)
	_overlay.queue_redraw()
	_log_selection(province_id)


func get_view(province_id: String) -> ProvinceView:
	var view: ProvinceView = _views.get(province_id, null)
	return view


func refresh_all() -> void:
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		view.refresh()
	_overlay.queue_redraw()


## The terrain is one full-world rectangle painted by a shader that reads the
## generator's elevation/moisture image.
func _build_terrain() -> void:
	if _terrain == null:
		_terrain = ColorRect.new()
		_terrain.name = "Terrain"
		_terrain.size = WORLD_SIZE
		_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_terrain.z_index = -1
		add_child(_terrain)
		move_child(_terrain, 0)

	if state == null or state.field_image == null:
		return

	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("field", ImageTexture.create_from_image(state.field_image))
	material.set_shader_parameter("grid_size", Vector2(state.grid_size))
	material.set_shader_parameter("world_size", WORLD_SIZE)
	_terrain.material = material

	# Window is wider than the world when stretched: keep the edges sea-coloured.
	var backdrop := get_node_or_null("Background/Fill") as ColorRect
	if backdrop != null:
		backdrop.color = DEEP_SEA


func _build_views() -> void:
	for province in state.provinces:
		var view: ProvinceView = PROVINCE_SCENE.instantiate()
		add_child(view)
		view.setup(province)
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
	_overlay.queue_redraw()


func _on_state_changed() -> void:
	if game.map_state == null:
		return
	if state != game.map_state:
		state = game.map_state
		_rebuild_views()
	else:
		refresh_all()


func _on_phase_changed(_phase: int) -> void:
	refresh_all()


func _update_hover(point: Vector2) -> void:
	var province_id := province_at(point)
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


## Rivers and march routes, drawn above the provinces.
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

	# March routes: only the selected province's links, so the map does not
	# end up covered in dashed lines.
	var selected_province := state.get_province(selected_province_id) if not selected_province_id.is_empty() else null
	if selected_province == null:
		return

	for neighbor_id: String in selected_province.neighbors:
		var other := state.get_province(neighbor_id)
		if other == null:
			continue
		var direction := (other.map_position - selected_province.map_position).normalized()
		var from_point := selected_province.map_position + direction * 34.0
		var to_point := other.map_position - direction * 34.0
		if from_point.distance_to(to_point) > 12.0:
			_overlay.draw_dashed_line(from_point, to_point, ROAD_ACTIVE_COLOR, 2.6, 6.0, true)


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
