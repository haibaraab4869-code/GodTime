# -*- coding: utf-8 -*-
"""Shihung 主角部件生成器（确定性绘制 · 横版侧视）。

视角约定（对游戏一致性至关重要）：
  角色**面朝 +x**，镜头在角色正侧方，因此：
  - 只画得到**一只眼**，鼻子在脸部轮廓的前缘（+x）
  - 近侧（靠近镜头）一条手臂 + 一条腿；远侧同样各一条，被躯干/裙摆遮挡
  - 裙摆向 -x 拖出，腰饰垂带也向 -x 拖 —— 侧视剪影天然左右不对称
  游戏里 `rig.scale.x = -1` 即为朝左，不需要单独的镜像素材。

坐标系统：128x128 画布，脚底 y=120，髋 y=88，颈 y=45，头顶 y=8。
所有绘制在 4x 超采样后进行预乘 alpha 缩放，避免边缘黑边。

风格：水墨简化 —— 浓墨形体 + 纸色面部 + 赭金点线，无渐变。
层次靠"墨分五色"：远侧肢体最浓（背光）→ 袍身 → 后片裙摆 → 头发最浓。
"""
import json
import math
import os
from PIL import Image, ImageDraw

S = 4
W = 128
# 原型：只写临时目录，不碰 assets
ROOT = r"C:\Users\Administrator\Desktop\GodTime\.workbuddy\art-out\proto_parts"
PREVIEW = r"C:\Users\Administrator\Desktop\GodTime\.workbuddy\art-out\proto_preview"

# 描边总闸门。母版近黑像素仅占 10.5%，rig 占 35.7%，3.4 倍——主因是描边太粗。
# 0.55 使 1.3 -> 0.72px @128，接近母版那种"几乎看不见的边"。
EDGE_K = 0.55

# 墨色阶
# 底色是游戏内深夜蓝 #142032，不是纸白，旧墨阶在此底色上全部糊死（袍身仅 1.00:1）。
# 现按定稿母版实测的明度结构重排：亮袍 + 深线 + 金饰，主体过 3:1，描边/头发允许贴天空。
INK_FAR = (88, 87, 82, 255)      # 远侧肢体：被躯干遮挡层，可低于 3
INK = (123, 122, 116, 255)       # 主形（袍身）：对天空 3.80，锚点
# 近侧袖比袍身亮一档：同色会让挥臂时只有袖口和金饰在动，
# 袖子本身看不见，整条手臂读成"飘着的白棍"。
INK_SLEEVE = (138, 137, 130, 255)
INK_BACK = (102, 101, 96, 255)   # 后片裙摆
HAIR = (50, 48, 46, 255)
INK_EDGE = (50, 48, 48, 255)
# 褶皱必须比描边浅：深蓝底上褶皱比外轮廓还黑会读成脏点（旧值是反的）
CREASE = (84, 82, 78, 255)
SKIN = (250, 239, 222, 255)
SKIN_FAR = (214, 202, 186, 255)  # 远侧皮肤：压暗一档
PAPER = (248, 240, 227, 255)
GOLD = (198, 158, 44, 255)
GOLD_D = (146, 112, 24, 255)

# --- 侧视骨架关键坐标（与 tools/build_rig.gd 必须保持一致）---
CENTER = 64
HIP_Y = 88
HEAD_BOT = 45
HEAD_TOP = 8
SHOULDER_Y = 50
ELBOW_Y = 67
KNEE_Y = 103
ARM_NEAR_X = 73
ARM_FAR_X = 54
LEG_NEAR_X = 64
LEG_FAR_X = 60
SASH1 = (58, 80)     # 注意：落地时若腰线上移，这里与 build_rig.gd 必须同步改
SASH2 = (54, 85)
HEM_PIVOT = (64, 84)


# ------------------------------------------------------------------ geometry

def catmull(pts, seg=10, closed=False):
    p = list(pts)
    if closed:
        p = [p[-1]] + p + [p[0], p[1]]
    else:
        p = [p[0]] + p + [p[-1]]
    out = []
    for i in range(len(p) - 3):
        p0, p1, p2, p3 = p[i], p[i + 1], p[i + 2], p[i + 3]
        for j in range(seg):
            t = j / seg
            t2, t3 = t * t, t * t * t
            x = 0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    if not closed:
        out.append(p[-2])
    return out


def ribbon(pts, w0, w1, seg=12):
    path = catmull(pts, seg=seg)
    n = len(path)
    left, right = [], []
    for i, (x, y) in enumerate(path):
        if i == 0:
            dx, dy = path[1][0] - x, path[1][1] - y
        elif i == n - 1:
            dx, dy = x - path[i - 1][0], y - path[i - 1][1]
        else:
            dx, dy = path[i + 1][0] - path[i - 1][0], path[i + 1][1] - path[i - 1][1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        w = w0 + (w1 - w0) * (i / (n - 1) if n > 1 else 0.0)
        left.append((x + nx * w / 2, y + ny * w / 2))
        right.append((x - nx * w / 2, y - ny * w / 2))
    return left + right[::-1]


def sp(pts):
    return [(x * S, y * S) for x, y in pts]


def fill(d, pts, color, edge=None, ew=1.3):
    q = sp(pts)
    if len(q) < 3:
        return
    d.polygon(q, fill=color)
    if edge:
        d.line(q + [q[0]], fill=edge, width=max(1, int(round(ew * S * EDGE_K))), joint="curve")


def curve_fill(d, pts, color, edge=None, ew=1.3, seg=10):
    fill(d, catmull(pts, seg=seg, closed=True), color, edge, ew)


def ellipse(d, box, color, edge=None, ew=1.2):
    q = [box[0] * S, box[1] * S, box[2] * S, box[3] * S]
    d.ellipse(q, fill=color,
              outline=edge, width=max(1, int(round(ew * S * EDGE_K))) if edge else 0)


def stroke(d, pts, w0, w1, color, edge=None, ew=0.9, seg=12):
    q = sp(ribbon(pts, w0, w1, seg=seg))
    d.polygon(q, fill=color)
    if edge:
        d.line(q + [q[0]], fill=edge, width=max(1, int(round(ew * S * EDGE_K))), joint="curve")


def wash(img, pts, color):
    tmp = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(tmp).polygon(sp(pts), fill=color)
    img.alpha_composite(tmp)


def layer():
    img = Image.new("RGBA", (W * S, W * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


# -------------------------------------------------------------------- parts

def p_head(img, d):
    # 1) 后脑发团：bob 侧视剪影。
    #    原型改：母版 y=40 处宽度只剩 9px（就是脖子），说明发尾到 y≈37 就结束了；
    #    rig 原来拖到 y=47，在 y=40-48 一带凭空多出 17-19px，是第二大偏差项。
    #    同时后脑收紧到 x=52.4（母版 y=24 处头宽 25px，原型要贴近这个值）。
    back = [(66.0, 9.0), (60.0, 6.6), (55.2, 9.2), (52.8, 16.0), (52.4, 23.0),
            (53.2, 29.0), (55.6, 33.6), (59.0, 36.4), (62.4, 36.8), (64.8, 34.6),
            (66.0, 29.0), (66.2, 23.0), (66.2, 16.0)]
    curve_fill(d, back, HAIR, INK_EDGE, 1.3, seg=10)

    # 2) 面部：近侧脸（约 75°侧转）。
    #    原型改：前后径从 21px 收到 17px。可见头宽 = 发团后缘到脸前缘，
    #    脸太宽会把发团盖掉（上一版就缩成一条细条）。母版脸 14px / 发团 13px。
    face = [(63.6, 13.0), (68.9, 12.0), (74.2, 14.2), (77.6, 19.4), (78.9, 25.2),
            (79.1, 29.2), (80.0, 33.2), (77.9, 34.8), (78.8, 37.2), (79.5, 39.4),
            (77.3, 40.2), (76.1, 42.8), (73.9, 45.4), (69.8, 46.4), (65.2, 45.2),
            (63.1, 38.0), (62.8, 26.0), (63.1, 18.0)]
    curve_fill(d, face, SKIN, INK_EDGE, 1.2, seg=8)

    # 3) 头顶 + 刘海：后缘跟随后脑缩到 54，前缘 78.6 给前额留檐口
    cap = [(54.0, 20.0), (54.4, 13.0), (57.4, 8.0), (62.4, 5.6), (68.6, 5.4),
           (73.4, 8.4), (76.4, 13.4), (77.8, 19.0), (77.6, 22.6)]
    cap += [(74.6, 19.8), (72.0, 24.0), (68.6, 20.4), (65.0, 23.8),
            (61.4, 20.6), (57.6, 23.6), (54.8, 21.0), (54.2, 23.0)]
    curve_fill(d, cap, HAIR, INK_EDGE, 1.1, seg=8)

    # 4) 鬓发：贴颊的一缕，把"头发/脸"的直边界改成曲线
    stroke(d, [(66.0, 21.0), (67.4, 29.4), (66.0, 38.2)], 4.2, 1.6, HAIR)
    # 颈后发尾：原版拖到 y=42.6，但母版 y=40 处只剩脖子 9px（x 60-68），
    # 这条发尾在左侧凭空多出 14px。母版发型是短发，颈后不该有垂发。
    # stroke(d, [(56.0, 34.0), (56.2, 39.4), (58.0, 42.6)], 3.8, 1.8, HAIR)

    # 5) 五官：侧视只有近侧一只眼。不画眉毛——128px 下眉/眼会糊成一条黑带
    stroke(d, [(69.3, 31.4), (72.3, 33.4), (75.2, 31.2)], 2.2, 1.9, CREASE)  # 闭目
    ellipse(d, (74.4, 24.2, 76.6, 26.8), GOLD)                        # 眉间朱砂
    stroke(d, [(77.2, 39.8), (78.8, 39.6)], 1.2, 1.0, CREASE)         # 口
    # 鼻底暗部
    wash(img, catmull([(77.0, 34.2), (78.7, 34.8), (77.4, 36.6), (76.2, 35.4)],
                      seg=6, closed=True), (198, 178, 154, 130))


def p_crown(img, d):
    # 原型改：母版是宽冠（约头宽 3/4）+ 五尖，旧的只有 16px 宽三尖，缩得像个发卡。
    # 头缩窄后冠也要跟着缩，居中对齐新头中轴 x=67
    pts = [(56.6, 8.0), (56.2, 3.6), (59.6, 5.6), (62.2, 1.2), (64.6, 5.4),
           (67.0, 0.2), (69.4, 5.4), (71.8, 1.2), (74.4, 5.6), (77.8, 3.6),
           (77.4, 8.0)]
    fill(d, pts, GOLD, INK_EDGE, 1.1)
    stroke(d, [(57.0, 7.3), (67.0, 7.6), (77.0, 7.3)], 1.1, 1.1, GOLD_D)


def p_torso(img, d):
    # 颈：侧视略偏后，只露出一小段
    fill(d, [(63.0, 42.6), (72.2, 43.8), (72.8, 52.0), (63.4, 52.0)],
         SKIN, INK_EDGE, 1.0)
    stroke(d, [(64.8, 45.6), (64.6, 51.0)], 1.2, 1.0, (206, 188, 166, 255))

    # 袍身：肩窄、胸腹微丰、腰微收。
    # 原型改：下缘从 86.5 收到 74 —— 腰线抬高，让裙从 y=70 开始展开（母版腰线更高）。
    body = [(58.4, 46.0), (72.6, 46.2), (77.0, 52.6), (77.2, 62.0), (76.6, 70.0),
            (75.0, 74.0), (56.0, 74.0), (54.4, 68.0), (53.8, 62.0), (55.6, 51.0)]
    curve_fill(d, body, INK, INK_EDGE, 1.4, seg=12)

    # 背侧皴笔（让墨块有体积，不是剪纸）：与描边同墨，只降不透明度，不得更深
    stroke(d, [(56.4, 55.0), (55.2, 64.0), (56.8, 72.0)], 2.8, 1.4,
           INK_EDGE[:3] + (200,))

    # 交领：从颈后斜向前胸的纸色宽带，侧视下的主要明度分割
    stroke(d, [(65.0, 45.4), (70.6, 51.0), (75.2, 58.2)], 5.6, 4.6,
           PAPER, INK_EDGE, 1.0)
    stroke(d, [(66.6, 46.6), (71.6, 51.8), (75.6, 58.0)], 1.0, 0.8, GOLD_D)

    # 前襟内衬（比袍身亮一档，避免整片死黑）
    curve_fill(d, [(70.0, 58.0), (76.2, 58.4), (75.2, 72.4), (69.8, 72.4)],
               INK_SLEEVE, None, 0, seg=8)

    # 腰部横向衣褶
    stroke(d, [(56.8, 68.0), (64.0, 70.2), (73.4, 68.2)], 1.3, 0.9,
           CREASE[:3] + (210,))


def p_hem_front(img, d):
    # 原型 D：前后片合并成**一片裙**。
    # 母版裙是一整片连续伞形，rig 的两片拼不出这个轮廓——不管怎么调曲线，
    # 只要还是两片，腰部必然有一条缝，剪影就永远差一截。
    #
    # 逐行剖面校准（母版 / 本版）：
    #   y=72  40px / 40px   母版腰线更高、展开更早（旧版这里只有 26px，差 14）
    #   y=104 48px / 48px   下摆宽对齐
    #   y=112  9px / —      母版裙已收尾只剩脚；本版裙终于 108，脚露出（用户要求"到小腿露脚"）
    curve_fill(d, [(52.0, 70.0), (77.0, 70.6), (86.0, 76.0), (85.0, 94.0),
                   (85.0, 106.4), (62.0, 107.2), (39.0, 106.4), (38.0, 94.0),
                   (42.0, 78.0), (48.0, 72.6)],
               INK, INK_EDGE, 1.3, seg=12)
    # 下摆金边：母版最有辨识度的元素
    stroke(d, [(84.2, 102.6), (72.0, 106.8), (50.0, 106.2), (39.4, 98.0)],
           2.8, 2.2, GOLD)
    # 褶向：浅于描边，只做两三条长线，母版褶皱极少
    stroke(d, [(70.0, 78.0), (73.0, 92.0), (72.6, 105.0)], 1.4, 0.9,
           CREASE[:3] + (200,))
    stroke(d, [(52.0, 76.0), (43.0, 90.0), (40.0, 103.0)], 1.3, 0.9,
           CREASE[:3] + (170,))


def p_hem_back(img, d):
    # 原型 D：内容合并进 p_hem_front，这里留空（部件文件仍需存在，rig 有引用）
    pass


def p_gold_line(img, d):
    # 前襟金线：沿袍身前缘下行，侧视下勾出"正面在哪一侧"
    # 原型改：止于新腰线 y=74（旧的到 82，会压到裙上）
    stroke(d, [(74.4, 47.6), (76.4, 57.0), (75.4, 66.0), (73.8, 74.0)],
           1.1, 1.8, GOLD)


def p_sash_1(img, d):
    # 腰带：侧视只见横过腰的一段
    # 原型改：整体上移 6px —— 腰线从 80 抬到 74，腰带跟着走，否则会掉在裙中间
    stroke(d, [(52.8, 73.2), (58.0, 72.4), (63.6, 72.6)], 3.8, 3.2,
           GOLD, GOLD_D, 0.7)
    # 结，略偏后（原型改：缩小，原来 6x6 的球占了腰中间，读成"腰带系歪了"）
    ellipse(d, (56.6, 71.4, 61.0, 75.8), GOLD, GOLD_D, 0.8)
    stroke(d, [(57.6, 73.4), (60.2, 74.4)], 0.9, 0.8, GOLD_D)
    # 垂带向后拖
    stroke(d, [(56.4, 75.8), (51.6, 81.0), (50.0, 86.4), (48.2, 90.8)],
           3.6, 1.4, GOLD, GOLD_D, 0.7)


def p_sash_2(img, d):
    # 原型改：跟随腰线上移 6px
    stroke(d, [(54.4, 78.4), (50.4, 83.8), (49.2, 88.2)], 3.2, 1.2, GOLD_D)


def p_arm_upper(img, d, cx, body, ew, cuff, ext, w=5.0):
    """袖（侧视）。ext = 袖根向 -x 多伸的量，防止抬臂时肩部露缝。

    原型改：远侧袖原来伸到 x=46.2，在 y=48-56 一带凭空多出 19px 宽度
    （母版该处只有 16px）。远侧袖本应被躯干遮住，只露一条边——现在用 w 参数
    分档：近侧 w=5.0（可见主体），远侧 w=3.2 + ext 0.8（露出降到 4px）。
    """
    pts = [(cx - w - ext, 46.4), (cx + w, 47.2), (cx + w * 1.15, 61.8),
           (cx + w * 0.9, 66.8), (cx - w * 0.9, 66.8), (cx - w * 1.1, 59.6)]
    curve_fill(d, pts, body, INK_EDGE, ew, seg=10)
    # 前缘受光细线：袖与袍同色同值会糊成一片，靠这道极细的高光分开
    stroke(d, [(cx + w * 0.9, 48.4), (cx + w * 1.12, 56.6), (cx + w * 0.94, 63.4)],
           0.9, 0.7, (88, 81, 73, 210))
    # 金袖口
    curve_fill(d, [(cx - w * 1.08, 61.8), (cx + w * 1.12, 62.0),
                   (cx + w * 0.9, 66.8), (cx - w * 0.9, 66.8)],
               cuff, INK_EDGE, 0.8, seg=6)
    # 袖褶
    stroke(d, [(cx - 2.4, 48.6), (cx - 3.0, 57.2)], 1.3, 1.0, CREASE)


def p_arm_lower(img, d, cx, skin, ew):
    # 前臂：粗短，止于髋上方。再细就是一根白棍，读不成手
    stroke(d, [(cx + 0.4, 63.2), (cx + 1.2, 72.2), (cx + 1.4, 78.2)],
           7.2, 5.8, skin, INK_EDGE, ew)
    ellipse(d, (cx - 2.2, 77.4, cx + 5.4, 84.4), skin, INK_EDGE, ew)
    # 腕饰
    stroke(d, [(cx - 2.0, 76.4), (cx + 4.0, 76.8)], 1.5, 1.3, GOLD_D)


def p_thigh(img, d, cx, skin, ew):
    stroke(d, [(cx, 85.4), (cx - 0.8, 95.0), (cx - 0.6, 104.6)],
           9.8, 7.8, skin, INK_EDGE, ew)


def p_shin(img, d, cx, skin, ew):
    stroke(d, [(cx - 0.6, 100.6), (cx - 0.8, 108.6), (cx - 1.0, 115.6)],
           7.4, 5.6, skin, INK_EDGE, ew)
    # 脚：脚尖朝 +x
    fill(d, [(cx - 3.8, 112.8), (cx + 0.8, 112.4), (cx + 9.6, 115.2),
             (cx + 10.6, 118.8), (cx + 8.6, 120.0), (cx - 3.4, 120.0),
             (cx - 5.0, 116.4)],
         skin, INK_EDGE, ew)
    stroke(d, [(cx - 3.2, 113.2), (cx + 6.2, 113.8)], 1.3, 1.0, GOLD_D)


PARTS = [
    # name, z, 绘制
    ("leg_far_shin",   0, lambda i, d: p_shin(i, d, LEG_FAR_X, SKIN_FAR, 1.1)),
    ("leg_far_thigh",  1, lambda i, d: p_thigh(i, d, LEG_FAR_X, SKIN_FAR, 1.1)),
    ("arm_far_lower",  2, lambda i, d: p_arm_lower(i, d, ARM_FAR_X, SKIN_FAR, 1.1)),
    ("arm_far_upper",  3, lambda i, d: p_arm_upper(i, d, ARM_FAR_X, INK_FAR, 1.2, GOLD_D, 0.8, 3.2)),
    ("leg_near_thigh", 4, lambda i, d: p_thigh(i, d, LEG_NEAR_X, SKIN, 1.3)),
    ("leg_near_shin",  5, lambda i, d: p_shin(i, d, LEG_NEAR_X, SKIN, 1.3)),
    ("hem_back",       6, p_hem_back),
    ("torso",          8, p_torso),
    ("hem_front",      9, p_hem_front),
    ("sash_2",        10, p_sash_2),
    ("sash_1",        11, p_sash_1),
    ("gold_line",     12, p_gold_line),
    ("arm_near_lower", 13, lambda i, d: p_arm_lower(i, d, ARM_NEAR_X, SKIN, 1.3)),
    ("arm_near_upper", 14, lambda i, d: p_arm_upper(i, d, ARM_NEAR_X, INK_SLEEVE, 1.3, GOLD, 1.8, 5.0)),
    ("head",          16, p_head),
    ("crown",         17, p_crown),
]

PIVOTS = {
    "crown": (CENTER, HEAD_TOP),
    "head": (CENTER, HEAD_BOT),
    # 注意：躯干下缘从 86.5 收到 74，理论上枢轴该提到 74，
    # 但枢轴与 build_rig.gd 的骨架坐标绑定，单独改会让 poses.json 对不齐。
    # 本原型先留旧值（HIP_Y=88，旋转 10° 甩 2.4px，可接受），落地时与 rig 同步再提。
    "torso": (CENTER, HIP_Y),
    "hem_back": HEM_PIVOT,
    "hem_front": HEM_PIVOT,
    "sash_1": SASH1,
    "sash_2": SASH2,
    "gold_line": (CENTER, HIP_Y),
    "arm_near_upper": (ARM_NEAR_X, SHOULDER_Y),
    "arm_near_lower": (ARM_NEAR_X, ELBOW_Y),
    "arm_far_upper": (ARM_FAR_X, SHOULDER_Y),
    "arm_far_lower": (ARM_FAR_X, ELBOW_Y),
    "leg_near_thigh": (LEG_NEAR_X, HIP_Y),
    "leg_near_shin": (LEG_NEAR_X, KNEE_Y),
    "leg_far_thigh": (LEG_FAR_X, HIP_Y),
    "leg_far_shin": (LEG_FAR_X, KNEE_Y),
}


def premul_resize(img, size):
    return img.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def main():
    os.makedirs(ROOT, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    made, order = {}, []
    for name, z, fn in PARTS:
        img, d = layer()
        fn(img, d)
        small = premul_resize(img, (W, W))
        small.save(os.path.join(ROOT, "char_shihung_part_%s.png" % name))
        made[name] = small
        order.append((z, name))

    comp = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    for z, name in sorted(order):
        comp.alpha_composite(made[name])
    comp.save(os.path.join(PREVIEW, "char_shihung_rest_composite.png"))
    comp.resize((W * 4, W * 4), Image.NEAREST).save(
        os.path.join(PREVIEW, "char_shihung_rest_composite_4x.png"))

    spec = {
        "canvas": W,
        "feet_y": 120,
        # 视角声明（docs/art/README.md 规则 G-3）：side = 横版侧视，front = 正视（NPC）
        "view_class": "side",
        "view": "side, facing +x",
        "flippable": True,
        "generator": "tools/gen_parts.py",
        "draw_order": [n for _, n in sorted(order)],
        "pivots": {k: list(v) for k, v in PIVOTS.items()},
    }
    with open(os.path.join(ROOT, "parts.json"), "w", encoding="utf-8") as f:
        json.dump(spec, f, ensure_ascii=False, indent=2)

    # 静止姿三档：2x 细节 / 1x 原始 / 0.5x 屏上真实尺寸（= rig.scale）
    # 底色改游戏内深蓝，中灰底会让提亮后的袍身撞成一片
    pad = 12
    sheet_w = pad + 256 + pad + 128 + pad + 64 + pad
    sheet_h = pad + 256 + pad
    sheet = Image.new("RGB", (sheet_w, sheet_h), (20, 32, 50))
    x = pad
    for s in (256, 128, 64):
        im = comp.resize((s, s), Image.LANCZOS)
        sheet.paste(im, (x, pad + (256 - s) // 2), im)
        x += s + pad
    sheet.save(os.path.join(PREVIEW, "char_shihung_rest_sheet.png"))

    # 部件分解图：按包围盒居中 + 红叉标枢轴
    from PIL import ImageDraw as _ID
    cols, cell = 4, 112
    grid = Image.new("RGB", (cols * cell, 4 * cell), (118, 122, 130))
    gd = _ID.Draw(grid)
    for i, (z, name) in enumerate(sorted(order)):
        im = made[name]
        box = im.split()[3].point(lambda v: 255 if v > 8 else 0).getbbox()
        if box is None:
            continue
        crop = im.crop(box)
        s = min(1.0, 92.0 / max(crop.width, crop.height))
        if s < 1.0:
            crop = crop.resize((max(1, int(crop.width * s)),
                                max(1, int(crop.height * s))), Image.LANCZOS)
        cx = (i % cols) * cell + cell // 2
        cy = (i // cols) * cell + cell // 2
        ox, oy = cx - crop.width // 2, cy - crop.height // 2
        grid.paste(crop, (ox, oy), crop)
        ax = ox + (PIVOTS[name][0] - box[0]) * s
        ay = oy + (PIVOTS[name][1] - box[1]) * s
        gd.line([(ax - 4, ay), (ax + 4, ay)], fill=(220, 60, 60))
        gd.line([(ax, ay - 4), (ax, ay + 4)], fill=(220, 60, 60))
    grid.resize((grid.width * 2, grid.height * 2), Image.LANCZOS).save(
        os.path.join(PREVIEW, "char_shihung_parts_grid.png"))
    print("done: %d parts" % len(order))


if __name__ == "__main__":
    main()
