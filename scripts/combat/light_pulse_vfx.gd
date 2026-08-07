extends Node2D
class_name LightPulseVfx

## Expanding golden ring used by Alba's Fulgor hero power.

var _radius: float = 140.0
var _lifetime: float = 0.45
var _age: float = 0.0
var _color := Color(1.0, 0.92, 0.55, 0.85)


func play(radius: float, color: Color = Color(1.0, 0.92, 0.55, 0.85), lifetime: float = 0.45) -> void:
	_radius = maxf(24.0, radius)
	_color = color
	_lifetime = maxf(0.15, lifetime)
	_age = 0.0
	z_as_relative = false
	z_index = 24
	y_sort_enabled = false
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	var ease := 1.0 - (1.0 - t) * (1.0 - t)
	var current_r := lerpf(_radius * 0.18, _radius, ease)
	var alpha := lerpf(_color.a, 0.0, t)
	var fill := Color(_color.r, _color.g, _color.b, alpha * 0.22)
	var rim := Color(_color.r, _color.g, _color.b, alpha)
	draw_circle(Vector2.ZERO, current_r, fill)
	draw_arc(Vector2.ZERO, current_r, 0.0, TAU, 48, rim, 3.0, true)
	draw_arc(Vector2.ZERO, current_r * 0.55, 0.0, TAU, 36, Color(1, 1, 0.9, alpha * 0.55), 2.0, true)
