class_name CombatEffects
extends RefCounted

const VFX_SHEET: Texture2D = preload(
	"res://assets/tilesets/tiny_tiles/VFX/VFX_death_explosion.png"
)
const VFX_SCENE: PackedScene = preload("res://scenes/combat/animated_vfx.tscn")
const FRAME_SIZE := 80

static var _frames_cache: Dictionary = {}


static func spawn_melee_impact(parent: Node, world_position: Vector2) -> void:
	_spawn_vfx(parent, world_position, 1, 3, 14.0, 24)


static func spawn_ranged_impact(parent: Node, world_position: Vector2) -> void:
	_spawn_vfx(parent, world_position, 2, 3, 16.0, 24)


static func spawn_death_burst(parent: Node, world_position: Vector2) -> void:
	_spawn_vfx(parent, world_position, 0, 4, 9.0, 26)


static func create_vfx_frames(from_frame: int, to_frame: int, fps: float) -> SpriteFrames:
	var cache_key := "%d:%d:%.1f" % [from_frame, to_frame, fps]
	if _frames_cache.has(cache_key):
		return _frames_cache[cache_key]

	var frames := SpriteFrames.new()
	frames.add_animation(&"play")
	frames.set_animation_loop(&"play", false)
	frames.set_animation_speed(&"play", fps)

	for frame_idx in range(from_frame, to_frame + 1):
		var atlas := AtlasTexture.new()
		atlas.atlas = VFX_SHEET
		atlas.region = Rect2(frame_idx * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		frames.add_frame(&"play", atlas)

	_frames_cache[cache_key] = frames
	return frames


static func _spawn_vfx(
	parent: Node,
	world_position: Vector2,
	from_frame: int,
	to_frame: int,
	fps: float,
	z_index_value: int
) -> void:
	if parent == null:
		return

	var vfx: AnimatedVfx = VFX_SCENE.instantiate()
	vfx.z_index = z_index_value
	vfx.y_sort_enabled = false
	parent.add_child(vfx)
	vfx.global_position = world_position
	vfx.play_sequence(from_frame, to_frame, fps)
