extends SceneTree
## 29 区世界验收：29 区逐个进场 / 36 边逐条来回 / 出生点与落点不卡墙 / 大地图锚点。
## 运行：godot --headless --path . --script tests/test_world_29.gd

const Maps := preload("res://game/world_data.gd")

var world: Node2D
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func body_clear(point: Vector2, rects: Array, bounds: Rect2) -> bool:
	var body := Rect2(point - Vector2(11.7, 19.7), Vector2(23.4, 39.4))
	if body.position.x < bounds.position.x or body.end.x > bounds.end.x: return false
	if body.position.y < bounds.position.y or body.end.y > bounds.end.y: return false
	for rect in rects:
		if body.intersects(rect): return false
	return true

func supported(point: Vector2, rects: Array, bounds: Rect2) -> bool:
	var body := Rect2(point - Vector2(11.7, 19.7), Vector2(23.4, 39.4))
	for rect in rects:
		if rect.position.y < body.end.y - 1: continue
		if rect.position.y > body.end.y + 64: continue
		if point.x < rect.position.x + 8 or point.x > rect.end.x - 8: continue
		return true
	return false

func run() -> void:
	world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.player.set_physics_process(false)

	var db := Maps.db()
	check(int(db.version) == 7, "version == 7 (实际 %s)" % str(db.version))
	check(Maps.LAYOUT_VERSION == 7, "LAYOUT_VERSION == 7")
	check(db.regions.size() == 29, "29 个区（实际 %d）" % db.regions.size())
	check(db.edges.size() == 36, "36 条边（实际 %d）" % db.edges.size())

	var rooms := 0
	var quota := {}
	var dark: Array[String] = []
	var bosses: Array[String] = []
	for id in db.regions:
		var zone := Maps.region(id)
		rooms += zone.rooms.size()
		quota[int(zone.chapter)] = int(quota.get(int(zone.chapter), 0)) + 1
		check(int(zone.layout_version) == 7, id + " layout_version 7")
		check(int(zone.bounds[0]) == 0 and int(zone.bounds[1]) == 0, id + " bounds 原点为 0")
		check(int(zone.bounds[2]) > 0 and int(zone.bounds[3]) > 0, id + " bounds 尺寸为正")
		check(zone.structure.connections.size() == zone.links.size(), id + " connections 与 links 等长")
		for index in range(zone.links.size()):
			check(int(zone.structure.connections[index].link) == index, "%s connections[%d].link 对齐" % [id, index])
		if zone.checkpoint == null: dark.append(id)
		if str(zone.boss) != "": bosses.append(id)
	check(rooms == 320, "320 个房间（实际 %d）" % rooms)
	check(dark.size() == 4, "4 个暗区（实际 %s）" % str(dark))
	check(bosses.size() == 8, "8 个 Boss 区（实际 %s）" % str(bosses))
	var expected_quota := {1: 5, 2: 3, 3: 4, 4: 3, 5: 4, 6: 3, 7: 3, 8: 4}
	for chapter in expected_quota:
		check(int(quota.get(chapter, 0)) == expected_quota[chapter], "第%d章区数 %d" % [chapter, expected_quota[chapter]])

	# 世界序必须严格递增，暗区紧随宿主区
	var previous := 0
	for id in db.regions:
		var number := int(Maps.region(id).number)
		check(number == previous + 1, "%s number 连续（%d）" % [id, number])
		previous = number

	# 逐区进场：出生点与每个门廊落点都必须站得住
	for id in db.regions:
		var zone := Maps.region(id)
		var bounds := Maps.bounds(id)
		var geometry := Maps.geometry(id, false, {})
		check(geometry.size() > 0, id + " 现在态几何非空")
		var spawn := Maps.spawn(id)
		check(bounds.has_point(spawn), id + " 出生点在 bounds 内")
		check(body_clear(spawn, geometry, bounds), "%s 出生点不卡墙 %s" % [id, str(spawn)])
		check(supported(spawn, geometry, bounds), "%s 出生点脚下有地 %s" % [id, str(spawn)])
		world.load_map(id)
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		check(world.current_map == id, id + " load_map 成功")
		check(body_clear(world.player.position, geometry, bounds), id + " 进场落点不卡墙")
		var model := Maps.model(id)
		check(model.walls.size() > 0, id + " 墙体栅格非空")
		check(model.collision.size() > 0, id + " 碰撞体非空")
		# 房间图连通：links 必须把 20 个房连成一棵树/网
		var seen := {}
		var queue: Array[int] = [0]
		seen[0] = true
		while not queue.is_empty():
			var index: int = queue.pop_back()
			for link in zone.links:
				var pair: Array = link
				for side in [pair[0], pair[1]]:
					if not seen.has(int(side)) and (int(pair[0]) == index or int(pair[1]) == index):
						seen[int(side)] = true
						queue.append(int(side))
		check(seen.size() == zone.rooms.size(), "%s 房间全连通（%d/%d）" % [id, seen.size(), zone.rooms.size()])
		# 灯龛
		var rests := 0
		for item in Maps.interactions(id):
			if item.id == "rest": rests += 1
		check(rests == (0 if zone.checkpoint == null else 1), "%s 灯龛数量符合暗区规则" % id)
		# Boss 交互点
		var boss_points := 0
		for item in Maps.interactions(id):
			if str(item.id).begins_with("boss_"): boss_points += 1
		check(boss_points == (1 if str(zone.boss) != "" else 0), "%s Boss 交互点符合" % id)

	# --- 能力取得入口（design/maps/ability-grants.md · grants 契约 v1.4）---
	# 每条 interaction 的 room 索引都必须指向真正装着它的那间房，at 也必须落在房内：
	# 取得点是玩家要走过去站住的地方，画布外的浮点在游戏里永远取不到。
	var grant_points := 0
	var grant_regions: Array[String] = []
	var grant_codes: Array[String] = []
	for id in db.regions:
		var zone := Maps.region(id)
		for item in Maps.interactions(id):
			var room := Maps.rect(zone.rooms[int(item.room)].rect)
			# travel_* 的 at 是贴墙门位，正好压在房 rect 的边上（has_point 半开区间会判它在房外），
			# 门位正确性由下面的"门廊与落点"段单独校验；这里只校非旅行交互。
			if not str(item.id).begins_with("travel_"):
				check(room.has_point(item.at), "%s %s 的 at %s 落在 room %d 内" % [id, item.id, str(item.at), int(item.room)])
				check(Maps.room_at(id, item.at) == int(item.room), "%s %s 的 room 索引指向所在房" % [id, item.id])
			if not str(item.id).begins_with("ability_"): continue
			grant_points += 1
			if not grant_regions.has(id): grant_regions.append(id)
			var code := str(item.get("ability", ""))
			if not grant_codes.has(code): grant_codes.append(code)
			check(str(item.name) != "", "%s %s 有交互名" % [id, item.id])
			check(str(item.get("era", "")) in ["past", "present", "both"], "%s %s era 合法（%s）" % [id, item.id, str(item.get("era", ""))])
			check(float(item.radius) >= 40.0 and float(item.radius) <= 64.0, "%s %s radius 40—64" % [id, item.id])
			check(str(item.get("text", "")) != "", "%s %s 带取得文案" % [id, item.id])
	check(grant_points == 9, "9 条能力取得点（实际 %d）" % grant_points)
	check(grant_regions.size() == 8, "取得点分布在 8 区（实际 %d）%s" % [grant_regions.size(), str(grant_regions)])
	check(grant_codes.size() == 9, "9 个能力代号（实际 %d）%s" % [grant_codes.size(), str(grant_codes)])
	# auto（触碰即取）只属于 PW，且全表恰好 1 条带这个键
	var auto_grants := 0
	var auto_codes: Array[String] = []
	for id in db.regions:
		for item in Maps.interactions(id):
			if not str(item.id).begins_with("ability_"): continue
			if bool(item.get("auto", false)):
				auto_grants += 1
				auto_codes.append(str(item.get("ability", "")))
	check(auto_grants == 1, "能力取得点里恰好 1 条 auto（实际 %d）" % auto_grants)
	check(auto_codes == ["PW"], "auto 只属于 PW（实际 %s）" % str(auto_codes))
	# region.ability 恒为空：W06 同时发 P2 与 QS，标量字段承载不了，代号只在交互里
	for id in db.regions:
		check(str(Maps.region(id).ability) == "", id + " region.ability 为空")
	# W01：VC 取得点与 I-01「VC 时间切换」完全同点 → 取得点优先，不再生成 item_I01
	var w01_items: Array[String] = []
	for item in Maps.interactions("W01"):
		if str(item.id).begins_with("item_"): w01_items.append(str(item.id))
	check(not w01_items.has("item_I01"), "W01 不再有与 VC 取得点重复的道具交互（实际 %s）" % str(w01_items))
	check(w01_items.has("item_I03"), "W01 的叙事物 I-03 刻漏残铭仍然保留")
	# 取得点半径内的其余叙事物一条都不能删
	check(Maps.interactions("W06").any(func(i): return i.id == "item_I02"), "W06 角闻医舍·药簿保留")
	check(Maps.interactions("W09").any(func(i): return i.id == "item_I04"), "W09 塔顶风历保留")
	check(Maps.interactions("W12").any(func(i): return i.id == "item_I02"), "W12 石工亲笔信保留")

	# 36 条边逐条来回：两侧 travel_* 存在、落点站得住、大地图锚点不是 spawn 兜底
	var shared := 0
	var loops := 0
	for edge in db.edges:
		var a := str(edge.a)
		var b := str(edge.b)
		if str(edge.kind) == "loop": loops += 1
		else: shared += 1
		var at_a := Maps.anchor(a, "travel_" + b)
		var at_b := Maps.anchor(b, "travel_" + a)
		check(at_a != Maps.spawn(a), "%s 在 %s 侧有 travel_%s 交互" % [str(edge.id), a, b])
		check(at_b != Maps.spawn(b), "%s 在 %s 侧有 travel_%s 交互" % [str(edge.id), b, a])
		# 走真实转场路径：load_map 会兜底把落点挪到能站住的地方
		world.load_map(b, Maps.entry(b, a))
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		var bounds_b := Maps.bounds(b)
		var geometry_b := Maps.geometry(b, false, {})
		check(world.current_map == b, "%s 正向可进入 %s" % [str(edge.id), b])
		check(body_clear(world.player.position, geometry_b, bounds_b), "%s 正向落点不卡墙 %s -> %s" % [str(edge.id), a, b])
		check(supported(world.player.position, geometry_b, bounds_b), "%s 正向落点有地 %s -> %s" % [str(edge.id), a, b])
		world.load_map(a, Maps.entry(a, b))
		for actor in world.actors.get_children(): actor.set_physics_process(false)
		var bounds_a := Maps.bounds(a)
		var geometry_a := Maps.geometry(a, false, {})
		check(world.current_map == a, "%s 反向可进入 %s" % [str(edge.id), a])
		check(body_clear(world.player.position, geometry_a, bounds_a), "%s 反向落点不卡墙 %s -> %s" % [str(edge.id), b, a])
		check(supported(world.player.position, geometry_a, bounds_a), "%s 反向落点有地 %s -> %s" % [str(edge.id), b, a])
	check(shared == 29, "29 条共边（实际 %d）" % shared)
	check(loops == 7, "7 条跨空回环（实际 %d）" % loops)

	# 门廊：每条 travel_* 都要有可触发的整条门廊
	for id in db.regions:
		for item in Maps.interactions(id):
			if not str(item.id).begins_with("travel_"): continue
			check(item.has("porch") and item.has("landing"), "%s %s 带门廊与落点" % [id, item.id])
			check(str(item.get("edge", "")) != "", "%s %s 指向 edge id" % [id, item.id])
			var porch := Maps.boundary(item)
			check(porch.size.x >= 48 and porch.size.y >= 48, "%s %s 门廊尺寸 %s" % [id, item.id, str(porch.size)])

	# 进度门：置位方母区可进，对侧锁死并给出提示
	for edge in db.edges:
		if str(edge.get("gate", "")) == "": continue
		var opener := str(edge.opener)
		check(opener != "", "%s 进度门有置位方" % str(edge.id))
		var other := str(edge.a) if opener == str(edge.b) else str(edge.b)
		world.load_map(other)
		check(not world.gate_reason(edge).is_empty(), "%s 从 %s 侧锁死" % [str(edge.id), other])

	# --- 任务2：入口去 M01 化 + 惰性载荷落地 ---
	world.load_map("M05")
	check(world.current_map == "W01", "旧 M 区号回落到 W01（实际 %s）" % world.current_map)

	var spawn_total := 0
	for id in db.regions:
		var want := 0
		for enemy in Maps.region(id).get("enemies", []):
			if str(enemy.get("tier", "")) == "环境": continue
			if int(enemy.get("hp", 0)) <= 0: continue
			if Array(enemy.get("rooms", [])).is_empty(): continue
			want += clampi(int(enemy.get("count", 1)), 1, 12)
		spawn_total += want
		world.load_map(id)
		check(world.actors.get_child_count() == want, "%s 敌人数 %d（实际 %d）" % [id, want, world.actors.get_child_count()])
		for actor in world.actors.get_children(): actor.set_physics_process(false)
	check(spawn_total == 293, "非环境敌人共 293（实际 %d）" % spawn_total)

	# 遗存放量：首次给产出、二次不再给
	world.load_map("W02")
	var item_ids: Array = []
	for item in Maps.interactions("W02"):
		if str(item.id).begins_with("item_"): item_ids.append(item.id)
	check(item_ids.size() > 0, "W02 有遗存交互")
	var souls_before: int = world.souls
	var bones_before: int = world.bones
	for item_id in item_ids: world._interact(item_id)
	check(world.souls > souls_before or world.bones > bones_before, "W02 遗存有产出（魂魄 %d→%d / 凶骨 %d→%d）" % [souls_before, world.souls, bones_before, world.bones])
	var souls_once: int = world.souls
	var bones_once: int = world.bones
	for item_id in item_ids: world._interact(item_id)
	check(world.souls == souls_once and world.bones == bones_once, "遗存不可重复领取")

	# --- 任务3：机关（devices[]） ---
	var device_total := 0
	for id in db.regions:
		var zone := Maps.region(id)
		var expected_points := 0
		for device in zone.get("devices", []):
			device_total += 1
			expected_points += maxi(1, Maps.device_targets(device).size())
		var points := 0
		for item in Maps.interactions(id):
			if item.has("device"): points += 1
		check(points == expected_points, "%s 机关交互点 %d（实际 %d）" % [id, expected_points, points])
	check(device_total == 58, "机关共 58（实际 %d）" % device_total)

	# 升降平台必须真的动（W02 不在下面的解谜抽检清单里）
	world.load_map("W02")
	var lift := -1
	for index in range(world.device_bay.devices.size()):
		if str(world.device_bay.devices[index].type) == "升降平台": lift = index
	check(lift >= 0, "W02 有升降平台")
	if lift >= 0:
		var before: float = world.device_bay.lift_height(lift)
		var guard := 0
		while int(world.device_bay.devices[lift].state[0]) != int(world.device_bay.devices[lift].targets[0]) and guard < 16:
			world.device_bay.operate(lift, 0)
			guard += 1
		# operate 会打开日志面板，面板会暂停整棵树；关掉面板物理才会推进。
		world.journal.close_reader()
		for frame in range(140):
			await physics_frame
		var after: float = world.device_bay.lift_height(lift)
		check(after - before > 60.0, "升降平台真的升起（%.0f → %.0f）" % [before, after])

	var solved_devices := 0
	for id in ["W01", "W03", "W09", "W12", "W20", "W23"]:
		world.load_map(id)
		for index in range(world.device_bay.devices.size()):
			var entry: Dictionary = world.device_bay.devices[index]
			if bool(entry.passive): continue
			var flag := str(entry.flag)
			if not bool(entry.solved):
				check(not world.chapter_flags.get(flag, false), "%s 机关 %d 初始未置位" % [id, index])
			for dial in range(entry.targets.size()):
				var turns := 0
				while int(entry.state[dial]) != int(entry.targets[dial]) and turns <= int(entry.span) + 1:
					world.device_bay.operate(index, dial)
					turns += 1
			check(bool(entry.solved), "%s 机关 %d 可调到目标档位" % [id, index])
			check(world.chapter_flags.get(flag, false), "%s 机关 %d 置位 %s" % [id, index, flag])
			solved_devices += 1
	check(solved_devices >= 8, "抽检解开的机关 %d 个" % solved_devices)

	# 大地图：29 区 + 36 条连线端点都要落在 travel_* 上，不能崩
	world.load_map("W02")
	world.atlas.open_map()
	world.atlas.overview = true
	world.atlas.refresh()
	await process_frame
	await process_frame
	world.atlas.overview = false
	world.atlas.refresh()
	await process_frame
	world.atlas.close_map()
	check(not world.atlas.visible, "大地图可开可关")

	# --- M4 两态几何 ---
	for id in db.regions:
		var past_model := Maps.model(id, true)
		var now_model := Maps.model(id, false)
		check(past_model.collision.size() > 0 and now_model.collision.size() > 0, "%s 两态都有几何" % id)
		var spawn_at := Maps.spawn(id)
		check(body_clear(spawn_at, Maps.geometry(id, true, {}), Maps.bounds(id)), "%s 过去态出生点不卡墙" % id)
		check(supported(spawn_at, Maps.geometry(id, true, {}), Maps.bounds(id)), "%s 过去态出生点有地" % id)
	check(Maps.model("W01", true).free.size() != Maps.model("W01", false).free.size(), "W01 两态自由空间不同（断桥只在过去）")
	var area_now := 0.0
	for wall in Maps.model("W23", false).walls: area_now += wall.size.x * wall.size.y
	var area_past := 0.0
	for wall in Maps.model("W23", true).walls: area_past += wall.size.x * wall.size.y
	check(area_now > area_past, "W23 现在态实心面积更大（%.0f > %.0f）" % [area_now, area_past])
	var sealed := 0
	for room in Maps.region("W23").rooms:
		if str(room.era) != "past": continue
		var centre := Maps.rect(room.rect).get_center()
		check(not body_clear(centre, Maps.model("W23", false).collision, Maps.bounds("W23")), "W23 %s 现在态封死" % str(room.id))
		check(body_clear(centre, Maps.model("W23", true).collision, Maps.bounds("W23")), "W23 %s 过去态开放" % str(room.id))
		sealed += 1
	check(sealed == 8, "W23 八门景室 8 间只在过去（实际 %d）" % sealed)

	world.load_map("W01")
	world.player.health = world.player.maximum_health
	world._switch_era()
	check(world.past_era, "W01 可切到过去")
	world._switch_era()
	check(not world.past_era, "W01 可切回现在")

	# 世界入口必须能进：W01 出生房站得住
	world.load_map("W01")
	check(world.current_map == "W01", "世界入口 W01 可加载")
	check(world.player.position.y > Maps.rect(Maps.region("W01").rooms[0].rect).position.y, "W01 出生点在地面高度以下")

	print("WORLD29 REGIONS=%d ROOMS=%d EDGES=%d CHECKS=%d FAILURES=%d" % [
		db.regions.size(), rooms, db.edges.size(), checks, failures])
	quit(0 if failures == 0 else 1)
