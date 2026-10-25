extends SceneTree

# Verifies the semantic input layer: default bindings, keyboard/gamepad
# rebinding isolation, conflict removal, reset, persistence, and the buffer.

const SAVE_PATH := "user://input_bindings.cfg"

func _initialize() -> void:
	_run.call_deferred()

func _fail(failures: int, message: String) -> int:
	print("FAIL: ", message)
	return failures + 1

func _run() -> void:
	var failures := 0
	var InputActions = load("res://game/input_actions.gd").new()
	get_root().add_child(InputActions)
	await process_frame

	if not SAVE_PATH.is_empty() and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	InputActions.reset_to_defaults(false)
	await process_frame

	# 1. Defaults are registered into InputMap.
	for action in InputActions.ACTION_ORDER:
		if not InputMap.has_action(action):
			failures = _fail(failures, "action not registered: " + action)
	print("actions_registered=", InputActions.ACTION_ORDER.size())

	# 2. A gamepad binding exists for movement, jump, attack, dash and era switch.
	for action in ["jump", "attack", "dash", "switch_era", "move_left", "move_right"]:
		var has_joy := false
		for descriptor in InputActions.bindings[action]:
			if String(descriptor.get("type", "")) != "key":
				has_joy = true
		if not has_joy:
			failures = _fail(failures, "no gamepad binding for " + action)
	print("gamepad_bindings_ok")

	# 3. Rebinding with a key must keep the existing gamepad binding.
	var before_count: int = InputActions.bindings["jump"].size()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Z
	InputActions.rebind("jump", key, false)
	var after = InputActions.bindings["jump"]
	var kept_joy := false
	var has_z := false
	for descriptor in after:
		if String(descriptor.get("type", "")) == "button":
			kept_joy = true
		if String(descriptor.get("type", "")) == "key" and int(descriptor.get("code", 0)) == KEY_Z:
			has_z = true
	if not kept_joy:
		failures = _fail(failures, "keyboard rebind wiped the gamepad binding")
	if not has_z:
		failures = _fail(failures, "new key was not stored")
	print("rebind_kept_pad size ", before_count, " -> ", after.size())

	# 4. Rebinding to a key already used by another action removes it there.
	InputActions.reset_to_defaults(false)
	var taken := InputEventKey.new()
	taken.physical_keycode = KEY_SPACE
	var conflicted: String = InputActions.rebind("attack", taken, false)
	print("conflict_from=", conflicted)
	if conflicted != "jump":
		failures = _fail(failures, "expected jump to lose the space key, got '%s'" % conflicted)
	for descriptor in InputActions.bindings["jump"]:
		if String(descriptor.get("type", "")) == "key" and int(descriptor.get("code", 0)) == KEY_SPACE:
			failures = _fail(failures, "space is still bound to jump")

	# 5. The InputMap actually reflects the change.
	var jump_has_space := false
	for event in InputMap.action_get_events("jump"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_SPACE:
			jump_has_space = true
	if jump_has_space:
		failures = _fail(failures, "InputMap still has space on jump")
	print("inputmap_synced")

	# 6. Gamepad rebinding keeps the keyboard binding.
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
	InputActions.rebind("dash", pad, false)
	var dash_keys := 0
	var dash_pad := false
	for descriptor in InputActions.bindings["dash"]:
		if String(descriptor.get("type", "")) == "key":
			dash_keys += 1
		if String(descriptor.get("type", "")) == "button" \
				and int(descriptor.get("button", 0)) == JOY_BUTTON_RIGHT_SHOULDER:
			dash_pad = true
	if dash_keys == 0:
		failures = _fail(failures, "gamepad rebind wiped keyboard bindings")
	if not dash_pad:
		failures = _fail(failures, "gamepad button was not stored")
	print("pad_rebind_kept_keys=", dash_keys)

	# 7. A press is buffered and can be consumed exactly once.
	var buffer = load("res://game/input_buffer.gd").new()
	buffer.press(0.15)
	if not buffer.is_active():
		failures = _fail(failures, "buffer did not arm")
	if not buffer.consume():
		failures = _fail(failures, "buffer did not consume")
	if buffer.consume():
		failures = _fail(failures, "buffer consumed twice")
	print("buffer_single_consume")

	# 8. A buffered press expires after its window.
	buffer.press(0.05)
	buffer.tick(0.06)
	if buffer.is_active():
		failures = _fail(failures, "buffer did not expire")
	print("buffer_expiry")

	# 9. Persistence: save, reset in memory, reload from disk.
	InputActions.reset_to_defaults(true)
	await process_frame
	var key_d := InputEventKey.new()
	key_d.physical_keycode = KEY_L
	InputActions.rebind("dash", key_d, true)
	await process_frame
	var reloaded = load("res://game/input_actions.gd").new()
	reloaded._load()
	var saved_key := false
	for descriptor in reloaded.bindings["dash"]:
		if String(descriptor.get("type", "")) == "key" and int(descriptor.get("code", 0)) == KEY_L:
			saved_key = true
	if not saved_key:
		failures = _fail(failures, "rebind was not persisted to disk")
	print("persistence_ok")
	reloaded.free()

	# 10. Reset restores defaults.
	reloaded = null
	var restored_keys := 0
	InputActions.reset_to_defaults(false)
	for descriptor in InputActions.bindings["dash"]:
		if String(descriptor.get("type", "")) == "key":
			restored_keys += 1
	if restored_keys != 1:
		failures = _fail(failures, "reset did not restore default dash keys")
	print("reset_ok")

	# 11. binding_text always returns something human-readable.
	for action in InputActions.ACTION_ORDER:
		var text: String = InputActions.binding_text(action)
		if text.is_empty():
			failures = _fail(failures, "empty binding text for " + action)
	print("sample_text=", InputActions.binding_text("jump"))

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)
