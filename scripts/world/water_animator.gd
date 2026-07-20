extends Node2D

## Legacy per-tile ripples disabled — water visuals are organic lake sprites now.
## Kept so DayNightManager can still call set_night_mode safely.

@export var pulse_strength := 0.4
@export var pulse_speed := 0.9
@export_range(0.05, 1.0, 0.05) var update_interval := 0.12

var _night_mode := false
var _base_pulse_strength := 0.4


func _ready() -> void:
	_base_pulse_strength = pulse_strength


func setup(_ground_layer: TinyTilesMap) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func set_night_mode(is_night: bool) -> void:
	_night_mode = is_night
	pulse_strength = _base_pulse_strength * (0.5 if is_night else 1.0)
