# 地图文档入口

> **状态：29 区规格已全量批准（v1.3，2026-10-30）。** 旧地图文档体系（48 区竖向骨架、镜头取景、结构重排表、世界地图、纵向地图、地图集与镜头、三灵地图重构等）已于 2026-10-30 按用户指令整体清空并作废，无法从 git 恢复。本目录现有**一套完整的替代规格**：1 份世界总控 + 29 份单图文档 + 29 份机器可读 JSON + 1 张世界坐标总表。旧 48 区仅作为 `game/data/world_regions.json` 里的待替换实现存在，**不是设计依据**。

---

## 一、要替换 `game/` 里的旧 48 区地图，按这个顺序读

**只读一份不够**——总控给拓扑与规则，世界坐标表给拼图，JSON 给机器可读的唯一数据源，单图文档给"为什么这么排"。推荐的交接顺序如下（**本节只是阅读顺序，不含任何代码改动**）：

| 步 | 读什么 | 要拿走的东西 | 为什么先读它 |
| --- | --- | --- | --- |
| 1 | [`world-map-25.md`](world-map-25.md) | 29 区拓扑、章节配额 `5/3/4/3/4/3/3/4`、角色档（含「暗区」）、能力门闭环、两条进度门、敌人六档、道具体系、§7.4/§7.5 两类环境规范 | 它是全部 29 份单图的上游。**不看它就看不懂单图为什么这么排房间**（W06 为什么要 18 房、W25 为什么不能写成下坠、暗区为什么允许没有灯龛） |
| 2 | [`_world-coordinates.md`](_world-coordinates.md) | 每区 `canvas_origin`、四边世界矩形、**每条跨区接口的两侧门位世界坐标** | 这是"把 29 张图拼成一张世界图"的唯一权威表。拼错了，镜头、存档定位、地图 UI 全错 |
| 3 | [`data/world-25.json`](data/world-25.json) | 29 个 region 的元信息（`id`/`name`/`chapter`/`role`/`size`/`rooms_est`/`links`/`encounters`）、36 条边 | 机器可读的世界级索引。工程侧生成 `world_regions.json` 时**以它为骨架** |
| 4 | [`data/wXX.json`](data/) × 29 | 每区 `rooms`/`links`/`world_links`/`items`/`enemies`/`boss`/`devices`/`flags`/`checkpoint` | **机器可读的唯一数据源**。字段契约见 [`data/_schema.md`](data/_schema.md) |
| 5 | `w01-*.md` … `w29-*.md` × 29 | 每区主题、地形意图、双时代差异、技能应用点、Boss 招式表、验收清单 | 给"JSON 里放不下的设计意图"。**改某个区之前必须读那一份**，否则会把设计意图实现成纯数值 |

**三条硬规矩**：

1. **JSON 与单图文档冲突时以 JSON 为准**（它是唯一机器可读源）；但 **JSON 与总控冲突时以总控为准并回改 JSON**——总控是规则层。
2. **不要手改单份 JSON 的坐标**：跨区门位由 [`../../tools/build_world_coords.py`](../../tools/build_world_coords.py) 统一求解，手改会让共边两侧错位。改拓扑请改生成器里的 `CHAIN` / `BRANCH` 再重跑。
3. **动手前的基线自检**：`python tools/build_world_coords.py` 与 `python tools/verify_map_specs.py` 必须都是 0 错误（见第四节）。

---

## 二、目录索引

| 路径 | 内容 | 性质 |
| --- | --- | --- |
| [`world-map-25.md`](world-map-25.md) | **世界总控 v1.3**：29 区拓扑、章节骨架、能力门、敌人与道具体系、两类环境规范 | ✅ 已批准，上游依据 |
| [`_world-coordinates.md`](_world-coordinates.md) | **世界坐标总表**：29 区原点与四边矩形、29 条共边 + 7 条跨空接口的逐条门位 | ✅ 生成物，勿手改 |
| [`data/world-25.json`](data/world-25.json) | 世界级 JSON（文件名沿用 `world-25`，自 v1.3 起内容为 29 区） | ✅ 机器可读，唯一世界索引 |
| [`data/_schema.md`](data/_schema.md) | 单图数据契约 v1.3（含「暗区」档、`checkpoint: null` 合法性、11 条校验要求） | ✅ 契约，不得自创字段 |
| `data/w01.json` … `data/w29.json` | 29 份单图 JSON | ✅ 机器可读，唯一数据源 |
| [`_template-w-map.md`](_template-w-map.md) | 单图文档模板（0—9 节） | 📐 模板 |
| [`_audit-hazard-platforming.md`](_audit-hazard-platforming.md) | 环境危害与平台挑战专项审计（作为反证材料保留） | 📎 参考 |
| [`reference/hollow-knight/`](reference/hollow-knight/README.md) | 《空洞骑士》全图 + 15 张区域拆解图、浏览页 | 📎 外部参考，非规格 |

- 参考素材的入口：[参考索引](reference/hollow-knight/README.md) · [浏览页](reference/hollow-knight/index.html)。它只提供形状原型与结构规律，**不构成设计依据**。
- `reference/` 下已放 `.gdignore`，Godot 不导入；其中 675 MB 原始 PNG 不建议纳入版本库（见仓库 `.gitignore`）。

### 29 份单图文档

| 章 | 区 | 角色 | 房 | 文档 |
| --- | --- | --- | --- | --- |
| 1 | W01 刻漏津渡 | 过渡（教学长廊） | 7 | [`w01-kelou-jindu.md`](w01-kelou-jindu.md) |
| 1 | W02 双版市廛 | 中枢（唯一网） | 17 | [`w02-shuangban-shican.md`](w02-shuangban-shican.md) |
| 1 | W03 城簿廊与寄信井 | 主题大区 | 15 | [`w03-chengbu-jiixinjing.md`](w03-chengbu-jiixinjing.md) |
| 1 | W04 鼓楼封粮门 | 边界（城缘关隘） | 12 | [`w04-gulou-fengliangmen.md`](w04-gulou-fengliangmen.md) |
| 1 | **W26 无姓者墓园** | **暗区** | 2 | [`w26-wuxingzhe-muyuan.md`](w26-wuxingzhe-muyuan.md) |
| 2 | W05 灰羽焚田 | 过渡（横向） | 8 | [`w05-huiyu-fentian.md`](w05-huiyu-fentian.md) |
| 2 | W06 鸾巢医舍 | 主题大区 | 18 | [`w06-luanchao-yishe.md`](w06-luanchao-yishe.md) |
| 2 | W07 反焚鸾台 | 准入秘境 | 7 | [`w07-fanfen-luantai.md`](w07-fanfen-luantai.md) |
| 3 | W08 浮桥逐日 | 过渡（悬索） | 7 | [`w08-fuqiao-zhuri.md`](w08-fuqiao-zhuri.md) |
| 3 | W09 无翼试风庭 | 主题大区 | 17 | [`w09-wuyi-shifengting.md`](w09-wuyi-shifengting.md) |
| 3 | W10 风葬关 | 边界（山风关隘） | 9 | [`w10-fengzangguan.md`](w10-fengzangguan.md) |
| 3 | **W27 藏风坳** | **暗区** | 3 | [`w27-cangfeng-ao.md`](w27-cangfeng-ao.md) |
| 4 | W11 负石悬棺道 | 过渡（山前长坡） | 7 | [`w11-fushi-xuanguandao.md`](w11-fushi-xuanguandao.md) |
| 4 | W12 天倾井 | 动脉（纵） | 20 | [`w12-tianqing-jing.md`](w12-tianqing-jing.md) |
| 4 | W13 无钟回音室 | 准入秘境 | 7 | [`w13-wuzhong-huiyinshi.md`](w13-wuzhong-huiyinshi.md) |
| 5 | W14 盐海焚舟岸 | 主题大区 | 16 | [`w14-yanhai-fenzhouan.md`](w14-yanhai-fenzhouan.md) |
| 5 | W15 赤潮观测塔 | 过渡（竖向） | 5 | [`w15-chichao-guanceta.md`](w15-chichao-guanceta.md) |
| 5 | W16 焰海盐宫 | 主题大区 | 17 | [`w16-yanhai-yangong.md`](w16-yanhai-yangong.md) |
| 5 | **W28 溺火石碑** | **暗区** | 1 | [`w28-nihuo-shibei.md`](w28-nihuo-shibei.md) |
| 6 | W17 白骨千名廊 | 动脉（横） | 18 | [`w17-baigu-qianminglang.md`](w17-baigu-qianminglang.md) |
| 6 | W18 未封之口 | 准入秘境 | 8 | [`w18-weifeng-zhikou.md`](w18-weifeng-zhikou.md) |
| 6 | W19 归墟议冢 | 中枢（脊柱） | 18 | [`w19-guixu-yizhong.md`](w19-guixu-yizhong.md) |
| 7 | W20 息壤书岸 | 主题大区 | 16 | [`w20-xirang-shuan.md`](w20-xirang-shuan.md) |
| 7 | W21 海眼审录庭 | 主题大区 | 17 | [`w21-haiyan-shenluting.md`](w21-haiyan-shenluting.md) |
| 7 | W22 墨海下层 | 准入秘境 | 8 | [`w22-mohai-xiaceng.md`](w22-mohai-xiaceng.md) |
| 8 | W23 八门汇流厅 | 终局（门厅） | 13 | [`w23-bamen-huiliuting.md`](w23-bamen-huiliuting.md) |
| 8 | W24 司历心湖 | 主题大区 | 17 | [`w24-sili-xinhu.md`](w24-sili-xinhu.md) |
| 8 | W25 未删的明日 | 终局（最终场） | 8 | [`w25-weishan-de-mingri.md`](w25-weishan-de-mingri.md) |
| 8 | **W29 不曾发生的春天** | **暗区** | 2 | [`w29-buzeng-fasheng-de-chuntian.md`](w29-buzeng-fasheng-de-chuntian.md) |

> 合计 **320 房 / 29 区**。四个暗区编号排在主干之后，但**章节归位在第 1 / 3 / 5 / 8 章**。

---

## 三、与实现的关系

`game/data/world_regions.json` 是当前唯一的运行时地图数据，已按本目录规格**全量替换**为 **29 区 / 320 房 / 36 边**（`version: 7`）。旧的 48 区数据与 `game/regions/m01…m48.tscn`、`game/m01_layout.gd` 已删除，`M` 前缀不得再出现在新代码里。

- 运行时文件由 `python tools/build_runtime_world.py` 生成，**不要手改** `game/data/world_regions.json`。
- **替换的起点是 `data/world-25.json` + `_world-coordinates.md`**：先用它们生成一张 29 区的世界骨架（区 → 画布原点 → 四边接口），再把 29 份 `data/wXX.json` 逐个填进各自的 `canvas_origin` 框。
- 单图文档（`wXX-*.md`）不直接喂引擎，它是"为什么这么填"的解释层；引擎只吃 JSON。
- **不得以现有实现反推规格**：`game/` 侧只允许跟随本目录，冲突时以设计目录为准。

---

## 四、自检与生成命令

```bash
python tools/build_world_coords.py   # 求解世界坐标 + 回写 29 份 JSON 的 canvas_origin/world_links + 重写 _world-coordinates.md
python tools/verify_map_specs.py     # 规格校验：房间数/邻接/门位/Boss/灯龛/地刺/精灵/挑战段/暗区
```

两个脚本都必须 **0 错误**。当前基线：

```
合计房间 320（总控 320）
静态地刺 18 处 / 11 区（共 73 根）
精灵计数 12（含 4 条跨区同个体实体）
跨区接口 29 条共边 / 7 条跨空连接，门位不重合 0 处
平台挑战段 16 段 / 3 区
=== CONCERNS · 0 项错误，2 项警告 ===
```

两条警告都是 W03 `R05↔R09` / `R09↔R14` 相接边 <48px 的既有误报，不影响门位与通行。
