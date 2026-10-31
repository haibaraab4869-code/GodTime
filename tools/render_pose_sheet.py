# -*- coding: utf-8 -*-
"""把 Godot 导出的骨骼姿态渲染成评审图（离线，无需开窗口）。

读 tools/export_poses.gd 产出的 poses.json，按 z 序合成部件，
输出 4 帧 x 9 clip 的姿态表，用于确认动画没有穿模/飞散。

坐标变换要点：
  贴图里的美术是按"静止枢轴"画的，骨骼当前位置只是该枢轴的落点。
  正确变换 = 先把美术绕**静止枢轴**旋转，再把该枢轴平移到骨骼当前位置。
  若直接用骨骼当前位置当旋转中心（早期版本的 bug），偏移小的部件看着没问题，
  大角度挥臂时才会暴露——前臂会从袖子末端飘出去。
"""
import json
import math
import os
from PIL import Image, ImageDraw

PARTS_DIR = r"C:\Users\Administrator\Desktop\GodTime\assets\characters\shihung\parts"
PREVIEW = r"C:\Users\Administrator\Desktop\GodTime\assets\characters\shihung\preview"
POSES = os.path.join(os.environ["APPDATA"], "Godot", "app_userdata",
                     "时间之神 - 探索原型", "poses.json")
CANVAS = 128

# 与游戏内底色一致（ai-prompt-spec §12.5 第 5 步：贴 #142032 看分离度）。
# 旧值是中灰底，提亮后的袍身会与它撞成一片，评审图失去意义。
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
    """art 已缩放到 canvas 尺寸；rest/cur 为 1x 画布坐标。"""
    th = math.radians(rot_deg)
    c, sn = math.cos(th), math.sin(th)
    rx, ry = rest[0] * scale, rest[1] * scale
    ux, uy = cur[0] * scale, cur[1] * scale
    # 输出坐标 -> 输入坐标 的逆仿射
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
    return canvas.convert("RGBA")


def main():
    with open(POSES, "r", encoding="utf-8") as f:
        data = json.load(f)
    pivots = load_pivots()
    os.makedirs(PREVIEW, exist_ok=True)

    S = 3
    imgs = load_parts(S)
    clips = list(data["clips"].keys())
    cell = 128 * S + 12
    cols = 4
    head = 30
    sheet = Image.new("RGB", (cols * cell + 16, len(clips) * (cell + head) + 16), BG)
    d = ImageDraw.Draw(sheet)

    for ci, clip in enumerate(clips):
        info = data["clips"][clip]
        y0 = 16 + ci * (cell + head)
        d.text((10, y0 - 14), "%s  (%.2fs)" % (clip, info["length"]), fill=LABEL)
        for fi, fr in enumerate(info["frames"]):
            img = render_frame(fr["parts"], imgs, pivots, S)
            x = 8 + fi * cell
            sheet.paste(img, (x, y0 + 6), img)

    sheet.save(os.path.join(PREVIEW, "char_shihung_pose_sheet.png"))
    print("pose sheet:", sheet.size)
    # 静止姿对照图不在这里出：它属于纯美术评审，由 tools/gen_parts.py 负责。
    # 两个脚本都写同一个文件会互相覆盖成不同尺寸。


if __name__ == "__main__":
    main()
