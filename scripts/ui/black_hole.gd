extends TextureRect
## Plays the black-hole spritesheet (10 x 6 frames) as a looping animation and
## adds a very slow "breathing" scale so the menu never feels static.
##
## The planet is sampled with nearest-neighbour filtering and its breathing is
## snapped to whole design pixels, so it reads as pixel art instead of a
## smoothly scaled HD sprite. The campaign field uses the same 4 px grid.
##
## The sheet lives at SHEET_PATH. If it is missing the node stays empty and
## only logs a warning, so the menu still works without the asset.

const SHEET_PATH := "res://assets/ui/black_hole_sheet.png"

@export var columns: int = 10
@export var rows: int = 6
@export var frame_count: int = 60
@export var fps: float = 10.0
## Redraw/animation tick. Frames still advance at `fps`; this is the rate at
## which the breathing value is recalculated.
@export var idle_fps: float = 15.0
@export var breathing_scale: float = 1.035
@export var breathing_seconds: float = 7.0
@export var pixel_step: float = 4.0

var _atlas: AtlasTexture
var _time: float = 0.0
var _accum: float = 0.0
var _last_frame: int = -1
var _frame_size: Vector2 = Vector2.ZERO
var _settings: GameSettings


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
		_settings.changed.connect(_apply_settings)
	_apply_settings()


## The menu-animations setting (and the Low preset) freeze the spritesheet on
## its first frame with a neutral scale. The sheet still sets the mood without
## redrawing every frame.
func _apply_settings() -> void:
	var enabled := _settings != null and _settings.menu_animations_enabled()
	set_process(enabled)
	_accum = 0.0
	if not enabled:
		scale = Vector2.ONE
		_show_frame(0)


## Advances in fixed steps: frames change at `fps`, breathing is snapped to the
## pixel grid, and skipped frames never make the animation run faster.
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var step := 1.0 / maxf(idle_fps, 1.0)
	_accum += delta
	if _accum < step:
		return
	var steps := mini(int(floorf(_accum / step)), 4)
	_accum -= steps * step
	_time += steps * step

	var frame := int(_time * fps) % frame_count
	if frame != _last_frame:
		_show_frame(frame)
	_apply_breath()


func _show_frame(frame: int) -> void:
	_last_frame = frame
	var cell := Vector2(frame % columns, floori(float(frame) / float(columns)))
	_atlas.region = Rect2(cell * _frame_size, _frame_size)


func _update_pivot() -> void:
	pivot_offset = size * 0.5


## Triangle wave over a full inhale/exhale cycle, rounded to whole `pixel_step`
## pixels of extra size. The planet's edge therefore lands on the same grid as
## the map instead of drifting through sub-pixel positions.
func _apply_breath() -> void:
	var half_cycle := maxf(breathing_seconds, 0.01)
	var phase := fposmod(_time, half_cycle * 2.0) / half_cycle
	var amount := phase if phase <= 1.0 else 2.0 - phase
	var base_px := maxf(size.x, 1.0)
	var step_scale := pixel_step / base_px
	var target := 1.0 + (breathing_scale - 1.0) * amount
	scale = Vector2.ONE * (1.0 + roundf((target - 1.0) / step_scale) * step_scale)
