class_name BuildingRallyMarker
extends Node2D

## World-space rally flag + dotted path. Parent Building owns selection visibility.

const LINE_COLOR := Color(0.45, 0.95, 0.55, 0.72)
const LINE_COLOR_SOFT := Color(0.45, 0.95, 0.55, 0.28)
const POLE_COLOR := Color(0.42, 0.28, 0.16, 0.95)
const FLAG_COLOR := Color(1.0, 0.88, 0.38, 0.95)
const FLAG_EDGE := Color(0.85, 0.55, 0.25, 1.0)
const BASE_COLOR := Color(0.45, 0.95, 0.55, 0.45)
const DASH_LENGTH := 10.0
const GAP_LENGTH := 7.0
const LINE_WIDTH := 2.0

var _from_world := Vector2.ZERO
var _to_world := Vector2.ZERO
var _active := false


func set_route(from_world: Vector2, to_world: Vector2) -> void:
	_from_world = from_world
	_to_world = to_world
	_active = true
	# Keep the node at the destination so the flag sorts near ground props.
	global_position = to_world
	queue_redraw()


func clear_route() -> void:
	_active = false
	queue_redraw()


func _draw() -> void:
	if not _active:
		return

	var from_local := to_local(_from_world)
	var to_local := Vector2.ZERO
	_draw_dotted_line(from_local, to_local)
	_draw_flag(to_local)


func _draw_dotted_line(from_local: Vector2, to_local: Vector2) -> void:
	var delta := to_local - from_local
	var length := delta.length()
	if length < 2.0:
		return
	var direction := delta / length
	var perpendicular := Vector2(-direction.y, direction.x)
	var drawn := 0.0
	var drawing := true
	while drawn < length:
		var segment := DASH_LENGTH if drawing else GAP_LENGTH
		var next := minf(drawn + segment, length)
		if drawing:
			var a := from_local + direction * drawn
			var b := from_local + direction * next
			# Soft outer stroke for readability on busy terrain.
			draw_line(
				a + perpendicular * 0.6,
				b + perpendicular * 0.6,
				LINE_COLOR_SOFT,
				LINE_WIDTH + 1.5,
				true
			)
			draw_line(a, b, LINE_COLOR, LINE_WIDTH, true)
		drawn = next
		drawing = not drawing


func _draw_flag(origin: Vector2) -> void:
	# Ground marker (iso-ish ellipse) matching selection rings.
	_draw_ellipse_fill(origin + Vector2(0.0, 2.0), Vector2(9.0, 4.0), BASE_COLOR)
	_draw_ellipse_outline(origin + Vector2(0.0, 2.0), Vector2(9.0, 4.0), FLAG_EDGE, 1.5)

	var pole_top := origin + Vector2(0.0, -26.0)
	draw_line(origin, pole_top, POLE_COLOR, 2.2, true)
	draw_circle(origin, 1.8, POLE_COLOR)

	var pennant := PackedVector2Array([
		pole_top,
		pole_top + Vector2(16.0, 5.0),
		pole_top + Vector2(0.0, 11.0),
	])
	draw_colored_polygon(pennant, FLAG_COLOR)
	var outline := pennant.duplicate()
	outline.append(pennant[0])
	draw_polyline(outline, FLAG_EDGE, 1.4, true)


func _draw_ellipse_fill(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	const SEGMENTS := 24
	for i in SEGMENTS:
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)


func _draw_ellipse_outline(center: Vector2, radii: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	const SEGMENTS := 24
	for i in SEGMENTS + 1:
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_polyline(points, color, width, true)
