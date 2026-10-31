"""从定稿母版 master_128.png 采样描边/头发/袍身的真实明度关系。

目的：handoff T1 表里 INK_EDGE / CREASE 的新值是估的，需要用母版实测来定。
母版是 AI 出的「thick ink outline + flat color」，它给出的层间关系就是目标。
"""
import os
from collections import Counter
from PIL import Image

ROOT = r"C:\Users\Administrator\Desktop\GodTime\.workbuddy\art-out"
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


im = Image.open(os.path.join(ROOT, "master_128.png")).convert("RGBA")
W, H = im.size
px = im.load()

# 只取不透明像素
body = []
for y in range(H):
    for x in range(W):
        r, g, b, a = px[x, y]
        if a > 200:
            body.append((r, g, b))

print("不透明像素数：", len(body))

# 明度直方图（按 sRGB 灰度值分箱，便于理解）
gray = [round(0.299 * r + 0.587 * g + 0.114 * b) for r, g, b in body]
hist = Counter(g // 8 * 8 for g in gray)
print("\n灰度分布（按 8 为步长，只列占比 >0.5% 的箱）：")
total = len(gray)
for k in sorted(hist):
    pct = hist[k] / total * 100
    if pct > 0.5:
        bar = "#" * int(pct)
        print(f"  {k:3d}-{k+7:3d}  {pct:5.1f}%  {bar}")

# 关键分位
gray_sorted = sorted(gray)
def q(p):
    return gray_sorted[min(len(gray_sorted) - 1, int(len(gray_sorted) * p))]

print("\n灰度分位：")
for p in (0.02, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.98):
    print(f"  P{int(p*100):02d} = {q(p)}")

# 最暗的一撮 = 描边 / 头发
darkest = [c for c in body if round(0.299*c[0] + 0.587*c[1] + 0.114*c[2]) <= q(0.05)]
avg = tuple(round(sum(c[i] for c in darkest) / len(darkest)) for i in range(3))
print("\n最暗 5%（描边+头发）平均色：", avg, f" 对天空 {cr(avg, SKY):.2f}:1")

# 主色（P50 附近）
mid = [c for c in body if abs(round(0.299*c[0]+0.587*c[1]+0.114*c[2]) - q(0.50)) <= 4]
avg_mid = tuple(round(sum(c[i] for c in mid) / len(mid)) for i in range(3))
print("P50 附近（袍身）平均色：", avg_mid, f" 对天空 {cr(avg_mid, SKY):.2f}:1")

# 头发区：取角色上部 1/4 的不透明像素
hair = []
for y in range(int(H * 0.05), int(H * 0.28)):
    for x in range(W):
        r, g, b, a = px[x, y]
        if a > 200:
            hair.append((r, g, b))
if hair:
    g_avg = round(sum(0.299*c[0]+0.587*c[1]+0.114*c[2] for c in hair) / len(hair))
    print(f"\n上部 1/4 区域（头/冠）平均灰度：{g_avg}")

print("\n" + "=" * 70)
print("关键比值：描边 vs 袍身 = %.2f : 1" % cr(avg, avg_mid))
print("这意味着 gen_parts.py 的 INK_EDGE 对新袍身的合理倍数参考此值。")
