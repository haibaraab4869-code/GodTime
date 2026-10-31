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
ROOT = r"C:\Users\Administrator\Desktop\GodTime\assets\characters\shihung\parts"
PREVIEW = r"C:\Users\Administrator\Desktop\GodTime\assets\characters\shihung\preview"

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
SASH1 = (58, 80)
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
        d.line(q + [q[0]], fill=edge, width=max(1, int(round(ew * S))), joint="curve")


def curve_fill(d, pts, color, edge=None, ew=1.3, seg=10):
    fill(d, catmull(pts, seg=seg, closed=True), color, edge, ew)


def ellipse(d, box, color, edge=None, ew=1.2):
    q = [box[0] * S, box[1] * S, box[2] * S, box[3] * S]
    d.ellipse(q, fill=color,
              outline=edge, width=max(1, int(round(ew * S))) if edge else 0)


def stroke(d, pts, w0, w1, color, edge=None, ew=0.9, seg=12):
    q = sp(ribbon(pts, w0, w1, seg=seg))
    d.polygon(q, fill=color)
    if edge:
        d.line(q + [q[0]], fill=edge, width=max(1, int(round(ew * S))), joint="curve")


def wash(img, pts, color):
    tmp = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(tmp).polygon(sp(pts), fill=color)
    img.alpha_composite(tmp)


def layer():
    img = Image.new("RGBA", (W * S, W * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


# -------------------------------------------------------------------- parts

def p_head(img, d):
    # 1) 后脑发团：bob 侧视剪影。前缘推到 x=66 —— 侧视下后脑勺本来就占半个头
    back = [(66.0, 9.0), (58.0, 7.6), (50.6, 11.0), (46.0, 17.4), (44.0, 26.0),
            (44.6, 35.0), (47.4, 42.6), (51.2, 46.8), (55.8, 47.0), (60.4, 44.0),
            (63.4, 36.4), (65.0, 27.0), (65.6, 17.0)]
    curve_fill(d, back, HAIR, INK_EDGE, 1.3, seg=10)

    # 2) 面部：近侧脸（约 75°侧转，不是严格 90°）。
    #    严格正侧脸在 60px 屏上只剩一条竖缝，读不出脸；留 17px 颊面才认得出。
    face = [(63.6, 13.0), (70.0, 12.0), (76.2, 14.2), (80.2, 19.4), (81.8, 25.2),
            (82.0, 29.2), (83.6, 33.2), (80.6, 34.8), (81.6, 37.2), (82.4, 39.4),
            (79.8, 40.2), (78.4, 42.8), (75.8, 45.4), (71.0, 46.4), (65.6, 45.2),
            (63.2, 38.0), (62.8, 26.0), (63.2, 18.0)]
    curve_fill(d, face, SKIN, INK_EDGE, 1.2, seg=8)

    # 3) 头顶 + 刘海：前缘只到 x=78.6，给前额留出檐口
    cap = [(46.0, 20.0), (46.6, 12.0), (50.4, 7.2), (57.0, 4.8), (64.0, 4.4),
           (71.0, 5.8), (76.4, 10.0), (78.8, 16.0), (78.6, 22.6)]
    cap += [(75.6, 19.8), (72.8, 24.0), (69.2, 20.4), (65.4, 23.8),
            (61.6, 20.6), (57.6, 23.6), (53.0, 21.0), (49.4, 23.2)]
    curve_fill(d, cap, HAIR, INK_EDGE, 1.1, seg=8)

    # 4) 鬓发：贴颊的一缕，把"头发/脸"的直边界改成曲线
    stroke(d, [(66.4, 21.0), (68.0, 29.4), (66.4, 38.2)], 4.2, 1.6, HAIR)
    # 颈后发尾
    stroke(d, [(48.4, 34.0), (48.8, 41.4), (51.4, 46.2)], 4.2, 2.0, HAIR)

    # 5) 五官：侧视只有近侧一只眼。不画眉毛——128px 下眉/眼会糊成一条黑带
    stroke(d, [(70.4, 31.4), (74.0, 33.4), (77.4, 31.2)], 2.3, 2.0, CREASE)  # 闭目
    ellipse(d, (76.4, 24.2, 79.0, 26.8), GOLD)                        # 眉间朱砂
    stroke(d, [(79.6, 39.8), (81.6, 39.6)], 1.3, 1.1, CREASE)         # 口
    # 鼻底暗部
    wash(img, catmull([(79.4, 34.2), (81.4, 34.8), (79.8, 36.6), (78.4, 35.4)],
                      seg=6, closed=True), (198, 178, 154, 130))


def p_crown(img, d):
    pts = [(56.0, 8.4), (56.0, 4.2), (59.8, 6.6), (64.0, 0.4),
           (68.2, 6.6), (72.0, 4.2), (72.0, 8.4)]
    fill(d, pts, GOLD, INK_EDGE, 1.1)
    stroke(d, [(56.8, 7.7), (64.0, 8.2), (71.2, 7.7)], 1.1, 1.1, GOLD_D)


def p_torso(img, d):
    # 颈：侧视略偏后，只露出一小段
    fill(d, [(63.0, 42.6), (72.2, 43.8), (72.8, 52.0), (63.4, 52.0)],
         SKIN, INK_EDGE, 1.0)
    stroke(d, [(64.8, 45.6), (64.6, 51.0)], 1.2, 1.0, (206, 188, 166, 255))

    # 袍身：肩窄、胸腹微丰、腰微收，下缘收进裙里
    body = [(58.4, 46.0), (72.6, 46.2), (77.0, 52.6), (77.4, 64.0),
            (76.4, 76.0), (74.6, 86.5), (56.0, 86.5), (54.0, 78.0),
            (53.8, 64.0), (55.6, 51.0)]
    curve_fill(d, body, INK, INK_EDGE, 1.4, seg=12)

    # 背侧皴笔（让墨块有体积，不是剪纸）：与描边同墨，只降不透明度，不得更深
    stroke(d, [(56.4, 55.0), (55.2, 68.0), (56.8, 83.0)], 2.8, 1.4,
           INK_EDGE[:3] + (200,))

    # 交领：从颈后斜向前胸的纸色宽带，侧视下的主要明度分割
    stroke(d, [(65.0, 45.4), (70.6, 51.0), (75.2, 58.2)], 5.6, 4.6,
           PAPER, INK_EDGE, 1.0)
    stroke(d, [(66.6, 46.6), (71.6, 51.8), (75.6, 58.0)], 1.0, 0.8, GOLD_D)

    # 前襟内衬（比袍身亮一档，避免整片死黑）
    curve_fill(d, [(70.0, 60.4), (76.4, 60.8), (75.4, 84.0), (69.6, 84.0)],
               INK_SLEEVE, None, 0, seg=8)

    # 腰部横向衣褶
    stroke(d, [(56.6, 75.0), (64.0, 77.6), (73.6, 75.4)], 1.3, 0.9,
           (60, 54, 48, 210))


def p_hem_front(img, d):
    # 前片：短，收到膝上，让前小腿露出来
    curve_fill(d, [(64.4, 78.8), (74.8, 79.0), (79.6, 90.6), (78.2, 97.6),
                   (66.2, 96.2), (63.8, 88.0)],
               INK, INK_EDGE, 1.3, seg=10)
    stroke(d, [(78.4, 96.6), (72.0, 97.6), (66.4, 96.4)], 1.7, 1.4, GOLD)
    stroke(d, [(69.8, 83.0), (73.6, 91.0), (72.6, 96.2)], 1.3, 0.9,
           (58, 52, 46, 220))


def p_hem_back(img, d):
    # 后片：长，向 -x 拖出，是跑动时主要的跟动元素
    curve_fill(d, [(54.2, 78.6), (64.6, 78.8), (64.0, 96.4), (44.0, 106.0),
                   (40.6, 102.0), (49.4, 88.0)],
               INK_BACK, INK_EDGE, 1.3, seg=10)
    # 拖尾底缘
    stroke(d, [(42.6, 104.0), (53.0, 103.0), (63.4, 96.8)], 1.5, 1.0,
           (54, 48, 43, 255))
    # 褶向：必须浅于描边，否则后片上会留下比外轮廓更黑的死线
    stroke(d, [(51.0, 84.0), (45.6, 93.6), (42.6, 101.6)], 1.6, 1.0,
           CREASE[:3] + (200,))
    stroke(d, [(57.4, 82.0), (53.0, 92.0), (50.0, 100.6)], 1.2, 0.8,
           CREASE[:3] + (160,))


def p_gold_line(img, d):
    # 前襟金线：沿袍身前缘下行，侧视下勾出"正面在哪一侧"
    stroke(d, [(74.4, 47.6), (76.8, 58.6), (75.8, 70.0), (74.0, 82.0)],
           1.1, 1.8, GOLD)


def p_sash_1(img, d):
    # 腰带：侧视只见横过腰的一段
    stroke(d, [(52.4, 79.2), (58.0, 78.4), (63.4, 78.6)], 3.8, 3.2,
           GOLD, GOLD_D, 0.7)
    # 结，略偏后
    ellipse(d, (55.0, 77.0, 61.2, 83.2), GOLD, GOLD_D, 0.8)
    stroke(d, [(56.8, 79.8), (59.8, 81.0)], 0.9, 0.8, GOLD_D)
    # 垂带向后拖
    stroke(d, [(56.2, 81.8), (51.4, 87.0), (49.8, 92.4), (48.0, 96.8)],
           3.6, 1.4, GOLD, GOLD_D, 0.7)


def p_sash_2(img, d):
    stroke(d, [(54.2, 84.4), (50.2, 89.8), (49.0, 94.2)], 3.2, 1.2, GOLD_D)


def p_arm_upper(img, d, cx, body, ew, cuff, ext):
    """袖（侧视）。ext = 袖根向 -x 多伸的量，防止抬臂时肩部露缝。"""
    pts = [(cx - 5.6 - ext, 46.0), (cx + 5.4, 47.2), (cx + 6.4, 61.8),
           (cx + 5.0, 66.8), (cx - 5.0, 66.8), (cx - 6.2, 59.6)]
    curve_fill(d, pts, body, INK_EDGE, ew, seg=10)
    # 前缘受光细线：袖与袍同色同值会糊成一片，靠这道极细的高光分开
    stroke(d, [(cx + 5.0, 48.4), (cx + 6.2, 56.6), (cx + 5.2, 63.4)],
           0.9, 0.7, (88, 81, 73, 210))
    # 金袖口
    curve_fill(d, [(cx - 6.0, 61.8), (cx + 6.3, 62.0),
                   (cx + 5.0, 66.8), (cx - 5.0, 66.8)],
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
    ("arm_far_upper",  3, lambda i, d: p_arm_upper(i, d, ARM_FAR_X, INK_FAR, 1.2, GOLD_D, 2.2)),
    ("leg_near_thigh", 4, lambda i, d: p_thigh(i, d, LEG_NEAR_X, SKIN, 1.3)),
    ("leg_near_shin",  5, lambda i, d: p_shin(i, d, LEG_NEAR_X, SKIN, 1.3)),
    ("hem_back",       6, p_hem_back),
    ("torso",          8, p_torso),
    ("hem_front",      9, p_hem_front),
    ("sash_2",        10, p_sash_2),
    ("sash_1",        11, p_sash_1),
    ("gold_line",     12, p_gold_line),
    ("arm_near_lower", 13, lambda i, d: p_arm_lower(i, d, ARM_NEAR_X, SKIN, 1.3)),
    ("arm_near_upper", 14, lambda i, d: p_arm_upper(i, d, ARM_NEAR_X, INK_SLEEVE, 1.3, GOLD, 1.8)),
    ("head",          16, p_head),
    ("crown",         17, p_crown),
]

PIVOTS = {
    "crown": (CENTER, HEAD_TOP),
    "head": (CENTER, HEAD_BOT),
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
    pad = 12
    sheet_w = pad + 256 + pad + 128 + pad + 64 + pad
    sheet_h = pad + 256 + pad
    sheet = Image.new("RGB", (sheet_w, sheet_h), (118, 122, 130))
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
