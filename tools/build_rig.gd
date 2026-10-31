extends SceneTree

## 主角骨骼 rig 构建工具（一次性生成器，不参与运行时）。
##
## 运行：
##   Godot --headless --path <项目根> --script res://tools/build_rig.gd
##
## 产物：
##   res://assets/characters/shihung/rig/shihung_rig.tscn
##   —— 含 Skeleton2D + 15 根 Bone2D + 16 个部件 Sprite2D + AnimationPlayer（11 个动画）
##
## 为什么用脚本而不是手写 .tscn：Bone2D 的 rest、AnimationLibrary 的序列化格式都由引擎
## 自己写入最可靠，手写极易产出"能加载但骨骼错位"的坏场景。
##
## ---------------------------------------------------------------- 视角与符号约定
## 横版侧视，角色**面朝 +x**（画布右方），镜头在角色正侧方。
## Godot 2D 的 rotation 正值在屏幕上表现为**顺时针**，代入 y 轴向下可得：
##   * 朝**下**的骨骼（四肢、腰饰、裙摆）：正角度 → 末端摆向 -x（即**向后**）
##   * 朝**上**的骨骼（躯干、头、冠）：正角度 → 顶端摆向 +x（即**前倾**）
## 所以：跑动时"布料向后拖"用**正**角度，前倾用**正**角度，后仰用**负**角度。
## 游戏里 rig.scale.x = -1 即朝左，骨骼角度无需镜像。

const PARTS_DIR := "res://assets/characters/shihung/parts/"
const OUT_PATH := "res://assets/characters/shihung/rig/shihung_rig.tscn"

const CANVAS := 128
const CENTER := 64
const HIP_Y := 88
const HEAD_BOT := 45
const HEAD_TOP := 8
const SHOULDER_Y := 50
const ELBOW_Y := 67
const KNEE_Y := 103
const ARM_NEAR_X := 73
const ARM_FAR_X := 54
const LEG_FAR_X := 60
const SASH1 := Vector2(58, 80)
const SASH2 := Vector2(54, 85)
const HEM_PIVOT := Vector2(64, 84)

## 骨骼定义：name -> [parent, 相对父骨骼的位置, 长度]
const BONES := [
	["root", "Skeleton2D", Vector2(CENTER, HIP_Y), 44.0],
	["torso", "root", Vector2(0, 0), 40.0],
	["head", "torso", Vector2(0, -(HIP_Y - HEAD_BOT)), 37.0],
	["crown", "head", Vector2(0, -(HEAD_BOT - HEAD_TOP)), 12.0],
	["arm_near_upper", "torso", Vector2(ARM_NEAR_X - CENTER, -(HIP_Y - SHOULDER_Y)), 16.0],
	["arm_near_lower", "arm_near_upper", Vector2(0, ELBOW_Y - SHOULDER_Y), 15.0],
	["arm_far_upper", "torso", Vector2(ARM_FAR_X - CENTER, -(HIP_Y - SHOULDER_Y)), 16.0],
	["arm_far_lower", "arm_far_upper", Vector2(0, ELBOW_Y - SHOULDER_Y), 15.0],
	["hem_back", "root", Vector2(0, HEM_PIVOT.y - HIP_Y), 14.0],
	["leg_near_thigh", "root", Vector2(0, 0), 15.0],
	["leg_near_shin", "leg_near_thigh", Vector2(0, KNEE_Y - HIP_Y), 13.0],
	["leg_far_thigh", "root", Vector2(LEG_FAR_X - CENTER, 0), 15.0],
	["leg_far_shin", "leg_far_thigh", Vector2(0, KNEE_Y - HIP_Y), 13.0],
	["sash_1", "root", Vector2(SASH1.x - CENTER, SASH1.y - HIP_Y), 12.0],
	["sash_2", "sash_1", Vector2(SASH2.x - SASH1.x, SASH2.y - SASH1.y), 11.0],
]

## 部件 -> [骨骼, 该部件的枢轴画布坐标, z_index]
## 枢轴必须与该骨骼在画布中的绝对位置一致，否则静止姿就会错位。
## 侧视 z 序（后 → 前）：远侧腿 → 远侧臂 → 近侧腿（藏在裙下）→ 后摆 → 袍身
##   → 前摆 → 腰饰 → 金线 → 近侧臂 → 头 → 冠。
## 近侧腿必须在裙摆**之后**，否则大腿会穿出裙子。
const PART_MAP := {
	"leg_far_shin": ["leg_far_shin", Vector2(LEG_FAR_X, KNEE_Y), 0],
	"leg_far_thigh": ["leg_far_thigh", Vector2(LEG_FAR_X, HIP_Y), 1],
	"arm_far_lower": ["arm_far_lower", Vector2(ARM_FAR_X, ELBOW_Y), 2],
	"arm_far_upper": ["arm_far_upper", Vector2(ARM_FAR_X, SHOULDER_Y), 3],
	"leg_near_thigh": ["leg_near_thigh", Vector2(CENTER, HIP_Y), 4],
	"leg_near_shin": ["leg_near_shin", Vector2(CENTER, KNEE_Y), 5],
	"hem_back": ["hem_back", HEM_PIVOT, 6],
	"torso": ["torso", Vector2(CENTER, HIP_Y), 8],
	"hem_front": ["hem_back", HEM_PIVOT, 9],
	"sash_2": ["sash_2", SASH2, 10],
	"sash_1": ["sash_1", SASH1, 11],
	"gold_line": ["torso", Vector2(CENTER, HIP_Y), 12],
	"arm_near_lower": ["arm_near_lower", Vector2(ARM_NEAR_X, ELBOW_Y), 13],
	"arm_near_upper": ["arm_near_upper", Vector2(ARM_NEAR_X, SHOULDER_Y), 14],
	"head": ["head", Vector2(CENTER, HEAD_BOT), 16],
	"crown": ["crown", Vector2(CENTER, HEAD_TOP), 17],
}


func _initialize() -> void:
	var rig := _build()
	if rig == null:
		quit(1)
		return
	var packed := PackedScene.new()
	var err := packed.pack(rig)
	if err != OK:
		push_error("pack failed: %s" % err)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/characters/shihung/rig"))
	err = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		push_error("save failed: %s" % err)
		quit(1)
		return
	print("saved ", OUT_PATH)
	_report(rig)
	quit(0)


func _build() -> Node2D:
	var rig := Node2D.new()
	rig.name = "ShihungRig"

	var skeleton := Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	# 让骨骼画布中心对齐 rig 原点，这样 scale.x 取负时是"原地翻转"而不是整体位移
	skeleton.position = Vector2(-CENTER, -HIP_Y)
	rig.add_child(skeleton)

	var made := {}
	for spec in BONES:
		var bname: String = spec[0]
		var parent_path: String = spec[1]
		var local_pos: Vector2 = spec[2]
		var length: float = spec[3]

		var bone := Bone2D.new()
		bone.name = bname
		bone.position = local_pos
		bone.rotation = 0.0
		bone.scale = Vector2.ONE
		bone.length = length
		bone.auto_calculate_length_and_angle = false
		bone.rest = Transform2D(0.0, local_pos)

		var parent: Node = skeleton if parent_path == "Skeleton2D" else made[parent_path]
		parent.add_child(bone)
		made[bname] = bone

	# 部件
	for part_name in PART_MAP.keys():
		var info: Array = PART_MAP[part_name]
		var bone_name: String = info[0]
		var pivot: Vector2 = info[1]
		var z: int = info[2]

		var tex_path := PARTS_DIR + "char_shihung_part_%s.png" % part_name
		var tex := load(tex_path)
		if tex == null:
			push_error("missing texture: " + tex_path)
			return null

		var sprite := Sprite2D.new()
		sprite.name = "spr_" + part_name
		sprite.texture = tex
		sprite.centered = false
		sprite.offset = -pivot
		sprite.z_index = z
		made[bone_name].add_child(sprite)

	# 动画
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	rig.add_child(player)
	var lib := AnimationLibrary.new()
	for entry in _animations():
		lib.add_animation(entry[0], entry[1])
	player.add_animation_library("", lib)
	player.play("idle")

	_set_owner(rig, rig)
	return rig


func _set_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owner(child, owner_node)


func _report(rig: Node2D) -> void:
	# 注意：本脚本是 SceneTree 而非 @tool，rig 尚未入树，skeleton.get_bone_count()
	# 会返回 0。骨骼数量以 BONES 定义为准，真实的入树校验见 tools/verify_rig.gd。
	print("bones defined=", BONES.size())
	var player: AnimationPlayer = rig.get_node("AnimationPlayer")
	print("animations=", player.get_animation_list())
	var bad := 0
	for part_name in PART_MAP.keys():
		var info: Array = PART_MAP[part_name]
		var bone_name: String = info[0]
		var pivot: Vector2 = info[1]
		var bone: Bone2D = rig.get_node("Skeleton2D/" + _rel_path(bone_name))
		var spr: Sprite2D = bone.get_node("spr_" + part_name)
		if spr.offset != -pivot:
			print("  WARN offset mismatch: ", part_name)
			bad += 1
	print("part offset check: ", "OK" if bad == 0 else "FAILED %d" % bad)


func _rel_path(bone_name: String) -> String:
	for spec in BONES:
		if spec[0] == bone_name:
			if spec[1] == "Skeleton2D":
				return bone_name
			return _rel_path(spec[1]).path_join(bone_name)
	return bone_name


# ---------------------------------------------------------------- animations

func _deg(d: float) -> float:
	return deg_to_rad(d)


## 返回 [[名称, Animation], ...]
func _animations() -> Array:
	var out := []
	out.append(_anim_idle())
	out.append(_anim_run())
	out.append(_anim_jump())
	out.append(_anim_fall())
	out.append(_anim_dash())
	out.append(_anim_attack())
	out.append(_anim_hurt())
	out.append(_anim_respawn())
	out.append(_anim_turn())
	out.append(_anim_land())
	out.append(_anim_era_switch())
	return out


const P_TORSO := "Skeleton2D/root/torso"
const P_HEAD := "Skeleton2D/root/torso/head"
const P_CROWN := "Skeleton2D/root/torso/head/crown"
const P_ARM_NU := "Skeleton2D/root/torso/arm_near_upper"
const P_ARM_NL := "Skeleton2D/root/torso/arm_near_upper/arm_near_lower"
const P_ARM_FU := "Skeleton2D/root/torso/arm_far_upper"
const P_ARM_FL := "Skeleton2D/root/torso/arm_far_upper/arm_far_lower"
const P_LEG_NT := "Skeleton2D/root/leg_near_thigh"
const P_LEG_NS := "Skeleton2D/root/leg_near_thigh/leg_near_shin"
const P_LEG_FT := "Skeleton2D/root/leg_far_thigh"
const P_LEG_FS := "Skeleton2D/root/leg_far_thigh/leg_far_shin"
const P_SASH1 := "Skeleton2D/root/sash_1"
const P_SASH2 := "Skeleton2D/root/sash_1/sash_2"
const P_HEM := "Skeleton2D/root/hem_back"
const P_ROOT := "Skeleton2D/root"


func _new_anim(length: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return a


## 给某根骨骼加旋转轨道。keys: [[时间, 角度(度)], ...]
func _rot(anim: Animation, path: String, keys: Array) -> void:
	var t := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t, NodePath(path + ":rotation"))
	anim.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
	for k in keys:
		anim.track_insert_key(t, float(k[0]), _deg(float(k[1])))


func _pos(anim: Animation, path: String, keys: Array) -> void:
	var t := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t, NodePath(path + ":position"))
	anim.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
	for k in keys:
		anim.track_insert_key(t, float(k[0]), k[1])


func _scale(anim: Animation, path: String, keys: Array) -> void:
	var t := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t, NodePath(path + ":scale"))
	anim.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS)
	for k in keys:
		anim.track_insert_key(t, float(k[0]), k[1])


func _anim_idle() -> Array:
	var a := _new_anim(2.4, true)
	_rot(a, P_TORSO, [[0.0, 0.0], [1.2, 1.8], [2.4, 0.0]])
	_pos(a, P_TORSO, [[0.0, Vector2.ZERO], [1.2, Vector2(0, 0.9)], [2.4, Vector2.ZERO]])
	_rot(a, P_HEAD, [[0.0, 0.0], [1.2, -1.6], [2.4, 0.0]])
	_rot(a, P_CROWN, [[0.0, 0.0], [1.2, 1.0], [2.4, 0.0]])
	_rot(a, P_ARM_NU, [[0.0, 3.0], [1.2, 6.0], [2.4, 3.0]])
	_rot(a, P_ARM_NL, [[0.0, -7.0], [1.2, -5.0], [2.4, -7.0]])
	_rot(a, P_ARM_FU, [[0.0, 1.0], [1.2, 4.0], [2.4, 1.0]])
	_rot(a, P_ARM_FL, [[0.0, -6.0], [1.2, -4.0], [2.4, -6.0]])
	_rot(a, P_LEG_NT, [[0.0, 0.0], [1.2, 0.6], [2.4, 0.0]])
	_rot(a, P_LEG_NS, [[0.0, 2.0], [1.2, 3.2], [2.4, 2.0]])
	_rot(a, P_LEG_FT, [[0.0, -2.0], [1.2, -1.4], [2.4, -2.0]])
	_rot(a, P_LEG_FS, [[0.0, 3.0], [1.2, 4.0], [2.4, 3.0]])
	_rot(a, P_HEM, [[0.0, 1.0], [1.2, 3.2], [2.4, 1.0]])
	_rot(a, P_SASH1, [[0.0, 5.0], [1.2, 9.0], [2.4, 5.0]])
	_rot(a, P_SASH2, [[0.0, 3.0], [1.2, 6.0], [2.4, 3.0]])
	return ["idle", a]


func _anim_run() -> Array:
	# 0.5s / 循环。侧视跑的核心是**前后跨步**，因此大腿振幅必须够大（±26°），
	# 小腿只负责折叠（始终为正 = 向后收）。
	var a := _new_anim(0.5, true)
	_rot(a, P_LEG_NT, [[0.0, -26.0], [0.125, -6.0], [0.25, 16.0], [0.375, 2.0], [0.5, -26.0]])
	_rot(a, P_LEG_NS, [[0.0, 10.0], [0.125, 16.0], [0.25, 8.0], [0.375, 52.0], [0.5, 10.0]])
	_rot(a, P_LEG_FT, [[0.0, 16.0], [0.125, 2.0], [0.25, -26.0], [0.375, -6.0], [0.5, 16.0]])
	_rot(a, P_LEG_FS, [[0.0, 8.0], [0.125, 52.0], [0.25, 10.0], [0.375, 16.0], [0.5, 8.0]])
	# 手臂与同侧腿反相
	_rot(a, P_ARM_NU, [[0.0, 28.0], [0.125, 0.0], [0.25, -28.0], [0.375, 0.0], [0.5, 28.0]])
	_rot(a, P_ARM_NL, [[0.0, -48.0], [0.125, -36.0], [0.25, -46.0], [0.375, -58.0],
			[0.5, -48.0]])
	_rot(a, P_ARM_FU, [[0.0, -26.0], [0.125, 0.0], [0.25, 26.0], [0.375, 0.0], [0.5, -26.0]])
	_rot(a, P_ARM_FL, [[0.0, -46.0], [0.125, -58.0], [0.25, -48.0], [0.375, -36.0],
			[0.5, -46.0]])
	# 躯干前倾 + 每步一次上下起伏
	_rot(a, P_TORSO, [[0.0, 9.0], [0.25, 10.0], [0.5, 9.0]])
	_pos(a, P_TORSO, [[0.0, Vector2.ZERO], [0.125, Vector2(0, -1.8)], [0.25, Vector2.ZERO],
			[0.375, Vector2(0, -1.8)], [0.5, Vector2.ZERO]])
	_rot(a, P_HEAD, [[0.0, -5.0], [0.25, -6.0], [0.5, -5.0]])
	_rot(a, P_CROWN, [[0.0, -2.0], [0.25, -3.0], [0.5, -2.0]])
	_rot(a, P_HEM, [[0.0, 15.0], [0.125, 25.0], [0.25, 15.0], [0.375, 25.0], [0.5, 15.0]])
	_rot(a, P_SASH1, [[0.0, 32.0], [0.125, 43.0], [0.25, 32.0], [0.375, 43.0], [0.5, 32.0]])
	_rot(a, P_SASH2, [[0.0, 23.0], [0.25, 32.0], [0.5, 23.0]])
	return ["run", a]


func _anim_jump() -> Array:
	var a := _new_anim(0.26, false)
	_rot(a, P_LEG_NT, [[0.0, 0.0], [0.08, -22.0], [0.26, -16.0]])
	_rot(a, P_LEG_NS, [[0.0, 0.0], [0.08, 58.0], [0.26, 42.0]])
	_rot(a, P_LEG_FT, [[0.0, 0.0], [0.08, 12.0], [0.26, 8.0]])
	_rot(a, P_LEG_FS, [[0.0, 0.0], [0.08, 26.0], [0.26, 18.0]])
	_rot(a, P_ARM_NU, [[0.0, 0.0], [0.08, -42.0], [0.26, -30.0]])
	_rot(a, P_ARM_NL, [[0.0, 0.0], [0.08, -26.0], [0.26, -18.0]])
	_rot(a, P_ARM_FU, [[0.0, 0.0], [0.08, 26.0], [0.26, 18.0]])
	_rot(a, P_ARM_FL, [[0.0, 0.0], [0.08, -18.0], [0.26, -12.0]])
	_rot(a, P_TORSO, [[0.0, 0.0], [0.08, 7.0], [0.26, 5.0]])
	_rot(a, P_HEAD, [[0.0, 0.0], [0.08, -4.0], [0.26, -3.0]])
	_rot(a, P_HEM, [[0.0, 0.0], [0.26, 16.0]])
	_rot(a, P_SASH1, [[0.0, 0.0], [0.26, 28.0]])
	_rot(a, P_SASH2, [[0.0, 0.0], [0.26, 20.0]])
	return ["jump", a]


func _anim_fall() -> Array:
	var a := _new_anim(0.4, true)
	_rot(a, P_LEG_NT, [[0.0, 8.0], [0.2, 12.0], [0.4, 8.0]])
	_rot(a, P_LEG_NS, [[0.0, 14.0], [0.2, 20.0], [0.4, 14.0]])
	_rot(a, P_LEG_FT, [[0.0, -10.0], [0.2, -6.0], [0.4, -10.0]])
	_rot(a, P_LEG_FS, [[0.0, 20.0], [0.2, 14.0], [0.4, 20.0]])
	_rot(a, P_ARM_NU, [[0.0, -20.0], [0.2, -26.0], [0.4, -20.0]])
	_rot(a, P_ARM_NL, [[0.0, -34.0], [0.2, -30.0], [0.4, -34.0]])
	_rot(a, P_ARM_FU, [[0.0, 16.0], [0.2, 22.0], [0.4, 16.0]])
	_rot(a, P_ARM_FL, [[0.0, -30.0], [0.2, -26.0], [0.4, -30.0]])
	_rot(a, P_TORSO, [[0.0, 4.0], [0.2, 6.0], [0.4, 4.0]])
	_rot(a, P_HEAD, [[0.0, -6.0], [0.2, -8.0], [0.4, -6.0]])
	_rot(a, P_HEM, [[0.0, 22.0], [0.2, 28.0], [0.4, 22.0]])
	_rot(a, P_SASH1, [[0.0, 34.0], [0.2, 42.0], [0.4, 34.0]])
	_rot(a, P_SASH2, [[0.0, 24.0], [0.2, 32.0], [0.4, 24.0]])
	return ["fall", a]


func _anim_dash() -> Array:
	var a := _new_anim(0.18, false)
	_rot(a, P_TORSO, [[0.0, 0.0], [0.05, 24.0], [0.18, 17.0]])
	_rot(a, P_HEAD, [[0.0, 0.0], [0.05, -15.0], [0.18, -11.0]])
	_rot(a, P_LEG_NT, [[0.0, 0.0], [0.05, -34.0], [0.18, -22.0]])
	_rot(a, P_LEG_NS, [[0.0, 0.0], [0.05, 18.0], [0.18, 12.0]])
	_rot(a, P_LEG_FT, [[0.0, 0.0], [0.05, 32.0], [0.18, 24.0]])
	_rot(a, P_LEG_FS, [[0.0, 0.0], [0.05, 24.0], [0.18, 18.0]])
	_rot(a, P_ARM_NU, [[0.0, 0.0], [0.05, 40.0], [0.18, 32.0]])
	_rot(a, P_ARM_NL, [[0.0, 0.0], [0.05, -22.0], [0.18, -16.0]])
	_rot(a, P_ARM_FU, [[0.0, 0.0], [0.05, 34.0], [0.18, 28.0]])
	_rot(a, P_HEM, [[0.0, 0.0], [0.05, 30.0], [0.18, 26.0]])
	_rot(a, P_SASH1, [[0.0, 0.0], [0.05, 48.0], [0.18, 42.0]])
	_rot(a, P_SASH2, [[0.0, 0.0], [0.05, 36.0], [0.18, 32.0]])
	return ["dash", a]


func _anim_attack() -> Array:
	# 近侧手向前直击：负角度 = 向 +x（前）。蓄力时先向后（正）再前挥（负）。
	var a := _new_anim(0.26, false)
	_rot(a, P_ARM_NU, [[0.0, 0.0], [0.06, 42.0], [0.13, -78.0], [0.26, -36.0]])
	_rot(a, P_ARM_NL, [[0.0, 0.0], [0.06, -24.0], [0.13, -12.0], [0.26, -8.0]])
	_rot(a, P_ARM_FU, [[0.0, 0.0], [0.06, -18.0], [0.13, 26.0], [0.26, 14.0]])
	_rot(a, P_ARM_FL, [[0.0, 0.0], [0.06, -10.0], [0.13, -28.0], [0.26, -18.0]])
	_rot(a, P_TORSO, [[0.0, 0.0], [0.06, 9.0], [0.13, -11.0], [0.26, -5.0]])
	_rot(a, P_HEAD, [[0.0, 0.0], [0.06, -5.0], [0.13, 6.0], [0.26, 3.0]])
	_rot(a, P_LEG_NT, [[0.0, 0.0], [0.13, -8.0], [0.26, -4.0]])
	_rot(a, P_LEG_NS, [[0.0, 0.0], [0.13, 10.0], [0.26, 6.0]])
	_rot(a, P_LEG_FT, [[0.0, 0.0], [0.13, 8.0], [0.26, 4.0]])
	_rot(a, P_HEM, [[0.0, 0.0], [0.06, -6.0], [0.13, 12.0], [0.26, 8.0]])
	_rot(a, P_SASH1, [[0.0, 0.0], [0.06, -8.0], [0.13, 24.0], [0.26, 12.0]])
	_rot(a, P_SASH2, [[0.0, 0.0], [0.06, -6.0], [0.13, 18.0], [0.26, 8.0]])
	return ["attack", a]


func _anim_hurt() -> Array:
	var a := _new_anim(0.32, false)
	_rot(a, P_TORSO, [[0.0, 0.0], [0.06, -15.0], [0.32, 0.0]])
	_rot(a, P_HEAD, [[0.0, 0.0], [0.06, -17.0], [0.18, -9.0], [0.32, 0.0]])
	_rot(a, P_ARM_NU, [[0.0, 0.0], [0.06, -30.0], [0.32, 0.0]])
	_rot(a, P_ARM_NL, [[0.0, 0.0], [0.06, -18.0], [0.32, 0.0]])
	_rot(a, P_ARM_FU, [[0.0, 0.0], [0.06, 26.0], [0.32, 0.0]])
	_rot(a, P_LEG_NT, [[0.0, 0.0], [0.06, 12.0], [0.32, 0.0]])
	_rot(a, P_LEG_FT, [[0.0, 0.0], [0.06, -10.0], [0.32, 0.0]])
	_rot(a, P_HEM, [[0.0, 0.0], [0.06, -12.0], [0.32, 0.0]])
	_rot(a, P_SASH1, [[0.0, 0.0], [0.06, -16.0], [0.32, 0.0]])
	return ["hurt", a]


func _anim_respawn() -> Array:
	var a := _new_anim(0.6, false)
	_scale(a, P_ROOT, [[0.0, Vector2(1.0, 0.82)], [0.2, Vector2(1.0, 0.95)],
			[0.38, Vector2(1.0, 1.04)], [0.6, Vector2.ONE]])
	_rot(a, P_TORSO, [[0.0, 10.0], [0.3, -3.0], [0.6, 0.0]])
	_rot(a, P_HEAD, [[0.0, 16.0], [0.3, -4.0], [0.6, 0.0]])
	_rot(a, P_CROWN, [[0.0, 6.0], [0.4, -3.0], [0.6, 0.0]])
	return ["respawn", a]


func _anim_turn() -> Array:
	var a := _new_anim(0.16, false)
	_scale(a, P_ROOT, [[0.0, Vector2.ONE], [0.06, Vector2(0.86, 0.94)], [0.16, Vector2.ONE]])
	_rot(a, P_TORSO, [[0.0, 0.0], [0.06, 5.0], [0.16, 0.0]])
	_rot(a, P_HEAD, [[0.0, 0.0], [0.06, -6.0], [0.16, 0.0]])
	return ["turn", a]


func _anim_land() -> Array:
	var a := _new_anim(0.22, false)
	_scale(a, P_ROOT, [[0.0, Vector2(1.0, 0.88)], [0.08, Vector2(1.06, 0.88)],
			[0.22, Vector2.ONE]])
	_rot(a, P_LEG_NT, [[0.0, -14.0], [0.08, -20.0], [0.22, 0.0]])
	_rot(a, P_LEG_NS, [[0.0, 30.0], [0.08, 38.0], [0.22, 0.0]])
	_rot(a, P_LEG_FT, [[0.0, 10.0], [0.08, 16.0], [0.22, 0.0]])
	_rot(a, P_LEG_FS, [[0.0, 22.0], [0.08, 30.0], [0.22, 0.0]])
	_rot(a, P_TORSO, [[0.0, 6.0], [0.08, 9.0], [0.22, 0.0]])
	_rot(a, P_ARM_NU, [[0.0, 18.0], [0.08, 24.0], [0.22, 0.0]])
	_rot(a, P_ARM_FU, [[0.0, -16.0], [0.08, -20.0], [0.22, 0.0]])
	_rot(a, P_HEM, [[0.0, 0.0], [0.08, 15.0], [0.22, 0.0]])
	_rot(a, P_SASH1, [[0.0, 0.0], [0.08, 18.0], [0.22, 0.0]])
	return ["land", a]


func _anim_era_switch() -> Array:
	var a := _new_anim(0.5, false)
	_rot(a, P_HEAD, [[0.0, 0.0], [0.15, -9.0], [0.35, 4.0], [0.5, 0.0]])
	_rot(a, P_CROWN, [[0.0, 0.0], [0.15, -7.0], [0.35, 3.0], [0.5, 0.0]])
	_rot(a, P_ARM_NU, [[0.0, 0.0], [0.15, -20.0], [0.5, 0.0]])
	_rot(a, P_ARM_FU, [[0.0, 0.0], [0.15, 18.0], [0.5, 0.0]])
	_rot(a, P_HEM, [[0.0, 0.0], [0.15, 15.0], [0.35, 5.0], [0.5, 0.0]])
	_rot(a, P_SASH1, [[0.0, 0.0], [0.15, 26.0], [0.35, 9.0], [0.5, 0.0]])
	_rot(a, P_SASH2, [[0.0, 0.0], [0.18, 18.0], [0.5, 0.0]])
	_rot(a, P_TORSO, [[0.0, 0.0], [0.15, -4.0], [0.5, 0.0]])
	return ["era_switch", a]
