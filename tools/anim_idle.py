"""
anim_idle.py —— 待机序列帧生成器（设计侧工具，纯后期，不调用模型）

为什么是程序化而不是 AI 逐帧
------------------------------
实测（2026-10-29，本机 ComfyUI + Illustrious-XL v2.0 + qsuimo-000005）：
  · img2img denoise ≤0.58：剪影 IoU 0.96–0.98，形锁得住，但姿势几乎不动，
    逐帧差异集中在轮廓线上（重绘噪声），播出来是"抖"不是"动"；
  · img2img denoise ≥0.68：灰袍漂成橄榄绿、金腰带退化成游离棒状物、袍身膨胀，
    形与色同时崩。
结论：AI 只负责出母版（定造型/风格/比例），运动交给位移场合成。

原理
----
唯一画源 → 每帧只是同一张图的位移采样 → 帧间零重绘 → 零闪烁。
运动 = 正弦位移场，周期 N 帧，f(0) 与 f(N) 同相位，循环天然闭合（实测闭合差 = 0）。

用法
----
  python tools/anim_idle.py            # 用默认母版出 12 帧
  python tools/anim_idle.py --heads 3  # 顺便把头身比校正到 3.0 再出
产物全部落在 .workbuddy/art-out/，不写 assets/、不写 game/。
"""

import argparse
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, ".workbuddy", "art-out")
SRC_DEFAULT = os.path.join(ART, "master_128.png")

PAPER = (248, 240, 227)
SKY = (20, 32, 50)
FPS = 12

# ---- 母版实测几何（128 画布）----
FOOT_Y = 120.0
CX = 64.0
BODY_H = 116.0
CROWN_Y = 4.0
NECK_Y = 37.5

# ---- 运动幅度 ----
A_BREATH = 0.0240   # 垂直呼吸缩放：全身高波动约 5 px
A_CHEST = 0.0220    # 胸腔横向扩张
A_HEM = 3.0         # 袍摆横向摆幅 px
A_HEAD = 1.1        # 头部滞后横移 px
LAG_HEM = 1.05
LAG_HEAD = 0.50
ASYM = 0.08         # 相位非对称：吸气快、呼气慢


def _warp(src, sx, sy):
    """双线性重采样（premultiplied alpha，避免边缘黑边）"""
    H, W = src.shape[:2]
    a0 = src[..., 3:4]
    prem = np.concatenate([src[..., :3] * a0, a0], axis=2)
    x0 = np.floor(sx).astype(np.int32)
    y0 = np.floor(sy).astype(np.int32)
    fx = sx - x0
    fy = sy - y0
    x0c, x1c = np.clip(x0, 0, W - 1), np.clip(x0 + 1, 0, W - 1)
    y0c, y1c = np.clip(y0, 0, H - 1), np.clip(y0 + 1, 0, H - 1)
    inside = (sx >= -0.5) & (sx <= W - 0.5) & (sy >= -0.5) & (sy <= H - 0.5)
    out = np.empty_like(prem)
    for c in range(4):
        ch = prem[..., c]
        out[..., c] = (ch[y0c, x0c] * (1 - fx) * (1 - fy) + ch[y0c, x1c] * fx * (1 - fy) +
                       ch[y1c, x0c] * (1 - fx) * fy + ch[y1c, x1c] * fx * fy)
    out[~inside] = 0.0
    a = np.clip(out[..., 3], 0.0, 1.0)
    rgb = np.zeros_like(out[..., :3])
    nz = a > 1e-6
    rgb[nz] = out[nz][:, :3] / a[nz][:, None]
    return np.concatenate([np.clip(rgb, 0, 1), a[..., None]], axis=2)


def chibi(src, target_heads):
    """把母版头身比校正到 target_heads（总高与脚底基线不变：头放大、颈下压缩）

    锚点约定：冠顶固定 y=4；新颈位 = 冠顶 + 新头高；颈下绕脚底压缩。
    横向只放大头部，颈下保持原宽（否则长袍会被压成漏斗）。
    """
    head_now = NECK_Y - CROWN_Y
    body = FOOT_Y - CROWN_Y
    new_head = body / target_heads
    s_up = new_head / head_now                  # 头部放大
    s_dn = (body - new_head) / (body - head_now)  # 颈下压缩
    neck_new = CROWN_Y + new_head
    # 混合带放在下颌（NECK_Y-3）而不是颈中，否则颈部会跟着头部一起被拉长
    jaw_new = neck_new - 3.0
    H, W = src.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    sy_up = CROWN_Y + (yy - CROWN_Y) / s_up     # 绕冠顶放大
    sy_dn = FOOT_Y - (FOOT_Y - yy) / s_dn       # 绕脚底压缩
    w = np.clip((yy - jaw_new) / 3.0, 0.0, 1.0)
    sy = sy_up * (1 - w) + sy_dn * w
    sx = CX + (xx - CX) * ((1 - w) * s_up + w * 1.0)
    return _warp(src, sx, sy)


def _phase(t):
    return t - ASYM * math.sin(2.0 * math.pi * t)


def make_frame(src, k, n, foot_y=FOOT_Y, cx=CX, body_h=BODY_H):
    t = (k % n) / float(n)
    ph = 2.0 * math.pi * _phase(t)
    breath = math.sin(ph)
    hem = math.sin(ph - LAG_HEM)
    head = math.sin(ph - LAG_HEAD)

    H, W = src.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)

    sy = foot_y - (foot_y - yy) * (1.0 - A_BREATH * breath)
    u = np.clip((foot_y - sy) / body_h, 0.0, 1.0)

    hem_w = np.clip((0.58 - u) / 0.58, 0.0, 1.0) ** 1.7
    sx = xx + hem_w * A_HEM * hem

    head_w = np.clip((u - 0.70) / 0.30, 0.0, 1.0)
    sx = sx + head_w * A_HEAD * head

    chest_w = np.exp(-((u - 0.56) ** 2) / (2 * 0.11 ** 2))
    sx = sx + (xx - cx) * A_CHEST * breath * chest_w

    return (np.clip(_warp(src, sx, sy), 0, 1) * 255).astype(np.uint8)


def measure(mask):
    """返回 (头高, 全身高, 脚底y, 质心x, 质心y)。

    颈部定位：只在「头顶下方 12%–50% 身高」这段固定窗口里找行宽极小。
    旧版用「宽度 > 50% max 的第一行」做起点，一旦下摆被拉开（run 的跨步）
    最大行宽会变，起点跟着漂，颈就量错——实测头高会从 34 跳到 56。
    """
    ys, xs = np.nonzero(mask)
    top, bot = ys.min(), ys.max()
    rows = mask.sum(axis=1).astype(float)
    sm = np.convolve(rows, np.ones(3) / 3, mode="same")
    span = bot - top
    lo = top + int(span * 0.12)
    hi = top + int(span * 0.50)
    seg = sm[lo:hi]
    neck = lo + int(np.argmin(seg))
    return neck - top, bot - top + 1, bot, xs.mean(), ys.mean()


def verify(frames, label="", loop=True, base_exempt=False, closure=None,
           gate_smooth=True, gate_head=True):
    """一致性断言。

    loop        循环片段才检查接缝；非循环片段的「末帧→首帧」本来就不该像
    base_exempt 位移类片段（jump/fall/dash/era_switch）豁免脚底基线
    closure     程序化产线的闭合差（像素级，应为 0）。给了 closure 就以它为准，
                接缝 IoU 降级为参考值——闭合差 0 已经证明循环严格无缝
    gate_smooth 蓄意大幅形变的片段（squash/impulse）只报数不判定——
                C5/C6 的阈值是为稳态循环推出来的，套到压缩帧上必然误判
    gate_head   压缩/拉伸片段（jump/respawn/land）头高本来就会变，不判定 C1
    """
    masks = [np.asarray(f.split()[-1]) > 8 for f in frames]
    n = len(masks)
    info = [measure(m) for m in masks]
    head = [i[0] for i in info]
    by = [i[2] for i in info]
    adj = []
    for k in range(n):
        a, b = masks[k], masks[(k + 1) % n]
        adj.append(float(np.logical_and(a, b).sum()) / float(np.logical_or(a, b).sum()))
    dmax = 0.0
    for k in range(n):
        a, b = info[k], info[(k + 1) % n]
        dmax = max(dmax, math.hypot(a[3] - b[3], a[4] - b[4]))
    seam = float(np.logical_and(masks[n - 1], masks[0]).sum()) / float(
        np.logical_or(masks[n - 1], masks[0]).sum())

    rows = []
    rows.append(("头高一致性", "Δ ≤ 3px" if gate_head else "参考值",
                 "%.0f–%.0f (Δ%d)" % (min(head), max(head), max(head) - min(head)),
                 (max(head) - min(head) <= 3) if gate_head else True))
    rows.append(("脚底基线", "120 ± 1px（位移类豁免）", "%.0f–%.0f" % (min(by), max(by)),
                 True if base_exempt else (max(by) - min(by) <= 2)))
    rows.append(("相邻帧剪影 IoU", "≥ 0.72" if gate_smooth else "参考值",
                 "%.3f–%.3f" % (min(adj), max(adj)),
                 (min(adj) >= 0.72) if gate_smooth else True))
    rows.append(("相邻帧质心位移", "≤ 6.3px" if gate_smooth else "参考值",
                 "%.2f px" % dmax, (dmax <= 6.3) if gate_smooth else True))
    if not loop:
        rows.append(("循环接缝 IoU", "—（非循环）", "—", True))
    elif closure is not None:
        rows.append(("循环接缝 IoU", "参考值（闭合差=0 已足够）", "%.3f" % seam, True))
    else:
        rows.append(("循环接缝 IoU", "≥ 0.90", "%.3f" % seam, seam >= 0.90))
    if closure is not None:
        rows.append(("循环闭合差", "0", str(closure), closure == 0))

    print("\n[%s] 一致性校验" % (label or "frames"))
    print("  %-16s %-24s %-18s %s" % ("指标", "门槛", "实测", "判定"))
    for a, b, c, ok in rows:
        tag = "PASS" if ok else "FAIL"
        if b.startswith("参考值"):
            tag = "n/a"
        print("  %-16s %-24s %-18s %s" % (a, b, c, tag))
    return all(r[3] for r in rows)


def export(frames, outdir, tag):
    os.makedirs(outdir, exist_ok=True)
    for k, f in enumerate(frames):
        f.save(os.path.join(outdir, "%s_%02d.png" % (tag, k)))

    def comp(im, scale, bgc):
        bg = Image.new("RGBA", im.size, bgc + (255,))
        bg.alpha_composite(im)
        if scale != 1:
            bg = bg.resize((im.width * scale, im.height * scale), Image.NEAREST)
        return bg.convert("RGB")

    for scale, bgc, name in ((4, PAPER, "paper"),):
        g = [comp(f, scale, bgc) for f in frames]
        g[0].save(os.path.join(ART, "%s_preview_%s.gif" % (tag, name)), save_all=True,
                  append_images=g[1:], duration=int(1000 / FPS), loop=0, optimize=False)
    gd = [comp(f, 4, SKY) for f in frames]
    gd[0].save(os.path.join(ART, "%s_preview_dark.gif" % tag), save_all=True,
               append_images=gd[1:], duration=int(1000 / FPS), loop=0, optimize=False)

    cell = 256
    cols = min(6, len(frames))
    rows_ = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGB", (cell * cols, (cell + 20) * rows_), (255, 255, 255))
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(frames):
        x = (i % cols) * cell
        y = (i // cols) * (cell + 20)
        sheet.paste(comp(f, 2, PAPER), (x, y + 20))
        d.text((x + 6, y + 5), "%s f%02d" % (tag, i), fill=(0, 0, 0))
    sheet.save(os.path.join(ART, "%s_sheet.png" % tag))
    print("frames -> %s" % outdir)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC_DEFAULT)
    ap.add_argument("--n", type=int, default=12, help="帧数（12 帧 @12fps = 1s 循环）")
    ap.add_argument("--heads", type=float, default=0.0, help="校正头身比，如 3.0；0 = 不改")
    ap.add_argument("--tag", default="idle")
    args = ap.parse_args()

    src = np.asarray(Image.open(args.src).convert("RGBA")).astype(np.float64) / 255.0
    if args.heads > 0:
        src = chibi(src, args.heads)
        print("头身比已校正到 %.2f" % args.heads)

    frames = [Image.fromarray(make_frame(src, k, args.n), "RGBA") for k in range(args.n)]
    # 闭合校验：f(N) 应与 f(0) 完全相同
    a0 = np.asarray(frames[0]).astype(np.int16)
    aN = make_frame(src, args.n, args.n).astype(np.int16)
    print("循环闭合最大差: %d（0 = 严格闭合）" % int(np.abs(a0 - aN).max()))

    verify(frames, args.tag)
    export(frames, os.path.join(ART, "%s_128" % args.tag), args.tag)


if __name__ == "__main__":
    main()
