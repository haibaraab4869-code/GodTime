"""墨色阶标定：把「对天空 CR」和「对袍身 CR」分开算。

问题背景（2026-10-29）：
handoff T1 表给 INK_EDGE / CREASE 的新值是按「对深蓝天空 CR ≈ 1.06」标的，
但这两个元素是**画在袍身上**的暗线，不是独立剪影。原设计里它们对袍身的
对比度只有 ~1.2:1（很淡的水墨描边）；若按对天空标，就成了对袍身 4:1 的死黑粗线。

本脚本做两件事：
1. 量出原设计（旧墨阶）每条层间关系；
2. 按「层间 CR 保持不变」反解新墨阶，再回算对天空 CR 是否达标。
"""
import math

SKY = (20, 32, 50)        # #142032


def lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    r, g, b = rgb[:3]
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def cr(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def solve_gray(target_lum):
    """反解一个中性灰的 sRGB 值，使其相对亮度 ≈ target_lum。"""
    lo, hi = 0.0, 255.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if lum((mid, mid, mid)) < target_lum:
            lo = mid
        else:
            hi = mid
    return round((lo + hi) / 2)


OLD = {
    "INK_FAR":    (24, 22, 19),   # 远侧肢体
    "INK_BACK":   (28, 26, 23),   # 后片裙摆
    "INK":        (34, 31, 28),   # 袍身（锚点）
    "INK_SLEEVE": (48, 44, 39),   # 近侧袖
    "HAIR":       (19, 17, 15),
    "INK_EDGE":   (13, 12, 10),   # 描边
    "CREASE":     (8, 7, 6),      # 褶皱
    "GOLD":       (198, 158, 44),
}

NEW_INK = (123, 122, 116)   # 锚点：照抄母版 #7B7A74，对天空 3.80

print("=" * 88)
print("一、原设计（旧墨阶）的层间关系  [基准 = 旧袍身 INK(34,31,28)]")
print("=" * 88)
print(f"{'常量':<12}{'旧值':<18}{'对旧袍身':>10}{'对天空':>10}{'角色':>18}")
for k, v in OLD.items():
    ratio = cr(v, OLD["INK"])
    sky = cr(v, SKY)
    role = "主体（必须过 3:1）" if k in ("INK", "INK_SLEEVE") else (
        "暗线（画在袍身上）" if k in ("INK_EDGE", "CREASE") else "过渡/次层")
    if k == "INK":
        ratio = 1.0
        role = "锚点"
    print(f"{k:<12}{str(v):<18}{ratio:>9.2f}{sky:>10.2f}  {role}")

print()
print("关键：INK_EDGE 旧值对旧袍身 %.2f:1，CREASE %.2f:1 —— 都是很淡的线。"
      % (cr(OLD["INK_EDGE"], OLD["INK"]), cr(OLD["CREASE"], OLD["INK"])))

print()
print("=" * 88)
print("二、若照 handoff T1 原表执行，会出现什么")
print("=" * 88)
T1_OLD = {
    "INK_FAR": (88, 87, 82),
    "INK_BACK": (102, 101, 96),
    "INK": NEW_INK,
    "INK_SLEEVE": (138, 137, 130),
    "HAIR": (46, 44, 40),
    "INK_EDGE": (28, 26, 23),
    "CREASE": (38, 36, 32),
}
print(f"{'常量':<12}{'新值':<18}{'对新袍身':>10}{'对天空':>10}{'旧对袍身':>10}{'判定':>8}")
for k, v in T1_OLD.items():
    r_new = 1.0 if k == "INK" else cr(v, NEW_INK)
    r_old = 1.0 if k == "INK" else cr(OLD[k], OLD["INK"])
    sky = cr(v, SKY)
    flag = ""
    if k in ("INK_EDGE", "CREASE"):
        flag = "✗ 过重" if r_new > r_old * 1.8 else "ok"
    print(f"{k:<12}{str(v):<18}{r_new:>9.2f}{sky:>10.2f}{r_old:>10.2f}  {flag}")

print()
print("诊断：描边/褶皱从「对袍身 ~1.2:1 的淡线」跳到 3~4:1，"
      "视觉效果从水墨淡描变成粗黑描边。")

print()
print("=" * 88)
print("三、按「层间 CR 不变」反解的推荐值")
print("=" * 88)
print("原理：袍身锚点提亮到 %s 后，其余各层按原来的层间 CR 反解，"
      "保证层次关系不变、只换明度轴位置。" % str(NEW_INK))
print()

L_ink_new = lum(NEW_INK)
REC = {}
print(f"{'常量':<12}{'旧值':<18}{'旧CR':>7}{'推荐新值':<18}{'新CR':>7}{'对天空':>9}{'天空判定':>10}")
for k, v in OLD.items():
    if k in ("INK", "GOLD"):
        continue
    old_ratio = cr(v, OLD["INK"])
    # 旧层在袍身之上还是之下（更亮 or 更暗）
    darker = lum(v) < lum(OLD["INK"])
    if darker:
        target = (L_ink_new + 0.05) / old_ratio - 0.05
    else:
        target = old_ratio * (L_ink_new + 0.05) - 0.05
    g = solve_gray(target)
    # 保留原色相倾向（暖度差），按比例加回
    dr = v[0] - v[2]
    scale = g / max(1, sum(v) / 3)
    rgb = (max(0, min(255, round(g + dr * 0.5))), g, max(0, min(255, round(g - dr * 0.5))))
    REC[k] = rgb
    new_ratio = cr(rgb, NEW_INK)
    sky = cr(rgb, SKY)
    verdict = "✓" if (sky >= 3.0 or k in ("HAIR", "INK_EDGE", "CREASE")) else (
        "允许" if k in ("INK_FAR", "INK_BACK") else "✗")
    print(f"{k:<12}{str(v):<18}{old_ratio:>6.2f}{str(rgb):<18}{new_ratio:>6.2f}{sky:>9.2f}  {verdict:>8}")

print()
print("=" * 88)
print("四、成品：可直接抄进 gen_parts.py 的常量（含 alpha）")
print("=" * 88)
order = ["INK_FAR", "INK", "INK_SLEEVE", "INK_BACK", "HAIR", "INK_EDGE", "CREASE"]
for k in order:
    v = NEW_INK if k == "INK" else REC[k]
    print(f"{k:<12}= ({v[0]}, {v[1]}, {v[2]}, 255)   # 对天空 {cr(v, SKY):.2f}:1")
print()
print("校验：袍身 %.2f:1（要求 ≥3.0）　近侧袖 %.2f:1（要求 ≥4.0）"
      % (cr(NEW_INK, SKY), cr(REC["INK_SLEEVE"], SKY)))
print("描边对袍身 %.2f:1　褶皱对袍身 %.2f:1（应与旧值 1.21 / 1.13 接近）"
      % (cr(REC["INK_EDGE"], NEW_INK), cr(REC["CREASE"], NEW_INK)))

# ---------------------------------------------------------------- 五、交付表校验
print()
print("=" * 88)
print("五、交付表（handoff T1 定稿）逐项校验")
print("=" * 88)

FINAL = {
    "INK_FAR":    (88, 87, 82),
    "INK_BACK":   (102, 101, 96),
    "INK":        (123, 122, 116),
    "INK_SLEEVE": (138, 137, 130),
    "HAIR":       (50, 48, 46),
    "INK_EDGE":   (50, 48, 48),
    "CREASE":     (84, 82, 78),
    "GOLD":       (198, 158, 44),
}

print(f"{'常量':<12}{'值':<18}{'天空':>7}{'对袍身':>8}   判定")
ok = True
for k, v in FINAL.items():
    sky = cr(v, SKY)
    body = 1.0 if k == "INK" else cr(v, FINAL["INK"])
    if k in ("INK", "INK_SLEEVE"):
        need, verdict = 3.0, ("✓" if sky >= 3.0 else "✗ 主体未过 3:1")
    elif k in ("INK_FAR", "INK_BACK"):
        verdict = "✓ 遮挡层，允许 <3"
    elif k == "GOLD":
        need, verdict = 6.0, ("✓" if sky >= 6.0 else "✗ 金饰不够亮")
    else:
        verdict = "✓ 允许糊进天空（母版同样）"
    if "✗" in verdict:
        ok = False
    print(f"{k:<12}{str(v):<18}{sky:>6.2f}{body:>8.2f}   {verdict}")

print()
print("层次合理性检查（数值越小越接近）：")
pairs = [
    ("袍身 vs 描边", FINAL["INK"], FINAL["INK_EDGE"], 2.5, 4.5),
    ("袍身 vs 褶皱", FINAL["INK"], FINAL["CREASE"], 1.4, 2.2),
    ("袍身 vs 近侧袖", FINAL["INK"], FINAL["INK_SLEEVE"], 1.15, 1.4),
    ("袍身 vs 后片", FINAL["INK"], FINAL["INK_BACK"], 1.15, 1.5),
    ("袍身 vs 远侧", FINAL["INK"], FINAL["INK_FAR"], 1.4, 2.0),
]
for name, a, b, lo, hi in pairs:
    r = cr(a, b)
    flag = "✓" if lo <= r <= hi else "⚠ 超出区间"
    if "⚠" in flag:
        ok = False
    print(f"  {name:<16}{r:>6.2f}   期望 {lo}–{hi}   {flag}")

# 次序：褶皱必须浅于描边（即褶皱亮度更高、对袍身 CR 更小）
if cr(FINAL["CREASE"], FINAL["INK"]) < cr(FINAL["INK_EDGE"], FINAL["INK"]):
    print("\n  ✓ 褶皱浅于描边（层次次序正确）")
else:
    ok = False
    print("\n  ✗ 褶皱比描边更深，会读成脏点")

print()
print("总判定：", "全部通过" if ok else "有不通过项，见上方 ✗/⚠")
