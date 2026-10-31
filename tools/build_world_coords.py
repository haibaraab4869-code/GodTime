#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""29 区世界坐标构建器（TASK-05 / v1.3 升格后）

**世界观（显式规划）**

主干是一条自西向东的链，章节顺序即推进顺序；5 个支区挂在主干上下：

    主干：W01 → W02 → W04 → W05 → W06 → W08 → W09 → W10 → W11 → W12 → W14
          → W15 → W16 → W17 → W19 → W20 → W21 → W23 → W24 → W25

    支区：W03 在 W02 之上并贴 W04 西墙｜W07 在 W06 东墙下段｜W13 在 W12 西墙
          （W11 之上）｜W18 在 W17 之上｜W22 在 W21 之下

为什么用显式规划而不是自动布局：36 条边里有 7 条是跨章 `loop` 回环（含 `ENDGAME`），
世界本来就不是一张平面拼图；自动求解会为了满足这些边把整条链拉成乱麻。
所以这是**设计决定**：主干与支区拼成连续世界，回环只保证门朝外、指向对方。

脚本职责：
1. 按 PLAN 写入 `canvas_origin`；
2. 重算每条 `world_links` 的 `side` / `pos`，使**共边两端的门世界坐标完全重合**；
3. 把占位 `to_room`（TBD / 空串）解析成真实房号；
4. 校验：主干共边率、门位重合、区域面积不重叠、门点不越界、to_room 有效；
5. 输出 `docs/design/maps/_world-coordinates.md`。

用法：python tools/build_world_coords.py [--dry]
"""
from __future__ import annotations

import io
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "docs" / "design" / "maps" / "data"
DOCS = ROOT / "docs" / "design" / "maps"
OUT_MD = DOCS / "_world-coordinates.md"

# 单图 §7.1 连接表里手写的门位是**设计值**，必须保留；归一化只负责把它落到墙上并对齐两端。
# 行格式（各图略有出入，但都以 `| N-… |` 开头）：
#   | N-3 | R10 东侧 (2112,880) | W04 | R01 | 无 | 是 |
HINT_ROW = re.compile(r"^\|\s*N-[^|]*\|")
HINT_COORD = re.compile(r"\(\s*(\d+)\s*,\s*(\d+)\s*\)")
HINT_ROOM = re.compile(r"\bR\d{2}\b")
HINT_TGT = re.compile(r"\bW\d{2}\b")

DOOR_HINT = defaultdict(list)  # (rid, 目标区) -> [(房号, x, y), ...] 按文档行序

# 主干个别区需要抬高/压低以同时贴住两个邻居（W04 要同时贴 W02 与 W03）
CHAIN_Y = {"W04": -1920.0}

CHAIN = ["W01", "W02", "W04", "W05", "W06", "W08", "W09", "W10", "W11", "W12",
         "W14", "W15", "W16", "W17", "W19", "W20", "W21", "W23", "W24", "W25"]

# id -> (锚点区, 规则, dy, x 规则)
BRANCH = {
    "W03": ("W02", "stack_n", 0.0, "east_edge_at:W04"),
    "W07": ("W06", "east_of", 800.0, "flush"),
    "W13": ("W12", "west_of", 640.0, "flush"),
    "W18": ("W17", "stack_n", 0.0, "center"),
    "W22": ("W21", "stack_s", 0.0, "center"),
    # 暗区（总控 v1.3 · 决策 3A 升格）：小方块贴在宿主外侧，只有一道门
    "W26": ("W03", "west_of", 1280.0, "flush"),   # 墓园：贴井底南口西墙，底边与 W03 齐平
    "W27": ("W10", "stack_n", 0.0, "center"),     # 藏风坳：贴在风口西廊北墙外
    "W28": ("W15", "stack_n", 0.0, "center"),     # 溺火石碑：贴在塔顶观测台北墙外
    "W29": ("W25", "east_of", 2560.0, "flush"),   # 不曾发生的春天：贴原告席东墙，门厅地面与 R04 齐平（3200）
}


def load_all():
    out = {}
    for f in sorted(DATA.glob("w[0-9][0-9].json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        out[d["id"]] = d
    load_door_hints()
    return out


def load_door_hints():
    """从单图 §7.1 连接表抓设计门位。第一个坐标对是区局部坐标（W05 行里还有第二对世界坐标，忽略）。"""
    DOOR_HINT.clear()
    for f in sorted(DOCS.glob("w[0-9][0-9]-*.md")):
        rid = f.name[:3].upper()
        for ln in f.read_text(encoding="utf-8").splitlines():
            s = ln.strip()
            if not HINT_ROW.match(s):
                continue
            cells = [c.strip() for c in s.strip("|").split("|")]
            if len(cells) < 6:
                continue
            body = cells[1]
            cs = HINT_COORD.findall(body)
            tgts = HINT_TGT.findall(" ".join(cells[2:4]))
            if not cs or not tgts:
                continue
            rm = HINT_ROOM.findall(body)
            DOOR_HINT[(rid, tgts[0])].append(
                (rm[0] if rm else "", int(cs[0][0]), int(cs[0][1])))


def save(rid, d):
    p = DATA / f"{rid.lower()}.json"
    with io.open(p, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)


def rooms_of(d):
    return {r["id"]: r for r in d.get("rooms") or []}


def center(room):
    x, y, w, h = room["rect"]
    return x + w / 2.0, y + h / 2.0


def kind_of(links):
    ks = {w.get("kind", "main") for _, _, w in links}
    # loop 主导：一端标了 loop 就按跨空连接处理（W02↔W12、W04↔W24 属此类）
    if "loop" in ks:
        return "loop"
    for k in ("main", "branch", "secret"):
        if k in ks:
            return k
    return "loop"


def build_pairs(regions):
    pairs = defaultdict(list)
    for rid, d in regions.items():
        for idx, wl in enumerate(d.get("world_links") or []):
            if wl.get("to") not in regions:
                continue
            pairs[tuple(sorted((rid, wl["to"])))].append((rid, idx, wl))
    return pairs


def plan(regions):
    origin = {}
    x = 0.0
    for rid in CHAIN:
        origin[rid] = [x, CHAIN_Y.get(rid, 0.0)]
        x += regions[rid]["size"][0]

    for rid, (anchor, rule, dy, mode) in BRANCH.items():
        w, h = regions[rid]["size"]
        ax, ay = origin[anchor]
        aw, ah = regions[anchor]["size"]
        if rule == "east_of":
            ox, oy = ax + aw, ay + dy
        elif rule == "west_of":
            ox, oy = ax - w, ay + dy
        elif rule == "stack_n":
            ox, oy = ax + (aw - w) / 2.0, ay - h
        else:
            ox, oy = ax + (aw - w) / 2.0, ay + ah + dy
        if mode.startswith("east_edge_at:"):
            tgt = mode.split(":", 1)[1]
            ox = origin[tgt][0] - w
        origin[rid] = [float(ox), float(oy)]
    return origin


def pick_room(d, want, side):
    rs = rooms_of(d)
    if want in rs:
        return rs[want]
    if not rs:
        return None
    if side == "E":
        return max(rs.values(), key=lambda r: r["rect"][0] + r["rect"][2])
    if side == "W":
        return min(rs.values(), key=lambda r: r["rect"][0])
    if side == "S":
        return max(rs.values(), key=lambda r: r["rect"][1] + r["rect"][3])
    return min(rs.values(), key=lambda r: r["rect"][1])


def rect(origin, regions, rid):
    x, y = origin[rid]
    w, h = regions[rid]["size"]
    return x, y, x + w, y + h


def flush_kind(origin, regions, a, b, tol=1e-6, min_overlap=64):
    ax, ay, ax2, ay2 = rect(origin, regions, a)
    bx, by, bx2, by2 = rect(origin, regions, b)
    if abs(ax2 - bx) < tol and min(ay2, by2) - max(ay, by) >= min_overlap:
        return "aE"
    if abs(bx2 - ax) < tol and min(ay2, by2) - max(ay, by) >= min_overlap:
        return "bE"
    if abs(ay2 - by) < tol and min(ax2, bx2) - max(ax, bx) >= min_overlap:
        return "aS"
    if abs(by2 - ay) < tol and min(ax2, bx2) - max(ax, bx) >= min_overlap:
        return "bS"
    return None


HINT_AXIS = {"E": "y", "W": "y", "S": "x", "N": "x"}


def wall_coord(d, side):
    W, H = d["size"]
    return {"E": float(W), "W": 0.0, "S": float(H), "N": 0.0}[side]


def room_on_wall(d, side, coord):
    """找出贴着 side 边框、且门位落在它朝向面区间内的房间。"""
    wall = wall_coord(d, side)
    for r in d.get("rooms") or []:
        x, y, w, h = r["rect"]
        if side in ("E", "W"):
            if abs((x + w if side == "E" else x) - wall) > 1e-6:
                continue
            if y - 1 <= coord <= y + h + 1:
                return r
        else:
            if abs((y + h if side == "S" else y) - wall) > 1e-6:
                continue
            if x - 1 <= coord <= x + w + 1:
                return r
    return None


def take_hint(rid, other, prefer_room=""):
    pool = DOOR_HINT.get((rid, other)) or []
    if not pool:
        return None
    for i, h in enumerate(pool):
        if prefer_room and h[0] == prefer_room:
            return pool.pop(i)
    return pool.pop(0)


def wall_intervals(d, side):
    """这条边框上有房间贴着的区段（合并后）。门只能开在这些区段里，否则是开在实心墙上。"""
    wall = wall_coord(d, side)
    spans = []
    for r in d.get("rooms") or []:
        x, y, w, h = r["rect"]
        if side in ("E", "W"):
            if abs((x + w if side == "E" else x) - wall) > 1e-6:
                continue
            spans.append((y, y + h))
        else:
            if abs((y + h if side == "S" else y) - wall) > 1e-6:
                continue
            spans.append((x, x + w))
    spans.sort()
    out = []
    for lo, hi in spans:
        if out and lo <= out[-1][1] + 1e-6:
            out[-1] = (out[-1][0], max(out[-1][1], hi))
        else:
            out.append((lo, hi))
    return out


def clamp_into(coord, intervals, margin=40.0):
    """把 coord 夹进最近的区段（留 margin，区段太薄就不留）。"""
    best = None
    for lo, hi in intervals:
        m = margin if hi - lo >= 2 * margin else (hi - lo) / 2.0
        c = min(max(coord, lo + m), hi - m)
        dist = abs(c - coord)
        if best is None or dist < best[0]:
            best = (dist, c)
    return coord if best is None else best[1]


def normalize(regions, origin, pairs):
    """重算 side / pos / room / to_room。

    原则：
    - `pos` 优先取单图 §7.1 手写的设计门位（自由轴数值保留，贴墙轴强制落到边框）；
    - 共边对的两端自由轴取世界坐标均值，因此**门位重合**且各自都落在自己那间房的面上；
    - `room` 由门位几何反查（谁贴着这条墙、谁包含这个高度），不再猜；
    - `to_room` 直接取对侧 `room`，保证一道门两侧指向的房间互为对端。
    """
    for key, links in pairs.items():
        a, b = key
        fk = flush_kind(origin, regions, a, b)
        sides, room_of = {}, {}

        for rid, idx, wl in links:
            other = b if rid == a else a
            if fk is None:
                dx = origin[other][0] - origin[rid][0]
                dy = origin[other][1] - origin[rid][1]
                side = ("E" if dx > 0 else "W") if abs(dx) >= abs(dy) else ("S" if dy > 0 else "N")
            else:
                side = {"aE": ("E", "W"), "bE": ("W", "E"),
                        "aS": ("S", "N"), "bS": ("N", "S")}[fk][0 if rid == a else 1]
            sides[rid] = side
            wl["side"] = side
            wl["flush"] = fk is not None

        # ---- 共边对：两端的自由轴取世界均值 ----
        if fk is not None:
            axis = "y" if fk in ("aE", "bE") else "x"
            vals = []
            for rid, _, wl in links:
                side = sides[rid]
                h = take_hint(rid, b if rid == a else a, wl.get("room", ""))
                if h is None:
                    continue
                wx = origin[rid][0] + (h[1] if axis == "x" else 0)
                wy = origin[rid][1] + (h[2] if axis == "y" else 0)
                vals.append(wy if axis == "y" else wx)
            ax, ay, ax2, ay2 = rect(origin, regions, a)
            bx, by, bx2, by2 = rect(origin, regions, b)
            lo, hi = (max(ay, by), min(ay2, by2)) if axis == "y" else (max(ax, bx), min(ax2, bx2))
            if vals:
                free = sum(vals) / len(vals)
            else:  # 没有设计值：退化为「各自那间房的中心」均值
                acc = []
                for rid, _, wl in links:
                    rm = room_on_wall(regions[rid], sides[rid], (lo + hi) / 2.0) \
                        or pick_room(regions[rid], None, sides[rid])
                    if rm:
                        acc.append(origin[rid][1] + center(rm)[1] if axis == "y"
                                   else origin[rid][0] + center(rm)[0])
                free = sum(acc) / len(acc) if acc else (lo + hi) / 2.0
            if hi - lo >= 80:
                free = max(lo + 40, min(hi - 40, free))

            # 门只能开在「两侧墙上都真有房间」的区段；两侧都对齐才算一道能走的门
            iv = None
            for rid, _, wl in links:
                o = origin[rid][1] if axis == "y" else origin[rid][0]
                ivs = [(a0 + o, b0 + o) for a0, b0 in wall_intervals(regions[rid], sides[rid])]
                if iv is None:
                    iv = ivs
                else:
                    iv = [(max(p0, q0), min(p1, q1)) for p0, p1 in iv for q0, q1 in ivs
                          if min(p1, q1) > max(p0, q0)]
            if iv:
                free = clamp_into(free, iv)

            for rid, _, wl in links:
                side = sides[rid]
                ox, oy = origin[rid]
                wx, wy = (ax2 if rid == a else bx2, free) if axis == "y" else (free, ay2 if rid == a else by2)
                if axis == "y":
                    wx = (ax2 if side == "E" else ax) if rid == a else (bx2 if side == "E" else bx)
                else:
                    wy = (ay2 if side == "S" else ay) if rid == a else (by2 if side == "S" else by)
                pos = [int(round(wx - ox)), int(round(wy - oy))]
                wl["pos"] = pos
                rm = room_on_wall(regions[rid], side, pos[1] if axis == "y" else pos[0])
                if rm is None:
                    rm = pick_room(regions[rid], None, side)
                if rm:
                    wl["room"] = rm["id"]
                    room_of[rid] = rm["id"]
            for rid, _, wl in links:
                other = b if rid == a else a
                if room_of.get(other):
                    wl["to_room"] = room_of[other]
            continue

        # ---- 跨空连接：两端各自独立，只保证贴着本区边框 ----
        for rid, _, wl in links:
            other = b if rid == a else a
            side = sides[rid]
            h = take_hint(rid, other, wl.get("room", ""))
            ivs = wall_intervals(regions[rid], side)
            if h is not None:
                pos = list(h[1:])
                if side in ("E", "W"):
                    pos[0] = int(round(wall_coord(regions[rid], side)))
                    pos[1] = int(round(clamp_into(pos[1], ivs)))
                else:
                    pos[1] = int(round(wall_coord(regions[rid], side)))
                    pos[0] = int(round(clamp_into(pos[0], ivs)))
            else:
                rm = pick_room(regions[rid], None, side)
                cx, cy = center(rm) if rm else (0, 0)
                W, H = regions[rid]["size"]
                px, py = {"E": (W, cy), "W": (0, cy), "S": (cx, H), "N": (cx, 0)}[side]
                pos = [int(round(px)), int(round(py))]
            wl["pos"] = pos
            rm = room_on_wall(regions[rid], side, pos[1] if side in ("E", "W") else pos[0])
            if rm is None:
                rm = pick_room(regions[rid], None, side)
            if rm:
                wl["room"] = rm["id"]
                room_of[rid] = rm["id"]
        for rid, _, wl in links:
            other = b if rid == a else a
            if room_of.get(other):
                wl["to_room"] = room_of[other]

def verify(regions, origin, pairs):
    problems = []
    for key, links in pairs.items():
        if kind_of(links) == "loop":
            continue
        if flush_kind(origin, regions, *key) is None:
            problems.append("未共边: %s-%s (%s)" % (key[0], key[1], kind_of(links)))

    for key, links in pairs.items():
        if flush_kind(origin, regions, *key) is None:
            continue
        pts = {}
        for rid, _, wl in links:
            ox, oy = origin[rid]
            pts.setdefault(rid, (ox + wl["pos"][0], oy + wl["pos"][1]))
        if len(pts) == 2:
            p, q = list(pts.values())
            if abs(p[0] - q[0]) > 1 or abs(p[1] - q[1]) > 1:
                problems.append("门位不重合: %s-%s %s vs %s" % (key[0], key[1], p, q))

    ids = sorted(regions)
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            ax, ay, ax2, ay2 = rect(origin, regions, ids[i])
            bx, by, bx2, by2 = rect(origin, regions, ids[j])
            ox = min(ax2, bx2) - max(ax, bx)
            oy = min(ay2, by2) - max(ay, by)
            if ox > 1 and oy > 1:
                problems.append("区域重叠: %s × %s (%d×%d)" % (ids[i], ids[j], int(ox), int(oy)))

    for rid, d in regions.items():
        W, H = d["size"]
        for wl in d.get("world_links") or []:
            x, y = wl["pos"]
            if not (0 <= x <= W and 0 <= y <= H):
                problems.append("门点越界: %s->%s %s (画布 %d×%d)" % (rid, wl["to"], wl["pos"], W, H))
                continue
            s = wl["side"]
            on_wall = ((s == "E" and x == W) or (s == "W" and x == 0) or
                       (s == "S" and y == H) or (s == "N" and y == 0))
            if not on_wall:
                problems.append("门点不在 %s 墙: %s->%s %s" % (s, rid, wl["to"], wl["pos"]))

    for rid, d in regions.items():
        for wl in d.get("world_links") or []:
            tr = wl.get("to_room")
            tgt = regions.get(wl["to"])
            if not isinstance(tr, str) or not tr:
                problems.append("to_room 空: %s->%s" % (rid, wl["to"]))
            elif tr not in rooms_of(d) and tgt and tr not in rooms_of(tgt):
                problems.append("to_room 无效: %s->%s:%s" % (rid, wl["to"], tr))

    # 门位必须落在所连房间的朝向面上：否则玩家走到门前看到的是别人家的墙
    for rid, d in regions.items():
        for wl in d.get("world_links") or []:
            s = wl["side"]
            free = wl["pos"][1] if s in ("E", "W") else wl["pos"][0]
            rm = room_on_wall(d, s, free)
            if rm is None:
                problems.append("门位不在任何房间面上: %s->%s %s %s" % (rid, wl["to"], s, wl["pos"]))
            elif wl.get("room") != rm["id"]:
                problems.append("room 与门位不符: %s->%s 记 %s 实为 %s" % (
                    rid, wl["to"], wl.get("room"), rm["id"]))

    # 一道门两侧互为对端
    for key, links in pairs.items():
        a, b = key
        got = {rid: wl for rid, _, wl in links}
        if len(got) != 2:
            continue
        for rid, other in ((a, b), (b, a)):
            if rid in got and got[rid].get("to_room") != got[other].get("room"):
                problems.append("门口不对端: %s->%s to_room=%s 但 %s 侧房间=%s" % (
                    rid, other, got[rid].get("to_room"), other, got[other].get("room")))
    return problems


def report(regions, origin, pairs):
    print("%-4s%-12s%3s%14s%20s%20s%20s" % ("区", "名称", "章", "size", "origin", "世界 x", "世界 y"))
    for rid in sorted(regions):
        d = regions[rid]
        ox, oy = origin[rid]
        w, h = d["size"]
        print("%-4s%-12s%3d%14s%20s%20s%20s" % (
            rid, d["name"], d["chapter"], "(%d,%d)" % (w, h),
            "(%d,%d)" % (ox, oy),
            "[%d, %d]" % (ox, ox + w), "[%d, %d]" % (oy, oy + h)))
    xs = [origin[r][0] for r in origin] + [origin[r][0] + regions[r]["size"][0] for r in origin]
    ys = [origin[r][1] for r in origin] + [origin[r][1] + regions[r]["size"][1] for r in origin]
    print("\n世界包围盒 x∈[%d, %d] y∈[%d, %d]  跨度 %d × %d" % (
        min(xs), max(xs), min(ys), max(ys), max(xs) - min(xs), max(ys) - min(ys)))


def write_md(regions, origin, pairs):
    xs = [origin[r][0] for r in origin] + [origin[r][0] + regions[r]["size"][0] for r in origin]
    ys = [origin[r][1] for r in origin] + [origin[r][1] + regions[r]["size"][1] for r in origin]
    L = []
    L.append("# 29 区世界坐标总表（TASK-05 / v1.3 升格后）\n")
    L.append("> 本表是 29 张单图 `canvas_origin` 的唯一权威。生成器 `tools/build_world_coords.py`，校验器 `tools/verify_map_specs.py`。")
    L.append("> **不要手改单份 JSON 的坐标**——共边两侧会错位。改拓扑请改生成器里的 `CHAIN` / `BRANCH` 再重跑。\n")
    L.append("**世界包围盒**：x ∈ [%d, %d]，y ∈ [%d, %d]，跨度 **%d × %d** px。\n" % (
        min(xs), max(xs), min(ys), max(ys), max(xs) - min(xs), max(ys) - min(ys)))
    L.append("## 1. 世界规划\n")
    L.append("- **主干（自西向东，20 区）**：" + " → ".join(CHAIN))
    L.append("- **支区（5 区）**：W03 在 W02 之上并贴 W04 西墙 ｜ W07 在 W06 东墙下段 ｜ W13 在 W12 西墙（W11 之上） ｜ W18 在 W17 之上 ｜ W22 在 W21 之下")
    L.append("- **暗区（4 区，v1.3 升格）**：W26 墓园贴 W03 井底南口西墙 ｜ W27 藏风坳贴 W10 风口西廊北墙 ｜ W28 溺火石碑贴 W15 塔顶北墙 ｜ W29 不曾发生的春天贴 W25 原告席东墙。四个都是「一间到三间 + 一道门」的小方块，不计入主干链")
    L.append("- 主干 y 基准 = 0；支区按偏移放置。相邻区在共用墙上至少留 160px 的门位余量。\n")
    L.append("## 2. 区域坐标表\n")
    L.append("| 区 | 名称 | 章 | 尺寸 w×h | canvas_origin | 世界范围 x | 世界范围 y |")
    L.append("| --- | --- | --- | --- | --- | --- | --- |")
    for rid in sorted(regions):
        d = regions[rid]
        ox, oy = origin[rid]
        w, h = d["size"]
        L.append("| %s | %s | %d | %d×%d | `[%d, %d]` | [%d, %d] | [%d, %d] |" % (
            rid, d["name"], d["chapter"], w, h, ox, oy, ox, ox + w, oy, oy + h))
    L.append("\n## 3. 跨区接口\n")
    L.append("| 边 | 类别 | 西/北端 | 门位（世界） | 东/南端 | 门位（世界） | 共边 | 门槛 |")
    L.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for key, links in sorted(pairs.items()):
        a, b = key
        k = kind_of(links)
        fk = flush_kind(origin, regions, a, b)
        la = next((w for r, _, w in links if r == a), None)
        lb = next((w for r, _, w in links if r == b), None)

        def wp(rid, wl):
            if not wl:
                return "—"
            ox, oy = origin[rid]
            return "(%d, %d)" % (ox + wl["pos"][0], oy + wl["pos"][1])
        req = (la or {}).get("requires") or ""
        dup = "" if len(links) == 2 else " ×%d" % len(links)
        # 同一对区可能同时存在 main 与 loop 两道门（W14↔W15 观测塔即此类），标签要写明复合类型
        ks = {w.get("kind", "main") for _, _, w in links}
        disp = k if len(ks) == 1 else "+".join(
            x for x in ("main", "branch", "secret", "loop") if x in ks)
        L.append("| %s↔%s | `%s`%s | %s | %s | %s | %s | %s | `%s` |" % (
            a, b, disp, dup, a, wp(a, la), b, wp(b, lb), "✓" if fk else "—", req))
    L.append("\n## 4. 约定\n")
    L.append("- **共边**：两区共享一条世界边，门点两侧世界坐标完全一致；玩家穿门即进邻区，无过渡。")
    L.append("- **跨空连接**：`loop` 类跨章回环（7 条，含 `ENDGAME`）。两端在世界图上不相邻，门开在各自外侧，靠过渡走廊／升降／剧情门表现，**不参与共边校验**。")
    L.append("- `pos` 为**区局部坐标**；世界点 = `canvas_origin + pos`。门点必落在本区边框上，且落在所连房间的朝向面内（取房间矩形中心投影后夹进共边区间）。")
    L.append("- 引擎侧：跨区镜头用 `canvas_origin` 直接换算；同区内房间坐标仍是局部的，不要与 `canvas_origin` 重复相加。")
    L.append("- **`×N` 与复合标签**：`×N` 表示两区之间的门记录条数（`links` 计数，正常为 2 = 双向各一条）。出现 `main+loop` **不代表两道门**，只是两端 `kind` 标注不一致时的复合显示（W02↔W12、W04↔W24 属此类：一端按主干写 `main`、另一端按回环写 `loop`）。曾经唯一真正双门的一对是 **W14↔W15 赤潮观测塔**（主门 R10↔R01 贴地过闸 + 回环门 R10↔R06 塔顶风廊），v1.3 收口时已**折叠为单条 `E15`**：运行时一条区对只能承载一条边（`[[a,b]]` 索引对 + `connections` 逐条对齐），同对双门会撞索引。塔顶回落改为 M3 的区内风井交互，**不要给同一对区加第二条边**。")
    OUT_MD.write_text("\n".join(L) + "\n", encoding="utf-8")


def main():
    dry = "--dry" in sys.argv
    regions = load_all()
    pairs = build_pairs(regions)
    origin = plan(regions)
    normalize(regions, origin, pairs)
    problems = verify(regions, origin, pairs)

    report(regions, origin, pairs)
    print("\n=== 校验 ===")
    print("\n".join(problems) if problems else
          "全部通过：主干共边 ✓ 门位重合 ✓ 无区域重叠 ✓ 门点不越界 ✓ to_room 全部有效 ✓")

    if not dry:
        for rid, d in regions.items():
            d["canvas_origin"] = [int(origin[rid][0]), int(origin[rid][1])]
            save(rid, d)
        write_md(regions, origin, pairs)
        print("\n已写回 29 份 JSON + %s" % OUT_MD.name)
    else:
        print("\n[dry] 未写盘")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
