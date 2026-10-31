"""把 IoU 拆成「位置误差」和「形状误差」。

如果最佳平移后 IoU 明显上升，说明角色在画布里站的位置不同（可一键对齐）；
如果平移后仍低，说明是造型本身差——那只能重画。

同时输出逐行宽度剖面：看清是"头大"还是"裙宽"造成的不重合。
"""
import os
from PIL import Image

ART = r"C:\Users\Administrator\Desktop\GodTime\.workbuddy\art-out"
CUR = r"C:\Users\Administrator\Desktop\GodTime\assets\characters\shihung\preview\char_shihung_rest_composite.png"
PRO = os.path.join(ART, "proto_preview", "char_shihung_rest_composite.png")
MAS = os.path.join(ART, "master_128.png")


def mask(im):
    px = im.load()
    return [[1 if px[x, y][3] >= 100 else 0 for x in range(128)] for y in range(128)]


def iou(a, b):
    inter = uni = 0
    for y in range(128):
        for x in range(128):
            av, bv = a[y][x], b[y][x]
            if av and bv:
                inter += 1
            if av or bv:
                uni += 1
    return inter / uni if uni else 0


def shifted(m, dx, dy):
    out = [[0] * 128 for _ in range(128)]
    for y in range(128):
        for x in range(128):
            sy, sx = y - dy, x - dx
            if 0 <= sy < 128 and 0 <= sx < 128:
                out[y][x] = m[sy][sx]
    return out


def best_shift(a, b, r=10):
    best = (-1, 0, 0)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            v = iou(a, shifted(b, dx, dy))
            if v > best[0]:
                best = (v, dx, dy)
    return best


mm = {n: mask(Image.open(p).convert("RGBA"))
      for n, p in (("现状", CUR), ("原型", PRO), ("母版", MAS))}

print("平移对齐测试（搜索 ±10px）")
for n in ("现状", "原型"):
    v0 = iou(mm[n], mm["母版"])
    v, dx, dy = best_shift(mm[n], mm["母版"])
    print(f"  {n}: 原始 {v0:.3f} -> 最佳 {v:.3f}（母版需平移 dx={dx}, dy={dy}）  "
          f"提升 {v - v0:+.3f}")

print("\n逐行宽度剖面（不透明像素的 x 范围与宽度，每 8 行）")
print(f"{'y':>4}  {'现状 范围/宽':<22}{'原型 范围/宽':<22}{'母版 范围/宽':<22}")
for y in range(0, 128, 8):
    row = []
    for n in ("现状", "原型", "母版"):
        xs = [x for x in range(128) if mm[n][y][x]]
        row.append(f"{min(xs)}-{max(xs)}/{max(xs)-min(xs)+1}" if xs else "-")
    print(f"{y:>4}  {row[0]:<22}{row[1]:<22}{row[2]:<22}")

print("\n整体包围盒")
for n in ("现状", "原型", "母版"):
    xs = [x for y in range(128) for x in range(128) if mm[n][y][x]]
    ys = [y for y in range(128) for x in range(128) if mm[n][y][x]]
    print(f"  {n}: x {min(xs)}-{max(xs)}（宽 {max(xs)-min(xs)+1}）  "
          f"y {min(ys)}-{max(ys)}（高 {max(ys)-min(ys)+1}）")
