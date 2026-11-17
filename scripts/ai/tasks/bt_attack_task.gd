class_name BTAttackTask
extends BTAction
## Leaf task: run the bot's attack rule.
##
## Always succeeds: attacks and advances are independent steps now, so a turn
## with no available battle must not stop the tree before the advance task.
func _tick(_delta: float) -> int:
	var bot := get_agent()
	if bot == null or not bot.has_method("attack_phase"):
		return BT.FAILURE

	bot.attack_phase()
	return BT.SUCCESS
