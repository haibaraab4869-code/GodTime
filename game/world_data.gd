extends RefCounted

const LAYOUT_VERSION := 7
const Mythic := preload("res://game/mythic_puzzle.gd")
static var database: Dictionary = {}
static var cache: Dictionary = {}
static var TITLES: Dictionary:
	get:
		var result := {}
		for id in db().regions: result[id] = db().regions[id].title
		return result

static func db() -> Dictionary:
	if database.is_empty():
		database = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/world_regions.json"))
		for zone in database.regions.values():
			for hazard in zone.structure.hazards:
				if hazard.kind == "buried":
					hazard.kind = "open"
					hazard.cracked = true
	return database

static func region(id: String) -> Dictionary: return db().regions[id]

static func bounds(id: String) -> Rect2:
	var b: Array = region(id).bounds
	return Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))

static func rect(values: Array) -> Rect2:
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))

static func interactions(id: String) -> Array:
	var result: Array = []
	for raw in region(id).interactions:
		var item: Dictionary = raw.duplicate()
		item.at = Vector2(float(raw.at[0]), float(raw.at[1]))
		result.append(item)
	return result

static func era_ok(item: Dictionary, past: bool) -> bool:
	# 交互的时代归属：缺省 both（旅行门/灯龛/道具都没有这个字段）。
	# 能力取得点是唯一带 era 的交互，过去态/现在态的互斥由这一处统一判定：
	# nearest_interaction / _interact / _draw / 章节标牌四处都调它，不要各写一份。
	var era := str(item.get("era", "both"))
	if era == "both": return true
	return era == ("past" if past else "present")

static func anchor(id: String, action: String) -> Vector2:
	if action.begins_with("to_"): action = "travel_" + action.trim_prefix("to_")
	for item in interactions(id):
		if item.id == action: return item.at
	return spawn(id)

static func spawn(id: String) -> Vector2:
	# 出生房的地面在 floor_y，不是 rect 底边：W01 R01 的房间盒向下多出 384px 实心岩体，
	# 用 rect.end.y 会把人塞进墙里。（handoff-world-29 §1 第 2 条）
	var room: Dictionary = region(id).rooms[0]
	var r := rect(room.rect)
	var floor_y := float(room.get("floor_y", r.end.y))
	return Vector2(r.position.x + 48, floor_y - 20)

static func entry(id: String, from: String) -> Vector2:
	for item in interactions(id):
		if item.id == "travel_" + from:
			# 转换器按 floor_y 算好落点：跨区入口的 at 是贴墙点，不是地面点。
			if item.has("landing"):
				return Vector2(float(item.landing[0]), float(item.landing[1]))
			return item.at - Vector2(float(item.get("side", 1)) * 40, 0)
	return spawn(id)

static func boundary(item: Dictionary) -> Rect2:
	# 门廊：从门位 at.y 到该房 floor_y 的整条触发区，否则站在地面永远走不到门口。
	if item.has("porch"):
		var p: Array = item.porch
		return Rect2(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
	return Rect2(item.at - Vector2(24, 48), Vector2(48, 72))

static func room_at(id: String, at: Vector2) -> int:
	var best := INF
	var index := 0
	for i in range(region(id).rooms.size()):
		var r := rect(region(id).rooms[i].rect)
		if r.has_point(at): return i
		var distance := r.get_center().distance_squared_to(at)
		if distance < best:
			best = distance
			index = i
	return index

static func layers(id: String) -> Array[String]:
	var result: Array[String] = []
	for room in region(id).rooms: result.append(room.id + " " + room.name)
	return result

static func level_at(id: String, at: Vector2) -> int: return room_at(id, at)

static func connections(id: String) -> Array:
	return db().edges.filter(func(e): return e.a == id or e.b == id)

static func target(edge: Dictionary, id: String) -> String: return edge.b if edge.a == id else edge.a

static func model(id: String, past := false) -> Dictionary:
	# 两态几何分开缓存：过去态与现在态的房间/连边集合不同（M4）。
	var key := "%s:%s" % [id, past]
	if cache.has(key): return cache[key]
	var data := region(id)
	if int(data.get("layout_version", 6)) == 7:
		cache[key] = load("res://game/map_slice_geometry.gd").build(data, past)
		return cache[key]
	var free: Array[Rect2] = []
	var platforms: Array[Rect2] = []
	var stairs: Array = []
	var bridge := Rect2()
	for room in data.rooms:
		var r := rect(room.rect)
		var cut := float(int(room.shape) * 32)
		free.append(Rect2(r.position + Vector2(0, cut), r.size - Vector2(0, cut)))
		if cut > 0: free.append(Rect2(r.position + Vector2(cut, 0), Vector2(r.size.x - cut * 2, cut)))
	for index in range(data.links.size()):
		var link: Array = data.links[index]
		var a := rect(data.rooms[int(link[0])].rect)
		var b := rect(data.rooms[int(link[1])].rect)
		var ca := Vector2(a.get_center().x, a.end.y)
		var cb := Vector2(b.get_center().x, b.end.y)
		if is_equal_approx(ca.y, cb.y):
			free.append(Rect2(minf(ca.x, cb.x), ca.y - (192 if "gallery" in data.structure.skeleton else 128), absf(ca.x - cb.x), 192 if "gallery" in data.structure.skeleton else 128))
		else:
			var top := minf(ca.y, cb.y)
			var bottom := maxf(ca.y, cb.y)
			free.append(Rect2(ca.x - 128, top - 128, 256, bottom - top + 128))
			var route: Array[Vector2] = []
			var meta: Dictionary = data.structure.connections.filter(func(c): return int(c.link) == index)[0]
			var tier: String = meta.tier
			var traversal: String = str(data.mythic.traversal)
			if tier in ["R1", "R2"]:
				var rise := 48 if tier == "R1" else 128
				for step in range(1, int(ceil((bottom - top) / rise))):
					var x := ca.x + (-56 if step % 2 == 1 else 56)
					var y := bottom - step * rise
					platforms.append(Rect2(x - 56, y, 112, 16))
					route.append(Vector2(x, y - 20))
			else:
				platforms.append(Rect2(ca.x - 128, top + (bottom - top) * 0.5, 48 if tier == "R3" else 96, 16))
				if tier == "R3": platforms.append(Rect2(ca.x - 128, (top + bottom) / 2, 256, 16))
				elif tier == "R4" and int(data.structure.max_drop) < int(bottom - top): platforms.append(Rect2(ca.x - 128, bottom - float(data.structure.max_drop), 256, 16))
			if traversal == "terrace" and tier == "R3": traversal = "wall" if int(data.number) >= 22 else "vine"
			elif traversal == "terrace" and tier in ["R4", "R5"] and meta.return_assist: traversal = "vine"
			platforms.append(Rect2(ca.x - 40, top, 80, 12))
			stairs.append({"link": link, "top": top, "bottom": bottom, "center": ca.x, "steps": route, "tier": tier, "traversal": traversal, "assisted": bool(meta.return_assist) or tier == "R3"})
	for hall in data.structure.pogo_halls:
		var left := float(hall.left)
		var right := float(hall.right)
		var floor_y := float(hall.floor)
		free.append(Rect2(left - 96, floor_y - 192, right - left + 192, 192))
		free.append(Rect2(left - 64, floor_y - 384, 128, 384))
		free.append(Rect2(right - 64, floor_y - 384, 128, 384))
		platforms.append(Rect2(left - 16, floor_y, right - left + 32, 24))
		platforms.append(Rect2(left + 64, floor_y - 192, right - left - 128, 24))
		# Wall-side return stairs are safe, broad and never inside the nail bed.
		for side in [left - 64, right + 32]:
			for k in range(1, 4): platforms.append(Rect2(side, floor_y - k * 48, 32, 12))
	for hazard in data.structure.hazards:
		if int(hazard.hall) < 0:
			var r := rect(hazard.rect)
			platforms.append(Rect2(r.position + Vector2(-8, 12), Vector2(r.size.x + 16, 16)))
	if "R5" in data.structure.tiers:
		var last_room := rect(data.rooms[-1].rect)
		var bottom := last_room.end.y
		var top := maxf(128, bottom - float(data.structure.max_drop))
		bottom = top + float(data.structure.max_drop)
		var tower_x := bounds(id).end.x - 160
		free.append(Rect2(tower_x - 96, top - 128, 192, bottom - top + 128))
		free.append(Rect2(last_room.get_center().x, bottom - 128, tower_x - last_room.get_center().x + 96, 128))
		platforms.append(Rect2(tower_x - 96, top, 80, 16))
		platforms.append(Rect2(tower_x - 96, bottom, 192, 16))
		for k in range(1, 3): platforms.append(Rect2(tower_x - 96 if k == 1 else tower_x + 48, top + (bottom - top) * k / 3, 48, 16))
		stairs.append({"link": [], "top": top, "bottom": bottom, "center": tower_x, "steps": [], "tier": "R5", "traversal": "vine", "assisted": true})
	for k in range(int(data.structure.niches)):
		var room := rect(data.rooms[k % data.rooms.size()].rect)
		var x := room.end.x
		free.append(Rect2(x - 32, room.end.y - 176, 128, 128))
		platforms.append(Rect2(x, room.end.y - 48, 96, 12))
		platforms.append(Rect2(x + 32, room.end.y - 96, 64, 16))
	if data.get("mythic", {}).has("chamber"):
		var mechanism_room := rect(data.rooms[int(data.mythic.chamber)].rect)
		platforms = platforms.filter(func(p): return not mechanism_room.has_point(p.get_center()))
		var center_x := mechanism_room.get_center().x
		platforms.append(Rect2(mechanism_room.position.x, mechanism_room.end.y, maxf(0, center_x - 128 - mechanism_room.position.x), 24))
		platforms.append(Rect2(center_x + 128, mechanism_room.end.y, maxf(0, mechanism_room.end.x - center_x - 128), 24))
	# Existing narrative and arrival markers keep a real, supported footing.
	for point in interactions(id):
		if point.id == "mythic_1": continue
		platforms.append(Rect2(point.at + Vector2(-28, 20), Vector2(56, 16)))
	# Convert the empty-space union into solid walls; merge rows into long bodies.
	var area := bounds(id)
	var walls: Array[Rect2] = []
	var open_cells := {}
	for y in range(0, int(area.size.y), 32):
		var start := -1
		for x in range(0, int(area.size.x) + 32, 32):
			var solid := x < int(area.size.x)
			if solid:
				var point := Vector2(x + 16, y + 16)
				for empty in free:
					if empty.has_point(point):
						solid = false
						open_cells[Vector2i(x, y)] = true
						break
			if solid and start < 0: start = x
			elif not solid and start >= 0:
				walls.append(Rect2(start, y, x - start, 32))
				start = -1
	var collision: Array[Rect2] = walls.duplicate()
	collision.append_array(platforms)
	var outline: Array = []
	for cell in open_cells:
		var at := Vector2(cell)
		for side in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if open_cells.has(cell + side * 32): continue
			if side == Vector2i.LEFT: outline.append([at, at + Vector2(0, 32)])
			elif side == Vector2i.RIGHT: outline.append([at + Vector2(32, 0), at + Vector2(32, 32)])
			elif side == Vector2i.UP: outline.append([at, at + Vector2(32, 0)])
			else: outline.append([at + Vector2(0, 32), at + Vector2(32, 32)])
	cache[key] = {"free": free, "walls": walls, "platforms": platforms, "stairs": stairs, "collision": collision, "outline": outline, "bridge": bridge}
	return cache[key]

static func device_targets(raw: Dictionary) -> Array:
	# 机关目标档位。空数组 = 无解谜（levels<=1，或 solution 是一整句说明）。
	var levels := int(raw.get("levels", 1))
	if levels <= 1: return []
	var solution: Variant = raw.get("solution", 0)
	if solution is Array: return solution.map(func(value): return int(value))
	if solution is int or solution is float: return [int(solution)]
	var text := str(solution)
	if text.length() > 24: return []
	var digits := ""
	var result: Array = []
	for letter in text:
		if letter >= "0" and letter <= "9": digits += letter
		elif not digits.is_empty():
			result.append(int(digits))
			digits = ""
	if not digits.is_empty(): result.append(int(digits))
	return result

static func device_pads(id: String, flags: Dictionary) -> Array[Rect2]:
	# 解谜类机关置位后补一块落脚台；无解谜的机关（说明牌）不补，免得凭空挡住落口。
	var result: Array[Rect2] = []
	var zone := region(id)
	for raw in zone.get("devices", []):
		if str(raw.get("type", "")) == "升降平台": continue
		var targets := device_targets(raw)
		if targets.is_empty(): continue
		var peak := 0
		for value in targets: peak = maxi(peak, int(value))
		if peak == 0: continue
		var flag := str(raw.get("flag", ""))
		if flag.is_empty() or not flags.get(flag, false): continue
		var room := {}
		for candidate in zone.rooms:
			if str(candidate.id) == str(raw.get("room", "")): room = candidate
		if room.is_empty(): continue
		var r := rect(room.rect)
		var floor_y := float(room.get("floor_y", r.end.y))
		result.append(Rect2(r.position.x + 48, floor_y - 160, maxf(96.0, r.size.x - 96), 12))
	return result

static func geometry(id: String, past: bool, _flags: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = model(id, past).collision.duplicate()
	# Era-specific masonry is off the permanent connectors and all narrative anchors.
	# 29 区世界（layout_version 7）没有这堵旧"现在态封墙"，它会在末房中心凭空立一堵 32×64。
	if int(region(id).get("layout_version", 6)) < 7 and not past and not _flags.get("terrain_" + id, false):
		var last := rect(region(id).rooms[-1].rect)
		var floor_y := float(region(id).rooms[-1].get("floor_y", last.end.y))
		result.append(Rect2(last.get_center().x - 16, floor_y - 64, 32, 64))
	result.append_array(Mythic.barriers(region(id), model(id, past), past, _flags))
	# 29 区世界没有旧的三灵因果锁，mythic 一律为 {}；两行护栏保证无 mythic 的区安全跳过。
	var mythic: Dictionary = region(id).get("mythic", {})
	if int(mythic.get("chamber", -1)) >= 0:
		result.append_array(load("res://game/mythic_environment.gd").fixtures(region(id), past, _flags))
	return result
