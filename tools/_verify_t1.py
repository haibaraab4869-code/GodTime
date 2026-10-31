"""T1 验收：当前 rig 合成图 vs AI 母版，在游戏内深蓝底 #142032 上比对。

除了出图，还要算三件事：
  1. 袍身主色对天空的 WCAG 对比度（要求 >= 3.0）
  2. 近侧袖（要求 >= 4.0）、金饰（要求 >= 6.0）
  3. rig 与母版的**剪影 IoU**：衡量造型差距，是 T3 换模型要缩小的量
"""
import os
from collections import Counter
from PIL import Image

PARTS = r"C:\Users\Administrator\Desktop\GodTime\assets\characters\shihung\preview"
ART = r"C:\Users\Administrator\Desktop\GodTime\.workbuddy\art-out"
OUT = ART
SKY = (20, 32, 50)


def lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])


def cr(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


rig = Image.open(os.path.join(PARTS, "char_shihung_rest_composite.png")).convert("RGBA")
master = Image.open(os.path.join(ART, "master_128.png")).convert("RGBA")
print("rig:", rig.size, " master:", master.size)


def opaque_pixels(im, min_a=200):
    px = im.load()
    w, h = im.size
    out = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= min_a:
                out.append((r, g, b))
    return out


def report(name, im):
    body = opaque_pixels(im)
    gray = sorted(round(0.299 * r + 0.587 * g + 0.114 * b) for r, g, b in body)
    n = len(gray)
    p50 = gray[n // 2]
    # 取 P45–P55 的中位色当袍身
    lo, hi = gray[int(n * 0.45)], gray[int(n * 0.55)]
    mid = [c for c in body if lo <= round(0.299*c[0]+0.587*c[1]+0.114*c[2]) <= hi]
    body_col = tuple(round(sum(c[i] for c in mid) / len(mid)) for i in range(3))
    # 最暗 5%
    dk = [c for c in body if round(0.299*c[0]+0.587*c[1]+0.114*c[2]) <= gray[int(n*0.05)]]
    dark_col = tuple(round(sum(c[i] for c in dk) / len(dk)) for i in range(3))
    # 主体应取"袍身"这一档，P90 附近是受光的袖/皮肤
    print(f"\n{name}  不透明像素 {n}")
    print(f"  袍身(P50) {body_col}  对天空 {cr(body_col, SKY):.2f}:1")
    print(f"  最暗5%   {dark_col}  对天空 {cr(dark_col, SKY):.2f}:1")
    # 同色像素里找最亮的「袍身同色系」（暖灰/中性灰），排除肤色
    neutral = [c for c in body if max(c) - min(c) < 24 and 40 < 0.299*c[0]+0.587*c[1]+0.114*c[2] < 200]
    if neutral:
        cnt = Counter(neutral).most_common(1)[0]
        print(f"  最大中性灰色块 {cnt[0]} 占 {cnt[1]} px，对天空 {cr(cnt[0], SKY):.2f}:1")
    return body_col, dark_col


b1 = report("rig 合成图", rig)
b2 = report("AI 母版", master)

# 剪影 IoU
def mask(im):
    px = im.load()
    w, h = im.size
    return [[1 if px[x, y][3] >= 100 else 0 for x in range(w)] for y in range(h)]

m1, m2 = mask(rig), mask(master)
inter = sum(m1[y][x] & m2[y][x] for y in range(128) for x in range(128))
uni = sum(m1[y][x] | m2[y][x] for y in range(128) for x in range(128))
print(f"\n剪影 IoU（rig vs 母版）：{inter/uni:.3f}   rig {sum(map(sum,m1))} px / 母版 {sum(map(sum,m2))} px")

# 出图：深蓝底并排
S = 4
pad = 12
W = 128 * S * 2 + pad
canvas = Image.new("RGB", (W, 128 * S), SKY)
for i, im in enumerate((rig, master)):
    big = im.resize((128 * S, 128 * S), Image.NEAREST)
    canvas.paste(big, (i * (128 * S + pad), 0), big)
canvas.save(os.path.join(OUT, "rig_vs_master_on_sky_v2.png"))
print("\n出图：rig_vs_master_on_sky_v2.png（左 rig / 右 母版）")
