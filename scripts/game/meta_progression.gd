extends Node

signal fragments_changed(amount: int)
signal unlocks_changed

const SAVE_PATH := "user://meta_progression.cfg"

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
		"description": "Empiezas con 6 torres extra y 16 segmentos de muro.",
		"cost": 400,
	},
}

var fragments: int = 0
var unlocked: Dictionary = {}
## Best nights survived in a single run.
var best_nights: int = 0
## Times the player completed a full WIN_NIGHTS run.
var wins: int = 0


func _ready() -> void:
	load_save()


func load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	fragments = int(cfg.get_value("meta", "fragments", 0))
	best_nights = int(cfg.get_value("meta", "best_nights", 0))
	wins = int(cfg.get_value("meta", "wins", 0))
	var unlocked_ids: Array = cfg.get_value("meta", "unlocked", [])
	unlocked.clear()
	for id in unlocked_ids:
		unlocked[str(id)] = true
	fragments_changed.emit(fragments)
	unlocks_changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "fragments", fragments)
	cfg.set_value("meta", "best_nights", best_nights)
	cfg.set_value("meta", "wins", wins)
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
	var bonus := 50 if is_unlocked("start_wood") else 0
	if is_unlocked("war_chest"):
		bonus += 150
	return bonus


func get_start_food_bonus() -> int:
	var bonus := 25 if is_unlocked("start_food") else 0
	if is_unlocked("war_chest"):
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
	if is_unlocked("start_gold"):
		bonus += 15
	if is_unlocked("start_gold_cache"):
		bonus += 60
	if is_unlocked("war_chest"):
		bonus += 100
	return bonus


func get_extra_villagers() -> int:
	return 1 if is_unlocked("extra_villager") else 0


func get_gather_multiplier() -> float:
	var mult := 1.0
	if is_unlocked("gather_boost"):
		mult *= 1.05
	if is_unlocked("gather_mastery"):
		mult *= 1.10
	return mult


func get_knight_hp_bonus() -> int:
	return 15 if is_unlocked("knight_hp") else 0


func get_archer_damage_bonus() -> int:
	return 3 if is_unlocked("archer_dmg") else 0


func get_mage_chain_target_bonus() -> int:
	return 1 if is_unlocked("mage_chain") else 0


func get_mage_chain_damage_bonus() -> int:
	return 2 if is_unlocked("mage_chain") else 0


func get_population_cap_bonus() -> int:
	var bonus := 0
	if is_unlocked("pop_surge"):
		bonus += 8
	# Housing for meta-spawned military so armies do not softlock population.
	bonus += get_starter_knight_count()
	bonus += get_starter_archer_count()
	bonus += get_starter_mage_count()
	return bonus


func get_starter_knight_count() -> int:
	var count := 0
	if is_unlocked("knight_guard"):
		count += 3
	if is_unlocked("knight_company"):
		count += 8
	if is_unlocked("knight_legion"):
		count += 20
	return count


func get_starter_archer_count() -> int:
	var count := 0
	if is_unlocked("archer_patrol"):
		count += 4
	if is_unlocked("archer_company"):
		count += 10
	return count


func get_starter_mage_count() -> int:
	var count := 0
	if is_unlocked("mage_coven"):
		count += 5
	if is_unlocked("mage_company"):
		count += 8
	if is_unlocked("mage_academy"):
		count += 15
	return count


func get_starter_tower_count() -> int:
	var count := 0
	if is_unlocked("free_tower"):
		count += 1
	if is_unlocked("bastion_outpost"):
		count += 1
	if is_unlocked("grand_bastion"):
		count += 6
	return count


func get_starter_wall_segments() -> int:
	var count := 0
	if is_unlocked("starter_walls"):
		count += 4
	if is_unlocked("grand_bastion"):
		count += 16
	return count


func has_free_tower() -> bool:
	return get_starter_tower_count() > 0


func has_starter_walls() -> bool:
	return get_starter_wall_segments() > 0


func has_free_curfew() -> bool:
	return is_unlocked("free_curfew")


func has_foresight() -> bool:
	return is_unlocked("foresight")
