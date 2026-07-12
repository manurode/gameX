class_name AnimatedVfx
extends AnimatedSprite2D


func play_sequence(from_frame: int, to_frame: int, fps: float) -> void:
	sprite_frames = CombatEffects.create_vfx_frames(from_frame, to_frame, fps)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	animation_finished.connect(_on_animation_finished, CONNECT_ONE_SHOT)
	play(&"play")


func _on_animation_finished() -> void:
	queue_free()
