# RUN-0001｜探索原型导入与启动烟雾测试

> 编号：RUN-0001｜类型：烟雾测试｜结论：**PASS（仅限“可导入、可启动、无脚本报错”）**
> 重要限制：本次**未覆盖任何玩法功能**。移动、跳跃、冲刺、时代切换、扣血复位等行为均**未做人工或自动化验证**，其验收状态为 `NOT RUN`。不得据本记录声称“原型玩法可用”。

## 被测对象

| 项 | 值 |
| --- | --- |
| 构建标识 | 无版本控制临时标识，以源文件 SHA-256 代替 |
| `game/main.tscn` | `9951b9e962991a3438d3eded4733217fac9f2249e82549bfdeeacd273a963d8b` |
| `game/player.gd` | `899bca0e122b6159e1f6b37280ad0bc446c7b4c9ca96af12af0059bf0e467310` |
| `game/world.gd` | `7824bf471a56bfb986a7c6c91007cb41af75bf4de6bdcee6072ba61be8061774` |
| `project.godot` | `3736ef5fb4722d5c27d4154ac190e0f5cfa35b9ac4f8d9851ced16414daa204d` |
| 引擎版本 | `4.7.2.stable.official.ed1daf0bf`（`Godot_v4.7.2-stable_win64.exe`） |
| 平台 | Windows，`--headless`（无渲染、无音频设备） |
| 执行者 | 开发代理代为执行；**尚无人工见证**，需由项目负责人复跑确认 |
| 执行时间 | 2026-10-25 |
| 前置条件 | 项目根目录存在 `.godot/` 缓存；未初始化 Git |

## 执行记录

### A. 资源导入

```text
命令：Godot_v4.7.2-stable_win64.exe --headless --path <项目根> --import
退出码：0
关键输出：first_scan_filesystem 与 loading_editor_layout 两个阶段均为 [ DONE ]
异常：无
```

### B. 主场景启动

```text
命令：Godot_v4.7.2-stable_win64.exe --headless --path <项目根> --quit-after 300
退出码：0
stdout：仅一行版本横幅 "Godot Engine v4.7.2.stable.official.ed1daf0bf"
stderr：空
异常：无脚本解析错误、无运行时报错、无缺失资源警告
```

## 逐项结果

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 项目可被引擎导入 | PASS | A，退出码 0 |
| 主场景可加载（约 300 帧） | PASS | B，退出码 0，stderr 为空 |
| GDScript 无解析错误 | PASS | B 无报错输出 |
| 无缺失资源引用 | PASS | B 无警告输出 |
| 渲染画面正确（颜色、HUD 排版） | **NOT RUN** | headless 无渲染输出 |
| 音频输出 | **NOT RUN** | 项目尚无音频 |
| 移动/跳跃/冲刺手感 | **NOT RUN** | 需人工操作 |
| 时代切换与危险复位 | **NOT RUN** | 需人工操作，验收项见 [feature-time-switch.md](../../design/feature-time-switch.md#7-验收标准) |
| 窗口拉伸与分辨率表现 | **NOT RUN** | headless 不验证显示配置 |
| 目标设备性能 | **NOT RUN** | 未定义目标设备与预算 |

## 结论与风险

- 可以确认：当前源码在 `4.7.2` 下能被干净导入并启动，不存在阻断启动的脚本或资源错误。这解除了“代码能否跑起来”的不确定性。
- **不能确认**：任何玩法行为是否符合设计意图。`docs/overview/project-overview.md` 中“已实现”的表述仅指代码存在，不等于通过验收。
- 风险：headless 运行不加载渲染管线，`d3d12` 与 `Forward Plus` 的配置问题不在本记录覆盖范围内；需在有显示设备的会话中复跑一次。
- 后续动作：由负责人执行一次带窗口的人工烟雾测试，按上表补齐 `NOT RUN` 项，另建 `RUN-0002`，不覆盖本记录。
