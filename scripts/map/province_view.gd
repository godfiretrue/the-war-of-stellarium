class_name ProvinceView
extends Node2D
## Visual for one ProvinceData on the procedurally generated continent.
##
## The land itself (relief, biomes, sea) is painted by the terrain shader in
## MapView; this node only adds what the player needs to read at a glance:
## - ownership tint and a coloured border along the province outline
## - castle icon in cities (recruitment hubs), small waypoint in open land
## - tactical shield with the troop count

const RADIUS := 54.0
const SIDES := 6

const COLOR_BORDER := Color(0.06, 0.08, 0.12, 0.95)
const COLOR_BORDER_SELECTED := Color(1.0, 0.86, 0.30, 1.0)
const COLOR_BORDER_HOVER := Color(0.95, 0.98, 1.0, 1.0)
const COLOR_BORDER_NEUTRAL := Color(0.10, 0.08, 0.06, 0.60)

@onready var _fill: Polygon2D = $Fill
@onready var _border: Line2D = $Border
@onready var _visuals: Node2D = $Visuals
@onready var _name_label: Label = $Name
@onready var _info_label: Label = $Info

var data: ProvinceData
var _selected := false
var _hovered := false
var _connected_draw := false


func setup(province: ProvinceData) -> void:
	data = province
	position = province.map_position
	name = "Province_%s" % province.id

	var shape: PackedVector2Array = province.polygon if province.polygon.size() >= 3 else _hexagon(RADIUS)
	_fill.polygon = shape
	_border.points = _closed(shape)
	_border.joint_mode = Line2D.LINE_JOINT_ROUND

	# Label placements: clean, uncrowded
	_name_label.offset_left = -80
	_name_label.offset_right = 80
	_name_label.offset_top = -6
	_name_label.offset_bottom = 12
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Dark outline keeps names readable over forest, rock and snow.
	_name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.06, 0.95))
	_name_label.add_theme_constant_override("outline_size", 4)

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

	_name_label.text = data.display_name
	if data.is_capital:
		_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
		_name_label.add_theme_font_size_override("font_size", 13)
	elif data.is_city:
		_name_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
		_name_label.add_theme_font_size_override("font_size", 12)
	else:
		_name_label.add_theme_color_override("font_color", Color(0.88, 0.91, 0.95))
		_name_label.add_theme_font_size_override("font_size", 11)

	# Troop badge only when troops are present.
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
	if data != null:
		_fill.color = _province_color()
	_apply_border()
	if _visuals != null:
		_visuals.queue_redraw()


func set_hovered(value: bool) -> void:
	_hovered = value
	if data != null:
		_fill.color = _province_color()
	_apply_border()
	if _visuals != null:
		_visuals.queue_redraw()


func _apply_border() -> void:
	var owned := data != null and not data.is_neutral()
	if _selected:
		_border.default_color = COLOR_BORDER_SELECTED
		_border.width = 3.2
		z_index = 2
	elif _hovered:
		_border.default_color = COLOR_BORDER_HOVER
		_border.width = 2.8
		z_index = 1
	else:
		if owned:
			_border.default_color = _faction_line_color()
			_border.width = 2.2
		else:
			_border.default_color = COLOR_BORDER_NEUTRAL
			_border.width = 1.2
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


## Faint ownership wash over the terrain; the border line carries the strong
## colour. Neutral land stays untinted so its natural colours show.
func _province_color() -> Color:
	var tint := Color(0.0, 0.0, 0.0, 0.0)
	match data.owner_faction:
		Balance.Faction.HUMANS:
			tint = Color(0.30, 0.55, 1.0, 0.13)
		Balance.Faction.ELVES:
			tint = Color(0.25, 0.85, 0.45, 0.11)
	if _hovered or _selected:
		tint.a = maxf(tint.a, 0.0) + 0.07
		if data.is_neutral():
			tint = Color(1.0, 1.0, 1.0, 0.10)
	return tint


# --- Visual Drawing (Icons & Shields) -----------------------------------

func _on_visuals_draw() -> void:
	if data == null:
		return

	if data.is_capital:
		_draw_capital_icon()
	elif data.is_city:
		if String(data.territory_type).begins_with("Fortress"):
			_draw_fortress_icon()
		else:
			_draw_town_icon()
	else:
		_draw_waypoint_icon()

	if data.total_troops() > 0:
		_draw_army_shield()


func _draw_capital_icon() -> void:
	var center := Vector2(0, -21)
	var gold := Color(1.0, 0.86, 0.35)
	var dark := Color(0.08, 0.10, 0.14, 0.95)

	_visuals.draw_rect(Rect2(center + Vector2(-12, -7), Vector2(24, 16)), dark)
	_visuals.draw_rect(Rect2(center + Vector2(-9, -9), Vector2(18, 4)), gold)
	_visuals.draw_rect(Rect2(center + Vector2(-9, -13), Vector2(4, 4)), gold)
	_visuals.draw_rect(Rect2(center + Vector2(5, -13), Vector2(4, 4)), gold)
	_visuals.draw_rect(Rect2(center + Vector2(-5, -5), Vector2(10, 10)), gold)
	_visuals.draw_rect(Rect2(center + Vector2(-1.5, 0), Vector2(3, 5)), dark)

	var star := center + Vector2(0, -19)
	_visuals.draw_circle(star, 3.2, Color(1.0, 0.92, 0.45))
	_visuals.draw_circle(star, 1.5, Color.WHITE)


## Town: three shuttered houses on a dark plate, smaller than a capital.
func _draw_town_icon() -> void:
	var center := Vector2(0, -18)
	var wall := Color(0.93, 0.95, 0.99)
	var dark := Color(0.08, 0.10, 0.14, 0.95)

	_visuals.draw_rect(Rect2(center + Vector2(-12, -3), Vector2(24, 8)), dark)
	for offset: Vector2 in [Vector2(-8, -2), Vector2(0, -6), Vector2(8, -2)]:
		var base := center + offset
		_visuals.draw_rect(Rect2(base + Vector2(-3, -1), Vector2(6, 5)), wall)
		_visuals.draw_colored_polygon(PackedVector2Array([
			base + Vector2(-4.5, 0), base + Vector2(0, -5), base + Vector2(4.5, 0),
		]), wall)


## Fortress: a single tall tower with battlements.
func _draw_fortress_icon() -> void:
	var center := Vector2(0, -20)
	var stone := Color(0.84, 0.88, 0.93)
	var dark := Color(0.08, 0.10, 0.14, 0.95)

	_visuals.draw_rect(Rect2(center + Vector2(-10, -6), Vector2(20, 14)), dark)
	_visuals.draw_rect(Rect2(center + Vector2(-6, -9), Vector2(12, 14)), stone)
	_visuals.draw_rect(Rect2(center + Vector2(-6, -13), Vector2(3, 4)), stone)
	_visuals.draw_rect(Rect2(center + Vector2(-1.5, -13), Vector2(3, 4)), stone)
	_visuals.draw_rect(Rect2(center + Vector2(3, -13), Vector2(3, 4)), stone)
	_visuals.draw_rect(Rect2(center + Vector2(-2, 0), Vector2(4, 5)), dark)


## Open land: a small hollow diamond, the classic "road waypoint" marker.
## No castle means no recruitment, and nothing else competes with the relief.
func _draw_waypoint_icon() -> void:
	var center := Vector2(0, -15)
	var radius := 4.5
	var diamond := PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0),
		center + Vector2(0, -radius),
	])
	_visuals.draw_polyline(diamond, Color(0.02, 0.04, 0.06, 0.8), 3.0, true)
	_visuals.draw_polyline(diamond, Color(0.93, 0.95, 0.98, 0.9), 1.4, true)


func _draw_army_shield() -> void:
	var center := Vector2(0, 18)
	var shield_pts := PackedVector2Array([
		center + Vector2(-12, -7),
		center + Vector2(12, -7),
		center + Vector2(12, 2),
		center + Vector2(0, 13),
		center + Vector2(-12, 2),
	])

	var border_col := Color(1.0, 0.86, 0.35) if data.is_owned_by(Balance.Faction.HUMANS) else Color(0.55, 0.95, 0.65)
	if data.is_neutral():
		border_col = Color(0.75, 0.78, 0.84)

	_visuals.draw_colored_polygon(shield_pts, Color(0.08, 0.10, 0.14, 0.95))
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
