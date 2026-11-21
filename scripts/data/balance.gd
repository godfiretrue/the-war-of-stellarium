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
## v0.4 added the anti-snowball block (home guard, conquest unrest, capital
## penalty, garrison doctrine); see AI_CONTEXT.md for the 20-game measurements.

enum Faction { NEUTRAL = -1, HUMANS = 0, ELVES = 1 }
## MOUNTAINS keeps its old value so nothing that stored the integer breaks.
enum Terrain { PLAINS = 0, MOUNTAINS = 1, FOREST = 2, COAST = 3 }

const PLAYER_FACTION := Faction.HUMANS

const FACTION_NAMES := {
	Faction.NEUTRAL: "Neutral",
	Faction.HUMANS: "Humans",
	Faction.ELVES: "Elves",
}

const TERRAIN_NAMES := {
	Terrain.PLAINS: "Plains",
	Terrain.MOUNTAINS: "Mountains",
	Terrain.FOREST: "Forest",
	Terrain.COAST: "Coast",
}

## Multiplier applied to a defending army's power, by terrain.
const TERRAIN_DEFENSE := {
	Terrain.PLAINS: 1.0,
	Terrain.MOUNTAINS: 1.35,
	Terrain.FOREST: 1.15,
	Terrain.COAST: 1.0,
}

## Faction resource produced by each terrain type. Humans draw Aether from the
## lowlands (plains, forest and coast); Elves mine Iron in the mountains.
## Forest and coast used to be classified as plains, so mapping them to Aether
## keeps Human resource income unchanged.
const TERRAIN_RESOURCE := {
	Terrain.PLAINS: "aether",
	Terrain.MOUNTAINS: "iron",
	Terrain.FOREST: "aether",
	Terrain.COAST: "aether",
}

const RESOURCE_NAMES := {
	"aether": "Aether",
	"iron": "Iron",
}

# --- Economy -------------------------------------------------------------

const STARTING_GOLD := 120
const STARTING_MANPOWER := 24

## Base gold and manpower produced by one province of each terrain, before the
## capital bonus and faction modifiers. The four entries average ~14.5 gold and
## ~5.5 manpower, close to the old flat 15/5 so the measured balance stays
## comparable. Coast still leads on gold, plains on manpower, and mountains sit
## in between with the best defence.
const TERRAIN_INCOME := {
	Terrain.PLAINS: {"gold": 13, "manpower": 10},
	Terrain.FOREST: {"gold": 12, "manpower": 6},
	Terrain.COAST: {"gold": 20, "manpower": 2},
	Terrain.MOUNTAINS: {"gold": 19, "manpower": 4},
}

const CAPITAL_GOLD_BONUS := 8
const CAPITAL_MANPOWER_BONUS := 2
const FACTION_RESOURCE_PER_TURN := 2

# --- Fortresses ----------------------------------------------------------

## A fortress is a role on top of the terrain, not a fifth biome. It adds a
## flat defence bonus and costs gold every turn, so holding one is a real
## strategic trade-off rather than a free upgrade.
const FORTRESS_DEFENSE_BONUS := 0.25
const FORTRESS_UPKEEP_GOLD := 4

## Per-faction economy modifiers.
## gold/manpower: income multipliers. recruit_cost: multiplier on recruitment price.
const FACTION_MODIFIERS := {
	Faction.HUMANS: {"gold": 1.0, "manpower": 1.0, "recruit_cost": 0.7},
	Faction.ELVES: {"gold": 1.15, "manpower": 1.15, "recruit_cost": 1.0},
}

# --- Capital loss penalty ------------------------------------------------

## Losing the capital hurts for a while instead of ending the game: income and
## recruitment stay possible from any owned city, just worse.
const CAPITAL_PENALTY_ENABLED := true
## Turns the penalty lasts after the capital is taken. Counted down at the end
## of every resolution step.
const CAPITAL_PENALTY_TURNS := 3
## Extra recruitment price while under the penalty (+30%).
const CAPITAL_RECRUIT_COST_PENALTY := 0.3
## Share of gold and manpower income lost while under the penalty (-25%).
const CAPITAL_INCOME_PENALTY := 0.25

# --- Conquest friction ---------------------------------------------------

## A freshly captured province stays unsettled: no income and no recruitment
## until it has been held this many resolution steps.
const CONQUEST_UNREST_ENABLED := true
const CONQUEST_UNREST_TURNS := 2

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

# --- Home guard ----------------------------------------------------------

## Defensive militia present in every owned province. It counts on defence
## only, never leaves, costs no upkeep and is lost with the province. Set the
## switch to false to disable the whole feature.
const HOME_GUARD_ENABLED := true
const HOME_GUARD_MAX := 2
const HOME_GUARD_CAPITAL_MAX := 4
## Militia raised per turn, up to the cap. A captured province starts at 0.
const HOME_GUARD_REGEN := 1
## Defence power per militia, before terrain. Two militia are worth roughly
## one swordsman on defence but add no attack and no upkeep.
const HOME_GUARD_DEFENSE := 4

# --- Garrison doctrine ---------------------------------------------------

## Troops the bot leaves behind when it marches; it sends the rest. Larger on
## the enemy border and in the capital, so a province is never stripped bare.
## Interiors only need a token force; the front needs enough to survive a raid.
const GARRISON_INTERIOR := 1
const GARRISON_BORDER := 2
const GARRISON_CAPITAL := 3

# --- Helpers -------------------------------------------------------------

static func faction_name(faction: int) -> String:
	return String(FACTION_NAMES.get(faction, "Neutral"))


static func terrain_name(terrain: int) -> String:
	return String(TERRAIN_NAMES.get(terrain, "Unknown"))


static func terrain_defense(terrain: int) -> float:
	return float(TERRAIN_DEFENSE.get(terrain, 1.0))


## Combined terrain and fortress multiplier for a defending army.
static func defense_multiplier(terrain: int, is_fortress: bool) -> float:
	var value := terrain_defense(terrain)
	if is_fortress:
		value += FORTRESS_DEFENSE_BONUS
	return value


## Base gold/manpower for one province of this terrain, before the capital
## bonus and faction modifiers. Returns a fresh dictionary, never the constant
## table, so callers can add the capital bonus without corrupting Balance.
static func terrain_income(terrain: int) -> Dictionary:
	var entry: Dictionary = TERRAIN_INCOME.get(terrain, {})
	return {
		"gold": int(entry.get("gold", 15)),
		"manpower": int(entry.get("manpower", 5)),
	}


static func terrain_resource(terrain: int) -> String:
	return String(TERRAIN_RESOURCE.get(terrain, ""))


static func resource_name(resource_key: String) -> String:
	return String(RESOURCE_NAMES.get(resource_key, resource_key))


static func modifier(faction: int, key: String, fallback: float) -> float:
	var table: Dictionary = FACTION_MODIFIERS.get(faction, {})
	return float(table.get(key, fallback))


static func is_player_faction(faction: int) -> bool:
	return faction == PLAYER_FACTION
