extends CanvasLayer

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## HUD was authored for this SubViewport size; grow chrome via font/metrics
## (not Control.scale) so text stays sharp on larger buffers.
const HUD_DESIGN_SIZE := Vector2(1280.0, 720.0)

@onready var help_label: Label = $TopLeft/MarginContainer/CyclePanel/VBoxContainer/HelpLabel
@onready var cycle_button: Button = $TopLeft/MarginContainer/CyclePanel/VBoxContainer/CycleButton
@onready var cycle_panel: PanelContainer = $TopLeft/MarginContainer/CyclePanel
@onready var _top_left: Control = $TopLeft
@onready var _selection_box: Control = $SelectionBox

var game_hub: PanelContainer
var minimap: Control
var _build_manager: Node
var _day_night_manager: DayNightManager
var _game_state_manager: GameStateManager
var _run_boon_manager: RunBoonManager
var _night_wave_manager: NightWaveManager

var _event_banner: PanelContainer
var _event_banner_label: Label
var _banner_timer: float = 0.0
var _boon_overlay: Control
var _boon_buttons_box: VBoxContainer
var _debug_boon_overlay: Control
var _debug_boon_list: VBoxContainer
var _debug_day_overlay: Control
var _debug_day_grid: GridContainer
var _end_overlay: Control
var _end_title: Label
var _end_body: Label
var _foresight_panel: PanelContainer
var _foresight_label: Label
var _foresight_hint: Label
var _last_cycle_ui_seconds := -1
var _ui_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_hub_nodes()
	_style_cycle_panel()
	_create_event_banner()
	_create_boon_overlay()
	_create_debug_boon_overlay()
	_create_debug_day_overlay()
	_create_end_overlay()
	_create_foresight_label()
	get_viewport().size_changed.connect(_apply_hud_scale)
	call_deferred("_apply_hud_scale")


func _apply_hud_scale() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x < 2.0 or vp_size.y < 2.0:
		return
	_ui_scale = clampf(
		minf(vp_size.x / HUD_DESIGN_SIZE.x, vp_size.y / HUD_DESIGN_SIZE.y),
		1.0,
		2.75
	)
	# Never use Control.scale for chrome: it upscales glyph atlases and blurs text.
	# Resize fonts/metrics instead so glyphs rasterize at the final pixel size.
	if _top_left != null:
		_top_left.scale = Vector2.ONE
	if _selection_box != null:
		_selection_box.scale = Vector2.ONE
	if _event_banner != null:
		_event_banner.scale = Vector2.ONE
	if _foresight_panel != null:
		_foresight_panel.scale = Vector2.ONE
	_reset_overlay_panel_scale(_boon_overlay)
	_reset_overlay_panel_scale(_debug_boon_overlay)
	_reset_overlay_panel_scale(_debug_day_overlay)
	_reset_overlay_panel_scale(_end_overlay)
	_apply_chrome_metrics()


func _reset_overlay_panel_scale(overlay: Control) -> void:
	if overlay == null or overlay.get_child_count() < 2:
		return
	var panel := overlay.get_child(1) as Control
	if panel != null:
		panel.scale = Vector2.ONE


func _fs(base: int) -> int:
	return maxi(1, int(round(float(base) * _ui_scale)))


func _px(base: float) -> float:
	return base * _ui_scale


func _apply_chrome_metrics() -> void:
	if _top_left != null:
		_top_left.offset_right = _px(720.0)
		_top_left.offset_bottom = _px(110.0)
		var top_margin := _top_left.get_node_or_null("MarginContainer") as MarginContainer
		if top_margin != null:
			top_margin.add_theme_constant_override("margin_left", _fs(16))
			top_margin.add_theme_constant_override("margin_top", _fs(12))
		if cycle_button != null:
			cycle_button.custom_minimum_size = Vector2(_px(180.0), 0.0)
			cycle_button.add_theme_font_size_override("font_size", _fs(15))
		if help_label != null:
			help_label.add_theme_font_size_override("font_size", _fs(13))
		if cycle_panel != null:
			cycle_panel.add_theme_stylebox_override("panel", _make_info_panel_style())

	if _event_banner != null:
		_event_banner.offset_left = -_px(280.0)
		_event_banner.offset_right = _px(280.0)
		_event_banner.offset_top = _px(72.0)
		_event_banner.offset_bottom = _px(128.0)
		var banner_style := StyleBoxFlat.new()
		banner_style.bg_color = Color(0.08, 0.06, 0.05, 0.92)
		banner_style.border_color = Color(0.85, 0.55, 0.25, 1.0)
		banner_style.set_border_width_all(maxi(1, _fs(2)))
		banner_style.set_corner_radius_all(_fs(6))
		banner_style.set_content_margin_all(_fs(10))
		_event_banner.add_theme_stylebox_override("panel", banner_style)
	if _event_banner_label != null:
		_event_banner_label.add_theme_font_size_override("font_size", _fs(17))

	if _foresight_panel != null:
		_foresight_panel.offset_left = -_px(12.0)
		_foresight_panel.offset_top = _px(10.0)
		_foresight_panel.offset_right = -_px(12.0)
		_foresight_panel.offset_bottom = _px(10.0)
		_foresight_panel.add_theme_stylebox_override("panel", _make_info_panel_style())
	if _foresight_label != null:
		_foresight_label.add_theme_font_size_override("font_size", _fs(14))
	if _foresight_hint != null:
		_foresight_hint.add_theme_font_size_override("font_size", _fs(13))

	_apply_centered_panel_metrics(_boon_overlay, 220.0, 160.0, 16, [
		{"path": [0, 0], "size": 20},
		{"path": [0, 1], "size": 12},
	])
	_apply_centered_panel_metrics(_debug_boon_overlay, 280.0, 240.0, 14, [
		{"path": [0, 0, 0], "size": 18},
		{"path": [0, 1], "size": 11},
	])
	_apply_centered_panel_metrics(_debug_day_overlay, 260.0, 220.0, 14, [
		{"path": [0, 0, 0], "size": 18},
		{"path": [0, 1], "size": 11},
	])
	_apply_centered_panel_metrics(_end_overlay, 240.0, 140.0, 18, [])
	if _end_title != null:
		_end_title.add_theme_font_size_override("font_size", _fs(28))
	if _end_body != null:
		_end_body.add_theme_font_size_override("font_size", _fs(14))


func _apply_centered_panel_metrics(
	overlay: Control,
	half_w: float,
	half_h: float,
	content_margin: int,
	font_nodes: Array
) -> void:
	if overlay == null or overlay.get_child_count() < 2:
		return
	var panel := overlay.get_child(1) as Control
	if panel == null:
		return
	panel.offset_left = -_px(half_w)
	panel.offset_right = _px(half_w)
	panel.offset_top = -_px(half_h)
	panel.offset_bottom = _px(half_h)
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		var scaled := style.duplicate() as StyleBoxFlat
		scaled.set_border_width_all(maxi(1, _fs(2)))
		scaled.set_corner_radius_all(_fs(8))
		scaled.set_content_margin_all(_fs(content_margin))
		panel.add_theme_stylebox_override("panel", scaled)
	for entry in font_nodes:
		var node: Node = panel
		var ok := true
		for idx in entry["path"]:
			if node == null or idx >= node.get_child_count():
				ok = false
				break
			node = node.get_child(idx)
		if ok and node is Label:
			(node as Label).add_theme_font_size_override("font_size", _fs(int(entry["size"])))


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_F10:
			_toggle_debug_boon_menu()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_F11:
			_toggle_debug_day_menu()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_ESCAPE:
			if _debug_day_overlay != null and _debug_day_overlay.visible:
				_set_debug_day_menu_visible(false)
				get_viewport().set_input_as_handled()
			elif _debug_boon_overlay != null and _debug_boon_overlay.visible:
				_set_debug_boon_menu_visible(false)
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0 and _event_banner != null:
			_event_banner.visible = false


func _resolve_hub_nodes() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	game_hub = main.get_node_or_null("Layout/HubMargin/GameHub") as PanelContainer
	if game_hub == null:
		game_hub = main.get_node_or_null("Layout/GameHub") as PanelContainer
	if game_hub != null:
		minimap = game_hub.get_node_or_null("MarginContainer/HBoxContainer/RightColumn/Minimap")
	if minimap == null and game_hub != null:
		minimap = game_hub.get_node_or_null("MarginContainer/HBoxContainer/CommandArea/RightColumn/Minimap")
	if minimap == null and game_hub != null:
		minimap = game_hub.get_node_or_null("MarginContainer/HBoxContainer/CommandArea/Minimap")


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
	ground: TinyTilesMap = null,
	run_boon_manager: RunBoonManager = null,
	game_state_manager: GameStateManager = null,
	night_wave_manager: NightWaveManager = null,
	market_manager: MarketManager = null
) -> void:
	_build_manager = build_manager
	_day_night_manager = day_night_manager
	_run_boon_manager = run_boon_manager
	_game_state_manager = game_state_manager
	_night_wave_manager = night_wave_manager
	_resolve_hub_nodes()

	if game_hub != null and game_hub.has_method("setup"):
		game_hub.setup(
			resource_manager,
			build_manager,
			selection_manager,
			population_manager,
			production_manager,
			curfew_manager,
			run_boon_manager,
			market_manager
		)
	if minimap != null and minimap.has_method("setup") and camera != null and ground != null:
		minimap.setup(camera, ground)
	if _build_manager != null and _build_manager.has_signal("build_mode_changed"):
		_build_manager.build_mode_changed.connect(_on_build_mode_changed)

	if _day_night_manager != null:
		_day_night_manager.cycle_changed.connect(_on_cycle_changed)
		_day_night_manager.phase_time_changed.connect(_on_phase_time_changed)
		_update_cycle_ui(_day_night_manager.current_phase)
		_update_help_for_cycle()

	if _night_wave_manager != null:
		_night_wave_manager.wave_warning.connect(_on_wave_warning)
		_night_wave_manager.wave_started.connect(_on_wave_started)
		if _night_wave_manager.has_signal("foresight_ready"):
			_night_wave_manager.foresight_ready.connect(_on_foresight_ready)
		if _night_wave_manager.has_method("refresh_foresight"):
			_night_wave_manager.refresh_foresight()

	if _run_boon_manager != null:
		_run_boon_manager.boon_choices_ready.connect(_on_boon_choices_ready)
		_run_boon_manager.boon_applied.connect(_on_boon_applied)

	if _game_state_manager != null:
		_game_state_manager.run_ended.connect(_on_run_ended)
		if not _game_state_manager.game_over.is_connected(_on_game_over_legacy):
			_game_state_manager.game_over.connect(_on_game_over_legacy)


func _make_info_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.055, 0.94)
	style.border_color = Color(0.72, 0.58, 0.32, 1.0)
	style.set_border_width_all(maxi(1, _fs(2)))
	style.set_corner_radius_all(_fs(8))
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = _fs(8)
	style.shadow_offset = Vector2(0, _px(3.0))
	style.set_content_margin_all(_fs(8))
	return style


func _style_cycle_panel() -> void:
	if cycle_panel != null:
		cycle_panel.add_theme_stylebox_override("panel", _make_info_panel_style())
		cycle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cycle_button == null:
		return
	cycle_button.disabled = true
	cycle_button.flat = true
	cycle_button.focus_mode = Control.FOCUS_NONE
	cycle_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cycle_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var empty := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		cycle_button.add_theme_stylebox_override(style_name, empty)
	cycle_button.add_theme_font_size_override("font_size", 15)
	cycle_button.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	cycle_button.add_theme_color_override("font_disabled_color", Color(0.9, 0.86, 0.74))
	cycle_button.add_theme_color_override("font_hover_color", Color(0.9, 0.86, 0.74))
	cycle_button.add_theme_color_override("font_pressed_color", Color(0.9, 0.86, 0.74))
	if help_label != null:
		help_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.64))
		help_label.add_theme_font_size_override("font_size", 13)


func _create_event_banner() -> void:
	_event_banner = PanelContainer.new()
	_event_banner.visible = false
	_event_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_event_banner.offset_left = -280.0
	_event_banner.offset_right = 280.0
	_event_banner.offset_top = 72.0
	_event_banner.offset_bottom = 128.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.05, 0.92)
	style.border_color = Color(0.85, 0.55, 0.25, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_event_banner.add_theme_stylebox_override("panel", style)
	_event_banner_label = Label.new()
	_event_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_banner_label.add_theme_font_size_override("font_size", 17)
	_event_banner_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	_event_banner.add_child(_event_banner_label)
	add_child(_event_banner)


func _create_foresight_label() -> void:
	_foresight_panel = PanelContainer.new()
	_foresight_panel.visible = false
	_foresight_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foresight_panel.anchor_left = 1.0
	_foresight_panel.anchor_top = 0.0
	_foresight_panel.anchor_right = 1.0
	_foresight_panel.anchor_bottom = 0.0
	_foresight_panel.offset_left = -12.0
	_foresight_panel.offset_top = 10.0
	_foresight_panel.offset_right = -12.0
	_foresight_panel.offset_bottom = 10.0
	_foresight_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_foresight_panel.grow_vertical = Control.GROW_DIRECTION_END

	_foresight_panel.add_theme_stylebox_override("panel", _make_info_panel_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	_foresight_panel.add_child(vbox)

	_foresight_label = Label.new()
	_foresight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_foresight_label.add_theme_font_size_override("font_size", 14)
	_foresight_label.add_theme_color_override("font_color", Color(0.9, 0.86, 0.74))
	_foresight_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foresight_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	vbox.add_child(_foresight_label)

	_foresight_hint = Label.new()
	_foresight_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_foresight_hint.add_theme_font_size_override("font_size", 13)
	_foresight_hint.add_theme_color_override("font_color", Color(0.78, 0.74, 0.64))
	_foresight_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foresight_hint.size_flags_horizontal = Control.SIZE_SHRINK_END
	vbox.add_child(_foresight_hint)

	add_child(_foresight_panel)
	_foresight_panel.resized.connect(_update_foresight_pivot)
	_update_foresight_pivot()


func _update_foresight_pivot() -> void:
	if _foresight_panel == null:
		return
	_foresight_panel.pivot_offset = Vector2(_foresight_panel.size.x, 0.0)


func _create_boon_overlay() -> void:
	_boon_overlay = Control.new()
	_boon_overlay.visible = false
	_boon_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_boon_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boon_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_boon_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220.0
	panel.offset_right = 220.0
	panel.offset_top = -160.0
	panel.offset_bottom = 160.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.07, 0.96)
	style.border_color = Color(0.75, 0.65, 0.35, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	_boon_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Bendición del amanecer"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Elige una recompensa para esta partida"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
	vbox.add_child(subtitle)

	_boon_buttons_box = VBoxContainer.new()
	_boon_buttons_box.add_theme_constant_override("separation", 8)
	vbox.add_child(_boon_buttons_box)
	add_child(_boon_overlay)


func _create_debug_boon_overlay() -> void:
	_debug_boon_overlay = Control.new()
	_debug_boon_overlay.visible = false
	_debug_boon_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_debug_boon_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_boon_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_boon_overlay.z_index = 20

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_boon_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280.0
	panel.offset_right = 280.0
	panel.offset_top = -240.0
	panel.offset_bottom = 240.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.12, 0.97)
	style.border_color = Color(0.35, 0.75, 0.85, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	_debug_boon_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "DEBUG — Bendiciones"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "Cerrar (Esc)"
	close_button.pressed.connect(_set_debug_boon_menu_visible.bind(false))
	header.add_child(close_button)

	var hint := Label.new()
	hint.text = "F8 para abrir/cerrar · click para aplicar al instante"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.65, 0.75, 0.8))
	vbox.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_debug_boon_list = VBoxContainer.new()
	_debug_boon_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_boon_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_debug_boon_list)

	add_child(_debug_boon_overlay)


func _toggle_debug_boon_menu() -> void:
	if _debug_boon_overlay == null:
		return
	_set_debug_boon_menu_visible(not _debug_boon_overlay.visible)


func _set_debug_boon_menu_visible(visible: bool) -> void:
	if _debug_boon_overlay == null:
		return
	if visible:
		_set_debug_day_menu_visible(false)
		_rebuild_debug_boon_list()
	_debug_boon_overlay.visible = visible


func _rebuild_debug_boon_list() -> void:
	if _debug_boon_list == null:
		return
	for child in _debug_boon_list.get_children():
		child.queue_free()
	if _run_boon_manager == null:
		var empty := Label.new()
		empty.text = "RunBoonManager no disponible"
		_debug_boon_list.add_child(empty)
		return
	for boon_id in _run_boon_manager.get_all_boon_ids():
		var def := _run_boon_manager.get_boon_def(boon_id)
		var button := Button.new()
		button.text = "%s\n%s" % [def.get("name", boon_id), def.get("description", "")]
		button.custom_minimum_size = Vector2(0, 48)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "id: %s" % boon_id
		button.pressed.connect(_on_debug_boon_pressed.bind(boon_id))
		_debug_boon_list.add_child(button)


func _on_debug_boon_pressed(boon_id: String) -> void:
	if _run_boon_manager == null:
		return
	if _run_boon_manager.debug_apply_boon(boon_id):
		_set_debug_boon_menu_visible(false)


func _create_debug_day_overlay() -> void:
	_debug_day_overlay = Control.new()
	_debug_day_overlay.visible = false
	_debug_day_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_debug_day_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_day_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_day_overlay.z_index = 20

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_day_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260.0
	panel.offset_right = 260.0
	panel.offset_top = -220.0
	panel.offset_bottom = 220.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.12, 0.97)
	style.border_color = Color(0.85, 0.7, 0.35, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	_debug_day_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "DEBUG — Día"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "Cerrar (Esc)"
	close_button.pressed.connect(_set_debug_day_menu_visible.bind(false))
	header.add_child(close_button)

	var hint := Label.new()
	hint.text = "F11 para abrir/cerrar · salta al inicio del día elegido"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.65, 0.75, 0.8))
	vbox.add_child(hint)

	_debug_day_grid = GridContainer.new()
	_debug_day_grid.columns = 5
	_debug_day_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_day_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_debug_day_grid.add_theme_constant_override("h_separation", 8)
	_debug_day_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(_debug_day_grid)

	add_child(_debug_day_overlay)


func _toggle_debug_day_menu() -> void:
	if _debug_day_overlay == null:
		return
	_set_debug_day_menu_visible(not _debug_day_overlay.visible)


func _set_debug_day_menu_visible(visible: bool) -> void:
	if _debug_day_overlay == null:
		return
	if visible:
		_set_debug_boon_menu_visible(false)
		_rebuild_debug_day_grid()
	_debug_day_overlay.visible = visible


func _rebuild_debug_day_grid() -> void:
	if _debug_day_grid == null:
		return
	for child in _debug_day_grid.get_children():
		child.queue_free()
	if _day_night_manager == null:
		var empty := Label.new()
		empty.text = "DayNightManager no disponible"
		_debug_day_grid.add_child(empty)
		return
	var current_day := _day_night_manager.cycle_number
	for day in range(1, BalanceConfig.WIN_NIGHTS + 1):
		var button := Button.new()
		button.text = "Día %d" % day
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if day == current_day:
			button.text = "Día %d ★" % day
			button.tooltip_text = "Día actual"
		else:
			button.tooltip_text = "Saltar al inicio del día %d" % day
		button.pressed.connect(_on_debug_day_pressed.bind(day))
		_debug_day_grid.add_child(button)


func _on_debug_day_pressed(day: int) -> void:
	if _day_night_manager == null:
		return
	_day_night_manager.debug_set_day(day)
	if _boon_overlay != null:
		_boon_overlay.visible = false
	_set_debug_day_menu_visible(false)
	_show_banner("DEBUG: Día %d" % day, 2.5)


func _create_end_overlay() -> void:
	_end_overlay = Control.new()
	_end_overlay.visible = false
	_end_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240.0
	panel.offset_right = 240.0
	panel.offset_top = -140.0
	panel.offset_bottom = 140.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.97)
	style.border_color = Color(0.7, 0.55, 0.3, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	_end_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_end_title)

	_end_body = Label.new()
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_body.add_theme_font_size_override("font_size", 14)
	_end_body.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	vbox.add_child(_end_body)

	var menu_button := Button.new()
	menu_button.text = "Volver al menú"
	menu_button.custom_minimum_size = Vector2(0, 36)
	menu_button.pressed.connect(_on_return_to_menu)
	vbox.add_child(menu_button)
	add_child(_end_overlay)


func _show_banner(text: String, duration: float = 5.0) -> void:
	if _event_banner == null or _event_banner_label == null:
		return
	_event_banner_label.text = text
	_event_banner.visible = true
	_banner_timer = duration


func _on_game_over_legacy() -> void:
	pass


func _on_run_ended(won: bool, nights_survived: int, fragments_earned: int) -> void:
	if _boon_overlay != null:
		_boon_overlay.visible = false
	if _debug_boon_overlay != null:
		_debug_boon_overlay.visible = false
	if _debug_day_overlay != null:
		_debug_day_overlay.visible = false
	if _end_overlay == null:
		return
	_ensure_paused_input_chain()
	_end_overlay.visible = true
	if won:
		_end_title.text = "VICTORIA"
		_end_title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
		_end_body.text = (
			"Has sobrevivido %d noches.\n"
			+ "Recompensa: +%d fragmentos (total %d)."
		) % [nights_survived, fragments_earned, MetaProgression.fragments]
	else:
		_end_title.text = "DERROTA"
		_end_title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		_end_body.text = (
			"El Centro Urbano ha caído tras %d noche(s).\n"
			+ "Recompensa: +%d fragmentos (total %d)."
		) % [nights_survived, fragments_earned, MetaProgression.fragments]
	if help_label != null:
		help_label.text = "Partida terminada"


func _ensure_paused_input_chain() -> void:
	# SubViewportContainer stops forwarding mouse input while the tree is paused
	# unless the viewport chain itself uses PROCESS_MODE_ALWAYS.
	var node: Node = self
	while node != null:
		node.process_mode = Node.PROCESS_MODE_ALWAYS
		node = node.get_parent()
	# Keep the simulation frozen: do not inherit ALWAYS from the SubViewport.
	var viewport := get_parent()
	if viewport != null:
		var game_world := viewport.get_node_or_null("GameWorld")
		if game_world != null:
			game_world.process_mode = Node.PROCESS_MODE_PAUSABLE


func _on_return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


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
	_update_cycle_ui(phase, true)
	if phase != DayNightManager.CyclePhase.DAY and _foresight_panel != null:
		_foresight_panel.visible = false
	if (
		phase == DayNightManager.CyclePhase.DUSK
		and _run_boon_manager != null
		and _run_boon_manager.should_keep_daylight()
	):
		_show_banner("Equinoccio de verano — sin oscuridad ni enemigos", 4.5)
	if _build_manager != null and _build_manager.build_mode_active:
		return
	_update_help_for_cycle()


func _update_cycle_ui(phase: DayNightManager.CyclePhase, force: bool = false) -> void:
	if cycle_button == null or _day_night_manager == null:
		return
	var seconds := ceili(_day_night_manager.seconds_remaining)
	if not force and seconds == _last_cycle_ui_seconds:
		return
	_last_cycle_ui_seconds = seconds
	var icon := "☾" if phase == DayNightManager.CyclePhase.NIGHT else "☀"
	var nights_left := maxi(0, BalanceConfig.WIN_NIGHTS - _day_night_manager.nights_survived)
	cycle_button.text = "%s Día %d · %s %02d:%02d · %d/%d noches" % [
		icon,
		_day_night_manager.cycle_number,
		_day_night_manager.get_phase_display_name(),
		seconds / 60,
		seconds % 60,
		_day_night_manager.nights_survived,
		BalanceConfig.WIN_NIGHTS,
	]
	cycle_button.tooltip_text = (
		"Defiende el Centro Urbano.\nQuedan %d noche(s) para la victoria"
		% nights_left
	)
	if cycle_panel != null:
		cycle_panel.tooltip_text = cycle_button.tooltip_text


func _on_phase_time_changed(_seconds_remaining: float) -> void:
	if _day_night_manager != null:
		_update_cycle_ui(_day_night_manager.current_phase, false)


func _on_wave_warning(direction_name: String, modifier_id: int = 0, modifier_name: String = "") -> void:
	var mod_text := modifier_name
	if mod_text.is_empty():
		mod_text = NightModifier.get_display_name(modifier_id as NightModifier.Id)
	var description := NightModifier.get_description(modifier_id as NightModifier.Id)
	_show_banner(
		"CUERNO — %s por el %s\n%s" % [mod_text, direction_name, description],
		6.0
	)
	if help_label != null:
		help_label.set_deferred(
			"text",
			"ATARDECER — %s desde el %s. Prepara defensas." % [mod_text, direction_name]
		)


func _on_wave_started(enemy_count: int, _modifier_id: int = 0) -> void:
	if help_label != null:
		help_label.set_deferred(
			"text",
			"NOCHE — %d enemigos atacan. Protege el Centro Urbano." % enemy_count
		)


func _on_foresight_ready(
	modifier_id: int,
	modifier_name: String,
	direction_name: String = "",
	enemy_count: int = 0
) -> void:
	if _foresight_panel == null or _foresight_label == null:
		return
	var direction_text := direction_name if not direction_name.is_empty() else "?"
	var count_text := ("%d enemigos" % enemy_count) if enemy_count > 0 else "? enemigos"
	var description := NightModifier.get_description(modifier_id as NightModifier.Id)
	_foresight_label.text = "Presagio · %s\n%s · %s" % [modifier_name, direction_text, count_text]
	if _foresight_hint != null:
		_foresight_hint.text = description
		_foresight_hint.visible = not description.is_empty()
	_foresight_panel.tooltip_text = description
	_foresight_panel.visible = true
	_foresight_panel.reset_size()


func _on_boon_choices_ready(choices: Array) -> void:
	if _boon_overlay == null or _boon_buttons_box == null:
		return
	for child in _boon_buttons_box.get_children():
		child.queue_free()
	for choice in choices:
		var boon_id := str(choice)
		var def := {}
		if _run_boon_manager != null:
			def = _run_boon_manager.get_boon_def(boon_id)
		var button := Button.new()
		button.text = "%s\n%s" % [def.get("name", boon_id), def.get("description", "")]
		button.custom_minimum_size = Vector2(0, 52)
		button.pressed.connect(_on_boon_button_pressed.bind(boon_id))
		_boon_buttons_box.add_child(button)
	_boon_overlay.visible = true


func _on_boon_button_pressed(boon_id: String) -> void:
	if _run_boon_manager != null:
		_run_boon_manager.select_boon(boon_id)


func _on_boon_applied(boon_id: String) -> void:
	if _boon_overlay != null:
		_boon_overlay.visible = false
	var def := {}
	if _run_boon_manager != null:
		def = _run_boon_manager.get_boon_def(boon_id)
	_show_banner("Bendición: %s" % def.get("name", boon_id), 3.5)


func _update_help_for_cycle() -> void:
	if help_label == null or _day_night_manager == null:
		return
	match _day_night_manager.current_phase:
		DayNightManager.CyclePhase.NIGHT:
			if (
				_run_boon_manager != null
				and _run_boon_manager.should_keep_daylight()
			):
				help_label.text = "EQUINOCCIO — Día eterno. Puedes seguir construyendo."
			else:
				help_label.text = "NOCHE — Protege el Centro Urbano. Si cae, pierdes."
		DayNightManager.CyclePhase.DUSK:
			if (
				_run_boon_manager != null
				and _run_boon_manager.should_keep_daylight()
			):
				help_label.text = "EQUINOCCIO — Sin oscuridad ni enemigos esta noche."
			else:
				help_label.text = "ATARDECER — Últimos segundos para preparar defensas."
		DayNightManager.CyclePhase.DAWN:
			help_label.text = "AMANECER — Elige una bendición y reorganiza la base."
		_:
			help_label.text = (
				"Defiende el Centro Urbano  |  Sobrevive %d noches"
				% BalanceConfig.WIN_NIGHTS
			)
