extends Node2D

const BAR_WIDTH := 52.0
const BAR_HEIGHT := 5.0
const GARRISON_FONT_SIZE := 11

var _building: Building
var _was_visible := false


func _ready() -> void:
	_building = get_parent() as Building
	z_index = 10
	y_sort_enabled = false
	visible = false
	set_process(false)
	if _building != null:
		if _building.has_signal("garrison_changed"):
			_building.garrison_changed.connect(_on_visual_state_changed)
		if _building.has_signal("health_changed"):
			_building.health_changed.connect(_on_health_changed)
		_refresh_visibility()


func _exit_tree() -> void:
	if _building == null or not is_instance_valid(_building):
		return
	if _building.garrison_changed.is_connected(_on_visual_state_changed):
		_building.garrison_changed.disconnect(_on_visual_state_changed)
	if _building.health_changed.is_connected(_on_health_changed):
		_building.health_changed.disconnect(_on_health_changed)


func _process(_delta: float) -> void:
	if not _building.should_show_health_bar():
		_set_bar_visible(false)
		set_process(false)
		return
	position = _building.sprite_offset + Vector2(0.0, -52.0)


func _on_health_changed(_current_hp: int, _max_hp: int) -> void:
	_refresh_visibility()
	if visible:
		queue_redraw()


func _on_visual_state_changed() -> void:
	_refresh_visibility()
	if visible:
		queue_redraw()


func notify_selection_changed() -> void:
	_refresh_visibility()


func _refresh_visibility() -> void:
	if _building == null:
		_set_bar_visible(false)
		set_process(false)
		return
	var show_bar := _building.should_show_health_bar()
	_set_bar_visible(show_bar)
	if show_bar:
		position = _building.sprite_offset + Vector2(0.0, -52.0)
		queue_redraw()
		set_process(
			not _building.is_selected
			and _building.building_state != Building.BuildingState.CONSTRUCTING
			and not _building.repair_in_progress
		)
	else:
		set_process(false)


func _set_bar_visible(value: bool) -> void:
	if _was_visible == value and visible == value:
		return
	_was_visible = value
	visible = value


func _draw() -> void:
	if _building == null or _building.max_hp <= 0:
		return

	var ratio := clampf(float(_building.hp) / float(_building.max_hp), 0.0, 1.0)
	var bg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT)
	var fg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH * ratio, BAR_HEIGHT)
	draw_rect(bg_rect, Color(0.12, 0.08, 0.08, 0.88))
	draw_rect(fg_rect, Color(0.35, 0.75, 0.95, 0.95))
	draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.55), false, 1.0)

	if _building.is_selected and _building.can_garrison:
		var garrison_text := "%d/%d" % [_building.get_garrison_count(), _building.garrison_capacity]
		var font := ThemeDB.fallback_font
		var text_width := font.get_string_size(garrison_text, HORIZONTAL_ALIGNMENT_CENTER, -1, GARRISON_FONT_SIZE).x
		var ascent := font.get_ascent(GARRISON_FONT_SIZE)
		var text_height := font.get_height(GARRISON_FONT_SIZE)
		var pad_x := 3.0
		var pad_y := 1.5
		var chip_w := text_width + pad_x * 2.0
		var chip_h := text_height + pad_y * 2.0
		var chip_y := -2.0 - chip_h
		var chip_rect := Rect2(-chip_w * 0.5, chip_y, chip_w, chip_h)
		draw_rect(chip_rect, Color(0.10, 0.08, 0.06, 0.90))
		draw_rect(chip_rect, Color(0.0, 0.0, 0.0, 0.55), false, 1.0)
		var text_pos := Vector2(-text_width * 0.5, chip_y + pad_y + ascent)
		draw_string(
			font,
			text_pos,
			garrison_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			GARRISON_FONT_SIZE,
			Color(0.95, 0.94, 0.88, 1.0)
		)
