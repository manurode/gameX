class_name BuildingFootprint
extends RefCounted

## Derives walk-block / placement outlines from building plot art so units
## cannot cross the ground plan but can still pass behind tall sprite mass.

const ALPHA_THRESHOLD := 0.28
const POLYGON_EPSILON := 2.5
## Slightly inset so unit circles can graze the stone edge without snagging.
const HULL_INSET := 0.94
const BOTTOM_BAND := 0.42

static var _tex_poly_cache: Dictionary = {}


static func plot_texture_path(building_texture_path: String) -> String:
	if building_texture_path.is_empty():
		return ""
	return building_texture_path.get_basename() + "_plot.png"


static func load_plot_texture(building_texture_path: String) -> Texture2D:
	var path := plot_texture_path(building_texture_path)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Texture-centered outline (pre-scale / pre-plant). Cached by path + mode.
static func get_tex_local_outline(texture: Texture2D, mode: String = "opaque") -> PackedVector2Array:
	if texture == null:
		return PackedVector2Array()
	var cache_key := "%s::%s" % [texture.resource_path, mode]
	if cache_key.is_empty() or cache_key.begins_with("::"):
		cache_key = "%s::%s" % [str(texture.get_rid().get_id()), mode]
	if _tex_poly_cache.has(cache_key):
		return _tex_poly_cache[cache_key]

	var image := OcclusionUtils.get_texture_image(texture)
	if image == null:
		return PackedVector2Array()

	var outline := PackedVector2Array()
	match mode:
		"mill_tower":
			outline = _outline_from_mill_tower(image)
		"bottom_band":
			outline = _outline_from_bottom_band(image, BOTTOM_BAND)
		_:
			outline = _outline_from_alpha(image)

	if outline.size() >= 3:
		outline = _inset_polygon(Geometry2D.convex_hull(outline), HULL_INSET)
	_tex_poly_cache[cache_key] = outline
	return outline


## Converts texture-centered points into Building-local space (matches sprite plant).
static func to_building_local(
	tex_local_poly: PackedVector2Array,
	texture: Texture2D,
	visual_scale: float,
	plant_unscaled: float,
	sort_dy: float
) -> PackedVector2Array:
	if tex_local_poly.size() < 3 or texture == null:
		return PackedVector2Array()
	var height := float(texture.get_height())
	var base_offset := Vector2(0.0, -height * 0.5 + plant_unscaled)
	var draw_offset := DepthSort.compensate_draw_offset(base_offset, sort_dy, visual_scale)
	var result := PackedVector2Array()
	result.resize(tex_local_poly.size())
	for i in tex_local_poly.size():
		result[i] = (draw_offset + tex_local_poly[i]) * visual_scale
	return result


static func polygon_center(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for point in poly:
		sum += point
	return sum / float(poly.size())


static func polygon_half_extents(poly: PackedVector2Array, center: Vector2) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var max_x := 0.0
	var max_y := 0.0
	for point in poly:
		var d := point - center
		max_x = maxf(max_x, absf(d.x))
		max_y = maxf(max_y, absf(d.y))
	return Vector2(max_x, max_y)


static func _outline_from_alpha(image: Image) -> PackedVector2Array:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return PackedVector2Array()
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image, ALPHA_THRESHOLD)
	var raw_polys := bitmap.opaque_to_polygons(
		Rect2(Vector2.ZERO, Vector2(width, height)),
		POLYGON_EPSILON
	)
	return _largest_tex_centered_poly(raw_polys, width, height)


static func _outline_from_bottom_band(image: Image, band: float) -> PackedVector2Array:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return PackedVector2Array()
	var band_clamped := clampf(band, 0.15, 1.0)
	var band_height := maxi(1, int(round(float(height) * band_clamped)))
	var band_y := height - band_height
	var band_image := image.get_region(Rect2i(0, band_y, width, band_height))
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(band_image, ALPHA_THRESHOLD)
	var raw_polys := bitmap.opaque_to_polygons(
		Rect2(Vector2.ZERO, Vector2(width, band_height)),
		POLYGON_EPSILON
	)
	var half := Vector2(float(width), float(height)) * 0.5
	var best := PackedVector2Array()
	var best_area := -1.0
	for raw in raw_polys:
		if raw.size() < 3:
			continue
		var local_poly := PackedVector2Array()
		for point in raw:
			local_poly.append(Vector2(point.x, point.y + float(band_y)) - half)
		var area := _polygon_area(local_poly)
		if area > best_area:
			best_area = area
			best = local_poly
	return best


## Mill plot includes a walkable wheat field — block only the tower/base mass.
static func _outline_from_mill_tower(image: Image) -> PackedVector2Array:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return PackedVector2Array()

	var y0 := int(float(height) * 0.40)
	var mask := Image.create(width, height, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0, 0, 0, 0))
	for y in range(y0, height):
		for x in range(width):
			var color := image.get_pixel(x, y)
			if color.a < ALPHA_THRESHOLD:
				continue
			if OcclusionUtils.is_mill_farm_pixel_color(color):
				continue
			if OcclusionUtils.is_building_plot_pixel_color(color):
				continue
			mask.set_pixel(x, y, Color(1, 1, 1, 1))

	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(mask, ALPHA_THRESHOLD)
	var raw_polys := bitmap.opaque_to_polygons(
		Rect2(Vector2.ZERO, Vector2(width, height)),
		POLYGON_EPSILON
	)
	# Merge every solid fragment (tower halves, steps, door stone) into one hull.
	# Largest-only left gaps units could walk through.
	var half := Vector2(float(width), float(height)) * 0.5
	var merged := PackedVector2Array()
	for raw in raw_polys:
		if raw.size() < 3:
			continue
		for point in raw:
			merged.append(Vector2(point.x, point.y) - half)
	if merged.size() < 3:
		return PackedVector2Array()
	return Geometry2D.convex_hull(merged)


static func _largest_tex_centered_poly(
	raw_polys: Array,
	width: int,
	height: int
) -> PackedVector2Array:
	var half := Vector2(float(width), float(height)) * 0.5
	var best := PackedVector2Array()
	var best_area := -1.0
	for raw in raw_polys:
		if raw.size() < 3:
			continue
		var local_poly := PackedVector2Array()
		for point in raw:
			local_poly.append(Vector2(point.x, point.y) - half)
		var area := _polygon_area(local_poly)
		if area > best_area:
			best_area = area
			best = local_poly
	return best


static func _inset_polygon(poly: PackedVector2Array, factor: float) -> PackedVector2Array:
	if poly.size() < 3 or is_equal_approx(factor, 1.0):
		return poly
	var center := polygon_center(poly)
	var result := PackedVector2Array()
	result.resize(poly.size())
	for i in poly.size():
		result[i] = center + (poly[i] - center) * factor
	return result


static func _polygon_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5
