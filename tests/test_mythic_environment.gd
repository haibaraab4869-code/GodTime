extends SceneTree
const Maps := preload("res://game/world_data.gd")
const Puzzle := preload("res://game/mythic_puzzle.gd")
var world: Node2D
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func run() -> void:
	world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.player.set_physics_process(false)
	for id in Maps.db().regions:
		world.chapter_flags["mythic_" + id] = 1
		world.load_map(id)
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		var env = world.environment
		var spec: Dictionary = Maps.region(id).mythic
		check(is_instance_valid(env) and env.map_id == id, id + " physical environment instantiated")
		var initial_shapes := Maps.geometry(id, false, world.chapter_flags).size()
		for index in range(spec.controls.size()):
			world.player.position = env.control_position(index)
			check(world._is_clear(world.player.position, world._geometry(false)), id + " device control clear")
			world.past_era = true
			var old: int = env.value(index)
			env.operate(index)
			check(env.value(index) == old, id + " past device is a record, not future actuator")
		world.past_era = false
		check(not env.can_finish(), id + " no automatic completion on entry")
		if spec.family == "echo":
			env.operate((int(spec.echo_order[0]) + 1) % 3)
			check(env.echo_index == 0 and Puzzle.progress(id, world.chapter_flags) == 1, id + " wrong note resets only local sequence")
			for index in spec.echo_order: env.operate(int(index))
			check(world.chapter_flags.get("echo_" + id, false), id + " actual sequence unlocks echo receiver")
		else:
			for index in range(3 if spec.family == "triad" else 1):
				world.player.position = env.control_position(index)
				for turn in range(int(spec.targets[index])): env.operate(index)
			check(env.aligned(), id + " physical controls reach authored target")
		for frame in range(150): await physics_frame
		check(env.can_finish(), id + " completed physical mechanism powers receiver")
		match str(spec.family):
			"tide", "sluice":
				var goal := Maps.anchor(id, "mythic_1")
				world.player.position = goal + Vector2(0, 30)
				world.player.velocity = Vector2.ZERO
				env.apply_motion(world.player, 1.0 / 60)
				check(world.player.velocity.y < 0 and env.water_y < env.chamber.end.y - 70, id + " moving water surface supplies real buoyancy")
			"wind":
				world.player.position = env.chamber.get_center()
				world.player.velocity = Vector2.ZERO
				env.apply_motion(world.player, 1.0 / 60)
				check(world.player.velocity.y == -340, id + " aligned wind changes actual velocity")
			"root", "triad": check(Maps.geometry(id, false, world.chapter_flags).size() > initial_shapes, id + " root growth changes solid geometry")
			"gear": check(env.lift is AnimatableBody2D and env.lift.position.y < env.lift_origin.y - 8, id + " powered gear moves a collidable platform")
			"light": check(env.beam_hits and env.beam.size() == 3, id + " reflected ray physically reaches receiver")
		if spec.family == "light":
			var blocker := StaticBody2D.new()
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(24, 24)
			shape.shape = rectangle
			blocker.add_child(shape)
			blocker.position = env.beam[1].lerp(env.beam[2], 0.5)
			world.add_child(blocker)
			for frame in range(3): await physics_frame
			check(not env.beam_hits, id + " physical occluder interrupts reflected beam")
			blocker.queue_free()
			for frame in range(3): await physics_frame
			check(env.beam_hits, id + " removing occluder restores receiver")
		world.player.position = Maps.anchor(id, "mythic_1")
		world._operate_mythic(1)
		check(Puzzle.progress(id, world.chapter_flags) == 2, id + " receiver commits cause after physical solution")
		world.player.position = Maps.anchor(id, "mythic_2")
		world.past_era = bool(spec.steps[2].past)
		world._operate_mythic(2)
		check(Puzzle.progress(id, world.chapter_flags) == 3, id + " authored final era locks solution")
		print("ENVIRONMENT=", id, " family=", spec.family, " failures=", failures)
	var path := "user://mythic_environment_%d.cfg" % Time.get_ticks_usec()
	world.save_path = path
	world.persist_progress = true
	world.chapter_flags.ability_PG = true
	world.chapter_flags.ledger_past = true
	world._save_progress()
	var restored = load("res://game/main.tscn").instantiate()
	restored.save_path = path
	root.add_child(restored)
	await process_frame
	check(restored.chapter_flags.get("device_M46_1", -1) == world.chapter_flags.device_M46_1, "device phase survives fresh scene and disk load")
	check(restored.chapter_flags.get("echo_M45", false), "echo success survives disk load")
	restored.load_map("M43")
	restored._restart_mythic()
	check(Puzzle.progress("M43", restored.chapter_flags) == 0, "lamp replay resets current mechanism")
	check(restored.chapter_flags.ability_PG and restored.chapter_flags.ledger_past and Puzzle.progress("M46", restored.chapter_flags) == 3, "replay preserves permanent ability, story and other regions")
	world.persist_progress = false
	restored.persist_progress = false
	for file in [path, path + ".chapter"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	restored.queue_free()
	world.queue_free()
	await process_frame
	print("MYTHIC_ENVIRONMENT ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
