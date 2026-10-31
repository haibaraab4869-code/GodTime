extends SceneTree

## 集成回归：在真实 `main.tscn` 上验证状态机行为。
## 覆盖 —— 换相三阶段与代价、穷奇突刺的能力门保护、麒麟回血流程、
## 受击打断、闪避无敌与精准闪避、HUD 信号链路。

const Config := preload("res://game/combat_config.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		print("FAIL: ", message)
		failures += 1

func _run() -> void:
	var scene: PackedScene = load("res://game/main.tscn")
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame

	var player = root.get_node("Player")
	_check(player.combat.form == "taotie", "default form should be taotie")
	_check(player.maximum_health == 4, "default max health should be 4")
	_check(is_equal_approx(player.move_speed, 300.0), "move_speed should be re-scaled to 300")
	_check(is_equal_approx(player.jump_speed, 660.0), "jump_speed should be re-scaled to 660")

	_test_form_speed_scaling(player)
	_test_shift_sequence(player)
	_test_force_form_at_checkpoint(player)
	_test_heavy_lunge_guard(root, player)
	_test_qilin_heal_flow(player)
	_test_hurt_interrupts_heal(player)
	_test_dodge_invulnerability(player)
	_test_mark_lifecycle(root, player)

	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)

# --- 1. 流派移速倍率 -----------------------------------------------------
func _test_form_speed_scaling(player) -> void:
	var expected := {
		"taotie": 1.00, "qiongqi": 1.08, "taowu": 0.92, "hundun": 0.96,
	}
	for form in Config.FORM_ORDER:
		player.force_form(form)
		var speed: float = Config.form_speed(player.move_speed, form)
		var ratio := speed / 300.0
		print("speed_%s=%.1f (x%.2f)" % [form, speed, ratio])
		_check(is_equal_approx(ratio, float(expected[form])),
			"%s speed multiplier should be %.2f" % [form, expected[form]])
	player.force_form("taotie")

# --- 2. 换相三阶段 -------------------------------------------------------
func _test_shift_sequence(player) -> void:
	# 默认关闭战斗内换相（守立项案"在存档点切换"）。
	_check(not player.combat.can_shift_in_field(), "field shift must be off by default")
	player.combat.qi = 70
	player.shift_buffer.press(0.1)
	player._try_begin_shift()
	_check(player.shift_phase == 0, "shift must be refused while the field shift is disabled")
	_check(player.combat.qi == 70, "a refused shift must not consume qi")
	player.shift_buffer.clear()

	# 手动打开提案 B，验证三阶段与总时长 1.48s。
	Config.set_field_shift_enabled(true)
	player.combat.shift_cooldown_remaining = 0.0
	player.shift_buffer.press(0.1)
	player._try_begin_shift()
	_check(player.shift_phase == 2, "shift should enter the fade-out phase")
	_check(player.shift_target_form == "qiongqi", "shift should cycle to the next form")

	var elapsed := 0.0
	var saw_blank := false
	var saw_fade_in := false
	while player.shift_phase != 0 and elapsed < 3.0:
		player._tick_shift(0.05)
		elapsed += 0.05
		if player.shift_phase == 3:
			saw_blank = true
		if player.shift_phase == 4:
			saw_fade_in = true
	print("shift_elapsed=%.2f blank=%s fade_in=%s form=%s qi=%d" % [
		elapsed, str(saw_blank), str(saw_fade_in), player.combat.form, player.combat.qi])
	_check(saw_blank, "shift must pass through the blank silhouette phase")
	_check(saw_fade_in, "shift must end with the fade-in phase")
	_check(player.combat.form == "qiongqi", "shift should land on 穷奇")
	_check(player.combat.qi == 0, "shift must clear qi")
	_check(absf(elapsed - 1.484) < 0.12, "shift total should be ~1.48s, got %.2f" % elapsed)
	_check(player.combat.shift_cooldown_remaining > 11.0, "shift should start a ~12s cooldown")

	# 冷却内不可再次换相。
	player.shift_buffer.press(0.1)
	player._try_begin_shift()
	_check(player.shift_phase == 0, "shift must be blocked during cooldown")
	player.shift_buffer.clear()

	Config.set_field_shift_enabled(false)
	player.combat.shift_cooldown_remaining = 0.0

# --- 3. 存档点换相 -------------------------------------------------------
func _test_force_form_at_checkpoint(player) -> void:
	player.combat.qi = 50
	player.combat.reverse_stacks = 4
	player.force_form("taowu")
	print("force_form=%s qi=%d reverse=%d" % [player.combat.form, player.combat.qi, player.combat.reverse_stacks])
	_check(player.combat.form == "taowu", "checkpoint shift should change form")
	_check(player.combat.qi == 0, "checkpoint shift must clear qi (原案)")
	_check(player.combat.reverse_stacks == 0, "checkpoint shift must clear temporary buffs (原案)")
	# 存档点换相不受冷却限制。
	_check(player.shift_phase == 0, "checkpoint shift is instant, no performance lock")
	player.force_form("taotie")

# --- 4. 穷奇突刺不得跨越缺口（能力门保护）------------------------------
func _test_heavy_lunge_guard(root, player) -> void:
	# 把玩家放到平台右边缘之外（前方没有地面）观察冲量是否被取消。
	var floor_rect: Rect2 = root._geometry(false)[0]
	player.global_position = Vector2(floor_rect.end.x + 30.0, floor_rect.position.y - 46.0)
	player.velocity = Vector2.ZERO
	player.force_form("qiongqi")
	var has_ground: bool = player._ground_ahead(1, 24.0)
	print("ground_ahead_over_gap=%s" % str(has_ground))
	_check(not has_ground, "there should be no ground beyond the platform edge")

	player.velocity = Vector2.ZERO
	player._try_heavy_lunge()
	print("velocity_after_guarded_lunge=%.1f" % player.velocity.x)
	_check(is_zero_approx(player.velocity.x),
		"RED LINE: qiongqi lunge must not fire without ground ahead")

	# 站在平台中央时应允许冲量（显式传入探测结果，避免依赖当帧物理状态）。
	player.global_position = Vector2(floor_rect.position.x + 40.0, floor_rect.position.y - 46.0)
	player.velocity = Vector2.ZERO
	player._try_heavy_lunge_with(true)
	_check(player.velocity.x > 0.0, "lunge should apply when ground exists ahead")
	player.force_form("taotie")

# --- 5. 麒麟回血流程 -----------------------------------------------------
func _test_qilin_heal_flow(player) -> void:
	player.set_qilin_level(1)
	print("after_qilin health=%d/%d charges=%d" % [
		player.health, player.maximum_health, player.abilities.heal_charges_left()])
	_check(player.maximum_health == 6, "L1 qilin should raise max health to 6")
	_check(player.abilities.heal_charges_left() == 2, "L1 should give 2 heal charges")

	# 满血不可回。
	_check(not player.try_heal(), "full health must refuse healing")
	_check(player.abilities.heal_charges_left() == 2, "refused heal must not consume a charge")

	player.health = 3
	_check(player.try_heal(), "damaged player should start healing")
	# 推进到结算点（0.55s）。
	var steps := 0
	while player.abilities.healing_remaining > 0.0 and steps < 200:
		player._tick_heal(0.02)
		steps += 1
	print("after_heal health=%d/%d charges=%d" % [
		player.health, player.maximum_health, player.abilities.heal_charges_left()])
	_check(player.health == 4, "heal should restore exactly 1 health")
	_check(player.abilities.heal_charges_left() == 1, "a completed heal consumes one charge")
	_check(player.abilities.healing_remaining <= 0.0, "heal timer should finish")

# --- 6. 受击打断回血，且不消耗次数 --------------------------------------
func _test_hurt_interrupts_heal(player) -> void:
	player.health = 4
	player.invuln_remaining = 0.0
	var charges_before: int = player.abilities.heal_charges_left()
	_check(player.try_heal(), "heal should start")
	_check(player.abilities.healing_remaining > 0.0, "heal timer should be running")
	player._tick_heal(0.1)
	player.take_damage(1)
	print("after_hit healing_remaining=%.2f charges=%d health=%d" % [
		player.abilities.healing_remaining, player.abilities.heal_charges_left(), player.health])
	_check(player.abilities.healing_remaining <= 0.0, "taking damage must interrupt the heal")
	_check(player.abilities.heal_charges_left() == charges_before, "an interrupted heal must not consume a charge")
	_check(player.health == 3, "the damage itself still applies")
	_check(player.hurt_remaining > 0.0, "taking damage should enter a hurt state")

# --- 7. 闪避无敌与精准闪避 ----------------------------------------------
func _test_dodge_invulnerability(player) -> void:
	player.force_form("qiongqi")
	player.health = 6
	player.hurt_remaining = 0.0
	player.abilities.heal_charges_used = 0
	player.invuln_remaining = 0.3
	player.precise_window_remaining = 0.18
	player.combat.qi = 0
	player.take_damage(2)
	print("during_invuln health=%d qi=%d" % [player.health, player.combat.qi])
	_check(player.health == 6, "damage during dodge i-frames must be ignored")
	_check(player.combat.qi == 15, "precise dodge should grant 15 qi")
	_check(player.combat.is_sharp(), "precise dodge should arm the sharp window")

	# 无敌结束后照常吃伤害。
	player.invuln_remaining = 0.0
	player.precise_window_remaining = 0.0
	player.hurt_remaining = 0.0
	player.take_damage(2)
	_check(player.health == 4, "damage after i-frames must apply")
	player.force_form("taotie")

# --- 8. 形态标记生命周期 -------------------------------------------------
func _test_mark_lifecycle(root, player) -> void:
	var dummy = root.get_node("Targets").get_node("DummyStart")
	dummy.health = dummy.maximum_health
	dummy.global_position = player.global_position + Vector2(20, -12)

	player.force_form("hundun")
	# 末段挂乱痕。
	player.combo_index = Config.combo_length("hundun") - 1
	player.attack_buffer.press(0.2)
	player.combo_grace_remaining = 0.0
	player.attack_cooldown_remaining = 0.0
	player._start_combo_segment()
	_check(player.combo_index == 0, "combo index should restart when no grace window is open")
	# 直接推进到末段。
	player.combo_grace_remaining = 0.5
	player._start_combo_segment()
	player.combo_grace_remaining = 0.5
	player._start_combo_segment()
	print("hundun_combo_index=%d marks=%s" % [player.combo_index, str(player.target_marks(dummy))])
	_check(player.combo_index == 2, "third segment should be the chaos-mark segment")

	player.attack_hit_nodes.clear()
	player._apply_attack_hits()
	var marks: Dictionary = player.target_marks(dummy)
	print("marks_after_hit=%s" % str(marks))
	_check(int(marks.get("chaos", 0)) == 1, "the final segment should apply one chaos mark")

	# 引爆清空痕迹。
	player._heavy_resolved = {"mark_consumed": "chaos"}
	player._consume_marks_on(dummy, "chaos")
	_check(int(player.target_marks(dummy).get("chaos", 0)) == 0, "explosion must consume the chaos marks")
	player.force_form("taotie")
