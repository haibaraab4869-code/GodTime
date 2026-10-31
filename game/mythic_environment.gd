extends Node2D
## Physical exploration mechanisms. Local controls and state persist per region.
const Maps := preload("res://game/world_data.gd")
const Puzzle := preload("res://game/mythic_puzzle.gd")
var world: Node2D
var map_id: String
var spec: Dictionary
var active := false
var chamber: Rect2
var water_y := 0.0
var lift: AnimatableBody2D
var lift_origin := Vector2.ZERO
var phase_clock := 0.0
var echo_index := 0
var playback := -1
var playback_left := 0.0
var glowing := -1
var sound: AudioStreamPlayer
var tones: Array[AudioStreamWAV] = []
var beam: PackedVector2Array = []
var beam_hits := false

func _ready() -> void:
	spec = Maps.region(map_id).get("mythic", {})
	# 29 区世界不实现旧 mythic 机关（devices 只作元数据）：没有 chamber 就整体空转。
	active = spec.has("chamber")
	if not active:
		set_physics_process(false)
		return
	chamber = Maps.rect(Maps.region(map_id).rooms[int(spec.chamber)].rect)
	water_y = chamber.end.y
	sound = AudioStreamPlayer.new()
	sound.volume_db = -17
	add_child(sound)
	for frequency in [220.0, 330.0, 440.0]:
		var bytes := PackedByteArray()
		for i in range(6615):
			var envelope := sin(PI * i / 6615.0)
			var sample := int(sin(TAU * frequency * i / 44100.0) * envelope * 22000)
			bytes.append(sample & 255)
			bytes.append((sample >> 8) & 255)
		var tone := AudioStreamWAV.new()
		tone.format = AudioStreamWAV.FORMAT_16_BITS
		tone.mix_rate = 44100
		tone.data = bytes
		tones.append(tone)
	if spec.family == "gear":
		lift = AnimatableBody2D.new()
		lift.sync_to_physics = false
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(88, 14)
		shape.shape = rectangle
		lift.add_child(shape)
		lift_origin = Vector2(chamber.get_center().x + 64, chamber.end.y - 40)
		lift.position = lift_origin
		add_child(lift)
	_refresh_beam()

func stage() -> int: return Puzzle.progress(map_id, world.chapter_flags)
func value(index: int) -> int: return int(world.chapter_flags.get("device_%s_%d" % [map_id, index], target(index) if stage() >= 2 else 0))
func target(index: int) -> int: return int(spec.targets[index])
func aligned() -> bool:
	for i in range(3 if spec.family == "triad" else 1):
		if value(i) != target(i): return false
	return true

func control_position(index: int) -> Vector2:
	var at := Vector2(float(spec.controls[index][0]), float(spec.controls[index][1]))
	if spec.family in ["tide", "sluice", "triad"]:
		at.y = minf(at.y, water_y - 16)
	return at

func interactions() -> Array:
	var result: Array = []
	if not active: return result
	if stage() < 1: return result
	var labels: Array = {
		"sluice": ["神龙分流阀：切换支渠"], "tide": ["神龙水尺：调整蓄水量"],
		"wind": ["凤凰风向仪：旋转导流翼"], "root": ["凤凰焚枝印：选择保留的活根"],
		"gear": ["麒麟校准柄：转动齿轮相位"], "light": ["凤凰石镜：转动反射面"],
		"echo": ["龙音柱", "凤音柱", "麟音柱"],
		"triad": ["神龙水轮相位", "凤凰风轮相位", "麒麟地脉相位"]}[spec.family]
	for i in range(labels.size()):
		result.append({"id": "device_" + str(i), "name": labels[i], "at": control_position(i), "radius": 52})
	return result

func operate(index: int) -> void:
	if not active: return
	if stage() < 1: return
	if world.past_era:
		world._notify("过去的记录已保存；到未来调整实体机关。", 4)
		return
	if spec.family == "echo":
		_play(index)
		if bool(world.chapter_flags.get("echo_" + map_id, false)): return
		if int(spec.echo_order[echo_index]) == index:
			echo_index += 1
			if echo_index == spec.echo_order.size():
				world.chapter_flags["echo_" + map_id] = true
				world._save_progress()
				world._notify("三腔回声一致，回声门已响应。", 4)
		else:
			echo_index = 0
			world._notify("回声不符，仅重置本次音序。过去的第一座神兽站可重播原声。", 5)
		queue_redraw()
		return
	var proposed: Dictionary = world.chapter_flags.duplicate()
	proposed["device_%s_%d" % [map_id, index]] = (value(index) + 1) % 3
	if not world._is_clear(world.player.position, Maps.geometry(map_id, world.past_era, proposed)):
		world._notify("当前位置无法使用该能力", 4)
		return
	world.chapter_flags = proposed
	world._build_terrain(world._geometry(world.past_era))
	world._save_progress()
	_refresh_beam()
	world._notify("机关档位 %d · %s" % [value(index) + 1, "已对准过去的真纹" if aligned() else "可继续调整，对照过去的记录"], 4)
	queue_redraw()

func _play(index: int) -> void:
	glowing = index
	sound.stream = tones[index]
	sound.play()

func play_memory() -> void:
	if not active or spec.family != "echo": return
	playback = 0
	playback_left = 0

func _physics_process(delta: float) -> void:
	if world.get("hitstop_left") != null and world.hitstop_left > 0: return
	if world.current_map != map_id: return
	phase_clock += delta
	if playback >= 0:
		playback_left -= delta
		if playback_left <= 0:
			_play(int(spec.echo_order[playback]))
			playback += 1
			playback_left = 0.55
			if playback >= spec.echo_order.size(): playback = -1
	var water_depth := 0.0
	if stage() >= 1 and not world.past_era and spec.family in ["sluice", "tide"]:
		water_depth = float(spec.water_levels[value(0)])
	if stage() >= 1 and not world.past_era and spec.family == "triad" and value(0) == target(0): water_depth = 64
	water_y = move_toward(water_y, chamber.end.y - water_depth, delta * 110)
	if is_instance_valid(lift):
		var enabled: bool = stage() >= 1 and aligned() and not world.past_era
		var distance := float(spec.lift_height) * (0.5 - cos(phase_clock * float(spec.lift_speed)) * 0.5) if enabled else 0.0
		lift.position = lift_origin - Vector2(0, distance)
	_refresh_beam()
	queue_redraw()

func apply_motion(body: CharacterBody2D, _delta: float) -> void:
	if not active: return
	if not chamber.has_point(body.position): return
	if spec.family in ["tide", "sluice", "triad"] and wet_area().has_point(body.position + Vector2(0, 16)) and water_y < chamber.end.y - 4:
		body.velocity.y = clampf((water_y - 16 - body.position.y) * 6, -190, 85)
		var swim_jump: bool = Input.is_action_pressed("jump")
		var buffer = body.get("jump_buffer")
		if buffer != null and buffer.is_active():
			buffer.consume()
			swim_jump = true
		if swim_jump: body.velocity.y = -340
		if Input.is_action_pressed("dive"): body.velocity.y = 180
		if spec.family == "sluice":
			var current := float(spec.wind_bias)
			if body.position.x < chamber.position.x + 64 and current < 0: current = 0
			if body.position.x > chamber.end.x - 64 and current > 0: current = 0
			body.velocity.x += current
	if spec.family == "wind" and stage() >= 1 and not world.past_era:
		if absf(body.position.x - chamber.get_center().x) < 110:
			if aligned():
				body.velocity.y = -340
				body.velocity.x += float(spec.wind_bias)
			else: body.velocity.y = maxf(body.velocity.y, 100)
	if spec.family == "triad" and stage() >= 1 and not world.past_era and value(1) == target(1) and Input.is_action_pressed("jump"):
		if absf(body.position.x - chamber.get_center().x) < 72: body.velocity.y = -230

func wet_area() -> Rect2:
	var area := Rect2(chamber.position.x, water_y, chamber.size.x, maxf(0, chamber.end.y - water_y))
	if spec.family == "sluice" and not aligned():
		area.position.x += chamber.size.x * (value(0) % 2) / 3
		area.size.x /= 3
	return area

func can_finish() -> bool:
	if not active: return false
	if stage() != 1 or world.past_era: return false
	match str(spec.family):
		"echo": return bool(world.chapter_flags.get("echo_" + map_id, false))
		"light": return aligned() and beam_hits
		"sluice", "tide": return aligned() and absf(water_y - (chamber.end.y - float(spec.water_levels[target(0)]))) < 3
		_: return aligned()

func _refresh_beam() -> void:
	if spec.family != "light": return
	beam_hits = false
	var mirror := Vector2(chamber.get_center().x, chamber.end.y - 192)
	var source := Vector2(chamber.position.x + 24, mirror.y)
	var direction: Vector2 = [Vector2.RIGHT, Vector2.UP, Vector2.DOWN][value(0)]
	var receiver: Vector2 = mirror + [Vector2.RIGHT, Vector2.UP, Vector2.DOWN][target(0)] * 128
	beam = PackedVector2Array([source, mirror])
	if stage() < 1 or world.past_era: return
	var endpoint := mirror + direction * 128
	var query := PhysicsRayQueryParameters2D.create(mirror + direction * 6, endpoint, 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): endpoint = hit.position
	beam.append(endpoint)
	beam_hits = endpoint.distance_to(receiver) < 12

func _draw() -> void:
	if spec.is_empty(): return
	var tint := Color(Maps.region(map_id).color)
	if spec.family in ["sluice", "tide", "triad"] and water_y < chamber.end.y:
		draw_rect(wet_area(), Color(0.2, 0.55, 0.75, 0.45))
		for x in range(int(wet_area().position.x), int(wet_area().end.x), 16):
			draw_line(Vector2(x, water_y + sin(phase_clock * 3 + x * 0.07) * 3), Vector2(x + 16, water_y + sin(phase_clock * 3 + (x + 16) * 0.07) * 3), Color("94d9e1"), 2)
	if spec.family == "wind":
		for y in range(int(chamber.position.y + 32), int(chamber.end.y), 36):
			var a := Vector2(chamber.get_center().x, y + fmod(-phase_clock * 70, 36))
			draw_line(a + Vector2(-12, 12), a, Color("a4d5dc"), 3)
			draw_line(a, a + Vector2(12, 12), Color("a4d5dc"), 3)
	if spec.family == "light" and beam.size() >= 2:
		draw_polyline(beam, Color("ffe3a0") if beam_hits else Color("a99870"), 4)
		var mirror := Vector2(chamber.get_center().x, chamber.end.y - 192)
		var receiver: Vector2 = mirror + [Vector2.RIGHT, Vector2.UP, Vector2.DOWN][target(0)] * 128
		draw_circle(receiver, 11, Color("ffdc81"), false, 3)
	if is_instance_valid(lift):
		draw_circle(lift_origin - Vector2(0, 100), 30, tint.lightened(0.25), false, 6)
		for i in range(8):
			var angle := phase_clock + i * TAU / 8
			var p := lift_origin - Vector2(0, 100)
			draw_line(p + Vector2.from_angle(angle) * 24, p + Vector2.from_angle(angle) * 38, tint.lightened(0.5), 5)
		draw_rect(Rect2(lift.position - Vector2(44, 7), Vector2(88, 14)), Color("bca275"))
	for shape in fixtures(Maps.region(map_id), world.past_era, world.chapter_flags):
		draw_rect(shape, Color("75916d") if spec.family in ["root", "triad"] else Color("a99773"))
		if spec.family in ["root", "triad"]:
			draw_line(Vector2(chamber.position.x + 48, chamber.end.y), shape.get_center(), Color("496f52"), 5)
	for i in range(spec.controls.size()):
		var at := control_position(i)
		var color: Color = [Color("6fc6d1"), Color("e4a36d"), Color("98bd86")][i]
		draw_circle(at, 18 if glowing == i and sound.playing else 12, color, false, 3)
		if spec.family != "echo":
			for notch in range(value(i) + 1): draw_circle(at + Vector2(-8 + notch * 8, -22), 2.5, color)
	var goal := Maps.anchor(map_id, "mythic_1")
	draw_arc(goal, 22, 0, TAU, 24, Color("e0d595") if can_finish() else Color("66777b"), 3)

static func fixtures(zone: Dictionary, past: bool, flags: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var spec: Dictionary = zone.mythic
	var family: String = spec.family
	var room := Maps.rect(zone.rooms[int(spec.chamber)].rect)
	var goal := Vector2(float(spec.stations[1][0]), float(spec.stations[1][1]))
	if family in ["gear", "wind", "root", "triad"]:
		result.append(Rect2(goal + Vector2(-40, 20), Vector2(80, 14)))
	if family in ["root", "triad"] and Puzzle.progress(zone.id, flags) >= 1:
		var aligned := int(flags.get("device_%s_0" % zone.id, 0)) == int(spec.targets[0])
		if family == "triad": aligned = int(flags.get("device_%s_2" % zone.id, 0)) == int(spec.targets[2])
		if aligned or Puzzle.progress(zone.id, flags) >= 2:
			for i in range(1, 4):
				var x := lerpf(room.position.x + 72, goal.x, i / 4.0)
				result.append(Rect2(x - 28, room.end.y - i * 48, 56, 12))
	return result
