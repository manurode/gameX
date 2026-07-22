extends Node2D

signal spawn_mode_changed(active: bool, type_id: String)

var spawn_mode_active: bool = false
var selected_unit_type: String = "knight"
var spawn_valid: bool = false

## Debug spawn hotkeys (F1–F9) stay inert until Ctrl+Shift+M unlocks them.
var _spawn_hotkeys_unlocked: bool = false

var _ghost_sprite: Sprite2D
var _ground_layer: TinyTilesMap
var _units_container: Node2D
var _build_manager: Node


func setup(
	ground_layer: TinyTilesMap,
	units_container: Node2D,
	build_manager: Node = null
) -> void:
	_ground_layer = ground_layer
	_units_container = units_container
	_build_manager = build_manager
	_create_ghost()


func cancel_spawn_mode() -> void:
	if spawn_mode_active:
		_cancel_spawn_mode()


func _create_ghost() -> void:
	_ghost_sprite = Sprite2D.new()
	_ghost_sprite.centered = true
	_ghost_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ghost_sprite.modulate = Color(0.55, 0.85, 1.0, 0.6)
	_ghost_sprite.visible = false
	_ghost_sprite.z_index = 50
	add_child(_ghost_sprite)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE and spawn_mode_active:
			_cancel_spawn_mode()
			get_viewport().set_input_as_handled()
			return
		if OS.is_debug_build() and _is_spawn_hotkey_unlock(key_event):
			_spawn_hotkeys_unlocked = true
			get_viewport().set_input_as_handled()
			return
		if (
			OS.is_debug_build()
			and _spawn_hotkeys_unlocked
			and key_event.keycode in UnitDatabase.SPAWN_HOTKEYS
		):
			var type_id: String = UnitDatabase.SPAWN_HOTKEYS[key_event.keycode]
			if type_id == "enemy":
				_spawn_debug_enemy_at_cursor()
			else:
				_start_spawn_mode(type_id)
			get_viewport().set_input_as_handled()
			return

	if not spawn_mode_active:
		return

	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_try_spawn_unit(_screen_to_world(mouse_event.position))
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_spawn_mode()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not spawn_mode_active:
		_ghost_sprite.visible = false
		return

	var world_pos := _screen_to_world(get_viewport().get_mouse_position())
	_ghost_sprite.global_position = world_pos
	spawn_valid = _is_valid_spawn(world_pos)
	_ghost_sprite.modulate = Color(0.55, 0.85, 1.0, 0.65) if spawn_valid else Color(0.95, 0.35, 0.35, 0.55)
	_ghost_sprite.visible = true


func _start_spawn_mode(type_id: String) -> void:
	if _build_manager != null and _build_manager.has_method("cancel_build_mode"):
		_build_manager.call("cancel_build_mode")

	selected_unit_type = type_id
	spawn_mode_active = true
	_update_ghost_texture()
	spawn_mode_changed.emit(true, type_id)


func _cancel_spawn_mode() -> void:
	spawn_mode_active = false
	_ghost_sprite.visible = false
	spawn_mode_changed.emit(false, "")


func _update_ghost_texture() -> void:
	var def := UnitDatabase.get_definition(selected_unit_type)
	var preview_path: String = def.get("preview", "")
	if preview_path.is_empty():
		return
	var texture: Texture2D = load(preview_path)
	if texture == null:
		return
	# Preview sheets are horizontal strips — show only the first 80×80 frame.
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(0, 0, mini(80, texture.get_width()), mini(80, texture.get_height()))
	_ghost_sprite.texture = atlas
	_ghost_sprite.offset = Vector2(0.0, -36.0)


func _is_spawn_hotkey_unlock(key_event: InputEventKey) -> bool:
	return (
		key_event.keycode == KEY_M
		and key_event.ctrl_pressed
		and key_event.shift_pressed
		and not key_event.alt_pressed
		and not key_event.meta_pressed
	)


func _spawn_debug_enemy_at_cursor() -> void:
	_try_spawn_unit(_screen_to_world(get_viewport().get_mouse_position()), "enemy")


func _try_spawn_unit(world_pos: Vector2, type_id: String = "") -> void:
	if not _is_valid_spawn(world_pos):
		return

	var spawn_type := type_id if not type_id.is_empty() else selected_unit_type
	var scene := UnitDatabase.get_scene(spawn_type)
	if scene == null:
		return

	var unit: Unit = scene.instantiate()
	_units_container.add_child(unit)
	unit.global_position = world_pos
	UnitDatabase.apply_definition_to_unit(unit, spawn_type)
	var enemy_kinds := ["enemy", "ember", "mire", "hexwing"]
	if spawn_type in enemy_kinds and unit is EnemyUnit:
		var kind := "normal" if spawn_type == "enemy" else spawn_type
		(unit as EnemyUnit).configure_kind(kind)
	if _ground_layer != null:
		unit.set_ground_layer(_ground_layer)
	unit.reset_navigation()
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null and world.has_method("register_player_unit") and spawn_type not in enemy_kinds:
		world.call("register_player_unit", unit)


func _is_valid_spawn(world_pos: Vector2) -> bool:
	if _ground_layer == null:
		return false
	return not _ground_layer.is_water_at(world_pos)


func _screen_to_world(screen_point: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_point
