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
	if _building == null or _building.building_state != Building.BuildingState.CONSTRUCTING:
		return

	var ratio := clampf(_building.construction_progress, 0.0, 1.0)
	# Scaffold frame during early construction
	if ratio < 0.85:
		var scaffold_color := Color(0.45, 0.38, 0.28, lerpf(0.5, 0.15, ratio / 0.85))
		var scaffold_rect := Rect2(-BAR_WIDTH * 0.65, -10.0, BAR_WIDTH * 1.3, 14.0)
		draw_rect(scaffold_rect, scaffold_color)
		draw_rect(scaffold_rect, Color(0.3, 0.25, 0.18, 0.6), false, 1.0)

	var bg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT)
	var fg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH * ratio, BAR_HEIGHT)
	draw_rect(bg_rect, Color(0.1, 0.1, 0.12, 0.9))
	draw_rect(fg_rect, Color(0.35, 0.75, 0.95, 0.95))
	draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.55), false, 1.0)


func refresh_from_building() -> void:
	if _building == null:
		visible = false
		return
	var constructing := _building.building_state == Building.BuildingState.CONSTRUCTING
	visible = constructing
	if not constructing:
		_last_drawn_progress = -1.0
		return
	position = _building.sprite_offset + Vector2(0.0, -62.0)
	var progress := _building.construction_progress
	if absf(progress - _last_drawn_progress) < 0.01 and _last_drawn_progress >= 0.0:
		return
	_last_drawn_progress = progress
	queue_redraw()
