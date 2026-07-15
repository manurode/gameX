class_name Arrow
extends Area2D

const MAX_LIFETIME := 2.5

var speed: float = 300.0
var damage: int = 12
var direction: Vector2 = Vector2.RIGHT
var shooter: Unit
var target: Unit
var building_target: Building

var _lifetime: float = 0.0
var _has_hit := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()
	queue_redraw()


func _physics_process(delta: float) -> void:
	var motion := direction * speed * delta
	global_position += motion
	_lifetime += delta

	if not _has_hit and target != null and _can_hit_unit(target):
		if global_position.distance_to(target.get_sprite_center()) <= 18.0:
			_hit_unit(target)

	if not _has_hit and building_target != null and _can_hit_building(building_target):
		if global_position.distance_to(building_target.get_attack_point()) <= 22.0:
			_hit_building(building_target)

	if _lifetime >= MAX_LIFETIME:
		queue_free()


func _draw() -> void:
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(10.0, 0.0),
			Vector2(-6.0, -3.0),
			Vector2(-4.0, 0.0),
			Vector2(-6.0, 3.0),
		]),
		Color(0.72, 0.52, 0.28, 1.0)
	)


func _can_hit_unit(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit) or unit == shooter or unit.hp <= 0 or unit._is_dying:
		return false
	if unit.garrisoned_building != null:
		return false
	if shooter != null and is_instance_valid(shooter) and not shooter.is_hostile_to(unit):
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
	if _has_hit:
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
	queue_free()


func _hit_building(building: Building) -> void:
	if _has_hit:
		return
	_has_hit = true
	building.take_damage(damage, shooter)
	queue_free()
