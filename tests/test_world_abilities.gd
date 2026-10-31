extends SceneTree
## 29 区能力取得入口验收：取得 / 时代锁定 / 门真的开 / 主线无循环门。
## 权威清单：docs/design/maps/ability-grants.md（9 条 / 8 区）；
## 运行时入口：game/data/world_regions.json 的 interactions[id = ability_<CODE>]。
## 运行：godot --headless --path . --script tests/test_world_abilities.gd

const Maps := preload("res://game/world_data.gd")

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)

func _initialize() -> void: call_deferred("run")

# --- 数据取景 -------------------------------------------------------------

func grants() -> Array:
	# 不硬编码清单：从运行时数据反读，转换器一旦漏条目本测试即失败。
	var result: Array = []
	for id in Maps.db().regions:
		for item in Maps.interactions(id):
			if not str(item.id).begins_with("ability_"): continue
			result.append({
				"map": id, "id": str(item.id), "code": str(item.get("ability", "")),
				"at": item.at, "era": str(item.get("era", "both")),
				"text": str(item.get("text", "")), "name": str(item.name),
			})
	return result

func grant_for(code: String) -> Dictionary:
	for grant in grants():
		if grant.code == code: return grant
	return {}

func grants_of(map_id: String) -> Array:
	return grants().filter(func(g): return g.map == map_id)

func codes() -> Array:
	var result: Array = []
	for grant in grants():
		if not result.has(grant.code): result.append(grant.code)
	return result

func source_of(edge: Dictionary) -> String:
	# 跨空回环（loop）是拿到能力后往回抄近路，源区是后一个；其余是前一个。
	var a := Maps.region(str(edge.a))
	var b := Maps.region(str(edge.b))
	var earlier := str(edge.a) if int(a.number) < int(b.number) else str(edge.b)
	var later := str(edge.b) if earlier == str(edge.a) else str(edge.a)
	return later if str(edge.kind) == "loop" else earlier

func era_flag(era: String, past: bool) -> bool:
	if era == "both": return true
	return era == ("past" if past else "present")

func _unlock_grant_prereqs(world: Node2D, grant: Dictionary) -> void:
	# DB 中泉前置：D2「三灵协作」（w21_trinity_3）须先置位，否则交互提示不出现。
	if str(grant.get("code", "")) == "DB":
		world.chapter_flags["w21_trinity_3"] = true

# --- 主流程 ---------------------------------------------------------------

func run() -> void:
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	var player = world.player

	# ---- 阶段 0：移动侧能力仍然只认旗标（原有断言保留） ----
	world.load_map("W01")
	var arena := Maps.rect(Maps.region("W01").rooms[-1].rect)
	var ground := Vector2(arena.position.x + 100, arena.end.y - 20)
	player.position = ground
	for frame in range(4): await physics_frame
	player.jump_buffer.press(player.jump_buffer_window)
	for frame in range(8): await physics_frame
	var rising: float = player.velocity.y
	player.jump_buffer.press(player.jump_buffer_window)
	for frame in range(2): await physics_frame
	check(player.velocity.y >= rising, "no unearned double jump")
	player.jump_buffer.clear()
	player.position = ground
	player.velocity = Vector2.ZERO
	world.chapter_flags.ability_P2 = true
	for frame in range(4): await physics_frame
	player.jump_buffer.press(player.jump_buffer_window)
	for frame in range(8): await physics_frame
	rising = player.velocity.y
	player.jump_buffer.press(player.jump_buffer_window)
	for frame in range(2): await physics_frame
	check(player.velocity.y < rising - 50, "unlocked double jump affects real motion")
	player.position = ground - Vector2(0, 100)
	player.velocity = Vector2.ZERO
	player.dash_ready = true
	world.chapter_flags.ability_PA = true
	player.dash_buffer.press(player.dash_buffer_window)
	for frame in range(2): await physics_frame
	check(player.dash_remaining > 0 and absf(player.velocity.x) > 400, "unlocked air dash affects real motion")
	player.dash_remaining = 0
	player.position = Vector2(arena.position.x + 12, arena.end.y - 110)
	player.velocity = Vector2.ZERO
	world.chapter_flags.ability_PW = true
	world.chapter_flags.ability_P2 = false
	Input.action_press("move_left")
	for frame in range(4): await physics_frame
	player.jump_buffer.press(player.jump_buffer_window)
	for frame in range(2): await physics_frame
	check(player.velocity.x > 0 and player.velocity.y < 0, "unlocked wall jump pushes away from real wall")
	Input.action_release("move_left")
	player._wall_push_left = 0
	player.position = ground - Vector2(0, 120)
	player.velocity = Vector2(0, 350)
	world.chapter_flags.ability_PG = true
	Input.action_press("jump")
	for frame in range(3): await physics_frame
	check(player.velocity.y <= 65, "hold jump glides after unlock")
	Input.action_release("jump")

	# ---- 阶段 1：取得入口存在且唯一（9 条 / 8 区） ----
	var points := grants()
	check(points.size() == 9, "运行时 9 条能力取得点（实际 %d）" % points.size())
	var regions := {}
	for grant in points: regions[grant.map] = true
	check(regions.size() == 8, "9 条取得点分布在 8 区（实际 %d）" % regions.size())
	check(codes().size() == 9, "9 个不同能力代号（实际 %d）" % codes().size())

	# ---- 阶段 2：时代锁定（P2/PA/DS/DT 只在过去，QS/PG 只在现在，VC/PW/DB 两态都在） ----
	for grant in points:
		world.chapter_flags.clear()
		world.load_map(grant.map)
		_unlock_grant_prereqs(world, grant)
		world.journal.close_reader()
		player.position = grant.at
		# 错的那一态：nearest_interaction 不得返回该取得点
		world.past_era = (grant.era != "past")
		if grant.era != "both":
			var blocked: Dictionary = world.nearest_interaction()
			check(str(blocked.get("id", "")) != grant.id,
				"%s %s 在%s态调不到（实际 %s）" % [grant.map, grant.code, "过去" if world.past_era else "现在", str(blocked.get("id", "无"))])
		for era_is_past in [false, true]:
			if not era_flag(grant.era, era_is_past): continue
			world.past_era = era_is_past
			var found: Dictionary = world.nearest_interaction()
			check(str(found.get("id", "")) == grant.id,
				"%s %s 在%s态可交互（实际 %s）" % [grant.map, grant.code, "过去" if era_is_past else "现在", str(found.get("id", "无"))])

	# ---- 阶段 2.5：auto（触碰即取）只属于 PW，且不按键即发放 ----
	# PW 井壁蹬痕：进入 radius 即取得，不弹面板、不需按 E（ability-grants.md §2.5）。
	var auto_count := 0
	for grant in points:
		# 运行时交互带 auto 键才算触碰即取；其余 8 条必须没有这个键。
		var raw := {}
		for item in Maps.interactions(grant.map):
			if str(item.id) == grant.id: raw = item
		if bool(raw.get("auto", false)):
			auto_count += 1
			check(grant.code == "PW", "auto 只出现在 PW（实际 %s）" % grant.code)
	check(auto_count == 1, "9 条取得点里恰好 1 条 auto（实际 %d）" % auto_count)
	world.chapter_flags.clear()
	world.load_map("W12")
	world.journal.close_reader()
	var pw := grant_for("PW")
	player.position = pw.at - Vector2(0, 20)  # 站进 radius 内
	world.past_era = (pw.era == "past")
	check(not world.ability_available("PW"), "PW 触碰前未取得")
	# 不调用 interact_nearby / _interact，直接推进物理帧，让 _check_auto_grants 自动发放
	for frame in range(4): await physics_frame
	check(world.ability_available("PW"), "PW 触碰即取（不按键）")
	world.journal.close_reader()

	# ---- 阶段 2.6：DB 中泉受 D2 三灵协作（w21_trinity_3）前置 ----
	# 未置 flag 时中泉只冒泡、不给能力（ability-grants.md §3.9 / §4.2）：
	# nearest_interaction 不返回 ability_DB，_grant_ability 也拒绝发放。
	world.chapter_flags.clear()
	world.load_map("W21")
	world.journal.close_reader()
	var db := grant_for("DB")
	player.position = db.at
	world.past_era = false  # era: both
	check(str(world.nearest_interaction().get("id", "")) != db.id, "w21_trinity_3 未置位时中泉不出现 DB 交互")
	world._grant_ability(db.id)
	check(not world.ability_available("DB"), "w21_trinity_3 未置位时中泉拒绝发放 DB")
	world.journal.close_reader()
	world.chapter_flags["w21_trinity_3"] = true
	check(str(world.nearest_interaction().get("id", "")) == db.id, "w21_trinity_3 置位后中泉出现 DB 交互")
	world.interact_nearby()
	check(world.ability_available("DB"), "w21_trinity_3 置位后站在中泉可取 DB")
	world.journal.close_reader()

	# ---- 阶段 3：每区走真实入口取得，其余能力仍未获得 ----
	var all_codes := codes()
	for grant in points:
		world.chapter_flags.clear()
		world.load_map(grant.map)
		_unlock_grant_prereqs(world, grant)
		world.journal.close_reader()
		player.position = grant.at
		world.past_era = (grant.era == "past")
		world.interact_nearby()
		var shown := str(world.journal.body.text)
		check(world.ability_available(grant.code), "%s %s 取得后 ability_%s 为真" % [grant.map, grant.code, grant.code])
		for other in all_codes:
			if other == grant.code: continue
			check(not world.ability_available(other), "%s 取得 %s 时未顺带发放 %s" % [grant.map, grant.code, other])
		check(shown.contains(grant.text), "%s %s 的文案走 grants[].text" % [grant.map, grant.code])
		# 旧的 M01/M02「白螭河纹拓片」叙事分支已删除，VC 不得再被吞成拓片文案
		check(not shown.contains("白螭"), "%s %s 不再走白螭河纹拓片旧文案" % [grant.map, grant.code])
		world.journal.close_reader()

	# ---- 阶段 3.5：日志/HUD 的能力列表跟着旗标走（● 已取得 / ○ 未取得） ----
	world.chapter_flags.clear()
	world.current_map = "W01"
	world._grant_ability("ability_VC")
	world.journal.close_reader()
	world._show_journal()
	var log_text := str(world.journal.body.text)
	check(log_text.contains("● 时间切换"), "日志能力列表显示已取得的时间切换")
	check(log_text.contains("○ 凤凰二段跳"), "日志能力列表里未取得的能力仍是空心圈")
	world.journal.close_reader()

	# ---- 阶段 4：门真的开（W06 E08 需要 P2） ----
	world.chapter_flags.clear()
	world.load_map("W06")
	world.journal.close_reader()
	var main_edge := {}
	for edge in Maps.connections("W06"):
		if str(edge.id) == "E08": main_edge = edge
	check(not main_edge.is_empty(), "W06 有主线边 E08（W06→W08）")
	if not main_edge.is_empty():
		check(str(main_edge.requires) == "P2", "E08 的 requires 是 P2（实际 %s）" % str(main_edge.requires))
		check(not world.gate_reason(main_edge).is_empty(), "未取 P2 时 E08 锁死")
		var p2 := grant_for("P2")
		player.position = p2.at
		world.past_era = true
		world.interact_nearby()
		world.journal.close_reader()
		check(world.gate_reason(main_edge).is_empty(), "取得 P2 后 E08 打开")

	# ---- 阶段 5：每条 requires 边在源区授予所需能力后即开（无「先过门才能拿能力」） ----
	var gated_edges := 0
	for edge in Maps.db().edges:
		var code := str(edge.get("requires", ""))
		if code.is_empty(): continue
		gated_edges += 1
		world.chapter_flags.clear()
		var grant := grant_for(code)
		check(not grant.is_empty(), "%s 所需能力 %s 有取得点" % [str(edge.id), code])
		if grant.is_empty(): continue
		_unlock_grant_prereqs(world, grant)
		# 用真实取得路径发能力（不是直接置旗标）
		world.current_map = grant.map
		world.past_era = (grant.era == "past")
		world._grant_ability(grant.id)
		world.journal.close_reader()
		check(world.ability_available(code), "%s：%s 可从 %s 真实取得" % [str(edge.id), code, grant.map])
		# gate_reason 是纯数据判定（只读 Maps + chapter_flags + current_map），
		# 换到源区不必重建地形。
		world.current_map = source_of(edge)
		check(world.gate_reason(edge).is_empty(),
			"%s 在源区 %s 授予 %s 后开门" % [str(edge.id), world.current_map, code])
	check(gated_edges == 18, "18 条 requires 边（实际 %d）" % gated_edges)

	# ---- 阶段 6：全 29 区可达（不动点推演：门不会互相锁死） ----
	var reached := {"W01": true}
	var granted := {}
	var changed := true
	var passes := 0
	while changed and passes < 40:
		changed = false
		passes += 1
		for id in reached.keys():
			for grant in grants_of(str(id)):
				if granted.has(grant.code): continue
				granted[grant.code] = true
				changed = true
		for edge in Maps.db().edges:
			var a := str(edge.a)
			var b := str(edge.b)
			if reached.has(a) == reached.has(b): continue
			var here := a if reached.has(a) else b
			var there := b if here == a else a
			world.chapter_flags.clear()
			for code in granted: world.chapter_flags["ability_" + str(code)] = true
			var gate := str(edge.get("gate", ""))
			if not gate.is_empty():
				# 进度门由母区首领置位：母区能到就能开
				if not reached.has(str(edge.opener)): continue
				world.chapter_flags[gate] = true
			world.current_map = here
			if world.gate_reason(edge).is_empty():
				reached[there] = true
				changed = true
	check(granted.size() == 9, "推演中 9 个能力全部到手（实际 %d）" % granted.size())
	check(reached.size() == 29, "29 区全部可达（实际 %d）" % reached.size())
	world.chapter_flags.clear()
	world.load_map("W01")
	world.journal.close_reader()

	# ---- 阶段 7：DS 持有后 HUD 状态图标常驻 + 战场提示碑可反复读 ----
	world.chapter_flags.clear()
	world.load_map("W16")
	world.journal.close_reader()
	var ds := grant_for("DS")
	check(not ds.is_empty(), "DS 有取得点")
	player.position = ds.at
	world.past_era = (ds.era == "past")
	world.interact_nearby()
	world.journal.close_reader()
	check(world.ability_available("DS"), "DS 取得后 ability_available(\"DS\") 为真")
	world._update_hud(world.player.health, world.player.maximum_health)
	check(bool(world.ds_status_icon.visible), "持有 DS 时 HUD 状态图标常驻显示")
	check(str(world.ds_status_icon.tip_text) == str(world.ABILITY_USAGE["DS"]), "HUD 图标说明复用红线句常量")
	# 战场提示碑：可反复读、不置旗标、不扣资源
	var flags_before := int(world.chapter_flags.size())
	var souls_before := int(world.souls)
	var bones_before := int(world.bones)
	world._interact("sign_I09")
	world.journal.close_reader()
	check(int(world.chapter_flags.size()) == flags_before, "sign_I09 不置任何旗标")
	check(world.souls == souls_before and world.bones == bones_before, "sign_I09 不扣魂魄/凶骨")
	world._interact("sign_I09")
	world.journal.close_reader()
	check(int(world.chapter_flags.size()) == flags_before, "sign_I09 二次调查仍不置旗标")

	world.queue_free()
	await process_frame
	print("CHECKS=", checks)
	print("FAILURES=", failures)
	quit(0 if failures == 0 else 1)
