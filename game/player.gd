extends CharacterBody2D

signal health_changed(current: int, maximum: int)
signal respawned

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

var attack_remaining: float = 0.0
var attack_cooldown_remaining: float = 0.0
var attack_hit_nodes: Array[Node] = []

var jump_buffer := InputBuffer.new()
var attack_buffer := InputBuffer.new()
var dash_buffer := InputBuffer.new()

var _coyote_remaining := 0.0
var _was_on_floor := false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and not event.is_echo():
		jump_buffer.press(jump_buffer_window)
	if event.is_action_pressed("attack"):
		attack_buffer.press(attack_buffer_window)
	if event.is_action_pressed("dash"):
		dash_buffer.press(dash_buffer_window)

func _ready() -> void:
	health = maximum_health
	health_changed.emit(health, maximum_health)
	_was_on_floor = is_on_floor()

func _physics_process(delta: float) -> void:
	jump_buffer.tick(delta)
	attack_buffer.tick(delta)
	dash_buffer.tick(delta)

	var direction := Input.get_axis("move_left", "move_right")
	if absf(direction) > 0.01:
		facing = 1 if direction > 0.0 else -1

	var on_floor := is_on_floor()
	if on_floor:
		_coyote_remaining = coyote_time
		dash_ready = true
	else:
		_coyote_remaining = maxf(0.0, _coyote_remaining - delta)

	if dash_buffer.consume() and on_floor and dash_ready:
		dash_remaining = dash_duration
		dash_ready = false

	_update_attack(delta)

	if dash_remaining > 0.0:
		dash_remaining = maxf(0.0, dash_remaining - delta)
		velocity.x = facing * dash_speed
		velocity.y = 0.0
	else:
		velocity.x = direction * move_speed
		velocity.y += gravity_strength * delta
		if jump_buffer.is_active() and _coyote_remaining > 0.0:
			jump_buffer.consume()
			_coyote_remaining = 0.0
			velocity.y = -jump_speed
		elif velocity.y < 0.0 and Input.is_action_just_released("jump"):
			velocity.y *= jump_cut_multiplier

	move_and_slide()

	if _was_on_floor and not is_on_floor():
		_coyote_remaining = coyote_time
	_was_on_floor = is_on_floor()

	if position.y > 700.0:
		take_damage(1)
		respawn()
	queue_redraw()

func _update_attack(delta: float) -> void:
	attack_cooldown_remaining = maxf(0.0, attack_cooldown_remaining - delta)
	var was_active := attack_remaining > 0.0
	if attack_remaining > 0.0:
		attack_remaining = maxf(0.0, attack_remaining - delta)

	if attack_remaining <= 0.0 and attack_cooldown_remaining <= 0.0 \
			and dash_remaining <= 0.0 and attack_buffer.is_active():
		attack_buffer.consume()
		attack_remaining = attack_duration
		attack_cooldown_remaining = attack_cooldown
		attack_hit_nodes.clear()

	# Keep testing for targets for the whole swing so that anything entering
	# the box mid-swing is still hit; the hit list prevents double damage.
	if attack_remaining > 0.0:
		_apply_attack_hits()
	elif was_active:
		attack_hit_nodes.clear()

func attack_box() -> Rect2:
	var box_width := attack_reach
	var x := 12.0 if facing > 0 else -12.0 - box_width
	return Rect2(x, -attack_height * 0.5 - 2.0, box_width, attack_height)

func _apply_attack_hits() -> void:
	var box := attack_box()
	for target in get_tree().get_nodes_in_group("attackable"):
		if not is_instance_valid(target) or target in attack_hit_nodes:
			continue
		var node := target as Node2D
		if node == null:
			continue
		if box.intersects(Rect2(node.global_position - global_position - Vector2(8, 12), Vector2(16, 24))):
			attack_hit_nodes.append(target)
			if target.has_method("take_damage"):
				target.take_damage(attack_damage)

func is_attacking() -> bool:
	return attack_remaining > 0.0

func take_damage(amount: int) -> void:
	health = maxi(0, health - amount)
	health_changed.emit(health, maximum_health)
	if health == 0:
		health = maximum_health
		health_changed.emit(health, maximum_health)
		respawn()

func respawn() -> void:
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
	respawned.emit()

func _draw() -> void:
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
