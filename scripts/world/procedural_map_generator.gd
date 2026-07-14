class_name ProceduralMapGenerator
extends RefCounted

const DEFAULT_MAP_SIZE := Vector2i(64, 64)
const TOWN_CLEAR_RADIUS := 7.5
const CONTENT_CLEAR_RADIUS := 9.0
const WATER_THRESHOLD := 0.38

const GRASS_A := 0
const GRASS_B := 1
const GRASS_C := 2
const GRASS_D := 3
const WATER := 4

var map_size := DEFAULT_MAP_SIZE


func generate(requested_seed: int = 0) -> Dictionary:
	var world_seed := requested_seed
	if world_seed == 0:
		world_seed = int(Time.get_unix_time_from_system()) ^ Time.get_ticks_usec()

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = world_seed
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.055
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 4

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = world_seed ^ 0x5F3759DF
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.16

	var town_center_cell := Vector2i(map_size.x / 2, map_size.y / 2)
	var ground_tiles: Array[int] = []
	var water_cells: Array[Vector2i] = []
	var water_set: Dictionary = {}

	ground_tiles.resize(map_size.x * map_size.y)
	for y in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, y)
			var distance_to_town := Vector2(cell - town_center_cell).length()
			var water_value := terrain_noise.get_noise_2d(float(x), float(y))
			var is_water := distance_to_town > TOWN_CLEAR_RADIUS and water_value > WATER_THRESHOLD
			var tile := WATER if is_water else _pick_grass_tile(detail_noise, cell)
			ground_tiles[_cell_index(cell)] = tile
			if is_water:
				water_cells.append(cell)
				water_set[cell] = true

	_carve_routes_to_edges(town_center_cell, ground_tiles, water_cells, water_set)
	var reachable_set := _get_reachable_ground(town_center_cell, water_set)
	_fill_unreachable_ground(ground_tiles, water_cells, water_set, reachable_set)

	var occupied: Dictionary = {}
	var resource_placements := _generate_resources(
		rng, town_center_cell, water_set, reachable_set, occupied
	)
	var decoration_placements := _generate_decorations(
		rng, town_center_cell, water_set, reachable_set, occupied
	)

	return {
		"seed": world_seed,
		"map_size": map_size,
		"town_center_cell": town_center_cell,
		"ground_tiles": ground_tiles,
		"water_cells": water_cells,
		"water_set": water_set,
		"resource_placements": resource_placements,
		"decoration_placements": decoration_placements,
	}


func _pick_grass_tile(noise: FastNoiseLite, cell: Vector2i) -> int:
	var value := noise.get_noise_2d(float(cell.x), float(cell.y))
	if value < -0.38:
		return GRASS_C
	if value > 0.42:
		return GRASS_B
	if absf(value) < 0.08:
		return GRASS_D
	return GRASS_A


func _generate_resources(
	rng: RandomNumberGenerator,
	town_center: Vector2i,
	water_set: Dictionary,
	reachable_set: Dictionary,
	occupied: Dictionary
) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	_append_random_placements(placements, rng, town_center, water_set, reachable_set, occupied, 52, {
		"kind": "wood",
		"variant_count": 2,
		"amount": BalanceConfig.TREE_CAPACITY,
	})
	_append_random_placements(placements, rng, town_center, water_set, reachable_set, occupied, 18, {
		"kind": "gold",
		"variant_count": 2,
		"amount": BalanceConfig.GOLD_VEIN_CAPACITY,
	})
	_append_random_placements(placements, rng, town_center, water_set, reachable_set, occupied, 14, {
		"kind": "food",
		"variant_count": 2,
		"amount": 220,
		"columns": 3,
		"rows": 2,
	})
	return placements


func _generate_decorations(
	rng: RandomNumberGenerator,
	town_center: Vector2i,
	water_set: Dictionary,
	reachable_set: Dictionary,
	occupied: Dictionary
) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	_append_random_placements(placements, rng, town_center, water_set, reachable_set, occupied, 34, {
		"kind": "hill",
		"variant_count": 2,
		"blocks": true,
	})
	return placements


func _append_random_placements(
	target: Array[Dictionary],
	rng: RandomNumberGenerator,
	town_center: Vector2i,
	water_set: Dictionary,
	reachable_set: Dictionary,
	occupied: Dictionary,
	count: int,
	template: Dictionary
) -> void:
	var placed := 0
	var attempts := 0
	var max_attempts := count * 80
	while placed < count and attempts < max_attempts:
		attempts += 1
		var cell := Vector2i(
			rng.randi_range(2, map_size.x - 3),
			rng.randi_range(2, map_size.y - 3)
		)
		if Vector2(cell - town_center).length() <= CONTENT_CLEAR_RADIUS:
			continue
		if cell in water_set or cell not in reachable_set or cell in occupied:
			continue
		if _has_occupied_neighbor(cell, occupied):
			continue

		var placement := template.duplicate()
		placement["cell"] = cell
		placement["variant"] = rng.randi_range(0, int(template.get("variant_count", 1)) - 1)
		placement.erase("variant_count")
		target.append(placement)
		occupied[cell] = true
		placed += 1


func _has_occupied_neighbor(cell: Vector2i, occupied: Dictionary) -> bool:
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			if Vector2i(x, y) in occupied:
				return true
	return false


func _carve_routes_to_edges(
	town_center: Vector2i,
	ground_tiles: Array[int],
	water_cells: Array[Vector2i],
	water_set: Dictionary
) -> void:
	var targets: Array[Vector2i] = [
		Vector2i(town_center.x, 0),
		Vector2i(town_center.x, map_size.y - 1),
		Vector2i(0, town_center.y),
		Vector2i(map_size.x - 1, town_center.y),
	]
	for target in targets:
		var cell := town_center
		while cell != target:
			_set_cell_as_ground(cell, ground_tiles, water_cells, water_set)
			if cell.x != target.x:
				cell.x += signi(target.x - cell.x)
			elif cell.y != target.y:
				cell.y += signi(target.y - cell.y)
		_set_cell_as_ground(target, ground_tiles, water_cells, water_set)


func _get_reachable_ground(start: Vector2i, water_set: Dictionary) -> Dictionary:
	var reachable: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	var index := 0
	var directions: Array[Vector2i] = [
		Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	]
	while index < frontier.size():
		var cell := frontier[index]
		index += 1
		for direction in directions:
			var neighbor := cell + direction
			if not _is_in_bounds(neighbor) or neighbor in water_set or neighbor in reachable:
				continue
			reachable[neighbor] = true
			frontier.append(neighbor)
	return reachable


func _fill_unreachable_ground(
	ground_tiles: Array[int],
	water_cells: Array[Vector2i],
	water_set: Dictionary,
	reachable_set: Dictionary
) -> void:
	for y in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, y)
			if cell in water_set or cell in reachable_set:
				continue
			ground_tiles[_cell_index(cell)] = WATER
			water_set[cell] = true
			water_cells.append(cell)


func _set_cell_as_ground(
	cell: Vector2i,
	ground_tiles: Array[int],
	water_cells: Array[Vector2i],
	water_set: Dictionary
) -> void:
	ground_tiles[_cell_index(cell)] = GRASS_A
	if cell in water_set:
		water_set.erase(cell)
		water_cells.erase(cell)


func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y


func _cell_index(cell: Vector2i) -> int:
	return cell.y * map_size.x + cell.x
