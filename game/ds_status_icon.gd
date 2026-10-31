extends Control
## DS「龙鳞耐热」HUD 状态图标（20×20 程序化矢量）。
## 鳞片填充 #E0A040、外轮廓 #1C1A17、弧线高光——带形状轮廓，不依赖单色辨识（无障碍）。
## 说明文字由 world_game.gd 注入 ABILITY_USAGE["DS"]（红线句单一真源），本文件不手抄红线句。

var scale_color := Color("e0a040")
var outline_color := Color("1c1a17")
var highlight_color := Color("f0c060")

var tip_text := ""
var _tip: Label

func _ready() -> void:
	custom_minimum_size = Vector2(20, 20)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_tip = Label.new()
	_tip.add_theme_font_size_override("font_size", 14)
	_tip.add_theme_color_override("font_color", Color("f8f0e3"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.09, 0.11, 0.94)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_tip.add_theme_stylebox_override("normal", style)
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tip)
	mouse_entered.connect(_show_tip)
	mouse_exited.connect(_hide_tip)
	focus_entered.connect(_show_tip)
	focus_exited.connect(_hide_tip)

func set_tip(text: String) -> void:
	if tip_text == text:
		return
	tip_text = text
	_tip.text = text

func _draw() -> void:
	# 鳞片主体：六边形盾形，上尖下尖，左右对称。
	var points := PackedVector2Array([
		Vector2(10, 2), Vector2(16, 6), Vector2(17, 12),
		Vector2(10, 17), Vector2(3, 12), Vector2(4, 6),
	])
	draw_colored_polygon(points, scale_color)
	draw_polyline(PackedVector2Array([
		points[0], points[1], points[2], points[3], points[4], points[5], points[0],
	]), outline_color, 1.5)
	# 上缘一撇高光（弧线），不是护甲光环。
	draw_arc(Vector2(10, 10), 4.5, -2.4, -0.7, 8, highlight_color, 1.2)

func _show_tip() -> void:
	if tip_text.is_empty():
		return
	_tip.position = Vector2(24, -4)
	_tip.visible = true

func _hide_tip() -> void:
	_tip.visible = false

func _gui_input(event: InputEvent) -> void:
	# 手柄/键盘聚焦后按调查键（ui_accept）也能唤起说明，非仅 hover 可达。
	if event.is_action_pressed("ui_accept"):
		_show_tip()
		accept_event()
