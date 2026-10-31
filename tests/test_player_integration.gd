extends SceneTree

## 退役（2026-10-31）：29 区重构把玩家身上的四凶/能力状态机（player.combat / force_form /
## abilities / shift_* / try_heal / set_qilin_level 等）整体拆解到 world.combat（CombatState）
## 与 AbilityState，本测试访问 player.combat 会 SCRIPT ERROR。拆解后的校验已由
## test_combat.gd / test_abilities.gd / test_attack.gd / test_boss_route.gd 承接，
## 无单一等价物可直指，按主理人「最小正确」裁决退役。

func _init() -> void:
	print("SKIP: player 四凶/能力状态机已拆解到 world.combat + AbilityState，旧玩家集成测试退役")
	quit(0)
