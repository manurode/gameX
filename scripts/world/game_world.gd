extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D
@onready var ground_layer: TinyTilesMap = $Terrain/Ground
@onready var decorations: Node2D = $DecorationsHigh
@onready var water_animator: Node2D = $Terrain/WaterAnimator
@onready var units: Node2D = $Units


func on_ground_ready(ground: TinyTilesMap) -> void:
	var bounds := ground.get_map_bounds()
	camera.set_map_bounds(bounds)
	navigation_region.setup_from_ground(ground)
	decorations.setup(ground)
	water_animator.setup(ground)

	for unit in units.get_children():
		if unit is Unit:
			(unit as Unit).set_ground_layer(ground)

	var spawn_points: Array[Vector2] = [
		ground.map_to_local(Vector2i(3, 4)),
		ground.map_to_local(Vector2i(4, 6)),
		ground.map_to_local(Vector2i(8, 5)),
	]
	var idx := 0
	for unit in units.get_children():
		if unit is Unit and idx < spawn_points.size():
			(unit as Unit).global_position = spawn_points[idx] + Vector2(idx * 14.0, 0.0)
			idx += 1
