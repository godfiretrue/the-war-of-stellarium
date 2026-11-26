class_name FactionDoctrine
extends Resource
## Fixed AI personality for a faction. It only holds numbers; BotController owns
## the decisions. Profiles are cached because the values never change at runtime.

@export var attack_margin: float = 1.0
## Extra caution when attacking a fortress or Highlands ground.
@export var fortress_margin_bonus: float = 0.0
## Extra troops kept at home instead of joining an attack.
@export var attack_reserve_delta: int = 0
@export var ambush_cap: int = 1
## Preferred combat role among units close in price to the strongest affordable one.
@export var recruit_role_bias: String = ""
@export var recruit_tie_break_gold: float = 4.0


static var _profiles: Dictionary = {}


static func for_faction(faction: int) -> FactionDoctrine:
	if not _profiles.has(faction):
		var profile := FactionDoctrine.new()
		if faction == Balance.Faction.HUMANS:
			# Humans field cavalry and attack on fair odds.
			profile.attack_margin = 1.0
			profile.ambush_cap = 1
			profile.recruit_role_bias = Balance.ROLE_CAVALRY
		else:
			# Elves weigh fortified ground, field ranged units and ambush more.
			profile.attack_margin = 1.0
			profile.fortress_margin_bonus = 0.05
			profile.ambush_cap = 2
			profile.recruit_role_bias = Balance.ROLE_RANGED
		_profiles[faction] = profile
	return _profiles[faction]
