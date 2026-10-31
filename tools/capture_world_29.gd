extends SceneTree
## 29 区世界实机截图：世界入口 W01 → 中枢 W02 → 主题大区 W09 → 终局 W23。
## 不写存档：persist_progress = false。

const OUT := "res://docs/qa/runs/"
const Maps := preload("res://game/world_data.gd")

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + name
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " error=", err)

func run() -> void:
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.player.set_physics_process(false)
	world.hazards.set_physics_process(false)
	for actor in world.actors.get_children(): actor.set_physics_process(false)
	for id in ["W01", "W02", "W09", "W23"]:
		world.load_map(id)
		await process_frame
		world.player.set_physics_process(false)
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		# 把镜头挪到第一个机关所在处，截图里才看得到机关与遭遇战
		var device_at := Vector2.ZERO
		for item in Maps.interactions(id):
			if item.has("device"):
				device_at = item.at
				break
		var actors: Array = world.actors.get_children()
		if device_at != Vector2.ZERO:
			world.player.position = device_at + Vector2(-90, -20)
		elif not actors.is_empty():
			world.player.position = actors[0].position + Vector2(-120, 0)
		world.reset_view()
		for frame in range(6):
			await process_frame
		print("ACTORS ", id, " = ", actors.size())
		await shot("world29-%s.png" % id.to_lower())
	print("WORLD29 CAPTURES DONE zoom=", world.camera.zoom)
	quit(0)
