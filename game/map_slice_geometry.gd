extends RefCounted

## v7 区切片几何：把 29 区设计里的 rooms / links / connections 变成可走的空间。
##
## 设计数据里房间是**精确铺满**区矩形的：floor_y 往往正好等于 rect 底边，而正下方
## 就是另一个房间的自由空间。若只按"非自由即实心"栅格化，上下相邻的房间会合成一个
## 大空腔，玩家会直接掉到区底。因此这里额外生成两层东西：
##   1. 竖井/走廊开口（openings）——连接处必须是通的；
##   2. 地板实体（slabs）——每个房间的 floor_y 处铺 16px 实心地板，开口处挖掉。
##
## 两态（M4）：rooms[].era / links[].era 为 "past" / "present" 的条目只在那一态存在。
## 现在态下，只在过去存在的房间就是实心岩体、只在过去存在的连边就是断口——
## 这正是 W01「现在桥断三段」与 W23 八门景室只在过去可进的数据依据。

static func box(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])

static func era_key(past: bool) -> String:
	return "past" if past else "present"

static func build(data: Dictionary, past := false) -> Dictionary:
	var free: Array[Rect2] = []
	var platforms: Array[Rect2] = []
	var stairs: Array = []
	var openings: Array[Rect2] = []
	var floors: Array = data.rooms.map(func(r): return float(r.floor_y))
	var area := box(data.bounds)
	var here := era_key(past)
	var active := {}
	for index in range(data.rooms.size()):
		var room_era := str(data.rooms[index].get("era", "both"))
		if room_era == "both" or room_era == here: active[index] = true

	for index in range(data.rooms.size()):
		if not active.has(index): continue
		var room: Dictionary = data.rooms[index]
		var r := box(room.rect)
		var ceiling := float(room.get("ceiling_y", r.position.y))
		free.append(Rect2(Vector2(r.position.x, ceiling), Vector2(r.size.x, float(room.floor_y) - ceiling)))

	for i in range(data.links.size()):
		var link: Array = data.links[i]
		if not active.has(int(link[0])) or not active.has(int(link[1])): continue
		var matches: Array = data.structure.connections.filter(func(c): return int(c.link) == i)
		var meta: Dictionary = matches[0]
		var link_era := str(meta.get("era", "both"))
		if link_era != "both" and link_era != here: continue
		var a := box(data.rooms[int(link[0])].rect)
		var b := box(data.rooms[int(link[1])].rect)
		var ay: float = floors[int(link[0])]
		var by: float = floors[int(link[1])]
		# 竖直相邻（上下楼）走竖井；否则走走廊。判据看矩形是否在 y 上不重叠，
		# 不能用"房间中心 x 是否相等"——设计里上下楼的房间宽度常常不同。
		var stacked := a.end.y <= b.position.y + 0.5 or b.end.y <= a.position.y + 0.5
		if stacked:
			var top := minf(ay, by)
			var bottom := maxf(ay, by)
			var low := maxf(a.position.x, b.position.x)
			var high := minf(a.end.x, b.end.x)
			var width := 128.0
			var center: float = a.get_center().x + float(meta.get("shaft_offset", 0))
			if high - low >= width:
				center = clampf(center, low + width / 2, high - width / 2)
			elif high > low:
				center = (low + high) / 2
				width = maxf(48.0, high - low)
			var ceiling := maxf(0.0, top - 192)
			var slot := Rect2(center - width / 2, ceiling, width, bottom - ceiling)
			free.append(slot)
			openings.append(slot)
			var landings: Array[Rect2] = []
			for k in range(int(meta.landings)):
				var landing := Rect2(center - 64, top + 256 + k * 320, 64, 16)
				landings.append(landing)
				platforms.append(landing)
			stairs.append({"link": link, "top": top, "bottom": bottom, "center": center,
				"steps": [], "tier": meta.tier, "traversal": "vine", "assisted": bool(meta.return_assist),
				"assist_offset": 0, "width": width, "depth_cue": meta.get("cue", data.structure.depth_cue),
				"landings": landings})
		else:
			var left := minf(a.get_center().x, b.get_center().x)
			var right := maxf(a.get_center().x, b.get_center().x)
			var ceiling := maxf(0.0, minf(ay, by) - 192)
			var corridor := Rect2(left, ceiling, right - left, maxf(ay, by) - ceiling)
			free.append(corridor)
			openings.append(corridor)

	# 每个房间在 floor_y 处铺 16px 地板；竖井与走廊的开口从这里挖掉。
	var slabs: Array[Rect2] = []
	for index in range(data.rooms.size()):
		if not active.has(index): continue
		var room: Dictionary = data.rooms[index]
		var r := box(room.rect)
		var fy: float = float(room.floor_y)
		var pieces: Array[Rect2] = [Rect2(r.position.x, fy, r.size.x, 16)]
		for hole in openings:
			if hole.end.y <= fy or hole.position.y >= fy + 16: continue
			var next: Array[Rect2] = []
			for piece in pieces:
				var left := maxf(piece.position.x, hole.position.x)
				var right := minf(piece.end.x, hole.end.x)
				if right <= left:
					next.append(piece)
					continue
				if left > piece.position.x:
					next.append(Rect2(piece.position.x, piece.position.y, left - piece.position.x, 16))
				if right < piece.end.x:
					next.append(Rect2(right, piece.position.y, piece.end.x - right, 16))
			pieces = next
		slabs.append_array(pieces)

	var bridge := Rect2(640, floors[0], 256, 12)
	var walls: Array[Rect2] = []
	var cells := {}
	for y in range(0, int(area.end.y), 32):
		var start := -1
		for x in range(0, int(area.end.x) + 32, 32):
			var solid := x < int(area.end.x)
			if solid:
				for empty in free:
					# 栅格中心正好落在房间地板线上时按实心处理会把地板啃掉 16px，
					# 让"落点 = floor_y - 20"的人卡在墙里；这里放宽 0.4px。
					if empty.grow(0.4).has_point(Vector2(x + 16, y + 16)):
						solid = false
						cells[Vector2i(x, y)] = true
						break
			if solid and start < 0: start = x
			elif not solid and start >= 0:
				walls.append(Rect2(start, y, x - start, 32))
				start = -1
	# 地板实体会盖住栅格里的若干格；从开放格表里扣掉，轮廓线才会画出地板边缘。
	for slab in slabs:
		var x0 := int(floor(slab.position.x / 32.0)) * 32
		var x1 := int(ceil(slab.end.x / 32.0)) * 32
		for x in range(x0, x1, 32):
			var row := int(floor(slab.position.y / 32.0)) * 32
			cells.erase(Vector2i(x, row))
	walls.append_array(slabs)

	var porches: Array[Rect2] = []
	for point in data.interactions:
		if point.has("porch"):
			var p: Array = point.porch
			porches.append(Rect2(p[0], p[1], p[2], p[3]))
	var snaps: Array = []
	for point in data.interactions:
		if point.id == "mythic_1": continue
		var feet := Vector2(point.at[0], point.at[1] + 20)
		var supported := false
		for surface in walls + platforms:
			if feet.x >= surface.position.x + 12 and feet.x <= surface.end.x - 12 and surface.position.y >= feet.y and surface.position.y <= feet.y + 8:
				point.at[1] = surface.position.y - 20
				supported = true
				break
		if not supported:
			var pad := Rect2(feet - Vector2(28, 0), Vector2(56, 16))
			# 悬空遗存给一块落脚板；但门廊里不能加，否则会挡住跨区入口的落地。
			var blocked := false
			for porch in porches:
				if porch.intersects(pad): blocked = true
			for wall in walls:
				if wall.has_point(feet): blocked = true
			if blocked: continue
			if not platforms.any(func(p): return p.grow(48).intersects(pad)):
				platforms.append(pad)
				snaps.append(point.id)
	var collision: Array[Rect2] = walls.duplicate()
	collision.append_array(platforms)
	# 轮廓按行/列合并成连续线段：29 区里最大的区有 3 万多个开放格，
	# 逐格画四边会让每帧几万条 draw_line，合并后通常只剩几百条。
	var outline: Array = []
	var max_x := int(area.end.x)
	var max_y := int(area.end.y)
	for y in range(0, max_y + 32, 32):
		for pair in [[Vector2i(0, -32), 0], [Vector2i(0, 32), 32]]:
			var dir: Vector2i = pair[0]
			var start := -1
			for x in range(0, max_x + 32, 32):
				var need: bool = cells.has(Vector2i(x, y)) and not cells.has(Vector2i(x, y) + dir)
				if need and start < 0: start = x
				elif not need and start >= 0:
					outline.append([Vector2(start, y + pair[1]), Vector2(x, y + pair[1])])
					start = -1
	for x in range(0, max_x + 32, 32):
		for pair in [[Vector2i(-32, 0), 0], [Vector2i(32, 0), 32]]:
			var dir: Vector2i = pair[0]
			var start := -1
			for y in range(0, max_y + 32, 32):
				var need: bool = cells.has(Vector2i(x, y)) and not cells.has(Vector2i(x, y) + dir)
				if need and start < 0: start = y
				elif not need and start >= 0:
					outline.append([Vector2(x + pair[1], start), Vector2(x + pair[1], y)])
					start = -1
	return {"free": free, "walls": walls, "platforms": platforms, "stairs": stairs,
		"collision": collision, "outline": outline, "bridge": bridge, "anchor_pads": snaps}
