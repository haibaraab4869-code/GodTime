# RUN-0002｜基础攻击逻辑自动验证

> 编号：RUN-0002｜类型：自动化（脚本断言）｜结论：**PASS（11/11 断言通过，退出码 0）**
> 覆盖范围：攻击判定方向、命中范围、单次挥击去重、跨挥击重复命中的可行性、背向不命中、挥击中途进入范围的命中、目标破碎与破碎后免伤。
> **不覆盖**：渲染画面、打击手感、动画、音效、真实输入按键路径。

## 被测对象

| 项 | 值 |
| --- | --- |
| 构建标识 | 无版本控制临时标识，以源文件 SHA-256 代替（见下方） |
| 引擎版本 | `4.7.2.stable.official.ed1daf0bf` |
| 平台 | Windows，`--headless` |
| 脚本 | `tests/test_attack.gd` |
| 执行时间 | 2026-10-25 |

## 执行命令

```text
Godot_v4.7.2-stable_win64.exe --headless --path <项目根> --script res://tests/test_attack.gd
退出码：0
```

## 输出

```text
dummy_count=3
right_box=[P: (12.0, -18.0), S: (34.0, 32.0)] left_box=[P: (-46.0, -18.0), S: (34.0, 32.0)]
near_hit health 3 -> 2
multi_hit health 3 -> 2
next_swing health -> 1
behind health 3 -> 3
mid_swing_entry health 3 -> 2
broken=true health=0
broken_health=0 respawn_in=2.0
era_switch_ok past_era=false
FAILURES=0
```

## 逐项结果

| # | 断言 | 结果 |
| --- | --- | --- |
| 1 | 面向右时判定框在 +x 方向 | PASS |
| 2 | 面向左时判定框在 -x 方向 | PASS |
| 3 | 范围内目标生命减 1 | PASS |
| 4 | 400px 外目标不受伤 | PASS |
| 5 | 同一次挥击内重复检测只结算一次 | PASS |
| 6 | 清空命中列表后，新挥击可再次造成伤害 | PASS |
| 7 | 背后目标不受伤 | PASS |
| 8 | 挥击起手时范围外、中途进入范围的目标被命中 | PASS |
| 9 | 上述中途进入的目标不会被重复结算 | PASS |
| 10 | 目标生命归零即破碎，破碎期间免伤 | PASS |
| 11 | 时代切换连续执行两次不崩溃 | PASS |

## 修订记录

- 首轮实现只在挥击起手帧结算一次命中，导致挥击动画期间进入范围的目标无法被击中。已改为**整个挥击期持续检测**，并用 `attack_hit_nodes` 保证同一目标只结算一次；第 8、9 项断言即针对该缺陷的回归。

## 风险与后续

- 该脚本直接调用 `_apply_attack_hits()` 与 `attack_box()`，属于**白盒验证**；它不覆盖 `_physics_process` 中的按键到出招的完整链路。真实按键路径需人工测试。
- 判定使用 `Rect2` 与 `global_position` 计算，未使用 Godot 物理层；若后续改为 `Area2D` 实现，本脚本需同步重写。
- 待人工在有窗口的会话中确认打击手感，另建 `RUN-0003`，不覆盖本记录。

## 源文件校验值（SHA-256）

| 文件 | SHA-256 |
| --- | --- |
| `game/player.gd` | `7a330167ba492e50d9cd7fe744052ddacceb02c66c830a5304ce2739ed4507e0` |
| `game/training_dummy.gd` | `073c5b258976f117a741ec33be4368f58b2f36f3e5b2c574279795896de8b500` |
| `tests/test_attack.gd` | `85dce5e1e736e5e0a3fd7dd8a1308ee6a8ac764f2faf6daf235b53a32a719c71` |
| `game/main.tscn` | `196c49bb423a3cbcf10f5fdea9c2068ff14655da3796909708fa088cfd71e9ea` |
| `game/world.gd` | `173f717bfe7dad94079efc80f687e515368dc4105ea4d84761cec7757ea1ee14` |

> 因尚无版本控制，文件后续修改不会自动反映在此处；需要严格复现时，以执行当次的 `Get-FileHash` 为准。
