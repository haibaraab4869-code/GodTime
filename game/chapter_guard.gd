extends Node2D

signal defeated
var player: CharacterBody2D
var boss := false
var health := 5
var maximum_health := 5
var phase := "approach"
var timer := 0.0
var facing := -1.0
var hit := false
var beats := 0
var waves: Array[Dictionary] = []
var flash := 0.0
var spawn_at := Vector2.ZERO
var active := true
var hunger := false
var chaos_marks := 0
var stagger := preload("res://game/stagger.gd").new(40)

func _ready() -> void:
	spawn_at = position
	maximum_health = 240 if boss else 45
	health = maximum_health
	stagger = preload("res://game/stagger.gd").new(100 if boss else 40, boss)
	add_to_group("attackable")
	process_physics_priority = 2

func reset_fight() -> void:
	health = maximum_health
	position = spawn_at
	phase = "approach"
	timer = 0
	waves.clear()
	beats = 0
	hunger = false
	chaos_marks = 0
	stagger = preload("res://game/stagger.gd").new(100 if boss else 40, boss)
	visible = true
	if not is_in_group("attackable"): add_to_group("attackable")

func _physics_process(delta: float) -> void:
	if player != null and player.world != null and player.world.get("hitstop_left") != null and player.world.hitstop_left > 0: return
	if not active or health <= 0 or player == null: return
	flash = maxf(0, flash - delta)
	stagger.tick(delta)
	timer -= delta
	for wave in waves:
		wave.x += wave.dir * 190 * delta
		wave.life -= delta
		if not wave.hit and absf(player.position.x - wave.x) < 22 and absf(player.position.y - (position.y - 8)) < 23:
			wave.hit = true
			_hurt_player(true)
	waves = waves.filter(func(w): return w.life > 0)
	match phase:
		"approach":
			if absf(player.position.y - (position.y - 8)) > 64: return
			facing = signf(player.position.x - position.x)
			if absf(player.position.x - position.x) < (480 if boss else 240):
				if absf(player.position.x - position.x) > (130 if boss else 52):
					position.x += facing * (62 if boss else 42) * delta
					var limits := Vector2(360, player.world.world_bounds().end.x - 360)
					if player.world.has_method("guard_bounds"): limits = player.world.guard_bounds(spawn_at)
					position.x = clampf(position.x, limits.x, limits.y)
				else:
					phase = "warning"
					timer = 1.0 if boss else 0.7
		"warning":
			if timer <= 0:
				phase = "strike"
				timer = 0.2
				hit = false
				if boss:
					if player.world.audio != null: player.world.audio.play_cue("drum")
					waves.append({"x": position.x, "dir": facing, "life": 3.0, "hit": false})
		"strike":
			if not hit and Rect2(position + Vector2(-80 if facing < 0 else 0, -40), Vector2(80, 52)).has_point(player.position):
				hit = true
				_hurt_player(false)
			if timer <= 0:
				beats += 1
				phase = "warning" if boss and beats % 3 != 0 else "recover"
				timer = 0.85 if phase == "warning" else (2.5 if boss else 1.4)
		"recover":
			if timer <= 0: phase = "approach"
		"stagger":
			if timer <= 0:
				phase = "recover"
				timer = 1.2
	queue_redraw()

func _hurt_player(projectile: bool) -> void:
	var world = player.world
	if player.dash_remaining > 0:
		world.combat.evade(get_instance_id())
		return
	if projectile and world.combat.absorb_left > 0:
		world.combat.state.add_qi(8)
		return
	if world.combat.ward_left > 0:
		world.combat.ward_left = 0
		return
	if world.hurt_lock > 0: return
	world.hurt_lock = 0.65
	player.take_damage(1)

func take_player_hit(source: CharacterBody2D) -> void:
	source.world.combat.deal_hit(self, source.world.combat.current_hit)

func hit_bounds() -> Rect2:
	return Rect2(global_position - Vector2(20, 52), Vector2(40, 64))

func receive_combat(hit_data: Dictionary, form: String) -> void:
	if health <= 0: return
	if hit_data.get("mark_consumed", "") == "hunger": hunger = false
	if hit_data.get("mark_consumed", "") == "chaos": chaos_marks = 0
	if hit_data.get("mark", "") == "hunger": hunger = true
	if hit_data.get("mark", "") == "chaos": chaos_marks = mini(3, chaos_marks + 1)
	chaos_marks = mini(3, chaos_marks + int(hit_data.get("marks", 0)))
	var multiplier := 1.0
	if form == "hundun": multiplier += stagger.register_hit()
	var damage := int(round(float(hit_data.get("damage", 0)) * multiplier))
	if stagger.apply_poise_damage(float(hit_data.get("poise", 0))):
		phase = "stagger"
		timer = stagger.stagger_remaining
		hit = true
	if float(hit_data.get("stun", 0)) > 0:
		phase = "stagger"
		timer = maxf(timer, float(hit_data.stun))
	take_damage(damage)

func take_damage(amount: int) -> void:
	if health <= 0 or not active: return
	health = maxi(0, health - amount)
	flash = 0.12
	if health == 0:
		waves.clear()
		remove_from_group("attackable")
		visible = false
		defeated.emit()
	queue_redraw()

func _draw() -> void:
	if health <= 0: return
	var ink := Color("ead5a3") if flash <= 0 else Color.WHITE
	draw_rect(Rect2(-12, -38, 24, 50), ink)
	draw_circle(Vector2(0, -43), 10, ink)
	draw_line(Vector2(-18, -54), Vector2(18, -54), Color("8e5140"), 5)
	if boss:
		draw_circle(Vector2(facing * 15, -12), 22, Color("9b6349"))
		draw_arc(Vector2(facing * 15, -12), 19, 0, TAU, 32, ink, 3)
		draw_line(Vector2(-facing * 12, -24), Vector2(facing * 44, -48 if phase == "warning" else 2), ink, 5)
	if phase == "warning":
		draw_line(Vector2.ZERO, Vector2(facing * 115, 0), Color("d98b4d"), 4)
		draw_circle(Vector2(0, -70), 6, Color("d98b4d"))
	if phase == "recover": draw_arc(Vector2(0, -63), 8, 0, TAU, 12, Color("a9c9a6"), 2)
	draw_rect(Rect2(-30, -85, 60, 5), Color("39494b"))
	draw_rect(Rect2(-30, -85, 60.0 * health / maximum_health, 5), Color("d7aa69"))
	for wave in waves:
		draw_arc(Vector2(wave.x - position.x, 8), 17, PI, TAU, 16, Color("e7b476"), 4)
