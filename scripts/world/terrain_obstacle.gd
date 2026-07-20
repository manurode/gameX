class_name TerrainObstacle
extends Node2D

## Alpha / simplify settings for visual footprint extraction from the sprite base.
const ALPHA_THRESHOLD := 0.28
const POLYGON_EPSILON := 3.5
## Turquoise / teal water pixels used for lake collision (shore vegetation stays walkable).
const WATER_MIN_BLUE := 0.32

@export var blocks_movement: bool = false
@export var slow_multiplier: float = 1.0
@export var slow_radius: float = 0.0
@export var nav_block_half_size := Vector2(40.0, 25.0)

var _sprite: Sprite2D
var _collision_body: StaticBody2D
var _block_outlines_local: Array[PackedVector2Array] = []


func setup(
	texture: Texture2D,
	world_position: Vector2,
	sprite_offset: Vector2,
	blocks: bool,
	slow_mult: float = 1.0,
	slow_rad: float = 0.0,
	block_half: Vector2 = Vector2(40.0, 25.0),
	show_sprite: bool = true,
	scale_factor: float = 1.0,
	footprint_band: float = 0.0,
	occludes: bool = true,
	use_water_mask: bool = false
) -> void:
	blocks_movement = blocks
	slow_multiplier = slow_mult
	slow_radius = slow_rad
	nav_block_half_size = block_half
	y_sort_enabled = true
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
		if occludes:
			add_to_group("occlusion_props")

	if blocks_movement:
		if use_water_mask and texture != null:
			_block_outlines_local = _build_water_block_outlines(
				texture,
				sprite_offset,
				scale_factor
			)
		elif footprint_band > 0.0 and texture != null:
			_block_outlines_local = _build_visual_block_outlines(
				texture,
				sprite_offset,
				scale_factor,
				footprint_band
			)
		if _block_outlines_local.is_empty():
			_block_outlines_local = [_local_block_diamond()]
		_build_collision_from_outlines()

	if slow_multiplier < 1.0 and slow_radius > 0.0:
		add_to_group("slow_zones")


func get_sort_y() -> float:
	return global_position.y


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


func blocks_world_point(world_point: Vector2) -> bool:
	if not blocks_movement:
		return false
	var local_point := to_local(world_point)
	for outline in _block_outlines_local:
		if outline.size() >= 3 and Geometry2D.is_point_in_polygon(local_point, outline):
			return true
	return false


func get_nav_block_outlines() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not blocks_movement:
		return result
	for outline in _block_outlines_local:
		if outline.size() < 3:
			continue
		var world_outline := PackedVector2Array()
		for point in outline:
			world_outline.append(to_global(point))
		result.append(world_outline)
	return result


func get_nav_block_outline() -> PackedVector2Array:
	var outlines := get_nav_block_outlines()
	if outlines.is_empty():
		return PackedVector2Array()
	# Prefer the largest polygon for single-outline callers (build ghost, etc.).
	var best := outlines[0]
	var best_area := _polygon_area(best)
	for i in range(1, outlines.size()):
		var area := _polygon_area(outlines[i])
		if area > best_area:
			best = outlines[i]
			best_area = area
	return best


## Closest point on the solid footprint perimeter (any side of the obstacle).
func get_closest_surface_point(from_position: Vector2) -> Vector2:
	var outlines := get_nav_block_outlines()
	if outlines.is_empty():
		return global_position
	var best := outlines[0][0]
	var best_dist := from_position.distance_squared_to(best)
	for outline in outlines:
		for i in outline.size():
			var segment_start := outline[i]
			var segment_end := outline[(i + 1) % outline.size()]
			var closest := Geometry2D.get_closest_point_to_segment(
				from_position,
				segment_start,
				segment_end
			)
			var dist := from_position.distance_squared_to(closest)
			if dist < best_dist:
				best_dist = dist
				best = closest
	return best


func _build_collision_from_outlines() -> void:
	_collision_body = StaticBody2D.new()
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 0
	for outline in _block_outlines_local:
		if outline.size() < 3:
			continue
		var col_poly := CollisionPolygon2D.new()
		col_poly.polygon = outline
		_collision_body.add_child(col_poly)
	add_child(_collision_body)


func _build_visual_block_outlines(
	texture: Texture2D,
	sprite_offset: Vector2,
	scale_factor: float,
	footprint_band: float
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var image := OcclusionUtils.get_texture_image(texture)
	if image == null:
		return result

	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return result

	var band := clampf(footprint_band, 0.15, 1.0)
	var band_height := maxi(1, int(round(float(height) * band)))
	var band_y := height - band_height
	var band_image := image.get_region(Rect2i(0, band_y, width, band_height))

	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(band_image, ALPHA_THRESHOLD)
	var raw_polys := bitmap.opaque_to_polygons(
		Rect2(Vector2.ZERO, Vector2(width, band_height)),
		POLYGON_EPSILON
	)

	var half_tex := Vector2(float(width), float(height)) * 0.5
	for raw in raw_polys:
		if raw.size() < 3:
			continue
		var local_poly := PackedVector2Array()
		for point in raw:
			# Band coords -> full texture centered coords -> sprite local (offset + scale).
			var tex_local := Vector2(point.x, point.y + float(band_y)) - half_tex
			local_poly.append((sprite_offset + tex_local) * scale_factor)
		if local_poly.size() >= 3:
			result.append(local_poly)
	return result


func _build_water_block_outlines(
	texture: Texture2D,
	sprite_offset: Vector2,
	scale_factor: float
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var image := OcclusionUtils.get_texture_image(texture)
	if image == null:
		return result

	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return result

	var mask := Image.create(width, height, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in height:
		for x in width:
			if _is_water_color(image.get_pixel(x, y)):
				mask.set_pixel(x, y, Color.WHITE)

	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(mask, 0.5)
	var raw_polys := bitmap.opaque_to_polygons(
		Rect2(Vector2.ZERO, Vector2(width, height)),
		POLYGON_EPSILON
	)

	var half_tex := Vector2(float(width), float(height)) * 0.5
	for raw in raw_polys:
		if raw.size() < 3:
			continue
		var local_poly := PackedVector2Array()
		for point in raw:
			var tex_local := Vector2(point.x, point.y) - half_tex
			local_poly.append((sprite_offset + tex_local) * scale_factor)
		if local_poly.size() >= 3:
			result.append(local_poly)
	return result


func _is_water_color(color: Color) -> bool:
	if color.a < ALPHA_THRESHOLD:
		return false
	# Turquoise / teal body of water — excludes shore rocks and green vegetation.
	return color.b > color.g * 0.7 and color.g > color.r and color.b > WATER_MIN_BLUE


func _block_center_local() -> Vector2:
	return Vector2(0.0, -nav_block_half_size.y * 0.12)


func _local_block_diamond() -> PackedVector2Array:
	var center := _block_center_local()
	var half := nav_block_half_size
	return PackedVector2Array([
		center + Vector2(0.0, -half.y),
		center + Vector2(half.x, 0.0),
		center + Vector2(0.0, half.y),
		center + Vector2(-half.x, 0.0),
	])


func _polygon_area(outline: PackedVector2Array) -> float:
	if outline.size() < 3:
		return 0.0
	var area := 0.0
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5
