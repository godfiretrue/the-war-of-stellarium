class_name Balance
extends RefCounted
## Central tuning table for the prototype.
##
## Every gameplay number lives here so a balance pass touches a single file.
## Nothing in this class has side effects; callers read constants and helpers.
##
## Tuning log: v0.3 raised province income and cut unit costs so armies can
## grow past one or two regiments, and lowered COMBAT_LOSS_FACTOR so battles
## leave survivors instead of wiping both sides.

enum Faction { NEUTRAL = -1, HUMANS = 0, ELVES = 1 }
enum Terrain { PLAINS = 0, MOUNTAINS = 1 }

const PLAYER_FACTION := Faction.HUMANS

const FACTION_NAMES := {
	Faction.NEUTRAL: "Neutral",
	Faction.HUMANS: "Humans",
	Faction.ELVES: "Elves",
}

const TERRAIN_NAMES := {
	Terrain.PLAINS: "Plains",
	Terrain.MOUNTAINS: "Mountains",
}

## Multiplier applied to a defending army's power, by terrain.
const TERRAIN_DEFENSE := {
	Terrain.PLAINS: 1.0,
	Terrain.MOUNTAINS: 1.25,
}

## Faction resource produced by each terrain type (Humans mine Aether on
## Plains, Elves mine Iron in Mountains).
const TERRAIN_RESOURCE := {
	Terrain.PLAINS: "aether",
	Terrain.MOUNTAINS: "iron",
}

const RESOURCE_NAMES := {
	"aether": "Aether",
	"iron": "Iron",
}

# --- Economy -------------------------------------------------------------

const STARTING_GOLD := 120
const STARTING_MANPOWER := 24

const PROVINCE_GOLD_INCOME := 15
const PROVINCE_MANPOWER_INCOME := 5
const CAPITAL_GOLD_BONUS := 8
const CAPITAL_MANPOWER_BONUS := 2
const FACTION_RESOURCE_PER_TURN := 2

## Per-faction economy modifiers.
## gold/manpower: income multipliers. recruit_cost: multiplier on recruitment price.
const FACTION_MODIFIERS := {
	Faction.HUMANS: {"gold": 1.0, "manpower": 1.0, "recruit_cost": 0.7},
	Faction.ELVES: {"gold": 1.15, "manpower": 1.15, "recruit_cost": 1.0},
}

# --- Combat --------------------------------------------------------------

## Casualties as a share of the enemy's power ratio. The defender pays more
## per loss than the attacker, so a clearly stronger attacker can break a
## garrison instead of chipping one trooper per round.
const ATTACKER_LOSS_FACTOR := 0.7
const DEFENDER_LOSS_FACTOR := 1.0
const COMBAT_RANDOM_MIN := 0.9
const COMBAT_RANDOM_MAX := 1.1

# --- Upkeep --------------------------------------------------------------

const UPKEEP_EXPONENT := 1.2
const UPKEEP_COST_DIVISOR := 15.0

# --- Units ---------------------------------------------------------------

const UNIT_DEFS := {
	"human_swordsmen": {
		"display_name": "Swordsmen",
		"faction": Faction.HUMANS,
		"attack": 5,
		"defense": 5,
		"gold_cost": 24,
		"manpower_cost": 5,
		"upkeep": 2,
	},
	"human_crossbowmen": {
		"display_name": "Crossbowmen",
		"faction": Faction.HUMANS,
		"attack": 7,
		"defense": 3,
		"gold_cost": 30,
		"manpower_cost": 6,
		"upkeep": 3,
	},
	"elf_boar": {
		"display_name": "Mechanical Boar",
		"faction": Faction.ELVES,
		"attack": 6,
		"defense": 7,
		"gold_cost": 30,
		"manpower_cost": 6,
		"upkeep": 3,
	},
	"elf_riflemen": {
		"display_name": "Riflemen",
		"faction": Faction.ELVES,
		"attack": 8,
		"defense": 4,
		"gold_cost": 36,
		"manpower_cost": 8,
		"upkeep": 4,
	},
}

# --- Starting armies -----------------------------------------------------

const CAPITAL_STARTING_TROOPS := 5
const SECOND_PROVINCE_STARTING_TROOPS := 2

## unit id used for each faction's starting garrison
const STARTING_UNIT := {
	Faction.HUMANS: "human_swordsmen",
	Faction.ELVES: "elf_boar",
}

# --- Helpers -------------------------------------------------------------

static func faction_name(faction: int) -> String:
	return String(FACTION_NAMES.get(faction, "Neutral"))


static func terrain_name(terrain: int) -> String:
	return String(TERRAIN_NAMES.get(terrain, "Unknown"))


static func terrain_defense(terrain: int) -> float:
	return float(TERRAIN_DEFENSE.get(terrain, 1.0))


static func terrain_resource(terrain: int) -> String:
	return String(TERRAIN_RESOURCE.get(terrain, ""))


static func resource_name(resource_key: String) -> String:
	return String(RESOURCE_NAMES.get(resource_key, resource_key))


static func modifier(faction: int, key: String, fallback: float) -> float:
	var table: Dictionary = FACTION_MODIFIERS.get(faction, {})
	return float(table.get(key, fallback))


static func is_player_faction(faction: int) -> bool:
	return faction == PLAYER_FACTION
