class_name BTAdvanceTask
extends BTAction
## Leaf task: march troops toward the enemy capital.

func _tick(_delta: float) -> int:
	var bot := get_agent()
	if bot == null or not bot.has_method("advance_phase"):
		return BT.FAILURE

	bot.advance_phase()
	return BT.SUCCESS
