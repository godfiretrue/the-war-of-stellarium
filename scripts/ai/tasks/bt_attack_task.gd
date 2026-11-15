class_name BTAttackTask
extends BTAction
## Leaf task: run the bot's attack rule.
##
## Returns FAILURE when no battle was fought, which lets the enclosing
## selector fall through to the advance task.

func _tick(_delta: float) -> int:
	var bot := get_agent()
	if bot == null or not bot.has_method("attack_phase"):
		return BT.FAILURE

	var battles: int = bot.attack_phase()
	return BT.SUCCESS if battles > 0 else BT.FAILURE
