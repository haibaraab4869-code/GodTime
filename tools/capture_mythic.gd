extends SceneTree
const Maps := preload("res://game/world_data.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.player.set_physics_process(false)
	for id in ["M01", "M02", "M03", "M04", "M05", "M07", "M14", "M43"]:
		world.chapter_flags["mythic_" + id] = 1
		world.load_map(id)
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		var environment = world.environment
		if environment.spec.family == "echo":
			for index in environment.spec.echo_order: environment.operate(int(index))
		else:
			for index in range(3 if environment.spec.family == "triad" else 1):
				world.player.position = environment.control_position(index)
				for turn in range(int(environment.spec.targets[index])): environment.operate(index)
		world.player.position = environment.chamber.get_center()
		world.camera.reset_smoothing()
		for frame in range(150): await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://mythic_" + id + ".png")
		print("MECHANIC_CAPTURE=", id)
	world.queue_free()
	await process_frame
	quit()
