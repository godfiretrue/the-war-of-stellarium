class_name ProvinceView
extends Area2D
## Visual for one ProvinceData.
##
## The node owns no game rules and no input: MapView hit-tests the polygon and
## calls set_selected()/set_hovered(). Keeping input in one place makes the
## click path testable and avoids per-node event plumbing.

const RADIUS := 54.0
const SIDES := 6

const FACTION_COLORS := {
	Balance.Faction.HUMANS: Color(0.24, 0.42, 0.75),
	Balance.Faction.ELVES: Color(0.16, 0.55, 0.32),
	Balance.Faction.NEUTRAL: Color(0.40, 0.41, 0.45),
}

## Mountains are drawn darker so terrain reads at a glance.
const TERRAIN_SHADE := {
	Balance.Terrain.PLAINS: 1.0,
	Balance.Terrain.MOUNTAINS: 0.76,
}

const COLOR_BORDER := Color(0.07, 0.08, 0.10, 0.9)
const COLOR_BORDER_SELECTED := Color(1.0, 0.85, 0.35)
const COLOR_BORDER_HOVER := Color(0.95, 0.95, 0.98, 0.9)

@onready var _fill: Polygon2D = $Fill
@onready var _border: Line2D = $Border
@onready var _hit: CollisionPolygon2D = $Hit
@onready var _name_label: Label = $Name
@onready var _info_label: Label = $Info

var data: ProvinceData

var _selected := false
var _hovered := false


func setup(province: ProvinceData) -> void:
	data = province
	position = province.map_position
	name = "Province_%s" % province.id
	input_pickable = false

	var shape := _hexagon(RADIUS)
	_fill.polygon = shape
	_hit.polygon = shape
	_border.points = _closed(shape)

	refresh()


func refresh() -> void:
	if data == null:
		return

	_fill.color = _province_color()
	_name_label.text = data.display_name

	var owner_text := Balance.faction_name(data.owner_faction)
	if data.is_capital:
		owner_text += " capital"
	_info_label.text = "%s\n%s\n%d troops" % [
		owner_text,
		Balance.terrain_name(data.terrain),
		data.total_troops(),
	]
	_apply_border()


func set_selected(value: bool) -> void:
	_selected = value
	_apply_border()


func set_hovered(value: bool) -> void:
	_hovered = value
	_apply_border()


## Polygon in the province's local space, used by MapView for click tests.
func hit_polygon() -> PackedVector2Array:
	return _hit.polygon


func _apply_border() -> void:
	if _selected:
		_border.default_color = COLOR_BORDER_SELECTED
		_border.width = 4.0
	elif _hovered:
		_border.default_color = COLOR_BORDER_HOVER
		_border.width = 4.0
	else:
		_border.default_color = COLOR_BORDER
		_border.width = 3.0


func _province_color() -> Color:
	var base: Color = FACTION_COLORS.get(data.owner_faction, FACTION_COLORS[Balance.Faction.NEUTRAL])
	var shade: float = TERRAIN_SHADE.get(data.terrain, 1.0)
	return Color(base.r * shade, base.g * shade, base.b * shade, 1.0)


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
