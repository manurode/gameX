extends Node

## Invariants of the wall post lattice.
##
## Corners look right only because two segments that meet always share a post:
## the art paints half a column at each end of a segment, so a shared post means
## the two columns land on the same pixels. These checks pin that down.

const LATTICE_RANGE := 5


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_posts_round_trip()
	_test_post_coords_is_nearest()
	_test_segment_identity()
	_test_neighbours_share_a_post()
	await _test_world_placement()
	print("WALL_GEOMETRY_OK")
	get_tree().quit(0)


func _test_posts_round_trip() -> void:
	for i in range(-LATTICE_RANGE, LATTICE_RANGE + 1):
		for j in range(-LATTICE_RANGE, LATTICE_RANGE + 1):
			var coords := Vector2i(i, j)
			var back := WallTexture.post_coords(WallTexture.post_position(coords))
			assert(back == coords, "post %v round-tripped to %v" % [coords, back])


func _test_post_coords_is_nearest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260726
	for _sample in 400:
		var point := Vector2(rng.randf_range(-800.0, 800.0), rng.randf_range(-800.0, 800.0))
		var picked := WallTexture.post_coords(point)
		var picked_dist := point.distance_squared_to(WallTexture.post_position(picked))
		for i in range(-8, 9):
			for j in range(-8, 9):
				var other := WallTexture.post_position(Vector2i(i, j))
				assert(
					point.distance_squared_to(other) >= picked_dist - 0.01,
					"post_coords(%v) missed a nearer post at %v" % [point, other]
				)


func _test_segment_identity() -> void:
	var keys: Dictionary = {}
	var centers: Dictionary = {}
	for i in range(-LATTICE_RANGE, LATTICE_RANGE + 1):
		for j in range(-LATTICE_RANGE, LATTICE_RANGE + 1):
			for vertical in [false, true]:
				var post := Vector2i(i, j)
				var center := WallTexture.segment_center(post, vertical)
				assert(
					WallTexture.segment_post(center, vertical) == post,
					"segment %v/%s lost its post" % [post, vertical]
				)
				var key := WallTexture.segment_key(center, vertical)
				assert(not keys.has(key), "duplicate segment key %s" % key)
				keys[key] = true
				# The two orientations must never resolve to the same center, or a
				# corner would stack two full segments instead of sharing a post.
				var rounded := Vector2i(roundi(center.x), roundi(center.y))
				assert(not centers.has(rounded), "SE and SW segments collide at %v" % rounded)
				centers[rounded] = true


func _test_neighbours_share_a_post() -> void:
	var post := Vector2i(3, -1)
	var straight := [
		[WallTexture.segment_center(post, false), false],
		[WallTexture.segment_center(post + Vector2i(1, 0), false), false],
	]
	var corner := [
		[WallTexture.segment_center(post, false), false],
		[WallTexture.segment_center(post + Vector2i(1, 0), true), true],
	]
	for pair in [straight, corner]:
		var first := WallTexture.segment_end_posts(pair[0][0], pair[0][1])
		var second := WallTexture.segment_end_posts(pair[1][0], pair[1][1])
		var shared := 0
		for end_post in first:
			if second.has(end_post):
				shared += 1
		assert(shared == 1, "neighbouring segments shared %d posts, expected 1" % shared)


func _test_world_placement() -> void:
	var world: Node = load("res://scenes/world/game_world.tscn").instantiate()
	add_child(world)
	for _frame in 12:
		await get_tree().physics_frame

	_assert_tall_art_does_not_reserve_ground(world)
	_assert_starter_ring_is_closed(world)
	world.queue_free()


## The Ciudadela's sprite reaches far past the ground it stands on. A wall whose
## painted base clears that ground has to be buildable, even though it overlaps
## the sprite's bounding box.
func _assert_tall_art_does_not_reserve_ground(world: Node) -> void:
	var build_manager: Node = world.get_node("BuildManager")
	var town_center: Building = null
	for child in world.buildings.get_children():
		if child is Building and (child as Building).building_type_id == "town_center":
			town_center = child as Building
			break
	assert(town_center != null, "no town center in the test world")

	var anchor := town_center.get_anchor_position()
	var beside := WallTexture.nearest_segment(anchor + Vector2(210.0, 0.0))
	var outline := WallTexture.get_ground_outline(beside["pos"], beside["vertical"])
	assert(
		Geometry2D.intersect_polygons(outline, town_center.get_ground_footprint_polygon()).is_empty(),
		"test setup: the sample segment overlaps the town center footprint"
	)
	assert(
		town_center.get_selection_rect().has_point(beside["pos"]),
		"test setup: the sample segment must sit inside the sprite bounds"
	)
	assert(
		build_manager._is_valid_wall_segment(beside["pos"], beside["vertical"]),
		"a wall clear of the town center footprint was rejected"
	)

	var on_top := WallTexture.nearest_segment(town_center.get_interaction_center())
	assert(
		not build_manager._is_valid_wall_segment(on_top["pos"], on_top["vertical"]),
		"a wall on top of the town center was accepted"
	)


func _assert_starter_ring_is_closed(world: Node) -> void:
	# 24 segments is exactly the perimeter of the ring the spawner lays out, so a
	# full grant has to come back closed.
	var buildings: Node2D = world.buildings
	var before := _wall_segments(buildings).size()
	world.spawn_starter_walls(24)

	var segments := _wall_segments(buildings)
	assert(
		segments.size() == before + 24,
		"expected 24 starter walls, got %d" % (segments.size() - before)
	)

	# Every post of a closed ring carries exactly two segments, and each of those
	# pairs is what renders as a straight join or a shared corner column.
	var post_uses: Dictionary = {}
	for segment in segments:
		for post in WallTexture.segment_end_posts(segment["pos"], segment["vertical"]):
			post_uses[post] = int(post_uses.get(post, 0)) + 1
	for post in post_uses:
		assert(post_uses[post] == 2, "post %v carries %d segments" % [post, post_uses[post]])


func _wall_segments(buildings: Node2D) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for child in buildings.get_children():
		if not (child is Building) or (child as Building).building_type_id != "wall":
			continue
		var wall := child as Building
		var center := wall.get_anchor_position()
		var vertical := wall.is_wall_vertical()
		# Placement must land exactly on the lattice, otherwise columns drift.
		var snapped := WallTexture.snap_segment_center(center, vertical)
		assert(center.distance_to(snapped) < 0.5, "wall at %v is off-lattice" % center)
		segments.append({"pos": snapped, "vertical": vertical})
	return segments
