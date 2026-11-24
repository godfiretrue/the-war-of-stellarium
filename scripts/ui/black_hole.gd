extends TextureRect
## Plays the black-hole spritesheet (10 x 6 frames) as a looping animation and
## adds a very slow "breathing" scale so the menu never feels static.
##
## The sheet lives at SHEET_PATH. If it is missing the node stays empty and
## only logs a warning, so the menu still works without the asset.

const SHEET_PATH := "res://assets/ui/black_hole_sheet.png"

@export var columns: int = 10
@export var rows: int = 6
@export var frame_count: int = 60
@export var fps: float = 10.0
@export var breathing_scale: float = 1.035
@export var breathing_seconds: float = 7.0

var _atlas: AtlasTexture
var _time: float = 0.0
var _last_frame: int = -1
var _frame_size: Vector2 = Vector2.ZERO
var _settings: GameSettings
var _breath_tween: Tween
var _breathing := false


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_update_pivot)
	_update_pivot()

	if not ResourceLoader.exists(SHEET_PATH):
		push_warning("BlackHole: %s not found, skipping animation" % SHEET_PATH)
		set_process(false)
		return

	var sheet := load(SHEET_PATH) as Texture2D
	if sheet == null:
		set_process(false)
		return

	_frame_size = sheet.get_size() / Vector2(columns, rows)
	_atlas = AtlasTexture.new()
	_atlas.atlas = sheet
	_atlas.filter_clip = true
	texture = _atlas
	_show_frame(0)
	_settings = get_node_or_null("/root/Settings") as GameSettings
	if _settings != null:
		_settings.changed.connect(_apply_quality)
	_apply_quality()


## Low freezes the animation on its first frame and cancels the breathing
## tween; the spritesheet still sets the mood without redrawing every frame.
func _apply_quality() -> void:
	var low := _settings != null and _settings.is_low_quality()
	set_process(not low)
	if low:
		_stop_breathing()
		_show_frame(0)
	else:
		_start_breathing()


func _process(delta: float) -> void:
	_time += delta
	var frame := int(_time * fps) % frame_count
	if frame != _last_frame:
		_show_frame(frame)


func _show_frame(frame: int) -> void:
	_last_frame = frame
	var cell := Vector2(frame % columns, floori(float(frame) / float(columns)))
	_atlas.region = Rect2(cell * _frame_size, _frame_size)


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _start_breathing() -> void:
	if _breathing:
		return
	_breathing = true
	_breath_tween = create_tween().set_loops()
	_breath_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath_tween.tween_property(self, "scale", Vector2.ONE * breathing_scale, breathing_seconds)
	_breath_tween.tween_property(self, "scale", Vector2.ONE, breathing_seconds)


func _stop_breathing() -> void:
	_breathing = false
	if _breath_tween != null:
		_breath_tween.kill()
		_breath_tween = null
	scale = Vector2.ONE
