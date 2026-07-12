extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D
@onready var ground_layer: TinyTilesMap = $Terrain/Ground
@onready var decorations: Node2D = $DecorationsHigh
@onready var water_animator: Node2D = $Terrain/WaterAnimator
@onready var units: Node2D = $Units
@onready var buildings: Node2D = $Buildings
@onready var selection_manager: Node = $SelectionManager
@onready var build_manager: Node = $BuildManager
@onready var resource_manager: ResourceManager = $ResourceManager

const BUILDING_SCENE: PackedScene = preload("res://scenes/buildings/building.tscn")


func _ready() -> void:
	add_to_group("game_world")


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
			var spawned_unit := unit as Unit
			spawned_unit.global_position = spawn_points[idx] + Vector2(idx * 14.0, 0.0)
			spawned_unit.reset_navigation()
			idx += 1

	_spawn_initial_buildings(ground)
	rebuild_navigation()
	build_manager.setup(ground, buildings, resource_manager, selection_manager)
	selection_manager.setup(buildings, resource_manager)

	var hud := get_node_or_null("/root/Main/HUD")
	if hud != null and hud.has_method("setup"):
		hud.call("setup", resource_manager, build_manager)


func rebuild_navigation() -> void:
	var obstacle_list: Array = []
	if decorations.has_method("get_obstacles"):
		obstacle_list = decorations.call("get_obstacles")

	var building_list: Array = []
	for child in buildings.get_children():
		if child is Building:
			building_list.append(child)

	navigation_region.rebuild_navigation(obstacle_list, building_list)
	_refresh_unit_navigation()


func _refresh_unit_navigation() -> void:
	for unit in units.get_children():
		if unit is Unit:
			var spawned_unit := unit as Unit
			spawned_unit.navigation_agent.target_position = spawned_unit.global_position


func _spawn_initial_buildings(ground: TinyTilesMap) -> void:
	var placements: Array[Dictionary] = [
		{"type": "house_small", "cell": Vector2i(9, 2)},
		{"type": "mill", "cell": Vector2i(11, 9)},
	]
	for placement in placements:
		var building: Building = BUILDING_SCENE.instantiate()
		building.configure(placement.type, Building.BuildingState.ACTIVE, 1.0)
		buildings.add_child(building)
		building.global_position = ground.map_to_local(placement.cell)
