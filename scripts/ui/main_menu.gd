extends Control

const GAME_SCENE := "res://scenes/main.tscn"

@onready var _vbox: VBoxContainer = $CenterContainer/VBoxContainer
@onready var _subtitle: Label = $CenterContainer/VBoxContainer/SubtitleLabel
@onready var _large_button: Button = $CenterContainer/VBoxContainer/LargeButton
@onready var _medium_button: Button = $CenterContainer/VBoxContainer/MediumButton
@onready var _small_button: Button = $CenterContainer/VBoxContainer/SmallButton

var _fragments_label: Label
var _shop_box: VBoxContainer
var _meta_built: bool = false


func _ready() -> void:
	_ensure_meta_ui()
	_refresh_meta_ui()
	if not MetaProgression.fragments_changed.is_connected(_on_fragments_changed):
		MetaProgression.fragments_changed.connect(_on_fragments_changed)
	if not MetaProgression.unlocks_changed.is_connected(_refresh_meta_ui):
		MetaProgression.unlocks_changed.connect(_refresh_meta_ui)


func _on_large_pressed() -> void:
	_start_game(GameSettings.MapSizePreset.LARGE)


func _on_medium_pressed() -> void:
	_start_game(GameSettings.MapSizePreset.MEDIUM)


func _on_small_pressed() -> void:
	_start_game(GameSettings.MapSizePreset.SMALL)


func _start_game(preset: GameSettingsData.MapSizePreset) -> void:
	GameSettings.map_size_preset = preset
	get_tree().change_scene_to_file(GAME_SCENE)


func _ensure_meta_ui() -> void:
	if _meta_built:
		return
	_meta_built = true

	if _subtitle != null:
		_subtitle.text = "Sobrevive 5 noches. Gasta fragmentos en ventajas permanentes."

	_fragments_label = Label.new()
	_fragments_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fragments_label.add_theme_font_size_override("font_size", 14)
	_fragments_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	_vbox.add_child(_fragments_label)
	_vbox.move_child(_fragments_label, _subtitle.get_index() + 1)

	var shop_title := Label.new()
	shop_title.text = "Progreso permanente"
	shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_title.add_theme_font_size_override("font_size", 16)
	shop_title.add_theme_color_override("font_color", Color(0.85, 0.88, 0.8))
	_vbox.add_child(shop_title)
	_vbox.move_child(shop_title, _fragments_label.get_index() + 1)

	_shop_box = VBoxContainer.new()
	_shop_box.add_theme_constant_override("separation", 6)
	_vbox.add_child(_shop_box)
	_vbox.move_child(_shop_box, shop_title.get_index() + 1)

	# Keep map-size buttons at the bottom.
	_vbox.move_child(_large_button, _vbox.get_child_count() - 1)
	_vbox.move_child(_medium_button, _vbox.get_child_count() - 1)
	_vbox.move_child(_small_button, _vbox.get_child_count() - 1)


func _on_fragments_changed(_amount: int) -> void:
	_refresh_meta_ui()


func _refresh_meta_ui() -> void:
	_ensure_meta_ui()
	if _fragments_label != null:
		_fragments_label.text = "Fragmentos: %d" % MetaProgression.fragments
	if _shop_box == null:
		return
	for child in _shop_box.get_children():
		child.queue_free()
	for unlock_id in MetaProgression.UNLOCKS.keys():
		var def: Dictionary = MetaProgression.UNLOCKS[unlock_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(220, 0)
		info.add_theme_font_size_override("font_size", 11)
		info.text = "%s (%d)\n%s" % [
			def.get("name", unlock_id),
			def.get("cost", 0),
			def.get("description", ""),
		]
		row.add_child(info)

		var button := Button.new()
		button.custom_minimum_size = Vector2(96, 0)
		if MetaProgression.is_unlocked(unlock_id):
			button.text = "Comprado"
			button.disabled = true
		else:
			button.text = "Comprar"
			button.disabled = not MetaProgression.can_purchase(unlock_id)
			button.pressed.connect(_on_purchase_pressed.bind(str(unlock_id)))
		row.add_child(button)
		_shop_box.add_child(row)


func _on_purchase_pressed(unlock_id: String) -> void:
	MetaProgression.purchase(unlock_id)
	_refresh_meta_ui()
