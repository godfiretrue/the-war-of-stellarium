class_name CombatResolver
extends RefCounted
## Pure numeric combat: an attacking force versus one province's garrison.
##
## No nodes, no signals, no side effects beyond applying defender losses to the
## target province. GameState applies the rest of the result, which keeps the
## formula testable in isolation and identical for player and bot.


## Resolves one battle.
##
## attacking_units: unit_id -> count that left the origin province.
## target: the province being attacked (its garrison takes the losses).
## Returns a result dictionary; "attacker_survivors" holds the troops that
## would return home or occupy the province, decided by the caller.
static func resolve(
	attacking_units: Dictionary,
	target: ProvinceData,
	attacker_faction: int,
	rng: RandomNumberGenerator = null,
) -> Dictionary:
	var random := rng
	if random == null:
		random = RandomNumberGenerator.new()
		random.randomize()

	var attacker_total := troop_count(attacking_units)
	var defender_total := target.total_troops()

	if attacker_total <= 0:
		return _result(attacker_faction, target, 0, 0, 0, 0, {}, target.garrison.duplicate(true), false)

	# An undefended province is taken without a fight.
	if defender_total <= 0:
		return _result(attacker_faction, target, 0.0, 0.0, 0, 0, attacking_units.duplicate(true), {}, true)

	var attack_power := attack_power_of(attacking_units)
	attack_power *= random.randf_range(Balance.COMBAT_RANDOM_MIN, Balance.COMBAT_RANDOM_MAX)

	var defense_power := target.defense_power()
	defense_power *= random.randf_range(Balance.COMBAT_RANDOM_MIN, Balance.COMBAT_RANDOM_MAX)

	var total_power := attack_power + defense_power
	var ratio := 0.5
	if total_power > 0.0:
		ratio = attack_power / total_power

	var attacker_losses := int(ceil(float(attacker_total) * (1.0 - ratio) * Balance.ATTACKER_LOSS_FACTOR))
	var defender_losses := int(ceil(float(defender_total) * ratio * Balance.DEFENDER_LOSS_FACTOR))
	attacker_losses = clampi(attacker_losses, 0, attacker_total)
	defender_losses = clampi(defender_losses, 0, defender_total)

	target.remove_troops(defender_losses)

	var attacker_survivors: Dictionary = attacking_units.duplicate(true)
	apply_losses(attacker_survivors, attacker_losses)

	var captured := target.total_troops() == 0
	return _result(
		attacker_faction,
		target,
		attack_power,
		defense_power,
		attacker_losses,
		defender_losses,
		attacker_survivors,
		target.garrison.duplicate(true),
		captured,
	)


static func troop_count(units: Dictionary) -> int:
	var total := 0
	for unit_id: String in units.keys():
		total += maxi(int(units[unit_id]), 0)
	return total


static func attack_power_of(units: Dictionary) -> float:
	var power := 0.0
	for unit_id: String in units.keys():
		var count := int(units[unit_id])
		if count <= 0:
			continue
		var unit := UnitCatalog.get_unit(unit_id)
		if unit != null:
			power += float(unit.attack) * float(count)
	return power


## Spreads losses over the force, one trooper at a time, so no unit type is
## wiped out while another is untouched.
static func apply_losses(units: Dictionary, losses: int) -> void:
	var remaining: int = maxi(losses, 0)
	if remaining <= 0:
		return

	var unit_ids: Array = units.keys()
	while remaining > 0:
		var removed_any := false
		for unit_id: String in unit_ids:
			if remaining <= 0:
				break
			var count := int(units.get(unit_id, 0))
			if count <= 0:
				continue
			units[unit_id] = count - 1
			remaining -= 1
			removed_any = true
		if not removed_any:
			break

	for unit_id: String in unit_ids:
		if int(units.get(unit_id, 0)) <= 0:
			units.erase(unit_id)


static func _result(
	attacker_faction: int,
	target: ProvinceData,
	attack_power: float,
	defense_power: float,
	attacker_losses: int,
	defender_losses: int,
	attacker_survivors: Dictionary,
	defender_survivors: Dictionary,
	captured: bool,
) -> Dictionary:
	return {
		"kind": "battle",
		"ok": true,
		"province": target.id,
		"province_name": target.display_name,
		"terrain": target.terrain,
		"attacker_faction": attacker_faction,
		"defender_faction": target.owner_faction,
		"attacker_power": attack_power,
		"defender_power": defense_power,
		"attacker_losses": attacker_losses,
		"defender_losses": defender_losses,
		"attacker_survivors": attacker_survivors,
		"defender_survivors": defender_survivors,
		"captured": captured,
	}
