#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""29 区世界运行时转换器（docs/development/handoff-world-29.md §9）。

设计侧输入（只读）：
    docs/design/maps/data/world-25.json
    docs/design/maps/data/w01.json … w29.json

运行时输出（只写）：
    game/data/world_regions.json   （version 7 / 29 regions / 36 edges）

用法：
    python tools/build_runtime_world.py                # 全量重建
    python tools/build_runtime_world.py --only W05     # 只替换该区节点与相关边
    python tools/build_runtime_world.py --dry-run      # 只算不写
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / "docs" / "design" / "maps" / "data"
OUTPUT = ROOT / "game" / "data" / "world_regions.json"

# §6 基准表的世界序（number 按此给，不是 W 号）
WORLD_ORDER = [
    "W01", "W02", "W03", "W26", "W04",
    "W05", "W06", "W07",
    "W08", "W09", "W10", "W27",
    "W11", "W12", "W13",
    "W14", "W15", "W28", "W16",
    "W17", "W18", "W19",
    "W20", "W21", "W22",
    "W23", "W24", "W25", "W29",
]

# §14.1
CHAPTER_NAMES = {
    1: "断刻之城", 2: "丹丘羽坠", 3: "羽渊悬空", 4: "不周断脊",
    5: "炎狱旧海", 6: "归墟骨城", 7: "沧海息壤", 8: "八荒重刻",
}

# §14.2（6 位 hex，不带 #）
CHAPTER_COLORS = {
    1: "648d93", 2: "a98b60", 3: "7e9eb3", 4: "8a83a4",
    5: "b67e58", 6: "7d9997", 7: "5d9e8d", 8: "a395be",
}

# §14.3
CHAPTER_QUOTA = {1: 5, 2: 3, 3: 4, 4: 3, 5: 4, 6: 3, 7: 3, 8: 4}

# §14.4
ABILITY_CODES = ["VC", "P2", "QS", "PA", "PW", "PG", "DS", "DT", "DB"]
GATE_FLAGS = ["FINAL_DOOR", "ENDGAME", "w25_verdict_sealed"]

# §4.7：进度旗标边的置位方（设计侧 opener 仅供理解，运行时按此表落字段）
GATE_OPENERS = {"E25": "W24", "E32": "W24", "E36": "W25"}

# §Grant（_schema.md v1.4）：能力取得点契约
GRANT_ERAS = {"past", "present", "both"}
GRANT_RADIUS_RANGE = (40, 64)
GRANT_MARGIN = 20          # 取得点距房 rect 四边的最小余量（玩家碰撞体半宽）
GRANT_DEDUP_RADIUS = 64.0  # grant 同房同点的「永久强化」道具不再生成 item_*
GRANT_DEDUP_KINDS = {"永久强化"}
# `auto: true` = 触碰即取（进入 radius 即发放，不弹面板、无需按 E）。
# 只允许这些代号用：给别处加 auto 会静默改变手感，一律拒绝。
GRANT_AUTO_CODES = {"PW"}

# §5.2 + 设计侧实际出现的其余枚举（v7 几何不读 shape，仅元数据）
SHAPE_CODES = {
    "矩形": 0, "竖井": 1, "拱顶": 2, "梯形": 3,
    "斜坡": 4, "楼梯": 5, "L形": 6, "梯田": 7,
}

SIDE_CODES = {"W": -1, "N": -1, "E": 1, "S": 1}

PORCH_DEPTH = 96      # §4.4 门廊宽 96
PORCH_HEIGHT = 140    # 竖门廊在楼层上方的高度
LANDING_INSET = 72    # 落点离墙距离
FLOOR_CLEARANCE = 20  # 落点吸附 floor_y - 20

TOTAL_REGIONS = 29
TOTAL_ROOMS = 320
TOTAL_EDGES = 36
TOTAL_GRANTS = 9


class SpecError(RuntimeError):
    pass


def need(mapping, key, ctx):
    """§9：不猜。缺字段直接 raise 并指出区号 + 字段。"""
    if not isinstance(mapping, dict) or key not in mapping:
        raise SpecError(f"{ctx}: 缺少必填字段 {key!r}")
    return mapping[key]


def solution_dials(device, ctx):
    """机关目标档位。

    levels<=1 或 solution 是一整句说明（"…坠入即落到燃羽堆最上层 y=2144"）时，
    这个机关没有解谜，只留一个交互点当说明牌；只有真正的短口令才拆盘。
    """
    levels = int(device.get("levels", 1))
    solution = device.get("solution", 0)
    if levels <= 1:
        return [0]
    if isinstance(solution, list):
        return [int(v) for v in solution]
    if isinstance(solution, (int, float)):
        return [int(solution)]
    if isinstance(solution, str) and len(solution) <= 24:
        digits = re.findall(r"\d+", solution)
        if digits:
            return [int(v) for v in digits]
    return [0]


def normalize(value):
    """整数化的浮点写成 int，保证 JSON 幂等且易读。"""
    if isinstance(value, float):
        rounded = round(value, 1)
        if rounded == int(rounded):
            return int(rounded)
        return rounded
    if isinstance(value, list):
        return [normalize(v) for v in value]
    if isinstance(value, dict):
        return {k: normalize(v) for k, v in value.items()}
    return value


def load_design():
    world = json.loads((DESIGN / "world-25.json").read_text(encoding="utf-8"))
    specs = {}
    for index in range(1, 30):
        path = DESIGN / f"w{index:02d}.json"
        if not path.exists():
            raise SpecError(f"缺少设计文件 {path}")
        spec = json.loads(path.read_text(encoding="utf-8"))
        specs[need(spec, "id", str(path))] = spec
    if len(specs) != TOTAL_REGIONS:
        raise SpecError(f"设计区数 {len(specs)} != {TOTAL_REGIONS}")
    return world, specs


def door_geometry(wl: dict, room: dict, ctx: str):
    """把设计门位（贴墙的一点）展开成可触发的门廊与落点。"""
    side_code = need(wl, "side", ctx)
    if side_code not in SIDE_CODES:
        raise SpecError(f"{ctx}: 未知门朝向 {side_code!r}")
    side = SIDE_CODES[side_code]
    pos = need(wl, "pos", ctx)
    ax, ay = float(pos[0]), float(pos[1])
    rx, ry, rw, rh = [float(v) for v in need(room, "rect", ctx)]
    floor_y = float(need(room, "floor_y", ctx))

    if side_code in ("W", "E"):
        door = "h"
        porch_x = ax - PORCH_DEPTH if side > 0 else ax
        height = max(PORCH_DEPTH, floor_y - ay)
        porch = [porch_x, floor_y - height, PORCH_DEPTH, height]
        landing = [ax - side * LANDING_INSET, floor_y - FLOOR_CLEARANCE]
    else:
        door = "v"
        porch_x = ax - PORCH_DEPTH / 2
        porch = [porch_x, floor_y - PORCH_HEIGHT, PORCH_DEPTH, PORCH_HEIGHT]
        # 竖门正下方常常就是竖井开口，落点要偏出 ±64 的井口，否则一传送就悬空。
        shift = -96 if (ax - 96) - rx >= 40 else 96
        landing = [ax + shift, floor_y - FLOOR_CLEARANCE]

    # 门廊必须落在房间 x 区间内，否则玩家永远站不进去
    left, right = rx, rx + rw
    px, pw = porch[0], porch[2]
    if px < left:
        porch[0] = left
    if porch[0] + pw > right:
        porch[0] = right - pw
    if porch[2] <= 0:
        raise SpecError(f"{ctx}: 门廊宽度非法 {porch}")
    landing[0] = min(max(landing[0], left + 24), right - 24)
    return door, [normalize(v) for v in porch], [normalize(v) for v in landing]


def build_room(spec_room: dict, ctx: str) -> dict:
    shape_name = need(spec_room, "shape", ctx)
    if shape_name not in SHAPE_CODES:
        raise SpecError(f"{ctx}: 未知房间形状 {shape_name!r}（请在 SHAPE_CODES 补登）")
    rect = need(spec_room, "rect", ctx)
    room = {
        "id": need(spec_room, "id", ctx),
        "name": need(spec_room, "name", ctx),
        "rect": [int(v) for v in rect],
        "shape": SHAPE_CODES[shape_name],
        "floor_y": float(need(spec_room, "floor_y", ctx)),
        "ceiling_y": float(rect[1]),
    }
    for key in ("era", "content", "region", "landmark", "note"):
        if key in spec_room:
            room[key] = spec_room[key]
    return room


def build_connections(spec: dict, rooms: list[dict], links: list[list[int]]) -> list[dict]:
    ctx = spec["id"]
    raw_links = need(spec, "links", ctx)
    if len(raw_links) != len(links):
        raise SpecError(f"{ctx}: links 索引化后条数不一致")
    connections = []
    for index, (raw, pair) in enumerate(zip(raw_links, links)):
        a = rooms[pair[0]]
        b = rooms[pair[1]]
        ay, by = float(a["floor_y"]), float(b["floor_y"])
        ax = a["rect"][0] + a["rect"][2] / 2
        bx = b["rect"][0] + b["rect"][2] / 2
        if abs(ax - bx) < 0.5:
            dy = abs(ay - by)
            tier = "R1" if dy <= 320 else ("R2" if dy <= 640 else "R3")
            landings = max(0, math.ceil((dy - 256) / 320)) if dy > 256 else 0
            overlap_left = max(a["rect"][0], b["rect"][0])
            overlap_right = min(a["rect"][0] + a["rect"][2], b["rect"][0] + b["rect"][2])
            offset = 0.0
            if overlap_right - overlap_left >= 160:
                center = min(max(ax, overlap_left + 80), overlap_right - 80)
                offset = round(center - ax, 1)
            connections.append({
                "link": index,
                "tier": tier,
                "landings": landings,
                "return_assist": dy > 256,
                "shaft_offset": normalize(offset),
                "era": raw.get("era", "both"),
            })
        else:
            connections.append({
                "link": index,
                "tier": "R1",
                "landings": 0,
                "return_assist": False,
                "era": raw.get("era", "both"),
            })
    return connections


def build_grants(spec: dict, rooms: list[dict], room_index: dict) -> list[dict]:
    """§Grant（_schema.md v1.4）：能力取得点 → 每条 grant 一个 world_ability 交互。

    载荷自带 `ability`，**不写 region.ability**：一个区可能发两个能力（W06 是 P2 + QS），
    标量字段承载不了。
    """
    ctx = spec["id"]
    result = []
    low, high = GRANT_RADIUS_RANGE
    for index, raw in enumerate(spec.get("grants") or []):
        label = f"{ctx}.grants[{index}]"
        ability = str(need(raw, "ability", label))
        if ability not in ABILITY_CODES:
            raise SpecError(f"{label}: 能力代号 {ability!r} 不在白名单 {ABILITY_CODES}")
        room_id = need(raw, "room", label)
        if room_id not in room_index:
            raise SpecError(f"{label}: 落在不存在的房间 {room_id}")
        room = rooms[room_index[room_id]]
        pos = need(raw, "pos", label)
        if not isinstance(pos, list) or len(pos) != 2:
            raise SpecError(f"{label}: pos 必须是 [x, y]，实际 {pos!r}")
        x, y = float(pos[0]), float(pos[1])
        rx, ry, rw, rh = [float(v) for v in room["rect"]]
        if not (rx + GRANT_MARGIN <= x <= rx + rw - GRANT_MARGIN
                and ry + GRANT_MARGIN <= y <= ry + rh - GRANT_MARGIN):
            raise SpecError(
                f"{label}: pos {pos} 不在 {room_id} rect {room['rect']} 的四边 {GRANT_MARGIN}px 余量内")
        era = str(need(raw, "era", label))
        if era not in GRANT_ERAS:
            raise SpecError(f"{label}: era {era!r} 不在 {sorted(GRANT_ERAS)}")
        radius = int(need(raw, "radius", label))
        if not (low <= radius <= high):
            raise SpecError(f"{label}: radius {radius} 不在 {low}—{high}")
        # auto：选填，缺省 false；出现就必须是 bool，且只在 GRANT_AUTO_CODES 里的代号上。
        auto = raw.get("auto", False)
        if not isinstance(auto, bool):
            raise SpecError(f"{label}: auto 必须是 true/false，实际 {auto!r}")
        if auto and ability not in GRANT_AUTO_CODES:
            raise SpecError(
                f"{label}: 只有 {'/'.join(sorted(GRANT_AUTO_CODES))} 允许 auto（触碰即取），"
                f"{ability} 加 auto 会静默改变取得手感")
        result.append({
            "ability": ability,
            "room": room_index[room_id],
            "pos": [normalize(x), normalize(y)],
            "era": era,
            "radius": radius,
            "label": str(need(raw, "label", label)),
            "text": str(need(raw, "text", label)),
            "auto": auto,
        })
    return result


def suppressed_by_grant(grants: list[dict], room: int, pos: list) -> bool:
    """取得点优先：与某条 grant 同房且 <64px 的「永久强化」道具不再出 item_*。

    只收「永久强化」（W01 I-01『VC 时间切换』与 VC 取得点完全同点）；
    同半径内的叙事物（W06『药簿』、W09『塔顶风历』、W12『石工亲笔信』）一律保留。
    """
    for grant in grants:
        if grant["room"] != room:
            continue
        dx = float(grant["pos"][0]) - float(pos[0])
        dy = float(grant["pos"][1]) - float(pos[1])
        if math.hypot(dx, dy) < GRANT_DEDUP_RADIUS:
            return True
    return False


def build_region(meta: dict, spec: dict, number: int, titles: dict) -> dict:
    ctx = spec["id"]
    chapter = int(need(spec, "chapter", ctx))
    if chapter != int(meta["chapter"]):
        raise SpecError(f"{ctx}: chapter 与世界索引不一致（{chapter} != {meta['chapter']}）")
    if chapter not in CHAPTER_NAMES or chapter not in CHAPTER_COLORS:
        raise SpecError(f"{ctx}: 章节 {chapter} 不在 §14 表内")

    rooms = [build_room(raw, ctx) for raw in need(spec, "rooms", ctx)]
    room_index = {}
    for index, room in enumerate(rooms):
        if room["id"] in room_index:
            raise SpecError(f"{ctx}: 房间号重复 {room['id']}")
        room_index[room["id"]] = index

    # links：房号对 → 索引对（顺序即 connections 的顺序，不许排序）
    links = []
    for raw in need(spec, "links", ctx):
        a = need(raw, "a", ctx)
        b = need(raw, "b", ctx)
        if a not in room_index or b not in room_index:
            raise SpecError(f"{ctx}: links 引用了不存在的房间 {a}-{b}")
        links.append([room_index[a], room_index[b]])

    grants = build_grants(spec, rooms, room_index)

    interactions = []
    # 1) 跨区入口：每侧一条 travel_<对端>
    for raw in need(spec, "world_links", ctx):
        peer = need(raw, "to", ctx)
        room_id = need(raw, "room", ctx)
        if peer not in titles:
            raise SpecError(f"{ctx}: world_links 指向未知区 {peer}")
        if room_id not in room_index:
            raise SpecError(f"{ctx}: world_links 落在不存在的房间 {room_id}")
        room = rooms[room_index[room_id]]
        door, porch, landing = door_geometry(raw, room, f"{ctx}.{peer}")
        interactions.append({
            "id": "travel_" + peer,
            "name": "通往 " + str(titles[peer]),
            "at": [int(v) if float(v).is_integer() else normalize(float(v)) for v in raw["pos"]],
            "room": room_index[room_id],
            "radius": 0,
            "edge": "",
            "side": SIDE_CODES[need(raw, "side", ctx)],
            "door": door,
            "porch": porch,
            "landing": landing,
        })

    # 2) 道具（与 grant 同房同点的「永久强化」由取得点接管，见 suppressed_by_grant）
    for raw in need(spec, "items", ctx):
        room_id = need(raw, "room", ctx)
        if room_id not in room_index:
            raise SpecError(f"{ctx}: items 落在不存在的房间 {room_id}")
        pos = need(raw, "pos", ctx)
        kind = need(raw, "type", ctx)
        if str(kind) in GRANT_DEDUP_KINDS and suppressed_by_grant(grants, room_index[room_id], pos):
            continue
        interactions.append({
            "id": "item_" + str(raw["id"]).replace("-", ""),
            "name": need(raw, "name", ctx),
            "at": [int(v) for v in pos],
            "room": room_index[room_id],
            "radius": 60,
            "kind": kind,
            "obtain": raw.get("obtain", ""),
            "missable": bool(raw.get("missable", False)),
            "requires": raw.get("requires", ""),
        })

    # 2.2) 能力取得点（§Grant）：era 原样带出，引擎两态都读这一条字段；
    # auto 只在为 true 时写（false 省略，保持 412 条交互里只有 PW 一条带这个键）
    for grant in grants:
        interaction = {
            "id": "ability_" + grant["ability"],
            "name": grant["label"],
            "at": grant["pos"],
            "room": grant["room"],
            "radius": grant["radius"],
            "ability": grant["ability"],
            "era": grant["era"],
            "text": grant["text"],
        }
        if grant["auto"]:
            interaction["auto"] = True
        interactions.append(interaction)

    # 2.5) 机关：单档 device_<index>；多盘口令（"水轮 2 · 风轮 1 · 地脉 3"）拆成 device_<index>_<dial>
    for index, device in enumerate(spec.get("devices") or []):
        label = f"{ctx}.devices[{index}]"
        room_id = need(device, "room", label)
        if room_id not in room_index:
            raise SpecError(f"{label}: 落在不存在的房间 {room_id}")
        room = rooms[room_index[room_id]]
        cx = room["rect"][0] + room["rect"][2] / 2
        fy = room["floor_y"] - FLOOR_CLEARANCE
        dials = solution_dials(device, label)
        title = str(need(device, "type", label)) + " · " + str(need(device, "id", label))
        if len(dials) > 1:
            spread = 72
            for dial in range(len(dials)):
                interactions.append({
                    "id": "device_%d_%d" % (index, dial),
                    "name": title + " · 第%d盘" % (dial + 1),
                    "at": [normalize(cx + (dial - (len(dials) - 1) / 2) * spread), normalize(fy)],
                    "room": room_index[room_id],
                    "radius": 56,
                    "device": index,
                    "dial": dial,
                })
        else:
            interactions.append({
                "id": "device_%d" % index,
                "name": title,
                "at": [normalize(cx), normalize(fy)],
                "room": room_index[room_id],
                "radius": 64,
                "device": index,
            })

    # 3) 灯龛（暗区 checkpoint 为 null → 不生成）
    checkpoint = spec.get("checkpoint")
    if checkpoint:
        room_id = need(checkpoint, "room", ctx)
        if room_id not in room_index:
            raise SpecError(f"{ctx}: checkpoint 落在不存在的房间 {room_id}")
        interactions.append({
            "id": "rest",
            "name": "灯龛 · " + rooms[room_index[room_id]]["name"],
            "at": [int(v) for v in need(checkpoint, "pos", ctx)],
            "room": room_index[room_id],
            "radius": 60,
        })

    # 4) Boss 交互点（放 Boss 房中心偏下）
    boss = spec.get("boss")
    if boss:
        room_id = need(boss, "room", ctx)
        if room_id not in room_index:
            raise SpecError(f"{ctx}: boss 落在不存在的房间 {room_id}")
        room = rooms[room_index[room_id]]
        cx = room["rect"][0] + room["rect"][2] / 2
        interactions.append({
            "id": "boss_" + ctx,
            "name": str(boss["name"]),
            "at": [normalize(cx), normalize(room["floor_y"] - FLOOR_CLEARANCE)],
            "room": room_index[room_id],
            "radius": 72,
        })

    size = need(spec, "size", ctx)
    region = {
        "id": ctx,
        "number": number,
        "chapter": chapter,
        "chapter_name": CHAPTER_NAMES[chapter],
        "title": need(spec, "name", ctx),
        "role": spec.get("role", ""),
        "color": CHAPTER_COLORS[chapter],
        "world_origin": [int(v) for v in need(spec, "canvas_origin", ctx)],
        "bounds": [0, 0, int(size[0]), int(size[1])],
        "rooms": rooms,
        "links": links,
        "interactions": interactions,
        "structure": {
            "connections": build_connections(spec, rooms, links),
            "hazards": [],
            "depth_cue": "",
            "skeleton": "spine",
            # 以下四项 v7 几何不读，但 world_game 仍会访问，保持空数组最安全
            "pogo_halls": [],
            "pogo_objects": [],
            "tiers": [],
            "niches": 0,
        },
        "mythic": {},
        # 一个区可能有两个能力（W06 = P2 + QS），标量字段按契约恒为空；
        # 能力由 interactions 里的 world_ability 交互自带 ability 字段承载（§Grant v1.4）。
        "ability": "",
        "layout_version": 7,
        "items": spec.get("items", []),
        "enemies": spec.get("enemies", []),
        "boss": boss if boss else "",
        "devices": spec.get("devices", []),
        "flags": spec.get("flags", []),
        "sprite": spec.get("sprite", []),
        "elite_guard": spec.get("elite_guard", []),
        "challenges": spec.get("challenges") or [],
        "checkpoint": checkpoint if checkpoint else None,
    }
    return normalize(region)


def build_edges(world: dict) -> list[dict]:
    edges = []
    for raw in world["edges"]:
        edge_id = need(raw, "id", "edges")
        requires = str(need(raw, "requires", edge_id)).strip()
        if requires in ABILITY_CODES:
            ability, gate = requires, ""
        elif requires in GATE_FLAGS:
            ability, gate = "", requires
        elif requires == "":
            ability, gate = "", ""
        else:
            raise SpecError(f"{edge_id}: requires {requires!r} 不在能力/进度白名单内")
        opener = GATE_OPENERS.get(edge_id, "")
        if gate and not opener:
            raise SpecError(f"{edge_id}: 进度门缺少置位方区号")
        edges.append({
            "id": edge_id,
            "a": need(raw, "a", edge_id),
            "b": need(raw, "b", edge_id),
            "kind": need(raw, "kind", edge_id),
            "requires": ability,
            "opener": opener,
            "gate": gate,
        })
    return edges


def attach_edge_ids(regions: dict, edges: list[dict]):
    """把 edge id 写回两侧的 travel_* 交互（§1 第 7 条）。"""
    for edge in edges:
        matched = 0
        for side in (edge["a"], edge["b"]):
            peer = edge["b"] if side == edge["a"] else edge["a"]
            for item in regions[side]["interactions"]:
                if item["id"] == "travel_" + peer:
                    if item.get("edge"):
                        raise SpecError(
                            f"{side}: 同一对端 {peer} 出现多条 travel_*（一条区对只允许一条边）")
                    item["edge"] = edge["id"]
                    matched += 1
        if matched != 2:
            raise SpecError(f"{edge['id']}: 两侧 travel_* 未配齐（找到 {matched} 条）")


def self_check(regions: dict, edges: list[dict]):
    problems = []
    if len(regions) != TOTAL_REGIONS:
        problems.append(f"区数 {len(regions)} != {TOTAL_REGIONS}")
    room_count = sum(len(r["rooms"]) for r in regions.values())
    if room_count != TOTAL_ROOMS:
        problems.append(f"房间数 {room_count} != {TOTAL_ROOMS}")
    if len(edges) != TOTAL_EDGES:
        problems.append(f"边数 {len(edges)} != {TOTAL_EDGES}")
    quota = {}
    for region in regions.values():
        quota[region["chapter"]] = quota.get(region["chapter"], 0) + 1
        if region["bounds"][:2] != [0, 0]:
            problems.append(f"{region['id']}: bounds 原点必须是 [0,0]")
        if region["bounds"][2] != region["world_origin"][0] and False:
            pass
        for index, pair in enumerate(region["links"]):
            meta = region["structure"]["connections"][index]
            if int(meta["link"]) != index:
                problems.append(f"{region['id']}: connections[{index}].link != {index}")
            if pair[0] >= len(region["rooms"]) or pair[1] >= len(region["rooms"]):
                problems.append(f"{region['id']}: links[{index}] 索引越界")
        # 出生点必须站在 rooms[0] 的地面上（§1 第 2 条）
        first = region["rooms"][0]
        spawn_y = first["floor_y"] - FLOOR_CLEARANCE
        if not (first["ceiling_y"] <= spawn_y <= first["floor_y"]):
            problems.append(f"{region['id']}: 出生点不在 rooms[0] 的自由空间内")
        for item in region["interactions"]:
            if not (0 <= item["room"] < len(region["rooms"])):
                problems.append(f"{region['id']}: 交互 {item['id']} 的 room 索引越界")
            if not str(item["id"]).startswith("ability_"):
                continue
            # 取得点必须落在自己那间房里（世界内站得到，不是画布外的浮点）
            room = region["rooms"][int(item["room"])]
            rx, ry, rw, rh = [float(v) for v in room["rect"]]
            ax, ay = float(item["at"][0]), float(item["at"][1])
            if not (rx <= ax <= rx + rw and ry <= ay <= ry + rh):
                problems.append(f"{region['id']}: 取得点 {item['id']} 的 at {item['at']} 不在 {room['id']} 内")
            if str(item.get("era", "")) not in GRANT_ERAS:
                problems.append(f"{region['id']}: 取得点 {item['id']} 的 era {item.get('era')!r} 非法")
    # 9 个能力各恰好一次（_schema.md 校验要求 12 第 ① 条）
    owners = {}
    for region in regions.values():
        for item in region["interactions"]:
            if not str(item["id"]).startswith("ability_"):
                continue
            code = str(item.get("ability", ""))
            if code in owners:
                problems.append(f"能力 {code} 出现两次：{owners[code]} / {region['id']}")
            owners[code] = region["id"]
    if len(owners) != TOTAL_GRANTS:
        problems.append(f"取得点 {len(owners)} 条 != {TOTAL_GRANTS}")
    if set(owners) != set(ABILITY_CODES):
        problems.append(f"取得点能力集合与白名单不一致：缺 {sorted(set(ABILITY_CODES) - set(owners))}")
    # auto（触碰即取）只允许出现在白名单代号上：给别处加 auto 会静默改变取得手感。
    for region in regions.values():
        for item in region["interactions"]:
            if not item.get("auto"):
                continue
            code = str(item.get("ability", ""))
            if code not in GRANT_AUTO_CODES:
                problems.append(
                    f"{region['id']}: {item['id']} 带 auto，但 {code or '(无代号)'} 不在 {sorted(GRANT_AUTO_CODES)}")
    for chapter, expected in CHAPTER_QUOTA.items():
        if quota.get(chapter, 0) != expected:
            problems.append(f"第 {chapter} 章区数 {quota.get(chapter, 0)} != {expected}")
    if problems:
        for line in problems:
            print("  [FAIL] " + line)
        raise SpecError(f"自检未通过：{len(problems)} 项")


def check_door_parity(regions: dict, edges: list[dict], specs: dict):
    """共边的门位两侧世界坐标必须完全相等（误差 0）。

    7 条跨空回环（loop）两侧房间不接壤，只能靠 travel_* 传送，不参与共边校验。
    """
    shared = [e for e in edges if e["kind"] != "loop"]
    if len(shared) != 29:
        raise SpecError(f"共边数 {len(shared)} != 29")
    if len(edges) - len(shared) != 7:
        raise SpecError(f"跨空回环数 {len(edges) - len(shared)} != 7")
    for edge in shared:
        points = {}
        for side, peer in ((edge["a"], edge["b"]), (edge["b"], edge["a"])):
            origin = regions[side]["world_origin"]
            for raw in specs[side]["world_links"]:
                if raw["to"] != peer:
                    continue
                points[side] = (origin[0] + raw["pos"][0], origin[1] + raw["pos"][1])
        if len(points) != 2:
            raise SpecError(f"{edge['id']}: 缺少 world_links 一侧")
        if points[edge["a"]] != points[edge["b"]]:
            raise SpecError(
                f"{edge['id']}: 门位世界坐标不一致 {points[edge['a']]} != {points[edge['b']]}")


def describe(regions: dict, edges: dict):
    rooms = sum(len(r["rooms"]) for r in regions.values())
    interactions = sum(len(r["interactions"]) for r in regions.values())
    quota = {}
    for region in regions.values():
        quota[region["chapter"]] = quota.get(region["chapter"], 0) + 1
    print(f"区数 {len(regions)} / 房间 {rooms} / 边 {len(edges)} / 交互 {interactions}")
    print("每章区数 " + " / ".join(str(quota.get(c, 0)) for c in range(1, 9)))
    grants = {}
    autos = []
    for region in regions.values():
        for item in region["interactions"]:
            if str(item["id"]).startswith("ability_"):
                grants[str(item["ability"])] = region["id"]
                if item.get("auto"):
                    autos.append(str(item["ability"]))
    print("能力取得点 %d 条 %s ｜ 触碰即取 %s" % (len(grants), " ".join(
        f"{code}@{grants[code]}" for code in ABILITY_CODES if code in grants),
        "/".join(autos) if autos else "无"))
    kinds = {}
    for edge in edges:
        kinds[edge["kind"]] = kinds.get(edge["kind"], 0) + 1
    print("边类型 " + " ".join(f"{k}={v}" for k, v in sorted(kinds.items())))
    gated = [e["id"] + ":" + e["gate"] for e in edges if e["gate"]]
    print("进度门 " + (", ".join(gated) if gated else "无"))
    dark = [r["id"] for r in regions.values() if r["checkpoint"] is None]
    print("暗区（无灯龛） " + ", ".join(sorted(dark)))


def dump(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="29 区世界运行时转换器")
    parser.add_argument("--only", metavar="W05", help="只替换该 region 节点，其余保留原样")
    parser.add_argument("--dry-run", action="store_true", help="只打印统计与差异，不落盘")
    args = parser.parse_args(argv)

    world, specs = load_design()
    titles = {region["id"]: region["name"] for region in world["regions"]}
    if set(titles) != set(specs):
        raise SpecError("世界索引与单图数据的区号集合不一致")

    numbers = {region_id: index + 1 for index, region_id in enumerate(WORLD_ORDER)}
    if set(numbers) != set(titles):
        raise SpecError("WORLD_ORDER 与设计区号集合不一致")

    regions = {}
    for region_id in WORLD_ORDER:
        meta = next(r for r in world["regions"] if r["id"] == region_id)
        regions[region_id] = build_region(meta, specs[region_id], numbers[region_id], titles)

    edges = build_edges(world)
    attach_edge_ids(regions, edges)
    self_check(regions, edges)
    check_door_parity(regions, edges, specs)

    if args.only:
        target = args.only.upper()
        if target not in regions:
            raise SpecError(f"--only 未知区号 {args.only}")
        if not OUTPUT.exists():
            raise SpecError("--only 需要已存在的 world_regions.json")
        existing = json.loads(OUTPUT.read_text(encoding="utf-8"))
        existing["version"] = 7
        existing.setdefault("regions", {})[target] = regions[target]
        existing["edges"] = edges
        payload = existing
        print(f"单区替换 {target}（其余节点保留）")
    else:
        payload = {"version": 7, "regions": regions, "edges": edges}

    describe(payload["regions"], payload["edges"])
    text = dump(payload)

    if args.dry_run:
        print("--dry-run：未落盘")
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"写入 {OUTPUT.relative_to(ROOT)}（{len(text.encode('utf-8'))} 字节）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
