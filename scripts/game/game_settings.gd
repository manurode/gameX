class_name GameSettingsData
extends Node

enum MapSizePreset { LARGE, MEDIUM, SMALL }
enum Difficulty { BEGINNER, ADVANCED, EXPERT }

const MAP_SIZE_LARGE := Vector2i(64, 64)
const MAP_SIZE_MEDIUM := Vector2i(32, 32)
const MAP_SIZE_SMALL := Vector2i(16, 16)

## Window size used when playing from the editor (F5), so Maximized never sticks.
const EDITOR_PLAY_SIZE := Vector2i(1280, 720)

var map_size_preset: MapSizePreset = MapSizePreset.MEDIUM
## Default is BEGINNER until the player starts a run on another setting (persisted).
## Combat baseline matches ADVANCED; BEGINNER eases waves, EXPERT doubles them.
var difficulty: Difficulty = Difficulty.BEGINNER


func _ready() -> void:
	# Wait a frame so Game embedding can attach before we touch the window.
	_apply_window_mode_after_embed.call_deferred()


func _apply_window_mode_after_embed() -> void:
	await get_tree().process_frame
	_apply_window_mode()


func _apply_window_mode() -> void:
	# Embedded Game dock owns the window. Touching mode/size breaks the debug bar.
	if Engine.is_embedded_in_editor() or OS.has_feature("embedded_in_editor"):
		return

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)

	# Exported game: fill the work area (above the taskbar).
	if OS.has_feature("template"):
		DisplayServer.window_set_position(usable.position)
		DisplayServer.window_set_size(usable.size)
		return

	# Editor binary / F5: always a normal centered window.
	# Returning early used to leave ProjectSettings Maximized intact — that also
	# disables embedding on the next play until the project is reloaded.
	var target := Vector2i(
		mini(EDITOR_PLAY_SIZE.x, usable.size.x - 48),
		mini(EDITOR_PLAY_SIZE.y, usable.size.y - 48)
	).max(Vector2i(640, 360))
	DisplayServer.window_set_size(target)
	DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)


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


func get_difficulty_label(diff: Difficulty = difficulty) -> String:
	match diff:
		Difficulty.BEGINNER:
			return "Principiante"
		Difficulty.EXPERT:
			return "Experto"
		_:
			return "Avanzado"


## Wave size multiplier applied after base count + army pressure.
func get_enemy_count_mult(diff: Difficulty = difficulty) -> float:
	match diff:
		Difficulty.BEGINNER:
			return 0.5
		Difficulty.EXPERT:
			return 2.0
		_:
			return 1.0


## When false, enemies keep base HP/damage every night (no +4%/night climb).
func enemy_stats_scale_with_night(diff: Difficulty = difficulty) -> bool:
	return diff != Difficulty.BEGINNER


## Meta-fragment payout multiplier at end of run.
func get_fragment_reward_mult(diff: Difficulty = difficulty) -> float:
	match diff:
		Difficulty.ADVANCED:
			return 3.0
		Difficulty.EXPERT:
			return 4.0
		_:
			return 1.0
