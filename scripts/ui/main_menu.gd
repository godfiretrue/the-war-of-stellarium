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
var loading_screen: Node

const MIN_LOADING_SECONDS := 1.1

var _loading := false
var _loading_thread: Thread
var _loading_mutex := Mutex.new()
var _loading_done := false
var _loading_state: MapState
var _loading_started_ms := 0
var _loading_continue := false
var _loading_save: Dictionary = {}

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
	loading_screen = get_node_or_null("/root/LoadingScreen")
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
	set_process(false)


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
	if _loading:
		return
	_begin_loading(-1, false, {})


func _on_continue() -> void:
	if _loading:
		return
	var result := SaveSystem.read_save()
	if not bool(result.get("ok", false)):
		_status.text = Loc.t("load_failed", [String(result.get("reason", "unknown"))])
		_continue.disabled = true
		return

	var data: Dictionary = result.get("data", {})
	_begin_loading(int(data.get("map_seed", 0)), true, data)


## Generates the world on a worker thread so the menu and the loading overlay
## keep animating. Finalization, save application and the scene change happen
## on the main thread in _process().
func _begin_loading(map_seed: int, is_continue: bool, save_data: Dictionary) -> void:
	_loading = true
	_loading_continue = is_continue
	_loading_save = save_data
	_loading_done = false
	_loading_state = null
	_loading_started_ms = Time.get_ticks_msec()
	_status.text = ""
	_set_busy(true)
	if loading_screen != null:
		loading_screen.begin(Loc.t("loading_world"))
	set_process(true)

	_loading_thread = Thread.new()
	var error := _loading_thread.start(_generate_world_thread.bind(map_seed))
	if error != OK:
		_fail_loading(Loc.t("world_failed"))


func _generate_world_thread(map_seed: int) -> void:
	var state := MapFactory.generate_map_data(map_seed)
	_loading_mutex.lock()
	_loading_state = state
	_loading_done = true
	_loading_mutex.unlock()


func _process(_delta: float) -> void:
	if not _loading:
		return

	var done := false
	_loading_mutex.lock()
	done = _loading_done
	_loading_mutex.unlock()
	if not done:
		return

	_loading = false
	set_process(false)
	if _loading_thread != null:
		_loading_thread.wait_to_finish()
		_loading_thread = null

	var state: MapState = _loading_state
	if state == null:
		_fail_loading(Loc.t("world_failed"))
		return

	# Armies and validation touch shared game data, so they stay on the main
	# thread even though the expensive terrain/province generation ran off it.
	MapFactory.finalize_map(state)
	if _loading_continue:
		game.start_new_game_from_map(state)
		SaveSystem.apply_save(game, _loading_save)
		turn_manager.resume_game(int(_loading_save.get("turn_number", 1)))
	else:
		turn_manager.start_game_from_map(state)

	_enter_map()


func _enter_map() -> void:
	var tree := get_tree()
	var screen := loading_screen
	var elapsed := float(Time.get_ticks_msec() - _loading_started_ms) / 1000.0
	if elapsed < MIN_LOADING_SECONDS:
		await tree.create_timer(MIN_LOADING_SECONDS - elapsed).timeout

	# The menu is freed by the scene change, so both halves of the transition
	# live on the persistent autoload: everything falls into the black hole
	# first, the scene swaps behind the black, then the black fades away.
	if screen != null:
		await screen.collapse_into_hole()
	var error := tree.change_scene_to_file("res://scenes/map/map.tscn")
	if error != OK:
		_fail_loading(Loc.t("world_failed"))
		return
	if screen != null:
		screen.reveal_after_frames(2)


func _fail_loading(message: String) -> void:
	_loading = false
	set_process(false)
	if _loading_thread != null and _loading_thread.is_started():
		_loading_thread.wait_to_finish()
		_loading_thread = null
	_status.text = message
	_set_busy(false)
	if loading_screen != null:
		loading_screen.finish()


func _set_busy(busy: bool) -> void:
	_new_game.disabled = busy
	_continue.disabled = busy or not SaveSystem.has_save()
	_settings_button.disabled = busy
	_quit.disabled = busy


## The menu can be freed by a scene change while the worker thread is still
## generating; joining it here prevents "Thread destroyed while running".
func _exit_tree() -> void:
	if _loading_thread != null and _loading_thread.is_started():
		_loading_thread.wait_to_finish()
		_loading_thread = null


func _on_quit() -> void:
	get_tree().quit()


## Black hole fades in first, then the menu column fades in just after it.
func _play_intro() -> void:
	_black_hole.modulate.a = 0.0
	_menu_column.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_property(_black_hole, "modulate:a", 1.0, 1.6)
	tween.parallel().tween_property(_menu_column, "modulate:a", 1.0, 1.0).set_delay(0.5)
