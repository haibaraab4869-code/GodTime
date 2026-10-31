extends "res://game/world_base.gd"

const ABILITIES := { "P2": "凤凰二段跳", "PA": "凤凰空中冲刺", "PW": "凤凰蹬墙", "PG": "凤凰滑翔", "QS": "麒麟初识", "DS": "龙鳞耐热", "DT": "龙尾破壁", "DB": "龙息冻水与酸蚀", "VC": "时间切换" }
# 能力用法提示（机制口径）。取得文案走 grants[].text（世界内说法），两者不互相替换。
const ABILITY_USAGE := {
	"VC": "按切换键在两代之间换边；换到没地的一侧会落下去，只掉位置不掉血。",
	"P2": "空中再次按跳跃。",
	"PA": "空中按冲刺，每次落地恢复。",
	"PW": "贴墙时按跳跃，向外蹬出。",
	"PG": "下落时按住跳跃减缓下降。",
	"QS": "最大生命增至六格，灯龛恢复。",
	"DS": "龙鳞只挡地形的热，不挡敌人打你。",
	"DT": "标记脆壁的探索通路已开放。",
	"DB": "冻水与酸蚀的探索通路已开放。",
}
const GATE_HINTS := {
	"FINAL_DOOR": "先完成公开副本登记，此门由内侧开启。",
	"ENDGAME": "此门自内而开。",
	"w25_verdict_sealed": "先在原告席落判，再回看这扇门。",
}
# 战场提示碑第二行（W16 R09 灯龛旁 · 本区专属战术提示，24 字）。红线句不在此处，复用 ABILITY_USAGE["DS"]。
const DS_BATTLE_HINT := "借火的殿里只有盐台是凉的——没有鳞也能靠盐台打完"
var region_instance: Node2D
var region_guard: Node2D
var environment: Node2D
var hazards: Node2D
var device_bay: Node2D
var hitstop_left := 0.0
var camera_room := -1

func _process(delta: float) -> void:
	super._process(delta)
	if hitstop_left <= 0: _update_fixed_camera(delta)

func _update_fixed_camera(_delta: float) -> void:
	if player == null or camera == null: return
	camera.zoom = Vector2(1.6, 1.6)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	var rooms: Array = Maps.region(current_map).rooms
	if camera_room < 0 or camera_room >= rooms.size() or not Maps.rect(rooms[camera_room].rect).has_point(player.position):
		camera_room = Maps.room_at(current_map, player.position)
	var room := Maps.rect(rooms[camera_room].rect)
	var clamp_to_space := room.has_point(player.position)
	for shaft in Maps.model(current_map, past_era).stairs:
		var shaft_center := float(shaft.center)
		var shaft_top := float(shaft.top)
		var shaft_bottom := float(shaft.bottom)
		var shaft_width := float(shaft.get("width", 256))
		if absf(player.position.x - shaft_center) <= maxf(96.0, shaft_width * 0.5) and player.position.y >= shaft_top - 48.0 and player.position.y <= shaft_bottom:
			room = Rect2(shaft_center - shaft_width * 0.5, shaft_top - 96.0, shaft_width, shaft_bottom - shaft_top + 192.0)
			clamp_to_space = true
			break
	var half_view := get_viewport_rect().size / camera.zoom * 0.5
	var lead := 60.0 if Input.is_action_pressed("move_down") else (-60.0 if player.velocity.y < -20 else 0.0)
	var center: Vector2 = player.position + Vector2(0, clampf(lead, -96.0, 96.0))
	if clamp_to_space:
		center.x = room.get_center().x if room.size.x <= half_view.x * 2 else clampf(center.x, room.position.x + half_view.x, room.end.x - half_view.x)
		center.y = room.get_center().y if room.size.y <= half_view.y * 2 else clampf(center.y, room.position.y + half_view.y, room.end.y - half_view.y)
	camera.global_position = center

func reset_view() -> void:
	camera_room = -1
	_update_fixed_camera(0.0)
	camera.reset_smoothing()

func _on_respawn() -> void:
	super._on_respawn()
	reset_view()

func _drop_position() -> Vector2:
	var at := super._drop_position()
	if is_instance_valid(hazards) and soul_drop.get("map", "") == current_map and hazards.unsafe(at):
		var safe: Vector2 = hazards.safe_position(at)
		return Maps.anchor(current_map, "rest") if safe == Vector2.INF else safe
	return at
func on_pogo() -> void:
	hitstop_left = 0.06
	if is_instance_valid(hazards): hazards.register_pogo()
	if audio != null: audio.play_cue("pogo", 1.0 + maxf(0, player.pogo_combo - 1) * 0.10)
	for joy in Input.get_connected_joypads(): Input.start_joy_vibration(joy, 0.25, 0.35, 0.12)
func test_pogo_surfaces(box: Rect2) -> void:
	if is_instance_valid(hazards): hazards.pogo_hit(box, player.position.y + 20)
	for target in get_tree().get_nodes_in_group("pogoable"):
		if target in player.attack_hit_nodes or not target.has_method("hit_bounds"): continue
		if target.has_meta("projectile_kind") and target.get_meta("projectile_kind") not in ["stone", "bone"]: continue
		var surface: Rect2 = target.hit_bounds()
		if box.intersects(surface) and player.position.y + 20 <= surface.position.y + 8:
			if player.pogo():
				player.attack_hit_nodes.append(target)
				if target.has_method("struck"): target.struck()
func hazard_fall() -> void:
	if is_instance_valid(hazards): hazards.damage()
const Mythic := preload("res://game/mythic_puzzle.gd")
var boundary_cooldown := 0.65
var boundary_armed := false
var boundary_busy := false
var boundary_notice := 0.0
## 本区「触碰即取」的取得点（grants[].auto）。load_map 时缓存，每帧最多 1 次距离判定：
## 29 区共 413 条交互，绝不能在 _physics_process 里全表遍历。
var auto_grants: Array = []

func _physics_process(delta: float) -> void:
	hitstop_left = maxf(0, hitstop_left - delta)
	if hitstop_left > 0: return
	boundary_cooldown = maxf(0, boundary_cooldown - delta)
	boundary_notice = maxf(0, boundary_notice - delta)
	if player == null or player.health <= 0 or journal.visible or settings_panel.visible or (atlas != null and atlas.visible): return
	_check_boundary()
	_check_auto_grants()

func _cache_auto_grants() -> void:
	auto_grants.clear()
	for item in Maps.interactions(current_map):
		if item.get("auto", false): auto_grants.append(item)

func _check_auto_grants() -> void:
	# 触碰即取：进入 radius 就发放，不弹面板、不 pause、不抢输入（PW 井壁蹬痕）。
	for item in auto_grants:
		if ability_available(str(item.get("ability", ""))): continue
		if not Maps.era_ok(item, past_era): continue
		if player.position.distance_to(item.at) > float(item.radius): continue
		_grant_ability(str(item.id))

func _check_boundary() -> void:
	if boundary_busy: return
	var inside: Array = []
	for item in Maps.interactions(current_map):
		if item.id.begins_with("travel_") and Maps.boundary(item).has_point(player.position): inside.append(item)
	if inside.is_empty():
		if boundary_cooldown <= 0: boundary_armed = true
		return
	if not boundary_armed or boundary_cooldown > 0: return
	for item in inside:
		# 横门（W/E 墙）用左右推，竖门（N/S 墙）用跳／下踩；两者都要求"向外"的速度。
		var outward := 0.0
		if str(item.get("door", "h")) == "v":
			if float(item.side) < 0:
				if Input.is_action_pressed("jump") and player.velocity.y < -20: outward = 1.0
			elif Input.is_action_pressed("move_down"): outward = 1.0
		else:
			outward = Input.get_axis("move_left", "move_right") * float(item.side)
			if outward > 0 and player.velocity.x * float(item.side) <= 1: outward = 0.0
		if outward <= 0: continue
		var target: String = item.id.trim_prefix("travel_")
		for edge in Maps.connections(current_map):
			if Maps.target(edge, current_map) != target: continue
			var reason := gate_reason(edge)
			if not reason.is_empty():
				if boundary_notice <= 0:
					_notify(reason, 3)
					boundary_notice = 2.0
				return
			boundary_busy = true
			boundary_armed = false
			if not str(edge.opener).is_empty(): _set_flag("open_" + edge.id)
			exit_requested.emit(target, "from_" + current_map)
			load_map(target, Maps.entry(target, current_map))
			boundary_busy = false
			return

func apply_map_motion(body: CharacterBody2D, _delta: float) -> void:
	if is_instance_valid(environment): environment.apply_motion(body, _delta)
	if not Input.is_action_pressed("jump"): return
	for shaft in Maps.model(current_map, past_era).stairs:
		if not shaft.assisted: continue
		var kind: String = shaft.traversal
		if kind == "terrace": continue
		if kind == "wall" and (not ability_available("PW") or absf(body.position.x - float(shaft.center)) < 100): continue
		var deep: bool = shaft.tier in ["R4", "R5", "D4", "D5"]
		var center: float = float(shaft.center) + float(shaft.get("assist_offset", 96 if deep else 0))
		if absf(body.position.x - center) <= (20 if deep else 110) and body.position.y >= float(shaft.top) - 48 and body.position.y <= float(shaft.bottom):
			body.velocity.y = -260 if kind == "wind" else -225
			return

func _operate_mythic(station: int) -> void:
	var spec: Dictionary = Maps.region(current_map).mythic
	var outcome := Mythic.attempt(current_map, spec, station, past_era, chapter_flags)
	if not outcome.ok:
		_notify((str(spec.clue) if station == 0 and past_era and Mythic.progress(current_map, chapter_flags) > 0 else outcome.message), 5)
		if station == 0 and past_era and is_instance_valid(environment): environment.play_memory()
		return
	if station == 1 and is_instance_valid(environment) and not environment.can_finish():
		_notify("先调整机关室内的实体装置，再抵达三灵站2；过去的真纹可在站1重看。", 5)
		return
	var proposed := chapter_flags.duplicate()
	proposed["mythic_" + current_map] = outcome.next
	var next_geometry := Maps.geometry(current_map, past_era, proposed)
	if not _is_clear(player.position, next_geometry):
		_notify("当前位置无法使用该能力", 4)
		return
	chapter_flags = proposed
	_build_terrain(next_geometry)
	_save_progress()
	_notify(outcome.message, 6)
	if station == 0: _notify(str(spec.clue) + "\n" + outcome.message, 10)
	if station == 0 and is_instance_valid(environment): environment.play_memory()
	queue_redraw()

func _ready() -> void:
	super._ready()
	if not _is_clear(player.position, _geometry(false)) or not persist_progress:
		load_map(current_map, Maps.spawn(current_map))
	checkpoint_at = Maps.anchor(checkpoint_map, "rest")
	_update_ability_stats()
	player.health = player.maximum_health
	reset_view()
	_save_progress()

func _restart_mythic() -> void:
	var proposed := chapter_flags.duplicate()
	proposed["mythic_" + current_map] = 0
	proposed.erase("echo_" + current_map)
	for i in range(3): proposed.erase("device_%s_%d" % [current_map, i])
	if not _is_clear(player.position, Maps.geometry(current_map, past_era, proposed)):
		_notify("当前位置无法使用该能力", 4)
		return
	chapter_flags = proposed
	journal.close_reader()
	load_map(current_map, Maps.anchor(current_map, "rest"))
	_save_progress()
	_notify("本图机关已复位。剧情、永久能力和战斗奖励保留。", 5)

func ability_available(code: String) -> bool:
	return ABILITIES.has(code) and bool(chapter_flags.get("ability_" + code, false))

func _update_ability_stats() -> void:
	player.maximum_health = 6 if ability_available("QS") else 4
	player.health = mini(player.health, player.maximum_health)

func world_bounds() -> Rect2: return Maps.bounds(current_map)

func _geometry(past: bool) -> Array[Rect2]:
	var result := Maps.geometry(current_map, past, chapter_flags)
	result.append_array(_device_pads())
	return result

func _device_pads() -> Array[Rect2]:
	# 机关置位后的物理后果统一走几何：非升降类补一块落脚台，
	# 这样光路 / 潮位 / 风场 / 音柱 / 根系 / 三灵不需要各写一套特判。
	return Maps.device_pads(current_map, chapter_flags)

func _rebuild_device_geometry() -> void:
	_build_terrain(_geometry(past_era))
	queue_redraw()

func _build_terrain(rectangles: Array[Rect2]) -> void:
	super._build_terrain(rectangles)
	var platforms: Array = Maps.model(current_map, past_era).platforms
	for i in range(rectangles.size()):
		if rectangles[i] in platforms and rectangles[i].size.y <= 16:
			var body := terrain.get_child(i)
			body.set_meta("drop_through", true)
			body.get_child(0).one_way_collision = true
			body.get_child(0).one_way_collision_margin = 4

func load_map(id: String, at := Vector2(-1, -1)) -> void:
	if not Maps.db().regions.has(id):
		# 老存档/老脚本仍可能传 M0x：不要静默早退，直接回落到世界入口。
		push_warning("未知区域 %s，回落到 W01" % id)
		if id == "W01": return
		load_map("W01")
		return
	_clear_requests()
	if journal.visible: journal.close_reader()
	if atlas != null and atlas.visible: atlas.close_map()
	for child in get_children():
		if child is Label:
			remove_child(child)
			child.queue_free()
	if actors != null:
		for child in actors.get_children():
			actors.remove_child(child)
			child.queue_free()
	if is_instance_valid(region_instance):
		remove_child(region_instance)
		region_instance.queue_free()
	guard = null
	region_guard = null
	current_map = id
	boundary_cooldown = 0.65
	boundary_armed = false
	past_era = false
	if at.x < 0: at = Maps.spawn(id)
	camera.limit_left = -10000000
	camera.limit_top = -10000000
	camera.limit_right = 10000000
	camera.limit_bottom = 10000000
	_build_terrain(_geometry(false))
	var landing_geometry := _geometry(false)
	if not _is_clear(at, landing_geometry): at = Maps.anchor(id, "rest")
	# 兜底：落点正好压在竖井开口上时，挪到最近能站住的地方，绝不让玩家一进场就掉下去。
	if not _has_support(at, landing_geometry): at = _nearest_safe_position(at, landing_geometry)
	player.position = at
	player.checkpoint = at
	player.velocity = Vector2.ZERO
	player.attack_remaining = 0
	player.attack_cooldown_remaining = 0
	player.dash_remaining = 0
	if combat != null: combat.clear_action()
	heal_remaining = 0
	region_instance = load("res://game/regions/" + id.to_lower() + ".tscn").instantiate()
	add_child(region_instance)
	environment = load("res://game/mythic_environment.gd").new()
	environment.world = self
	environment.map_id = id
	region_instance.add_child(environment)
	device_bay = load("res://game/map_devices.gd").new()
	device_bay.world = self
	device_bay.map_id = id
	region_instance.add_child(device_bay)
	device_bay.build()
	hazards = load("res://game/map_hazards.gd").new()
	hazards.world = self
	region_instance.add_child(hazards)
	for object in Maps.region(id).structure.pogo_objects:
		var anchor = load("res://game/pogo_anchor.gd").new()
		anchor.world = self
		anchor.style = object.style
		anchor.position = Vector2(object.at[0], object.at[1])
		region_instance.add_child(anchor)
	_build_chapter_signs()
	_spawn_region_enemies()
	_cache_auto_grants()
	chapter_flags["visited_" + id] = true
	chapter_flags["seen_%s_%d" % [id, Maps.room_at(id, at)]] = true
	camera.reset_smoothing()
	reset_view()
	DisplayServer.window_set_title("时间之神 · " + id + " " + Maps.region(id).title)
	_save_progress()
	_notify(Maps.region(id).title + " · " + _objective_text(), 5)
	queue_redraw()

func _build_signs() -> void: _build_chapter_signs()

func _build_chapter_signs() -> void:
	var spec: Dictionary = Maps.region(current_map).get("mythic", {})
	for item in Maps.interactions(current_map):
		if not Maps.era_ok(item, past_era): continue
		if item.id == "rest" or str(item.id).begins_with("ability_"): _world_label(item.name, item.at + Vector2(-36, -88), 15, true)
		elif item.id.begins_with("travel_"): _world_label("贴边 → " + item.id.trim_prefix("travel_"), item.at + Vector2(-20, -58), 13, true)
		elif item.has("device"): _world_label(str(item.name), item.at + Vector2(-34, -84), 13, true)
		elif item.id.begins_with("mythic_"): _world_label("三灵站 " + str(int(item.id.trim_prefix("mythic_")) + 1), item.at + Vector2(-30, -66), 14, true)
	if not spec.is_empty():
		_world_label(str(spec.terrain) + "\n" + {"terrace": "沿阶地跳跃通行", "wind": "风井：按住跳跃乘风上行", "vine": "根梯：按住跳跃攀援上行"}[spec.traversal], Maps.spawn(current_map) + Vector2(-24, -136), 14, true)
	for room in Maps.region(current_map).rooms:
		var r := Maps.rect(room.rect)
		_world_label(room.name, r.position + Vector2(24, 22), 17, true)

func _update_hud(hp: int, maximum: int) -> void:
	if hud == null: return
	var zone := Maps.region(current_map)
	hud.text = "第%d章 %s / %s %s · %s · 生命%d/%d 药%d 魂魄%d 凶骨%d" % [zone.chapter, zone.chapter_name, current_map, zone.title, "过去" if past_era else "未来", hp, maximum, heal_charges, souls, bones]
	if combat != null: hud.text += "  " + combat.display_name() + " 气%d" % combat.state.qi
	if ds_status_icon != null:
		# DS 持有时常驻鳞片图标；说明文字复用红线句单一真源，不另抄一份。
		ds_status_icon.set_tip(ABILITY_USAGE["DS"])
		ds_status_icon.visible = ability_available("DS")

func _objective_text() -> String:
	var zone := Maps.region(current_map)
	# 旧三灵因果锁在 29 区世界里已不存在；只有显式带 steps 的区才走这条提示。
	var spec: Dictionary = zone.get("mythic", {})
	if not spec.is_empty() and spec.has("steps") and not spec.steps.is_empty():
		var progress := Mythic.progress(current_map, chapter_flags)
		if progress < 3:
			if progress == 1: return "%s · 到神兽机关室按E调整实体装置，再抵达站2；Tab看两代因果。" % spec.terrain
			return "%s · %d/3：%s（%s） · Tab切换时间，贴边向外走自动过图" % [spec.terrain, progress, spec.steps[progress].text, "过去" if spec.steps[progress].past else "未来"]
	if str(zone.boss) != "" and not chapter_flags.get("boss_" + current_map, false):
		return "先在灯龛休息，再挑战守印者；胜利后开放下一章主路。"
	return "沿房间网络探索；贴边向外走即可前往相邻区，M 查看房间与世界地图。"

func nearest_interaction() -> Dictionary:
	var items := Maps.interactions(current_map)
	var result := {}
	var best := INF
	# 未取得的能力遗迹优先：三处取得点与叙事物重合或贴得极近
	# （W06 QS 祭台与药簿同点、W09 PA 石龛与塔顶风历差 32px、W12 PW 蹬痕与石工亲笔信差 32px）。
	# 取得前只响应遗迹，取得后自然回落到叙事物（ability-grants.md §6 第 2 条）。
	for item in items:
		if not str(item.id).begins_with("ability_"): continue
		if not Maps.era_ok(item, past_era): continue
		if ability_available(str(item.get("ability", ""))): continue
		if not _grant_gate(item).is_empty(): continue
		var grant_distance: float = player.position.distance_to(item.at)
		if grant_distance <= float(item.radius) and grant_distance < best:
			best = grant_distance
			result = item
	if not result.is_empty(): return result
	for item in items:
		if item.id.begins_with("travel_"): continue
		if not Maps.era_ok(item, past_era): continue
		if str(item.id).begins_with("ability_") and not _grant_gate(item).is_empty(): continue
		var d: float = player.position.distance_to(item.at)
		if d <= float(item.radius) and d < best:
			best = d
			result = item
	if is_instance_valid(environment):
		for item in environment.interactions():
			var distance: float = player.position.distance_to(item.at)
			if distance < best and distance <= float(item.radius):
				best = distance
				result = item
	if soul_drop.get("map", "") == current_map:
		var at := _drop_position()
		if player.position.distance_to(at) <= minf(best, 64): return {"id": "recover_souls", "at": at, "name": "拾回魂魄", "radius": 64}
	return result

func _switch_era() -> void:
	var previous := past_era
	var target := _geometry(not past_era)
	if not _is_clear(player.position, target):
		_notify("当前位置无法使用该能力", 6)
		return
	# Unsupported terrain is a normal fall, not damage or forced relocation.
	past_era = not past_era
	_build_terrain(target)
	if audio != null:
		audio.set_era(past_era)
		audio.play_cue("switch")
	_update_hud(player.health, player.maximum_health)
	queue_redraw()

func gate_reason(edge: Dictionary) -> String:
	var destination := Maps.target(edge, current_map)
	var forward := int(Maps.region(destination).number) > int(Maps.region(current_map).number)
	# 方向判据保留，作用域收窄到 main/chapter：暗区与回环不走宿主区的下劈门。
	if forward and str(edge.kind) in ["main", "chapter"]:
		for hall in Maps.region(current_map).structure.pogo_halls:
			if hall.required and not chapter_flags.get("pogo_%s_%d" % [current_map, int(hall.id)], false): return "先完成双钉纹下劈回环：空中按住S／↓再攻击，借力两次并抵达对岸。"
	# 进度门（FINAL_DOOR / ENDGAME / w25_verdict_sealed）走通用判定，置位方母区可先通行。
	var gate := str(edge.get("gate", ""))
	if not gate.is_empty() and not chapter_flags.get(gate, false) and current_map != str(edge.get("opener", "")):
		return str(GATE_HINTS.get(gate, "此门尚未开启。"))
	if not str(edge.requires).is_empty() and edge.requires != "VC" and not ability_available(edge.requires): return "需要" + str(ABILITIES.get(edge.requires, edge.requires)) + "，可在后续遗迹取得。"
	return ""

func _soul_reward(label: String) -> int:
	# 设计里魂魄数量写在名字里："魂魄×3" / "大魂魄沉淀（200）" / "魂魄沉淀"（默认 3）。
	var digits := ""
	for index in range(label.length()):
		var letter := label[index]
		if letter >= "0" and letter <= "9":
			digits += letter
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else 3

func _spawn_region_enemies() -> void:
	# 按设计 enemies[] 生成：环境档（hp 0）是地形危险，交给 map_hazards；
	# 其余按 tier 折算成 Guard 的命中数（10 hp ≈ 1 次普攻）。
	if actors == null: return
	var rooms: Array = Maps.region(current_map).rooms
	for enemy in Maps.region(current_map).get("enemies", []):
		if str(enemy.get("tier", "")) == "环境": continue
		var hp := int(enemy.get("hp", 45))
		if hp <= 0: continue
		var targets: Array = enemy.get("rooms", [])
		if targets.is_empty(): continue
		var count := clampi(int(enemy.get("count", 1)), 1, 12)
		for index in range(count):
			var flag := "enemy_%s_%s_%d" % [current_map, str(enemy.get("id", "E")), index]
			if chapter_flags.get(flag, false): continue
			var room_name := str(targets[index % targets.size()])
			var room := {}
			for candidate in rooms:
				if str(candidate.id) == room_name: room = candidate
			if room.is_empty(): continue
			var r := Maps.rect(room.rect)
			var floor_y := float(room.get("floor_y", r.end.y))
			var actor := Guard.new()
			actor.position = Vector2(r.position.x + r.size.x * (0.28 + 0.44 * float(index % 3) / 2.0), floor_y - 24)
			actor.player = player
			actor.health = maxi(1, roundi(hp / 10.0))
			actor.maximum_health = actor.health
			actors.add_child(actor)
			actor.defeated.connect(func():
				_set_flag(flag, 20 if hp >= 100 else 8)
				_save_progress())

func _interact(id: String) -> void:
	if id.begins_with("niche_"):
		var key := current_map + "_" + id
		if chapter_flags.get(key, false): _notify("这处旁龛已经收录，遗存不会重复出现。", 3)
		else:
			_set_flag(key, 5)
			_show_entry("旁龛 · 旧路残纹", Maps.region(current_map).mythic.terrain + "的残纹已收录。\n魂魄 +5；剧情与主线能力不依赖旁龛奖励。")
		return
	if id == "view_inscription":
		_set_flag("view_inscription_read")
		_show_entry("井壁刻字", "向下有回声，向侧有归途。裂纹扬尘预告明刺，钉纹可借力；落下之前，先看归路。")
		return
	if id.begins_with("device_"):
		var parts := id.trim_prefix("device_").split("_")
		var device_index := int(parts[0])
		var dial := int(parts[1]) if parts.size() > 1 else 0
		if is_instance_valid(device_bay) and device_index < device_bay.devices.size():
			device_bay.operate(device_index, dial)
		elif is_instance_valid(environment): environment.operate(device_index)
		return
	if id.begins_with("mythic_"):
		_operate_mythic(int(id.trim_prefix("mythic_")))
		return
	if id.begins_with("ability_"):
		_grant_ability(id)
		return
	if id.begins_with("sign_"):
		# 战场提示碑：可反复读，不置旗标、不扣资源（数据驱动自 items[].type == 提示碑）。
		_show_entry("战场提示碑", ABILITY_USAGE["DS"] + "\n" + DS_BATTLE_HINT)
		return
	if id.begins_with("item_"):
		var item_key := "item_" + current_map + "_" + id.trim_prefix("item_")
		if chapter_flags.get(item_key, false):
			_notify("这处遗存已经收录，不会重复出现。", 2)
			return
		var entry := {}
		for item in Maps.interactions(current_map):
			if item.id == id: entry = item
		var label := str(entry.get("name", id))
		var kind := str(entry.get("kind", ""))
		var tail := ""
		match kind:
			"凶骨":
				bones += 1
				_set_flag(item_key)
				tail = "凶骨 +1（当前 %d）。" % bones
			"永久强化":
				# 主线能力由 world_ability 发放；这里的遗存只是记录，不发第二份。
				_set_flag(item_key)
				tail = "已记录。本图主线能力在神权遗迹处取得。"
			"地图残页", "关键道具":
				_set_flag(item_key)
				tail = "已归档。"
			"魂魄":
				var reward := _soul_reward(label)
				_set_flag(item_key, reward)
				tail = "魂魄 +%d。" % reward
			_:
				_set_flag(item_key, 2)
				tail = "魂魄 +2。"
		_show_entry(label, "已调查：%s（%s）。\n%s该遗存不再重复出现。" % [label, str(entry.get("obtain", "调查")), tail])
		return
	if id.begins_with("boss_"):
		if chapter_flags.get("boss_" + current_map, false):
			_show_entry("封印已解除", "本章主路已开放，仍可返回支洞与旧区。")
		elif guard == null: _spawn_region_boss()
		return
	if id.begins_with("travel_") or id in ["market_exit", "river_exit", "next"] or id.begins_with("to_"):
		return
	match id:
		"shortcut":
			_show_entry("灯街侧门", "修复旧灯后，沿地图侧缘通路向外移动即可前往相邻区域。")
		"lift", "lift_top":
			if id == "lift" and past_era: _set_flag("lift")
			if chapter_flags.get("lift", false): _show_entry("鼓索捷径", "旧索已固定，两端均可通行。")
			else: _show_entry("鼓索断裂", "到过去修复旧索。")
		"ladder":
			_show_entry("河沿返程", "沿地图侧缘出口返回寄信井。区域过渡无需按E。")
		"rest":
			_rest()
			_show_entry(Maps.region(current_map).title + " · 灯龛", "生命、补给和探索进度已保存。可在这里调整四凶流派。")
			journal.show_choice("切换基础流派", _choose_next_form)
		"survey": _show_entry(Maps.region(current_map).title + " · 地貌档案", str(Maps.region(current_map).get("note", "")))
		"cache":
			_set_flag("cache_" + current_map, 15)
			_show_entry("支洞遗存", "此处的探索奖励已记录；重复调查不会重复获得魂魄。")
		"world_terrain":
			var code := "DB" if Maps.region(current_map).chapter >= 7 else "DT"
			if not ability_available(code):
				_show_entry("环境封印", "需要" + ABILITIES[code] + "。")
				return
			_set_flag("terrain_" + current_map)
			_build_terrain(_geometry(past_era))
			_notify("标记环境障碍已解除；神龙能力不攻击敌人。", 4)
		"world_boss":
			if chapter_flags.get("boss_" + current_map, false):
				_show_entry("封印已解除", "本章主路已开放，仍可返回支洞和旧区域。")
			elif guard == null: _spawn_region_boss()
		"world_ending":
			if chapter_flags.get("clear_8", false):
				_set_flag("world_complete")
				_show_entry("未删的明日", "八章地图的主路已贯通。所有区域保持可返回。\n\n本版完成世界地图与通路，最终剧情演出仍待制作。")
			else: _show_entry("总钟封印", "先完成此地守印者挑战。")
		_:
			super._interact(id)

func _grant_gate(entry: Dictionary) -> String:
	# 设备前置（ability-grants.md §4.2）：DB 中泉须先完成 D2「三灵协作」全校准。
	# grants 契约不携带 flag，这里从当前区 devices[] 反查「三灵协作」型机关的 flag，
	# 避免把 w21_trinity_3 硬编码进两份代码。未满足时中泉只冒泡、不给能力。
	var code := str(entry.get("ability", ""))
	if code != "DB": return ""
	for raw in Maps.region(current_map).get("devices", []):
		if str(raw.get("type", "")) == "三灵协作":
			var flag := str(raw.get("flag", ""))
			if not flag.is_empty() and not chapter_flags.get(flag, false):
				return "泉眼只冒泡，尚未结冰。先让水轮、风轮、地脉三灵同时归位。"
	return ""

func _grant_ability(id: String) -> void:
	# 取得入口（docs/design/maps/ability-grants.md + data/wXX.json 的 grants）。
	# 代号与文案都由交互自带：一个区可以发两个能力（W06 = P2 + QS），
	# 所以不再读 region.ability（它按契约恒为空）。
	var entry := {}
	for item in Maps.interactions(current_map):
		if item.id == id: entry = item
	if entry.is_empty(): return
	if not Maps.era_ok(entry, past_era):
		_notify("这个时代的遗迹是空的；换一个时代再来。", 4)
		return
	var code := str(entry.get("ability", Maps.region(current_map).ability))
	if not ABILITIES.has(code): return
	var gate := _grant_gate(entry)
	if not gate.is_empty():
		_notify(gate, 4)
		return
	if ability_available(code):
		_show_entry("已取 · " + ABILITIES[code], "这处遗迹已经把它的能力交给你了，不会有第二份。")
		return
	# 与旧版一致的一次性魂魄奖励（_set_flag 自带去重，重复取得不会再给）。
	_set_flag("ability_" + code, 30)
	_update_ability_stats()
	_show_entry("神权重现 · " + ABILITIES[code],
		"%s\n\n遗迹已记录，能力永久保留。\n\n%s" % [str(entry.get("text", "")), str(ABILITY_USAGE.get(code, ""))])

func _spawn_region_boss() -> void:
	checkpoint_map = current_map
	checkpoint_at = Maps.anchor(current_map, "rest")
	player.checkpoint = checkpoint_at
	guard = Guard.new()
	guard.boss = true
	var zone := Maps.region(current_map)
	var arena := Maps.rect(zone.rooms[-1].rect)
	var boss: Variant = zone.get("boss", "")
	if boss is Dictionary:
		for room in zone.rooms:
			if str(room.id) == str(boss.get("room", "")): arena = Maps.rect(room.rect)
	guard.position = Vector2(arena.get_center().x - 64, arena.end.y - 12)
	guard.player = player
	actors.add_child(guard)
	var chapter: int = Maps.region(current_map).chapter
	guard.maximum_health = 240 + (chapter - 1) * 20
	guard.health = guard.maximum_health
	var map := current_map
	guard.defeated.connect(func():
		_set_flag("boss_" + map, 80)
		_set_flag("clear_%d" % chapter)
		guard = null
		_notify("封印已解除：下一章主路开放。", 6))
	_save_progress()

func _rest() -> void:
	checkpoint_map = current_map
	checkpoint_at = Maps.anchor(current_map, "rest")
	player.checkpoint = checkpoint_at
	_update_ability_stats()
	player.health = player.maximum_health
	heal_charges = 3 + int(chapter_flags.get("supply_upgrade", 0))
	player.health_changed.emit(player.health, player.maximum_health)
	if combat != null: combat.reset_fight()
	if audio != null: audio.play_cue("rest")
	_save_progress()

func _spawn_guard(is_boss: bool, at: Vector2, flag: String) -> void:
	var marker := "boss" if is_boss else ("head" if flag == "head_dead" else "bone")
	var anchor_at := Maps.anchor(current_map, marker)
	var r := Maps.rect(Maps.region(current_map).rooms[Maps.room_at(current_map, anchor_at)].rect)
	super._spawn_guard(is_boss, Vector2(r.get_center().x - 64, r.end.y - 12), flag)

func guard_bounds(at: Vector2) -> Vector2:
	var r := Maps.rect(Maps.region(current_map).rooms[Maps.room_at(current_map, at)].rect)
	return Vector2(r.position.x + 24, r.end.x - 24)

func _show_journal() -> void:
	var zone := Maps.region(current_map)
	var text := _objective_text() + "\n\n当前：第%d章 %s / %s %s（世界序 %d/%d）\n" % [
		zone.chapter, zone.chapter_name, current_map, zone.title, zone.number, Maps.db().regions.size()]
	text += "\n出口 %d 条：\n" % Maps.connections(current_map).size()
	for edge in Maps.connections(current_map):
		var peer := Maps.target(edge, current_map)
		var reason := gate_reason(edge)
		text += "  %s → %s %s（%s）%s\n" % [edge.id, peer, Maps.region(peer).title, edge.kind,
			"  " + reason if not reason.is_empty() else ""]
	text += "\n已获神权：\n"
	for code in ABILITIES:
		text += ("● " if ability_available(code) else "○ ") + ABILITIES[code] + "\n"
	text += "\nM 可切换区域图与世界图；贴边向外走即可过图，门口不需要按 E。"
	_show_entry("世界探索日志", text)

func _draw() -> void:
	var zone := Maps.region(current_map)
	var model := Maps.model(current_map, past_era)
	var tint := Color(zone.color)
	var area := world_bounds()
	# 天空（房间与井道空腔）与地形色统一取 world.gd 的单一来源：角色墨色阶的
	# 3.80:1 按 SKY_NOW 量得，旧的 zone 色填充（#587C81）会让提亮后的袍身只剩 1.06:1。
	var sky := sky_color()
	draw_rect(area, TERRAIN)
	for r in model.free:
		draw_rect(r, sky)
	for room in zone.rooms:
		var r := Maps.rect(room.rect)
		for x in range(int(r.position.x) + 24, int(r.end.x), 96):
			draw_line(Vector2(x, r.position.y + 64), Vector2(x, r.end.y - 16), Color(tint, 0.24), 5)
		draw_line(r.position, Vector2(r.end.x, r.position.y), tint.lightened(0.35), 3)
	for line in model.outline: draw_line(line[0], line[1], tint.lightened(0.22), 2)
	for platform in model.platforms:
		draw_rect(platform, Color("263638"))
		draw_line(platform.position, Vector2(platform.end.x, platform.position.y), Color("b9bea1"), 2)
	if zone.has("mythic"):
		for shaft in model.stairs:
			var style: String = shaft.traversal
			var cable: bool = shaft.get("depth_cue", "") == "cable"
			if not shaft.assisted and not cable: continue
			if style == "terrace" and not cable: continue
			var deep: bool = shaft.tier in ["R4", "R5", "D4", "D5"]
			var center: float = float(shaft.center) + float(shaft.get("assist_offset", 96 if deep else (-116 if style == "wall" else -32)))
			var a := Vector2(center, float(shaft.top))
			var b := Vector2(center, float(shaft.bottom))
			if cable and not shaft.assisted:
				draw_line(a, b, Color("89918c"), 3)
				for y in range(int(shaft.top), int(shaft.bottom), 48):
					for x in range(-30, 31, 12):
						draw_line(Vector2(center + x, y), Vector2(center + x + 5, y), Color("89918c"), 1)
				continue
			draw_line(a, b, Color("70ae91") if style == "vine" else Color("96cfd7"), 6)
			for y in range(int(shaft.top), int(shaft.bottom), 48):
				var at := Vector2(center, y)
				if style == "vine": draw_line(at - Vector2(40, 0), at + Vector2(40, 0), Color("70ae91"), 4)
				else:
					draw_line(at + Vector2(-12, 10), at, Color("96cfd7"), 2)
					draw_line(at, at + Vector2(12, 10), Color("96cfd7"), 2)
		for barrier in Mythic.barriers(zone, model, past_era, chapter_flags):
			draw_rect(barrier, {"sluice": Color("477f9b"), "wind": Color("a6d6dc"), "root": Color("679369"), "gear": Color("a08558"), "light": Color("e6d28b"), "tide": Color("456a9e"), "echo": Color("a49ac5"), "triad": Color("cfb494")}[zone.mythic.family])
	if current_map == "W01" and past_era: draw_rect(model.bridge, Color("b8a27d"))
	if int(zone.get("layout_version", 6)) < 7 and not past_era:
		var last := Maps.rect(zone.rooms[-1].rect)
		var floor_y := float(zone.rooms[-1].get("floor_y", last.end.y))
		draw_rect(Rect2(last.get_center().x - 16, floor_y - 64, 32, 64), Color("715943"))
	for item in Maps.interactions(current_map):
		# 只画当前时代存在的交互：能力取得点在过去态/现在态互斥。
		if not Maps.era_ok(item, past_era): continue
		var at: Vector2 = item.at
		if item.id == "rest":
			draw_rect(Rect2(at - Vector2(10, 38), Vector2(20, 58)), Color("344747"))
			draw_circle(at - Vector2(0, 24), 8, Color("edcd87"))
		elif item.id.begins_with("travel_"):
			draw_rect(Rect2(at - Vector2(15, 40), Vector2(30, 60)), Color("243740"))
			draw_arc(at - Vector2(0, 30), 13, PI, TAU, 16, Color("c9ceaf"), 3)
		elif str(item.id).begins_with("ability_"):
			# 已取得画空心圈，未取得画实心圈：不靠文案也能看出还能不能取。
			var taken := ability_available(str(item.get("ability", "")))
			if taken: draw_circle(at - Vector2(0, 8), 14, Color("3d4c46"), false, 3)
			else: draw_circle(at - Vector2(0, 8), 14, Color("c8d9c2"))
		elif item.id == "view_inscription":
			for k in range(4): draw_line(at + Vector2(-10, -40 - k * 8), at + Vector2(12, -45 - k * 8), Color("bde0ce"), 2)
		elif item.id.begins_with("sign_"):
			# 战场提示碑：竖长盐晶碑，地面锚定（at 取 floor_y - 40，碑底落到地面）。
			var sign_base := at + Vector2(0, 40)
			var sign_body := Rect2(sign_base + Vector2(-12, -72), Vector2(24, 72))
			draw_rect(sign_body, Color("c9b99a"))
			draw_line(sign_body.position, Vector2(sign_body.end.x, sign_body.position.y), Color("ecce9a"), 2)
			for k in range(3):
				draw_line(Vector2(sign_body.position.x + 5, sign_body.position.y + 20 + k * 15), Vector2(sign_body.end.x - 5, sign_body.position.y + 20 + k * 15), Color("13110f"), 2)
			draw_arc(Vector2(sign_body.get_center().x, sign_body.position.y + 4), 5, PI, TAU, 12, Color("e0a040"), 2)
		elif item.id.begins_with("mythic_"):
			var index: int = int(item.id.trim_prefix("mythic_"))
			var beast: String = zone.mythic.steps[index].beast
			var color: Color = {"dragon": Color("6fc6d1"), "phoenix": Color("e4a36d"), "qilin": Color("98bd86")}[beast]
			var p := at - Vector2(0, 14)
			draw_circle(p, 14, color, false, 3)
			if beast == "dragon": draw_polyline(PackedVector2Array([p+Vector2(-8,6),p+Vector2(6,0),p+Vector2(-6,-8),p+Vector2(8,-12)]), color, 3)
			elif beast == "phoenix":
				draw_line(p, p+Vector2(-22,-15), color, 3)
				draw_line(p, p+Vector2(22,-15), color, 3)
			else:
				draw_line(p+Vector2(-6,-10), p+Vector2(-10,-23), color, 3)
				draw_line(p+Vector2(6,-10), p+Vector2(10,-23), color, 3)
			if Mythic.progress(current_map, chapter_flags) > index: draw_circle(p, 5, Color("fff2c4"))
		elif item.id in ["ferryman", "white", "witness", "cloth", "rice", "salt", "ending"]: _draw_ferryman(at + Vector2(0, 20), Color("304545"))
		else: _draw_marker(at - Vector2(0, 10))
	if player != null and player.is_attacking():
		if player.attack_down: draw_arc(player.position, 38, 0.3, PI - 0.3, 18, Color("ead19b"), 4)
		else: draw_arc(player.position, 38, -1.1 if player.facing > 0 else PI - 1.1, 1.1 if player.facing > 0 else PI + 1.1, 18, Color("ead19b"), 4)
	_draw_drop()

