extends Node

@export var pulse_strength := 0.12
@export var pulse_speed := 1.8

var _ground_layer: TinyTilesMap
var _overlays: Array[Sprite2D] = []
var _time := 0.0
var _night_mode := false
var _base_pulse_strength := 0.12


func _ready() -> void:
	_base_pulse_strength = pulse_strength


func setup(ground_layer: TinyTilesMap) -> void:
	_ground_layer = ground_layer
	_create_water_overlays()


func set_night_mode(is_night: bool) -> void:
	_night_mode = is_night
	pulse_strength = _base_pulse_strength * (0.45 if is_night else 1.0)


func _create_water_overlays() -> void:
	if _ground_layer == null:
		return

	for cell in _ground_layer.get_water_cells():
		var sprite := Sprite2D.new()
		sprite.texture = load(
			"res://assets/tilesets/tiny_tiles/Environment/Terrain/Main/env_terrain_water.png"
		)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.position = _ground_layer.map_to_local(cell)
		sprite.modulate = Color(1.0, 1.0, 1.0, 0.35)
		add_child(sprite)
		_overlays.append(sprite)


func _process(delta: float) -> void:
	_time += delta
	var shimmer := 0.85 + sin(_time * pulse_speed) * pulse_strength
	var alpha_base := 0.28 if _night_mode else 0.38
	for overlay in _overlays:
		if is_instance_valid(overlay):
			overlay.modulate = Color(
				shimmer,
				shimmer + 0.05,
				1.0,
				alpha_base + sin(_time * pulse_speed + 0.5) * 0.08
			)
