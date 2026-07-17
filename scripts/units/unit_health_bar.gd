extends Node2D

const BAR_WIDTH := 38.0
const BAR_HEIGHT := 5.0

var _unit: Unit
var _was_visible := false


func _ready() -> void:
	_unit = get_parent() as Unit
	z_index = 10
	y_sort_enabled = false
	visible = false
	set_process(false)
	if _unit != null:
		_unit.health_changed.connect(_on_health_changed)
		_refresh_visibility()


func _exit_tree() -> void:
	if _unit != null and is_instance_valid(_unit) and _unit.health_changed.is_connected(_on_health_changed):
		_unit.health_changed.disconnect(_on_health_changed)


func _process(_delta: float) -> void:
	# Only runs while the bar should stay visible after damage / selection.
	if not _unit.should_show_health_bar():
		_set_bar_visible(false)
		set_process(false)
		return
	position = _unit.sprite_offset + Vector2(0.0, -42.0)


func _on_health_changed(_current_hp: int, _max_hp: int) -> void:
	_refresh_visibility()
	if visible:
		queue_redraw()


func notify_selection_changed() -> void:
	_refresh_visibility()


func _refresh_visibility() -> void:
	if _unit == null:
		_set_bar_visible(false)
		set_process(false)
		return
	var show_bar := _unit.should_show_health_bar()
	_set_bar_visible(show_bar)
	if show_bar:
		position = _unit.sprite_offset + Vector2(0.0, -42.0)
		queue_redraw()
		# Keep a light process tick only while timed visibility can expire.
		set_process(not _unit.is_selected and _unit.hp > 0)
	else:
		set_process(false)


func _set_bar_visible(value: bool) -> void:
	if _was_visible == value and visible == value:
		return
	_was_visible = value
	visible = value


func _draw() -> void:
	if _unit == null or _unit.max_hp <= 0:
		return

	var ratio := clampf(float(_unit.hp) / float(_unit.max_hp), 0.0, 1.0)
	var bg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT)
	var fg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH * ratio, BAR_HEIGHT)
	draw_rect(bg_rect, Color(0.12, 0.08, 0.08, 0.88))
	draw_rect(fg_rect, Color(0.28, 0.88, 0.38, 0.95))
	draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.55), false, 1.0)
