extends SceneTree

var failures := 0

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	var player = world.player
	for form in ["taotie", "qiongqi", "taowu", "hundun"]:
		world.load_map("W04")
		world.combat.state.set_form(form)
		world._rest()
		world.chapter_flags.erase("boss_dead")
		world._spawn_guard(true, world.Maps.anchor("W04", "boss"), "boss_dead")
		var boss = world.guard
		player.position = boss.position + Vector2(-110, -8)
		var respawns := [0]
		var track := func(): respawns[0] += 1
		player.respawned.connect(track)
		var lowest := 240
		for frame in range(7200):
			if boss.health <= 0 or respawns[0] > 0: break
			Input.action_release("move_left")
			Input.action_release("move_right")
			if boss.phase == "recover" and boss.timer > 1.0 and player.health < 4 and world.heal_charges > 0 and player.attack_remaining <= 0 and world.heal_remaining <= 0:
				world.heal_remaining = 0.9
			if world.heal_remaining > 0:
				player.attack_buffer.clear()
				await physics_frame
				continue
			var distance: float = absf(player.position.x - boss.position.x)
			if distance > 41:
				Input.action_press("move_right" if boss.position.x > player.position.x else "move_left")
			elif distance < 28:
				Input.action_press("move_left" if boss.position.x > player.position.x else "move_right")
			else:
				player.facing = 1 if boss.position.x > player.position.x else -1
				if boss.phase in ["recover", "stagger"] and boss.timer > 1.0 and world.combat.action_left <= 0 and player.attack_remaining <= 0:
					var cost := int(world.combat.Config.FORMS[form].skill.cost)
					world.combat.start_action("skill" if world.combat.state.qi >= cost and form != "taotie" else "heavy")
				elif world.combat.action_left <= 0:
					player.attack_buffer.press(player.attack_buffer_window)
			for wave in boss.waves:
				if absf(wave.x - player.position.x) < 85 and player.is_on_floor(): player.jump_buffer.press(player.jump_buffer_window)
			if boss.phase == "warning" and boss.timer < 0.13 and distance < 90 and player.is_on_floor(): player.dash_buffer.press(player.dash_buffer_window)
			await physics_frame
			lowest = mini(lowest, boss.health)
		Input.action_release("move_left")
		Input.action_release("move_right")
		player.respawned.disconnect(track)
		print("FORM=", form, " boss_hp=", boss.health, " lowest=", lowest, " player_hp=", player.health, " respawns=", respawns[0])
		if boss.health > 0:
			failures += 1
			print("FAIL: baseline form cannot finish simulated boss route: ", form)
	world.queue_free()
	await process_frame
	print("FAILURES=", failures)
	quit(0 if failures == 0 else 1)
