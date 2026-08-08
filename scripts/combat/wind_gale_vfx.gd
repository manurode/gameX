extends Node2D
class_name WindGaleVfx

## Expanding hollow ring of rising dust + leaves. Center stays empty so the caster stays visible.

const ISO_Y := 0.58
const LEAF_COUNT := 40
const DUST_COUNT := 56
const PUFF_COUNT := 28
const TEX_VERSION := 3

static var _tex_version: int = 0
static var _leaf_texture: Texture2D
static var _mote_texture: Texture2D
static var _puff_texture: Texture2D

var _radius: float = 140.0
var _lifetime: float = 0.85
var _age: float = 0.0
var _leaves: Array[Sprite2D] = []
var _leaf_data: Array[Dictionary] = []
var _dust: Array[Sprite2D] = []
var _dust_data: Array[Dictionary] = []
var _puffs: Array[Sprite2D] = []
var _puff_data: Array[Dictionary] = []


func play(radius: float, lifetime: float = 0.85) -> void:
	if _tex_version != TEX_VERSION:
		_leaf_texture = null
		_mote_texture = null
		_puff_texture = null
		_tex_version = TEX_VERSION
	_radius = maxf(48.0, radius)
	_lifetime = maxf(0.45, lifetime)
	_age = 0.0
	z_as_relative = false
	z_index = 12
	y_sort_enabled = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_spawn_ring_particles()
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	var expand := 1.0 - pow(1.0 - t, 2.2)
	# Dust stays visible through mid-cast, then fades.
	var fade := 1.0 - smoothstep(0.55, 1.0, t)
	# Rise curve: kicks off the ground quickly, then drifts up.
	var rise := smoothstep(0.0, 0.45, t) * lerpf(1.0, 1.35, t)

	_update_leaves(expand, fade, rise, delta)
	_update_dust(expand, fade, rise, delta)
	_update_puffs(expand, fade, rise, delta)
	queue_redraw()

	if _age >= _lifetime:
		queue_free()


func _draw() -> void:
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	var expand := 1.0 - pow(1.0 - t, 2.2)
	var r := lerpf(_radius * 0.08, _radius, expand)
	var alpha := lerpf(0.4, 0.0, smoothstep(0.4, 1.0, t))
	_draw_ellipse_arc(r, Color(0.72, 0.58, 0.36, alpha * 0.75), 2.4)
	_draw_ellipse_arc(r * 0.9, Color(0.65, 0.52, 0.32, alpha * 0.4), 1.4)


func _spawn_ring_particles() -> void:
	_leaves.clear()
	_leaf_data.clear()
	_dust.clear()
	_dust_data.clear()
	_puffs.clear()
	_puff_data.clear()

	var leaf_tex := _get_leaf_texture()
	for i in LEAF_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = leaf_tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.centered = true
		sprite.z_index = 4
		match i % 4:
			0:
				sprite.modulate = Color(0.78, 0.58, 0.22, 1.0)
			1:
				sprite.modulate = Color(0.55, 0.64, 0.28, 1.0)
			2:
				sprite.modulate = Color(0.68, 0.4, 0.18, 1.0)
			_:
				sprite.modulate = Color(0.84, 0.72, 0.36, 1.0)
		add_child(sprite)
		_leaves.append(sprite)
		_leaf_data.append({
			"angle": TAU * float(i) / float(LEAF_COUNT) + randf_range(-0.1, 0.1),
			"spin": randf_range(-14.0, 14.0),
			"orbit": randf_range(2.0, 4.0),
			"ring_t": randf_range(0.88, 1.08),
			"lift": randf_range(18.0, 42.0),
			"scale": randf_range(1.1, 1.7),
			"phase": randf() * TAU,
			"base_a": randf_range(0.85, 1.0),
		})

	var mote_tex := _get_mote_texture()
	for i in DUST_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = mote_tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.centered = true
		sprite.z_index = 3
		# Warm dirt tones so motes read on green grass.
		sprite.modulate = Color(
			randf_range(0.7, 0.88),
			randf_range(0.55, 0.7),
			randf_range(0.32, 0.45),
			1.0
		)
		add_child(sprite)
		_dust.append(sprite)
		_dust_data.append({
			"angle": TAU * float(i) / float(DUST_COUNT) + randf_range(-0.12, 0.12),
			"orbit": randf_range(1.8, 4.2),
			"ring_t": randf_range(0.82, 1.12),
			"lift": randf_range(22.0, 55.0),
			"scale": randf_range(1.4, 2.6),
			"phase": randf() * TAU,
			"base_a": randf_range(0.65, 0.9),
			"stagger": randf_range(0.0, 0.18),
		})

	var puff_tex := _get_puff_texture()
	for i in PUFF_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = puff_tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.centered = true
		sprite.z_index = 2
		sprite.modulate = Color(
			randf_range(0.78, 0.9),
			randf_range(0.62, 0.74),
			randf_range(0.4, 0.52),
			1.0
		)
		add_child(sprite)
		_puffs.append(sprite)
		_puff_data.append({
			"angle": TAU * float(i) / float(PUFF_COUNT) + randf_range(-0.15, 0.15),
			"orbit": randf_range(1.2, 2.8),
			"ring_t": randf_range(0.9, 1.06),
			"lift": randf_range(14.0, 38.0),
			"scale": randf_range(2.2, 3.8),
			"phase": randf() * TAU,
			"base_a": randf_range(0.45, 0.7),
			"stagger": randf_range(0.0, 0.12),
		})


func _update_leaves(expand: float, fade: float, rise: float, delta: float) -> void:
	for i in _leaves.size():
		var sprite := _leaves[i]
		var data: Dictionary = _leaf_data[i]
		if not is_instance_valid(sprite):
			continue
		data["angle"] = float(data["angle"]) + float(data["orbit"]) * delta
		_leaf_data[i] = data
		var r := _radius * expand * float(data["ring_t"])
		var wobble := sin(_age * 12.0 + float(data["phase"])) * 4.0
		var pos := _iso_point(float(data["angle"]), r)
		pos.y -= float(data["lift"]) * rise + wobble
		sprite.position = pos
		sprite.rotation += float(data["spin"]) * delta
		sprite.scale = Vector2.ONE * float(data["scale"]) * lerpf(0.8, 1.15, expand)
		sprite.modulate.a = fade * float(data["base_a"])


func _update_dust(expand: float, fade: float, rise: float, delta: float) -> void:
	for i in _dust.size():
		var sprite := _dust[i]
		var data: Dictionary = _dust_data[i]
		if not is_instance_valid(sprite):
			continue
		data["angle"] = float(data["angle"]) + float(data["orbit"]) * delta
		_dust_data[i] = data
		var local_t := clampf((_age / _lifetime) - float(data["stagger"]), 0.0, 1.0)
		var local_rise := smoothstep(0.0, 0.5, local_t) * lerpf(1.0, 1.4, local_t)
		var r := _radius * expand * float(data["ring_t"])
		var bob := sin(_age * 14.0 + float(data["phase"])) * 2.5
		var pos := _iso_point(float(data["angle"]), r)
		# Clear upward lift off the grass.
		pos.y -= float(data["lift"]) * local_rise * rise + bob
		sprite.position = pos
		var grow := lerpf(0.7, 1.25, local_rise)
		sprite.scale = Vector2.ONE * float(data["scale"]) * grow
		# Peak opacity while rising, then ease out with global fade.
		var rise_a := lerpf(0.35, 1.0, smoothstep(0.0, 0.25, local_t))
		sprite.modulate.a = fade * float(data["base_a"]) * rise_a


func _update_puffs(expand: float, fade: float, rise: float, delta: float) -> void:
	for i in _puffs.size():
		var sprite := _puffs[i]
		var data: Dictionary = _puff_data[i]
		if not is_instance_valid(sprite):
			continue
		data["angle"] = float(data["angle"]) + float(data["orbit"]) * delta
		_puff_data[i] = data
		var local_t := clampf((_age / _lifetime) - float(data["stagger"]), 0.0, 1.0)
		var local_rise := smoothstep(0.0, 0.55, local_t)
		var r := _radius * expand * float(data["ring_t"])
		var pos := _iso_point(float(data["angle"]), r)
		pos.y -= float(data["lift"]) * local_rise * rise
		sprite.position = pos
		# Puffs bloom as they leave the ground.
		var sx := float(data["scale"]) * lerpf(0.55, 1.35, local_rise)
		var sy := float(data["scale"]) * lerpf(0.4, 1.55, local_rise)
		sprite.scale = Vector2(sx, sy)
		var bloom := lerpf(0.25, 1.0, smoothstep(0.0, 0.3, local_t))
		sprite.modulate.a = fade * float(data["base_a"]) * bloom


func _iso_point(angle: float, radius: float) -> Vector2:
	return Vector2(cos(angle) * radius, sin(angle) * radius * ISO_Y)


func _ellipse_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(_iso_point(a, radius))
	return pts


func _draw_ellipse_arc(radius: float, color: Color, width: float) -> void:
	var pts := _ellipse_points(radius, 56)
	for i in pts.size():
		draw_line(pts[i], pts[(i + 1) % pts.size()], color, width, true)


static func _get_leaf_texture() -> Texture2D:
	if _leaf_texture != null:
		return _leaf_texture
	var size := 12
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in size:
			var nx := (x - 5.5) / 5.5
			var ny := (y - 5.5) / 5.5
			var leaf := absf(nx) + absf(ny) * 1.3
			if leaf <= 1.0:
				image.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - leaf) * 1.7, 0.0, 1.0)))
	_leaf_texture = ImageTexture.create_from_image(image)
	return _leaf_texture


static func _get_mote_texture() -> Texture2D:
	if _mote_texture != null:
		return _mote_texture
	var size := 8
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := (size - 1) * 0.5
	for y in size:
		for x in size:
			var dist := Vector2(x - center, y - center).length() / maxf(center, 0.01)
			if dist <= 1.0:
				image.set_pixel(x, y, Color(1, 1, 1, pow(1.0 - dist, 1.2) * 0.95))
	_mote_texture = ImageTexture.create_from_image(image)
	return _mote_texture


static func _get_puff_texture() -> Texture2D:
	if _puff_texture != null:
		return _puff_texture
	# Soft dusty lobe — larger and denser so it reads as lifted dirt on grass.
	var size := 28
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var cx := (size - 1) * 0.5
	var cy := (size - 1) * 0.55
	for y in size:
		for x in size:
			var nx := (x - cx) / (cx * 0.95)
			var ny := (y - cy) / (cy * 0.85)
			# Two overlapping lobes for a bit of volume.
			var d1 := sqrt(nx * nx + ny * ny)
			var d2 := sqrt((nx - 0.25) * (nx - 0.25) + (ny + 0.15) * (ny + 0.15) * 1.1)
			var d := minf(d1, d2 * 1.05)
			if d <= 1.0:
				var a := pow(1.0 - d, 1.35) * 0.85
				image.set_pixel(x, y, Color(1, 1, 1, a))
	_puff_texture = ImageTexture.create_from_image(image)
	return _puff_texture
