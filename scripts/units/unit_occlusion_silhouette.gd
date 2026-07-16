class_name UnitOcclusionSilhouette
extends Node

## Pixel-accurate silhouette when a unit is visually covered by environment props.
## While occluded, replaces the unit sprite with a per-frame composite
## (silhouette on covered pixels, original color on uncovered ones) so animation stays in sync.

const OCCLUDER_REFRESH_INTERVAL := 0.05
const SILHOUETTE_COLOR := Color(0.12, 0.28, 0.48, 0.82)
const Y_SLOP := 8.0
const SAMPLE_STEP := 1

var _unit: Unit
var _layer: Node2D
var _silhouette: Sprite2D
var _silhouette_texture: ImageTexture
var _occluder_timer := 0.0
var _cached_occluders: Array = []
var _occluded := false
var _frame_connected := false
var _hid_unit_sprite := false


func setup(unit: Unit, silhouette_layer: Node2D) -> void:
	_unit = unit
	_layer = silhouette_layer
	_silhouette_texture = ImageTexture.new()

	_silhouette = Sprite2D.new()
	_silhouette.name = "UnitSilhouette"
	_silhouette.texture = _silhouette_texture
	_silhouette.centered = true
	_silhouette.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_silhouette.z_as_relative = false
	_silhouette.z_index = 20
	_silhouette.visible = false
	_silhouette.y_sort_enabled = false
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
	if _occluded or not _cached_occluders.is_empty():
		_rebuild_silhouette()


func _process(delta: float) -> void:
	if _unit == null or not is_instance_valid(_unit) or _silhouette == null:
		return
	if _unit.garrisoned_building != null or _unit.hp <= 0:
		_cached_occluders.clear()
		_set_occluded(false)
		return

	_occluder_timer -= delta
	if _occluder_timer <= 0.0:
		_occluder_timer = OCCLUDER_REFRESH_INTERVAL
		_refresh_occluder_cache()

	if _cached_occluders.is_empty():
		_set_occluded(false)
		return

	_rebuild_silhouette()


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
	# Sprite may be hidden while we own the composite; still use it for sampling.
	if sprite == null:
		_cached_occluders.clear()
		return
	var unit_rect := OcclusionUtils.animated_sprite_global_rect(sprite, false)
	if unit_rect.size == Vector2.ZERO:
		_cached_occluders.clear()
		return
	_cached_occluders = _collect_overlapping_front_occluders(unit_rect)


func _rebuild_silhouette() -> void:
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

	var image := OcclusionUtils.build_occlusion_composite_image(
		sprite,
		_cached_occluders,
		SILHOUETTE_COLOR,
		SAMPLE_STEP
	)
	if image == null:
		_set_occluded(false)
		return

	_silhouette_texture.set_image(image)
	_sync_transform()
	_set_occluded(true)


func _collect_overlapping_front_occluders(unit_rect: Rect2) -> Array:
	var result: Array = []
	var unit_y := _unit.global_position.y
	for node in _unit.get_tree().get_nodes_in_group("occlusion_props"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var occluder := node as Node2D
		if occluder.global_position.y + Y_SLOP <= unit_y:
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


func _sync_transform() -> void:
	var src := _unit.animated_sprite
	if src == null or _silhouette == null:
		return
	_silhouette.global_position = src.global_position
	_silhouette.offset = src.offset
	_silhouette.scale = src.scale
	_silhouette.rotation = src.rotation
	_silhouette.centered = src.centered
	_silhouette.flip_h = false
	_silhouette.flip_v = false
