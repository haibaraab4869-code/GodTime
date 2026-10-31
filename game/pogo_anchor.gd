extends Node2D
var world: Node2D
var style := "bell"
var flash := 0.0
func _ready() -> void: add_to_group("pogoable")
func hit_bounds() -> Rect2: return Rect2(global_position - Vector2(18, 6), Vector2(36, 12))
func struck() -> void: flash = 0.16
func _process(delta: float) -> void:
	flash = maxf(0, flash - delta)
	queue_redraw()
func _draw() -> void:
	var color := Color("fff2cb") if flash > 0 else Color("b4a581")
	draw_line(Vector2(0, -64), Vector2(0, -8), Color("7f857c"), 2)
	if style == "bell": draw_arc(Vector2(0, 4), 18, PI, TAU, 16, color, 3)
	else: draw_rect(Rect2(-18, -6, 36, 12), color, false, 3)
	draw_line(Vector2(-18, 2), Vector2(18, 2), color, 3)
