class_name WallTexture
extends RefCounted

## Painted Mediterranean wall segments on the two iso 2:1 diagonals.
## wall_se (/) runs bottom-left → top-right along axis (2, -1).
## wall_sw (\) runs top-left → bottom-right along axis (2, 1).
##
## Segment centers sit on the lattice. Spacing is tuned so neighboring
## centers share roughly one pillar (~60px painted overlap).
## Junctions (corners / T / cross) use one building per lattice cell with a
## 4-bit connection mask — never stack two full straight sprites.
const TEXTURE_SE := "res://assets/tilesets/mediterranean/Buildings/wall_se.png"
const TEXTURE_SW := "res://assets/tilesets/mediterranean/Buildings/wall_sw.png"
const TEXTURE_JUNC_DIR := "res://assets/tilesets/mediterranean/Buildings/"

## Connection bits from the segment center along each iso axis.
const DIR_SE_POS := 1 ## toward +SE step (up-right)
const DIR_SE_NEG := 2 ## toward -SE step (down-left)
const DIR_SW_POS := 4 ## toward +SW step (down-right)
const DIR_SW_NEG := 8 ## toward -SW step (up-left)
const MASK_STRAIGHT_SE := DIR_SE_POS | DIR_SE_NEG
const MASK_STRAIGHT_SW := DIR_SW_POS | DIR_SW_NEG
const MASK_ALL := DIR_SE_POS | DIR_SE_NEG | DIR_SW_POS | DIR_SW_NEG

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


static func get_junction_texture_path(mask: int, phase: String = "complete") -> String:
	var stem := "wall_junc_%02d" % clampi(mask, 0, 15)
	if phase.is_empty() or phase == "complete":
		return TEXTURE_JUNC_DIR + stem + ".png"
	return TEXTURE_JUNC_DIR + stem + "_" + phase + ".png"


static func get_texture(vertical: bool = false, phase: String = "complete") -> Texture2D:
	return _load_texture(get_texture_path(vertical, phase), get_texture_path(vertical, "complete"))


static func get_texture_for_mask(mask: int, phase: String = "complete") -> Texture2D:
	var normalized := normalize_mask(mask, false)
	if normalized == MASK_STRAIGHT_SE:
		return get_texture(false, phase)
	if normalized == MASK_STRAIGHT_SW:
		return get_texture(true, phase)
	var path := get_junction_texture_path(normalized, phase)
	var fallback := get_texture_path(vertical_from_mask(normalized), "complete")
	return _load_texture(path, fallback)


static func get_arm_texture_path(dir_bit: int, phase: String = "complete") -> String:
	var name := ""
	match dir_bit:
		DIR_SE_POS:
			name = "wall_arm_se_pos"
		DIR_SE_NEG:
			name = "wall_arm_se_neg"
		DIR_SW_POS:
			name = "wall_arm_sw_pos"
		DIR_SW_NEG:
			name = "wall_arm_sw_neg"
		_:
			return ""
	if phase.is_empty() or phase == "complete":
		return TEXTURE_JUNC_DIR + name + ".png"
	return TEXTURE_JUNC_DIR + name + "_" + phase + ".png"


static func get_arm_texture(dir_bit: int, phase: String = "complete") -> Texture2D:
	var path := get_arm_texture_path(dir_bit, phase)
	var fallback := get_arm_texture_path(dir_bit, "complete")
	return _load_texture(path, fallback)


static func get_corner_post_path(phase: String = "complete") -> String:
	if phase.is_empty() or phase == "complete":
		return TEXTURE_JUNC_DIR + "wall_corner_post.png"
	return TEXTURE_JUNC_DIR + "wall_corner_post_" + phase + ".png"


static func get_corner_post_texture(phase: String = "complete") -> Texture2D:
	return _load_texture(get_corner_post_path(phase), get_corner_post_path("complete"))


static func is_junction_mask(mask: int) -> bool:
	var normalized := normalize_mask(mask, false)
	return normalized != MASK_STRAIGHT_SE and normalized != MASK_STRAIGHT_SW


## Outward nudge so layered arms meet a post instead of crossing roofs.
const ARM_OUTSET_PX := 12.0


static func arm_outset(dir_bit: int) -> Vector2:
	var offset := dir_offset(dir_bit)
	if offset.length_squared() < 0.01:
		return Vector2.ZERO
	return offset.normalized() * ARM_OUTSET_PX


static func _load_texture(path: String, fallback_path: String) -> Texture2D:
	var resolved := path
	if not ResourceLoader.exists(resolved):
		resolved = fallback_path
	if not ResourceLoader.exists(resolved):
		return null
	if _cache.has(resolved):
		return _cache[resolved]
	var texture: Texture2D = load(resolved)
	_cache[resolved] = texture
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


static func dir_offset(dir_bit: int) -> Vector2:
	match dir_bit:
		DIR_SE_POS:
			return get_segment_step(false)
		DIR_SE_NEG:
			return -get_segment_step(false)
		DIR_SW_POS:
			return get_segment_step(true)
		DIR_SW_NEG:
			return -get_segment_step(true)
		_:
			return Vector2.ZERO


static func all_dir_bits() -> Array[int]:
	return [DIR_SE_POS, DIR_SE_NEG, DIR_SW_POS, DIR_SW_NEG]


## vertical=true → SW backslash (\) = default "horizontal" wall on screen.
## vertical=false → SE slash (/) = "vertical" wall, chosen when dragging upward.
static func is_horizontal(vertical: bool) -> bool:
	return vertical


static func default_orientation() -> bool:
	## Idle / default drag: horizontal SW (\).
	return true


static func mask_from_vertical(vertical: bool) -> int:
	return MASK_STRAIGHT_SW if vertical else MASK_STRAIGHT_SE


static func vertical_from_mask(mask: int) -> bool:
	var normalized := normalize_mask(mask, false)
	if normalized == MASK_STRAIGHT_SW:
		return true
	if normalized == MASK_STRAIGHT_SE:
		return false
	# Mixed junction: prefer SW when present for legacy callers.
	return (normalized & MASK_STRAIGHT_SW) != 0


## Expand single-axis stubs to full straights; keep multi-axis junction bits.
static func normalize_mask(mask: int, fallback_vertical: bool) -> int:
	var bits := mask & MASK_ALL
	if bits == 0:
		return mask_from_vertical(fallback_vertical)
	var se := bits & MASK_STRAIGHT_SE
	var sw := bits & MASK_STRAIGHT_SW
	if se != 0 and sw == 0:
		return MASK_STRAIGHT_SE
	if sw != 0 and se == 0:
		return MASK_STRAIGHT_SW
	return bits


static func has_se_axis(mask: int) -> bool:
	return (mask & MASK_STRAIGHT_SE) != 0


static func has_sw_axis(mask: int) -> bool:
	return (mask & MASK_STRAIGHT_SW) != 0


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


static func cell_key(world_pos: Vector2) -> String:
	var snap := snap_position(world_pos)
	return "%d:%d" % [roundi(snap.x), roundi(snap.y)]


static func segment_key(world_pos: Vector2, vertical: bool) -> String:
	## Legacy key; prefer cell_key — one wall building per lattice cell.
	return cell_key(world_pos) + ":%d" % (1 if vertical else 0)


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


## Nav / collision outline for junction masks (union of active axes).
static func get_block_outline_for_mask(center: Vector2, mask: int) -> PackedVector2Array:
	var normalized := normalize_mask(mask, false)
	var has_se := has_se_axis(normalized)
	var has_sw := has_sw_axis(normalized)
	if has_se and not has_sw:
		return get_block_outline(center, false)
	if has_sw and not has_se:
		return get_block_outline(center, true)
	# Corner / T / cross: diamond covering both diagonal blocks.
	var se := get_block_outline(center, false)
	var sw := get_block_outline(center, true)
	var pts: Array[Vector2] = []
	for p in se:
		pts.append(p)
	for p in sw:
		pts.append(p)
	var hull := Geometry2D.convex_hull(PackedVector2Array(pts))
	if hull.size() >= 3:
		return hull
	return se
