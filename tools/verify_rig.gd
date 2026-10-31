extends SceneTree

## 骨骼 rig 校验：确认骨骼层级、部件对位、动画确实驱动骨骼。
## 运行：Godot --headless --path <项目根> --script res://tools/verify_rig.gd

const RIG_PATH := "res://assets/characters/shihung/rig/shihung_rig.tscn"
const CENTER := 64.0
const HIP_Y := 88.0

const ARM_NEAR_X := 73.0
const ARM_FAR_X := 54.0
const LEG_FAR_X := 60.0

const PART_PIVOTS := {
	"crown": Vector2(64, 8),
	"head": Vector2(64, 45),
	"torso": Vector2(64, 88),
	"hem_back": Vector2(64, 84),
	"hem_front": Vector2(64, 84),
	"sash_1": Vector2(58, 80),
	"sash_2": Vector2(54, 85),
	"gold_line": Vector2(64, 88),
	"arm_near_upper": Vector2(ARM_NEAR_X, 50),
	"arm_near_lower": Vector2(ARM_NEAR_X, 67),
	"arm_far_upper": Vector2(ARM_FAR_X, 50),
	"arm_far_lower": Vector2(ARM_FAR_X, 67),
	"leg_near_thigh": Vector2(64, 88),
	"leg_near_shin": Vector2(64, 103),
	"leg_far_thigh": Vector2(LEG_FAR_X, 88),
	"leg_far_shin": Vector2(LEG_FAR_X, 103),
}

var failures := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(RIG_PATH)
	_check(packed != null, "rig scene loads")
	if packed == null:
		quit(1)
		return

	var rig: Node2D = packed.instantiate()
	get_root().add_child(rig)
	await process_frame

	var skeleton: Skeleton2D = rig.get_node_or_null("Skeleton2D")
	_check(skeleton != null, "Skeleton2D exists")
	_check(skeleton.get_bone_count() == 15, "bone count == 15 (got %d)" % skeleton.get_bone_count())

	var player: AnimationPlayer = rig.get_node_or_null("AnimationPlayer")
	_check(player != null, "AnimationPlayer exists")
	var names: PackedStringArray = player.get_animation_list()
	var expected := ["attack", "dash", "era_switch", "fall", "hurt", "idle", "jump", "land",
			"respawn", "run", "turn"]
	for n in expected:
		_check(n in names, "animation '%s' present" % n)
	_check(names.size() == 11, "exactly 11 animations (got %d)" % names.size())

	# 部件对位：sprite 顶点应等于 (枢轴 - (CENTER, HIP_Y))
	print("-- part placement --")
	var bad := 0
	for part_name in PART_PIVOTS.keys():
		var spr := _find_sprite(rig, part_name)
		if spr == null:
			print("  FAIL missing sprite for ", part_name)
			failures += 1
			bad += 1
			continue
		var want: Vector2 = PART_PIVOTS[part_name] - Vector2(CENTER, HIP_Y)
		var got: Vector2 = spr.global_position - rig.global_position
		if got.distance_to(want) > 1.0:
			print("  FAIL %s at %s want %s" % [part_name, got, want])
			failures += 1
			bad += 1
	_check(bad == 0, "all 16 parts sit at their pivot (%d bad)" % bad)

	# 动画是否真的改变骨骼
	print("-- animation drives bones --")
	for anim_name in expected:
		var bones := ["Skeleton2D/root/torso", "Skeleton2D/root/leg_near_thigh",
				"Skeleton2D/root/torso/arm_near_upper"]
		var moved := 0
		var samples := []
		for bpath in bones:
			var bone: Bone2D = rig.get_node_or_null(bpath)
			if bone == null:
				continue
			player.play(anim_name)
			player.seek(0.0, true)
			var r0 := bone.rotation
			player.seek(player.get_animation(anim_name).length * 0.45, true)
			var r1 := bone.rotation
			if absf(r1 - r0) > 0.01:
				moved += 1
			samples.append("%s:%.3f->%.3f" % [bone.name, r0, r1])
		_check(moved > 0, "%s changes >=1 bone  [%s]" % [anim_name, ", ".join(samples)])

	# 布料跟动：下摆骨必须在位移类动画里真的摆动，否则裙子会像木板一样僵硬
	print("-- cloth follow --")
	var hem: Bone2D = rig.get_node_or_null("Skeleton2D/root/hem_back")
	_check(hem != null, "hem bone exists")
	if hem != null:
		for clip in ["run", "fall", "dash"]:
			player.play(clip)
			player.seek(0.0, true)
			var h0 := hem.rotation
			# 逐点取样取最大偏移：布料摆动是往复的，单点可能正好落回原位
			var swing := 0.0
			var length: float = player.get_animation(clip).length
			for i in range(1, 9):
				player.seek(length * float(i) / 8.0, true)
				swing = maxf(swing, absf(hem.rotation - h0))
			_check(swing > 0.05, "%s swings hem (max delta %.3f rad)" % [clip, swing])

	# 动画结束后骨骼应回到静止姿态
	print("-- rest pose restored --")
	player.stop()
	await process_frame
	var torso: Bone2D = rig.get_node("Skeleton2D/root/torso")
	_check(absf(torso.rotation) < 0.02, "torso back to rest rotation (%.4f)" % torso.rotation)

	# 视角声明（docs/art/README.md 规则 G-1 / G-3）：主角必须是 side、可翻转、且部件名不含 front/back
	print("-- view class --")
	for pn in PART_PIVOTS.keys():
		# front/back 只允许用于「身前/身后」（hem_front / hem_back = 前摆/后摆）；
		# 用来表达肢体左右（纵深）则是侧视命名错误，应改 near/far。
		var lateral_fore_aft: bool = (pn.begins_with("arm_front") or pn.begins_with("arm_back")
				or pn.begins_with("leg_front") or pn.begins_with("leg_back"))
		_check(not lateral_fore_aft, "%s 未用 front/back 表达左右（应用 near/far）" % pn)

	var f := FileAccess.open("res://assets/characters/shihung/parts/parts.json", FileAccess.READ)
	_check(f != null, "parts.json readable")
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			var spec: Dictionary = parsed
			_check(String(spec.get("view_class", "")) == "side",
					"view_class == side（NPC 才允许 front），实为 %s" % spec.get("view_class", "<缺失>"))
			_check(bool(spec.get("flippable", false)), "flippable == true（NPC 必须为 false）")
		else:
			_check(false, "parts.json 可解析")

	print("FAILURES=%d" % failures)
	rig.queue_free()
	quit(0 if failures == 0 else 1)


func _find_sprite(root: Node, part_name: String) -> Sprite2D:
	var target := "spr_" + part_name
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n.name == target and n is Sprite2D:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
