extends SceneTree
## 主角视觉 v1 截图采集（真实渲染，非示意图）：
## A. rig 单独贴 #142032 深蓝底，按 RIG_SCALE 0.5（约 58px）截 run 四帧与 idle；
## B. 游戏内 M01 实机画面，确认整合与真实底色。
## 不写存档：persist_progress = false。

const SKY := Color("142032")
const RIG := preload("res://assets/characters/shihung/rig/shihung_rig.tscn")
const RIG_SCALE := 0.5
const OUT := "res://docs/qa/runs/"

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT + name
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " error=", err)

func run() -> void:
	var view := Vector2(root.size)
	var bg := ColorRect.new()
	bg.color = SKY
	bg.size = view
	bg.position = Vector2.ZERO
	root.add_child(bg)
	var rig: Node2D = RIG.instantiate()
	rig.scale = Vector2(RIG_SCALE, RIG_SCALE)
	rig.position = Vector2(view.x * 0.5, view.y * 0.5)
	root.add_child(rig)
	var player: AnimationPlayer = rig.get_node("AnimationPlayer")
	player.play("run")
	player.pause()
	for i in range(4):
		var t: float = 0.125 * float(i)
		player.seek(t, true)
		for frame in range(3):
			await process_frame
		await shot("char-visual-run-t%d.png" % i)
	player.play("idle")
	player.pause()
	player.seek(0.0, true)
	for frame in range(3):
		await process_frame
	await shot("char-visual-idle.png")
	rig.queue_free()
	bg.queue_free()
	for frame in range(16):
		await process_frame

	# --- B. 游戏内实机画面（M01 标准房，角色居中） ---
	var world = load("res://game/main.tscn").instantiate()
	world.persist_progress = false
	root.add_child(world)
	await process_frame
	world.player.set_physics_process(false)
	world.set_physics_process(false)
	world.hazards.set_physics_process(false)
	for actor in world.actors.get_children():
		actor.set_physics_process(false)
	world.player.position = Vector2(1328, 492)
	world.player.velocity = Vector2.ZERO
	world.reset_view()
	for frame in range(30):
		await process_frame
	await shot("char-visual-ingame-m01.png")
	print("INGAME zoom=", world.camera.zoom, " rig_scale=", world.player.rig.scale)
	for node in world.find_children("*", "AudioStreamPlayer", true, false):
		node.stop()
		node.stream = null
	world.queue_free()
	for frame in range(8):
		await process_frame
	quit()
