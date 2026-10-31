# 资产登记（Asset Manifest）

> 状态：**草案 v4**（2026-10-26）。v1 = 7 头身成人 + 纵向分层（已删）；v2 = 3 头身但**正面 A-pose**（已删）；v3 = 横版侧视 + 16 部件骨骼 rig；v4 = 补 `parts.json` 的视角字段（`view_class` / `flippable`），与规则 G-3 对齐。
> **只登记已落盘的文件**。未制作项不登记。路径均为项目内 `res://` 相对路径。
> 体积与尺寸为 2026-10-26 实测值，当前占用 **2.50 MB**（v1 9.4 MB / v2 2.6 MB），其中 2.44 MB 是 5 张评审图。

## 1. 路径与命名规则

### 1.1 目录结构

```
res://assets/
└── characters/
    └── shihung/                    主角时衡
        ├── parts/                  16 张部件贴图 + parts.json（引擎引用）
        ├── rig/                    骨骼场景 shihung_rig.tscn（引擎引用）
        └── preview/                评审图（引擎不引用，仅供人工检查）
```

**相对 v1 的变化**：删除 `source/`、`layers/`、`export/`、`spec/` 四个目录。

| v1 目录 | 当前处置 | 原因 |
| --- | --- | --- |
| `source/` | **删除** | 新链路为程序化绘制，不再依赖 AI 母版；旧母版已废弃（§6） |
| `layers/` | → `parts/` | 「层」改为「可绑定骨骼的部件」，语义与用途都变了，需换名避免混读 |
| `export/` | → `parts/` + `rig/` | 不再有「成品帧」——成品是骨骼场景，不是序列帧 |
| `spec/` | → 并入本文 §4 | 规格数据（枢轴、z 序、层序）由 `parts.json` 机器可读持有，叙述部分并入文档 |

### 1.2 命名规则

**部件贴图**：`char_<对象>_part_<部件名>.png`

| 段 | 取值 | 示例 |
| --- | --- | --- |
| 类别 | `char` / `env` / `ui` / `vfx` | `char` |
| 对象 | 对象标识，小写英文 | `shihung` |
| 固定词 | `part` | `part` |
| 部件名 | 语义名，`snake_case`，与骨骼同名 | `arm_near_upper` |

示例：`char_shihung_part_arm_near_upper.png`

- **不出现密度后缀**：部件只有一套 128×128 源，缩放由 `rig.scale` 在引擎内完成，不导出 1x/2x 副本（v1 的 `@2x`/`@4x` 规则作废）。
- **部件名必须与骨骼名一一对应**：`build_rig.gd` 用 `"char_shihung_part_%s.png" % part_name` 拼路径，改名即断链。
- 中文名不入文件系统，避免跨平台编码问题。

### 1.3 新增规则（适用范围：`assets/characters/` 全部角色，含怪物）

**规则 E：`parts/` 与 `rig/` 是唯一允许被场景引用的目录；`preview/` 仅供人工评审，不得被场景引用。**

- 违反时 `verify_rig.gd` 不报错（它只校验 rig 内部），需在美术评审中人工记录。
- 理由：`preview/` 里的图是约 1.9 MB 的评审拼图，导入后会被打进构建包，纯属浪费。

**规则 F：每个角色只保留一套骨骼 rig；换方案时删除旧 rig 与旧部件，不做并行保留。**

- 本轮据此删除了 v1 与 v2 的全部资产（§6）。并行保留会导致「不知道哪套是当前版本」。

**规则 G（v3 新增）：全部角色资产一律画**横版侧视、朝 +x**；朝向用 `near`/`far` 命名，禁止 `front`/`back`。**

- 名称里出现 `front` 会把「身体正面」误读成「朝向」，在侧视项目里是持续性误导。
- 朝左不另做素材，由 `rig.scale.x = -1` 处理。若某角色确实需要双面差异（如护盾只在某一侧），须在本文单独登记例外。
- 违反时外观检查能过（图还是能加载），但角色会变成"正面对着镜头横着走"——v2 就踩过这个坑，因此提为规则而非建议。

## 2. 资产清单

### 2.1 部件（`characters/shihung/parts/`）

| ID | 文件 | 尺寸 | 体积 | 绑定骨骼 | z | 状态 |
| --- | --- | --- | --- | --- | --- | --- |
| CH-SHIHUNG-101 | `char_shihung_part_leg_far_shin.png` | 128×128 | 1 KB | leg_far_shin | 0 | 可用 |
| CH-SHIHUNG-102 | `char_shihung_part_leg_far_thigh.png` | 128×128 | 1 KB | leg_far_thigh | 1 | 可用 |
| CH-SHIHUNG-103 | `char_shihung_part_arm_far_lower.png` | 128×128 | 1 KB | arm_far_lower | 2 | 可用 |
| CH-SHIHUNG-104 | `char_shihung_part_arm_far_upper.png` | 128×128 | 1 KB | arm_far_upper | 3 | 可用 |
| CH-SHIHUNG-105 | `char_shihung_part_leg_near_thigh.png` | 128×128 | 1 KB | leg_near_thigh | 4 | 可用 |
| CH-SHIHUNG-106 | `char_shihung_part_leg_near_shin.png` | 128×128 | 1 KB | leg_near_shin | 5 | 可用 |
| CH-SHIHUNG-107 | `char_shihung_part_hem_back.png` | 128×128 | 2 KB | hem_back | 6 | 可用 |
| CH-SHIHUNG-108 | `char_shihung_part_torso.png` | 128×128 | 3 KB | torso | 8 | 可用 |
| CH-SHIHUNG-109 | `char_shihung_part_hem_front.png` | 128×128 | 1 KB | hem_back | 9 | 可用 |
| CH-SHIHUNG-110 | `char_shihung_part_sash_2.png` | 128×128 | 1 KB | sash_2 | 10 | 可用 |
| CH-SHIHUNG-111 | `char_shihung_part_sash_1.png` | 128×128 | 1 KB | sash_1 | 11 | 可用 |
| CH-SHIHUNG-112 | `char_shihung_part_gold_line.png` | 128×128 | 1 KB | torso | 12 | 可用 |
| CH-SHIHUNG-113 | `char_shihung_part_arm_near_lower.png` | 128×128 | 1 KB | arm_near_lower | 13 | 可用 |
| CH-SHIHUNG-114 | `char_shihung_part_arm_near_upper.png` | 128×128 | 1 KB | arm_near_upper | 14 | 可用 |
| CH-SHIHUNG-115 | `char_shihung_part_head.png` | 128×128 | 3 KB | head | 16 | 可用 |
| CH-SHIHUNG-116 | `char_shihung_part_crown.png` | 128×128 | 1 KB | crown | 17 | 可用 |
| CH-SHIHUNG-120 | `parts.json` | — | 1 KB | — | — | 可用 |

`parts.json` 是机器可读的枢轴与层序清单，与 `tools/build_rig.gd` 的 `PART_MAP` 必须同步；`tools/render_pose_sheet.py` 依赖它做离线姿态渲染。其中**视角三元组是规则 G-3 的落地字段**：

| 字段 | 当前值 | 含义 |
| --- | --- | --- |
| `view_class` | `"side"` | 视角类别，只允许 `side`（主角/怪物）或 `front`（NPC） |
| `view` | `"side, facing +x"` | 人类可读描述 |
| `flippable` | `true` | 是否允许 `rig.scale.x = -1` 翻转；NPC 必须为 `false` |

`tools/verify_rig.gd` 的 `-- view class --` 段会断言这三项，并检查没有任何部件用 `front`/`back` 表达左右侧（`arm_front*`、`leg_back*` 之类）。

### 2.2 骨骼（`characters/shihung/rig/`）

| ID | 文件 | 内容 | 体积 | 状态 |
| --- | --- | --- | --- | --- |
| CH-SHIHUNG-201 | `shihung_rig.tscn` | `ShihungRig`(Node2D) → `Skeleton2D` → 15 `Bone2D` → 16 `Sprite2D` + `AnimationPlayer`（11 个 `Animation`） | 52 KB | 可用 |

场景结构要点：

- `Skeleton2D.position = (-64, -88)`，使画布髋点对齐 rig 原点；这样 `Rig.scale.x = -1` 是**原地翻转**而不是整体位移。
- 每个 `Sprite2D`：`centered = false`、`offset = -pivot`、`z_index` 见上表。
- `AnimationPlayer` 默认播放 `idle`。

### 2.3 评审图（`characters/shihung/preview/`）

| ID | 文件 | 尺寸 | 体积 | 内容 |
| --- | --- | --- | --- | --- |
| CH-SHIHUNG-301 | `char_shihung_pose_sheet.png` | 1600×4702 | 2.28 MB | 11 个片段 × 4 帧的骨骼实际姿态，用于查穿模/飞散 |
| CH-SHIHUNG-302 | `char_shihung_rest_sheet.png` | 496×280 | 37 KB | 静止姿三档：2× 细节 / 1× 原始 / 0.5× 屏上真实尺寸（约 58 px 高） |
| CH-SHIHUNG-303 | `char_shihung_rest_composite.png` | 128×128 | 9 KB | 16 部件按 z 序合成的静止姿（1× 原尺寸） |
| CH-SHIHUNG-304 | `char_shihung_rest_composite_4x.png` | 512×512 | 15 KB | 同上，最近邻放大 4×，看像素细节 |
| CH-SHIHUNG-305 | `char_shihung_parts_grid.png` | 896×896 | 63 KB | 16 个部件按包围盒居中平铺，红叉标出枢轴 |

**出图脚本分工（避免互相覆盖）**：`gen_parts.py` 出 302–305（纯美术评审，不需要引擎）；`render_pose_sheet.py` 只出 301（从 Godot 读出的真实骨骼变换）。两者都写 `preview/`，但文件名不重叠。

`char_shihung_pose_sheet.png` 是**能验证动画是否正确的唯一离线证据**：它渲染的是从 Godot 读出的真实骨骼变换，不是手画的示意。

## 3. 工程引用状态

**已接入**（v1 时期为「未接入」）。改动两处：

| 文件 | 改动 |
| --- | --- |
| `game/main.tscn` | 在 `Player` 下新增 `Rig` 节点，`instance = shihung_rig.tscn`，`position = (0, 4)`，`scale = (0.5, 0.5)` |
| `game/player.gd` | 新增 `rig`/`anim` 引用、`_update_visual()`、`_trigger()`、`_pick_locomotion()`、`CLIP_PRIORITY` 优先级表；`_draw()` 的矩形占位在检测到 `rig` 时直接 return |

接入后 `_draw()` 仍保留占位逻辑，作用是在 rig 缺失（例如测试里单独实例化 player）时保底可见，不参与正常渲染。

2026-10-26 接入复核：`player.gd` 在切换动画前恢复骨骼初始变换，避免未被下一片段驱动的腿、手臂或根骨骼残留上一动作的姿势；一次性动画按游戏动作时长调整播放速度（例如 0.26 秒攻击片段适配 0.16 秒挥击窗口）。`tests/test_visual.gd` 已增加姿势残留与动画时长回归。Godot 4.7.2 导入、D3D12 窗口启动（120 帧）、骨骼校验及视觉／攻击／输入／手感／能力／战斗脚本检查均通过。另有现存 `tests/test_player_integration.gd` 依赖尚未接入玩家的 `combat` 属性，当前报错；这项不属于本次主角视觉接入的通过项。

**回归覆盖**：`tests/test_visual.gd`（20 项断言）覆盖 rig 存在、15 骨骼、11 动画、16 部件、脚底与碰撞盒对齐、朝向翻转、idle/run/jump/fall 切换、优先级不可打断、`take_damage`/`respawn` 触发。该测试不检查部件名，因此本轮改名 `front/back → near/far` 不影响它。

## 4. 生产工具与规格

| ID | 工具 | 语言 | 职责 |
| --- | --- | --- | --- |
| CH-SHIHUNG-401 | `tools/gen_parts.py` | Python + Pillow | **部件生成的唯一真源**。按骨骼画布坐标确定性绘制 16 张侧视部件；4× 超采样 + 预乘 alpha 缩放；输出 `parts/*.png`、`parts.json` 与 5 张评审图 |
| CH-SHIHUNG-402 | `tools/build_rig.gd` | GDScript（SceneTree） | 生成 `rig/shihung_rig.tscn`：15 骨骼、16 部件绑定、11 个动画。用脚本而非手写 `.tscn`，因为 `Bone2D.rest` 与 `AnimationLibrary` 的序列化格式由引擎写入才可靠 |
| CH-SHIHUNG-403 | `tools/verify_rig.gd` | GDScript（SceneTree） | 断言：15 骨骼 / 11 动画 / 16 部件枢轴偏差 < 1 px / 每个片段至少驱动 1 根骨骼 / 下摆在 run·fall·dash 中实际摆动 / 动画结束回到静止姿 |
| CH-SHIHUNG-404 | `tools/export_poses.gd` | GDScript（SceneTree） | 采样 11 个片段各 4 帧，导出 `user://poses.json`（每个部件的枢轴坐标 + 全局旋转 + z） |
| CH-SHIHUNG-405 | `tools/render_pose_sheet.py` | Python + Pillow | 读 `poses.json` 渲染评审图。坐标变换关键点：贴图绕**静止枢轴**旋转，再把枢轴平移到骨骼当前位置 |

### 4.1 重跑顺序

```bash
python tools/gen_parts.py                                    # 1. 重画部件
Godot --headless --path . --import                            # 2. 导入贴图
Godot --headless --path . --script res://tools/build_rig.gd    # 3. 重建 rig
Godot --headless --path . --script res://tools/verify_rig.gd   # 4. 校验（须 FAILURES=0）
Godot --headless --path . --script res://tools/export_poses.gd # 5. 采样
python tools/render_pose_sheet.py                             # 6. 出评审图
```

**换视角或改体型时，必须同时改 `gen_parts.py` 与 `build_rig.gd` 的坐标常量，再按上序全跑。** 两个文件的 `CENTER / HIP_Y / KNEE_Y / ARM_NEAR_X / ARM_FAR_X / LEG_FAR_X / SASH1 / SASH2` 必须逐字一致，否则静止姿会错位——`verify_rig.gd` 的枢轴断言就是这条的守门人。

### 4.2 技术规格

| 项 | 值 |
| --- | --- |
| 格式 | PNG RGBA，sRGB |
| 部件画布 | 128×128，共 16 张 |
| 色彩空间 | 非预乘存储；生成时在预乘空间做 LANCZOS 缩放，避免透明边缘黑边 |
| 过滤 | Godot 默认（线性）；整数倍放大时建议改为 nearest |
| 屏上缩放 | `rig.scale = 0.5` → 角色约 23×58 px |
| 单帧三角形量 | 16 个四边形，可忽略 |

## 5. AI 辅助记录与授权

| 字段 | 内容 |
| --- | --- |
| 当前资产是否由 AI 出图 | **否**。16 张部件由 `tools/gen_parts.py` 程序化绘制，无 AI 图像参与 |
| 为什么不用 AI | AI 无法输出骨骼文件；且两轮实测 AI 生成的 A-pose 母版四肢与躯干粘连，切不出可绑定部件（§6） |
| v1/v2 遗留的 AI 素材 | 6 个 ImageGen 原始输出与抠图母版，**已全部删除**，不进入资源库 |
| 参考素材 | 无。未使用任何第三方图像作为参考或输入 |
| 商用与再分发 | 程序化绘制产物，本轮判断无第三方授权风险；若后续引入 AI 素材，仍需项目负责人确认商用范围 |
| 授权底线 | 依 `docs/art/README.md`：授权未核实前，资产标记为「可用（内部）」，不对外发布 |

## 6. 删除记录

### 6.1 第三轮（2026-10-26，视角由正面改为侧视）

按用户要求「如果不是（横版侧视）就删除之前生成的内容重新生成」执行。删除 v2 全部产物 **44 个文件**（16 部件 + 16 `.import` + `parts.json` + 5 评审图 + 5 `.import` + `rig.tscn`），目录整体清空后重建。

| 批次 | 内容 | 删除原因 |
| --- | --- | --- |
| v2 正面 A-pose 资产 | `parts/` 16 张 + `parts.json` | 正面视角与「纯 2D 横版」不符 |
| v2 骨骼场景 | `rig/shihung_rig.tscn` | 骨骼坐标、z 序、全部动画数值均按正面布局，无法复用 |
| v2 评审图 | `preview/` 5 张 | 全部为正面姿态，已失效 |

**未删除**：`tools/` 下 5 个生产工具。它们是参数化的，改坐标即可重画——这正是程序化链路相对 AI 出图的价值。

### 6.2 第二轮（2026-10-26）

按用户要求「删除此前生成的旧模型及相关资源」执行，共删 26 个文件，9.4 MB → 2.6 MB。

| 批次 | 内容 | 删除原因 |
| --- | --- | --- |
| 第一轮产物（16 项） | `layers/` 5 张分层 + `layers.json`、`export/` 6 张帧与立绘、`spec/` 3 份规格、`source/` 抠图母版 | 7 头身方案被取代 |
| 第二轮中途废弃（6 项） | `source/char_shihung_master_apose_01.png`、`_02.png`、`char_shihung_limbs_01.png`、3 个 ImageGen 原始输出 | 四肢与躯干粘连，切出的部件不可绑定 |
| 重复预览（4 项） | `preview/char_shihung_rest_4x.png`、`char_shihung_review_sheet.png`、`parts/_rest_composite_check*.png` | 被 `rest_sheet` / `rest_composite` 取代 |

## 7. 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-10-26 | 初版建立；登记 7 头身主角 16 项资产；确立 `assets/characters/<id>/` 四级目录与 `@2x` 密度规则 |
| 2026-10-26 | **v2 重写**：目录由四级改为 `parts/`+`rig/`+`preview/`；命名取消密度后缀、新增 `part` 固定词；登记 16 部件 + 1 rig + 5 评审图 + 5 生产工具；引用状态由「未接入」改为「已接入」；新增规则 E/F |
| 2026-10-26 | **v3 重写**：部件名 `front/back` → `near/far`（16 项全改）；z 序按侧视重排；登记新增规则 G（侧视命名铁律）；删除 v2 全部 44 个文件并登记删除记录；尺寸/体积更新为实测值 |
