extends Node2D

# Prototype scope: two-era navigation and safe placement only. Geometry and tuning are provisional.
const FLOOR_Y := 420.0
const WORLD_WIDTH := 2200.0
const COMMON: Array[Rect2] = [
	Rect2(0, FLOOR_Y, 300, 72), Rect2(510, FLOOR_Y, 340, 72),
	Rect2(1080, FLOOR_Y, 370, 72), Rect2(1650, FLOOR_Y, 550, 72),
	Rect2(560, 320, 105, 18), Rect2(1190, 315, 120, 18)
]
const PAST: Array[Rect2] = [
	Rect2(300, FLOOR_Y, 210, 72), Rect2(850, FLOOR_Y, 230, 72),
	Rect2(680, 350, 110, 18), Rect2(1685, 350, 80, 18)
]
const PRESENT: Array[Rect2] = [
	Rect2(1450, FLOOR_Y, 200, 72), Rect2(780, 362, 50, 58),
	Rect2(920, 345, 95, 18)
]

const SettingsPanel := preload("res://game/settings_panel.gd")

@onready var terrain: Node2D = $Terrain
@onready var player: CharacterBody2D = $Player
var past_era := false
var hud: Label
var guide: Label
var notification: Label
var notice_timer := 0.0
var finish_marker := false
var switch_requested := false
var reset_requested := false
var settings_panel: CanvasLayer

func _unhandled_input(event: InputEvent) -> void:
	if settings_panel != null and settings_panel.visible:
		return
	if event.is_action_pressed("switch_era"):
		switch_requested = true
	if event.is_action_pressed("reset_checkpoint"):
		reset_requested = true
	if event.is_action_pressed("open_settings"):
		if settings_panel != null:
			settings_panel.open_panel()
			get_viewport().set_input_as_handled()

func _ready() -> void:
	player.world = self
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = _label(canvas, Vector2(20, 16), 23, Color("f5e6b7"))
	guide = _label(canvas, Vector2(20, 54), 16, Color("d3dce9"))
	notification = _label(canvas, Vector2(20, 98), 18, Color("ffdd83"))
	settings_panel = SettingsPanel.new()
	add_child(settings_panel)
	settings_panel.setup(InputActions)
	InputActions.bindings_changed.connect(_refresh_guide)
	_refresh_guide()
	_build_terrain(_geometry(past_era))
	player.health_changed.connect(_update_hud)
	player.respawned.connect(_on_respawn)
	_update_hud(player.health, player.maximum_health)
	_notify("寻找断桥：切换时代以穿过不同地形。")
	queue_redraw()

func _refresh_guide() -> void:
	if InputActions == null:
		return
	guide.text = "移动 %s   跳跃 %s   攻击 %s   冲刺 %s   时代 %s   回点 %s   （Esc/Start 改键）" % [
		InputActions.binding_text("move_left") + "/" + InputActions.binding_text("move_right"),
		InputActions.binding_text("jump"),
		InputActions.binding_text("attack"),
		InputActions.binding_text("dash"),
		InputActions.binding_text("switch_era"),
		InputActions.binding_text("reset_checkpoint"),
	]

func _label(canvas: CanvasLayer, location: Vector2, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	canvas.add_child(label)
	label.position = location
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color("11182a"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _process(delta: float) -> void:
	if switch_requested:
		switch_requested = false
		_switch_era()
	if reset_requested:
		reset_requested = false
		player.respawn()
	if player.position.x >= 2070 and not finish_marker:
		finish_marker = true
		_notify("已抵达探索切片终点！可继续切换时代观察地形。")
	notice_timer -= delta
	if notice_timer <= 0.0:
		notification.text = ""

func _geometry(era_is_past: bool) -> Array[Rect2]:
	var result: Array[Rect2] = COMMON.duplicate()
	result.append_array(PAST if era_is_past else PRESENT)
	return result

func _build_terrain(rectangles: Array[Rect2]) -> void:
	for child in terrain.get_children():
		terrain.remove_child(child)
		child.queue_free()
	for rectangle in rectangles:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = rectangle.position + rectangle.size * 0.5
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
	var destination := origin
	var unsafe := not _is_clear(origin, rectangles) or not _has_support(origin, rectangles)
	if unsafe:
		destination = _nearest_safe_position(origin, rectangles)
		var lethal: bool = player.health <= 1
		player.take_damage(1)
		if lethal:
			# Damage respawns at the common-era checkpoint before terrain is rebuilt.
			destination = player.checkpoint
		_notify("切换位置无法安全立足：已扣 1 生命并复位到安全地点。")
	past_era = target_past
	_build_terrain(rectangles)
	player.global_position = destination
	player.velocity = Vector2.ZERO if unsafe else player.velocity
	_update_hud(player.health, player.maximum_health)
	queue_redraw()

func _is_clear(point: Vector2, rectangles: Array[Rect2]) -> bool:
	var bounds := Rect2(point - Vector2(12, 20), Vector2(24, 40))
	if bounds.position.x < 0 or bounds.end.x > WORLD_WIDTH:
		return false
	for rectangle in rectangles:
		if bounds.intersects(rectangle):
			return false
	return true

func _has_support(point: Vector2, rectangles: Array[Rect2]) -> bool:
	var foot := point.y + 20.0
	for rectangle in rectangles:
		if point.x >= rectangle.position.x + 12 and point.x <= rectangle.end.x - 12:
			if rectangle.position.y >= foot - 2 and rectangle.position.y <= foot + 90:
				return true
	return false

func _nearest_safe_position(origin: Vector2, rectangles: Array[Rect2]) -> Vector2:
	var nearest: Vector2 = player.checkpoint
	var best := INF
	for rectangle in rectangles:
		if rectangle.size.x < 30 or rectangle.position.y > 500:
			continue
		var x := rectangle.position.x + 13.0
		while x <= rectangle.end.x - 13.0:
			var candidate := Vector2(x, rectangle.position.y - 20.0)
			if _is_clear(candidate, rectangles):
				var score := origin.distance_squared_to(candidate)
				if score < best:
					best = score
					nearest = candidate
			x += 12.0
	return nearest

func _update_hud(current: int, maximum: int) -> void:
	hud.text = "时间之神  |  %s  |  生命 %d/%d  |  目标：抵达右侧时之门" % ["过去" if past_era else "现在", current, maximum]

func _on_respawn() -> void:
	finish_marker = false
	_notify("已返回起点；时代与生命状态保留。")

func _notify(message: String) -> void:
	notification.text = message
	notice_timer = 3.5

func _draw() -> void:
	draw_rect(Rect2(-100, -400, WORLD_WIDTH + 200, 1100), Color("202849") if past_era else Color("142032"))
	draw_rect(Rect2(-100, 490, WORLD_WIDTH + 200, 400), Color("10192b"))
	for x in range(60, 2200, 240):
		draw_circle(Vector2(x, 120 + (x % 4) * 14), 3.0, Color("e3c582"))
	for rectangle in _geometry(past_era):
		var era_specific := PAST.has(rectangle) if past_era else PRESENT.has(rectangle)
		draw_rect(rectangle, Color("bc8c64") if past_era and era_specific else Color("517f9c") if era_specific else Color("657987"))
		draw_rect(Rect2(rectangle.position, Vector2(rectangle.size.x, 5)), Color("ecce9a") if past_era else Color("9acecf"))
	draw_rect(Rect2(2040, 326, 15, 94), Color("d9a867"))
	draw_rect(Rect2(2100, 326, 15, 94), Color("d9a867"))
	draw_arc(Vector2(2077, 350), 37, PI, TAU, 24, Color("f2d58e"), 5.0)
