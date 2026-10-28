class_name BTAttackTask
extends BTAction
## Leaf task: run the bot's attack rule.
##
## Returns FAILURE when no battle was fought, which lets the enclosing
## selector fall through to the advance task.

func _tick(_delta: float) -> int:
	var agent := get_agent()
	if agent == null or not agent.has_method("attack_phase"):
		return BT.FAILURE

	var battles: int = agent.attack_phase()
	return BT.SUCCESS if battles > 0 else BT.FAILURE
