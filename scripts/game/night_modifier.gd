class_name NightModifier
extends RefCounted

enum Id {
	SWARM,
	SIEGE,
	AMBUSH,
	RAID,
	FOG,
	ELITE,
	ECLIPSE,
}

const DEFINITIONS := {
	Id.SWARM: {
		"id": Id.SWARM,
		"name": "Enjambre",
		"description": "Muchos enemigos débiles que llegan en oleadas continuas.",
		"count_mult": 1.6,
		"continuous_spawn": true,
		"dual_direction": false,
		"fog": false,
		"eclipse": false,
		"composition": [
			{"kind": "swarm", "weight": 1.0},
		],
	},
	Id.SIEGE: {
		"id": Id.SIEGE,
		"name": "Asedio",
		"description": "Pocos tanques rompemuros. Prioriza torres y caballeros.",
		"count_mult": 0.55,
		"continuous_spawn": false,
		"dual_direction": false,
		"fog": false,
		"eclipse": false,
		"composition": [
			{"kind": "siege", "weight": 0.35},
			{"kind": "mire", "weight": 0.35},
			{"kind": "normal", "weight": 0.3},
		],
	},
	Id.AMBUSH: {
		"id": Id.AMBUSH,
		"name": "Emboscada",
		"description": "La horda ataca desde dos direcciones a la vez.",
		"count_mult": 1.15,
		"continuous_spawn": false,
		"dual_direction": true,
		"fog": false,
		"eclipse": false,
		"composition": [
			{"kind": "normal", "weight": 0.45},
			{"kind": "ember", "weight": 0.3},
			{"kind": "hexwing", "weight": 0.25},
		],
	},
	Id.RAID: {
		"id": Id.RAID,
		"name": "Saqueo",
		"description": "Saqueadores priorizan molinos y minas y roban recursos.",
		"count_mult": 1.0,
		"continuous_spawn": false,
		"dual_direction": false,
		"fog": false,
		"eclipse": false,
		"composition": [
			{"kind": "raider", "weight": 0.7},
			{"kind": "normal", "weight": 0.3},
		],
	},
	Id.FOG: {
		"id": Id.FOG,
		"name": "Niebla",
		"description": "Spawn más cercano y oscuridad densa. El toque de queda importa.",
		"count_mult": 1.05,
		"continuous_spawn": false,
		"dual_direction": false,
		"fog": true,
		"eclipse": false,
		"composition": [
			{"kind": "normal", "weight": 0.6},
			{"kind": "swarm", "weight": 0.4},
		],
	},
	Id.ELITE: {
		"id": Id.ELITE,
		"name": "Élite",
		"description": "Uno o más elites acompañan a la oleada normal.",
		"count_mult": 0.9,
		"continuous_spawn": false,
		"dual_direction": false,
		"fog": false,
		"eclipse": false,
		"composition": [
			{"kind": "normal", "weight": 0.75},
			{"kind": "elite", "weight": 0.25},
		],
	},
	Id.ECLIPSE: {
		"id": Id.ECLIPSE,
		"name": "Eclipse",
		"description": "Noche más larga y consumo de comida elevado.",
		"count_mult": 1.1,
		"continuous_spawn": false,
		"dual_direction": false,
		"fog": false,
		"eclipse": true,
		"composition": [
			{"kind": "normal", "weight": 0.4},
			{"kind": "hexwing", "weight": 0.25},
			{"kind": "mire", "weight": 0.15},
			{"kind": "ember", "weight": 0.2},
		],
	},
}


static func all_ids() -> Array:
	return DEFINITIONS.keys()


static func get_definition(id: Id) -> Dictionary:
	return DEFINITIONS.get(id, {})


static func pick_random(exclude: Array = []) -> Id:
	var pool: Array = []
	for id in all_ids():
		if id in exclude:
			continue
		pool.append(id)
	if pool.is_empty():
		pool = all_ids()
	return pool.pick_random()


static func get_display_name(id: Id) -> String:
	return str(get_definition(id).get("name", "Amenaza"))


static func get_description(id: Id) -> String:
	return str(get_definition(id).get("description", ""))
