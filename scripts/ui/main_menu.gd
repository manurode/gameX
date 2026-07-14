extends Control

const GAME_SCENE := "res://scenes/main.tscn"


func _on_large_pressed() -> void:
	_start_game(GameSettings.MapSizePreset.LARGE)


func _on_medium_pressed() -> void:
	_start_game(GameSettings.MapSizePreset.MEDIUM)


func _on_small_pressed() -> void:
	_start_game(GameSettings.MapSizePreset.SMALL)


func _start_game(preset: GameSettingsData.MapSizePreset) -> void:
	GameSettings.map_size_preset = preset
	get_tree().change_scene_to_file(GAME_SCENE)
