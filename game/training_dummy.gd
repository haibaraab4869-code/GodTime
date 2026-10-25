extends Node2D

# Prototype training dummy. Not a designed enemy: no AI, no attacks, no reward.
# It exists so the player attack can be observed, tuned and tested.
const GROUP := "attackable"

@export var maximum_health: int = 3
@export var respawn_delay: float = 2.0

var health: int = 3
var flash_remaining := 0.0
var respawn_remaining := 0.0

func _ready() -> void:
	health = maximum_health
	add_to_group(GROUP)

func take_damage(amount: int) -> void:
	if respawn_remaining > 0.0:
		return
	health = maxi(0, health - amount)
	flash_remaining = 0.12
	if health == 0:
		respawn_remaining = respawn_delay
	queue_redraw()

func is_broken() -> bool:
	return respawn_remaining > 0.0

func _process(delta: float) -> void:
	if flash_remaining > 0.0:
		flash_remaining = maxf(0.0, flash_remaining - delta)
		queue_redraw()
	if respawn_remaining > 0.0:
		respawn_remaining = maxf(0.0, respawn_remaining - delta)
		if respawn_remaining <= 0.0:
			health = maximum_health
		queue_redraw()

func _draw() -> void:
	if respawn_remaining > 0.0:
		draw_rect(Rect2(-8, 9, 7, 4), Color("5a5f74"))
		draw_rect(Rect2(1, 11, 6, 3), Color("5a5f74"))
		draw_rect(Rect2(-3, 6, 4, 3), Color("5a5f74"))
		return
	var body := Color("e8e2cf") if flash_remaining <= 0.0 else Color("ffffff")
	draw_rect(Rect2(-8, -12, 16, 24), body)
	draw_rect(Rect2(-8, -12, 16, 4), Color("c9c0a6"))
	draw_rect(Rect2(-5, -5, 3, 4), Color("2c3756"))
	draw_rect(Rect2(2, -5, 3, 4), Color("2c3756"))
	for index in range(maximum_health):
		var filled := index < health
		var pip := Rect2(-maximum_health * 4 + index * 8, -22, 5, 4)
		draw_rect(pip, Color("f2d58e") if filled else Color("3b4560"))
