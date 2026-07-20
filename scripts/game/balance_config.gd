class_name BalanceConfig
extends RefCounted

## Blitz pacing: short frenetic runs (~8–12 min for 5 nights).
## Opening goal: first day can afford lumber + mill + house, with a thin wall buffer.
## Ignoring either wood or food still collapses the run; military stays gold-gated.
const PHASE_DURATIONS := {
	"day": 55.0,
	"dusk": 12.0,
	"night": 45.0,
	"dawn": 10.0,
}

const WIN_NIGHTS := 5

const INITIAL_WOOD := 260
const INITIAL_GOLD := 0
const INITIAL_FOOD := 135
const INITIAL_VILLAGERS := 5

const WOOD_PER_SECOND := 1.0
const GOLD_PER_SECOND := 1.0
## ~2 farmers cover 5 starters with surplus to train; 1 farmer alone is tight.
const FOOD_PER_SECOND := 0.32
const TREE_CAPACITY := 2400
const GOLD_VEIN_CAPACITY := 900
const GOLD_MOUNTAIN_CAPACITY := 4500
const MILL_MAX_WORKERS := 3

const VILLAGER_FOOD_PER_SECOND := 1.0 / 30.0
const SQUAD_FOOD_PER_SECOND_AT_NIGHT := 1.0 / 10.0
const STARVATION_WORK_MULTIPLIER := 0.5
const STARVATION_DAMAGE_PER_SECOND := 2.0

const SQUAD_SIZE := 1
const SQUAD_FOOD_COST := 100
const SQUAD_GOLD_COST := 40
const SQUAD_TRAIN_TIME := 6.0

const GARRISON_SOLDIER_DAMAGE_WEIGHT := 1.0
const GARRISON_CIVILIAN_DAMAGE_WEIGHT := 0.35
const GARRISON_CIVILIAN_ATTACK_COOLDOWN := 1.6

const META_REWARD_PER_NIGHT := 5
const META_REWARD_VICTORY := 25
const ECLIPSE_NIGHT_DURATION_MULT := 1.4
const ECLIPSE_FOOD_UPKEEP_MULT := 1.5


static func get_gather_rate(resource_key: String) -> float:
	match resource_key:
		"wood":
			return WOOD_PER_SECOND
		"gold":
			return GOLD_PER_SECOND
		"food":
			return FOOD_PER_SECOND
	return 0.0
