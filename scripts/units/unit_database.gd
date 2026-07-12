class_name UnitDatabase
extends RefCounted

const DEFINITIONS: Dictionary = {
	"knight": {
		"name": "Caballero",
		"scene": "res://scenes/units/unit_knight.tscn",
		"preview": "res://assets/tilesets/tiny_tiles/Characters/Knight/chr_knight_idle.png",
	},
	"archer": {
		"name": "Arquero",
		"scene": "res://scenes/units/unit_archer.tscn",
		"preview": "res://assets/tilesets/tiny_tiles/Characters/Archer/chr_archer_idle.png",
	},
	"builder": {
		"name": "Constructor",
		"scene": "res://scenes/units/unit_builder.tscn",
		"preview": "res://assets/tilesets/tiny_tiles/Characters/Builder/chr_builder_idle.png",
	},
}

const SPAWN_HOTKEYS: Dictionary = {
	KEY_F1: "knight",
	KEY_F2: "archer",
	KEY_F3: "builder",
}


static func get_definition(type_id: String) -> Dictionary:
	return DEFINITIONS.get(type_id, {})


static func get_all_type_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in DEFINITIONS.keys():
		ids.append(key)
	return ids


static func get_scene(type_id: String) -> PackedScene:
	var def := get_definition(type_id)
	var scene_path: String = def.get("scene", "")
	if scene_path.is_empty():
		return null
	return load(scene_path)


static func get_hotkey_for_type(type_id: String) -> Key:
	for key in SPAWN_HOTKEYS:
		if SPAWN_HOTKEYS[key] == type_id:
			return key
	return KEY_NONE
