class_name GameStateManager
extends Node

signal game_over
signal victory
signal run_ended(victory: bool, nights_survived: int, fragments_earned: int)

var _game_over: bool = false
var _victory: bool = false
var _town_center: Building
var _day_night: DayNightManager
var _rewards_granted: bool = false


func setup(town_center: Building, day_night: DayNightManager = null) -> void:
	_town_center = town_center
	_day_night = day_night
	if _town_center != null and not _town_center.destroyed.is_connected(_on_town_center_destroyed):
		_town_center.destroyed.connect(_on_town_center_destroyed)
	if _day_night != null and not _day_night.victory_reached.is_connected(_on_victory_reached):
		_day_night.victory_reached.connect(_on_victory_reached)


func is_game_over() -> bool:
	return _game_over


func is_victory() -> bool:
	return _victory


func is_run_finished() -> bool:
	return _game_over or _victory


func _on_town_center_destroyed() -> void:
	if _game_over or _victory:
		return
	_game_over = true
	_finish_run(false)


func _on_victory_reached() -> void:
	if _game_over or _victory:
		return
	_victory = true
	_finish_run(true)


func _finish_run(won: bool) -> void:
	var nights := 0
	if _day_night != null:
		nights = _day_night.nights_survived
		_day_night.automatic_cycle = false
	var reward := 0
	if not _rewards_granted:
		_rewards_granted = true
		reward = MetaProgression.award_run_rewards(nights, won)
	get_tree().paused = true
	if won:
		victory.emit()
	else:
		game_over.emit()
	run_ended.emit(won, nights, reward)
