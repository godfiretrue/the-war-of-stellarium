class_name GameSettings
extends Node
## Player settings, persisted to user://settings.cfg.
##
## Registered as the "Settings" autoload so both the main menu and the HUD can
## read the current language before their _ready() runs. Every change is saved
## immediately and announced with `changed`, so open screens retranslate without
## a restart.
##
## Screens reach it with get_node("/root/Settings") typed as GameSettings; this
## project never references autoloads by bare name (it breaks --check-only).

signal changed

const PATH := "user://settings.cfg"
const LANGUAGES: Array[String] = ["pt", "en"]
const DEFAULT_LANGUAGE := "pt"

var language: String = DEFAULT_LANGUAGE
var fullscreen := false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		language = String(config.get_value("ui", "language", language))
		fullscreen = bool(config.get_value("ui", "fullscreen", fullscreen))

	if not LANGUAGES.has(language):
		language = DEFAULT_LANGUAGE
	Loc.language = language
	_apply_fullscreen(fullscreen)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("ui", "language", language)
	config.set_value("ui", "fullscreen", fullscreen)
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


func _apply_fullscreen(value: bool) -> void:
	# The headless test runner has no window; setting a mode there is a no-op
	# at best and prints errors at worst.
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED
	)
