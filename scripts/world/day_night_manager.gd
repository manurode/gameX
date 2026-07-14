class_name DayNightManager
extends Node

enum CyclePhase { DAY, DUSK, NIGHT, DAWN }

signal cycle_changed(phase: CyclePhase)
signal phase_time_changed(seconds_remaining: float)
signal cycle_started(cycle_number: int)

const DAY_COLOR := Color(1.0, 1.0, 1.0)
const NIGHT_COLOR := Color(0.28, 0.32, 0.55)
const TRANSITION_SECONDS := 1.5

var current_phase: CyclePhase = CyclePhase.DAY
var seconds_remaining: float = BalanceConfig.PHASE_DURATIONS.day
var cycle_number: int = 1
var automatic_cycle: bool = true

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
	reset_cycle()


func _process(delta: float) -> void:
	if not automatic_cycle or delta <= 0.0:
		return
	advance_time(delta)


func advance_time(delta: float) -> void:
	var remaining_delta := delta
	while remaining_delta > 0.0:
		if remaining_delta < seconds_remaining:
			seconds_remaining -= remaining_delta
			remaining_delta = 0.0
		else:
			remaining_delta -= seconds_remaining
			_advance_phase()
	phase_time_changed.emit(seconds_remaining)


func reset_cycle() -> void:
	cycle_number = 1
	current_phase = CyclePhase.DAY
	seconds_remaining = _get_phase_duration(current_phase)
	_animate_visuals(false)
	_update_unit_shadows(false)
	cycle_changed.emit(current_phase)
	cycle_started.emit(cycle_number)
	phase_time_changed.emit(seconds_remaining)


func toggle_cycle() -> void:
	_advance_phase()


func set_phase(phase: CyclePhase) -> void:
	current_phase = phase
	seconds_remaining = _get_phase_duration(phase)
	_animate_visuals(phase == CyclePhase.NIGHT)
	_update_unit_shadows(phase == CyclePhase.NIGHT)
	if _water_animator != null and _water_animator.has_method("set_night_mode"):
		_water_animator.call("set_night_mode", phase == CyclePhase.NIGHT)
	cycle_changed.emit(current_phase)


func is_night() -> bool:
	return current_phase == CyclePhase.NIGHT


func is_construction_allowed() -> bool:
	return current_phase != CyclePhase.NIGHT


func get_phase_display_name() -> String:
	match current_phase:
		CyclePhase.DAY:
			return "Día"
		CyclePhase.DUSK:
			return "Atardecer"
		CyclePhase.NIGHT:
			return "Noche"
		CyclePhase.DAWN:
			return "Amanecer"
	return ""


func _advance_phase() -> void:
	var next_phase := CyclePhase.DAY
	match current_phase:
		CyclePhase.DAY:
			next_phase = CyclePhase.DUSK
		CyclePhase.DUSK:
			next_phase = CyclePhase.NIGHT
		CyclePhase.NIGHT:
			next_phase = CyclePhase.DAWN
		CyclePhase.DAWN:
			cycle_number += 1
			next_phase = CyclePhase.DAY
	set_phase(next_phase)
	if next_phase == CyclePhase.DAY:
		cycle_started.emit(cycle_number)


func _get_phase_duration(phase: CyclePhase) -> float:
	match phase:
		CyclePhase.DAY:
			return BalanceConfig.PHASE_DURATIONS.day
		CyclePhase.DUSK:
			return BalanceConfig.PHASE_DURATIONS.dusk
		CyclePhase.NIGHT:
			return BalanceConfig.PHASE_DURATIONS.night
		CyclePhase.DAWN:
			return BalanceConfig.PHASE_DURATIONS.dawn
	return 1.0


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
