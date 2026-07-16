extends Node2D

const BAR_WIDTH := 48.0
const BAR_HEIGHT := 5.0
const AMOUNT_FONT_SIZE := 11

var _resource: ResourceNode


func _ready() -> void:
	_resource = get_parent() as ResourceNode
	z_index = 10
	y_sort_enabled = false


func _process(_delta: float) -> void:
	if _resource == null:
		visible = false
		return
	visible = _resource.should_show_amount_bar()
	position = _resource.get_amount_bar_offset()
	queue_redraw()


func _draw() -> void:
	if _resource == null or not _resource.should_show_amount_bar():
		return
	if _resource.is_infinite or _resource.get_initial_amount() <= 0:
		return

	var max_amount := _resource.get_initial_amount()
	var ratio := clampf(float(_resource.amount_remaining) / float(max_amount), 0.0, 1.0)
	var bg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT)
	var fg_rect := Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH * ratio, BAR_HEIGHT)
	draw_rect(bg_rect, Color(0.12, 0.08, 0.08, 0.88))
	draw_rect(fg_rect, _fill_color())
	draw_rect(bg_rect, Color(0.0, 0.0, 0.0, 0.55), false, 1.0)

	if _resource.is_selected:
		var amount_text := "%d/%d" % [_resource.amount_remaining, max_amount]
		var font := ThemeDB.fallback_font
		var text_width := font.get_string_size(
			amount_text, HORIZONTAL_ALIGNMENT_CENTER, -1, AMOUNT_FONT_SIZE
		).x
		var text_pos := Vector2(-text_width * 0.5, BAR_HEIGHT + 12.0)
		draw_string(
			font,
			text_pos,
			amount_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			AMOUNT_FONT_SIZE,
			Color(0.92, 0.95, 0.88, 0.95)
		)


func _fill_color() -> Color:
	match _resource.resource_kind:
		ResourceNode.ResourceKind.WOOD:
			return Color(0.42, 0.72, 0.32, 0.95)
		ResourceNode.ResourceKind.GOLD:
			return Color(0.92, 0.78, 0.28, 0.95)
		ResourceNode.ResourceKind.FOOD:
			return Color(0.78, 0.85, 0.30, 0.95)
		_:
			return Color(0.70, 0.70, 0.70, 0.95)
