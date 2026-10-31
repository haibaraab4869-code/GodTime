extends RefCounted
## Test helper simulates outward movement at a real portal. Does not unlock gates.
static func cross(world: Node, target: String) -> void:
	const Maps = preload("res://game/world_data.gd")
	for item in Maps.interactions(world.current_map):
		if item.id != "travel_" + target: continue
		world.player.position = item.at
		world.player.velocity.x = float(item.side) * 120
		world.boundary_cooldown = 0
		world.boundary_armed = true
		var action := "move_right" if item.side > 0 else "move_left"
		Input.action_press(action)
		world._check_boundary()
		Input.action_release(action)
		return
