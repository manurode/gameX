class_name EquipmentDatabase
extends RefCounted

const DEFINITIONS: Dictionary = {
	"villager": {
		"name": "Aldeano",
		"train_time": 10.0,
		"cost": {"wood": 0, "gold": 0, "food": 45},
		"building_types": ["town_center"],
		"transforms_to": "",
	},
	"knight_squad": {
		"name": "Caballero",
		"train_time": BalanceConfig.SQUAD_TRAIN_TIME,
		"cost": {"wood": 0, "gold": BalanceConfig.SQUAD_GOLD_COST, "food": 0},
		"building_types": ["stable"],
		"transforms_to": "knight",
		"squad_size": BalanceConfig.SQUAD_SIZE,
	},
	"archer_squad": {
		"name": "Arquero",
		"train_time": BalanceConfig.SQUAD_TRAIN_TIME,
		"cost": {"wood": 0, "gold": BalanceConfig.SQUAD_GOLD_COST, "food": 0},
		"building_types": ["barracks"],
		"transforms_to": "archer",
		"squad_size": BalanceConfig.SQUAD_SIZE,
	},
	"mage_squad": {
		"name": "Mago",
		"train_time": BalanceConfig.SQUAD_TRAIN_TIME,
		"cost": {"wood": 0, "gold": BalanceConfig.SQUAD_GOLD_COST + 10, "food": 0},
		"building_types": ["arcanum"],
		"transforms_to": "mage",
		"squad_size": BalanceConfig.SQUAD_SIZE,
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
