extends CanvasLayer

@onready var resources_label: Label = $MarginContainer/VBoxContainer/ResourcesLabel
@onready var build_label: Label = $MarginContainer/VBoxContainer/BuildLabel
@onready var help_label: Label = $MarginContainer/VBoxContainer/HelpLabel

var _resource_manager: ResourceManager
var _build_manager: Node


func setup(resource_manager: ResourceManager, build_manager: Node) -> void:
	_resource_manager = resource_manager
	_build_manager = build_manager
	if _resource_manager != null:
		_resource_manager.resources_changed.connect(_on_resources_changed)
		_on_resources_changed(_resource_manager.wood, _resource_manager.stone, _resource_manager.wheat)
	if _build_manager != null and _build_manager.has_signal("build_mode_changed"):
		_build_manager.build_mode_changed.connect(_on_build_mode_changed)


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
