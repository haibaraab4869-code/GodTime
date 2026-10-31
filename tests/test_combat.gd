extends SceneTree

## 四凶流派回归：连段/重击/技能的伤害、削韧、凶气、标记、切换代价、逆劲、精闪、余波。
## 断言对象是 docs/design/feature-four-beasts.md 的规则，数值来自 game/combat_config.gd。

const Config := preload("res://game/combat_config.gd")
const CombatState := preload("res://game/combat_state.gd")
const CombatRules := preload("res://game/combat_rules.gd")
const Stagger := preload("res://game/stagger.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _fail(message: String) -> void:
	print("FAIL: ", message)
	failures += 1

func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _run() -> void:
	_test_dps_band()
	_test_combo_damage_and_qi()
	_test_taotie_marks_and_bite()
	_test_qiongqi_precise_dodge()
	_test_taowu_reverse()
	_test_hundun_marks_and_aftershock()
	_test_switch_costs()
	_test_poise_break()
	_test_qi_cycle_efficiency()
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)

# --- 1. 四套连段 DPS 必须落在同一强度带内 --------------------------------
func _test_dps_band() -> void:
	var dps := {}
	for form in Config.FORM_ORDER:
		var total_damage := 0
		var total_time := 0.0
		var chain: Array = Config.form_data(form)["combo"]
		for segment in chain:
			total_damage += int(segment["damage"])
			total_time += float(segment["duration"])
		dps[form] = float(total_damage) / total_time
		print("dps_%s=%.2f (dmg=%d time=%.3f)" % [form, dps[form], total_damage, total_time])
		_check(dps[form] >= 14.8 and dps[form] <= 21.2,
			"%s combo DPS %.2f outside the 18±18%% band" % [form, dps[form]])
	var values: Array = dps.values()
	var lowest: float = values.min()
	var highest: float = values.max()
	print("dps_spread=%.2f..%.2f" % [lowest, highest])
	# 带宽约束：最高与最低之差不得超过 40%（文档 §3.1）
	_check(highest / lowest <= 1.40, "DPS spread too wide: %.2f vs %.2f" % [highest, lowest])

# --- 2. 连段伤害与凶气逐段正确 ------------------------------------------
func _test_combo_damage_and_qi() -> void:
	# 饕餮末段必须挂饥印。
	var last := Config.combo_segment("taotie", Config.combo_length("taotie") - 1)
	_check(String(last.get("applies_mark", "")) == "hunger", "taotie final segment must apply hunger")
	var chaos_last := Config.combo_segment("hundun", Config.combo_length("hundun") - 1)
	_check(String(chaos_last.get("applies_mark", "")) == "chaos", "hundun final segment must apply chaos")
	# 穷奇与梼杌无末段标记（收益来自精闪与削韧）。
	for form in ["qiongqi", "taowu"]:
		for segment in Config.form_data(form)["combo"]:
			_check(String(segment.get("applies_mark", "")) == "",
				"%s should not apply marks" % form)

	var state = CombatState.new()
	var before: int = state.qi
	state.add_qi(int(Config.combo_segment("taotie", 0)["qi"]))
	_check(state.qi == before + 8, "combo qi gain should be 8, got %d" % state.qi)
	_check(state.spend_qi(30) == false, "spending 30 with 8 qi must fail")
	_check(state.qi == 8, "failed spend must not change qi")

# --- 3. 饕餮：饥印撕咬、同目标冷却、Boss 回血上限 -------------------------
func _test_taotie_marks_and_bite() -> void:
	var state = CombatState.new()
	state.set_form("taotie")
	_check(state.can_bite_heal(1, false), "first bite should be allowed")
	state.register_bite(1, true, false)
	_check(not state.can_bite_heal(1, false), "same target bite must respect 6s cooldown")
	_check(state.can_bite_heal(2, false), "a different target should still be bitable")

	var boss = CombatState.new()
	boss.set_form("taotie")
	var healed := 0
	for i in 5:
		if boss.can_bite_heal(100 + i, true):
			boss.register_bite(100 + i, true, true)
			healed += 1
	print("boss_heal_used=", boss.boss_heal_used, " healed=", healed)
	_check(boss.boss_heal_used == int(Config.FORMS["taotie"]["heavy"]["boss_heal_cap"]),
		"boss heal must cap at %d per fight" % Config.FORMS["taotie"]["heavy"]["boss_heal_cap"])
	_check(boss.boss_heal_exhausted(), "boss heal should report exhausted at cap")

	# 有印/无印的撕咬伤害差异。
	var marked := CombatRules.resolve_heavy("taotie", {"hunger": true}, false)
	var plain := CombatRules.resolve_heavy("taotie", {"hunger": false}, false)
	print("bite_marked=", marked["damage"], " bite_plain=", plain["damage"], " heal=", marked.get("heal", 0))
	_check(int(marked["damage"]) == 22, "marked bite should deal 22")
	_check(int(plain["damage"]) == 11, "unmarked bite should deal 11")
	_check(int(marked.get("heal", 0)) == 1, "marked bite should heal 1")
	_check(int(plain.get("heal", 0)) == 0, "unmarked bite must not heal")

# --- 4. 穷奇：精准闪避强化与同目标节流 -----------------------------------
func _test_qiongqi_precise_dodge() -> void:
	var state = CombatState.new()
	state.set_form("qiongqi")
	_check(state.is_sharp() == false, "sharp must start inactive")
	_check(state.register_precise_dodge(7, 0.4), "first precise dodge should register")
	_check(state.is_sharp(), "sharp should be active after a precise dodge")
	var qi_after: int = state.qi
	_check(qi_after == 15, "precise dodge should grant 15 qi, got %d" % qi_after)
	_check(not state.register_precise_dodge(7, 0.4), "same target must be throttled for 3s")
	_check(state.qi == qi_after, "throttled dodge must not grant more qi")

	var normal := CombatRules.resolve_heavy("qiongqi", {}, false)
	var boosted := CombatRules.resolve_heavy("qiongqi", {}, true)
	print("qiongqi_heavy normal=", normal["damage"], " sharp=", boosted["damage"])
	_check(int(normal["damage"]) == 20, "base heavy should be 20")
	_check(int(boosted["damage"]) == 36, "sharp heavy should be 36 (x1.8)")
	_check(bool(boosted["sharp_consumed"]), "sharp should be consumed by the boosted heavy")

	# 追击：目标在收招 → 26 伤害 + 硬直；不在 → 弱斩 8 且不位移。
	var vulnerable := CombatRules.resolve_skill("qiongqi", false, {"target_vulnerable": true, "target_in_range": true})
	var safe := CombatRules.resolve_skill("qiongqi", false, {"target_vulnerable": false, "target_in_range": true})
	print("qiongqi_skill vulnerable=", vulnerable["damage"], " stun=", vulnerable["stun"], " lunge=", vulnerable["lunge"])
	_check(int(vulnerable["damage"]) == 26, "chase should deal 26")
	_check(is_equal_approx(float(vulnerable["stun"]), 0.35), "chase should stun 0.35s")
	_check(is_equal_approx(float(vulnerable["lunge"]), 48.0), "chase should lunge 48")
	_check(int(safe["damage"]) == 8, "non-vulnerable skill should deal 8")
	_check(is_equal_approx(float(safe["lunge"]), 0.0), "non-vulnerable skill must not lunge")

# --- 5. 梼杌：逆劲层数与加成上限 -----------------------------------------
func _test_taowu_reverse() -> void:
	var state = CombatState.new()
	state.set_form("taowu")
	for i in 10:
		state.register_damage_taken()
	print("reverse_stacks=", state.reverse_stacks)
	var max_stacks := int(Config.FORMS["taowu"]["passive"]["max_stacks"])
	_check(state.reverse_stacks == max_stacks, "reverse stacks should cap at %d" % max_stacks)
	print("reverse_poise_bonus=%.2f damage_bonus=%.2f" % [state.reverse_poise_bonus(), state.reverse_damage_bonus()])
	_check(is_equal_approx(state.reverse_poise_bonus(), 0.40), "5 stacks should give +40% poise")
	_check(is_equal_approx(state.reverse_damage_bonus(), 0.20), "5 stacks should give +20% damage")

	var stacked := CombatRules.resolve_heavy("taowu",
		{"charge_ratio": 1.0, "reverse_poise_bonus": 0.40, "reverse_damage_bonus": 0.20}, false)
	print("taowu_heavy stacked dmg=", stacked["damage"], " poise=", stacked["poise"])
	_check(int(stacked["damage"]) == 36, "30 * 1.2 should be 36")
	_check(is_equal_approx(float(stacked["poise"]), 56.0), "40 * 1.4 should be 56")

	# 未蓄满时按比例衰减，但不低于 min_ratio。
	var half := CombatRules.resolve_heavy("taowu", {"charge_ratio": 0.55}, false)
	print("taowu_half_charge dmg=", half["damage"])
	_check(int(half["damage"]) == 17, "55%% charge of 30 should be ~17, got %d" % int(half["damage"]))
	_check(int(state.consume_reverse()) == max_stacks, "consume_reverse should return used stacks")
	_check(state.reverse_stacks == 0, "reverse should be cleared after a heavy")

# --- 6. 混沌：乱痕引爆与余波封顶 -----------------------------------------
func _test_hundun_marks_and_aftershock() -> void:
	var none := CombatRules.resolve_heavy("hundun", {"chaos_marks": 0}, false)
	var three := CombatRules.resolve_heavy("hundun", {"chaos_marks": 3}, false)
	print("hundun_heavy none=", none["damage"], " three_marks=", three["damage"])
	_check(int(none["damage"]) == 18, "markless heavy should still deal 18")
	_check(int(three["damage"]) == 84, "3 marks should deal 84")
	_check(String(three["mark_consumed"]) == "chaos", "explosion must consume the marks")
	_check(String(none["mark_consumed"]) == "", "markless heavy consumes nothing")

	var normal = Stagger.new(int(Config.POISE["normal_enemy"]), false)
	var ratio := 0.0
	for i in 10:
		ratio = normal.register_hit()
	print("aftershock_normal=%.3f stacks=%d" % [ratio, normal.aftershock_stacks])
	_check(is_equal_approx(ratio, 0.15), "normal aftershock should cap at 15%")

	var boss = Stagger.new(int(Config.POISE["boss"]), true)
	ratio = 0.0
	for i in 10:
		ratio = boss.register_hit()
	print("aftershock_boss=%.4f stacks=%d" % [ratio, boss.aftershock_stacks])
	_check(is_equal_approx(ratio, 0.075), "boss aftershock should cap at 7.5%")

	# 抗性减益应用到伤害。
	var reduced := CombatRules.apply_resistance(100, 0.075)
	print("resisted_damage=", reduced)
	_check(reduced == 93, "100 damage at 7.5%% resistance should be 93")

# --- 7. 换相代价 ---------------------------------------------------------
func _test_switch_costs() -> void:
	var state = CombatState.new()
	state.set_form("taotie")
	state.add_qi(80)
	state.reverse_stacks = 3
	state.sharp_remaining = 0.4
	print("before_shift qi=", state.qi, " reverse=", state.reverse_stacks)
	state.apply_field_shift("qiongqi")
	_check(state.form == "qiongqi", "form should change")
	_check(state.qi == 0, "shift must clear qi")
	_check(state.reverse_stacks == 0, "shift must clear reverse stacks")
	_check(is_equal_approx(state.sharp_remaining, 0.0), "shift must clear sharp")
	_check(is_equal_approx(state.shift_cooldown_remaining, 12.0), "shift cooldown should be 12s")
	_check(is_equal_approx(state.qi_gain_penalty_remaining, 3.0), "qi penalty should last 3s")

	# 3s 内凶气获取减半。
	state.add_qi(20)
	print("qi_after_penalty_gain=", state.qi)
	_check(state.qi == 10, "qi gain during penalty should be halved, got %d" % state.qi)
	state.tick(3.1)
	state.add_qi(20)
	_check(state.qi == 30, "qi gain should be full after the penalty, got %d" % state.qi)

	# 战斗内换相默认关闭（守立项案"在存档点切换"）。
	var gated = CombatState.new()
	_check(not gated.can_shift_in_field(), "field shift must be disabled by default")

# --- 8. 削韧与破甲 -------------------------------------------------------
func _test_poise_break() -> void:
	var normal = Stagger.new(int(Config.POISE["normal_enemy"]), false)
	# 40 削韧触发破甲：无视 30% poise。
	var broke: bool = normal.apply_poise_damage(40.0)
	print("break_triggered=", broke, " poise=", normal.poise)
	_check(broke, "a 40-poise hit should break a 30-poise target")
	_check(normal.is_staggered(), "target should be staggered after break")

	# 非破甲攻击不应击破满 poise 的精英。
	var elite = Stagger.new(int(Config.POISE["elite"]), false)
	var not_broken: bool = elite.apply_poise_damage(14.0)
	_check(not not_broken, "14 poise should not break a 90-poise elite")
	_check(elite.poise == 76.0, "elite poise should drop exactly by 14, got %.1f" % elite.poise)

# --- 9. 凶气循环效率 -----------------------------------------------------
## 指标定义与文档 §3.3 一致：**打满一次技能需要几次完整连段** = 技能消耗 / 一次连段总凶气。
func _test_qi_cycle_efficiency() -> void:
	for form in Config.FORM_ORDER:
		var chain: Array = Config.form_data(form)["combo"]
		var total_qi := 0
		for segment in chain:
			total_qi += int(segment["qi"])
		var cost := int(Config.form_data(form)["skill"]["cost"])
		var combos_per_skill := float(cost) / float(total_qi)
		print("qi_cycle_%s combo_qi=%d cost=%d combos_per_skill=%.2f" % [form, total_qi, cost, combos_per_skill])
		_check(combos_per_skill >= 0.85 and combos_per_skill <= 1.35,
			"%s needs %.2f combos per skill, outside 0.85-1.35" % [form, combos_per_skill])
