extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.load_map("M02")
	world.player.set_physics_process(false)
	world.set_physics_process(false)
	for actor in world.actors.get_children(): actor.set_physics_process(false)
	for view in [{"name": "mouth", "at": Vector2(2776, 972)}, {"name": "inside", "at": Vector2(2728, 1336)}]:
		world.player.position = view.at
		world.player.velocity = Vector2.ZERO
		world.reset_view()
		for frame in range(30): await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://docs/qa/runs/m02-ch1-" + view.name + ".png"
		var error := root.get_texture().get_image().save_png(path)
		print("CAPTURE ", path, " error=", error, " zoom=", world.camera.zoom, " center=", world.camera.get_screen_center_position())
		if error != OK:
			quit(1)
			return
	for node in world.find_children("*", "AudioStreamPlayer", true, false):
		node.stop()
		node.stream = null
	world.queue_free()
	for frame in range(8): await process_frame
	quit()
