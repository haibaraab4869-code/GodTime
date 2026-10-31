extends SceneTree
const Maps := preload("res://game/world_data.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	var player = world.player
	for id in Maps.db().regions:
		world.load_map(id)
		world.hazards.set_physics_process(false) # Collision traversal is isolated from hazard skill trials.
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		var shafts: Array = Maps.model(id).stairs
		var candidates := shafts.filter(func(s): return s.tier == "R1")
		if candidates.is_empty(): candidates = shafts.filter(func(s): return s.assisted and s.traversal in ["vine", "wind"])
		var shaft: Dictionary = candidates[0]
		var x: float = float(shaft.center) + float(shaft.get("assist_offset", 84 if shaft.tier in ["R4", "R5"] else (0 if shaft.traversal in ["wind", "vine"] else -144)))
		if shaft.traversal == "terrace":
			for offset in [-144, 144, -208, 208]:
				var candidate := Vector2(float(shaft.center) + offset, float(shaft.bottom) - 20)
				var supported: bool = world._geometry(false).any(func(r): return absf(r.position.y - float(shaft.bottom)) < 2 and candidate.x >= r.position.x + 12 and candidate.x <= r.end.x - 12)
				if supported and world._is_clear(candidate, world._geometry(false)):
					x = candidate.x
					break
		player.position = Vector2(x, float(shaft.bottom) - 20)
		player.velocity = Vector2.ZERO
		player.control_lock = 0
		player.jump_buffer.clear()
		for frame in range(3): await physics_frame
		var reached := false
		if shaft.traversal in ["wind", "vine"]:
			Input.action_press("jump")
			for frame in range(360):
				await physics_frame
				if player.position.y <= float(shaft.top) - 24:
					reached = true
					break
			Input.action_release("jump")
		else:
			# R1 shelves: no special power and only real jump buffers.
			for target in shaft.steps:
				player.jump_buffer.press(player.jump_buffer_window)
				for frame in range(90):
					Input.action_release("move_left")
					Input.action_release("move_right")
					if absf(player.position.x - target.x) > 3: Input.action_press("move_right" if target.x > player.position.x else "move_left")
					await physics_frame
					if player.position.distance_to(target) < 8 and player.is_on_floor(): break
				Input.action_release("move_left")
				Input.action_release("move_right")
				reached = player.position.y <= float(shaft.top) + 48
		checks += 1
		if not reached:
			failures += 1
			print("FAIL: ", id, " shaft=", shaft.tier, " mode=", shaft.traversal, " from=", shaft.bottom, " top=", shaft.top, " pos=", player.position)
	print("STRUCTURE_TRAVERSAL ", checks, " real ascents, ", failures, " failures")
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
