class_name Arrow
extends Area2D

const MAX_LIFETIME := 2.5

var speed: float = 300.0
var damage: int = 12
var direction: Vector2 = Vector2.RIGHT
var shooter: Unit
var target: Unit

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

	if not _has_hit and target != null and is_instance_valid(target) and target.hp > 0:
		if global_position.distance_to(target.get_sprite_center()) <= 18.0:
			_hit_unit(target)

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


func _on_body_entered(body: Node2D) -> void:
	if _has_hit or not body is Unit:
		return

	var unit := body as Unit
	if unit == shooter or unit.hp <= 0:
		return

	_hit_unit(unit)


func _hit_unit(unit: Unit) -> void:
	if _has_hit:
		return
	_has_hit = true
	unit.take_damage(damage, shooter)
	queue_free()
