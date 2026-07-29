extends PanelContainer

const BUILD_ORDER: Array[String] = [
	"house_small", "house_big", "lumber_camp", "mill",
	"mine", "stable", "barracks", "arcanum", "tower", "wall",
]

const TEX_WOOD := "res://assets/ui/icons/icon_wood.png"
const TEX_GOLD := "res://assets/ui/icons/icon_gold.png"
const TEX_FOOD := "res://assets/ui/icons/icon_food.png"

const SLOT_SIZE := Vector2(108, 132)
const ICON_SIZE := Vector2(72, 60)
const RESOURCE_ICON_SIZE := Vector2(56, 56)
const ACTION_SLOT_SIZE := Vector2(88, 92)
const UNIT_CARD_ICON_SIZE := Vector2(56, 50)

# Palette aligned with menu / dialog panels
const COL_PANEL_INNER := Color(0.12, 0.1, 0.075, 0.9)
const COL_BORDER := Color(0.72, 0.58, 0.32, 1.0)
const COL_BORDER_DIM := Color(0.42, 0.35, 0.24, 1.0)
const COL_GOLD := Color(1.0, 0.9, 0.55, 1.0)
const COL_GOLD_SOFT := Color(0.92, 0.82, 0.52, 1.0)
const COL_CREAM := Color(0.9, 0.86, 0.74, 1.0)
const COL_MUTED := Color(0.78, 0.74, 0.64, 1.0)
const COL_ENEMY_ACCENT := Color(0.95, 0.42, 0.38, 1.0)
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
var _building_info_panel: PanelContainer
var _unit_selection_scroll: ScrollContainer
var _unit_selection_row: HBoxContainer
var _unit_selection_layout_key: String = ""
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
var _selected_units: Array[Unit] = []
var _special_actions_box: HBoxContainer
var _actions_spacer: Control
var _demolish_action_box: HBoxContainer
var _special_action_buttons: Dictionary = {}


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
		if _selection_manager.has_signal("selection_changed"):
			_selection_manager.selection_changed.connect(_on_unit_selection_changed)
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
	resources_row.add_theme_constant_override("separation", 14)
	resources_row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_vbox.add_child(resources_row)

	for entry in entries:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.alignment = BoxContainer.ALIGNMENT_CENTER

		var icon := TextureRect.new()
		icon.custom_minimum_size = RESOURCE_ICON_SIZE
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Same filter path as building icons in the hub.
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.texture = load(entry.texture) as Texture2D
		cell.add_child(icon)

		var amount := Label.new()
		amount.text = "0"
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount.add_theme_font_size_override("font_size", 15)
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
	if _selection_mode == null:
		return
	if _selection_info != null:
		_ensure_special_actions_box()
		_ensure_unit_selection_ui()
		if _building_info_panel == null:
			_building_info_panel = _selection_mode.get_node_or_null("InfoPanel") as PanelContainer
		return

	var info_panel := PanelContainer.new()
	info_panel.name = "InfoPanel"
	info_panel.custom_minimum_size = Vector2(240, 0)
	info_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_panel.add_theme_stylebox_override("panel", _make_inner_panel_style())
	_selection_mode.add_child(info_panel)
	_building_info_panel = info_panel

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
	_selection_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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

	_special_actions_box = HBoxContainer.new()
	_special_actions_box.name = "SpecialActionsBox"
	_special_actions_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_special_actions_box.add_theme_constant_override("separation", 6)
	_selection_actions.add_child(_special_actions_box)

	_market_box = VBoxContainer.new()
	_market_box.visible = false
	_market_box.clip_contents = true
	_market_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_box.add_theme_constant_override("separation", 4)
	_selection_actions.add_child(_market_box)

	_ensure_demolish_action_box()

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

	_ensure_unit_selection_ui()


func _ensure_unit_selection_ui() -> void:
	if _selection_mode == null:
		return

	var existing_scroll := _selection_mode.get_node_or_null("UnitSelectionScroll") as ScrollContainer
	if existing_scroll != null:
		_unit_selection_scroll = existing_scroll
		var padding := existing_scroll.get_node_or_null("UnitSelectionPadding") as MarginContainer
		if padding != null:
			_unit_selection_row = padding.get_node_or_null("UnitSelectionRow") as HBoxContainer
		else:
			_unit_selection_row = existing_scroll.get_node_or_null("UnitSelectionRow") as HBoxContainer
		_apply_unit_selection_layout_flags()
		if _unit_selection_row != null:
			if not _selection_mode.resized.is_connected(_layout_unit_selection_scroll):
				_selection_mode.resized.connect(_layout_unit_selection_scroll)
			return

	_unit_selection_scroll = ScrollContainer.new()
	_unit_selection_scroll.name = "UnitSelectionScroll"
	_unit_selection_scroll.visible = false
	_unit_selection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_unit_selection_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_selection_mode.add_child(_unit_selection_scroll)
	_selection_mode.move_child(_unit_selection_scroll, 0)
	_apply_unit_selection_layout_flags()

	var scroll_padding := MarginContainer.new()
	scroll_padding.name = "UnitSelectionPadding"
	scroll_padding.add_theme_constant_override("margin_left", 2)
	scroll_padding.add_theme_constant_override("margin_right", 2)
	scroll_padding.add_theme_constant_override("margin_top", 4)
	scroll_padding.add_theme_constant_override("margin_bottom", 6)
	_unit_selection_scroll.add_child(scroll_padding)

	_unit_selection_row = HBoxContainer.new()
	_unit_selection_row.name = "UnitSelectionRow"
	_unit_selection_row.add_theme_constant_override("separation", 10)
	_unit_selection_row.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll_padding.add_child(_unit_selection_row)

	if not _selection_mode.resized.is_connected(_layout_unit_selection_scroll):
		_selection_mode.resized.connect(_layout_unit_selection_scroll)


func _apply_unit_selection_layout_flags() -> void:
	if _unit_selection_scroll == null:
		return
	# Match building InfoPanel: shrink to content and let SelectionMode center it.
	_unit_selection_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_unit_selection_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _unit_selection_row != null:
		_unit_selection_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_unit_selection_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _layout_unit_selection_scroll() -> void:
	if (
		_unit_selection_scroll == null
		or _unit_selection_row == null
		or _selection_mode == null
		or not _unit_selection_scroll.visible
	):
		return

	var pad_w := 4
	var padding := _unit_selection_scroll.get_node_or_null("UnitSelectionPadding") as MarginContainer
	if padding != null:
		pad_w = padding.get_theme_constant("margin_left") + padding.get_theme_constant("margin_right")

	var content_w := _unit_selection_row.get_combined_minimum_size().x + pad_w
	var available_w := maxf(_selection_mode.size.x - 8.0, 120.0)
	if content_w > available_w:
		_unit_selection_scroll.custom_minimum_size.x = available_w
		_unit_selection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	else:
		_unit_selection_scroll.custom_minimum_size.x = content_w
		_unit_selection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _ensure_special_actions_box() -> void:
	if _special_actions_box == null and _selection_actions != null:
		_special_actions_box = HBoxContainer.new()
		_special_actions_box.name = "SpecialActionsBox"
		_special_actions_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_special_actions_box.add_theme_constant_override("separation", 6)
		# Keep special actions before the market column when both exist.
		var market_idx := _market_box.get_index() if _market_box != null else -1
		_selection_actions.add_child(_special_actions_box)
		if market_idx >= 0:
			_selection_actions.move_child(_special_actions_box, market_idx)

	_ensure_demolish_action_box()

	if _production_queue_label == null:
		_production_queue_label = Label.new()
		_production_queue_label.visible = false
		_production_progress_label = Label.new()
		_production_progress_label.visible = false
		_production_pending_label = Label.new()
		_production_pending_label.visible = false


func _ensure_demolish_action_box() -> void:
	if _selection_actions == null:
		return
	if _actions_spacer == null:
		_actions_spacer = Control.new()
		_actions_spacer.name = "ActionsSpacer"
		_actions_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_actions_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_selection_actions.add_child(_actions_spacer)
	if _demolish_action_box == null:
		_demolish_action_box = HBoxContainer.new()
		_demolish_action_box.name = "DemolishActionBox"
		_demolish_action_box.size_flags_horizontal = Control.SIZE_SHRINK_END
		_demolish_action_box.add_theme_constant_override("separation", 6)
		_selection_actions.add_child(_demolish_action_box)
	# Always keep spacer + demolish at the far right of the action row.
	_selection_actions.move_child(_actions_spacer, _selection_actions.get_child_count() - 1)
	_selection_actions.move_child(_demolish_action_box, _selection_actions.get_child_count() - 1)


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
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
		def.get("build_time", 0.0),
		def.get("description", "")
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
	if type_id == "gate":
		return WallTexture.get_gate_texture(false)
	var texture_path: String = def.get("texture", "")
	if texture_path.is_empty():
		return null
	return load(texture_path)


func _format_cost_parts(cost: Dictionary, include_villager: bool = false) -> PackedStringArray:
	var parts: PackedStringArray = []
	if cost.get("wood", 0) > 0:
		parts.append("%d madera" % cost.wood)
	if cost.get("gold", 0) > 0:
		parts.append("%d oro" % cost.gold)
	if cost.get("food", 0) > 0:
		parts.append("%d comida" % cost.food)
	if include_villager:
		parts.append("1 aldeano")
	return parts


func _format_cost_tooltip(
	name: String,
	cost: Dictionary,
	duration: float = 0.0,
	description: String = ""
) -> String:
	var parts := _format_cost_parts(cost)
	var details := " · ".join(parts) if not parts.is_empty() else "Gratis"
	if duration > 0.0:
		details += " · %.0f s" % duration
	if description.is_empty():
		return "%s\n%s" % [name, details]
	return "%s\n%s\n%s" % [name, description, details]


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
		_population_label.text = "Población: %d/%d" % [pop, cap]
	if _selection_mode != null and _selection_mode.visible:
		_update_production_status_labels()


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
		_food_upkeep_label.text = "Consumo alimento: %.2f/s | balance %+.2f" % [upkeep, net]
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
	if building != null:
		_selected_units.clear()
	_production_feedback_text = ""
	_production_feedback_timer = 0.0
	_refresh_selection_panel()


func _on_unit_selection_changed(units: Array) -> void:
	_selected_units.clear()
	for node in units:
		if node is Unit and is_instance_valid(node):
			_selected_units.append(node)
	if not _selected_units.is_empty():
		_selected_building = null
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
	if not _selected_units.is_empty():
		var valid_units := _get_valid_selected_units()
		if valid_units.is_empty():
			_refresh_selection_panel()
		else:
			var layout_key := _get_unit_selection_layout_key(valid_units)
			if (
				_selection_mode != null
				and _selection_mode.visible
				and layout_key != _unit_selection_layout_key
			):
				_show_unit_selection(valid_units)
			else:
				_update_unit_selection_meta()
	if _selection_mode == null or not _selection_mode.visible:
		return
	_update_production_progress_label()


func _refresh_selection_panel() -> void:
	_ensure_selection_ui()
	if _selection_mode == null:
		return

	if _selected_building != null and is_instance_valid(_selected_building):
		_show_building_selection()
		return

	var valid_units := _get_valid_selected_units()
	if not valid_units.is_empty():
		_show_unit_selection(valid_units)
		return

	_show_build_mode()
	_unit_selection_layout_key = ""
	_production_panel_key = ""


func _show_building_selection() -> void:
	_show_selection_mode()
	if _building_info_panel != null:
		_building_info_panel.visible = true
	if _unit_selection_scroll != null:
		_unit_selection_scroll.visible = false
	_unit_selection_layout_key = ""

	var building := _selected_building
	var building_name := building.get_display_name()
	_selection_title.text = building_name
	_selection_icon.texture = _get_building_icon(building.building_type_id)
	_update_selection_meta()

	var items := _get_production_items_for_building(building)
	var show_market := _should_show_market(building)
	var special_actions := _get_special_actions_for_building(building)
	var has_actions := not items.is_empty() or show_market or not special_actions.is_empty()

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
	elif not special_actions.is_empty():
		_production_title.text = "ACCIONES"
		_production_title.add_theme_color_override("font_color", COL_GOLD_SOFT)
	else:
		_production_title.text = ""
		_production_title.add_theme_color_override("font_color", COL_GOLD_SOFT)

	_production_title.visible = not items.is_empty() or not special_actions.is_empty()
	_production_items_box.visible = not items.is_empty()
	_market_box.visible = show_market
	_selection_actions.visible = true

	var trades_left := 0
	if _market_manager != null:
		trades_left = _market_manager.get_trades_remaining()
	var special_key := ",".join(special_actions)
	if building.building_type_id == "gate":
		special_key += ":L%d" % (1 if building.is_gate_locked() else 0)
	var panel_key := "%d:%s:%s:m%d:s%s" % [
		building.get_instance_id(),
		",".join(items),
		"x2" if _has_production_double() else "x1",
		trades_left if show_market else -1,
		special_key,
	]
	if _production_panel_key != panel_key:
		_rebuild_production_item_buttons(items)
		_rebuild_market_buttons(show_market)
		_rebuild_special_action_buttons(special_actions)
		_production_panel_key = panel_key

	_update_production_status_labels()
	_update_market_status()
	_update_special_action_affordability()


func _show_unit_selection(units: Array[Unit]) -> void:
	_show_selection_mode()
	if _building_info_panel != null:
		_building_info_panel.visible = false
	if _actions_panel != null:
		_actions_panel.visible = false
	if _unit_selection_scroll != null:
		_unit_selection_scroll.visible = true
		call_deferred("_layout_unit_selection_scroll")

	var layout_key := _get_unit_selection_layout_key(units)
	if layout_key != _unit_selection_layout_key:
		_rebuild_unit_selection_cards(units)
		_unit_selection_layout_key = layout_key
	else:
		_update_unit_selection_meta()


func _get_valid_selected_units() -> Array[Unit]:
	var valid: Array[Unit] = []
	for unit in _selected_units:
		if unit != null and is_instance_valid(unit) and unit.hp > 0:
			valid.append(unit)
	return valid


func _get_unit_group_key(unit: Unit) -> String:
	if unit is EnemyUnit:
		return "enemy:%s" % (unit as EnemyUnit).enemy_kind
	return "ally:%s" % unit.unit_type_id


func _get_unit_selection_layout_key(units: Array[Unit]) -> String:
	var groups := _group_selected_units(units)
	var parts: PackedStringArray = []
	for group_key in groups.keys():
		parts.append("%s=%d" % [group_key, (groups[group_key] as Array).size()])
	parts.sort()
	return "|".join(parts)


func _group_selected_units(units: Array[Unit]) -> Dictionary:
	var groups: Dictionary = {}
	for unit in units:
		var key := _get_unit_group_key(unit)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(unit)
	return groups


func _sorted_unit_group_keys(groups: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in groups.keys():
		keys.append(key)
	keys.sort_custom(func(a: String, b: String) -> bool:
		var a_enemy := a.begins_with("enemy:")
		var b_enemy := b.begins_with("enemy:")
		if a_enemy != b_enemy:
			return not a_enemy
		var a_units: Array = groups[a]
		var b_units: Array = groups[b]
		if a_units.is_empty() or b_units.is_empty():
			return a < b
		return UnitDatabase.get_unit_display_name(a_units[0]) < UnitDatabase.get_unit_display_name(b_units[0])
	)
	return keys


func _rebuild_unit_selection_cards(units: Array[Unit]) -> void:
	if _unit_selection_row == null:
		return
	for child in _unit_selection_row.get_children():
		child.queue_free()

	var groups := _group_selected_units(units)
	for group_key in _sorted_unit_group_keys(groups):
		var group_units: Array = groups[group_key]
		_unit_selection_row.add_child(_create_unit_group_card(group_units))
	call_deferred("_layout_unit_selection_scroll")


func _create_unit_group_card(units: Array) -> Control:
	var sample: Unit = units[0]
	var count: int = units.size()
	var is_enemy := sample.team_id == Team.ENEMY

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.set_meta("units", units)
	var card_style := _make_inner_panel_style()
	if is_enemy:
		card_style.border_color = COL_ENEMY_ACCENT
	card.add_theme_stylebox_override("panel", card_style)

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 10)
	card_margin.add_theme_constant_override("margin_right", 10)
	card_margin.add_theme_constant_override("margin_top", 8)
	card_margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(card_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	card_margin.add_child(header)

	var icon := TextureRect.new()
	icon.custom_minimum_size = UNIT_CARD_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var icon_type_id := UnitDatabase.get_icon_type_id_for_unit(sample)
	icon.texture = UnitDatabase.get_unit_icon(icon_type_id)
	header.add_child(icon)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	titles.add_child(title_row)

	var title := Label.new()
	title.name = "UnitTitle"
	title.text = UnitDatabase.get_unit_display_name(sample)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override(
		"font_color",
		COL_ENEMY_ACCENT if is_enemy else COL_GOLD_SOFT
	)
	title.clip_text = false
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_row.add_child(title)

	if count > 1:
		title_row.add_child(_create_unit_count_chip(count, is_enemy))

	var meta := Label.new()
	meta.name = "UnitMeta"
	meta.text = _format_unit_group_meta(units)
	meta.add_theme_font_size_override("font_size", 13)
	meta.add_theme_color_override("font_color", COL_MUTED)
	meta.autowrap_mode = TextServer.AUTOWRAP_OFF
	titles.add_child(meta)

	return card


func _create_unit_count_chip(count: int, is_enemy: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = COL_BTN
	chip_style.border_color = COL_ENEMY_ACCENT if is_enemy else COL_BORDER_DIM
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(5)
	chip_style.set_content_margin_all(4)
	chip.add_theme_stylebox_override("panel", chip_style)

	var chip_label := Label.new()
	chip_label.text = "×%d" % count
	chip_label.add_theme_font_size_override("font_size", 13)
	chip_label.add_theme_color_override(
		"font_color",
		COL_ENEMY_ACCENT if is_enemy else COL_GOLD
	)
	chip.add_child(chip_label)
	return chip


func _format_unit_group_meta(units: Array) -> String:
	if units.is_empty():
		return ""
	var sample: Unit = units[0]
	var total_hp := 0
	var total_max_hp := 0
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		total_hp += unit.hp
		total_max_hp += unit.max_hp

	var parts: PackedStringArray = ["PV %d/%d" % [total_hp, total_max_hp]]
	if sample.can_attack:
		var attack_value := sample.get_attack_damage()
		parts.append("ATK %d" % attack_value)
		if sample.combat_style == Unit.CombatStyle.RANGED:
			parts.append("Alcance %.0f" % sample.attack_range_max)
		else:
			parts.append("Cuerpo a cuerpo")
	else:
		var roles: PackedStringArray = []
		if sample.can_gather:
			roles.append("Recolector")
		if sample.can_build:
			roles.append("Constructor")
		if not roles.is_empty():
			parts.append(" · ".join(roles))
		else:
			parts.append("Sin combate")
	return "\n".join(parts)


func _update_unit_selection_meta() -> void:
	if _unit_selection_row == null:
		return
	for card in _unit_selection_row.get_children():
		if not card.has_meta("units"):
			continue
		var units: Array = card.get_meta("units")
		var live_units: Array[Unit] = []
		for unit in units:
			if unit is Unit and is_instance_valid(unit) and unit.hp > 0:
				live_units.append(unit)
		if live_units.is_empty():
			continue
		var meta := card.find_child("UnitMeta", true, false) as Label
		if meta != null:
			meta.text = _format_unit_group_meta(live_units)


func _get_special_actions_for_building(building: Building) -> Array[String]:
	var actions: Array[String] = []
	if building == null or not is_instance_valid(building):
		return actions
	if (
		building.building_type_id == "wall"
		and building.building_state == Building.BuildingState.ACTIVE
	):
		actions.append("build_gate")
	elif (
		building.building_type_id == "gate"
		and building.building_state == Building.BuildingState.ACTIVE
	):
		actions.append("toggle_gate_lock")
	if building.can_demolish():
		actions.append("demolish")
	return actions


func _rebuild_special_action_buttons(actions: Array[String]) -> void:
	_ensure_demolish_action_box()
	if _special_actions_box == null:
		return

	for child in _special_actions_box.get_children():
		child.queue_free()
	if _demolish_action_box != null:
		for child in _demolish_action_box.get_children():
			child.queue_free()
	_special_action_buttons.clear()

	var left_actions: Array[String] = []
	var has_demolish := false
	for action_id in actions:
		if action_id == "demolish":
			has_demolish = true
		else:
			left_actions.append(action_id)

	_special_actions_box.visible = not left_actions.is_empty()
	if _demolish_action_box != null:
		_demolish_action_box.visible = has_demolish
	if _actions_spacer != null:
		_actions_spacer.visible = has_demolish

	for action_id in left_actions:
		_add_special_action_button(_special_actions_box, action_id)
	if has_demolish:
		_add_special_action_button(_demolish_action_box, "demolish")


func _add_special_action_button(parent: HBoxContainer, action_id: String) -> void:
	if parent == null:
		return
	var slot := Control.new()
	slot.custom_minimum_size = ACTION_SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.clip_contents = true
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_style_dialog_button(button, true)
	button.add_theme_font_size_override("font_size", 13)
	button.text = _special_action_label(action_id)
	button.tooltip_text = _special_action_tooltip(action_id)
	button.pressed.connect(_on_special_action_pressed.bind(action_id))
	slot.add_child(button)
	parent.add_child(slot)
	_special_action_buttons[action_id] = button


func _special_action_label(action_id: String) -> String:
	match action_id:
		"build_gate":
			return "Puerta"
		"toggle_gate_lock":
			if _selected_building != null and _selected_building.is_gate_locked():
				return "Desbloquear"
			return "Bloquear"
		"demolish":
			return "Demoler"
		_:
			return action_id


func _special_action_tooltip(action_id: String) -> String:
	match action_id:
		"build_gate":
			var def := BuildingDatabase.get_definition("gate")
			return _format_cost_tooltip(
				"Construir puerta",
				BuildingDatabase.get_cost("gate"),
				float(def.get("build_time", 0.0)),
				str(def.get("description", ""))
			)
		"toggle_gate_lock":
			if _selected_building != null and _selected_building.is_gate_locked():
				return "Desbloquear\nSe abrirá cuando un aliado se acerque"
			return "Bloquear cerrada\nPermanecerá cerrada aunque haya aliados cerca"
		"demolish":
			return _format_demolish_tooltip()
		_:
			return ""


func _format_demolish_tooltip() -> String:
	if _selected_building == null or not is_instance_valid(_selected_building):
		return "Demoler"
	var refund := _selected_building.get_demolish_refund()
	var parts := _format_cost_parts(refund)
	if parts.is_empty():
		return "Demoler\nNo recuperas recursos"
	return "Demoler\nRecuperas: %s" % " · ".join(parts)


func _on_special_action_pressed(action_id: String) -> void:
	if _selected_building == null or not is_instance_valid(_selected_building):
		return
	match action_id:
		"build_gate":
			if _build_manager != null and _build_manager.has_method("try_convert_wall_to_gate"):
				_build_manager.try_convert_wall_to_gate(_selected_building)
		"toggle_gate_lock":
			_selected_building.toggle_gate_locked()
			_production_panel_key = ""
			_refresh_selection_panel()
		"demolish":
			_demolish_selected_building()


func _demolish_selected_building() -> void:
	var building := _selected_building
	if building == null or not is_instance_valid(building) or not building.can_demolish():
		return
	if _selection_manager != null and _selection_manager.has_method("clear_selection"):
		_selection_manager.clear_selection()
	building.demolish(_resource_manager)


func _update_special_action_affordability() -> void:
	if _special_action_buttons.is_empty():
		return
	for action_id in _special_action_buttons.keys():
		var button: Button = _special_action_buttons[action_id]
		if button == null or not is_instance_valid(button):
			continue
		button.text = _special_action_label(action_id)
		button.tooltip_text = _special_action_tooltip(action_id)
		if action_id == "build_gate":
			var cost := BuildingDatabase.get_cost("gate")
			var affordable := _resource_manager == null or _resource_manager.can_afford(cost)
			button.disabled = not affordable
			button.modulate = Color(1, 1, 1, 1) if affordable else Color(0.55, 0.55, 0.55, 0.85)
		else:
			button.disabled = false
			button.modulate = Color.WHITE


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
	if building.building_type_id == "gate" and building.building_state == Building.BuildingState.ACTIVE:
		if building.is_gate_locked():
			parts.append("Bloqueada")
		elif building.is_gate_open():
			parts.append("Abierta")
		else:
			parts.append("Cerrada")
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
		var unit_name: String = def.get("name", item_id)

		var slot := Control.new()
		slot.custom_minimum_size = ACTION_SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var button := Button.new()
		button.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.clip_contents = true
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_style_dialog_button(button, true)
		button.add_theme_font_size_override("font_size", 13)
		button.text = unit_name
		button.set_meta("unit_name", unit_name)
		button.set_meta("item_id", item_id)
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
		slot.add_child(button)
		_apply_production_tooltip(
			button,
			{"can_produce": true, "missing_resources": false, "missing_population": false}
		)
		_production_items_box.add_child(slot)
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


func _get_production_output_count() -> int:
	if _run_boon_manager != null:
		return _run_boon_manager.get_production_output_count()
	return 1


func _get_production_availability(item_id: String) -> Dictionary:
	if _production_manager == null or _selected_building == null:
		return {"can_produce": true, "missing_resources": false, "missing_population": false, "other_block": ""}
	return _production_manager.get_production_availability(
		_selected_building,
		item_id,
		_get_production_output_count()
	)


func _format_production_cost_line(cost: Dictionary, include_villager: bool, show_have: bool) -> String:
	var parts: PackedStringArray = []
	var wood_needed: int = cost.get("wood", 0)
	if wood_needed > 0:
		if show_have and _resource_manager != null:
			parts.append("%d/%d madera" % [_resource_manager.wood, wood_needed])
		else:
			parts.append("%d madera" % wood_needed)
	var gold_needed: int = cost.get("gold", 0)
	if gold_needed > 0:
		if show_have and _resource_manager != null:
			parts.append("%d/%d oro" % [_resource_manager.gold, gold_needed])
		else:
			parts.append("%d oro" % gold_needed)
	var food_needed: int = cost.get("food", 0)
	if food_needed > 0:
		if show_have and _resource_manager != null:
			parts.append("%d/%d comida" % [_resource_manager.food, food_needed])
		else:
			parts.append("%d comida" % food_needed)
	if include_villager:
		parts.append("1 aldeano")
	return " · ".join(parts) if not parts.is_empty() else "Gratis"


func _format_production_tooltip(item_id: String, availability: Dictionary) -> String:
	var def := EquipmentDatabase.get_definition(item_id)
	if def.is_empty():
		return ""
	var unit_name: String = def.get("name", item_id)
	var cost: Dictionary = def.get("cost", {})
	var consumes_villager := not str(def.get("transforms_to", "")).is_empty()
	var missing_resources: bool = availability.get("missing_resources", false)
	var show_have: bool = missing_resources and not bool(availability.get("can_produce", true))
	var cost_line := _format_production_cost_line(cost, consumes_villager, show_have)
	var train_time: float = def.get("train_time", 0.0)
	var details := cost_line
	if train_time > 0.0:
		details += " · %.0f s" % train_time
	if _has_production_double():
		details += " · genera 2 unidades"

	var lines: PackedStringArray = ["%s\n%s" % [unit_name, details]]
	var block_subtitle := _format_production_block_subtitle(availability)
	if not block_subtitle.is_empty():
		lines.append(block_subtitle)
	if availability.get("missing_population", false) and _population_manager != null:
		var output_count := _get_production_output_count()
		var free_slots := maxi(
			0,
			_population_manager.population_cap
			- _population_manager.population
			- _population_manager.reserved_population
		)
	return "\n".join(lines)


func _apply_production_tooltip(button: Button, availability: Dictionary, override_text: String = "") -> void:
	if not override_text.is_empty():
		button.tooltip_text = override_text
		return
	var item_id: String = button.get_meta("item_id", "")
	button.tooltip_text = _format_production_tooltip(item_id, availability)


func _format_production_block_subtitle(availability: Dictionary) -> String:
	if availability.get("missing_resources", false) and availability.get("missing_population", false):
		return "Sin recursos y falta alojamiento"
	if availability.get("missing_resources", false):
		return "Sin recursos"
	if availability.get("missing_population", false):
		return "Falta alojamiento"
	return ""


func _build_production_button_text(unit_name: String, availability: Dictionary, queued_count: int) -> String:
	var subtitle := ""
	if not availability.get("can_produce", true):
		subtitle = _format_production_block_subtitle(availability)
	elif _has_production_double():
		subtitle = "x2"
	elif queued_count > 0:
		subtitle = "(x%d)" % queued_count
	if subtitle.is_empty():
		return unit_name
	return "%s\n%s" % [unit_name, subtitle]


func _apply_production_button_style(button: Button, can_produce: bool) -> void:
	var normal: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	if normal == null:
		return
	if can_produce:
		normal.border_color = COL_BORDER_DIM
		normal.bg_color = COL_BTN
	else:
		normal.border_color = Color(0.25, 0.22, 0.18, 1.0)
		normal.bg_color = COL_BTN_DISABLED


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
		var unit_name: String = button.get_meta("unit_name", def.get("name", item_id))
		var availability := _get_production_availability(item_id)
		var can_produce: bool = availability.get("can_produce", true)

		_apply_production_button_style(button, can_produce)
		button.text = _build_production_button_text(unit_name, availability, queued_count)

		if can_produce and double_active:
			button.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
		elif can_produce:
			button.add_theme_color_override("font_color", COL_CREAM)
		else:
			button.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45, 1.0))

		_apply_production_tooltip(button, availability)

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
		var item_id: String = button.get_meta("item_id", "")
		var availability := _get_production_availability(item_id)
		var cost_tooltip := _format_production_tooltip(item_id, availability)
		if not cost_tooltip.is_empty():
			_apply_production_tooltip(button, availability, "%s\n%s" % [cost_tooltip, status_tooltip])
		else:
			_apply_production_tooltip(button, availability, status_tooltip)
		return
	var item_id: String = button.get_meta("item_id", "")
	_apply_production_tooltip(button, _get_production_availability(item_id))


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
	var availability := _get_production_availability(item_id)
	if not availability.get("can_produce", true):
		var reason := _production_manager.get_enqueue_block_reason(
			_selected_building,
			item_id,
			_get_production_output_count()
		)
		if reason.is_empty():
			reason = "No se puede producir ahora"
		_production_feedback_text = reason
		_production_feedback_timer = 3.5
		_update_production_status_labels()
		return
	if _production_manager.enqueue(_selected_building, item_id):
		_production_feedback_text = ""
		_production_feedback_timer = 0.0
		_update_production_status_labels()
		return
	var reason := _production_manager.get_enqueue_block_reason(
		_selected_building,
		item_id,
		_get_production_output_count()
	)
	if reason.is_empty():
		reason = "No se puede producir ahora"
	_production_feedback_text = reason
	_production_feedback_timer = 3.5
	_update_production_status_labels()


func _show_selection_mode() -> void:
	if _build_mode != null:
		_build_mode.visible = false
	if _selection_mode != null:
		_selection_mode.visible = true
		_selection_mode.clip_contents = false
	var center_area := _selection_mode.get_parent() if _selection_mode != null else null
	if center_area is Control:
		(center_area as Control).clip_contents = false


func _show_build_mode() -> void:
	if _build_mode != null:
		_build_mode.visible = true
	if _selection_mode != null:
		_selection_mode.visible = false
	var center_area := _selection_mode.get_parent() if _selection_mode != null else null
	if center_area is Control:
		(center_area as Control).clip_contents = true
	if _building_info_panel != null:
		_building_info_panel.visible = false
	if _unit_selection_scroll != null:
		_unit_selection_scroll.visible = false
	if _actions_panel != null:
		_actions_panel.visible = false
	_set_production_status_message("")


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
	_update_special_action_affordability()


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
