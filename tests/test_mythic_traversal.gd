extends SceneTree
const Maps := preload("res://game/world_data.gd")
var world: Node2D
var player: CharacterBody2D
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label, " at ", player.position)
func go(goal: Vector2, jump: bool) -> bool:
	if jump: player.jump_buffer.press(player.jump_buffer_window)
	for frame in range(300):
		Input.action_release("move_left")
		Input.action_release("move_right")
		if absf(player.position.x - goal.x) > 3: Input.action_press("move_right" if player.position.x < goal.x else "move_left")
		if player.position.distance_to(goal) < 12: break
		await physics_frame
	Input.action_release("move_left")
	Input.action_release("move_right")
	return player.position.distance_to(goal) < 14
func run() -> void:
	world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	player = world.player
	for id in Maps.db().regions:
		if Maps.region(id).mythic.family in ["echo", "light"]: continue
		world.chapter_flags["mythic_" + id] = 1
		world.load_map(id)
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		var env = world.environment
		var spec: Dictionary = Maps.region(id).mythic
		for index in range(3 if spec.family == "triad" else 1):
			player.position = env.control_position(index)
			for turn in range(int(spec.targets[index])): env.operate(index)
		player.velocity = Vector2.ZERO
		var goal := Maps.anchor(id, "mythic_1")
		if spec.family in ["root", "triad"]:
			player.position = Vector2(env.chamber.position.x + 64, env.chamber.end.y - 20)
			for frame in range(3): await physics_frame
			var shapes: Array = env.fixtures(Maps.region(id), false, world.chapter_flags)
			shapes.sort_custom(func(a, b): return a.position.y > b.position.y)
			var ok := true
			for shape in shapes:
				if not await go(Vector2(shape.get_center().x, shape.position.y - 20), true):
					ok = false
					break
			check(ok and player.position.distance_to(goal) < 14, id + " real baseline player crosses grown roots")
		elif spec.family == "gear":
			player.position = env.lift.position - Vector2(0, 27)
			var start_y: float = player.position.y
			for frame in range(300):
				await physics_frame
				if player.position.y <= goal.y + 28: break
			check(player.position.y < start_y - 80, id + " platform carries player upward")
			check(await go(goal, true), id + " can jump from moving platform onto exit balcony")
		elif spec.family == "wind":
			player.position = Vector2(env.chamber.get_center().x + 64, env.chamber.end.y - 20)
			for frame in range(120):
				await physics_frame
				if player.position.y <= goal.y + 32: break
			check(await go(goal, false), id + " wind carries player to upper exit")
		else:
			player.position = Vector2(env.chamber.position.x + 64, env.chamber.end.y - 20)
			for frame in range(160): await physics_frame
			check(await go(goal, false), id + " buoyancy lets player swim to raised receiver")
			Input.action_press("dive")
			var surface_y: float = player.position.y
			for frame in range(24): await physics_frame
			Input.action_release("dive")
			check(player.position.y > surface_y + 24, id + " can dive to submerged paths")
		print("PHYSICAL_TRIAL=", id, " failures=", failures)
	world.queue_free()
	await process_frame
	print("MYTHIC_TRAVERSAL ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
