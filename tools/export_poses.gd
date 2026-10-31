extends SceneTree

## 把 rig 的骨骼动画采样导出为 JSON，供离线渲染姿态评审图使用。
##
## 运行：Godot --headless --path <项目根> --script res://tools/export_poses.gd
## 产物：user://poses.json（路径会打印在 stdout）
##
## 每个采样帧给出每个部件的"枢轴画布坐标 + 全局旋转 + z 序"，
## 外部工具据此把 128x128 部件贴图绕枢轴旋转后合成，即可在没有窗口的
## 情况下检查动画是否穿模、部件是否飞散。

const RIG_PATH := "res://assets/characters/shihung/rig/shihung_rig.tscn"
const CANVAS_CENTER := Vector2(64, 88)
const SAMPLES := 4

const CLIPS := ["idle", "run", "jump", "fall", "dash", "attack", "hurt", "land",
		"era_switch", "respawn", "turn"]

const PART_ORDER := [
	"leg_far_shin", "leg_far_thigh", "arm_far_lower", "arm_far_upper",
	"leg_near_thigh", "leg_near_shin", "hem_back", "torso", "hem_front",
	"sash_2", "sash_1", "gold_line", "arm_near_lower", "arm_near_upper",
	"head", "crown",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(RIG_PATH)
	var rig: Node2D = packed.instantiate()
	get_root().add_child(rig)
	await process_frame

	var player: AnimationPlayer = rig.get_node("AnimationPlayer")
	var out := {"canvas": 128, "feet_y": 120, "clips": {}}

	for clip in CLIPS:
		var anim := player.get_animation(clip)
		player.play(clip)
		var frames := []
		for i in range(SAMPLES):
			var t: float = anim.length * float(i) / float(SAMPLES)
			player.seek(t, true)
			var parts := []
			for pname in PART_ORDER:
				var spr := _find_sprite(rig, "spr_" + pname)
				if spr == null:
					continue
				var pivot: Vector2 = (spr.global_position - rig.global_position) + CANVAS_CENTER
				parts.append({
					"n": pname,
					"p": [pivot.x, pivot.y],
					"r": spr.global_rotation,
					"z": spr.z_index,
				})
			frames.append({"t": t, "parts": parts})
		out["clips"][clip] = {"length": anim.length, "frames": frames}
		print("%s: %d frames over %.2fs" % [clip, frames.size(), anim.length])

	var path := "user://poses.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("wrote ", ProjectSettings.globalize_path(path))
	rig.queue_free()
	quit(0)


func _find_sprite(root: Node, target: String) -> Sprite2D:
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n.name == target and n is Sprite2D:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
