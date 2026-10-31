extends RefCounted

## 削韧 / 失衡 / 破甲与「余波」抗性减益。
##
## 纯逻辑。每个可受击目标持有一个 `StaggerTracker`。
## 依据 docs/design/feature-four-beasts.md §3.2。

const Config := preload("res://game/combat_config.gd")

## 单次削韧达到该值视为"破甲"，无视一部分 poise。
var break_threshold: int = int(Config.POISE["break_threshold"])

var poise_max: int
var poise: float
var stagger_remaining: float = 0.0
var _regen_remaining: float = 0.0

## 混沌「余波」：对同一目标的抗性减益层数（按敌人被连续命中计）。
var aftershock_stacks: int = 0
var _since_last_hit: float = 0.0
var is_boss: bool = false

func _init(maximum: int, boss := false) -> void:
	poise_max = maximum
	poise = float(maximum)
	is_boss = boss

func tick(delta: float) -> void:
	if stagger_remaining > 0.0:
		stagger_remaining = maxf(0.0, stagger_remaining - delta)
		if stagger_remaining <= 0.0:
			# 失衡结束后 2s 内以固定速率回复。
			_regen_remaining = 2.0
		return
	if _regen_remaining > 0.0:
		_regen_remaining = maxf(0.0, _regen_remaining - delta)
		poise = minf(float(poise_max), poise + float(Config.POISE["regen_per_second"]) * delta)

	if aftershock_stacks > 0:
		_since_last_hit += delta
		if _since_last_hit >= float(Config.FORMS["hundun"]["passive"]["reset_after"]):
			aftershock_stacks = 0

func is_staggered() -> bool:
	return stagger_remaining > 0.0

## 施加削韧。返回是否触发（或刷新）失衡。
## `break_armor` 为真时（单次削韧 ≥ 40），无视一部分 poise。
func apply_poise_damage(amount: float) -> bool:
	if stagger_remaining > 0.0:
		return false
	var effective := amount
	if amount >= float(break_threshold):
		effective = amount * (1.0 + float(Config.POISE["break_ignore_ratio"]))
	poise = maxf(0.0, poise - effective)
	if poise <= 0.0:
		var cfg: Dictionary = Config.POISE
		if is_boss:
			stagger_remaining = float(cfg["stagger_boss"])
		elif poise_max >= int(cfg["elite"]):
			stagger_remaining = float(cfg["stagger_elite"])
		else:
			stagger_remaining = float(cfg["stagger_normal"])
		return true
	return false

## 混沌「余波」：记录一次命中，返回该目标的抗性减益比例（0.0–1.0）。
func register_hit() -> float:
	_since_last_hit = 0.0
	var passive: Dictionary = Config.FORMS["hundun"]["passive"]
	var max_stacks := int(passive["max_stacks"])
	if aftershock_stacks < max_stacks:
		aftershock_stacks += 1
	var per_stack := float(passive["boss_per_stack"] if is_boss else passive["normal_per_stack"])
	return aftershock_stacks * per_stack

func aftershock_ratio() -> float:
	var passive: Dictionary = Config.FORMS["hundun"]["passive"]
	var per_stack := float(passive["boss_per_stack"] if is_boss else passive["normal_per_stack"])
	return aftershock_stacks * per_stack
