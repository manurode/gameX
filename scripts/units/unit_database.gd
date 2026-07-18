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
		"idle_up_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_idle_back.png",
		"idle_side_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_idle_side.png",
		"walk_up_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_run_upward.png",
		"walk_down_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_run_downward.png",
		"walk_side_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_run_side.png",
		"gather_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_afk.png",
		"gather_up_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_afk_back.png",
		"gather_side_sheet": "res://assets/tilesets/mediterranean/Characters/villager/chr_villager_afk_side.png",
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
		"idle_up_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_idle_back.png",
		"idle_side_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_idle_side.png",
		"walk_up_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_run_upward.png",
		"walk_down_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_run_downward.png",
		"walk_side_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_run_side.png",
		"attack_up_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_attack_back.png",
		"attack_down_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_attack.png",
		"attack_side_sheet": "res://assets/tilesets/mediterranean/Characters/knight/chr_knight_attack_side.png",
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
		"idle_up_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_idle_back.png",
		"idle_side_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_idle_side.png",
		"walk_up_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_run_upward.png",
		"walk_down_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_run_downward.png",
		"walk_side_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_run_side.png",
		"attack_up_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_attack_back.png",
		"attack_down_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_attack.png",
		"attack_side_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_attack_side.png",
		"death_up_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_deploy_back.png",
		"death_down_sheet": "res://assets/tilesets/mediterranean/Characters/archer/chr_archer_deploy.png",
	},
	"builder": {
		"name": "Constructor",
		"scene": "res://scenes/units/unit_builder.tscn",
		"preview": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_idle.png",
		"idle_sheet": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_idle.png",
		"idle_up_sheet": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_idle_back.png",
		"idle_side_sheet": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_idle_side.png",
		"walk_up_sheet": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_run_upward.png",
		"walk_down_sheet": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_run_downward.png",
		"walk_side_sheet": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_run_side.png",
		"gather_sheet": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_afk.png",
		"gather_up_sheet": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_afk_back.png",
		"gather_side_sheet": "res://assets/tilesets/mediterranean/Characters/builder/chr_builder_afk_side.png",
	},
	"enemy": {
		"name": "Monstruo",
		"scene": "res://scenes/units/unit_enemy.tscn",
		"preview": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_idle.png",
		"kinds": ["normal", "swarm", "siege", "elite", "raider"],
		"idle_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_idle.png",
		"idle_up_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_idle_back.png",
		"idle_side_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_idle_side.png",
		"walk_up_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_run_upward.png",
		"walk_down_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_run_downward.png",
		"walk_side_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_run_side.png",
		"attack_up_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_attack_back.png",
		"attack_down_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_attack.png",
		"attack_side_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_attack_side.png",
		"death_up_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_deploy_back.png",
		"death_down_sheet": "res://assets/tilesets/mediterranean/Characters/enemy/chr_enemy_deploy.png",
	},
}

const SPAWN_HOTKEYS: Dictionary = {
	KEY_F1: "knight",
	KEY_F2: "archer",
	KEY_F3: "builder",
	KEY_F4: "enemy",
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

	# Always assign (or clear) every sheet slot so transforms don't keep old art.
	_apply_sheet(unit, def, "idle_sheet", "idle_sheet")
	_apply_sheet(unit, def, "idle_up_sheet", "idle_up_sheet")
	_apply_sheet(unit, def, "idle_side_sheet", "idle_side_sheet")
	_apply_sheet(unit, def, "walk_up_sheet", "walk_up_sheet")
	_apply_sheet(unit, def, "walk_down_sheet", "walk_down_sheet")
	_apply_sheet(unit, def, "walk_side_sheet", "walk_side_sheet")
	_apply_sheet(unit, def, "attack_up_sheet", "attack_up_sheet")
	_apply_sheet(unit, def, "attack_down_sheet", "attack_down_sheet")
	_apply_sheet(unit, def, "attack_side_sheet", "attack_side_sheet")
	_apply_sheet(unit, def, "death_up_sheet", "death_up_sheet")
	_apply_sheet(unit, def, "death_down_sheet", "death_down_sheet")
	_apply_sheet(unit, def, "gather_sheet", "gather_sheet")
	_apply_sheet(unit, def, "gather_up_sheet", "gather_up_sheet")
	_apply_sheet(unit, def, "gather_side_sheet", "gather_side_sheet")

	SpriteSheetUtils.clear_cache()
	unit.rebuild_visuals()


static func _apply_sheet(unit: Unit, def: Dictionary, def_key: String, property: String) -> void:
	var path: String = def.get(def_key, "")
	if path.is_empty():
		unit.set(property, null)
		return
	var texture = load(path)
	if texture == null:
		push_warning("UnitDatabase: failed to load sheet %s for %s" % [path, def_key])
	unit.set(property, texture)
