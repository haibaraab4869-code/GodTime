# 单图数据契约 `data/wXX.json`

> **29 张图**共用同一份结构（v1.4 起；v1.3 为首版 29 图，v1.2 为 25 张）。**字段名不得改动、不得自创同义字段**，否则下游脚本与 AI 生成器无法统一处理。
> 本契约由主理人维护；单图文档的「§8 AI 可直接实现的参数」必须与本文件一致。

## 字段表

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | string | ✓ | `W01`…`W29`（W26—W29 为 v1.3 升格的四个暗区） |
| `name` | string | ✓ | 中文区名 |
| `chapter` | int | ✓ | 1—8 |
| `role` | string | ✓ | 中枢 / 动脉 / 过渡 / 主题大区 / 准入秘境 / 边界 / 终局 / **暗区** |
| `shape` | string | ✓ | 形状原型（自由文本，与总控一致） |
| `aspect` | string | ✓ | `"3.6:1"` 形式 |
| `size` | `[w,h]` | ✓ | 区域外框 px，必须 `w/h` ≈ aspect |
| `canvas_origin` | `[x,y]` | ✓ | 该区在世界坐标中的左上角 |
| `rooms` | Room[] | ✓ | 房间数组 |
| `links` | Link[] | ✓ | 房间内连接（同一区内的通行关系） |
| `world_links` | WorldLink[] | ✓ | 跨区出入口 |
| `items` | Item[] | ✓ | 道具与收集物 |
| `enemies` | Enemy[] | ✓ | 杂兵 / 远程 / 飞行 / 环境 / 精英 |
| `sprite` | Sprite[] | ✓ | 精灵（不可杀，环境型） |
| `elite_guard` | EliteGuard[] | ✓ | 精怪（可战斗精英，锁门） |
| `boss` | Boss \| null | ✓ | 守印者 / BOSS，无则 `null` |
| `devices` | Device[] | ✓ | 机关（沿用已实现的八类） |
| `challenges` | Challenge[] | 选填 | **平台挑战段**。全作仅 W07/W09/W12 三段有此字段，其余 26 区缺省即 `[]`。规范见总控 §7.5 |
| `flags` | string[] | ✓ | 需持久化的旗标名 |
| `checkpoint` | `{room,pos}` \| `null` | 条件必填 | 灯龛位置。**`role == "暗区"` 时允许 `null`**（v1.3 新增：暗区只有 1—3 房、一道门，不设常驻灯龛，死亡直接回宿主区灯龛）；其余角色必须给出 |
| `grants` | Grant[] | 选填 | **能力取得点段（v1.4 新增）**。全作共 **9 条**、分布在 **8 区**（W06 两条：`P2`+`QS`），其余 21 区缺省即 `[]`。规范见下节 |

### Room

```json
{
  "id": "R01",
  "name": "入口泊位",
  "rect": [0, 0, 512, 384],
  "shape": "矩形",
  "floor_y": 384,
  "era": "both",
  "region": "A 入口段",
  "content": "教学",
  "landmark": false
}
```

- `era`：`both` / `past` / `present`（只在单时代存在的房间必须标，并在文档里说明玩家如何在该房间内切时而不被卡墙）。
- `rect` **不得重叠**；相邻房间的相接边必须完全对齐。
- `landmark` 为 `true` 的房间必须是全高地标所在房。

### Link（区内）

```json
{ "a": "R01", "b": "R02", "side": "E", "kind": "main", "requires": "", "era": "both" }
```

- `kind`：`main` / `branch` / `loop` / `secret`。
- `side`：`N/S/E/W` 或 `V`（垂直井连通）。

### WorldLink（跨区）

```json
{ "side": "E", "room": "R07", "pos": [3840, 208], "to": "W02", "to_room": "R01", "requires": "", "kind": "main" }
```

- `requires` 取值只能是：`""` / 能力代号（`P2` `QS` `PA` `PW` `PG` `DS` `DT` `DB` `VC`）/ 进度旗标（`ENDGAME` `FINAL_DOOR`）。

### Item

```json
{ "id": "I-01", "type": "叙事物", "name": "无姓碑", "room": "R05", "pos": [320, 320], "obtain": "调查", "missable": false, "requires": "" }
```

- `type`：`关键道具` / `永久强化` / `消耗品` / `叙事物` / `凶骨` / `魂魄` / `地图残页`。

### Enemy

```json
{ "id": "E-01", "tier": "杂兵", "name": "纸人", "hp": 45, "rooms": ["R03", "R05"], "count": 6, "era": "both", "respawn": "checkpoint" }
```

- `tier`：`杂兵` / `远程` / `飞行` / `环境` / `精英`。
- **静态危险地形（地刺）也走 `环境` 档**，形态写在 `name` 的括号里：`名称（地刺｜顶刺｜斜刺墙）`，例如 `"name": "阶脚地刺（地刺）"`。规范见总控 §7.4。加一条自检：`tier == "环境"` 且 `name` 含上述三形态之一者，判为静态地刺，必须同时满足「`hp` = 0、`respawn` = `none`、不在 Boss 战场房、所在区不是秘境/过渡/终局」。

### Sprite（精灵）

```json
{ "id": "SPL-01", "name": "纸面灵", "room": "R04", "era": "present", "blocks": "现在态封住主脉", "dispel": "切至过去即不存在", "detour_cost": "过去路线多 2 个房间" }
```

- **跨区单一个体**（选填字段，v1.2 新增）：同一只精灵在相邻两区出现、且两处同为单时代独占时，每个区各留一条实体（因为它真的堵在那儿），但**只有栖息区计入全作总数**。填写方式：
  - `shared_individual`：string，共享标识，同一个个体的所有条目填同一个值；
  - `counted`：bool，默认 `true`；非栖息区填 `false`。
  - 现状两例（计数表见总控 §7.1 表后规则）：潮文灵 `chao_wen_ling` —— W20（R05 写工地，`counted: false`）／W21（R08 栖息处，`counted: true`）；刻齿灵 `ke_chi_ling` —— W23（R04 咬死东门洞，`counted: false`）／W24（R06 湖岸北口，`counted: true`）。全作精灵总数按 `counted: true` 计 = **12**；安抚状态用共享旗标一处记录即对两区生效。

### EliteGuard（精怪）

```json
{
  "id": "ELT-01", "name": "抄手头目", "room": "R09", "arena": [1024, 384],
  "trigger": "进入锁门", "phases": 2,
  "moves": [{ "name": "横扫", "telegraph": 0.4, "window": 0.18, "damage": 2, "dodge": "冲刺", "cd": 2.4 }],
  "weakness": "重击破甲后 1.2s 失衡", "reward": "凶骨 ×1"
}
```

### Boss

```json
{
  "id": "B-01", "name": "报丧鼓将", "room": "R10", "arena": [1280, 512],
  "hp": 240, "stagger": 100, "door_lock": true,
  "phases": [{ "hp_above": 0.5, "new_moves": ["三连鼓"], "terrain_change": "none" }],
  "moves": [{ "name": "地波", "telegraph": 1.0, "window": 0.2, "damage": 2, "dodge": "跳跃/冲刺", "cd": 3.0 }],
  "fairness": { "min_telegraph": 0.3, "no_offscreen_startup": true },
  "on_defeat": { "drop": "章印", "flags": ["w04_boss_down"], "map_change": "封条落下，东门开放" }
}
```

### Device（机关）

```json
{ "id": "D1", "room": "R06", "type": "潮位", "levels": 3, "solution": 2, "flag": "w16_tide_2", "fail_feedback": "水位不对，接收点不响应" }
```

- `type` 只能取已实现的八类：`水路改道` / `潮位` / `风场` / `根系` / `升降平台` / `光路` / `音柱` / `三灵协作`。

### Challenge（平台挑战段 · v1.2 新增）

```json
{
  "id": "CH-01",
  "name": "试风塔外壁·风骨跳",
  "optional": true,
  "count": 6,
  "rooms": ["R08", "R07"],
  "gate": "",
  "steps": [
    { "n": 1, "from": "R08", "to": "R08", "span": 120, "rise": 180, "landing": 96, "era": "both", "requires": [], "note": "单跳即可，落点两态皆可站" },
    { "n": 6, "from": "R08", "to": "R07", "span": 120, "rise": -240, "landing": 128, "era": "present", "requires": ["PA"], "note": "空槽横风把落点东推 96，须空冲逆风修正" }
  ],
  "fail": "落塔基安全带，不掉血，不重置已通过段数",
  "reward": ["I-14", "I-15"],
  "reward_note": "",
  "era_note": "现在态读结构、过去态站缺口；2 处断口只在过去态可站，末段横风只在现在态成立"
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | `CH-01` |
| `name` | string | 段名 |
| `optional` | bool | 是否为可选支线。**三段恒为 `true`**（总控 §7.5 第 3 条） |
| `count` | int | 段数，必须等于 `steps` 长度 |
| `rooms` | string[] | 起止与经过房间（去重） |
| `gate` | string | 前置旗标；无则 `""`。W12 填 `"w12_pw_tutorial_3"`（未完成三阶教学则第 2 段滑落） |
| `steps[].span` | int | 跨度 px |
| `steps[].rise` | int | 高差 px，**正数为上升** |
| `steps[].landing` | int | 落点宽度 px |
| `steps[].era` | string | 该段**必须**在哪个时代完成：`both` / `past` / `present` |
| `steps[].requires` | string[] | 该段需要的能力代号；无则 `[]` |
| `fail` | string | 失败处理（**一律不致死、不送回检查点**） |
| `reward` | string[] | 物品 id 列表；捷径类段填 `[]` |
| `reward_note` | string | 捷径类回报的文字说明（如 W12「省 R11 一房、约 35—45s」） |
| `era_note` | string | 双时代读法说明 |

### Grant（能力取得点 · v1.4 新增）

```json
"grants": [
  { "ability": "P2", "room": "R13", "pos": [960, 500], "era": "past", "radius": 48, "label": "燧羽穗", "text": "巢口垂着一穗燧羽。握住它，第二口气就留在脚下了。" }
]
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ability` | string | ✓ | 能力代号，白名单 `VC/P2/QS/PA/PW/PG/DS/DT/DB`，**全作每个代号恰好出现一次** |
| `room` | string | ✓ | 该区真实房号（`rooms[].id`） |
| `pos` | `[x,y]` | ✓ | **区局部画布坐标**，与 `items[].pos` / `interactions[].at` / `checkpoint.pos` 同一坐标系（非世界坐标） |
| `era` | string | ✓ | 取得所需时代：`past` / `present` / `both` |
| `radius` | int | ✓ | 交互半径 px，取值 40—64；**接触即取**用 48，**需要主动交互**（调查/祭台/剥取/校准）用 56 |
| `label` | string | ✓ | 世界内交互名（HUD 短名，4—5 字，不解释机制） |
| `text` | string | ✓ | 一句取得文案，**≤40 字**；遵循项目文案规范：只给世界内的说法，不解释机制、不写数值 |
| `auto` | bool | — | 选填，默认 `false`。`true` = 触碰即取：进入 `radius` 即发放，不弹面板、不需按 E（文案仍进日志）。**只允许 `PW` 使用**（w12 §3.2「接触即取、无输入要求」）；给其他代号加 `auto` 会静默改变手感，转换器直接报错 |

- 坐标是**取得判定点**，不是物件贴图锚点：必须落在该房 `rect` 内，四边各留 ≥20px（玩家碰撞体半宽），不得贴墙、不得悬空；例外仅 `DS` 的鳞台（台面高 56，原设计）。
- `grants` 与 `checkpoint`、`challenges` 并列，**新键一律追加在 `checkpoint` 之后**，不得重排既有键序。
- 权威清单（含逐条说明、坐标依据、取得前可进可出复核、来源行号）见 **`../ability-grants.md`**；本契约只固定结构，不复制清单内容。
- **不改 `rooms[].rect` / `size` / `canvas_origin`**：29 区是精确铺满的，任一 `rect` 变动都会破坏铺满与共边门位。

## 校验要求（交付前自检）

1. `rooms` 内 `rect` 两两不重叠；相接边对齐；所有 `rect` 落在 `size` 内。
2. `links` 无悬空 `id`；主脉从入口房到出口房连通。
3. `world_links.to` 必须是总控里真实存在的邻接区，且方向与总控一致。
4. 每个 `requires` 非空的世界连接，必须在总控 §5 能力门闭环表里找得到对应项。
5. `checkpoint.room` 必须是可站立房间，且不在锁门的战场房内。**例外**：`role == "暗区"` 时 `checkpoint` 允许为 `null`；非 null 时同样受本约束。
6. `flags` 覆盖：灯龛、一次性奖励、机关档位、Boss/精怪击破、跨区门开启。
7. **挑战段**（若有 `challenges`）：`count` 必须等于 `steps` 长度；`steps[].n` 从 1 连续编到 `count`；`from` / `to` / `rooms` 必须都是本区真实房号；`era` ∈ `both/past/present`；`requires` 取值合法；`optional` 必须为 `true`。
8. **静态地刺**：`tier == "环境"` 且 `name` 含 `（地刺）`/`（顶刺）`/`（斜刺墙）` 的条目，须满足 `hp == 0`、`respawn == "none"`、不在 Boss 战场房、所在区不是秘境/过渡/终局/暗区。全作处数合计应为 **18**。
9. **精灵计数**：各区 `sprite` 中 `counted != false` 的条数之和，必须等于 `data/world-25.json` 各 `encounters.sprite` 之和（= **12**）。`shared_individual` 相同的条目跨区共享安抚状态。
10. **暗区（v1.3）**：`role == "暗区"` 的图必须满足——① 房间 1—4；② `world_links` 恰好 1 条（叶子，度数 1）；③ `boss` 为 `null` 或 `""`；④ `elite_guard` 为 `[]`；⑤ `sprite` 为 `[]`；⑥ `chapter` 与其宿主区同章，且宿主区（`world_links[0].to`）在本区所在章内。
11. **房间总数**：29 张图的 `rooms` 条数之和必须为 **320**（升格前后不变；已计入 `data/world-25.json` 各 `rooms_est`）。
12. **能力取得点（v1.4）**：`grants` 若存在，须同时满足——
    - ① **9 个能力各恰好出现一次**：29 图 `grants[].ability` 的并集 = `VC/P2/QS/PA/PW/PG/DS/DT/DB`，无缺项、无重复，合计 **9 条 / 8 区**；
    - ② `room` 必须是**本区真实房号**；
    - ③ `pos` 必须落在该房 `rect` 内且四边余量 ≥ **20px**（玩家碰撞体半宽；`DS` 鳞台 56 高是唯一原设计例外，其判定点距地面 56px，仍在房内）；
    - ④ `era` ∈ `past/present/both`，且 `radius` ∈ 40—64、`label` 非空、`text` ≤40 字。

以上 1—12 由 `tools/verify_map_specs.py` 机检（v1.4 起新增第 12 条 `grants` 检查）；交付前基线为 **CONCERNS · 0 项错误 / 2 项警告**（两条 W03 窄接边为既有误报，不得为消警告而改 W03）。

## 版本记录

| 版本 | 日期 | 变更摘要 |
| --- | --- | --- |
| v1.2 | 2026-10-30 | 新增 `challenges` 平台挑战段契约（全作 3 段 / 3 区）；`sprite` 增 `shared_individual` / `counted`（跨区单一个体计数规则，精灵总数按 `counted: true` 计 = 12） |
| v1.3 | 2026-10-30 | 25 → **29 图**（W26—W29 四个内嵌暗区升格为独立区，房间总数仍 320）；新增「暗区」`role` 档，允许 `checkpoint: null`；新增校验要求 10（暗区六条） |
| v1.4 | 2026-11-02 | **新增 `grants` 能力取得点段**：顶层数组，9 条 / 8 区（W06 两条 `P2`+`QS`），字段 `ability/room/pos/era/radius/label/text`；新增校验要求 12（白名单各一次 / room 有效 / pos 在房内且余量 ≥20px / era 合法 / radius 40—64 / text ≤40 字）；新增 §Grant 字段表与 `../ability-grants.md` 权威清单。起因：29 区替换后 9 个探索能力在运行时无取得入口（`world_regions.json` 的 `ability` 全为空、`interactions` 无 `world_ability`），第二章 `P2` 门会卡死 |
