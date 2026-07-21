class_name Fireball
extends Area2D

## Hexwing ranged projectile — glowing fire orb with a short ember trail.

const MAX_LIFETIME := 2.2

var speed: float = 260.0
var damage: int = 12
var direction: Vector2 = Vector2.RIGHT
var shooter: Unit
var target: Unit
var building_target: Building

var _lifetime: float = 0.0
var _has_hit := false
var _trail: Array[Vector2] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	z_index = 35
	queue_redraw()


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_lifetime += delta

	_trail.push_front(global_position)
	if _trail.size() > 7:
		_trail.resize(7)

	if not _has_hit and target != null and _can_hit_unit(target):
		if global_position.distance_squared_to(target.get_sprite_center()) <= 400.0:
			_hit_unit(target)

	if not _has_hit and building_target != null and _can_hit_building(building_target):
		if global_position.distance_squared_to(building_target.get_attack_point()) <= 484.0:
			_hit_building(building_target)

	queue_redraw()
	if _lifetime >= MAX_LIFETIME:
		queue_free()


func _draw() -> void:
	var pulse := 0.85 + 0.15 * sin(_lifetime * 28.0)
	# Ember trail (oldest first, drawn dimmest).
	for i in range(_trail.size() - 1, 0, -1):
		var p := to_local(_trail[i])
		var t := 1.0 - float(i) / float(maxi(1, _trail.size()))
		var r := 2.2 + 2.8 * t
		draw_circle(p, r, Color(1.0, 0.35, 0.05, 0.18 * t))
		draw_circle(p, r * 0.55, Color(1.0, 0.75, 0.2, 0.35 * t))

	# Outer glow
	draw_circle(Vector2.ZERO, 7.5 * pulse, Color(1.0, 0.25, 0.02, 0.28))
	draw_circle(Vector2.ZERO, 5.2 * pulse, Color(1.0, 0.45, 0.05, 0.55))
	# Core
	draw_circle(Vector2.ZERO, 3.4, Color(1.0, 0.72, 0.15, 0.95))
	draw_circle(Vector2(-0.8, -0.9), 1.5, Color(1.0, 0.95, 0.7, 0.9))


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
