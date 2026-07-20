class_name DayNightManager
extends Node

enum CyclePhase { DAY, DUSK, NIGHT, DAWN }

signal cycle_changed(phase: CyclePhase)
signal phase_time_changed(seconds_remaining: float)
signal cycle_started(cycle_number: int)
signal night_survived(nights_survived: int)
signal victory_reached

const DAY_COLOR := Color(1.0, 1.0, 1.0)
const DUSK_COLOR := Color(0.70, 0.52, 0.46)
const DAWN_COLOR := Color(0.82, 0.74, 0.68)
## Cool oppressive ambient — local PointLight2Ds carve readable pockets.
const NIGHT_COLOR := Color(0.12, 0.13, 0.22)
const FOG_NIGHT_COLOR := Color(0.07, 0.08, 0.14)
const TRANSITION_SECONDS := 1.5
const LIGHT_TEXTURE_SIZE := 256

var current_phase: CyclePhase = CyclePhase.DAY
var seconds_remaining: float = BalanceConfig.PHASE_DURATIONS.day
var cycle_number: int = 1
var nights_survived: int = 0
var automatic_cycle: bool = true
var night_duration_multiplier: float = 1.0
var use_fog_visuals: bool = false

var _modulate: CanvasModulate
var _water_animator: Node
var _transition_tween: Tween
var _run_finished: bool = false

static var _shared_light_texture: Texture2D


func _ready() -> void:
	add_to_group("day_night_manager")


static func get_shared_light_texture() -> Texture2D:
	if _shared_light_texture != null:
		return _shared_light_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.45),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = LIGHT_TEXTURE_SIZE
	texture.height = LIGHT_TEXTURE_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.repeat = GradientTexture2D.REPEAT_NONE
	_shared_light_texture = texture
	return _shared_light_texture


func setup(modulate: CanvasModulate, water_animator: Node = null) -> void:
	_modulate = modulate
	_water_animator = water_animator
	if _modulate != null:
		_modulate.color = DAY_COLOR
	reset_cycle()


func _process(delta: float) -> void:
	if not automatic_cycle or _run_finished or delta <= 0.0:
		return
	advance_time(delta)


func advance_time(delta: float) -> void:
	if _run_finished:
		return
	var remaining_delta := delta
	while remaining_delta > 0.0 and not _run_finished:
		if remaining_delta < seconds_remaining:
			seconds_remaining -= remaining_delta
			remaining_delta = 0.0
		else:
			remaining_delta -= seconds_remaining
			_advance_phase()
	phase_time_changed.emit(seconds_remaining)


func reset_cycle() -> void:
	cycle_number = 1
	nights_survived = 0
	_run_finished = false
	night_duration_multiplier = 1.0
	use_fog_visuals = false
	current_phase = CyclePhase.DAY
	seconds_remaining = _get_phase_duration(current_phase)
	_animate_visuals()
	_update_cycle_entity_visuals(false)
	cycle_changed.emit(current_phase)
	cycle_started.emit(cycle_number)
	phase_time_changed.emit(seconds_remaining)


func toggle_cycle() -> void:
	_advance_phase()


func set_phase(phase: CyclePhase) -> void:
	current_phase = phase
	seconds_remaining = _get_phase_duration(phase)
	var keep_daylight := _should_keep_daylight()
	var is_night := phase == CyclePhase.NIGHT and not keep_daylight
	_animate_visuals()
	_update_cycle_entity_visuals(is_night)
	if _water_animator != null and _water_animator.has_method("set_night_mode"):
		_water_animator.call("set_night_mode", is_night)
	cycle_changed.emit(current_phase)


func is_night() -> bool:
	return current_phase == CyclePhase.NIGHT


func should_apply_night_visuals() -> bool:
	return is_night() and not _should_keep_daylight()


func _should_keep_daylight() -> bool:
	var boons := get_tree().get_first_node_in_group("run_boon_manager")
	return boons is RunBoonManager and (boons as RunBoonManager).should_keep_daylight()


func is_construction_allowed() -> bool:
	return current_phase != CyclePhase.NIGHT


func is_run_finished() -> bool:
	return _run_finished


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
	if _run_finished:
		return

	var next_phase := CyclePhase.DAY
	match current_phase:
		CyclePhase.DAY:
			next_phase = CyclePhase.DUSK
		CyclePhase.DUSK:
			next_phase = CyclePhase.NIGHT
		CyclePhase.NIGHT:
			nights_survived += 1
			night_survived.emit(nights_survived)
			next_phase = CyclePhase.DAWN
			night_duration_multiplier = 1.0
			use_fog_visuals = false
		CyclePhase.DAWN:
			if nights_survived >= BalanceConfig.WIN_NIGHTS:
				_run_finished = true
				automatic_cycle = false
				victory_reached.emit()
				return
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
			return BalanceConfig.PHASE_DURATIONS.night * night_duration_multiplier
		CyclePhase.DAWN:
			return BalanceConfig.PHASE_DURATIONS.dawn
	return 1.0


func _animate_visuals() -> void:
	if _modulate == null:
		return

	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()

	var target_color := DAY_COLOR
	if not _should_keep_daylight():
		match current_phase:
			CyclePhase.NIGHT:
				target_color = FOG_NIGHT_COLOR if use_fog_visuals else NIGHT_COLOR
			CyclePhase.DUSK:
				target_color = DUSK_COLOR
			CyclePhase.DAWN:
				target_color = DAWN_COLOR
			_:
				target_color = DAY_COLOR
	_transition_tween = create_tween()
	_transition_tween.tween_property(_modulate, "color", target_color, TRANSITION_SECONDS)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _update_cycle_entity_visuals(is_night: bool) -> void:
	for node in get_tree().get_nodes_in_group("units"):
		if node is Unit:
			(node as Unit).apply_cycle_visuals(is_night)
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Building:
			(node as Building).apply_cycle_visuals(is_night)
