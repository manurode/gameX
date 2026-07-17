class_name UnitDatabase
extends RefCounted

const DEFINITIONS: Dictionary = {
	"villager": {
		"name": "Aldeano",
		"scene": "res://scenes/units/unit_villager.tscn",
		"preview": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_idle.png",
		"move_speed": 88.0,
		"max_hp": 80,
		"can_attack": false,
		"can_build": true,
		"can_gather": true,
		"is_civilian": true,
		"combat_style": Unit.CombatStyle.MELEE,
		"idle_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_idle.png",
		"walk_up_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_run_upward.png",
		"walk_down_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_run_downward.png",
		"gather_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_afk.png",
	},
	"knight": {
		"name": "Caballero",
		"scene": "res://scenes/units/unit_knight.tscn",
		"preview": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_idle.png",
		"move_speed": 95.0,
		"max_hp": 100,
		"can_attack": true,
		"can_build": false,
		"can_gather": false,
		"is_civilian": false,
		"combat_style": Unit.CombatStyle.MELEE,
		"attack_damage": 18,
		"attack_cooldown": 1.0,
		"melee_range": 54.0,
		"idle_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_idle.png",
		"walk_up_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_run_upward.png",
		"walk_down_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_run_downward.png",
		"attack_up_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_attack_back.png",
		"attack_down_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_attack.png",
		"death_up_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_deploy_back.png",
		"death_down_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_deploy.png",
	},
	"archer": {
		"name": "Arquero",
		"scene": "res://scenes/units/unit_archer.tscn",
		"preview": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_idle.png",
		"move_speed": 105.0,
		"max_hp": 100,
		"can_attack": true,
		"can_build": false,
		"can_gather": false,
		"is_civilian": false,
		"combat_style": Unit.CombatStyle.RANGED,
		"attack_damage": 14,
		"attack_cooldown": 1.2,
		"attack_range_min": 95.0,
		"attack_range_max": 220.0,
		"idle_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_idle.png",
		"walk_up_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_run_upward.png",
		"walk_down_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_run_downward.png",
		"attack_up_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_attack_back.png",
		"attack_down_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_attack.png",
		"death_up_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_deploy_back.png",
		"death_down_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_deploy.png",
	},
	"builder": {
		"name": "Constructor",
		"scene": "res://scenes/units/unit_builder.tscn",
		"preview": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_idle.png",
	},
	"enemy": {
		"name": "Monstruo",
		"scene": "res://scenes/units/unit_enemy.tscn",
		"preview": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_idle.png",
		"kinds": ["normal", "swarm", "siege", "elite", "raider"],
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


static func apply_definition_to_unit(unit: Unit, type_id: String) -> void:
	var def := get_definition(type_id)
	if def.is_empty():
		return

	unit.unit_type_id = type_id
	unit.move_speed = def.get("move_speed", unit.move_speed)
	unit.max_hp = def.get("max_hp", unit.max_hp)
	if type_id == "knight":
		unit.max_hp += MetaProgression.get_knight_hp_bonus()
	unit.hp = unit.max_hp
	unit.can_attack = def.get("can_attack", unit.can_attack)
	unit.can_build = def.get("can_build", unit.can_build)
	unit.can_gather = def.get("can_gather", unit.can_gather)
	unit.is_civilian = def.get("is_civilian", unit.is_civilian)
	unit.combat_style = def.get("combat_style", unit.combat_style)
	unit.attack_damage = def.get("attack_damage", unit.attack_damage)
	unit.attack_cooldown = def.get("attack_cooldown", unit.attack_cooldown)
	unit.melee_range = def.get("melee_range", unit.melee_range)
	unit.attack_range_min = def.get("attack_range_min", unit.attack_range_min)
	unit.attack_range_max = def.get("attack_range_max", unit.attack_range_max)

	var idle_path: String = def.get("idle_sheet", "")
	if not idle_path.is_empty():
		unit.idle_sheet = load(idle_path)
	var walk_up_path: String = def.get("walk_up_sheet", "")
	if not walk_up_path.is_empty():
		unit.walk_up_sheet = load(walk_up_path)
	var walk_down_path: String = def.get("walk_down_sheet", "")
	if not walk_down_path.is_empty():
		unit.walk_down_sheet = load(walk_down_path)
	var attack_up_path: String = def.get("attack_up_sheet", "")
	if not attack_up_path.is_empty():
		unit.attack_up_sheet = load(attack_up_path)
	var attack_down_path: String = def.get("attack_down_sheet", "")
	if not attack_down_path.is_empty():
		unit.attack_down_sheet = load(attack_down_path)
	var death_up_path: String = def.get("death_up_sheet", "")
	if not death_up_path.is_empty():
		unit.death_up_sheet = load(death_up_path)
	var death_down_path: String = def.get("death_down_sheet", "")
	if not death_down_path.is_empty():
		unit.death_down_sheet = load(death_down_path)
	var gather_path: String = def.get("gather_sheet", "")
	if not gather_path.is_empty():
		unit.gather_sheet = load(gather_path)

	unit.rebuild_visuals()
