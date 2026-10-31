import json, math, collections

d = json.load(open('game/data/world_regions.json', encoding='utf-8'))
R = d['regions']
print('区域数', len(R))

# 统计每个区的平台生成参数，复现 world_data.gd 的规则
tiers = collections.Counter()
total_step = 0
rows = []

for k in sorted(R, key=lambda s: int(s[1:])):
    v = R[k]
    s = v.get('structure', {})
    rooms = v['rooms']
    conns = {int(c['link']): c for c in s.get('connections', [])}
    step = 0
    detail = []
    for idx, link in enumerate(v['links']):
        a = rooms[link[0]]['rect']
        b = rooms[link[1]]['rect']
        ay = a[1] + a[3]
        by = b[1] + b[3]
        if abs(ay - by) < 1:
            continue
        tier = conns.get(idx, {}).get('tier', '?')
        tiers[tier] += 1
        span = abs(by - ay)
        if tier in ('R1', 'R2', 'D1', 'D2'):
            rise = 48 if tier in ('R1', 'D1') else 128
            n = max(0, math.ceil(span / rise) - 1)
            step += n
            detail.append((idx, tier, span, n))
        elif tier in ('R3', 'D3'):
            step += 2
            detail.append((idx, tier, span, 2))
        else:
            step += 1
            detail.append((idx, tier, span, 1))
    total_step += step
    rows.append((k, s.get('skeleton'), s.get('tiers'), len(rooms), len(v['links']), step))

print()
print('落差级分布:', dict(tiers))
print()
print('区   骨架                             落差级              房间 连接 阶梯平台')
for r in rows[:10]:
    print('%-4s %-32s %-18s %3d %3d %5d' % (r[0], str(r[1])[:32], str(r[2])[:18], r[3], r[4], r[5]))
print()
print('总阶梯平台数:', total_step)
