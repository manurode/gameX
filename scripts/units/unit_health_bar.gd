extends Node2D

const BAR_WIDTH := 38.0
const BAR_HEIGHT := 5.0

var _unit: Unit


func _ready() -> void:
	_unit = get_parent() as Unit
	z_index = 10
	y_sort_enabled = false


func _process(_delta: float) -> void:
	visible = _unit.should_show_health_bar()
	position = _unit.sprite_offset + Vector2(0.0, -42.0)
	queue_redraw()


func _draw() -> void:
	if _unit.max_hp <= 0:
		return

	var ratio := clampf(float(_unit.hp) / float(_unit.max_hp), 0.0, 1.0)
	var bg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT)
	var fg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH * ratio, BAR_HEIGHT)
	draw_rect(bg_rect, Color(0.12, 0.08, 0.08, 0.88))
	draw_rect(fg_rect, Color(0.28, 0.88, 0.38, 0.95))
	draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.55), false, 1.0)
