extends Control
## Main menu: new game, continue from save, quit.
##
## The map scene is the only gameplay scene; this menu starts a game (or
## restores one) and then switches to it.

var game: GameState
var turn_manager: Node

@onready var _new_game: Button = $Background/Center/Box/NewGame
@onready var _continue: Button = $Background/Center/Box/Continue
@onready var _quit: Button = $Background/Center/Box/Quit
@onready var _status: Label = $Background/Center/Box/Status


func _ready() -> void:
	# A Control scene root does not size itself to the window; do it explicitly.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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
