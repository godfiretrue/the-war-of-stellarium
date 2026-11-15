class_name ProvinceView
extends Area2D
## Visual for one ProvinceData on the continental map.
##
## Intuitive, visual-first representation:
## - Fortified Castles / Cities: Visible Castle & Keep icons (Instantly signals recruitment hub)
## - Corridors / Open Fields: Landscape & Waypoint icons (Instantly signals open transit & field battles)
## - Armies: Tactical military shield token with troop count (No text clutter)

const RADIUS := 54.0
const SIDES := 6

const FACTION_COLORS := {
	Balance.Faction.HUMANS: Color(0.20, 0.38, 0.68, 0.90),
	Balance.Faction.ELVES: Color(0.14, 0.48, 0.28, 0.90),
	Balance.Faction.NEUTRAL: Color(0.26, 0.29, 0.34, 0.85),
}

const TERRAIN_SHADE := {
	Balance.Terrain.PLAINS: 1.0,
	Balance.Terrain.MOUNTAINS: 0.74,
}

const COLOR_BORDER := Color(0.06, 0.08, 0.12, 0.95)
const COLOR_BORDER_CORRIDOR := Color(0.16, 0.19, 0.25, 0.80)
const COLOR_BORDER_SELECTED := Color(1.0, 0.86, 0.30, 1.0)
const COLOR_BORDER_HOVER := Color(0.95, 0.98, 1.0, 1.0)

@onready var _fill: Polygon2D = $Fill
@onready var _border: Line2D = $Border
@onready var _hit: CollisionPolygon2D = $Hit
@onready var _visuals: Node2D = $Visuals
@onready var _name_label: Label = $Name
@onready var _info_label: Label = $Info

var data: ProvinceData
var _selected := false
var _hovered := false
var _connected_draw := false
var _decor: Array[Dictionary] = []


func setup(province: ProvinceData) -> void:
	data = province
	position = province.map_position
	name = "Province_%s" % province.id
	input_pickable = false

	var shape: PackedVector2Array = province.polygon if province.polygon.size() >= 3 else _hexagon(RADIUS)
	_fill.polygon = shape
	_hit.polygon = shape
	_border.points = _closed(shape)

	# Painted terrain: sample a shared world-sized texture in world coordinates
	# so neighbouring provinces of the same terrain flow into each other.
	var world_uv := PackedVector2Array()
	for point in shape:
		world_uv.append(point + province.map_position)
	_fill.texture = TerrainTextures.get_texture(TerrainTextures.kind_for(province))
	_fill.uv = world_uv
	_build_decor(shape)

	# Label placements: clean, uncrowded
	_name_label.offset_left = -80
	_name_label.offset_right = 80
	_name_label.offset_top = -6
	_name_label.offset_bottom = 12
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_info_label.offset_left = -80
	_info_label.offset_right = 80
	_info_label.offset_top = 10
	_info_label.offset_bottom = 30
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if not _connected_draw and _visuals != null:
		_visuals.draw.connect(_on_visuals_draw)
		_connected_draw = true

	refresh()


func refresh() -> void:
	if data == null:
		return

	_fill.color = _province_color()

	# Name label: clean single line
	_name_label.text = data.display_name
	if data.is_capital:
		_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
		_name_label.add_theme_font_size_override("font_size", 13)
	elif data.is_city:
		_name_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		_name_label.add_theme_font_size_override("font_size", 12)
	else:
		_name_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
		_name_label.add_theme_font_size_override("font_size", 11)

	# Info label: only shows troop badge if troops are present!
	var troops := data.total_troops()
	if troops > 0:
		_info_label.text = "%d" % troops
		_info_label.add_theme_color_override("font_color", Color.WHITE)
		_info_label.add_theme_font_size_override("font_size", 12)
	else:
		_info_label.text = ""

	_apply_border()
	if _visuals != null:
		_visuals.queue_redraw()


func set_selected(value: bool) -> void:
	_selected = value
	_apply_border()
	if _visuals != null:
		_visuals.queue_redraw()


func set_hovered(value: bool) -> void:
	_hovered = value
	_apply_border()
	if _visuals != null:
		_visuals.queue_redraw()


func hit_polygon() -> PackedVector2Array:
	return _hit.polygon


func _apply_border() -> void:
	var owned := data != null and not data.is_neutral()
	var faction_line := _faction_line_color()
	if _selected:
		_border.default_color = COLOR_BORDER_SELECTED
		_border.width = 4.5
		z_index = 2
	elif _hovered:
		_border.default_color = COLOR_BORDER_HOVER
		_border.width = 3.5
		z_index = 1
	else:
		if owned:
			_border.default_color = faction_line
			_border.width = 3.0
		else:
			_border.default_color = Color(0.13, 0.10, 0.07, 0.75)
			_border.width = 1.8
		z_index = 0


func _faction_line_color() -> Color:
	if data == null:
		return COLOR_BORDER
	match data.owner_faction:
		Balance.Faction.HUMANS:
			return Color(0.35, 0.60, 1.0, 0.95)
		Balance.Faction.ELVES:
			return Color(0.30, 0.90, 0.50, 0.95)
	return COLOR_BORDER


## Light ownership tint multiplied over the painted terrain: the land keeps
## its natural look, the border line carries the strong ownership colour.
func _province_color() -> Color:
	match data.owner_faction:
		Balance.Faction.HUMANS:
			return Color(0.72, 0.82, 1.0)
		Balance.Faction.ELVES:
			return Color(0.76, 1.0, 0.86)
	return Color(1.0, 1.0, 1.0)


# --- Terrain decoration --------------------------------------------------

## Deterministic scatter of trees / peaks / hills so every province reads as
## a landscape. Kept away from the icon, name and troop shield area.
func _build_decor(shape: PackedVector2Array) -> void:
	_decor.clear()
	if data == null or shape.size() < 3:
		return

	var kind := TerrainTextures.kind_for(data)
	var wanted := 7
	match kind:
		"forest":
			wanted = 22
		"mountain":
			wanted = 10
		_:
			wanted = 7

	var rect := Rect2(shape[0], Vector2.ZERO)
	for point in shape:
		rect = rect.expand(point)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(data.id)

	var attempts := 0
	while _decor.size() < wanted and attempts < 500:
		attempts += 1
		var candidate := Vector2(
			rng.randf_range(rect.position.x, rect.end.x),
			rng.randf_range(rect.position.y, rect.end.y),
		)
		if not Geometry2D.is_point_in_polygon(candidate, shape):
			continue
		if absf(candidate.x) < 46.0 and candidate.y > -42.0 and candidate.y < 38.0:
			continue
		if _edge_distance(candidate, shape) < 9.0:
			continue
		var crowded := false
		for entry: Dictionary in _decor:
			if (entry["pos"] as Vector2).distance_to(candidate) < 15.0:
				crowded = true
				break
		if crowded:
			continue
		_decor.append({"pos": candidate, "scale": rng.randf_range(0.8, 1.25), "tone": rng.randf()})

	# Back to front, so lower items overlap the ones behind them.
	_decor.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector2).y < (b["pos"] as Vector2).y
	)


static func _edge_distance(point: Vector2, shape: PackedVector2Array) -> float:
	var best := INF
	var count := shape.size()
	for index in count:
		var closest := Geometry2D.get_closest_point_to_segment(point, shape[index], shape[(index + 1) % count])
		best = minf(best, point.distance_to(closest))
	return best


func _draw_decor() -> void:
	var kind := TerrainTextures.kind_for(data)
	for entry: Dictionary in _decor:
		var pos: Vector2 = entry["pos"]
		var size: float = entry["scale"]
		var tone: float = entry["tone"]
		match kind:
			"forest":
				_draw_tree(pos, size, tone, true)
			"mountain":
				_draw_peak(pos, size, tone)
			_:
				if tone > 0.72:
					_draw_tree(pos, size * 0.8, tone, false)
				else:
					_draw_hill(pos, size)


func _draw_tree(pos: Vector2, size: float, tone: float, dense: bool) -> void:
	var green := Color(0.08, 0.26, 0.12).lerp(Color(0.16, 0.38, 0.17), tone)
	if not dense:
		green = green.lightened(0.1)
	_visuals.draw_rect(Rect2(pos + Vector2(-1.2, -2.0) * size, Vector2(2.4, 4.0) * size), Color(0.25, 0.16, 0.09))
	_visuals.draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-6.0, -1.0) * size, pos + Vector2(6.0, -1.0) * size, pos + Vector2(0.0, -10.0) * size,
	]), green.darkened(0.15))
	_visuals.draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-4.5, -6.0) * size, pos + Vector2(4.5, -6.0) * size, pos + Vector2(0.0, -14.0) * size,
	]), green)


func _draw_peak(pos: Vector2, size: float, tone: float) -> void:
	var half := 11.0 * size
	var height := (16.0 + tone * 6.0) * size
	var apex := pos + Vector2(0.0, -height)
	# Shaded side, lit side, snow cap.
	_visuals.draw_colored_polygon(PackedVector2Array([pos + Vector2(-half, 0.0), apex, pos + Vector2(1.0, 0.0)]), Color(0.36, 0.33, 0.31))
	_visuals.draw_colored_polygon(PackedVector2Array([apex, pos + Vector2(half, 0.0), pos + Vector2(1.0, 0.0)]), Color(0.60, 0.57, 0.53))
	_visuals.draw_colored_polygon(PackedVector2Array([
		apex, apex + Vector2(-3.6, height * 0.3), apex + Vector2(-0.5, height * 0.22), apex + Vector2(2.0, height * 0.32), apex + Vector2(4.0, height * 0.28),
	]), Color(0.95, 0.96, 0.98))


func _draw_hill(pos: Vector2, size: float) -> void:
	var col := Color(0.30, 0.42, 0.18, 0.75)
	_visuals.draw_arc(pos, 7.0 * size, PI * 1.12, PI * 1.88, 8, col, 1.6, true)
	_visuals.draw_arc(pos + Vector2(8.0, 2.0) * size, 5.0 * size, PI * 1.12, PI * 1.88, 8, col, 1.4, true)


# --- Visual Drawing (Icons & Shields) -----------------------------------

func _on_visuals_draw() -> void:
	if data == null:
		return

	_draw_decor()

	if data.is_city:
		_draw_castle_icon()
	else:
		_draw_corridor_icon()

	if data.total_troops() > 0:
		_draw_army_shield()


func _draw_castle_icon() -> void:
	var center := Vector2(0, -20)
	var col := Color(1.0, 0.86, 0.35) if data.is_capital else Color(0.92, 0.94, 0.98)
	var dark := Color(0.08, 0.10, 0.14, 0.95)

	# Base shadow backing
	_visuals.draw_rect(Rect2(center + Vector2(-15, -12), Vector2(30, 18)), dark)

	# Central Keep Tower
	_visuals.draw_rect(Rect2(center + Vector2(-7, -10), Vector2(14, 15)), col)
	# Battlements
	_visuals.draw_rect(Rect2(center + Vector2(-7, -14), Vector2(4, 4)), col)
	_visuals.draw_rect(Rect2(center + Vector2(3, -14), Vector2(4, 4)), col)

	# Left Flank Tower
	_visuals.draw_rect(Rect2(center + Vector2(-14, -6), Vector2(7, 11)), col)
	_visuals.draw_rect(Rect2(center + Vector2(-14, -9), Vector2(7, 3)), col)

	# Right Flank Tower
	_visuals.draw_rect(Rect2(center + Vector2(7, -6), Vector2(7, 11)), col)
	_visuals.draw_rect(Rect2(center + Vector2(7, -9), Vector2(7, 3)), col)

	# Arched Gate
	_visuals.draw_rect(Rect2(center + Vector2(-3, 0), Vector2(6, 6)), dark)

	# Capital Star
	if data.is_capital:
		var star_pos := center + Vector2(0, -18)
		_visuals.draw_circle(star_pos, 4.0, Color(1.0, 0.92, 0.45))
		_visuals.draw_circle(star_pos, 2.0, Color.WHITE)


func _draw_corridor_icon() -> void:
	var center := Vector2(0, -18)

	if data.terrain == Balance.Terrain.MOUNTAINS:
		# Stylized Mountain Peaks
		var peak1 := PackedVector2Array([center + Vector2(-12, 4), center + Vector2(-5, -10), center + Vector2(2, 4)])
		var peak2 := PackedVector2Array([center + Vector2(-2, 4), center + Vector2(6, -14), center + Vector2(14, 4)])
		_visuals.draw_colored_polygon(peak1, Color(0.48, 0.52, 0.58, 0.9))
		_visuals.draw_colored_polygon(peak2, Color(0.62, 0.66, 0.72, 0.9))
		# White Snowcap
		var snow := PackedVector2Array([center + Vector2(4, -14), center + Vector2(6, -14), center + Vector2(8, -10), center + Vector2(3, -10)])
		_visuals.draw_colored_polygon(snow, Color.WHITE)
	else:
		# Rolling Plain / Road Waypoint
		var col := Color(0.85, 0.88, 0.94, 0.65)
		_visuals.draw_arc(center + Vector2(-6, 2), 7.0, PI * 1.1, PI * 1.9, 6, col, 1.8, true)
		_visuals.draw_arc(center + Vector2(6, 2), 7.0, PI * 1.1, PI * 1.9, 6, col, 1.8, true)
		_visuals.draw_circle(center + Vector2(0, -2), 2.2, Color(0.95, 0.98, 1.0, 0.85))


func _draw_army_shield() -> void:
	var center := Vector2(0, 18)
	var shield_pts := PackedVector2Array([
		center + Vector2(-12, -7),
		center + Vector2(12, -7),
		center + Vector2(12, 2),
		center + Vector2(0, 13),
		center + Vector2(-12, 2)
	])

	var border_col := Color(1.0, 0.86, 0.35) if data.is_owned_by(Balance.Faction.HUMANS) else Color(0.55, 0.95, 0.65)
	if data.is_neutral():
		border_col = Color(0.75, 0.78, 0.84)

	# Shield background
	_visuals.draw_colored_polygon(shield_pts, Color(0.08, 0.10, 0.14, 0.95))
	# Shield border
	var closed_shield := PackedVector2Array(shield_pts)
	closed_shield.append(shield_pts[0])
	_visuals.draw_polyline(closed_shield, border_col, 2.0, true)


static func _hexagon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in SIDES:
		var angle := TAU * float(index) / float(SIDES) - PI / 2.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array(points)
	if points.size() > 0:
		result.append(points[0])
	return result
