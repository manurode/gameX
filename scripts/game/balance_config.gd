class_name BalanceConfig
extends RefCounted

## Long climb: early exits are short; a full clear is a deep meta-powered run.
## Opening goal: first day can afford lumber + mill + house, with a thin wall buffer.
## Ignoring either wood or food still collapses the run; military stays gold + villager gated.
const PHASE_DURATIONS := {
	"day": 55.0,
	"dusk": 12.0,
	"night": 45.0,
	"dawn": 10.0,
}

## Survive this many nights to win. Tuned so first runs die early and upgrades unlock depth.
const WIN_NIGHTS := 20

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
## Military eats by day (not while fighting at night).
const SQUAD_FOOD_PER_SECOND_BY_DAY := 1.0 / 10.0
## Meta shop armies: still eat by day, but cheaper than trained troops.
const META_MILITARY_DAY_UPKEEP_MULT := 0.35
## Pantry brought with meta starter military (per unit).
const META_ARMY_START_FOOD_PER_UNIT := 4
const STARVATION_WORK_MULTIPLIER := 0.5
const STARVATION_DAMAGE_PER_SECOND := 1.0

const SQUAD_SIZE := 1
## Military units cost gold + 1 villager (no food to train).
const SQUAD_GOLD_COST := 40
const SQUAD_TRAIN_TIME := 6.0

const GARRISON_SOLDIER_DAMAGE_WEIGHT := 1.0
const GARRISON_CIVILIAN_DAMAGE_WEIGHT := 0.35
const GARRISON_CIVILIAN_ATTACK_COOLDOWN := 1.6

## Meta fragments: 0 before night 3, exponential climb, exactly TARGET on full clear.
const META_FRAGMENT_TARGET_VICTORY := 50
const META_FRAGMENT_REWARD_START_NIGHT := 3
const META_FRAGMENT_GROWTH := 1.15

## Night wave count: exponential in cycle number. Late nights intentionally overload.
const WAVE_BASE_COUNT := 8
const WAVE_GROWTH := 1.16
const WAVE_COUNT_CAP := 140
## Extra HP/damage per night after the first (1.0 + rate * (n-1)).
const ENEMY_NIGHT_STAT_GROWTH := 0.04

const ECLIPSE_NIGHT_DURATION_MULT := 1.4
const ECLIPSE_FOOD_UPKEEP_MULT := 1.5

## Town-center market: emergency swaps only. High fee + daily cap keep mono-gathering
## from replacing a real economy (wood/food/gold each stay necessary).
## Relative values ≈ gather scarcity + role (gold gates military; food has upkeep).
const MARKET_RESOURCE_VALUE := {
	"wood": 1.0,
	"food": 2.5,
	"gold": 3.5,
}
## Fraction of value lost on every trade (0.4 → keep 60%). Round-trips lose ~64%.
const MARKET_FEE := 0.4
## Fixed lot sizes you pay per click (meaningful commitment, not 1-unit nibbles).
const MARKET_LOT_SIZE := {
	"wood": 50,
	"food": 30,
	"gold": 25,
}
## Max successful exchanges per day cycle (resets when a new day begins).
const MARKET_TRADES_PER_CYCLE := 3


static func get_gather_rate(resource_key: String) -> float:
	match resource_key:
		"wood":
			return WOOD_PER_SECOND
		"gold":
			return GOLD_PER_SECOND
		"food":
			return FOOD_PER_SECOND
	return 0.0


## Base enemy count for a night cycle (before modifier / army pressure).
static func get_wave_base_count(cycle_number: int) -> int:
	var n := maxi(1, cycle_number)
	var count := int(round(float(WAVE_BASE_COUNT) * pow(WAVE_GROWTH, float(n - 1))))
	return clampi(count, 4, WAVE_COUNT_CAP)


## Multiplier applied to enemy HP and attack damage for the given night.
static func get_enemy_night_stat_mult(cycle_number: int) -> float:
	var n := maxi(1, cycle_number)
	return 1.0 + ENEMY_NIGHT_STAT_GROWTH * float(n - 1)


## Cumulative fragments for ending a run after surviving `nights_survived` nights.
## Victory (nights >= WIN_NIGHTS) always yields META_FRAGMENT_TARGET_VICTORY.
static func meta_fragments_for_nights(nights_survived: int) -> int:
	if nights_survived < META_FRAGMENT_REWARD_START_NIGHT:
		return 0
	var n := mini(nights_survived, WIN_NIGHTS)
	if n >= WIN_NIGHTS:
		return META_FRAGMENT_TARGET_VICTORY
	var start := META_FRAGMENT_REWARD_START_NIGHT
	var r := META_FRAGMENT_GROWTH
	var total_w := 0.0
	var earned_w := 0.0
	for i in range(start, WIN_NIGHTS + 1):
		var w := pow(r, float(i - start))
		total_w += w
		if i <= n:
			earned_w += w
	var reward := int(round(float(META_FRAGMENT_TARGET_VICTORY) * earned_w / total_w))
	# Any paying night should feel like progress.
	return maxi(1, reward)
