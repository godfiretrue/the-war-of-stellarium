extends CanvasLayer
## Full-screen transition shown while a new world is generated.
##
## The heavy part of starting a campaign is procedural world generation. This
## layer covers the menu with the same starfield/black-hole language as the
## title screen, then fades away once the map scene is ready. It deliberately
## has no progress bar: the generator reports no meaningful percentage, so a
## fake bar would lie to the player.

const STARFIELD_SCRIPT := preload("res://scripts/ui/starfield.gd")
const BLACK_HOLE_SCRIPT := preload("res://scripts/ui/black_hole.gd")
const CONSTELLATION_SCRIPT := preload("res://scripts/ui/constellation_title.gd")

const FADE_IN_SECONDS := 0.28
const FADE_OUT_SECONDS := 0.45
const COLLAPSE_SECONDS := 0.7
const REVEAL_SECONDS := 0.55
const DOT_SECONDS := 0.35

var _root: Control
var _backdrop: ColorRect
var _content: Control
var _hole: TextureRect
var _message: Label
var _base_message := ""
var _dots := 0
var _dot_timer := 0.0
var _active := false
var _fade_tween: Tween
var _stage_tween: Tween


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.visible = false
	_root.process_mode = Node.PROCESS_MODE_DISABLED
	set_process(false)


func is_active() -> bool:
	return _active


## Shows the overlay and starts the fade-in. `message` is localized by the
## caller; an empty message keeps the last one.
func begin(message: String = "") -> void:
	if _active:
		if not message.is_empty():
			set_message(message)
		return
	_active = true
	_dots = 0
	_dot_timer = 0.0
	if not message.is_empty():
		_base_message = message
	_message.text = _base_message
	_reset_stage()
	_root.process_mode = Node.PROCESS_MODE_INHERIT
	_root.visible = true
	_root.modulate.a = 0.0
	set_process(true)
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN_SECONDS)


func set_message(message: String) -> void:
	_base_message = message
	_dots = 0
	_dot_timer = 0.0
	if _message != null:
		_message.text = message


## Fades the overlay out and hides it. Safe to call more than once.
func finish() -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	if _fade_tween != null:
		_fade_tween.kill()
	if _stage_tween != null:
		_stage_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT_SECONDS)
	_fade_tween.tween_callback(_hide_root)


## Sucks the whole scene into the black hole and leaves an opaque black screen.
## Awaited by the menu before it swaps scenes, so the world is never revealed
## while the title is still on screen. The tween lives on this autoload because
## the menu node is freed by the scene change.
func collapse_into_hole() -> void:
	if not _active:
		return
	set_process(false)
	_message.text = _base_message

	# Pivot on the black hole so everything spirals into it instead of shrinking
	# toward the screen centre.
	var hole_center: Vector2 = _content.get_global_transform().affine_inverse() * _hole.get_global_rect().get_center()
	_content.pivot_offset = hole_center
	if _stage_tween != null:
		_stage_tween.kill()
	_stage_tween = create_tween().set_parallel(true)
	_stage_tween.tween_property(_content, "scale", Vector2(0.02, 0.02), COLLAPSE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_stage_tween.tween_property(_content, "rotation", 0.35, COLLAPSE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_stage_tween.tween_property(_content, "modulate:a", 0.0, COLLAPSE_SECONDS).set_ease(Tween.EASE_IN)
	await _stage_tween.finished


## Reveals the new scene by fading the black backdrop out. Called after the
## scene change; the map is already built behind the black.
func reveal_after_frames(frames: int = 2) -> void:
	for _i in frames:
		await get_tree().process_frame
	_active = false
	if _stage_tween != null:
		_stage_tween.kill()
	_stage_tween = create_tween()
	_stage_tween.tween_property(_backdrop, "modulate:a", 0.0, REVEAL_SECONDS).set_ease(Tween.EASE_OUT)
	await _stage_tween.finished
	_hide_root()


func _reset_stage() -> void:
	if _content == null:
		return
	_content.pivot_offset = Vector2.ZERO
	_content.scale = Vector2.ONE
	_content.rotation = 0.0
	_content.modulate.a = 1.0
	_backdrop.modulate.a = 1.0


func _hide_root() -> void:
	_root.visible = false
	_root.process_mode = Node.PROCESS_MODE_DISABLED
	_reset_stage()


func _process(delta: float) -> void:
	_dot_timer += delta
	if _dot_timer < DOT_SECONDS:
		return
	_dot_timer = 0.0
	_dots = (_dots + 1) % 4
	_message.text = _base_message + ".".repeat(_dots)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.color = Color(0.02, 0.025, 0.05, 1.0)
	_root.add_child(_backdrop)

	# Everything except the backdrop lives here so it can be collapsed into the
	# black hole as one piece.
	_content = Control.new()
	_content.name = "Content"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)

	var stars := Control.new()
	stars.name = "Stars"
	stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.set_script(STARFIELD_SCRIPT)
	_content.add_child(stars)

	# Mirrors the title screen: black hole on the right, text on the left.
	_hole = TextureRect.new()
	_hole.name = "BlackHole"
	_hole.anchor_left = 0.4
	_hole.anchor_top = -0.08
	_hole.anchor_right = 1.0
	_hole.anchor_bottom = 1.08
	_hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hole.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hole.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hole.set_script(BLACK_HOLE_SCRIPT)
	_content.add_child(_hole)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.anchor_right = 0.55
	margin.anchor_bottom = 1.0
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 64)
	_content.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Control.new()
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.set_script(CONSTELLATION_SCRIPT)
	title.set("letter_height", 40.0)
	title.set("intro_seconds", 0.8)
	title.set("start_delay", 0.05)
	title.set("skip_intro", true)
	column.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.custom_minimum_size = Vector2(320, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.color = Color(0.95, 0.78, 0.38, 0.75)
	column.add_child(rule)

	_message = Label.new()
	_message.name = "Message"
	_message.text = Loc.t("loading_world")
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_message.add_theme_color_override("font_color", Color(0.72, 0.76, 0.86))
	_message.add_theme_font_size_override("font_size", 15)
	column.add_child(_message)
	_base_message = _message.text
