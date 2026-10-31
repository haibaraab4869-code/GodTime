extends SceneTree
## 底色对齐验收截图：M01 标准房（近/过去两时代）+ M02 704 井口，
## 用于检查天空 vs 岩体 vs 平台 vs 角色的可读性。不写存档。

const Views := [
	{"name": "m01-present", "map": "M01", "at": Vector2(1328, 492), "past": false},
	{"name": "m01-past", "map": "M01", "at": Vector2(1328, 492), "past": true},
	{"name": "m02-mouth", "map": "M02", "at": Vector2(2776, 972), "past": false},
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.player.set_physics_process(false)
	world.set_physics_process(false)
	world.hazards.set_physics_process(false)
	for actor in world.actors.get_children():
		actor.set_physics_process(false)
	var suffix: String = "A" if "--b" not in OS.get_cmdline_user_args() else "B"
	for view in Views:
		world.load_map(view.map)
		world.past_era = view.past
		world._build_terrain(world._geometry(view.past))
		world.player.position = view.at
		world.player.velocity = Vector2.ZERO
		world.reset_view()
		for frame in range(24):
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://docs/qa/runs/sky-%s-%s.png" % [suffix, view.name]
		var err := root.get_texture().get_image().save_png(path)
		print("CAPTURE ", path, " error=", err)
	for node in world.find_children("*", "AudioStreamPlayer", true, false):
		node.stop()
		node.stream = null
	world.queue_free()
	for frame in range(8):
		await process_frame
	quit()
