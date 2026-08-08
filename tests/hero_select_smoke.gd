extends Node

## Run via hero_select_smoke.tscn so autoloads (GameSettings / MetaProgression) compile.


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var ids := HeroDatabase.get_all_hero_ids()
	assert(ids.size() >= 1, "expected at least one hero")
	assert(HeroDatabase.has_hero("alba"))

	var alba := HeroDatabase.get_definition("alba")
	assert(not alba.is_empty())
	assert(str(alba.get("unit_type_id", "")) == "alba")
	var powers: Array = HeroDatabase.get_powers("alba")
	assert(powers.size() == 3, "each hero should define 3 powers")
	assert(HeroDatabase.is_power_unlocked_by_default(powers[0]))
	assert(not HeroDatabase.is_power_unlocked_by_default(powers[1]))
	assert(HeroDatabase.get_power_wins_required(powers[1]) >= 1)
	assert(HeroDatabase.get_power_wins_required(powers[2]) >= 2)

	var stats := HeroDatabase.get_card_stats("alba")
	assert(int(stats.get("max_hp", 0)) == 260)
	assert(int(stats.get("attack_damage", 0)) == 22)
	assert(HeroDatabase.get_portrait("alba") != null)
	assert(HeroDatabase.resolve_hero_id("missing") == HeroDatabase.DEFAULT_HERO_ID)

	assert(MetaProgression.is_hero_power_unlocked("alba", "fulgor"))
	assert(not MetaProgression.is_hero_power_unlocked("alba", "aurora") or MetaProgression.wins >= 1)
	assert(not str(GameSettings.selected_hero_id).is_empty())

	print("hero_select_smoke OK")
	var report := FileAccess.open("user://hero_select_smoke_ok.txt", FileAccess.WRITE)
	if report != null:
		report.store_string("OK\n")
		report.close()
	get_tree().quit(0)
