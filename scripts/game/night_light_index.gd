class_name NightLightIndex
extends RefCounted

## Rebuilds active player night-light sources once per physics frame.

static var _physics_frame := -1
static var _origins: PackedVector2Array = PackedVector2Array()
static var _radius_sq: PackedFloat32Array = PackedFloat32Array()


static func _ensure_built(tree: SceneTree) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _physics_frame:
		return
	_physics_frame = frame
	_origins.clear()
	_radius_sq.clear()
	if tree == null:
		return

	for node in tree.get_nodes_in_group("selectable_units"):
		if not node is Unit:
			continue
		var ally := node as Unit
		if ally.team_id != Team.PLAYER or not ally.is_night_light_active():
			continue
		var radius := ally.get_night_light_radius()
		if radius <= 0.0:
			continue
		_origins.append(ally.get_night_light_origin())
		_radius_sq.append(radius * radius)

	for node in tree.get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.team_id != Team.PLAYER or not building.is_night_light_active():
			continue
		var radius := building.get_night_light_radius()
		if radius <= 0.0:
			continue
		_origins.append(building.get_night_light_origin())
		_radius_sq.append(radius * radius)


static func is_position_lit(tree: SceneTree, world_position: Vector2) -> bool:
	_ensure_built(tree)
	var count := _origins.size()
	for i in count:
		if world_position.distance_squared_to(_origins[i]) <= _radius_sq[i]:
			return true
	return false
