class_name BTAmbushTask
extends BTAction
## Leaf task: hide a small garrison when the front stops moving.
##
## Kept duck-typed (has_method) so this script does not reference
## BotController by class name — that would be a circular class dependency.

func _tick(_delta: float) -> int:
	var bot := get_agent()
	if bot == null or not bot.has_method("ambush_phase"):
		return BT.FAILURE

	bot.ambush_phase()
	return BT.SUCCESS
