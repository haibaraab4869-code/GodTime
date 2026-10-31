extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal respawned
signal swing_started
signal died(at: Vector2)

const InputBuffer := preload("res://game/input_buffer.gd")

@export var move_speed: float = 240.0
@export var jump_speed: float = 420.0
@export var gravity_strength: float = 1100.0
@export var dash_speed: float = 540.0
@export var dash_duration: float = 0.16
@export var maximum_health: int = 4
@export var attack_damage: int = 1
@export var attack_duration: float = 0.16
@export var attack_cooldown: float = 0.32
@export var attack_reach: float = 34.0
@export var attack_height: float = 32.0

## How long a press stays queued before it is discarded.
@export var jump_buffer_window: float = 0.14
@export var attack_buffer_window: float = 0.18
@export var dash_buffer_window: float = 0.12
## Time after leaving the ground during which a jump still counts as grounded.
@export var coyote_time: float = 0.10
## Releasing jump during the rising phase cuts the remaining upward speed.
@export var jump_cut_multiplier: float = 0.45

var health: int = 4
var dash_remaining: float = 0.0
var dash_ready: bool = true
var facing: int = 1
var world: Node2D
var checkpoint: Vector2 = Vector2(80, 397)

# --- 视觉层：骨骼 rig ---
# rig 缺失时（例如只跑逻辑测试）自动回退到 _draw() 的矩形占位，逻辑不受影响。
const RIG_SCALE := 0.5
@onready var rig: Node2D = get_node_or_null("Rig")
@onready var anim: AnimationPlayer = rig.get_node_or_null("AnimationPlayer") if rig != null else null

var _clip := ""
var _override := ""
var _override_left := 0.0
var _last_facing := 1
var _last_era := false
var _era_seen := false
var _rest_transforms: Dictionary = {}

const CLIP_PRIORITY := {
	"turn": 1, "era_switch": 1, "land": 2, "dash": 3,
	"attack": 4, "hurt": 5, "respawn": 6,
}

var attack_remaining: float = 0.0
var attack_cooldown_remaining: float = 0.0
var attack_hit_nodes: Array[Node] = []

var jump_buffer := InputBuffer.new()
var attack_buffer := InputBuffer.new()
var dash_buffer := InputBuffer.new()

var _coyote_remaining := 0.0
var _was_on_floor := false
var _extra_jump_ready := false
var _air_time := 0.0
var _wall_push_left := 0.0
var attack_down := false
var pending_down := false
var pending_direction_locked := false
var control_lock := 0.0
var respawn_view_lock := 0.0
var damage_iframes := 0.0
var last_damage_frame := -1
var pogo_window_used := false
var pogo_first_step := false
var pogo_combo := 0
var pogo_anim_paused := false
var drop_bodies: Array[Node] = []
var drop_left := 0.0
@export var pogo_speed: float = 380.0

func _has_ability(code: String) -> bool:
	return world != null and world.has_method("ability_available") and world.ability_available(code)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and not event.is_echo():
		jump_buffer.press(jump_buffer_window)
	if event.is_action_pressed("attack"):
		pending_down = Input.is_action_pressed("move_down")
		pending_direction_locked = true
		attack_buffer.press(attack_buffer_window)
	if event.is_action_pressed("dash"):
		dash_buffer.press(dash_buffer_window)

func _ready() -> void:
	if rig != null:
		for bone in rig.find_children("*", "Bone2D", true, false):
			_rest_transforms[bone] = bone.transform
		_play_visual("idle")
	health = maximum_health
	health_changed.emit(health, maximum_health)
	_was_on_floor = is_on_floor()

func _physics_process(delta: float) -> void:
	drop_left = maxf(0, drop_left - delta)
	if drop_left <= 0:
		for body in drop_bodies:
			if is_instance_valid(body): remove_collision_exception_with(body)
		drop_bodies.clear()
	if Input.is_action_just_pressed("move_down") and is_on_floor():
		for i in range(get_slide_collision_count()):
			var body = get_slide_collision(i).get_collider()
			if body != null and body.get_meta("drop_through", false):
				add_collision_exception_with(body)
				drop_bodies.append(body)
				drop_left = 0.2
				velocity.y = 80
	damage_iframes = maxf(0, damage_iframes - delta)
	modulate.a = 0.45 if damage_iframes > 0 and int(damage_iframes * 12) % 2 == 0 else 1.0
	respawn_view_lock = maxf(0, respawn_view_lock - delta)
	control_lock = maxf(0, control_lock - delta)
	if world != null and world.get("hitstop_left") != null and world.hitstop_left > 0: return
	if pogo_anim_paused:
		if anim != null: anim.play()
		pogo_anim_paused = false
	if control_lock > 0:
		velocity = Vector2.ZERO
		return
	jump_buffer.tick(delta)
	attack_buffer.tick(delta)
	dash_buffer.tick(delta)

	var direction := Input.get_axis("move_left", "move_right")
	if absf(direction) > 0.01:
		facing = 1 if direction > 0.0 else -1

	var on_floor := is_on_floor()
	_wall_push_left = maxf(0, _wall_push_left - delta)
	if on_floor:
		pogo_combo = 0
		_extra_jump_ready = _has_ability("P2")
		_air_time = 0
		_coyote_remaining = coyote_time
		dash_ready = true
	else:
		_air_time += delta
		_coyote_remaining = maxf(0.0, _coyote_remaining - delta)

	if (on_floor or _has_ability("PA")) and dash_ready and dash_buffer.consume():
		dash_remaining = dash_duration
		dash_ready = false
		_trigger("dash", dash_duration)

	_update_attack(delta)
	if world != null and world.get("hitstop_left") != null and world.hitstop_left > 0: return

	if dash_remaining > 0.0:
		dash_remaining = maxf(0.0, dash_remaining - delta)
		velocity.x = facing * dash_speed
		velocity.y = 0.0
	else:
		if _wall_push_left <= 0: velocity.x = direction * move_speed
		velocity.y += gravity_strength * delta * (0.5 if pogo_first_step else 1.0)
		pogo_first_step = false
		if jump_buffer.is_active() and _coyote_remaining > 0.0:
			jump_buffer.consume()
			_coyote_remaining = 0.0
			velocity.y = -jump_speed
		elif jump_buffer.is_active() and is_on_wall() and _has_ability("PW"):
			jump_buffer.consume()
			velocity = Vector2(get_wall_normal().x * 290, -jump_speed)
			_wall_push_left = 0.16
			_extra_jump_ready = false
		elif jump_buffer.is_active() and _extra_jump_ready and _air_time > 0.08:
			jump_buffer.consume()
			_extra_jump_ready = false
			velocity.y = -jump_speed
		elif velocity.y < 0.0 and Input.is_action_just_released("jump"):
			velocity.y *= jump_cut_multiplier
		if velocity.y > 65 and _has_ability("PG") and Input.is_action_pressed("jump"): velocity.y = 65

	if world != null and world.has_method("apply_map_motion"): world.apply_map_motion(self, delta)
	move_and_slide()

	if _was_on_floor and not is_on_floor() and velocity.y >= 0.0:
		_coyote_remaining = coyote_time
	elif not _was_on_floor and is_on_floor():
		_trigger("land", 0.2)
	_was_on_floor = is_on_floor()

	var bottom: float = world.fall_limit() if world != null else 700.0
	if position.y > bottom:
		if world != null and world.has_method("hazard_fall"): world.hazard_fall()
		else:
			take_damage(1)
			respawn()
	_update_visual(delta)
	queue_redraw()

func _update_attack(delta: float) -> void:
	attack_cooldown_remaining = maxf(0.0, attack_cooldown_remaining - delta)
	var was_active := attack_remaining > 0.0
	if attack_remaining > 0.0:
		attack_remaining = maxf(0.0, attack_remaining - delta)

	if attack_remaining <= 0.0 and attack_cooldown_remaining <= 0.0 \
			and dash_remaining <= 0.0 and attack_buffer.is_active():
		attack_buffer.consume()
		attack_down = (pending_down if pending_direction_locked else Input.is_action_pressed("move_down")) and not is_on_floor()
		pending_direction_locked = false
		attack_remaining = attack_duration
		attack_cooldown_remaining = attack_cooldown
		attack_hit_nodes.clear()
		pogo_window_used = false
		_trigger("attack", attack_duration)
		swing_started.emit()

	# Keep testing for targets for the whole swing so that anything entering
	# the box mid-swing is still hit; the hit list prevents double damage.
	if attack_remaining > 0.0:
		_apply_attack_hits()
	elif was_active:
		attack_hit_nodes.clear()

func attack_box() -> Rect2:
	if attack_down: return attack_down_box()
	var box_width := attack_reach
	var x := 12.0 if facing > 0 else -12.0 - box_width
	return Rect2(x, -attack_height * 0.5 - 2.0, box_width, attack_height)

func attack_down_box() -> Rect2: return Rect2(-22, 6, 44, 34)

func pogo() -> bool:
	if attack_remaining > 0 and pogo_window_used: return false
	if world != null and world.has_method("_is_clear"):
		var future := global_position - Vector2(0, pogo_speed * 0.10)
		if not world._is_clear(future, world._geometry(world.past_era)): return false
	velocity.y = -pogo_speed
	pogo_combo = mini(4, pogo_combo + 1)
	if anim != null:
		anim.pause()
		pogo_anim_paused = true
	dash_remaining = 0
	pogo_first_step = true
	if attack_remaining > 0: pogo_window_used = true
	if _has_ability("PA"): dash_ready = true
	if _has_ability("P2"): _extra_jump_ready = true
	if world != null and world.has_method("on_pogo"): world.on_pogo()
	return true

func _apply_attack_hits() -> void:
	var box := attack_box()
	for target in get_tree().get_nodes_in_group("attackable"):
		if not is_instance_valid(target) or target in attack_hit_nodes:
			continue
		var node := target as Node2D
		if node == null:
			continue
		var target_bounds := Rect2(node.global_position - global_position - Vector2(8, 12), Vector2(16, 24))
		if target.has_method("hit_bounds"):
			target_bounds = target.hit_bounds()
			target_bounds.position -= global_position
		if box.intersects(target_bounds):
			attack_hit_nodes.append(target)
			var top_hit: bool = attack_down and global_position.y + 20 <= target_bounds.position.y + global_position.y + 10
			if target.has_meta("projectile_kind") and target.get_meta("projectile_kind") not in ["stone", "bone"]: top_hit = false
			if top_hit: pogo()
			if attack_down and damage_iframes > 0: continue
			if target.has_method("take_player_hit"):
				target.take_player_hit(self)
			elif target.has_method("take_damage"):
				target.take_damage(attack_damage)
	if attack_down and world != null and world.has_method("test_pogo_surfaces"):
		world.test_pogo_surfaces(Rect2(global_position + box.position, box.size))

func is_attacking() -> bool:
	return attack_remaining > 0.0

func take_damage(amount: int) -> void:
	if damage_iframes > 0: return
	if world != null and world.has_method("cancel_heal"):
		world.cancel_heal()
	health = maxi(0, health - amount)
	health_changed.emit(health, maximum_health)
	_trigger("hurt", 0.32)
	if health == 0:
		died.emit(global_position)
		health = maximum_health
		health_changed.emit(health, maximum_health)
		respawn()

func respawn() -> void:
	respawn_view_lock = 0.6
	pending_direction_locked = false
	attack_down = false
	pogo_first_step = false
	pogo_combo = 0
	pogo_anim_paused = false
	global_position = checkpoint
	velocity = Vector2.ZERO
	dash_remaining = 0.0
	attack_remaining = 0.0
	attack_cooldown_remaining = 0.0
	attack_hit_nodes.clear()
	jump_buffer.clear()
	attack_buffer.clear()
	dash_buffer.clear()
	_coyote_remaining = 0.0
	_extra_jump_ready = false
	_wall_push_left = 0
	_air_time = 0
	respawned.emit()
	_trigger("respawn", 0.6)

## 播放一次性动作，按优先级决定是否打断当前动作。
func _trigger(clip_name: String, duration: float) -> void:
	if anim == null:
		return
	var incoming: int = CLIP_PRIORITY.get(clip_name, 0)
	var current: int = CLIP_PRIORITY.get(_override, 0)
	if _override_left > 0.0 and incoming < current:
		return
	_override = clip_name
	_override_left = duration
	_clip = clip_name
	_play_visual(clip_name, duration)

## Each clip only keys some bones. Restore the others so interrupted poses
## cannot leave a bent leg or a squashed root in the next animation.
func _play_visual(clip_name: String, duration: float = 0.0) -> void:
	if anim == null or not anim.has_animation(clip_name):
		return
	anim.stop()
	for bone in _rest_transforms:
		bone.transform = _rest_transforms[bone]
	var speed := 1.0
	if duration > 0.0:
		speed = anim.get_animation(clip_name).length / duration
	anim.play(clip_name, -1.0, speed)
	anim.advance(0.0)

func _pick_locomotion() -> String:
	if not is_on_floor():
		return "jump" if velocity.y < 0.0 else "fall"
	if absf(velocity.x) > 6.0:
		return "run"
	return "idle"

func _update_visual(delta: float) -> void:
	if rig == null:
		return

	# 朝向：rig 原点即身体水平中心，故取负 scale 是原地翻转
	rig.scale = Vector2(RIG_SCALE * float(facing), RIG_SCALE)

	# 时代切换（world 属性延迟注入，故惰性读取）
	if world != null:
		var era: Variant = world.get("past_era")
		if era is bool:
			if not _era_seen:
				_era_seen = true
				_last_era = era
			elif era != _last_era:
				_last_era = era
				_trigger("era_switch", 0.5)

	# 原地转身时给一个轻微压缩
	if facing != _last_facing:
		_last_facing = facing
		if is_on_floor() and absf(velocity.x) < 20.0:
			_trigger("turn", 0.16)

	if _override_left > 0.0:
		_override_left = maxf(0.0, _override_left - delta)
		if _override_left > 0.0:
			return
		_override = ""

	var want := _pick_locomotion()
	if want != _clip:
		_clip = want
		if anim != null:
			_play_visual(want)

func _draw() -> void:
	# 有骨骼 rig 时不再绘制占位矩形
	if rig != null:
		return
	draw_rect(Rect2(-12, -20, 24, 40), Color("f5c96a") if dash_remaining <= 0.0 else Color("fff2b3"))
	draw_rect(Rect2(-8, -15, 16, 9), Color("2c3756"))
	draw_line(Vector2(-9, -20), Vector2(0, -30), Color("f5c96a"), 3.0)
	draw_line(Vector2(0, -30), Vector2(9, -20), Color("f5c96a"), 3.0)
	draw_circle(Vector2(facing * 5, -10), 2.0, Color("fbf7e8"))
	if attack_remaining > 0.0:
		var box := attack_box()
		draw_rect(box, Color("fff2b3", 0.35))
		draw_line(Vector2(box.position.x, box.position.y),
			Vector2(box.end.x, box.end.y), Color("ffe9a8"), 3.0)
		draw_line(Vector2(box.position.x, box.end.y),
			Vector2(box.end.x, box.position.y), Color("ffe9a8"), 3.0)
