class_name BuildingDestructionVfx
extends Node2D
## Building collapses into a painterly dust cloud. No fade, no sprite fragmentation.

const DUST_SHEET: Texture2D = preload(
	"res://assets/tilesets/tiny_tiles/VFX/VFX_building_dust.png"
)
const DUST_FRAME_SIZE := 256
const DUST_FRAME_COUNT := 8
const DUST_FPS := 12.0

static var _dust_frames: SpriteFrames

var _pivot: Node2D
var _collapse_sprite: Sprite2D
var _dust_anim: AnimatedSprite2D
var _dust_anim_secondary: AnimatedSprite2D
var _lifetime: float = 1.35


func play_from_building(building: Building) -> void:
	if building == null or building.sprite == null or building.sprite.texture == null:
		queue_free()
		return

	var src: Sprite2D = building.sprite
	z_index = maxi(src.z_index + 8, 28)
	y_sort_enabled = false
	global_position = building.global_position

	var tex: Texture2D = src.texture
	var building_scale: Vector2 = src.scale
	var building_offset: Vector2 = src.offset
	var footprint: Vector2 = building.get_footprint()

	var visual_size := Vector2(
		float(tex.get_width()) * absf(building_scale.x),
		float(tex.get_height()) * absf(building_scale.y)
	)
	var size_factor := clampf(maxf(visual_size.x, visual_size.y) / 220.0, 0.55, 2.6)
	var footprint_factor := clampf(maxf(footprint.x, footprint.y) / 90.0, 0.5, 2.8)
	var effect_scale := maxf(size_factor, footprint_factor * 0.85)
	var visual_center := Vector2(
		building_offset.x * building_scale.x,
		building_offset.y * building_scale.y
	)
	var visual_base := visual_center + Vector2(0.0, visual_size.y * 0.5)

	_spawn_collapse_sprite(src, visual_base)
	_spawn_dust_clouds(visual_size, visual_center, effect_scale)
	_run_collapse_sequence(effect_scale)


func _spawn_collapse_sprite(src: Sprite2D, visual_base: Vector2) -> void:
	_pivot = Node2D.new()
	_pivot.position = visual_base
	_pivot.z_index = 1
	add_child(_pivot)

	_collapse_sprite = Sprite2D.new()
	_collapse_sprite.texture = src.texture
	_collapse_sprite.scale = src.scale
	_collapse_sprite.offset = src.offset
	_collapse_sprite.modulate = src.modulate
	_collapse_sprite.texture_filter = src.texture_filter
	_collapse_sprite.centered = src.centered
	_collapse_sprite.flip_h = src.flip_h
	_collapse_sprite.flip_v = src.flip_v
	_collapse_sprite.position = -visual_base
	_collapse_sprite.rotation = src.rotation
	_pivot.add_child(_collapse_sprite)


func _spawn_dust_clouds(visual_size: Vector2, visual_center: Vector2, effect_scale: float) -> void:
	var frames := _get_dust_frames()
	# Match dust size to the on-screen building sprite.
	var match_scale := maxf(visual_size.x, visual_size.y) / float(DUST_FRAME_SIZE)
	var cloud_scale := Vector2.ONE * clampf(match_scale * 1.2, 0.55, 2.9)

	_dust_anim = AnimatedSprite2D.new()
	_dust_anim.sprite_frames = frames
	_dust_anim.animation = &"play"
	_dust_anim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_dust_anim.scale = cloud_scale
	_dust_anim.position = visual_center + Vector2(0.0, visual_size.y * 0.1)
	_dust_anim.z_index = 3
	add_child(_dust_anim)

	# Soft twin cloud for volume (same art, flipped).
	_dust_anim_secondary = AnimatedSprite2D.new()
	_dust_anim_secondary.sprite_frames = frames
	_dust_anim_secondary.animation = &"play"
	_dust_anim_secondary.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_dust_anim_secondary.scale = cloud_scale * Vector2(0.7, 0.65)
	_dust_anim_secondary.position = visual_center + Vector2(visual_size.x * 0.06, visual_size.y * 0.14)
	_dust_anim_secondary.z_index = 4
	_dust_anim_secondary.modulate = Color(1.0, 0.98, 0.95, 0.75)
	_dust_anim_secondary.flip_h = true
	add_child(_dust_anim_secondary)

	_lifetime = maxf(_lifetime, float(DUST_FRAME_COUNT) / DUST_FPS + 0.35)


func _run_collapse_sequence(effect_scale: float) -> void:
	var base_pos := _collapse_sprite.position

	var shake := create_tween()
	for _i in 6:
		var jitter := Vector2(randf_range(-5.0, 5.0), randf_range(-3.0, 3.0)) * effect_scale
		shake.tween_property(_collapse_sprite, "position", base_pos + jitter, 0.025)
	shake.tween_property(_collapse_sprite, "position", base_pos, 0.03)

	await get_tree().create_timer(0.04).timeout
	if not is_instance_valid(self):
		return

	_dust_anim.play(&"play")
	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(_dust_anim_secondary):
		_dust_anim_secondary.play(&"play")

	# Crush into the ground — full opacity, no fade.
	var crush := create_tween()
	crush.set_parallel(true)
	crush.tween_property(_pivot, "scale", Vector2(1.18, 0.12), 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	crush.tween_property(_pivot, "rotation_degrees", randf_range(-5.0, 5.0), 0.26)

	# Hide under peak dust — never fade the building.
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self):
		return
	_pivot.visible = false

	await get_tree().create_timer(_lifetime).timeout
	if is_instance_valid(self):
		queue_free()


static func _get_dust_frames() -> SpriteFrames:
	if _dust_frames != null:
		return _dust_frames
	var frames := SpriteFrames.new()
	frames.add_animation(&"play")
	frames.set_animation_loop(&"play", false)
	frames.set_animation_speed(&"play", DUST_FPS)
	for i in DUST_FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = DUST_SHEET
		atlas.region = Rect2(i * DUST_FRAME_SIZE, 0, DUST_FRAME_SIZE, DUST_FRAME_SIZE)
		frames.add_frame(&"play", atlas)
	_dust_frames = frames
	return _dust_frames
