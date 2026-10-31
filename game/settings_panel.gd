extends CanvasLayer

## In-game rebinding panel. Opens with the `open_settings` action (Esc / Start).
## Keyboard and gamepad bindings are edited separately: rebinding with a key
## keeps the pad binding, and vice versa.

signal closed

const ROW_START := 90
const ROW_HEIGHT := 34

var _input_actions: Node
var _rows: Array = []
var _capturing := false
var _capture_action := ""
var _status: Label
var _panel: VBoxContainer

func setup(input_actions: Node) -> void:
	layer = 30
	_input_actions = input_actions
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	_input_actions.bindings_changed.connect(_refresh_rows)

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("0d1424", 0.88)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var title := Label.new()
	title.text = "操作设置"
	title.position = Vector2(60, 40)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("f5e6b7"))
	add_child(title)

	_status = Label.new()
	_status.position = Vector2(60, 78)
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color("ffdd83"))
	_status.text = ""
	add_child(_status)

	_panel = VBoxContainer.new()
	_panel.position = Vector2(60, ROW_START)
	_panel.add_theme_constant_override("separation", 6)
	add_child(_panel)

	var reset := Button.new()
	reset.text = "恢复默认"
	reset.focus_mode = Control.FOCUS_ALL
	reset.position = Vector2(60, ROW_START + (_input_actions.ACTION_ORDER.size() + 1) * ROW_HEIGHT)
	reset.pressed.connect(_on_reset)
	add_child(reset)

	var close := Button.new()
	close.text = "关闭"
	close.focus_mode = Control.FOCUS_ALL
	close.position = Vector2(200, ROW_START + (_input_actions.ACTION_ORDER.size() + 1) * ROW_HEIGHT)
	close.pressed.connect(close_panel)
	add_child(close)

	for action in _input_actions.ACTION_ORDER:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = _input_actions.ACTION_LABELS.get(action, action)
		label.custom_minimum_size = Vector2(140, 26)
		label.add_theme_color_override("font_color", Color("d3dce9"))
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(340, 26)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_on_row_pressed.bind(action))
		row.add_child(button)
		_panel.add_child(row)
		_rows.append({"action": action, "button": button})
	_refresh_rows()

func _refresh_rows() -> void:
	if _input_actions == null:
		return
	for row in _rows:
		if not is_instance_valid(row["button"]):
			continue
		row["button"].text = _input_actions.binding_text(row["action"])

func _on_row_pressed(action: String) -> void:
	_capturing = true
	_capture_action = action
	_status.text = "请按下新的按键或手柄键…（Esc 取消）"

func _input(event: InputEvent) -> void:
	if not _capturing:
		return
	if event is InputEventKey and event.pressed and event.is_action_pressed("ui_cancel"):
		_capturing = false
		_status.text = ""
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event is InputEventJoypadMotion and absf(event.axis_value) < 0.6: return
	if event is InputEventKey and not event.pressed:
		return
	if event is InputEventKey and event.is_echo():
		return
	if event is InputEventKey and event.is_pressed() and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_capturing = false
		_status.text = ""
		get_viewport().set_input_as_handled()
		return

	var action := _capture_action
	var conflicted: String = _input_actions.rebind(action, event)
	_capturing = false
	_capture_action = ""
	if conflicted.is_empty():
		_status.text = "已将「%s」绑定到 %s" % [
			_input_actions.ACTION_LABELS.get(action, action),
			_input_actions.binding_text(action),
		]
	else:
		_status.text = "已绑定，并从「%s」移除了该按键" % _input_actions.ACTION_LABELS.get(conflicted, conflicted)
	get_viewport().set_input_as_handled()

func _on_reset() -> void:
	_input_actions.reset_to_defaults()
	_status.text = "已恢复默认绑定"

func open_panel() -> void:
	visible = true
	_status.text = ""
	get_tree().paused = true
	if not _rows.is_empty(): _rows[0].button.grab_focus()

func close_panel() -> void:
	_capturing = false
	_capture_action = ""
	visible = false
	_status.text = ""
	get_tree().paused = false
	closed.emit()

func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _capturing:
		return
	if event.is_action_pressed("open_settings") or event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()

func is_capturing() -> bool:
	return _capturing
