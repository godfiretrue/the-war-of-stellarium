class_name MapView
extends Node2D
## Renders the continental world map, marching routes, and owns input and selection.
##
## Game rules stay out of this node.

signal province_clicked(province_id: String)
signal province_selected(province_id: String)

const PROVINCE_SCENE := preload("res://scenes/map/province.tscn")
const ROAD_COLOR := Color(0.85, 0.88, 0.95, 0.22)
const ROAD_ACTIVE_COLOR := Color(1.0, 0.86, 0.35, 0.65)
const ROAD_WIDTH := 2.0

var state: MapState
var selected_province_id: String = ""

var game: GameState
var turn_manager: Node

var _views: Dictionary = {}
var _hovered_province_id: String = ""
var _overlay: Node2D


func _ready() -> void:
	# Rivers and march routes live on a node above the painted provinces.
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
	_build_views()
	queue_redraw()
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


## Province id under a viewport-space point, or "" when the point is off-map.
func province_at(point: Vector2) -> String:
	for province in state.provinces:
		var view: ProvinceView = _views.get(province.id, null)
		if view == null:
			continue
		var local_point := point - province.map_position
		if Geometry2D.is_point_in_polygon(local_point, view.hit_polygon()):
			return province.id
	return ""


func select_province(province_id: String) -> void:
	if state == null or not state.has_province(province_id):
		return

	selected_province_id = province_id
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		view.set_selected(view_id == province_id)
	province_selected.emit(province_id)
	queue_redraw()
	_log_selection(province_id)


func get_view(province_id: String) -> ProvinceView:
	var view: ProvinceView = _views.get(province_id, null)
	return view


func refresh_all() -> void:
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		view.refresh()
	queue_redraw()


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
	_build_views()
	queue_redraw()


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
	queue_redraw()


## Ocean, coastal shallows and foam. Drawn before (under) the province views.
func _draw() -> void:
	if state == null:
		return

	var ocean := TerrainTextures.get_texture("ocean")
	if not ocean.changed.is_connected(queue_redraw):
		ocean.changed.connect(queue_redraw)
	draw_texture_rect(ocean, Rect2(-300, -200, 1800, 1100), false)

	var coast := state.coastline
	if coast.size() < 3:
		return
	var ring := PackedVector2Array(coast)
	ring.append(coast[0])
	draw_polyline(ring, Color(0.0, 0.04, 0.10, 0.20), 78.0, true)
	draw_polyline(ring, Color(0.10, 0.38, 0.50, 0.14), 56.0, true)
	draw_polyline(ring, Color(0.16, 0.50, 0.58, 0.16), 38.0, true)
	draw_polyline(ring, Color(0.28, 0.62, 0.68, 0.20), 22.0, true)
	draw_polyline(ring, Color(0.80, 0.93, 0.95, 0.55), 5.0, true)


## River and march routes. Drawn above the land by a child node with a higher
## z_index, because the painted provinces would otherwise hide them.
func _draw_overlay() -> void:
	if state == null or _overlay == null:
		return

	_draw_river()

	var drawn_edges: Dictionary = {}
	var selected_province := state.get_province(selected_province_id) if not selected_province_id.is_empty() else null

	for province in state.provinces:
		for neighbor_id: String in province.neighbors:
			var edge_key := "%s|%s" % [province.id, neighbor_id]
			var reverse_key := "%s|%s" % [neighbor_id, province.id]
			if drawn_edges.has(edge_key) or drawn_edges.has(reverse_key):
				continue
			var other := state.get_province(neighbor_id)
			if other == null:
				continue

			var is_active_route := false
			if selected_province != null:
				if (province.id == selected_province_id and neighbor_id in selected_province.neighbors) or \
				   (neighbor_id == selected_province_id and province.id in selected_province.neighbors):
					is_active_route = true

			var col := ROAD_ACTIVE_COLOR if is_active_route else ROAD_COLOR
			var width := 3.0 if is_active_route else ROAD_WIDTH

			# Stop short of the icons and troop shields at both ends.
			var direction := (other.map_position - province.map_position).normalized()
			var from_point := province.map_position + direction * 38.0
			var to_point := other.map_position - direction * 38.0
			if from_point.distance_to(to_point) > 12.0:
				_overlay.draw_dashed_line(from_point, to_point, col, width, 7.0, true)
			drawn_edges[edge_key] = true


const RIVER_POINTS := [
	Vector2(558, 60), Vector2(580, 120), Vector2(548, 175), Vector2(566, 235), Vector2(540, 290),
	Vector2(562, 345), Vector2(548, 395), Vector2(572, 445), Vector2(560, 492),
]


func _draw_river() -> void:
	var curve := Curve2D.new()
	var count := RIVER_POINTS.size()
	for index in count:
		var point: Vector2 = RIVER_POINTS[index]
		var previous: Vector2 = RIVER_POINTS[maxi(index - 1, 0)]
		var following: Vector2 = RIVER_POINTS[mini(index + 1, count - 1)]
		var tangent := (following - previous) * 0.22
		curve.add_point(point, -tangent, tangent)
	var path := curve.tessellate(5, 3.0)
	_overlay.draw_polyline(path, Color(0.05, 0.12, 0.16, 0.55), 6.5, true)
	_overlay.draw_polyline(path, Color(0.30, 0.58, 0.78, 0.95), 4.0, true)
	_overlay.draw_polyline(path, Color(0.62, 0.82, 0.94, 0.55), 1.4, true)


func _edge_count() -> int:
	var total := 0
	for province in state.provinces:
		total += province.neighbors.size()
	return int(total / 2.0)


func _log_map_summary() -> void:
	print("[map] %d provinces, %d edges" % [state.province_count(), _edge_count()])
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
