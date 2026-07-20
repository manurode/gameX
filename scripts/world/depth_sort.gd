class_name DepthSort
extends RefCounted

## Shared isometric depth helpers.
## Godot 4.7 has no Node2D.y_sort_origin (only TileMapLayer). Tall props must
## shift global_position for Y-sort and compensate sprite.offset so art stays put.
## Iso tiles are 256x128; half-height (64) is the usual sprite plant offset.

const ISO_HALF_TILE := 64.0
## Walls plant slightly lower than other buildings.
const WALL_PLANT := 48.0


static func sort_y(item: CanvasItem) -> float:
	if item == null:
		return 0.0
	if item.has_method("get_sort_y"):
		return float(item.call("get_sort_y"))
	return item.global_position.y


static func plant_sort_dy(plant_unscaled: float, scale_factor: float) -> float:
	return plant_unscaled * scale_factor


## sort_bias > plant pulls the sort key north so canopy/cliff edges don't cover
## units/buildings standing visually in front of the mass.
static func biased_sort_dy(scale_factor: float, sort_bias: float = 0.0) -> float:
	return ISO_HALF_TILE * scale_factor - sort_bias


static func compensate_draw_offset(
	sprite_offset: Vector2,
	sort_dy: float,
	scale_factor: float
) -> Vector2:
	if is_zero_approx(scale_factor) or is_zero_approx(sort_dy):
		return sprite_offset
	return sprite_offset - Vector2(0.0, sort_dy / scale_factor)
