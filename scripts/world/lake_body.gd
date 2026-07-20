class_name LakeBody
extends Node2D

## Organic lake prop (visual only). Non-walkable water is the TileMap water_set mask.

const DEFAULT_OCCLUSION_CULL_RADIUS := 320.0
const INTERIOR_RADIUS := 200.0
const INTERIOR_ASPECT := 0.45

var _sprite: Sprite2D
var _anchor_position := Vector2.ZERO


func setup(
	texture: Texture2D,
	world_pos: Vector2,
	sprite_offset: Vector2,
	scale_factor: float,
	sort_bias: float
) -> void:
	_anchor_position = world_pos
	y_sort_enabled = true
	add_to_group("occlusion_props")

	var sort_dy := 0.0
	if sort_bias > 0.0:
		sort_dy = 64.0 * scale_factor - sort_bias
	global_position = world_pos + Vector2(0.0, sort_dy)

	var draw_offset := sprite_offset
	if not is_zero_approx(scale_factor) and not is_zero_approx(sort_dy):
		draw_offset = sprite_offset - Vector2(0.0, sort_dy / scale_factor)

	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.centered = true
	_sprite.offset = draw_offset
	_sprite.scale = Vector2(scale_factor, scale_factor)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)


func get_occlusion_sprites() -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	if _sprite != null:
		sprites.append(_sprite)
	return sprites


func get_occlusion_cull_radius() -> float:
	if _sprite == null or _sprite.texture == null:
		return DEFAULT_OCCLUSION_CULL_RADIUS
	var size := _sprite.texture.get_size() * _sprite.scale.abs()
	var half := maxf(size.x, size.y) * 0.5
	return maxf(DEFAULT_OCCLUSION_CULL_RADIUS, half + 64.0)


func uses_sparse_occlusion() -> bool:
	return true


func is_forest_interior(world_pos: Vector2) -> bool:
	## Soft interior so shore trees can silhouette units walking "through" the mass.
	var local := world_pos - _anchor_position
	var rx := INTERIOR_RADIUS
	var ry := rx * INTERIOR_ASPECT
	var nx := local.x / rx
	var ny := local.y / ry
	return nx * nx + ny * ny <= 1.0
