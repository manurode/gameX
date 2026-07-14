extends Node

const RIPPLE_A_PATH := "res://assets/tilesets/tiny_tiles/Environment/Terrain/Water/env_water_ripple_a.png"
const RIPPLE_B_PATH := "res://assets/tilesets/tiny_tiles/Environment/Terrain/Water/env_water_ripple_b.png"

@export var pulse_strength := 0.4
@export var pulse_speed := 0.9
@export_range(0.05, 1.0, 0.05) var update_interval := 0.12

var _ground_layer: TinyTilesMap
var _ripple_a_overlays: Array[Sprite2D] = []
var _ripple_b_overlays: Array[Sprite2D] = []
var _time := 0.0
var _update_accumulator := 0.0
var _night_mode := false
var _base_pulse_strength := 0.4


func _ready() -> void:
	_base_pulse_strength = pulse_strength


func setup(ground_layer: TinyTilesMap) -> void:
	_clear_overlays()
	_ground_layer = ground_layer
	_create_water_overlays()


func set_night_mode(is_night: bool) -> void:
	_night_mode = is_night
	pulse_strength = _base_pulse_strength * (0.5 if is_night else 1.0)


func _create_water_overlays() -> void:
	if _ground_layer == null:
		return

	var ripple_a: Texture2D = load(RIPPLE_A_PATH)
	var ripple_b: Texture2D = load(RIPPLE_B_PATH)
	for cell in _ground_layer.get_water_cells():
		var pos := _ground_layer.map_to_local(cell)
		var sprite_a := _make_ripple_sprite(ripple_a, pos)
		var sprite_b := _make_ripple_sprite(ripple_b, pos)
		add_child(sprite_a)
		add_child(sprite_b)
		_ripple_a_overlays.append(sprite_a)
		_ripple_b_overlays.append(sprite_b)


func _make_ripple_sprite(texture: Texture2D, pos: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.position = pos
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	return sprite


func _process(delta: float) -> void:
	_time += delta
	_update_accumulator += delta
	if _update_accumulator < update_interval:
		return
	_update_accumulator = 0.0

	var blend := 0.5 + sin(_time * pulse_speed) * pulse_strength
	var alpha_peak := 0.35 if _night_mode else 0.5
	var alpha_a := alpha_peak * (1.0 - blend)
	var alpha_b := alpha_peak * blend

	for overlay in _ripple_a_overlays:
		if is_instance_valid(overlay):
			overlay.modulate.a = alpha_a
	for overlay in _ripple_b_overlays:
		if is_instance_valid(overlay):
			overlay.modulate.a = alpha_b


func _clear_overlays() -> void:
	_ripple_a_overlays.clear()
	_ripple_b_overlays.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
