extends Control

## Keeps the world SubViewport at native window pixels so enlarging
## the window renders more detail instead of stretching a 1280x620 buffer.

@onready var _world_view: SubViewportContainer = $Layout/WorldView
@onready var _sub_viewport: SubViewport = $Layout/WorldView/SubViewport


func _ready() -> void:
	_sub_viewport.msaa_2d = Viewport.MSAA_4X
	_world_view.resized.connect(_sync_world_viewport_size)
	get_viewport().size_changed.connect(_sync_world_viewport_size)
	call_deferred("_sync_world_viewport_size")


func _sync_world_viewport_size() -> void:
	if _world_view == null or _sub_viewport == null:
		return

	var container_size := _world_view.size
	if container_size.x < 2.0 or container_size.y < 2.0:
		return

	# With canvas_items stretch, Control sizes are logical; multiply by the
	# stretch scale so the SubViewport renders at real screen pixels.
	var stretch_scale := get_viewport().get_stretch_transform().get_scale()
	var pixel_size := Vector2i((container_size * stretch_scale).round())
	pixel_size = pixel_size.max(Vector2i(2, 2))

	if _sub_viewport.size != pixel_size:
		_sub_viewport.size = pixel_size
