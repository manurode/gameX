class_name WallTexture
extends RefCounted

## Painted Mediterranean wall segments on the two iso 2:1 diagonals.
## wall_se (/) runs bottom-left → top-right along axis (2, -1).
## wall_sw (\) runs top-left → bottom-right along axis (2, 1).
##
## Segment centers sit on the lattice. Spacing is tuned so neighboring
## centers share roughly one pillar (~60px painted overlap). Corners place
## both orientations on the same lattice point (corner post).
const TEXTURE_SE := "res://assets/tilesets/mediterranean/Buildings/wall_se.png"
const TEXTURE_SW := "res://assets/tilesets/mediterranean/Buildings/wall_sw.png"

const ISO_STEP := 28.0
## spacing = 140 → euclidean ≈ 156. Painted span ≈ 216 → ~60px pillar share.
const SEGMENT_UNITS := 5
## Physical / nav thickness so chained segments form a continuous barrier.
const BLOCK_THICKNESS := 28.0
## Slight length overlap so adjacent segments leave no walkable gap.
const BLOCK_LENGTH_FACTOR := 1.12

static var _cache: Dictionary = {}


static func get_texture_path(vertical: bool = false, phase: String = "complete") -> String:
	## vertical=true → SW backslash (\); false → SE slash (/).
	var base := TEXTURE_SW if vertical else TEXTURE_SE
	if phase.is_empty() or phase == "complete":
		return base
	return base.get_basename() + "_" + phase + ".png"


static func get_texture(vertical: bool = false, phase: String = "complete") -> Texture2D:
	var path := get_texture_path(vertical, phase)
	if not ResourceLoader.exists(path):
		path = get_texture_path(vertical, "complete")
	if _cache.has(path):
		return _cache[path]
	var texture: Texture2D = load(path)
	_cache[path] = texture
	return texture


static func clear_cache() -> void:
	_cache.clear()


static func get_segment_spacing() -> float:
	return ISO_STEP * float(SEGMENT_UNITS)


static func get_segment_step(vertical: bool) -> Vector2:
	var spacing := get_segment_spacing()
	if vertical:
		# SW texture (\): step along (2, 1) — down-right on screen.
		return Vector2(spacing, spacing * 0.5)
	# SE texture (/): step along (2, -1) — up-right on screen.
	return Vector2(spacing, -spacing * 0.5)


static func get_axis_direction(vertical: bool) -> Vector2:
	return get_segment_step(vertical).normalized()


## vertical=true → SW backslash (\) = default "horizontal" wall on screen.
## vertical=false → SE slash (/) = "vertical" wall, chosen when dragging upward.
static func is_horizontal(vertical: bool) -> bool:
	return vertical


static func default_orientation() -> bool:
	## Idle / default drag: horizontal SW (\).
	return true


## Drag rules: stay on horizontal (SW) unless the mouse clearly moves upward / along SE.
static func orientation_from_delta(delta: Vector2) -> bool:
	if delta.length_squared() < 1.0:
		return default_orientation()
	var slash_dir := Vector2(2.0, -1.0).normalized()
	var backslash_dir := Vector2(2.0, 1.0).normalized()
	var slash_score := absf(delta.dot(slash_dir))
	var backslash_score := absf(delta.dot(backslash_dir))
	# Upward mouse travel unlocks the SE ("vertical") wall.
	var dragging_up := delta.y < -ISO_STEP * 0.5
	if dragging_up and slash_score >= backslash_score * 0.85:
		return false
	if slash_score > backslash_score * 1.25:
		return false
	return true


static func snap_position(world_pos: Vector2) -> Vector2:
	var s := ISO_STEP
	var a := roundf(world_pos.x / (2.0 * s) + world_pos.y / s)
	var b := roundf(world_pos.y / s - world_pos.x / (2.0 * s))
	return Vector2(s * (a - b), (s * 0.5) * (a + b))


## Project `to` onto the wall axis that passes through `from`.
static func project_to_axis(from: Vector2, to: Vector2, vertical: bool) -> Vector2:
	var step := get_segment_step(vertical)
	var axis := step.normalized()
	var along := (to - from).dot(axis)
	var count := int(round(along / step.length()))
	return snap_position(from + step * float(count))


static func segment_key(world_pos: Vector2, vertical: bool) -> String:
	var snap := snap_position(world_pos)
	return "%d:%d:%d" % [roundi(snap.x), roundi(snap.y), 1 if vertical else 0]


static func footprint(_vertical: bool) -> Vector2:
	return Vector2(52.0, 44.0)


static func pick_half_size(_vertical: bool) -> Vector2:
	# Covers the painted diagonal segment; runtime still syncs from sprite AABB.
	return Vector2(88.0, 70.0)


static func get_block_half_length() -> float:
	return get_segment_spacing() * BLOCK_LENGTH_FACTOR * 0.5


static func get_block_half_thickness() -> float:
	return BLOCK_THICKNESS * 0.5


## Oriented quad covering one wall segment (continuous barrier when chained).
static func get_block_outline(center: Vector2, vertical: bool) -> PackedVector2Array:
	var axis := get_axis_direction(vertical)
	var perp := Vector2(-axis.y, axis.x)
	var half_len := get_block_half_length()
	var half_thick := get_block_half_thickness()
	return PackedVector2Array([
		center - axis * half_len - perp * half_thick,
		center + axis * half_len - perp * half_thick,
		center + axis * half_len + perp * half_thick,
		center - axis * half_len + perp * half_thick,
	])
