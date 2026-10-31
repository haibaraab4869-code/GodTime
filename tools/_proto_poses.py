"""用现有 rig 的姿态数据（poses.json）渲染**原型部件**，检查动画是否还成立。

重点看：改了部件形状、但枢轴没动的情况下，
  · 躯干（下缘 86.5→74，枢轴仍在 88）转动时会不会甩出去
  · 合并成一片的裙（hem_front 承载全部裙形）转动是否自然
  · 远侧袖收窄后，抬臂会不会露缝
"""
import json
import math
import os
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PARTS_DIR = r"C:\Users\Administrator\Desktop\GodTime\.workbuddy\art-out\proto_parts"
OUT = r"C:\Users\Administrator\Desktop\GodTime\.workbuddy\art-out\proto_preview\proto_poses.png"
POSES = os.path.join(os.environ["APPDATA"], "Godot", "app_userdata",
                     "时间之神 - 探索原型", "poses.json")
CANVAS = 128
BG = (20, 32, 50)
LABEL = (196, 202, 178)


def load_pivots():
    with open(os.path.join(PARTS_DIR, "parts.json"), "r", encoding="utf-8") as f:
        return {k: tuple(v) for k, v in json.load(f)["pivots"].items()}


def load_parts(scale=1):
    out = {}
    for fn in os.listdir(PARTS_DIR):
        if fn.startswith("char_shihung_part_") and fn.endswith(".png"):
            name = fn[len("char_shihung_part_"):-4]
            im = Image.open(os.path.join(PARTS_DIR, fn)).convert("RGBA")
            if scale != 1:
                im = im.resize((CANVAS * scale, CANVAS * scale), Image.LANCZOS)
            out[name] = im
    return out


def place(canvas, art, rest, cur, rot_deg, scale=1):
    th = math.radians(rot_deg)
    c, sn = math.cos(th), math.sin(th)
    rx, ry = rest[0] * scale, rest[1] * scale
    ux, uy = cur[0] * scale, cur[1] * scale
    data = (c, sn, rx - c * ux - sn * uy,
            -sn, c, ry + sn * ux - c * uy)
    out = art.transform((CANVAS * scale, CANVAS * scale), Image.AFFINE, data,
                        resample=Image.BICUBIC)
    canvas.alpha_composite(out)


def render_frame(parts, imgs, pivots, scale=1):
    canvas = Image.new("RGBA", (CANVAS * scale, CANVAS * scale), (0, 0, 0, 0))
    for p in sorted(parts, key=lambda q: q["z"]):
        art = imgs.get(p["n"])
        rest = pivots.get(p["n"])
        if art is None or rest is None:
            continue
        place(canvas, art, rest, p["p"], math.degrees(p["r"]), scale)
    return canvas


with open(POSES, "r", encoding="utf-8") as f:
    data = json.load(f)
pivots = load_pivots()

S = 2
imgs = load_parts(S)
clips = list(data["clips"].keys())
cell = CANVAS * S + 8
cols = 4
head = 22
sheet = Image.new("RGB", (cols * cell + 12, len(clips) * (cell + head) + 12), BG)
d = ImageDraw.Draw(sheet)

for ci, clip in enumerate(clips):
    info = data["clips"][clip]
    y0 = 12 + ci * (cell + head)
    d.text((8, y0 - 12), "%s (%.2fs)" % (clip, info["length"]), fill=LABEL)
    for fi, fr in enumerate(info["frames"][:cols]):
        img = render_frame(fr["parts"], imgs, pivots, S)
        sheet.paste(img, (6 + fi * cell, y0 + 4), img)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
sheet.save(OUT)
print("出图：", OUT, sheet.size)
