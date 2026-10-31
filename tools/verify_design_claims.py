"""Verify the design member's factual corrections (read-only).

Checks C2 (room size distribution), C3 (vertical link drop histogram),
C4 (M02 overlapping rooms). Run: python tools/verify_design_claims.py
"""

from __future__ import annotations

import collections
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "game" / "data" / "world_regions.json"


def main() -> int:
    regions = json.loads(DATA.read_text(encoding="utf-8"))["regions"]

    # C2: room size distribution across all 488 rooms
    sizes = collections.Counter()
    total = 0
    for reg in regions.values():
        for room in reg["rooms"]:
            sizes[(room["rect"][2], room["rect"][3])] += 1
            total += 1
    print(f"[C2] rooms={total}")
    print("     top sizes:", sizes.most_common(5))
    has448 = sizes.get((448, 448), 0)
    tallest = max(h for _, h in sizes)
    widest = max(w for w, _ in sizes)
    print(f"     448x448 exists? {has448}   max height={tallest}  max width={widest}")
    # does every room fit the 800x450 viewport at zoom 1.6?
    over = [(w, h) for (w, h), n in sizes.items() if w > 800 or h > 450]
    print(f"     rooms exceeding 800x450 viewport: {over if over else 'none'}")

    # C3: vertical link drop histogram
    hist = collections.Counter()
    vtotal = 0
    for reg in regions.values():
        rooms = reg["rooms"]
        for link in reg["links"]:
            a, b = rooms[link[0]]["rect"], rooms[link[1]]["rect"]
            dy = (b[1] + b[3]) - (a[1] + a[3])
            if dy:
                hist[abs(dy)] += 1
                vtotal += 1
    print(f"[C3] vertical links={vtotal}  hist={dict(sorted(hist.items(), key=lambda kv: -kv[1]))}")
    print(f"     512-count={hist.get(512, 0)}")

    # C4: M02 overlapping rooms occupying the same x-span
    m02 = regions["M02"]["rooms"]
    print("[C4] M02 overlaps:")
    for i in range(len(m02)):
        for j in range(i + 1, len(m02)):
            ra, rb = m02[i]["rect"], m02[j]["rect"]
            x0 = max(ra[0], rb[0])
            x1 = min(ra[0] + ra[2], rb[0] + rb[2])
            y0 = max(ra[1], rb[1])
            y1 = min(ra[1] + ra[3], rb[1] + rb[3])
            if x1 > x0 and y1 > y0:
                print(f"     R{i+1} vs R{j+1}: overlap {x1-x0}x{y1-y0}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
