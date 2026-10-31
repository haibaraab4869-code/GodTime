"""Diagnose why the map still reads as endless filler platforms.

Reads the shipped runtime data and reports the per-region platform budget split,
so the gap between M01 (migrated) and the other 47 regions is quantified rather
than guessed.
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "game/data/world_regions.json"

d = json.loads(DATA.read_text(encoding="utf-8"))
regions = d["regions"]

tiers = {}
rows = []
tot_step = tot_hall = tot_misc = tot_anchor = 0

for rid in sorted(regions, key=lambda s: int(s[1:])):
    v = regions[rid]
    s = v["structure"]
    lv = int(v.get("layout_version", 6))
    rooms = v["rooms"]
    floors = [r["rect"][1] + r["rect"][3] for r in rooms]
    meta = {int(c["link"]): c for c in s.get("connections", [])}

    step = 0
    for i, link in enumerate(v["links"]):
        a, b = int(link[0]), int(link[1])
        if abs(floors[a] - floors[b]) < 1:
            continue
        m = meta.get(i, {})
        tier = m.get("tier", "?")
        tiers[tier] = tiers.get(tier, 0) + 1
        span = abs(floors[b] - floors[a])
        if lv == 7:
            step += int(m.get("landings", 0))
        elif tier.startswith("R") and tier in ("R1", "R2"):
            rise = 48.0 if tier == "R1" else 128.0
            step += max(0, math.ceil(span / rise) - 1)
        elif tier == "R3":
            step += 2
        else:
            step += 1

    hall = 0
    if lv != 7:
        for _ in s.get("pogo_halls", []):
            hall += 9  # floor + mid + 6 wall stairs
        if rid == "M01":
            hall += 9  # legacy M01 bridge staircase

    misc = sum(1 for h in s.get("hazards", []) if int(h.get("hall", -1)) < 0)
    if lv != 7 and "R5" in s.get("tiers", []):
        misc += 4
    misc += int(s.get("niches", 0)) * 2

    anchor = 0 if lv == 7 else sum(1 for i in v["interactions"] if i["id"] != "mythic_1")

    total = step + hall + misc + anchor
    tot_step += step; tot_hall += hall; tot_misc += misc; tot_anchor += anchor
    rows.append((rid, lv, len(rooms), len(v["links"]), step, hall, misc, anchor, total))

print("=== 落差级使用分布 ===")
for k in sorted(tiers):
    print(f"  {k:<4} {tiers[k]:>4}")
print()

print("区    版本 房间 连接  阶梯 下劈厅  杂项  锚点   合计")
for r in rows:
    print("%-5s %2d  %3d %4d %5d %5d %5d %5d %6d" % r)

total = tot_step + tot_hall + tot_misc + tot_anchor
print()
print(f"阶梯   {tot_step:>6}  ({tot_step/total*100:.0f}%)  <- 重复交替踏板的来源")
print(f"下劈厅 {tot_hall:>6}  ({tot_hall/total*100:.0f}%)")
print(f"杂项   {tot_misc:>6}  ({tot_misc/total*100:.0f}%)")
print(f"锚点   {tot_anchor:>6}  ({tot_anchor/total*100:.0f}%)  <- 每个锚点垫一块")
print(f"合计   {total:>6}   平均 {total/len(rows):.1f}/区")

mig = [r for r in rows if r[1] == 7]
old = [r for r in rows if r[1] != 7]
print()
print(f"已迁移(lv7): {len(mig)} 区, 平台 {sum(r[-1] for r in mig)}")
print(f"未迁移    : {len(old)} 区, 平台 {sum(r[-1] for r in old)}, 平均 {sum(r[-1] for r in old)/len(old):.1f}/区")
if mig:
    print(f"迁移前后均量对比: {sum(r[-1] for r in old)/len(old):.1f} -> {sum(r[-1] for r in mig)/len(mig):.1f}")
