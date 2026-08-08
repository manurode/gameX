class_name HeroDatabase
extends RefCounted

## Roster of playable heroes. Add new entries here; unit combat stats live in UnitDatabase.
## Each hero has exactly 3 powers: the first unlocks at start, the rest via campaign wins.

const DEFAULT_HERO_ID := "alba"

const HEROES: Dictionary = {
	"alba": {
		"id": "alba",
		"unit_type_id": "alba",
		"name": "Alba",
		"title": "Guardiana del Amanecer",
		"role": "Melee · Luz",
		"blurb": "Líder del asentamiento. Tanque de luz que abre hueco en las oleadas con Fulgor.",
		"accent": Color(1.0, 0.9, 0.55, 1.0),
		"powers": [
			{
				"id": "fulgor",
				"name": "Fulgor",
				"key": "R",
				"description": "Pulso de luz: 28 daño en área y ralentiza un 35% durante 2.5s.",
				"unlock": "start",
			},
			{
				"id": "aurora",
				"name": "Aurora",
				"key": "R",
				"description": "Haz sanador: restaura vitalidad a aliados cercanos.",
				"unlock": "win",
				"wins_required": 1,
			},
			{
				"id": "solsticio",
				"name": "Solsticio",
				"key": "R",
				"description": "Estallido solar que aturde enemigos en un radio amplio.",
				"unlock": "win",
				"wins_required": 2,
			},
		],
	},
}


static func get_all_hero_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in HEROES.keys():
		ids.append(str(key))
	ids.sort()
	return ids


static func has_hero(hero_id: String) -> bool:
	return HEROES.has(hero_id)


static func get_definition(hero_id: String) -> Dictionary:
	if HEROES.has(hero_id):
		return HEROES[hero_id]
	return HEROES.get(DEFAULT_HERO_ID, {})


static func resolve_hero_id(hero_id: String) -> String:
	if has_hero(hero_id):
		return hero_id
	return DEFAULT_HERO_ID


static func get_unit_type_id(hero_id: String) -> String:
	var def := get_definition(hero_id)
	return str(def.get("unit_type_id", resolve_hero_id(hero_id)))


static func get_display_name(hero_id: String) -> String:
	return str(get_definition(hero_id).get("name", hero_id.capitalize()))


static func get_powers(hero_id: String) -> Array:
	var def := get_definition(hero_id)
	var powers: Array = def.get("powers", [])
	return powers.duplicate(true)


static func get_power(hero_id: String, power_id: String) -> Dictionary:
	for power in get_powers(hero_id):
		if str(power.get("id", "")) == power_id:
			return power
	return {}


## Combat stats for hero cards (sourced from the unit definition).
static func get_card_stats(hero_id: String) -> Dictionary:
	var unit_type := get_unit_type_id(hero_id)
	var unit_def := UnitDatabase.get_definition(unit_type)
	return {
		"max_hp": int(unit_def.get("max_hp", 0)),
		"attack_damage": int(unit_def.get("attack_damage", 0)),
		"move_speed": float(unit_def.get("move_speed", 0.0)),
		"attack_cooldown": float(unit_def.get("attack_cooldown", 0.0)),
	}


static func get_portrait(hero_id: String) -> Texture2D:
	return UnitDatabase.get_unit_icon(get_unit_type_id(hero_id))


static func is_power_unlocked_by_default(power: Dictionary) -> bool:
	return str(power.get("unlock", "start")) == "start"


static func get_power_wins_required(power: Dictionary) -> int:
	if is_power_unlocked_by_default(power):
		return 0
	return maxi(1, int(power.get("wins_required", 1)))
