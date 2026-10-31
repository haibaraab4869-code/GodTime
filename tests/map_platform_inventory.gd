extends SceneTree
const Maps := preload("res://game/world_data.gd")
func _initialize() -> void:
	var total := 0
	var inventory := {}
	for id in Maps.db().regions:
		var model := Maps.model(id)
		var count: int = model.platforms.size()
		total += count
		inventory[id] = {"platforms": count, "collision_hash": str(model.collision.hash())}
	print("PLATFORM_TOTAL=", total, " W01=", inventory.W01.platforms)
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"total": total, "regions": inventory}, "\t"))
	quit()
