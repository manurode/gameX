class_name WallTexture
extends RefCounted

## Painted Mediterranean wall segments on the two iso 2:1 diagonals.
## wall_se (/) runs bottom-left → top-right along axis (2, -1).
## wall_sw (\) runs top-left → bottom-right along axis (2, 1).
const TEXTURE_SE := "res://assets/tilesets/mediterranean/Buildings/wall_se.png"
const TEXTURE_SW := "res://assets/tilesets/mediterranean/Buildings/wall_sw.png"

const ISO_STEP := 56.0
## Segment anchors every two lattice units. Sprite span ~170px → ~58px overlap for a seamless run.
const SEGMENT_UNITS := 2
## Physical / nav thickness so chained segments form a continuous barrier.
const BLOCK_THICKNESS := 28.0
## Slight length overlap so adjacent segments leave no walkable gap.
const BLOCK_LENGTH_FACTOR := 1.08

static var _cache: Dictionary = {}


static func get_texture(vertical: bool = false) -> Texture2D:
	## vertical=true → SW backslash (\); false → SE slash (/).
	var path := TEXTURE_SW if vertical else TEXTURE_SE
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


## vertical=true when the drag follows the backslash (\) axis.
static func orientation_from_delta(delta: Vector2) -> bool:
	if delta.length_squared() < 1.0:
		return false
	var slash_dir := Vector2(2.0, -1.0).normalized()
	var backslash_dir := Vector2(2.0, 1.0).normalized()
	var slash_score := absf(delta.dot(slash_dir))
	var backslash_score := absf(delta.dot(backslash_dir))
	if absf(slash_score - backslash_score) < 0.01 * maxf(slash_score, backslash_score):
		# Screen-axis drags tie on both iso axes — map Y-dominant to \.
		return absf(delta.y) > absf(delta.x)
	return backslash_score > slash_score


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
	# Keep overlap checks smaller than spacing so chained segments don't block each other.
	return Vector2(52.0, 44.0)


static func pick_half_size(_vertical: bool) -> Vector2:
	return Vector2(42.0, 34.0)


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
