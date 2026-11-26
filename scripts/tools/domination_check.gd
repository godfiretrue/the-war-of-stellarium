extends SceneTree
## Headless check for city-based dynamic victory and the save v8 -> v9 migration.
##
##   godot --headless --path . --script res://scripts/tools/domination_check.gd
##
## The player's save is backed up and restored, so this is safe to run on a
## working machine.

const TEST_SEED := 13579
const BACKUP_PATH := "user://savegame.domination_check_backup.json"


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var game := get_root().get_node_or_null("Game") as GameState
	if game == null:
		_fail("Game autoload missing")
		return

	_backup_save()
	game.start_new_game(TEST_SEED)
	if game.map_state == null:
		_fail("map was not generated")
		return

	var cities := game.map_state.city_count_total()
	var needed := ceili(float(cities) * Balance.DOMINATION_SHARE)
	# A fresh game already gives each faction two anchor cities.
	var to_assign := maxi(
		needed - game.map_state.city_count(Balance.Faction.HUMANS), 0
	)
	var assigned := 0
	for province in game.map_state.provinces:
		if assigned >= to_assign:
			break
		if province.is_city and not province.is_owned_by(Balance.Faction.HUMANS):
			province.owner_faction = Balance.Faction.HUMANS
			assigned += 1

	if assigned != to_assign:
		_fail("could not assign %d provinces" % to_assign)
		return

	game.advance_domination_tracking()
	if int(game.domination_streak[Balance.Faction.HUMANS]) != 1:
		_fail("first domination step was not counted")
		return
	if game.domination_winner() != Balance.Faction.NEUTRAL:
		_fail("victory fired after one step")
		return

	game.advance_domination_tracking()
	if int(game.domination_streak[Balance.Faction.HUMANS]) != 2:
		_fail("second domination step was not counted")
		return
	if game.domination_winner() != Balance.Faction.NEUTRAL:
		_fail("victory fired after two steps")
		return

	game.advance_domination_tracking()
	if game.domination_winner() != Balance.Faction.HUMANS:
		_fail("victory did not fire after %d steps" % Balance.DOMINATION_STREAK)
		return

	# Dropping below the share clears the counter immediately.
	var first: ProvinceData = null
	for province in game.map_state.provinces:
		if province.is_city and province.owner_faction == Balance.Faction.HUMANS:
			first = province
			break
	if first == null:
		_fail("no human province to release")
		return
	first.owner_faction = Balance.Faction.NEUTRAL
	game.advance_domination_tracking()
	if int(game.domination_streak[Balance.Faction.HUMANS]) != 0:
		_fail("losing ground did not reset the streak")
		return

	# v8 round-trip: the streak survives a save and load.
	game.domination_streak[Balance.Faction.HUMANS] = 2
	if not SaveSystem.save_game(game, 4):
		_fail("could not write test save")
		return
	var result := SaveSystem.read_save()
	if not bool(result.get("ok", false)):
		_fail("could not read test save: %s" % str(result.get("reason", "")))
		return
	var data: Dictionary = result["data"]
	if int(data.get("version", 0)) != 9:
		_fail("expected save version 9")
		return
	var factions: Dictionary = data.get("factions", {})
	if int(Dictionary(factions.get("0", {}))["domination_streak"]) != 2:
		_fail("streak was not serialized")
		return
	SaveSystem.load_game(game)
	if int(game.domination_streak[Balance.Faction.HUMANS]) != 2:
		_fail("streak was not restored")
		return

	# v8 migration injects NORMAL difficulty and a zeroed city streak; v7
	# chains through it, and v6 worlds are still refused.
	var legacy := {
		"version": 8,
		"map_seed": TEST_SEED,
		"world_scale": 1.0,
		"turn_number": 3,
		"factions": {"0": {"gold": 10}, "1": {"gold": 10}},
		"provinces": [],
	}
	var migrated: Dictionary = SaveSystem._migrate(legacy)
	if int(migrated.get("version", 0)) != 9:
		_fail("v8 save was not migrated to v9")
		return
	if int(migrated.get("difficulty", -1)) != Balance.Difficulty.NORMAL:
		_fail("v8 save did not get NORMAL difficulty")
		return
	var old_factions: Dictionary = migrated.get("factions", {})
	for key in old_factions.keys():
		if int(Dictionary(old_factions[key]).get("domination_streak", -1)) != 0:
			_fail("v8 faction %s did not get a zeroed streak" % str(key))
			return
	legacy["version"] = 6
	if not SaveSystem._migrate(legacy).is_empty():
		_fail("v6 save should still be refused")
		return

	_restore_save()
	print("[domination] OK: city streak, victory, v9 round-trip and v8 migration")
	quit(0)


func _backup_save() -> void:
	if FileAccess.file_exists(SaveSystem.SAVE_PATH):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(SaveSystem.SAVE_PATH),
			ProjectSettings.globalize_path(BACKUP_PATH))


func _restore_save() -> void:
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.copy_absolute(
			ProjectSettings.globalize_path(BACKUP_PATH),
			ProjectSettings.globalize_path(SaveSystem.SAVE_PATH))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	else:
		SaveSystem.delete_save()


func _fail(message: String) -> void:
	_restore_save()
	printerr("[domination] FAIL: %s" % message)
	quit(1)
