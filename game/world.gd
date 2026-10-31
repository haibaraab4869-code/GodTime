extends Node2D

## 世界运行时的通用基类。29 区地图几何由 world_data.gd / world_game.gd 提供，
## 旧的 m01_layout.gd（写死 M01 灰盒）已随 48 区地图一并退役。
signal exit_requested(map_id: String, anchor_id: String)
const SettingsPanel := preload("res://game/settings_panel.gd")
const Journal := preload("res://game/m01_journal.gd")
const DSStatusIcon := preload("res://game/ds_status_icon.gd")
const SAVE_PATH := "user://world_progress.cfg"
const SAVE_VERSION := 2
const VIEW_WIDTH := 4096.0
const VIEW_HEIGHT := 1024.0
const SAFE_DROP := 180.0
const FALLBACK_SPAWN := Vector2(48, 556)
# M01 时代的旧旗标已随 29 区地图退役；世界级进度全部走 chapter_flags。

# 世界底色单一来源（art-bible §2.6）：角色墨色阶的 3.80:1 是按 SKY_NOW 量的，
# 天空与地形必须成对出现——从深天空出发，更深的岩体无法达到 3:1。
const SKY_NOW := Color("142032")
const SKY_PAST := Color("202849")
const TERRAIN := Color("657987")


func sky_color() -> Color:
	return SKY_PAST if past_era else SKY_NOW

@export var persist_progress := true
@export var save_path := SAVE_PATH
@onready var terrain: Node2D = $Terrain
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Player/Camera
var past_era := false
var switch_requested := false
var reset_requested := false
var interact_requested := false
var notice_timer := 0.0
var clock := 0.0
var hud: Label
var ds_status_icon: Control
var objective: Label
var guide: Label
var prompt: Label
var notification: Label
var settings_panel: CanvasLayer
var journal: CanvasLayer
var _last_prompt := ""

func _ready() -> void:
	DisplayServer.window_set_title("时间之神 · 八荒")
	player.world = self
	player.checkpoint = FALLBACK_SPAWN
	player.global_position = FALLBACK_SPAWN
	_build_ui()
	_build_terrain(_geometry(past_era))
	player.health_changed.connect(_update_hud)
	player.respawned.connect(_on_respawn)
	InputActions.bindings_changed.connect(_refresh_guide)
	_refresh_guide()
	_update_hud(player.health, player.maximum_health)

func _unhandled_input(event: InputEvent) -> void:
	if journal.visible or settings_panel.visible:
		return
	if event.is_echo():
		return
	if event.is_action_pressed("open_settings"):
		_clear_requests()
		settings_panel.open_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_journal"):
		_show_journal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		interact_requested = true
	elif event.is_action_pressed("switch_era"):
		switch_requested = true
	elif event.is_action_pressed("reset_checkpoint"):
		reset_requested = true

func _process(delta: float) -> void:
	clock += delta
	if switch_requested:
		switch_requested = false
		_switch_era()
	if reset_requested:
		reset_requested = false
		player.respawn()
	if interact_requested:
		interact_requested = false
		interact_nearby()
	var nearby := nearest_interaction()
	var text := ""
	if not nearby.is_empty():
		text = "[%s]  %s" % [_short_binding("interact"), nearby.name]
	if text != _last_prompt:
		_last_prompt = text
		prompt.text = text
	notice_timer = maxf(0.0, notice_timer - delta)
	if notice_timer <= 0:
		notification.text = ""
	objective.text = _objective_text()
	queue_redraw()

func _clear_requests() -> void:
	switch_requested = false
	reset_requested = false
	interact_requested = false
	player.jump_buffer.clear()
	player.attack_buffer.clear()
	player.dash_buffer.clear()

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	var control := Control.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(control)
	var top := ColorRect.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 116
	top.color = Color(0.055, 0.09, 0.11, 0.94)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_child(top)
	var hud_row := HBoxContainer.new()
	hud_row.position = Vector2(26, 16)
	hud_row.add_theme_constant_override("separation", 8)
	hud_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_child(hud_row)
	hud = _screen_label(hud_row, 22, Color("f1e6cc"))
	ds_status_icon = DSStatusIcon.new()
	ds_status_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ds_status_icon.visible = false
	hud_row.add_child(ds_status_icon)
	objective = _screen_label(control, 16, Color("cad4d1"))
	objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	objective.offset_left = 26
	objective.offset_top = 56
	objective.offset_right = -26
	objective.offset_bottom = 110
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bottom := ColorRect.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -88
	bottom.color = Color(0.055, 0.09, 0.11, 0.93)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_child(bottom)
	prompt = _screen_label(control, 19, Color("f2cf8d"))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_left = 26
	prompt.offset_top = -84
	prompt.offset_right = -26
	prompt.offset_bottom = -55
	notification = _screen_label(control, 15, Color("e3ded0"))
	notification.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notification.offset_left = 26
	notification.offset_top = -55
	notification.offset_right = -26
	notification.offset_bottom = -30
	guide = _screen_label(control, 14, Color("9eafaf"))
	guide.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	guide.offset_left = 26
	guide.offset_top = -25
	guide.offset_right = -26
	guide.offset_bottom = -5
	settings_panel = SettingsPanel.new()
	add_child(settings_panel)
	settings_panel.setup(InputActions)
	journal = Journal.new()
	add_child(journal)

func _screen_label(parent: Node, size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _short_binding(action: String) -> String:
	return InputActions.binding_text(action).split(" / ")[0]

func _refresh_guide() -> void:
	guide.text = "%s / %s 移动    %s 跳跃    %s 攻击    %s 冲刺    %s 切换时代    %s 调查    %s 日志    Esc 设置" % [
		_short_binding("move_left"), _short_binding("move_right"), _short_binding("jump"),
		_short_binding("attack"), _short_binding("dash"), _short_binding("switch_era"),
		_short_binding("interact"), _short_binding("open_journal")]

func _update_hud(current: int, maximum: int) -> void:
	if hud == null:
		return
	# 区名与章节由 world_game 覆盖；基类不带区号，避免依赖子类字段。
	hud.text = "%s     ·     生命 %d / %d" % ["过去" if past_era else "现在", current, maximum]

func _objective_text() -> String:
	# 世界级目标文案由 world_game.gd 覆盖，这里只兜底。
	return "贴边向外走即可前往相邻区，M 查看房间与世界地图。"

func nearest_interaction() -> Dictionary:
	# 基类不持有区域数据；world_game.gd 按 world_regions.json 覆盖此方法。
	return {}

func interact_nearby() -> void:
	var item := nearest_interaction()
	if not item.is_empty():
		_interact(item.id)

func _interact(_id: String) -> void:
	# 区域交互全部由 world_game.gd 依 world_regions.json 处理；基类只兜底。
	_notify("这里没有可调查的目标。", 2)

func _show_entry(title: String, text: String) -> void:
	_clear_requests()
	journal.show_entry(title, text)

func _show_journal() -> void:
	# 世界日志由 world_game.gd 覆盖；基类只给兜底。
	_show_entry("调查日志", _objective_text())

func _save_progress() -> void:
	if not persist_progress:
		return
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	var error := config.save(save_path)
	if error != OK:
		_notify("本次进度未能写入磁盘；当前游玩进度仍保留。", 6.0)

func _geometry(era_is_past: bool) -> Array[Rect2]:
	return []

func _build_terrain(rectangles: Array[Rect2]) -> void:
	for child in terrain.get_children():
		terrain.remove_child(child)
		child.queue_free()
	for rectangle in rectangles:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = rectangle.get_center()
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rectangle.size
		collision.shape = shape
		body.add_child(collision)
		terrain.add_child(body)

func _switch_era() -> void:
	var target_past := not past_era
	var rectangles := _geometry(target_past)
	var origin := player.global_position
	# Validate before any era, terrain, health or movement state is changed.
	if not _is_clear(origin, rectangles):
		_notify("当前位置无法使用该能力", 6.0)
		return
	var destination := origin
	var unsafe := not _has_support(origin, rectangles)
	if unsafe:
		destination = _nearest_safe_position(origin, rectangles)
		var lethal: bool = player.health <= 1
		player.take_damage(1)
		if lethal:
			destination = player.checkpoint
		_notify("目标时代无法落脚：扣 1 生命，已安置到能移动的安全台。", 6.0)
	past_era = target_past
	_build_terrain(rectangles)
	player.global_position = destination
	if unsafe:
		player.velocity = Vector2.ZERO
	_update_hud(player.health, player.maximum_health)
	queue_redraw()

func _is_clear(point: Vector2, rectangles: Array[Rect2]) -> bool:
	var bounds := Rect2(point - Vector2(11.7, 19.7), Vector2(23.4, 39.4))
	var area := world_bounds()
	if bounds.position.x < area.position.x or bounds.end.x > area.end.x or bounds.position.y < area.position.y or bounds.end.y > area.end.y:
		return false
	for rectangle in rectangles:
		if bounds.intersects(rectangle):
			return false
	return true

func _has_support(point: Vector2, rectangles: Array[Rect2]) -> bool:
	var foot := point.y + 20.0
	for rectangle in rectangles:
		if point.x < rectangle.position.x + 12.0 or point.x > rectangle.end.x - 12.0:
			continue
		var drop := rectangle.position.y - foot
		if drop < -2.0 or drop > SAFE_DROP:
			continue
		var landing := Vector2(point.x, rectangle.position.y - 20.0)
		if not _is_clear(landing, rectangles):
			continue
		var fall_path := Rect2(point - Vector2(11.7, 19.7), Vector2(23.4, 39.4 + maxf(drop, 0.0)))
		var blocked := false
		for obstacle in rectangles:
			if fall_path.intersects(obstacle):
				blocked = true
				break
		if not blocked:
			return true
	return false

func _nearest_safe_position(origin: Vector2, rectangles: Array[Rect2]) -> Vector2:
	var nearest: Vector2 = player.checkpoint
	var best := 480.0 * 480.0
	for rectangle in rectangles:
		if rectangle.size.x < 52.0 or rectangle.position.y < 80.0 or rectangle.position.y > world_bounds().end.y - 40.0:
			continue
		var x := rectangle.position.x + 26.0
		while x <= rectangle.end.x - 26.0:
			var candidate := Vector2(x, rectangle.position.y - 20.0)
			var can_move := _is_clear(candidate + Vector2(24, 0), rectangles) \
				or _is_clear(candidate - Vector2(24, 0), rectangles)
			if can_move and _is_clear(candidate, rectangles):
				var score := origin.distance_squared_to(candidate)
				if score < best:
					best = score
					nearest = candidate
			x += 12.0
	return nearest

func world_bounds() -> Rect2:
	return Rect2(0, 0, VIEW_WIDTH, VIEW_HEIGHT)

func fall_limit() -> float:
	return world_bounds().end.y - 20.0

func _on_respawn() -> void:
	_notify("已返回渡口灯龛；葬帖、壁画与开闸进度保留。", 5.0)

func _notify(message: String, seconds := 4.0) -> void:
	if notification != null:
		notification.text = message
	notice_timer = seconds

func _world_label(text: String, at: Vector2, size := 16, light := false) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("eee5cf") if light else Color("334950"))
	add_child(label)

func _draw_ferryman(at: Vector2, ink: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(-10, 0), at + Vector2(9, 0),
		at + Vector2(5, -40), at + Vector2(-7, -40)]), ink)
	draw_circle(at + Vector2(-1, -45), 7, ink)
	draw_line(at + Vector2(-17, -49), at + Vector2(15, -49), ink, 3)
	draw_line(at + Vector2(14, 0), at + Vector2(14, -52), ink, 2)

func _draw_marker(at: Vector2) -> void:
	var bob := sin(clock * 3) * 2
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5 + bob), at + Vector2(4, bob),
		at + Vector2(0, 5 + bob), at + Vector2(-4, bob)]), Color("dbb86f"))
