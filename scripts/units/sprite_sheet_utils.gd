class_name SpriteSheetUtils
extends RefCounted

static var _frames_cache: Dictionary = {}


static func _sheet_id(sheet: Texture2D) -> int:
	return sheet.get_rid().get_id() if sheet != null else 0


static func build_character_frames(
	idle_sheet: Texture2D,
	walk_up_sheet: Texture2D,
	walk_down_sheet: Texture2D,
	attack_up_sheet: Texture2D = null,
	attack_down_sheet: Texture2D = null,
	death_up_sheet: Texture2D = null,
	death_down_sheet: Texture2D = null,
	frame_size: int = 80,
	idle_fps: float = 6.0,
	walk_fps: float = 10.0,
	attack_fps: float = 12.0,
	death_fps: float = 7.0,
	death_frame_count: int = -1,
	gather_sheet: Texture2D = null,
	gather_fps: float = 9.0
) -> SpriteFrames:
	var cache_key := "%d_%d_%d_%d_%d_%d_%d_%d_%d_%.1f_%.1f_%.1f_%.1f_%d_%.1f" % [
		_sheet_id(idle_sheet),
		_sheet_id(walk_up_sheet),
		_sheet_id(walk_down_sheet),
		_sheet_id(attack_up_sheet),
		_sheet_id(attack_down_sheet),
		_sheet_id(death_up_sheet),
		_sheet_id(death_down_sheet),
		_sheet_id(gather_sheet),
		frame_size,
		idle_fps,
		walk_fps,
		attack_fps,
		death_fps,
		death_frame_count,
		gather_fps,
	]
	if _frames_cache.has(cache_key):
		return _frames_cache[cache_key]

	var frames := SpriteFrames.new()

	if idle_sheet != null:
		_add_horizontal_frames(frames, &"idle", idle_sheet, frame_size, idle_fps, true)
	if walk_up_sheet != null:
		_add_horizontal_frames(frames, &"walk_up", walk_up_sheet, frame_size, walk_fps, true)
	if walk_down_sheet != null:
		_add_horizontal_frames(frames, &"walk_down", walk_down_sheet, frame_size, walk_fps, true)
	if attack_up_sheet != null:
		_add_horizontal_frames(frames, &"attack_up", attack_up_sheet, frame_size, attack_fps, false)
	if attack_down_sheet != null:
		_add_horizontal_frames(frames, &"attack_down", attack_down_sheet, frame_size, attack_fps, false)
	if death_up_sheet != null:
		_add_horizontal_frames(
			frames,
			&"death_up",
			death_up_sheet,
			frame_size,
			death_fps,
			false,
			death_frame_count
		)
	if death_down_sheet != null:
		_add_horizontal_frames(
			frames,
			&"death_down",
			death_down_sheet,
			frame_size,
			death_fps,
			false,
			death_frame_count
		)
	if gather_sheet != null:
		_add_horizontal_frames(frames, &"gather", gather_sheet, frame_size, gather_fps, true)

	if not frames.has_animation(&"idle"):
		if frames.has_animation(&"walk_down"):
			frames.add_animation(&"idle")
			var source_anim := &"walk_down"
			for frame_idx in frames.get_frame_count(source_anim):
				frames.add_frame(
					&"idle",
					frames.get_frame_texture(source_anim, frame_idx),
					frames.get_frame_duration(source_anim, frame_idx)
				)
			frames.set_animation_speed(&"idle", idle_fps)
			frames.set_animation_loop(&"idle", true)

	_frames_cache[cache_key] = frames
	return frames


static func _add_horizontal_frames(
	sprite_frames: SpriteFrames,
	animation_name: StringName,
	sheet: Texture2D,
	frame_size: int,
	fps: float,
	loop: bool,
	max_frames: int = -1
) -> void:
	if sheet == null or frame_size <= 0:
		return

	var frame_count := sheet.get_width() / frame_size
	if frame_count <= 0:
		return
	if max_frames > 0:
		frame_count = mini(frame_count, max_frames)

	sprite_frames.add_animation(animation_name)
	sprite_frames.set_animation_loop(animation_name, loop)
	sprite_frames.set_animation_speed(animation_name, fps)

	for frame_idx in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(frame_idx * frame_size, 0, frame_size, frame_size)
		sprite_frames.add_frame(animation_name, atlas)
