# 开发规范

> 本文是当前协作基线（2026-10-25 核对）。仓库已有一个可运行的 2D 探索原型，输入改为语义动作映射并支持手柄与玩家改键，有少量脚本级自动验证；但**仍未初始化 Git、没有 CI、没有通用测试框架、没有导出预设**。引擎版本已实测确认为 `4.7.2.stable.official.ed1daf0bf`。

## 项目与引擎边界

- 根目录 `project.godot` 为唯一 Godot 项目入口；编辑项目设置优先通过 Godot 编辑器，并检查生成的配置差异，避免误把本机选项当团队决策。
- 当前已核实的配置：项目名“时间之神 - 探索原型”、主场景 `res://game/main.tscn`、特性 `4.7` / `Forward Plus`、`canvas_items` / `expand`、3D 物理 `Jolt Physics`、Windows 驱动 `d3d12`。立项案已指定纯 2D 横版与 Steam 平台，因此 `Jolt` 与 `d3d12` 属于引擎初始化负担而非玩法依赖；**是否移除或改为 2D 专用配置（如 `gl_compatibility`）需团队评估后决定，不要随手改动**。
- 当前代码集中在 `game/`：`main.tscn`（单场景）、`input_actions.gd`（自动加载的动作与绑定注册表）、`input_buffer.gd`（输入缓冲）、`settings_panel.gd`（改键面板）、`player.gd`（角色控制与攻击）、`world.gd`（地形、时代切换与 HUD）、`training_dummy.gd`（可受击训练目标）。自动验证脚本在 `tests/`，**运行时代码与测试代码分开**，不要把测试脚本放回 `game/`。这仍是一个**原型切片**，不是已批准的项目架构；首个可玩里程碑确定后再批准 `scenes/`、`scripts/`、`assets/` 等目录结构，不为猜测中的功能建空目录。
- 原型中地形以常量 `Rect2` 数组硬编码在 `world.gd`，这属于原型期妥协。把玩法数值、地形与关卡数据外置到资源（如 `.tres`／JSON）前，应由工程负责人决定方案；不得让多个脚本各自复制一份常量表。
- 攻击判定目前以 `Rect2` 与 `global_position` 自行计算（`player.gd` 的 `attack_box`／`_apply_attack_hits`），通过节点组 `attackable` 收集目标，**未使用 Godot 物理层**。这与项目其余部分使用物理体的做法不同，属于原型简化；改为 `Area2D` 或 `PhysicsDirectSpaceState2D` 前需同步更新 `tests/test_attack.gd`，否则回归会失效。
- 时间能力、战斗、关卡等实现应由设计规格驱动：引用需求来源，定义输入、状态转移、失败/取消、存档恢复与测试入口；避免玩法数值散落硬编码。UI 展示不应成为玩法状态的唯一所有者。当前原型的 HUD 由 `world.gd` 直接写入 Label，属于可接受的临时形态，正式实现时改由信号驱动。

## 输入与可测试性

- 输入已改为**语义动作映射**（2026-10-25）。动作定义集中在自动加载单例 `game/input_actions.gd`（`InputActions`），在启动时写入 `InputMap`；代码只读动作名，不再出现 `KEY_*` 轮询。
- 当前动作：`move_left`、`move_right`、`jump`、`attack`、`dash`、`switch_era`、`reset_checkpoint`，以及驱动设置面板的 `open_settings`。前七个可由玩家改键。
- **默认绑定写在一张 GDScript 表里，而不是 `project.godot` 的 `[input]` 段**。原因：序列化段是 `Object(InputEventKey,...)` 形式，手写极易损坏且难以评审；GDScript 表可 diff、可读、可断言。改动默认键位就改 `DEFAULT_BINDINGS`。
- 键盘绑定使用 **`physical_keycode`**，避免 AZERTY 等布局下 WASD 位置错乱。玩家改键保留该行为。
- **键盘与手柄绑定互不覆盖**：`rebind()` 只替换同一设备类型的绑定。改键到已被其它动作占用的键时，该键从原动作移除，并返回原动作名以便提示。
- 玩家覆盖写入 `user://input_bindings.cfg`；载入时对条目做类型清洗，避免损坏的配置文件让启动崩溃。
- 输入缓冲与手感参数在 `game/player.gd`：`jump_buffer_window`、`attack_buffer_window`、`dash_buffer_window`、`coyote_time`、`jump_cut_multiplier`。缓冲本身由 `game/input_buffer.gd` 提供，只允许消费一次并自动过期。
- **不要绕过动作层**：新增输入一律先加动作，再在脚本里 `is_action_pressed`。直接读 `KEY_*` 会让手柄与改键同时失效。
- 测试用 `Input.action_press("attack")` 可驱动真实动作路径；但这仍不是硬件事件注入，手柄与真实按键链路需人工验证。

## Git 与文件维护

- 当前**未检测到 `.git`**；以下是**拟采用的规范**，不能表述为已启用。仓库初始化、远端绑定、保护分支及提交均须由项目负责人批准。
- `.gitignore` 当前仅忽略 `.godot/` 与 `/android/`；`.gitattributes` 为文本文件启用 `LF` 归一化；`.editorconfig` 为 UTF-8。这些规则不足以覆盖导出产物、临时文件和大文件，添加工具或平台前先审查忽略规则。
- Godot 的 `project.godot`、源场景/脚本/源资产，以及编辑器生成的 `*.uid`、`*.import` 等元数据，应按实际引用和引擎行为判断是否纳入版本控制；**不要一概删除或一概忽略**。`.godot/` 为缓存，不纳入版本控制；资源更名或移动优先在编辑器内操作，再核对引用和 Git 差异。当前 `game/*.gd.uid` 已存在，入库时应保留。
- 大型二进制源资产是否启用 Git LFS 由团队按仓库规模决定；未经确认不添加追踪规则或提交庞大生成文件。立项设计案与地图草案位于 `docs/design/`，是设计类的权威来源与创作提案，勿创建同名副本、覆盖或未经批准迁移。
- 若启用 Git，建议短期功能分支、聚焦提交和合并请求评审；合入前检查新增文件、异常大文件、敏感信息、项目能否正常导入及相关验证结果。禁止提交缓存、密钥、个人路径或编译输出；删除、强推、发布等高影响操作需明确审批。

## 命名、可追溯与去重

- `docs/` 依照[文档索引](../README.md)的唯一分类放置；Markdown 文件名采用 `kebab-case.md`，不建 `final`、`new`、`copy` 等平行版本。游戏文件路径也优先小写英文 `snake_case`，避免 Windows 大小写不敏感环境掩盖跨平台路径冲突；GDScript 类名 `PascalCase`，变量、函数、信号使用 `snake_case`，常量使用 `UPPER_SNAKE_CASE`。
- 现有代码基本遵守上述命名；`game/` 目录名本身为单词，符合 `snake_case` 风格，**不做无收益的改名**。
- 新增系统前先搜索相关场景、脚本和数据，选定**单一职责所有者**；共享数据只定义一次，不复制状态源、常量表或重复工具类。可复用性有真实第二使用者时再抽象，避免空泛的“万能管理器”。
- 文档、需求、脚本、测试之间用稳定的相对路径/需求 ID 建立映射；待需求 ID 体系明确前，可以引用具体设计文档标题与章节，不虚构编号。
- 关键技术决策（时间回溯/时代切换的状态模型、安全复位判据、存档格式、物理与渲染配置取舍）应记录背景、备选方案、决定及代价，并从对应设计/开发文档链接。时代切换的当前实现与原案差异见[功能规格：时间切换](../design/feature-time-switch.md)。

## 变更门槛

- 修改 `project.godot`、输入、物理设置或渲染后，至少通过 Godot 编辑器导入和实际目标设备运行验证；记录编辑器精确版本、平台、复现步骤和结果。已验证的基线见 [RUN-0001](../qa/runs/RUN-0001-prototype-smoke.md)。
- 无头验证命令（本机实测可用）：`Godot_v4.7.2-stable_win64.exe --headless --path <项目根> --import` 与 `--headless --path <项目根> --quit-after 300`。二者均须退出码为 0 且无脚本报错输出才算通过；仅“窗口没崩”不算通过。
- 改动战斗或输入逻辑后，运行全部现有断言脚本，要求各自末行 `FAILURES=0` 且退出码为 0：
  - `--script res://tests/test_attack.gd`（攻击判定）
  - `--script res://tests/test_input.gd`（动作注册、改键、持久化）
  - `--script res://tests/test_input_feel.gd`（缓冲、土狼时间、冷却期攻击）
  新增可断言规则时应在 `tests/` 补对应断言，并在 `docs/qa/runs/` 留痕；**脚本通过不等于手感与画面通过**。
- 编写无头验证脚本时注意：`SceneTree._initialize()` 阶段节点尚未进入场景树，此时 `get_tree()` 与节点组查询会失败。应在节点加入后 `await process_frame` 再断言。
- **GDScript 对不存在的属性赋值会报错但不会中断脚本**。测试脚本若引用了已改名的字段，可能表现为挂起而非失败退出（RUN-0003 首轮即因此超时）。无头脚本应始终以 `quit(code)` 结束，手动执行时设置超时。
- 发现配置或 API 与当前引擎版本不一致时，先查核该版本官方资料并标记知识缺口，不凭记忆臆写 Godot 4.7 行为；由工程负责人批准升级或替换方案。
