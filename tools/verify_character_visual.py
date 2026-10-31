# -*- coding: utf-8 -*-
"""主角视觉 v1 验收：墨色阶 WCAG 对比度 + 合成图/截图主色采样。

依据 docs/development/handoff-character-visual-v1.md §4 T1 / §5 验收口径。
只读 tools/gen_parts.py 的常量与生成的 PNG，不改任何资产。
用法：
  python tools/verify_character_visual.py [--image path.png]
"""
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PREVIEW = ROOT / "assets/characters/shihung/preview"
PARTS = ROOT / "assets/characters/shihung/parts"
SKY = (20, 32, 50)          # #142032 现在·天空
SKY_PAST = (32, 40, 73)     # #202849 过去·天空
TOL = 8


def srgb(v):
    v = v / 255.0
    return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4


def lum(rgb):
    r, g, b = rgb[:3]
    return 0.2126 * srgb(r) + 0.7152 * srgb(g) + 0.0722 * srgb(b)


def cr(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def constants():
    text = (ROOT / "tools/gen_parts.py").read_text(encoding="utf-8")
    names = ["INK_FAR", "INK_BACK", "INK", "INK_SLEEVE", "HAIR", "INK_EDGE",
             "CREASE", "GOLD", "GOLD_D", "SKIN", "SKIN_FAR", "PAPER"]
    out = {}
    for n in names:
        m = re.search(r"^%s\s*=\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)" % n, text, re.M)
        if not m:
            raise SystemExit("常量缺失: %s" % n)
        out[n] = tuple(int(x) for x in m.groups())
    return out


def near(a, b, tol=TOL):
    return all(abs(int(x) - int(y)) <= tol for x, y in zip(a[:3], b[:3]))


def mode_color(img, box=None, min_alpha=200, exclude=()):
    """返回区域内不透明像素的众数颜色（按出现次数降序，取首个不被排除的）。"""
    im = img.crop(box) if box else img
    counts = {}
    for count, (r, g, b, a) in im.getcolors(1 << 24) or []:
        if a < min_alpha:
            continue
        if any(near((r, g, b), e) for e in exclude):
            continue
        counts[(r, g, b)] = counts.get((r, g, b), 0) + count
    if not counts:
        return None
    return max(counts.items(), key=lambda kv: kv[1])


def main():
    const = constants()
    ink = const["INK"]
    checks = []

    def check(ok, label):
        checks.append((bool(ok), label))
        print("%s %s" % ("PASS" if ok else "FAIL", label))

    print("== 墨色阶对 #142032 ==")
    for name in ["INK_FAR", "INK_BACK", "INK", "INK_SLEEVE", "HAIR", "INK_EDGE", "CREASE"]:
        c = const[name]
        print("%-11s rgb%-16s CR(天空)=%5.2f  CR(袍身)=%5.2f"
              % (name, str(c), cr(c, SKY), cr(c, ink)))

    check(cr(const["INK"], SKY) >= 3.0, "袍身 INK 对天空 >= 3.0 (%.2f)" % cr(const["INK"], SKY))
    check(cr(const["INK_SLEEVE"], SKY) >= 4.0,
          "近侧袖 INK_SLEEVE 对天空 >= 4.0 (%.2f)" % cr(const["INK_SLEEVE"], SKY))
    check(cr(const["GOLD"], SKY) >= 6.0, "金饰 GOLD 对天空 >= 6.0 (%.2f)" % cr(const["GOLD"], SKY))
    check(lum(const["CREASE"]) > lum(const["INK_EDGE"]),
          "CREASE 比 INK_EDGE 浅（褶皱不比外轮廓重）")
    check(cr(const["INK_EDGE"], ink) >= 2.5,
          "描边 INK_EDGE 对袍身可读 (%.2f)" % cr(const["INK_EDGE"], ink))
    check(lum(const["INK_FAR"]) < lum(const["INK"]), "远侧肢体仍暗于袍身")
    check(lum(const["INK_BACK"]) < lum(const["INK"]), "后片裙摆仍暗于袍身")
    check(lum(const["INK_SLEEVE"]) > lum(const["INK"]), "近侧袖亮于袍身一档")

    golds = (const["GOLD"], const["GOLD_D"], const["SKIN"], const["SKIN_FAR"], const["PAPER"])
    for name, want in [("GOLD", (198, 158, 44)), ("GOLD_D", (146, 112, 24)),
                       ("SKIN", (250, 239, 222)), ("SKIN_FAR", (214, 202, 186)),
                       ("PAPER", (248, 240, 227))]:
        check(const[name] == want, "%s 未被改动 %s" % (name, str(want)))

    # 静态守卫：绘制函数里不得再出现比描边更黑的字面色（褶皱/内衬读成脏点的成因）
    text = (ROOT / "tools/gen_parts.py").read_text(encoding="utf-8")
    edge_lum = lum(const["INK_EDGE"])
    offenders = []
    for lineno, line in enumerate(text.splitlines(), 1):
        if re.match(r"^[A-Z_]+\s*=", line):
            continue
        for m in re.finditer(r"\((\d{1,3}),\s*(\d{1,3}),\s*(\d{1,3})(?:,\s*(\d{1,3}))?", line):
            alpha = m.group(4)
            if alpha is not None and int(alpha) == 0:
                continue
            rgb = tuple(int(x) for x in m.groups()[:3])
            if lum(rgb) < edge_lum * 0.98:
                offenders.append((lineno, rgb))
    for lineno, rgb in offenders:
        print("  L%d rgb%s 比描边更黑" % (lineno, str(rgb)))
    check(not offenders, "绘制函数内无比描边更黑的字面色（%d 处）" % len(offenders))

    print("\n== 合成图采样 ==")
    comp = Image.open(PREVIEW / "char_shihung_rest_composite.png").convert("RGBA")
    excl = golds + (const["INK_EDGE"], const["CREASE"], const["HAIR"])
    body = mode_color(comp, box=(54, 46, 78, 88), exclude=excl)
    whole = mode_color(comp)
    if body:
        print("袍身区域主色 rgb%s  x%d  对天空 CR=%.2f"
              % (str(body[0]), body[1], cr(body[0], SKY)))
        check(cr(body[0], SKY) >= 3.0, "合成图袍身主色对天空 >= 3.0 (%.2f)" % cr(body[0], SKY))
    if whole:
        print("整图主色   rgb%s  x%d  对天空 CR=%.2f"
              % (str(whole[0]), whole[1], cr(whole[0], SKY)))
        check(not near(whole[0], (16, 16, 8), 4), "整图主色不再是 rgb(16,16,8)")

    sleeve = mode_color(Image.open(PARTS / "char_shihung_part_arm_near_upper.png").convert("RGBA"),
                        exclude=excl)
    if sleeve:
        print("近侧袖部件主色 rgb%s  对天空 CR=%.2f" % (str(sleeve[0]), cr(sleeve[0], SKY)))
        check(cr(sleeve[0], SKY) >= 4.0, "近侧袖部件主色对天空 >= 4.0 (%.2f)" % cr(sleeve[0], SKY))

    args = sys.argv[1:]
    if "--image" in args:
        shot = Image.open(args[args.index("--image") + 1]).convert("RGBA")
        print("\n== 实机截图采样 %s (%dx%d) ==" % (Path(args[args.index('--image') + 1]).name,
                                                   shot.width, shot.height))
        s_body = mode_color(shot, exclude=golds + (const["INK_EDGE"], const["CREASE"],
                                                   const["HAIR"], SKY))
        s_whole = mode_color(shot)
        if s_body:
            print("截图袍身主色 rgb%s  x%d  CR=%.2f"
                  % (str(s_body[0]), s_body[1], cr(s_body[0], SKY)))
        if s_whole:
            print("截图整幅主色 rgb%s  x%d（背景 #142032 应占多数）" % (str(s_whole[0]), s_whole[1]))

    bad = [c for c in checks if not c[0]]
    print("\nCHECKS=%d FAILURES=%d" % (len(checks), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
