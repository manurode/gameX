class_name ProceduralMapGenerator
extends RefCounted

const DEFAULT_MAP_SIZE := Vector2i(64, 64)
const BASE_MAP_AREA := 64 * 64
const BASE_TOWN_CLEAR_RADIUS := 7.5
const BASE_CONTENT_CLEAR_RADIUS := 9.0
const BASE_TERRAIN_FREQUENCY := 0.055
const BASE_TREE_COUNT := 14
const BASE_GOLD_COUNT := 18
const BASE_HILL_COUNT := 8
const WATER_THRESHOLD := 0.38

## Relative cells occupied by one forest (~15 tiles, irregular diamond).
const FOREST_FOOTPRINT: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	Vector2i(2, 1), Vector2i(-1, 2),
]

## Relative cells occupied by one mountain chain (~23 tiles, elongated ridge).
const MOUNTAIN_FOOTPRINT: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
	Vector2i(1, 2), Vector2i(-1, 2), Vector2i(1, -2), Vector2i(-1, -2),
	Vector2i(3, 0), Vector2i(-3, 0),
]

## Wang grass: 2 edge types (dense/soft) × 4 edges → 16 tiles.
## Source IDs: 0..15 wang grass, 16 press, 17 water, 18 main.
const GRASS_VARIANT_COUNT := 16
const EDGE_DENSE := 0
const EDGE_SOFT := 1
const GRASS_A := 0 ## all-dense wang tile (N=E=S=W=dense)
const GRASS_PRESS := 16
const WATER := 17

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
	terrain_noise.frequency = BASE_TERRAIN_FREQUENCY * (64.0 / float(map_size.x))
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 4

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
			var is_water := distance_to_town > _get_town_clear_radius() and water_value > WATER_THRESHOLD
			# Placeholder grass; Wang codes resolved after water topology is final.
			ground_tiles[_cell_index(cell)] = WATER if is_water else GRASS_A
			if is_water:
				water_cells.append(cell)
				water_set[cell] = true

	_carve_routes_to_edges(town_center_cell, ground_tiles, water_cells, water_set)
	var reachable_set := _get_reachable_ground(town_center_cell, water_set)
	_fill_unreachable_ground(ground_tiles, water_cells, water_set, reachable_set)
	_assign_wang_grass(ground_tiles, water_set, world_seed)

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


func _assign_wang_grass(ground_tiles: Array[int], water_set: Dictionary, world_seed: int) -> void:
	## Cell terrain (dense/soft) from low-freq noise → organic meadow patches.
	## Shared edge = SOFT if either touching grass cell is soft (blob expands),
	## else DENSE. That yields Wang codes whose art crosses the diamond grid.
	var field_noise := FastNoiseLite.new()
	field_noise.seed = world_seed ^ 0xA5A5A5A5
	field_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	field_noise.frequency = 0.07 * (64.0 / float(map_size.x))
	field_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	field_noise.fractal_octaves = 3

	var cell_types: Array[int] = []
	cell_types.resize(map_size.x * map_size.y)
	for y in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, y)
			var idx := _cell_index(cell)
			if cell in water_set:
				cell_types[idx] = EDGE_DENSE
				continue
			cell_types[idx] = (
				EDGE_SOFT if field_noise.get_noise_2d(float(x), float(y)) >= 0.0 else EDGE_DENSE
			)

	for y in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, y)
			if cell in water_set:
				continue
			var self_type := cell_types[_cell_index(cell)]
			var n := _shared_edge_type(self_type, Vector2i(x, y - 1), cell_types, water_set)
			var s := _shared_edge_type(self_type, Vector2i(x, y + 1), cell_types, water_set)
			var w := _shared_edge_type(self_type, Vector2i(x - 1, y), cell_types, water_set)
			var e := _shared_edge_type(self_type, Vector2i(x + 1, y), cell_types, water_set)
			ground_tiles[_cell_index(cell)] = _wang_index(n, e, s, w)


func _shared_edge_type(
	self_type: int,
	neighbor: Vector2i,
	cell_types: Array[int],
	water_set: Dictionary
) -> int:
	if not _is_in_bounds(neighbor) or neighbor in water_set:
		return self_type
	var other := cell_types[_cell_index(neighbor)]
	# Soft meadow bleeds one edge into dense neighbors (organic blob, not a hard grid).
	return EDGE_SOFT if (self_type == EDGE_SOFT or other == EDGE_SOFT) else EDGE_DENSE


func _wang_index(n: int, e: int, s: int, w: int) -> int:
	return (n << 3) | (e << 2) | (s << 1) | w


func _generate_resources(
	rng: RandomNumberGenerator,
	town_center: Vector2i,
	water_set: Dictionary,
	reachable_set: Dictionary,
	occupied: Dictionary
) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	_append_random_placements(placements, rng, town_center, water_set, reachable_set, occupied, _scaled_count(BASE_TREE_COUNT), {
		"kind": "wood",
		"variant_count": 3,
		"amount": BalanceConfig.TREE_CAPACITY,
		"footprint": FOREST_FOOTPRINT,
	})
	_append_random_placements(placements, rng, town_center, water_set, reachable_set, occupied, _scaled_count(BASE_GOLD_COUNT), {
		"kind": "gold",
		"variant_count": 2,
		"amount": BalanceConfig.GOLD_VEIN_CAPACITY,
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
	_append_random_placements(placements, rng, town_center, water_set, reachable_set, occupied, _scaled_count(BASE_HILL_COUNT), {
		"kind": "hill",
		"variant_count": 3,
		"blocks": true,
		"footprint": MOUNTAIN_FOOTPRINT,
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
	var footprint: Array = template.get("footprint", [Vector2i.ZERO])
	var max_attempts := count * (120 if footprint.size() > 1 else 80)
	while placed < count and attempts < max_attempts:
		attempts += 1
		var margin := maxi(2, map_size.x / 16)
		var max_x := maxi(margin, map_size.x - margin - 1)
		var max_y := maxi(margin, map_size.y - margin - 1)
		var cell := Vector2i(
			rng.randi_range(margin, max_x),
			rng.randi_range(margin, max_y)
		)
		if Vector2(cell - town_center).length() <= _get_content_clear_radius():
			continue
		if not _can_place_footprint(cell, footprint, water_set, reachable_set, occupied):
			continue

		var placement := template.duplicate()
		placement["cell"] = cell
		placement["variant"] = rng.randi_range(0, int(template.get("variant_count", 1)) - 1)
		placement.erase("variant_count")
		placement.erase("footprint")
		target.append(placement)
		_mark_footprint(cell, footprint, occupied)
		placed += 1


func _can_place_footprint(
	origin: Vector2i,
	footprint: Array,
	water_set: Dictionary,
	reachable_set: Dictionary,
	occupied: Dictionary
) -> bool:
	var footprint_set: Dictionary = {}
	for offset_variant in footprint:
		var offset: Vector2i = offset_variant
		var cell := origin + offset
		footprint_set[cell] = true
		if not _is_in_bounds(cell):
			return false
		if cell in water_set or cell not in reachable_set or cell in occupied:
			return false

	# Keep a 1-cell buffer against other placements (outside this footprint).
	for cell_variant in footprint_set.keys():
		var cell: Vector2i = cell_variant
		for y in range(cell.y - 1, cell.y + 2):
			for x in range(cell.x - 1, cell.x + 2):
				var neighbor := Vector2i(x, y)
				if neighbor in footprint_set:
					continue
				if neighbor in occupied:
					return false
	return true


func _mark_footprint(origin: Vector2i, footprint: Array, occupied: Dictionary) -> void:
	for offset_variant in footprint:
		var offset: Vector2i = offset_variant
		occupied[origin + offset] = true


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


func _get_scale() -> float:
	return float(map_size.x * map_size.y) / float(BASE_MAP_AREA)


func _get_town_clear_radius() -> float:
	return BASE_TOWN_CLEAR_RADIUS * float(map_size.x) / 64.0


func _get_content_clear_radius() -> float:
	return BASE_CONTENT_CLEAR_RADIUS * float(map_size.x) / 64.0


func _scaled_count(base_count: int) -> int:
	return maxi(2, int(round(float(base_count) * _get_scale())))
