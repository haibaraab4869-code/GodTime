extends SceneTree
const Maps := preload("res://game/world_data.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.player.set_physics_process(false)
	world.set_physics_process(false)
	world.hazards.set_physics_process(false)
	for actor in world.actors.get_children(): actor.set_physics_process(false)
	var views := [
		{"name": "standard-room", "at": Vector2(1328, 492)},
		{"name": "d4-mouth", "at": Vector2(1240, 492)},
		{"name": "return-cable", "at": Vector2(424, 748)}]
	for view in views:
		world.player.position = view.at
		world.player.velocity = Vector2.ZERO
		world.reset_view()
		for frame in range(30): await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://docs/qa/runs/m01-v31-" + view.name + ".png"
		var error := root.get_texture().get_image().save_png(path)
		print("CAPTURE ", path, " error=", error, " zoom=", world.camera.zoom, " center=", world.camera.get_screen_center_position())
		if error != OK: quit(1); return
	for node in world.find_children("*", "AudioStreamPlayer", true, false):
		node.stop()
		node.stream = null
	world.queue_free()
	for frame in range(8): await process_frame
	quit()
