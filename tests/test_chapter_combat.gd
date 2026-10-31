extends SceneTree

var checks := 0
var failures := 0
var world: Node2D
var enemy: Node2D
var player: CharacterBody2D
var combat: Node

func _initialize() -> void: call_deferred("run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", text)

func run() -> void:
	world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.load_map("W04")
	world._spawn_guard(true, world.Maps.anchor("W04", "boss"), "boss_dead")
	enemy = world.guard
	enemy.set_physics_process(false)
	player = world.player
	player.position = enemy.position + Vector2(-40, -8)
	combat = world.combat
	player.facing = 1
	for i in range(3): await physics_frame
	# Drive the normal attack buffer, not a direct take_damage shortcut.
	player.attack_buffer.press(player.attack_buffer_window)
	for i in range(3): await physics_frame
	check(enemy.health < enemy.maximum_health and combat.state.qi > 0, "real swing routes into configured chapter combat")
	player.attack_remaining = 0
	player.attack_cooldown_remaining = 0
	player.attack_buffer.clear()
	combat.state.set_form("taotie")
	combat.deal_hit(enemy, combat.Rules.resolve_combo("taotie", 2, false))
	check(enemy.hunger, "taotie finisher marks enemy")
	player.health = 2
	var hp: int = enemy.health
	check(combat.start_action("heavy"), "heavy action begins")
	combat._physics_process(1)
	check(enemy.health < hp and not enemy.hunger and player.health == 3, "marked bite deals damage, consumes mark and heals")
	combat.deal_hit(enemy, combat.Rules.resolve_combo("taotie", 2, false))
	combat.deal_hit(enemy, combat.Rules.resolve_heavy("taotie", {}, false))
	check(player.health == 3, "same-target bite cannot heal again immediately")
	combat.state.set_form("qiongqi")
	combat.evade(enemy.get_instance_id())
	check(combat.state.is_sharp() and combat.state.qi == 15, "precise dash awards sharp and qi")
	enemy.phase = "recover"
	hp = enemy.health
	combat.deal_hit(enemy, combat.Rules.resolve_heavy("qiongqi", {}, true))
	check(enemy.health <= hp - 36 and not combat.state.is_sharp(), "sharp heavy consumes buff and applies multiplier")
	combat.state.set_form("taowu")
	world.hurt_lock = 0
	player.health = 4
	enemy._hurt_player(false)
	check(combat.state.reverse_stacks == 1, "taowu takes reverse stack through real enemy damage")
	combat.state.qi = 50
	combat.clear_action()
	player.attack_remaining = 0
	check(combat.start_action("skill"), "taowu skill spends qi")
	combat._physics_process(1)
	check(combat.ward_left > 0, "taowu skill readies ward")
	world.hurt_lock = 0
	var health: int = player.health
	enemy._hurt_player(false)
	check(player.health == health and combat.ward_left == 0, "taowu ward absorbs one hit")
	enemy.reset_fight()
	combat.clear_action()
	combat.state.set_form("hundun")
	combat.deal_hit(enemy, combat.Rules.resolve_combo("hundun", 2, false))
	check(enemy.chaos_marks == 1, "hundun finisher marks enemy")
	hp = enemy.health
	combat.deal_hit(enemy, combat.Rules.resolve_heavy("hundun", {}, false))
	check(enemy.health < hp - 30 and enemy.chaos_marks == 0, "hundun heavy detonates marks and benefits from aftershock")
	combat.clear_action()
	combat.state.qi = 0
	check(not combat.start_action("skill"), "insufficient qi cannot launch skill")
	combat.state.qi = 100
	check(combat.start_action("skill"), "funded skill begins")
	hp = enemy.health
	combat._physics_process(0.2)
	check(enemy.health == hp, "delayed skill does not hit immediately")
	combat._physics_process(0.7)
	check(enemy.health < hp and enemy.chaos_marks > 0, "delayed area strike hits in front and applies mark")
	combat.clear_action()
	combat.state.set_form("taotie")
	combat.state.qi = 50
	combat.start_action("skill")
	combat._physics_process(1)
	world.hurt_lock = 0
	health = player.health
	enemy._hurt_player(true)
	check(player.health == health and combat.state.qi == 28, "taotie absorbs ground wave and refunds qi")
	check(not combat.state.can_shift_in_field(), "chapter does not enable unapproved field form switching")
	world.souls = 100
	world._buy_supply()
	world.journal.close_reader()
	check(world.heal_charges == 4 and world.souls == 50, "chapter rewards can buy supply capacity")
	world._buy_supply()
	world.journal.close_reader()
	world._rest()
	check(world.heal_charges == 5 and player.maximum_health == 4, "supply upgrade preserves base health and refills at rest")
	world.queue_free()
	await process_frame
	print("CHECKS=", checks)
	print("FAILURES=", failures)
	quit(0 if failures == 0 else 1)
