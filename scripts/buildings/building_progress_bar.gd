extends Node2D

const BAR_WIDTH := 52.0
const BAR_HEIGHT := 6.0

var _building: Building
var _last_drawn_progress := -1.0


func _ready() -> void:
	_building = get_parent() as Building
	z_index = 11
	y_sort_enabled = false
	visible = false
	set_process(false)


func _draw() -> void:
	if _building == null:
		return

	var ratio := _current_progress()
	if ratio < 0.0:
		return

	var bg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT)
	var fg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH * ratio, BAR_HEIGHT)
	draw_rect(bg_rect, Color(0.1, 0.1, 0.12, 0.9))
	var fill := Color(0.35, 0.75, 0.95, 0.95)
	if _building.repair_in_progress:
		fill = Color(0.45, 0.85, 0.55, 0.95)
	draw_rect(fg_rect, fill)
	draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.55), false, 1.0)


func refresh_from_building() -> void:
	if _building == null:
		visible = false
		return
	var active := _is_progress_active()
	visible = active
	if not active:
		_last_drawn_progress = -1.0
		return
	position = _building.sprite_offset + Vector2(0.0, -62.0)
	var progress := _current_progress()
	if absf(progress - _last_drawn_progress) < 0.01 and _last_drawn_progress >= 0.0:
		return
	_last_drawn_progress = progress
	queue_redraw()


func _is_progress_active() -> bool:
	if _building == null:
		return false
	return (
		_building.building_state == Building.BuildingState.CONSTRUCTING
		or _building.repair_in_progress
	)


func _current_progress() -> float:
	if _building == null:
		return -1.0
	if _building.building_state == Building.BuildingState.CONSTRUCTING:
		return clampf(_building.construction_progress, 0.0, 1.0)
	if _building.repair_in_progress:
		return clampf(_building.get_repair_progress_ratio(), 0.0, 1.0)
	return -1.0
