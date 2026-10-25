extends SceneTree

# Temporary verification harness. Uses process_frame so nodes are inside the
# tree before the attack hit test runs (group lookup requires a live tree).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var scene: PackedScene = load("res://game/main.tscn")
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame

	var player = root.get_node("Player")
	var dummies := root.get_node("Targets").get_children()
	print("dummy_count=", dummies.size())
	if dummies.size() != 3:
		print("FAIL: expected 3 training targets")
		failures += 1

	# 1. Attack box points in the facing direction.
	player.facing = 1
	var right_box: Rect2 = player.attack_box()
	player.facing = -1
	var left_box: Rect2 = player.attack_box()
	print("right_box=", right_box, " left_box=", left_box)
	if right_box.position.x <= 0.0:
		print("FAIL: right-facing box should extend to +x")
		failures += 1
	if left_box.position.x >= 0.0:
		print("FAIL: left-facing box should extend to -x")
		failures += 1

	# 2. Target inside reach is hit once; one far away is not hit.
	player.facing = 1
	var dummy = dummies[0]
	dummy.global_position = player.global_position + Vector2(20, -12)
	var before: int = dummy.health
	player.attack_hit_nodes.clear()
	player._apply_attack_hits()
	print("near_hit health ", before, " -> ", dummy.health)
	if dummy.health != before - 1:
		print("FAIL: nearby target was not damaged")
		failures += 1

	var far = dummies[1]
	far.global_position = player.global_position + Vector2(400, -12)
	var far_before: int = far.health
	player._apply_attack_hits()
	if far.health != far_before:
		print("FAIL: distant target was damaged")
		failures += 1

	# 3. One swing may not damage the same target twice.
	dummy.global_position = player.global_position + Vector2(20, -12)
	dummy.health = dummy.maximum_health
	player.attack_hit_nodes.clear()
	var swing_before: int = dummy.health
	player._apply_attack_hits()
	player._apply_attack_hits()
	print("multi_hit health ", swing_before, " -> ", dummy.health)
	if dummy.health != swing_before - 1:
		print("FAIL: one swing applied damage more or less than once")
		failures += 1

	# 4. A fresh swing (cleared list) may damage the same target again.
	player.attack_hit_nodes.clear()
	player._apply_attack_hits()
	print("next_swing health -> ", dummy.health)
	if dummy.health != swing_before - 2:
		print("FAIL: a new swing did not damage the target again")
		failures += 1

	# 4. A target behind the player is not hit while facing forward.
	var behind = dummies[2]
	behind.global_position = player.global_position + Vector2(-20, -12)
	var behind_before: int = behind.health
	player.attack_hit_nodes.clear()
	player._apply_attack_hits()
	print("behind health ", behind_before, " -> ", behind.health)
	if behind.health != behind_before:
		print("FAIL: target behind the player was damaged")
		failures += 1

	# 5. A target entering range mid-swing is still hit exactly once.
	var late = dummies[1]
	late.global_position = player.global_position + Vector2(400, -12)
	late.health = late.maximum_health
	player.attack_hit_nodes.clear()
	player.attack_buffer.press(player.attack_buffer_window)
	player.attack_cooldown_remaining = 0.0
	player._update_attack(0.016)
	if not player.is_attacking():
		print("FAIL: swing did not start")
		failures += 1
	var late_before: int = late.health
	player._update_attack(0.016)
	if late.health != late_before:
		print("FAIL: out-of-range target was hit on swing start")
		failures += 1
	late.global_position = player.global_position + Vector2(20, -12)
	player._update_attack(0.016)
	print("mid_swing_entry health ", late_before, " -> ", late.health)
	if late.health != late_before - 1:
		print("FAIL: target entering range mid-swing was not hit")
		failures += 1
	player._update_attack(0.016)
	if late.health != late_before - 1:
		print("FAIL: mid-swing target was damaged twice")
		failures += 1

	# 6. Target breaks at zero health and reports it.
	dummy.health = 1
	dummy.respawn_remaining = 0.0
	dummy.take_damage(1)
	print("broken=", dummy.is_broken(), " health=", dummy.health)
	if not dummy.is_broken():
		print("FAIL: dummy did not break at zero health")
		failures += 1

	# 6. Damage while broken is ignored.
	dummy.take_damage(5)
	print("broken_health=", dummy.health, " respawn_in=", dummy.respawn_remaining)
	if dummy.health != 0:
		print("FAIL: broken target took further damage")
		failures += 1

	# 7. Era switching must not crash or disturb the player.
	root._switch_era()
	root._switch_era()
	print("era_switch_ok past_era=", root.past_era)

	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)
