extends CanvasLayer

@onready var game_hub: PanelContainer = $GameHub
@onready var minimap: Control = $Minimap
@onready var help_label: Label = $TopLeft/MarginContainer/VBoxContainer/HelpLabel
@onready var cycle_button: Button = $TopLeft/MarginContainer/VBoxContainer/CycleButton

var _build_manager: Node
var _day_night_manager: DayNightManager
var _game_state_manager: GameStateManager
var _game_over_label: Label


func _ready() -> void:
	if cycle_button != null:
		cycle_button.disabled = true
	_create_game_over_overlay()


func setup(
	resource_manager: ResourceManager,
	build_manager: Node,
	spawn_manager: Node = null,
	selection_manager: Node = null,
	day_night_manager: DayNightManager = null,
	population_manager: PopulationManager = null,
	production_manager: ProductionManager = null,
	curfew_manager: CurfewManager = null,
	camera: Camera2D = null,
	ground: TinyTilesMap = null
) -> void:
	_build_manager = build_manager
	_day_night_manager = day_night_manager

	if game_hub != null and game_hub.has_method("setup"):
		game_hub.setup(
			resource_manager,
			build_manager,
			selection_manager,
			population_manager,
			production_manager,
			curfew_manager
		)
	if minimap != null and minimap.has_method("setup") and camera != null and ground != null:
		minimap.setup(camera, ground)
	if _build_manager != null and _build_manager.has_signal("build_mode_changed"):
		_build_manager.build_mode_changed.connect(_on_build_mode_changed)

	if _day_night_manager != null:
		_day_night_manager.cycle_changed.connect(_on_cycle_changed)
		_day_night_manager.phase_time_changed.connect(_on_phase_time_changed)
		_update_cycle_ui(_day_night_manager.current_phase)
	var wave_manager := get_tree().get_first_node_in_group("night_wave_manager")
	if wave_manager is NightWaveManager:
		(wave_manager as NightWaveManager).wave_warning.connect(_on_wave_warning)
		(wave_manager as NightWaveManager).wave_started.connect(_on_wave_started)

	var world := get_tree().get_first_node_in_group("game_world")
	if world != null:
		_game_state_manager = world.get_node_or_null("GameStateManager")
		if _game_state_manager != null:
			_game_state_manager.game_over.connect(_on_game_over)


func _create_game_over_overlay() -> void:
	_game_over_label = Label.new()
	_game_over_label.text = "DERROTA — El Centro Urbano ha caído"
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_game_over_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_label.add_theme_font_size_override("font_size", 28)
	_game_over_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_game_over_label.visible = false
	add_child(_game_over_label)


func _on_game_over() -> void:
	if _game_over_label != null:
		_game_over_label.visible = true
	if help_label != null:
		help_label.text = "Derrota — reinicia la escena para volver a jugar"


func _on_cycle_button_pressed() -> void:
	pass


func _on_build_mode_changed(active: bool, type_id: String) -> void:
	if help_label == null:
		return
	if not active:
		_update_help_for_cycle()
		return
	var def := BuildingDatabase.get_definition(type_id)
	var name_text: String = def.get("name", type_id)
	help_label.text = "Colocando: %s — click izquierdo para confirmar, Esc para cancelar" % name_text


func _on_cycle_changed(phase: DayNightManager.CyclePhase) -> void:
	_update_cycle_ui(phase)
	if _build_manager != null and _build_manager.build_mode_active:
		return
	_update_help_for_cycle()


func _update_cycle_ui(phase: DayNightManager.CyclePhase) -> void:
	if cycle_button == null:
		return
	var icon := "☾" if phase == DayNightManager.CyclePhase.NIGHT else "☀"
	var seconds := ceili(_day_night_manager.seconds_remaining)
	cycle_button.text = "%s Día %d · %s %02d:%02d" % [
		icon,
		_day_night_manager.cycle_number,
		_day_night_manager.get_phase_display_name(),
		seconds / 60,
		seconds % 60,
	]


func _on_phase_time_changed(_seconds_remaining: float) -> void:
	if _day_night_manager != null:
		_update_cycle_ui(_day_night_manager.current_phase)


func _on_wave_warning(direction_name: String) -> void:
	if help_label != null:
		help_label.set_deferred("text", "CUERNO — La horda se aproxima por el %s" % direction_name)


func _on_wave_started(enemy_count: int) -> void:
	if help_label != null:
		help_label.set_deferred(
			"text",
			"NOCHE — %d enemigos atacan. La construcción está bloqueada." % enemy_count
		)


func _update_help_for_cycle() -> void:
	if help_label == null or _day_night_manager == null:
		return
	match _day_night_manager.current_phase:
		DayNightManager.CyclePhase.NIGHT:
			help_label.text = "NOCHE — Protege el Centro Urbano. Construcción bloqueada."
		DayNightManager.CyclePhase.DUSK:
			help_label.text = "ATARDECER — Últimos 30 segundos para preparar defensas."
		DayNightManager.CyclePhase.DAWN:
			help_label.text = "AMANECER — Reorganiza trabajadores y repara la base."
		_:
			help_label.text = "DÍA — Recolecta y fortifica  |  1-9: construir  |  Q: seleccionar escuadrón"
