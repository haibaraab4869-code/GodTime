extends RefCounted

## 四象能力状态：凤凰（移动链）、麒麟（生命与回血）、神龙（探索，无战斗判定）、时间（时代切换）。
##
## 纯逻辑。神龙相关的方法**一律不产生伤害判定**，这是立项案"三、3.2"的红线，
## 因此本文件不提供任何 enemy 相关的龙接口。
## 依据 docs/design/feature-divine-abilities.md。

const Config := preload("res://game/combat_config.gd")

# --- 解锁标记（对应地图总控的能力门最早取得点） -----------------------------
var has_double_jump := false      # P2 = M09
var has_air_dash := false         # PA = M16
var has_wall_jump := false        # PW = M22
var has_glide := false            # 立项案 3.1 有滑翔；地图取得点待补（见文档待确认 #2）
var qilin_level := 0              # QS = M10
var has_dragon_scales := false    # DS = M28
var has_dragon_tail := false      # DT = M34
var has_dragon_breath := false    # DB = M40

# --- 凤凰运行时状态 ---------------------------------------------------------
var double_jump_available := false
var _since_ground_or_wall := 0.0
var air_dash_available := true

# --- 麒麟运行时状态 ---------------------------------------------------------
var heal_charges_used := 0
var healing_remaining := 0.0
## 回血是否处于"进行中"。与 `healing_remaining` 分开，避免计时归零后
## 无法判断本次回血是否应结算（结算必须消耗次数，打断则不能）。
var _healing_active := false
var qilin_bonus_health := 0

# --- 神龙运行时状态 ---------------------------------------------------------
var tail_cooldown_remaining := 0.0
var breath_cooldown_remaining := 0.0
var ice_platforms: Array = []

func tick(delta: float) -> void:
	_since_ground_or_wall += delta
	tail_cooldown_remaining = maxf(0.0, tail_cooldown_remaining - delta)
	breath_cooldown_remaining = maxf(0.0, breath_cooldown_remaining - delta)

func on_grounded() -> void:
	double_jump_available = has_double_jump
	air_dash_available = has_air_dash
	_since_ground_or_wall = 0.0

func on_wall_contacted() -> void:
	double_jump_available = false
	air_dash_available = has_air_dash
	_since_ground_or_wall = 0.0

## 二段跳：返回是否成功发动。需已解锁且空中且已过最小间隔。
func try_double_jump() -> bool:
	if not has_double_jump or not double_jump_available:
		return false
	if _since_ground_or_wall < float(Config.PHOENIX["double_jump_min_gap"]):
		return false
	double_jump_available = false
	return true

## 空中冲刺：与地面冲刺共用 1 层充能（`charge_ready` 由外部传入）。
func can_air_dash(charge_ready: bool) -> bool:
	return has_air_dash and air_dash_available and charge_ready

func consume_air_dash() -> void:
	air_dash_available = false

func glide_fall_speed(in_updraft: bool) -> float:
	var base := float(Config.PHOENIX["glide_fall_speed"])
	if in_updraft:
		return -float(Config.PHOENIX["glide_updraft"])
	return base

func glide_horizontal(current_speed: float) -> float:
	var cfg: Dictionary = Config.PHOENIX
	var limit := float(cfg["glide_horizontal_max"])
	var scaled := current_speed * float(cfg["glide_horizontal_mult"])
	return clampf(scaled, -limit, limit)

# --- 麒麟 -------------------------------------------------------------------

func max_health_bonus() -> int:
	return qilin_bonus_health

func heal_charges_max() -> int:
	return int(Config.qilin_row(qilin_level)["heal_charges"])

func heal_charges_left() -> int:
	return maxi(0, heal_charges_max() - heal_charges_used)

func is_healing() -> bool:
	return _healing_active

func heal_duration() -> float:
	return float(Config.qilin_row(qilin_level)["heal_duration"])

## 获得/提升麒麟等级。按比例把当前生命抬到新上限（不做"只加上限不给血"）。
func set_qilin_level(level: int, current_health: int, previous_max: int) -> Dictionary:
	var clamped := clampi(level, 0, Config.QILIN_LEVELS.size() - 1)
	var old_max := previous_max
	qilin_level = clamped
	var new_max := int(Config.qilin_row(clamped)["health"])
	qilin_bonus_health = new_max - int(Config.BASE["maximum_health"])
	var new_health := current_health
	if old_max > 0 and new_max != old_max:
		new_health = int(round(float(current_health) / float(old_max) * float(new_max)))
		new_health = clampi(new_health, 1, new_max)
	heal_charges_used = 0
	return {"health": new_health, "maximum": new_max}

func can_heal(current_health: int, maximum: int) -> bool:
	if heal_charges_left() <= 0:
		return false
	return current_health < maximum

## 开始回血。返回是否成功；成功时外部应播放 `cast_qilin` 并启动计时。
func begin_heal() -> bool:
	if heal_charges_left() <= 0 or _healing_active:
		return false
	_healing_active = true
	healing_remaining = heal_duration()
	return true

## 完成回血：消耗一次机会（在动画结束/结算点才消耗）。
## 返回是否真的结算了（重复调用不会二次消耗）。
func finish_heal() -> bool:
	if not _healing_active:
		return false
	_healing_active = false
	healing_remaining = 0.0
	heal_charges_used += 1
	return true

## 被打断：不消耗次数（见文档 §3.4）。
func interrupt_heal() -> void:
	_healing_active = false
	healing_remaining = 0.0

func refill_heal_charges() -> void:
	heal_charges_used = 0

# --- 神龙（探索专用，无战斗判定） -------------------------------------------

## 环境高温/熔岩伤害减免。战斗伤害减免恒为 0（见文档 §4.3）。
func environmental_damage_scale() -> float:
	if has_dragon_scales:
		return 1.0 - float(Config.DRAGON["scales_env_reduction"])
	return 1.0

func combat_damage_scale() -> float:
	return 1.0 - float(Config.DRAGON["scales_combat_reduction"])

func can_use_tail() -> bool:
	return has_dragon_tail and tail_cooldown_remaining <= 0.0

func use_tail() -> void:
	tail_cooldown_remaining = float(Config.DRAGON["tail_cooldown"])

func can_use_breath() -> bool:
	return has_dragon_breath and breath_cooldown_remaining <= 0.0

func use_breath() -> void:
	breath_cooldown_remaining = float(Config.DRAGON["breath_cooldown"])

## 记录一块冰面。超过上限时最旧的先消失（见文档 §4.3 与验收项）。
func add_ice_platform(id: int) -> Array:
	ice_platforms.append(id)
	var limit := int(Config.DRAGON["ice_max_platforms"])
	var removed := []
	while ice_platforms.size() > limit:
		removed.append(ice_platforms.pop_front())
	return removed

## 时代切换时冰面只存在于当前时代：全部清除（重新冻结需重新施放）。
func clear_ice_on_era_change() -> void:
	ice_platforms.clear()
