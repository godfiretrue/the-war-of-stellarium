class_name BTRecruitTask
extends BTAction
## Leaf task: recruit units through the bot's own rules.
##
## Kept duck-typed (has_method) so this script does not reference
## BotController by class name — that would be a circular class dependency.

func _tick(_delta: float) -> int:
	var agent := get_agent()
	if agent == null or not agent.has_method("recruit_phase"):
		return BT.FAILURE

	agent.recruit_phase()
	return BT.SUCCESS
