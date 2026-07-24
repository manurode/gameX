class_name BuildingDatabase
extends RefCounted

const WEAPON_STATS: Dictionary = {
	"stone": {"damage": 4, "cooldown_mult": 1.0, "range_min": 0.0, "range_max": 260.0, "speed": 220.0},
	"crossbow": {"damage": 14, "cooldown_mult": 0.85, "range_min": 0.0, "range_max": 400.0, "speed": 380.0},
	"ballista": {"damage": 28, "cooldown_mult": 1.2, "range_min": 0.0, "range_max": 480.0, "speed": 420.0},
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
	"arcanum": [
		{"weapon": "stone", "wood": 0, "gold": 0, "food": 0, "hp_bonus": 0},
		{"weapon": "crossbow", "wood": 80, "gold": 70, "food": 0, "hp_bonus": 40},
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
		"name": "Ciudadela",
		"description": "Produce aldeanos.",
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
		"visual_scale": 1.35,
		"footprint": Vector2(210.0, 130.0),
		"pick_half_size": Vector2(259.0, 259.0),
		"is_core": true,
		"buildable": false,
		"produces": ["villager"],
	},
	"house_small": {
		"name": "Casa",
		"description": "+5 de población.",
		"texture": "res://assets/tilesets/mediterranean/Buildings/house_small.png",
		"wood": 60,
		"gold": 0,
		"food": 0,
		"build_time": 8.0,
		"max_hp": 220,
		"garrison_capacity": 4,
		"garrison_attack_multiplier": 1.6,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"visual_scale": 0.70,
		"footprint": Vector2(54.0, 35.0),
		"pick_half_size": Vector2(90.0, 90.0),
		"housing": 5,
	},
	"house_big": {
		"name": "Casa grande",
		"description": "+8 de población.",
		"texture": "res://assets/tilesets/mediterranean/Buildings/house_big.png",
		"wood": 80,
		"gold": 40,
		"food": 0,
		"build_time": 12.0,
		"max_hp": 380,
		"garrison_capacity": 7,
		"garrison_attack_multiplier": 1.7,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"visual_scale": 0.95,
		"footprint": Vector2(92.0, 58.0),
		"pick_half_size": Vector2(122.0, 122.0),
		"housing": 8,
	},
	"lumber_camp": {
		"name": "Aserradero",
		"description": "Permite extraer madera del bosque.",
		"texture": "res://assets/tilesets/mediterranean/Buildings/lumber_camp.png",
		"wood": 75,
		"gold": 0,
		"food": 0,
		"build_time": 10.0,
		"max_hp": 260,
		"garrison_capacity": 2,
		"garrison_attack_multiplier": 1.2,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"visual_scale": 0.82,
		"footprint": Vector2(68.0, 42.0),
		"pick_half_size": Vector2(105.0, 105.0),
		"gather_type": "wood",
		"gather_radius_cells": 3,
		"gather_rate": BalanceConfig.WOOD_PER_SECOND,
		"max_workers": 3,
	},
	"mill": {
		"name": "Molino",
		"description": "Produce comida con una granja.",
		"texture": "res://assets/tilesets/mediterranean/Buildings/mill.png",
		"wood": 90,
		"gold": 0,
		"food": 0,
		"build_time": 12.0,
		"max_hp": 320,
		"garrison_capacity": 6,
		"garrison_attack_multiplier": 1.4,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"visual_scale": 0.95,
		"footprint": Vector2(92.0, 70.0),
		"pick_half_size": Vector2(122.0, 152.0),
		"gather_type": "food",
		"spawns_gather_source": true,
		"gather_radius_cells": 0,
		"farm_offset": Vector2(0.0, 21.0),
		"farm_half_size": Vector2(42.0, 25.0),
		"gather_rate": BalanceConfig.FOOD_PER_SECOND,
		"max_workers": BalanceConfig.MILL_MAX_WORKERS,
	},
	"mine": {
		"name": "Mina",
		"description": "Permite extraer oro de la montaña.",
		"texture": "res://assets/tilesets/mediterranean/Buildings/mine.png",
		"wood": 75,
		"gold": 0,
		"food": 0,
		"build_time": 10.0,
		"max_hp": 340,
		"garrison_capacity": 3,
		"garrison_attack_multiplier": 1.3,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"visual_scale": 0.85,
		"footprint": Vector2(64.0, 48.0),
		"pick_half_size": Vector2(109.0, 109.0),
		"gather_type": "gold",
		"gather_radius_cells": 3,
		"gather_rate": BalanceConfig.GOLD_PER_SECOND,
		"max_workers": 3,
	},
	"stable": {
		"name": "Establo",
		"description": "Entrena caballeros.",
		"texture": "res://assets/tilesets/mediterranean/Buildings/stable.png",
		"wood": 170,
		"gold": 70,
		"food": 0,
		"build_time": 18.0,
		"max_hp": 300,
		"garrison_capacity": 8,
		"garrison_attack_multiplier": 1.5,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"visual_scale": 1.00,
		"footprint": Vector2(105.0, 62.0),
		"pick_half_size": Vector2(128.0, 128.0),
		# Courtyard wall draws below the plant; keep exits on open grass.
		"spawn_front_offset": 118.0,
		"produces": ["knight_squad"],
	},
	"barracks": {
		"name": "Cuartel",
		"description": "Entrena arqueros.",
		"texture": "res://assets/tilesets/mediterranean/Buildings/barracks.png",
		"wood": 170,
		"gold": 70,
		"food": 0,
		"build_time": 18.0,
		"max_hp": 320,
		"garrison_capacity": 8,
		"garrison_attack_multiplier": 1.5,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"visual_scale": 1.00,
		"footprint": Vector2(105.0, 62.0),
		"pick_half_size": Vector2(128.0, 128.0),
		"spawn_front_offset": 118.0,
		"produces": ["archer_squad"],
	},
	"arcanum": {
		"name": "Arcanum",
		"description": "Entrena magos.",
		"texture": "res://assets/tilesets/mediterranean/Buildings/arcanum.png",
		"wood": 180,
		"gold": 90,
		"food": 0,
		"build_time": 20.0,
		"max_hp": 300,
		"garrison_capacity": 6,
		"garrison_attack_multiplier": 1.4,
		"garrison_weapon": "stone",
		"can_garrison": true,
		"blocks_nav": true,
		"visual_scale": 1.05,
		"footprint": Vector2(110.0, 68.0),
		"pick_half_size": Vector2(134.0, 134.0),
		"spawn_front_offset": 125.0,
		"produces": ["mage_squad"],
	},
	"tower": {
		"name": "Torre",
		"description": "Ataca automáticamente a enemigos cercanos.",
		"texture": "res://assets/tilesets/mediterranean/Buildings/tower.png",
		"wood": 130,
		"gold": 35,
		"food": 0,
		"build_time": 16.0,
		"max_hp": 520,
		"garrison_capacity": 5,
		"garrison_attack_multiplier": 2.0,
		"garrison_weapon": "crossbow",
		"can_garrison": true,
		"blocks_nav": true,
		"visual_scale": 1.00,
		"footprint": Vector2(72.0, 48.0),
		"pick_half_size": Vector2(128.0, 128.0),
		"automatic_defense": true,
	},
	"wall": {
		"name": "Muralla",
		"description": "",
		"texture": "res://assets/tilesets/mediterranean/Buildings/wall_se.png",
		"texture_vertical": "res://assets/tilesets/mediterranean/Buildings/wall_sw.png",
		"wood": 15,
		"gold": 0,
		"food": 0,
		"build_time": 3.0,
		"max_hp": 180,
		"garrison_capacity": 0,
		"garrison_attack_multiplier": 1.0,
		"garrison_weapon": "stone",
		"can_garrison": false,
		"blocks_nav": true,
		"visual_scale": 0.95,
		"footprint": Vector2(86.0, 42.0),
		"pick_half_size": Vector2(88.0, 70.0),
	},
	"castle_small": {
		"name": "Castillo",
		"description": "Fortaleza defensiva con gran guarnición.",
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
		"visual_scale": 1.42,
		"footprint": Vector2(155.0, 98.0),
		"pick_half_size": Vector2(182.0, 182.0),
	},
	"castle_big": {
		"name": "Castillo grande",
		"description": "Fortaleza masiva con gran guarnición.",
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
		"visual_scale": 1.62,
		"footprint": Vector2(195.0, 120.0),
		"pick_half_size": Vector2(207.0, 207.0),
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


static func get_visual_scale(type_id: String) -> float:
	return float(get_definition(type_id).get("visual_scale", 1.0))


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


## Repair costs this fraction of the proportional construction cost (0.5 = 50% cheaper).
const REPAIR_COST_FACTOR := 0.5


static func get_repair_cost(type_id: String, current_hp: int, max_hp: int) -> Dictionary:
	if max_hp <= 0 or current_hp >= max_hp:
		return {"wood": 0, "gold": 0, "food": 0}
	var base_cost := get_cost(type_id)
	var missing_ratio := 1.0 - float(current_hp) / float(max_hp)
	var scale := missing_ratio * REPAIR_COST_FACTOR
	return {
		"wood": int(round(float(base_cost.get("wood", 0)) * scale)),
		"gold": int(round(float(base_cost.get("gold", 0)) * scale)),
		"food": int(round(float(base_cost.get("food", 0)) * scale)),
	}


static func is_buildable(type_id: String) -> bool:
	var def := get_definition(type_id)
	return def.get("buildable", true)


static func is_gather_building(type_id: String) -> bool:
	var def := get_definition(type_id)
	return not def.get("gather_type", "").is_empty()


static func get_max_workers(type_id: String) -> int:
	var def := get_definition(type_id)
	var base: int = int(def.get("max_workers", 0))
	if base <= 0 or not is_gather_building(type_id):
		return base
	return base + MetaProgression.get_gather_max_workers_bonus()


static func get_gather_type(type_id: String) -> String:
	return get_definition(type_id).get("gather_type", "")


static func spawns_gather_source(type_id: String) -> bool:
	return get_definition(type_id).get("spawns_gather_source", false)
