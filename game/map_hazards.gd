extends Node2D
var world: Node2D
var records: Array = []
var elapsed := 0.0
var invulnerable := 0.0
var active_hall := -1
var entry_side := 0
var bounces := 0
var last_safe := Vector2.INF
var last_pogo_frame := -1
var trail_left := 0.0
var trail_from := Vector2.ZERO
var trail_to := Vector2.ZERO

func _ready() -> void:
	for raw in world.Maps.region(world.current_map).structure.hazards:
		var h: Dictionary = raw.duplicate()
		h.box = world.Maps.rect(raw.rect)
		records.append(h)
	process_physics_priority = 2

func unsafe(at: Vector2) -> bool:
	var body := Rect2(at - Vector2(14, 22), Vector2(28, 44))
	for h in records:
		if body.intersects(h.box.grow(8)): return true
	return false

func pogo_hit(box: Rect2, feet: float) -> bool:
	for h in records:
		var top := Rect2(h.box.position - Vector2(0, 5), Vector2(h.box.size.x, 6))
		if box.intersects(top) and feet <= h.box.position.y + 8:
			if world.player.pogo():
				last_pogo_frame = Engine.get_physics_frames()
				return true
	return false

func register_pogo() -> void:
	if active_hall >= 0: bounces += 1

func _physics_process(delta: float) -> void:
	elapsed += delta
	trail_left = maxf(0, trail_left - delta)
	invulnerable = maxf(0, invulnerable - delta)
	if world.player.health <= 0 or world.hitstop_left > 0: return
	var at: Vector2 = world.player.position
	_update_trial(at)
	if world.player.is_on_floor() and not unsafe(at) and world._is_clear(at, world._geometry(world.past_era)):
		last_safe = at
	if invulnerable > 0 or last_pogo_frame == Engine.get_physics_frames():
		queue_redraw()
		return
	var body := Rect2(at - Vector2(12, 20), Vector2(24, 40))
	for h in records:
		if body.intersects(h.box):
			damage()
			break
	queue_redraw()

func _update_trial(at: Vector2) -> void:
	var halls: Array = world.Maps.region(world.current_map).structure.pogo_halls
	for hall in halls:
		if at.y < float(hall.floor) - 128 or at.y > float(hall.floor) + 32: continue
		if at.x < float(hall.left) - 96 or at.x > float(hall.right) + 96: continue
		if active_hall != int(hall.id):
			if absf(at.x - float(hall.left)) < 40 or absf(at.x - float(hall.right)) < 40:
				active_hall = int(hall.id)
				entry_side = -1 if at.x < (float(hall.left) + float(hall.right)) / 2 else 1
				bounces = 0
		if active_hall == int(hall.id) and bounces >= 2:
			var crossed: bool = at.x >= float(hall.right) - 12 if entry_side < 0 else at.x <= float(hall.left) + 12
			if crossed:
				world._set_flag("pogo_%s_%d" % [world.current_map, int(hall.id)])
				world._notify("下劈通路已贯通，回访无需重做。", 3)
		return
	active_hall = -1
	bounces = 0

func safe_position(origin: Vector2) -> Vector2:
	var geometry: Array[Rect2] = world._geometry(world.past_era)
	var best := 480.0 * 480.0
	var result := Vector2.INF
	for r in geometry:
		if r.size.x < 52 or r.position.y < 80: continue
		for x in range(int(r.position.x + 26), int(r.end.x - 25), 12):
			var candidate := Vector2(x, r.position.y - 20)
			var score := origin.distance_squared_to(candidate)
			if score < best and not unsafe(candidate) and world._is_clear(candidate, geometry):
				if world._is_clear(candidate + Vector2(24, 0), geometry) or world._is_clear(candidate - Vector2(24, 0), geometry):
					best = score
					result = candidate
	if result == Vector2.INF and last_safe != Vector2.INF and origin.distance_squared_to(last_safe) <= 480 * 480 and not unsafe(last_safe) and world._is_clear(last_safe, geometry): result = last_safe
	return result

func damage() -> void:
	if invulnerable > 0: return
	invulnerable = 1.0
	active_hall = -1
	bounces = 0
	var at: Vector2 = world.player.position
	var destination := safe_position(at)
	var lethal: bool = world.player.health <= 1
	world.player.take_damage(1)
	world.player.damage_iframes = 1.0
	if lethal:
		if is_instance_valid(world.hazards): world.hazards.invulnerable = 1.0
		return
	if destination == Vector2.INF:
		world.load_map(world.checkpoint_map, world.checkpoint_at)
		world.hazards.invulnerable = 1.0
	else:
		world.player.position = destination
		trail_from = at
		trail_to = destination
		trail_left = 0.15
	for joy in Input.get_connected_joypads(): Input.start_joy_vibration(joy, 0.5, 0.8, 0.2)
	world.player.velocity = Vector2.ZERO
	world.player.dash_remaining = 0
	world.player.attack_remaining = 0
	world.player.jump_buffer.clear()
	world.player.attack_buffer.clear()
	world.player.dash_buffer.clear()
	world.hurt_lock = 0.25
	world.player.control_lock = 0.25
	world.reset_view()

func _draw() -> void:
	if trail_left > 0: draw_line(trail_from, trail_to, Color(0.9, 0.9, 0.8, trail_left / 0.15), 3)
	for h in records:
		var r: Rect2 = h.box
		if bool(h.get("cracked", false)):
			for x in range(int(r.position.x) - 36, int(r.end.x) + 36, 18):
				draw_polyline(PackedVector2Array([Vector2(x, r.end.y + 5), Vector2(x + 8, r.end.y), Vector2(x + 14, r.end.y + 7)]), Color("8b8675"), 2)
			if r.get_center().distance_to(world.player.position) <= 200:
				for i in range(6):
					var phase := fmod(elapsed * 0.7 + float(i) / 6.0, 1.0)
					var dust := Vector2(r.position.x + r.size.x * float(i + 1) / 7.0 + sin(elapsed + i) * 5, r.position.y - phase * 26)
					draw_circle(dust, 2, Color(0.65, 0.61, 0.49, (1.0 - phase) * 0.6))
		var color := Color("d9c5a0")
		for x in range(int(r.position.x), int(r.end.x), 12):
			var tip := Vector2(x + (9 if h.kind == "nail" else 6), r.position.y)
			draw_polyline(PackedVector2Array([Vector2(x, r.end.y), tip, Vector2(x + 12, r.end.y)]), color, 2)
			if h.kind == "nail": draw_line(tip - Vector2(3, 0), tip + Vector2(3, 0), Color("fff0ce"), 2)
