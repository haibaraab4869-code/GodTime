extends RefCounted

## 四凶流派与四象能力的数值表 —— **唯一数据源**。
##
## 依据 `docs/design/feature-four-beasts.md` 与
## `docs/design/feature-divine-abilities.md`（均已按裁定更新为已批准）。
## 其他脚本只读本表，不复制常量；改数值只改这里。
##
## 伤害刻度：普通敌人 120 / 精英 480 / Boss 6000，普攻基准 10。

# --- 主角尺寸与基础运动 -----------------------------------------------------
## 碰撞盒四形态统一，理由见 docs/art/character-time-god.md §2.4。
const BODY_SIZE := Vector2(34.0, 92.0)
const BODY_HALF := Vector2(17.0, 46.0)

const BASE := {
	"move_speed": 300.0,
	"jump_speed": 660.0,
	"gravity_strength": 1100.0,
	"maximum_health": 4,
	"dash_speed": 540.0,
	"dash_duration": 0.16,
	"dash_charge_cooldown": 0.45,
	"jump_buffer_window": 0.14,
	"attack_buffer_window": 0.18,
	"dash_buffer_window": 0.12,
	"heavy_buffer_window": 0.16,
	"skill_buffer_window": 0.16,
	"shift_buffer_window": 0.10,
	"coyote_time": 0.10,
	"jump_cut_multiplier": 0.45,
	"combo_grace": 0.30,
	"hurt_light_duration": 0.25,
	"hurt_heavy_duration": 0.50,
	"qi_max": 100,
	"precise_dodge_window": 0.18,
}

# --- 四凶流派 ---------------------------------------------------------------
## combo: 普攻连段。heavy: 重击。skill: 技能。字段含义见文档对应表格。
const FORMS := {
	"taotie": {
		"display": "饕餮",
		"speed_mult": 1.00,
		"poise_max": 60,
		"hurt_stagger_mult": 1.0,
		"max_health_bonus": 0,
		"combo": [
			{"damage": 9, "reach": 30.0, "height": 36.0, "poise": 4, "qi": 8, "duration": 0.417},
			{"damage": 9, "reach": 30.0, "height": 36.0, "poise": 4, "qi": 8, "duration": 0.500},
			{"damage": 14, "reach": 34.0, "height": 44.0, "poise": 7, "qi": 12, "duration": 0.667, "applies_mark": "hunger"},
		],
		"heavy": {
			"duration": 0.833, "reach": 38.0, "height": 40.0, "poise": 10, "qi": 12,
			"damage_marked": 22, "damage_plain": 11, "heal": 1,
			"same_target_cooldown": 6.0, "boss_heal_cap": 2,
		},
		"skill": {
			"cost": 30, "duration": 0.833, "absorb_window": 0.35,
			"reach": 56.0, "height": 56.0,
			"melee_reduction": 0.60, "qi_per_bullet": 8,
		},
	},
	"qiongqi": {
		"display": "穷奇",
		"speed_mult": 1.08,
		"poise_max": 45,
		"hurt_stagger_mult": 1.15,
		"max_health_bonus": 0,
		"combo": [
			{"damage": 6, "reach": 38.0, "height": 44.0, "poise": 2, "qi": 7, "duration": 0.333},
			{"damage": 6, "reach": 38.0, "height": 44.0, "poise": 2, "qi": 7, "duration": 0.333},
			{"damage": 7, "reach": 38.0, "height": 44.0, "poise": 3, "qi": 7, "duration": 0.417},
			{"damage": 10, "reach": 44.0, "height": 48.0, "poise": 5, "qi": 10, "duration": 0.500},
		],
		"heavy": {
			"duration": 0.750, "reach": 52.0, "height": 34.0, "poise": 6, "qi": 12,
			"damage": 20, "lunge": 22.0, "lunge_stop": 0.15, "precise_mult": 1.8,
		},
		"skill": {
			"cost": 28, "duration": 0.667, "damage": 26, "damage_weak": 8,
			"lunge": 48.0, "max_range": 96.0, "stun": 0.35, "poise": 8,
			"precise_mult": 1.6,
		},
	},
	"taowu": {
		"display": "梼杌",
		"speed_mult": 0.92,
		"poise_max": 110,
		"hurt_stagger_mult": 0.7,
		"max_health_bonus": 0,
		"combo": [
			{"damage": 10, "reach": 44.0, "height": 52.0, "poise": 8, "qi": 8, "duration": 0.500},
			{"damage": 11, "reach": 44.0, "height": 52.0, "poise": 8, "qi": 8, "duration": 0.583},
			{"damage": 14, "reach": 48.0, "height": 58.0, "poise": 14, "qi": 8, "duration": 0.750},
		],
		"heavy": {
			"duration": 1.333, "charge": 0.60, "reach": 56.0, "height": 64.0,
			"poise": 40, "qi": 14, "damage": 30, "min_ratio": 0.55,
		},
		"skill": {
			"cost": 25, "duration": 0.833, "ready_window": 0.60,
			"poise_bonus": 0.30, "reach_bonus": 8.0, "poise_bonus_duration": 2.0,
			"absorb_hits": 1,
		},
		"passive": {"name": "逆劲", "max_stacks": 5, "poise_per_stack": 0.08, "damage_per_stack": 0.04, "decay_after": 10.0, "decay_step": 2.0},
	},
	"hundun": {
		"display": "混沌",
		"speed_mult": 0.96,
		"poise_max": 70,
		"hurt_stagger_mult": 0.95,
		"max_health_bonus": 0,
		"combo": [
			{"damage": 8, "reach": 56.0, "height": 40.0, "poise": 5, "qi": 7, "duration": 0.500},
			{"damage": 8, "reach": 56.0, "height": 40.0, "poise": 5, "qi": 7, "duration": 0.583},
			{"damage": 13, "reach": 56.0, "height": 44.0, "poise": 8, "qi": 11, "duration": 0.833, "applies_mark": "chaos"},
		],
		"heavy": {
			"duration": 1.000, "damage_plain": 18, "damage_per_mark": 22,
			"radius": 72.0, "poise": 10, "qi": 12, "qi_on_ignite": 15,
		},
		"skill": {
			"cost": 32, "duration": 1.000, "delay": 0.8,
			"width": 120.0, "height": 80.0, "offset": 40.0,
			"damage": 26, "poise": 12, "marks": 1,
		},
		"passive": {"name": "余波", "normal_per_stack": 0.03, "boss_per_stack": 0.015, "max_stacks": 5, "reset_after": 3.0},
	},
}

const FORM_ORDER := ["taotie", "qiongqi", "taowu", "hundun"]

## 换相（见 docs/design/player-state-machine.md §5）。
## 默认遵循立项案"在存档点切换"（提案 A）；`field_enabled` 为提案 B 的可选开关。
const SHIFT := {
	"hold_time": 0.40,
	"out_duration": 0.667,
	"blank_duration": 0.15,
	"in_duration": 0.667,
	"cooldown": 12.0,
	"qi_gain_penalty": 0.5,
	"qi_gain_penalty_duration": 3.0,
	"blank_invuln_normal_only": true,
}

## 战斗内换相开关。默认关闭 = 严格守立项案"在存档点切换"。
## 打开即启用提案 B（代价：1.48s 无防御 + 凶气清零 + 12s 冷却 + 3s 凶气减半）。
static var _field_shift_enabled := false

static func field_shift_enabled() -> bool:
	return _field_shift_enabled

## 仅供设置项与测试调用。正式 UI 暴露前需用户在文档中确认已采纳提案 B。
static func set_field_shift_enabled(value: bool) -> void:
	_field_shift_enabled = value

# --- 四象能力 ---------------------------------------------------------------
const PHOENIX := {
	"double_jump_speed": 486.0,
	"double_jump_min_gap": 0.08,
	"air_dash_speed": 540.0,
	"air_dash_duration": 0.16,
	"wall_slide_speed": 90.0,
	"wall_jump_horizontal": 260.0,
	"wall_jump_vertical": 620.0,
	"glide_fall_speed": 45.0,
	"glide_horizontal_mult": 0.85,
	"glide_horizontal_max": 300.0,
	"glide_updraft": 220.0,
}

## 麒麟等级表：索引 0 = 未获得。row: {health, heal_charges, heal_duration}
const QILIN_LEVELS := [
	{"health": 4, "heal_charges": 0, "heal_duration": 0.0},
	{"health": 6, "heal_charges": 2, "heal_duration": 0.55},
	{"health": 7, "heal_charges": 3, "heal_duration": 0.50},
	{"health": 8, "heal_charges": 4, "heal_duration": 0.45},
	{"health": 9, "heal_charges": 5, "heal_duration": 0.40},
]

const DRAGON := {
	"scales_env_reduction": 1.0,
	"scales_combat_reduction": 0.0,
	"tail_charge": 0.60,
	"tail_cooldown": 0.80,
	"tail_width": 32.0,
	"tail_height": 48.0,
	"breath_cooldown": 1.20,
	"ice_max_platforms": 3,
	"ice_thickness": 12.0,
	"acid_dissolve": 0.40,
}

# --- 削韧 -------------------------------------------------------------------
const POISE := {
	"normal_enemy": 30,
	"elite": 90,
	"boss": 300,
	"break_threshold": 40,
	"break_ignore_ratio": 0.30,
	"stagger_normal": 1.2,
	"stagger_elite": 1.0,
	"stagger_boss": 0.9,
	"regen_per_second": 25.0,
}

# --- 工具函数 ---------------------------------------------------------------

static func form_data(form: String) -> Dictionary:
	return FORMS.get(form, FORMS["taotie"])

static func combo_length(form: String) -> int:
	return (form_data(form).get("combo", []) as Array).size()

static func combo_segment(form: String, index: int) -> Dictionary:
	var chain: Array = form_data(form).get("combo", [])
	if chain.is_empty():
		return {}
	return chain[clampi(index, 0, chain.size() - 1)]

static func form_speed(base_speed: float, form: String) -> float:
	return base_speed * float(form_data(form).get("speed_mult", 1.0))

static func qilin_row(level: int) -> Dictionary:
	return QILIN_LEVELS[clampi(level, 0, QILIN_LEVELS.size() - 1)]
