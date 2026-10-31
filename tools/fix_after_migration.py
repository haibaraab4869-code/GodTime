#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""暗区升格后的数据收口：地面高、内容标注、房间内连接朝向、敌人数量分摊、旗标归属。

迁移脚本只搬数据，口径要靠这一步定；两个脚本都进版本库，重跑顺序：
    upgrade_dark_zones.py → fix_after_migration.py → build_world_coords.py
"""
from __future__ import annotations

import io
import json
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "docs" / "design" / "maps" / "data"


def load(rid):
    return json.loads((DATA / f"{rid.lower()}.json").read_text(encoding="utf-8"))


def save(rid, d):
    with io.open(DATA / f"{rid.lower()}.json", "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)


# 新区：地面高按房底重置、内容标注、区内连接朝向、旗标
NEW = {
    "W26": dict(
        content={"R01": "暗区·碑庭", "R02": "暗区·名墙"},
        link_side={("R01", "R02"): "V"},
        flags=["w26_grave_open", "w26_stele_read", "w26_narr_01", "w26_bone_01"],
        item_order=["I-01", "I-04"],
    ),
    "W27": dict(
        content={"R01": "暗区·坳口", "R02": "暗区·坳腹", "R03": "暗区·坳顶（PW 回访）"},
        link_side={("R01", "R02"): "V", ("R01", "R03"): "E"},
        flags=["w27_grove_enter", "w27_narr_01", "w27_soul_01", "w27_bone_01"],
        item_order=["I-01", "I-02", "I-05"],
    ),
    "W28": dict(
        content={"R01": "暗区·碑龛"},
        link_side={},
        flags=["w28_stele_read", "w28_stele_deep"],
        item_order=["I-02"],
    ),
    "W29": dict(
        content={"R01": "秘境门厅", "R02": "秘境本体（纯叙事，无战斗）"},
        link_side={("R01", "R02"): "S"},
        flags=["w29_spring_enter", "w29_narr_01", "w29_narr_02", "w29_narr_03",
               "w29_narr_04", "w29_soul_01"],
        item_order=["I-07", "I-08", "I-09", "I-10", "I-11"],
    ),
}

# 宿主：清掉已经不属于本区的旗标
HOST_FLAGS = {
    "W03": ["w03_checkpoint", "w03_well_cross", "w03_bone_picked", "w03_eraser_down",
            "w03_subclerk_down", "w03_ledger_read", "w03_letter_read", "w03_map_page",
            "w03_lightpath_1", "w03_lightpath_2", "w03_bucket_1"],
    "W10": ["w10_checkpoint", "w10_elite_guard_down", "w10_boss_down", "w10_boss_return_point",
            "w10_codex_mupai_past", "w10_codex_mupai_present", "w10_codex_fengli_first",
            "w10_codex_fengli_second", "w10_dev_wind_phase", "w10_dev_mirror_past",
            "w10_dev_mirror_present", "w10_pass_tally"],
    "W15": ["w15_checkpoint", "w15_tide_gauge_1", "w15_narr_tide", "w15_narr_lens",
            "w15_soul_01", "w15_soul_03", "w15_soul_06"],
    "W25": ["w25_cp_mingce", "w25_bone_r07", "w25_note_roster_past", "w25_note_roster_present",
            "w25_note_plaintiff_past", "w25_note_plaintiff_present", "w25_note_mural_past",
            "w25_note_mural_present", "w25_echo_sequence", "w25_plate_west", "w25_plate_east",
            "w25_secret_door_open", "w25_elite_r07_down", "w25_boss_phase2", "w25_boss_down",
            "w25_verdict_sealed", "w25_ending_choice"],
}

ENEMY_COUNT = {("W10", "E-01"): 3, ("W27", "E-01"): 2}


def main():
    for rid, cfg in NEW.items():
        d = load(rid)
        for r in d["rooms"]:
            r["floor_y"] = r["rect"][1] + r["rect"][3]
            if r["id"] in cfg["content"]:
                r["content"] = cfg["content"][r["id"]]
            r["region"] = d["name"]
        for lk in d["links"]:
            sd = cfg["link_side"].get((lk["a"], lk["b"])) or cfg["link_side"].get((lk["b"], lk["a"]))
            if sd:
                lk["side"] = sd
        # 道具按搬迁前的顺序重编号
        by_id = {i["id"]: i for i in d["items"]}
        ordered = [by_id[o] for o in cfg["item_order"] if o in by_id]
        ordered += [i for i in d["items"] if i not in ordered]
        d["items"] = [dict(i, id="I-%02d" % (n + 1)) for n, i in enumerate(ordered)]
        d["flags"] = list(cfg["flags"])
        save(rid, d)

    for rid, flags in HOST_FLAGS.items():
        d = load(rid)
        d["flags"] = list(flags)
        save(rid, d)

    for (rid, eid), cnt in ENEMY_COUNT.items():
        d = load(rid)
        for e in d["enemies"]:
            if e["id"] == eid:
                e["count"] = cnt
        save(rid, d)


if __name__ == "__main__":
    main()
