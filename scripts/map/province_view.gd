class_name ProvinceView
extends Node2D
## Visual for one ProvinceData on the procedurally generated continent.
##
## The land itself (relief, biomes, sea) is painted by the terrain shader in
## MapView; this node only adds what the player needs to read at a glance:
## - ownership tint and a coloured border along the province outline
## - castle icon in cities (recruitment hubs), small waypoint in open land
## - tactical shield with the troop count

const FOG_SHADER := preload("res://shaders/fog.gdshader")

const RADIUS := 54.0
const SIDES := 6
## Below this zoom only cities keep their names; open land labels would clutter
## a fitted map.
const LABEL_ZOOM := 1.35

const COLOR_BORDER := Color(0.06, 0.08, 0.12, 0.95)
const COLOR_BORDER_SELECTED := Color(1.0, 0.86, 0.30, 1.0)
const COLOR_BORDER_HOVER := Color(0.95, 0.98, 1.0, 1.0)
const COLOR_BORDER_NEUTRAL := Color(0.10, 0.08, 0.06, 0.60)
## Unscouted land keeps a faint cool outline so the map still reads as a map,
## without revealing who owns the province.
const COLOR_BORDER_UNKNOWN := Color(0.36, 0.42, 0.55, 0.30)
## Reachable neighbours while a march is armed (also drawn as routes).
const COLOR_BORDER_MARCH := Color(1.0, 0.72, 0.22, 0.95)
## Soft halo layers drawn outside the selected outline. Offsetting the polygon
## (instead of stroking it with a fat brush) keeps the corners clean.
const COLOR_GLOW_OUTER := Color(1.0, 0.86, 0.30, 0.09)
const COLOR_GLOW_INNER := Color(1.0, 0.86, 0.30, 0.15)
const COLOR_ICON_PLATE := Color(0.045, 0.060, 0.085, 0.90)

static var _plate_box: StyleBoxFlat

@onready var _fill: Polygon2D = $Fill
@onready var _fog: Polygon2D = $Fog
@onready var _border: Line2D = $Border
@onready var _visuals: Node2D = $Visuals
@onready var _name_label: Label = $Name
@onready var _info_label: Label = $Info

var data: ProvinceData
var _selected := false
var _hovered := false
var _march_target := false
var _march_mode := false
var _order_highlight := false
var _connected_draw := false
## Current map zoom, used for label level of detail.
var _view_zoom := 1.0
## Fog of war: remembered terrain and live troop intelligence are separate.
var _explored := true
var _intel := true


func setup(province: ProvinceData) -> void:
	data = province
	position = province.map_position
	name = "Province_%s" % province.id

	var shape: PackedVector2Array = province.polygon if province.polygon.size() >= 3 else _hexagon(RADIUS)
	_fill.polygon = shape

	# Every province owns its material because the shader's grain offset is the
	# province's world position. The palette comes from UiStyle so fog shares
	# the campaign's colour language.
	_fog.polygon = shape
	var fog_material := ShaderMaterial.new()
	fog_material.shader = FOG_SHADER
	fog_material.set_shader_parameter("world_origin", data.map_position)
	fog_material.set_shader_parameter("fog_base", UiStyle.BG)
	fog_material.set_shader_parameter("pixel_size", 4.0)
	_fog.material = fog_material

	_border.points = _closed(shape)
	_border.joint_mode = Line2D.LINE_JOINT_ROUND
	_border.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_border.end_cap_mode = Line2D.LINE_CAP_ROUND
	_border.antialiased = true

	# The banner and its troop count own the lower half of the province; the
	# name sits underneath so neither ever overlaps the other.
	_name_label.offset_left = -80
	_name_label.offset_right = 80
	_name_label.offset_top = 20
	_name_label.offset_bottom = 36
	# Labels stay above the arrow overlay so a route never hides a province name.
	_name_label.z_index = 5
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Dark outline keeps names readable over forest, rock and snow.
	_name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.06, 0.95))
	_name_label.add_theme_constant_override("outline_size", 4)

	# The count now lives inside the drawn shield; the old text plate would
	# only compete with it.
	_info_label.visible = false
	_info_label.text = ""

	if not _connected_draw and _visuals != null:
		_visuals.draw.connect(_on_visuals_draw)
		_connected_draw = true

	refresh()


func refresh() -> void:
	if data == null:
		return

	_fill.color = _province_color()
	_apply_fog_state()

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

	_update_label_visibility()

	# The troop count is drawn inside the army banner; no text plate is needed.
	_info_label.text = ""
	_info_label.visible = false

	_apply_border()
	if _visuals != null:
		_visuals.queue_redraw()


func set_selected(value: bool) -> void:
	_selected = value
	if data != null:
		_fill.color = _province_color()
	_apply_border()
	_update_label_visibility()
	if _visuals != null:
		_visuals.queue_redraw()


func set_hovered(value: bool) -> void:
	_hovered = value
	if data != null:
		_fill.color = _province_color()
	_apply_border()
	_update_label_visibility()
	if _visuals != null:
		_visuals.queue_redraw()


## Highlight used while the player is choosing a march destination.
func set_march_target(value: bool) -> void:
	_march_target = value
	_apply_border()


## March mode draws valid targets softly and dims every other province so the
## reachable set reads instantly. Leaving the mode restores the normal map.
func set_march_mode(active: bool, valid: bool) -> void:
	_march_mode = active
	_march_target = active and valid
	if data != null:
		_fill.color = _province_color()
	_apply_border()
	if _visuals != null:
		_visuals.queue_redraw()


## Both endpoints of an order hovered in the queue list.
func set_order_highlight(active: bool) -> void:
	if _order_highlight == active:
		return
	_order_highlight = active
	_apply_border()
	if _visuals != null:
		_visuals.queue_redraw()


## Map zoom changed: show every name once the player is close enough, while
## cities stay named at any zoom.
func set_view_zoom(value: float) -> void:
	if is_equal_approx(value, _view_zoom):
		return
	_view_zoom = value
	_update_label_visibility()


## Called by MapView after every board change. Explored terrain stays drawn;
## hidden garrisons (including ambushes) lose their army shield and number.
func set_intel(explored: bool, intel: bool) -> void:
	if _explored == explored and _intel == intel:
		return
	_explored = explored
	_intel = intel
	refresh()


func _update_label_visibility() -> void:
	# A remembered city name would reveal intelligence the fog is hiding.
	if data == null or not _explored or not _intel:
		_name_label.visible = false
		return
	_name_label.visible = data.is_city or _view_zoom >= LABEL_ZOOM \
		or _selected or _hovered


func _apply_border() -> void:
	# Faction colours are intelligence: without it an owned province still gets
	# only the faint neutral outline. Gold/white UI highlights remain, because
	# they are player feedback (selection, hover, march) rather than map info.
	var owned := _intel and data != null and not data.is_neutral()
	if _selected:
		_border.default_color = COLOR_BORDER_SELECTED
		_border.width = 4.0
		z_index = 3
	elif _order_highlight:
		_border.default_color = Color(1.0, 0.93, 0.68, 1.0)
		_border.width = 3.4
		z_index = 2
	elif _hovered:
		_border.default_color = COLOR_BORDER_HOVER
		_border.width = 3.2
		z_index = 2
	elif _march_target:
		_border.default_color = COLOR_BORDER_MARCH
		_border.width = 3.2
		z_index = 1
	elif _march_mode:
		_border.default_color = Color(0.30, 0.31, 0.36, 0.55)
		_border.width = 1.6
		z_index = 0
	else:
		if owned:
			_border.default_color = _faction_line_color()
			_border.width = 2.6
		else:
			_border.default_color = COLOR_BORDER_UNKNOWN if not _intel else COLOR_BORDER_NEUTRAL
			_border.width = 1.4 if not _intel else 1.8
		z_index = 0


## Three fog states: unknown land is opaque, remembered land is dithered, and
## visible land hides the veil so the normal ownership tint reads unchanged.
func _apply_fog_state() -> void:
	if _fog == null or _fog.material == null:
		return
	var mode := 2
	if _explored:
		mode = 0 if _intel else 1
	_fog.visible = mode != 0
	(_fog.material as ShaderMaterial).set_shader_parameter("fog_mode", mode)


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
## colour. Neutral land stays untinted so its natural colours show. Fog is a
## separate polygon, so this layer never darkens the terrain directly.
func _province_color() -> Color:
	# Without live intelligence no ownership or garrison tint may leak through
	# the remembered-terrain veil. The border still shows the explored outline.
	if not _intel:
		return Color(0.0, 0.0, 0.0, 0.0)
	# While a march target is being chosen, everything out of reach recedes.
	if _march_mode and not _march_target and not _selected:
		return Color(0.010, 0.015, 0.030, 0.34)

	var tint := Color(0.0, 0.0, 0.0, 0.0)
	match data.owner_faction:
		Balance.Faction.HUMANS:
			tint = Color(0.30, 0.55, 1.0, 0.13)
		Balance.Faction.ELVES:
			tint = Color(0.25, 0.85, 0.45, 0.11)
	if _march_target:
		tint = Color(1.0, 0.86, 0.35, 0.16)
	elif _hovered or _selected or _order_highlight:
		tint.a = maxf(tint.a, 0.0) + 0.08
		if data.is_neutral():
			tint = Color(1.0, 1.0, 1.0, 0.11)
	return tint


# --- Visual Drawing (Icons & Shields) -----------------------------------

func _on_visuals_draw() -> void:
	if data == null or not _explored:
		return

	if data.is_impassable and _intel:
		_draw_peak_marker()
	if data.ambush and data.owner_faction == Balance.PLAYER_FACTION:
		_draw_ambush_badge()
	if not _intel:
		return

	if _selected:
		_draw_selection_glow()

	if data.is_capital:
		_draw_capital_icon()
	elif data.is_city:
		if data.is_fortress:
			_draw_fortress_icon()
		else:
			_draw_town_icon()
	elif data.terrain == Balance.Terrain.HIGHLANDS:
		_draw_highland_icon()
	else:
		_draw_waypoint_icon()

	if data.total_troops() > 0:
		_draw_army_shield()


func _draw_capital_icon() -> void:
	var center := Vector2(0, -21)
	var gold := Color(1.0, 0.86, 0.35)
	var dark := Color(0.08, 0.10, 0.14, 0.95)

	_draw_plate(Rect2(center + Vector2(-13, -8), Vector2(26, 18)))
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

	_draw_plate(Rect2(center + Vector2(-11, -9), Vector2(22, 18)))
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


## Defensive high ground: a small crenellated ridge, distinct from a waypoint.
func _draw_highland_icon() -> void:
	var center := Vector2(0, -15)
	var stone := Color(0.92, 0.94, 0.98, 0.92)
	_visuals.draw_line(
		center + Vector2(-9, 5), center + Vector2(0, -6), stone, 2.0, true
	)
	_visuals.draw_line(
		center + Vector2(0, -6), center + Vector2(9, 5), stone, 2.0, true
	)
	_visuals.draw_line(
		center + Vector2(-10, 6), center + Vector2(10, 6), stone, 2.0, true
	)


## Consistent faction-coloured shield with the troop count drawn inside it.
func _draw_army_shield() -> void:
	var center := Vector2(0, 6)
	var half_width := 10.0
	var shield_pts := PackedVector2Array([
		center + Vector2(-half_width, -7),
		center + Vector2(half_width, -7),
		center + Vector2(half_width, 2),
		center + Vector2(0, 12),
		center + Vector2(-half_width, 2),
	])

	var border_col := _faction_line_color()
	if data.is_neutral():
		border_col = Color(0.75, 0.78, 0.84)

	_visuals.draw_colored_polygon(shield_pts, Color(0.06, 0.08, 0.12, 0.96))
	var closed_shield := PackedVector2Array(shield_pts)
	closed_shield.append(shield_pts[0])
	_visuals.draw_polyline(closed_shield, border_col, 2.0, true)

	var font := ThemeDB.fallback_font
	var font_size := 10
	var text := str(data.total_troops())
	var text_width := font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x
	_visuals.draw_string(
		font,
		center + Vector2(-text_width * 0.5, font_size * 0.36),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)


## A crossed ridge marks ground that can never be marched through.
func _draw_peak_marker() -> void:
	var center := Vector2(0, -17)
	var color := Color(0.94, 0.96, 1.0, 0.85)
	_visuals.draw_line(
		center + Vector2(-9, 7), center + Vector2(0, -8), color, 2.0, true
	)
	_visuals.draw_line(
		center + Vector2(0, -8), center + Vector2(9, 7), color, 2.0, true
	)
	_visuals.draw_line(
		center + Vector2(-7, 7), center + Vector2(7, 7), Color(0.05, 0.06, 0.09, 0.9), 3.0, true
	)


## Slashed eye over your own hidden garrison. The enemy never draws this.
func _draw_ambush_badge() -> void:
	var center := Vector2(16, -18)
	var color := Color(1.0, 0.62, 0.32, 0.95)
	_draw_plate(Rect2(center + Vector2(-9, -7), Vector2(18, 14)))
	_visuals.draw_circle(center, 4.2, color)
	_visuals.draw_circle(center, 1.8, Color(0.05, 0.06, 0.09, 0.95))
	_visuals.draw_line(
		center + Vector2(-5, 5), center + Vector2(5, -5), color, 1.6, true
	)


## Two clean halo bands outside the province outline.
func _draw_selection_glow() -> void:
	var shape: PackedVector2Array = _fill.polygon
	if shape.size() < 3:
		return
	for layer: Array in [[8.0, COLOR_GLOW_OUTER], [4.5, COLOR_GLOW_INNER]]:
		var pieces := Geometry2D.offset_polygon(shape, float(layer[0]), Geometry2D.JOIN_ROUND)
		for piece: PackedVector2Array in pieces:
			_visuals.draw_colored_polygon(piece, layer[1])


## Rounded dark plate behind a map icon, so white glyphs never fight the relief.
func _draw_plate(rect: Rect2) -> void:
	if _plate_box == null:
		_plate_box = StyleBoxFlat.new()
		_plate_box.bg_color = COLOR_ICON_PLATE
		_plate_box.set_corner_radius_all(3)
	_visuals.draw_style_box(_plate_box, rect)


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
