class_name OcclusionUtils
extends RefCounted

## Pixel-accurate helpers for environment occlusion / unit silhouettes.

const ALPHA_THRESHOLD := 0.35

static var _image_cache: Dictionary = {}  # RID -> Image
static var _opaque_sample_cache: Dictionary = {}  # String -> PackedVector2Array of texels
## Building textures: L8 mask where white = real structure that can hide units.
static var _structure_mask_cache: Dictionary = {}  # RID -> Image
## Fast 0/1 bytes for structure occlusion sampling (RID -> PackedByteArray).
static var _structure_bytes_cache: Dictionary = {}
static var _structure_size_cache: Dictionary = {}  # RID -> Vector2i


static func get_texture_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var key := texture.get_rid()
	if _image_cache.has(key):
		return _image_cache[key]
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image = image.duplicate()
		image.decompress()
	_image_cache[key] = image
	return image


## White = walls/roof/wood that can hide a unit. Black = plot grass, paths, wheat, bushes.
static func get_structure_occlusion_mask(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var key := texture.get_rid()
	if _structure_mask_cache.has(key):
		return _structure_mask_cache[key]
	_ensure_structure_bytes(texture)
	return _structure_mask_cache.get(key)


static func structure_occludes_texel(texture: Texture2D, x: int, y: int) -> bool:
	if texture == null or x < 0 or y < 0:
		return false
	_ensure_structure_bytes(texture)
	var key := texture.get_rid()
	if not _structure_bytes_cache.has(key):
		return false
	var size: Vector2i = _structure_size_cache[key]
	if x >= size.x or y >= size.y:
		return false
	return (_structure_bytes_cache[key] as PackedByteArray)[y * size.x + x] != 0


static func _ensure_structure_bytes(texture: Texture2D) -> void:
	if texture == null:
		return
	var key := texture.get_rid()
	if _structure_bytes_cache.has(key):
		return
	var src := get_texture_image(texture)
	if src == null:
		return
	var built := _build_structure_occlusion_bytes(src)
	_structure_bytes_cache[key] = built.bytes
	_structure_size_cache[key] = built.size
	_structure_mask_cache[key] = built.image

static func sprite_texel_coords(sprite: Sprite2D, world_pos: Vector2) -> Vector2i:
	if sprite == null or sprite.texture == null:
		return Vector2i(-1, -1)
	var image := get_texture_image(sprite.texture)
	if image == null:
		return Vector2i(-1, -1)
	var size := Vector2(image.get_width(), image.get_height())
	var local := sprite.to_local(world_pos) - sprite.offset
	if sprite.centered:
		local += size * 0.5
	if sprite.flip_h:
		local.x = size.x - local.x
	if sprite.flip_v:
		local.y = size.y - local.y
	var x := int(floor(local.x))
	var y := int(floor(local.y))
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return Vector2i(-1, -1)
	return Vector2i(x, y)


static func sprite_global_rect(sprite: Sprite2D) -> Rect2:
	if sprite == null or not sprite.visible or sprite.texture == null:
		return Rect2()
	var size := sprite.texture.get_size()
	var top_left := sprite.offset
	if sprite.centered:
		top_left -= size * 0.5
	var corners: Array[Vector2] = [
		top_left,
		top_left + Vector2(size.x, 0.0),
		top_left + size,
		top_left + Vector2(0.0, size.y),
	]
	var xf := sprite.get_global_transform()
	var min_v := xf * corners[0]
	var max_v := min_v
	for i in range(1, corners.size()):
		var p := xf * corners[i]
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	return Rect2(min_v, max_v - min_v)


static func animated_sprite_global_rect(sprite: AnimatedSprite2D, require_visible: bool = true) -> Rect2:
	if sprite == null or sprite.sprite_frames == null:
		return Rect2()
	if require_visible and not sprite.visible:
		return Rect2()
	var tex := animated_frame_texture(sprite)
	if tex == null:
		return Rect2()
	var size := tex.get_size()
	var top_left := sprite.offset
	if sprite.centered:
		top_left -= size * 0.5
	var corners: Array[Vector2] = [
		top_left,
		top_left + Vector2(size.x, 0.0),
		top_left + size,
		top_left + Vector2(0.0, size.y),
	]
	var xf := sprite.get_global_transform()
	var min_v := xf * corners[0]
	var max_v := min_v
	for i in range(1, corners.size()):
		var p := xf * corners[i]
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	return Rect2(min_v, max_v - min_v)


static func rects_overlap(a: Rect2, b: Rect2) -> bool:
	if a.size.x <= 0.0 or a.size.y <= 0.0 or b.size.x <= 0.0 or b.size.y <= 0.0:
		return false
	return a.intersects(b)


static func animated_display_pixel_to_world(sprite: AnimatedSprite2D, dx: int, dy: int) -> Vector2:
	var tex := animated_frame_texture(sprite)
	if tex == null:
		return sprite.global_position
	var size := tex.get_size()
	var local := Vector2(float(dx) + 0.5, float(dy) + 0.5)
	if sprite.centered:
		local -= size * 0.5
	local += sprite.offset
	return sprite.to_global(local)


static func sprite_alpha_at(sprite: Sprite2D, world_pos: Vector2) -> float:
	return sprite_color_at(sprite, world_pos).a


static func sprite_color_at(sprite: Sprite2D, world_pos: Vector2) -> Color:
	if sprite == null or not sprite.visible or sprite.texture == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var image := get_texture_image(sprite.texture)
	if image == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var texel := sprite_texel_coords(sprite, world_pos)
	if texel.x < 0:
		return Color(0.0, 0.0, 0.0, 0.0)
	return image.get_pixel(texel.x, texel.y)


static func sprite_opaque_at(sprite: Sprite2D, world_pos: Vector2, threshold: float = ALPHA_THRESHOLD) -> bool:
	return sprite_alpha_at(sprite, world_pos) >= threshold


## Painted wheat / soil on mill.png (and damaged variant) — not tower stone, roof, or sails.
static func is_mill_farm_pixel_color(color: Color) -> bool:
	if color.a < ALPHA_THRESHOLD:
		return false
	var r := color.r
	var g := color.g
	var b := color.b
	var is_wheat := (
		r > 0.55
		and g > 0.42
		and b < 0.55
		and (r + g) > 2.0 * b
		and absf(r - g) < 0.28
	)
	var is_soil := (
		r > 0.20
		and r < 0.60
		and g > 0.10
		and g < 0.42
		and b < 0.30
		and r > g + 0.02
	)
	return is_wheat or is_soil


## Grass / bushes / farm plot baked into building sprites — not walls, roof, or wood.
static func is_building_plot_pixel_color(color: Color) -> bool:
	if color.a < ALPHA_THRESHOLD:
		return false
	if is_mill_farm_pixel_color(color):
		return true
	var r := color.r
	var g := color.g
	var b := color.b
	var mx := maxf(r, maxf(g, b))
	if g > r + 0.04 and g > b + 0.04 and g > 0.14:
		return true
	if (
		b < 0.28
		and r > 0.14
		and g > 0.14
		and absf(r - g) < 0.10
		and (r + g) > 2.6 * b
		and mx < 0.72
	):
		return true
	return false


static func _is_groundish_plot_pixel(color: Color, tex_y: int, height: int) -> bool:
	if color.a < ALPHA_THRESHOLD:
		return false
	if is_building_plot_pixel_color(color):
		return true
	# Upper sprite is never treated as walkable plot (walls, sails, roofs).
	if tex_y < int(float(height) * 0.40):
		return false
	var r := color.r
	var g := color.g
	var b := color.b
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	var sat := ((mx - mn) / mx) if mx > 0.00001 else 0.0
	# Bright plaster walls.
	if mx > 0.78 and sat < 0.25 and b > 0.55:
		return false
	# Terracotta roof.
	if r > 0.65 and g < 0.55 and b < 0.40 and r > g + 0.15:
		return false
	# Dark wood.
	if mx < 0.35 and r >= g and g >= b:
		return false
	if tex_y > int(float(height) * 0.50):
		# Path / border stones.
		if mx >= 0.30 and mx <= 0.75 and sat < 0.20:
			return true
		# Warm dirt / courtyard.
		if (
			r >= g
			and g >= b - 0.02
			and (r - b) > 0.10
			and mx >= 0.35
			and mx <= 0.90
			and sat < 0.45
			and g > 0.28
		):
			return true
	return false


static func _build_structure_occlusion_bytes(src: Image) -> Dictionary:
	var width := src.get_width()
	var height := src.get_height()
	var ground: PackedByteArray = PackedByteArray()
	ground.resize(width * height)
	ground.fill(0)
	var queue: Array[Vector2i] = []
	var y0 := int(float(height) * 0.35)
	var seed_bottom := int(float(height) * 0.70)

	# Prefer raw RGBA bytes when available (much faster than get_pixel per texel).
	var use_raw := src.get_format() == Image.FORMAT_RGBA8
	var raw := src.get_data() if use_raw else PackedByteArray()

	for y in range(y0, height):
		for x in range(width):
			var color := _pixel_at(src, raw, use_raw, x, y, width)
			if is_building_plot_pixel_color(color) or (
				y > seed_bottom and _is_groundish_plot_pixel(color, y, height)
			):
				ground[y * width + x] = 1
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cell.x + dx
				var ny := cell.y + dy
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				var idx := ny * width + nx
				if ground[idx] != 0:
					continue
				var ncolor := _pixel_at(src, raw, use_raw, nx, ny, width)
				if _is_groundish_plot_pixel(ncolor, ny, height):
					ground[idx] = 1
					queue.append(Vector2i(nx, ny))
	# Upper region: only vegetation stays non-occluding (trees beside stables, etc.).
	var y_cut := int(float(height) * 0.45)
	for y in range(0, y_cut):
		for x in range(width):
			var idx := y * width + x
			if ground[idx] == 0:
				continue
			if not is_building_plot_pixel_color(_pixel_at(src, raw, use_raw, x, y, width)):
				ground[idx] = 0

	var bytes := PackedByteArray()
	bytes.resize(width * height)
	var mask := Image.create(width, height, false, Image.FORMAT_L8)
	mask.fill(Color(1, 1, 1, 1))
	for y in range(height):
		for x in range(width):
			var color := _pixel_at(src, raw, use_raw, x, y, width)
			var idx := y * width + x
			if color.a < ALPHA_THRESHOLD or ground[idx] != 0:
				bytes[idx] = 0
				mask.set_pixel(x, y, Color(0, 0, 0, 1))
			else:
				bytes[idx] = 1
				mask.set_pixel(x, y, Color(1, 1, 1, 1))
	return {"bytes": bytes, "size": Vector2i(width, height), "image": mask}


static func _pixel_at(
	src: Image,
	raw: PackedByteArray,
	use_raw: bool,
	x: int,
	y: int,
	width: int
) -> Color:
	if use_raw:
		var i := (y * width + x) * 4
		return Color(
			float(raw[i]) / 255.0,
			float(raw[i + 1]) / 255.0,
			float(raw[i + 2]) / 255.0,
			float(raw[i + 3]) / 255.0
		)
	return src.get_pixel(x, y)


static func _build_structure_occlusion_mask(src: Image) -> Image:
	return _build_structure_occlusion_bytes(src).image


## Opaque occluder pixel that should hide a unit (optional: ignore building plot decor).
static func sprite_occludes_at(
	sprite: Sprite2D,
	world_pos: Vector2,
	threshold: float = ALPHA_THRESHOLD,
	structure_only: bool = false
) -> bool:
	var texel := sprite_texel_coords(sprite, world_pos)
	if texel.x < 0:
		return false
	var image := get_texture_image(sprite.texture)
	if image == null:
		return false
	if image.get_pixel(texel.x, texel.y).a < threshold:
		return false
	if not structure_only:
		return true
	return structure_occludes_texel(sprite.texture, texel.x, texel.y)

static func any_sprite_opaque_at(sprites: Array, world_pos: Vector2, threshold: float = ALPHA_THRESHOLD) -> bool:
	for item in sprites:
		if item is Sprite2D and sprite_opaque_at(item, world_pos, threshold):
			return true
	return false


static func any_sprite_occludes_at(
	sprites: Array,
	world_pos: Vector2,
	threshold: float = ALPHA_THRESHOLD
) -> bool:
	for item in sprites:
		if not (item is Sprite2D):
			continue
		var sprite := item as Sprite2D
		var structure_only := (
			sprite.has_meta(&"occlusion_structure_only")
			and bool(sprite.get_meta(&"occlusion_structure_only"))
		)
		if sprite_occludes_at(sprite, world_pos, threshold, structure_only):
			return true
	return false


## Returns true if any opaque unit pixel is covered by an occluder sprite.
static func is_animated_sprite_occluded(
	unit_sprite: AnimatedSprite2D,
	occluder_sprites: Array,
	sample_step: int = 2
) -> bool:
	return animated_sprite_occlusion_ratio(unit_sprite, occluder_sprites, sample_step) > 0.0


static func _get_opaque_sample_points(texture: Texture2D, unit_img: Image, step: int) -> PackedVector2Array:
	var cache_key := "%d:%d" % [texture.get_rid().get_id(), step]
	if _opaque_sample_cache.has(cache_key):
		return _opaque_sample_cache[cache_key]
	var samples := PackedVector2Array()
	var width := unit_img.get_width()
	var height := unit_img.get_height()
	for ty in range(0, height, step):
		for tx in range(0, width, step):
			if unit_img.get_pixel(tx, ty).a >= ALPHA_THRESHOLD:
				samples.append(Vector2(tx, ty))
	_opaque_sample_cache[cache_key] = samples
	return samples


## Fraction of opaque unit pixels covered by occluders (0..1).
## early_exit_ratio: stop early once coverage is known above/below the threshold.
static func animated_sprite_occlusion_ratio(
	unit_sprite: AnimatedSprite2D,
	occluder_sprites: Array,
	sample_step: int = 2,
	early_exit_ratio: float = -1.0
) -> float:
	if unit_sprite == null or occluder_sprites.is_empty():
		return 0.0
	var frame_tex := animated_frame_texture(unit_sprite)
	if frame_tex == null:
		return 0.0
	var unit_img := get_texture_image(frame_tex)
	if unit_img == null:
		return 0.0

	var width := unit_img.get_width()
	var height := unit_img.get_height()
	var step := maxi(1, sample_step)
	var samples := _get_opaque_sample_points(frame_tex, unit_img, step)
	var opaque_samples := samples.size()
	if opaque_samples <= 0:
		return 0.0

	var covered_samples := 0
	var checked := 0
	for sample in samples:
		var tx := int(sample.x)
		var ty := int(sample.y)
		var dx := (width - 1 - tx) if unit_sprite.flip_h else tx
		var dy := (height - 1 - ty) if unit_sprite.flip_v else ty
		var world_pos := animated_display_pixel_to_world(unit_sprite, dx, dy)
		if any_sprite_occludes_at(occluder_sprites, world_pos):
			covered_samples += 1
		checked += 1
		if early_exit_ratio > 0.0:
			var remaining := opaque_samples - checked
			var max_possible := float(covered_samples + remaining) / float(opaque_samples)
			if max_possible < early_exit_ratio:
				return float(covered_samples) / float(opaque_samples)
			if float(covered_samples) / float(opaque_samples) >= early_exit_ratio:
				return float(covered_samples) / float(opaque_samples)

	return float(covered_samples) / float(opaque_samples)


## Alpha mask in unit *texture* UV space (matches AnimatedSprite2D + flip).
## Covered opaque pixels → white; everything else → transparent.
## Returns null when nothing is visually covered.
static func build_occlusion_mask_image(
	unit_sprite: AnimatedSprite2D,
	occluder_sprites: Array,
	sample_step: int = 1
) -> Image:
	if unit_sprite == null or occluder_sprites.is_empty():
		return null
	var frame_tex := animated_frame_texture(unit_sprite)
	if frame_tex == null:
		return null
	var unit_img := get_texture_image(frame_tex)
	if unit_img == null:
		return null

	var width := unit_img.get_width()
	var height := unit_img.get_height()
	var out := Image.create(width, height, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var step := maxi(1, sample_step)
	var any_hit := false

	for ty in range(0, height, step):
		for tx in range(0, width, step):
			var src_color := unit_img.get_pixel(tx, ty)
			if src_color.a < ALPHA_THRESHOLD:
				continue
			# Texture space → display space (AnimatedSprite2D flip happens at draw time).
			var dx := (width - 1 - tx) if unit_sprite.flip_h else tx
			var dy := (height - 1 - ty) if unit_sprite.flip_v else ty
			var world_pos := animated_display_pixel_to_world(unit_sprite, dx, dy)
			if not any_sprite_occludes_at(occluder_sprites, world_pos):
				continue
			any_hit = true
			for oy in range(step):
				for ox in range(step):
					var qx := tx + ox
					var qy := ty + oy
					if qx < width and qy < height:
						out.set_pixel(qx, qy, Color.WHITE)

	return out if any_hit else null


## Composite in unit display-pixel space:
## - opaque pixels covered by occluders → silhouette_color
## - other opaque pixels → original frame color
## Returns null when nothing is visually covered (caller should show the normal sprite).
static func build_occlusion_composite_image(
	unit_sprite: AnimatedSprite2D,
	occluder_sprites: Array,
	silhouette_color: Color,
	sample_step: int = 1
) -> Image:
	if unit_sprite == null or occluder_sprites.is_empty():
		return null
	var frame_tex := animated_frame_texture(unit_sprite)
	if frame_tex == null:
		return null
	var unit_img := get_texture_image(frame_tex)
	if unit_img == null:
		return null

	var width := unit_img.get_width()
	var height := unit_img.get_height()
	var out := Image.create(width, height, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var step := maxi(1, sample_step)
	var any_hit := false

	for dy in range(0, height, step):
		for dx in range(0, width, step):
			var tex_x := (width - 1 - dx) if unit_sprite.flip_h else dx
			var tex_y := (height - 1 - dy) if unit_sprite.flip_v else dy
			var src_color := unit_img.get_pixel(tex_x, tex_y)
			if src_color.a < ALPHA_THRESHOLD:
				continue
			var world_pos := animated_display_pixel_to_world(unit_sprite, dx, dy)
			var covered := any_sprite_occludes_at(occluder_sprites, world_pos)
			if covered:
				any_hit = true
			var paint := silhouette_color if covered else src_color
			for oy in range(step):
				for ox in range(step):
					var qx := dx + ox
					var qy := dy + oy
					if qx < width and qy < height:
						out.set_pixel(qx, qy, paint)

	return out if any_hit else null


static func animated_frame_texture(sprite: AnimatedSprite2D) -> Texture2D:
	if sprite == null or sprite.sprite_frames == null:
		return null
	var anim := sprite.animation
	if not sprite.sprite_frames.has_animation(anim):
		return null
	return sprite.sprite_frames.get_frame_texture(anim, sprite.frame)
