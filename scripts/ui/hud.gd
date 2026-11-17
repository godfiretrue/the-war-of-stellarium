class_name GameHUD
extends CanvasLayer
## Player-facing HUD and the player's map controller.
##
## Owns the two-step order flow (select a province, press March, click a
## neighbour), the recruit buttons, the queued-orders list and the keyboard
## shortcuts. Every rule change still goes through GameState, so the player and
## the bot share one rules path and the player also only queues orders.
##
## Layout lives in scenes/ui/hud.tscn; this script only fills it. All text goes
## through Loc, so changing the language retranslates the HUD in place.

const PLAYER := Balance.PLAYER_FACTION
const BATTLE_VISIBLE_SECONDS := 10.0
## Cards grow with their content but never past this share of the screen.
const CARD_MAX_HEIGHT_RATIO := 0.45
const ORDER_ROW_HEIGHT := 44.0
const BATTLE_ROW_HEIGHT := 64.0

var game: GameState
var turn_manager: Node
var map_view: MapView

var selected_province_id: String = ""
var march_origin_id: String = ""

var _battle_token := 0
var _last_battles: Array = []
var _game_over_winner := -2

@onready var _faction_dot: ColorRect = $Root/TopStrip/TopMargin/TopRow/FactionDot
@onready var _faction_name: Label = $Root/TopStrip/TopMargin/TopRow/FactionName
@onready var _gold: Label = $Root/TopStrip/TopMargin/TopRow/Gold
@onready var _manpower: Label = $Root/TopStrip/TopMargin/TopRow/Manpower
@onready var _resource: Label = $Root/TopStrip/TopMargin/TopRow/Resource
@onready var _turn_badge: PanelContainer = $Root/TopStrip/TopMargin/TopRow/TurnBadge
@onready var _turn: Label = $Root/TopStrip/TopMargin/TopRow/TurnBadge/Turn
@onready var _accent_bar: ColorRect = $Root/BottomStrip/BottomMargin/BottomRow/SelectionCard/AccentBar
@onready var _name: Label = $Root/BottomStrip/BottomMargin/BottomRow/SelectionCard/InfoBox/ProvinceName
@onready var _meta: Label = $Root/BottomStrip/BottomMargin/BottomRow/SelectionCard/InfoBox/ProvinceMeta
@onready var _troops: Label = $Root/BottomStrip/BottomMargin/BottomRow/SelectionCard/InfoBox/StatsRow/Troops
@onready var _attack: Label = $Root/BottomStrip/BottomMargin/BottomRow/SelectionCard/InfoBox/StatsRow/Attack
@onready var _defense: Label = $Root/BottomStrip/BottomMargin/BottomRow/SelectionCard/InfoBox/StatsRow/Defense
@onready var _income: Label = $Root/BottomStrip/BottomMargin/BottomRow/SelectionCard/InfoBox/StatsRow/Income
@onready var _recruit_a: Button = $Root/BottomStrip/BottomMargin/BottomRow/Actions/RecruitA
@onready var _recruit_b: Button = $Root/BottomStrip/BottomMargin/BottomRow/Actions/RecruitB
@onready var _march: Button = $Root/BottomStrip/BottomMargin/BottomRow/Actions/March
@onready var _end_turn: Button = $Root/BottomStrip/BottomMargin/BottomRow/Actions/EndTurn
@onready var _save: Button = $Root/BottomStrip/BottomMargin/BottomRow/Actions/Save
@onready var _options: Button = $Root/BottomStrip/BottomMargin/BottomRow/Actions/Options
@onready var _menu: Button = $Root/BottomStrip/BottomMargin/BottomRow/Actions/Menu
@onready var _hint: Label = $Root/Hint
@onready var _orders_card: PanelContainer = $Root/OrdersCard
@onready var _orders_title: Label = $Root/OrdersCard/OrdersBox/OrdersTitle
@onready var _orders_scroll: ScrollContainer = $Root/OrdersCard/OrdersBox/OrdersScroll
@onready var _orders_list: VBoxContainer = $Root/OrdersCard/OrdersBox/OrdersScroll/OrdersList
@onready var _battle_card: PanelContainer = $Root/BattleCard
@onready var _battle_title: Label = $Root/BattleCard/BattleBox/BattleTitle
@onready var _battle_scroll: ScrollContainer = $Root/BattleCard/BattleBox/BattleScroll
@onready var _battle_list: VBoxContainer = $Root/BattleCard/BattleBox/BattleScroll/BattleList
@onready var _settings_panel: SettingsPanel = $Root/SettingsPanel
@onready var _settings: GameSettings = get_node("/root/Settings")


func _ready() -> void:
	game = get_node_or_null("/root/Game") as GameState
	turn_manager = get_node_or_null("/root/TurnManager")
	map_view = get_parent() as MapView

	if game == null or turn_manager == null:
		push_error("GameHUD: Game/TurnManager autoloads are missing")
		return

	_style()
	_connect_signals()

	_battle_card.visible = false
	_hint.text = ""

	if game.map_state != null:
		var capital := game.map_state.capital_of(PLAYER)
		if capital != null:
			_select(capital.id)
		else:
			_refresh()
	else:
		_refresh()


func _connect_signals() -> void:
	game.state_changed.connect(_refresh)
	game.orders_changed.connect(_refresh_orders)
	turn_manager.phase_changed.connect(_on_phase_changed)
	turn_manager.resolution_finished.connect(_on_resolution_finished)
	turn_manager.game_finished.connect(_on_game_finished)
	_settings.changed.connect(_retranslate)

	if map_view != null:
		map_view.province_clicked.connect(_on_map_clicked)

	_recruit_a.pressed.connect(_on_recruit.bind(0))
	_recruit_b.pressed.connect(_on_recruit.bind(1))
	_march.pressed.connect(_on_march_pressed)
	_end_turn.pressed.connect(_on_end_turn_pressed)
	_save.pressed.connect(_on_save_pressed)
	_options.pressed.connect(_open_settings)
	_menu.pressed.connect(_on_menu_pressed)
	_settings_panel.closed.connect(_on_settings_closed)


# --- Look ----------------------------------------------------------------

func _style() -> void:
	_faction_dot.color = UiStyle.HUMAN
	_faction_name.add_theme_color_override("font_color", UiStyle.TEXT)
	_faction_name.text = Loc.faction_name(PLAYER)

	_pill(_gold, Color(0.91, 0.77, 0.42))
	_pill(_manpower, Color(0.56, 0.78, 0.91))
	_pill(_resource, Color(0.79, 0.65, 0.91))
	_turn.add_theme_color_override("font_color", UiStyle.GOLD)

	UiStyle.apply_hud_button(_recruit_a)
	UiStyle.apply_hud_button(_recruit_b)
	UiStyle.apply_hud_button(_march)
	UiStyle.apply_primary_button(_end_turn)
	UiStyle.apply_ghost_button(_save)
	UiStyle.apply_ghost_button(_options)
	UiStyle.apply_ghost_button(_menu)

	_battle_card.add_theme_stylebox_override("panel", UiStyle.panel_box())
	_orders_card.add_theme_stylebox_override("panel", UiStyle.panel_box())
	_orders_card.visible = false


func _pill(label: Label, accent: Color) -> void:
	label.add_theme_stylebox_override(
		"normal", UiStyle.capsule(Color(0.07, 0.08, 0.13, 0.85), Color(accent, 0.35))
	)
	label.add_theme_constant_override("outline_size", 0)


# --- Refresh -------------------------------------------------------------

func _refresh() -> void:
	if game == null or game.map_state == null:
		return

	_gold.text = "🪙 %d" % game.get_gold(PLAYER)
	_manpower.text = "👥 %d" % game.get_manpower(PLAYER)

	var key := game.faction_resource_key(PLAYER)
	_resource.text = "✦ %d %s" % [game.get_resource(PLAYER, key), Loc.resource_name(key)]

	_turn.text = Loc.t("turn_badge", [turn_manager.turn_number, Loc.phase_short(turn_manager.phase)])
	_style_turn_badge()

	_refresh_static_text()
	_refresh_selection()
	_refresh_buttons()
	_refresh_orders()


## Button labels and tooltips that do not depend on the selection.
func _refresh_static_text() -> void:
	_faction_name.text = Loc.faction_name(PLAYER)
	_march.text = Loc.t("march")
	_end_turn.text = Loc.t("end_turn")
	_save.text = Loc.t("save")
	_options.text = Loc.t("options")
	_menu.text = Loc.t("menu")

	_orders_title.text = Loc.t("orders_title")
	_march.tooltip_text = Loc.t("tip_march")
	_end_turn.tooltip_text = Loc.t("tip_end_turn")
	_save.tooltip_text = Loc.t("tip_save")
	_options.tooltip_text = Loc.t("tip_options")
	_menu.tooltip_text = Loc.t("tip_menu")


func _style_turn_badge() -> void:
	var phase: int = turn_manager.phase
	var color := UiStyle.GOLD
	if phase == 1:
		color = UiStyle.DANGER
	elif phase == 2:
		color = UiStyle.ACCENT
	elif phase >= 3:
		color = UiStyle.TEXT_DIM
	_turn.add_theme_color_override("font_color", color)
	_turn_badge.add_theme_stylebox_override(
		"panel", UiStyle.capsule(Color(0.07, 0.08, 0.13, 0.85), Color(color, 0.45))
	)


func _refresh_selection() -> void:
	var province := _selected_province()
	if province == null:
		_accent_bar.color = UiStyle.NEUTRAL
		_name.text = Loc.t("select_province")
		_name.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		_meta.text = ""
		_clear_stats()
		return

	var faction_color := UiStyle.faction_color(province.owner_faction)
	_accent_bar.color = faction_color

	var role := Loc.t("role_corridor")
	if province.is_capital:
		role = Loc.t("role_capital")
	elif province.is_city:
		role = Loc.t("role_castle")

	_name.text = province.display_name
	_name.add_theme_color_override(
		"font_color", UiStyle.GOLD if province.is_capital else UiStyle.TEXT
	)
	_meta.text = "%s · %s · %s" % [
		role,
		Loc.territory_type(province.territory_type),
		Loc.faction_name(province.owner_faction),
	]

	var troops := province.total_troops()
	_troops.text = "⚔ " + (Loc.t("troops", [troops]) if troops > 0 else Loc.t("troops_none"))
	_troops.add_theme_color_override("font_color", UiStyle.TEXT if troops > 0 else UiStyle.TEXT_DIM)

	if troops > 0:
		_attack.text = "%s %.0f" % [Loc.t("stat_attack"), province.attack_power()]
		_defense.text = "%s %.0f" % [
			Loc.t("stat_defense"), province.defense_power() * Balance.terrain_defense(province.terrain)
		]
	else:
		_attack.text = ""
		_defense.text = ""

	_income.text = ""
	if not province.resource_type.is_empty():
		_income.text = Loc.t("income", [
			province.resource_per_turn, Loc.resource_name(province.resource_type)
		])


func _clear_stats() -> void:
	_troops.text = ""
	_attack.text = ""
	_defense.text = ""
	_income.text = ""


func _refresh_buttons() -> void:
	var player_planning: bool = turn_manager.is_player_planning()
	_end_turn.disabled = not player_planning

	# Saves are only allowed at the start of a turn, before any order is queued.
	_save.disabled = not player_planning or game.has_queued_orders()

	var province := _selected_province()
	var owned: bool = province != null and province.is_owned_by(PLAYER)
	var can_march := player_planning and owned and province.total_troops() > 0
	_march.disabled = not can_march
	# March is the expected next step while a move is armed; otherwise ending the
	# turn is. Only one of them wears the gold primary style at a time.
	if march_origin_id.is_empty():
		UiStyle.apply_hud_button(_march)
		UiStyle.apply_primary_button(_end_turn)
	else:
		UiStyle.apply_primary_button(_march)
		UiStyle.apply_hud_button(_end_turn)

	var is_city_province := province != null and province.is_city
	var can_recruit_base := player_planning and owned and is_city_province

	var unit_ids := UnitCatalog.units_for_faction(PLAYER)
	var buttons: Array[Button] = [_recruit_a, _recruit_b]
	for index in buttons.size():
		var button := buttons[index]
		if index >= unit_ids.size():
			button.visible = false
			continue
		button.visible = true

		var unit_id := unit_ids[index]
		var unit := UnitCatalog.get_unit(unit_id)
		var costs := unit.costs_for(PLAYER)
		var gold_cost := int(costs["gold"])
		var manpower_cost := int(costs["manpower"])

		button.tooltip_text = Loc.t("recruit_tooltip", [
			Loc.unit_name(unit_id), int(unit.attack), int(unit.defense), int(unit.upkeep),
		])

		if province == null:
			button.text = "+ %s" % Loc.unit_name(unit_id)
			button.disabled = true
		elif not owned:
			button.text = "+ %s" % Loc.unit_name(unit_id)
			button.disabled = true
		elif not is_city_province:
			# Corridors cannot recruit; show the unit but explain why it is off.
			button.text = "+ %s" % Loc.unit_name(unit_id)
			button.disabled = true
			button.tooltip_text = "%s\n%s" % [
				button.tooltip_text, Loc.t("recruit_city_only"),
			]
		else:
			button.text = Loc.t("recruit", [
				Loc.unit_name(unit_id), gold_cost, manpower_cost,
			])
			var affordable := game.can_afford(PLAYER, gold_cost, manpower_cost)
			button.disabled = not (can_recruit_base and affordable)
			if not affordable:
				button.tooltip_text = "%s\n%s" % [
					button.tooltip_text, Loc.t("recruit_reason_gold"),
				]


func _retranslate() -> void:
	# The language lives in Settings; re-render everything that carries text.
	if game == null:
		return
	_faction_name.text = Loc.faction_name(PLAYER)
	_refresh()
	# Re-render the battle list only while it is still on screen; a language
	# change must not resurrect one that already timed out.
	if _battle_card.visible and not _last_battles.is_empty():
		_render_battles(false)


# --- Player actions ------------------------------------------------------

func _on_recruit(index: int) -> void:
	if not turn_manager.is_player_planning() or selected_province_id.is_empty():
		return

	var unit_ids := UnitCatalog.units_for_faction(PLAYER)
	if index < 0 or index >= unit_ids.size():
		return

	var result := game.queue_recruit(PLAYER, selected_province_id, unit_ids[index], 1)
	_hint.text = "" if result.get("ok", false) else Loc.reason(String(result.get("reason", "")))
	_refresh()


func _on_march_pressed() -> void:
	if not turn_manager.is_player_planning():
		_hint.text = Loc.t("hint_bot_turn")
		return

	if not march_origin_id.is_empty():
		_cancel_march()
		return

	var province := _selected_province()
	if province == null or not province.is_owned_by(PLAYER):
		return
	if province.total_troops() <= 0:
		_hint.text = Loc.t("hint_no_troops")
		return

	march_origin_id = selected_province_id
	_hint.text = Loc.t("hint_march")
	if map_view != null:
		map_view.set_march_targets(PackedStringArray(province.neighbors))
	_refresh_buttons()


func _on_end_turn_pressed() -> void:
	if not turn_manager.is_player_planning():
		return
	_cancel_march()
	_hint.text = ""
	_battle_card.visible = false
	_battle_token += 1
	turn_manager.end_player_turn()


func _on_save_pressed() -> void:
	if not turn_manager.is_player_planning() or game.has_queued_orders():
		_hint.text = Loc.t("save_turn_start_only")
		return
	var saved := SaveSystem.save_game(game, turn_manager.turn_number)
	_hint.text = Loc.t("saved") if saved else Loc.t("save_failed")


func _open_settings() -> void:
	_cancel_march()
	_hint.text = ""
	_settings_panel.open()


func _on_settings_closed() -> void:
	_refresh()


func _on_menu_pressed() -> void:
	# Only save when the queue is empty, so a resumed game never starts half
	# planned. Leaving with queued orders simply discards them.
	if turn_manager.is_player_planning() and not game.has_queued_orders():
		SaveSystem.save_game(game, turn_manager.turn_number)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_map_clicked(province_id: String) -> void:
	if _settings_panel.visible:
		return
	if not march_origin_id.is_empty():
		_handle_march_click(province_id)
	else:
		_select(province_id)


func _handle_march_click(target_id: String) -> void:
	var origin_id := march_origin_id
	var map := game.map_state

	if not turn_manager.is_player_planning():
		_cancel_march()
		return

	if not map.are_adjacent(origin_id, target_id):
		_cancel_march()
		_hint.text = Loc.t("hint_not_neighbor")
		_select(target_id)
		return

	var origin := map.get_province(origin_id)
	var result := game.queue_move(PLAYER, origin_id, target_id, origin.garrison.duplicate())
	_cancel_march()

	if not bool(result.get("ok", false)):
		_hint.text = Loc.reason(String(result.get("reason", "")))
		_refresh()
		return

	_hint.text = Loc.t("hint_order_queued")
	_select(origin_id)


func _cancel_march() -> void:
	march_origin_id = ""
	if map_view != null:
		map_view.set_march_targets(PackedStringArray())
	if _march != null:
		UiStyle.apply_hud_button(_march)
	_refresh_buttons()


func _select(province_id: String) -> void:
	selected_province_id = province_id
	if map_view != null:
		map_view.select_province(province_id)
	_refresh()


func _selected_province() -> ProvinceData:
	if game == null or game.map_state == null or selected_province_id.is_empty():
		return null
	return game.map_state.get_province(selected_province_id)


# --- Keyboard ------------------------------------------------------------

## Shortcuts are read here instead of on the buttons: HUD buttons have
## focus_mode NONE, so a focused button can never swallow Space.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	if _settings_panel != null and _settings_panel.visible:
		return

	var key := (event as InputEventKey).keycode
	match key:
		KEY_SPACE:
			_on_end_turn_pressed()
		KEY_M:
			_on_march_pressed()
		KEY_ESCAPE:
			if not march_origin_id.is_empty():
				_cancel_march()
				_hint.text = ""
		KEY_S:
			_on_save_pressed()
		KEY_R:
			_on_recruit(0)
		_:
			return
	get_viewport().set_input_as_handled()


# --- Signals -------------------------------------------------------------

func _on_phase_changed(_phase: int) -> void:
	if turn_manager.is_player_planning():
		# Clear the wait message when control comes back; leave other feedback
		# (save result, recruit errors) alone.
		if _hint.text == Loc.t("hint_bot_turn"):
			_hint.text = ""
	else:
		_cancel_march()
		# Only bot planning needs the message; resolution blinks past.
		if turn_manager.is_bot_planning():
			_hint.text = Loc.t("hint_bot_turn")
	_refresh()


func _on_resolution_finished(summary: Dictionary) -> void:
	_last_battles = summary.get("battles", [])
	if _last_battles.is_empty():
		_battle_card.visible = false
		return
	_render_battles(true)


## Renders every battle of the turn in one scrollable card. `reset_timer` is
## false on a language change so the existing timeout keeps running.
func _render_battles(reset_timer: bool) -> void:
	for child in _battle_list.get_children():
		_battle_list.remove_child(child)
		child.queue_free()

	_battle_title.text = Loc.t("battles_title", [_last_battles.size()])
	_battle_scroll.custom_minimum_size.y = _card_list_height(_last_battles.size(), BATTLE_ROW_HEIGHT)
	for result_variant in _last_battles:
		var result: Dictionary = result_variant
		var label := Label.new()
		label.text = _battle_text(result)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", UiStyle.TEXT)
		_battle_list.add_child(label)

	_battle_card.visible = true
	_battle_card.modulate.a = 1.0
	if not reset_timer:
		return

	# Only the newest summary may hide the card; an older timer is cancelled by
	# comparing the token it captured.
	_battle_token += 1
	var token := _battle_token
	var tween := create_tween()
	tween.tween_interval(BATTLE_VISIBLE_SECONDS)
	tween.tween_property(_battle_card, "modulate:a", 0.0, 0.6)
	tween.tween_callback(
		func() -> void:
			if token == _battle_token:
				_battle_card.visible = false
	)


func _battle_text(result: Dictionary) -> String:
	var from_name := String(result.get("from_name", result.get("province_name", "?")))
	var to_name := String(result.get("to_name", result.get("province_name", "?")))
	var losses := Loc.t("battle_losses", [
		int(result.get("attacker_losses", 0)), int(result.get("defender_losses", 0)),
	])

	if bool(result.get("swap", false)):
		return "%s — %s" % [Loc.t("battle_swap_line", [from_name, to_name]), losses]

	var title := Loc.t("battle_field", [String(result.get("province_name", "?"))])
	var province := _province(String(result.get("province_id", "")))
	if province != null and province.is_city:
		title = Loc.t("battle_siege", [province.display_name])

	return "%s\n%s\n%s" % [
		title,
		Loc.t("battle_line", [
			Loc.faction_name(int(result.get("attacker_faction", 0))),
			Loc.faction_name(int(result.get("defender_faction", 1))),
			float(result.get("attacker_power", 0.0)),
			float(result.get("defender_power", 0.0)),
		]),
		"%s · %s" % [
			losses,
			Loc.t("battle_captured") if bool(result.get("captured", false)) else Loc.t("battle_held"),
		],
	]


# --- Queued orders -------------------------------------------------------

func _refresh_orders() -> void:
	if game == null or _orders_list == null:
		return
	for child in _orders_list.get_children():
		_orders_list.remove_child(child)
		child.queue_free()

	var orders := game.queued_orders_for(PLAYER)
	_orders_card.visible = not orders.is_empty()
	if orders.is_empty():
		return

	for index in orders.size():
		var order: Dictionary = orders[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var label := Label.new()
		label.text = _order_text(order)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", UiStyle.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var cancel := Button.new()
		cancel.text = Loc.t("cancel")
		cancel.custom_minimum_size = Vector2(58, 24)
		cancel.add_theme_font_size_override("font_size", 11)
		UiStyle.apply_hud_button(cancel)
		cancel.pressed.connect(_on_cancel_order.bind(index))
		row.add_child(cancel)

		_orders_list.add_child(row)

	_orders_scroll.custom_minimum_size.y = _card_list_height(orders.size(), ORDER_ROW_HEIGHT)


## Height for a card's scroll area: one row per entry, capped so a long list
## never pushes the card past the bottom of the screen.
func _card_list_height(rows: int, row_height: float) -> float:
	var max_height := get_viewport().get_visible_rect().size.y * CARD_MAX_HEIGHT_RATIO
	return clampf(float(rows) * row_height, row_height, maxf(max_height - 52.0, row_height))


func _order_text(order: Dictionary) -> String:
	if String(order.get("type", "")) == "move":
		var units: Dictionary = order.get("units", {})
		return Loc.t("order_move", [
			_province_name(String(order.get("from_id", ""))),
			_province_name(String(order.get("to_id", ""))),
			CombatResolver.troop_count(units),
		])
	return Loc.t("order_recruit", [
		int(order.get("count", 0)),
		Loc.unit_name(String(order.get("unit_id", ""))),
		_province_name(String(order.get("province_id", ""))),
	])


func _on_cancel_order(index: int) -> void:
	var result := game.cancel_order(PLAYER, index)
	if not bool(result.get("ok", false)):
		_hint.text = Loc.reason(String(result.get("reason", "")))
	_refresh()


func _province(province_id: String) -> ProvinceData:
	if game == null or game.map_state == null or province_id.is_empty():
		return null
	return game.map_state.get_province(province_id)


func _province_name(province_id: String) -> String:
	var province := _province(province_id)
	return province.display_name if province != null else province_id


func _on_game_finished(winner: int) -> void:
	_cancel_march()
	_hint.text = ""
	_game_over_winner = winner
	_build_game_over()


func _build_game_over() -> void:
	var existing := get_node_or_null("GameOver")
	if existing != null:
		existing.queue_free()

	var overlay := ColorRect.new()
	overlay.name = "GameOver"
	overlay.color = Color(0.02, 0.02, 0.04, 0.80)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	var won := _game_over_winner == PLAYER
	var title := Label.new()
	title.text = Loc.t("victory") if won else Loc.t("defeat")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", UiStyle.GOLD if won else UiStyle.DANGER)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = Loc.t("victory_body", [Loc.faction_name(_game_over_winner)])
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", UiStyle.TEXT)
	box.add_child(subtitle)

	var button := Button.new()
	button.text = Loc.t("new_game")
	button.custom_minimum_size = Vector2(200, 44)
	button.pressed.connect(_on_new_game_pressed)
	box.add_child(button)
	UiStyle.apply_menu_button(button)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER


func _on_new_game_pressed() -> void:
	turn_manager.start_game()
	get_tree().reload_current_scene()
