extends RefCounted
## Pure causal state: no scene mutation until the caller validates collision.

static func progress(id: String, flags: Dictionary) -> int:
	return clampi(int(flags.get("mythic_" + id, 0)), 0, 3)

static func attempt(id: String, spec: Dictionary, station: int, past: bool, flags: Dictionary) -> Dictionary:
	var step := progress(id, flags)
	if step == 3: return {"ok": false, "message": "三灵因果锁已固定，两代通路均可返回。"}
	if station != step: return {"ok": false, "message": "先完成：" + str(spec.steps[step].text)}
	if bool(spec.steps[step].past) != past:
		return {"ok": false, "message": "此处需要切换到" + ("过去" if spec.steps[step].past else "未来") + "。"}
	return {"ok": true, "next": step + 1, "message": "因果锁已固定，前进边界开放。" if step == 2 else "因果已记录。下一步：" + str(spec.steps[step + 1].text)}

static func barriers(zone: Dictionary, model: Dictionary, past: bool, flags: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not zone.has("mythic"): return result
	# 29 区世界的 mythic 恒为 {}：没有 steps 的区不生成任何封锁体。
	var steps: Array = zone.mythic.get("steps", [])
	if steps.is_empty(): return result
	var step := progress(zone.id, flags)
	if step >= 2: return result
	# The first horizontal connector is a real temporal lock. The first station
	# is in the spawn room; its past action opens the future investigation route.
	if past == bool(zone.mythic.steps[step].past): return result
	for link in zone.links:
		var a: Array = zone.rooms[int(link[0])].rect
		var b: Array = zone.rooms[int(link[1])].rect
		if not is_equal_approx(float(a[1] + a[3]), float(b[1] + b[3])): continue
		var x := (float(a[0] + a[2] / 2) + float(b[0] + b[2] / 2)) / 2
		var y := float(a[1] + a[3])
		# Eight distinct silhouettes share the causal-lock contract.
		match str(zone.mythic.family):
			"sluice": result.append(Rect2(x - 24, y - 128, 48, 128))
			"wind":
				result.append(Rect2(x - 64, y - 128, 32, 128))
				result.append(Rect2(x + 32, y - 128, 32, 128))
			"root":
				result.append(Rect2(x - 48, y - 128, 96, 32))
				result.append(Rect2(x - 16, y - 96, 32, 96))
			"gear":
				result.append(Rect2(x - 48, y - 128, 96, 48))
				result.append(Rect2(x - 24, y - 80, 48, 80))
			"light": result.append(Rect2(x - 8, y - 128, 16, 128))
			"tide": result.append(Rect2(x - 64, y - 128, 128, 128))
			"echo":
				for dx in [-48, 0, 48]: result.append(Rect2(x + dx - 8, y - 128, 16, 128))
			"triad":
				result.append(Rect2(x - 48, y - 128, 32, 128))
				result.append(Rect2(x - 16, y - 96, 32, 96))
				result.append(Rect2(x + 16, y - 64, 32, 64))
		break
	return result
