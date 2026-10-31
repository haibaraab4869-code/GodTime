# RUN-0012 · M01 地图结构重构 v3.1 垂直切片

- 日期：2026-10-28
- 范围：仅 M01 五个房间重排；其余 47 区未推广地形重构，等待用户确认。
- 依据：`docs/development/handoff-map-reconstruction-v3.md`、`docs/design/feature-map-reconstruction.md`。
- 引擎：Godot 4.7.2 stable；无头物理测试固定 60 FPS。截图为 Windows 有窗口运行、D3D12 Forward+、RTX 4080 SUPER 真实渲染，不是示意图。

## 结果与平台实测

通过 M01 切片自动化及规定回归；是否推广 48 区仍须用户确认。

- 文档原基线：2896；当前工作区在任何地形修改前实测：**2894**。
- 当前工作区实际总数：**2894 → 2848**，减少 46。
- M01：**48 → 2**。两块均为 D4 中途落脚，没有 D1 填充平台、逐锚点垫台。
- 其余 47 区：总计 2846 块，逐区平台数和完整基础碰撞数组摘要与改前一致（47/47）。
- 文档 2896 与实测差 2 的来源尚未确认；没有把文档数字当作本次实测。全库 ≤1050 的最终预算暂不适用，因为未推广其余 47 区。
- 统计口径：真实 `WorldData.model(id).platforms`，与交接中的浮动平台预算一致；不把实体地板、临时能力平台或机关动态设施算进此数组。
- 原始证据：`m01-v31-platforms-before.json`、`m01-v31-platforms-after.json`、`m01-v31-platforms.log`。

## 切片实现

- 五房间 y/height 按 224 格线；新增明确物理 `floor_y`：448、512、448、960、1024。
- 三条 D1 为 64px 实体台地、零填充平台；两条 D4 为 512px，井宽 128px，每井一块落脚，位于井口下 256px。
- 西井保留无需机动神权的根索回程，东井为单向垂索深度提示；可攀根索与不可攀灰色垂索采用不同视觉。
- 固定镜头缩放 1.6，房间/井道通行空间钳制、平滑与 ±60px 前瞻；井口实测首屏可见中途落脚。
- 退役观照模块、输入、HUD 与能力门；M02 旧能力交互运行时变为叙事，M03 刻字直接可读。
- 旧潜刺加载为明刺+静态裂纹，近距扬尘，不依赖观照；保留 1 点伤害、复位、无敌与下劈闭环。
- 布局版本 7，旧版本 4/6 的坐标迁移到具名灯龛，保留资源、任务、流派及有效能力，剔除 VC。

## 自动化断言

| 项目 | 结果 | 原始记录 |
| --- | --- | --- |
| 设计约束校验 | 755 检查，0 失败，RESULT: PASS | `m01-v31-design.log` |
| 设计数据重建 | OK 48 regions（仅设计数据，不等于运行布局推广） | 执行 `tools/build_map_design.py` |
| v3.1 实现验收 | 3137 检查，0 失败 | `m01-v31-assertions.log` |
| M01 双时代连续物理回环 | 36 检查，0 失败 | `m01-v31-traversal.log` |
| M01 编译幂等 | PASS | `compile_m01(current) == current` |
| 其他 47 区平台及碰撞不变 | 47/47 PASS | 改前/改后 inventory JSON |
| Godot 编辑器导入 | 退出码 0，无脚本解析错误 | `m01-v31-import.log` |
| 编辑器诊断 | 本次修改文件无 error/warning | IDE diagnostics |

3137 项覆盖全 48 区固定镜头、退役输入/VC、无运行潜刺，及 M01 格线、真实落差、平台预算、单连接平台数、锚点实体支撑、井口真实相机首屏落脚可见、地刺与下劈闭环、真实 M07 连续下劈链、版本 4/6 隔离存档迁移及临时测试存档清理。

36 项连续物理回环使用基础移动/跳跃，无 P2/PA/PW/PG，不在单次路线中传送：入口→西井横越→上层台地→东井横越→机关室控制点→东井下落→M03 出口岸→下层台地→M02 出口岸→西根索返程→入口。过去/未来各走一次，全程无地刺伤害。未宣称其余 47 区满足 v3.1 全新布局断言。

## 规定回归

以下全部退出码 0、FAILURES=0；完整日志为同目录 `m01-v31-test_*.log`。

| 测试 | 结果 |
| --- | --- |
| `test_attack` | PASS |
| `test_input` | PASS |
| `test_input_feel` | PASS |
| `test_chapter_one` | 199 检查，0 失败 |
| `test_m01` | 17 检查，0 失败 |
| `test_pogo_routes` | 47 条真实下劈链，0 失败 |
| `test_world_regions` | 1333 检查，0 失败 |
| `test_structure_traversal` | 48 次真实攀升，0 失败 |

额外回归同样通过：`test_mythic_maps`（1305）、`test_mythic_environment`（498）、`test_mythic_traversal`（50）、`test_abilities`、`test_world_abilities`（12）。

## M01 实机截图

截图脚本关闭持久化、固定采样位置并停用角色/敌人物理以稳定取景；画面来自实际游戏场景与渲染，不代表人工手柄手感验收。

### 一屏标准房

![M01 标准房，固定缩放 1.6](m01-v31-standard-room.png)

### D4 井口

![M01 D4，128px 井口、灰色垂索与首屏落脚](m01-v31-d4-mouth.png)

### 西侧回程根索

![M01 回程根索](m01-v31-return-cable.png)

三张 PNG 保存 error=0，zoom 均为 (1.6, 1.6)；日志：`m01-v31-capture.log`。本机窗口实际采集尺寸 1080×608，固定缩放未变化。

## 本次改动文件清单

### 修改

- `game/data/world_regions.json`：仅 M01 记录增加布局版本、房间/锚点及结构元数据；其他 47 区磁盘记录不重排。
- `game/world_data.gd`：布局版本 7、M01 新几何分派、旧潜刺与 VC 加载兼容、时代墙实际地板读取。
- `game/world_game.gd`：固定镜头、观照退役、根索/深度提示、机关墙与巡逻出生读取实际地板。
- `game/input_actions.gd`：移除观照动作注册、默认键位与旧绑定残留。
- `game/map_hazards.gd`：移除潜刺揭示状态，裂纹与近距尘埃。
- `game/chapter_one.gd`：旧坐标迁移与 VC 存档清理。
- `game/pogo_anchor.gd`：删除已退役取景状态引用。
- `tools/build_world.py`：显式 `--m01-slice` 局部编译；无参数不再隐式重建全库，旧全量编译需显式 `--all-regions`。
- `tests/test_map_reconstruction.gd`：从 v2 重写为 v3.1 切片验收。
- `tests/test_m01.gd`：移除 VC 夹具并使用真实地板。
- `tests/test_world_regions.gd`：断桥东岸目标改为实际 64px 下层台地。
- `tests/test_structure_traversal.gd`：支持新井道根索偏移。

### 新增

- `game/map_slice_geometry.gd`（及 Godot `.uid`）：隔离 M01 实体台地与 D4 地形生成。
- `tools/build_m01_slice.py`：可重复的 M01-only 数据编译。
- `tests/map_platform_inventory.gd`（及 `.uid`）：真实平台统计及碰撞摘要。
- `tests/test_m01_slice_traversal.gd`（及 `.uid`）：双时代五房连续物理路线。
- `tools/capture_m01_slice.gd`（及 `.uid`）：真实窗口截图采集与音频资源退出清理。
- 本验证记录、同目录 `m01-v31-*.log`、两份平台 JSON、三张 PNG。

### 删除

- `game/map_view.gd` 及其 `.uid`。

未回滚或覆盖工作区原有未提交更改；未提交 Git。

## 与原方案的差异及待确认

1. 只 M01 启用版本 7 几何分支，保留其他区域旧生成器；这是用户要求的分阶段范围，不代表全库平台目标已经完成。
2. 房间格线元数据与内部实际 `floor_y` 分离，使 224 格线与 D1 64px / D4 512px 同时成立；落差断言读取实际地板，不靠标记伪造。
3. 为保证旧区仍可运行，旧磁盘潜刺记录在加载时转成明刺+裂纹；运行环境无潜刺机制。旧 M02 VC 数据也由加载与交互层兼容，不重建其他区记录。全库数据源清理等待推广阶段。
4. 首屏井口镜头使用井道空间钳制，而不是仍把井口锁在上层房间中心；保持固定缩放，避免落脚被首屏裁掉。
5. 统计基线为 2894 而非交接文档 2896；原始差异保留，待确认文档来源，不做虚假对齐。
6. 人工手柄操作的观感、0.06s 下劈定格与复位手感仍待用户实机确认。当前仅自动化连续物理测试与真实渲染采集通过。

## 重现入口

- Python：`python tools/build_world.py --m01-slice`。
- 平台：Godot `--headless --path . --script res://tests/map_platform_inventory.gd`。
- 断言：Godot `--headless --path . --fixed-fps 60 --script res://tests/test_map_reconstruction.gd`。
- 连续路线：同上改为 `res://tests/test_m01_slice_traversal.gd`。
- 截图：Godot `--path . --script res://tools/capture_m01_slice.gd`（不能使用 headless）。

本机 Python 的 Windows alias 不可用，实际使用已安装的 `C:/Users/Administrator/.workbuddy/binaries/python/versions/3.14.3/python.exe`；Godot 位于 `C:/Users/Administrator/Desktop/Godot_v4.7.2/Godot_v4.7.2-stable_win64_console.exe`。
