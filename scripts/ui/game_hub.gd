extends PanelContainer

const BUILD_ORDER: Array[String] = [
	"house_small", "house_big", "lumber_camp", "mill",
	"mine", "stable", "barracks", "tower", "wall",
]

const FORMATION_ORDER: Array[Unit.FormationType] = [
	Unit.FormationType.COLUMN,
	Unit.FormationType.LINE,
	Unit.FormationType.WEDGE,
	Unit.FormationType.DIAMOND,
]

const FORMATION_INFO: Dictionary = {
	Unit.FormationType.COLUMN: {
		"name": "Columna",
		"subtitle": "Columna de marcha",
		"tooltip": (
			"Columna de marcha\n"
			+ "Todos los soldados van uno detrás del otro.\n\n"
			+ "Uso: Ideal para moverse rápido por caminos estrechos, bosques densos o de noche.\n"
			+ "Ventaja: Fácil de controlar y seguir.\n"
			+ "Desventaja: Vulnerable a emboscadas frontales."
		),
	},
	Unit.FormationType.LINE: {
		"name": "Línea",
		"subtitle": "En línea",
		"tooltip": (
			"En línea\n"
			+ "Todos los soldados se colocan uno al lado del otro, formando un frente horizontal.\n\n"
			+ "Uso: Asaltar una posición enemiga o hacer una barrida de seguridad.\n"
			+ "Ventaja: Maximiza el poder de fuego hacia el frente.\n"
			+ "Desventaja: Difícil en terrenos irregulares; vulnerable por los flancos."
		),
	},
	Unit.FormationType.WEDGE: {
		"name": "Cuña",
		"subtitle": "Formación en V",
		"tooltip": (
			"Formación en V\n"
			+ "Un líder va adelante y los demás se despliegan en diagonal hacia atrás.\n\n"
			+ "Uso: Formación básica para patrullar; se adapta a casi cualquier terreno.\n"
			+ "Ventaja: Excelente fuego de cobertura hacia el frente y los lados."
		),
	},
	Unit.FormationType.DIAMOND: {
		"name": "Cuadro",
		"subtitle": "En diamante",
		"tooltip": (
			"En diamante\n"
			+ "Los soldados se agrupan formando un rombo. Un soldado va en el centro.\n\n"
			+ "Uso: Cuando la amenaza puede venir de cualquier dirección (360°).\n"
			+ "Ventaja: Defensa total y fácil de reorganizar."
		),
	},
}

const TEX_WOOD := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_resources_wood.png"
const TEX_GOLD := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_resources_stone.png"
const TEX_FOOD := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_resources_wheat.png"
const TEX_HAMMER := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_hammer.png"

const ICON_VARIANT_SIZE := 128
const SLOT_SIZE := Vector2(66, 80)
const ICON_SIZE := Vector2(36, 30)
const RESOURCE_ICON_SIZE := Vector2(22, 22)
const MIN_FORMATION_UNITS := 2

@onready var _resources_box: VBoxContainer = $MarginContainer/HBoxContainer/ResourcesBox
@onready var _build_tab_icon: TextureRect = $MarginContainer/HBoxContainer/CommandArea/TabColumn/BuildTabIcon
@onready var _build_grid: GridContainer = $MarginContainer/HBoxContainer/CommandArea/BuildGrid
@onready var _formation_grid: GridContainer = $MarginContainer/HBoxContainer/CommandArea/FormationGrid
@onready var _status_column: VBoxContainer = $MarginContainer/HBoxContainer/CommandArea/StatusColumn

var _production_box: VBoxContainer
var _production_title: Label
var _production_items_box: BoxContainer
var _production_item_buttons: Dictionary = {}
var _production_queue_label: Label
var _production_progress_label: Label
var _production_pending_label: Label
var _production_panel_key: String = ""
var _resource_manager: ResourceManager
var _build_manager: Node
var _selection_manager: Node
var _population_manager: PopulationManager
var _production_manager: ProductionManager
var _curfew_manager: CurfewManager
var _run_boon_manager: RunBoonManager
var _curfew_button: Button
var _resource_labels: Dictionary = {}
var _build_slots: Dictionary = {}
var _formation_slots: Dictionary = {}
var _population_label: Label
var _food_upkeep_label: Label
var _gather_bonus_label: Label
var _active_build_type: String = ""
var _formation_mode: bool = false
var _selected_unit_count: int = 0
var _selected_building: Building = null


func _ready() -> void:
	if _build_tab_icon != null:
		_build_tab_icon.texture = _make_icon_atlas(TEX_HAMMER)
	_show_build_panel()


func setup(
	resource_manager: ResourceManager,
	build_manager: Node,
	selection_manager: Node = null,
	population_manager: PopulationManager = null,
	production_manager: ProductionManager = null,
	curfew_manager: CurfewManager = null,
	run_boon_manager: RunBoonManager = null
) -> void:
	_resource_manager = resource_manager
	_build_manager = build_manager
	_selection_manager = selection_manager
	_population_manager = population_manager
	_production_manager = production_manager
	_curfew_manager = curfew_manager
	_run_boon_manager = run_boon_manager
	_build_resource_rows()
	_build_command_grid()
	_build_formation_grid()
	_build_curfew_button()
	_ensure_production_box()
	if _resource_manager != null:
		_resource_manager.resources_changed.connect(_on_resources_changed)
		_on_resources_changed(_resource_manager.wood, _resource_manager.gold, _resource_manager.food)
	if _build_manager != null and _build_manager.has_signal("build_mode_changed"):
		_build_manager.build_mode_changed.connect(_on_build_mode_changed)
	if _selection_manager != null:
		if _selection_manager.has_signal("selection_changed"):
			_selection_manager.selection_changed.connect(_on_selection_changed)
		if _selection_manager.has_signal("formation_changed"):
			_selection_manager.formation_changed.connect(_on_formation_changed)
		if _selection_manager.has_signal("building_selection_changed"):
			_selection_manager.building_selection_changed.connect(_on_building_selection_changed)
		_on_selection_changed(_selection_manager.selected_units)
	if _population_manager != null:
		_population_manager.population_changed.connect(_on_population_changed)
		_population_manager.food_shortage.connect(_on_food_shortage)
		_population_manager.food_upkeep_changed.connect(_on_food_upkeep_changed)
		_on_population_changed(_population_manager.population, _population_manager.population_cap)
		_on_food_upkeep_changed(_population_manager.get_food_upkeep_per_second())
	if _production_manager != null:
		_production_manager.queue_changed.connect(_on_production_queue_changed)
	if _curfew_manager != null:
		_curfew_manager.curfew_changed.connect(_on_curfew_changed)
		_refresh_curfew_button()
	if _run_boon_manager != null:
		_run_boon_manager.gather_multiplier_changed.connect(_on_gather_multiplier_changed)
		_on_gather_multiplier_changed(_run_boon_manager.get_gather_multiplier())


func _build_resource_rows() -> void:
	var entries: Array[Dictionary] = [
		{"key": "gold", "texture": TEX_GOLD, "label": "Oro"},
		{"key": "wood", "texture": TEX_WOOD, "label": "Madera"},
		{"key": "food", "texture": TEX_FOOD, "label": "Comida"},
	]
	var resources_row := HBoxContainer.new()
	resources_row.add_theme_constant_override("separation", 8)
	resources_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_resources_box.add_child(resources_row)

	for entry in entries:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.alignment = BoxContainer.ALIGNMENT_CENTER

		var icon := TextureRect.new()
		icon.custom_minimum_size = RESOURCE_ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _make_icon_atlas(entry.texture)
		cell.add_child(icon)

		var amount := Label.new()
		amount.text = "0"
		amount.add_theme_font_size_override("font_size", 14)
		amount.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
		amount.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		amount.add_theme_constant_override("shadow_offset_x", 1)
		amount.add_theme_constant_override("shadow_offset_y", 1)
		cell.add_child(amount)

		resources_row.add_child(cell)
		_resource_labels[entry.key] = amount

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 10)
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_resources_box.add_child(stats_row)

	_population_label = Label.new()
	_population_label.text = "Pob: 0/5"
	_population_label.add_theme_font_size_override("font_size", 11)
	_population_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	stats_row.add_child(_population_label)

	_food_upkeep_label = Label.new()
	_food_upkeep_label.text = "Consumo: 0/s"
	_food_upkeep_label.add_theme_font_size_override("font_size", 10)
	_food_upkeep_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.55))
	stats_row.add_child(_food_upkeep_label)

	_gather_bonus_label = Label.new()
	_gather_bonus_label.text = "Cosecha +20%"
	_gather_bonus_label.visible = false
	_gather_bonus_label.add_theme_font_size_override("font_size", 10)
	_gather_bonus_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.55))
	stats_row.add_child(_gather_bonus_label)


func _ensure_production_box() -> void:
	if _production_box != null:
		return
	var hbox := $MarginContainer/HBoxContainer
	_production_box = VBoxContainer.new()
	_production_box.name = "ProductionBox"
	_production_box.custom_minimum_size = Vector2(140, 0)
	_production_box.visible = false
	_production_box.add_theme_constant_override("separation", 2)
	hbox.add_child(_production_box)
	hbox.move_child(_production_box, 2)

	_production_title = Label.new()
	_production_title.add_theme_font_size_override("font_size", 11)
	_production_title.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	_production_box.add_child(_production_title)

	_production_items_box = HBoxContainer.new()
	_production_items_box.add_theme_constant_override("separation", 4)
	_production_box.add_child(_production_items_box)

	_production_queue_label = Label.new()
	_production_queue_label.add_theme_font_size_override("font_size", 10)
	_production_queue_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.55))
	_production_queue_label.visible = false
	_production_box.add_child(_production_queue_label)

	_production_progress_label = Label.new()
	_production_progress_label.add_theme_font_size_override("font_size", 10)
	_production_progress_label.visible = false
	_production_box.add_child(_production_progress_label)

	_production_pending_label = Label.new()
	_production_pending_label.add_theme_font_size_override("font_size", 10)
	_production_pending_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	_production_pending_label.visible = false
	_production_box.add_child(_production_pending_label)


func _build_command_grid() -> void:
	for i in BUILD_ORDER.size():
		var type_id: String = BUILD_ORDER[i]
		var slot := _create_build_slot(type_id, i + 1)
		_build_grid.add_child(slot)
		_build_slots[type_id] = slot


func _build_formation_grid() -> void:
	for i in FORMATION_ORDER.size():
		var formation: Unit.FormationType = FORMATION_ORDER[i]
		var slot := _create_formation_slot(formation, i + 1)
		_formation_grid.add_child(slot)
		_formation_slots[formation] = slot


func _build_curfew_button() -> void:
	if _status_column == null:
		return
	_curfew_button = Button.new()
	_curfew_button.text = "Toque de queda"
	_curfew_button.tooltip_text = (
		"Toque de queda\n"
		+ "Los aldeanos buscan refugio en el edificio más cercano con espacio.\n"
		+ "Los soldados permanecen fuera.\n\n"
		+ "Desactivado: los aldeanos siguen con sus tareas."
	)
	_curfew_button.focus_mode = Control.FOCUS_NONE
	_curfew_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_curfew_button.custom_minimum_size = Vector2(110, 28)
	_curfew_button.add_theme_font_size_override("font_size", 11)
	_curfew_button.pressed.connect(_on_curfew_button_pressed)
	_status_column.add_child(_curfew_button)
	_status_column.move_child(_curfew_button, 0)


func _on_curfew_button_pressed() -> void:
	if _curfew_manager != null:
		_curfew_manager.toggle()


func _on_curfew_changed(_active: bool) -> void:
	_refresh_curfew_button()


func _refresh_curfew_button() -> void:
	if _curfew_button == null or _curfew_manager == null:
		return
	var active := _curfew_manager.is_active
	_curfew_button.text = "Toque de queda: ON" if active else "Toque de queda"
	if active:
		_curfew_button.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	else:
		_curfew_button.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))


func _create_build_slot(type_id: String, hotkey: int) -> Button:
	var def := BuildingDatabase.get_definition(type_id)
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_build_slot_pressed.bind(type_id))

	var style := _create_slot_style()
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style.duplicate())
	button.add_theme_stylebox_override("pressed", style.duplicate())
	button.add_theme_stylebox_override("disabled", style.duplicate())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var content := MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("margin_left", 2)
	content.add_theme_constant_override("margin_top", 1)
	content.add_theme_constant_override("margin_right", 2)
	content.add_theme_constant_override("margin_bottom", 1)
	button.add_child(content)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(vbox)

	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _get_building_icon(type_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = def.get("name", type_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.clip_text = true
	vbox.add_child(name_label)

	var hotkey_label := Label.new()
	hotkey_label.text = str(hotkey)
	hotkey_label.add_theme_font_size_override("font_size", 10)
	hotkey_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	hotkey_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hotkey_label.position = Vector2(3, 1)
	hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(hotkey_label)

	var cost := BuildingDatabase.get_cost(type_id)
	button.tooltip_text = _format_cost_tooltip(
		def.get("name", type_id),
		cost,
		def.get("build_time", 0.0)
	)
	button.set_meta("style", style)
	button.set_meta("icon", icon)
	return button


func _create_formation_slot(formation: Unit.FormationType, hotkey: int) -> Button:
	var info: Dictionary = FORMATION_INFO[formation]
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_formation_slot_pressed.bind(formation))

	var style := _create_slot_style()
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style.duplicate())
	button.add_theme_stylebox_override("pressed", style.duplicate())
	button.add_theme_stylebox_override("disabled", style.duplicate())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var content := MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("margin_left", 2)
	content.add_theme_constant_override("margin_top", 1)
	content.add_theme_constant_override("margin_right", 2)
	content.add_theme_constant_override("margin_bottom", 1)
	button.add_child(content)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(vbox)

	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _create_formation_icon(formation)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = info.get("name", "")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var hotkey_label := Label.new()
	hotkey_label.text = str(hotkey)
	hotkey_label.add_theme_font_size_override("font_size", 10)
	hotkey_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	hotkey_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hotkey_label.position = Vector2(3, 1)
	hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(hotkey_label)

	button.tooltip_text = info.get("tooltip", "")
	button.set_meta("style", style)
	button.set_meta("icon", icon)
	button.set_meta("formation", formation)
	return button


func _create_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.85)
	style.border_color = Color(0.35, 0.3, 0.22, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(2)
	return style


func _create_formation_icon(formation: Unit.FormationType) -> Texture2D:
	var image := Image.create(48, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var dot_color := Color(0.82, 0.76, 0.55, 1.0)
	var leader_color := Color(0.95, 0.82, 0.35, 1.0)
	var dot_size := 5

	var points: Array[Vector2] = []
	match formation:
		Unit.FormationType.COLUMN:
			points = [Vector2(24, 8), Vector2(24, 16), Vector2(24, 24), Vector2(24, 32)]
		Unit.FormationType.LINE:
			points = [Vector2(8, 20), Vector2(18, 20), Vector2(28, 20), Vector2(38, 20)]
		Unit.FormationType.WEDGE:
			points = [Vector2(24, 8), Vector2(14, 20), Vector2(34, 20), Vector2(8, 32), Vector2(24, 32), Vector2(40, 32)]
		Unit.FormationType.DIAMOND:
			points = [Vector2(24, 20), Vector2(24, 8), Vector2(34, 20), Vector2(24, 32), Vector2(14, 20)]

	for i in points.size():
		var color := leader_color if i == 0 else dot_color
		_draw_dot(image, points[i], dot_size, color)

	return ImageTexture.create_from_image(image)


func _draw_dot(image: Image, center: Vector2, size: int, color: Color) -> void:
	var half := size / 2
	for y in range(-half, half + 1):
		for x in range(-half, half + 1):
			var px := int(center.x) + x
			var py := int(center.y) + y
			if px >= 0 and px < image.get_width() and py >= 0 and py < image.get_height():
				image.set_pixel(px, py, color)


func _get_building_icon(type_id: String) -> Texture2D:
	var def := BuildingDatabase.get_definition(type_id)
	if type_id == "wall":
		return WallTexture.get_texture(false)
	var texture_path: String = def.get("texture", "")
	if texture_path.is_empty():
		return null
	return load(texture_path)


func _make_icon_atlas(texture_path: String, variant_index: int = 0) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(texture_path)
	atlas.region = Rect2(variant_index * ICON_VARIANT_SIZE, 0, ICON_VARIANT_SIZE, ICON_VARIANT_SIZE)
	return atlas


func _format_cost_tooltip(name: String, cost: Dictionary, duration: float = 0.0) -> String:
	var parts: PackedStringArray = []
	if cost.get("wood", 0) > 0:
		parts.append("%d madera" % cost.wood)
	if cost.get("gold", 0) > 0:
		parts.append("%d oro" % cost.gold)
	if cost.get("food", 0) > 0:
		parts.append("%d comida" % cost.food)
	var details := " · ".join(parts) if not parts.is_empty() else "Gratis"
	if duration > 0.0:
		details += " · %.0f s" % duration
	return "%s\n%s" % [name, details]


func _on_build_slot_pressed(type_id: String) -> void:
	if _build_manager == null:
		return
	if _build_manager.has_method("start_build_mode"):
		_build_manager.start_build_mode(type_id)


func _on_formation_slot_pressed(formation: Unit.FormationType) -> void:
	if _selection_manager == null:
		return
	if _selection_manager.has_method("set_move_formation"):
		_selection_manager.set_move_formation(formation)
	_refresh_formation_highlight()


func _on_resources_changed(wood: int, gold: int, food: int) -> void:
	if _resource_labels.has("wood"):
		_resource_labels.wood.text = str(wood)
	if _resource_labels.has("gold"):
		_resource_labels.gold.text = str(gold)
	if _resource_labels.has("food"):
		_resource_labels.food.text = str(food)
	_refresh_affordability()
	_refresh_production_panel()


func _on_population_changed(pop: int, cap: int) -> void:
	if _population_label != null:
		_population_label.text = "Pob: %d/%d" % [pop, cap]


func _on_food_upkeep_changed(upkeep: float) -> void:
	if _food_upkeep_label == null or _population_manager == null:
		return
	if _population_manager.population <= 0:
		_food_upkeep_label.text = "Sin consumo"
	else:
		var income := 0.0
		var job_manager := get_tree().get_first_node_in_group("job_manager")
		if job_manager is JobManager:
			income = (job_manager as JobManager).get_food_income_per_second()
		var net := income - upkeep
		_food_upkeep_label.text = "%.2f/s  bal %+.2f" % [upkeep, net]
	if upkeep <= 0.0:
		_food_upkeep_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.55))
	elif _population_manager.food_shortage_active:
		_food_upkeep_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
	else:
		_food_upkeep_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45))


func _on_gather_multiplier_changed(multiplier: float) -> void:
	if _gather_bonus_label == null:
		return
	if multiplier > 1.0:
		var percent := int(round((multiplier - 1.0) * 100.0))
		_gather_bonus_label.text = "Cosecha +%d%%" % percent
		_gather_bonus_label.visible = true
	else:
		_gather_bonus_label.visible = false


func _on_food_shortage(active: bool) -> void:
	if _food_upkeep_label != null and _population_manager != null:
		_on_food_upkeep_changed(_population_manager.get_food_upkeep_per_second())


func _on_building_selection_changed(building: Building) -> void:
	_selected_building = building
	_refresh_production_panel()


func _on_production_queue_changed(building: Building) -> void:
	if building == _selected_building:
		_update_production_status_labels()


func _process(_delta: float) -> void:
	if _population_manager != null:
		_on_food_upkeep_changed(_population_manager.get_food_upkeep_per_second())
	if _production_box == null or not _production_box.visible:
		return
	_update_production_progress_label()


func _refresh_production_panel() -> void:
	if _production_box == null:
		return

	if _selected_building == null or _production_manager == null:
		_production_box.visible = false
		_production_panel_key = ""
		return

	var items := _get_production_items_for_building(_selected_building)
	if items.is_empty():
		_production_box.visible = false
		_production_panel_key = ""
		return

	_production_box.visible = true
	_production_title.text = _selected_building.get_display_name()

	var panel_key := "%d:%s" % [_selected_building.get_instance_id(), ",".join(items)]
	if _production_panel_key != panel_key:
		_rebuild_production_item_buttons(items)
		_production_panel_key = panel_key

	_update_production_status_labels()


func _get_production_items_for_building(building: Building) -> Array[String]:
	var items := building.get_production_items()
	if items.is_empty():
		items = EquipmentDatabase.get_items_for_building(building.building_type_id)
	return items


func _rebuild_production_item_buttons(items: Array[String]) -> void:
	for child in _production_items_box.get_children():
		child.queue_free()
	_production_item_buttons.clear()

	for item_id in items:
		var def := EquipmentDatabase.get_definition(item_id)
		var cost: Dictionary = def.get("cost", {})
		var cost_parts: PackedStringArray = []
		if cost.get("wood", 0) > 0:
			cost_parts.append("%d madera" % cost.wood)
		if cost.get("gold", 0) > 0:
			cost_parts.append("%d oro" % cost.gold)
		if cost.get("food", 0) > 0:
			cost_parts.append("%d comida" % cost.food)
		var cost_text := ", ".join(cost_parts) if not cost_parts.is_empty() else "Gratis"

		var button := Button.new()
		button.text = def.get("name", item_id)
		button.tooltip_text = "%s · %.0f s" % [cost_text, def.get("train_time", 0.0)]
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_on_production_pressed.bind(item_id))
		_production_items_box.add_child(button)
		_production_item_buttons[item_id] = button


func _update_production_status_labels() -> void:
	if _selected_building == null or _production_manager == null:
		return

	var items := _get_production_items_for_building(_selected_building)
	var queue_counts := _production_manager.get_queue_counts(_selected_building)
	for item_id in items:
		var button: Button = _production_item_buttons.get(item_id)
		if button == null:
			continue
		var def := EquipmentDatabase.get_definition(item_id)
		var queued_count: int = queue_counts.get(item_id, 0)
		button.text = def.get("name", item_id)
		if queued_count > 0:
			button.text += " (x%d)" % queued_count

	var queue := _production_manager.get_queue(_selected_building)
	if queue.size() > 0:
		_production_queue_label.visible = true
		_production_queue_label.text = "En cola: %d" % queue.size()
	else:
		_production_queue_label.visible = false

	_update_production_progress_label()

	var pending := _production_manager.get_pending_recruitment(_selected_building)
	if not pending.is_empty() and pending.get("count", 0) > 0:
		var pending_def := EquipmentDatabase.get_definition(pending.get("item_id", ""))
		var pending_name: String = pending_def.get("name", "equipo")
		_production_pending_label.text = "Esperando %d aldeano(s) para %s" % [pending.count, pending_name]
		_production_pending_label.visible = true
	else:
		_production_pending_label.visible = false


func _update_production_progress_label() -> void:
	if _production_progress_label == null or _production_manager == null or _selected_building == null:
		return

	var queue := _production_manager.get_queue(_selected_building)
	if queue.is_empty():
		_production_progress_label.visible = false
		return

	var current: Dictionary = queue[0]
	if not current.get("paid", true):
		_production_progress_label.text = "Esperando recursos..."
		_production_progress_label.visible = true
		return

	var time_total: float = maxf(float(current.get("time_total", 1.0)), 0.1)
	var progress: float = float(current.get("progress", 0.0))
	if progress >= time_total:
		var item_id: String = current.get("item_id", "")
		var def := EquipmentDatabase.get_definition(item_id)
		if def.get("transforms_to", "").is_empty() \
				and _population_manager != null \
				and not _population_manager.can_add_population():
			_production_progress_label.text = "Esperando espacio de población..."
			_production_progress_label.visible = true
			return

	var pct: float = progress / time_total
	_production_progress_label.text = "Produciendo... %d%%" % int(pct * 100.0)
	_production_progress_label.visible = true


func _on_production_pressed(item_id: String) -> void:
	if _production_manager == null or _selected_building == null:
		return
	if _production_manager.enqueue(_selected_building, item_id):
		_update_production_status_labels()


func _on_selection_changed(selected_units: Array) -> void:
	_selected_unit_count = selected_units.size()
	var show_formations := _selected_unit_count >= MIN_FORMATION_UNITS
	if show_formations:
		_show_formation_panel()
	else:
		_show_build_panel()
	_refresh_formation_highlight()


func _on_formation_changed(_formation: Unit.FormationType) -> void:
	_refresh_formation_highlight()


func _show_build_panel() -> void:
	_formation_mode = false
	if _build_grid != null:
		_build_grid.visible = true
	if _formation_grid != null:
		_formation_grid.visible = false
	if _build_tab_icon != null:
		_build_tab_icon.texture = _make_icon_atlas(TEX_HAMMER)


func _show_formation_panel() -> void:
	_formation_mode = true
	if _build_grid != null:
		_build_grid.visible = false
	if _formation_grid != null:
		_formation_grid.visible = true
	if _build_tab_icon != null:
		_build_tab_icon.texture = _create_formation_tab_icon()
	_refresh_formation_highlight()


func _create_formation_tab_icon() -> Texture2D:
	var image := Image.create(ICON_VARIANT_SIZE, ICON_VARIANT_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.1, 0.08, 1.0))
	var points := [Vector2(64, 28), Vector2(40, 56), Vector2(88, 56), Vector2(24, 84), Vector2(64, 84), Vector2(104, 84)]
	for i in points.size():
		var color := Color(0.95, 0.82, 0.35, 1.0) if i == 0 else Color(0.82, 0.76, 0.55, 1.0)
		_draw_dot(image, points[i], 10, color)
	return ImageTexture.create_from_image(image)


func _refresh_affordability() -> void:
	if _resource_manager == null:
		return
	for type_id in _build_slots:
		var button: Button = _build_slots[type_id]
		var icon: TextureRect = button.get_meta("icon")
		var style: StyleBoxFlat = button.get_meta("style")
		var can_afford := _resource_manager.can_afford(BuildingDatabase.get_cost(type_id))
		button.disabled = not can_afford
		icon.modulate = Color.WHITE if can_afford else Color(0.45, 0.45, 0.45, 0.8)
		if type_id == _active_build_type:
			style.border_color = Color(0.85, 0.72, 0.25, 1.0)
			style.bg_color = Color(0.18, 0.14, 0.08, 0.95)
		elif can_afford:
			style.border_color = Color(0.35, 0.3, 0.22, 1.0)
			style.bg_color = Color(0.08, 0.07, 0.06, 0.85)
		else:
			style.border_color = Color(0.25, 0.22, 0.18, 1.0)
			style.bg_color = Color(0.06, 0.05, 0.04, 0.9)
		_apply_slot_style(button, style)


func _refresh_formation_highlight() -> void:
	if _selection_manager == null:
		return
	var active_formation: Unit.FormationType = _selection_manager.move_formation
	for formation_key in _formation_slots:
		var formation: Unit.FormationType = formation_key
		var button: Button = _formation_slots[formation]
		var style: StyleBoxFlat = button.get_meta("style")
		var icon: TextureRect = button.get_meta("icon")
		var is_active: bool = _formation_mode and formation == active_formation
		if is_active:
			style.border_color = Color(0.95, 0.82, 0.28, 1.0)
			style.bg_color = Color(0.22, 0.17, 0.08, 0.98)
			icon.modulate = Color(1.15, 1.05, 0.7, 1.0)
			_apply_slot_style(button, style, 4)
		else:
			style.border_color = Color(0.35, 0.3, 0.22, 1.0)
			style.bg_color = Color(0.08, 0.07, 0.06, 0.85)
			icon.modulate = Color(0.72, 0.68, 0.58, 0.9)
			_apply_slot_style(button, style, 2)


func _apply_slot_style(button: Button, style: StyleBoxFlat, border_width: int = 2) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var state_style: StyleBoxFlat = button.get_theme_stylebox(state)
		if state_style != null:
			state_style.border_color = style.border_color
			state_style.bg_color = style.bg_color
			state_style.set_border_width_all(border_width)


func _on_build_mode_changed(active: bool, type_id: String) -> void:
	_active_build_type = type_id if active else ""
	_refresh_affordability()
