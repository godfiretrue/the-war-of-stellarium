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
## Cards grow with their content but never past this share of the screen.
const CARD_MAX_HEIGHT_RATIO := 0.40
const ORDER_ROW_HEIGHT := 40.0
const BATTLE_ROW_HEIGHT := 74.0
const TOAST_HOLD_SECONDS := 2.6

const MENU_SAVE := 0
const MENU_OPTIONS := 1
const MENU_MAIN := 2

var game: GameState
var turn_manager: Node
var map_view: MapView

var selected_province_id: String = ""
var march_origin_id: String = ""

var _last_battles: Array = []
var _game_over_winner := -2

var _orders_collapsed := true
var _had_orders := false
var _toast_tween: Tween
var _pulse_tween: Tween
var _pulse_hot := false

@onready var _root: Control = $Root
@onready var _emblem: PanelContainer = $Root/TopBar/TopMargin/TopRow/Emblem
@onready var _faction_dot: ColorRect = $Root/TopBar/TopMargin/TopRow/Emblem/FactionDot
@onready var _faction_name: Label = $Root/TopBar/TopMargin/TopRow/FactionName
@onready var _gold_chip: PanelContainer = $Root/TopBar/TopMargin/TopRow/GoldChip
@onready var _gold_icon: UiIcon = $Root/TopBar/TopMargin/TopRow/GoldChip/GoldBox/GoldIcon
@onready var _gold: Label = $Root/TopBar/TopMargin/TopRow/GoldChip/GoldBox/Gold
@onready var _manpower_chip: PanelContainer = $Root/TopBar/TopMargin/TopRow/ManpowerChip
@onready var _manpower_icon: UiIcon = $Root/TopBar/TopMargin/TopRow/ManpowerChip/ManpowerBox/ManpowerIcon
@onready var _manpower: Label = $Root/TopBar/TopMargin/TopRow/ManpowerChip/ManpowerBox/Manpower
@onready var _resource_chip: PanelContainer = $Root/TopBar/TopMargin/TopRow/ResourceChip
@onready var _resource_icon: UiIcon = $Root/TopBar/TopMargin/TopRow/ResourceChip/ResourceBox/ResourceIcon
@onready var _resource: Label = $Root/TopBar/TopMargin/TopRow/ResourceChip/ResourceBox/Resource
@onready var _turn_badge: PanelContainer = $Root/TopBar/TopMargin/TopRow/TurnBadge
@onready var _turn: Label = $Root/TopBar/TopMargin/TopRow/TurnBadge/Turn
@onready var _menu_button: Button = $Root/TopBar/TopMargin/TopRow/MenuButton
@onready var _menu_popup: PopupMenu = $Root/TopBar/MenuPopup
@onready var _accent_bar: ColorRect = $Root/BottomPanel/PanelRow/AccentBar
@onready var _name: Label = $Root/BottomPanel/PanelRow/InfoBox/ProvinceName
@onready var _meta: Label = $Root/BottomPanel/PanelRow/InfoBox/ProvinceMeta
@onready var _troops: Label = $Root/BottomPanel/PanelRow/InfoBox/StatsRow/Troops
@onready var _attack: Label = $Root/BottomPanel/PanelRow/InfoBox/StatsRow/Attack
@onready var _defense: Label = $Root/BottomPanel/PanelRow/InfoBox/StatsRow/Defense
@onready var _income: Label = $Root/BottomPanel/PanelRow/InfoBox/StatsRow/Income
@onready var _garrison_title: Label = $Root/BottomPanel/PanelRow/GarrisonBox/GarrisonTitle
@onready var _garrison_list: HBoxContainer = $Root/BottomPanel/PanelRow/GarrisonBox/GarrisonList
@onready var _recruit_a: Button = $Root/BottomPanel/PanelRow/ActionsBox/RecruitRow/RecruitA
@onready var _recruit_b: Button = $Root/BottomPanel/PanelRow/ActionsBox/RecruitRow/RecruitB
@onready var _march: Button = $Root/BottomPanel/PanelRow/ActionsBox/March
@onready var _end_turn: Button = $Root/EndTurn
@onready var _orders_tab: Button = $Root/OrdersTab
@onready var _orders_card: PanelContainer = $Root/OrdersCard
@onready var _orders_title: Label = $Root/OrdersCard/OrdersBox/OrdersHeader/OrdersTitle
@onready var _orders_collapse: Button = $Root/OrdersCard/OrdersBox/OrdersHeader/OrdersCollapse
@onready var _orders_scroll: ScrollContainer = $Root/OrdersCard/OrdersBox/OrdersScroll
@onready var _orders_list: VBoxContainer = $Root/OrdersCard/OrdersBox/OrdersScroll/OrdersList
@onready var _battle_card: PanelContainer = $Root/BattleCard
@onready var _battle_title: Label = $Root/BattleCard/BattleBox/BattleHeader/BattleTitle
@onready var _battle_dismiss: Button = $Root/BattleCard/BattleBox/BattleHeader/BattleDismiss
@onready var _battle_scroll: ScrollContainer = $Root/BattleCard/BattleBox/BattleScroll
@onready var _battle_list: VBoxContainer = $Root/BattleCard/BattleBox/BattleScroll/BattleList
@onready var _toast: PanelContainer = $Root/Toast
@onready var _toast_label: Label = $Root/Toast/ToastLabel
@onready var _march_panel: PanelContainer = $Root/MarchPanel
@onready var _march_label: Label = $Root/MarchPanel/MarchBox/MarchLabel
@onready var _march_count: SpinBox = $Root/MarchPanel/MarchBox/MarchCount
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
	_setup_focus_neighbors()
	_build_menu()

	_battle_card.visible = false
	_orders_card.visible = false
	_toast.visible = false
	_orders_collapsed = true
	_pulse_hot = false

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
		map_view.province_selected.connect(_on_map_selection)

	_recruit_a.pressed.connect(_on_recruit.bind(0))
	_recruit_b.pressed.connect(_on_recruit.bind(1))
	_march.pressed.connect(_on_march_pressed)
	_end_turn.pressed.connect(_on_end_turn_pressed)
	_menu_button.pressed.connect(_open_menu)
	_menu_popup.id_pressed.connect(_on_menu_id)
	_orders_tab.pressed.connect(_toggle_orders)
	_orders_collapse.pressed.connect(_toggle_orders)
	_battle_dismiss.pressed.connect(_dismiss_battles)
	_settings_panel.closed.connect(_on_settings_closed)
	_end_turn.resized.connect(_on_end_turn_resized)


# --- Focus navigation ----------------------------------------------------

## HUD buttons are focusable so a gamepad (or Tab) can move between them.
## Explicit neighbours keep that movement predictable: the buttons form a
## clockwise loop around the screen instead of jumping to whichever control
## happens to be geometrically closest. Godot skips hidden neighbours, so the
## orders/battle cards simply drop out of the loop while they are collapsed.
func _setup_focus_neighbors() -> void:
	var loop: Array[Control] = [
		_menu_button,      # top right
		_battle_dismiss,   # battle card, right edge
		_end_turn,         # bottom right
		_march,            # bottom centre
		_recruit_b,
		_recruit_a,        # bottom left-centre
		_orders_tab,       # left edge
		_orders_collapse,  # orders card, left edge
	]
	for index in loop.size():
		var button: Control = loop[index]
		var previous: Control = loop[(index - 1 + loop.size()) % loop.size()]
		var following: Control = loop[(index + 1) % loop.size()]
		button.focus_neighbor_left = previous.get_path()
		button.focus_neighbor_right = following.get_path()


# --- Look ----------------------------------------------------------------

func _style() -> void:
	_root.theme = UiStyle.hud_theme()

	var emblem_box := UiStyle.flat(Color(0.08, 0.09, 0.14, 0.95), UiStyle.GOLD_TRIM, 4)
	emblem_box.set_content_margin_all(6.0)
	_emblem.add_theme_stylebox_override("panel", emblem_box)
	_faction_dot.color = UiStyle.HUMAN
	_faction_name.add_theme_color_override("font_color", UiStyle.TEXT)
	_faction_name.text = Loc.faction_name(PLAYER)

	var chips: Array[PanelContainer] = [_gold_chip, _manpower_chip, _resource_chip]
	var accents: Array[Color] = [
		Color(0.91, 0.77, 0.42), Color(0.56, 0.78, 0.91), Color(0.79, 0.65, 0.91),
	]
	for index in chips.size():
		chips[index].add_theme_stylebox_override(
			"panel", UiStyle.capsule(Color(0.07, 0.08, 0.13, 0.85), Color(accents[index], 0.40))
		)
	_gold_icon.kind = UiIcon.Kind.COIN
	_gold_icon.tint = accents[0]
	_manpower_icon.kind = UiIcon.Kind.MANPOWER
	_manpower_icon.tint = accents[1]
	_resource_icon.kind = UiIcon.Kind.ETHER
	_resource_icon.tint = accents[2]
	_turn.add_theme_color_override("font_color", UiStyle.GOLD)

	UiStyle.apply_hud_button(_recruit_a)
	UiStyle.apply_hud_button(_recruit_b)
	UiStyle.apply_hud_button(_march)
	UiStyle.apply_primary_button(_end_turn)
	UiStyle.apply_ghost_button(_menu_button)
	UiStyle.apply_ghost_button(_orders_collapse)
	UiStyle.apply_ghost_button(_battle_dismiss)
	UiStyle.apply_tab_button(_orders_tab)
	_menu_button.add_theme_font_size_override("font_size", 16)

	_orders_card.add_theme_stylebox_override("panel", UiStyle.hud_panel())
	_battle_card.add_theme_stylebox_override("panel", UiStyle.hud_panel())
	_march_panel.add_theme_stylebox_override("panel", UiStyle.hud_panel())

	var toast_box := UiStyle.flat(Color(0.030, 0.038, 0.065, 0.97), UiStyle.GOLD_TRIM, 6)
	toast_box.set_border_width_all(1)
	toast_box.set_content_margin_all(8.0)
	toast_box.content_margin_left = 18.0
	toast_box.content_margin_right = 18.0
	_toast.add_theme_stylebox_override("panel", toast_box)


func _on_end_turn_resized() -> void:
	_end_turn.pivot_offset = _end_turn.size * 0.5


func _build_menu() -> void:
	_menu_popup.add_item(Loc.t("save"), MENU_SAVE)
	_menu_popup.add_item(Loc.t("options"), MENU_OPTIONS)
	_menu_popup.add_item(Loc.t("menu"), MENU_MAIN)
	_refresh_menu()


func _refresh_menu() -> void:
	_menu_popup.set_item_text(MENU_SAVE, Loc.t("save"))
	_menu_popup.set_item_text(MENU_OPTIONS, Loc.t("options"))
	_menu_popup.set_item_text(MENU_MAIN, Loc.t("menu"))
	var can_save: bool = turn_manager.is_player_planning() and not game.has_queued_orders()
	_menu_popup.set_item_disabled(MENU_SAVE, not can_save)
	_menu_button.tooltip_text = Loc.t("tip_menu_button")


func _open_menu() -> void:
	_refresh_menu()
	_menu_popup.reset_size()
	var pos := _menu_button.global_position + Vector2(0, _menu_button.size.y + 4)
	_menu_popup.position = Vector2i(pos)
	_menu_popup.popup()


func _on_menu_id(id: int) -> void:
	match id:
		MENU_SAVE:
			_on_save_pressed()
		MENU_OPTIONS:
			_open_settings()
		MENU_MAIN:
			_on_menu_pressed()


# --- Toast ---------------------------------------------------------------

## Small upper-centre message used for every hint and every rules error.
func _show_toast(text: String) -> void:
	if text.is_empty():
		return
	_toast_label.text = text
	_toast.visible = true
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.16)
	_toast_tween.tween_interval(TOAST_HOLD_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


# --- Refresh -------------------------------------------------------------

func _refresh() -> void:
	if game == null or game.map_state == null:
		return

	_refresh_economy()
	_turn.text = Loc.t("turn_badge", [turn_manager.turn_number, Loc.phase_short(turn_manager.phase)])
	_style_turn_badge()

	_refresh_static_text()
	_refresh_selection()
	_refresh_buttons()
	_refresh_orders()
	_refresh_menu()
	_update_end_turn_pulse()


func _refresh_economy() -> void:
	_gold.text = str(game.get_gold(PLAYER))
	_manpower.text = str(game.get_manpower(PLAYER))

	var key := game.faction_resource_key(PLAYER)
	var resource_value := game.get_resource(PLAYER, key)
	_resource.text = "%d %s" % [resource_value, Loc.resource_name(key)]

	var income := game.income_for(PLAYER)
	var upkeep := game.upkeep_for(PLAYER)
	var resources: Dictionary = income.get("resources", {})
	var resource_income := int(resources.get(key, 0))

	_gold_chip.tooltip_text = Loc.t("tip_gold", [
		game.get_gold(PLAYER), int(income.get("gold", 0)), upkeep,
	])
	_manpower_chip.tooltip_text = Loc.t("tip_manpower", [
		game.get_manpower(PLAYER), int(income.get("manpower", 0)),
	])
	_resource_chip.tooltip_text = Loc.t("tip_resource", [
		Loc.resource_name(key), resource_value, resource_income,
	])


## Button labels and tooltips that do not depend on the selection.
func _refresh_static_text() -> void:
	_faction_name.text = Loc.faction_name(PLAYER)
	_march.text = Loc.t("march")
	_end_turn.text = Loc.t("end_turn")

	_orders_title.text = Loc.t("orders_title")
	_garrison_title.text = Loc.t("garrison_title")
	_march_label.text = Loc.t("march_troops")
	_orders_tab.tooltip_text = Loc.t("tip_orders_toggle")
	_orders_collapse.tooltip_text = Loc.t("tip_orders_collapse")
	_battle_dismiss.tooltip_text = Loc.t("close")


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
		_meta.tooltip_text = ""
		_clear_stats()
		_refresh_garrison(null)
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
	_meta.text = "%s · %s · %s · %s" % [
		role,
		Loc.territory_type(province.territory_type),
		Loc.faction_name(province.owner_faction),
		Loc.terrain_name(province.terrain),
	]
	if province.unrest_turns > 0:
		_meta.text += " · " + Loc.t("unrest", [province.unrest_turns])

	# Terrain and fortress are the two inputs of the economy and the defence
	# multiplier, so the dock explains both without adding another text row.
	var base_income := province.base_income()
	var terrain_tip := Loc.t("tip_terrain", [
		int(base_income["gold"]),
		int(base_income["manpower"]),
		Balance.defense_multiplier(province.terrain, province.is_fortress),
	])
	if province.is_fortress:
		terrain_tip += "\n" + Loc.t("fortress_upkeep", [Balance.FORTRESS_UPKEEP_GOLD])
	_meta.tooltip_text = terrain_tip

	var troops := province.total_troops()
	var militia := province.home_guard if Balance.HOME_GUARD_ENABLED else 0
	_troops.text = Loc.t("troops", [troops]) if troops > 0 else Loc.t("troops_none")
	if militia > 0:
		_troops.text += " · " + Loc.t("militia", [militia])
	_troops.add_theme_color_override(
		"font_color", UiStyle.TEXT if (troops > 0 or militia > 0) else UiStyle.TEXT_DIM
	)

	# defense_power() already applies the terrain multiplier.
	if troops > 0 or militia > 0:
		_attack.text = "%s %.0f" % [Loc.t("stat_attack"), province.attack_power()]
		_defense.text = "%s %.0f" % [Loc.t("stat_defense"), province.defense_power()]
	else:
		_attack.text = ""
		_defense.text = ""

	_income.text = ""
	if not province.resource_type.is_empty():
		_income.text = Loc.t("income", [
			province.resource_per_turn, Loc.resource_name(province.resource_type)
		])

	_refresh_garrison(province)


## Garrison as small unit cards (icon tile + count) instead of one text line.
func _refresh_garrison(province: ProvinceData) -> void:
	for child in _garrison_list.get_children():
		_garrison_list.remove_child(child)
		child.queue_free()

	if province == null:
		_add_garrison_empty()
		return

	var total := province.total_troops()
	_garrison_title.text = Loc.t("garrison_title")
	if total > 0:
		_garrison_title.text = "%s · %d" % [Loc.t("garrison_title"), total]

	for unit_id: String in province.garrison.keys():
		var count := int(province.garrison[unit_id])
		if count <= 0:
			continue
		var unit := UnitCatalog.get_unit(unit_id)
		var unit_color := UiStyle.faction_color(province.owner_faction)
		if unit != null:
			unit_color = unit_color.lerp(UiStyle.GOLD, 0.15)
		var tooltip := "%s × %d" % [Loc.unit_name(unit_id), count]
		if unit != null:
			tooltip = "%s\n%s %d · %s %d" % [
				Loc.t("garrison_unit_line", [Loc.unit_name(unit_id), count]),
				Loc.t("stat_attack"), int(unit.attack),
				Loc.t("stat_defense"), int(unit.defense),
			]
		_garrison_list.add_child(_unit_card(
			unit_color, count, tooltip, _unit_icon_kind(unit_id)
		))

	if province.home_guard > 0 and Balance.HOME_GUARD_ENABLED:
		_garrison_list.add_child(_unit_card(
			UiStyle.GOLD, province.home_guard,
			Loc.t("garrison_militia", [province.home_guard]), UiIcon.Kind.SHIELD
		))

	if _garrison_list.get_child_count() == 0:
		_add_garrison_empty()


func _add_garrison_empty() -> void:
	var label := Label.new()
	label.text = Loc.t("garrison_empty")
	label.add_theme_font_size_override("font_size", UiStyle.FONT_SMALL)
	label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_garrison_list.add_child(label)


func _unit_card(color: Color, count: int, tooltip: String, kind: int = UiIcon.Kind.SHIELD) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(52, 46)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.tooltip_text = tooltip
	card.add_theme_stylebox_override("panel", UiStyle.unit_card_box(PLAYER))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(row)

	var icon := UiIcon.new()
	icon.custom_minimum_size = Vector2(14, 14)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.kind = kind
	icon.tint = color
	row.add_child(icon)

	var label := Label.new()
	label.text = str(count)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", UiStyle.FONT_BODY)
	label.add_theme_color_override("font_color", UiStyle.TEXT)
	row.add_child(label)
	return card


## Melee and ranged units get their own glyph so a garrison reads at a glance.
func _unit_icon_kind(unit_id: String) -> int:
	if unit_id.contains("sword") or unit_id.contains("boar"):
		return UiIcon.Kind.SWORD
	return UiIcon.Kind.BOW


func _clear_stats() -> void:
	_troops.text = ""
	_attack.text = ""
	_defense.text = ""
	_income.text = ""


func _refresh_buttons() -> void:
	var player_planning: bool = turn_manager.is_player_planning()
	_end_turn.disabled = not player_planning

	var province := _selected_province()
	var owned: bool = province != null and province.is_owned_by(PLAYER)
	var can_march := player_planning and owned and province.total_troops() > 0
	_march.disabled = not can_march
	_march.tooltip_text = _march_reason(player_planning, province, owned)

	# March is the expected next step while a move is armed; otherwise ending the
	# turn is. Only one of them wears the gold primary style at a time.
	if march_origin_id.is_empty():
		UiStyle.apply_hud_button(_march)
		UiStyle.apply_primary_button(_end_turn)
	else:
		UiStyle.apply_primary_button(_march)
		UiStyle.apply_hud_button(_end_turn)

	var is_city_province := province != null and province.is_city
	var in_unrest := province != null and province.unrest_turns > 0
	var can_recruit_base := player_planning and owned and is_city_province and not in_unrest

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
		var costs := game.recruit_costs(PLAYER, unit_id)
		var gold_cost := int(costs["gold"])
		var manpower_cost := int(costs["manpower"])

		button.tooltip_text = Loc.t("recruit_tooltip", [
			Loc.unit_name(unit_id), int(unit.attack), int(unit.defense), int(unit.upkeep),
		])
		if game.capital_penalty_turns(PLAYER) > 0:
			button.tooltip_text = "%s\n%s" % [
				button.tooltip_text,
				Loc.t("capital_penalty", [game.capital_penalty_turns(PLAYER)]),
			]

		if province == null:
			button.text = "+ %s" % Loc.unit_name(unit_id)
			button.disabled = true
			button.tooltip_text = "%s\n%s" % [
				button.tooltip_text, Loc.t("reason_no_selection"),
			]
		elif not owned:
			button.text = "+ %s" % Loc.unit_name(unit_id)
			button.disabled = true
			button.tooltip_text = "%s\n%s" % [
				button.tooltip_text, Loc.t("reason_not_owned"),
			]
		elif not player_planning:
			button.text = "+ %s" % Loc.unit_name(unit_id)
			button.disabled = true
			button.tooltip_text = "%s\n%s" % [
				button.tooltip_text, Loc.t("reason_not_planning"),
			]
		elif not is_city_province:
			# Corridors cannot recruit; show the unit but explain why it is off.
			button.text = "+ %s" % Loc.unit_name(unit_id)
			button.disabled = true
			button.tooltip_text = "%s\n%s" % [
				button.tooltip_text, Loc.t("recruit_city_only"),
			]
		elif in_unrest:
			# A province just taken cannot raise troops until it settles.
			button.text = "+ %s" % Loc.unit_name(unit_id)
			button.disabled = true
			button.tooltip_text = "%s\n%s" % [
				button.tooltip_text, Loc.t("recruit_unrest", [province.unrest_turns]),
			]
		else:
			button.text = Loc.t("recruit_short", [Loc.unit_name(unit_id)])
			button.tooltip_text = "%s\n%s" % [
				button.tooltip_text, Loc.t("recruit_cost", [gold_cost, manpower_cost]),
			]
			var affordable := game.can_afford(PLAYER, gold_cost, manpower_cost)
			button.disabled = not (can_recruit_base and affordable)
			if not affordable:
				button.tooltip_text = "%s\n%s" % [
					button.tooltip_text, Loc.t("recruit_reason_gold"),
				]


func _march_reason(player_planning: bool, province: ProvinceData, owned: bool) -> String:
	if not player_planning:
		return Loc.t("reason_not_planning")
	if province == null:
		return Loc.t("reason_no_selection")
	if not owned:
		return Loc.t("reason_not_owned")
	if province.total_troops() <= 0:
		return Loc.t("hint_no_troops")
	return Loc.t("tip_march")


## Gentle pulse while the player still has orders queued or affordable troops
## waiting to be recruited; completely still otherwise.
func _update_end_turn_pulse() -> void:
	var hot: bool = turn_manager.is_player_planning() and (
		not game.queued_orders_for(PLAYER).is_empty() or _can_recruit_anything()
	)
	if hot == _pulse_hot:
		return
	_pulse_hot = hot

	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	_end_turn.scale = Vector2.ONE
	_end_turn.modulate = Color.WHITE
	if not hot:
		return

	_on_end_turn_resized()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_end_turn, "scale", Vector2(1.035, 1.035), 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.parallel().tween_property(_end_turn, "modulate", Color(1.06, 1.06, 1.06), 1.0)
	_pulse_tween.tween_property(_end_turn, "scale", Vector2.ONE, 1.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.parallel().tween_property(_end_turn, "modulate", Color.WHITE, 1.0)


func _can_recruit_anything() -> bool:
	for unit_id: String in UnitCatalog.units_for_faction(PLAYER):
		var costs := game.recruit_costs(PLAYER, unit_id)
		if game.can_afford(PLAYER, int(costs["gold"]), int(costs["manpower"])):
			return true
	return false


func _retranslate() -> void:
	# The language lives in Settings; re-render everything that carries text.
	if game == null:
		return
	_faction_name.text = Loc.faction_name(PLAYER)
	_refresh()
	_refresh_menu()
	if _battle_card.visible and not _last_battles.is_empty():
		_render_battles()


# --- Player actions ------------------------------------------------------

func _on_recruit(index: int) -> void:
	if not turn_manager.is_player_planning() or selected_province_id.is_empty():
		return

	var unit_ids := UnitCatalog.units_for_faction(PLAYER)
	if index < 0 or index >= unit_ids.size():
		return

	var result := game.queue_recruit(PLAYER, selected_province_id, unit_ids[index], 1)
	if not bool(result.get("ok", false)):
		_show_toast(Loc.reason(String(result.get("reason", ""))))
	_refresh()


func _on_march_pressed() -> void:
	if not turn_manager.is_player_planning():
		_show_toast(Loc.t("hint_bot_turn"))
		return

	if not march_origin_id.is_empty():
		_cancel_march()
		return

	var province := _selected_province()
	if province == null or not province.is_owned_by(PLAYER):
		return
	if province.total_troops() <= 0:
		_show_toast(Loc.t("hint_no_troops"))
		return

	march_origin_id = selected_province_id
	_show_toast(Loc.t("hint_march"))
	_open_march_panel(province.total_troops())
	if map_view != null:
		map_view.set_march_targets(PackedStringArray(province.neighbors), province.id)
	_refresh_buttons()


func _on_end_turn_pressed() -> void:
	if not turn_manager.is_player_planning():
		return
	_cancel_march()
	_dismiss_battles()
	turn_manager.end_player_turn()


func _on_save_pressed() -> void:
	if not turn_manager.is_player_planning() or game.has_queued_orders():
		_show_toast(Loc.t("save_turn_start_only"))
		return
	var saved := SaveSystem.save_game(game, turn_manager.turn_number)
	_show_toast(Loc.t("saved") if saved else Loc.t("save_failed"))


func _open_settings() -> void:
	_cancel_march()
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


## Keeps the panel in sync when the map selects a province on its own (capital
## on load, battle-report focus).
func _on_map_selection(province_id: String) -> void:
	if selected_province_id == province_id:
		return
	selected_province_id = province_id
	_refresh()


func _handle_march_click(target_id: String) -> void:
	var origin_id := march_origin_id
	var map := game.map_state

	if not turn_manager.is_player_planning():
		_cancel_march()
		return

	if not map.are_adjacent(origin_id, target_id):
		_cancel_march()
		_show_toast(Loc.t("hint_not_neighbor"))
		_select(target_id)
		return

	var origin := map.get_province(origin_id)
	var wanted := mini(int(_march_count.value), origin.total_troops())
	var result := game.queue_move(PLAYER, origin_id, target_id, _units_for_count(origin.garrison, wanted))
	_cancel_march()

	if not bool(result.get("ok", false)):
		_show_toast(Loc.reason(String(result.get("reason", ""))))
		_refresh()
		return

	_show_toast(Loc.t("hint_order_queued"))
	_select(origin_id)


func _cancel_march() -> void:
	march_origin_id = ""
	_march_panel.visible = false
	if map_view != null:
		map_view.set_march_targets(PackedStringArray())
	if _march != null:
		UiStyle.apply_hud_button(_march)
	_refresh_buttons()


## Shows the troop-count chooser for the armed march, defaulting to the whole
## garrison so the player can still send everything with one click.
func _open_march_panel(available: int) -> void:
	_march_label.text = Loc.t("march_troops")
	_march_count.min_value = 1
	_march_count.max_value = maxi(available, 1)
	_march_count.value = maxi(available, 1)
	_march_panel.visible = true


## The first `count` troops of a garrison, used for partial marches. Unit order
## is stable, so the same count always sends the same stack.
func _units_for_count(garrison: Dictionary, count: int) -> Dictionary:
	var sending: Dictionary = {}
	var remaining: int = maxi(count, 0)
	for unit_id: String in garrison.keys():
		if remaining <= 0:
			break
		var take: int = mini(int(garrison[unit_id]), remaining)
		if take > 0:
			sending[unit_id] = take
			remaining -= take
	return sending


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

## Shortcuts are read in _input, before the GUI gets the event. A focused HUD
## button would otherwise consume Space/Enter and the shortcut would be lost;
## marking the key handled also stops that button from acting on it twice.
func _input(event: InputEvent) -> void:
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
		# Only bot planning needs a message; resolution blinks past.
		pass
	elif turn_manager.is_bot_planning():
		_show_toast(Loc.t("hint_bot_turn"))
		_cancel_march()
	_refresh()


func _on_resolution_finished(summary: Dictionary) -> void:
	_last_battles = summary.get("battles", [])
	if _last_battles.is_empty():
		_battle_card.visible = false
		return
	_render_battles()


## Renders every battle of the turn in one scrollable panel. Rows stay until
## dismissed or a new turn is ended, so the report can be read at leisure.
func _render_battles() -> void:
	for child in _battle_list.get_children():
		_battle_list.remove_child(child)
		child.queue_free()

	_battle_title.text = Loc.t("battles_title", [_last_battles.size()])
	_battle_scroll.custom_minimum_size.y = _card_list_height(_last_battles.size(), BATTLE_ROW_HEIGHT)
	for result_variant in _last_battles:
		var result: Dictionary = result_variant
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0, BATTLE_ROW_HEIGHT)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.tooltip_text = Loc.t("battle_focus_tip")
		row.add_theme_stylebox_override("panel", UiStyle.row_box())

		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 1)
		row.add_child(column)

		var lines := _battle_text(result).split("\n")
		for index in lines.size():
			var label := Label.new()
			label.text = lines[index]
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override(
				"font_size", UiStyle.FONT_BODY if index == 0 else UiStyle.FONT_SMALL
			)
			var color := UiStyle.TEXT
			if index == 1:
				color = UiStyle.TEXT_DIM
			elif index >= 2:
				color = UiStyle.GOLD if bool(result.get("captured", false)) else UiStyle.TEXT_DIM
			label.add_theme_color_override("font_color", color)
			column.add_child(label)

		row.gui_input.connect(_on_battle_row_input.bind(result))
		row.mouse_entered.connect(_on_battle_row_hover.bind(row, true))
		row.mouse_exited.connect(_on_battle_row_hover.bind(row, false))
		_battle_list.add_child(row)

	_battle_card.visible = true
	_battle_card.modulate.a = 1.0


func _on_battle_row_hover(row: PanelContainer, hovered: bool) -> void:
	row.add_theme_stylebox_override(
		"panel", UiStyle.row_hover_box() if hovered else UiStyle.row_box()
	)


func _on_battle_row_input(event: InputEvent, result: Dictionary) -> void:
	if event is not InputEventMouseButton:
		return
	var button_event := event as InputEventMouseButton
	if not button_event.pressed or button_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var province_id := String(result.get("province_id", ""))
	if province_id.is_empty():
		province_id = String(result.get("to_id", ""))
	if province_id.is_empty():
		return
	if map_view != null:
		map_view.focus_province(province_id)
	_select(province_id)


func _dismiss_battles() -> void:
	_battle_card.visible = false


func _battle_text(result: Dictionary) -> String:
	var from_name := String(result.get("from_name", result.get("province_name", "?")))
	var to_name := String(result.get("to_name", result.get("province_name", "?")))
	var losses := Loc.t("battle_losses", [
		int(result.get("attacker_losses", 0)), int(result.get("defender_losses", 0)),
	])

	if bool(result.get("swap", false)):
		return "%s\n%s\n%s" % [
			Loc.t("battle_swap_line", [from_name, to_name]),
			losses,
			Loc.t("battle_captured") if bool(result.get("captured", false)) else Loc.t("battle_held"),
		]

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
	if map_view != null:
		map_view.set_hovered_order({})

	var orders := game.queued_orders_for(PLAYER)

	if not orders.is_empty() and not _had_orders:
		_orders_collapsed = false
	if orders.is_empty():
		_orders_collapsed = true
	_had_orders = not orders.is_empty()

	for index in orders.size():
		var order: Dictionary = orders[index]
		_orders_list.add_child(_order_row(order, index))

	if not orders.is_empty():
		_orders_scroll.custom_minimum_size.y = _card_list_height(orders.size(), ORDER_ROW_HEIGHT)

	_update_orders_visibility()


func _update_orders_visibility() -> void:
	var count := game.queued_orders_for(PLAYER).size()
	if count == 0:
		_orders_tab.text = Loc.t("orders_tab_empty")
	else:
		_orders_tab.text = Loc.t("orders_tab", [count])
	_orders_card.visible = count > 0 and not _orders_collapsed
	_orders_tab.text = ("▾ " if _orders_card.visible else "▸ ") + _orders_tab.text


func _toggle_orders() -> void:
	var count := game.queued_orders_for(PLAYER).size()
	if count == 0:
		_show_toast(Loc.t("orders_empty"))
		_orders_collapsed = true
	else:
		_orders_collapsed = not _orders_collapsed
	_update_orders_visibility()


func _order_row(order: Dictionary, index: int) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 36)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = "%s\n%s" % [_order_text(order), Loc.t("order_hover_tip")]
	row.add_theme_stylebox_override("panel", UiStyle.row_box())

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	row.add_child(line)

	var is_move := String(order.get("type", "")) == "move"
	var icon := UiIcon.new()
	icon.custom_minimum_size = Vector2(13, 13)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.kind = UiIcon.Kind.MOVE if is_move else UiIcon.Kind.RECRUIT
	icon.tint = UiStyle.ACCENT if is_move else UiStyle.GOLD
	line.add_child(icon)

	var label := Label.new()
	label.text = _order_short_text(order)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", UiStyle.FONT_SMALL)
	label.add_theme_color_override("font_color", UiStyle.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(label)

	var count := Label.new()
	count.text = _order_count_text(order)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.add_theme_font_size_override("font_size", UiStyle.FONT_SMALL)
	count.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(count)

	# Flat and small: the row is about the order, not the remove button. A
	# bordered 30px button also stole the width long province names need.
	var cancel := Button.new()
	cancel.text = "×"
	cancel.tooltip_text = Loc.t("cancel")
	cancel.custom_minimum_size = Vector2(20, 22)
	cancel.flat = true
	cancel.add_theme_font_size_override("font_size", UiStyle.FONT_BODY)
	cancel.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	cancel.add_theme_color_override("font_hover_color", UiStyle.DANGER)
	cancel.add_theme_color_override("font_pressed_color", UiStyle.DANGER)
	cancel.pressed.connect(_on_cancel_order.bind(index))
	line.add_child(cancel)

	row.gui_input.connect(_on_order_row_input.bind(order))
	row.mouse_entered.connect(_on_order_row_hover.bind(order, true))
	row.mouse_exited.connect(_on_order_row_hover.bind(order, false))
	return row


func _on_order_row_input(event: InputEvent, order: Dictionary) -> void:
	if event is not InputEventMouseButton:
		return
	var button_event := event as InputEventMouseButton
	if not button_event.pressed or button_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var province_id := String(order.get("from_id", order.get("province_id", "")))
	if not province_id.is_empty():
		_select(province_id)


func _on_order_row_hover(order: Dictionary, hovered: bool) -> void:
	if map_view != null:
		map_view.set_hovered_order(order if hovered else {})


## Height for a card's scroll area: one row per entry, capped so a long list
## never pushes the card past the bottom of the screen. The 4px handles the
## VBox separation, otherwise two battles need a scrollbar for a 4px overflow.
func _card_list_height(rows: int, row_height: float) -> float:
	var max_height := get_viewport().get_visible_rect().size.y * CARD_MAX_HEIGHT_RATIO
	var needed := float(rows) * row_height + float(maxi(rows - 1, 0)) * 4.0
	return clampf(needed, row_height, maxf(max_height - 52.0, row_height))


func _order_short_text(order: Dictionary) -> String:
	if String(order.get("type", "")) == "move":
		return Loc.t("order_short_move", [
			_province_name(String(order.get("from_id", ""))),
			_province_name(String(order.get("to_id", ""))),
		])
	return Loc.t("order_short_recruit", [
		int(order.get("count", 0)), Loc.unit_name(String(order.get("unit_id", ""))),
	])


func _order_count_text(order: Dictionary) -> String:
	if String(order.get("type", "")) == "move":
		var troops := CombatResolver.troop_count(order.get("units", {}))
		return Loc.t("order_count_one" if troops == 1 else "order_count", [troops])
	# The short text already reads "+1 Besteiros"; a trailing x1 only repeats it.
	return ""


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
		_show_toast(Loc.reason(String(result.get("reason", ""))))
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
