class_name SaveSystem
extends RefCounted
## JSON save/load with a version field and atomic writes.
##
## Saves live in user:// (never .tres, per project rules). The write goes to a
## temporary file first and is then renamed over the real save, so a crash
## mid-write cannot corrupt an existing game.

const SAVE_PATH := "user://savegame.json"
const VERSION := 1


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


static func save_game(game: GameState, turn_number: int) -> bool:
	if game == null or game.map_state == null:
		return false

	var data := {
		"version": VERSION,
		"turn_number": turn_number,
		"factions": _serialize_factions(game),
		"provinces": _serialize_provinces(game.map_state),
	}

	var json := JSON.stringify(data, "\t")
	var tmp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot open %s for writing" % tmp_path)
		return false

	file.store_string(json)
	file.flush()
	file.close()

	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp_path),
		ProjectSettings.globalize_path(SAVE_PATH),
	)
	if error != OK:
		push_error("SaveSystem: rename failed with error %d" % error)
		return false

	return true


## Loads a save into GameState. Returns {ok, reason, turn}.
static func load_game(game: GameState) -> Dictionary:
	if not has_save():
		return {"ok": false, "reason": "no save file"}
	if game == null:
		return {"ok": false, "reason": "game state missing"}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "cannot open save file"}

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "save file is not valid JSON"}

	var data := _migrate(parsed)
	if data.is_empty():
		return {"ok": false, "reason": "unsupported save version"}

	game.start_new_game()
	_apply_factions(game, data.get("factions", {}))
	_apply_provinces(game, data.get("provinces", []))
	game.state_changed.emit()

	return {"ok": true, "turn": int(data.get("turn_number", 1))}


## Brings older saves up to the current version. Empty dictionary means the
## file is from the future or unknown and must not be loaded.
static func _migrate(raw: Dictionary) -> Dictionary:
	var version := int(raw.get("version", 0))
	if version <= 0 or version > VERSION:
		return {}

	var data := raw
	# Version 1 is current. Future steps look like:
	# if version < 2:
	#     ... transform data ...
	#     data["version"] = 2
	return data


static func _serialize_factions(game: GameState) -> Dictionary:
	var factions := {}
	for faction: int in game.factions():
		factions[str(faction)] = {
			"gold": game.get_gold(faction),
			"manpower": game.get_manpower(faction),
			"resources": game.faction_resources.get(faction, {}).duplicate(),
		}
	return factions


static func _serialize_provinces(map_state: MapState) -> Array:
	var provinces: Array = []
	for province in map_state.provinces:
		provinces.append({
			"id": province.id,
			"owner": province.owner_faction,
			"garrison": province.garrison.duplicate(),
		})
	return provinces


static func _apply_factions(game: GameState, factions: Dictionary) -> void:
	for key: String in factions.keys():
		var faction := int(key)
		var entry: Dictionary = factions[key]
		game.gold[faction] = int(entry.get("gold", 0))
		game.manpower[faction] = int(entry.get("manpower", 0))

		var stock := {"aether": 0, "iron": 0}
		var saved_resources: Dictionary = entry.get("resources", {})
		for resource_key: String in saved_resources.keys():
			stock[resource_key] = int(saved_resources[resource_key])
		game.faction_resources[faction] = stock


static func _apply_provinces(game: GameState, provinces: Array) -> void:
	for raw_entry in provinces:
		var entry: Dictionary = raw_entry
		var province := game.map_state.get_province(String(entry.get("id", "")))
		if province == null:
			continue

		# JSON numbers come back as floats; int() keeps the model integer-based.
		province.owner_faction = int(entry.get("owner", Balance.Faction.NEUTRAL))
		province.garrison.clear()

		var garrison: Dictionary = entry.get("garrison", {})
		for unit_id: String in garrison.keys():
			province.add_units(unit_id, int(garrison[unit_id]))
