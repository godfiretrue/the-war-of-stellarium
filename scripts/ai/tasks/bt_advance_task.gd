class_name BTAdvanceTask
extends BTAction
## Leaf task: march troops toward the enemy capital.

func _tick(_delta: float) -> int:
	var agent := get_agent()
	if agent == null or not agent.has_method("advance_phase"):
		return BT.FAILURE

	agent.advance_phase()
	return BT.SUCCESS
