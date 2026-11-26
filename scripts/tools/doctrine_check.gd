extends SceneTree
## Headless invariant check for the fixed faction AI profiles.

var _errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var humans := FactionDoctrine.for_faction(Balance.Faction.HUMANS)
	var elves := FactionDoctrine.for_faction(Balance.Faction.ELVES)

	if humans == null or elves == null:
		_errors.append("missing doctrine profile")
	else:
		if FactionDoctrine.for_faction(Balance.Faction.HUMANS) != humans:
			_errors.append("human profile is not cached")
		if FactionDoctrine.for_faction(Balance.Faction.ELVES) != elves:
			_errors.append("elf profile is not cached")
		var valid_roles := [
			Balance.ROLE_INFANTRY, Balance.ROLE_RANGED, Balance.ROLE_CAVALRY,
			Balance.ROLE_ANTI_CAVALRY, Balance.ROLE_ARMOUR, Balance.ROLE_SIEGE,
		]
		if not valid_roles.has(humans.recruit_role_bias):
			_errors.append("human recruit bias is not a role")
		if not valid_roles.has(elves.recruit_role_bias):
			_errors.append("elf recruit bias is not a role")
		if humans.attack_margin <= 0.0 or elves.attack_margin <= 0.0:
			_errors.append("attack margins must be positive")
		if humans.ambush_cap < 1 or elves.ambush_cap < 1:
			_errors.append("ambush caps must allow at least one ambush")
		if elves.ambush_cap <= humans.ambush_cap:
			_errors.append("elves should ambush more often than humans")
		if humans.attack_reserve_delta < elves.attack_reserve_delta:
			_errors.append("humans should hold at least as many troops back as elves")

	var bot := BotController.new()
	bot.bot_faction = Balance.Faction.HUMANS
	if bot.doctrine() != humans:
		_errors.append("BotController does not use the cached human doctrine")
	bot.bot_faction = Balance.Faction.ELVES
	if bot.doctrine() != elves:
		_errors.append("BotController does not use the cached elf doctrine")
	bot.free()

	if _errors.is_empty():
		print("[doctrine] OK: cached profiles, distinct roles, ambush and reserve invariants")
	else:
		for error in _errors:
			push_error("[doctrine] " + error)
	quit(0 if _errors.is_empty() else 1)
