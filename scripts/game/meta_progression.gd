extends Node

signal fragments_changed(amount: int)
signal unlocks_changed
signal slots_changed

const SLOT_COUNT := 3
const SAVE_PATH := "user://save_slots.cfg"
const LEGACY_SAVE_PATH := "user://meta_progression.cfg"

## Permanent shop unlocks, ordered cheap → epic.
## Economy: victory = 50 frags; night 10 ≈ 9; night 15 ≈ 23.
## Early buys feel reachable after a few short runs; legion/academy need many clears.
const UNLOCKS := {
	# --- Tier 1: primeros pasos (pocos fragmentos) ---
	"start_food": {
		"name": "Despensa",
		"description": "Empiezas con +25 comida.",
		"cost": 4,
	},
	"start_wood": {
		"name": "Reserva de madera",
		"description": "Empiezas con +50 madera.",
		"cost": 5,
	},
	"start_gold": {
		"name": "Monedas de viaje",
		"description": "Empiezas con +15 oro.",
		"cost": 6,
	},
	"knight_hp": {
		"name": "Armadura de caballero",
		"description": "Los caballeros tienen +15 HP.",
		"cost": 12,
	},
	# --- Tier 2: asentamiento ---
	"extra_villager": {
		"name": "Aldeano extra",
		"description": "Empiezas con +1 aldeano.",
		"cost": 25,
	},
	"gather_boost": {
		"name": "Herramientas mejores",
		"description": "Recolección permanente +5%.",
		"cost": 30,
	},
	"foresight": {
		"name": "Presagio",
		"description": "Ves modificador, dirección y número de enemigos de la próxima noche.",
		"cost": 35,
	},
	"starter_walls": {
		"name": "Empalizada",
		"description": "Empiezas con 4 segmentos de muro.",
		"cost": 40,
	},
	"free_tower": {
		"name": "Atalaya inicial",
		"description": "Empiezas con 1 torre cerca del centro.",
		"cost": 45,
	},
	"archer_dmg": {
		"name": "Puntas afiladas",
		"description": "Los arqueros infligen +3 de daño.",
		"cost": 50,
	},
	"mage_chain": {
		"name": "Relámpago mayor",
		"description": "Los magos encadenan +1 objetivo y +2 daño de cadena.",
		"cost": 55,
	},
	# --- Tier 3: poder de campaña ---
	"extra_gather_worker": {
		"name": "Cuadrillas ampliadas",
		"description": "+1 trabajador máximo en todos los edificios de recolección.",
		"cost": 70,
	},
	"pop_surge": {
		"name": "Asentamiento amplio",
		"description": "Límite de población base +8.",
		"cost": 80,
	},
	"start_gold_cache": {
		"name": "Tesoro del clan",
		"description": "Empiezas con +60 oro.",
		"cost": 90,
	},
	"gather_mastery": {
		"name": "Maestría recolectora",
		"description": "Recolección permanente +10% adicional.",
		"cost": 100,
	},
	"knight_guard": {
		"name": "Guardia de honor",
		"description": "Empiezas con 3 caballeros.",
		"cost": 110,
	},
	"archer_patrol": {
		"name": "Patrulla de arqueros",
		"description": "Empiezas con 4 arqueros.",
		"cost": 120,
	},
	"bastion_outpost": {
		"name": "Puesto avanzado",
		"description": "Empiezas con 1 torre extra.",
		"cost": 130,
	},
	"mage_coven": {
		"name": "Círculo de magos",
		"description": "Empiezas con 5 magos.",
		"cost": 160,
	},
	# --- Tier 4: épicos (cientos de fragmentos) ---
	"war_chest": {
		"name": "Cofre de guerra",
		"description": "Empiezas con +150 madera, +80 comida y +100 oro.",
		"cost": 220,
	},
	"knight_company": {
		"name": "Compañía de caballeros",
		"description": "Empiezas con 8 caballeros.",
		"cost": 250,
	},
	"archer_company": {
		"name": "Compañía de arqueros",
		"description": "Empiezas con 10 arqueros.",
		"cost": 270,
	},
	"mage_company": {
		"name": "Cónclave arcano",
		"description": "Empiezas con 8 magos.",
		"cost": 290,
	},
	"knight_legion": {
		"name": "Legión de caballeros",
		"description": "Empiezas con 20 caballeros.",
		"cost": 350,
	},
	"mage_academy": {
		"name": "Academia arcana",
		"description": "Empiezas con 15 magos.",
		"cost": 380,
	},
	"grand_bastion": {
		"name": "Gran bastión",
		"description": "Empiezas con 6 torres extra, 20 segmentos de muro y una puerta.",
		"cost": 400,
	},
}

## Active slot index, or -1 when none is selected.
var active_slot: int = -1
## Slot metadata mirrors: { occupied, name, fragments, unlocked, best_nights, wins, difficulty }
var _slots: Array[Dictionary] = []

var fragments: int = 0
var unlocked: Dictionary = {}
## Purchased unlocks the player wants applied this run (id -> true). Default on after buy.
var enabled: Dictionary = {}
## Best nights survived in a single run.
var best_nights: int = 0
## Times the player completed a full WIN_NIGHTS run.
var wins: int = 0
var save_name: String = ""


func _ready() -> void:
	_init_empty_slots()
	load_all_slots()


func _init_empty_slots() -> void:
	_slots.clear()
	for i in SLOT_COUNT:
		_slots.append(_make_empty_slot_data())


func _make_empty_slot_data() -> Dictionary:
	return {
		"occupied": false,
		"name": "",
		"fragments": 0,
		"unlocked": {},
		"enabled": {},
		"best_nights": 0,
		"wins": 0,
		"difficulty": int(GameSettingsData.Difficulty.BEGINNER),
	}


func load_all_slots() -> void:
	_init_empty_slots()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		# Legacy global preference (pre per-slot); used only as fallback for old slots.
		var legacy_fallback := int(GameSettingsData.Difficulty.BEGINNER)
		if cfg.has_section_key("settings", "difficulty"):
			legacy_fallback = _clamp_difficulty(int(cfg.get_value("settings", "difficulty", legacy_fallback)))
		for i in SLOT_COUNT:
			var section := "slot_%d" % i
			if not cfg.has_section(section):
				continue
			if not bool(cfg.get_value(section, "occupied", false)):
				continue
			var unlocked_dict := _unlocked_from_ids(cfg.get_value(section, "unlocked", []))
			_slots[i] = {
				"occupied": true,
				"name": str(cfg.get_value(section, "name", "Partida %d" % (i + 1))),
				"fragments": int(cfg.get_value(section, "fragments", 0)),
				"unlocked": unlocked_dict,
				"enabled": _enabled_from_save(
					cfg.get_value(section, "enabled", null),
					unlocked_dict
				),
				"best_nights": int(cfg.get_value(section, "best_nights", 0)),
				"wins": int(cfg.get_value(section, "wins", 0)),
				"difficulty": _clamp_difficulty(int(cfg.get_value(section, "difficulty", legacy_fallback))),
			}
	else:
		_migrate_legacy_save()
	_clear_active_runtime()
	slots_changed.emit()


func _clamp_difficulty(raw: int) -> int:
	if raw < int(GameSettingsData.Difficulty.BEGINNER) or raw > int(GameSettingsData.Difficulty.EXPERT):
		return int(GameSettingsData.Difficulty.BEGINNER)
	return raw


## Persist the active slot's difficulty when starting a run.
func save_slot_difficulty(diff: GameSettingsData.Difficulty) -> void:
	if not has_active_slot():
		return
	var clamped := _clamp_difficulty(int(diff))
	_slots[active_slot]["difficulty"] = clamped
	GameSettings.difficulty = clamped as GameSettingsData.Difficulty
	_persist_all_slots()


func _migrate_legacy_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LEGACY_SAVE_PATH) != OK:
		return
	var unlocked_ids: Array = cfg.get_value("meta", "unlocked", [])
	var unlocked_dict := _unlocked_from_ids(unlocked_ids)
	_slots[0] = {
		"occupied": true,
		"name": "Partida 1",
		"fragments": int(cfg.get_value("meta", "fragments", 0)),
		"unlocked": unlocked_dict,
		"enabled": _enabled_from_unlocked(unlocked_dict),
		"best_nights": int(cfg.get_value("meta", "best_nights", 0)),
		"wins": int(cfg.get_value("meta", "wins", 0)),
		"difficulty": int(GameSettingsData.Difficulty.BEGINNER),
	}
	_persist_all_slots()


func _unlocked_from_ids(unlocked_ids: Array) -> Dictionary:
	var result := {}
	for id in unlocked_ids:
		result[str(id)] = true
	return result


## Migrate missing enabled lists: all owned unlocks start active.
func _enabled_from_unlocked(unlocked_dict: Dictionary) -> Dictionary:
	var result := {}
	for id in unlocked_dict.keys():
		result[str(id)] = true
	return result


func _enabled_from_save(raw_enabled: Variant, unlocked_dict: Dictionary) -> Dictionary:
	if raw_enabled == null:
		return _enabled_from_unlocked(unlocked_dict)
	var active := {}
	if raw_enabled is Array:
		for id in raw_enabled as Array:
			active[str(id)] = true
	elif raw_enabled is Dictionary:
		for id in (raw_enabled as Dictionary).keys():
			if bool((raw_enabled as Dictionary)[id]):
				active[str(id)] = true
	else:
		return _enabled_from_unlocked(unlocked_dict)
	var result := {}
	for id in unlocked_dict.keys():
		var key := str(id)
		result[key] = active.get(key, false)
	return result


func _persist_all_slots() -> void:
	var cfg := ConfigFile.new()
	for i in SLOT_COUNT:
		var section := "slot_%d" % i
		var data: Dictionary = _slots[i]
		cfg.set_value(section, "occupied", bool(data.get("occupied", false)))
		cfg.set_value(section, "name", str(data.get("name", "")))
		cfg.set_value(section, "fragments", int(data.get("fragments", 0)))
		cfg.set_value(section, "best_nights", int(data.get("best_nights", 0)))
		cfg.set_value(section, "wins", int(data.get("wins", 0)))
		cfg.set_value(
			section,
			"difficulty",
			_clamp_difficulty(int(data.get("difficulty", GameSettingsData.Difficulty.BEGINNER)))
		)
		var unlocked_dict: Dictionary = data.get("unlocked", {})
		cfg.set_value(section, "unlocked", unlocked_dict.keys())
		var enabled_dict: Dictionary = data.get("enabled", {})
		var active_ids: Array = []
		for id in unlocked_dict.keys():
			var key := str(id)
			if bool(enabled_dict.get(key, true)):
				active_ids.append(key)
		cfg.set_value(section, "enabled", active_ids)
	cfg.save(SAVE_PATH)


func _clear_active_runtime() -> void:
	active_slot = -1
	save_name = ""
	fragments = 0
	unlocked.clear()
	enabled.clear()
	best_nights = 0
	wins = 0
	GameSettings.difficulty = GameSettingsData.Difficulty.BEGINNER


func get_slot_count() -> int:
	return SLOT_COUNT


func is_slot_occupied(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return false
	return bool(_slots[slot_index].get("occupied", false))


func get_slot_summary(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return _make_empty_slot_data()
	var data: Dictionary = _slots[slot_index]
	return {
		"occupied": bool(data.get("occupied", false)),
		"name": str(data.get("name", "")),
		"fragments": int(data.get("fragments", 0)),
		"best_nights": int(data.get("best_nights", 0)),
		"wins": int(data.get("wins", 0)),
		"difficulty": _clamp_difficulty(int(data.get("difficulty", GameSettingsData.Difficulty.BEGINNER))),
	}


func get_slot_record_text(slot_index: int) -> String:
	var summary := get_slot_summary(slot_index)
	if not summary.occupied:
		return ""
	var slot_best: int = summary.best_nights
	var slot_wins: int = summary.wins
	if slot_best >= BalanceConfig.WIN_NIGHTS or slot_wins > 0:
		return "Partidas ganadas: %d" % slot_wins
	if slot_best > 0:
		return "Récord: %d noches" % slot_best
	return "Sin récord aún"


func select_slot(slot_index: int) -> bool:
	if not is_slot_occupied(slot_index):
		return false
	_apply_slot_to_runtime(slot_index)
	fragments_changed.emit(fragments)
	unlocks_changed.emit()
	return true


func create_slot(slot_index: int, name: String) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return false
	if is_slot_occupied(slot_index):
		return false
	var cleaned := name.strip_edges()
	if cleaned.is_empty():
		cleaned = "Partida %d" % (slot_index + 1)
	_slots[slot_index] = {
		"occupied": true,
		"name": cleaned,
		"fragments": 0,
		"unlocked": {},
		"enabled": {},
		"best_nights": 0,
		"wins": 0,
		"difficulty": int(GameSettingsData.Difficulty.BEGINNER),
	}
	_persist_all_slots()
	_apply_slot_to_runtime(slot_index)
	slots_changed.emit()
	fragments_changed.emit(fragments)
	unlocks_changed.emit()
	return true


func delete_slot(slot_index: int) -> bool:
	if not is_slot_occupied(slot_index):
		return false
	_slots[slot_index] = _make_empty_slot_data()
	_persist_all_slots()
	if active_slot == slot_index:
		_clear_active_runtime()
		fragments_changed.emit(fragments)
		unlocks_changed.emit()
	slots_changed.emit()
	return true


func _apply_slot_to_runtime(slot_index: int) -> void:
	var data: Dictionary = _slots[slot_index]
	active_slot = slot_index
	save_name = str(data.get("name", ""))
	fragments = int(data.get("fragments", 0))
	best_nights = int(data.get("best_nights", 0))
	wins = int(data.get("wins", 0))
	unlocked = (data.get("unlocked", {}) as Dictionary).duplicate()
	enabled = (data.get("enabled", {}) as Dictionary).duplicate()
	var diff := _clamp_difficulty(int(data.get("difficulty", GameSettingsData.Difficulty.BEGINNER)))
	GameSettings.difficulty = diff as GameSettingsData.Difficulty


func has_active_slot() -> bool:
	return active_slot >= 0 and is_slot_occupied(active_slot)


## Kept for compatibility; reloads all slots from disk.
func load_save() -> void:
	load_all_slots()
	if has_active_slot():
		_apply_slot_to_runtime(active_slot)
		fragments_changed.emit(fragments)
		unlocks_changed.emit()


func save() -> void:
	if not has_active_slot():
		return
	var slot_diff := _clamp_difficulty(int(
		_slots[active_slot].get("difficulty", GameSettingsData.Difficulty.BEGINNER)
	))
	_slots[active_slot] = {
		"occupied": true,
		"name": save_name,
		"fragments": fragments,
		"unlocked": unlocked.duplicate(),
		"enabled": enabled.duplicate(),
		"best_nights": best_nights,
		"wins": wins,
		"difficulty": slot_diff,
	}
	_persist_all_slots()


func is_unlocked(id: String) -> bool:
	return unlocked.get(id, false)


## Owned and toggled on for the next run.
func is_enabled(id: String) -> bool:
	if not is_unlocked(id):
		return false
	return bool(enabled.get(id, true))


func set_unlock_enabled(id: String, value: bool) -> bool:
	if not is_unlocked(id):
		return false
	enabled[id] = value
	save()
	unlocks_changed.emit()
	return true


func can_purchase(id: String) -> bool:
	if is_unlocked(id) or not UNLOCKS.has(id):
		return false
	return fragments >= int(UNLOCKS[id].get("cost", 0))


func purchase(id: String) -> bool:
	if not can_purchase(id):
		return false
	var cost := int(UNLOCKS[id].get("cost", 0))
	fragments -= cost
	unlocked[id] = true
	enabled[id] = true
	save()
	fragments_changed.emit(fragments)
	unlocks_changed.emit()
	return true


func award_run_rewards(nights_survived: int, victory: bool) -> int:
	var nights := nights_survived
	if victory:
		nights = maxi(nights, BalanceConfig.WIN_NIGHTS)
	best_nights = maxi(best_nights, nights)
	if victory:
		wins += 1
	var reward := BalanceConfig.meta_fragments_for_nights(nights)
	if reward <= 0:
		# Still persist records even when the run yields no fragments.
		save()
		return 0
	reward = maxi(1, int(round(float(reward) * GameSettings.get_fragment_reward_mult())))
	fragments += reward
	save()
	fragments_changed.emit(fragments)
	return reward


## Text for the campaign setup screen: nights record, or wins after beating WIN_NIGHTS.
func get_record_display_text() -> String:
	if best_nights >= BalanceConfig.WIN_NIGHTS or wins > 0:
		return "Partidas ganadas: %d" % wins
	if best_nights > 0:
		return "Récord de supervivencia - %d noches" % best_nights
	return ""


func get_start_wood_bonus() -> int:
	var bonus := 50 if is_enabled("start_wood") else 0
	if is_enabled("war_chest"):
		bonus += 150
	return bonus


func get_start_food_bonus() -> int:
	var bonus := 25 if is_enabled("start_food") else 0
	if is_enabled("war_chest"):
		bonus += 80
	# Pantry that arrives with meta armies (not run-boon troops).
	bonus += get_starter_military_count() * BalanceConfig.META_ARMY_START_FOOD_PER_UNIT
	return bonus


func get_starter_military_count() -> int:
	return (
		get_starter_knight_count()
		+ get_starter_archer_count()
		+ get_starter_mage_count()
	)


func get_start_gold_bonus() -> int:
	var bonus := 0
	if is_enabled("start_gold"):
		bonus += 15
	if is_enabled("start_gold_cache"):
		bonus += 60
	if is_enabled("war_chest"):
		bonus += 100
	return bonus


func get_extra_villagers() -> int:
	return 1 if is_enabled("extra_villager") else 0


func get_gather_multiplier() -> float:
	var mult := 1.0
	if is_enabled("gather_boost"):
		mult *= 1.05
	if is_enabled("gather_mastery"):
		mult *= 1.10
	return mult


func get_gather_max_workers_bonus() -> int:
	return 1 if is_enabled("extra_gather_worker") else 0


func get_knight_hp_bonus() -> int:
	return 15 if is_enabled("knight_hp") else 0


func get_archer_damage_bonus() -> int:
	return 3 if is_enabled("archer_dmg") else 0


func get_mage_chain_target_bonus() -> int:
	return 1 if is_enabled("mage_chain") else 0


func get_mage_chain_damage_bonus() -> int:
	return 2 if is_enabled("mage_chain") else 0


func get_population_cap_bonus() -> int:
	var bonus := 0
	if is_enabled("pop_surge"):
		bonus += 8
	# Housing for meta-spawned military so armies do not softlock population.
	bonus += get_starter_knight_count()
	bonus += get_starter_archer_count()
	bonus += get_starter_mage_count()
	return bonus


func get_starter_knight_count() -> int:
	var count := 0
	if is_enabled("knight_guard"):
		count += 3
	if is_enabled("knight_company"):
		count += 8
	if is_enabled("knight_legion"):
		count += 20
	return count


func get_starter_archer_count() -> int:
	var count := 0
	if is_enabled("archer_patrol"):
		count += 4
	if is_enabled("archer_company"):
		count += 10
	return count


func get_starter_mage_count() -> int:
	var count := 0
	if is_enabled("mage_coven"):
		count += 5
	if is_enabled("mage_company"):
		count += 8
	if is_enabled("mage_academy"):
		count += 15
	return count


func get_starter_tower_count() -> int:
	var count := 0
	if is_enabled("free_tower"):
		count += 1
	if is_enabled("bastion_outpost"):
		count += 1
	if is_enabled("grand_bastion"):
		count += 6
	return count


func get_starter_wall_segments() -> int:
	var count := 0
	if is_enabled("starter_walls"):
		count += 4
	if is_enabled("grand_bastion"):
		count += 20
	return count


func has_free_tower() -> bool:
	return get_starter_tower_count() > 0


func has_starter_walls() -> bool:
	return get_starter_wall_segments() > 0


func has_starter_gate() -> bool:
	return is_enabled("grand_bastion")


func has_free_curfew() -> bool:
	return is_enabled("free_curfew")


func has_foresight() -> bool:
	return is_enabled("foresight")


func get_unlocked_upgrade_names() -> Array[String]:
	var names: Array[String] = []
	for id in UNLOCKS:
		if is_enabled(id):
			names.append(str(UNLOCKS[id].get("name", id)))
	return names


func get_unlocked_upgrade_descriptions() -> Array[String]:
	var descriptions: Array[String] = []
	for id in UNLOCKS:
		if is_enabled(id):
			descriptions.append(str(UNLOCKS[id].get("description", "")))
	return descriptions
