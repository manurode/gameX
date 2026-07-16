class_name OcclusionUtils
extends RefCounted

## Pixel-accurate helpers for environment occlusion / unit silhouettes.

const ALPHA_THRESHOLD := 0.35

static var _image_cache: Dictionary = {}  # RID -> Image


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
	if sprite == null or not sprite.visible or sprite.texture == null:
		return 0.0
	var image := get_texture_image(sprite.texture)
	if image == null:
		return 0.0
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
		return 0.0
	return image.get_pixel(x, y).a


static func sprite_opaque_at(sprite: Sprite2D, world_pos: Vector2, threshold: float = ALPHA_THRESHOLD) -> bool:
	return sprite_alpha_at(sprite, world_pos) >= threshold


static func any_sprite_opaque_at(sprites: Array, world_pos: Vector2, threshold: float = ALPHA_THRESHOLD) -> bool:
	for item in sprites:
		if item is Sprite2D and sprite_opaque_at(item, world_pos, threshold):
			return true
	return false


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
			var covered := any_sprite_opaque_at(occluder_sprites, world_pos)
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
