class_name DayNightManager
extends Node

enum CyclePhase { DAY, NIGHT }

signal cycle_changed(phase: CyclePhase)

const DAY_COLOR := Color(1.0, 1.0, 1.0)
const NIGHT_COLOR := Color(0.28, 0.32, 0.55)
const TRANSITION_SECONDS := 1.5

var current_phase: CyclePhase = CyclePhase.DAY

var _modulate: CanvasModulate
var _water_animator: Node
var _transition_tween: Tween


func _ready() -> void:
	add_to_group("day_night_manager")


func setup(modulate: CanvasModulate, water_animator: Node = null) -> void:
	_modulate = modulate
	_water_animator = water_animator
	if _modulate != null:
		_modulate.color = DAY_COLOR


func toggle_cycle() -> void:
	if current_phase == CyclePhase.DAY:
		set_phase(CyclePhase.NIGHT)
	else:
		set_phase(CyclePhase.DAY)


func set_phase(phase: CyclePhase) -> void:
	if current_phase == phase:
		return

	current_phase = phase
	_animate_visuals(phase == CyclePhase.NIGHT)
	_update_unit_shadows(phase == CyclePhase.NIGHT)
	if _water_animator != null and _water_animator.has_method("set_night_mode"):
		_water_animator.call("set_night_mode", phase == CyclePhase.NIGHT)
	cycle_changed.emit(current_phase)


func is_night() -> bool:
	return current_phase == CyclePhase.NIGHT


func _animate_visuals(is_night: bool) -> void:
	if _modulate == null:
		return

	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()

	var target_color := NIGHT_COLOR if is_night else DAY_COLOR
	_transition_tween = create_tween()
	_transition_tween.tween_property(_modulate, "color", target_color, TRANSITION_SECONDS)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _update_unit_shadows(is_night: bool) -> void:
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit:
			(node as Unit).apply_cycle_visuals(is_night)
