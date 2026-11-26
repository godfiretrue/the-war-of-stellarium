class_name CombatResolver
extends RefCounted
## Pure numeric combat: an attacking force versus one province's garrison.
##
## No nodes, no signals, no side effects beyond applying defender losses to the
## target province. GameState applies the rest of the result, which keeps the
## formula testable in isolation and identical for player and bot.
##
## predict() shares the same calculation but changes nothing, so the HUD can
## show a forecast before the order is queued.


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

	var attacker_factor := random.randf_range(Balance.COMBAT_RANDOM_MIN, Balance.COMBAT_RANDOM_MAX)
	var defender_factor := random.randf_range(Balance.COMBAT_RANDOM_MIN, Balance.COMBAT_RANDOM_MAX)
	var calc := _calculate(attacking_units, target, attacker_factor, defender_factor)

	var militia_losses := int(calc["militia_losses"])
	target.home_guard = int(calc["militia"]) - militia_losses
	target.remove_troops(int(calc["defender_losses"]) - militia_losses)

	var result := _result(
		attacker_faction,
		target,
		float(calc["attacker_power"]),
		float(calc["defender_power"]),
		int(calc["attacker_losses"]),
		int(calc["defender_losses"]),
		Dictionary(calc["attacker_survivors"]),
		target.garrison.duplicate(true),
		bool(calc["captured"]),
	)
	result["home_guard_losses"] = militia_losses
	return result


## Forecast of the same battle, with no RNG and no mutation of target.
##
## The expected point uses neutral factors (1.0/1.0). "best" is the attacker's
## favourable corner (1.1 attack, 0.9 defence) and "worst" the reverse, matching
## the random band resolve() draws from. Each point has the same numeric keys as
## a battle result, so callers do not need a second formula.
static func predict(
	attacking_units: Dictionary,
	target: ProvinceData,
	attacker_faction: int,
) -> Dictionary:
	return {
		"kind": "prediction",
		"ok": true,
		"province": target.id,
		"province_name": target.display_name,
		"terrain": target.terrain,
		"attacker_faction": attacker_faction,
		"defender_faction": target.owner_faction,
		"ambush": target.ambush,
		"undefended": target.defence_troops() <= 0 and troop_count(attacking_units) > 0,
		"expected": _prediction_point(
			attacking_units, target, 1.0, 1.0
		),
		"best": _prediction_point(
			attacking_units, target, Balance.COMBAT_RANDOM_MAX, Balance.COMBAT_RANDOM_MIN
		),
		"worst": _prediction_point(
			attacking_units, target, Balance.COMBAT_RANDOM_MIN, Balance.COMBAT_RANDOM_MAX
		),
	}


static func troop_count(units: Dictionary) -> int:
	var total := 0
	for unit_id: String in units.keys():
		total += maxi(int(units[unit_id]), 0)
	return total


## Attacking power, including role advantages against the defender.
## The optional defender/target context is what keeps counters and siege
## identical in resolve(), predict() and the field battles in GameState.
static func attack_power_of(
	units: Dictionary,
	defender_garrison: Dictionary = {},
	target: ProvinceData = null,
) -> float:
	var defender_total := troop_count(defender_garrison)
	var fortified := target != null and (
		target.is_fortress or target.terrain == Balance.Terrain.HIGHLANDS
	)
	var power := 0.0
	for unit_id: String in units.keys():
		var count := int(units[unit_id])
		if count <= 0:
			continue
		var unit := UnitCatalog.get_unit(unit_id)
		if unit == null:
			continue
		var contribution := float(unit.attack) * float(count)
		if defender_total > 0 and not unit.role.is_empty():
			var countered := Balance.counter_target(unit.role)
			if not countered.is_empty():
				var share := float(role_troops(defender_garrison, countered)) / float(defender_total)
				contribution *= 1.0 + Balance.COUNTER_BONUS * share
			if unit.role == Balance.ROLE_ANTI_CAVALRY:
				var cavalry_share := float(role_troops(defender_garrison, Balance.ROLE_CAVALRY))
				cavalry_share /= float(defender_total)
				contribution *= 1.0 + Balance.ANTI_CAVALRY_BONUS * cavalry_share
		if fortified and unit.role == Balance.ROLE_SIEGE:
			contribution *= 1.0 + Balance.SIEGE_ATTACK_BONUS
		power += contribution
	return power


## Troops of one combat role in a garrison, used by counters and sieges.
static func role_troops(units: Dictionary, role: String) -> int:
	var total := 0
	for unit_id: String in units.keys():
		if Balance.unit_role(unit_id) == role:
			total += maxi(int(units[unit_id]), 0)
	return total


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


# --- Shared calculation ---------------------------------------------------

## The one formula used by both resolve() and predict(). It reads target but
## never writes it; defender survivors are computed on a copy using the same
## order as ProvinceData.remove_troops().
static func _calculate(
	attacking_units: Dictionary,
	target: ProvinceData,
	attacker_factor: float,
	defender_factor: float,
) -> Dictionary:
	var attacker_total := troop_count(attacking_units)
	var defender_total := target.defence_troops()
	var militia := maxi(target.home_guard, 0) if Balance.HOME_GUARD_ENABLED else 0
	var defender_survivors := target.garrison.duplicate(true)

	if attacker_total <= 0:
		return {
			"attacker_power": 0.0,
			"defender_power": 0.0,
			"ratio": 0.0,
			"attacker_losses": 0,
			"defender_losses": 0,
			"militia": militia,
			"militia_losses": 0,
			"home_guard_after": militia,
			"attacker_survivors": {},
			"defender_survivors": defender_survivors,
			"captured": false,
		}

	# An undefended province is taken without a fight.
	if defender_total <= 0:
		return {
			"attacker_power": 0.0,
			"defender_power": 0.0,
			"ratio": 1.0,
			"attacker_losses": 0,
			"defender_losses": 0,
			"militia": militia,
			"militia_losses": 0,
			"home_guard_after": militia,
			"attacker_survivors": attacking_units.duplicate(true),
			"defender_survivors": {},
			"captured": true,
		}

	var siege_troops := role_troops(attacking_units, Balance.ROLE_SIEGE)
	var defense_multiplier := Balance.defense_multiplier_with_siege(
		target.terrain, target.is_fortress,
		float(siege_troops) / float(attacker_total)
	)
	var attack_power := attack_power_of(attacking_units, target.garrison, target) * attacker_factor
	var defense_power := target.raw_defense_power() * defense_multiplier * defender_factor
	# An ambushing garrison strikes from cover: stronger defence and a heavier
	# price for the army that walked into it.
	var ambushed := target.ambush
	if ambushed:
		defense_power *= Balance.AMBUSH_DEFENSE_MULTIPLIER

	var total_power := attack_power + defense_power
	var ratio := 0.5
	if total_power > 0.0:
		ratio = attack_power / total_power

	var attacker_losses := int(ceil(float(attacker_total) * (1.0 - ratio) * Balance.ATTACKER_LOSS_FACTOR))
	var defender_losses := int(ceil(float(defender_total) * ratio * Balance.DEFENDER_LOSS_FACTOR))
	if ambushed:
		attacker_losses = int(ceil(float(attacker_losses) * Balance.AMBUSH_ATTACKER_LOSS_MULTIPLIER))
	attacker_losses = clampi(attacker_losses, 0, attacker_total)
	defender_losses = clampi(defender_losses, 0, defender_total)

	# The levy takes the first losses, then the professional garrison. Militia
	# losses leave the province, they never transfer to the attacker.
	var militia_losses := mini(militia, defender_losses)
	var home_guard_after := militia - militia_losses
	defender_survivors = _apply_defender_losses(defender_survivors, defender_losses - militia_losses)

	var attacker_survivors := attacking_units.duplicate(true)
	apply_losses(attacker_survivors, attacker_losses)

	return {
		"attacker_power": attack_power,
		"defender_power": defense_power,
		"ratio": ratio,
		"attacker_losses": attacker_losses,
		"defender_losses": defender_losses,
		"militia": militia,
		"militia_losses": militia_losses,
		"home_guard_after": home_guard_after,
		"attacker_survivors": attacker_survivors,
		"defender_survivors": defender_survivors,
		"captured": troop_count(defender_survivors) == 0 and home_guard_after == 0,
	}


## Mirrors ProvinceData.remove_troops() without touching the real garrison.
static func _apply_defender_losses(garrison: Dictionary, losses: int) -> Dictionary:
	var survivors := garrison.duplicate(true)
	var remaining := maxi(losses, 0)
	for unit_id: String in survivors.keys():
		if remaining <= 0:
			break
		var count := int(survivors[unit_id])
		var taken := mini(count, remaining)
		var left := count - taken
		if left <= 0:
			survivors.erase(unit_id)
		else:
			survivors[unit_id] = left
		remaining -= taken
	return survivors


static func _prediction_point(
	attacking_units: Dictionary,
	target: ProvinceData,
	attacker_factor: float,
	defender_factor: float,
) -> Dictionary:
	var calc := _calculate(attacking_units, target, attacker_factor, defender_factor)
	return {
		"attacker_power": float(calc["attacker_power"]),
		"defender_power": float(calc["defender_power"]),
		"ratio": float(calc["ratio"]),
		"attacker_losses": int(calc["attacker_losses"]),
		"defender_losses": int(calc["defender_losses"]),
		"home_guard_losses": int(calc["militia_losses"]),
		"attacker_survivors": Dictionary(calc["attacker_survivors"]),
		"defender_survivors": Dictionary(calc["defender_survivors"]),
		"defender_home_guard": int(calc["home_guard_after"]),
		"captured": bool(calc["captured"]),
	}


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
		"defender_home_guard": target.home_guard,
		"home_guard_losses": 0,
		"ambush": target.ambush,
		"captured": captured,
	}
