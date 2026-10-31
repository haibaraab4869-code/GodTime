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
	world.chapter_flags.ability_VC = true
	for id in Maps.db().regions:
		for raw in Maps.region(id).structure.pogo_halls:
			if not raw.required: continue
			world.load_map(id)
			for actor in world.actors.get_children(): actor.set_physics_process(false)
			var hall: Dictionary = raw
			var nail: Dictionary = world.hazards.records.filter(func(h): return h.kind == "nail" and int(h.hall) == int(hall.id))[0]
			player.position = Vector2(hall.left, hall.floor - 20)
			player.velocity = Vector2.ZERO
			player.control_lock = 0
			player.damage_iframes = 0
			player.health = 4
			for frame in range(4): await physics_frame
			Input.action_press("move_right")
			Input.action_press("move_down")
			var key := "pogo_%s_%d" % [id, int(hall.id)]
			for frame in range(260):
				if player.is_on_floor() and player.position.x >= nail.box.position.x - 52 and player.position.x < nail.box.position.x: player.jump_buffer.press(player.jump_buffer_window)
				var gap: float = nail.box.position.y - (player.position.y + 20)
				if player.velocity.y > 0 and gap < 40 and gap >= -6 and player.position.x > nail.box.position.x - 20 and player.position.x < nail.box.end.x + 16 and player.attack_cooldown_remaining <= 0:
					player.pending_down = true
					player.pending_direction_locked = true
					player.attack_buffer.press(player.attack_buffer_window)
				await physics_frame
				if world.chapter_flags.get(key, false) or player.health < 4: break
			Input.action_release("move_right")
			Input.action_release("move_down")
			checks += 1
			if not world.chapter_flags.get(key, false) or player.health != 4:
				failures += 1
				print("FAIL: ", key, " position=", player.position, " hp=", player.health)
	print("POGO_ROUTES ", checks, " real chains, ", failures, " failures")
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
