#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
地图规格一致性校验器（25 区 · 单图 JSON 契约）
用法：python tools/verify_map_specs.py [--only w01 w02 ...]

校验项：
  1. 单图 JSON 与总控 world-25.json 的一致性（id/name/chapter/role/rooms_est）
  2. 房间矩形：不重叠、相接边对齐、落在 size 内、floor_y 合法
  3. 区内连通：主脉从入口房可走到所有出口房
  4. 跨区连接：目标区真实存在、互为邻接、方向合法
  5. requires 取值合法（能力代号 / 进度旗标 / 空）
  6. 道具与敌人坐标落在其声明房间内
  7. checkpoint 可站立且不在锁门战场房
  8. grants（能力取得点，v1.4）：白名单 / 房间有效 / 坐标在房内且留 20px 余量 /
     era 合法 / radius 40—64 / 9 个能力各恰好一条
退出码：0=PASS/仅有 WARN，1=FAIL
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPS = ROOT / "docs" / "design" / "maps"
DATA = MAPS / "data"
WORLD = DATA / "world-25.json"

ABILITIES = {"", "VC", "P2", "QS", "PA", "PW", "PG", "DS", "DT", "DB"}
PROGRESS = {"ENDGAME", "FINAL_DOOR"}
# 能力取得点（grants · 契约 v1.4）：全作 9 条，分布在 8 区（W06 两条）
GRANT_CODES = {"VC", "P2", "QS", "PA", "PW", "PG", "DS", "DT", "DB"}
GRANT_ERAS = {"past", "present", "both"}
GRANT_RADIUS = (40, 64)
GRANT_EDGE = 20      # 玩家碰撞体半宽 20px：取得点必须留出这么多余量，不得贴墙/悬空
GRANT_TOTAL = 9
ALLOWED_REQUIRES = ABILITIES | PROGRESS
DEVICE_TYPES = {"水路改道", "潮位", "风场", "根系", "升降平台", "光路", "音柱", "三灵协作"}
ENEMY_TIERS = {"杂兵", "远程", "飞行", "环境", "精英"}
# 静态危险地形（地刺）· 总控 §7.4（v1.1）：形态写在 name 里，tier 必须是「环境」
SPIKE_FORMS = ("（地刺）", "（顶刺）", "（斜刺墙）")
SPIKE_FORBIDDEN_ROLES = {"准入秘境", "过渡", "终局"}
SPIKE_TOTAL_EXPECT = (18, 11)  # (处, 区) —— 总控 §7.1/§7.4 批准口径
# 区内/本图旗标：wXX_something
LOCAL_FLAG = __import__("re").compile(r"^w\d{2}_[a-z0-9_]+$")

errors, warns = [], []


def err(where, msg):
    errors.append(f"[FAIL] {where}: {msg}")


def warn(where, msg):
    warns.append(f"[WARN] {where}: {msg}")


def rects_overlap(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return not (ax + aw <= bx or bx + bw <= ax or ay + ah <= by or by + bh <= ay)


def touch_edges(a, b):
    """相接边完全对齐：共享一条边且该边上的区间完全吻合或至少部分重合 >=48px。"""
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    # 水平相接
    if abs((ax + aw) - bx) < 1 or abs((bx + bw) - ax) < 1:
        lo, hi = max(ay, by), min(ay + ah, by + bh)
        return hi - lo
    if abs((ay + ah) - by) < 1 or abs((by + bh) - ay) < 1:
        lo, hi = max(ax, bx), min(ax + aw, bx + bw)
        return hi - lo
    return 0


def check_room(rm, size, where):
    rid = rm.get("id", "?")
    rect = rm.get("rect")
    if not isinstance(rect, list) or len(rect) != 4:
        err(f"{where}/{rid}", "rect 非法")
        return
    x, y, w, h = rect
    if w <= 0 or h <= 0:
        err(f"{where}/{rid}", "rect 宽高必须 > 0")
    if x < 0 or y < 0 or x + w > size[0] or y + h > size[1]:
        err(f"{where}/{rid}", f"rect {rect} 超出 size {size}")
    fy = rm.get("floor_y")
    if not isinstance(fy, (int, float)) or not (y < fy <= y + h):
        err(f"{where}/{rid}", f"floor_y={fy} 不在 rect 的 y 范围内")
    if rm.get("era") not in {"both", "past", "present"}:
        err(f"{where}/{rid}", f"era 非法: {rm.get('era')}")


def check_map(path, world_regions):
    raw = path.read_text(encoding="utf-8")
    try:
        d = json.loads(raw)
    except Exception as e:
        err(path.name, f"JSON 解析失败: {e}")
        return None

    mid = d.get("id")
    where = mid or path.name
    need = ["id", "name", "chapter", "role", "shape", "aspect", "size", "canvas_origin",
            "rooms", "links", "world_links", "items", "enemies", "sprite",
            "elite_guard", "boss", "devices", "flags", "checkpoint"]
    for k in need:
        if k not in d:
            err(where, f"缺字段 {k}")

    if mid in world_regions:
        wr = world_regions[mid]
        if d.get("name") != wr.get("name"):
            err(where, f"区名与总控不一致: {d.get('name')} != {wr.get('name')}")
        if d.get("chapter") != wr.get("chapter"):
            err(where, "chapter 与总控不一致")
        if wr.get("rooms_est") != len(d.get("rooms", [])):
            err(where, f"房间数 {len(d.get('rooms', []))} != 总控 rooms_est {wr.get('rooms_est')}")
    else:
        err(where, "总控 world-25.json 中不存在该 id")

    size = d.get("size") or [0, 0]
    if not (isinstance(size, list) and len(size) == 2):
        err(where, "size 非法")
        return d

    rooms = d.get("rooms") or []
    by_id = {}
    for rm in rooms:
        rid = rm.get("id")
        if rid in by_id:
            err(where, f"房间 id 重复: {rid}")
        by_id[rid] = rm
        check_room(rm, size, where)

    # 重叠 & 相接
    for i in range(len(rooms)):
        for j in range(i + 1, len(rooms)):
            a, b = rooms[i].get("rect"), rooms[j].get("rect")
            if not (a and b):
                continue
            if rects_overlap(a, b):
                err(where, f"房间重叠: {rooms[i]['id']} ↔ {rooms[j]['id']}")
            elif touch_edges(a, b) < 48:
                # 相邻但共边不足 48px：可走性差
                if touch_edges(a, b) > 0:
                    warn(where, f"相接边过窄(<48px): {rooms[i]['id']} ↔ {rooms[j]['id']}")

    # 区内连通（links 图）
    adj = {rid: set() for rid in by_id}
    for lk in d.get("links") or []:
        a, b = lk.get("a"), lk.get("b")
        if a not in by_id or b not in by_id:
            err(where, f"link 指向不存在的房间: {a}->{b}")
            continue
        adj[a].add(b)
        adj[b].add(a)
        if lk.get("kind") not in {"main", "branch", "loop", "secret"}:
            err(where, f"link kind 非法: {lk.get('kind')}")
        req = lk.get("requires", "") or ""
        if req and req not in ALLOWED_REQUIRES and not LOCAL_FLAG.match(req):
            err(where, f"link requires 非法: {req}")

    if by_id:
        start = next(iter(by_id))
        seen, stack = {start}, [start]
        while stack:
            cur = stack.pop()
            for nxt in adj[cur]:
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        missing = set(by_id) - seen
        if missing:
            err(where, f"区间不可达房间: {sorted(missing)}")

    # 跨区连接
    neighbors = {}
    if mid in world_regions:
        for lk in world_regions[mid].get("links", []):
            neighbors[lk["to"]] = lk.get("requires", "")
    for wl in d.get("world_links") or []:
        to = wl.get("to")
        if to not in neighbors:
            err(where, f"跨区连接目标 {to} 不是总控邻接区")
        elif (wl.get("requires", "") or "") != (neighbors[to] or ""):
            warn(where, f"跨区连接 {to} 的 requires='{wl.get('requires','')}' 与总控 '{neighbors[to]}' 不一致")
        if wl.get("room") not in by_id:
            err(where, f"跨区连接引用不存在的房间: {wl.get('room')}")
        wreq = wl.get("requires", "") or ""
        if wreq and wreq not in ALLOWED_REQUIRES and not LOCAL_FLAG.match(wreq):
            err(where, f"跨区连接 requires 非法: {wreq}")

    # 道具位置
    for it in d.get("items") or []:
        rm = by_id.get(it.get("room"))
        if not rm:
            err(where, f"道具 {it.get('id')} 房间不存在: {it.get('room')}")
            continue
        pos = it.get("pos") or [0, 0]
        x, y, w, h = rm["rect"]
        if not (x <= pos[0] <= x + w and y <= pos[1] <= y + h):
            err(where, f"道具 {it.get('id')} 坐标 {pos} 不在房间 {rm['id']} 内")

    # 敌人
    for en in d.get("enemies") or []:
        if en.get("tier") not in ENEMY_TIERS:
            err(where, f"敌人 {en.get('id')} tier 非法: {en.get('tier')}")
        for r in en.get("rooms") or []:
            if r not in by_id:
                err(where, f"敌人 {en.get('id')} 房间不存在: {r}")

    # 精灵 / 精怪 / Boss
    for sp in d.get("sprite") or []:
        if sp.get("room") not in by_id:
            err(where, f"精灵 {sp.get('id')} 房间不存在")
        if sp.get("era") == "both":
            warn(where, f"精灵 {sp.get('id')} 标记为 both，但精灵应单时代独占")
        if "counted" in sp and not isinstance(sp["counted"], bool):
            err(where, f"精灵 {sp.get('id')} counted 必须是 bool")

    # 平台挑战段（总控 §7.5；全作仅 W07/W09/W12 三段）
    for ch in d.get("challenges") or []:
        cnt, steps = ch.get("count"), ch.get("steps") or []
        if cnt != len(steps):
            err(where, f"挑战段 {ch.get('id')} count {cnt} != steps 长度 {len(steps)}")
        if [s.get("n") for s in steps] != list(range(1, len(steps) + 1)):
            err(where, f"挑战段 {ch.get('id')} steps[].n 未从 1 连续编号")
        if ch.get("optional") is not True:
            err(where, f"挑战段 {ch.get('id')} optional 必须为 true（§7.5 第 3 条）")
        for r in ch.get("rooms") or []:
            if r not in by_id:
                err(where, f"挑战段 {ch.get('id')} 房间不存在: {r}")
        for s in steps:
            for k in ("from", "to"):
                if s.get(k) not in by_id:
                    err(where, f"挑战段 {ch.get('id')} 段 {s.get('n')} 的 {k} 房号不存在")
            if s.get("era") not in ("both", "past", "present"):
                err(where, f"挑战段 {ch.get('id')} 段 {s.get('n')} era 非法: {s.get('era')}")
            for ab in s.get("requires") or []:
                if ab not in ALLOWED_REQUIRES:
                    err(where, f"挑战段 {ch.get('id')} 段 {s.get('n')} requires 非法: {ab}")
    for eg in d.get("elite_guard") or []:
        if eg.get("room") not in by_id:
            err(where, f"精怪 {eg.get('id')} 房间不存在")
        if len(eg.get("moves") or []) > 3:
            err(where, f"精怪 {eg.get('id')} 招式 {len(eg.get('moves'))} > 3")
        for mv in eg.get("moves") or []:
            if mv.get("damage", 0) >= 1 and mv.get("telegraph", 0) < 0.3:
                err(where, f"精怪 {eg.get('id')} 攻击招式 {mv.get('name')} 预警 <0.3s")

    boss = d.get("boss")
    if boss:
        if boss.get("room") not in by_id:
            err(where, "Boss 房间不存在")
        for mv in boss.get("moves") or []:
            if mv.get("damage", 0) >= 1 and mv.get("telegraph", 0) < 0.3:
                err(where, f"Boss 攻击招式 {mv.get('name')} 预警 <0.3s")

    # 机关
    for dv in d.get("devices") or []:
        if dv.get("type") not in DEVICE_TYPES:
            err(where, f"机关类型越界: {dv.get('type')}")
        if dv.get("room") not in by_id:
            err(where, f"机关 {dv.get('id')} 房间不存在")

    # 静态危险地形（地刺）· 总控 §7.4：tier 必须是环境；秘境/过渡/终局与 Boss 战场房恒为 0
    boss_room = (boss or {}).get("room") if boss else None
    for en in d.get("enemies") or []:
        nm = en.get("name") or ""
        if not any(f in nm for f in SPIKE_FORMS):
            continue
        if en.get("tier") != "环境":
            err(where, f"静态地刺 {en.get('id')} 的 tier 必须是「环境」，实为 {en.get('tier')}")
        if d.get("role") in SPIKE_FORBIDDEN_ROLES:
            err(where, f"静态地刺 {en.get('id')} 落在禁区 role={d.get('role')}（§7.4 第 6 条：秘境/过渡/终局恒 0 处）")
        if boss_room and boss_room in (en.get("rooms") or []):
            err(where, f"静态地刺 {en.get('id')} 位于 Boss 战场房 {boss_room}（§7.4 第 6 条）")

    # 存档点
    cp = d.get("checkpoint") or {}
    if not cp:
        # 暗区与纯叙事秘境没有常驻灯龛：不设 checkpoint 是合法设计（总控 v1.3 暗区档）
        if d.get("role") not in ("暗区",):
            err(where, "checkpoint 缺失")
    elif cp.get("room") not in by_id:
        err(where, "checkpoint 房间不存在")
    else:
        locked = {eg.get("room") for eg in (d.get("elite_guard") or [])}
        if boss:
            locked.add(boss.get("room"))
        if cp.get("room") in locked:
            err(where, "checkpoint 设在锁门战场房内")
        px, py = cp.get("pos") or [0, 0]
        x, y, w, h = by_id[cp["room"]]["rect"]
        if not (x <= px <= x + w and y <= py <= y + h):
            err(where, "checkpoint 坐标不在其房间内")

    # 能力取得点（grants · 契约 v1.4；全作 9 条 / 8 区）
    for gr in d.get("grants") or []:
        code = gr.get("ability")
        tag = f"grants/{code}"
        if code not in GRANT_CODES:
            err(where, f"{tag}: ability 不在白名单 VC/P2/QS/PA/PW/PG/DS/DT/DB 内")
        if gr.get("era") not in GRANT_ERAS:
            err(where, f"{tag}: era 非法: {gr.get('era')}")
        rad = gr.get("radius")
        if not isinstance(rad, int) or not (GRANT_RADIUS[0] <= rad <= GRANT_RADIUS[1]):
            err(where, f"{tag}: radius {rad} 越界（{GRANT_RADIUS[0]}—{GRANT_RADIUS[1]}）")
        for k in ("label", "text"):
            if not isinstance(gr.get(k), str) or not gr.get(k).strip():
                err(where, f"{tag}: {k} 缺失或为空")
        if isinstance(gr.get("text"), str) and len(gr["text"]) > 40:
            err(where, f"{tag}: text 超过 40 字（{len(gr['text'])}）")
        grm = by_id.get(gr.get("room"))
        if not grm:
            err(where, f"{tag}: 房间不存在: {gr.get('room')}")
            continue
        pos = gr.get("pos")
        if not (isinstance(pos, list) and len(pos) == 2):
            err(where, f"{tag}: pos 非法: {pos}")
            continue
        gx, gy, gw, gh = grm["rect"]
        if not (gx <= pos[0] <= gx + gw and gy <= pos[1] <= gy + gh):
            err(where, f"{tag}: 坐标 {pos} 不在房间 {grm['id']} 内")
        elif min(pos[0] - gx, gx + gw - pos[0], pos[1] - gy, gy + gh - pos[1]) < GRANT_EDGE:
            err(where, f"{tag}: 坐标 {pos} 距房间 {grm['id']} 边界不足 {GRANT_EDGE}px（贴墙/悬空风险）")

    return d


def main():
    only = set()
    if "--only" in sys.argv:
        only = {s.lower() for s in sys.argv[sys.argv.index("--only") + 1:]}

    if not WORLD.exists():
        print("缺少总控数据 data/world-25.json")
        return 1
    wd = json.loads(WORLD.read_text(encoding="utf-8"))
    world_regions = {r["id"]: r for r in wd["regions"]}

    files = sorted(DATA.glob("w[0-9][0-9].json"))
    if only:
        files = [f for f in files if f.stem.lower() in only]
    if not files:
        print("未找到任何单图 JSON（data/wXX.json）")
        return 1

    print(f"校验 {len(files)} 份单图规格 …\n")
    total_rooms = 0
    for f in files:
        d = check_map(f, world_regions)
        if d:
            n = len(d.get("rooms") or [])
            total_rooms += n
            print(f"  {d.get('id')} {d.get('name'):<10} 房间 {n:>3}  精灵 {sum(1 for sp in (d.get('sprite') or []) if sp.get('counted', True) is not False):>2}  "
                  f"精怪 {len(d.get('elite_guard') or []):>2}  Boss {'✓' if d.get('boss') else '—'}"
                  f"  挑战 {sum(c.get('count', 0) for c in (d.get('challenges') or [])) or '—'}")

    print(f"\n合计房间 {total_rooms}（总控 {sum(r['rooms_est'] for r in wd['regions'])}）")

    # 静态地刺总量核对（总控 §7.1 批准口径 18 处 / 11 区，分章 3/2/3/1/4/1/4/0）
    # 口径：每条「环境」地刺条目 = 1 处（1 组），`count` 是该处的根数，不参与处数统计
    if not only:
        z, n, roots = 0, 0, 0
        for f in sorted(DATA.glob("w[0-9][0-9].json")):
            try:
                dd = json.loads(f.read_text(encoding="utf-8"))
            except Exception:
                continue
            hits = [en for en in (dd.get("enemies") or [])
                    if any(fm in (en.get("name") or "") for fm in SPIKE_FORMS)]
            if hits:
                z += 1
                n += len(hits)
                roots += sum(h.get("count", 1) for h in hits)
        print(f"静态地刺 {n} 处 / {z} 区（共 {roots} 根，总控口径 {SPIKE_TOTAL_EXPECT[0]} 处 / {SPIKE_TOTAL_EXPECT[1]} 区）")
        if (n, z) != SPIKE_TOTAL_EXPECT:
            warn("地刺总量", f"{n} 处 / {z} 区 与总控口径 {SPIKE_TOTAL_EXPECT[0]} / {SPIKE_TOTAL_EXPECT[1]} 不符（§7.4）")

        # 精灵计数核对（决策 4A：同一只个体跨区出现，只栖息区计入总数）
        sc, shared = 0, 0
        for f in sorted(DATA.glob("w[0-9][0-9].json")):
            try:
                dd = json.loads(f.read_text(encoding="utf-8"))
            except Exception:
                continue
            for sp in dd.get("sprite") or []:
                if sp.get("shared_individual"):
                    shared += 1
                if sp.get("counted", True) is not False:
                    sc += 1
        want = sum((r.get("encounters") or {}).get("sprite", 0) for r in wd["regions"])
        print(f"精灵计数 {sc}（总控 encounters 合计 {want}；含 {shared} 条跨区同个体实体）")
        if sc != want:
            warn("精灵计数", f"{sc} 与总控 encounters.sprite 合计 {want} 不符（决策 4A）")

        # 跨区接口核对（TASK-05：世界坐标、共边门位、to_room）
        allreg = {}
        for f in sorted(DATA.glob("w[0-9][0-9].json")):
            try:
                dd = json.loads(f.read_text(encoding="utf-8"))
            except Exception:
                continue
            allreg[dd["id"]] = dd

        def _rooms(x):
            return {r["id"] for r in x.get("rooms") or []}

        pairs = {}
        for rid, dd in allreg.items():
            for wl in dd.get("world_links") or []:
                t = wl.get("to")
                if t not in allreg:
                    err("跨区", f"{rid} 指向不存在的区: {t}")
                    continue
                pairs.setdefault(tuple(sorted((rid, t))), []).append((rid, wl))
                if not isinstance(wl.get("to_room"), str) or not wl["to_room"]:
                    err("跨区", f"{rid}->{t} 的 to_room 为空")
                elif wl["to_room"] not in _rooms(allreg[t]):
                    err("跨区", f"{rid}->{t} 的 to_room 不存在: {wl['to_room']}")

        flush_n, gap_n, mism = 0, 0, []
        for key, links in pairs.items():
            a, b = key
            sa, sb = {r for r, _ in links}, None
            if sa != {a, b}:
                err("跨区", f"{a}-{b} 不是双向接口（只有 {sorted(sa)} 声明）")
                continue
            kinds = {wl.get("kind", "main") for _, wl in links}
            is_loop = "loop" in kinds
            LA = next(wl for r, wl in links if r == a)
            LB = next(wl for r, wl in links if r == b)
            ox, oy = allreg[a]["canvas_origin"]
            px, py = allreg[b]["canvas_origin"]
            pa = (ox + LA["pos"][0], oy + LA["pos"][1])
            pb = (px + LB["pos"][0], py + LB["pos"][1])
            if is_loop:
                gap_n += 1
                continue
            flush_n += 1
            if abs(pa[0] - pb[0]) > 1 or abs(pa[1] - pb[1]) > 1:
                mism.append(f"{a}-{b} {pa} vs {pb}")
        for m in mism:
            err("跨区", f"共边门位不重合: {m}")
        print(f"跨区接口 {flush_n} 条共边 / {gap_n} 条跨空连接（回环），门位不重合 {len(mism)} 处")

        # 平台挑战段核对（总控 §7.5：全作 3 段 / 3 区）
        cz, cn = 0, 0
        for f in sorted(DATA.glob("w[0-9][0-9].json")):
            try:
                dd = json.loads(f.read_text(encoding="utf-8"))
            except Exception:
                continue
            chs = dd.get("challenges") or []
            if chs:
                cz += 1
                cn += sum(c.get("count", 0) for c in chs)
        print(f"平台挑战段 {cn} 段 / {cz} 区（总控 §7.5 口径 16 段 / 3 区）")
        if (cn, cz) != (16, 3):
            warn("挑战段总量", f"{cn} 段 / {cz} 区 与 §7.5 清单 16 段 / 3 区 不符")

        # 能力取得点核对（契约 v1.4：9 个能力各恰好一条 / 共 9 条 / 分布在 8 区）
        gz, gn, seen = 0, 0, {}
        for f in sorted(DATA.glob("w[0-9][0-9].json")):
            try:
                dd = json.loads(f.read_text(encoding="utf-8"))
            except Exception:
                continue
            grs = dd.get("grants") or []
            if grs:
                gz += 1
                gn += len(grs)
            for gr in grs:
                seen.setdefault(gr.get("ability"), []).append(dd.get("id"))
        print(f"能力取得点 {gn} 条 / {gz} 区（契约 {GRANT_TOTAL} 条：9 个能力各恰好一条）")
        for code in sorted(GRANT_CODES):
            hit = seen.get(code) or []
            if not hit:
                err("能力取得点", f"{code} 无取得入口（grants 缺项）")
            elif len(hit) > 1:
                err("能力取得点", f"{code} 出现 {len(hit)} 次（{'、'.join(hit)}），必须恰好一条")
        for code, hit in seen.items():
            if code not in GRANT_CODES:
                err("能力取得点", f"越界能力代号 {code}（{'、'.join(hit)}）")
        if gn != GRANT_TOTAL:
            err("能力取得点", f"共 {gn} 条，契约 v1.4 为 {GRANT_TOTAL} 条")

    for w in warns:
        print(w)
    for e in errors:
        print(e)

    print("\n=== 判定 ===")
    if errors:
        print(f"FAIL · {len(errors)} 项错误，{len(warns)} 项警告")
        return 1
    if warns:
        print(f"CONCERNS · 0 项错误，{len(warns)} 项警告")
        return 0
    print("PASS · 全部检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
