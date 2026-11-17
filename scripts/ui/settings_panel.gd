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
	UiStyle.apply_menu_button(_close)
	for button: Button in [_language_pt, _language_en]:
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 13)
	_close.alignment = HORIZONTAL_ALIGNMENT_CENTER

	_language_pt.pressed.connect(_on_language.bind("pt"))
	_language_en.pressed.connect(_on_language.bind("en"))
	_fullscreen.toggled.connect(_on_fullscreen)
	_close.pressed.connect(close)

	_settings.changed.connect(_refresh)
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
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


func _refresh() -> void:
	_title.text = Loc.t("settings_title")
	_language_label.text = Loc.t("language")
	_fullscreen_label.text = Loc.t("fullscreen")
	_note.text = Loc.t("settings_note")
	_close.text = Loc.t("close")

	# Toggle buttons report `pressed` when already selected; set the state
	# explicitly so a language change from anywhere keeps the UI in sync.
	_language_pt.set_pressed_no_signal(_settings.language == "pt")
	_language_en.set_pressed_no_signal(_settings.language == "en")
	_fullscreen.set_pressed_no_signal(_settings.fullscreen)

	var selected := Color(0.22, 0.25, 0.48, 0.95)
	for button in [_language_pt, _language_en]:
		button.add_theme_stylebox_override(
			"pressed", UiStyle.box(selected, UiStyle.GOLD, 4)
		)
		button.add_theme_stylebox_override(
			"hover_pressed", UiStyle.box(selected, UiStyle.GOLD, 4)
		)
