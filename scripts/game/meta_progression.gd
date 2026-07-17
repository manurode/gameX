extends Node

signal fragments_changed(amount: int)
signal unlocks_changed

const SAVE_PATH := "user://meta_progression.cfg"

const UNLOCKS := {
	"extra_villager": {
		"name": "Aldeano extra",
		"description": "Empiezas con +1 aldeano.",
		"cost": 30,
	},
	"start_wood": {
		"name": "Reserva de madera",
		"description": "Empiezas con +50 madera.",
		"cost": 20,
	},
	"start_food": {
		"name": "Despensa",
		"description": "Empiezas con +25 comida.",
		"cost": 20,
	},
	"gather_boost": {
		"name": "Herramientas mejores",
		"description": "Recolección permanente +5%.",
		"cost": 40,
	},
	"free_tower": {
		"name": "Atalaya inicial",
		"description": "Empiezas con 1 torre cerca del centro.",
		"cost": 50,
	},
	"starter_walls": {
		"name": "Empalizada",
		"description": "Empiezas con 4 segmentos de muro.",
		"cost": 45,
	},
	"knight_hp": {
		"name": "Armadura de caballero",
		"description": "Los caballeros tienen +15 HP.",
		"cost": 35,
	},
	"free_curfew": {
		"name": "Toque de queda gratis",
		"description": "Activa el toque de queda gratis en el primer atardecer.",
		"cost": 25,
	},
	"foresight": {
		"name": "Presagio",
		"description": "Ves el modificador de la próxima noche con antelación.",
		"cost": 40,
	},
}

var fragments: int = 0
var unlocked: Dictionary = {}


func _ready() -> void:
	load_save()


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	fragments = int(cfg.get_value("meta", "fragments", 0))
	var unlocked_ids: Array = cfg.get_value("meta", "unlocked", [])
	unlocked.clear()
	for id in unlocked_ids:
		unlocked[str(id)] = true
	fragments_changed.emit(fragments)
	unlocks_changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "fragments", fragments)
	cfg.set_value("meta", "unlocked", unlocked.keys())
	cfg.save(SAVE_PATH)


func is_unlocked(id: String) -> bool:
	return unlocked.get(id, false)


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
	save()
	fragments_changed.emit(fragments)
	unlocks_changed.emit()
	return true


func award_run_rewards(nights_survived: int, victory: bool) -> int:
	var reward := nights_survived * BalanceConfig.META_REWARD_PER_NIGHT
	if victory:
		reward += BalanceConfig.META_REWARD_VICTORY
	if reward <= 0:
		return 0
	fragments += reward
	save()
	fragments_changed.emit(fragments)
	return reward


func get_start_wood_bonus() -> int:
	return 50 if is_unlocked("start_wood") else 0


func get_start_food_bonus() -> int:
	return 25 if is_unlocked("start_food") else 0


func get_extra_villagers() -> int:
	return 1 if is_unlocked("extra_villager") else 0


func get_gather_multiplier() -> float:
	return 1.05 if is_unlocked("gather_boost") else 1.0


func get_knight_hp_bonus() -> int:
	return 15 if is_unlocked("knight_hp") else 0


func has_free_tower() -> bool:
	return is_unlocked("free_tower")


func has_starter_walls() -> bool:
	return is_unlocked("starter_walls")


func has_free_curfew() -> bool:
	return is_unlocked("free_curfew")


func has_foresight() -> bool:
	return is_unlocked("foresight")
