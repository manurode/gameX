extends PanelContainer

const BUILD_ORDER: Array[String] = [
	"house_small", "house_big", "mill", "stable",
	"tower", "wall", "castle_small", "castle_big",
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
const TEX_STONE := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_resources_stone.png"
const TEX_WHEAT := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_resources_wheat.png"
const TEX_HAMMER := "res://assets/tilesets/tiny_tiles/UI/Icons/UI_icon_hammer.png"

const ICON_VARIANT_SIZE := 128
const SLOT_SIZE := Vector2(78, 78)
const MIN_FORMATION_UNITS := 2

@onready var _resources_box: VBoxContainer = $MarginContainer/HBoxContainer/ResourcesBox
@onready var _build_tab_icon: TextureRect = $MarginContainer/HBoxContainer/CommandArea/TabColumn/BuildTabIcon
@onready var _build_grid: GridContainer = $MarginContainer/HBoxContainer/CommandArea/BuildGrid
@onready var _formation_grid: GridContainer = $MarginContainer/HBoxContainer/CommandArea/FormationGrid
@onready var _status_label: Label = $MarginContainer/HBoxContainer/CommandArea/StatusColumn/StatusLabel

var _resource_manager: ResourceManager
var _build_manager: Node
var _selection_manager: Node
var _resource_labels: Dictionary = {}
var _build_slots: Dictionary = {}
var _formation_slots: Dictionary = {}
var _active_build_type: String = ""
var _formation_mode: bool = false
var _selected_unit_count: int = 0


func _ready() -> void:
	if _build_tab_icon != null:
		_build_tab_icon.texture = _make_icon_atlas(TEX_HAMMER)
	_show_build_panel()


func setup(resource_manager: ResourceManager, build_manager: Node, selection_manager: Node = null) -> void:
	_resource_manager = resource_manager
	_build_manager = build_manager
	_selection_manager = selection_manager
	_build_resource_rows()
	_build_command_grid()
	_build_formation_grid()
	if _resource_manager != null:
		_resource_manager.resources_changed.connect(_on_resources_changed)
		_on_resources_changed(_resource_manager.wood, _resource_manager.stone, _resource_manager.wheat)
	if _build_manager != null and _build_manager.has_signal("build_mode_changed"):
		_build_manager.build_mode_changed.connect(_on_build_mode_changed)
	if _selection_manager != null:
		if _selection_manager.has_signal("selection_changed"):
			_selection_manager.selection_changed.connect(_on_selection_changed)
		if _selection_manager.has_signal("formation_changed"):
			_selection_manager.formation_changed.connect(_on_formation_changed)
		_on_selection_changed(_selection_manager.selected_units)
	_update_status(false, "")


func _build_resource_rows() -> void:
	var entries: Array[Dictionary] = [
		{"key": "wood", "texture": TEX_WOOD, "label": "Madera"},
		{"key": "stone", "texture": TEX_STONE, "label": "Piedra"},
		{"key": "wheat", "texture": TEX_WHEAT, "label": "Trigo"},
	]
	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _make_icon_atlas(entry.texture)
		row.add_child(icon)

		var amount := Label.new()
		amount.text = "0"
		amount.add_theme_font_size_override("font_size", 18)
		amount.add_theme_color_override("font_color", Color(0.95, 0.88, 0.55))
		amount.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		amount.add_theme_constant_override("shadow_offset_x", 1)
		amount.add_theme_constant_override("shadow_offset_y", 1)
		row.add_child(amount)

		_resources_box.add_child(row)
		_resource_labels[entry.key] = amount


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
	content.add_theme_constant_override("margin_left", 4)
	content.add_theme_constant_override("margin_top", 2)
	content.add_theme_constant_override("margin_right", 4)
	content.add_theme_constant_override("margin_bottom", 2)
	button.add_child(content)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(vbox)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 40)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _get_building_icon(type_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = def.get("name", type_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var hotkey_label := Label.new()
	hotkey_label.text = str(hotkey)
	hotkey_label.add_theme_font_size_override("font_size", 11)
	hotkey_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	hotkey_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hotkey_label.position = Vector2(4, 2)
	hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(hotkey_label)

	var cost := BuildingDatabase.get_cost(type_id)
	button.tooltip_text = _format_cost_tooltip(def.get("name", type_id), cost)
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
	content.add_theme_constant_override("margin_left", 4)
	content.add_theme_constant_override("margin_top", 2)
	content.add_theme_constant_override("margin_right", 4)
	content.add_theme_constant_override("margin_bottom", 2)
	button.add_child(content)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(vbox)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _create_formation_icon(formation)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = info.get("name", "")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var hotkey_label := Label.new()
	hotkey_label.text = str(hotkey)
	hotkey_label.add_theme_font_size_override("font_size", 11)
	hotkey_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	hotkey_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hotkey_label.position = Vector2(4, 2)
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
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
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
	if def.get("procedural", false):
		return _create_wall_icon()
	var texture_path: String = def.get("texture", "")
	if texture_path.is_empty():
		return null
	return load(texture_path)


func _create_wall_icon() -> Texture2D:
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var noise := sin(float(x) * 0.35) * 0.08 + cos(float(y) * 0.5) * 0.06
			var base := 0.42 + noise
			if y < 3 or y > 28:
				base *= 0.75
			image.set_pixel(x, y, Color(base * 0.55, base * 0.52, base * 0.48, 1.0))
	return ImageTexture.create_from_image(image)


func _make_icon_atlas(texture_path: String, variant_index: int = 0) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(texture_path)
	atlas.region = Rect2(variant_index * ICON_VARIANT_SIZE, 0, ICON_VARIANT_SIZE, ICON_VARIANT_SIZE)
	return atlas


func _format_cost_tooltip(name: String, cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	if cost.get("wood", 0) > 0:
		parts.append("%d madera" % cost.wood)
	if cost.get("stone", 0) > 0:
		parts.append("%d piedra" % cost.stone)
	if cost.get("wheat", 0) > 0:
		parts.append("%d trigo" % cost.wheat)
	if parts.is_empty():
		return name
	return "%s\n%s" % [name, " · ".join(parts)]


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


func _on_resources_changed(wood: int, stone: int, wheat: int) -> void:
	if _resource_labels.has("wood"):
		_resource_labels.wood.text = str(wood)
	if _resource_labels.has("stone"):
		_resource_labels.stone.text = str(stone)
	if _resource_labels.has("wheat"):
		_resource_labels.wheat.text = str(wheat)
	_refresh_affordability()


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
	_update_formation_status()


func _show_build_panel() -> void:
	_formation_mode = false
	if _build_grid != null:
		_build_grid.visible = true
	if _formation_grid != null:
		_formation_grid.visible = false
	if _build_tab_icon != null:
		_build_tab_icon.texture = _make_icon_atlas(TEX_HAMMER)
	if _active_build_type.is_empty():
		_update_status(false, "")


func _show_formation_panel() -> void:
	_formation_mode = true
	if _build_grid != null:
		_build_grid.visible = false
	if _formation_grid != null:
		_formation_grid.visible = true
	if _build_tab_icon != null:
		_build_tab_icon.texture = _create_formation_tab_icon()
	_update_formation_status()
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
	if not _formation_mode:
		_update_status(active, type_id)


func _update_status(active: bool, type_id: String) -> void:
	if _status_label == null:
		return
	if not active:
		_status_label.text = "Construcción"
		return
	var def := BuildingDatabase.get_definition(type_id)
	_status_label.text = def.get("name", type_id)


func _update_formation_status() -> void:
	if _status_label == null or _selection_manager == null:
		return
	var info: Dictionary = FORMATION_INFO.get(_selection_manager.move_formation, {})
	var subtitle: String = info.get("subtitle", "Formaciones")
	_status_label.text = "%s (%d)" % [subtitle, _selected_unit_count]
