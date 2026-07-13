class_name BuildingDatabase
extends RefCounted

const WEAPON_STATS: Dictionary = {
	"stone": {"damage": 4, "cooldown_mult": 1.0, "range_min": 0.0, "range_max": 220.0, "speed": 220.0},
	"crossbow": {"damage": 14, "cooldown_mult": 0.85, "range_min": 0.0, "range_max": 260.0, "speed": 380.0},
	"ballista": {"damage": 28, "cooldown_mult": 1.2, "range_min": 0.0, "range_max": 320.0, "speed": 420.0},
}

const UPGRADE_PATHS: Dictionary = {
	"house_small": [
		{"weapon": "stone", "wood": 0, "stone": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "crossbow", "wood": 60, "stone": 40, "food": 0, "hp_bonus": 40},
	],
	"house_big": [
		{"weapon": "stone", "wood": 0, "stone": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "crossbow", "wood": 80, "stone": 55, "food": 0, "hp_bonus": 60},
		{"weapon": "ballista", "wood": 120, "stone": 90, "food": 20, "hp_bonus": 80},
	],
	"mill": [
		{"weapon": "stone", "wood": 0, "stone": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "crossbow", "wood": 70, "stone": 50, "food": 0, "hp_bonus": 50},
	],
	"stable": [
		{"weapon": "stone", "wood": 0, "stone": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "crossbow", "wood": 90, "stone": 60, "food": 10, "hp_bonus": 50},
	],
	"tower": [
		{"weapon": "crossbow", "wood": 0, "stone": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "ballista", "wood": 100, "stone": 120, "food": 0, "hp_bonus": 100},
	],
	"wall": [
		{"weapon": "stone", "wood": 0, "stone": 0, "food": 0, "hp_bonus": 0},
	],
	"castle_small": [
		{"weapon": "crossbow", "wood": 0, "stone": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "ballista", "wood": 150, "stone": 200, "food": 30, "hp_bonus": 200},
	],
	"castle_big": [
		{"weapon": "ballista", "wood": 0, "stone": 0, "food": 0, "hp_bonus": 0},
	],
}

const DEFINITIONS: Dictionary = {
	"town_center": {
		"name": "Centro Urbano",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/Castle Small/env_buildings_castle_small.png",
		"wood": 0,
		"stone": 0,
		"food": 0,
		"build_time": 0.0,
		"max_hp": 800,
		"garrison_capacity": 10,
		"garrison_attack_multiplier": 1.8,
		"garrison_weapon": "crossbow",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(120.0, 75.0),
		"pick_half_size": Vector2(90.0, 80.0),
		"is_core": true,
		"buildable": false,
		"produces": ["villager"],
		"tint": Color(0.85, 0.92, 1.0, 1.0),
	},
	"house_small": {
		"name": "Casa",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/House Small/env_buildings_house_small.png",
		"wood": 50,
		"stone": 20,
		"food": 0,
		"build_time": 8.0,
		"max_hp": 220,
		"garrison_capacity": 4,
		"garrison_attack_multiplier": 1.6,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(70.0, 45.0),
		"pick_half_size": Vector2(55.0, 50.0),
		"housing": 5,
	},
	"house_big": {
		"name": "Casa grande",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/House Big/env_buildings_house_big.png",
		"wood": 90,
		"stone": 45,
		"food": 0,
		"build_time": 14.0,
		"max_hp": 380,
		"garrison_capacity": 7,
		"garrison_attack_multiplier": 1.7,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(90.0, 55.0),
		"pick_half_size": Vector2(70.0, 60.0),
		"housing": 8,
	},
	"lumber_camp": {
		"name": "Aserradero",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/House Small/env_buildings_house_small.png",
		"wood": 80,
		"stone": 0,
		"food": 0,
		"build_time": 10.0,
		"max_hp": 260,
		"garrison_capacity": 2,
		"garrison_attack_multiplier": 1.2,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(75.0, 45.0),
		"pick_half_size": Vector2(58.0, 50.0),
		"gather_type": "wood",
		"gather_radius_cells": 3,
		"gather_rate": 8.0,
		"max_workers": 3,
		"tint": Color(0.75, 1.0, 0.75, 1.0),
	},
	"mill": {
		"name": "Molino",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/Mill/env_buildings_mill.png",
		"wood": 100,
		"stone": 0,
		"food": 0,
		"build_time": 16.0,
		"max_hp": 320,
		"garrison_capacity": 6,
		"garrison_attack_multiplier": 1.4,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(85.0, 50.0),
		"pick_half_size": Vector2(65.0, 55.0),
		"gather_type": "food",
		"gather_radius_cells": 3,
		"gather_rate": 8.0,
		"max_workers": 3,
	},
	"mine": {
		"name": "Mina",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/Tower/env_buildings_tower.png",
		"wood": 60,
		"stone": 40,
		"food": 0,
		"build_time": 14.0,
		"max_hp": 340,
		"garrison_capacity": 3,
		"garrison_attack_multiplier": 1.3,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(70.0, 50.0),
		"pick_half_size": Vector2(55.0, 55.0),
		"gather_type": "stone",
		"gather_radius_cells": 3,
		"gather_rate": 6.0,
		"max_workers": 3,
		"tint": Color(0.85, 0.85, 0.95, 1.0),
	},
	"stable": {
		"name": "Establo",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/Village/env_buildings_village.png",
		"wood": 120,
		"stone": 50,
		"food": 30,
		"build_time": 18.0,
		"max_hp": 300,
		"garrison_capacity": 8,
		"garrison_attack_multiplier": 1.5,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(100.0, 60.0),
		"pick_half_size": Vector2(75.0, 65.0),
		"produces": ["knight_gear", "archer_gear"],
	},
	"tower": {
		"name": "Torre",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/Tower/env_buildings_tower.png",
		"wood": 80,
		"stone": 110,
		"food": 0,
		"build_time": 22.0,
		"max_hp": 520,
		"garrison_capacity": 5,
		"garrison_attack_multiplier": 2.0,
		"garrison_weapon": "crossbow",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(60.0, 50.0),
		"pick_half_size": Vector2(45.0, 70.0),
		"produces": ["archer_gear"],
	},
	"wall": {
		"name": "Muralla",
		"texture": "",
		"wood": 25,
		"stone": 35,
		"food": 0,
		"build_time": 5.0,
		"max_hp": 180,
		"garrison_capacity": 3,
		"garrison_attack_multiplier": 1.3,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(80.0, 30.0),
		"pick_half_size": Vector2(50.0, 25.0),
		"procedural": true,
	},
	"castle_small": {
		"name": "Castillo",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/Castle Small/env_buildings_castle_small.png",
		"wood": 200,
		"stone": 300,
		"food": 50,
		"build_time": 45.0,
		"max_hp": 1200,
		"garrison_capacity": 12,
		"garrison_attack_multiplier": 2.2,
		"garrison_weapon": "crossbow",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(120.0, 75.0),
		"pick_half_size": Vector2(90.0, 80.0),
	},
	"castle_big": {
		"name": "Castillo grande",
		"texture": "res://assets/tilesets/tiny_tiles/Environment/Buildings/Castle Big/env_buildings_castle_big.png",
		"wood": 400,
		"stone": 500,
		"food": 100,
		"build_time": 90.0,
		"max_hp": 2500,
		"garrison_capacity": 18,
		"garrison_attack_multiplier": 2.5,
		"garrison_weapon": "ballista",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(150.0, 90.0),
		"pick_half_size": Vector2(110.0, 95.0),
	},
}


static func get_weapon_stats(weapon_id: String) -> Dictionary:
	return WEAPON_STATS.get(weapon_id, WEAPON_STATS.stone)


static func get_upgrade_path(type_id: String) -> Array:
	return UPGRADE_PATHS.get(type_id, [{"weapon": "stone", "wood": 0, "stone": 0, "food": 0, "hp_bonus": 0}])


static func get_upgrade_cost(type_id: String, current_level: int) -> Dictionary:
	var path: Array = get_upgrade_path(type_id)
	var next_level := current_level + 1
	if next_level >= path.size():
		return {}
	var tier: Dictionary = path[next_level]
	return {
		"wood": tier.get("wood", 0),
		"stone": tier.get("stone", 0),
		"food": tier.get("food", 0),
	}


static func can_upgrade(type_id: String, current_level: int) -> bool:
	var path: Array = get_upgrade_path(type_id)
	return current_level + 1 < path.size()


static func get_definition(type_id: String) -> Dictionary:
	return DEFINITIONS.get(type_id, {})


static func get_all_type_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in DEFINITIONS.keys():
		ids.append(key)
	return ids


static func get_cost(type_id: String) -> Dictionary:
	var def := get_definition(type_id)
	return {
		"wood": def.get("wood", 0),
		"stone": def.get("stone", 0),
		"food": def.get("food", 0),
	}


static func is_buildable(type_id: String) -> bool:
	var def := get_definition(type_id)
	return def.get("buildable", true)


static func is_gather_building(type_id: String) -> bool:
	var def := get_definition(type_id)
	return not def.get("gather_type", "").is_empty()


static func get_gather_type(type_id: String) -> String:
	return get_definition(type_id).get("gather_type", "")
