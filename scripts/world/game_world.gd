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
@onready var unit_spawn_manager: Node = $UnitSpawnManager
@onready var resource_manager: ResourceManager = $ResourceManager
@onready var population_manager: PopulationManager = $PopulationManager
@onready var job_manager: JobManager = $JobManager
@onready var production_manager: ProductionManager = $ProductionManager
@onready var game_state_manager: GameStateManager = $GameStateManager
@onready var day_night_modulate: CanvasModulate = $DayNightModulate
@onready var day_night_manager: DayNightManager = $DayNightManager
@onready var night_wave_manager: NightWaveManager = $NightWaveManager

const BUILDING_SCENE: PackedScene = preload("res://scenes/buildings/building.tscn")
const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/unit_villager.tscn")

var _town_center: Building


func _ready() -> void:
	add_to_group("game_world")
	population_manager.add_to_group("population_manager")
	job_manager.add_to_group("job_manager")
	production_manager.add_to_group("production_manager")


func on_ground_ready(ground: TinyTilesMap) -> void:
	var bounds := ground.get_map_bounds()
	camera.set_map_bounds(bounds)
	navigation_region.setup_from_ground(ground)
	decorations.setup(ground)
	water_animator.setup(ground)

	population_manager.setup(resource_manager)
	job_manager.setup(resource_manager, population_manager, ground)
	production_manager.setup(
		resource_manager,
		population_manager,
		job_manager,
		units,
		ground
	)

	for child in units.get_children():
		child.queue_free()

	_spawn_starting_settlement(ground)
	rebuild_navigation()

	build_manager.setup(ground, buildings, resource_manager, selection_manager, job_manager)
	unit_spawn_manager.setup(ground, units, build_manager)
	build_manager.build_mode_changed.connect(_on_build_mode_changed)
	unit_spawn_manager.spawn_mode_changed.connect(_on_spawn_mode_changed)
	selection_manager.setup(buildings, resource_manager)
	day_night_manager.setup(day_night_modulate, water_animator)
	night_wave_manager.setup(day_night_manager, units, ground)

	if _town_center != null:
		game_state_manager.setup(_town_center)

	population_manager.recalculate_cap_from_buildings()

	var hud := get_node_or_null("/root/Main/HUD")
	if hud != null and hud.has_method("setup"):
		hud.call(
			"setup",
			resource_manager,
			build_manager,
			unit_spawn_manager,
			selection_manager,
			day_night_manager,
			population_manager,
			production_manager
		)


func _spawn_starting_settlement(ground: TinyTilesMap) -> void:
	var center_cell := Vector2i(7, 6)
	_town_center = _spawn_building("town_center", center_cell, ground, Building.BuildingState.ACTIVE, 1.0)

	var villager_cells: Array[Vector2i] = [
		Vector2i(6, 6),
		Vector2i(8, 6),
		Vector2i(7, 5),
	]
	for i in villager_cells.size():
		_spawn_villager(ground, villager_cells[i], i)


func _spawn_building(
	type_id: String,
	cell: Vector2i,
	ground: TinyTilesMap,
	state: Building.BuildingState,
	progress: float
) -> Building:
	var building: Building = BUILDING_SCENE.instantiate()
	building.configure(type_id, state, progress)
	buildings.add_child(building)
	building.global_position = ground.map_to_local(cell)
	if state == Building.BuildingState.ACTIVE:
		if BuildingDatabase.is_gather_building(type_id):
			job_manager.on_building_completed(building)
		var produces: Array = BuildingDatabase.get_definition(type_id).get("produces", [])
		if not produces.is_empty():
			production_manager.register_producer(building)
	return building


func register_player_unit(unit: Unit) -> void:
	if unit.has_meta("player_unit_registered"):
		return
	unit.set_meta("player_unit_registered", true)
	unit.died.connect(_on_player_unit_died.bind(unit))


func _spawn_villager(ground: TinyTilesMap, cell: Vector2i, index: int) -> void:
	var villager: Unit = VILLAGER_SCENE.instantiate()
	units.add_child(villager)
	villager.global_position = ground.map_to_local(cell) + Vector2(index * 12.0, 0.0)
	villager.set_ground_layer(ground)
	villager.reset_navigation()
	population_manager.register_unit(villager)
	register_player_unit(villager)
	job_manager.on_villager_spawned(villager)


func _on_player_unit_died(unit: Unit) -> void:
	population_manager.unregister_unit(unit)
	job_manager.release_unit_job(unit)


func _on_build_mode_changed(active: bool, _type_id: String) -> void:
	if active and unit_spawn_manager.has_method("cancel_spawn_mode"):
		unit_spawn_manager.call("cancel_spawn_mode")


func _on_spawn_mode_changed(active: bool, _type_id: String) -> void:
	if active and build_manager.has_method("cancel_build_mode"):
		build_manager.call("cancel_build_mode")


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
