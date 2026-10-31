extends Node

## Central input binding registry.
##
## Defaults live in this file rather than the serialized `[input]` section of
## project.godot: a GDScript table is diffable, reviewable and safe to edit by
## hand, whereas the serialized section is easy to corrupt. Actions are pushed
## into InputMap at startup; player overrides persist to user://.

signal bindings_changed

const SAVE_PATH := "user://input_bindings.cfg"
const ACTION_DEADZONE := 0.2

## Actions shown in the remap panel, in display order.
const ACTION_ORDER := [
	"move_left",
	"move_right",
	"jump",
	"move_down",
	"attack",
	"dash",
	"switch_era",
	"reset_checkpoint",
	"interact",
	"open_journal",
	"heal",
	"heavy_attack",
	"beast_skill",
	"open_map",
]

## Registered but not user-rebindable: they drive the settings panel itself.
const META_ACTIONS := ["open_settings"]

const ACTION_LABELS := {
	"move_left": "左移",
	"move_right": "右移",
	"jump": "跳跃",
	"dive": "水中下潜",
	"move_down": "下移 / 水中下潜",
	"attack": "攻击",
	"dash": "冲刺",
	"switch_era": "切换时代",
	"reset_checkpoint": "回到存档点",
	"interact": "调查 / 交谈",
	"open_journal": "渡口日志",
	"heal": "包扎疗伤",
	"heavy_attack": "流派重击",
	"beast_skill": "凶气技能",
	"open_map": "区域分层地图",
}

const JOY_NAMES := {
	JOY_BUTTON_A: "手柄 A",
	JOY_BUTTON_B: "手柄 B",
	JOY_BUTTON_X: "手柄 X",
	JOY_BUTTON_Y: "手柄 Y",
	JOY_BUTTON_BACK: "手柄 Back",
	JOY_BUTTON_GUIDE: "手柄 Guide",
	JOY_BUTTON_START: "手柄 Start",
	JOY_BUTTON_LEFT_STICK: "手柄 L3",
	JOY_BUTTON_RIGHT_STICK: "手柄 R3",
	JOY_BUTTON_LEFT_SHOULDER: "手柄 LB",
	JOY_BUTTON_RIGHT_SHOULDER: "手柄 RB",
	JOY_BUTTON_DPAD_UP: "手柄 ↑",
	JOY_BUTTON_DPAD_DOWN: "手柄 ↓",
	JOY_BUTTON_DPAD_LEFT: "手柄 ←",
	JOY_BUTTON_DPAD_RIGHT: "手柄 →",
}

const AXIS_NAMES := {
	JOY_AXIS_LEFT_X: "左摇杆X",
	JOY_AXIS_LEFT_Y: "左摇杆Y",
	JOY_AXIS_RIGHT_X: "右摇杆X",
	JOY_AXIS_RIGHT_Y: "右摇杆Y",
	JOY_AXIS_TRIGGER_LEFT: "左扳机",
	JOY_AXIS_TRIGGER_RIGHT: "右扳机",
}

const DEFAULT_BINDINGS := {
	"move_down": [{"type": "key", "code": KEY_S}, {"type": "key", "code": KEY_DOWN}, {"type": "axis", "axis": JOY_AXIS_LEFT_Y, "value": 1.0}],
	"open_map": [{"type": "key", "code": KEY_M}, {"type": "button", "button": JOY_BUTTON_DPAD_DOWN}],
	"heavy_attack": [{"type": "key", "code": KEY_K}, {"type": "button", "button": JOY_BUTTON_RIGHT_STICK}],
	"beast_skill": [{"type": "key", "code": KEY_L}, {"type": "button", "button": JOY_BUTTON_LEFT_STICK}],
	"heal": [{"type": "key", "code": KEY_H}, {"type": "button", "button": JOY_BUTTON_DPAD_UP}],
	"move_left": [
		{"type": "key", "code": KEY_A},
		{"type": "key", "code": KEY_LEFT},
		{"type": "axis", "axis": JOY_AXIS_LEFT_X, "value": -1.0},
	],
	"move_right": [
		{"type": "key", "code": KEY_D},
		{"type": "key", "code": KEY_RIGHT},
		{"type": "axis", "axis": JOY_AXIS_LEFT_X, "value": 1.0},
	],
	"jump": [
		{"type": "key", "code": KEY_SPACE},
		{"type": "key", "code": KEY_W},
		{"type": "key", "code": KEY_UP},
		{"type": "button", "button": JOY_BUTTON_A},
	],
	"attack": [
		{"type": "key", "code": KEY_J},
		{"type": "key", "code": KEY_X},
		{"type": "button", "button": JOY_BUTTON_X},
	],
	"dash": [
		{"type": "key", "code": KEY_SHIFT},
		{"type": "button", "button": JOY_BUTTON_B},
	],
	"switch_era": [
		{"type": "key", "code": KEY_TAB},
		{"type": "button", "button": JOY_BUTTON_Y},
	],
	"reset_checkpoint": [
		{"type": "key", "code": KEY_R},
		{"type": "button", "button": JOY_BUTTON_BACK},
	],
	"open_settings": [
		{"type": "key", "code": KEY_ESCAPE},
		{"type": "button", "button": JOY_BUTTON_START},
	],
	"interact": [
		{"type": "key", "code": KEY_E},
		{"type": "button", "button": JOY_BUTTON_RIGHT_SHOULDER},
	],
	"open_journal": [
		{"type": "key", "code": KEY_Q},
		{"type": "button", "button": JOY_BUTTON_LEFT_SHOULDER},
	],
}

var bindings: Dictionary = {}
# Tests can use their own ConfigFile without touching the player's bindings.
var save_path := SAVE_PATH

func _ready() -> void:
	bindings = _default_bindings()
	_load()
	_apply_all()

func _default_bindings() -> Dictionary:
	return DEFAULT_BINDINGS.duplicate(true)

func all_actions() -> Array:
	var result := []
	result.append_array(ACTION_ORDER)
	result.append_array(META_ACTIONS)
	return result

# --- event conversion -------------------------------------------------------

func _to_event(descriptor: Dictionary) -> InputEvent:
	match String(descriptor.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(descriptor.get("code", 0))
			return key
		"button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(descriptor.get("button", 0))
			return button
		"axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(descriptor.get("axis", 0))
			motion.axis_value = float(descriptor.get("value", 0.0))
			return motion
	return null

func _describe(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: int = key.physical_keycode
		if code == 0:
			code = key.keycode
		if code == 0:
			return {}
		return {"type": "key", "code": code}
	if event is InputEventJoypadButton:
		return {"type": "button", "button": (event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion and absf(event.axis_value) >= 0.6:
		return {"type": "axis", "axis": event.axis, "value": signf(event.axis_value)}
	return {}

# --- apply ------------------------------------------------------------------

func _apply_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_set_deadzone(action, ACTION_DEADZONE)
	InputMap.action_erase_events(action)
	for descriptor in bindings.get(action, []):
		var event := _to_event(descriptor)
		if event != null:
			InputMap.action_add_event(action, event)
	if action == "move_down":
		if not InputMap.has_action("dive"): InputMap.add_action("dive")
		InputMap.action_erase_events("dive")
		for event in InputMap.action_get_events(action): InputMap.action_add_event("dive", event)

func _apply_all() -> void:
	for retired in ["view_wide", "view_close"]:
		if InputMap.has_action(retired): InputMap.erase_action(retired)
	for action in all_actions():
		if not bindings.has(action):
			bindings[action] = []
		_apply_action(action)

# --- persistence ------------------------------------------------------------

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("bindings", "actions", bindings)
	config.save(save_path)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	var saved = config.get_value("bindings", "actions", null)
	if typeof(saved) != TYPE_DICTIONARY:
		return
	if not saved.has("move_down") and saved.has("dive"): saved["move_down"] = saved.dive
	for action in all_actions():
		if saved.has(action) and saved[action] is Array:
			bindings[action] = _sanitize(saved[action])

func _sanitize(raw: Array) -> Array:
	var clean := []
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var descriptor := entry as Dictionary
		match String(descriptor.get("type", "")):
			"key":
				clean.append({"type": "key", "code": int(descriptor.get("code", 0))})
			"button":
				clean.append({"type": "button", "button": int(descriptor.get("button", 0))})
			"axis":
				clean.append({
					"type": "axis",
					"axis": int(descriptor.get("axis", 0)),
					"value": float(descriptor.get("value", 0.0)),
				})
	return clean

# --- editing ----------------------------------------------------------------

func _device_group(descriptor: Dictionary) -> String:
	return "key" if String(descriptor.get("type", "")) == "key" else "joy"

func _same_binding(a: Dictionary, b: Dictionary) -> bool:
	if String(a.get("type", "")) != String(b.get("type", "")):
		return false
	match String(a.get("type", "")):
		"key":
			return int(a.get("code", 0)) == int(b.get("code", 0))
		"button":
			return int(a.get("button", 0)) == int(b.get("button", 0))
		"axis":
			return int(a.get("axis", 0)) == int(b.get("axis", 0)) \
				and is_equal_approx(float(a.get("value", 0.0)), float(b.get("value", 0.0)))
	return false

## Rebinds `action` to `event`, replacing only bindings of the same device, so a
## new keyboard key does not wipe the gamepad binding and vice versa.
## Returns the conflicting action name (which loses the binding), or "".
func rebind(action: String, event: InputEvent, save := true) -> String:
	if not ACTION_ORDER.has(action):
		return ""
	var descriptor := _describe(event)
	if descriptor.is_empty():
		return ""

	var group := _device_group(descriptor)
	var conflicted := ""

	for other in ACTION_ORDER:
		if other == action:
			continue
		var kept := []
		for existing in bindings.get(other, []):
			if _device_group(existing) == group and _same_binding(existing, descriptor):
				conflicted = other
				continue
			kept.append(existing)
		bindings[other] = kept

	var replaced := []
	for existing in bindings.get(action, []):
		if _device_group(existing) != group:
			replaced.append(existing)
	replaced.append(descriptor)
	bindings[action] = replaced

	_apply_action(action)
	for other in ACTION_ORDER:
		if other != action:
			_apply_action(other)
	if save:
		_save()
	bindings_changed.emit()
	return conflicted

func reset_to_defaults(save := true) -> void:
	bindings = _default_bindings()
	_apply_all()
	if save:
		_save()
	bindings_changed.emit()

# --- display ----------------------------------------------------------------

func binding_text(action: String) -> String:
	var parts := []
	for descriptor in bindings.get(action, []):
		match String(descriptor.get("type", "")):
			"key":
				var code := int(descriptor.get("code", 0))
				parts.append(OS.get_keycode_string(code))
			"button":
				var button := int(descriptor.get("button", 0))
				parts.append(JOY_NAMES.get(button, "手柄键%d" % button))
			"axis":
				var axis := int(descriptor.get("axis", 0))
				var sign_text := "+" if float(descriptor.get("value", 0.0)) > 0.0 else "-"
				parts.append("%s%s" % [AXIS_NAMES.get(axis, "轴%d" % axis), sign_text])
	if parts.is_empty():
		return "未绑定"
	return " / ".join(parts)
