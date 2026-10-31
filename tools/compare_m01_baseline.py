"""Compare the migrated M01 slice against the 47 legacy regions.

The point is to prove that v3.1 rules already work and only need推广, and to
derive the per-connection platform budget the rest of the map should hit.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
d = json.loads((ROOT / "game/data/world_regions.json").read_text(encoding="utf-8"))["regions"]

m1 = d["M01"]
floors = [r["rect"][1] + r["rect"][3] for r in m1["rooms"]]
print("=== M01（已迁移 v3.1）===")
print("房间底边:", floors)
print("连接:")
for i, link in enumerate(m1["links"]):
    a, b = int(link[0]), int(link[1])
    span = abs(floors[a] - floors[b])
    m = next((c for c in m1["structure"]["connections"] if int(c["link"]) == i), {})
    print(f"  link{i}  {floors[a]}->{floors[b]}  落差{span:>4}px  tier={m.get('tier','?'):<3} landings={m.get('landings','?')}")
print(f"  平台总数 = 5（2 块 D4 落脚 + 3 块锚点吸附）")

# 每个竖向连接的落差分布（其余47区）
print()
print("=== 其余 47 区的真实落差分布 ===")
spans = {}
for rid, v in d.items():
    if rid == "M01":
        continue
    f = [r["rect"][1] + r["rect"][3] for r in v["rooms"]]
    for link in v["links"]:
        a, b = int(link[0]), int(link[1])
        s = abs(f[a] - f[b])
        if s:
            spans[s] = spans.get(s, 0) + 1

for s in sorted(spans):
    print(f"  落差 {s:>4}px : {spans[s]:>3} 条")

print()
total_v = sum(spans.values())
print(f"竖向连接总数 {total_v}，其中落差 512px 的 {spans.get(512,0)} 条 ({spans.get(512,0)/total_v*100:.0f}%)")

# 如果按 M01 的规则（512->D4 一块落脚，64->D1 零块）重算，47区需要多少平台
print()
print("=== 若按 M01 规则推广，47 区平台需求 ===")
need = 0
by_region = {}
for rid, v in d.items():
    if rid == "M01":
        continue
    f = [r["rect"][1] + r["rect"][3] for r in v["rooms"]]
    n = 0
    for link in v["links"]:
        a, b = int(link[0]), int(link[1])
        s = abs(f[a] - f[b])
        if s == 0:
            continue
        if s <= 96:
            n += 0        # D1
        elif s <= 225:
            n += 1        # D2
        elif s <= 450:
            n += 0        # D3
        elif s <= 704:
            n += 1        # D4
        else:
            n += 2        # D5
    by_region[rid] = n
    need += n

print(f"仅按落差的「理论最少落脚」= {need} 块（平均 {need/47:.1f}/区）")
print()
print("注意：这是下界。还要加：")
print("  - 锚点确实无地形可吸附时的补块")
print("  - 下劈厅的地板")
print("  - 龛的落脚")
print()
print("逐区理论下界（前12）:")
for rid in sorted(by_region, key=lambda s: int(s[1:]))[:12]:
    print(f"  {rid}: {by_region[rid]}")
