class_name RunBoonManager
extends Node

signal boon_choices_ready(choices: Array)
signal boon_applied(boon_id: String)
signal gather_multiplier_changed(multiplier: float)

const BOON_DEFS := {
	"gather_surge": {
		"name": "Cosecha abundante",
		"description": "+20% recolección durante el próximo día.",
	},
	"free_walls": {
		"name": "Muros de fortuna",
		"description": "4 segmentos de muro aparecen junto al centro.",
	},
	"free_tower": {
		"name": "Torre de guardia",
		"description": "Una torre aparece cerca del centro urbano.",
	},
	"extra_villagers": {
		"name": "Refugiados",
		"description": "2 aldeanos se unen a tu asentamiento.",
	},
	"temp_archers": {
		"name": "Arqueros de paso",
		"description": "3 arqueros temporales aparecen cerca del centro.",
	},
	"auto_curfew": {
		"name": "Toque de queda",
		"description": "Activa el toque de queda ahora.",
	},
	"resource_cache": {
		"name": "Botín recuperado",
		"description": "+80 madera y +40 oro.",
	},
}

var gather_multiplier: float = 1.0
var _pending_choices: Array[String] = []
var _awaiting_choice: bool = false
var _day_night: DayNightManager
var _game_world: Node
var _curfew_manager: CurfewManager
var _resource_manager: ResourceManager
var _used_this_dawn: bool = false


func _ready() -> void:
	add_to_group("run_boon_manager")


func setup(
	day_night: DayNightManager,
	game_world: Node,
	curfew_manager: CurfewManager,
	resource_manager: ResourceManager
) -> void:
	_day_night = day_night
	_game_world = game_world
	_curfew_manager = curfew_manager
	_resource_manager = resource_manager
	if not _day_night.cycle_changed.is_connected(_on_cycle_changed):
		_day_night.cycle_changed.connect(_on_cycle_changed)


func is_awaiting_choice() -> bool:
	return _awaiting_choice


func get_gather_multiplier() -> float:
	return gather_multiplier


func offer_dawn_boons() -> void:
	if _awaiting_choice or _used_this_dawn:
		return
	if _day_night != null and _day_night.nights_survived >= BalanceConfig.WIN_NIGHTS:
		return
	_used_this_dawn = true
	_pending_choices = _roll_choices(3)
	_awaiting_choice = true
	if _day_night != null:
		_day_night.automatic_cycle = false
	boon_choices_ready.emit(_pending_choices)


func select_boon(boon_id: String) -> void:
	if not _awaiting_choice:
		return
	if boon_id not in _pending_choices and not BOON_DEFS.has(boon_id):
		return
	_awaiting_choice = false
	_pending_choices.clear()
	_apply_boon(boon_id)
	if _day_night != null:
		_day_night.automatic_cycle = true
	boon_applied.emit(boon_id)


func get_boon_def(boon_id: String) -> Dictionary:
	return BOON_DEFS.get(boon_id, {})


func _on_cycle_changed(phase: DayNightManager.CyclePhase) -> void:
	match phase:
		DayNightManager.CyclePhase.DAWN:
			_used_this_dawn = false
			offer_dawn_boons()
		DayNightManager.CyclePhase.DUSK, DayNightManager.CyclePhase.NIGHT:
			if gather_multiplier != 1.0:
				gather_multiplier = 1.0
				gather_multiplier_changed.emit(gather_multiplier)


func _roll_choices(count: int) -> Array[String]:
	var pool: Array[String] = []
	for key in BOON_DEFS.keys():
		pool.append(str(key))
	pool.shuffle()
	var choices: Array[String] = []
	for i in mini(count, pool.size()):
		choices.append(pool[i])
	return choices


func _apply_boon(boon_id: String) -> void:
	match boon_id:
		"gather_surge":
			gather_multiplier = 1.2
			gather_multiplier_changed.emit(gather_multiplier)
		"free_walls":
			if _game_world != null and _game_world.has_method("spawn_starter_walls"):
				_game_world.call("spawn_starter_walls", 4)
		"free_tower":
			if _game_world != null and _game_world.has_method("spawn_free_tower"):
				_game_world.call("spawn_free_tower")
		"extra_villagers":
			if _game_world != null and _game_world.has_method("spawn_bonus_villagers"):
				_game_world.call("spawn_bonus_villagers", 2)
		"temp_archers":
			if _game_world != null and _game_world.has_method("spawn_temp_archers"):
				_game_world.call("spawn_temp_archers", 3)
		"auto_curfew":
			if _curfew_manager != null:
				_curfew_manager.set_active(true)
		"resource_cache":
			if _resource_manager != null:
				_resource_manager.add_resources({"wood": 80, "gold": 40})
