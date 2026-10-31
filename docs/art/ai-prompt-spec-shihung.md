# 主角「时衡」出图提示词方案（本地 ComfyUI）

> 状态：**草案 v1**（2026-10-29）。适用对象：主角 `shihung` 的概念图与 2D 序列帧动画参考。
> 上游依据：[美术圣经](art-bible.md) §2（视角分层、水墨简化、2.8 头身、配色）、§3（角色设定）、§5（11 项动画）；
> [资产登记](asset-manifest.md) §4.1（AI 不产出骨骼，正式资产由 `gen_parts.py` 程序化绘制）。
> **本文只解决「怎么用文生图把美术圣经的规格翻译成像素」**，不改变任何已确认的美术决策。
> 所有参数均来自本机实测（8 张对照图，附录 A），标「实测」的结论可直接复核。

---

## 0 一句话结论

`Illustrious-XL-v2.0` + `qsuimo-000005` **LoRA 权重 0.60–0.75** + 水墨 tag 组合，可以稳定出到「侧视、焦墨平涂、纸白底、赭金点线」的时衡概念图；
**序列帧不要指望 AI 逐帧生成**——一图多帧会比例/视角/风格各走各的，逐帧 img2img 则是低 denoise 只改线条不改姿势、高 denoise 形色同崩（§12.1，8 张对照实测）。
现行路线：**AI 只出一次母版，运动由程序化位移场合成**（§12），12 帧 idle 已过全部一致性断言，循环闭合差 = 0。最终入游戏仍以 `gen_parts.py` 骨骼链路为准。

---

## 1 环境与硬事实（先确认，别猜）

| 项 | 值 | 说明 |
| --- | --- | --- |
| ComfyUI | `E:\ComfyUI_portable\ComfyUI\main.py`，端口 8188，v0.42.1 / torch 2.14+cu130 | 本机 RTX 4080 SUPER 16 GB |
| 底模 | `SDXL\Illustrious-XL-v2.0.safetensors`（6.6 GB） | 必须写全子目录，写错只报 `invalid prompt` |
| LoRA | `角色卡\qsuimo-000005.safetensors`（162.6 MB，SDXL rank 档） | 同上 |
| 备用底模 | `SDXL\NoobAI-XL-v1.1.safetensors` | 仅当 Illustrious 出不来再试，tag 体系同源 |
| **无** ControlNet | `models/controlnet` 为空 | 所以没有 OpenPose/Depth 硬控姿态 |
| **无** AnimateDiff / IPAdapter | `custom_nodes` 只有 KJNodes、essentials | 所以没有帧间时序一致性节点 |
| **无** 动画相关节点 | — | 序列帧一致性只能靠 seed / img2img / 后期计算 |

> **这三条「无」是整个方案的地基**：没有姿态控制网络，就意味着「同一个角色的不同姿势」只能靠图生图往母版上贴，不能靠骨架驱动。任何声称「一图生成 8 帧循环」的提示词在这种环境下都不可复现。

---

## 2 美术圣经 → 提示词词元对照表

这张表是本文的核心。左列是**必须守住的规格**，右列是**模型能听懂的词**。改提示词前先回来对一遍。

| 美术圣经规格 | 出处 | 提示词词元 | 备注 |
| --- | --- | --- | --- |
| 2.8 头身（目标 3） | §2.3 | `chibi, super deformed, 3 heads tall` | 三个词要一起给；只写 `chibi` 会跑到 2.2 头身 |
| 横版侧视，朝 +x（右） | §2.1 | `side view, profile, facing right` | 再加 `front view` 到负向，否则 30% 概率给正面 |
| 只露一只眼 | §2.1 | `half-closed eyes` + 负向 `both eyes visible` | `one eye` 无意义，模型不认；靠 profile + 负向兜 |
| 中性少年神祇 | §3.2 | `androgynous young boy` | 写 `boy` 会偏幼，写 `shota` 会偏黄，别用 |
| 焦墨发 `#13110F` | §2.4 | `black hair, bob cut` | hex 不认，用色名 |
| 重墨袍 `#221F1C` | §2.4 | `dark grey long robe, wide sleeves, crossed collar` | `dark grey` 比 `black` 稳：`black` 会吃掉墨色层次 |
| 宣纸白 `#F8F0E3` | §2.4 | `cream paper background, plain background` | 顺手当抠图色键（见 §7.3） |
| 古金 `#C69E2C` | §2.4 | `gold trim, gold sash` | 金色面积要控制，多写一条就多一片金 |
| 三尖金冠 | §3.3 / §2.7 | `small three-pronged gold crown` | **实测不稳**（多给 5–8 尖），见 §9 坑 ③ |
| 眉间朱砂 | §3.3 | `vermilion dot on forehead` | 侧视下常被刘海盖住，需 `forehead visible` |
| 左腰两条金垂带 | §2.7 | `two short gold ribbons hanging at waist` | **别写 `long`**，会变成满地金带（实测） |
| 赤足 | §3.3 | `bare feet` + 负向 `shoes` | — |
| 后拖袍摆 | §2.7 | `long trailing robe hem behind` | 这是侧视剪影的不对称来源，必须写 |
| 水墨简化 | §2.2 | `ink wash painting, sumi-e, flat color, thick ink outline, limited palette` | 这五个是风格命门，缺一个就滑向赛璐璐 |
| 禁用渐变/高饱和 | §2.4 | 负向 `gradient, oversaturated, cel shading` | 平涂靠负向守 |

**风格为什么能压住 LoRA 的二次元底子**：`qsuimo-000005` 是「角色卡」类 LoRA，本身带强烈的日系 Q 版倾向。实测 0.65 权重下，只要 `ink wash painting, flat color, limited palette` 三个词在位，出图仍然是焦墨平涂 + 纸白，不会变成彩色赛璐璐；一旦把这三个词删掉，立刻回落到动漫上色。**风格词与 LoRA 权重是拉锯关系，不是叠加关系。**

---

## 3 概念图提示词（可直接复制）

### 3.1 分层结构

按七层写，顺序不要乱——Illustrious 对靠前的 token 权重更高，把「体型」和「视角」放前面，才能压住 LoRA 自带的比例。

```
[L1 质量] masterpiece, best quality, amazing quality, very aesthetic,
[L2 体型] chibi, super deformed, 3 heads tall, full body, solo,
[L3 视角] side view, profile, facing right,
[L4 姿态] standing, standing straight, feet on ground,
[L5 角色] androgynous young boy, short black hair, bob cut, half-closed eyes,
          small three-pronged gold crown, vermilion dot on forehead,
[L6 服饰] dark grey long robe, wide sleeves, crossed collar, gold trim,
          gold sash, two short gold ribbons hanging at waist, bare feet,
          long trailing robe hem behind,
[L7 风格] ink wash painting, sumi-e, flat color, thick ink outline,
          limited palette, black and gold,
[L8 背景] blank background, empty background, plain cream paper background, no shadow
```

### 3.2 概念图 A：侧视站姿全身（母版，最重要）

```text
masterpiece, best quality, amazing quality, very aesthetic, chibi, super deformed, 3 heads tall, full body, solo, standing, standing straight, side view, profile, facing right, feet on ground, androgynous young boy, short black hair, bob cut, half-closed eyes, small three-pronged gold crown, vermilion dot on forehead, dark grey long robe, wide sleeves, crossed collar, gold trim, gold sash, two short gold ribbons hanging at waist, bare feet, long trailing robe hem behind, ink wash painting, sumi-e, flat color, thick ink outline, limited palette, black and gold, blank background, empty background, plain cream paper background, no shadow
```

**这张图是全流程的锚**：后续每一帧的 img2img 都用它当 init，所以它必须过审（比例、朝向、金饰位置、剪影不对称全部对）。不过审就重抽，不要指望后期修。

### 3.3 概念图 B：剪影与色板验证

同 A 的提示词，只改两处：`full body` → `full body, in silhouette`，并删掉 `ink wash painting` 系列。用途：在 58 px 屏上尺寸下确认「三尖冠 / 前伸鼻尖 / 后拖袍摆 / 腰垂带」四个识别锚点还站得住（对应美术圣经 §2.7）。这不是出图给玩家看的，是给美术评审看的。

### 3.4 概念图 C：三视图设定表

```text
masterpiece, best quality, chibi, super deformed, 3 heads tall, character sheet, turnaround, front view, side view, back view, three views of the same character, full body, standing, androgynous young boy, short black hair, bob cut, small three-pronged gold crown, vermilion dot on forehead, dark grey long robe, wide sleeves, gold trim, gold sash, two short gold ribbons, bare feet, ink wash painting, sumi-e, flat color, thick ink outline, limited palette, black and gold, blank background, plain cream paper background
```

分辨率用 **1024×1024**（正方形才装得下三栏），负向加 `different characters, inconsistent size`。
**注意**：三视图只用于「设定沟通」，不用于切图。实测多视图出图的比例一致性不足（附录 A-3），切出来的部件没法绑骨骼——这一点和美术圣经 §4.1 的结论一致，不是新问题。

---

## 4 负向提示词（三档，按需组合）

### T1 通用质量档（永远带着）

```text
worst quality, low quality, lowres, jpeg artifacts, blurry, bad anatomy, bad hands, extra fingers, extra limbs, deformed, watermark
```

### T2 结构铁律档（概念图必带）

```text
multiple views, character sheet, border, frame, cropped, text, chinese text, japanese text, kanji, calligraphy, inscription, lettering, signature, red seal, stamp
```

> **这一档是实测换来的**：水墨 tag 会强烈诱发「题跋 + 朱印」的国画构图，早期 4 张里有 3 张右侧被写上书法。补上 `chinese text, kanji, calligraphy, inscription, red seal` 后（附录 A-7），书法消失。**不写这串，每张都要手工裁掉右侧 1/6。**

### T3 风格污染档（序列帧必带，概念图可选）

```text
3d, cgi, photorealistic, render, gradient, airbrush, cel shading, oversaturated, realistic proportions, adult, long legs, tall, front view, facing viewer, both eyes visible, shoes, trousers, background scenery, black swirl, extra ribbons
```

`black swirl` 是实测项：不写它会给你一个占满画面的墨色旋涡（附录 A-1），虽然好看，但作为母版无法抠图对齐。

### 不要写的负向词

`ugly` `evil` `bad` `worst`（除 `worst quality`）——这些词在 SDXL 上几乎无效，只会占用 token 预算，稀释真正起作用的词。

---

## 5 参数表

### 5.1 概念图

| 参数 | 值 | 依据 |
| --- | --- | --- |
| 分辨率 | 832×1216（竖） | SDXL 原生 1024 档的等比近似；竖构图给袍摆留空间 |
| LoRA 权重 | **0.65**（可 0.60–0.75） | 实测 §5.3 |
| steps | 28–30 | — |
| CFG | 5.0–5.5 | Illustrious 甜区；≥7 会硬化出黑边 |
| sampler | `dpmpp_2m` | 跨 seed 更稳；`euler_ancestral` 适合探索期出多样稿 |
| scheduler | `karras`（配 dpmpp_2m）/ `normal`（配 euler_a） | — |
| seed | 固定，记在文件名里 | 母版 seed 必须留档，后续 img2img 续用 |

### 5.2 序列帧

| 参数 | 值 | 依据 |
| --- | --- | --- |
| 分辨率 | **与母版完全一致**（832×1216） | 实测：一换画幅，角色占画比例就变，后面的归一化全废 |
| LoRA 权重 | **0.75**（比概念图高） | 权重越高，跨帧的服饰/发/冠越不容易漂 |
| 采样 | 同概念图 | 采样器一变，墨线粗细就变 |
| denoise | 见 §7.2 表 | 分片段给值，不给单一值 |
| batch | 1 张/次 | 批量只适合探索，不适合成序列 |

### 5.3 LoRA 权重实测对照（同 seed 20261029，同提示词）

| 权重 | 头身比 | 姿态服从度 | 主要问题 | 结论 |
| --- | --- | --- | --- | --- |
| 0.35 | 3.4 头身 | 差（写 `standing` 出跪坐） | 飘带暴走成满画金环 | 不可用 |
| 0.65 | 3.0 头身 | 好 | 轻微题跋 | **概念图基准值** |
| 0.70 | 2.9 头身 | 好 | 金饰偏散 | 序列帧可用 |
| 0.90 | 3.1 头身 | 中（姿态偏僵） | 冠变形、整体变平 | 仅在跨帧漂移时临时提到 0.8–0.85 |

> 权重与「体型」不是线性关系：**0.35 反而更不 Q**（3.4 头身），因为 LoRA 的 Q 版先验被底模的正常比例盖过去了。想稳住 3 头身，权重不能低于 0.6。

---

## 6 元素主题与技能风格变体

美术圣经定的是**本体配色不随章节/时代改变**（§2.6）。所以变体只允许改三样：**墨气形态、背景色温、点缀色（限制在金色体系内 + 四凶各自的唯一强调色）**。

### 6.1 四凶流派（战斗技能风格）

技能系统见 [第一章设计](../design/feature-chapter-one.md)：饕餮「吞地波 / 饥印」、穷奇「追击 / 锐」、梼杌「护身 / 逆劲」、混沌「延迟范围 / 余波」。落在提示词上：

| 流派 | 追加正向词 | 追加负向词 | 视觉逻辑 |
| --- | --- | --- | --- |
| 饕餮 | `swallowing vortex of ink, open mouth motif, purple-black ink aura, heavy dark gold` | `sharp lines, white glow` | 墨被「吸」成旋涡，边缘糊化 |
| 穷奇 | `sharp wind slash, thin straight ink streaks, cold teal accent, winged silhouette` | `soft blur, round shapes` | 墨被「切」成细直线 |
| 梼杌 | `cracked iron ink blocks, scale pattern, dark red accent, hard angular shadow` | `flowing, smoke` | 墨被「压」成裂块 |
| 混沌 | `faceless void, smoke-eroded edges, negative space devouring the form, pale grey` | `clear outline, symmetry` | 墨被「吃」掉轮廓 |

**唯一强调色的用量**：不超过画面 5%。超过就违反 §2.4「禁用高饱和」——四凶的强调色属于「战斗特效可例外」，但例外范围仅限特效层，不许染到袍身。

### 6.2 时代（Tab 切换）

过去 `#202849` 偏暖紫蓝、现在 `#142032` 偏冷深蓝，但角色本体不换色。所以：

- 过去：背景追加 `warm indigo backdrop, dusty violet haze`，正向保留全部金饰词；
- 现在：背景追加 `cold deep blue backdrop, desaturated`，**不要**加 `dim`（会把金饰一起压暗，金就不亮了）；
- 两者都不许出现 `color shift on character, palette swap` 之类的词。

### 6.3 三灵（神龙 / 凤凰 / 麒麟）

只在环境谜题与技能特效里出现，不进主角立绘。需要时追加：
- 神龙：`coiling dragon of ink, scale texture, cloud scroll`
- 凤凰：`phoenix feather strokes, vermilion brush flare`（唯一允许用朱红的地方）
- 麒麟：`jade-white qilin, single horn, earth-toned ink`

---

## 7 序列帧动画方案（重点）

### 7.1 先否掉一条错路

**不要用「一图多帧 / character sheet / 4 panels in a row」。** 实测（附录 A-3，1216×832，提示词明确写 `4 panels in a row, same character repeated`）：出来的是 4 个**比例不同、视角不同（正面/四分之三/侧面混着来）、表情不同**的角色，还凭空多了两个圆形道具。原因是 SDXL 没有「分格」的空间先验，它把 `character sheet` 理解成「画几个像的」而不是「画同一个人的第 N 帧」。没有 ControlNet 网格、没有 AnimateDiff，这条路走不通。

### 7.2 可行管线：母版锁形 + 逐帧 img2img

> **⚠️ 本节已于 2026-10-29 被实测推翻，不要再按它做。** 8 张不同 denoise 的对照证明：低 denoise 锁得住形但几乎不动、且逐帧差异是线条重绘噪声（播出来是"抖"不是"动"）；高 denoise 形与色同时崩（灰袍漂成橄榄绿、金腰带退化成游离棒状物）。现行路线见 **§12「AI 只出母版，运动用位移场合成」**。本节保留仅为记录否决过程。

```
① 概念图 A 过审（母版 master.png）
② 逐帧 img2img：init = 母版，denoise 按片段取值，正向只改「动作层」
③ 每 3 帧回切母版重新 img2img（防止链式漂移累积）
④ 归一化：色键抠图 → 头高归一到 42 px → 脚底对齐 y=120 → 髋点居中 x=64
⑤ 拼图校验：叠图 / 剪影 IoU / 色板 ΔE
⑥ 不合格帧单独重抽，不回退整条序列
```

**denoise 取值表**（实测校准，改动越小值越低）：

| 片段 | 动作幅度 | denoise | 备注 |
| --- | --- | --- | --- |
| `idle` | 呼吸、衣摆微动 | 0.45–0.50 | 只改 `breathing, slight sway`，几乎不动形 |
| `era_switch` | 抬头环视 | 0.50–0.55 | 头动，身不动 |
| `turn` / `land` | 挤压变形 | 0.55–0.60 | 加 `squash, compressed` |
| `hurt` | 后仰 | 0.60 | 加 `recoiling backward, leaning back` |
| `attack` | 单臂前挥 | 0.62–0.66 | 加 `arm extended forward, swinging arm` |
| `run` | 前后跨步 | 0.65–0.70 | 实测 0.62 只出「走路」，见附录 A-4 |
| `dash` | 前倾 + 布后掠 | 0.68–0.72 | 加 `leaning forward, cloth swept back` |
| `jump` / `fall` | 收腿 / 张臂 | 0.68–0.72 | 加 `knees tucked` / `arms spread` |
| `respawn` | 纵向挤压 | 0.55 | 加 `stretched, elongated` |

> **阈值在哪**：denoise ≤ 0.55 时，动作词基本只能微调（实测 0.62 才刚出「跨步」，要到跑得开需要 0.68+）；denoise ≥ 0.75 时，冠的尖数、腰带结法、袍摆长度开始各帧不一致。**0.70 是这条序列的上限。**

### 7.3 抠图与对齐（决定成品能不能用）

- **背景必须是纯色纸白**（`#F8F0E3` 一档）：这让抠图变成色键运算，比 AI 抠图稳得多，也不会有半透明毛边。正向写 `plain cream paper background`，负向写 `background scenery, black swirl`。
- **头高归一化**：每帧量出「发顶 → 下颌」像素高 H，按 `42 / H` 缩放；整图高度随之落在 116 px 附近。这一步不做，序列播起来会「一会儿大一会儿小」——手工逐帧动画最常见的翻车点。
- **脚底基线**：除 `jump` / `fall` / `dash` 外，脚底一律对齐 `y = 120`。位移类片段改为对齐**髋点**，否则起跳帧会被拉回地面。
- **髋点居中 x = 64**：让 `rig`/精灵节点原地翻转时视觉不位移（对齐美术圣经 §2.1 的 +x 约定）。

### 7.4 11 个片段的帧数与循环要求

对应 `player.gd` 的 11 项动画（美术圣经 §5.1），按 **12 fps 逐帧**折算：

| 片段 | 骨骼版时长 | 序列帧数 | 循环 | 闭合要求 |
| --- | --- | --- | --- | --- |
| `idle` | 2.40 s | 12 | ✓ | 第 1 帧与尾帧位置重合（呼吸回到最低点） |
| `run` | 0.50 s | 8 | ✓ | 左右脚各落地一次，首末帧为同一相位 |
| `jump` | 0.26 s | 4 | ✗ | 末帧接 `fall` 首帧，不允许回弹 |
| `fall` | 0.40 s | 5 | ✓ | 布摆振幅在 ±5% 内抖动即可循环 |
| `dash` | 0.18 s | 3 | ✗ | 首帧为启动、末帧为最大前倾 |
| `attack` | 0.26 s | 4 | ✗ | 蓄力 → 挥出 → 收招三拍，末帧回静止 |
| `hurt` | 0.32 s | 4 | ✗ | 末帧必须能接 `idle` 第 1 帧 |
| `respawn` | 0.60 s | 7 | ✗ | 由挤压恢复，末帧 = 静止姿 |
| `turn` | 0.16 s | 2 | ✗ | 用挤压过渡，不画转身中间帧 |
| `land` | 0.22 s | 3 | ✗ | 末帧 = `idle` 第 1 帧 |
| `era_switch` | 0.50 s | 6 | ✗ | 末帧回静止姿 |

合计 **58 帧**。这是「能进游戏看效果」的最小集，不是最终交付量。

> **状态（2026-10-29）**：这 58 帧已由 `tools/anim_frames.py` 全部产出并通过校验，**但走的是 §12 的程序化位移场，不是本节下面那套 img2img 流程**（后者已被实测推翻，见 §12.1）。帧数、循环标志、12 fps 三个参数与本表完全一致。

**循环片段的闭合做法**：先生成第 1 帧到第 N 帧（N 不含闭合帧），再用「第 1 帧」当 init、denoise 0.40 生成第 N+1 帧，要求它与第 1 帧在剪影 IoU 上 ≥ 0.90，然后**丢掉第 N+1 帧**——它只是用来验证「循环接缝不跳」，不作为素材。真正的循环靠首末帧同相位。

### 7.5 帧间一致性的 7 条硬指标（可量化，交给脚本断言）

| # | 指标 | 阈值 | 违反后果 |
| --- | --- | --- | --- |
| C1 | 头高 H | 42 ± 1.5 px | 播放时「忽大忽小」 |
| C2 | 脚底基线 | 120 ± 1 px（位移类豁免） | 角色在地面上「飘 / 陷」 |
| C3 | 髋点水平位置 | 64 ± 1 px | 翻转时视觉位移 |
| C4 | 主色板偏差 | 8 个色值 ΔE ≤ 5 | 帧与帧之间「换了个人」 |
| C5 | 同片段相邻帧剪影 IoU | ≥ 0.72 | 动作断裂、读不出速度 |
| C6 | 同片段相邻帧质心位移 | ≤ 0.15 × 头高 | 跳帧感 |
| C7 | 循环接缝 IoU（首帧 vs 虚拟闭合帧） | ≥ 0.90 | 循环处「抖一下」 |

C4 的 8 个色值直接取美术圣经 §2.4：`#13110F` `#221F1C` `#302C27` `#181613` `#F8F0E3` `#FAEFDE` `#C69E2C` `#927018`。校验方式：统计每帧非背景像素的色值直方图，取前 8 个峰值与目标色做 ΔE 比对。

### 7.6 序列帧的定位（必须写清楚，否则会被误当交付物）

- **可以**：验证动作手感、做动画预览、给程序对时序、给美术评审看节奏。
- **不可以**：直接替换 `assets/characters/shihung/parts/`。原因是 §7.1 的同一条：AI 出的是**整人像**，切不出枢轴对齐的 16 个部件。正式资产仍走 `gen_parts.py` → `build_rig.gd` → `verify_rig.gd`。
- 若将来要真做序列帧交付，前置条件是补 `ControlNet OpenPose`（骨架硬控）+ 逐帧修线，这两项当前**都没有**，属于待立项，不是待调参。

---

## 8 一键调用（本地 API）

节点图（API 格式）：`CheckpointLoaderSimple` → `LoraLoader` → 双 `CLIPTextEncode` → `EmptyLatentImage`（txt2img）或 `LoadImage`+`VAEEncode`（img2img）→ `KSampler` → `VAEDecode` → `SaveImage`。

完整参数模板见 [prompts/shihung-concept.json](prompts/shihung-concept.json) 与 [prompts/shihung-frame.json](prompts/shihung-frame.json)。字段含义：

| 字段 | 对应节点 | 备注 |
| --- | --- | --- |
| `ckpt` | CheckpointLoaderSimple.ckpt_name | 必须带 `SDXL\` 前缀 |
| `lora` / `lora_w` | LoraLoader | 权重同时作用于 model 与 clip |
| `init` / `denoise` | LoadImage / KSampler | 仅 img2img 需要 |
| `w` `h` | EmptyLatentImage | 序列帧必须与母版一致 |

启动服务：

```powershell
& "E:\ComfyUI_portable\python_embeded\python.exe" -s "E:\ComfyUI_portable\ComfyUI\main.py" --port 8188 --disable-auto-launch
```

出图落在 `E:\ComfyUI_portable\ComfyUI\output\`，文件名为 `filename_prefix` + 递增序号。**拿到图必须真的打开看**——`status: success` 只代表显存没炸，不代表图能用。

---

## 9 已踩的坑（按踩到的顺序）

| # | 现象 | 原因 | 处置 |
| --- | --- | --- | --- |
| ① | 出来的图全身蜷在半空、背景大墨旋涡 | `simple background` 被理解成「留白即构图」 | 正向改 `blank background, empty background`，负向加 `black swirl` |
| ② | 右侧被写满书法 + 朱印 | 水墨 tag 诱发国画题跋格式 | 负向加 `chinese text, kanji, calligraphy, inscription, red seal, stamp`（实测有效） |
| ③ | 三尖冠变 5–8 尖 | 「三尖」不是 SDXL 的稳定概念 | 只能靠重抽 + 后期修；**不要**改成 `three spikes` 硬顶，会变成三角帽子 |
| ④ | 腰部垂带铺满地面 | `long` + `two` 被放大成装饰主题 | 改 `two short gold ribbons hanging at waist` |
| ⑤ | 同 seed 只改动作词，比例从 3 头身漂到 2.5 头身 | seed 锁的是噪声，不是角色 | 序列帧必须 img2img，不能纯 txt2img 换姿势（附录 A-5） |
| ⑥ | 一图四帧各画各的 | 无分格先验 | 放弃，见 §7.1 |
| ⑦ | 0.35 权重反而更不 Q | LoRA 先验被底模正常比例盖过 | 权重下限 0.6 |
| ⑧ | 换画幅后归一化全废 | 角色占画比例随画幅变 | 序列帧画幅与母版严格一致 |
| ⑨ | 想「修正」冠形，结果冠整个消失，变成头巾/厨师帽 | 负向写 `tall crown, many spikes, oversized crown` 把「冠」这个对象一起压没了；正向写 `thin gold band` 又把冠拉成发带 | **不要用负向词修饰主体对象本身**，只能重抽或用正向词替换描述（6/6 全废，见附录 B） |
| ⑩ | `two short gold ribbons` 出来是一根铁丝 | `short` + `ribbon` 让模型理解成细绳 | 改回 `two long gold ribbons hanging at waist`（长/短交给构图决定，后期裁） |
| ⑪ | 脚被当成背景抠掉，归一化高度算错 | 浅肤色 `#FAEFDC` 与纸白 `#F8F0E3` 距离太近，全局阈值区分不了 | 改用**从边框洪水填充**背景；阈值判定只做初筛 |
| ⑫ | 袍身压暗到配色表后，角色在天空底色上消失 | 不是 bug，是配色表本身的已知缺陷 | 见 §11.3，**不要**为了「对色表」而压暗 |

---

## 10 待确认

| 事项 | 影响 | 谁定 |
| --- | --- | --- |
| AI 生图是否可作为「参考素材」入库，还是仅限内部评审 | 关系到能否把概念图放进 `docs/art/` | 项目负责人（资产登记 §5 授权条款） |
| 「三尖金冠」是否接受「多尖冠 + 后期修」 | 与 §2.7 识别锚点冲突 | 美术负责人 |
| 是否立项补 ControlNet / AnimateDiff | 决定序列帧能否做成可交付资产 | 技术美术 |
| 是否需要 4 套四凶风格的角色变体图 | 影响工作量（每套 4 张） | 战斗设计 |
| **袍身是否必须对色表 `#221F1C`** | 对色表 = 牺牲天空底色下的可辨识度（1.0–1.14:1），与 §2.6 的阻塞问题同源 | 美术负责人 + 技术美术（须与描边方案一起定） |
| 母版是否入库、以什么状态入库（参考 / 可用（内部）） | 决定它能否被后续资产引用 | 项目负责人 |
| **母版头身比是否重新出一版** | 现行母版含冠 3.4 / 不含冠 5.0；后期拉伸校正会拉长脖子（已验证不可用），要么接受现状、要么改提示词重抽（§12.4） | 美术负责人 |

---

## 11 母版定稿记录（2026-10-29）

### 11.1 选型过程

按 §5.3 的权重结论连抽 3 批共 19 张，只有一张同时满足「3 头身 / 侧视 / 造型完整 / 无文字 / 底干净」：

| 批次 | 张数 | 改了什么 | 结果 |
| --- | --- | --- | --- |
| B1（`cand_*`） | 6 | 冠改「thin gold band / coronet with three spikes」，垂带改「short」 | **全军覆没**：冠变头巾/厨师帽，垂带变铁丝，底色发灰（坑⑨⑩） |
| B2（`c2_*`） | 6 | 回退冠词，只补负向（文字/头巾/灰底） | 文字没了、底干净了，但冠形不稳、垂带仍偏细 |
| B3（`c3_*`） | 4 | **完全回退 A-2 原版提示词**，负向只加文字与头巾类 | **`c3_20261029` 可用**：无文字、米白底、3 头身、短垂带、赤足、袍摆后拖 |
| B4（`c4_*`） | 3 | 袍身改 `very dark charcoal / near black` | 颜色对了但构图崩（一张三人、一张带朱印、一张飘黑带） |

**定稿**：`c3_20261029_00001_.png`（seed 20261029，LoRA 0.65，832×1216，28 步，cfg 5.0，euler_a / normal）。

> 结论一句话：**这张图是「原版提示词 + 一条文字负向」的产物，不是调优出来的**。前面所有「改良」都是在破坏它。调提示词时优先回退，不要叠加。

### 11.2 后期链路（确定性，可重跑）

| 步 | 操作 | 参数 |
| --- | --- | --- |
| 1 | 水平镜像 | 模型给的是朝左，美术圣经要求朝 +x → 翻转 |
| 2 | 底色统一 | 洪水填充去背景 → 填 `#F8F0E3`（实测底色 240/240/235，与目标差 ΔE≈2） |
| 3 | 去地面接触线 | 底部区域整行覆盖率 > 22% 画宽判为地线并清除 |
| 4 | 归一化 | 剪影高 → 116 px，脚底对齐 `y=120`，髋点居中 `x=64`（画布 128×128） |
| 5 | 剪影验证 | 缩到 58 px 贴在 `#142032` 底上看分离度 |

产物（`C:\Users\Administrator\Desktop\GodTime\.workbuddy\art-out\`）：

| 文件 | 内容 |
| --- | --- |
| `master_full.png` | 832×1216，朝右、宣纸白底、已去地线（母版正本） |
| `master_128.png` / `master_128_4x.png` | 128×128 归一化，剪影 54×116，脚底 y=120 |
| `master_silhouette58.png` | 58 px 屏上尺寸剪影验证 |
| `master_dark.png` 及 `_128` / `_silhouette58` | 袍身压到 `#2B2A28` 的对照版（见 §11.3） |

### 11.3 一个意外发现：袍身**不能**压到配色表的值

为了对齐 §2.4 的重墨袍 `#221F1C`，做了一版「只压中性灰、保留金色与肤色」的色阶压缩（实测袍身落到 `#2B2A28`，非常接近目标）。压完在深蓝天空底色上做剪影验证，结果：

| 袍身 | 对「现在」`#142032` | 对「过去」`#202849` | 58 px 下的可读性 |
| --- | --- | --- | --- |
| 母版实际（偏亮灰 `#7B7A74`） | **3.80 : 1** ✓ | **3.34 : 1** ✓ | 冠、头、袍摆、脚全部可辨 |
| 压暗版 `#2B2A28` | 1.14 : 1 ✗ | 1.00 : 1 ✗ | 只剩金饰与脸，身体融进背景 |
| 配色表 `#221F1C`（计算值） | 1.00 : 1 ✗ | 1.14 : 1 ✗ | 同上 |

**这三行把美术圣经 §2.6 记录的缺陷原样复现了**：文档写「现在·天空 1.00:1、过去·天空 1.14:1」，而 `#221F1C` 与 `#2B2A28` 算出来正好是这两个数。也就是说——

- **AI 母版偏亮的袍身不是缺陷，它恰好是 §2.6 那个阻塞问题的「方案 A（提高世界底色明度）」的反向版本**：不改背景，改角色。
- 但如果正式资产按配色表做成 `#221F1C`，就一定会掉进 1.0–1.14:1 的坑，那时只能靠 §2.6 的**方案 B（CanvasGroup + 纸色描边）**解决，而不是继续调角色颜色。
- 因此**不建议**把母版的袍色压到配色表值当「修正」。若美术负责人坚持对色表，需要同时把描边方案一起定，否则等于用一张好看的立绘换一个不可玩的主角。

### 11.4 偏差清单（母版相对美术圣经）

| 项 | 目标 | 实测 | 处置 |
| --- | --- | --- | --- |
| 头身比 | 2.8（目标 3） | **3.4 含冠 / 5.0 不含冠** | 见 §12.4：两种口径差一倍，冠占了头块近一半 |
| 头高 | 42 px（发顶→下颌） | 冠顶→下颌 34 px；发顶→下颌 23 px | 严格 3 头身需把头放大 1.8×，会明显更 Q，待定 |
| 剪影 | 46×118 | 54×116 | 偏宽 8 px，袍摆拖得更长；不影响识别 |
| 冠 | 三尖 | 五尖 | **未解决**，需重抽或手工修（坑③） |
| 腰垂带 | 两条金垂带 | 一条腰绳 + 流苏 | **未解决**，词元无法稳定控制 |
| 眉间朱砂 | 可见 | 被刘海遮住 | 需 `forehead visible` 或后期补点 |
| 金线 | 1.1–1.4 px 焦墨线 + 平涂金 | 水彩晕染状边缘 | 属 AI 笔触特性，正式资产由脚本画 |
| 袍色 | `#221F1C` | `#7B7A74` | **有意保留**，理由见 §11.3 |
| 底色 | `#F8F0E3` | `#F8F0E3` | 命中 |

**结论**：母版够用于「确立造型方向 + 当位移场的画源」，**不够用于切 16 部件**。冠尖数与垂带这两项要么手工修，要么接受并在程序化绘制阶段按配色表重画——后者更省事，因为 `gen_parts.py` 本来就是坐标驱动的。

---

## 12 序列帧产线（2026-10-29 定稿）：AI 只出母版，运动用位移场合成

### 12.1 为什么放弃「逐帧 img2img」

用定稿母版 `master_full.png` 当 init，同提示词只调 denoise，各出 1 张（共 8 张）：

| denoise | 剪影 IoU（对母版） | 与母版的像素差 | 差异落在哪 | 判定 |
| --- | --- | --- | --- | --- |
| 0.38 | 0.975 | mean 7.4 / 10.9% 像素 >12 | 轮廓线 | 形锁得住，**几乎不动** |
| 0.48 | 0.969 | mean 8.7 / 20.4% | 轮廓线 | 同上 |
| 0.58 | 0.959 | mean 11.2 / 23.8% | 轮廓线 | 同上，**已接近上限** |
| 0.68 | 0.934 | — | 形+色 | 袍色漂成橄榄绿、腰带变形 |
| 0.75 | 0.907 | — | 形+色 | 腰带退化成**游离的棒状物**、袍身膨胀、剪影宽 641→731 px |

两个致命点：

1. **低 denoise 只改线条不改姿势。** 差异热力图显示能量几乎全在描边上——那是 Denoise 重绘噪声，不是动作。12 帧播出来的观感是「线条在呼吸」，不是角色在呼吸。
2. **高 denoise 连颜色一起改。** 灰袍 → 橄榄绿是色相漂移，不是阴影变化；金腰带断成两根游离棒状物是物体解构。这两项都无法用负向词救回来。

所以「逐帧 img2img」这条路在**没有 ControlNet OpenPose / AnimateDiff 的本地环境**下不可行，与 §7.1 否掉一图多帧是同一个根因：缺少动作这个可控条件。

### 12.2 现行路线

```
AI（1 次）  ──→ 母版 master_full.png  ──→ 归一化 master_128.png
                                              │
                           程序化位移场（12 次采样）──→ idle_00..11.png
                                              │
                            一致性断言 → 自动 PASS/FAIL（tools/anim_idle.py）
```

核心思想：**唯一画源 + 位移采样 = 帧间零重绘 = 零闪烁**。分类上这是「网格变形 / mesh warp」动画（《空洞骑士》《茶杯头》同一族），不是逐帧手绘。

运动由 4 层正弦位移叠加，全部绕**脚底锚点**以免脚离地：

| 层 | 通道 | 幅度 | 相位 |
| --- | --- | --- | --- |
| 呼吸压缩 | 垂直缩放 | 2.4%（全身高波动 ≈5 px） | 主相位 |
| 胸腔扩张 | 横向 | 2.2% | 主相位 |
| 袍摆摆动 | 横向，权重 ∝ 下摆程度 | ±3.0 px | 滞后 1.05 rad |
| 头部跟随 | 横向，仅头块 | ±1.1 px | 滞后 0.50 rad |

相位做 8% 非对称（`g(t)=t-0.08·sin(2πt)`）：**吸气 5 帧、呼气 7 帧**，比对称正弦更像活物，且 `g(0)=g(1)=0` 保证循环严格闭合。

### 12.3 实测校验（`tools/anim_idle.py` 自动断言）

12 帧 / 12 fps / 1 s 循环，128×128 RGBA：

| 指标 | 门槛 | 实测 | 判定 |
| --- | --- | --- | --- |
| 头高一致性 | Δ ≤ 3 px | 34–36（Δ2） | PASS |
| 脚底基线 | 120 ± 1 px | 119 | PASS |
| 相邻帧剪影 IoU | ≥ 0.72 | **0.932–0.978** | PASS |
| 相邻帧质心位移 | ≤ 6.3 px | **0.99 px** | PASS |
| 循环接缝 IoU | ≥ 0.90 | **0.978** | PASS |
| 循环闭合像素差（f00 vs f12） | 0 | **0** | PASS |

对比：AI 逐帧方案里，相邻帧 IoU 最好也只有 0.93–0.96，且是**噪声式的**；程序化方案的同项指标是**信号式的**（差异全部来自真实位移）。

### 12.4 顺带测出来的问题：母版头身比

量母版逐行轮廓（`tools/anim_idle.py` 与 `.workbuddy/tmp/rows.py`）：

| 位置 | y（128 画布） |
| --- | --- |
| 冠顶 | 4 |
| 发顶（暗色起始） | 约 18 |
| 下颌 / 颈最细处 | 约 35–37 |
| 脚底 | 119 |

于是「头高」有两种口径，差一倍：

- **含冠口径**（冠顶→下颌）：34 px → **3.4 头身**
- **严格口径**（发顶→下颌，不含冠）：23 px → **5.0 头身**

美术圣经 §2.1 的口径是「发顶 `y=4` → 下颌 `y=46` = 42 px」，即 36.2%、2.8 头身——**但那套设定里没有这顶高冠**。所以母版"看起来"是 3.4 头身，实际是靠金冠把头块撑到近一半换来的。

处置：`tools/anim_idle.py --heads 3.0` 可做一键校正（头放大、颈下压缩、总高与脚底不变），**但实测这条路不通**：头绕冠顶放大会把下巴整体下移约 5 px，而肩线没动，于是那段间隙只能靠**拉伸颈部**来填——实测颈长从 8 px 拉到 13 px，出来是「长脖怪」而不是更萌。把混合带从颈中改到下颌也没解决。

**结论**：头身比是造型层参数，不是后期参数。要 3 头身就得**重抽或手绘重画**，不能拿当前母版拉伸。当前母版按「含冠 3.4 头身」用，观感成立；严格 3 头身留作下一版母版的生成约束（提示词里把 `small three-pronged gold crown` 压矮、把 `chibi, super deformed` 权重提上去）。

### 12.5 复用方式

```bash
python tools/anim_idle.py                # 出 12 帧 idle + 自动校验 + 预览 GIF
python tools/anim_idle.py --n 8          # 改帧数
python tools/anim_idle.py --heads 3.0    # 头身比校正（已知会把脖子拉长，仅作对比，别当成品）
```

产物全部落在 `.workbuddy/art-out/`（`clips/idle/`、`idle_preview.gif`、`idle_sheet.png`），**不写 `assets/`、不写 `game/`**。`idle` 只是 11 个片段之一，全量产出见 §12.6。

### 12.6 11 个片段全部补齐（`tools/anim_frames.py`）

把位移场拆成 7 个可调层（`vs` 垂直缩放 / `rise` 上移 / `lean` 前倾 / `hem` 袍摆横移 / `spread` 下摆下沉 / `sleeve` 袖摆横移 / `head` 头部跟随 / `toe` 脚尖横移 / `xs` 横向缩放），每个片段只给「层参数曲线」，画源始终是同一张母版。

| 片段 | 帧数 | 循环 | 驱动它的层 | 校验 |
| --- | --- | --- | --- | --- |
| `idle` | 12 | ✓ | vs + hem + head + sleeve（4 层正弦） | 全项 PASS |
| `run` | 8 | ✓ | **独立画源** `runpose_128.png` + vs/rise/lean/hem/sleeve（见 §12.9） | 位移类，基线豁免；全项 PASS |
| `jump` | 4 | ✗ | vs 0.93→1.06 + toe 蹬直 | 位移类，C1/C5/C6 豁免 |
| `fall` | 5 | ✓ | vs 1.03 + hem 抖动 + spread 波 | 全项 PASS |
| `dash` | 3 | ✗ | lean 4→9、vs 压缩、hem 后吹 | 全项 PASS |
| `attack` | 4 | ✗ | lean −2.2→+5.2、sleeve −6→+9 | C5/C6 参考；末帧 = 静止 ✓ |
| `hurt` | 4 | ✗ | lean −5、vs 0.96、head 后仰 | 全项 PASS；末帧差 1.85 |
| `respawn` | 7 | ✗ | vs 0.80→1.00 + xs 1.10→1.00（ease-out） | 压缩类，C1/C5/C6 参考 |
| `turn` | 2 | ✗ | xs 0.90 挤压过渡 | 末帧 = 静止 ✓ |
| `land` | 3 | ✗ | vs 0.86→1.025→1.0 + spread | 压缩类，C1/C5/C6 参考 |
| `era_switch` | 6 | ✗ | rise 2.2 + vs 1.035（正弦包络） | 位移类，基线豁免 |

合计 **58 帧**，与 §7.4 的帧数表逐项对齐。

**校验口径按片段类型分开**（这一步不做，会得出一堆假 FAIL）：

| 门槛 | 适用 | 说明 |
| --- | --- | --- |
| 头高 Δ ≤ 3px | 除 jump/respawn/land 外 | 压缩/拉伸片段头高本来就该变 |
| 脚底 120 ± 1px | 除 jump/fall/dash/era_switch 外 | 位移类片段脚本来就会离地 |
| 相邻帧 IoU ≥ 0.72、质心 ≤ 6.3px | 稳态片段（idle/run/fall/dash/hurt/turn） | 蓄意大幅形变（attack/respawn/land/jump）只报数不判定 |
| 循环闭合差 = 0 | idle/run/fall | 程序化产线的严格闭合证明，比接缝 IoU 更硬 |
| 末帧 ≈ 静止姿（平均像素差 ≤ 2） | attack/hurt/respawn/turn/land/era_switch | 保证能接回 `idle` 第 0 帧 |

实测结果：58 帧 **全部 PASS**，三个循环片段闭合差均为 0，六个需回静止的末帧平均像素差 0.00–1.85。

### 12.7 这条产线的能力边界（别把预览当资产）

位移场只能做**整体形变**，不能换四肢姿势。长袍把手臂和腿都盖住了，所以：

- `run` **已改用独立画源**（§12.9）——站姿母版做不出跨步，任何纯位移都读成「腰在扭」；
- `attack` 是「袖摆横扫 + 身体前冲」，**没有举手挥砍**；
- `jump`/`fall` 是「拉伸压缩 + 布摆」，不含腾空骨骼姿势。

这三条决定它只能当**手感/节奏预览**（与 §7.6 定位一致）。要实现真正的骨骼姿势动画，前置条件仍然是补 `ControlNet OpenPose` 或用 `gen_parts.py` 的 16 部件骨骼，属于立项问题。

### 12.8 交付清单

```
.workbuddy/art-out/
├── clips/<clip>/<clip>_00..NN.png     58 帧，128×128 RGBA
├── clip_manifest.json                 帧数/循环/fps/闭合差，给程序侧读
├── all_clips_overview.png             11 片段总览
├── master_128.png                     定稿站立母版（10 个片段的画源）
├── runpose_128.png                    跑姿画源（run 专用）+ _raw 备份
├── run_profile_compare.gif            run 两档幅度（vivid / soft）并排 4x 循环
├── run_58px_compare.png               run 两档在 58 px 游戏内尺寸下的对比
├── <clip>_preview.gif                 逐片段 4x 循环预览
├── <clip>_preview_dark.gif            同图深蓝底（检查天空下剪影）
├── <clip>_sheet.png                   逐片段帧条
└── <clip>_at58px.png                  58 px 屏上真实尺寸（6x 放大，深蓝底）
```

`at58px` 那组是关键验收图：抽查 idle / run / attack 三组共 24 帧，58 px 深蓝底上金冠与交领金线承担了剪影分离，没有一帧糊进背景——§11.3 担心的「压暗袍身导致 1.0:1」问题，在当前袍色 `#7B7A74` + 金饰下不成立。

---

### 12.9 `run` 换成跑姿画源（2026-10-29 晚，用户实测反馈驱动）

**触发**：用户看完第一版 run 直接说「不行，这个像是腰在动」。复盘确认这是**结构性缺陷**，不是调参问题：

母版双脚实测挤在 x=59–73（并拢 14 px），袍子直筒到地。位移场里 `hem` 层让整条下摆同向横摆，视觉上等价于「腰在左右扭」。先后试过三种补救，全部失败：

| 尝试 | 做法 | 结果 |
| --- | --- | --- |
| 跨步剪切 `stride` | 前后侧反向拉伸 | 变成「下摆整体变宽/变窄」，读成胖瘦抖动 |
| 下摆分片 `gap` | 沿中线真实裂开、缝隙填压暗袍身色 | 像「裙子被剪成两半」，且脚被切成残片 |
| 前后片纵向错位 `hem_f/hem_b` | 前片抬起、后片下沉 | 仍是一道笔直的竖缝，无腿的形态 |

**根因**：站立姿态里没有「腿」这个结构信息，任何布料形变都伪造不出跨步。

**解法**：给 `run` 换独立画源——用定稿母版做 **img2img（denoise 0.78–0.86）** 抽跑姿，再用**程序化位移场**只负责节奏。

| 步骤 | 参数 / 做法 |
| --- | --- |
| 抽跑姿 | init=`master_full.png`，denoise **0.80**，LoRA 0.72，`chibi + 2.8 heads tall + body leaning forward + front leg lifted + back leg extended` |
| 选型 | 8 张候选里取 `runp2_401`：后脚离地 4 px、脚距 37 px、前倾成立 |
| 抠图归一 | 走 `char_mask` 洪水填充 → 归一化到 128 画布（身高 116、脚底 120） |
| 调色对齐 | 袍身 `#747371 → #7A7974`（只动低饱和中明度像素，金饰与肤色不动），对齐定稿母版 |
| 节奏 | `breath`（定稿）：袍摆/袖摆脉动全部关闭，只留 1 倍频呼吸（`vs` ±1.2%）——三档对照见 §12.9.1 |

**代价（必须知情）**：img2img 的 denoise 是「姿势 vs 身份」的单一旋钮，改姿势必改细节。跑姿画源与定稿母版相比：

- 袍形：多层裙摆 → 一片式；袖口金边由「滚边」变「云纹」；
- 金冠大一圈；头身比 3.35 → 3.48；
- 袍色已用调色对齐，发型/配色/赤足/朝向/纸白底保持一致；
- **后脚是绷脚背（脚尖朝下、脚跟抬起），前脚脚掌平但整只离地约 4 px** —— 提示词 `back leg extended` 在插画语料里对应的就是「蹬地绷脚」，加上长袍遮住整条腿只露脚掌，读起来像「踮着脚」。这是 img2img 改姿势的连带结果，不是参数写错。脚在 128 画布上只有 6–8 px 高（58 px 游戏内约 3 px）。**2026-10-29 与用户确认暂不修**；若将来要改，最优解是**只框后脚做 inpaint**（denoise 0.55，提示词加 `heel touching ground`），不要重抽整张——重抽会连带改掉已对齐的袍形与配色。

`stride`/`gap`/`hem_f`/`hem_b`/`leg_df`/`leg_db` 六个层仍保留在代码里，但 `run` 不再使用——它们证明了「单张站姿画源做不出步态」这条结论，留作后续参考。

**本轮修的 bug**：`rise` 符号写反（`sy = ... - rise`）。反向映射里内容要上移应采样源图更低处，即 `+ rise`。旧写法导致「上浮」实际是下沉：run 的腾空帧脚比触地帧还低 4 px。已在 `render()` 修正，`era_switch` 的上浮方向随之变正确。

### 12.9.1 幅度三档标定：定稿 = breath（只呼吸，布料不动）（2026-10-29 深夜）

**一晚迭代三次，全部保留在代码里可切换**（`tools/anim_frames.py::RUN_PROFILES`，`--profile breath|vivid|soft`，`--amp` 可再叠倍率）：

| 轮次 | 用户原话 | 做了什么 | 结果 |
| --- | --- | --- | --- |
| 1 | 「幅度还是太大了，跟空洞骑士一样轻微浮动就好了」 | 先全线压 40%（v3a），压成静止 | 质心位移 0.88 px = 不动，废弃 |
| 2 | — | 按层重做：上下交给 `rise` 刚体浮动，袖摆压到 24% → **soft** | 与旧版并排对比，用户选回大动作版 → **vivid** 定为默认 |
| 3 | 「袖摆和袍摆都不要晃动，只需要待机感的轻微晃动」 | 换约束：不是「小一点」而是「布料不许动」→ **breath** | **定稿** |

**关键认知：第 3 轮才问对了问题。** 前两轮都在调「振幅大小」，用户真正在意的是「**哪些层允许动**」——他要的不是更小的摆动，而是**没有摆动**。把 `hem`/`sleeve` 的脉动直接置 0 之后，问题一次收敛。以后遇到「太晃」，先确认是「幅度」问题还是「自由度」问题。

**两条判据**（调任何片段都适用）：

1. **常值偏移不产生晃动，脉动才产生。** `lean` 的前倾基准、`hem` 的后飘基准是「在往前跑」的静态倾向，压小它们只会让角色变呆，不会让动作变稳。只该压乘 `sin` 的脉动项。
2. **晃动感的放大器是袖摆，不是上下浮动。** vivid 的 `sleeve` ±5.4 px 在 4× 预览里峰峰 **43 px**，读成「整个人在晃」；而真正承担节奏的上下位移在同尺度只有 20 px。

**三档参数**：

| 层 | **breath（默认 / 定稿）** | vivid（大动作） | soft（轻微浮动） |
| --- | --- | --- | --- |
| `vs` 垂直缩放 | **+0.012·sin(a)（1 倍频呼吸）** | −0.028·step | −0.008·step |
| `rise` 腾空 | **0** | 1.8 | 1.9 |
| `hem` 袍摆 | **−3.1 常值，脉动 0** | −3.8 ±2.6 | −3.1 ±1.2 |
| `sleeve` 袖摆 | **0（完全不动）** | ±5.4 | ±1.3 |
| `lean` 前倾 | **1.6 常值** | 2.0+1.8·step | 1.6+0.6·step |
| `head` 头部 | **±0.5** | ±0.6 | ±0.3 |

`breath` 的设计要点：

- 袍摆/袖摆的**脉动严格为 0**，不是压小；但**常值保留**（前倾 1.6、后飘 −3.1），所以画面仍是「在跑」的姿势，不是一张站桩图。
- 唯一在动的是 `vs` 呼吸：1 倍频、绕脚底锚点，头顶上下 ≈ ±1.4 px（116 × 0.012），**脚底基线完全不漂**。
- `head` 只跟 0.5 px 滞后，纯粹为了不读成「缩放滤镜」，量级接近量化噪声。
- 8 帧一圈 = 0.67 s 一次呼吸。12 fps 下这是位移场能给出的**最慢合法周期**（更慢就得跨两个循环才闭合，会破坏 loop），所以它比 idle（1 s）略快，属于帧数约束而非设计选择。

**实测（128 画布，8 帧）**：

| 版本 | 头顶行程 | 垂直质心行程 | 相邻帧 IoU 最低 | 结论 |
| --- | --- | --- | --- | --- |
| **breath（定稿）** | 1.4 px | **0.52 px** | 0.972 | 布料静止，只有呼吸 |
| vivid | 5 px | 3.1 px | 0.839 | 动作读得出，也读得出晃 |
| soft | 3 px | 2.1 px | 0.914 | 偏静 |
| v3a（全压 40%） | — | 0.88 px | 0.956 | 等于静止，废弃 |

三档全部校验 PASS、闭合差 0；`vivid` 另经逐像素复验与初版 v2 **完全一致（最大差 0）**，证明 profile 化没有改动曲线本身。

**两条经验**：

- **观看尺度决定结论。** vivid 是在 4× 预览下被判断为「晃」的——那个尺度上 5 px 行程 = 20 px；但在 58 px 游戏内它只有约 2.5 px。同一个动画在两个尺度上的主观感受差别很大，验收要两种尺寸一起看，且**以用户实际看的那一版为准**，不要拿数值去推翻他的观感。
- **不要用「统一乘系数」收幅度。** 各层的物理角色不同（谁承担节奏、谁只是放大器），一个系数会让该保留的也被砍掉——v3a 就是这么压成静止的。要按层改，或者直接关掉某一层。

**验收图**：`run_profile_compare.gif`（breath / vivid 两列并排 4× 循环）、`run_58px_compare.png`（58 px 游戏内实际尺寸、两档对比、4× 像素块放大）。


---

## 附录 A 实测记录（2026-10-29，本机 RTX 4080 SUPER）

全部 8 张图存于 `E:\ComfyUI_portable\ComfyUI\output\`，文件名与结论如下。

| 编号 | 文件 | 参数 | 结果 | 结论 |
| --- | --- | --- | --- | --- |
| A-1 | `godtime_00001_.png` | 0.65 / 832×1216 / 28步 / cfg5 / euler_a | 2.8 头身、单眼、焦墨平涂、纸白、赤足、金腰带；但蜷空漂浮 + 大墨旋涡（坑①） | 风格成立，构图需约束 |
| A-2 | `godtime_00002_.png` | 同上 + `standing` + `blank background` | 完整站立、3.0 头身、侧视（略偏左）、后拖袍摆、赤足；右侧书法（坑②） | **母版候选** |
| A-3 | `godtime_00003_.png` | 1216×832 + `4 panels in a row` | 4 个比例/视角/表情各异的角色 + 2 个圆形杂物 | 一图多帧不可用（§7.1） |
| A-4 | `godtime_frame_00001_.png` | img2img，init=A-2，denoise 0.62 | 同角色、同冠同袍同腰带，姿态变跨步（非跑），仍有书法 | img2img 锁形有效；跑步需 0.68+ |
| A-5 | `godtime_00004_.png` | 纯 txt2img，同 seed，仅改动作词 | 比例漂到 2.5 头身、飘带变多、上色从平涂转体积渐变 | seed 锁不住角色（坑⑤） |
| A-6 | `godtime_00005_.png` | LoRA 0.35 | 3.4 头身、跪坐（无视 `standing`）、金带铺满画 | 权重过低不可用（坑⑦） |
| A-7 | `godtime_00006_.png` | LoRA 0.90 | 3.1 头身、姿态偏僵、冠化形 | 仅漂移时临时上调 |
| A-8 | `godtime_00007_.png` | 0.70 + dpmpp_2m karras + cfg5.5 + 强负向 | **书法消失**、2.6 头身、冠裂成两段、金带成地面积带 | 负向有效（坑②解决）；冠与垂带仍需改词（坑③④） |

**整体判断**：风格层（水墨平涂 / 纸白 / 赭金）与体型层（2.6–3.2 头身）已经可控且可复现；**服饰细节层（冠尖数、垂带长度、腰带结法）不稳定**，这是 SDXL + 单 LoRA 的固有上限，只能靠重抽率换质量或用 ControlNet 硬控。前者意味着每张成品的重抽成本约 3–5 次，做 58 帧序列要预留 3–5 小时的抽卡时间。

---

## 附录 B 母版选型的 19 张（2026-10-29）

全部存于 `E:\ComfyUI_portable\ComfyUI\output\`，同目录下有拼图 `_sheet_candidates.png`、`_sheet_c2.png`、`_sheet_c3.png`、`_sheet_c4.png`。

| 批次 | 文件前缀 | 张数 | 改动 | 判定 |
| --- | --- | --- | --- | --- |
| B1 | `cand_A_* / cand_B_*` | 6 | 冠改 `thin gold band` / `coronet with three spikes`；垂带改 `short`；负向加 `tall crown, many spikes` | **全部淘汰**：冠消失成头巾/厨师帽（坑⑨）、垂带成铁丝（坑⑩）、底色发灰 |
| B2 | `c2_*` | 6 | 回退冠词，负向只加文字/头巾/灰底，扫 6 seed | 文字与灰底解决；冠形不稳（出现白晕、塌成发带）、垂带偏细 |
| B3 | `c3_*` | 4 | 完全回退 A-2 原版词，负向只加文字类 | `c3_20261029` **定稿**；其余 3 张分别跪姿、灰底、巨冠 |
| B4 | `c4_*` | 3 | 袍身改 `very dark charcoal / near black` | 颜色到位但构图崩：三人同框 / 带朱印 / 飘黑带 |

**代价记录**：19 张里只有 1 张可用（5.3% 命中率）。按这个比例，58 帧序列若全靠重抽，需约 1100 次生成；这正是 §7.6 说「序列帧不宜当交付资产」的量化理由。

---

## 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-10-29 | 初版建立：确立模特/LoRA/参数基线，实测 8 张得出「权重 0.60–0.75」「一图多帧不可用」「img2img 锁形可用」三条结论；给出 11 片段帧数表与 7 条一致性硬指标 |
| 2026-10-29 | 补 §11 母版定稿：19 张选型记录、后期链路、偏差清单；新增坑⑨–⑫（负向词反噬主体、`short ribbon` 变铁丝、肤色被当背景抠掉、压暗袍身复现 §2.6 缺陷）；补附录 B 与 3 项待确认 |
| 2026-10-29 | **推翻 §7.2**：8 张 denoise 对照证明逐帧 img2img 不可行（低 denoise 只改线条、高 denoise 形色同崩）。新增 §12 现行产线「AI 只出母版 + 程序化位移场」，交付 12 帧 idle 并通过 5 条一致性断言（闭合差 = 0）；新增 `tools/anim_idle.py`；复核头身比（含冠 3.4 / 不含冠 5.0），修正 §11.4 原「约 2.9」的估测错误 |
| 2026-10-29 | 补 §12.6–12.8：新增 `tools/anim_frames.py`，11 个片段 58 帧全部产出并 PASS；校验口径按片段类型分开（压缩/位移片段豁免 C1/C2/C5/C6，非循环片段不查接缝，新增「末帧≈静止姿」门槛）；补 `clip_manifest.json` 与能力边界说明 |
| 2026-10-29 | **run 换画源**（用户反馈「像腰在动」）：证伪 stride/gap/hem_f 三种布料形变方案，改用 img2img denoise 0.80 抽跑姿母版当独立画源 + 位移场只做节奏；新增 §12.9；修复 `rise` 符号反写的 bug（腾空帧脚反而更低 4px）；跑姿画源袍色调色对齐 `#7A7974` |
| 2026-10-29 | **run 幅度改为轻微浮动**（用户反馈「幅度还是太大，跟空洞骑士一样轻微浮动就好」）：v3a 全线压 40% 压成静止（质心位移 0.88px），复得两条判据（常值不产生晃动、袖摆是放大器）；为此做出 soft 档（`rise` 主浮动 + `vs` 0.008 + `sleeve` ±1.3，头顶行程 3px、质心 2.1px）。随后用户看两版并排对比选回大动作版 `vivid`（= 原 v2，逐像素复验最大差 0）——但这仍不是终点，见下一条 |
| 2026-10-29 | `clip_run` 参数 profile 化：新增 `RUN_PROFILES` 与 `--profile`、`--amp` 开关；新增 §12.9.1 记录两档对照、实测数值与「观看尺度决定结论」的经验；验收图 `run_profile_compare.gif`、`run_58px_compare.png` |
| 2026-10-29 | **run 幅度定稿 = `breath`**（用户：「袖摆和袍摆都不要晃动，只需要待机感的轻微晃动」）：`hem`/`sleeve` 脉动置 0、`rise` 置 0，只留 1 倍频 `vs` 呼吸（±1.2%，头顶 ±1.4px、脚底不漂），前倾/后飘常值保留以维持跑姿；实测质心位移 0.52px、相邻帧 IoU 0.972。**三档（breath/vivid/soft）并列保留可切换，默认 breath**；§12.9.1 重写为三档标定，补「第 3 轮才问对问题：要的不是更小的摆幅，而是没有摆幅」这条认知 |
| 2026-10-29 | 记录跑姿画源的**后脚绷脚背（踮脚）**这一已知偏差：成因（`back leg extended` 的插画语料对应 + 长袍遮挡）、尺度（脚高 6–8px @128，约 3px @58）、处置（用户确认暂不修，将来若改只对后脚 inpaint，勿重抽整张） |
