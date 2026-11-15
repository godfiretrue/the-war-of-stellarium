class_name BTRecruitTask
extends BTAction
## Leaf task: recruit units through the bot's own rules.
##
## Kept duck-typed (has_method) so this script does not reference
## BotController by class name — that would be a circular class dependency.

func _tick(_delta: float) -> int:
	var bot := get_agent()
	if bot == null or not bot.has_method("recruit_phase"):
		return BT.FAILURE

	bot.recruit_phase()
	return BT.SUCCESS
