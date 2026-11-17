extends Control
## Main menu: new game, continue from save, settings, quit.
##
## The map scene is the only gameplay scene; this menu starts a game (or
## restores one) and then switches to it. Nodes are looked up by unique name
## (%Name) so the layout can change without touching this script.
##
## Text comes from Loc and the Settings autoload, so switching the language in
## the settings panel retranslates this screen in place.

var game: GameState
var turn_manager: Node

@onready var _new_game: Button = %NewGame
@onready var _continue: Button = %Continue
@onready var _settings_button: Button = %SettingsButton
@onready var _quit: Button = %Quit
@onready var _status: Label = %Status
@onready var _menu_column: Control = %MenuMargin
@onready var _black_hole: Control = %BlackHole
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _settings: GameSettings = get_node("/root/Settings")


func _ready() -> void:
	# A Control scene root does not size itself to the window; do it explicitly.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for button: Button in [_new_game, _continue, _settings_button, _quit]:
		UiStyle.apply_menu_button(button)
	_play_intro()

	game = get_node_or_null("/root/Game") as GameState
	turn_manager = get_node_or_null("/root/TurnManager")
	if game == null or turn_manager == null:
		push_error("MainMenu: Game/TurnManager autoloads are missing")
		return

	_new_game.pressed.connect(_on_new_game)
	_continue.pressed.connect(_on_continue)
	_settings_button.pressed.connect(_open_settings)
	_quit.pressed.connect(_on_quit)
	_settings_panel.closed.connect(_on_settings_closed)
	_settings.changed.connect(_retranslate)

	_continue.disabled = not SaveSystem.has_save()
	_retranslate()
	_new_game.grab_focus()


func _retranslate() -> void:
	_new_game.text = Loc.t("new_game")
	_continue.text = Loc.t("continue")
	_settings_button.text = Loc.t("settings")
	_quit.text = Loc.t("quit")
	_update_status()


func _update_status() -> void:
	_status.text = Loc.t("saved_available") if SaveSystem.has_save() else ""


func _open_settings() -> void:
	_settings_panel.open()


func _on_settings_closed() -> void:
	_new_game.grab_focus()


func _on_new_game() -> void:
	turn_manager.start_game()
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")


func _on_continue() -> void:
	var result := SaveSystem.load_game(game)
	if not bool(result.get("ok", false)):
		_status.text = Loc.t("load_failed", [String(result.get("reason", "unknown"))])
		_continue.disabled = true
		return

	turn_manager.resume_game(int(result.get("turn", 1)))
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")


func _on_quit() -> void:
	get_tree().quit()


## Black hole fades in first, then the menu column fades in just after it.
func _play_intro() -> void:
	_black_hole.modulate.a = 0.0
	_menu_column.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_property(_black_hole, "modulate:a", 1.0, 1.6)
	tween.parallel().tween_property(_menu_column, "modulate:a", 1.0, 1.0).set_delay(0.5)
