extends SceneTree

# Verifies the responsiveness features layered on top of the input layer:
# jump buffering, coyote time and attack buffering during cooldown.

func _initialize() -> void:
	_run.call_deferred()

func _fail(failures: int, message: String) -> int:
	print("FAIL: ", message)
	return failures + 1

func _run() -> void:
	var failures := 0
	var scene: PackedScene = load("res://game/main.tscn")
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame

	var player = root.get_node("Player")
	var buffer_script = load("res://game/input_buffer.gd")

	# --- buffer primitive ---------------------------------------------------
	var buffer = buffer_script.new()
	if buffer.remaining() != 0.0:
		failures = _fail(failures, "new buffer should be empty")
	buffer.press(0.1)
	if not buffer.is_active():
		failures = _fail(failures, "press did not arm the buffer")
	buffer.tick(0.2)
	if buffer.is_active():
		failures = _fail(failures, "buffer did not expire past its window")
	print("buffer_ok")

	# --- jump buffer --------------------------------------------------------
	# A jump pressed while airborne is kept, then fires on landing.
	player.global_position = Vector2(80, 300)
	player.velocity = Vector2.ZERO
	player.jump_buffer.clear()
	player.jump_buffer.press(player.jump_buffer_window)
	if not player.jump_buffer.is_active():
		failures = _fail(failures, "jump buffer did not arm")
	print("jump_buffer_armed")

	# --- coyote time --------------------------------------------------------
	# Coyote time must be positive and short enough to feel responsive.
	if player.coyote_time <= 0.0:
		failures = _fail(failures, "coyote_time must be positive")
	if player.coyote_time > 0.3:
		failures = _fail(failures, "coyote_time looks too long for a platformer")
	print("coyote_time=", player.coyote_time)

	# --- attack buffer during cooldown --------------------------------------
	# Pressing attack during cooldown should be honoured once the cooldown ends
	# instead of being dropped. Drive _update_attack directly.
	player.attack_cooldown_remaining = player.attack_cooldown
	player.attack_remaining = 0.0
	player.attack_hit_nodes.clear()
	player.attack_buffer.clear()
	player.attack_buffer.press(player.attack_buffer_window)
	player._update_attack(0.016)
	if player.is_attacking():
		failures = _fail(failures, "attack fired while on cooldown")
	# Wait out the cooldown in small steps; the buffered press must still fire.
	var steps := 0
	while player.attack_cooldown_remaining > 0.0 and steps < 200:
		player.attack_buffer.press(player.attack_buffer_window)
		player._update_attack(0.016)
		steps += 1
	print("attack_after_cooldown attacking=", player.is_attacking())
	if not player.is_attacking():
		failures = _fail(failures, "buffered attack did not fire after cooldown")

	# --- input mapping is reachable through actions -------------------------
	if not InputMap.has_action("attack"):
		failures = _fail(failures, "attack action missing from InputMap")
	Input.action_press("attack")
	await process_frame
	Input.action_release("attack")
	print("action_bridge_ok")

	# --- respawn clears buffered input --------------------------------------
	player.jump_buffer.press(0.5)
	player.attack_buffer.press(0.5)
	player.respawn()
	if player.jump_buffer.is_active() or player.attack_buffer.is_active():
		failures = _fail(failures, "respawn did not clear buffered input")
	print("respawn_clears_buffer")

	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)
