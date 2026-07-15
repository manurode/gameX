class_name TerrainObstacle
extends Node2D

@export var blocks_movement: bool = false
@export var slow_multiplier: float = 1.0
@export var slow_radius: float = 0.0
@export var nav_block_half_size := Vector2(40.0, 25.0)

var _sprite: Sprite2D
var _collision_body: StaticBody2D


func setup(
	texture: Texture2D,
	world_position: Vector2,
	sprite_offset: Vector2,
	blocks: bool,
	slow_mult: float = 1.0,
	slow_rad: float = 0.0,
	block_half: Vector2 = Vector2(40.0, 25.0),
	show_sprite: bool = true
) -> void:
	blocks_movement = blocks
	slow_multiplier = slow_mult
	slow_radius = slow_rad
	nav_block_half_size = block_half
	position = world_position

	if show_sprite:
		_sprite = Sprite2D.new()
		_sprite.texture = texture
		_sprite.centered = true
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_sprite.offset = sprite_offset
		_sprite.y_sort_enabled = true
		add_child(_sprite)

	if blocks_movement:
		_collision_body = StaticBody2D.new()
		_collision_body.collision_layer = 1
		_collision_body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = nav_block_half_size * 2.0
		shape.shape = rect
		shape.position = Vector2(0.0, -nav_block_half_size.y * 0.5)
		_collision_body.add_child(shape)
		add_child(_collision_body)

	if slow_multiplier < 1.0 and slow_radius > 0.0:
		add_to_group("slow_zones")


func is_point_in_slow_zone(world_point: Vector2) -> bool:
	if slow_multiplier >= 1.0 or slow_radius <= 0.0:
		return false
	return global_position.distance_to(world_point) <= slow_radius


func get_slow_multiplier_at(world_point: Vector2) -> float:
	if is_point_in_slow_zone(world_point):
		return slow_multiplier
	return 1.0


func get_nav_block_outline() -> PackedVector2Array:
	if not blocks_movement:
		return PackedVector2Array()

	var center := global_position + Vector2(0.0, -nav_block_half_size.y * 0.5)
	var half := nav_block_half_size
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y),
		center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y),
		center + Vector2(-half.x, half.y),
	])
