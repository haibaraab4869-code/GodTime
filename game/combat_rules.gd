extends RefCounted

## 四凶战斗解析：给定流派与动作，算出伤害、削韧、凶气、射程与各类附加效果。
##
## 把"数值怎么算"集中在这里，`player.gd` 只负责状态与时序。
## 依据 docs/design/feature-four-beasts.md §2 各表。

const Config := preload("res://game/combat_config.gd")
const Stagger := preload("res://game/stagger.gd")

## 一次攻击的解析结果。用字典而不是类，便于测试直接比字段。
static func resolve_combo(form: String, index: int, sharp: bool) -> Dictionary:
	var seg := Config.combo_segment(form, index)
	if seg.is_empty():
		return {}
	return {
		"kind": "combo",
		"index": index,
		"damage": int(seg["damage"]),
		"reach": float(seg["reach"]),
		"height": float(seg["height"]),
		"poise": float(seg["poise"]),
		"qi": int(seg["qi"]),
		"duration": float(seg["duration"]),
		"mark": String(seg.get("applies_mark", "")),
		"sharp_consumed": false,
	}

static func resolve_heavy(form: String, stacks: Dictionary, sharp: bool) -> Dictionary:
	var data := Config.form_data(form)
	var cfg: Dictionary = data.get("heavy", {})
	var result := {
		"kind": "heavy",
		"duration": float(cfg.get("duration", 0.5)),
		"reach": float(cfg.get("reach", 40.0)),
		"height": float(cfg.get("height", 40.0)),
		"poise": float(cfg.get("poise", 6)),
		"qi": int(cfg.get("qi", 10)),
		"lunge": 0.0,
		"lunge_stop": 0.0,
		"sharp_consumed": false,
		"mark_consumed": "",
	}
	match form:
		"taotie":
			var marked := bool(stacks.get("hunger", false))
			result["damage"] = int(cfg["damage_marked"]) if marked else int(cfg["damage_plain"])
			result["heal"] = int(cfg["heal"]) if marked else 0
			result["mark_consumed"] = "hunger" if marked else ""
		"qiongqi":
			var damage := float(cfg["damage"])
			var poise := float(cfg["poise"])
			if sharp:
				damage *= float(cfg["precise_mult"])
				poise *= 1.5
				result["sharp_consumed"] = true
			result["damage"] = int(round(damage))
			result["poise"] = poise
			result["lunge"] = float(cfg["lunge"])
			result["lunge_stop"] = float(cfg["lunge_stop"])
		"taowu":
			var ratio := clampf(float(stacks.get("charge_ratio", 1.0)), float(cfg["min_ratio"]), 1.0)
			var bonus_add := float(stacks.get("reverse_damage_bonus", 0.0))
			var poise_add := float(stacks.get("reverse_poise_bonus", 0.0))
			result["damage"] = int(round(float(cfg["damage"]) * ratio * (1.0 + bonus_add)))
			result["poise"] = float(cfg["poise"]) * ratio * (1.0 + poise_add)
			result["charge_ratio"] = ratio
		"hundun":
			var marks := int(stacks.get("chaos_marks", 0))
			if marks > 0:
				result["damage"] = int(cfg["damage_plain"]) + int(cfg["damage_per_mark"]) * marks
				result["mark_consumed"] = "chaos"
			else:
				result["damage"] = int(cfg["damage_plain"])
			result["radius"] = float(cfg["radius"])
			result["qi_on_ignite"] = int(cfg["qi_on_ignite"]) if marks > 0 else 0
	return result

static func resolve_skill(form: String, sharp: bool, context: Dictionary) -> Dictionary:
	var cfg: Dictionary = Config.form_data(form).get("skill", {})
	var result := {
		"kind": "skill",
		"cost": int(cfg.get("cost", 0)),
		"duration": float(cfg.get("duration", 0.5)),
		"sharp_consumed": false,
	}
	match form:
		"taotie":
			result["reach"] = float(cfg["reach"])
			result["height"] = float(cfg["height"])
			result["absorb_window"] = float(cfg["absorb_window"])
			result["melee_reduction"] = float(cfg["melee_reduction"])
			result["qi_per_bullet"] = int(cfg["qi_per_bullet"])
		"qiongqi":
			var vulnerable := bool(context.get("target_vulnerable", false))
			var in_range := bool(context.get("target_in_range", false))
			var damage := float(cfg["damage_weak"])
			var stun := 0.0
			if vulnerable:
				damage = float(cfg["damage"])
				stun = float(cfg["stun"])
			if sharp and vulnerable:
				damage *= float(cfg["precise_mult"])
				result["sharp_consumed"] = true
			result["damage"] = int(round(damage))
			result["lunge"] = float(cfg["lunge"]) if (vulnerable and in_range) else 0.0
			result["stun"] = stun
			result["vulnerable"] = vulnerable
			result["poise"] = float(cfg["poise"]) if vulnerable else 0.0
		"taowu":
			result["ready_window"] = float(cfg["ready_window"])
			result["poise_bonus"] = float(cfg["poise_bonus"])
			result["reach_bonus"] = float(cfg["reach_bonus"])
			result["poise_bonus_duration"] = float(cfg["poise_bonus_duration"])
			result["absorb_hits"] = int(cfg["absorb_hits"])
		"hundun":
			result["delay"] = float(cfg["delay"])
			result["width"] = float(cfg["width"])
			result["height"] = float(cfg["height"])
			result["offset"] = float(cfg["offset"])
			result["damage"] = int(cfg["damage"])
			result["poise"] = float(cfg["poise"])
			result["marks"] = int(cfg["marks"])
	return result

## 抗性减益后实际伤害。`resistance` 为 0.0–1.0 的减伤比例。
static func apply_resistance(damage: int, resistance: float) -> int:
	var reduced := float(damage) * (1.0 - clampf(resistance, 0.0, 0.95))
	return maxi(1, int(round(reduced)))
