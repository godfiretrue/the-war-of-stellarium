class_name SettingsPanel
extends Control
## Small overlay with the persistent player settings.
##
## Reused by the main menu and by the in-game HUD, so language can be changed
## without leaving a campaign. The panel owns no state: it reads and writes the
## Settings autoload and redraws itself on `Settings.changed`.

signal closed

@onready var _title: Label = $Center/Panel/Column/Title
@onready var _language_label: Label = $Center/Panel/Column/LanguageRow/Label
@onready var _language_pt: Button = $Center/Panel/Column/LanguageRow/LanguagePt
@onready var _language_en: Button = $Center/Panel/Column/LanguageRow/LanguageEn
@onready var _fullscreen_label: Label = $Center/Panel/Column/FullscreenRow/Label
@onready var _fullscreen: CheckButton = $Center/Panel/Column/FullscreenRow/FullscreenCheck
@onready var _quality_label: Label = $Center/Panel/Column/QualityRow/Label
@onready var _quality: OptionButton = $Center/Panel/Column/QualityRow/QualityOption
@onready var _animation_label: Label = $Center/Panel/Column/AnimationRow/Label
@onready var _animation: OptionButton = $Center/Panel/Column/AnimationRow/AnimationOption
@onready var _note: Label = $Center/Panel/Column/Note
@onready var _close: Button = $Center/Panel/Column/Close
@onready var _panel: PanelContainer = $Center/Panel
@onready var _settings: GameSettings = get_node("/root/Settings")


func _ready() -> void:
	# A Control scene root inside a CanvasLayer does not size itself; make it
	# cover the screen so the dim layer blocks clicks on the map behind it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", UiStyle.panel_box())

	UiStyle.apply_menu_button(_language_pt)
	UiStyle.apply_menu_button(_language_en)
	UiStyle.apply_menu_button(_quality)
	UiStyle.apply_menu_button(_animation)
	UiStyle.apply_menu_button(_close)
	_quality.add_theme_font_size_override("font_size", 13)
	_animation.add_theme_font_size_override("font_size", 13)
	for button: Button in [_language_pt, _language_en]:
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 13)
	_close.alignment = HORIZONTAL_ALIGNMENT_CENTER

	_language_pt.pressed.connect(_on_language.bind("pt"))
	_language_en.pressed.connect(_on_language.bind("en"))
	_fullscreen.toggled.connect(_on_fullscreen)
	_quality.item_selected.connect(_on_quality)
	_animation.item_selected.connect(_on_animation)
	_close.pressed.connect(close)

	_settings.changed.connect(_refresh)
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# ui_cancel also covers the gamepad's cancel button, not just Escape.
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	_refresh()
	_close.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _on_language(value: String) -> void:
	_settings.set_language(value)


func _on_fullscreen(value: bool) -> void:
	_settings.set_fullscreen(value)


func _on_quality(index: int) -> void:
	_settings.set_quality(_quality.get_item_id(index))


func _on_animation(index: int) -> void:
	# Item id 0 = animations on, id 1 = off. Keeping ids independent of the
	# display order means retranslation cannot change the meaning.
	_settings.set_menu_animations(_animation.get_item_id(index) == 0)


func _refresh() -> void:
	_title.text = Loc.t("settings_title")
	_language_label.text = Loc.t("language")
	_fullscreen_label.text = Loc.t("fullscreen")
	_quality_label.text = Loc.t("graphics_quality")
	_animation_label.text = Loc.t("menu_animations")
	_note.text = Loc.t("settings_note")
	_close.text = Loc.t("close")

	# Toggle buttons report `pressed` when already selected; set the state
	# explicitly so a language change from anywhere keeps the UI in sync.
	_language_pt.set_pressed_no_signal(_settings.language == "pt")
	_language_en.set_pressed_no_signal(_settings.language == "en")
	_fullscreen.set_pressed_no_signal(_settings.fullscreen)

	# Rebuild the preset list once, then only retranslate it. Clearing it again
	# would run inside our own item_selected handler when the player picks a
	# preset (set_quality emits `changed`, which calls this function).
	var keys: Array[String] = ["quality_low", "quality_medium", "quality_high"]
	if _quality.item_count != keys.size():
		_quality.clear()
		for id in keys.size():
			_quality.add_item("", id)
	for id in keys.size():
		_quality.set_item_text(id, Loc.t(keys[id]))
	_quality.select(_quality.get_item_index(_settings.graphics_quality))

	var animation_keys: Array[String] = ["animations_on", "animations_off"]
	if _animation.item_count != animation_keys.size():
		_animation.clear()
		for id in animation_keys.size():
			_animation.add_item("", id)
	for id in animation_keys.size():
		_animation.set_item_text(id, Loc.t(animation_keys[id]))
	var animation_id := 0 if _settings.menu_animations else 1
	_animation.select(_animation.get_item_index(animation_id))

	var selected := Color(0.22, 0.25, 0.48, 0.95)
	for button in [_language_pt, _language_en]:
		button.add_theme_stylebox_override(
			"pressed", UiStyle.box(selected, UiStyle.GOLD, 4)
		)
		button.add_theme_stylebox_override(
			"hover_pressed", UiStyle.box(selected, UiStyle.GOLD, 4)
		)
