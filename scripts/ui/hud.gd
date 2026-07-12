extends CanvasLayer

@onready var resources_label: Label = $MarginContainer/VBoxContainer/ResourcesLabel
@onready var build_label: Label = $MarginContainer/VBoxContainer/BuildLabel
@onready var spawn_label: Label = $MarginContainer/VBoxContainer/SpawnLabel
@onready var help_label: Label = $MarginContainer/VBoxContainer/HelpLabel

var _resource_manager: ResourceManager
var _build_manager: Node
var _spawn_manager: Node


func setup(resource_manager: ResourceManager, build_manager: Node, spawn_manager: Node = null) -> void:
	_resource_manager = resource_manager
	_build_manager = build_manager
	_spawn_manager = spawn_manager
	if _resource_manager != null:
		_resource_manager.resources_changed.connect(_on_resources_changed)
		_on_resources_changed(_resource_manager.wood, _resource_manager.stone, _resource_manager.wheat)
	if _build_manager != null and _build_manager.has_signal("build_mode_changed"):
		_build_manager.build_mode_changed.connect(_on_build_mode_changed)
	if _spawn_manager != null and _spawn_manager.has_signal("spawn_mode_changed"):
		_spawn_manager.spawn_mode_changed.connect(_on_spawn_mode_changed)
	_update_spawn_label(false, "")


func _on_resources_changed(wood: int, stone: int, wheat: int) -> void:
	if resources_label != null:
		resources_label.text = "Madera: %d  |  Piedra: %d  |  Trigo: %d" % [wood, stone, wheat]


func _on_build_mode_changed(active: bool, type_id: String) -> void:
	if build_label == null:
		return
	if not active:
		build_label.text = "Construcción: pulsa 1-8 para elegir edificio | U: mejorar edificio"
		return
	var def := BuildingDatabase.get_definition(type_id)
	var name_text: String = def.get("name", type_id)
	build_label.text = "Colocando: %s (click izq. confirmar, Esc cancelar)" % name_text


func _on_spawn_mode_changed(active: bool, type_id: String) -> void:
	_update_spawn_label(active, type_id)


func _update_spawn_label(active: bool, type_id: String) -> void:
	if spawn_label == null:
		return
	if not active:
		spawn_label.text = "Spawn: F1 Caballero  |  F2 Arquero  |  F3 Constructor"
		return
	var def := UnitDatabase.get_definition(type_id)
	var name_text: String = def.get("name", type_id)
	spawn_label.text = "Spawneando: %s (click izq. confirmar, Esc cancelar)" % name_text
