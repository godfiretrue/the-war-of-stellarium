extends SceneTree
## Headless check for the battle forecast.
##
## The forecast must use the same formula as resolve(), stay inside its random
## band, and never mutate the province it reads.
##
##   godot --headless --path . --script res://scripts/tools/predict_check.gd


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var target := _defended_province()
	var attackers := {"human_swordsmen": 10, "human_crossbowmen": 4}
	var before := target.garrison.duplicate(true)
	var guard := target.home_guard
	var prediction := CombatResolver.predict(attackers, target, Balance.Faction.HUMANS)

	if target.garrison != before or target.home_guard != guard:
		_fail("predict mutated the target province")
		return
	if not bool(prediction["ok"]) or prediction["kind"] != "prediction":
		_fail("prediction has the wrong shape")
		return

	var expected := Dictionary(prediction["expected"])
	var best := Dictionary(prediction["best"])
	var worst := Dictionary(prediction["worst"])
	if float(expected["attacker_power"]) <= 0.0 or float(expected["defender_power"]) <= 0.0:
		_fail("expected powers are missing")
		return
	if int(best["attacker_losses"]) > int(expected["attacker_losses"]) \
			or int(expected["attacker_losses"]) > int(worst["attacker_losses"]):
		_fail("attacker loss band is not ordered")
		return
	if int(best["defender_losses"]) < int(expected["defender_losses"]) \
			or int(expected["defender_losses"]) < int(worst["defender_losses"]):
		_fail("defender loss band is not ordered")
		return

	# The forecast must contain what the real roll can produce. Rounding to
	# whole troops can make both corners land on the same integer, so compare
	# against the ordered band rather than assuming best <= worst.
	var low := mini(int(best["attacker_losses"]), int(worst["attacker_losses"]))
	var high := maxi(int(best["attacker_losses"]), int(worst["attacker_losses"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for _i in 100:
		var probe := target.duplicate(true) as ProvinceData
		var result := CombatResolver.resolve(attackers.duplicate(true), probe, Balance.Faction.HUMANS, rng)
		var losses := int(result["attacker_losses"])
		if losses < low or losses > high:
			_fail("resolved attacker losses %d outside band %d..%d" % [losses, low, high])
			return

	# A hidden garrison is stronger and costs more attacker lives.
	var plain := _defended_province()
	plain.ambush = false
	var plain_prediction := Dictionary(
		CombatResolver.predict(attackers, plain, Balance.Faction.HUMANS)["expected"]
	)
	if float(expected["defender_power"]) <= float(plain_prediction["defender_power"]):
		_fail("ambush did not raise predicted defence")
		return
	if int(expected["attacker_losses"]) <= int(plain_prediction["attacker_losses"]):
		_fail("ambush did not raise predicted attacker losses")
		return

	# Empty provinces are free captures, with no fight and no losses.
	var empty := ProvinceData.new()
	empty.id = "empty"
	empty.display_name = "Empty"
	var empty_prediction := Dictionary(
		CombatResolver.predict(attackers, empty, Balance.Faction.HUMANS)["expected"]
	)
	if not bool(CombatResolver.predict(attackers, empty, Balance.Faction.HUMANS)["undefended"]):
		_fail("empty province was not flagged undefended")
		return
	if not bool(empty_prediction["captured"]) or int(empty_prediction["attacker_losses"]) != 0:
		_fail("undefended province forecast is wrong")
		return

	# Role counters are deterministic and must be visible to the forecast.
	var swords := {"human_swordsmen": 10}
	var counter_power := CombatResolver.attack_power_of(swords, {"human_catapult": 10})
	var plain_power := CombatResolver.attack_power_of(swords, {"human_swordsmen": 10})
	if not is_equal_approx(counter_power, plain_power * (1.0 + Balance.COUNTER_BONUS)):
		_fail("infantry did not counter siege")
		return
	var pikes := {"human_pikemen": 10}
	var anti_power := CombatResolver.attack_power_of(pikes, {"elf_boar": 10})
	var anti_plain := CombatResolver.attack_power_of(pikes, {"human_swordsmen": 10})
	if not is_equal_approx(anti_power, anti_plain * (1.0 + Balance.ANTI_CAVALRY_BONUS)):
		_fail("anti-cavalry did not counter cavalry")
		return

	# Siege softens a fortress and hits harder on fortified ground.
	var fort := ProvinceData.new()
	fort.id = "fort"
	fort.display_name = "Fort"
	fort.terrain = Balance.Terrain.PLAINS
	fort.is_fortress = true
	fort.garrison = {"elf_riflemen": 4}
	var siege_units := {"human_catapult": 10}
	var siege_defence := float(Dictionary(
		CombatResolver.predict(siege_units, fort, Balance.Faction.HUMANS)["expected"]
	)["defender_power"])
	var normal_defence := float(Dictionary(
		CombatResolver.predict({"human_swordsmen": 10}, fort, Balance.Faction.HUMANS)["expected"]
	)["defender_power"])
	if siege_defence >= normal_defence:
		_fail("siege did not reduce fortress defence")
		return
	var open_power := CombatResolver.attack_power_of(siege_units)
	var fort_power := CombatResolver.attack_power_of(siege_units, {}, fort)
	if not is_equal_approx(fort_power, open_power * (1.0 + Balance.SIEGE_ATTACK_BONUS)):
		_fail("siege did not gain its fortified attack bonus")
		return

	print("[predict] OK: expected %d/%d losses, band %d..%d, 100 rolls inside band" % [
		int(expected["attacker_losses"]), int(expected["defender_losses"]),
		low, high,
	])
	quit(0)


func _defended_province() -> ProvinceData:
	var province := ProvinceData.new()
	province.id = "hold"
	province.display_name = "Hold"
	province.terrain = Balance.Terrain.MOUNTAINS
	province.owner_faction = Balance.Faction.ELVES
	province.is_fortress = true
	province.ambush = true
	province.garrison = {"elf_riflemen": 4, "elf_boar": 2}
	province.home_guard = 2
	return province


func _fail(message: String) -> void:
	printerr("[predict] FAIL: %s" % message)
	quit(1)
