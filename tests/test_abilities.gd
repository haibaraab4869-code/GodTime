extends SceneTree

## 四象能力回归：凤凰移动链、麒麟生命与回墨、神龙探索能力（含"零战斗判定"红线）。
## 断言对象是 docs/design/feature-divine-abilities.md。

const Config := preload("res://game/combat_config.gd")
const AbilityState := preload("res://game/ability_state.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		print("FAIL: ", message)
		failures += 1

func _run() -> void:
	_test_phoenix_chain()
	_test_phoenix_glide()
	_test_qilin_levels()
	_test_qilin_heal_rules()
	_test_dragon_exploration_only()
	_test_dragon_ice_limits()
	_test_ability_orthogonality()
	print("FAILURES=", failures)
	quit(1 if failures > 0 else 0)

# --- 凤凰 ---------------------------------------------------------------
func _test_phoenix_chain() -> void:
	var a = AbilityState.new()
	_check(not a.try_double_jump(), "double jump must be locked before unlocking")
	a.has_double_jump = true
	a.on_grounded()
	# 最小间隔保护：刚离地立刻二段跳应被拒绝。
	_check(not a.try_double_jump(), "double jump inside the 0.08s gap must be refused")
	a.tick(0.09)
	_check(a.try_double_jump(), "double jump should fire after the gap")
	_check(not a.try_double_jump(), "only one double jump per airtime")
	a.on_grounded()
	_check(a.double_jump_available, "landing should restore the double jump")
	print("phoenix_double_jump_ok")

	# 空中冲刺需要解锁，并且与地面冲刺共用充能。
	var b = AbilityState.new()
	b.on_grounded()
	_check(not b.can_air_dash(true), "air dash should be locked before unlocking")
	b.has_air_dash = true
	b.on_grounded()
	_check(b.can_air_dash(true), "air dash should be available with a charge")
	_check(not b.can_air_dash(false), "air dash must respect the shared charge")
	b.consume_air_dash()
	_check(not b.can_air_dash(true), "air dash is single use until landing")
	b.on_grounded()
	_check(b.can_air_dash(true), "landing restores the air dash")
	print("phoenix_air_dash_ok")

	# 蹬墙与贴墙下滑参数来自配置。
	print("wall_slide_speed=%.1f wall_jump=(%.1f, %.1f)" % [
		Config.PHOENIX["wall_slide_speed"], Config.PHOENIX["wall_jump_horizontal"], Config.PHOENIX["wall_jump_vertical"]])
	_check(float(Config.PHOENIX["wall_slide_speed"]) < 200.0, "wall slide must be slow enough to react")

func _test_phoenix_glide() -> void:
	var a = AbilityState.new()
	var fall := a.glide_fall_speed(false)
	var lift := a.glide_fall_speed(true)
	print("glide_fall=%.1f updraft_result=%.1f" % [fall, lift])
	_check(is_equal_approx(fall, 45.0), "glide fall speed should be 45")
	_check(lift < 0.0, "updraft must produce upward motion (negative y)")
	_check(is_equal_approx(absf(lift), 220.0), "updraft should be 220 px/s upward")

	# 滑翔水平速度上限，不给额外加速。
	var fast := a.glide_horizontal(1000.0)
	print("glide_horizontal_capped=%.1f" % fast)
	_check(is_equal_approx(fast, 300.0), "glide horizontal must cap at 300")
	var slow := a.glide_horizontal(200.0)
	_check(is_equal_approx(slow, 170.0), "glide should keep 85%% of horizontal speed")

	# 滑翔无时长限制：文档明确不给耐力条。
	_check(not a.has_method("tick_glide_stamina"), "glide must not have a stamina limiter")

# --- 麒麟 ---------------------------------------------------------------
func _test_qilin_levels() -> void:
	var a = AbilityState.new()
	_check(a.max_health_bonus() == 0, "no qilin means no bonus health")
	_check(a.heal_charges_max() == 0, "no qilin means no heal charges")

	var result := a.set_qilin_level(1, 4, 4)
	print("qilin_L1 health=", result["health"], "/", result["maximum"], " charges=", a.heal_charges_max())
	_check(int(result["maximum"]) == 6, "L1 max health should be 6")
	_check(int(result["health"]) == 6, "4/4 -> 6/6 must scale proportionally, not 4/6")
	_check(a.heal_charges_max() == 2, "L1 should grant 2 heal charges")

	# 强化只加回血次数（守原案"其强化继续提高回血次数"）。
	var expected := [3, 4, 5]
	for index in 3:
		var level := index + 2
		var row := Config.qilin_row(level)
		print("qilin_L%d health=%d charges=%d" % [level, int(row["health"]), int(row["heal_charges"])])
		_check(int(row["heal_charges"]) == expected[index],
			"L%d should grant %d heal charges" % [level, expected[index]])

	# 上限封顶。
	var capped := a.set_qilin_level(9, 9, 9)
	_check(int(capped["maximum"]) == 9, "qilin max health must cap at 9")

func _test_qilin_heal_rules() -> void:
	var a = AbilityState.new()
	a.set_qilin_level(1, 6, 6)
	_check(not a.can_heal(6, 6), "full health must not allow healing")
	_check(a.can_heal(4, 6), "damaged health should allow healing")

	# 回血被打断：不消耗次数（文档 §3.4）。
	_check(a.begin_heal(), "heal should start")
	a.interrupt_heal()
	_check(a.heal_charges_left() == 2, "interrupting a heal must not consume a charge")

	# 正常完成才消耗。
	a.begin_heal()
	a.finish_heal()
	print("heal_charges_after=", a.heal_charges_left())
	_check(a.heal_charges_left() == 1, "a completed heal should consume exactly one charge")

	a.refill_heal_charges()
	_check(a.heal_charges_left() == 2, "refill should restore charges")

	# 无次数时不允许开始。
	var empty = AbilityState.new()
	_check(not empty.begin_heal(), "no charges means no heal")

# --- 神龙：零战斗判定红线 ------------------------------------------------
func _test_dragon_exploration_only() -> void:
	var a = AbilityState.new()
	_check(is_equal_approx(a.environmental_damage_scale(), 1.0), "no scales means full environmental damage")
	a.has_dragon_scales = true
	print("dragon_env_scale=%.2f combat_scale=%.2f" % [a.environmental_damage_scale(), a.combat_damage_scale()])
	_check(is_equal_approx(a.environmental_damage_scale(), 0.0), "scales must nullify environmental damage")
	_check(is_equal_approx(a.combat_damage_scale(), 1.0), "RED LINE: scales must not reduce combat damage")

	# 红线：龙能力不得提供任何战斗接口。
	for forbidden in ["damage_enemy", "freeze_enemy", "corrode_enemy", "tail_attack_enemy", "breath_damage"]:
		_check(not a.has_method(forbidden), "RED LINE: dragon must not expose combat method '%s'" % forbidden)
	_check(not ("combat_damage" in a), "RED LINE: dragon state must not carry a combat damage field")

	# 龙鳞是纯被动：无时长、无冷却。
	_check(not ("scales_duration" in Config.DRAGON), "scales must be permanent (no duration)")

	# 龙尾与龙息有冷却，且冷却生效。
	a.has_dragon_tail = true
	_check(a.can_use_tail(), "tail should be ready after unlock")
	a.use_tail()
	_check(not a.can_use_tail(), "tail must respect its cooldown")
	a.tick(0.85)
	_check(a.can_use_tail(), "tail should be ready again after 0.8s")

	a.has_dragon_breath = true
	_check(a.can_use_breath(), "breath should be ready after unlock")
	a.use_breath()
	_check(not a.can_use_breath(), "breath must respect its 1.2s cooldown")
	print("dragon_cooldowns_ok tail=%.2f breath=%.2f" % [
		Config.DRAGON["tail_cooldown"], Config.DRAGON["breath_cooldown"]])

	# 未解锁时不可用。
	var locked = AbilityState.new()
	_check(not locked.can_use_tail(), "tail must be locked before M34")
	_check(not locked.can_use_breath(), "breath must be locked before M40")

func _test_dragon_ice_limits() -> void:
	var a = AbilityState.new()
	a.has_dragon_breath = true
	var limit := int(Config.DRAGON["ice_max_platforms"])
	var removed_all: Array = []
	for i in limit + 1:
		removed_all.append_array(a.add_ice_platform(i))
	print("ice_platforms=%d removed=%s" % [a.ice_platforms.size(), str(removed_all)])
	_check(a.ice_platforms.size() == limit, "ice platforms must cap at %d" % limit)
	_check(removed_all.size() == 1 and int(removed_all[0]) == 0, "the oldest ice platform must disappear first")

	# 时代切换后冰面清除（只存在于当前时代）。
	a.clear_ice_on_era_change()
	_check(a.ice_platforms.is_empty(), "era change must clear ice platforms")

# --- 正交性 -------------------------------------------------------------
func _test_ability_orthogonality() -> void:
	# 四项能力各解决不同问题，不得互相替代：检查解锁标记彼此独立。
	var a = AbilityState.new()
	a.has_double_jump = true
	_check(not a.has_air_dash, "phoenix branches must unlock separately")
	_check(not a.has_dragon_scales, "phoenix must not grant dragon scales")
	a.set_qilin_level(4, 4, 4)
	_check(not a.has_dragon_tail, "qilin must not grant dragon abilities")
	# 麒麟不是能力门：它不改变任何地形通过性。
	_check(not a.has_method("unlock_passage"), "qilin must not unlock map passages")
	print("orthogonality_ok")
