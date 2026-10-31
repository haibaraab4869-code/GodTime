#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 4 个内嵌暗区升格为独立区（总控 v1.3 · 决策 3A · 2026-10-30）

W03 无姓者墓园 → W26 ｜ W10 藏风坳 → W27 ｜ W15 溺火石碑 → W28 ｜ W25 不曾发生的春天 → W29

做四件事（幂等，可重复跑）：
1. 把宿主里指定的房间（含房里的一切）整体迁到新区，房号重排为 R01…；
2. 宿主用「延长邻房」的方式把空出来的矩形重新铺满（不加房，总数保持 320）；
3. 两侧各写一条 `kind=secret` 的 world_link，门位取新区的设计值；
4. 旧 `wXX_*` 旗标改前缀（宿主 → 新区）。

跑完必须接着跑 `python tools/build_world_coords.py` 重算世界坐标。
"""
from __future__ import annotations

import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "docs" / "design" / "maps" / "data"

# host: 宿主 ｜ new: 新区 ｜ rooms: 迁出的房号（按新区房序）｜ size: 新区画布
# host_tiles: 宿主重铺后的矩形（房号 → rect）
# host_door / new_door: 两侧世界连接（门位是**区局部坐标**，自由轴由 build_world_coords 校准）
MIGRATIONS = [
    dict(
        host="W03", new="W26", name="无姓者墓园", chapter=1,
        shape="矩形", aspect="1.10:1", role="暗区",
        rooms=["R16", "R17"],
        size=[704, 640],
        # 迁入后重排：R01 碑庭在下（贴门），R02 名墙在上（凶骨）
        order=[("R16", "R01", [0, 320, 704, 320]), ("R17", "R02", [0, 0, 704, 320])],
        host_tiles={
            "R12": [576, 1120, 576, 800],
            "R13": [1152, 1120, 608, 800],
            "R14": [1760, 1120, 352, 800],
            "R15": [0, 1600, 576, 320],
        },
        host_door=dict(side="W", room="R15", pos=[0, 1760]),
        new_door=dict(side="E", room="R01", pos=[704, 480]),
        note="井底南口西墙开洞进墓园；过去态可读的无姓碑开洞，现在态是实心墙",
    ),
    dict(
        host="W10", new="W27", name="藏风坳", chapter=3,
        shape="分叉团块", aspect="2.29:1", role="暗区",
        rooms=["R07", "R08", "R11"],
        size=[1392, 608],
        order=[("R07", "R01", [0, 320, 672, 288]),
               ("R08", "R02", [0, 0, 672, 320]),
               ("R11", "R03", [672, 0, 720, 608])],
        host_tiles={
            "R04": [0, 0, 672, 1216],
            "R12": [672, 0, 720, 608],
        },
        host_door=dict(side="N", room="R04", pos=[336, 0]),
        new_door=dict(side="S", room="R01", pos=[336, 608]),
        note="风口西廊北墙的横风口后是坳口；玄关需 P2+PA 穿 420 横风口",
    ),
    dict(
        host="W15", new="W28", name="溺火石碑", chapter=5,
        shape="拱顶", aspect="1.65:1", role="暗区",
        rooms=["R05"],
        size=[528, 320],
        order=[("R05", "R01", [0, 0, 528, 320])],
        host_tiles={"R04": [0, 640, 1056, 320]},
        host_door=dict(side="N", room="R06", pos=[264, 0]),
        new_door=dict(side="S", room="R01", pos=[264, 320]),
        note="碑在塔顶北檐外的风口岩龛里；门槛热浪 2 s 扣 1 血，DS 后归零",
    ),
    dict(
        host="W25", new="W29", name="不曾发生的春天", chapter=8,
        shape="矩形", aspect="0.56:1", role="暗区",
        rooms=["R09", "R10"],
        size=[720, 1280],
        order=[("R09", "R01", [0, 0, 720, 640]),
               ("R10", "R02", [0, 640, 720, 640])],
        host_tiles={"R04": [2480, 720, 720, 2480]},
        host_door=dict(side="E", room="R04", pos=[3200, 1000]),
        new_door=dict(side="W", room="R01", pos=[0, 280]),
        note="原告席东墙的三字叠刻门；w25_verdict_sealed 前不可开",
    ),
]


def load(rid):
    return json.loads((DATA / f"{rid.lower()}.json").read_text(encoding="utf-8"))


def save(rid, d):
    with io.open(DATA / f"{rid.lower()}.json", "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)


def migrate(m):
    host = load(m["host"])
    if (DATA / f"{m['new'].lower()}.json").exists():
        raise SystemExit(f"{m['new']} 已存在，迁移不重复执行")

    rid_map = {old: new for old, new, _ in m["order"]}
    rect_map = {new: rect for _, new, rect in m["order"]}
    src_rooms = {r["id"]: r for r in host["rooms"]}
    moved = [src_rooms[o] for o, _, _ in m["order"]]

    # ---- 新区 ----
    new = {
        "id": m["new"], "name": m["name"], "chapter": m["chapter"],
        "role": m["role"], "shape": m["shape"], "aspect": m["aspect"],
        "size": m["size"], "canvas_origin": [0, 0],
        "rooms": [], "links": [], "world_links": [],
        "items": [], "enemies": [], "sprite": [], "elite_guard": [],
        "devices": [], "flags": [], "checkpoint": None,
    }
    # 逐房做仿射映射：房号重排会把房间搬到画布别的位置，道具/地面高不能整体平移
    def remap(room_id, pos):
        old = src_rooms[room_id]["rect"]
        new_r = rect_map[rid_map[room_id]]
        return [pos[0] - old[0] + new_r[0], pos[1] - old[1] + new_r[1]]

    for r in moved:
        nid = rid_map[r["id"]]
        nr = rect_map[nid]
        floor = r.get("floor_y")
        if isinstance(floor, int):
            floor = r["rect"][1] + r["rect"][3] if abs(floor - (r["rect"][1] + r["rect"][3])) <= 64 \
                else floor - r["rect"][1] + nr[1]
        new["rooms"].append(dict(
            r, id=nid, rect=list(nr), floor_y=floor,
            region=(r.get("region", "").replace("暗区", "").strip() or m["name"]),
        ))

    # 区内 link：两端都迁过来的才保留
    for lk in host.get("links") or []:
        if lk["a"] in rid_map and lk["b"] in rid_map:
            new["links"].append(dict(lk, a=rid_map[lk["a"]], b=rid_map[lk["b"]]))

    # 道具 / 敌人 / 机关 / 灯龛：按房间挑出来搬走
    for key in ("items", "enemies", "sprite", "elite_guard"):
        keep = []
        for it in host.get(key) or []:
            rs = it.get("rooms") or ([it["room"]] if "room" in it else [])
            hit = [x for x in rs if x in rid_map]
            if not hit:
                keep.append(it)
                continue
            rest = [x for x in rs if x not in rid_map]
            if rest:
                keep.append(dict(it, **({"rooms": rest} if "rooms" in it else {})))
            it = dict(it)
            if "room" in it:
                it["room"] = rid_map[it["room"]]
                if it.get("pos"):
                    it["pos"] = remap([k for k, v in rid_map.items() if v == it["room"]][0], it["pos"])
            if "rooms" in it:
                it["rooms"] = [rid_map[x] for x in it["rooms"] if x in rid_map]
                if len(it["rooms"]) != len(rs):
                    # 一组成员跨了宿主与暗区两侧：这里只搬进新区的那部分，数量口径需人工复核
                    print(f"  [注意] {it['id']} {it['name']} 跨区，新区只收 {it['rooms']}")
            new[key].append(it)
        host[key] = keep

    moved_ids = set(rid_map)
    host["devices"] = [d for d in host.get("devices") or [] if d.get("room") not in moved_ids]

    if host.get("checkpoint") and host["checkpoint"].get("room") in moved_ids:
        cp = dict(host["checkpoint"])
        cp["room"] = rid_map[cp["room"]]
        new["checkpoint"] = cp
        host["checkpoint"] = None

    # ---- 宿主：移房 + 重铺 ----
    host["rooms"] = [r for r in host["rooms"] if r["id"] not in moved_ids]
    for r in host["rooms"]:
        if r["id"] in m["host_tiles"]:
            r["rect"] = list(m["host_tiles"][r["id"]])
    host["links"] = [lk for lk in host.get("links") or []
                     if lk["a"] not in moved_ids and lk["b"] not in moved_ids]

    # ---- 旗标改前缀 ----
    old_pre, new_pre = m["host"].lower() + "_", m["new"].lower() + "_"
    new["flags"] = []
    kept = []
    for f in host.get("flags") or []:
        if any(t in f for t in ("grave", "grove", "stele", "spring", "narr", "soul")) and f.startswith(old_pre):
            new["flags"].append(f.replace(old_pre, new_pre, 1))
        else:
            kept.append(f)
    host["flags"] = kept
    for it in new["items"]:
        stem = "narr" if it["type"] == "叙事物" else "soul"
        f = f"{new_pre}{stem}_{it['room'].lower()}"
        if f not in new["flags"]:
            new["flags"].append(f)

    # ---- 世界连接（两侧各一条，门位先用设计值，坐标由构建器校准）----
    host["world_links"].append(dict(
        m["host_door"], to=m["new"], to_room=new["rooms"][0]["id"],
        requires="", kind="secret", flush=True))
    new["world_links"].append(dict(
        m["new_door"], to=m["host"], to_room=m["host_door"]["room"],
        requires="", kind="secret", flush=True))

    save(m["host"], host)
    save(m["new"], new)
    print(f"{m['host']} → {m['new']} {m['name']}: 迁出 {len(moved)} 房，宿主剩 {len(host['rooms'])} 房；"
          f"搬走 {len(new['items'])} 道具 / {len(new['enemies'])} 敌人组")


def main():
    for m in MIGRATIONS:
        migrate(m)


if __name__ == "__main__":
    main()
