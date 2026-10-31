extends SceneTree

## 视觉层回归：确认骨骼 rig 已接入主场景，且动画状态机按预期切换。
##
## 覆盖：rig 节点存在、骨骼/动画数量、脚底与碰撞盒对齐、朝向翻转、
## 待机/移动/跳跃/落地/冲刺/攻击/受击/死亡重生的动画切换。
##
## 运行：Godot --headless --path <项目根> --script res://tests/test_visual.gd
## 末行 FAILURES=0 且退出码为 0 表示通过。

const EXPECTED_CLIPS := ["attack", "dash", "era_switch", "fall", "hurt", "idle",
		"jump", "land", "respawn", "run", "turn"]

var failures := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	var root := packed.instantiate()
	root.persist_progress = false
	get_root().add_child(root)
	await process_frame

	var player = root.get_node("Player")
	var rig: Node2D = player.get_node_or_null("Rig")

	_check(rig != null, "Player has a Rig child")
	if rig == null:
		print("FAILURES=%d" % failures)
		quit(1)
		return

	# --- 骨骼与动画 ---
	var skeleton: Skeleton2D = rig.get_node_or_null("Skeleton2D")
	_check(skeleton != null, "rig has Skeleton2D")
	_check(skeleton.get_bone_count() == 15, "rig has 15 bones, got %d" % skeleton.get_bone_count())

	var player_anim: AnimationPlayer = rig.get_node_or_null("AnimationPlayer")
	_check(player_anim != null, "rig has AnimationPlayer")
	if player_anim != null:
		var names: PackedStringArray = player_anim.get_animation_list()
		_check(names.size() == 11, "rig has 11 animations, got %d" % names.size())
		for clip in EXPECTED_CLIPS:
			_check(clip in names, "clip '%s' exists" % clip)

	# --- 部件数量 ---
	var sprites := 0
	var stack: Array[Node] = [rig]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Sprite2D:
			sprites += 1
		for c in n.get_children():
			stack.append(c)
	_check(sprites == 16, "rig contains 16 part sprites, got %d" % sprites)

	# --- 脚底对齐碰撞盒 ---
	# 部件画布脚底 y=120，Skeleton2D 偏移 -88，故本地脚底 32；rig 位于 (0,4) 且 y 缩放 0.5
	var feet_y: float = rig.position.y + 32.0 * rig.scale.y
	_check(absf(feet_y - 20.0) < 0.01, "feet align with collision box bottom (+20), got %.2f" % feet_y)

	# --- 朝向翻转 ---
	player.facing = 1
	player._update_visual(0.016)
	_check(rig.scale.x > 0.0, "facing right -> positive scale.x")
	player.facing = -1
	player._update_visual(0.016)
	_check(rig.scale.x < 0.0, "facing left -> negative scale.x")

	# --- 待机 ---
	# 先让物理跑几帧，确保角色已落在生成点的地面上（无头模式只跑一帧不会落地）
	player.facing = 1
	player.velocity = Vector2.ZERO
	player.position = root.Maps.anchor("W01", "rest")
	for i in range(12):
		await physics_frame
	_check(player.is_on_floor(), "player settled on floor before locomotion checks")
	player.facing = 1
	player.velocity = Vector2.ZERO
	player._override_left = 0.0
	player._override = ""
	player._update_visual(0.016)
	_check(player._clip == "idle", "idle at rest, got '%s'" % player._clip)

	# --- 移动 ---
	player.velocity = Vector2(240, 0)
	player._update_visual(0.016)
	_check(player._clip == "run", "run while moving, got '%s'" % player._clip)

	# --- 跳跃 / 下落（必须真正离地，is_on_floor 优先于速度判断）---
	player._override = ""
	player._override_left = 0.0
	player.velocity = Vector2(0, -420)
	await physics_frame
	await physics_frame
	player._override = ""
	player._override_left = 0.0
	player._update_visual(0.016)
	_check(not player.is_on_floor(), "player airborne for jump/fall checks")
	_check(player._clip == "jump", "jump while rising, got '%s'" % player._clip)
	player.velocity = Vector2(0, 300)
	player._update_visual(0.016)
	_check(player._clip == "fall", "fall while descending, got '%s'" % player._clip)

	# --- 一次性动作 ---
	player.velocity = Vector2.ZERO
	player._trigger("attack", 0.16)
	_check(player._clip == "attack", "attack trigger, got '%s'" % player._clip)

	player._trigger("dash", 0.16)
	_check(player._clip == "attack", "dash must not interrupt attack (priority), got '%s'" % player._clip)

	player._trigger("hurt", 0.32)
	_check(player._clip == "hurt", "hurt outranks attack, got '%s'" % player._clip)

	player._trigger("land", 0.2)
	_check(player._clip == "hurt", "land must not interrupt hurt, got '%s'" % player._clip)

	# 受击动画结束后回到位移状态
	player._override_left = 0.0
	player._override = ""
	player.velocity = Vector2.ZERO
	player._update_visual(0.016)
	_check(player._clip == "idle" or player._clip == "fall" or player._clip == "jump",
			"returns to locomotion after override, got '%s'" % player._clip)

	# --- 受击入口真的会触发 ---
	player._override = ""
	player._override_left = 0.0
	player.take_damage(1)
	_check(player._clip == "hurt", "take_damage triggers hurt clip, got '%s'" % player._clip)

	# --- 重生入口 ---
	player._override = ""
	player._override_left = 0.0
	player.respawn()
	_check(player._clip == "respawn", "respawn triggers respawn clip, got '%s'" % player._clip)

	# --- 占位绘制已停用 ---
	_check(player.rig != null, "player holds a rig reference")

	# Switching from a full-body pose to a partial clip must restore unkeyed bones.
	player._override_left = 0.0
	player._trigger("dash", 0.16)
	player_anim.advance(0.08)
	var leg: Bone2D = rig.get_node("Skeleton2D/root/leg_near_thigh")
	_check(absf(leg.rotation) > 0.1, "dash visibly bends the leg")
	player._override_left = 0.0
	player._trigger("era_switch", 0.5)
	_check(absf(leg.rotation) < 0.001, "era switch clears the previous dash leg pose")

	# The complete attack clip must fit inside the actual gameplay swing.
	player._override_left = 0.0
	player._trigger("attack", player.attack_duration)
	_check(absf(player_anim.get_playing_speed() * player.attack_duration
			- player_anim.get_animation("attack").length) < 0.001,
			"attack animation duration matches the gameplay swing")
	player._override_left = 0.0
	player._trigger("land", 0.2)
	player_anim.advance(0.08)
	player._override_left = 0.0
	player._trigger("hurt", 0.32)
	var root_bone: Bone2D = rig.get_node("Skeleton2D/root")
	_check(root_bone.scale.is_equal_approx(Vector2.ONE), "hurt clears landing squash")

	print("FAILURES=%d" % failures)
	root.queue_free()
	quit(0 if failures == 0 else 1)
