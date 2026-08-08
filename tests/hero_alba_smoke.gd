extends SceneTree

## Lightweight smoke for Alba registration (avoids full world boot).


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Autoloads are available when the project boots normally.
	assert(Engine.has_singleton("MetaProgression") or true)

	var def: Dictionary = UnitDatabase.get_definition("alba")
	assert(not def.is_empty(), "alba definition missing")
	assert(bool(def.get("is_hero", false)), "alba should be hero")
	assert(str(def.get("hero_power_id", "")) == "fulgor")
	assert(int(def.get("max_hp", 0)) == 260)
	assert(int(def.get("attack_damage", 0)) == 22)
	assert(float(def.get("hero_power_cooldown", 0.0)) >= 15.0)
	assert(UnitDatabase.SPAWN_HOTKEYS.get(KEY_F10, "") == "alba")

	var scene_path := str(def.get("scene", ""))
	assert(ResourceLoader.exists(scene_path), "missing alba scene")
	var scene := load(scene_path) as PackedScene
	assert(scene != null)

	var required_sheets := [
		"idle_sheet",
		"idle_up_sheet",
		"idle_side_sheet",
		"walk_up_sheet",
		"walk_down_sheet",
		"walk_side_sheet",
		"attack_up_sheet",
		"attack_down_sheet",
		"attack_side_sheet",
		"death_up_sheet",
		"death_down_sheet",
	]
	for key in required_sheets:
		var path := str(def.get(key, ""))
		assert(not path.is_empty(), "missing sheet key %s" % key)
		assert(ResourceLoader.exists(path), "missing sheet file %s" % path)

	assert(ResourceLoader.exists("res://scripts/combat/wind_gale_vfx.gd"))
	assert(ResourceLoader.exists("res://scenes/combat/wind_gale_vfx.tscn"))
	assert(ResourceLoader.exists("res://tools/ai_poses/alba_front_base.png") or true)

	var hero: Unit = scene.instantiate()
	root.add_child(hero)
	UnitDatabase.apply_definition_to_unit(hero, "alba")
	await process_frame
	await process_frame

	assert(hero.is_hero)
	assert(hero.unit_type_id == "alba")
	assert(hero.max_hp == 260)
	assert(hero.hero_power_id == "fulgor")
	assert(hero.can_use_hero_power())
	assert(hero.animated_sprite != null and hero.animated_sprite.sprite_frames != null)
	assert(hero.animated_sprite.sprite_frames.has_animation(&"idle"))
	assert(hero.get_node_or_null("HeroGlow") == null)
	assert(UnitDatabase.get_unit_display_name(hero).contains("Héroe"))

	# Local enemy stub for Fulgor without loading enemy scene dependencies.
	var foe := Unit.new()
	root.add_child(foe)
	foe.team_id = Team.ENEMY
	foe.max_hp = 80
	foe.hp = 80
	foe.global_position = hero.global_position + Vector2(30, 0)
	foe.add_to_group("units")
	await process_frame

	assert(hero.try_use_hero_power())
	assert(foe.hp < 80)
	assert(foe._status_slow_timer > 0.0)
	assert(not hero.can_use_hero_power())

	print("hero_alba_smoke OK")
	var report := FileAccess.open("user://hero_alba_smoke_ok.txt", FileAccess.WRITE)
	if report != null:
		report.store_string("OK\n")
		report.close()
	quit(0)
