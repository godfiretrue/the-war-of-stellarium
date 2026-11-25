class_name UiIcon
extends Control
## Tiny procedural glyph used by the campaign HUD (resource chips, garrison
## tiles, order rows).
##
## The HUD draws every icon from primitives instead of font glyphs so it never
## depends on emoji coverage in the system font and keeps one visual weight.

enum Kind { COIN, MANPOWER, ETHER, SHIELD, MOVE, RECRUIT, SWORD, BOW, AMBUSH }

@export var kind: Kind = Kind.COIN:
	set(value):
		kind = value
		queue_redraw()

@export var tint: Color = UiStyle.GOLD:
	set(value):
		tint = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	if radius < 1.0:
		return
	match kind:
		Kind.COIN:
			_draw_coin(center, radius)
		Kind.MANPOWER:
			_draw_manpower(center, radius)
		Kind.ETHER:
			_draw_ether(center, radius)
		Kind.SHIELD:
			_draw_shield(center, radius)
		Kind.MOVE:
			_draw_move(center, radius)
		Kind.RECRUIT:
			_draw_recruit(center, radius)
		Kind.SWORD:
			_draw_sword(center, radius)
		Kind.BOW:
			_draw_bow(center, radius)
		Kind.AMBUSH:
			_draw_ambush(center, radius)


func _draw_coin(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 0.92, _alpha(0.18))
	draw_arc(center, radius * 0.90, 0.0, TAU, 24, tint, 1.4, true)
	draw_circle(center, radius * 0.34, tint)


func _draw_manpower(center: Vector2, radius: float) -> void:
	draw_circle(center + Vector2(0, -radius * 0.40), radius * 0.32, tint)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-radius * 0.66, radius * 0.80),
		center + Vector2(-radius * 0.52, radius * 0.28),
		center + Vector2(0, radius * 0.10),
		center + Vector2(radius * 0.52, radius * 0.28),
		center + Vector2(radius * 0.66, radius * 0.80),
	]), tint)


func _draw_ether(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -radius * 0.95),
		center + Vector2(radius * 0.66, 0),
		center + Vector2(0, radius * 0.95),
		center + Vector2(-radius * 0.66, 0),
	])
	draw_colored_polygon(points, _alpha(0.30))
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, tint, 1.3, true)
	draw_line(
		center + Vector2(0, -radius * 0.95),
		center + Vector2(0, radius * 0.95),
		_alpha(0.45), 1.0, true
	)


func _draw_shield(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(-radius * 0.70, -radius * 0.78),
		center + Vector2(radius * 0.70, -radius * 0.78),
		center + Vector2(radius * 0.70, radius * 0.05),
		center + Vector2(0, radius * 0.88),
		center + Vector2(-radius * 0.70, radius * 0.05),
	])
	draw_colored_polygon(points, _alpha(0.22))
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, tint, 1.3, true)


func _draw_move(center: Vector2, radius: float) -> void:
	draw_line(
		center + Vector2(-radius * 0.85, 0),
		center + Vector2(radius * 0.30, 0),
		tint, 1.6, true
	)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(radius * 0.82, 0),
		center + Vector2(radius * 0.18, -radius * 0.46),
		center + Vector2(radius * 0.18, radius * 0.46),
	]), tint)


func _draw_recruit(center: Vector2, radius: float) -> void:
	draw_line(
		center + Vector2(-radius * 0.72, 0), center + Vector2(radius * 0.72, 0),
		tint, 2.0, true
	)
	draw_line(
		center + Vector2(0, -radius * 0.72), center + Vector2(0, radius * 0.72),
		tint, 2.0, true
	)


func _alpha(value: float) -> Color:
	return Color(tint.r, tint.g, tint.b, value)


func _draw_sword(center: Vector2, radius: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius * 0.95),
		center + Vector2(radius * 0.26, -radius * 0.62),
		center + Vector2(radius * 0.26, radius * 0.18),
		center + Vector2(-radius * 0.26, radius * 0.18),
		center + Vector2(-radius * 0.26, -radius * 0.62),
	]), tint)
	draw_line(
		center + Vector2(-radius * 0.64, radius * 0.24),
		center + Vector2(radius * 0.64, radius * 0.24),
		tint, 2.0, true
	)
	draw_line(
		center + Vector2(0, radius * 0.24), center + Vector2(0, radius * 0.68),
		tint, 2.2, true
	)


func _draw_bow(center: Vector2, radius: float) -> void:
	var arc_center := center + Vector2(-radius * 0.18, 0)
	draw_arc(arc_center, radius * 0.92, -1.05, 1.05, 18, tint, 1.9, true)
	var top := arc_center + Vector2(cos(-1.05), sin(-1.05)) * radius * 0.92
	var bottom := arc_center + Vector2(cos(1.05), sin(1.05)) * radius * 0.92
	draw_line(top, bottom, _alpha(0.55), 1.0, true)
	draw_line(center + Vector2(-radius * 0.55, 0), center + Vector2(radius * 0.92, 0), tint, 1.3, true)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(radius * 0.52, 0),
		center + Vector2(radius * 0.20, -radius * 0.26),
		center + Vector2(radius * 0.20, radius * 0.26),
	]), tint)


## Hooded eye for ambush: an outline with a slashed pupil.
func _draw_ambush(center: Vector2, radius: float) -> void:
	var eye := PackedVector2Array([
		center + Vector2(-radius * 0.90, 0),
		center + Vector2(0, -radius * 0.58),
		center + Vector2(radius * 0.90, 0),
		center + Vector2(0, radius * 0.58),
	])
	var closed := eye.duplicate()
	closed.append(eye[0])
	draw_polyline(closed, tint, 1.4, true)
	draw_circle(center, radius * 0.20, tint)
	draw_line(
		center + Vector2(-radius * 0.34, radius * 0.46),
		center + Vector2(radius * 0.34, -radius * 0.46),
		_alpha(0.60), 1.2, true
	)
