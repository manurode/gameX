class_name WallTexture
extends RefCounted

# Mediterranean coastal palette: cream stucco body, terracotta cap, stone base.
const MORTAR := Color(0.72, 0.66, 0.58, 1.0)
const STONE_LIGHT := Color(0.93, 0.90, 0.84, 1.0)
const STONE_MID := Color(0.88, 0.84, 0.76, 1.0)
const STONE_DARK := Color(0.78, 0.73, 0.64, 1.0)
const CRENEL_LIGHT := Color(0.82, 0.42, 0.28, 1.0)
const CRENEL_DARK := Color(0.70, 0.34, 0.22, 1.0)
const SHADOW := Color(0.28, 0.24, 0.20, 0.85)
const HIGHLIGHT := Color(0.97, 0.94, 0.88, 1.0)

static var _cache: Dictionary = {}


static func get_texture(width: int = 128, height: int = 64) -> Texture2D:
	var key := "%d_%d" % [width, height]
	if _cache.has(key):
		return _cache[key]
	var texture := ImageTexture.create_from_image(_generate(width, height))
	_cache[key] = texture
	return texture


static func get_segment_spacing() -> float:
	return 80.0


static func _generate(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var body_top := int(height * 0.22)
	var body_bottom := height - int(height * 0.14)
	var shadow_top := height - int(height * 0.12)

	_draw_stone_body(image, width, body_top, body_bottom)
	_draw_crenellations(image, width, body_top)
	_draw_base_shadow(image, width, shadow_top, height)
	_draw_top_highlight(image, width, body_top)

	return image


static func _draw_stone_body(image: Image, width: int, top_y: int, bottom_y: int) -> void:
	var row_height := maxi(6, int((bottom_y - top_y) / 3.5))
	var y := top_y
	var row := 0
	while y < bottom_y:
		var row_bottom := mini(y + row_height - 1, bottom_y - 1)
		var x := 0
		var offset := (row % 2) * int(row_height * 0.6)
		if offset > 0:
			x -= offset
		while x < width:
			var block_w := _block_width(x, row, row_height)
			var block_h := row_bottom - y + 1
			var stone := _stone_color(x, row)
			_fill_rect(image, x + 1, y + 1, block_w - 2, block_h - 2, stone)
			if x > 0:
				_fill_rect(image, x, y, 1, block_h, MORTAR)
			if y > top_y:
				_fill_rect(image, x, y, block_w, 1, MORTAR)
			x += block_w
		y = row_bottom + 1
		row += 1


static func _draw_crenellations(image: Image, width: int, body_top: int) -> void:
	var merlon_w := maxi(10, width / 8)
	var gap_w := maxi(6, merlon_w / 2)
	var crenel_h := body_top
	var x := 0
	var idx := 0
	while x < width:
		var segment_w := merlon_w if idx % 2 == 0 else gap_w
		if idx % 2 == 0:
			var color := CRENEL_LIGHT if idx % 4 == 0 else CRENEL_DARK
			_fill_rect(image, x, 0, segment_w, crenel_h, color)
			_fill_rect(image, x + 1, 1, segment_w - 2, crenel_h - 2, color.lightened(0.04))
			_fill_rect(image, x, crenel_h - 1, segment_w, 1, MORTAR)
		else:
			_fill_rect(image, x, crenel_h - 4, segment_w, 4, MORTAR)
		x += segment_w
		idx += 1


static func _draw_base_shadow(image: Image, width: int, top_y: int, height: int) -> void:
	for y in range(top_y, height):
		var fade := float(y - top_y) / float(height - top_y)
		var alpha := lerpf(0.35, 0.75, fade)
		for x in width:
			var existing := image.get_pixel(x, y)
			if existing.a < 0.01:
				image.set_pixel(x, y, Color(SHADOW.r, SHADOW.g, SHADOW.b, alpha * 0.5))
			else:
				image.set_pixel(x, y, existing.darkened(fade * 0.25))


static func _draw_top_highlight(image: Image, width: int, body_top: int) -> void:
	for x in width:
		if image.get_pixel(x, body_top).a > 0.01:
			image.set_pixel(x, body_top, image.get_pixel(x, body_top).lightened(0.08))


static func _block_width(x: int, row: int, row_height: int) -> int:
	var base := row_height * 2 + (absi(x + row * 17) % 3) * 4
	return clampi(base, row_height + 4, row_height * 3 + 8)


static func _stone_color(x: int, row: int) -> Color:
	var hash_val := absi(x * 13 + row * 29) % 5
	match hash_val:
		0:
			return STONE_LIGHT
		1, 2:
			return STONE_MID
		3:
			return STONE_DARK
		_:
			return STONE_MID.lightened(0.06)


static func _fill_rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	if w <= 0 or h <= 0:
		return
	for py in range(y, y + h):
		if py < 0 or py >= image.get_height():
			continue
		for px in range(x, x + w):
			if px < 0 or px >= image.get_width():
				continue
			image.set_pixel(px, py, color)
