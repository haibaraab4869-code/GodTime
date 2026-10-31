extends SceneTree
const Maps := preload("res://game/world_data.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.player.set_physics_process(false)
	world.chapter_flags.ability_VC = true
	for id in ["M02", "M07", "M06", "M13"]:
		Input.action_release("view_wide")
		Input.action_release("view_close")
		world.load_map(id)
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		world.boundary_cooldown = 0
		world.framing.lock_left = 0
		world.player.respawn_view_lock = 0
		if id == "M07":
			var h: Dictionary = Maps.region(id).structure.pogo_halls[0]
			world.player.position = Vector2(h.left, h.floor - 20)
			Input.action_press("view_wide")
		elif id == "M06":
			var hazard: Dictionary = world.hazards.records.filter(func(h): return h.kind == "buried")[0]
			world.player.position = hazard.box.position - Vector2(40, 28)
			Input.action_press("view_close")
		elif id == "M13":
			var s: Dictionary = Maps.model(id).stairs[-1]
			world.player.position = Vector2(float(s.center), float(s.top) + 120)
			Input.action_press("view_wide")
		else: world.player.position = Maps.anchor(id, "world_ability")
		world.camera.reset_smoothing()
		for frame in range(50): await physics_frame
		if id == "M06": world.hazards.elapsed = 1.3
		world.hazards.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://reconstruction_" + id + ".png")
		print("RECONSTRUCTION_CAPTURE=", id, " mode=", world.view_mode)
	Input.action_release("view_wide")
	Input.action_release("view_close")
	world.queue_free()
	await process_frame
	quit()
