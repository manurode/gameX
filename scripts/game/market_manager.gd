class_name MarketManager
extends Node

signal trades_changed(trades_remaining: int)

const RESOURCE_KEYS: Array[String] = ["wood", "gold", "food"]
const RESOURCE_LABELS := {
	"wood": "madera",
	"gold": "oro",
	"food": "comida",
}

var _resource_manager: ResourceManager
var _day_night: DayNightManager
var _trades_used_this_cycle: int = 0


func setup(resource_manager: ResourceManager, day_night: DayNightManager) -> void:
	_resource_manager = resource_manager
	_day_night = day_night
	_trades_used_this_cycle = 0
	if _day_night != null and not _day_night.cycle_started.is_connected(_on_cycle_started):
		_day_night.cycle_started.connect(_on_cycle_started)
	_emit_trades_changed()


func get_trades_remaining() -> int:
	return maxi(0, BalanceConfig.MARKET_TRADES_PER_CYCLE - _trades_used_this_cycle)


func get_trades_used() -> int:
	return _trades_used_this_cycle


func get_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for from_key in RESOURCE_KEYS:
		for to_key in RESOURCE_KEYS:
			if from_key == to_key:
				continue
			var offer := get_offer(from_key, to_key)
			if not offer.is_empty():
				offers.append(offer)
	return offers


func get_offer(from_key: String, to_key: String) -> Dictionary:
	if from_key == to_key:
		return {}
	if not BalanceConfig.MARKET_LOT_SIZE.has(from_key):
		return {}
	if not BalanceConfig.MARKET_RESOURCE_VALUE.has(from_key):
		return {}
	if not BalanceConfig.MARKET_RESOURCE_VALUE.has(to_key):
		return {}

	var pay: int = int(BalanceConfig.MARKET_LOT_SIZE[from_key])
	var receive := _compute_receive(from_key, to_key, pay)
	if pay <= 0 or receive <= 0:
		return {}
	return {
		"from": from_key,
		"to": to_key,
		"pay": pay,
		"receive": receive,
		"from_label": RESOURCE_LABELS.get(from_key, from_key),
		"to_label": RESOURCE_LABELS.get(to_key, to_key),
	}


func can_exchange(from_key: String, to_key: String) -> bool:
	return get_exchange_block_reason(from_key, to_key).is_empty()


func get_exchange_block_reason(from_key: String, to_key: String) -> String:
	if _resource_manager == null:
		return "Mercado no disponible"
	var offer := get_offer(from_key, to_key)
	if offer.is_empty():
		return "Intercambio no válido"
	if get_trades_remaining() <= 0:
		return "Sin intercambios hoy (%d/%d)" % [
			BalanceConfig.MARKET_TRADES_PER_CYCLE,
			BalanceConfig.MARKET_TRADES_PER_CYCLE,
		]
	var pay: int = int(offer.pay)
	var cost := {from_key: pay}
	if not _resource_manager.can_afford(cost):
		return "Faltan %d %s" % [pay, offer.from_label]
	return ""


func try_exchange(from_key: String, to_key: String) -> bool:
	var reason := get_exchange_block_reason(from_key, to_key)
	if not reason.is_empty():
		return false
	var offer := get_offer(from_key, to_key)
	var pay: int = int(offer.pay)
	var receive: int = int(offer.receive)
	if not _resource_manager.spend({from_key: pay}):
		return false
	_resource_manager.add_resources({to_key: receive})
	_trades_used_this_cycle += 1
	_emit_trades_changed()
	return true


func format_offer_text(offer: Dictionary) -> String:
	return "%d %s → %d %s" % [
		int(offer.get("pay", 0)),
		offer.get("from_label", ""),
		int(offer.get("receive", 0)),
		offer.get("to_label", ""),
	]


func _compute_receive(from_key: String, to_key: String, pay: int) -> int:
	var from_value: float = float(BalanceConfig.MARKET_RESOURCE_VALUE[from_key])
	var to_value: float = float(BalanceConfig.MARKET_RESOURCE_VALUE[to_key])
	if to_value <= 0.0:
		return 0
	var kept := 1.0 - BalanceConfig.MARKET_FEE
	var raw := float(pay) * from_value * kept / to_value
	return maxi(1, int(floor(raw)))


func _on_cycle_started(_cycle_number: int) -> void:
	_trades_used_this_cycle = 0
	_emit_trades_changed()


func _emit_trades_changed() -> void:
	trades_changed.emit(get_trades_remaining())
