extends Camera2D

const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const PAN_SPEED := 500.0
const ZOOM_STEP := 0.1

func _ready() -> void:
	position = Vector2(640, 360)

func _process(delta: float) -> void:
	_handle_pan(delta)

func _handle_pan(delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		direction.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		direction.x += 1.0

	if direction != Vector2.ZERO:
		position += direction.normalized() * PAN_SPEED * delta / zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return

		var delta_zoom := 0.0
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			delta_zoom = -ZOOM_STEP
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			delta_zoom = ZOOM_STEP

		if delta_zoom != 0.0:
			var new_zoom := clampf(zoom.x + delta_zoom, MIN_ZOOM, MAX_ZOOM)
			zoom = Vector2(new_zoom, new_zoom)
