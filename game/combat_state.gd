extends RefCounted

## 四凶战斗状态：凶气、流派资源、换相冷却与代价。
##
## 纯逻辑，不依赖场景树，便于 `--headless --script` 断言。
## 数值全部来自 `combat_config.gd`，本文件不写死数字。

const Config := preload("res://game/combat_config.gd")

signal form_changed(from_form: String, to_form: String)
signal qi_changed(current: int, maximum: int)

var form: String = "taotie"
var qi: int = 0

## 换相冷却与"凶气获取减半"惩罚计时（仅提案 B 的战斗内换相使用）。
var shift_cooldown_remaining: float = 0.0
var qi_gain_penalty_remaining: float = 0.0

## 梼杌被动"逆劲"：层数与上次承伤计时。
var reverse_stacks: int = 0
var _since_last_hit_taken: float = 0.0

## 穷奇精闪"锐"：窗口剩余。>0 时强化下一次重击或技能。
var sharp_remaining: float = 0.0
var _sharp_target_cooldowns: Dictionary = {}

## 饕餮：对同一目标的撕咬回血冷却。
var _bite_cooldowns: Dictionary = {}
## 饕餮：本场 Boss 战已回复的生命点数。
var boss_heal_used: int = 0

func set_form(new_form: String) -> void:
	if new_form == form or not Config.FORMS.has(new_form):
		return
	var old := form
	form = new_form
	qi = 0
	reverse_stacks = 0
	sharp_remaining = 0.0
	_clear_form_temp_state()
	qi_changed.emit(qi, Config.BASE["qi_max"])
	form_changed.emit(old, new_form)

## 换相时清空一切"临时增益"（立项案"切换清空凶气及临时增益"）。
func _clear_form_temp_state() -> void:
	_bite_cooldowns.clear()
	boss_heal_used = 0
	qi_gain_penalty_remaining = 0.0
	_sharp_target_cooldowns.clear()

func tick(delta: float) -> void:
	shift_cooldown_remaining = maxf(0.0, shift_cooldown_remaining - delta)
	qi_gain_penalty_remaining = maxf(0.0, qi_gain_penalty_remaining - delta)
	if sharp_remaining > 0.0:
		sharp_remaining = maxf(0.0, sharp_remaining - delta)
	for key in _sharp_target_cooldowns.keys():
		_sharp_target_cooldowns[key] = maxf(0.0, float(_sharp_target_cooldowns[key]) - delta)
	for key in _bite_cooldowns.keys():
		_bite_cooldowns[key] = maxf(0.0, float(_bite_cooldowns[key]) - delta)

	# 梼杌逆劲：10s 未承伤后每 2s 掉 1 层。
	if form == "taowu" and reverse_stacks > 0:
		_since_last_hit_taken += delta
		var decay_start := float(Config.FORMS["taowu"]["passive"]["decay_after"])
		var step := float(Config.FORMS["taowu"]["passive"]["decay_step"])
		while reverse_stacks > 0 and _since_last_hit_taken >= decay_start + step:
			_since_last_hit_taken -= step
			reverse_stacks -= 1

func add_qi(amount: int) -> void:
	if amount <= 0:
		return
	var scaled := float(amount)
	if qi_gain_penalty_remaining > 0.0:
		scaled *= (1.0 - float(Config.SHIFT["qi_gain_penalty"]))
	qi = clampi(qi + int(round(scaled)), 0, int(Config.BASE["qi_max"]))
	qi_changed.emit(qi, Config.BASE["qi_max"])

func spend_qi(cost: int) -> bool:
	if cost <= 0:
		return true
	if qi < cost:
		return false
	qi -= cost
	qi_changed.emit(qi, Config.BASE["qi_max"])
	return true

func has_qi(cost: int) -> bool:
	return qi >= cost

# --- 换相 -------------------------------------------------------------------

## 是否允许此刻发起战斗内换相。存档点换相走 `force_form`，不经过此检查。
func can_shift_in_field() -> bool:
	if not Config.field_shift_enabled():
		return false
	return shift_cooldown_remaining <= 0.0

## 完成一次战斗内换相，施加全部代价。
func apply_field_shift(new_form: String) -> void:
	var from_form := form
	form = new_form
	qi = 0
	reverse_stacks = 0
	sharp_remaining = 0.0
	_bite_cooldowns.clear()
	boss_heal_used = 0
	_clear_form_temp_state()
	shift_cooldown_remaining = float(Config.SHIFT["cooldown"])
	qi_gain_penalty_remaining = float(Config.SHIFT["qi_gain_penalty_duration"])
	qi_changed.emit(qi, Config.BASE["qi_max"])
	form_changed.emit(from_form, new_form)

# --- 穷奇精闪 ---------------------------------------------------------------

## 记录一次精准闪避。同一目标 3s 内只给一次收益（防贴脸反复刷）。
func register_precise_dodge(target_id: int, window: float) -> bool:
	if form != "qiongqi":
		return false
	if float(_sharp_target_cooldowns.get(target_id, 0.0)) > 0.0:
		return false
	sharp_remaining = window
	_sharp_target_cooldowns[target_id] = 3.0
	add_qi(15)
	return true

func is_sharp() -> bool:
	return sharp_remaining > 0.0

func consume_sharp() -> bool:
	if sharp_remaining <= 0.0:
		return false
	sharp_remaining = 0.0
	return true

# --- 梼杌逆劲 ---------------------------------------------------------------

func register_damage_taken() -> void:
	if form != "taowu":
		return
	_since_last_hit_taken = 0.0
	var max_stacks := int(Config.FORMS["taowu"]["passive"]["max_stacks"])
	reverse_stacks = mini(reverse_stacks + 1, max_stacks)

func reverse_poise_bonus() -> float:
	if form != "taowu":
		return 0.0
	return reverse_stacks * float(Config.FORMS["taowu"]["passive"]["poise_per_stack"])

func reverse_damage_bonus() -> float:
	if form != "taowu":
		return 0.0
	return reverse_stacks * float(Config.FORMS["taowu"]["passive"]["damage_per_stack"])

func consume_reverse() -> int:
	var used := reverse_stacks
	reverse_stacks = 0
	_since_last_hit_taken = 0.0
	return used

# --- 饕餮撕咬 ---------------------------------------------------------------

## 撕咬对同一目标是否可回血。`is_boss` 时检查每场回血上限。
func can_bite_heal(target_id: int, is_boss: bool) -> bool:
	var cfg: Dictionary = Config.FORMS["taotie"]["heavy"]
	if float(_bite_cooldowns.get(target_id, 0.0)) > 0.0:
		return false
	if is_boss and boss_heal_used >= int(cfg["boss_heal_cap"]):
		return false
	return true

func register_bite(target_id: int, healed: bool, is_boss: bool) -> void:
	var cfg: Dictionary = Config.FORMS["taotie"]["heavy"]
	_bite_cooldowns[target_id] = float(cfg["same_target_cooldown"])
	if is_boss:
		boss_heal_used += 1 if healed else 0

func boss_heal_exhausted() -> bool:
	return boss_heal_used >= int(Config.FORMS["taotie"]["heavy"]["boss_heal_cap"])
