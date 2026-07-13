class_name GameStateManager
extends Node

signal game_over

var _game_over: bool = false
var _town_center: Building


func setup(town_center: Building) -> void:
	_town_center = town_center
	if _town_center != null and not _town_center.destroyed.is_connected(_on_town_center_destroyed):
		_town_center.destroyed.connect(_on_town_center_destroyed)


func is_game_over() -> bool:
	return _game_over


func _on_town_center_destroyed() -> void:
	if _game_over:
		return
	_game_over = true
	get_tree().paused = true
	game_over.emit()
