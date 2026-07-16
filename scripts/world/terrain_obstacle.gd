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
	show_sprite: bool = true,
	scale_factor: float = 1.0
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
		_sprite.scale = Vector2(scale_factor, scale_factor)
		_sprite.y_sort_enabled = true
		add_child(_sprite)
		add_to_group("occlusion_props")

	if blocks_movement:
		_collision_body = StaticBody2D.new()
		_collision_body.collision_layer = 1
		_collision_body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var convex := ConvexPolygonShape2D.new()
		convex.points = _local_block_diamond()
		shape.shape = convex
		_collision_body.add_child(shape)
		add_child(_collision_body)

	if slow_multiplier < 1.0 and slow_radius > 0.0:
		add_to_group("slow_zones")


func get_occlusion_sprites() -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	if _sprite != null and _sprite.visible and _sprite.texture != null:
		sprites.append(_sprite)
	return sprites


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

	var center := _block_center_world()
	var half := nav_block_half_size
	# Isometric diamond matching the ground footprint (not the tall AABB).
	return PackedVector2Array([
		center + Vector2(0.0, -half.y),
		center + Vector2(half.x, 0.0),
		center + Vector2(0.0, half.y),
		center + Vector2(-half.x, 0.0),
	])


func _block_center_local() -> Vector2:
	# Sit the diamond on the sprite base, not up in the peaks.
	return Vector2(0.0, -nav_block_half_size.y * 0.12)


func _block_center_world() -> Vector2:
	return global_position + _block_center_local()


func _local_block_diamond() -> PackedVector2Array:
	var center := _block_center_local()
	var half := nav_block_half_size
	return PackedVector2Array([
		center + Vector2(0.0, -half.y),
		center + Vector2(half.x, 0.0),
		center + Vector2(0.0, half.y),
		center + Vector2(-half.x, 0.0),
	])
