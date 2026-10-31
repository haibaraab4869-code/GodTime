extends Node2D
## 机关（devices[]）：29 区共 58 个、7 种类型。
##
## 每个机关有 levels 个档位，solution 可能是单档（int）也可能是多盘口令
## （"水轮 2 · 风轮 1 · 地脉 3"）。多盘机关在数据侧拆成 device_<i>_<dial>
## 三个交互点，各调各的盘，全部对上才置 flag。
## 升降平台是唯一带实体的类型（可站可乘）；其余类型置位后由世界侧补一块
## 落脚台（world_game._device_pads()），物理后果统一走几何而不是逐类型特判。

const Maps := preload("res://game/world_data.gd")
const LIFT_SPACING := 96.0
const LIFT_WIDTH := 160.0

var world: Node2D
var map_id := ""
var devices: Array = []

func build() -> void:
	var zone := Maps.region(map_id)
	var raw_devices: Array = zone.get("devices", [])
	for index in range(raw_devices.size()):
		var raw: Dictionary = raw_devices[index]
		var targets := Maps.device_targets(raw)
		var peak := 0
		for value in targets: peak = maxi(peak, int(value))
		var span := maxi(maxi(2, int(raw.get("levels", 2))), peak + 1)
		var state: Array = []
		for step in range(maxi(1, targets.size())): state.append(0)
		var room: Dictionary = _room(str(raw.get("room", "")))
		var base := float(room.get("floor_y", 0.0))
		var key := "dev_%s_%d" % [map_id, index]
		var saved: Variant = world.chapter_flags.get(key, [])
		if saved is Array and saved.size() == state.size():
			for step in range(state.size()): state[step] = int(saved[step])
		var entry := {
			"index": index, "raw": raw, "targets": targets, "span": span,
			"state": state, "solved": false, "key": key,
			"flag": str(raw.get("flag", "")), "type": str(raw.get("type", "")),
			"room": room, "base": base, "passive": targets.is_empty(),
			"at": Vector2(Maps.rect(room.rect).get_center().x, base - 32.0),
			"points": [], "lift": null,
		}
		for step in range(maxi(1, targets.size())): entry.points.append(entry.at)
		entry.solved = _matches(entry)
		# 无解谜的机关（说明牌 / 已被剧情打开）和初始就正确的机关（目标档 0）
		# 开场即就绪，旗标静默置位，否则它们永远等不到一次"调对"的操作。
		if bool(entry.solved) and not str(entry.flag).is_empty():
			world.chapter_flags[str(entry.flag)] = true
		if entry.type == "升降平台": _make_lift(entry)
		devices.append(entry)
	for item in Maps.interactions(map_id):
		if not item.has("device"): continue
		var index := int(item.device)
		if index < 0 or index >= devices.size(): continue
		var dial := int(item.get("dial", 0))
		if dial == 0: devices[index].at = item.at
		if dial < devices[index].points.size(): devices[index].points[dial] = item.at
	queue_redraw()

func _room(name: String) -> Dictionary:
	for room in Maps.region(map_id).rooms:
		if str(room.id) == name: return room
	return Maps.region(map_id).rooms[0]

func _matches(entry: Dictionary) -> bool:
	var targets: Array = entry.targets
	var state: Array = entry.state
	if targets.is_empty(): return true
	if targets.size() != state.size(): return false
	for step in range(targets.size()):
		if int(state[step]) != int(targets[step]): return false
	return true

func _passive_text(entry: Dictionary) -> String:
	var note := str(entry.raw.get("solution", ""))
	if note.length() > 24: return note
	return "这个机关没有可调档位，靠剧情或地形推进。"

func _state_text(entry: Dictionary) -> String:
	var now: Array[String] = []
	for value in entry.state: now.append(str(int(value)))
	var want: Array[String] = []
	for value in entry.targets: want.append(str(int(value)))
	return "档位 " + " / ".join(now) + "（目标 " + " / ".join(want) + "）"

func operate(index: int, dial := 0) -> void:
	if index < 0 or index >= devices.size(): return
	var entry: Dictionary = devices[index]
	var title := str(entry.type) + " · " + str(entry.raw.get("id", ""))
	if entry.targets.size() > 1: title += " · 第%d盘" % (clampi(dial, 0, entry.targets.size() - 1) + 1)
	if bool(entry.passive):
		world._show_entry(title, _passive_text(entry))
		return
	if bool(entry.solved):
		world._show_entry(title, "机关已在正确档位：%s\n%s" % [_state_text(entry), _effect_text(entry)])
		return
	var slot := clampi(dial, 0, entry.targets.size() - 1)
	entry.state[slot] = (int(entry.state[slot]) + 1) % int(entry.span)
	entry.solved = _matches(entry)
	world.chapter_flags[str(entry.key)] = entry.state.duplicate()
	if entry.solved:
		if not str(entry.flag).is_empty(): world._set_flag(str(entry.flag), 30)
		world._show_entry(title, "机关归位：%s\n%s" % [_state_text(entry), _effect_text(entry)])
		world._rebuild_device_geometry()
	else:
		world._notify(str(entry.raw.get("fail_feedback", "档位不对，再调一次。")), 4)
	queue_redraw()

func _effect_text(entry: Dictionary) -> String:
	match str(entry.type):
		"升降平台": return "平台已到第 %d 档，站上去即可升降。" % int(entry.state[0])
		"光路": return "光斑落到接收端，对侧通路打开。"
		"潮位": return "水位对齐，浮力足以够到壁龛。"
		"风场": return "横风改向，上行气流已稳定。"
		"音柱": return "三音成序，柱底石门松开。"
		"根系": return "活根接上，根桥长到对岸。"
		"三灵协作": return "三灵同时归位，井口不再回推。"
	return "机关已生效。"

func _make_lift(entry: Dictionary) -> void:
	var body := AnimatableBody2D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(LIFT_WIDTH, 12)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector2(entry.at.x, float(entry.base) - 8.0 - float(int(entry.state[0])) * LIFT_SPACING)
	add_child(body)
	entry.lift = body

func _physics_process(delta: float) -> void:
	if world == null or world.current_map != map_id: return
	for entry in devices:
		if entry.lift == null: continue
		var target: float = float(entry.base) - 8.0 - float(int(entry.state[0])) * LIFT_SPACING
		var offset: float = target - entry.lift.position.y
		if absf(offset) < 0.01: continue
		# 逐帧限速升降，并手动带住站在平台上的主角（AnimatableBody 不会载人）。
		var step := clampf(offset, -110.0 * delta, 110.0 * delta)
		entry.lift.position.y += step
		var rider: CharacterBody2D = world.player
		var top: float = entry.lift.position.y - 6.0
		if absf(rider.position.x - entry.lift.position.x) <= LIFT_WIDTH * 0.5 and rider.position.y <= top and rider.position.y >= top - 40.0:
			rider.position.y += step

func lift_height(index: int) -> float:
	if index < 0 or index >= devices.size(): return 0.0
	var entry: Dictionary = devices[index]
	if entry.lift == null: return 0.0
	return float(entry.base) - float(entry.lift.position.y)

func _draw() -> void:
	for entry in devices:
		var base := float(entry.base)
		var tint := Color("8fb8a8") if bool(entry.solved) else Color("b08a6a")
		for dial in range(entry.points.size()):
			var at: Vector2 = entry.points[dial]
			draw_rect(Rect2(at.x - 10, base - 64, 20, 64), tint)
			draw_line(Vector2(at.x - 14, base - 64), Vector2(at.x + 14, base - 64), Color("e2d9b8"), 2)
			var value := int(entry.state[dial])
			for step in range(int(entry.span)):
				var y := base - 12 - step * 10
				draw_line(Vector2(at.x + 12, y), Vector2(at.x + 20, y), Color("e2d9b8") if step == value else Color("5c6b70"), 2)
		if bool(entry.solved):
			draw_circle(entry.at + Vector2(0, -72), 5, Color("edcd87"))
