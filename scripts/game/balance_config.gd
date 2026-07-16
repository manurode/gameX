class_name BalanceConfig
extends RefCounted

const PHASE_DURATIONS := {
	"day": 120.0,
	"dusk": 30.0,
	"night": 60.0,
	"dawn": 30.0,
}

const INITIAL_WOOD := 2000
const INITIAL_GOLD := 2000
const INITIAL_FOOD := 1000
const INITIAL_VILLAGERS := 5

const WOOD_PER_SECOND := 1.0
const GOLD_PER_SECOND := 1.0
const FOOD_PER_SECOND := 0.25
const TREE_CAPACITY := 2400
const GOLD_VEIN_CAPACITY := 900
const MILL_MAX_WORKERS := 3

const VILLAGER_FOOD_PER_SECOND := 1.0 / 30.0
const SQUAD_FOOD_PER_SECOND_AT_NIGHT := 1.0 / 10.0
const STARVATION_WORK_MULTIPLIER := 0.5
const STARVATION_DAMAGE_PER_SECOND := 2.0

const SQUAD_SIZE := 5
const SQUAD_FOOD_COST := 120
const SQUAD_GOLD_COST := 40
const SQUAD_TRAIN_TIME := 6.0

const GARRISON_SOLDIER_DAMAGE_WEIGHT := 1.0
const GARRISON_CIVILIAN_DAMAGE_WEIGHT := 0.35
const GARRISON_CIVILIAN_ATTACK_COOLDOWN := 1.6


static func get_gather_rate(resource_key: String) -> float:
	match resource_key:
		"wood":
			return WOOD_PER_SECOND
		"gold":
			return GOLD_PER_SECOND
		"food":
			return FOOD_PER_SECOND
	return 0.0
