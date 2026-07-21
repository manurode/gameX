class_name RunBoonManager
extends Node

signal boon_choices_ready(choices: Array)
signal boon_applied(boon_id: String)
signal gather_multiplier_changed(multiplier: float)
signal production_double_changed(active: bool)

const BOON_DEFS := {
	"gather_surge": {
		"name": "Cosecha abundante",
		"description": "+20% recolección durante el próximo día.",
	},
	"free_walls": {
		"name": "Muros de fortuna",
		"description": "Coloca 4 segmentos de muro gratis donde quieras.",
	},
	"free_tower": {
		"name": "Torre de guardia",
		"description": "Coloca 1 torre gratis donde quieras.",
	},
	"extra_villagers": {
		"name": "Refugiados",
		"description": "2 aldeanos se unen a tu asentamiento.",
	},
	"temp_archers": {
		"name": "Arqueros de paso",
		"description": "3 arqueros aparecen cerca del centro hasta el anochecer.",
	},
	"temp_knights": {
		"name": "Caballeros de paso",
		"description": "2 caballeros aparecen cerca del centro hasta el anochecer.",
	},
	"production_double": {
		"name": "Producción doble",
		"description": "Cada entrenamiento genera 2 unidades durante el próximo día.",
	},
	"dawn_repair": {
		"name": "Reparación del alba",
		"description": "Restaura toda la vida de tus edificios.",
	},
	"resource_cache": {
		"name": "Botín recuperado",
		"description": "+80 madera y +40 oro.",
	},
	"night_sight": {
		"name": "Ojo nocturno",
		"description": "Durante la próxima noche ves a los enemigos en la oscuridad y en el minimapa.",
	},
	"summer_equinox": {
		"name": "Equinoccio de verano",
		"description": "La próxima noche no trae oscuridad ni enemigos.",
	},
}

var gather_multiplier: float = 1.0
var production_double_active: bool = false
var _pending_choices: Array[String] = []
var _awaiting_choice: bool = false
var _day_night: DayNightManager
var _game_world: Node
var _curfew_manager: CurfewManager
var _resource_manager: ResourceManager
var _used_this_dawn: bool = false
var _enemy_night_vision_pending: bool = false
var _enemy_night_vision_active: bool = false
var _summer_equinox_pending: bool = false
var _summer_equinox_active: bool = false


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


func has_enemy_night_vision() -> bool:
	return _enemy_night_vision_active


func has_production_double() -> bool:
	return production_double_active


func get_production_output_count() -> int:
	return 2 if production_double_active else 1


func should_keep_daylight() -> bool:
	return _summer_equinox_pending or _summer_equinox_active


func is_summer_equinox_active() -> bool:
	return _summer_equinox_active


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


## Aplica una bendición al instante (testing). Cierra la elección pendiente si la hay.
func debug_apply_boon(boon_id: String) -> bool:
	if not BOON_DEFS.has(boon_id):
		return false
	if _awaiting_choice:
		_awaiting_choice = false
		_pending_choices.clear()
		if _day_night != null:
			_day_night.automatic_cycle = true
	_apply_boon(boon_id)
	boon_applied.emit(boon_id)
	return true


func get_boon_def(boon_id: String) -> Dictionary:
	return BOON_DEFS.get(boon_id, {})


func get_all_boon_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in BOON_DEFS.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func _on_cycle_changed(phase: DayNightManager.CyclePhase) -> void:
	match phase:
		DayNightManager.CyclePhase.DAY:
			_summer_equinox_active = false
			_summer_equinox_pending = false
		DayNightManager.CyclePhase.DAWN:
			_enemy_night_vision_active = false
			_used_this_dawn = false
			offer_dawn_boons()
		DayNightManager.CyclePhase.DUSK:
			_activate_summer_equinox_if_pending()
			_clear_daytime_boons()
		DayNightManager.CyclePhase.NIGHT:
			_activate_summer_equinox_if_pending()
			_clear_daytime_boons()
			if _enemy_night_vision_pending:
				_enemy_night_vision_active = true
				_enemy_night_vision_pending = false


func _activate_summer_equinox_if_pending() -> void:
	if not _summer_equinox_pending:
		return
	_summer_equinox_active = true
	_summer_equinox_pending = false


func _clear_daytime_boons() -> void:
	if gather_multiplier != 1.0:
		gather_multiplier = 1.0
		gather_multiplier_changed.emit(gather_multiplier)
	if production_double_active:
		production_double_active = false
		production_double_changed.emit(false)
	if _game_world != null and _game_world.has_method("clear_temp_boon_units"):
		_game_world.call("clear_temp_boon_units")
	elif _game_world != null and _game_world.has_method("clear_temp_archers"):
		_game_world.call("clear_temp_archers")


func _roll_choices(count: int) -> Array[String]:
	var pool: Array[String] = []
	var exclude_equinox := (
		_day_night != null
		and _day_night.nights_survived >= BalanceConfig.WIN_NIGHTS - 1
	)
	for key in BOON_DEFS.keys():
		var boon_id := str(key)
		if exclude_equinox and boon_id == "summer_equinox":
			continue
		pool.append(boon_id)
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
			_grant_free_build("wall", 4)
		"free_tower":
			_grant_free_build("tower", 1)
		"extra_villagers":
			if _game_world != null and _game_world.has_method("spawn_bonus_villagers"):
				_game_world.call("spawn_bonus_villagers", 2)
		"temp_archers":
			if _game_world != null and _game_world.has_method("spawn_temp_archers"):
				_game_world.call("spawn_temp_archers", 3)
		"temp_knights":
			if _game_world != null and _game_world.has_method("spawn_temp_knights"):
				_game_world.call("spawn_temp_knights", 2)
		"production_double":
			production_double_active = true
			production_double_changed.emit(true)
		"dawn_repair":
			if _game_world != null and _game_world.has_method("repair_all_player_buildings"):
				_game_world.call("repair_all_player_buildings")
		"resource_cache":
			if _resource_manager != null:
				_resource_manager.add_resources({"wood": 80, "gold": 40})
		"night_sight":
			_enemy_night_vision_pending = true
		"summer_equinox":
			_summer_equinox_pending = true


func _grant_free_build(type_id: String, count: int) -> void:
	if _game_world == null:
		return
	var build_manager := _game_world.get_node_or_null("BuildManager")
	if build_manager != null and build_manager.has_method("grant_free_placements"):
		build_manager.call("grant_free_placements", type_id, count)
