class_name GameSettings
extends Node
## Player settings, persisted to user://settings.cfg.
##
## Registered as the "Settings" autoload so both the main menu and the HUD can
## read the current language before their _ready() runs. Every change is saved
## immediately and announced with `changed`, so open screens retranslate and
## re-apply the graphics preset without a restart.
##
## Screens reach it with get_node("/root/Settings") typed as GameSettings; this
## project never references autoloads by bare name (it breaks --check-only).

signal changed

const PATH := "user://settings.cfg"
const LANGUAGES: Array[String] = ["pt", "en"]
const DEFAULT_LANGUAGE := "pt"
## Menu ambience starts on. The setting is about CPU/GPU cost and motion
## sensitivity, not about the saved graphics preset.
const DEFAULT_MENU_ANIMATIONS := true

## Graphics presets. Low renders the campaign at the 1152x648 design resolution
## and strips the expensive shader layers; High renders at the native window
## resolution with every effect. The presets exist because the campaign runs on
## a software/virtualised GPU (VMware SVGA): the full-resolution terrain and
## water shaders are what make that driver fall over.
const QUALITY_LOW := 0
const QUALITY_MEDIUM := 1
const QUALITY_HIGH := 2
const QUALITY_MIN := QUALITY_LOW
const QUALITY_MAX := QUALITY_HIGH

## The canvas the HUD is authored against (see AI_CONTEXT). Low/Medium render
## the whole 2D tree at this size and upscale it to the window.
const BASE_SIZE := Vector2i(1152, 648)

var language: String = DEFAULT_LANGUAGE
var fullscreen := false
var menu_animations := DEFAULT_MENU_ANIMATIONS
## -1 means "not chosen yet": _ready() picks a preset from the video adapter.
var graphics_quality: int = -1


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		language = String(config.get_value("ui", "language", language))
		fullscreen = bool(config.get_value("ui", "fullscreen", fullscreen))
		menu_animations = bool(config.get_value("ui", "menu_animations", menu_animations))
		graphics_quality = int(config.get_value("video", "quality", graphics_quality))

	if not LANGUAGES.has(language):
		language = DEFAULT_LANGUAGE
	if graphics_quality < QUALITY_MIN or graphics_quality > QUALITY_MAX:
		graphics_quality = _detect_quality()
	Loc.language = language
	_apply_fullscreen(fullscreen)
	apply_render_mode()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("ui", "language", language)
	config.set_value("ui", "fullscreen", fullscreen)
	config.set_value("ui", "menu_animations", menu_animations)
	config.set_value("video", "quality", graphics_quality)
	config.save(PATH)


func set_language(value: String) -> void:
	if not LANGUAGES.has(value) or value == language:
		return
	language = value
	Loc.language = value
	save_settings()
	changed.emit()


func set_fullscreen(value: bool) -> void:
	if value == fullscreen:
		return
	fullscreen = value
	_apply_fullscreen(value)
	save_settings()
	changed.emit()


func toggle_fullscreen() -> void:
	set_fullscreen(not fullscreen)


func set_menu_animations(value: bool) -> void:
	if value == menu_animations:
		return
	menu_animations = value
	save_settings()
	changed.emit()


## The Low preset strips animation on its own for performance, so it overrides
## the player's choice. Everything else follows the saved setting.
func menu_animations_enabled() -> bool:
	return menu_animations and not is_low_quality()


func set_quality(value: int) -> void:
	value = clampi(value, QUALITY_MIN, QUALITY_MAX)
	if value == graphics_quality:
		return
	graphics_quality = value
	apply_render_mode()
	save_settings()
	changed.emit()


## True on the Low preset: expensive shader layers and menu animations off.
func is_low_quality() -> bool:
	return graphics_quality == QUALITY_LOW


## Picks a starting preset. Virtual/software adapters cannot afford a full
## native-resolution render, and on this project's VMware host that path also
## crashes the OpenGL driver, so they start on Low.
func _detect_quality() -> int:
	if DisplayServer.get_name() == "headless":
		return QUALITY_HIGH
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var software := adapter.contains("vmware") or adapter.contains("svga") \
		or adapter.contains("llvmpipe") or adapter.contains("softpipe") \
		or adapter.contains("software") or adapter.contains("basic render")
	return QUALITY_LOW if software else QUALITY_HIGH


## Low and Medium render the 2D tree at the authored 1152x648 canvas and let the
## GPU/driver upscale it. High renders at the real window resolution.
##
## Screens made of mostly flat UI (the main menu) have no detail to gain from
## native resolution, but pay for it on a virtual/software GPU. They can pass
## `force_viewport` to render at the authored canvas without changing the
## player's saved preset; the campaign keeps the full High render.
func apply_render_mode(force_viewport: bool = false) -> void:
	# The headless test runner has no window; touching the root's content scale
	# is pointless there and can print errors.
	if DisplayServer.get_name() == "headless":
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var root := tree.root
	if graphics_quality == QUALITY_HIGH and not force_viewport:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	else:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = BASE_SIZE


func _apply_fullscreen(value: bool) -> void:
	# The headless test runner has no window; setting a mode there is a no-op
	# at best and prints errors at worst.
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED
	)
