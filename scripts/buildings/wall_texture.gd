class_name WallTexture
extends RefCounted

## Painted Mediterranean wall segments on the two iso 2:1 diagonals.
## wall_se (/) runs bottom-left → top-right along axis (2, -1).
## wall_sw (\) runs top-left → bottom-right along axis (2, 1).
##
## Geometry model: walls live on a lattice of *posts* one segment apart along
## each diagonal, and a segment is the edge between two neighbouring posts,
## drawn centered on that edge. The art paints a full column at both ends of a
## segment, exactly SEGMENT_SPACING apart, so two segments sharing a post render
## their columns pixel-on-pixel. Straight runs, corners, T junctions and crosses
## therefore all resolve to a single shared column with no dedicated corner art.
##
## post(i, j) = i * STEP_SE + j * STEP_SW
const TEXTURE_SE := "res://assets/tilesets/mediterranean/Buildings/wall_se.png"
const TEXTURE_SW := "res://assets/tilesets/mediterranean/Buildings/wall_sw.png"

## Screen-X distance between two posts. Matches the painted column spacing of
## the art (148 px at 0.95 visual scale), so shared posts overlap exactly.
const SEGMENT_SPACING := 140.0
const STEP_SE := Vector2(SEGMENT_SPACING, -SEGMENT_SPACING * 0.5)
const STEP_SW := Vector2(SEGMENT_SPACING, SEGMENT_SPACING * 0.5)
## Physical / nav thickness so chained segments form a continuous barrier.
const BLOCK_THICKNESS := 28.0
## Slight length overlap so adjacent segments leave no walkable gap.
const BLOCK_LENGTH_FACTOR := 1.06
## Painted base strip, used for placement overlap. Deliberately slimmer than the
## nav block: a wall may be built anywhere its art does not cover a building.
const GROUND_THICKNESS := 18.0

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


static func get_segment_step(vertical: bool) -> Vector2:
	return STEP_SW if vertical else STEP_SE


static func get_segment_length() -> float:
	return STEP_SE.length()


static func get_axis_direction(vertical: bool) -> Vector2:
	return get_segment_step(vertical).normalized()


# --- Post lattice -------------------------------------------------------------


static func post_position(coords: Vector2i) -> Vector2:
	return STEP_SE * float(coords.x) + STEP_SW * float(coords.y)


## Nearest post to a world point. The basis is not orthogonal, so rounding the
## fractional coordinates can miss; scan the ring around them and keep the best.
static func post_coords(world_pos: Vector2) -> Vector2i:
	var sum := world_pos.x / SEGMENT_SPACING  # i + j
	var diff := world_pos.y / (SEGMENT_SPACING * 0.5)  # j - i
	var base := Vector2i(roundi((sum - diff) * 0.5), roundi((sum + diff) * 0.5))
	var best := base
	var best_dist := INF
	for di in [-1, 0, 1]:
		for dj in [-1, 0, 1]:
			var candidate := base + Vector2i(di, dj)
			var dist := world_pos.distance_squared_to(post_position(candidate))
			if dist < best_dist:
				best_dist = dist
				best = candidate
	return best


# --- Segments (edges between posts) -------------------------------------------


## Center of the segment leaving `post` along the given axis (its low-post edge).
static func segment_center(post: Vector2i, vertical: bool) -> Vector2:
	return post_position(post) + get_segment_step(vertical) * 0.5


## The post a segment starts from, derived from its painted center.
static func segment_post(center: Vector2, vertical: bool) -> Vector2i:
	return post_coords(center - get_segment_step(vertical) * 0.5)


static func snap_segment_center(world_pos: Vector2, vertical: bool) -> Vector2:
	return segment_center(segment_post(world_pos, vertical), vertical)


## Segment of either orientation whose center is closest to `world_pos`.
static func nearest_segment(world_pos: Vector2) -> Dictionary:
	var best := {"pos": snap_segment_center(world_pos, false), "vertical": false}
	var best_dist := world_pos.distance_squared_to(best["pos"])
	var sw_center := snap_segment_center(world_pos, true)
	if world_pos.distance_squared_to(sw_center) < best_dist:
		return {"pos": sw_center, "vertical": true}
	return best


static func segment_key(center: Vector2, vertical: bool) -> String:
	var post := segment_post(center, vertical)
	return "%d:%d:%d" % [post.x, post.y, 1 if vertical else 0]


## Both end posts of a segment, in lattice coordinates.
static func segment_end_posts(center: Vector2, vertical: bool) -> Array[Vector2i]:
	var low := segment_post(center, vertical)
	var high := low + (Vector2i(0, 1) if vertical else Vector2i(1, 0))
	return [low, high]


static func footprint(_vertical: bool) -> Vector2:
	return Vector2(52.0, 44.0)


static func pick_half_size(_vertical: bool) -> Vector2:
	# Covers the painted diagonal segment; runtime still syncs from sprite AABB.
	return Vector2(88.0, 70.0)


static func get_block_length() -> float:
	return get_segment_length() * BLOCK_LENGTH_FACTOR


static func get_block_half_length() -> float:
	return get_block_length() * 0.5


static func get_block_half_thickness() -> float:
	return BLOCK_THICKNESS * 0.5


## Oriented quad covering one wall segment (continuous barrier when chained).
static func get_block_outline(center: Vector2, vertical: bool) -> PackedVector2Array:
	return _oriented_quad(center, vertical, get_block_half_length(), get_block_half_thickness())


## Tighter quad matching the painted base, used for build placement checks.
static func get_ground_outline(center: Vector2, vertical: bool) -> PackedVector2Array:
	return _oriented_quad(center, vertical, get_segment_length() * 0.5, GROUND_THICKNESS * 0.5)


static func _oriented_quad(
	center: Vector2,
	vertical: bool,
	half_len: float,
	half_thick: float
) -> PackedVector2Array:
	var axis := get_axis_direction(vertical)
	var perp := Vector2(-axis.y, axis.x)
	return PackedVector2Array([
		center - axis * half_len - perp * half_thick,
		center + axis * half_len - perp * half_thick,
		center + axis * half_len + perp * half_thick,
		center - axis * half_len + perp * half_thick,
	])
