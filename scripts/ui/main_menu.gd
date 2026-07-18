extends Control

const GAME_SCENE := "res://scenes/main.tscn"

enum Screen { TITLE, SETUP, UPGRADES }

# Palette aligned with in-game wood / gold UI
const COL_SKY_TOP := Color(0.06, 0.08, 0.14, 1.0)
const COL_SKY_MID := Color(0.12, 0.16, 0.14, 1.0)
const COL_SKY_BOT := Color(0.18, 0.22, 0.12, 1.0)
const COL_PANEL := Color(0.09, 0.07, 0.055, 0.94)
const COL_PANEL_INNER := Color(0.12, 0.1, 0.075, 0.9)
const COL_BORDER := Color(0.72, 0.58, 0.32, 1.0)
const COL_BORDER_DIM := Color(0.42, 0.35, 0.24, 1.0)
const COL_GOLD := Color(1.0, 0.9, 0.55, 1.0)
const COL_GOLD_SOFT := Color(0.92, 0.82, 0.52, 1.0)
const COL_CREAM := Color(0.9, 0.86, 0.74, 1.0)
const COL_MUTED := Color(0.72, 0.68, 0.58, 1.0)
const COL_BTN := Color(0.14, 0.11, 0.08, 0.95)
const COL_BTN_HOVER := Color(0.22, 0.17, 0.1, 0.98)
const COL_BTN_PRESSED := Color(0.1, 0.08, 0.05, 1.0)
const COL_BTN_DISABLED := Color(0.08, 0.07, 0.06, 0.85)

var _screen: Screen = Screen.TITLE
var _title_screen: Control
var _setup_screen: Control
var _upgrades_screen: Control
var _title_label: Label
var _cta_label: Label
var _fragments_label: Label
var _shop_list: VBoxContainer
var _difficulty_button: Button
var _difficulty_hint: Label
var _cta_pulse_t: float = 0.0


func _ready() -> void:
	_build_atmosphere()
	_build_title_screen()
	_build_setup_screen()
	_build_upgrades_screen()
	_show_screen(Screen.TITLE)

	if not MetaProgression.fragments_changed.is_connected(_on_fragments_changed):
		MetaProgression.fragments_changed.connect(_on_fragments_changed)
	if not MetaProgression.unlocks_changed.is_connected(_refresh_shop):
		MetaProgression.unlocks_changed.connect(_refresh_shop)

	call_deferred("_play_title_intro")


func _process(delta: float) -> void:
	if _screen != Screen.TITLE or _cta_label == null:
		return
	_cta_pulse_t += delta
	var a := 0.55 + 0.45 * (0.5 + 0.5 * sin(_cta_pulse_t * 2.4))
	_cta_label.modulate.a = a


func _unhandled_input(event: InputEvent) -> void:
	if _screen != Screen.TITLE:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_on_play_pressed()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Atmosphere
# ---------------------------------------------------------------------------

func _build_atmosphere() -> void:
	var sky := ColorRect.new()
	sky.name = "SkyTop"
	sky.color = COL_SKY_TOP
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	move_child(sky, 0)

	var mid := ColorRect.new()
	mid.name = "SkyMid"
	mid.color = COL_SKY_MID
	mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	mid.anchor_top = 0.35
	mid.offset_top = 0.0
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mid)
	move_child(mid, 1)

	var ground := ColorRect.new()
	ground.name = "GroundBand"
	ground.color = COL_SKY_BOT
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.anchor_top = 0.62
	ground.offset_top = 0.0
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)
	move_child(ground, 2)

	# Soft vignette via dark side fades
	var left_fade := ColorRect.new()
	left_fade.color = Color(0, 0, 0, 0.35)
	left_fade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_fade.anchor_right = 0.18
	left_fade.offset_right = 0.0
	left_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_fade)

	var right_fade := ColorRect.new()
	right_fade.color = Color(0, 0, 0, 0.35)
	right_fade.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_fade.anchor_left = 0.82
	right_fade.offset_left = 0.0
	right_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right_fade)

	var bottom_fade := ColorRect.new()
	bottom_fade.color = Color(0, 0, 0, 0.45)
	bottom_fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_fade.anchor_top = 0.78
	bottom_fade.offset_top = 0.0
	bottom_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_fade)

	# Horizon gold line
	var horizon := ColorRect.new()
	horizon.color = Color(0.75, 0.55, 0.25, 0.35)
	horizon.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	horizon.anchor_top = 0.62
	horizon.anchor_bottom = 0.62
	horizon.offset_top = -1.0
	horizon.offset_bottom = 1.0
	horizon.anchor_left = 0.15
	horizon.anchor_right = 0.85
	horizon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(horizon)

	# Soft “moon” glow
	var moon := ColorRect.new()
	moon.color = Color(0.85, 0.88, 0.75, 0.12)
	moon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	moon.offset_left = -140.0
	moon.offset_right = -60.0
	moon.offset_top = 48.0
	moon.offset_bottom = 128.0
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(moon)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 18:
		var star := ColorRect.new()
		var bright := rng.randf_range(0.25, 0.7)
		star.color = Color(0.9, 0.88, 0.75, bright)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sz := rng.randi_range(1, 2)
		star.custom_minimum_size = Vector2(sz, sz)
		star.set_anchors_preset(Control.PRESET_TOP_LEFT)
		star.anchor_left = rng.randf_range(0.05, 0.95)
		star.anchor_right = star.anchor_left
		star.anchor_top = rng.randf_range(0.04, 0.48)
		star.anchor_bottom = star.anchor_top
		star.offset_left = 0.0
		star.offset_top = 0.0
		star.offset_right = float(sz)
		star.offset_bottom = float(sz)
		add_child(star)


# ---------------------------------------------------------------------------
# Title screen
# ---------------------------------------------------------------------------

func _build_title_screen() -> void:
	_title_screen = Control.new()
	_title_screen.name = "TitleScreen"
	_title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_screen.gui_input.connect(_on_title_gui_input)
	add_child(_title_screen)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var eyebrow := Label.new()
	eyebrow.text = "SOBREVIVE · CONSTRUYE · RESISTE"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", COL_MUTED)
	vbox.add_child(eyebrow)

	_title_label = Label.new()
	_title_label.text = "gameX"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_font_size_override("font_size", 96)
	_title_label.add_theme_color_override("font_color", COL_GOLD)
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_title_label.add_theme_constant_override("shadow_offset_x", 3)
	_title_label.add_theme_constant_override("shadow_offset_y", 4)
	vbox.add_child(_title_label)

	var rule := _make_gold_rule(280.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rule)

	var tagline := Label.new()
	tagline.text = "Sobrevive 5 noches en tu asentamiento."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tagline.add_theme_font_size_override("font_size", 16)
	tagline.add_theme_color_override("font_color", COL_CREAM)
	vbox.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	var play_btn := _make_primary_button("Jugar", Vector2(260, 52))
	play_btn.pressed.connect(_on_play_pressed)
	vbox.add_child(play_btn)

	_cta_label = Label.new()
	_cta_label.text = "o pulsa cualquier tecla"
	_cta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cta_label.add_theme_font_size_override("font_size", 12)
	_cta_label.add_theme_color_override("font_color", COL_MUTED)
	vbox.add_child(_cta_label)


func _play_title_intro() -> void:
	if _title_label == null:
		return
	_title_label.modulate.a = 0.0
	await get_tree().process_frame
	_title_label.pivot_offset = _title_label.size * 0.5
	_title_label.scale = Vector2(0.92, 0.92)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_title_label, "modulate:a", 1.0, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(_title_label, "scale", Vector2.ONE, 0.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Setup screen (map / difficulty / upgrades)
# ---------------------------------------------------------------------------

func _build_setup_screen() -> void:
	_setup_screen = Control.new()
	_setup_screen.name = "SetupScreen"
	_setup_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_screen.visible = false
	add_child(_setup_screen)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_screen.add_child(center)

	var panel := _make_panel(Vector2(520, 0))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var brand := Label.new()
	brand.text = "gameX"
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_font_size_override("font_size", 28)
	brand.add_theme_color_override("font_color", COL_GOLD)
	brand.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	brand.add_theme_constant_override("shadow_offset_x", 1)
	brand.add_theme_constant_override("shadow_offset_y", 2)
	header.add_child(brand)

	_fragments_label = Label.new()
	_fragments_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fragments_label.add_theme_font_size_override("font_size", 14)
	_fragments_label.add_theme_color_override("font_color", COL_GOLD_SOFT)
	header.add_child(_fragments_label)

	var subtitle := Label.new()
	subtitle.text = "Prepara tu campaña"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", COL_MUTED)
	vbox.add_child(subtitle)

	vbox.add_child(_make_gold_rule(0.0))

	var map_title := _make_section_label("Tamaño del mapa")
	vbox.add_child(map_title)

	var map_row := VBoxContainer.new()
	map_row.add_theme_constant_override("separation", 8)
	vbox.add_child(map_row)

	map_row.add_child(_make_map_choice_button(
		"Grande", "64×64", "Mapa amplio. Más recursos, más peligro.", _on_large_pressed
	))
	map_row.add_child(_make_map_choice_button(
		"Mediano", "32×32", "Equilibrio recomendado.", _on_medium_pressed
	))
	map_row.add_child(_make_map_choice_button(
		"Pequeño", "16×16", "Partidas rápidas y cerradas.", _on_small_pressed
	))

	var opts_title := _make_section_label("Opciones")
	vbox.add_child(opts_title)

	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 10)
	vbox.add_child(opts)

	_difficulty_button = _make_secondary_button("Dificultad: Normal", Vector2(0, 44))
	_difficulty_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty_button.pressed.connect(_on_difficulty_pressed)
	opts.add_child(_difficulty_button)

	var upgrades_btn := _make_secondary_button("Mejoras", Vector2(140, 44))
	upgrades_btn.pressed.connect(_on_upgrades_pressed)
	opts.add_child(upgrades_btn)

	_difficulty_hint = Label.new()
	_difficulty_hint.text = ""
	_difficulty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_hint.add_theme_font_size_override("font_size", 11)
	_difficulty_hint.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4, 0.9))
	vbox.add_child(_difficulty_hint)

	var back := _make_ghost_button("← Volver")
	back.pressed.connect(_on_back_to_title)
	vbox.add_child(back)

	_refresh_fragments_label()


# ---------------------------------------------------------------------------
# Upgrades / meta shop
# ---------------------------------------------------------------------------

func _build_upgrades_screen() -> void:
	_upgrades_screen = Control.new()
	_upgrades_screen.name = "UpgradesScreen"
	_upgrades_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_upgrades_screen.visible = false
	add_child(_upgrades_screen)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_upgrades_dim_input)
	_upgrades_screen.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_upgrades_screen.add_child(center)

	var panel := _make_panel(Vector2(560, 520))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Progreso permanente"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_GOLD)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Gasta fragmentos en ventajas que persisten entre partidas."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_MUTED)
	vbox.add_child(hint)

	var frags := Label.new()
	frags.name = "ShopFragments"
	frags.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	frags.add_theme_font_size_override("font_size", 15)
	frags.add_theme_color_override("font_color", COL_GOLD_SOFT)
	vbox.add_child(frags)

	vbox.add_child(_make_gold_rule(0.0))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_shop_list = VBoxContainer.new()
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_shop_list)

	var back := _make_secondary_button("Volver", Vector2(0, 40))
	back.pressed.connect(_on_back_to_setup)
	vbox.add_child(back)

	_refresh_shop()


# ---------------------------------------------------------------------------
# Screen flow
# ---------------------------------------------------------------------------

func _show_screen(screen: Screen) -> void:
	_screen = screen
	_title_screen.visible = screen == Screen.TITLE
	_setup_screen.visible = screen == Screen.SETUP
	_upgrades_screen.visible = screen == Screen.UPGRADES
	if screen == Screen.SETUP:
		_refresh_fragments_label()
		_difficulty_hint.text = ""
	if screen == Screen.UPGRADES:
		_refresh_shop()


func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_play_pressed()


func _on_play_pressed() -> void:
	_show_screen(Screen.SETUP)


func _on_back_to_title() -> void:
	_show_screen(Screen.TITLE)


func _on_upgrades_pressed() -> void:
	_show_screen(Screen.UPGRADES)


func _on_back_to_setup() -> void:
	_show_screen(Screen.SETUP)


func _on_upgrades_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_back_to_setup()


func _on_difficulty_pressed() -> void:
	_difficulty_hint.text = "Próximamente — la dificultad aún no está disponible."


func _on_large_pressed() -> void:
	_start_game(GameSettings.MapSizePreset.LARGE)


func _on_medium_pressed() -> void:
	_start_game(GameSettings.MapSizePreset.MEDIUM)


func _on_small_pressed() -> void:
	_start_game(GameSettings.MapSizePreset.SMALL)


func _start_game(preset: GameSettingsData.MapSizePreset) -> void:
	GameSettings.map_size_preset = preset
	get_tree().change_scene_to_file(GAME_SCENE)


# ---------------------------------------------------------------------------
# Meta shop data
# ---------------------------------------------------------------------------

func _on_fragments_changed(_amount: int) -> void:
	_refresh_fragments_label()
	_refresh_shop()


func _refresh_fragments_label() -> void:
	if _fragments_label != null:
		_fragments_label.text = "%d fragmentos" % MetaProgression.fragments
	if _upgrades_screen != null:
		var shop_frags := _upgrades_screen.find_child("ShopFragments", true, false) as Label
		if shop_frags != null:
			shop_frags.text = "Fragmentos: %d" % MetaProgression.fragments


func _refresh_shop() -> void:
	_refresh_fragments_label()
	if _shop_list == null:
		return
	for child in _shop_list.get_children():
		child.queue_free()

	for unlock_id in MetaProgression.UNLOCKS.keys():
		var def: Dictionary = MetaProgression.UNLOCKS[unlock_id]
		var unlocked := MetaProgression.is_unlocked(unlock_id)
		var can_buy := MetaProgression.can_purchase(unlock_id)

		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_stylebox_override("panel", _make_inner_row_style())
		_shop_list.add_child(row)

		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 10)
		pad.add_theme_constant_override("margin_right", 10)
		pad.add_theme_constant_override("margin_top", 8)
		pad.add_theme_constant_override("margin_bottom", 8)
		row.add_child(pad)

		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		pad.add_child(h)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		h.add_child(info)

		var name_lbl := Label.new()
		name_lbl.text = "%s  ·  %d" % [def.get("name", unlock_id), def.get("cost", 0)]
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", COL_CREAM if not unlocked else COL_MUTED)
		info.add_child(name_lbl)

		var desc := Label.new()
		desc.text = str(def.get("description", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", Color(0.65, 0.62, 0.52, 1.0))
		info.add_child(desc)

		var button := Button.new()
		button.custom_minimum_size = Vector2(100, 36)
		button.focus_mode = Control.FOCUS_NONE
		if unlocked:
			button.text = "Comprado"
			button.disabled = true
		else:
			button.text = "Comprar"
			button.disabled = not can_buy
			button.pressed.connect(_on_purchase_pressed.bind(str(unlock_id)))
		_style_button(button, unlocked or not can_buy)
		h.add_child(button)


func _on_purchase_pressed(unlock_id: String) -> void:
	MetaProgression.purchase(unlock_id)
	_refresh_shop()


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _make_panel(min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.border_color = COL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_inner_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL_INNER
	style.border_color = COL_BORDER_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


func _make_gold_rule(width: float) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(0.72, 0.58, 0.32, 0.55)
	rule.custom_minimum_size = Vector2(width, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width <= 0.0 else Control.SIZE_SHRINK_CENTER
	return rule


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.75, 0.68, 0.48, 1.0))
	return label


func _make_primary_button(text: String, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, false, true)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", COL_GOLD)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7, 1.0))
	button.add_theme_color_override("font_pressed_color", COL_CREAM)
	return button


func _make_secondary_button(text: String, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, false, false)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COL_CREAM)
	return button


func _make_ghost_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", COL_MUTED)
	button.add_theme_color_override("font_hover_color", COL_GOLD_SOFT)
	return button


func _make_map_choice_button(title: String, size_label: String, subtitle: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 58)
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	_style_button(button, false, false)
	button.pressed.connect(on_pressed)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	button.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 2)
	row.add_child(texts)

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override("separation", 8)
	texts.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", COL_GOLD_SOFT)
	title_row.add_child(title_lbl)

	var size_lbl := Label.new()
	size_lbl.text = size_label
	size_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_lbl.add_theme_font_size_override("font_size", 12)
	size_lbl.add_theme_color_override("font_color", COL_MUTED)
	title_row.add_child(size_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.62, 0.52, 1.0))
	texts.add_child(sub_lbl)

	var play_hint := Label.new()
	play_hint.text = "▶"
	play_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	play_hint.add_theme_font_size_override("font_size", 14)
	play_hint.add_theme_color_override("font_color", COL_BORDER)
	row.add_child(play_hint)

	return button


func _style_button(button: Button, disabled_look: bool = false, primary: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.14, 0.08, 0.95) if primary else COL_BTN
	normal.border_color = COL_BORDER if primary else COL_BORDER_DIM
	normal.set_border_width_all(2 if primary else 1)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)

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
	button.add_theme_stylebox_override("focus", normal)

	if disabled_look:
		button.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45, 1.0))
		button.add_theme_color_override("font_disabled_color", Color(0.5, 0.48, 0.42, 1.0))
