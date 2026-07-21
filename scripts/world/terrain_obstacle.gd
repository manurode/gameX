class_name TerrainObstacle
extends Node2D

## Alpha / simplify settings for visual footprint extraction from the sprite base.
const ALPHA_THRESHOLD := 0.28
const POLYGON_EPSILON := 3.5
## Turquoise / teal water pixels used for lake collision (shore vegetation stays walkable).
const WATER_MIN_BLUE := 0.32
## Skip fully transparent / fringe pixels before the float teal test (a >= ALPHA_THRESHOLD).
const WATER_ALPHA_BYTE_MIN := 72

@export var blocks_movement: bool = false
@export var slow_multiplier: float = 1.0
@export var slow_radius: float = 0.0
@export var nav_block_half_size := Vector2(40.0, 25.0)

## Texture-centered water polygons keyed by lake texture resource path.
static var _water_tex_poly_cache: Dictionary = {}
## Optional baked alpha masks (lake_x_water_mask.png) keyed by lake texture path.
static var _water_mask_texture_cache: Dictionary = {}
## Precomputed outlines from lake_water_outlines.json (path -> Array of polys).
static var _water_outline_file_cache: Dictionary = {}
static var _water_outline_file_loaded: bool = false

const WATER_OUTLINES_PATH := "res://assets/tilesets/mediterranean/Decor/lake_water_outlines.json"

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
	if texture == null:
		return result

	# Cache by resource path so every lake of the same variant reuses outlines.
	var cache_key := texture.resource_path
	if cache_key.is_empty():
		cache_key = str(texture.get_rid().get_id())

	var tex_polys: Array
	if _water_tex_poly_cache.has(cache_key):
		tex_polys = _water_tex_poly_cache[cache_key]
	else:
		tex_polys = extract_water_tex_polys(texture)
		_water_tex_poly_cache[cache_key] = tex_polys

	for tex_local in tex_polys:
		if tex_local.size() < 3:
			continue
		var local_poly := PackedVector2Array()
		for point in tex_local:
			local_poly.append((sprite_offset + point) * scale_factor)
		if local_poly.size() >= 3:
			result.append(local_poly)
	return result


## Prefer baked JSON outlines (instant). Else baked alpha mask + BitMap.
## Falls back to a one-time teal scan only if bake assets are missing.
static func extract_water_tex_polys(texture: Texture2D) -> Array:
	var baked := _load_baked_water_outlines(texture)
	if not baked.is_empty():
		return baked

	var mask_image := _load_baked_water_mask_image(texture)
	if mask_image != null:
		return _polys_from_alpha_mask(mask_image)

	var image := OcclusionUtils.get_texture_image(texture)
	if image == null:
		return []
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return []
	return _extract_water_tex_polys_from_color(image, width, height)


static func _ensure_water_outline_file_loaded() -> void:
	if _water_outline_file_loaded:
		return
	_water_outline_file_loaded = true
	if not FileAccess.file_exists(WATER_OUTLINES_PATH):
		return
	var file := FileAccess.open(WATER_OUTLINES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_water_outline_file_cache = parsed


static func _load_baked_water_outlines(texture: Texture2D) -> Array:
	var result: Array = []
	var lake_path := texture.resource_path
	if lake_path.is_empty():
		return result
	_ensure_water_outline_file_loaded()
	if not _water_outline_file_cache.has(lake_path):
		return result
	var raw_polys: Variant = _water_outline_file_cache[lake_path]
	if typeof(raw_polys) != TYPE_ARRAY:
		return result
	for raw in raw_polys:
		if typeof(raw) != TYPE_ARRAY or raw.size() < 3:
			continue
		var tex_poly := PackedVector2Array()
		for point in raw:
			if typeof(point) != TYPE_ARRAY or point.size() < 2:
				continue
			tex_poly.append(Vector2(float(point[0]), float(point[1])))
		if tex_poly.size() >= 3:
			result.append(tex_poly)
	return result


static func _load_baked_water_mask_image(texture: Texture2D) -> Image:
	var lake_path := texture.resource_path
	if lake_path.is_empty():
		return null
	if _water_mask_texture_cache.has(lake_path):
		var cached: Variant = _water_mask_texture_cache[lake_path]
		return cached as Image

	var mask_path := lake_path.get_basename() + "_water_mask.png"
	if not FileAccess.file_exists(mask_path):
		_water_mask_texture_cache[lake_path] = null
		return null

	# Load PNG bytes directly — avoids texture import / VRAM round-trip.
	var mask_image := Image.load_from_file(ProjectSettings.globalize_path(mask_path))
	_water_mask_texture_cache[lake_path] = mask_image
	return mask_image


## Call once per lake variant before spawning many lakes (fills outline cache).
static func warmup_water_outlines(texture: Texture2D) -> void:
	if texture == null:
		return
	var cache_key := texture.resource_path
	if cache_key.is_empty():
		cache_key = str(texture.get_rid().get_id())
	if _water_tex_poly_cache.has(cache_key):
		return
	_water_tex_poly_cache[cache_key] = extract_water_tex_polys(texture)


static func _polys_from_alpha_mask(mask_image: Image) -> Array:
	var result: Array = []
	var width := mask_image.get_width()
	var height := mask_image.get_height()
	if width <= 0 or height <= 0:
		return result

	# Crop to opaque bounds — same polygons, less work for opaque_to_polygons.
	var used := mask_image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return result
	var cropped := mask_image.get_region(used)

	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(cropped, 0.5)
	var raw_polys := bitmap.opaque_to_polygons(
		Rect2(Vector2.ZERO, Vector2(used.size.x, used.size.y)),
		POLYGON_EPSILON
	)

	var half_tex := Vector2(float(width), float(height)) * 0.5
	var origin := Vector2(float(used.position.x), float(used.position.y))
	for raw in raw_polys:
		if raw.size() < 3:
			continue
		var tex_poly := PackedVector2Array()
		for point in raw:
			tex_poly.append(origin + Vector2(point.x, point.y) - half_tex)
		if tex_poly.size() >= 3:
			result.append(tex_poly)
	return result


## Texture-centered water polygons from a full-color lake sprite (slow fallback).
static func _extract_water_tex_polys_from_color(
	image: Image,
	width: int,
	height: int
) -> Array:
	var src := image
	if src.get_format() != Image.FORMAT_RGBA8:
		src = image.duplicate()
		src.convert(Image.FORMAT_RGBA8)

	var pixels := src.get_data()
	var mask_data := PackedByteArray()
	mask_data.resize(width * height * 4)
	var i := 0
	var pixel_count := width * height
	for _p in pixel_count:
		var a: int = pixels[i + 3]
		if a >= WATER_ALPHA_BYTE_MIN:
			var r := float(pixels[i]) / 255.0
			var g := float(pixels[i + 1]) / 255.0
			var b := float(pixels[i + 2]) / 255.0
			if b > g * 0.7 and g > r and b > WATER_MIN_BLUE:
				mask_data[i] = 255
				mask_data[i + 1] = 255
				mask_data[i + 2] = 255
				mask_data[i + 3] = 255
		i += 4

	var mask := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, mask_data)
	return _polys_from_alpha_mask(mask)


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
