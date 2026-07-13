extends CanvasLayer

@onready var game_hub: PanelContainer = $GameHub
@onready var help_label: Label = $TopLeft/MarginContainer/HelpLabel

var _build_manager: Node


func setup(resource_manager: ResourceManager, build_manager: Node, spawn_manager: Node = null, selection_manager: Node = null) -> void:
	_build_manager = build_manager
	if game_hub != null and game_hub.has_method("setup"):
		game_hub.setup(resource_manager, build_manager, selection_manager)
	if _build_manager != null and _build_manager.has_signal("build_mode_changed"):
		_build_manager.build_mode_changed.connect(_on_build_mode_changed)


func _on_build_mode_changed(active: bool, type_id: String) -> void:
	if help_label == null:
		return
	if not active:
		help_label.text = "1-8: construir  |  Esc: cancelar  |  WASD: cámara  |  U: mejorar"
		return
	var def := BuildingDatabase.get_definition(type_id)
	var name_text: String = def.get("name", type_id)
	help_label.text = "Colocando: %s — click izquierdo para confirmar, Esc para cancelar" % name_text
