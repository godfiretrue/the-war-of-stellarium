extends SceneTree
## Headless invariant check for the authored bot behaviour-tree resource.

const TREE_PATH := "res://data/ai/elf_turn_bt.tres"

var _errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tree := load(TREE_PATH) as BehaviorTree
	if tree == null:
		_errors.append("behaviour tree resource is missing or not a BehaviorTree")
		_finish()
		return

	var root := tree.root_task
	if root == null:
		_errors.append("tree has no root task")
		_finish()
		return
	if not root is BTSequence:
		_errors.append("root is not a BTSequence")
		_finish()
		return
	if root.custom_name != "Elf turn":
		_errors.append("root name is wrong: %s" % root.custom_name)
	if root.children.size() != 3:
		_errors.append("root should have 3 children, has %d" % root.children.size())
		_finish()
		return

	_expect_script(root.children[0], "bt_recruit_task")
	_expect_script(root.children[1], "bt_ambush_task")

	var military: BTTask = root.children[2]
	if not military is BTSequence:
		_errors.append("third child is not the Attack/advance sequence")
		_finish()
		return
	if military.custom_name != "Attack, then advance":
		_errors.append("military sequence name is wrong")
	if military.children.size() != 2:
		_errors.append("military sequence should have 2 children")
		_finish()
		return
	_expect_script(military.children[0], "bt_attack_task")
	_expect_script(military.children[1], "bt_advance_task")

	# The bot must run the authored resource, not a freshly built copy.
	var bot := BotController.new()
	if bot.get_behavior_tree() != tree:
		_errors.append("BotController does not load the authored .tres")
	bot.free()

	_finish()


func _expect_script(task: BTTask, stem: String) -> void:
	var script: Script = task.get_script() as Script
	var path := script.resource_path if script != null else "<none>"
	if not path.ends_with("/%s.gd" % stem):
		_errors.append("expected %s.gd on task, got %s" % [stem, path])


func _finish() -> void:
	if _errors.is_empty():
		print("[bot_tree] OK: authored resource matches the canonical tree")
	else:
		for error in _errors:
			push_error("[bot_tree] " + error)
	quit(0 if _errors.is_empty() else 1)
