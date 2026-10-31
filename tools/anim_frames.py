"""
anim_frames.py —— 11 个片段的序列帧生成器（设计侧工具，纯后期，不调模型）

沿用 anim_idle.py 的结论：唯一画源 + 位移场采样 = 帧间零重绘 = 零闪烁。
本文件把位移场拆成 7 个可调层，每个片段只给「层参数曲线」，不换画源。

层的物理含义（全部以内容位移计，+x 为角色朝向的右侧）
  vs      垂直缩放（1.0 = 原高），绕脚底锚点
  rise    整体上移 px（离地；只有 jump/era_switch 用）
  lean    前倾 px，权重随高度 1.25 次方 → 上身倾、脚不动
  hem     袍摆横向位移 px，权重随「接近下摆」1.7 次方（**整条同向摆，用于待机/飘动**）
  spread  下摆纵向下沉 px（袍身被压开时用）
  sleeve  袖摆横向位移 px，高斯权重带 u∈0.52±0.08
  head    头部横向位移 px，权重仅 u>0.70
  toe     脚尖横向位移 px，权重仅 u<0.07（**整只脚同向，老参数**）
  xs      横向缩放（1.0 = 原宽），绕身体中线

跑步腿（2026-10-29 追加，解决「看着像腰在动」）
  stride  前后腿反向张开 px：以 LEG_MID 为中轴，前侧 +、后侧 −，
          权重沿腿长从髋 0 渐变到脚底 1。**不是整体横摆**，是对称张开，
          正弦过零时回并腿 —— 这是「跨步」而不是「扭腰」
  lift_f  前脚离地 px（内容上移），权重 = 腿部纵向 × 前侧
  lift_b  后脚离地 px，权重 = 腿部纵向 × 后侧

  为什么需要 stride：母版双脚实测挤在 x=59–73（并拢 14px），
  只做整体位移永远只能读出「躯干在晃」。stride 把 14px 的脚距拉开到 24px，
  58px 屏上才读得出「一步」。

局限（必须知道，否则会误判成品）：
  纯位移场**不能换四肢姿势**——长袍把手臂和腿都盖住了，所以
  · run 是「躯干起伏 + 袍摆摆动 + 脚尖交替」，不是抬腿；
  · attack 是「袖摆横扫」，不是举手挥砍；
  · jump/fall 是「拉伸压缩 + 布摆」，不含骨骼腾空姿势。
  这些片段够做手感/节奏预览，不够当最终资产（与 §7.6 的定位一致）。
"""

import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from anim_idle import (ART, BODY_H, CX, FPS, FOOT_Y, PAPER, SKY, _warp,  # noqa: E402
                       measure, verify)

FIRST, LAST = 0.0, 1.0

# ---- 腿部几何（128 画布实测）----
# 袍摆下沿收窄于 y≈117；脚（肤色）只在 y=112–116、x=59–73 出现 → 双脚并拢
LEG_TOP = 74.0      # 髋：从这里开始允许分腿（抬腿 0，脚底 1）
FOOT_LOW = 119.0    # 脚底
LEG_MID = 66.5      # 前后腿分界中线（实测脚区 x 59–73 的中点）
LEG_HALF = 11.0     # 前后侧过渡半宽
FOOT_TOP = 106.0    # 脚部抬升权重的起算高度
NOTCH_SIG = 7.0     # 下摆中线凹陷的高斯半宽
NOTCH_TOP = 100.0   # 凹陷从这一行往下生效
GAP_TOP = 86.0      # 分片裂缝的起点（袍身中下段，不能从腰部就裂）


def _smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _leg_w(yy):
    """沿腿长的权重：髋 0 → 脚底 1（平滑）"""
    return _smooth((yy - LEG_TOP) / (FOOT_LOW - LEG_TOP))


def _front_w(xx):
    """前后侧权重：0 = 身后，1 = 身前，leg_mid 处 0.5"""
    return _smooth((xx - (LEG_MID - LEG_HALF)) / (2.0 * LEG_HALF))


def _foot_w(yy):
    """只在脚掌高度生效，避免整条腿被抬"""
    return _smooth((yy - FOOT_TOP) / (FOOT_LOW - FOOT_TOP))


def _split_legs(img, gmap):
    """按下摆中线把前后两片真实拉开，中间露出袍内侧。

    为什么不能填纯色：平涂水墨里一块硬边纯色 = 贴片，放大立刻穿帮。
    所以缝隙用「源图自身、往上取 7px 的同一列」压暗 22% 填充——
    纹理和笔触跟周围连续，读起来是深处的布而不是补丁。
    裂缝止于脚掌上沿（FOOT_TOP）：脚整体留在前片里，不会被切成两半。
    两侧各做 1px 羽化，避免硬切边。
    """
    H, W = img.shape[:2]
    out = img.copy()
    m = int(round(LEG_MID))
    for y in range(int(GAP_TOP), int(FOOT_TOP)):
        gi = int(round(gmap[y]))
        if gi < 1:
            continue
        # 分界线随高度略向后斜（髋在前、脚在后），避免一条垂直直线
        mm = m - int(round(0.10 * (y - GAP_TOP)))
        lo, hi = mm - gi, mm + gi
        if lo < 0 or hi > W:
            continue
        # 从上方 7px 取同列像素压暗 → 自己图里的纹理当阴影
        ys = max(y - 7, 0)
        band = img[ys, lo:hi].copy()
        band[..., :3] *= 0.78
        out[y, lo:hi] = band
        # 1px 羽化
        if lo - 1 >= 0:
            out[y, lo - 1, :3] = 0.5 * out[y, lo - 1, :3] + 0.5 * band[0, :3]
        if hi < W:
            out[y, hi, :3] = 0.5 * out[y, hi, :3] + 0.5 * band[-1, :3]
        # 后片左移、前片右移（脚掌以上才动）
        row = img[y]
        if mm - gi > 0:
            out[y, 0:mm - gi] = row[gi:mm]
        if W - (mm + gi) > 0:
            out[y, mm + gi:W] = row[mm:W - gi]
    return out


def _shift_legs(img, df, db, top=96.0, bot=119.0, split=58.0):
    """把跑姿图的前腿片与后腿片各自横移，做出「收拢 / 张开」的交替。

    跑姿画源的两腿实测在 x≈39 与 x≈76，中间 x≈55–62 是真空隙，
    所以按 x=58 分片不会切开布料——这是它比站姿母版可用的原因。
    前片最后画（覆盖后片），保证「前腿在前」的遮挡关系。
    位移量随 y 从 top 的 0 渐变到 bot 的满量，避免上方出现横向断口。
    """
    H, W = img.shape[:2]
    out = np.zeros_like(img)
    m = int(round(split))
    for y in range(H):
        if y < top:
            out[y] = img[y]
            continue
        t = _smooth((y - top) / (bot - top))
        row = img[y]
        orow = np.zeros_like(row)
        dbi = int(round(db * t))
        dfi = int(round(df * t))
        # 后片
        x0, x1 = 0, m
        d0, d1 = x0 + dbi, x1 + dbi
        sx0, sx1 = max(x0, x0 - dbi), min(x1, W - dbi)
        if sx1 > sx0:
            orow[sx0 + dbi:sx1 + dbi] = row[sx0:sx1]
        # 前片（覆盖）
        x0, x1 = m, W
        sx0, sx1 = max(x0, x0 - dfi), min(x1, W - dfi)
        if sx1 > sx0:
            orow[sx0 + dfi:sx1 + dfi] = row[sx0:sx1]
        # 两片分开时中间会空出一条，用袍身边缘压暗填上，否则是一道白缝
        if dfi > dbi:
            g0, g1 = max(m + dbi, 0), min(m + dfi, W)
            if g1 > g0:
                edge = row[min(m, W - 1)]
                if edge[3] > 0.5:
                    fill = edge.copy()
                    fill[:3] *= 0.68
                    orow[g0:g1] = fill
        out[y] = orow
    return out


def P(**kw):
    d = dict(vs=1.0, rise=0.0, lean=0.0, hem=0.0, spread=0.0,
             sleeve=0.0, head=0.0, toe=0.0, xs=1.0,
             stride=0.0, lift_f=0.0, lift_b=0.0, notch=0.0, gap=0.0,
             hem_f=0.0, hem_b=0.0, leg_df=0.0, leg_db=0.0)
    d.update(kw)
    return d


def render(src, p, dbg=None):
    H, W = src.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)

    # 反向映射：目标像素去源图采样。内容想「上移 d」→ 采样源图更低处 → sy = yy + d
    # 旧版写成 -rise，导致「上浮」实际是下沉（run 的腾空帧脚比触地帧还低 4px）
    sy = FOOT_Y - (FOOT_Y - yy) / p["vs"] + p["rise"]
    u = np.clip((FOOT_Y - sy) / BODY_H, 0.0, 1.0)

    sx = xx.astype(np.float64) - p["lean"] * (u ** 1.25)

    hem_w = np.clip((0.58 - u) / 0.58, 0.0, 1.0) ** 1.7
    sx = sx - p["hem"] * hem_w
    sy = sy - p["spread"] * hem_w

    # ---- 腿：前后反向张开（跨步）----
    if p["stride"]:
        side = 2.0 * _front_w(xx) - 1.0        # −1 身后 … +1 身前
        sx = sx - p["stride"] * side * _leg_w(yy)

    # ---- 下摆中线凹陷：两腿分开时布被夹在两腿之间往上提 ----
    # 光靠横向拉伸只能做出「整体变宽/变窄」（读成胖瘦抖动），
    # 下沿轮廓出现 M 形缺口才读得出「腿分开」
    if p["notch"]:
        nw = np.exp(-((xx - LEG_MID) ** 2) / (2.0 * NOTCH_SIG ** 2))
        nw = nw * _smooth((yy - NOTCH_TOP) / (FOOT_LOW - NOTCH_TOP))
        sy = sy + p["notch"] * nw

    # ---- 脚：前后交替离地 ----
    if p["lift_f"] or p["lift_b"]:
        fw = _front_w(xx)
        fwt = _foot_w(yy) * _leg_w(yy)
        sy = sy + (p["lift_f"] * fw + p["lift_b"] * (1.0 - fw)) * fwt

    # ---- 下摆前后片的纵向错位：前腿把布顶起来、后腿把布坠下去 ----
    # 只做横向平移会读成「裙子裂开」，纵向一错开才有「腿在迈」
    if p["hem_f"] or p["hem_b"]:
        fw = _front_w(xx)
        bw = _smooth((yy - GAP_TOP) / (FOOT_TOP - GAP_TOP))
        sy = sy - (p["hem_f"] * fw + p["hem_b"] * (1.0 - fw)) * bw

    head_w = np.clip((u - 0.70) / 0.30, 0.0, 1.0)
    sx = sx - p["head"] * head_w

    sl_w = np.exp(-((u - 0.52) ** 2) / (2 * 0.08 ** 2))
    sx = sx - p["sleeve"] * sl_w

    toe_w = np.clip((0.07 - u) / 0.07, 0.0, 1.0)
    sx = sx - p["toe"] * toe_w

    sx = CX + (sx - CX) / p["xs"]
    img = np.clip(_warp(src, sx, sy), 0, 1)

    # ---- 腿部分片：真实裂开（在 warp 之后做，因为它是目标图上的操作）----
    if p["gap"]:
        rows = np.arange(H, dtype=np.float64)
        gw = _smooth((rows - GAP_TOP) / (FOOT_TOP - GAP_TOP))
        img = _split_legs(img, p["gap"] * gw)

    # ---- 前后腿交替收拢/张开（跑姿画源专用）----
    if p["leg_df"] or p["leg_db"]:
        img = _shift_legs(img, p["leg_df"], p["leg_db"])

    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def ph(k, n):
    return 2.0 * math.pi * (k % n) / float(n)


def smooth(t):
    """ease-out 三次：起步快、收尾稳"""
    t = min(max(t, 0.0), 1.0)
    return 1.0 - (1.0 - t) ** 3


# ----------------------------- 片段定义 -----------------------------
# 每个函数返回该帧的层参数；非循环片段要求末帧与 idle 第 0 帧一致（全 0）

def clip_idle(k, n):
    a = ph(k, n)
    g = a - 0.08 * math.sin(a)              # 吸气快、呼气慢
    return P(vs=1.0 + 0.024 * math.sin(g),
             hem=-3.0 * math.sin(g - 1.05),
             head=-1.1 * math.sin(g - 0.50),
             sleeve=-0.6 * math.sin(g - 0.6))


RUN_AMP = 1.0           # 幅度总闸门（--amp 覆盖）
RUN_PROFILE = "breath"  # 默认：跑姿造型不动、只做待机式呼吸（用户 2026-10-29 定稿）


def _run_vivid(k, n, m):
    """大动作版：触地压 2.8% + 袖摆 ±5.4，读得出体重，也读得出晃。"""
    a = ph(k, n)
    step = 0.5 - 0.5 * math.cos(2.0 * a)
    return P(vs=1.0 - 0.028 * m * step,
             rise=1.8 * m * (1.0 - step),
             lean=2.0 + 1.8 * m * step,
             hem=-3.8 + 2.6 * m * math.sin(2.0 * a + 0.9),
             sleeve=-5.4 * m * math.sin(a),
             head=-0.6 * m * math.sin(2.0 * a - 0.3))


def _run_soft(k, n, m):
    """轻微浮动版：上下交给 rise 刚体平移，袖摆几乎不动。"""
    a = ph(k, n)
    step = 0.5 - 0.5 * math.cos(2.0 * a)
    return P(vs=1.0 - 0.008 * m * step,
             rise=1.9 * m * (1.0 - step),
             lean=1.6 + 0.6 * m * step,
             hem=-3.1 + 1.2 * m * math.sin(2.0 * a + 0.9),
             sleeve=-1.3 * m * math.sin(a),
             head=-0.3 * m * math.sin(2.0 * a - 0.3))


def _run_breath(k, n, m):
    """待机式呼吸（默认）：跑姿造型完全不动，只有躯干的呼吸缩放。

    用户原话：「袖摆和袍摆都不要晃动，只需要待机感的轻微晃动就行了」。
    所以 hem / sleeve 的脉动**严格为 0**——不是压小，是关掉；
    常值（lean 前倾 1.6、hem 后飘 −3.1）保留，它们让画面仍是「在跑」的姿势，
    而不是一张站着不动的图。
    唯一在动的是 vs：1 倍频呼吸（一圈 = 一次吸呼），绕脚底锚点，
    头顶上下约 ±1.4 px（116 × 0.012），脚底基线完全不漂。
    head 只跟一个 0.5 px 的滞后，纯粹为了不读成「缩放滤镜」，量级接近量化噪声。
    """
    a = ph(k, n)
    return P(vs=1.0 + 0.012 * m * math.sin(a),
             lean=1.6,
             hem=-3.1,
             head=-0.5 * m * math.sin(a - 0.5))


RUN_PROFILES = {"vivid": _run_vivid, "soft": _run_soft, "breath": _run_breath}


def clip_run(k, n):
    """奔行：画源用跑姿母版（runpose_128），位移场负责节奏。

    为什么不用站姿母版：站姿是直筒到地的长袍、双脚并拢 14px，
    任何纯位移/分片都只能让「布」动，读成「腰在扭」（用户实测反馈）。
    跑姿母版脚距 37px、后脚已离地 4px，跨步形状是画出来的，不需要伪造。

    三档幅度的由来（2026-10-29 一晚调了三轮，全部保留可切换）：
      vivid   触地压 2.8% + sleeve ±5.4 —— 「幅度太大，像在晃」
      soft    压到静止后重建的一版（rise 主浮动）—— 用户看完对比选回 vivid
      breath  **定稿**：用户要的其实是「跑姿造型别动、只留待机呼吸」，
              于是把 hem/sleeve 的脉动直接关掉，只留 vs 呼吸

    两条标定判据（调任何片段都适用）：
      · 常值偏移（lean 基准、hem 后飘）不产生晃动感，压它只会让角色变呆；
        晃的是乘 sin 的脉动项。
      · 晃动感的放大器是袖摆而非上下浮动。
    """
    return RUN_PROFILES[RUN_PROFILE](k, n, RUN_AMP)


def clip_jump(k, n):
    # 蹲 → 蹬 → 伸 → 顶点拉伸；末帧接 fall 首帧，不回弹
    t = k / (n - 1.0)
    curve = [(0.0, P(vs=0.930, lean=1.0, hem=-1.0, spread=1.5)),
             (0.34, P(vs=0.965, lean=2.2, hem=-1.5)),
             (0.67, P(vs=1.045, lean=1.0, toe=2.0, hem=1.5)),
             (1.0, P(vs=1.060, lean=0.5, toe=3.0, hem=2.5, sleeve=-1.5))][k] \
        if k < 4 else (t, P())
    return curve[1]


def clip_fall(k, n):
    a = ph(k, n)
    return P(vs=1.030 + 0.006 * math.sin(a),
             hem=-2.6 * math.sin(a) - 0.8,
             spread=1.0 + 0.8 * math.sin(a + 1.0),
             sleeve=-2.4 * math.sin(a + 0.7),
             head=-0.9 * math.sin(a - 0.3),
             toe=1.6)


def clip_dash(k, n):
    prog = [0.55, 0.85, 1.0][k] if k < 3 else 1.0
    return P(vs=1.0 - 0.020 * prog,
             lean=4.0 + 5.0 * prog,
             hem=-4.0 - 4.0 * prog,
             sleeve=-2.0 - 3.0 * prog,
             head=-1.5 * prog,
             toe=1.0 * prog)


def clip_attack(k, n):
    # 蓄力 → 挥出 → 收势 → 静止
    seq = [P(vs=0.985, lean=-2.2, sleeve=-6.0, hem=1.5, head=1.2),
           P(vs=1.010, lean=4.0, sleeve=9.0, hem=-3.5, head=-1.2),
           P(vs=1.000, lean=5.2, sleeve=7.0, hem=-2.0, head=-0.8),
           P()]
    return seq[k] if k < len(seq) else P()


def clip_hurt(k, n):
    seq = [P(vs=0.960, lean=-5.0, head=-2.2, hem=3.2, sleeve=2.4),
           P(vs=0.945, lean=-3.6, head=-1.6, hem=2.4, sleeve=1.8),
           P(vs=0.980, lean=-1.4, head=-0.6, hem=1.0, sleeve=0.8),
           P(vs=0.995, lean=-0.4, head=-0.2)]
    return seq[k] if k < len(seq) else P()


def clip_respawn(k, n):
    t = smooth(k / (n - 1.0))
    s = 0.80 + 0.20 * t
    return P(vs=s, xs=1.0 + 0.10 * (1.0 - t),
             hem=-1.2 * (1.0 - t), head=0.0)


def clip_turn(k, n):
    return [P(vs=1.020, xs=0.900), P()][k] if k < 2 else P()


def clip_land(k, n):
    seq = [P(vs=0.860, xs=1.060, hem=2.0, spread=1.6, sleeve=1.2),
           P(vs=1.025, xs=0.985, hem=-0.8, spread=-0.4),
           P()]
    return seq[k] if k < len(seq) else P()


def clip_era_switch(k, n):
    t = k / (n - 1.0)
    env = math.sin(math.pi * min(t * 1.15, 1.0))
    return P(vs=1.0 + 0.035 * env, rise=2.2 * env,
             hem=-1.6 * env, sleeve=-1.4 * env, head=-0.6 * env)


CLIPS = [
    # 名称, 帧数, 是否循环, 生成函数, 说明, 校验选项
    ("idle", 12, True, clip_idle, "呼吸待机", {}),
    ("run", 8, True, clip_run, "奔行：跑姿画源 + 腾空/触地节奏",
     {"base_exempt": True}),
    ("jump", 4, False, clip_jump, "起跳：蹲→蹬→伸→顶点",
     {"base_exempt": True, "gate_smooth": False, "gate_head": False}),
    ("fall", 5, True, clip_fall, "下落：拉伸 + 布摆抖动", {"base_exempt": True}),
    ("dash", 3, False, clip_dash, "冲刺：逐帧加大前倾", {"base_exempt": True}),
    ("attack", 4, False, clip_attack, "攻击：蓄力→袖摆挥出→收势",
     {"gate_smooth": False, "ends_at_rest": True}),
    ("hurt", 4, False, clip_hurt, "受击：后仰压缩→回位", {"ends_at_rest": True}),
    ("respawn", 7, False, clip_respawn, "复活：挤压到恢复",
     {"gate_smooth": False, "gate_head": False, "ends_at_rest": True}),
    ("turn", 2, False, clip_turn, "转向：偏转压缩过渡", {"ends_at_rest": True}),
    ("land", 3, False, clip_land, "落地：压缩→回弹→静止",
     {"gate_smooth": False, "gate_head": False, "ends_at_rest": True}),
    ("era_switch", 6, False, clip_era_switch, "换时代：轻微上浮拉伸",
     {"base_exempt": True, "ends_at_rest": True}),
]


def load_master(name="master_128.png"):
    return np.asarray(Image.open(os.path.join(ART, name)).convert("RGBA")).astype(np.float64) / 255.0


# 片段级画源覆盖：run 用跑姿母版（站立母版做不出跨步）
SRC_MAP = {"run": "runpose_128.png"}


def build(src, fn, n):
    return [Image.fromarray(render(src, fn(k, n)), "RGBA") for k in range(n)]


def comp(im, scale, bgc):
    bg = Image.new("RGBA", im.size, bgc + (255,))
    bg.alpha_composite(im)
    if scale != 1:
        bg = bg.resize((im.width * scale, im.height * scale), Image.NEAREST)
    return bg.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="只跑指定片段，逗号分隔")
    ap.add_argument("--amp", type=float, default=1.0,
                    help="run 起伏幅度倍率（1.0 = profile 标定值）")
    ap.add_argument("--profile", default="breath", choices=sorted(RUN_PROFILES),
                    help="run 幅度曲线：breath（默认，只呼吸）/ vivid（大动作）/ soft（轻微浮动）")
    args = ap.parse_args()
    global RUN_AMP, RUN_PROFILE
    RUN_AMP = args.amp
    RUN_PROFILE = args.profile
    want = set(x.strip() for x in args.only.split(",") if x.strip())

    src = load_master()
    outroot = os.path.join(ART, "clips")
    total = 0
    overview = []
    manifest = []

    for name, n, loop, fn, desc, opts in CLIPS:
        if want and name not in want:
            continue
        src = load_master(SRC_MAP.get(name, "master_128.png"))
        frames = build(src, fn, n)
        outdir = os.path.join(outroot, name)
        os.makedirs(outdir, exist_ok=True)
        for k, f in enumerate(frames):
            f.save(os.path.join(outdir, "%s_%02d.png" % (name, k)))

        # 闭合校验：循环片段要求 f(n) 与 f(0) 严格同帧
        if loop:
            a0 = np.asarray(frames[0]).astype(np.int16)
            aN = render(src, fn(n, n)).astype(np.int16)
            close = int(np.abs(a0 - aN).max())
        else:
            close = None

        ok = verify(frames, "%s (%s)" % (name, desc), loop=loop,
                    base_exempt=opts.get("base_exempt", False),
                    closure=close,
                    gate_smooth=opts.get("gate_smooth", True),
                    gate_head=opts.get("gate_head", True))

        # 非循环片段的关键门槛：末帧要能接回 idle 第 0 帧
        rest_ok = True
        if opts.get("ends_at_rest"):
            rest = render(src, P()).astype(np.int16)
            last = np.asarray(frames[-1]).astype(np.int16)
            d_rest = float(np.abs(rest - last).mean())
            rest_ok = d_rest <= 2.0
            print("  %-16s %-24s %-18s %s" % ("末帧≈静止姿", "平均像素差 ≤ 2.0",
                                              "%.2f" % d_rest, "PASS" if rest_ok else "FAIL"))
        ok = ok and rest_ok
        print("  帧数 %d  循环 %s  闭合差 %s  总体 %s" % (
            n, "是" if loop else "否",
            "-" if close is None else close,
            "PASS" if ok else "REVIEW"))

        g = [comp(f, 4, PAPER) for f in frames]
        g[0].save(os.path.join(ART, "%s_preview.gif" % name), save_all=True,
                  append_images=g[1:], duration=int(1000 / FPS), loop=0, optimize=False)
        gd = [comp(f, 4, SKY) for f in frames]
        gd[0].save(os.path.join(ART, "%s_preview_dark.gif" % name), save_all=True,
                   append_images=gd[1:], duration=int(1000 / FPS), loop=0, optimize=False)

        cell = 200
        sheet = Image.new("RGB", (cell * n, cell + 20), (255, 255, 255))
        d = ImageDraw.Draw(sheet)
        for i, f in enumerate(g):
            im = comp(frames[i], 1, PAPER).resize((cell, cell), Image.LANCZOS)
            sheet.paste(im, (i * cell, 20))
            d.text((i * cell + 6, 5), "%s %02d" % (name, i), fill=(0, 0, 0))
        sheet.save(os.path.join(ART, "%s_sheet.png" % name))
        overview.append((name, desc, frames, loop, close, ok))
        manifest.append({
            "clip": name,
            "desc": desc,
            "frames": n,
            "loop": loop,
            "fps": FPS,
            "duration_ms": round(n * 1000.0 / FPS, 1),
            "closure_diff": close,
            "dir": "clips/%s" % name,
            "gates": "PASS" if ok else "REVIEW",
        })
        total += n

    print("\n总计 %d 帧" % total)

    # 总览图：每个片段一行，128px 一格
    if overview:
        cell = 128
        maxn = max(len(o[2]) for o in overview)
        sheet = Image.new("RGB", (cell * maxn + 160, (cell + 10) * len(overview) + 26), (255, 255, 255))
        d = ImageDraw.Draw(sheet)
        d.text((6, 6), "clip", fill=(0, 0, 0))
        for r, (name, desc, frames, loop, close, ok) in enumerate(overview):
            y = 26 + r * (cell + 10)
            d.text((6, y + cell // 2 - 12), "%s%s" % (name, " (loop)" if loop else ""), fill=(0, 0, 0))
            d.text((6, y + cell // 2 + 2), "%d 帧" % len(frames), fill=(120, 120, 120))
            for i, f in enumerate(frames):
                sheet.paste(comp(f, 1, PAPER).resize((cell, cell), Image.LANCZOS),
                            (160 + i * cell, y))
        sheet.save(os.path.join(ART, "all_clips_overview.png"))
        print("总览: all_clips_overview.png")

    import json
    with open(os.path.join(ART, "clip_manifest.json"), "w", encoding="utf-8") as fh:
        json.dump({
            "note": "程序化位移场产出，非逐帧手绘。可与 idle 第 0 帧对齐。",
            "source": "master_128.png",
            "fps": FPS,
            "total_frames": total,
            "clips": manifest,
        }, fh, ensure_ascii=False, indent=2)
    print("清单: clip_manifest.json")


if __name__ == "__main__":
    main()
