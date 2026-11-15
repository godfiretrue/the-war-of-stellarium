extends Control
## Main menu: new game, continue from save, quit.
##
## The map scene is the only gameplay scene; this menu starts a game (or
## restores one) and then switches to it. Nodes are looked up by unique name
## (%Name) so the layout can change without touching this script.

const ACCENT := Color(0.55, 0.62, 1.0)
const TEXT_NORMAL := Color(0.86, 0.88, 0.95)
const TEXT_DISABLED := Color(0.42, 0.44, 0.52)

var game: GameState
var turn_manager: Node

@onready var _new_game: Button = %NewGame
@onready var _continue: Button = %Continue
@onready var _quit: Button = %Quit
@onready var _status: Label = %Status
@onready var _menu_column: Control = %MenuMargin
@onready var _black_hole: Control = %BlackHole


func _ready() -> void:
	# A Control scene root does not size itself to the window; do it explicitly.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for button: Button in [_new_game, _continue, _quit]:
		_style_button(button)
	_play_intro()

	game = get_node_or_null("/root/Game") as GameState
	turn_manager = get_node_or_null("/root/TurnManager")
	if game == null or turn_manager == null:
		push_error("MainMenu: Game/TurnManager autoloads are missing")
		return

	_new_game.pressed.connect(_on_new_game)
	_continue.pressed.connect(_on_continue)
	_quit.pressed.connect(_on_quit)

	_continue.disabled = not SaveSystem.has_save()
	_status.text = "A saved campaign is available." if SaveSystem.has_save() else ""
	_new_game.grab_focus()


func _on_new_game() -> void:
	turn_manager.start_game()
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")


func _on_continue() -> void:
	var result := SaveSystem.load_game(game)
	if not bool(result.get("ok", false)):
		_status.text = "Could not load save: %s" % String(result.get("reason", "unknown"))
		_continue.disabled = true
		return

	turn_manager.resume_game(int(result.get("turn", 1)))
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")


func _on_quit() -> void:
	get_tree().quit()


# --- Look and feel -------------------------------------------------------

## Flat, left-aligned buttons with an accent bar on hover/focus.
func _style_button(button: Button) -> void:
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_color_override("font_color", TEXT_NORMAL)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)

	button.add_theme_stylebox_override("normal", _box(Color(0.08, 0.09, 0.16, 0.55), Color(0.3, 0.33, 0.5, 0.6)))
	button.add_theme_stylebox_override("hover", _box(Color(0.16, 0.18, 0.36, 0.8), ACCENT))
	button.add_theme_stylebox_override("focus", _box(Color(0.16, 0.18, 0.36, 0.8), ACCENT))
	button.add_theme_stylebox_override("pressed", _box(Color(0.22, 0.25, 0.5, 0.9), Color.WHITE))
	button.add_theme_stylebox_override("disabled", _box(Color(0.06, 0.07, 0.11, 0.4), Color(0.2, 0.21, 0.28, 0.5)))


func _box(fill: Color, bar: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = bar
	box.border_width_left = 4
	box.set_corner_radius_all(2)
	box.content_margin_left = 22.0
	box.content_margin_right = 16.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box


## Black hole fades in first, then the menu column fades in just after it.
func _play_intro() -> void:
	_black_hole.modulate.a = 0.0
	_menu_column.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_property(_black_hole, "modulate:a", 1.0, 1.6)
	tween.parallel().tween_property(_menu_column, "modulate:a", 1.0, 1.0).set_delay(0.5)
