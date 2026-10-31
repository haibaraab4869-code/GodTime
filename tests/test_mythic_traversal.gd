extends SceneTree

## 退役（2026-10-31）：29 区地图里 mythic 秘境已彻底移除——world_regions.json 每个 region 的
## mythic 一律为 {}，mythic.family / 机关水位 / 根系 / 升降平台等旧 48 区系统不再存在，
## 本测试访问 spec.family 会 SCRIPT ERROR。对应校验已无对象，按主理人「最小正确」裁决退役。

func _init() -> void:
	print("SKIP: mythic 秘境在 29 区已移除（mythic={}），旧秘境遍历测试退役")
	quit(0)
