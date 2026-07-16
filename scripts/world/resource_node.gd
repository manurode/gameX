class_name ResourceNode
extends Node2D

signal depleted

enum ResourceKind { WOOD, FOOD, GOLD }

@export var resource_kind: ResourceKind = ResourceKind.WOOD
@export var amount_remaining: int = 100
var is_infinite: bool = false
var _initial_amount: int = 100

const PICK_RADIUS := 72.0

var pick_radius: float = PICK_RADIUS
var _sprites: Array[Sprite2D] = []


func _ready() -> void:
	add_to_group("resource_nodes")
	y_sort_enabled = true


func setup(texture: Texture2D, world_pos: Vector2, kind: ResourceKind, amount: int, sprite_offset: Vector2) -> void:
	resource_kind = kind
	amount_remaining = amount
	_initial_amount = amount
	is_infinite = false
	global_position = world_pos
	_add_sprite(texture, Vector2.ZERO, sprite_offset)


func setup_crop_field(
	center_pos: Vector2,
	textures: Array[Texture2D],
	columns: int,
	rows: int
) -> void:
	resource_kind = ResourceKind.FOOD
	amount_remaining = 0
	_initial_amount = 0
	is_infinite = true
	global_position = center_pos

	var spacing := Vector2(38.0, 22.0)
	var start := Vector2(-float(columns - 1) * spacing.x * 0.5, -float(rows - 1) * spacing.y * 0.5)
	var tex_index := 0

	for row in rows:
		for col in columns:
			var texture: Texture2D = textures[tex_index % textures.size()]
			tex_index += 1
			if texture == null:
				continue
			var offset := Vector2(float(col) * spacing.x, float(row) * spacing.y) + start
			var sprite_offset := Vector2(0.0, -texture.get_height() * 0.5 + 64.0)
			_add_sprite(texture, offset, sprite_offset, 0.92 + float(row) * 0.01)


func _add_sprite(texture: Texture2D, local_pos: Vector2, sprite_offset: Vector2, scale_factor: float = 1.0) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.position = local_pos
	sprite.offset = sprite_offset
	sprite.scale = Vector2(scale_factor, scale_factor)
	add_child(sprite)
	_sprites.append(sprite)


func get_resource_key() -> String:
	match resource_kind:
		ResourceKind.WOOD:
			return "wood"
		ResourceKind.FOOD:
			return "food"
		ResourceKind.GOLD:
			return "gold"
	return ""


func get_work_position(from_position: Vector2) -> Vector2:
	if _sprites.is_empty():
		return global_position
	var best_pos := to_global(_sprites[0].position + _sprites[0].offset)
	var best_dist := from_position.distance_squared_to(best_pos)
	for i in range(1, _sprites.size()):
		var sprite := _sprites[i]
		var pos := to_global(sprite.position + sprite.offset)
		var dist := from_position.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best_pos = pos
	return best_pos


func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= pick_radius


func harvest(amount: int) -> int:
	if is_infinite:
		return maxi(0, amount)
	if amount_remaining <= 0:
		return 0
	var gathered := mini(amount, amount_remaining)
	amount_remaining -= gathered
	if amount_remaining <= 0:
		_on_depleted()
	elif _sprites.size() > 1:
		_update_field_visual()
	return gathered


func has_resources() -> bool:
	return is_infinite or amount_remaining > 0


func _update_field_visual() -> void:
	var ratio := clampf(float(amount_remaining) / float(maxi(1, _initial_amount)), 0.2, 1.0)
	for i in _sprites.size():
		var sprite := _sprites[i]
		if ratio < 0.5 and i % 2 == 1:
			sprite.visible = false
		else:
			sprite.modulate = Color(ratio, ratio, ratio * 0.85, 1.0)


func _on_depleted() -> void:
	for sprite in _sprites:
		sprite.modulate = Color(0.45, 0.45, 0.35, 0.35)
	depleted.emit()
