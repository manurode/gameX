class_name PlayerBuildingIndex
extends RefCounted

## Active player buildings cached once per physics frame for enemy targeting.

static var _physics_frame := -1
static var _buildings: Array[Building] = []


static func get_targets(tree: SceneTree) -> Array[Building]:
	var frame := Engine.get_physics_frames()
	if frame == _physics_frame:
		return _buildings
	_physics_frame = frame
	_buildings.clear()
	if tree == null:
		return _buildings
	for node in tree.get_nodes_in_group("buildings"):
		if not node is Building:
			continue
		var building := node as Building
		if building.team_id != Team.PLAYER:
			continue
		if building.building_state != Building.BuildingState.ACTIVE:
			continue
		if not building.can_be_damaged():
			continue
		_buildings.append(building)
	return _buildings
