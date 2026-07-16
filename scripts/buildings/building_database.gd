class_name BuildingDatabase
extends RefCounted

const WEAPON_STATS: Dictionary = {
	"stone": {"damage": 4, "cooldown_mult": 1.0, "range_min": 0.0, "range_max": 220.0, "speed": 220.0},
	"crossbow": {"damage": 14, "cooldown_mult": 0.85, "range_min": 0.0, "range_max": 260.0, "speed": 380.0},
	"ballista": {"damage": 28, "cooldown_mult": 1.2, "range_min": 0.0, "range_max": 320.0, "speed": 420.0},
}

const UPGRADE_PATHS: Dictionary = {
	"house_small": [
		{"weapon": "stone", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "crossbow", "wood": 60, "gold": 40, "food": 0, "hp_bonus": 40},
	],
	"house_big": [
		{"weapon": "stone", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "crossbow", "wood": 80, "gold": 55, "food": 0, "hp_bonus": 60},
		{"weapon": "ballista", "wood": 120, "gold": 90, "food": 20, "hp_bonus": 80},
	],
	"mill": [
		{"weapon": "stone", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "crossbow", "wood": 70, "gold": 50, "food": 0, "hp_bonus": 50},
	],
	"stable": [
		{"weapon": "stone", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "crossbow", "wood": 90, "gold": 60, "food": 10, "hp_bonus": 50},
	],
	"tower": [
		{"weapon": "crossbow", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "ballista", "wood": 100, "gold": 120, "food": 0, "hp_bonus": 100},
	],
	"wall": [
		{"weapon": "stone", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0},
	],
	"castle_small": [
		{"weapon": "crossbow", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "ballista", "wood": 150, "gold": 200, "food": 30, "hp_bonus": 200},
	],
	"castle_big": [
		{"weapon": "ballista", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0},
	],
}

const DEFINITIONS: Dictionary = {
	"town_center": {
		"name": "Centro Urbano",
		"texture": "res://assets/tilesets/mediterranean/Buildings/town_center.png",
		"wood": 0,
		"gold": 0,
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
	},
	"house_small": {
		"name": "Casa",
		"texture": "res://assets/tilesets/mediterranean/Buildings/house_small.png",
		"wood": 80,
		"gold": 0,
		"food": 0,
		"build_time": 10.0,
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
		"texture": "res://assets/tilesets/mediterranean/Buildings/house_big.png",
		"wood": 90,
		"gold": 45,
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
		"texture": "res://assets/tilesets/mediterranean/Buildings/lumber_camp.png",
		"wood": 100,
		"gold": 0,
		"food": 0,
		"build_time": 12.0,
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
		"gather_rate": BalanceConfig.WOOD_PER_SECOND,
		"max_workers": 3,
	},
	"mill": {
		"name": "Molino",
		"texture": "res://assets/tilesets/mediterranean/Buildings/mill.png",
		"wood": 120,
		"gold": 0,
		"food": 0,
		"build_time": 15.0,
		"max_hp": 320,
		"garrison_capacity": 6,
		"garrison_attack_multiplier": 1.4,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(85.0, 50.0),
		"pick_half_size": Vector2(65.0, 55.0),
		"gather_type": "food",
		"spawns_gather_source": true,
		"gather_radius_cells": 3,
		"gather_rate": BalanceConfig.FOOD_PER_SECOND,
		"max_workers": BalanceConfig.MILL_MAX_WORKERS,
	},
	"mine": {
		"name": "Mina",
		"texture": "res://assets/tilesets/mediterranean/Buildings/mine.png",
		"wood": 100,
		"gold": 0,
		"food": 0,
		"build_time": 12.0,
		"max_hp": 340,
		"garrison_capacity": 3,
		"garrison_attack_multiplier": 1.3,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(70.0, 50.0),
		"pick_half_size": Vector2(55.0, 55.0),
		"gather_type": "gold",
		"gather_radius_cells": 3,
		"gather_rate": BalanceConfig.GOLD_PER_SECOND,
		"max_workers": 3,
	},
	"stable": {
		"name": "Establo",
		"texture": "res://assets/tilesets/mediterranean/Buildings/stable.png",
		"wood": 200,
		"gold": 80,
		"food": 0,
		"build_time": 20.0,
		"max_hp": 300,
		"garrison_capacity": 8,
		"garrison_attack_multiplier": 1.5,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(100.0, 60.0),
		"pick_half_size": Vector2(75.0, 65.0),
		"produces": ["knight_squad"],
	},
	"barracks": {
		"name": "Cuartel",
		"texture": "res://assets/tilesets/mediterranean/Buildings/barracks.png",
		"wood": 200,
		"gold": 80,
		"food": 0,
		"build_time": 20.0,
		"max_hp": 320,
		"garrison_capacity": 8,
		"garrison_attack_multiplier": 1.5,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(100.0, 60.0),
		"pick_half_size": Vector2(75.0, 65.0),
		"produces": ["archer_squad"],
	},
	"tower": {
		"name": "Torre",
		"texture": "res://assets/tilesets/mediterranean/Buildings/tower.png",
		"wood": 150,
		"gold": 40,
		"food": 0,
		"build_time": 18.0,
		"max_hp": 520,
		"garrison_capacity": 5,
		"garrison_attack_multiplier": 2.0,
		"garrison_weapon": "crossbow",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(60.0, 50.0),
		"pick_half_size": Vector2(45.0, 70.0),
		"automatic_defense": true,
	},
	"wall": {
		"name": "Muralla",
		"texture": "res://assets/tilesets/mediterranean/Buildings/wall.png",
		"wood": 15,
		"gold": 0,
		"food": 0,
		"build_time": 3.0,
		"max_hp": 180,
		"garrison_capacity": 3,
		"garrison_attack_multiplier": 1.3,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"footprint": Vector2(80.0, 30.0),
		"pick_half_size": Vector2(50.0, 25.0),
		# Segment walls stay procedural so lines chain cleanly; palette matches the pack.
		"procedural": true,
	},
	"castle_small": {
		"name": "Castillo",
		"texture": "res://assets/tilesets/mediterranean/Buildings/castle_small.png",
		"wood": 200,
		"gold": 300,
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
		"texture": "res://assets/tilesets/mediterranean/Buildings/castle_big.png",
		"wood": 400,
		"gold": 500,
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
	return UPGRADE_PATHS.get(type_id, [{"weapon": "stone", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0}])


static func get_upgrade_cost(type_id: String, current_level: int) -> Dictionary:
	var path: Array = get_upgrade_path(type_id)
	var next_level := current_level + 1
	if next_level >= path.size():
		return {}
	var tier: Dictionary = path[next_level]
	return {
		"wood": tier.get("wood", 0),
		"gold": tier.get("gold", 0),
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
		"gold": def.get("gold", 0),
		"food": def.get("food", 0),
	}


static func get_repair_cost(type_id: String, current_hp: int, max_hp: int) -> Dictionary:
	if max_hp <= 0 or current_hp >= max_hp:
		return {"wood": 0, "gold": 0, "food": 0}
	var base_cost := get_cost(type_id)
	var missing_ratio := 1.0 - float(current_hp) / float(max_hp)
	return {
		"wood": int(round(float(base_cost.get("wood", 0)) * missing_ratio)),
		"gold": int(round(float(base_cost.get("gold", 0)) * missing_ratio)),
		"food": int(round(float(base_cost.get("food", 0)) * missing_ratio)),
	}


static func is_buildable(type_id: String) -> bool:
	var def := get_definition(type_id)
	return def.get("buildable", true)


static func is_gather_building(type_id: String) -> bool:
	var def := get_definition(type_id)
	return not def.get("gather_type", "").is_empty()


static func get_gather_type(type_id: String) -> String:
	return get_definition(type_id).get("gather_type", "")


static func spawns_gather_source(type_id: String) -> bool:
	return get_definition(type_id).get("spawns_gather_source", false)
