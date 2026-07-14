class_name GameSettingsData
extends Node

enum MapSizePreset { LARGE, MEDIUM, SMALL }

const MAP_SIZE_LARGE := Vector2i(64, 64)
const MAP_SIZE_MEDIUM := Vector2i(32, 32)
const MAP_SIZE_SMALL := Vector2i(16, 16)

var map_size_preset: MapSizePreset = MapSizePreset.LARGE


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
