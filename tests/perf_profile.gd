extends Node

## Headless frame-time profiler for the night spawn spike and build hitches.
## Run as a scene (autoloads must be live):
##   godot --headless --path . tests/perf_profile.tscn

const WARM_FRAMES := 30
const MEASURE_FRAMES := 130
const TARGET_DAY := 10
const ARMY_SIZE := 30
const MAP_SEED := 20260730

var _main: Node
var _world: Node
var _day_night: DayNightManager
var _waves: NightWaveManager


func _ready() -> void:
	_run.call_deferred()


func _find_ground_layer(node: Node) -> TinyTilesMap:
	if node is TinyTilesMap:
		return node
	for child in node.get_children():
		var found := _find_ground_layer(child)
		if found != null:
			return found
	return null


func _run() -> void:
	# Fixed seed: wave modifiers and enemy mixes are random, and comparing runs is
	# meaningless if the army size moves between them.
	seed(20260730)
	# Match a real mid/late run: Avanzado waves on the big map.
	GameSettings.difficulty = GameSettingsData.Difficulty.ADVANCED
	GameSettings.map_size_preset = GameSettingsData.MapSizePreset.LARGE

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	_main = main_scene.instantiate()
	# The map seed defaults to the clock, which would hand every run a different
	# town layout and wall ring. Pin it before _ready() reads it.
	var ground := _find_ground_layer(_main)
	if ground == null:
		print("PERF_PROFILE_SETUP_FAILED no TinyTilesMap in main.tscn")
		get_tree().quit(1)
		return
	ground.fixed_seed = MAP_SEED
	get_tree().root.add_child(_main)
	# Map generation + settlement spawn spans several frames.
	for _i in 600:
		await get_tree().process_frame
		_world = get_tree().get_first_node_in_group("game_world")
		if _world != null and _world.get("ground_layer") != null:
			break
	_day_night = get_tree().get_first_node_in_group("day_night_manager")
	_waves = get_tree().get_first_node_in_group("night_wave_manager")
	if _world == null or _day_night == null or _waves == null:
		print("PERF_PROFILE_SETUP_FAILED world=%s dn=%s waves=%s" % [_world, _day_night, _waves])
		get_tree().quit(1)
		return

	# Ghost sprites need a renderer; silence their headless _process spam.
	for node_name in ["BuildManager", "UnitSpawnManager"]:
		var node := _world.get_node_or_null(node_name)
		if node != null:
			node.set_process(false)
			node.set_process_unhandled_input(false)

	_day_night.automatic_cycle = false
	_spawn_army(ARMY_SIZE)
	for _i in WARM_FRAMES:
		await get_tree().process_frame

	# Run one early wave first so enemy sheets / shaders are already loaded. A real
	# player pays those cold loads on night 1, not on the night under test.
	_day_night.debug_set_day(2)
	_waves._pick_next_modifier()
	_day_night.set_phase(DayNightManager.CyclePhase.DUSK)
	for _i in 5:
		await get_tree().process_frame
	_day_night.set_phase(DayNightManager.CyclePhase.NIGHT)
	for _i in 60:
		await get_tree().process_frame
	_day_night.set_phase(DayNightManager.CyclePhase.DAWN)
	for _i in 20:
		await get_tree().process_frame

	print("=== BASELINE day, units=%d ===" % get_tree().get_nodes_in_group("units").size())
	await _measure("baseline", 40)

	_day_night.debug_set_day(TARGET_DAY)
	# Wave size is planned at DAWN; jumping days skips that, so re-plan for day 10.
	_waves._pick_next_modifier()
	for _i in 5:
		await get_tree().process_frame
	_day_night.set_phase(DayNightManager.CyclePhase.DUSK)
	for _i in 5:
		await get_tree().process_frame

	# The wave spawns on the DUSK -> NIGHT transition.
	var spawn_start := Time.get_ticks_usec()
	_day_night.set_phase(DayNightManager.CyclePhase.NIGHT)
	var spawn_call_ms := float(Time.get_ticks_usec() - spawn_start) / 1000.0
	print("=== NIGHT %d: set_phase(NIGHT) sync cost %.1f ms, planned=%d ===" % [
		TARGET_DAY,
		spawn_call_ms,
		_planned_wave_count(),
	])

	await _measure("night_spawn", MEASURE_FRAMES)

	print("=== STEADY NIGHT, enemies=%d ===" % get_tree().get_nodes_in_group("enemies").size())
	await _measure("night_steady", 60)

	await _profile_building_placement()
	await _profile_walled_wave()
	await _profile_late_wave()

	print("PERF_PROFILE_DONE")
	get_tree().quit(0)


## Placing / completing a building is the other reported hitch.
func _profile_building_placement() -> void:
	var ground: TinyTilesMap = _world.get("ground_layer")
	var layer: Node2D = _world.get("buildings")
	var center: Vector2i = ground.get_town_center_cell()
	var scene: PackedScene = load("res://scenes/buildings/building.tscn")

	print("=== BUILDING PLACEMENT (10 houses) ===")
	var place_worst := 0.0
	var place_total := 0.0
	var finish_worst := 0.0
	var placed: Array[Building] = []
	for i in 10:
		var world_pos := ground.map_to_local(center + Vector2i(-14 + i * 3, -10))
		var started := Time.get_ticks_usec()
		var building: Building = scene.instantiate()
		building.configure("house_small", Building.BuildingState.CONSTRUCTING, 0.0)
		layer.add_child(building)
		building.place_at(world_pos)
		var job_manager = get_tree().get_first_node_in_group("job_manager")
		if job_manager != null:
			job_manager.alert_nearby_builders(building)
		var place_ms := float(Time.get_ticks_usec() - started) / 1000.0
		place_total += place_ms
		place_worst = maxf(place_worst, place_ms)
		placed.append(building)
		await get_tree().process_frame

	print("place: avg=%.1fms worst=%.1fms" % [place_total / 10.0, place_worst])
	await _measure("after_place", 40)

	for building in placed:
		var started := Time.get_ticks_usec()
		building.add_construction_progress(2.0)
		finish_worst = maxf(finish_worst, float(Time.get_ticks_usec() - started) / 1000.0)
		await get_tree().process_frame
	print("complete_construction worst=%.1fms" % finish_worst)
	await _measure("after_complete", 60)


## Walls turn on the enemy breach logic, which asks for path metrics synchronously.
func _profile_walled_wave() -> void:
	_world.spawn_starter_walls(40)
	for _i in 30:
		await get_tree().process_frame

	_day_night.debug_set_day(15)
	_waves._pick_next_modifier()
	for _i in 10:
		await get_tree().process_frame
	_day_night.set_phase(DayNightManager.CyclePhase.DUSK)
	for _i in 5:
		await get_tree().process_frame

	_day_night.set_phase(DayNightManager.CyclePhase.NIGHT)
	print("=== NIGHT 15 BEHIND WALLS: planned=%d ===" % _planned_wave_count())
	await _measure("walled_spawn", 150)
	print("=== WALLED STEADY, enemies=%d ===" % get_tree().get_nodes_in_group("enemies").size())
	await _measure("walled_steady", 90)


## Night 20 is the wave-count cap: the true worst case.
func _profile_late_wave() -> void:
	_day_night.debug_set_day(20)
	_waves._pick_next_modifier()
	for _i in 10:
		await get_tree().process_frame
	_day_night.set_phase(DayNightManager.CyclePhase.DUSK)
	for _i in 5:
		await get_tree().process_frame

	var started := Time.get_ticks_usec()
	_day_night.set_phase(DayNightManager.CyclePhase.NIGHT)
	var spawn_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("=== NIGHT 20: set_phase(NIGHT) sync cost %.1f ms, planned=%d ===" % [
		spawn_ms,
		_planned_wave_count(),
	])
	await _measure("night20_spawn", 150)
	print("night 20 live enemies after drain: %d" % get_tree().get_nodes_in_group("enemies").size())


## Tolerates a build without the batched spawn queue, so the same harness can
## profile older revisions for comparison.
func _planned_wave_count() -> int:
	var pending := 0
	if _waves.has_method("_pending_spawn_count"):
		pending = _waves._pending_spawn_count()
	return _waves._spawned.size() + pending + _waves._continuous_remaining


func _spawn_army(count: int) -> void:
	var ground: TinyTilesMap = _world.get("ground_layer")
	var units_parent: Node2D = _world.get("units")
	var center: Vector2i = ground.get_town_center_cell()
	for i in count:
		var type_id := "knight" if i % 2 == 0 else "archer"
		var scene: PackedScene = UnitDatabase.get_scene(type_id)
		var unit: Unit = scene.instantiate()
		units_parent.add_child(unit)
		unit.global_position = ground.map_to_local(
			center + Vector2i(-8 + (i % 8), 4 + int(i / 8))
		)
		UnitDatabase.apply_definition_to_unit(unit, type_id)
		unit.set_ground_layer(ground)
		unit.reset_navigation()


func _measure(label: String, frames: int) -> void:
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for _i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now

	var total := 0.0
	var worst := 0.0
	var worst_index := -1
	for i in samples.size():
		total += samples[i]
		if samples[i] > worst:
			worst = samples[i]
			worst_index = i
	var sorted_samples := samples.duplicate()
	sorted_samples.sort()
	var p50: float = sorted_samples[int(sorted_samples.size() * 0.5)]
	var p95: float = sorted_samples[int(sorted_samples.size() * 0.95)]

	print(
		"[%s] frames=%d avg=%.1f p50=%.1f p95=%.1f worst=%.1f (frame %d) total=%.0fms"
		% [label, frames, total / float(frames), p50, p95, worst, worst_index, total]
	)
	var spikes := ""
	for i in samples.size():
		if samples[i] > maxf(16.0, p50 * 3.0):
			spikes += " %d:%.0f" % [i, samples[i]]
	if not spikes.is_empty():
		print("[%s] spikes(frame:ms):%s" % [label, spikes])
