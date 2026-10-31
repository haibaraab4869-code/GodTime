"""原型 vs 现状 vs 母版：三列并排 + 剪影 IoU 与近黑占比。

判定指标（都是相对母版的差距，越小越好）：
  IoU      剪影重合度，目标 >= 0.75
  dark%    近黑像素占比，母版 10.5%，现状 35.7%
  body CR  袍身对天空对比度，要求 >= 3.0
"""
import os
from PIL import Image

ART = r"C:\Users\Administrator\Desktop\GodTime\.workbuddy\art-out"
CUR = r"C:\Users\Administrator\Desktop\GodTime\assets\characters\shihung\preview\char_shihung_rest_composite.png"
PRO = os.path.join(ART, "proto_preview", "char_shihung_rest_composite.png")
MAS = os.path.join(ART, "master_128.png")
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


def mask(im, thr=100):
    px = im.load()
    return [[1 if px[x, y][3] >= thr else 0 for x in range(128)] for y in range(128)]


def iou(a, b):
    inter = sum(a[y][x] & b[y][x] for y in range(128) for x in range(128))
    uni = sum(a[y][x] | b[y][x] for y in range(128) for x in range(128))
    return inter / uni if uni else 0


def near_dark_pct(im):
    px = im.load()
    tot = dk = 0
    for y in range(128):
        for x in range(128):
            r, g, b, a = px[x, y]
            if a >= 200:
                tot += 1
                if 0.299 * r + 0.587 * g + 0.114 * b <= 60:
                    dk += 1
    return dk / tot * 100 if tot else 0


def body_cr(im):
    """取最大中性灰色块（袍身）算对天空对比度，避免被描边/肤色干扰。"""
    px = im.load()
    from collections import Counter
    cnt = Counter()
    for y in range(128):
        for x in range(128):
            r, g, b, a = px[x, y]
            if a >= 200 and max(r, g, b) - min(r, g, b) < 20:
                g0 = 0.299 * r + 0.587 * g + 0.114 * b
                if g0 > 70:
                    cnt[(r, g, b)] += 1
    if not cnt:
        return None, 0
    col = cnt.most_common(1)[0][0]
    return col, cr(col, SKY)


imgs = [(n, Image.open(p).convert("RGBA")) for n, p in
        (("现状 rig", CUR), ("原型", PRO), ("AI 母版", MAS))]
mm = {n: mask(im) for n, im in imgs}

print("%-10s %8s %8s %10s %12s" % ("版本", "IoU", "近黑%", "袍身色", "对天空CR"))
for n, im in imgs:
    col, c = body_cr(im)
    print("%-10s %8.3f %8.1f %10s %12.2f" % (n, iou(mm[n], mm["AI 母版"]),
                                             near_dark_pct(im), str(col), c))

# 三列并排
S = 4
pad = 10
W = 128 * S * 3 + pad * 2
canvas = Image.new("RGB", (W, 128 * S), SKY)
for i, (n, im) in enumerate(imgs):
    big = im.resize((128 * S, 128 * S), Image.NEAREST)
    canvas.paste(big, (i * (128 * S + pad), 0), big)
canvas.save(os.path.join(ART, "proto_vs_current_vs_master.png"))
print("\n出图：proto_vs_current_vs_master.png（左 现状 / 中 原型 / 右 母版）")
