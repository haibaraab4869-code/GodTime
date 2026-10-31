extends SceneTree

const Maps := preload("res://game/world_data.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.player.set_physics_process(false)
	for id in Maps.db().regions:
		world.load_map(id)
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		for i in range(Maps.region(id).rooms.size()): world.chapter_flags["seen_%s_%d" % [id, i]] = true
		world.camera.reset_smoothing()
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://world_" + id + ".png")
		world.atlas.reveal_all = true
		world.atlas.open_map()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://world_" + id + "_atlas.png")
		world.atlas.close_map()
		print("CAPTURE=", id)
	world.atlas.overview = true
	world.atlas.open_map()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://world_all_regions.png")
	print("WORLD=", ProjectSettings.globalize_path("user://world_all_regions.png"))
	world.atlas.close_map()
	world.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	quit()
