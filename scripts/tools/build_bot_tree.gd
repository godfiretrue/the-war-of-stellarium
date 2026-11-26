extends SceneTree
## Regenerates the bot's LimboAI BehaviourTree resource from the one canonical
## tree definition (BotController.build_behavior_tree()).
##
## Run from the project folder:
##   godot --headless --path . --script res://scripts/tools/build_bot_tree.gd
##
## Keeping this generator means the .tres never has to be hand-edited: change
## build_behavior_tree(), rerun this tool, and the resource is regenerated.

const OUTPUT_PATH := "res://data/ai/elf_turn_bt.tres"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bot := BotController.new()
	var tree: BehaviorTree = bot.build_behavior_tree()
	bot.free()

	var error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://data/ai")
	)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("[bot_tree] cannot create data/ai: %d" % error)
		quit(1)
		return

	error = ResourceSaver.save(tree, OUTPUT_PATH)
	if error != OK:
		push_error("[bot_tree] cannot save %s: %d" % [OUTPUT_PATH, error])
		quit(1)
		return

	var loaded := load(OUTPUT_PATH) as BehaviorTree
	if loaded == null or loaded.root_task == null:
		push_error("[bot_tree] saved resource failed to load back")
		quit(1)
		return

	print("[bot_tree] wrote %s" % OUTPUT_PATH)
	quit(0)
