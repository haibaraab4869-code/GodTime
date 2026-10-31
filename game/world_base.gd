extends "res://game/world.gd"
## 世界运行时基础层：存档、魂魄遗落、包扎、守卫与区域旗标。
## 地图设定只有一份来源：world_data.gd + data/world_regions.json（W01–W29）。

const Maps := preload("res://game/world_data.gd")
const Guard := preload("res://game/chapter_guard.gd")
const Combat := preload("res://game/chapter_combat.gd")

var current_map := "W01"
var chapter_flags: Dictionary = {}
var actors: Node2D
var guard: Node2D
var checkpoint_map := "W01"
var checkpoint_at := Vector2(160, 460)
var souls := 0
var bones := 0
var heal_remaining := 0.0
var heal_charges := 3
var hurt_lock := 0.0
var combat: Node
var audio: Node
var switching := false
var return_after_switch := false
var soul_drop: Dictionary = {}
var atlas: CanvasLayer

func _ready() -> void:
	super._ready()
	actors = Node2D.new()
	add_child(actors)
	combat = Combat.new()
	combat.world = self
	combat.player = player
	add_child(combat)
	audio = preload("res://game/chapter_audio.gd").new()
	add_child(audio)
	player.swing_started.connect(func(): audio.play_cue("step"))
	player.died.connect(_on_died)
	if persist_progress:
		var cfg := ConfigFile.new()
		if cfg.load(save_path + ".chapter") == OK:
			chapter_flags = cfg.get_value("chapter", "flags", {})
			souls = int(cfg.get_value("chapter", "souls", 0))
			bones = int(cfg.get_value("chapter", "bones", 0))
			soul_drop = cfg.get_value("chapter", "soul_drop", {})
			checkpoint_map = str(cfg.get_value("chapter", "checkpoint_map", "W01"))
			checkpoint_at = cfg.get_value("chapter", "checkpoint_at", Maps.spawn("W01"))
			# 旧存档可能指向已废弃的区域：一律回落到世界入口，避免卡在空图。
			if not Maps.db().regions.has(checkpoint_map):
				checkpoint_map = "W01"
				checkpoint_at = Maps.spawn("W01")
				soul_drop = {}
			combat.state.set_form(str(cfg.get_value("chapter", "form", "taotie")))
			heal_charges = 3 + clampi(int(chapter_flags.get("supply_upgrade", 0)), 0, 2)
			if int(cfg.get_value("chapter", "layout_version", 1)) < Maps.LAYOUT_VERSION:
				checkpoint_at = Maps.anchor(checkpoint_map, "rest")
				if not soul_drop.is_empty():
					var drop_map := str(soul_drop.get("map", checkpoint_map))
					if Maps.db().regions.has(drop_map): soul_drop.at = Maps.anchor(drop_map, "rest")
					else: soul_drop = {}
			load_map(checkpoint_map, checkpoint_at)
	atlas = preload("res://game/world_atlas.gd").new()
	atlas.world = self
	add_child(atlas)
	_refresh_guide()

func _process(delta: float) -> void:
	super._process(delta)
	if objective != null: objective.text = _objective_text()
	queue_redraw()
	hurt_lock = maxf(0, hurt_lock - delta)
	if heal_remaining > 0:
		if player.velocity.length() > 25 or player.dash_remaining > 0 or player.is_attacking() or combat.action_left > 0:
			heal_remaining = 0
			_notify("疗伤被移动打断，药未消耗。", 2)
		else:
			heal_remaining -= delta
			if heal_remaining <= 0:
				heal_charges -= 1
				player.health = mini(player.maximum_health, player.health + 1)
				player.health_changed.emit(player.health, player.maximum_health)
	_update_hud(player.health, player.maximum_health)

func load_map(id: String, at := Vector2(-1, -1)) -> void:
	## 通用切图骨架。world_game.gd 覆盖它，按 world_regions.json 装配区域实例。
	if not Maps.db().regions.has(id): return
	_clear_requests()
	if journal.visible: journal.close_reader()
	for child in get_children():
		if child is Label:
			remove_child(child)
			child.queue_free()
	for child in actors.get_children():
		actors.remove_child(child)
		child.queue_free()
	guard = null
	current_map = id
	if at.x < 0: at = Maps.spawn(id)
	past_era = false
	player.global_position = at
	player.velocity = Vector2.ZERO
	player.attack_remaining = 0
	player.attack_cooldown_remaining = 0
	player.dash_remaining = 0
	if combat != null: combat.clear_action()
	player.checkpoint = at
	heal_remaining = 0
	_build_terrain(_geometry(past_era))
	chapter_flags["visited_" + id] = true
	camera.reset_smoothing()
	DisplayServer.window_set_title("时间之神 · " + id + " " + Maps.region(id).title)
	_notify(Maps.region(id).title + "  ·  " + _objective_text(), 5)
	_save_progress()
	queue_redraw()

func cancel_heal() -> void:
	heal_remaining = 0
	if combat != null: combat.on_hurt()
	if audio != null: audio.play_cue("hit")

func cancel_heal_only() -> void:
	heal_remaining = 0

func _switch_era() -> void:
	var before := past_era
	switching = true
	super._switch_era()
	switching = false
	if return_after_switch:
		return_after_switch = false
		_on_respawn()
	if audio != null and before != past_era:
		audio.set_era(past_era)
		audio.play_cue("switch")

func _unhandled_input(event: InputEvent) -> void:
	if atlas != null and atlas.visible: return
	if event.is_action_pressed("open_map") and not journal.visible and not settings_panel.visible:
		_clear_requests()
		atlas.open_map()
		get_viewport().set_input_as_handled()
		return
	if not journal.visible and not settings_panel.visible and not event.is_echo():
		if event.is_action_pressed("heal") and heal_remaining <= 0 and heal_charges > 0 and player.health < player.maximum_health:
			if combat.action_left > 0: return
			heal_remaining = 0.9
			_notify("正在包扎……保持站定 0.9 秒；可用冲刺取消。", 2)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _refresh_guide() -> void:
	super._refresh_guide()
	if guide != null: guide.text += "    %s 地图  %s 包扎  %s 重击  %s 技能" % [_short_binding("open_map"), _short_binding("heal"), _short_binding("heavy_attack"), _short_binding("beast_skill")]

func _set_flag(key: String, reward := 0) -> void:
	if not chapter_flags.get(key, false):
		chapter_flags[key] = true
		souls += reward
	_save_progress()

func _interact(id: String) -> void:
	## 世界级通用交互；区域专属交互由 world_game.gd 处理后再回落。
	if id == "recover_souls":
		if soul_drop.get("map", "") == current_map:
			souls += int(soul_drop.get("amount", 0))
			soul_drop.clear()
			_save_progress()
			_notify("遗落的魂魄已全部取回。", 4)
		return
	super._interact(id)

func _choose_next_form() -> void:
	var order := ["taotie", "qiongqi", "taowu", "hundun"]
	combat.state.set_form(order[(order.find(combat.state.form) + 1) % order.size()])
	_save_progress()
	_show_entry("灯龛 · " + combat.display_name(), "流派已切换，凶气与临时增益清空。\n\n" + combat.help_text() + "\n\n普攻命中积累凶气，重击与技能沿用既有四凶数据。流派只能在灯龛切换，不需要后续探索能力。")
	journal.show_choice("切换至下一流派", _choose_next_form)

func _spawn_guard(is_boss: bool, at: Vector2, flag: String) -> void:
	guard = Guard.new()
	guard.boss = is_boss
	guard.position = at
	guard.player = player
	actors.add_child(guard)
	guard.defeated.connect(func():
		_set_flag(flag, 80 if is_boss else 25)
		_save_progress()
		_notify("报丧鼓将已败，粮道封印解除。向东处理证词。" if is_boss else "封印已散，奖励与捷径均已保存。", 7)
		guard = null)

func _on_respawn() -> void:
	if switching:
		return_after_switch = true
		return
	heal_remaining = 0
	if guard != null: guard.reset_fight()
	if combat != null: combat.reset_fight()
	# 区域内的返回点始终落在当前几何的安全面上。
	if current_map != checkpoint_map:
		load_map(checkpoint_map, checkpoint_at)
	else:
		past_era = false
		_build_terrain(_geometry(false))
		player.position = checkpoint_at
		player.checkpoint = checkpoint_at
	_notify("返回灯龛；调查、机关、支线选择与已击败的首领均保留。", 5)

func _on_died(at: Vector2) -> void:
	# 再次死亡会覆盖上一份遗落物，包括零魂魄死亡。
	soul_drop = {"map": current_map, "at": at, "amount": souls} if souls > 0 else {}
	souls = 0
	_save_progress()

func _drop_position() -> Vector2:
	var at: Vector2 = soul_drop.get("at", Vector2(150, 460))
	var geometry := _geometry(past_era)
	if _is_clear(at, geometry) and _has_support(at, geometry): return at
	return _nearest_safe_position(at, geometry)

func _save_progress() -> void:
	super._save_progress()
	if not persist_progress: return
	var cfg := ConfigFile.new()
	cfg.set_value("chapter", "layout_version", Maps.LAYOUT_VERSION)
	cfg.set_value("chapter", "flags", chapter_flags)
	cfg.set_value("chapter", "souls", souls)
	cfg.set_value("chapter", "bones", bones)
	cfg.set_value("chapter", "checkpoint_map", checkpoint_map)
	cfg.set_value("chapter", "checkpoint_at", checkpoint_at)
	cfg.set_value("chapter", "soul_drop", soul_drop)
	if combat != null: cfg.set_value("chapter", "form", combat.state.form)
	if cfg.save(save_path + ".chapter") != OK: _notify("章节存档写入失败，当前进度仍在内存中。", 5)

func _draw_drop() -> void:
	if soul_drop.get("map", "") != current_map: return
	var at := _drop_position()
	draw_circle(at, 10, Color("bad7d1"))
	draw_arc(at, 16 + sin(clock * 3) * 2, 0, TAU, 24, Color("d9e6c5"), 2)
