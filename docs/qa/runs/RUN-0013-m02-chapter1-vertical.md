# RUN-0013 · 第01章竖向推广：M02 首区

日期：2026-10-29。仅施工 M02；M01 不重做，M03–M06 等待确认。

## 数据依据

按用户顺序读取 `chapter1-vertical-plan.json`、竖向重排表、`level-flow-chapter-one.md`、`feature-map-reconstruction.md`。数值取 JSON；没有读取旧 tier 来推配额。编译时从真实组底边计算落差，再用 JSON bands 分类。

M02 四组的矩形底边和实际物理地板均为 448 / 544 / 992 / 1696；横向同组地板一致。

| 链接 | 房间 | 实际落差 | 几何等级 | 浮台 | 回程辅助 | cue |
| --- | --- | --- | --- | --- | --- | --- |
| 2 | 1→4 | 96 | D1 | 0 | false | 空 |
| 4 | 2→5 | 96 | D1 | 0 | true | 空 |
| 6 | 4→6 | 448 | D3 | 0 | false | 空 |
| 7 | 5→7 | 448 | D3 | 0 | false | 空 |
| 10 | 8→9 | 704 | D4 | 1 | false | cable |

实际 distinct_drops=[96,448,704]，与 JSON 严格一致。704 井宽128，贯穿灰色垂索，唯一落脚在井口下256，首屏可见。不新增深井回程索。M02 磁盘 ability 清为空，不仅靠运行时兼容。

## 实测浮台及未施工区

口径为真实 `WorldData.model(id).platforms.size()`；含旧版本锚点垫台，实体地板不计。用户基线与本次施工前工作区存在差异，不以文档数替代实测。

| 区域 | 用户给定基线 | 本轮实测改前→改后 | 实际落差集合 | JSON 目标 | 状态 |
| --- | --- | --- | --- | --- | --- |
| M02 | 65 | 69→1 | [96,448,704] | [96,448,704] | 通过，预算≤3 |
| M03 | 64 | 70→70 | [512] | [192,384,448,704,768] | 未施工，不宣称符合 |
| M04 | 49 | 54→54 | [512] | [224,416,448,512] | 未施工，不宣称符合 |
| M05 | 49 | 50→50 | [512] | [192,320,480,608] | 未施工，不宣称符合 |
| M06 | 62 | 64→64 | [512] | [128,384,512,640] | 未施工，不宣称符合 |

全库平台 2848→2780。M01 仍2块；47个非M02区域逐区平台数和基础碰撞hash均不变。原始证据 `m02-ch1-platforms-before.json` / `m02-ch1-platforms-after.json`。

## 自动化

Godot 4.7.2，固定60FPS：

- `test_m02_vertical`：95项，0失败。逐条组底边/落差/几何分档/配额/cue/回程索/自然锚点支撑、零VC/强制下劈、首屏落脚实际相机可见、井道上下中固定zoom及角色可见。
- 同测试双时代连续基础移动路线：入口→上街横越第一井口→96台地→机关控制器→448井→旧市横廊→704井→M03出口；未解锁 P2/PA/PW/PG，无中途传送。为隔离地形验证，设置因果锁进度2，敌人停物理；不是完整剧情游玩验收。
- 规定8项回归全过：`test_attack`、`test_input`、`test_input_feel`、`test_chapter_one`(199)、`test_m01`(17)、`test_pogo_routes`(47真实链)、`test_world_regions`(1333)、`test_structure_traversal`(48真实攀升)。
- 额外回归：`test_map_reconstruction`(3133)、`test_m01_slice_traversal`(36)、`test_m03_camera`(6)、`test_mythic_maps`(1305)、`test_mythic_environment`(498)、`test_mythic_traversal`(50)，全部0失败。重构断言总数由3137变3133，原测试按运行危险物/交互循环计数，本次移除M02旧下劈危险物后自然减少；未修改该测试文件。
- M02编译幂等 PASS；其他47区模型不变 PASS；本次代码诊断0。
- 日志在本目录 `m02-ch1-*.log`。

## 实机截图

Windows有窗口Godot，D3D12 Forward+，RTX4080SUPER真实渲染。采样时停角色/敌人物理、禁用存档，非人工操作手感验收。实际zoom均(1.6,1.6)，PNG保存error=0，退出码0。

![M02 704井口及首屏落脚](m02-ch1-mouth.png)

![M02 704井中及底层出口岸](m02-ch1-inside.png)

## 本次改动文件

修改：
- `game/data/world_regions.json`：仅M02记录，组底边、VC清理、链接几何分档/配额、cue、交互与边界同步，清除该区旧强制下劈填充。
- `game/map_slice_geometry.gd`：支持显式ceiling_y、shaft_offset和逐链接cue；旧M01使用原默认值，碰撞hash不变。

新增：
- `tools/build_m02_slice.py`：仅M02的幂等编译。
- `tests/test_m02_vertical.gd`及引擎生成uid。
- `tools/capture_m02_vertical.gd`及引擎生成uid。
- 本记录、两份平台JSON、两张PNG、测试/截图日志。

未修改镜头、`player.gd`的pogo闭合逻辑或`map_hazards.gd`的伤害/安全点逻辑，未修改M01、M03–M06数据。未覆盖原工作区已有修改，未提交Git。

## 保守处理 / 待确认

1. D2=1与“≤450连接零浮台”冲突。本轮M02无D2，不影响；M03–M06含D2时需确认，未自行定规则。
2. 96px上下组的房间矩形沿用224高，矩形会重叠。下层实际净空采用64px，保留32px实体分层，避免把上层地板挖掉；同组底边绝对不偏移。两条448井口向左错开128，以免96+448连成一次544坠落；数值落差、宽度/配额不变。净空观感待用户确认，不新增平台机制。
3. 保留原有两份旁龛奖励，移动到实体支撑处，不凭计划niches=1删奖励；是否合并待确认。
4. 旧存档全局布局版本仍7（本轮不触发全库迁移）。现有加载流程对实体内出生会回到安全spawn，checkpoint_at会重设具名rest；未引入新的区域存档版本。极端旧魂魄掉落坐标若受重排影响的专项迁移待确认。
5. M03的768四重深度提示严格延期，不在本轮实现。第01章其他区域旧强制下劈也不在本轮批量清理：只保证已施工M02 pogo_gates=0。

重现：`python tools/build_m02_slice.py`；Godot `--headless --path . --fixed-fps 60 --script res://tests/test_m02_vertical.gd`；截图使用非headless `--script res://tools/capture_m02_vertical.gd`。
