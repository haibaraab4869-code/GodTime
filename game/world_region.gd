extends Node2D
@export var map_id := "W01"

func _ready() -> void:
	var data = preload("res://game/world_data.gd")
	for item in data.interactions(map_id):
		var marker := Marker2D.new()
		marker.name = item.id
		marker.position = item.at
		add_child(marker)
