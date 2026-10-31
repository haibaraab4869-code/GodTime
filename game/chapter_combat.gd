extends Node

const State := preload("res://game/combat_state.gd")
const Rules := preload("res://game/combat_rules.gd")
const Config := preload("res://game/combat_config.gd")
var state := State.new()
var player: CharacterBody2D
var world: Node2D
var combo := 0
var combo_window := 0.0
var current_hit: Dictionary = {}
var action_left := 0.0
var action_total := 0.0
var pending_kind := ""
var ward_left := 0.0
var absorb_left := 0.0
var buff_left := 0.0
var action_fired := false

func _ready() -> void:
	player.swing_started.connect(_on_swing)
	process_physics_priority = -1

func display_name() -> String:
	return {"taotie": "饕餮", "qiongqi": "穷奇", "taowu": "梼杌", "hundun": "混沌"}[state.form]

func help_text() -> String:
	return {"taotie": "普攻末段施饥印；重击撕咬有印目标可回血，同目标有冷却，Boss 每战最多两格。技能吞噬地波并回气。", "qiongqi": "普攻四段；冲刺避开攻击获得锐，强化下一次重击。技能追击收招或失衡中的敌人。", "taowu": "受伤积累逆劲。重击蓄势后破甲；技能准备一次护身，强化随后攻击的削韧和距离。", "hundun": "普攻末段施混沌印，重击引爆印记。技能在面前延迟生成范围爆发。连续命中会累积余波削弱目标。"}[state.form]

func _unhandled_input(event: InputEvent) -> void:
	if world.journal.visible or world.settings_panel.visible or event.is_echo(): return
	if event.is_action_pressed("heavy_attack"): start_action("heavy")
	elif event.is_action_pressed("beast_skill"): start_action("skill")

func clear_action() -> void:
	action_left = 0
	pending_kind = ""
	current_hit = {}
	combo = 0
	combo_window = 0
	ward_left = 0
	absorb_left = 0
	buff_left = 0

func reset_fight() -> void:
	clear_action()
	state.qi = 0
	state.reverse_stacks = 0
	state.sharp_remaining = 0
	state._clear_form_temp_state()

func on_hurt() -> void:
	state.register_damage_taken()
	action_left = 0
	pending_kind = ""

func _physics_process(delta: float) -> void:
	if world.get("hitstop_left") != null and world.hitstop_left > 0: return
	state.tick(delta)
	combo_window = maxf(0, combo_window - delta)
	ward_left = maxf(0, ward_left - delta)
	absorb_left = maxf(0, absorb_left - delta)
	buff_left = maxf(0, buff_left - delta)
	if action_left <= 0: return
	action_left = maxf(0, action_left - delta)
	player.attack_buffer.clear()
	if player.dash_remaining > 0:
		clear_action()
		return
	if not action_fired and action_left <= action_total * 0.25:
		action_fired = true
		_fire_action()
	if action_left <= 0: pending_kind = ""

func _on_swing() -> void:
	if action_left > 0: return
	if combo_window <= 0: combo = 0
	current_hit = Rules.resolve_combo(state.form, combo, state.is_sharp())
	combo = (combo + 1) % Config.FORMS[state.form].combo.size()
	combo_window = 1.25

func start_action(kind: String) -> bool:
	if action_left > 0 or player.attack_remaining > 0 or player.dash_remaining > 0: return false
	if kind == "skill":
		var cost := int(Config.FORMS[state.form].skill.cost)
		if not state.spend_qi(cost):
			world._notify("凶气不足；普攻命中可积累。", 3)
			return false
		current_hit = Rules.resolve_skill(state.form, state.is_sharp(), {"target_vulnerable": true, "target_in_range": true})
	else:
		current_hit = Rules.resolve_heavy(state.form, {"charge_ratio": 1.0, "reverse_damage_bonus": state.reverse_damage_bonus(), "reverse_poise_bonus": state.reverse_poise_bonus()}, state.is_sharp())
	action_total = float(current_hit.duration)
	action_left = action_total
	pending_kind = kind
	action_fired = false
	player.attack_cooldown_remaining = action_total
	player._trigger("attack", action_total)
	world.cancel_heal_only()
	return true

func _fire_action() -> void:
	if pending_kind == "skill" and state.form == "taotie":
		absorb_left = float(current_hit.absorb_window)
		return
	if pending_kind == "skill" and state.form == "taowu":
		ward_left = float(current_hit.ready_window)
		buff_left = float(current_hit.poise_bonus_duration)
		return
	var reach := float(current_hit.get("reach", 80))
	var height := float(current_hit.get("height", 60))
	if pending_kind == "skill" and state.form == "hundun": reach = float(current_hit.width)
	if buff_left > 0: reach += 8
	var box := Rect2(player.position + Vector2(8 if player.facing > 0 else -8 - reach, -height * 0.5), Vector2(reach, height))
	for target in get_tree().get_nodes_in_group("attackable"):
		if target.has_method("receive_combat") and box.intersects(Rect2(target.position - Vector2(12, 40), Vector2(24, 52))):
			deal_hit(target, current_hit)

func deal_hit(target: Node2D, source: Dictionary) -> void:
	var hit := source.duplicate()
	if hit.is_empty(): hit = Rules.resolve_combo(state.form, 0, false)
	if hit.get("kind") == "heavy":
		hit = Rules.resolve_heavy(state.form, {"hunger": target.hunger, "chaos_marks": target.chaos_marks, "charge_ratio": 1.0, "reverse_damage_bonus": state.reverse_damage_bonus(), "reverse_poise_bonus": state.reverse_poise_bonus()}, state.is_sharp())
	elif hit.get("kind") == "skill" and state.form == "qiongqi":
		hit = Rules.resolve_skill(state.form, state.is_sharp(), {"target_vulnerable": target.phase == "recover" or target.phase == "stagger", "target_in_range": true})
	if buff_left > 0: hit.poise = float(hit.get("poise", 0)) * 1.3
	target.receive_combat(hit, state.form)
	state.add_qi(int(hit.get("qi", 0)) + int(hit.get("qi_on_ignite", 0)))
	if hit.get("sharp_consumed", false): state.consume_sharp()
	if hit.get("heal", 0) > 0 and state.can_bite_heal(target.get_instance_id(), target.boss):
		var healed: bool = player.health < player.maximum_health
		if healed:
			player.health += 1
			player.health_changed.emit(player.health, player.maximum_health)
		state.register_bite(target.get_instance_id(), healed, target.boss)
	if state.form == "taowu" and hit.get("kind") == "heavy": state.consume_reverse()

func evade(target_id: int) -> void:
	state.register_precise_dodge(target_id, 2.0)
