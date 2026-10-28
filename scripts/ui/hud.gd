class_name GameHUD
extends CanvasLayer
## Player-facing HUD and the player's map controller.
##
## Owns the two-step move flow (select a province, press March, click a
## neighbour) and the recruit buttons. Every rule change still goes through
## GameState, so the player and the bot share one rules path.

const PLAYER := Balance.PLAYER_FACTION

var game: GameState
var turn_manager: Node
var map_view: MapView

var selected_province_id: String = ""
var march_origin_id: String = ""

@onready var _gold: Label = $Root/TopStrip/TopRow/Gold
@onready var _manpower: Label = $Root/TopStrip/TopRow/Manpower
@onready var _resource: Label = $Root/TopStrip/TopRow/Resource
@onready var _turn: Label = $Root/TopStrip/TopRow/Turn
@onready var _info: Label = $Root/BottomStrip/BottomRow/Info
@onready var _recruit_a: Button = $Root/BottomStrip/BottomRow/RecruitA
@onready var _recruit_b: Button = $Root/BottomStrip/BottomRow/RecruitB
@onready var _march: Button = $Root/BottomStrip/BottomRow/March
@onready var _end_turn: Button = $Root/BottomStrip/BottomRow/EndTurn
@onready var _hint: Label = $Root/Hint
@onready var _battle: Label = $Root/Battle
@onready var _save: Button = $Root/BottomStrip/BottomRow/Save
@onready var _menu: Button = $Root/BottomStrip/BottomRow/Menu


func _ready() -> void:
	game = get_node_or_null("/root/Game") as GameState
	turn_manager = get_node_or_null("/root/TurnManager")
	map_view = get_parent() as MapView

	if game == null or turn_manager == null:
		push_error("GameHUD: Game/TurnManager autoloads are missing")
		return

	game.state_changed.connect(_refresh)
	game.battle_resolved.connect(_on_battle_resolved)
	turn_manager.phase_changed.connect(_on_phase_changed)
	turn_manager.game_finished.connect(_on_game_finished)

	if map_view != null:
		map_view.province_clicked.connect(_on_map_clicked)

	_recruit_a.pressed.connect(_on_recruit.bind(0))
	_recruit_b.pressed.connect(_on_recruit.bind(1))
	_march.pressed.connect(_on_march_pressed)
	_end_turn.pressed.connect(_on_end_turn_pressed)
	_save.pressed.connect(_on_save_pressed)
	_menu.pressed.connect(_on_menu_pressed)

	_battle.text = ""
	_hint.text = ""
	_refresh()


# --- Refresh -------------------------------------------------------------

func _refresh() -> void:
	if game == null or game.map_state == null:
		return

	_gold.text = "Gold %d" % game.get_gold(PLAYER)
	_manpower.text = "Manpower %d" % game.get_manpower(PLAYER)

	var key := game.faction_resource_key(PLAYER)
	_resource.text = "%s %d" % [Balance.resource_name(key), game.get_resource(PLAYER, key)]
	_turn.text = "Turn %d · %s" % [turn_manager.turn_number, turn_manager.phase_short_name()]

	_refresh_selection()
	_refresh_buttons()


func _refresh_selection() -> void:
	var province := _selected_province()
	if province == null:
		_info.text = "Select a province"
		return

	var header := "%s — %s, %s" % [
		province.display_name,
		Balance.faction_name(province.owner_faction),
		Balance.terrain_name(province.terrain),
	]
	if province.is_capital:
		header += " (capital)"

	var lines := PackedStringArray([header])
	lines.append("Garrison: %d troops [%s]" % [province.total_troops(), province.garrison_summary()])
	lines.append("Attack %.0f · Defence %.0f (terrain x%.2f)" % [
		province.attack_power(), province.defense_power(), Balance.terrain_defense(province.terrain),
	])
	if not province.resource_type.is_empty():
		lines.append("%s +%d per turn" % [
			Balance.resource_name(province.resource_type), province.resource_per_turn,
		])
	_info.text = "\n".join(lines)


func _refresh_buttons() -> void:
	var player_turn: bool = turn_manager.is_player_turn()
	_end_turn.disabled = not player_turn

	var province := _selected_province()
	var owned: bool = province != null and province.is_owned_by(PLAYER)
	_march.disabled = not (player_turn and owned and province.total_troops() > 0)

	var unit_ids := UnitCatalog.units_for_faction(PLAYER)
	var buttons: Array[Button] = [_recruit_a, _recruit_b]
	for index in buttons.size():
		var button := buttons[index]
		if index >= unit_ids.size():
			button.visible = false
			continue
		button.visible = true

		var unit := UnitCatalog.get_unit(unit_ids[index])
		var costs := unit.costs_for(PLAYER)
		var gold_cost := int(costs["gold"])
		var manpower_cost := int(costs["manpower"])
		button.text = "Recruit %s — %dg %dmp" % [unit.display_name, gold_cost, manpower_cost]
		button.disabled = not (player_turn and owned and game.can_afford(PLAYER, gold_cost, manpower_cost))


# --- Player actions ------------------------------------------------------

func _on_recruit(index: int) -> void:
	if not turn_manager.is_player_turn() or selected_province_id.is_empty():
		return

	var unit_ids := UnitCatalog.units_for_faction(PLAYER)
	if index < 0 or index >= unit_ids.size():
		return

	var result := game.recruit(PLAYER, selected_province_id, unit_ids[index], 1)
	_hint.text = "" if result.get("ok", false) else String(result.get("reason", "cannot recruit"))
	_refresh()


func _on_march_pressed() -> void:
	if not turn_manager.is_player_turn():
		return
	var province := _selected_province()
	if province == null or not province.is_owned_by(PLAYER) or province.total_troops() <= 0:
		return

	march_origin_id = selected_province_id
	_hint.text = "March: click an adjacent province to move or attack."
	_refresh()


func _on_end_turn_pressed() -> void:
	if not turn_manager.is_player_turn():
		return
	march_origin_id = ""
	_hint.text = ""
	_battle.text = ""
	turn_manager.end_player_turn()


func _on_save_pressed() -> void:
	var saved := SaveSystem.save_game(game, turn_manager.turn_number)
	_hint.text = "Game saved." if saved else "Saving failed."


func _on_menu_pressed() -> void:
	SaveSystem.save_game(game, turn_manager.turn_number)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_map_clicked(province_id: String) -> void:
	if not march_origin_id.is_empty():
		_handle_march_click(province_id)
	else:
		_select(province_id)


func _handle_march_click(target_id: String) -> void:
	var origin_id := march_origin_id
	var map := game.map_state

	if not turn_manager.is_player_turn():
		march_origin_id = ""
		_hint.text = ""
		return

	if not map.are_adjacent(origin_id, target_id):
		march_origin_id = ""
		_hint.text = ""
		_select(target_id)
		return

	var origin := map.get_province(origin_id)
	var result := game.move(PLAYER, origin_id, target_id, origin.garrison.duplicate())
	march_origin_id = ""

	if not bool(result.get("ok", false)):
		_hint.text = String(result.get("reason", "move failed"))
		_refresh()
		return

	_hint.text = ""
	var kind := String(result.get("kind", ""))
	if kind == "move" or bool(result.get("captured", false)):
		_select(target_id)
	else:
		_select(origin_id)


func _select(province_id: String) -> void:
	selected_province_id = province_id
	if map_view != null:
		map_view.select_province(province_id)
	_refresh()


func _selected_province() -> ProvinceData:
	if game == null or game.map_state == null or selected_province_id.is_empty():
		return null
	return game.map_state.get_province(selected_province_id)


# --- Signals -------------------------------------------------------------

func _on_phase_changed(_phase: int) -> void:
	_refresh()


func _on_battle_resolved(result: Dictionary) -> void:
	var attacker := Balance.faction_name(int(result.get("attacker_faction", 0)))
	var defender := Balance.faction_name(int(result.get("defender_faction", 1)))
	_battle.text = "Battle at %s\n%s attacked %s — power %.0f vs %.0f\nLosses: %d attacker, %d defender · %s" % [
		String(result.get("province_name", "?")),
		attacker,
		defender,
		float(result.get("attacker_power", 0.0)),
		float(result.get("defender_power", 0.0)),
		int(result.get("attacker_losses", 0)),
		int(result.get("defender_losses", 0)),
		"province captured" if bool(result.get("captured", false)) else "province held",
	]
	_refresh()


func _on_game_finished(winner: int) -> void:
	march_origin_id = ""
	_hint.text = ""

	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.02, 0.04, 0.78)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var won := winner == PLAYER
	var title := Label.new()
	title.text = "Victory" if won else "Defeat"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.98, 0.87, 0.45) if won else Color(0.85, 0.35, 0.35))
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "%s control Stellarium." % Balance.faction_name(winner)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	box.add_child(subtitle)

	var button := Button.new()
	button.text = "New Game"
	button.custom_minimum_size = Vector2(190, 42)
	button.pressed.connect(_on_new_game_pressed)
	box.add_child(button)


func _on_new_game_pressed() -> void:
	turn_manager.start_game()
	get_tree().reload_current_scene()
