extends CanvasLayer

const Maps := preload("res://game/world_data.gd")
var world: Node2D
var previous_pause := false
var overview := false
var reveal_all := false
var diagram: Control
var zoom := 1.0
var pan := Vector2.ZERO

class Diagram extends Control:
	var atlas: CanvasLayer
	func _draw() -> void:
		var maps = preload("res://game/world_data.gd")
		var font := ThemeDB.fallback_font
		var current: String = atlas.world.current_map
		var drawing := Rect2(50, 125, 1180, 480)
		if atlas.overview:
			var area := Rect2()
			var first := true
			for id in maps.db().regions:
				var r := maps.region(id)
				var at := Vector2(float(r.world_origin[0]), float(r.world_origin[1]))
				var b := Rect2(at, maps.bounds(id).size * 0.18)
				area = b if first else area.merge(b)
				first = false
			var scale_factor: float = minf(drawing.size.x / area.size.x, drawing.size.y / area.size.y) * atlas.zoom
			var origin: Vector2 = drawing.get_center() - area.get_center() * scale_factor + atlas.pan
			for edge in maps.db().edges:
				var a: Dictionary = maps.region(edge.a)
				var b: Dictionary = maps.region(edge.b)
				var ca: Vector2 = origin + (Vector2(a.world_origin[0], a.world_origin[1]) + maps.anchor(edge.a, "travel_" + edge.b) * 0.18) * scale_factor
				var cb: Vector2 = origin + (Vector2(b.world_origin[0], b.world_origin[1]) + maps.anchor(edge.b, "travel_" + edge.a) * 0.18) * scale_factor
				var elbow := Vector2(cb.x, ca.y)
				var line_color := Color("40515b") if edge.kind == "main" else Color("796e58")
				draw_line(ca, elbow, line_color, 1)
				draw_line(elbow, cb, line_color, 1)
			for id in maps.db().regions:
				var r: Dictionary = maps.region(id)
				var at := Vector2(r.world_origin[0], r.world_origin[1])
				var known: bool = atlas.reveal_all or atlas.world.chapter_flags.get("visited_" + id, false)
				var tint := Color(r.color) if known else Color(r.color).darkened(0.55)
				var model: Dictionary = maps.model(id, false)
				for room in model.free:
					draw_rect(Rect2(origin + (at + room.position * 0.18) * scale_factor, room.size * scale_factor * 0.18), tint.darkened(0.5))
				for line in model.outline: draw_line(origin + (at + line[0] * 0.18) * scale_factor, origin + (at + line[1] * 0.18) * scale_factor, tint.lightened(0.2), 1)
				var label: String = id + (" " + str(r.title) if known and atlas.zoom >= 1.5 else "")
				draw_string(font, origin + at * scale_factor + Vector2(0, -4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ead8a9") if id == current else tint.lightened(0.4))
				if id == current: draw_circle(origin + (at + atlas.world.player.position * 0.18) * scale_factor, 4, Color("f3dfac"))
		else:
			var area: Rect2 = maps.bounds(current)
			var scale_factor: float = minf(drawing.size.x / area.size.x, drawing.size.y / area.size.y) * atlas.zoom
			var origin: Vector2 = drawing.get_center() - area.get_center() * scale_factor + atlas.pan
			var data: Dictionary = maps.region(current)
			var model: Dictionary = maps.model(current, atlas.world.past_era)
			for r in model.free: draw_rect(Rect2(origin + r.position * scale_factor, r.size * scale_factor), Color("22383d"))
			for line in model.outline: draw_line(origin + line[0] * scale_factor, origin + line[1] * scale_factor, Color(data.color).lightened(0.3), 1.3)
			for i in range(data.rooms.size()):
				var seen: bool = atlas.reveal_all or atlas.world.chapter_flags.get("seen_%s_%d" % [current, i], false)
				var room: Rect2 = maps.rect(data.rooms[i].rect)
				if not seen: draw_rect(Rect2(origin + room.position * scale_factor, room.size * scale_factor), Color(0.04, 0.06, 0.08, 0.8))
				else: draw_string(font, origin + room.get_center() * scale_factor, str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("bec8b2"))
			for item in maps.interactions(current):
				if not atlas.reveal_all and not atlas.world.chapter_flags.get("seen_%s_%d" % [current, item.room], false): continue
				var at: Vector2 = origin + item.at * scale_factor
				if item.id == "rest": draw_circle(at, 5, Color("edcb80"))
				elif item.id.begins_with("travel_"): draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), Color("87bfc8"))
				elif item.id.begins_with("mythic_"):
					var step: int = int(item.id.trim_prefix("mythic_"))
					var beast: String = data.mythic.steps[step].beast
					var color: Color = {"dragon": Color("6fc6d1"), "phoenix": Color("e4a36d"), "qilin": Color("98bd86")}[beast]
					draw_circle(at, 5, color)
					draw_string(font, at + Vector2(7, -5), str(step + 1) + {"dragon": "龙", "phoenix": "凤", "qilin": "麟"}[beast], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
				else: draw_circle(at, 2.5, Color("c9c4a7"))
			if is_instance_valid(atlas.world.environment):
				var environment = atlas.world.environment
				var chamber: int = int(data.get("mythic", {}).get("chamber", -1))
				if chamber >= 0 and (atlas.reveal_all or atlas.world.chapter_flags.get("seen_%s_%d" % [current, chamber], false)):
					for item in environment.interactions():
						var at: Vector2 = origin + item.at * scale_factor
						draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color("e4ad79"), false, 2)
			draw_circle(origin + atlas.world.player.position * scale_factor, 5, Color("ffefca"))
			draw_arc(origin + atlas.world.player.position * scale_factor, 8, 0, TAU, 16, Color("d5ad6c"), 2)

func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color("10191f")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	diagram = Diagram.new()
	diagram.atlas = self
	add_child(diagram)
	var heading := Label.new()
	heading.name = "Heading"
	heading.position = Vector2(45, 25)
	heading.add_theme_font_size_override("font_size", 26)
	add_child(heading)
	var toggle := Button.new()
	toggle.text = "切换 区域 / 世界全图"
	toggle.position = Vector2(830, 30)
	toggle.pressed.connect(func(): overview = not overview; zoom = 1; pan = Vector2.ZERO; refresh())
	add_child(toggle)
	var close := Button.new()
	close.text = "返回探索 · M / Esc"
	close.position = Vector2(1060, 30)
	close.pressed.connect(close_map)
	add_child(close)
	var legend := Label.new()
	legend.text = "滚轮缩放 · 拖拽平移 · 金点灯龛 · 方块自动出口 · 小点为遗存 · 暗色未探索"
	legend.position = Vector2(45, 658)
	add_child(legend)
	visible = false

func refresh() -> void:
	get_node("Heading").text = "八荒世界 · %d区" % Maps.db().regions.size() if overview else world.current_map + " " + Maps.region(world.current_map).title + " · 房间网络"
	diagram.queue_redraw()

func open_map() -> void:
	world.reset_view()
	previous_pause = get_tree().paused
	world._set_flag("seen_%s_%d" % [world.current_map, Maps.room_at(world.current_map, world.player.position)])
	visible = true
	get_tree().paused = true
	refresh()

func close_map() -> void:
	visible = false
	get_tree().paused = previous_pause

func _input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("open_map") or event.is_action_pressed("ui_cancel"):
		close_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("switch_era"):
		overview = not overview
		zoom = 1
		pan = Vector2.ZERO
		refresh()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom = clampf(zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.83), 0.5, 8)
		refresh()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		pan += event.relative
		refresh()
