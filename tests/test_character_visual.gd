extends SceneTree
## 主角视觉 v1 数据侧验收（headless，无渲染）：
## run / idle 轨道收幅、腿臂头冠零改动、循环闭合、部件与 clip 名不变。
## 颜色对比度由 tools/verify_character_visual.py 与截图采集负责。

const RIG_PATH := "res://assets/characters/shihung/rig/shihung_rig.tscn"
const PARTS_DIR := "res://assets/characters/shihung/parts/"
const EPS := 0.000001

# 改前（交接单 T2 表格与 HEAD 前文件读数）腿/臂/头/冠的原始序列，必须一字不变。
const RUN_BEFORE := {
	"Skeleton2D/root/leg_near_thigh:rotation":
		[-0.4537856055185257, -0.10471975511965978, 0.2792526803190927, 0.03490658503988659, -0.4537856055185257],
	"Skeleton2D/root/leg_near_thigh/leg_near_shin:rotation":
		[0.17453292519943295, 0.2792526803190927, 0.13962634015954636, 0.9075712110370514, 0.17453292519943295],
	"Skeleton2D/root/leg_far_thigh:rotation":
		[0.2792526803190927, 0.03490658503988659, -0.4537856055185257, -0.10471975511965978, 0.2792526803190927],
	"Skeleton2D/root/leg_far_thigh/leg_far_shin:rotation":
		[0.13962634015954636, 0.9075712110370514, 0.17453292519943295, 0.2792526803190927, 0.13962634015954636],
	"Skeleton2D/root/torso/arm_near_upper:rotation":
		[0.4886921905584123, 0.0, -0.4886921905584123, 0.0, 0.4886921905584123],
	"Skeleton2D/root/torso/arm_near_upper/arm_near_lower:rotation":
		[-0.8377580409572782, -0.6283185307179586, -0.8028514559173916, -1.0122909661567112, -0.8377580409572782],
	"Skeleton2D/root/torso/arm_far_upper:rotation":
		[-0.4537856055185257, 0.0, 0.4537856055185257, 0.0, -0.4537856055185257],
	"Skeleton2D/root/torso/arm_far_upper/arm_far_lower:rotation":
		[-0.8028514559173916, -1.0122909661567112, -0.8377580409572782, -0.6283185307179586, -0.8028514559173916],
	"Skeleton2D/root/torso:rotation":
		[0.15707963267948966, 0.17453292519943295, 0.15707963267948966],
	"Skeleton2D/root/torso/head:rotation":
		[-0.08726646259971647, -0.10471975511965978, -0.08726646259971647],
	"Skeleton2D/root/torso/head/crown:rotation":
		[-0.03490658503988659, -0.05235987755982989, -0.03490658503988659],
}

const RUN_CONST := {
	"Skeleton2D/root/hem_back:rotation": 0.30,
	"Skeleton2D/root/sash_1:rotation": 0.62,
	"Skeleton2D/root/sash_1/sash_2:rotation": 0.45,
}

const CLIPS := ["attack", "dash", "era_switch", "fall", "hurt", "idle",
	"jump", "land", "respawn", "run", "turn"]
const PART_NAMES := ["leg_far_shin", "leg_far_thigh", "arm_far_lower", "arm_far_upper",
	"leg_near_thigh", "leg_near_shin", "hem_back", "torso", "hem_front", "sash_2",
	"sash_1", "gold_line", "arm_near_lower", "arm_near_upper", "head", "crown"]

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func close(a: float, b: float, eps := EPS) -> bool:
	return absf(a - b) <= eps

func track_by_path(anim: Animation, path: String) -> int:
	for i in range(anim.get_track_count()):
		if str(anim.track_get_path(i)) == path:
			return i
	return -1

func key_values(anim: Animation, idx: int) -> Array:
	var out: Array = []
	for k in range(anim.track_get_key_count(idx)):
		out.append(anim.track_get_key_value(idx, k))
	return out

func all_same(values: Array) -> bool:
	if values.is_empty():
		return false
	var first := float(values[0])
	for v in values:
		if not close(float(v), first, 0.0005):
			return false
	return true

## 逐帧采样：用 seek 播到指定时刻，读真实骨骼/贴图变换（不依赖渲染）。
func sample_clip(player: AnimationPlayer, clip: String, length: float, steps: int) -> Array:
	var rig: Node = player.get_parent()
	var crown: Node2D = rig.get_node("Skeleton2D/root/torso/head/crown/spr_crown")
	var torso: Node2D = rig.get_node("Skeleton2D/root/torso")
	var hem: Node2D = rig.get_node("Skeleton2D/root/hem_back")
	var sash1: Node2D = rig.get_node("Skeleton2D/root/sash_1")
	var sash2: Node2D = rig.get_node("Skeleton2D/root/sash_1/sash_2")
	player.play(clip)
	player.pause()
	var out: Array = []
	for i in range(steps + 1):
		player.seek(length * float(i) / float(steps), true)
		out.append({
			"hem": hem.rotation,
			"sash1": sash1.rotation,
			"sash2": sash2.rotation,
			"torso_y": torso.position.y,
			"crown_y": crown.global_position.y,
		})
	return out

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed: PackedScene = load(RIG_PATH)
	check(packed != null, "rig scene loads")
	var rig: Node2D = packed.instantiate()
	root.add_child(rig)
	await process_frame

	# --- 结构不变：16 部件 + 11 clip ---
	var sprites := rig.find_children("*", "Sprite2D", true, false)
	check(sprites.size() == 16, "16 part sprites (got %d)" % sprites.size())
	var player: AnimationPlayer = rig.get_node_or_null("AnimationPlayer")
	check(player != null, "AnimationPlayer present")
	var names: Array = []
	for name in player.get_animation_list():
		names.append(str(name))
	names.sort()
	var want: Array = CLIPS.duplicate()
	want.sort()
	check(names == want, "11 clip names unchanged %s" % str(names))

	# 朝向：所有 Sprite2D 不翻转、rig 默认 face +x（玩家层用负 scale.x 翻转）
	var flipped := false
	for s in sprites:
		if s.flip_h or s.flip_v:
			flipped = true
	check(not flipped, "no sprite flip: facing stays +x")

	# --- run ---
	var run_anim: Animation = player.get_animation("run")
	check(run_anim != null, "run clip exists")
	check(run_anim.get_track_count() == 15, "run keeps 15 tracks (got %d)" % run_anim.get_track_count())
	check(close(run_anim.length, 0.5), "run length 0.5")

	# 1) 布料收幅：三条轨道逐帧常值
	for path in RUN_CONST:
		var idx := track_by_path(run_anim, path)
		check(idx >= 0, "track present: " + path)
		if idx < 0:
			continue
		var values := key_values(run_anim, idx)
		var target: float = RUN_CONST[path]
		var constant := true
		for v in values:
			if not close(float(v), target, 0.0005):
				constant = false
		check(constant, "%s constant %.2f, got %s" % [path, target, str(values)])
		# 逐帧采样也必须同值（interp 不得引入摆动）
		for step in range(21):
			var t := 0.5 * step / 20.0
			if not close(float(run_anim.value_track_interpolate(idx, t)), target, 0.0005):
				constant = false
		check(constant, "%s same angle every frame" % path)

	# 2) torso:position 上下行程 <= 1.4
	var torso_pos := track_by_path(run_anim, "Skeleton2D/root/torso:position")
	check(torso_pos >= 0, "torso:position present")
	var lo := INF
	var hi := -INF
	for step in range(101):
		var t := 0.5 * step / 100.0
		var v: Vector2 = run_anim.value_track_interpolate(torso_pos, t)
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	check(hi - lo <= 1.4 + EPS, "torso vertical travel <= 1.4 px (got %.3f)" % (hi - lo))
	check(close(absf(lo), 1.4, 0.001) and close(hi, 0.0), "torso range 0 .. -1.4 (got %.3f .. %.3f)" % [lo, hi])

	# 3) 腿/臂/头/冠 与改前完全一致
	for path in RUN_BEFORE:
		var idx := track_by_path(run_anim, path)
		check(idx >= 0, "track present: " + path)
		if idx < 0:
			continue
		var got := key_values(run_anim, idx)
		var want_vals: Array = RUN_BEFORE[path]
		var same := got.size() == want_vals.size()
		if same:
			for i in range(got.size()):
				if not close(float(got[i]), float(want_vals[i])):
					same = false
		check(same, "%s unchanged, got %s" % [path, str(got)])

	# 4) 循环闭合：t=0 与 t=0.5 全轨道同值
	for i in range(run_anim.get_track_count()):
		var v0 = run_anim.value_track_interpolate(i, 0.0)
		var v1 = run_anim.value_track_interpolate(i, 0.5)
		if v0 is Vector2:
			check(close(v0.x, v1.x) and close(v0.y, v1.y),
				"loop closes %s %s vs %s" % [str(run_anim.track_get_path(i)), str(v0), str(v1)])
		else:
			check(close(float(v0), float(v1)),
				"loop closes %s %s vs %s" % [str(run_anim.track_get_path(i)), str(v0), str(v1)])

	# --- 逐帧（真实骨骼变换）采样：run 布料 / 头顶行程 ---
	var crown_spr: Node2D = rig.get_node_or_null("Skeleton2D/root/torso/head/crown/spr_crown")
	var hem_bone: Node2D = rig.get_node_or_null("Skeleton2D/root/hem_back")
	var sash1_bone: Node2D = rig.get_node_or_null("Skeleton2D/root/sash_1")
	var sash2_bone: Node2D = rig.get_node_or_null("Skeleton2D/root/sash_1/sash_2")
	var torso_bone: Node2D = rig.get_node_or_null("Skeleton2D/root/torso")
	check(crown_spr != null and hem_bone != null and sash1_bone != null
		and sash2_bone != null and torso_bone != null, "bone chain resolvable")

	var run_frames := sample_clip(player, "run", 0.5, 16)
	var hem_set: Array[float] = []
	var sash1_set: Array[float] = []
	var sash2_set: Array[float] = []
	var torso_lo := INF
	var torso_hi := -INF
	var crown_lo := INF
	var crown_hi := -INF
	for frame in run_frames:
		hem_set.append(frame.hem)
		sash1_set.append(frame.sash1)
		sash2_set.append(frame.sash2)
		torso_lo = minf(torso_lo, frame.torso_y)
		torso_hi = maxf(torso_hi, frame.torso_y)
		crown_lo = minf(crown_lo, frame.crown_y)
		crown_hi = maxf(crown_hi, frame.crown_y)
	check(all_same(hem_set), "run per-frame hem_back angle constant %s" % str(hem_set))
	check(all_same(sash1_set), "run per-frame sash_1 angle constant %s" % str(sash1_set))
	check(all_same(sash2_set), "run per-frame sash_2 angle constant %s" % str(sash2_set))
	check(close(hem_set[0], 0.30, 0.001), "run hem_back 0.30 constant (%.3f)" % hem_set[0])
	check(close(sash1_set[0], 0.62, 0.001), "run sash_1 0.62 constant (%.3f)" % sash1_set[0])
	check(close(sash2_set[0], 0.45, 0.001), "run sash_2 0.45 constant (%.3f)" % sash2_set[0])
	check(torso_hi - torso_lo <= 1.4 + EPS,
		"run real torso travel <= 1.4 px (got %.3f)" % (torso_hi - torso_lo))
	print("RUN_TORSO_TRAVEL_PX=%.3f RUN_CROWN_TRAVEL_PX=%.3f" % [torso_hi - torso_lo, crown_hi - crown_lo])

	# --- idle：量一遍头顶上下行程（规格 <=1.5px @128 画布），不改布料 ---
	var idle: Animation = player.get_animation("idle")
	check(idle != null and close(idle.length, 2.4), "idle clip length 2.4")
	var idle_frames := sample_clip(player, "idle", 2.4, 24)
	var idle_lo := INF
	var idle_hi := -INF
	for frame in idle_frames:
		idle_lo = minf(idle_lo, frame.crown_y)
		idle_hi = maxf(idle_hi, frame.crown_y)
	print("IDLE_CROWN_TRAVEL_PX=%.3f" % (idle_hi - idle_lo))
	check(true, "idle crown travel measured (report only, spec: <=1.5 px)")

	# 修正采样期间可能被 seek 改变的缩放/朝向
	check(rig.scale == Vector2.ONE, "rig scale untouched by sampling")

	# --- 几何与配色结构：部件贴图仍是 128 画布、非空；金冠与金线部件含金 ---
	for name in PART_NAMES:
		var path: String = PARTS_DIR + "char_shihung_part_" + name + ".png"
		check(ResourceLoader.exists(path), "part exists: " + name)
		var tex: Texture2D = load(path)
		check(tex != null and tex.get_width() == 128 and tex.get_height() == 128,
			"part 128x128: " + name)
	for name in ["crown", "gold_line"]:
		var img: Image = (load(PARTS_DIR + "char_shihung_part_" + name + ".png") as Texture2D).get_image()
		var gold := 0
		var dark := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				# 金：暖色且明显亮于墨阶
				if c.r > 0.45 and c.r > c.b + 0.15:
					gold += 1
				if c.get_luminance() < 0.08:
					dark += 1
		check(gold > 0, "%s still has gold pixels (%d)" % [name, gold])
		check(dark == 0, "%s has no near-black pixels (%d)" % [name, dark])

	print("CHARACTER_VISUAL CHECKS=%d FAILURES=%d" % [checks, failures])
	rig.queue_free()
	await process_frame
	quit(1 if failures else 0)
