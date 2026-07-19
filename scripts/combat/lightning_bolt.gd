class_name LightningBolt
extends Node2D

## Instant chain-lightning VFX: staff → primary, then fan branches to nearby foes.

const MAIN_GROW_SECONDS := 0.09
const BRANCH_GROW_SECONDS := 0.11
const HOLD_SECONDS := 0.26
const BRANCH_START_DELAY := 0.07

var damage: int = 12
var chain_damage: int = 4
var chain_radius: float = 70.0
var chain_max_targets: int = 2
var shooter: Unit
var target: Unit
var building_target: Building
var emit_origin: Vector2 = Vector2.ZERO

var _segments: Array[Dictionary] = []
var _impact_points: Array[Vector2] = []
var _elapsed: float = 0.0
var _rng := RandomNumberGenerator.new()
var _fired := false
var _flicker_token: int = 0


func _ready() -> void:
	z_index = 40
	_rng.seed = Time.get_ticks_usec()
	# Defer so emit_origin / targets set by the shooter are available.
	call_deferred("_fire")


func _process(delta: float) -> void:
	if not _fired:
		return
	_elapsed += delta
	_flicker_token = int(_elapsed * 28.0)
	queue_redraw()
	if _elapsed >= MAIN_GROW_SECONDS + BRANCH_GROW_SECONDS + HOLD_SECONDS:
		queue_free()


func _fire() -> void:
	if _fired:
		return
	_fired = true

	var origin := emit_origin
	if origin == Vector2.ZERO and shooter != null and is_instance_valid(shooter):
		origin = shooter.get_staff_emit_point()
	emit_origin = origin
	global_position = origin

	var primary_point := origin + Vector2(40.0, 0.0)
	if target != null and _can_hit_unit(target):
		primary_point = target.get_sprite_center()
		target.take_damage(damage, shooter)
		_impact_points.append(primary_point)
		_segments.append({
			"from": origin,
			"to": primary_point,
			"delay": 0.0,
			"grow": MAIN_GROW_SECONDS,
			"main": true,
		})
		_apply_chain_branches(target, primary_point)
	elif building_target != null and _can_hit_building(building_target):
		primary_point = building_target.get_attack_point()
		building_target.take_damage(damage, shooter)
		_impact_points.append(primary_point)
		_segments.append({
			"from": origin,
			"to": primary_point,
			"delay": 0.0,
			"grow": MAIN_GROW_SECONDS,
			"main": true,
		})
	else:
		# Fallback flash if target vanished mid-cast.
		_segments.append({
			"from": origin,
			"to": origin + Vector2(28.0, -18.0),
			"delay": 0.0,
			"grow": MAIN_GROW_SECONDS,
			"main": true,
		})
		_impact_points.append(origin + Vector2(28.0, -18.0))

	queue_redraw()


func _apply_chain_branches(primary: Unit, primary_point: Vector2) -> void:
	if chain_damage <= 0 or chain_radius <= 0.0 or chain_max_targets <= 0:
		return
	if shooter == null or not is_instance_valid(shooter):
		return

	var tree := get_tree()
	if tree == null:
		return

	var candidates: Array[Dictionary] = []
	for item in UnitSpatialIndex.query_nearby(tree, primary.global_position, chain_radius):
		if not item is Unit:
			continue
		var enemy := item as Unit
		if enemy == primary or not _can_hit_unit(enemy):
			continue
		candidates.append({
			"unit": enemy,
			"dist": primary.global_position.distance_squared_to(enemy.global_position),
		})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.dist) < float(b.dist)
	)

	var chained := 0
	for entry in candidates:
		if chained >= chain_max_targets:
			break
		var enemy: Unit = entry.unit
		var hit_point := enemy.get_sprite_center()
		enemy.take_damage(chain_damage, shooter)
		_impact_points.append(hit_point)
		_segments.append({
			"from": primary_point,
			"to": hit_point,
			"delay": BRANCH_START_DELAY + float(chained) * 0.03,
			"grow": BRANCH_GROW_SECONDS,
			"main": false,
		})
		chained += 1


func _can_hit_unit(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit) or unit == shooter or unit.hp <= 0 or unit._is_dying:
		return false
	if unit.garrisoned_building != null:
		return false
	if shooter != null and is_instance_valid(shooter) and not Team.are_hostile(shooter.team_id, unit.team_id):
		return false
	return true


func _can_hit_building(building: Building) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	if building.hp <= 0 or building.building_state == Building.BuildingState.DESTROYED:
		return false
	if shooter == null or not is_instance_valid(shooter):
		return false
	if not Team.are_hostile(shooter.team_id, building.team_id):
		return false
	if shooter.garrisoned_building == building:
		return false
	return true


func _draw() -> void:
	if _segments.is_empty():
		return

	# Staff tip charge flash.
	var tip_local := to_local(emit_origin)
	var tip_pulse := 0.55 + 0.45 * absf(sin(_elapsed * 40.0))
	draw_circle(tip_local, 5.5 * tip_pulse, Color(0.55, 0.9, 1.0, 0.35 * tip_pulse))
	draw_circle(tip_local, 2.8, Color(0.95, 1.0, 1.0, 0.9 * tip_pulse))

	for i in range(_segments.size()):
		var seg: Dictionary = _segments[i]
		var progress := _segment_progress(seg)
		if progress <= 0.0:
			continue
		var from_g: Vector2 = seg.from
		var to_g: Vector2 = seg.to
		var end_g := from_g.lerp(to_g, progress)
		var from_l := to_local(from_g)
		var to_l := to_local(end_g)
		var is_main: bool = bool(seg.main)
		var fade := _fade_alpha()
		var core_w := 2.8 if is_main else 2.0
		var glow_w := 5.2 if is_main else 3.6

		_draw_jagged_bolt(
			from_l, to_l,
			Color(0.25, 0.55, 1.0, 0.35 * fade),
			glow_w,
			i * 17 + _flicker_token,
			true
		)
		_draw_jagged_bolt(
			from_l, to_l,
			Color(0.55, 0.88, 1.0, 0.95 * fade),
			core_w,
			i * 17 + _flicker_token,
			false
		)
		_draw_jagged_bolt(
			from_l, to_l,
			Color(0.92, 0.98, 1.0, 0.75 * fade),
			maxf(1.0, core_w * 0.45),
			i * 31 + _flicker_token * 3,
			false
		)

		# Decorative forks near the tip of a growing / held bolt.
		if progress > 0.55:
			_draw_forks(from_l, to_l, is_main, fade, i)

	for point in _impact_points:
		var local_p := to_local(point)
		var burst := clampf((_elapsed - BRANCH_START_DELAY) / 0.12, 0.0, 1.0)
		if burst <= 0.0:
			continue
		var a := (1.0 - burst * 0.65) * _fade_alpha()
		draw_circle(local_p, 6.0 * burst, Color(0.45, 0.8, 1.0, 0.28 * a))
		draw_circle(local_p, 2.4, Color(1.0, 1.0, 1.0, 0.85 * a))


func _segment_progress(seg: Dictionary) -> float:
	var t := _elapsed - float(seg.delay)
	if t <= 0.0:
		return 0.0
	var grow := maxf(0.001, float(seg.grow))
	return clampf(t / grow, 0.0, 1.0)


func _fade_alpha() -> float:
	var end_t := MAIN_GROW_SECONDS + BRANCH_GROW_SECONDS + HOLD_SECONDS
	var fade_start := end_t - 0.12
	if _elapsed < fade_start:
		return 1.0
	return clampf(1.0 - (_elapsed - fade_start) / 0.12, 0.0, 1.0)


func _draw_jagged_bolt(
	from: Vector2,
	to: Vector2,
	color: Color,
	width: float,
	seed_offset: int,
	soft: bool
) -> void:
	var delta := to - from
	var length := delta.length()
	if length <= 0.001:
		return
	var dir := delta / length
	var perp := Vector2(-dir.y, dir.x)
	var segments := maxi(3, int(length / 14.0))
	var points := PackedVector2Array()
	points.append(from)
	for i in range(1, segments):
		var t := float(i) / float(segments)
		var base := from.lerp(to, t)
		var wobble_amp := (11.0 if soft else 7.5) * (1.0 - absf(t - 0.5) * 1.15)
		# Deterministic flicker from seed + segment index.
		var n := _hash_noise(seed_offset + i * 13)
		var wobble := (n * 2.0 - 1.0) * wobble_amp
		points.append(base + perp * wobble)
	points.append(to)
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, width, true)


func _draw_forks(from: Vector2, to: Vector2, is_main: bool, fade: float, seg_index: int) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 28.0:
		return
	var dir := delta / length
	var perp := Vector2(-dir.y, dir.x)
	var fork_count := 2 if is_main else 1
	for f in range(fork_count):
		var along := 0.35 + 0.2 * float(f) + 0.08 * _hash_noise(seg_index * 9 + f * 5 + _flicker_token)
		var root := from.lerp(to, clampf(along, 0.2, 0.75))
		var side := 1.0 if (f + seg_index) % 2 == 0 else -1.0
		var fork_len := (16.0 if is_main else 11.0) * (0.75 + 0.35 * _hash_noise(seg_index + f * 11))
		var tip := root + dir * fork_len * 0.35 + perp * side * fork_len
		_draw_jagged_bolt(
			root, tip,
			Color(0.7, 0.92, 1.0, 0.55 * fade),
			1.4,
			seg_index * 41 + f * 7 + _flicker_token,
			false
		)


func _hash_noise(v: int) -> float:
	# Cheap 0..1 hash for flicker without reallocating RNG every draw.
	var x := (v * 1103515245 + 12345) & 0x7fffffff
	return float(x % 1000) / 999.0
