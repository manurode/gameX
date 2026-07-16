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


static func footprint(vertical: bool) -> Vector2:
	# Keep overlap checks smaller than spacing so chained segments don't block each other.
	if vertical:
		return Vector2(52.0, 44.0)
	return Vector2(52.0, 44.0)


static func pick_half_size(vertical: bool) -> Vector2:
	if vertical:
		return Vector2(42.0, 34.0)
	return Vector2(42.0, 34.0)
