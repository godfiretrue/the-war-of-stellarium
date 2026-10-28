class_name MapView
extends Node2D
## Renders the province graph, draws adjacency edges and owns map input and
## selection. Game rules stay out of this node.
##
## The Game and TurnManager singletons are resolved through the tree so this
## script parses cleanly in editors with a stale autoload cache.

signal province_clicked(province_id: String)
signal province_selected(province_id: String)

const PROVINCE_SCENE := preload("res://scenes/map/province.tscn")
const EDGE_COLOR := Color(0.56, 0.58, 0.63, 0.55)
const EDGE_WIDTH := 5.0

var state: MapState
var selected_province_id: String = ""

var game: GameState
var turn_manager: Node

var _views: Dictionary = {}
var _hovered_province_id: String = ""


func _ready() -> void:
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
	_log_selection(province_id)


func get_view(province_id: String) -> ProvinceView:
	var view: ProvinceView = _views.get(province_id, null)
	return view


func refresh_all() -> void:
	for view_id: String in _views.keys():
		var view: ProvinceView = _views[view_id]
		view.refresh()


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


func _draw() -> void:
	if state == null:
		return

	var drawn_edges: Dictionary = {}
	for province in state.provinces:
		for neighbor_id: String in province.neighbors:
			var edge_key := "%s|%s" % [province.id, neighbor_id]
			var reverse_key := "%s|%s" % [neighbor_id, province.id]
			if drawn_edges.has(edge_key) or drawn_edges.has(reverse_key):
				continue
			var other := state.get_province(neighbor_id)
			if other == null:
				continue
			draw_line(province.map_position, other.map_position, EDGE_COLOR, EDGE_WIDTH, true)
			drawn_edges[edge_key] = true


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

	print("[map] selected %s | %s | %s | %d troops [%s] | capital=%s | neighbours: %s" % [
		province.display_name,
		Balance.faction_name(province.owner_faction),
		Balance.terrain_name(province.terrain),
		province.total_troops(),
		province.garrison_summary(),
		str(province.is_capital),
		", ".join(neighbor_labels),
	])
