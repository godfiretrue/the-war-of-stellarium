class_name UnitType
extends Resource
## Definition of one recruitable unit type.
##
## Pure data: never references scene nodes. Instances are built by
## UnitCatalog from Balance.UNIT_DEFS, so this script has no self-reference.

@export var id: String = ""
@export var display_name: String = ""
@export var faction: int = Balance.Faction.NEUTRAL
@export var attack: int = 0
@export var defense: int = 0
@export var gold_cost: int = 0
@export var manpower_cost: int = 0
@export var upkeep: int = 0


## Recruitment price after the recruiter's faction modifier.
func costs_for(recruiter_faction: int) -> Dictionary:
	var multiplier: float = Balance.modifier(recruiter_faction, "recruit_cost", 1.0)
	var costs: Dictionary = {}
	costs["gold"] = int(ceil(gold_cost * multiplier))
	costs["manpower"] = int(ceil(manpower_cost * multiplier))
	return costs
