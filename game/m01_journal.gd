extends CanvasLayer

## A paused, keyboard/gamepad-accessible reader shared by story entries/log.
var panel: PanelContainer
var title_label: Label
var body: RichTextLabel
var close_button: Button
var was_paused := false
var choice_button: Button
var choices: Array[Button] = []

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.06, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 90
	panel.offset_right = -90
	panel.offset_top = 80
	panel.offset_bottom = -80
	add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 26)
	column.add_child(title_label)
	body = RichTextLabel.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 19)
	column.add_child(body)
	close_button = Button.new()
	close_button.text = "返回游戏  ·  交互键 / 日志键 / Esc"
	close_button.pressed.connect(close_reader)
	column.add_child(close_button)
	visible = false

func show_entry(heading: String, text: String) -> void:
	if not visible:
		was_paused = get_tree().paused
	for button in choices:
		if is_instance_valid(button): button.queue_free()
	choices.clear()
	choice_button = null
	title_label.text = heading
	body.text = text
	body.scroll_to_line(0)
	visible = true
	get_tree().paused = true
	close_button.grab_focus()

func show_choice(label: String, callback: Callable) -> void:
	choice_button = Button.new()
	choice_button.text = label
	close_button.get_parent().add_child(choice_button)
	choice_button.pressed.connect(callback, CONNECT_ONE_SHOT)
	choices.append(choice_button)

func close_reader() -> void:
	visible = false
	get_tree().paused = was_paused

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("interact") \
			or event.is_action_pressed("open_journal") or event.is_action_pressed("ui_cancel")):
		close_reader()
		get_viewport().set_input_as_handled()
