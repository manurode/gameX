extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D
@onready var ground_layer: TinyTilesMap = $Terrain/Ground
@onready var y_sort_world: Node2D = $YSortWorld
@onready var unit_silhouettes: Node2D = $UnitSilhouettes
@onready var decorations: Node = $WorldDecorations
@onready var water_animator: Node2D = $Terrain/WaterAnimator
@onready var units: Node2D = $YSortWorld
@onready var buildings: Node2D = $YSortWorld
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
@onready var curfew_manager: CurfewManager = $CurfewManager
@onready var run_boon_manager: RunBoonManager = $RunBoonManager
@onready var market_manager: MarketManager = $MarketManager

const BUILDING_SCENE: PackedScene = preload("res://scenes/buildings/building.tscn")
const VILLAGER_SCENE: PackedScene = preload("res://scenes/units/unit_villager.tscn")
const ARCHER_SCENE: PackedScene = preload("res://scenes/units/unit_archer.tscn")
const KNIGHT_SCENE: PackedScene = preload("res://scenes/units/unit_knight.tscn")
const MAGE_SCENE: PackedScene = preload("res://scenes/units/unit_mage.tscn")

var _town_center: Building


func _ready() -> void:
	add_to_group("game_world")
	unit_silhouettes.add_to_group("unit_silhouette_layer")
	population_manager.add_to_group("population_manager")
	job_manager.add_to_group("job_manager")
	production_manager.add_to_group("production_manager")
	resource_manager.add_to_group("resource_manager")


func on_ground_ready(ground: TinyTilesMap) -> void:
	var bounds := ground.get_map_bounds()
	camera.set_map_bounds(bounds)
	navigation_region.setup_from_ground(ground)
	decorations.setup(ground, y_sort_world)
	water_animator.setup(ground)

	_apply_meta_start_resources()
	population_manager.setup(resource_manager)
	job_manager.setup(resource_manager, population_manager, ground)
	curfew_manager.setup(job_manager)
	production_manager.setup(
		resource_manager,
		population_manager,
		job_manager,
		units,
		ground
	)

	for node in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(node):
			node.queue_free()

	_spawn_starting_settlement(ground)
	_apply_meta_start_buildings()
	population_manager.recalculate_cap_from_buildings()
	_apply_meta_start_army()
	rebuild_navigation()

	build_manager.setup(ground, buildings, resource_manager, selection_manager, job_manager)
	unit_spawn_manager.setup(ground, units, build_manager)
	build_manager.build_mode_changed.connect(_on_build_mode_changed)
	unit_spawn_manager.spawn_mode_changed.connect(_on_spawn_mode_changed)
	selection_manager.setup(buildings, resource_manager)
	day_night_manager.setup(day_night_modulate, water_animator)
	night_wave_manager.setup(day_night_manager, units, ground)
	run_boon_manager.setup(day_night_manager, self, curfew_manager, resource_manager)
	market_manager.setup(resource_manager, day_night_manager)

	if _town_center != null:
		game_state_manager.setup(_town_center, day_night_manager)

	population_manager.recalculate_cap_from_buildings()

	var hud := get_node_or_null("/root/Main/Layout/WorldView/SubViewport/HUD")
	if hud != null and hud.has_method("setup"):
		hud.call(
			"setup",
			resource_manager,
			build_manager,
			unit_spawn_manager,
			selection_manager,
			day_night_manager,
			population_manager,
			production_manager,
			curfew_manager,
			camera,
			ground,
			run_boon_manager,
			game_state_manager,
			night_wave_manager,
			market_manager
		)


func _apply_meta_start_resources() -> void:
	resource_manager.wood = BalanceConfig.INITIAL_WOOD + MetaProgression.get_start_wood_bonus()
	resource_manager.gold = BalanceConfig.INITIAL_GOLD + MetaProgression.get_start_gold_bonus()
	resource_manager.food = BalanceConfig.INITIAL_FOOD + MetaProgression.get_start_food_bonus()
	resource_manager.refresh()


func _apply_meta_start_buildings() -> void:
	var towers := MetaProgression.get_starter_tower_count()
	for _i in towers:
		spawn_free_tower()
	var walls := MetaProgression.get_starter_wall_segments()
	if walls > 0:
		spawn_starter_walls(walls)


func _apply_meta_start_army() -> void:
	_spawn_starter_military(KNIGHT_SCENE, "knight", MetaProgression.get_starter_knight_count(), Vector2i(-2, -2))
	_spawn_starter_military(ARCHER_SCENE, "archer", MetaProgression.get_starter_archer_count(), Vector2i(2, -2))
	_spawn_starter_military(MAGE_SCENE, "mage", MetaProgression.get_starter_mage_count(), Vector2i(0, -3))


func _spawn_starting_settlement(ground: TinyTilesMap) -> void:
	var center_cell := ground.get_town_center_cell()
	_town_center = _spawn_building("town_center", center_cell, ground, Building.BuildingState.ACTIVE, 1.0)

	var villager_offsets: Array[Vector2i] = [
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(-1, 1),
		Vector2i(1, 1),
	]
	var extra := MetaProgression.get_extra_villagers()
	if extra > 0:
		villager_offsets.append(Vector2i(0, 1))
	var villager_cells: Array[Vector2i] = []
	for offset in villager_offsets:
		villager_cells.append(center_cell + offset)
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
	building.place_at(ground.map_to_local(cell))
	if state == Building.BuildingState.ACTIVE:
		if BuildingDatabase.is_gather_building(type_id):
			job_manager.on_building_completed(building)
		var produces: Array = BuildingDatabase.get_definition(type_id).get("produces", [])
		if not produces.is_empty():
			production_manager.register_producer(building)
		if type_id == "wall":
			building.notify_world_placed()
	return building


func spawn_free_tower() -> void:
	if ground_layer == null or _town_center == null:
		return
	var center := ground_layer.get_town_center_cell()
	var cell = _find_free_spawn_cell(center, "tower", 4, 16)
	if cell == null:
		push_warning("spawn_free_tower: no free cell around town center")
		return
	_spawn_building("tower", cell as Vector2i, ground_layer, Building.BuildingState.ACTIVE, 1.0)
	rebuild_navigation()


func _find_free_spawn_cell(
	center: Vector2i,
	type_id: String,
	min_radius: int,
	max_radius: int
) -> Variant:
	for radius in range(min_radius, max_radius + 1):
		for cell in _cells_in_ring(center, radius):
			if _can_spawn_building_at(cell, type_id):
				return cell
	return null


func _cells_in_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if radius <= 0:
		cells.append(center)
		return cells
	# Prefer cardinal sides first, then fill the square ring clockwise.
	var ordered: Array[Vector2i] = [
		Vector2i(radius, 0),
		Vector2i(-radius, 0),
		Vector2i(0, radius),
		Vector2i(0, -radius),
	]
	for offset in ordered:
		cells.append(center + offset)
	for x in range(-radius, radius + 1):
		for y in [-radius, radius]:
			var cell := center + Vector2i(x, y)
			if cell not in cells:
				cells.append(cell)
	for y in range(-radius + 1, radius):
		for x in [-radius, radius]:
			var cell := center + Vector2i(x, y)
			if cell not in cells:
				cells.append(cell)
	return cells


func _can_spawn_building_at(cell: Vector2i, type_id: String) -> bool:
	if ground_layer == null or not ground_layer.is_walkable_cell(cell):
		return false
	var world_pos := ground_layer.map_to_local(cell)
	if ground_layer.is_water_at(world_pos):
		return false

	var def := BuildingDatabase.get_definition(type_id)
	var footprint: Vector2 = def.get("footprint", Vector2(70.0, 45.0))
	var pick: Vector2 = def.get("pick_half_size", Vector2(55.0, 50.0))
	# Approximate the future selection rect so sprites do not stack visually.
	var sprite_center := world_pos + Vector2(0.0, -pick.y * 0.45)
	var visual_half := pick + Vector2(10.0, 10.0)
	var visual_rect := Rect2(sprite_center - visual_half, visual_half * 2.0)
	var footprint_half := footprint * 0.55
	var footprint_rect := Rect2(world_pos - footprint_half, footprint_half * 2.0)

	for node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var other := node as Building
		if other.building_state == Building.BuildingState.DESTROYED:
			continue
		if visual_rect.intersects(other.get_selection_rect(), true):
			return false

	for node in get_tree().get_nodes_in_group("terrain_obstacles"):
		if node is TerrainObstacle and _spawn_overlaps_obstacle(world_pos, footprint_rect, node as TerrainObstacle):
			return false
	return true


func _spawn_overlaps_obstacle(world_pos: Vector2, test_rect: Rect2, obstacle: TerrainObstacle) -> bool:
	if obstacle == null or not obstacle.blocks_movement:
		return false
	var outlines := obstacle.get_nav_block_outlines()
	if outlines.is_empty():
		return test_rect.has_point(obstacle.global_position)
	var corners := [
		test_rect.position,
		test_rect.position + Vector2(test_rect.size.x, 0.0),
		test_rect.position + test_rect.size,
		test_rect.position + Vector2(0.0, test_rect.size.y),
	]
	for outline in outlines:
		if outline.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(world_pos, outline):
			return true
		for point in outline:
			if test_rect.has_point(point):
				return true
		for corner in corners:
			if Geometry2D.is_point_in_polygon(corner, outline):
				return true
	return false


func spawn_starter_walls(count: int) -> void:
	if ground_layer == null or _town_center == null:
		return
	var center := ground_layer.get_town_center_cell()
	var offsets: Array[Vector2i] = [
		Vector2i(2, -1),
		Vector2i(2, 0),
		Vector2i(2, 1),
		Vector2i(-2, -1),
		Vector2i(-2, 0),
		Vector2i(-2, 1),
		Vector2i(-1, 2),
		Vector2i(0, 2),
		Vector2i(1, 2),
		Vector2i(-1, -2),
		Vector2i(0, -2),
		Vector2i(1, -2),
	]
	var placed := 0
	for offset in offsets:
		if placed >= count:
			break
		var building := _spawn_building(
			"wall",
			center + offset,
			ground_layer,
			Building.BuildingState.ACTIVE,
			1.0
		)
		building.set_wall_vertical(offset.x != 0 and abs(offset.x) >= abs(offset.y))
		placed += 1
	rebuild_navigation()


func spawn_bonus_villagers(count: int) -> void:
	if ground_layer == null or _town_center == null:
		return
	var center := ground_layer.get_town_center_cell()
	for i in count:
		if not population_manager.can_add_population():
			break
		_spawn_villager(ground_layer, center + Vector2i(i + 1, 1), i)


func spawn_temp_archers(count: int) -> void:
	_spawn_temp_boon_units(ARCHER_SCENE, "archer", count, Vector2i(-1, -2))


func spawn_temp_knights(count: int) -> void:
	_spawn_temp_boon_units(KNIGHT_SCENE, "knight", count, Vector2i(-1, -3))


func _spawn_starter_military(
	scene: PackedScene,
	type_id: String,
	count: int,
	base_offset: Vector2i
) -> void:
	if count <= 0 or ground_layer == null or _town_center == null or scene == null:
		return
	var center := ground_layer.get_town_center_cell()
	var cols := maxi(4, int(ceil(sqrt(float(count)))))
	for i in count:
		if not population_manager.can_add_population():
			break
		var col := i % cols
		var row := int(i / cols)
		var unit: Unit = scene.instantiate()
		units.add_child(unit)
		unit.global_position = ground_layer.map_to_local(
			center + base_offset + Vector2i(col, row)
		)
		UnitDatabase.apply_definition_to_unit(unit, type_id)
		unit.set_ground_layer(ground_layer)
		unit.reset_navigation()
		population_manager.register_unit(unit)
		register_player_unit(unit)
		if day_night_manager.should_apply_night_visuals():
			unit.apply_cycle_visuals(true, true)


func _spawn_temp_boon_units(
	scene: PackedScene,
	type_id: String,
	count: int,
	base_offset: Vector2i
) -> void:
	if ground_layer == null or _town_center == null or scene == null:
		return
	var center := ground_layer.get_town_center_cell()
	for i in count:
		var unit: Unit = scene.instantiate()
		units.add_child(unit)
		unit.global_position = ground_layer.map_to_local(center + base_offset + Vector2i(i, 0))
		UnitDatabase.apply_definition_to_unit(unit, type_id)
		unit.set_ground_layer(ground_layer)
		unit.reset_navigation()
		unit.set_meta("temp_boon_unit", true)
		register_player_unit(unit)
		if day_night_manager.should_apply_night_visuals():
			unit.apply_cycle_visuals(true, true)


func clear_temp_archers() -> void:
	clear_temp_boon_units()


func clear_temp_boon_units() -> void:
	var to_remove: Array[Unit] = []
	for child in units.get_children():
		if child is Unit and child.has_meta("temp_boon_unit"):
			to_remove.append(child as Unit)
	for unit in to_remove:
		if is_instance_valid(unit):
			unit.queue_free()


func repair_all_player_buildings() -> void:
	for node in get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var building := node as Building
		if not is_instance_valid(building):
			continue
		if building.team_id != Team.PLAYER:
			continue
		if building.building_state != Building.BuildingState.ACTIVE:
			continue
		if building.hp >= building.max_hp:
			continue
		# Same path as villager repair: restore HP and refresh damaged → complete sprite.
		building._complete_repair()


func register_player_unit(unit: Unit) -> void:
	if unit.has_meta("player_unit_registered"):
		return
	unit.set_meta("player_unit_registered", true)
	unit.died.connect(_on_player_unit_died.bind(unit))


func spawn_squad_members(
	leader: Unit,
	unit_type_id: String,
	extra_count: int,
	squad_id: String,
	spawn_positions: Array = []
) -> void:
	var scene := UnitDatabase.get_scene(unit_type_id)
	if scene == null:
		population_manager.release_reserved_population(extra_count)
		return
	var spacing := Unit.PERSONAL_SPACE_RADIUS * 2.0
	for i in extra_count:
		var member: Unit = scene.instantiate()
		units.add_child(member)
		if i < spawn_positions.size() and spawn_positions[i] is Vector2:
			member.global_position = spawn_positions[i]
		else:
			var angle := TAU * float(i) / float(maxi(1, extra_count))
			member.global_position = leader.global_position + Vector2(cos(angle), sin(angle)) * spacing
		UnitDatabase.apply_definition_to_unit(member, unit_type_id)
		member.set_ground_layer(ground_layer)
		member.reset_navigation()
		if not squad_id.is_empty():
			member.set_meta("squad_id", squad_id)
		population_manager.register_unit(member)
		register_player_unit(member)
		if day_night_manager.should_apply_night_visuals():
			member.apply_cycle_visuals(true, true)
	population_manager.release_reserved_population(extra_count)


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
	if not unit.has_meta("temp_boon_unit"):
		population_manager.unregister_unit(unit)
	job_manager.on_villager_died(unit)


func _on_build_mode_changed(active: bool, _type_id: String) -> void:
	if active and unit_spawn_manager.has_method("cancel_spawn_mode"):
		unit_spawn_manager.call("cancel_spawn_mode")


func _on_spawn_mode_changed(active: bool, _type_id: String) -> void:
	if active and build_manager.has_method("cancel_build_mode"):
		build_manager.call("cancel_build_mode")


func rebuild_navigation(changed_node: Node2D = null) -> void:
	var obstacle_list: Array = []
	if decorations.has_method("get_obstacles"):
		obstacle_list = decorations.call("get_obstacles")

	var building_list: Array = []
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Building and is_instance_valid(node):
			building_list.append(node)

	if changed_node == null:
		navigation_region.rebuild_navigation(obstacle_list, building_list)
		return
	navigation_region.update_sources(obstacle_list, building_list)
	navigation_region.request_rebuild_at(changed_node.global_position)
