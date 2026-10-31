extends SceneTree

## Isolated map preview: --script res://tools/preview_world.gd -- --map=W12
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	var target := "W01"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="): target = arg.trim_prefix("--map=").to_upper()
	if not world.Maps.db().regions.has(target): target = "W01"
	world.load_map(target)
	DisplayServer.window_set_title("地图预览（不保存） · " + target)
