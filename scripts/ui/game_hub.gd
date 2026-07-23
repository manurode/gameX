extends PanelContainer

const BUILD_ORDER: Array[String] = [
	"house_small", "house_big", "lumber_camp", "mill",
	"mine", "stable", "barracks", "arcanum", "tower", "wall",
]

const TEX_WOOD := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_resources_wood_clear.png"
const TEX_GOLD := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_resources_gold.png"
const TEX_FOOD := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_resources_food.png"

const ICON_VARIANT_SIZE := 128
const SLOT_SIZE := Vector2(108, 132)
const ICON_SIZE := Vector2(72, 60)
const RESOURCE_ICON_SIZE := Vector2(30, 30)
const ACTION_SLOT_SIZE := Vector2(88, 92)

# Palette aligned with menu / dialog panels
const COL_PANEL_INNER := Color(0.12, 0.1, 0.075, 0.9)
const COL_BORDER := Color(0.72, 0.58, 0.32, 1.0)
const COL_BORDER_DIM := Color(0.42, 0.35, 0.24, 1.0)
const COL_GOLD := Color(1.0, 0.9, 0.55, 1.0)
const COL_GOLD_SOFT := Color(0.92, 0.82, 0.52, 1.0)
const COL_CREAM := Color(0.9, 0.86, 0.74, 1.0)
const COL_MUTED := Color(0.78, 0.74, 0.64, 1.0)
const COL_BTN := Color(0.14, 0.11, 0.08, 0.95)
const COL_BTN_HOVER := Color(0.22, 0.17, 0.1, 0.98)
const COL_BTN_PRESSED := Color(0.1, 0.08, 0.05, 1.0)
const COL_BTN_DISABLED := Color(0.08, 0.07, 0.06, 0.85)

@onready var _resources_box: VBoxContainer = $MarginContainer/HBoxContainer/LeftColumn/ResourcesBox
@onready var _curfew_slot: VBoxContainer = $MarginContainer/HBoxContainer/LeftColumn/CurfewSlot
@onready var _build_mode: HBoxContainer = $MarginContainer/HBoxContainer/CenterArea/BuildMode
@onready var _selection_mode: HBoxContainer = $MarginContainer/HBoxContainer/CenterArea/SelectionMode
@onready var _build_row: HBoxContainer = $MarginContainer/HBoxContainer/CenterArea/BuildMode/BuildRow

var _selection_info: VBoxContainer
var _selection_icon: TextureRect
var _selection_title: Label
var _selection_meta: Label
var _actions_panel: PanelContainer
var _selection_actions: HBoxContainer
var _production_box: VBoxContainer
var _production_title: Label
var _production_items_box: BoxContainer
var _production_item_buttons: Dictionary = {}
var _market_box: VBoxContainer
var _market_title: Label
var _market_items_box: GridContainer
var _market_limit_label: Label
var _market_buttons: Dictionary = {}
var _food_ui_timer := 0.0
var _production_queue_label: Label
var _production_progress_label: Label
var _production_pending_label: Label
var _production_status_label: Label
var _production_panel_key: String = ""
var _production_feedback_text: String = ""
var _production_feedback_timer: float = 0.0
var _resource_manager: ResourceManager
var _build_manager: Node
var _selection_manager: Node
var _population_manager: PopulationManager
var _production_manager: ProductionManager
var _curfew_manager: CurfewManager
var _run_boon_manager: RunBoonManager
var _market_manager: MarketManager
var _curfew_button: Button
var _resource_labels: Dictionary = {}
var _build_slots: Dictionary = {}
var _population_label: Label
var _food_upkeep_label: Label
var _gather_bonus_label: Label
var _production_double_label: Label
var _active_build_type: String = ""
var _selected_building: Building = null


func _ready() -> void:
	_ensure_selection_ui()
	_show_build_mode()


func setup(
	resource_manager: ResourceManager,
	build_manager: Node,
	selection_manager: Node = null,
	population_manager: PopulationManager = null,
	production_manager: ProductionManager = null,
	curfew_manager: CurfewManager = null,
	run_boon_manager: RunBoonManager = null,
	market_manager: MarketManager = null
) -> void:
	_resource_manager = resource_manager
	_build_manager = build_manager
	_selection_manager = selection_manager
	_population_manager = population_manager
	_production_manager = production_manager
	_curfew_manager = curfew_manager
	_run_boon_manager = run_boon_manager
	_market_manager = market_manager
	_build_resource_rows()
	_build_command_grid()
	_build_curfew_button()
	_ensure_selection_ui()
	if _resource_manager != null:
		_resource_manager.resources_changed.connect(_on_resources_changed)
		_on_resources_changed(_resource_manager.wood, _resource_manager.gold, _resource_manager.food)
	if _market_manager != null and not _market_manager.trades_changed.is_connected(_on_market_trades_changed):
		_market_manager.trades_changed.connect(_on_market_trades_changed)
	if _build_manager != null and _build_manager.has_signal("build_mode_changed"):
		_build_manager.build_mode_changed.connect(_on_build_mode_changed)
	if _selection_manager != null:
		if _selection_manager.has_signal("building_selection_changed"):
			_selection_manager.building_selection_changed.connect(_on_building_selection_changed)
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
		_run_boon_manager.production_double_changed.connect(_on_production_double_changed)
		_on_gather_multiplier_changed(_run_boon_manager.get_gather_multiplier())
		_on_production_double_changed(_run_boon_manager.has_production_double())


func _build_resource_rows() -> void:
	var entries: Array[Dictionary] = [
		{"key": "gold", "texture": TEX_GOLD, "label": "Oro"},
		{"key": "wood", "texture": TEX_WOOD, "label": "Madera"},
		{"key": "food", "texture": TEX_FOOD, "label": "Comida"},
	]

	var resources_panel := PanelContainer.new()
	resources_panel.add_theme_stylebox_override("panel", _make_inner_panel_style())
	_resources_box.add_child(resources_panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 10)
	panel_margin.add_theme_constant_override("margin_right", 10)
	panel_margin.add_theme_constant_override("margin_top", 8)
	panel_margin.add_theme_constant_override("margin_bottom", 8)
	resources_panel.add_child(panel_margin)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 4)
	panel_margin.add_child(panel_vbox)

	var resources_row := HBoxContainer.new()
	resources_row.add_theme_constant_override("separation", 10)
	resources_row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_vbox.add_child(resources_row)

	for entry in entries:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.alignment = BoxContainer.ALIGNMENT_CENTER

		var icon := TextureRect.new()
		icon.custom_minimum_size = RESOURCE_ICON_SIZE
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _make_icon_atlas(entry.texture)
		cell.add_child(icon)

		var amount := Label.new()
		amount.text = "0"
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount.add_theme_font_size_override("font_size", 16)
		amount.add_theme_color_override("font_color", COL_GOLD)
		amount.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		amount.add_theme_constant_override("shadow_offset_x", 1)
		amount.add_theme_constant_override("shadow_offset_y", 1)
		cell.add_child(amount)

		resources_row.add_child(cell)
		_resource_labels[entry.key] = amount

	var stats_col := VBoxContainer.new()
	stats_col.add_theme_constant_override("separation", 1)
	stats_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_vbox.add_child(stats_col)

	_population_label = Label.new()
	_population_label.text = "Pob: 0/5"
	_population_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_population_label.add_theme_font_size_override("font_size", 12)
	_population_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	stats_col.add_child(_population_label)

	_food_upkeep_label = Label.new()
	_food_upkeep_label.text = "Consumo: 0/s"
	_food_upkeep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_food_upkeep_label.add_theme_font_size_override("font_size", 11)
	_food_upkeep_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.55))
	stats_col.add_child(_food_upkeep_label)

	var bonus_row := HBoxContainer.new()
	bonus_row.add_theme_constant_override("separation", 8)
	bonus_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_col.add_child(bonus_row)

	_gather_bonus_label = Label.new()
	_gather_bonus_label.text = "Cosecha +20%"
	_gather_bonus_label.visible = false
	_gather_bonus_label.add_theme_font_size_override("font_size", 11)
	_gather_bonus_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.55))
	bonus_row.add_child(_gather_bonus_label)

	_production_double_label = Label.new()
	_production_double_label.text = "Producción x2"
	_production_double_label.visible = false
	_production_double_label.add_theme_font_size_override("font_size", 11)
	_production_double_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	bonus_row.add_child(_production_double_label)
func _ensure_selection_ui() -> void:
	if _selection_mode == null or _selection_info != null:
		return

	var info_panel := PanelContainer.new()
	info_panel.name = "InfoPanel"
	info_panel.custom_minimum_size = Vector2(240, 0)
	info_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_panel.add_theme_stylebox_override("panel", _make_inner_panel_style())
	_selection_mode.add_child(info_panel)

	var info_margin := MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 10)
	info_margin.add_theme_constant_override("margin_right", 10)
	info_margin.add_theme_constant_override("margin_top", 8)
	info_margin.add_theme_constant_override("margin_bottom", 8)
	info_panel.add_child(info_margin)

	_selection_info = VBoxContainer.new()
	_selection_info.add_theme_constant_override("separation", 5)
	info_margin.add_child(_selection_info)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	_selection_info.add_child(header)

	_selection_icon = TextureRect.new()
	_selection_icon.custom_minimum_size = Vector2(56, 50)
	_selection_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_selection_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(_selection_icon)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)

	_selection_title = Label.new()
	_selection_title.add_theme_font_size_override("font_size", 16)
	_selection_title.add_theme_color_override("font_color", COL_GOLD_SOFT)
	_selection_title.clip_text = false
	_selection_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	titles.add_child(_selection_title)

	_selection_meta = Label.new()
	_selection_meta.add_theme_font_size_override("font_size", 13)
	_selection_meta.add_theme_color_override("font_color", COL_MUTED)
	_selection_meta.autowrap_mode = TextServer.AUTOWRAP_OFF
	titles.add_child(_selection_meta)

	# Fixed-height status slot under building info: never reflows ActionsPanel.
	var status_slot := Control.new()
	status_slot.name = "ProductionStatusSlot"
	status_slot.custom_minimum_size = Vector2(0, 36)
	status_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_slot.clip_contents = true
	_selection_info.add_child(status_slot)

	_production_status_label = Label.new()
	_production_status_label.name = "ProductionStatus"
	_production_status_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_production_status_label.add_theme_font_size_override("font_size", 12)
	_production_status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.48, 0.0))
	_production_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_production_status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_production_status_label.clip_text = false
	_production_status_label.text = ""
	status_slot.add_child(_production_status_label)

	_actions_panel = PanelContainer.new()
	_actions_panel.name = "ActionsPanel"
	_actions_panel.clip_contents = true
	_actions_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_actions_panel.add_theme_stylebox_override("panel", _make_inner_panel_style())
	_selection_mode.add_child(_actions_panel)

	var actions_margin := MarginContainer.new()
	actions_margin.add_theme_constant_override("margin_left", 10)
	actions_margin.add_theme_constant_override("margin_right", 10)
	actions_margin.add_theme_constant_override("margin_top", 8)
	actions_margin.add_theme_constant_override("margin_bottom", 8)
	_actions_panel.add_child(actions_margin)

	_production_box = VBoxContainer.new()
	_production_box.name = "ProductionBox"
	_production_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_production_box.add_theme_constant_override("separation", 5)
	actions_margin.add_child(_production_box)

	_production_title = Label.new()
	_production_title.add_theme_font_size_override("font_size", 13)
	_production_title.add_theme_color_override("font_color", COL_GOLD_SOFT)
	_production_title.clip_text = true
	_production_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_production_box.add_child(_production_title)

	_selection_actions = HBoxContainer.new()
	_selection_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_actions.add_theme_constant_override("separation", 10)
	_production_box.add_child(_selection_actions)

	_production_items_box = HBoxContainer.new()
	_production_items_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_production_items_box.add_theme_constant_override("separation", 6)
	_selection_actions.add_child(_production_items_box)

	_market_box = VBoxContainer.new()
	_market_box.visible = false
	_market_box.clip_contents = true
	_market_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_box.add_theme_constant_override("separation", 4)
	_selection_actions.add_child(_market_box)

	_market_title = Label.new()
	_market_title.text = "MERCADO"
	_market_title.add_theme_font_size_override("font_size", 13)
	_market_title.add_theme_color_override("font_color", COL_GOLD_SOFT)
	_market_box.add_child(_market_title)

	_market_items_box = GridContainer.new()
	_market_items_box.columns = 2
	_market_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_items_box.add_theme_constant_override("h_separation", 6)
	_market_items_box.add_theme_constant_override("v_separation", 4)
	_market_box.add_child(_market_items_box)

	_market_limit_label = Label.new()
	_market_limit_label.add_theme_font_size_override("font_size", 12)
	_market_limit_label.add_theme_color_override("font_color", Color(0.65, 0.74, 0.82))
	_market_box.add_child(_market_limit_label)

	_production_queue_label = Label.new()
	_production_queue_label.visible = false
	_production_progress_label = Label.new()
	_production_progress_label.visible = false
	_production_pending_label = Label.new()
	_production_pending_label.visible = false


func _build_command_grid() -> void:
	if _build_row == null:
		return
	for i in BUILD_ORDER.size():
		var type_id: String = BUILD_ORDER[i]
		var slot := _create_build_slot(type_id)
		_build_row.add_child(slot)
		_build_slots[type_id] = slot


func _build_curfew_button() -> void:
	if _curfew_slot == null:
		return
	_curfew_button = Button.new()
	_curfew_button.text = "Toque de queda"
	_curfew_button.tooltip_text = (
		"Toque de queda\n"
		+ "Los aldeanos dejan cualquier tarea y buscan refugio en el edificio más cercano con espacio.\n"
		+ "Los soldados permanecen fuera.\n\n"
		+ "Desactivado: los aldeanos siguen con sus tareas."
	)
	_curfew_button.focus_mode = Control.FOCUS_NONE
	_curfew_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_curfew_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_curfew_button.custom_minimum_size = Vector2(0, 34)
	_curfew_button.clip_text = true
	_curfew_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_curfew_button.add_theme_font_size_override("font_size", 13)
	_style_dialog_button(_curfew_button)
	_curfew_button.pressed.connect(_on_curfew_button_pressed)
	_curfew_slot.add_child(_curfew_button)

func _on_curfew_button_pressed() -> void:
	if _curfew_manager != null:
		_curfew_manager.toggle()


func _on_curfew_changed(_active: bool) -> void:
	_refresh_curfew_button()


func _refresh_curfew_button() -> void:
	if _curfew_button == null or _curfew_manager == null:
		return
	var active := _curfew_manager.is_active
	_curfew_button.text = "Toque queda: ON" if active else "Toque de queda"
	if active:
		_curfew_button.add_theme_color_override("font_color", COL_GOLD)
	else:
		_curfew_button.add_theme_color_override("font_color", COL_CREAM)


func _create_build_slot(type_id: String) -> Button:
	var def := BuildingDatabase.get_definition(type_id)
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	content.add_theme_constant_override("margin_left", 6)
	content.add_theme_constant_override("margin_top", 8)
	content.add_theme_constant_override("margin_right", 6)
	content.add_theme_constant_override("margin_bottom", 6)
	button.add_child(content)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(vbox)

	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _get_building_icon(type_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = def.get("name", type_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", COL_CREAM)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(name_label)

	var cost := BuildingDatabase.get_cost(type_id)
	button.tooltip_text = _format_cost_tooltip(
		def.get("name", type_id),
		cost,
		def.get("build_time", 0.0)
	)
	button.set_meta("style", style)
	button.set_meta("icon", icon)
	return button


func _create_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BTN
	style.border_color = COL_BORDER_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(4)
	return style


func _make_inner_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL_INNER
	style.border_color = COL_BORDER_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


func _style_dialog_button(button: Button, compact: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_BTN
	normal.border_color = COL_BORDER_DIM
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(6 if compact else 8)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COL_BTN_HOVER
	hover.border_color = COL_BORDER

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = COL_BTN_PRESSED

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = COL_BTN_DISABLED
	disabled.border_color = Color(0.28, 0.24, 0.18, 1.0)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", COL_CREAM)
	button.add_theme_color_override("font_hover_color", COL_GOLD)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.45, 1.0))


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


func _on_resources_changed(wood: int, gold: int, food: int) -> void:
	if _resource_labels.has("wood"):
		_resource_labels.wood.text = str(wood)
	if _resource_labels.has("gold"):
		_resource_labels.gold.text = str(gold)
	if _resource_labels.has("food"):
		_resource_labels.food.text = str(food)
	_refresh_affordability()
	_refresh_selection_panel()


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


func _on_production_double_changed(active: bool) -> void:
	if _production_double_label != null:
		_production_double_label.visible = active
	_refresh_selection_panel()


func _on_food_shortage(_active: bool) -> void:
	if _food_upkeep_label != null and _population_manager != null:
		_on_food_upkeep_changed(_population_manager.get_food_upkeep_per_second())


func _on_building_selection_changed(building: Building) -> void:
	_selected_building = building
	_production_feedback_text = ""
	_production_feedback_timer = 0.0
	_refresh_selection_panel()


func _on_production_queue_changed(building: Building) -> void:
	if building == _selected_building:
		_update_production_status_labels()
		_update_selection_meta()


func _process(delta: float) -> void:
	_food_ui_timer -= delta
	if _food_ui_timer <= 0.0 and _population_manager != null:
		_food_ui_timer = 0.35
		_on_food_upkeep_changed(_population_manager.get_food_upkeep_per_second())
	if _production_feedback_timer > 0.0:
		_production_feedback_timer -= delta
		if _production_feedback_timer <= 0.0:
			_production_feedback_text = ""
			if _selection_mode != null and _selection_mode.visible:
				_update_production_status_labels()
	if _selected_building != null and is_instance_valid(_selected_building):
		_update_selection_meta()
	if _selection_mode == null or not _selection_mode.visible:
		return
	_update_production_progress_label()


func _refresh_selection_panel() -> void:
	_ensure_selection_ui()
	if _selection_mode == null:
		return

	if _selected_building == null or not is_instance_valid(_selected_building):
		_show_build_mode()
		_production_panel_key = ""
		return

	_show_selection_mode()

	var building := _selected_building
	var building_name := building.get_display_name()
	_selection_title.text = building_name
	_selection_icon.texture = _get_building_icon(building.building_type_id)
	_update_selection_meta()

	var items := _get_production_items_for_building(building)
	var show_market := _should_show_market(building)
	var has_actions := not items.is_empty() or show_market

	if _actions_panel != null:
		_actions_panel.visible = has_actions

	if not has_actions:
		_production_panel_key = ""
		return

	if _has_production_double() and not items.is_empty():
		_production_title.text = "PRODUCCIÓN · x2"
		_production_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	elif not items.is_empty():
		_production_title.text = "PRODUCCIÓN"
		_production_title.add_theme_color_override("font_color", COL_GOLD_SOFT)
	else:
		_production_title.text = ""
		_production_title.add_theme_color_override("font_color", COL_GOLD_SOFT)

	_production_title.visible = not items.is_empty()
	_production_items_box.visible = not items.is_empty()
	_market_box.visible = show_market
	_selection_actions.visible = true

	var trades_left := 0
	if _market_manager != null:
		trades_left = _market_manager.get_trades_remaining()
	var panel_key := "%d:%s:%s:m%d" % [
		building.get_instance_id(),
		",".join(items),
		"x2" if _has_production_double() else "x1",
		trades_left if show_market else -1,
	]
	if _production_panel_key != panel_key:
		_rebuild_production_item_buttons(items)
		_rebuild_market_buttons(show_market)
		_production_panel_key = panel_key

	_update_production_status_labels()
	_update_market_status()


func _update_selection_meta() -> void:
	if _selection_meta == null or _selected_building == null or not is_instance_valid(_selected_building):
		return
	var building := _selected_building
	var parts: PackedStringArray = ["PV %d/%d" % [building.hp, building.max_hp]]
	if building.can_garrison:
		parts.append("Guarnición %d/%d" % [building.get_garrison_count(), building.garrison_capacity])
	if BuildingDatabase.is_gather_building(building.building_type_id):
		parts.append("Trabajadores max: %d" % BuildingDatabase.get_max_workers(building.building_type_id))
	if building.upgrade_level > 0:
		parts.append("Nv.%d" % (building.upgrade_level + 1))
	_selection_meta.text = "\n".join(parts)


func _should_show_market(building: Building) -> bool:
	return (
		building != null
		and building.building_type_id == "town_center"
		and _market_manager != null
	)


func _has_production_double() -> bool:
	return _run_boon_manager != null and _run_boon_manager.has_production_double()


func _get_production_items_for_building(building: Building) -> Array[String]:
	var items := building.get_production_items()
	if items.is_empty():
		items = EquipmentDatabase.get_items_for_building(building.building_type_id)
	return items


func _rebuild_production_item_buttons(items: Array[String]) -> void:
	for child in _production_items_box.get_children():
		child.queue_free()
	_production_item_buttons.clear()
	_production_items_box.visible = not items.is_empty()

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
		button.custom_minimum_size = ACTION_SLOT_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.clip_contents = true
		_style_dialog_button(button, true)
		button.add_theme_font_size_override("font_size", 13)

		var unit_name: String = def.get("name", item_id)
		if _has_production_double():
			button.text = "%s\nx2" % unit_name
			button.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
		else:
			button.text = unit_name
		button.tooltip_text = "%s · %.0f s%s" % [
			cost_text,
			def.get("train_time", 0.0),
			" · genera 2 unidades" if _has_production_double() else "",
		]
		button.pressed.connect(_on_production_pressed.bind(item_id))
		# Fixed bottom padding so text does not jump when the bar appears.
		var style_names := ["normal", "hover", "pressed", "disabled"]
		for style_name in style_names:
			var style: StyleBoxFlat = button.get_theme_stylebox(style_name) as StyleBoxFlat
			if style != null:
				style.content_margin_bottom = 12.0
		var progress_bar := _create_production_progress_bar()
		button.add_child(progress_bar)
		button.set_meta("progress_bar", progress_bar)
		button.set_meta("base_tooltip", button.tooltip_text)
		_production_items_box.add_child(button)
		_production_item_buttons[item_id] = button


func _rebuild_market_buttons(show_market: bool) -> void:
	for child in _market_items_box.get_children():
		child.queue_free()
	_market_buttons.clear()

	if not show_market or _market_manager == null:
		_market_box.visible = false
		return

	_market_box.visible = true

	for offer in _market_manager.get_offers():
		var from_key: String = offer.from
		var to_key: String = offer.to
		var button := Button.new()
		button.text = _format_market_offer_compact(offer)
		button.tooltip_text = (
			"Intercambia en el mercado de la Ciudadela.\n"
			+ "Comisión del mercado: %d%% · máximo %d intercambios por día."
		) % [
			int(BalanceConfig.MARKET_FEE * 100.0),
			BalanceConfig.MARKET_TRADES_PER_CYCLE,
		]
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.custom_minimum_size = Vector2(140, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size", 12)
		_style_dialog_button(button, true)
		button.pressed.connect(_on_market_exchange_pressed.bind(from_key, to_key))
		_market_items_box.add_child(button)
		_market_buttons["%s>%s" % [from_key, to_key]] = button


func _format_market_offer_compact(offer: Dictionary) -> String:
	const SHORT := {"wood": "madera", "gold": "oro", "food": "comida"}
	var from_key: String = str(offer.get("from", ""))
	var to_key: String = str(offer.get("to", ""))
	return "%d %s → %d %s" % [
		int(offer.get("pay", 0)),
		SHORT.get(from_key, offer.get("from_label", from_key)),
		int(offer.get("receive", 0)),
		SHORT.get(to_key, offer.get("to_label", to_key)),
	]


func _update_market_status() -> void:
	if _market_manager == null or not _should_show_market(_selected_building):
		return

	var remaining := _market_manager.get_trades_remaining()
	_market_limit_label.text = "Intercambios hoy: %d/%d" % [
		remaining,
		BalanceConfig.MARKET_TRADES_PER_CYCLE,
	]
	if remaining <= 0:
		_market_limit_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	else:
		_market_limit_label.add_theme_color_override("font_color", Color(0.65, 0.74, 0.82))

	for offer in _market_manager.get_offers():
		var key := "%s>%s" % [offer.from, offer.to]
		var button: Button = _market_buttons.get(key)
		if button == null:
			continue
		var can_trade := _market_manager.can_exchange(offer.from, offer.to)
		button.disabled = not can_trade
		button.text = _format_market_offer_compact(offer)
		var reason := _market_manager.get_exchange_block_reason(offer.from, offer.to)
		if reason.is_empty():
			button.tooltip_text = (
				"Intercambia en el mercado de la Ciudadela.\n"
				+ "Comisión del mercado: %d%% · máximo %d intercambios por día."
			) % [
				int(BalanceConfig.MARKET_FEE * 100.0),
				BalanceConfig.MARKET_TRADES_PER_CYCLE,
			]
		else:
			button.tooltip_text = reason


func _on_market_exchange_pressed(from_key: String, to_key: String) -> void:
	if _market_manager == null:
		return
	if _market_manager.try_exchange(from_key, to_key):
		_production_feedback_text = ""
		_production_feedback_timer = 0.0
		_update_market_status()
		_update_production_status_labels()
		return
	var reason := _market_manager.get_exchange_block_reason(from_key, to_key)
	if reason.is_empty():
		reason = "No se puede intercambiar ahora"
	_production_feedback_text = reason
	_production_feedback_timer = 3.5
	_update_market_status()
	_update_production_status_labels()


func _on_market_trades_changed(_trades_remaining: int) -> void:
	if _selection_mode != null and _selection_mode.visible:
		_production_panel_key = ""
		_refresh_selection_panel()


func _update_production_status_labels() -> void:
	if _selected_building == null or _production_manager == null:
		return

	var items := _get_production_items_for_building(_selected_building)
	var queue_counts := _production_manager.get_queue_counts(_selected_building)
	var double_active := _has_production_double()
	for item_id in items:
		var button: Button = _production_item_buttons.get(item_id)
		if button == null:
			continue
		var def := EquipmentDatabase.get_definition(item_id)
		var queued_count: int = queue_counts.get(item_id, 0)
		var unit_name: String = def.get("name", item_id)
		if double_active:
			button.text = "%s\nx2" % unit_name
			button.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
		else:
			button.text = unit_name
			button.add_theme_color_override("font_color", COL_CREAM)
		if queued_count > 0:
			button.text += "\n(x%d)" % queued_count

	_update_production_progress_label()


func _set_production_status_message(text: String) -> void:
	if _production_status_label == null:
		return
	# Keep reserved height even when empty so the hub never jumps.
	_production_status_label.text = text
	if text.is_empty():
		_production_status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.48, 0.0))
	else:
		_production_status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.48, 1.0))


func _resolve_production_status_message(_queue: Array, current: Dictionary = {}) -> String:
	if not _production_feedback_text.is_empty():
		return _production_feedback_text

	if not current.is_empty():
		if not current.get("paid", true):
			return "Esperando recursos..."
		var time_total: float = maxf(float(current.get("time_total", 1.0)), 0.1)
		var progress: float = float(current.get("progress", 0.0))
		if progress >= time_total:
			var item_id: String = current.get("item_id", "")
			var def := EquipmentDatabase.get_definition(item_id)
			if def.get("transforms_to", "").is_empty() \
					and _population_manager != null \
					and not _population_manager.can_add_population():
				return "Falta espacio de población — construye casas"

	var pending := _production_manager.get_pending_recruitment(_selected_building)
	if not pending.is_empty() and pending.get("count", 0) > 0:
		var pending_def := EquipmentDatabase.get_definition(pending.get("item_id", ""))
		var pending_name: String = pending_def.get("name", "equipo")
		return "Esperando %d aldeano(s) para %s" % [pending.count, pending_name]

	return ""


func _create_production_progress_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = "TrainProgress"
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 4.0
	bar.offset_right = -4.0
	bar.offset_top = -8.0
	bar.offset_bottom = -3.0
	# Always occupy the same slot; empty fill when idle so layout never shifts.
	bar.modulate.a = 0.35

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.06, 0.04, 0.95)
	bg.set_corner_radius_all(2)
	bg.set_content_margin_all(0)

	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_GOLD
	fill.set_corner_radius_all(2)
	fill.set_content_margin_all(0)

	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _set_production_button_progress(button: Button, ratio: float, active: bool, status_tooltip: String = "") -> void:
	var bar: ProgressBar = button.get_meta("progress_bar", null)
	if bar != null:
		bar.value = ratio if active else 0.0
		bar.modulate.a = 1.0 if active else 0.35
	if active and not status_tooltip.is_empty():
		button.tooltip_text = status_tooltip
	elif button.has_meta("base_tooltip"):
		button.tooltip_text = button.get_meta("base_tooltip")


func _clear_production_button_progress() -> void:
	for item_id in _production_item_buttons:
		var button: Button = _production_item_buttons[item_id]
		if button == null or not is_instance_valid(button):
			continue
		_set_production_button_progress(button, 0.0, false)


func _update_production_progress_label() -> void:
	if _production_manager == null or _selected_building == null:
		_set_production_status_message("")
		return

	var queue := _production_manager.get_queue(_selected_building)
	if queue.is_empty():
		_clear_production_button_progress()
		_set_production_status_message(_resolve_production_status_message(queue))
		return

	var current: Dictionary = queue[0]
	var active_item_id: String = current.get("item_id", "")
	var time_total: float = maxf(float(current.get("time_total", 1.0)), 0.1)
	var progress: float = float(current.get("progress", 0.0))
	var ratio: float = 0.0
	var status_tooltip := ""
	var status_message := _resolve_production_status_message(queue, current)

	if not current.get("paid", true):
		status_tooltip = status_message
	elif progress >= time_total:
		ratio = 1.0
		status_tooltip = status_message if not status_message.is_empty() else "Produciendo... 100%"
	else:
		ratio = clampf(progress / time_total, 0.0, 1.0)
		var remaining: float = maxf(time_total - progress, 0.0)
		status_tooltip = "Produciendo... %d%% · %.1f s" % [int(ratio * 100.0), remaining]

	_set_production_status_message(status_message)

	for item_id in _production_item_buttons:
		var button: Button = _production_item_buttons[item_id]
		if button == null or not is_instance_valid(button):
			continue
		var is_active: bool = str(item_id) == active_item_id
		_set_production_button_progress(
			button,
			ratio if is_active else 0.0,
			is_active,
			status_tooltip if is_active else ""
		)


func _on_production_pressed(item_id: String) -> void:
	if _production_manager == null or _selected_building == null:
		return
	if _production_manager.enqueue(_selected_building, item_id):
		_production_feedback_text = ""
		_production_feedback_timer = 0.0
		_update_production_status_labels()
		return
	var reason := _production_manager.get_enqueue_block_reason(_selected_building, item_id)
	if reason.is_empty():
		reason = "No se puede producir ahora"
	_production_feedback_text = reason
	_production_feedback_timer = 3.5
	_update_production_status_labels()


func _show_build_mode() -> void:
	if _build_mode != null:
		_build_mode.visible = true
	if _selection_mode != null:
		_selection_mode.visible = false
	_set_production_status_message("")


func _show_selection_mode() -> void:
	if _build_mode != null:
		_build_mode.visible = false
	if _selection_mode != null:
		_selection_mode.visible = true


func _show_build_panel() -> void:
	_show_build_mode()


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
			style.border_color = COL_BORDER
			style.bg_color = Color(0.18, 0.14, 0.08, 0.95)
		elif can_afford:
			style.border_color = COL_BORDER_DIM
			style.bg_color = COL_BTN
		else:
			style.border_color = Color(0.25, 0.22, 0.18, 1.0)
			style.bg_color = COL_BTN_DISABLED
		_apply_slot_style(button, style)


func _apply_slot_style(button: Button, style: StyleBoxFlat, border_width: int = 1) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var state_style: StyleBoxFlat = button.get_theme_stylebox(state)
		if state_style != null:
			state_style.border_color = style.border_color
			state_style.bg_color = style.bg_color
			state_style.set_border_width_all(border_width)


func _on_build_mode_changed(active: bool, type_id: String) -> void:
	_active_build_type = type_id if active else ""
	_refresh_affordability()
