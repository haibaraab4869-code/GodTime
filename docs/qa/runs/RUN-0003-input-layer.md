# RUN-0003｜语义输入层、手柄绑定与输入缓冲

> 编号：RUN-0003｜类型：自动化（脚本断言）｜结论：**PASS（21/21 断言通过，三个脚本退出码均为 0）**
> 覆盖范围：动作注册、手柄默认绑定、键盘与手柄绑定隔离、改键冲突处理、InputMap 同步、持久化、恢复默认、绑定文本、缓冲单次消费与过期、跳跃缓冲、土狼时间参数、冷却期攻击缓冲、动作桥接、重生清理缓冲。
> **不覆盖**：真实手柄硬件、真实按键事件注入、设置面板的视觉与鼠标交互。

## 被测对象

| 项 | 值 |
| --- | --- |
| 引擎版本 | `4.7.2.stable.official.ed1daf0bf` |
| 平台 | Windows，`--headless` |
| 脚本 | `tests/test_input.gd`（11 项）、`tests/test_input_feel.gd`（6 项）、`tests/test_attack.gd`（11 项，迁移后复跑） |
| 执行时间 | 2026-10-25 |

## 执行命令

```text
--headless --path <项目根> --script res://tests/test_input.gd        → FAILURES=0
--headless --path <项目根> --script res://tests/test_input_feel.gd   → FAILURES=0
--headless --path <项目根> --script res://tests/test_attack.gd       → FAILURES=0
--headless --path <项目根> --import                                  → 退出码 0
--headless --path <项目根> --quit-after 200                          → 退出码 0
```

## 关键输出

```text
actions_registered=7
gamepad_bindings_ok
rebind_kept_pad size 4 -> 2
conflict_from=jump
inputmap_synced
pad_rebind_kept_keys=1
buffer_single_consume
buffer_expiry
persistence_ok
reset_ok
sample_text=Space / W / Up / 手柄 A
```

```text
buffer_ok
jump_buffer_armed
coyote_time=0.1
attack_after_cooldown attacking=true
action_bridge_ok
respawn_clears_buffer
```

## 逐项结果

| # | 断言 | 结果 |
| --- | --- | --- |
| 1 | 7 个动作全部注册进 `InputMap` | PASS |
| 2 | 移动/跳跃/攻击/冲刺/切时代均有手柄绑定 | PASS |
| 3 | 用键盘改键后手柄绑定仍保留 | PASS |
| 4 | 改键到已被占用的键时，原动作失去该键 | PASS |
| 5 | `InputMap` 与内部绑定表保持同步 | PASS |
| 6 | 用手柄键改键后键盘绑定仍保留 | PASS |
| 7 | 缓冲中的按键只能被消费一次 | PASS |
| 8 | 缓冲超过时间窗后自动失效 | PASS |
| 9 | 改键写入 `user://input_bindings.cfg` 并能重新载入 | PASS |
| 10 | `reset_to_defaults` 恢复默认绑定 | PASS |
| 11 | 每个动作都能输出可读的绑定文本 | PASS |
| 12 | 跳跃缓冲可被置位 | PASS |
| 13 | 土狼时间为正且不超过 0.3s | PASS |
| 14 | 冷却期间按攻击不会立即出招 | PASS |
| 15 | 冷却结束瞬间，缓冲的攻击仍会发动 | PASS |
| 16 | `InputMap` 动作可被 `Input.action_press` 驱动 | PASS |
| 17 | 重生会清空跳跃与攻击缓冲 | PASS |

（`tests/test_attack.gd` 的 11 项见 [RUN-0002](RUN-0002-attack-logic.md)，本次迁移后复跑仍全部通过。）

## 顺带修复的缺陷

- `tests/test_attack.gd` 原先写入已不存在的 `player.attack_requested`。GDScript 对这种属性赋值只是报错而不中断，导致**脚本挂起而不是失败退出**，第一次运行超时 180 秒被强制终止。已改为通过 `attack_buffer.press()` 触发，并补上"挥击是否真的开始"的断言。

## 风险与后续

- **未在真实手柄上验证**。绑定表与 `InputMap` 内容已断言，但手柄的按键索引、摇杆轴向在不同型号上可能不同；需人工插手柄实测。
- 设置面板（`settings_panel.gd`）仅有语法与启动验证，**鼠标点击、按钮焦点、暂停交互均未测**。
- 输入缓冲只在逻辑层断言，**手感仍需人工确认**。
- 待人工在带窗口的会话中执行一次完整试玩，另建 `RUN-0004`，不覆盖本记录。

## 源文件校验值（SHA-256）

| 文件 | SHA-256 |
| --- | --- |
| `game/input_actions.gd` | `0e25d9e8cd143d6b67f7b9dd685adb0c966b0a779c34f147d7c4c527d37f8fdd` |
| `game/input_buffer.gd` | `37661b0f040dedd14b7b7f655eee4426e03de0d54808397f26dfe4e565f1221a` |
| `game/settings_panel.gd` | `69edc09a1b07bcf85e554af21c9ad4ed3fe72042d68cb447d2d5307aea882340` |
| `game/player.gd` | `2776f5734f6993f8d0a04d3bc1e77c780bd9c1d780e70e8f66b1b7f926a81cca` |
| `game/world.gd` | `b4124e92c91387c33fa2ad3b9a329f7b311e4302ceae2627b6edbfd6baa1ec10` |
| `game/training_dummy.gd` | `073c5b258976f117a741ec33be4368f58b2f36f3e5b2c574279795896de8b500` |
| `project.godot` | `972a3b5ce25e625c887b45a7906833a0d093eba0d08d0a4801dd194246d4e550` |
| `tests/test_input.gd` | `9c227f451a4b09dddba93d6185bd74b765be2fe6fbaa91ca31b5143ffc2be509` |
| `tests/test_input_feel.gd` | `7b3d884c47f4b826131d71f8d0ea9da3d974a868752fa6731ef208cf3815cb36` |

> `tests/test_attack.gd` 与 `game/world.gd` 在本次缩进统一后有变动，哈希以执行当次为准。
