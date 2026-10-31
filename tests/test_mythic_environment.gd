extends SceneTree

## 退役（2026-10-31）：29 区地图里 mythic 秘境已彻底移除——world_regions.json 每个 region 的
## mythic 一律为 {}，world.environment / 三灵机关 / 环境物理这套旧 48 区系统不再有对应数据，
## 本测试访问 spec.controls 会 SCRIPT ERROR。对应校验已无对象，按主理人「最小正确」裁决退役。

func _init() -> void:
	print("SKIP: mythic 秘境在 29 区已移除（mythic={}），旧机关/环境测试退役")
	quit(0)
