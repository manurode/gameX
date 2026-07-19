class_name LightningBolt
extends Area2D

const MAX_LIFETIME := 1.6
const CHAIN_VFX_SECONDS := 0.28

var speed: float = 420.0
var damage: int = 12
var chain_damage: int = 4
var chain_radius: float = 70.0
var chain_max_targets: int = 2
var direction: Vector2 = Vector2.RIGHT
var shooter: Unit
var target: Unit
var building_target: Building

var _lifetime: float = 0.0
var _has_hit := false
var _chain_points: Array[Vector2] = []
var _chain_timer: float = 0.0
var _show_chain := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _show_chain:
		_chain_timer -= delta
		queue_redraw()
		if _chain_timer <= 0.0:
			queue_free()
		return

	var motion := direction * speed * delta
	global_position += motion
	_lifetime += delta

	if not _has_hit and target != null and _can_hit_unit(target):
		if global_position.distance_squared_to(target.get_sprite_center()) <= 324.0:
			_hit_unit(target)

	if not _has_hit and building_target != null and _can_hit_building(building_target):
		if global_position.distance_squared_to(building_target.get_attack_point()) <= 484.0:
			_hit_building(building_target)

	if _lifetime >= MAX_LIFETIME:
		queue_free()


func _draw() -> void:
	if _show_chain and not _chain_points.is_empty():
		var origin_local := to_local(_chain_points[0])
		for i in range(1, _chain_points.size()):
			var a := to_local(_chain_points[i - 1]) if i > 1 else origin_local
			if i == 1:
				a = origin_local
			var b := to_local(_chain_points[i])
			_draw_jagged_bolt(a, b, Color(0.55, 0.85, 1.0, 0.95), 2.4)
			_draw_jagged_bolt(a, b, Color(0.85, 0.95, 1.0, 0.55), 1.1)
		return

	# Primary flying bolt tip.
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(12.0, 0.0),
			Vector2(-5.0, -3.5),
			Vector2(-2.0, 0.0),
			Vector2(-5.0, 3.5),
		]),
		Color(0.65, 0.9, 1.0, 1.0)
	)
	draw_circle(Vector2(-1.0, 0.0), 3.0, Color(0.9, 0.98, 1.0, 0.85))


func _draw_jagged_bolt(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var delta := to - from
	var length := delta.length()
	if length <= 0.001:
		return
	var dir := delta / length
	var perp := Vector2(-dir.y, dir.x)
	var segments := maxi(2, int(length / 18.0))
	var points := PackedVector2Array()
	points.append(from)
	for i in range(1, segments):
		var t := float(i) / float(segments)
		var base := from.lerp(to, t)
		var wobble := sin(float(i) * 2.7 + length * 0.05) * 9.0
		var jitter := perp * wobble * (1.0 - absf(t - 0.5) * 1.2)
		points.append(base + jitter)
	points.append(to)
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, width, true)


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


func _on_body_entered(body: Node2D) -> void:
	if _has_hit or _show_chain:
		return
	if body is Unit:
		var unit := body as Unit
		if not _can_hit_unit(unit):
			return
		_hit_unit(unit)
	elif body is Building:
		var building := body as Building
		if not _can_hit_building(building):
			return
		_hit_building(building)


func _hit_unit(unit: Unit) -> void:
	if _has_hit:
		return
	_has_hit = true
	unit.take_damage(damage, shooter)
	_apply_chain(unit)
	_begin_chain_vfx(unit.get_sprite_center())


func _hit_building(building: Building) -> void:
	if _has_hit:
		return
	_has_hit = true
	building.take_damage(damage, shooter)
	# No unit chain from buildings; brief impact flash then free.
	_chain_points = [global_position, building.get_attack_point()]
	_show_chain = true
	_chain_timer = CHAIN_VFX_SECONDS * 0.6
	queue_redraw()


func _apply_chain(primary: Unit) -> void:
	_chain_points.clear()
	_chain_points.append(primary.get_sprite_center())
	if chain_damage <= 0 or chain_radius <= 0.0 or chain_max_targets <= 0:
		return
	if shooter == null or not is_instance_valid(shooter):
		return

	var origin := primary.global_position
	var candidates: Array[Dictionary] = []
	var tree := get_tree()
	if tree == null:
		return

	for item in UnitSpatialIndex.query_nearby(tree, origin, chain_radius):
		if not item is Unit:
			continue
		var enemy := item as Unit
		if enemy == primary or not _can_hit_unit(enemy):
			continue
		var dist_sq := origin.distance_squared_to(enemy.global_position)
		candidates.append({"unit": enemy, "dist": dist_sq})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.dist) < float(b.dist)
	)

	var chained := 0
	for entry in candidates:
		if chained >= chain_max_targets:
			break
		var enemy: Unit = entry.unit
		enemy.take_damage(chain_damage, shooter)
		_chain_points.append(enemy.get_sprite_center())
		chained += 1


func _begin_chain_vfx(primary_center: Vector2) -> void:
	if _chain_points.is_empty():
		_chain_points.append(primary_center)
	if _chain_points.size() == 1:
		# Still show a short impact spark even without splash targets.
		_chain_points.append(primary_center + Vector2(8.0, -10.0))
	global_position = primary_center
	_show_chain = true
	_chain_timer = CHAIN_VFX_SECONDS
	queue_redraw()
