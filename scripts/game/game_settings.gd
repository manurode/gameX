class_name GameSettingsData
extends Node

enum MapSizePreset { LARGE, MEDIUM, SMALL }

const MAP_SIZE_LARGE := Vector2i(64, 64)
const MAP_SIZE_MEDIUM := Vector2i(32, 32)
const MAP_SIZE_SMALL := Vector2i(16, 16)

var map_size_preset: MapSizePreset = MapSizePreset.MEDIUM


func _ready() -> void:
	# Maximized windowed: title bar + close button, stays above the Windows taskbar.
	# Avoids borderless/fullscreen covering the HUD without an in-game quit menu.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func get_map_size() -> Vector2i:
	match map_size_preset:
		MapSizePreset.MEDIUM:
			return MAP_SIZE_MEDIUM
		MapSizePreset.SMALL:
			return MAP_SIZE_SMALL
		_:
			return MAP_SIZE_LARGE


func get_preset_label(preset: MapSizePreset) -> String:
	match preset:
		MapSizePreset.MEDIUM:
			return "Mediano (32×32)"
		MapSizePreset.SMALL:
			return "Pequeño (16×16)"
		_:
			return "Grande (64×64)"
