extends Control
## New-game setup: seed, world size and difficulty.
##
## The panel owns no game state. It records the player's choices and emits one
## plain dictionary for the main menu to hand to the threaded loading path.
## Numeric ids stay stable so retranslation only changes labels, not meaning.

signal confirmed(options: Dictionary)
signal closed

const SIZE_IDS := [1.0, 1.5, 2.0]

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _seed_label: Label
var _seed_field: LineEdit
var _size_label: Label
var _size_option: OptionButton
var _difficulty_label: Label
var _difficulty_option: OptionButton
var _note: Label
var _error: Label
var _start: Button
var _back: Button
var _settings: GameSettings


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	visible = false
	_settings = get_node_or_null("/root/Settings")
	if _settings != null:
		_settings.changed.connect(_retranslate)
	_retranslate()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.025, 0.05, 0.82)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(440, 350)
	_panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	_title = _add_label(column, "Title", UiStyle.FONT_TITLE, UiStyle.GOLD)
	_seed_label = _add_label(column, "SeedLabel", UiStyle.FONT_BODY, UiStyle.TEXT)
	_seed_field = LineEdit.new()
	_seed_field.name = "SeedField"
	_seed_field.custom_minimum_size = Vector2(0, 32)
	_seed_field.add_theme_font_size_override("font_size", UiStyle.FONT_BODY)
	column.add_child(_seed_field)

	_size_label = _add_label(column, "SizeLabel", UiStyle.FONT_BODY, UiStyle.TEXT)
	_size_option = OptionButton.new()
	_size_option.name = "SizeOption"
	UiStyle.apply_menu_button(_size_option)
	_size_option.add_theme_font_size_override("font_size", UiStyle.FONT_BODY)
	for id in SIZE_IDS.size():
		_size_option.add_item("", id)
	column.add_child(_size_option)

	_difficulty_label = _add_label(column, "DifficultyLabel", UiStyle.FONT_BODY, UiStyle.TEXT)
	_difficulty_option = OptionButton.new()
	_difficulty_option.name = "DifficultyOption"
	UiStyle.apply_menu_button(_difficulty_option)
	_difficulty_option.add_theme_font_size_override("font_size", UiStyle.FONT_BODY)
	for id in [Balance.Difficulty.EASY, Balance.Difficulty.NORMAL, Balance.Difficulty.HARD]:
		_difficulty_option.add_item("", id)
	column.add_child(_difficulty_option)

	_note = _add_label(column, "Note", UiStyle.FONT_SMALL, UiStyle.TEXT_DIM)
	_error = _add_label(column, "Error", UiStyle.FONT_SMALL, UiStyle.DANGER)
	_error.text = ""

	_start = Button.new()
	_start.name = "Start"
	UiStyle.apply_menu_button(_start)
	_start.alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_start)
	_back = Button.new()
	_back.name = "Back"
	UiStyle.apply_menu_button(_back)
	_back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_back)

	_start.pressed.connect(_on_start)
	_back.pressed.connect(close)


func _add_label(parent: Node, node_name: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	_seed_field.text = ""
	_size_option.select(_size_option.get_item_index(2))
	_difficulty_option.select(_difficulty_option.get_item_index(Balance.Difficulty.NORMAL))
	_error.text = ""
	_start.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _on_start() -> void:
	var raw_seed := _seed_field.text.strip_edges()
	var map_seed := -1
	if not raw_seed.is_empty():
		if not raw_seed.is_valid_int():
			_error.text = Loc.t("world_seed_invalid")
			return
		map_seed = int(raw_seed)
		if map_seed < 0:
			map_seed = -1
	_error.text = ""
	var options := {
		"seed": map_seed,
		"world_scale": SIZE_IDS[_size_option.get_selected_id()],
		"difficulty": _difficulty_option.get_selected_id(),
	}
	visible = false
	confirmed.emit(options)


func _retranslate() -> void:
	_title.text = Loc.t("new_game_title")
	_seed_label.text = Loc.t("world_seed")
	_size_label.text = Loc.t("world_size")
	_difficulty_label.text = Loc.t("difficulty")
	_note.text = Loc.t("new_game_note")
	_start.text = Loc.t("start_game")
	_back.text = Loc.t("back")

	var size_keys := ["world_size_1", "world_size_15", "world_size_2"]
	for id in SIZE_IDS.size():
		_size_option.set_item_text(_size_option.get_item_index(id), Loc.t(size_keys[id]))
	var difficulty_keys := [
		"difficulty_easy", "difficulty_normal", "difficulty_hard",
	]
	for id in [Balance.Difficulty.EASY, Balance.Difficulty.NORMAL, Balance.Difficulty.HARD]:
		_difficulty_option.set_item_text(
			_difficulty_option.get_item_index(id), Loc.t(difficulty_keys[id])
		)
