class_name ResourceNode
extends Node2D

signal depleted
signal amount_changed(remaining: int, initial_amount: int)

enum ResourceKind { WOOD, FOOD, GOLD }

@export var resource_kind: ResourceKind = ResourceKind.WOOD
@export var amount_remaining: int = 100
var is_infinite: bool = false
var is_selected: bool = false
var _initial_amount: int = 100

const PICK_RADIUS := 72.0
const AMOUNT_BAR_SCRIPT := preload("res://scripts/world/resource_amount_bar.gd")

var pick_radius: float = PICK_RADIUS
var _sprites: Array[Sprite2D] = []
var _work_anchors: Array[Vector2] = []
var _amount_bar: Node2D = null
var _selection_indicator: Line2D = null


func _ready() -> void:
	add_to_group("resource_nodes")
	y_sort_enabled = true
	_ensure_amount_bar()
	_setup_selection_indicator()


func setup(
	texture: Texture2D,
	world_pos: Vector2,
	kind: ResourceKind,
	amount: int,
	sprite_offset: Vector2,
	scale_factor: float = 1.0
) -> void:
	resource_kind = kind
	amount_remaining = amount
	_initial_amount = amount
	is_infinite = false
	global_position = world_pos
	_add_sprite(texture, Vector2.ZERO, sprite_offset, scale_factor)
	# Tall resource visuals (trees, gold rocks) occlude units; crop fields do not.
	if kind != ResourceKind.FOOD:
		add_to_group("occlusion_props")
	_ensure_amount_bar()
	_setup_selection_indicator()


func get_occlusion_sprites() -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	for sprite in _sprites:
		if sprite != null and sprite.visible and sprite.texture != null:
			sprites.append(sprite)
	return sprites


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
	_ensure_amount_bar()
	_setup_selection_indicator()


## Invisible food source bound to a mill's painted farm plot (no yellow wheat tiles).
func setup_mill_farm_zone(center_pos: Vector2, half_size: Vector2) -> void:
	resource_kind = ResourceKind.FOOD
	amount_remaining = 0
	_initial_amount = 0
	is_infinite = true
	global_position = center_pos
	pick_radius = maxf(half_size.x, half_size.y) * 1.15
	_work_anchors = [
		Vector2(-half_size.x * 0.55, half_size.y * 0.1),
		Vector2(0.0, half_size.y * 0.25),
		Vector2(half_size.x * 0.55, half_size.y * 0.1),
	]
	_ensure_amount_bar()
	_setup_selection_indicator()


func _add_sprite(texture: Texture2D, local_pos: Vector2, sprite_offset: Vector2, scale_factor: float = 1.0) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.position = local_pos
	sprite.offset = sprite_offset
	sprite.scale = Vector2(scale_factor, scale_factor)
	add_child(sprite)
	_sprites.append(sprite)


func _ensure_amount_bar() -> void:
	if _amount_bar != null:
		return
	_amount_bar = Node2D.new()
	_amount_bar.set_script(AMOUNT_BAR_SCRIPT)
	_amount_bar.name = "AmountBar"
	add_child(_amount_bar)


func _setup_selection_indicator() -> void:
	if _selection_indicator == null:
		_selection_indicator = Line2D.new()
		_selection_indicator.name = "SelectionIndicator"
		_selection_indicator.width = 2.0
		_selection_indicator.default_color = Color(0.45, 0.95, 0.55, 0.55)
		_selection_indicator.antialiased = true
		_selection_indicator.visible = false
		_selection_indicator.y_sort_enabled = false
		add_child(_selection_indicator)

	var radius_x := 40.0
	var radius_y := 18.0
	if not _work_anchors.is_empty():
		radius_x = clampf(pick_radius, 28.0, 90.0)
		radius_y = radius_x * 0.55
	else:
		var sprites := get_occlusion_sprites()
		if not sprites.is_empty():
			var max_half_w := 0.0
			for sprite in sprites:
				var size := sprite.texture.get_size() * sprite.scale.abs()
				max_half_w = maxf(max_half_w, size.x * 0.38)
			radius_x = clampf(max_half_w, 28.0, 140.0)
			radius_y = radius_x * 0.45

	var points := PackedVector2Array()
	const SEGMENTS := 48
	for i in SEGMENTS + 1:
		var angle := float(i) / float(SEGMENTS) * TAU
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	_selection_indicator.points = points
	_selection_indicator.closed = true
	_selection_indicator.visible = is_selected


func get_resource_key() -> String:
	match resource_kind:
		ResourceKind.WOOD:
			return "wood"
		ResourceKind.FOOD:
			return "food"
		ResourceKind.GOLD:
			return "gold"
	return ""


func get_initial_amount() -> int:
	return _initial_amount


func get_work_position(from_position: Vector2) -> Vector2:
	if not _work_anchors.is_empty():
		var best_anchor := to_global(_work_anchors[0])
		var best_anchor_dist := from_position.distance_squared_to(best_anchor)
		for i in range(1, _work_anchors.size()):
			var anchor_pos := to_global(_work_anchors[i])
			var anchor_dist := from_position.distance_squared_to(anchor_pos)
			if anchor_dist < best_anchor_dist:
				best_anchor_dist = anchor_dist
				best_anchor = anchor_pos
		return best_anchor
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


func get_amount_bar_offset() -> Vector2:
	var sprites := get_occlusion_sprites()
	if sprites.is_empty():
		return Vector2(0.0, -60.0)

	var top_y := INF
	var center_x := 0.0
	for sprite in sprites:
		var size := sprite.texture.get_size() * sprite.scale
		var local_top := sprite.position.y + sprite.offset.y - size.y * 0.5
		if local_top < top_y:
			top_y = local_top
		center_x += sprite.position.x + sprite.offset.x
	center_x /= float(sprites.size())
	return Vector2(center_x, top_y - 10.0)


func contains_point(world_point: Vector2) -> bool:
	if not _work_anchors.is_empty():
		var local := to_local(world_point)
		var rx := maxf(pick_radius, 1.0)
		var ry := rx * 0.55
		var nx := local.x / rx
		var ny := local.y / ry
		return nx * nx + ny * ny <= 1.0

	var sprites := get_occlusion_sprites()
	if sprites.is_empty():
		return global_position.distance_to(world_point) <= pick_radius

	var in_bounds := false
	for sprite in sprites:
		if OcclusionUtils.sprite_global_rect(sprite).grow(2.0).has_point(world_point):
			in_bounds = true
			break
	if not in_bounds:
		return false
	return OcclusionUtils.any_sprite_opaque_at(sprites, world_point)


func harvest(amount: int) -> int:
	if is_infinite:
		return maxi(0, amount)
	if amount_remaining <= 0:
		return 0
	var gathered := mini(amount, amount_remaining)
	amount_remaining -= gathered
	amount_changed.emit(amount_remaining, _initial_amount)
	if amount_remaining <= 0:
		_on_depleted()
	elif _sprites.size() > 1:
		_update_field_visual()
	return gathered


func has_resources() -> bool:
	return is_infinite or amount_remaining > 0


func should_show_amount_bar() -> bool:
	if is_infinite or _initial_amount <= 0:
		return false
	if not has_resources() and not is_selected:
		return false
	return is_selected


func select() -> void:
	is_selected = true
	if _selection_indicator != null:
		_selection_indicator.visible = true


func deselect() -> void:
	is_selected = false
	if _selection_indicator != null:
		_selection_indicator.visible = false


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
	if is_selected:
		deselect()
	depleted.emit()
