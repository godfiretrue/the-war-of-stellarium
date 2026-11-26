class_name MapFactory
extends RefCounted
## Builds the campaign map.
##
## The continent is generated procedurally by WorldGenerator from a seed; only
## a few anchor provinces (capitals, fortresses) are guaranteed. Province ids
## of generated provinces depend on the seed, so saves store the seed and
## rebuild the same map before applying ownership and garrisons.

## The campaign is authored on the 2x continent; 1.0 is kept for the
## reference-size balance runs and for old saves.
const DEFAULT_WORLD_SCALE := 2.0

## Pass a negative seed for a fresh random world.
static func create_default_map(map_seed: int = -1, world_scale: float = DEFAULT_WORLD_SCALE) -> MapState:
	var state := generate_map_data(map_seed, world_scale)
	if state == null:
		return MapState.new()
	return finalize_map(state)


## Pure world generation, safe to run on a worker thread: it only builds data
## resources and never touches the scene tree. Call finalize_map() afterwards on
## the main thread.
static func generate_map_data(map_seed: int = -1, world_scale: float = DEFAULT_WORLD_SCALE) -> MapState:
	var world_seed := map_seed
	if world_seed < 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		world_seed = rng.randi() & 0x7fffffff

	var generator := WorldGenerator.new()
	var state := generator.build(world_seed, world_scale)
	if state == null:
		push_error("MapFactory: world generation failed for seed %d" % world_seed)
		return null
	return state


## Main-thread half of map creation: starting armies, garrisons and validation.
## Keeping this separate lets the expensive generation run in a Thread.
static func finalize_map(state: MapState) -> MapState:
	if state == null:
		return MapState.new()

	_apply_starting_armies(state)

	for problem: String in state.validate():
		push_error("MapFactory: %s" % problem)

	return state


static func _apply_starting_armies(state: MapState) -> void:
	for faction: int in [Balance.Faction.HUMANS, Balance.Faction.ELVES]:
		var unit_id := String(Balance.STARTING_UNIT[faction])

		var capital := state.capital_of(faction)
		if capital != null:
			capital.add_units(unit_id, Balance.CAPITAL_STARTING_TROOPS)

		# Second garrison must reach a city: wildlands are corridors with no
		# permanent garrison and cannot recruit, so they are never a fallback.
		for province in state.provinces:
			if province.is_owned_by(faction) and not province.is_capital and province.is_city:
				province.add_units(unit_id, Balance.SECOND_PROVINCE_STARTING_TROOPS)
				break

	# Only cities and fortresses raise militia. Neutral fortresses keep the
	# initial levy; every other neutral province, including wildlands, stays at 0.
	for province in state.provinces:
		if not province.is_neutral() and not province.is_wildland():
			province.home_guard = province.home_guard_cap()
		elif province.is_fortress:
			province.home_guard = Balance.HOME_GUARD_MAX
