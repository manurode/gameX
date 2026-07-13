class_name EquipmentDatabase
extends RefCounted

const DEFINITIONS: Dictionary = {
	"villager": {
		"name": "Aldeano",
		"train_time": 12.0,
		"cost": {"wood": 0, "stone": 0, "food": 50},
		"building_types": ["town_center"],
		"transforms_to": "",
	},
	"knight_gear": {
		"name": "Equipo de caballero",
		"train_time": 20.0,
		"cost": {"wood": 0, "stone": 30, "food": 20},
		"building_types": ["stable"],
		"transforms_to": "knight",
		"batch_size": 1,
	},
	"archer_gear": {
		"name": "Equipo de arquero",
		"train_time": 16.0,
		"cost": {"wood": 40, "stone": 0, "food": 15},
		"building_types": ["stable", "tower"],
		"transforms_to": "archer",
		"batch_size": 1,
	},
}


static func get_definition(item_id: String) -> Dictionary:
	return DEFINITIONS.get(item_id, {})


static func can_produce_at(building_type_id: String, item_id: String) -> bool:
	var def := get_definition(item_id)
	var allowed: Array = def.get("building_types", [])
	return building_type_id in allowed


static func get_items_for_building(building_type_id: String) -> Array[String]:
	var items: Array[String] = []
	for item_id in DEFINITIONS.keys():
		if can_produce_at(building_type_id, item_id):
			items.append(item_id)
	return items
