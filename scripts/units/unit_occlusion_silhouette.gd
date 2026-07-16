class_name UnitOcclusionSilhouette
extends Node

## Pixel-accurate silhouette when a unit is visually covered by environment props.
## Only paints pixels that overlap opaque texels of trees/buildings/hills — never units.

const CHECK_INTERVAL := 0.05
const SILHOUETTE_COLOR := Color(0.12, 0.28, 0.48, 0.82)
const Y_SLOP := 8.0
## 1 = exact; 2 is cheaper and still tight for 80px unit frames.
const SAMPLE_STEP := 1

var _unit: Unit
var _layer: Node2D
var _silhouette: Sprite2D
var _silhouette_texture: ImageTexture
var _check_timer := 0.0
var _occluded := false


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


func set_active(active: bool) -> void:
	set_process(active)
	if not active:
		_set_occluded(false)


func _exit_tree() -> void:
	if is_instance_valid(_silhouette):
		_silhouette.queue_free()
	_silhouette = null


func _process(delta: float) -> void:
	if _unit == null or not is_instance_valid(_unit) or _silhouette == null:
		return
	if _unit.garrisoned_building != null or _unit.hp <= 0:
		_set_occluded(false)
		return

	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_INTERVAL
		_rebuild()

	if _occluded:
		_sync_transform()


func _set_occluded(value: bool) -> void:
	_occluded = value
	if _silhouette != null:
		_silhouette.visible = value


func _rebuild() -> void:
	var sprite := _unit.animated_sprite
	if sprite == null or not sprite.visible:
		_set_occluded(false)
		return

	var unit_rect := OcclusionUtils.animated_sprite_global_rect(sprite)
	if unit_rect.size == Vector2.ZERO:
		_set_occluded(false)
		return

	var occluders := _collect_overlapping_front_occluders(unit_rect)
	if occluders.is_empty():
		_set_occluded(false)
		return

	var image := OcclusionUtils.build_occlusion_silhouette_image(
		sprite,
		occluders,
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
	# Image is already in display-pixel space (flip baked into sampling).
	_silhouette.flip_h = false
	_silhouette.flip_v = false
