extends Node2D

const BAR_WIDTH := 52.0
const BAR_HEIGHT := 5.0
const GARRISON_FONT_SIZE := 11

var _building: Building


func _ready() -> void:
	_building = get_parent() as Building
	z_index = 10
	y_sort_enabled = false
	if _building.has_signal("garrison_changed"):
		_building.garrison_changed.connect(queue_redraw)


func _process(_delta: float) -> void:
	visible = _building.should_show_health_bar()
	position = _building.sprite_offset + Vector2(0.0, -52.0)
	queue_redraw()


func _draw() -> void:
	if _building.max_hp <= 0:
		return

	var ratio := clampf(float(_building.hp) / float(_building.max_hp), 0.0, 1.0)
	var bg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT)
	var fg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH * ratio, BAR_HEIGHT)
	draw_rect(bg_rect, Color(0.12, 0.08, 0.08, 0.88))
	draw_rect(fg_rect, Color(0.88, 0.72, 0.28, 0.95))
	draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.55), false, 1.0)

	if _building.is_selected and _building.can_garrison:
		var garrison_text := "%d/%d" % [_building.get_garrison_count(), _building.garrison_capacity]
		var font := ThemeDB.fallback_font
		var text_width := font.get_string_size(garrison_text, HORIZONTAL_ALIGNMENT_CENTER, -1, GARRISON_FONT_SIZE).x
		var text_pos := Vector2(-text_width * 0.5, BAR_HEIGHT + 2.0)
		draw_string(font, text_pos, garrison_text, HORIZONTAL_ALIGNMENT_LEFT, -1, GARRISON_FONT_SIZE, Color(0.92, 0.95, 0.88, 0.95))
