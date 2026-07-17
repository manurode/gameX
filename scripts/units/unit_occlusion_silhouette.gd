class_name UnitOcclusionSilhouette
extends Node

## When a unit is covered by environment props, mirrors its AnimatedSprite2D onto a
## high-z overlay as a flat blue silhouette. Animation stays live; occlusion is only
## a yes/no check (full-body tint avoids edge bleed from partial masks).
##
## Triggers when an occluder's sprite draws in front of the unit (Y-sort), or when the
## unit is deep inside a forest stand. Leaf-fringe / edge touches do not count.

const OCCLUDER_REFRESH_INTERVAL := 0.12
const SILHOUETTE_COLOR := Color(0.12, 0.28, 0.48, 0.82)
const SAMPLE_STEP := 4
## Ignore tiny fringe overlaps (single leaves at the forest edge).
const MIN_COVER_RATIO := 0.16
const SHADER_PATH := "res://shaders/unit_occlusion_silhouette.gdshader"
const VIEWPORT_MARGIN := 96.0

static var _shared_material: ShaderMaterial

var _unit: Unit
var _layer: Node2D
var _silhouette: AnimatedSprite2D
var _material: ShaderMaterial
var _occluder_timer := 0.0
var _cached_occluders: Array = []
var _occluded := false
var _frame_connected := false
var _hid_unit_sprite := false
var _occlusion_dirty := true
var _last_anim: StringName = &""
var _last_frame := -1
var _last_flip_h := false
var _last_flip_v := false
var _last_check_pos := Vector2.INF
var _sample_budget_timer := 0.0


func setup(unit: Unit, silhouette_layer: Node2D) -> void:
	_unit = unit
	_layer = silhouette_layer
	# Stagger expensive checks across units.
	_occluder_timer = randf() * OCCLUDER_REFRESH_INTERVAL
	_sample_budget_timer = randf() * OCCLUDER_REFRESH_INTERVAL

	if _shared_material == null:
		var shader := load(SHADER_PATH) as Shader
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = shader
		_shared_material.set_shader_parameter("silhouette_color", SILHOUETTE_COLOR)
		_shared_material.set_shader_parameter("alpha_threshold", OcclusionUtils.ALPHA_THRESHOLD)
	_material = _shared_material

	_silhouette = AnimatedSprite2D.new()
	_silhouette.name = "UnitSilhouette"
	_silhouette.centered = true
	_silhouette.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_silhouette.z_as_relative = false
	_silhouette.z_index = 20
	_silhouette.visible = false
	_silhouette.y_sort_enabled = false
	_silhouette.material = _material
	# Frame is mirrored from the unit; do not advance independently.
	_silhouette.speed_scale = 0.0
	_layer.add_child(_silhouette)

	if _unit.animated_sprite != null and not _frame_connected:
		_unit.animated_sprite.frame_changed.connect(_on_unit_frame_changed)
		_frame_connected = true


func set_active(active: bool) -> void:
	set_process(active)
	if not active:
		_cached_occluders.clear()
		_set_occluded(false)


func _exit_tree() -> void:
	_restore_unit_sprite()
	if _frame_connected and _unit != null and is_instance_valid(_unit) and _unit.animated_sprite != null:
		if _unit.animated_sprite.frame_changed.is_connected(_on_unit_frame_changed):
			_unit.animated_sprite.frame_changed.disconnect(_on_unit_frame_changed)
	_frame_connected = false
	if is_instance_valid(_silhouette):
		_silhouette.queue_free()
	_silhouette = null


func _on_unit_frame_changed() -> void:
	# Keep the silhouette animation in sync cheaply; defer pixel sampling to the timer.
	_occlusion_dirty = true
	if _occluded:
		_sync_sprite_from_unit()


func _process(delta: float) -> void:
	if _unit == null or not is_instance_valid(_unit) or _silhouette == null:
		return
	if _unit.garrisoned_building != null or _unit.hp <= 0:
		_cached_occluders.clear()
		_set_occluded(false)
		return

	if not _is_unit_roughly_on_screen():
		if _occluded:
			_set_occluded(false)
		_cached_occluders.clear()
		return

	_occluder_timer -= delta
	if _occluder_timer <= 0.0:
		_occluder_timer = OCCLUDER_REFRESH_INTERVAL
		_refresh_occluder_cache()
		_occlusion_dirty = true

	var pos := _unit.global_position
	if pos.distance_squared_to(_last_check_pos) > 4.0:
		_last_check_pos = pos
		_occlusion_dirty = true

	if _cached_occluders.is_empty():
		_set_occluded(false)
		return

	_sync_sprite_from_unit()

	_sample_budget_timer -= delta
	if _occlusion_dirty and _sample_budget_timer <= 0.0:
		_sample_budget_timer = OCCLUDER_REFRESH_INTERVAL
		_update_occlusion_if_needed()


func _is_unit_roughly_on_screen() -> bool:
	var viewport := _unit.get_viewport()
	if viewport == null:
		return true
	var canvas_xform := viewport.get_canvas_transform()
	var screen_pos := canvas_xform * _unit.global_position
	var rect := viewport.get_visible_rect().grow(VIEWPORT_MARGIN)
	return rect.has_point(screen_pos)


func _set_occluded(value: bool) -> void:
	_occluded = value
	if _silhouette != null:
		_silhouette.visible = value
	if value:
		_hide_unit_sprite()
	else:
		_restore_unit_sprite()


func _hide_unit_sprite() -> void:
	if _hid_unit_sprite or _unit == null or _unit.animated_sprite == null:
		return
	if _unit.garrisoned_building != null:
		return
	_unit.animated_sprite.visible = false
	_hid_unit_sprite = true


func _restore_unit_sprite() -> void:
	if not _hid_unit_sprite or _unit == null or not is_instance_valid(_unit):
		_hid_unit_sprite = false
		return
	if _unit.animated_sprite != null and _unit.garrisoned_building == null and _unit.hp > 0:
		_unit.animated_sprite.visible = true
	_hid_unit_sprite = false


func _refresh_occluder_cache() -> void:
	var sprite := _unit.animated_sprite
	if sprite == null:
		_cached_occluders.clear()
		return
	var unit_rect := OcclusionUtils.animated_sprite_global_rect(sprite, false)
	if unit_rect.size == Vector2.ZERO:
		_cached_occluders.clear()
		return
	_cached_occluders = _collect_overlapping_front_occluders(unit_rect)


func _sync_sprite_from_unit() -> void:
	var src := _unit.animated_sprite
	if src == null or _silhouette == null:
		return

	if _silhouette.sprite_frames != src.sprite_frames:
		_silhouette.sprite_frames = src.sprite_frames
		_occlusion_dirty = true

	var anim := src.animation
	var anim_changed := anim != _last_anim
	if anim_changed and src.sprite_frames != null and src.sprite_frames.has_animation(anim):
		_silhouette.play(anim)
		_silhouette.pause()
		_last_anim = anim
		_occlusion_dirty = true

	var frame_changed := src.frame != _last_frame or anim_changed
	if frame_changed:
		_silhouette.frame = src.frame
		_last_frame = src.frame
		_occlusion_dirty = true
	elif _silhouette.frame != src.frame:
		_silhouette.frame = src.frame

	if src.flip_h != _last_flip_h or src.flip_v != _last_flip_v:
		_last_flip_h = src.flip_h
		_last_flip_v = src.flip_v
		_occlusion_dirty = true

	_silhouette.flip_h = src.flip_h
	_silhouette.flip_v = src.flip_v
	_silhouette.global_position = src.global_position
	_silhouette.offset = src.offset
	_silhouette.scale = src.scale
	_silhouette.rotation = src.rotation
	_silhouette.centered = src.centered


func _update_occlusion_if_needed() -> void:
	if not _occlusion_dirty:
		return

	var sprite := _unit.animated_sprite
	if sprite == null or _cached_occluders.is_empty():
		_set_occluded(false)
		return

	var live_occluders: Array = []
	for item in _cached_occluders:
		if is_instance_valid(item) and item is Sprite2D:
			live_occluders.append(item)
	_cached_occluders = live_occluders
	if _cached_occluders.is_empty():
		_set_occluded(false)
		return

	_occlusion_dirty = false
	var ratio := OcclusionUtils.animated_sprite_occlusion_ratio(
		sprite,
		_cached_occluders,
		SAMPLE_STEP,
		MIN_COVER_RATIO
	)
	_set_occluded(ratio >= MIN_COVER_RATIO)


func _collect_overlapping_front_occluders(unit_rect: Rect2) -> Array:
	var result: Array = []
	var unit_y := _unit.global_position.y
	var unit_pos := _unit.global_position
	for node in _unit.get_tree().get_nodes_in_group("occlusion_props"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var occluder := node as Node2D
		# Cheap distance reject before expensive sprite work.
		if occluder.global_position.distance_squared_to(unit_pos) > 220.0 * 220.0:
			continue
		# Sort key is node position (resources may bias theirs for canopy edges).
		var draws_in_front := occluder.global_position.y > unit_y
		var forest_interior := false
		if not draws_in_front and occluder.has_method("is_forest_interior"):
			forest_interior = bool(occluder.call("is_forest_interior", unit_pos))
		if not draws_in_front and not forest_interior:
			continue
		if not occluder.has_method("get_occlusion_sprites"):
			continue
		var sprites: Array = occluder.call("get_occlusion_sprites")
		for item in sprites:
			if not (item is Sprite2D):
				continue
			var occ_sprite := item as Sprite2D
			var occ_rect := OcclusionUtils.sprite_global_rect(occ_sprite)
			if OcclusionUtils.rects_overlap(unit_rect, occ_rect):
				result.append(occ_sprite)
	return result
