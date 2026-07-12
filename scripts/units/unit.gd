class_name Unit
extends CharacterBody2D

@export var move_speed: float = 95.0
@export var max_hp: int = 100
@export var selection_half_size := Vector2(40.0, 40.0)
@export var idle_sheet: Texture2D
@export var walk_up_sheet: Texture2D
@export var walk_down_sheet: Texture2D
@export var sprite_offset := Vector2(0.0, -36.0)

var hp: int
var is_selected: bool = false

var _ground_layer: TinyTilesMap
var _was_on_water := false
var _last_grass_cell := Vector2i(999999, 999999)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var selection_indicator: Polygon2D = $SelectionIndicator
@onready var shadow_sprite: Sprite2D = $Shadow
@onready var dust_particles: GPUParticles2D = $DustParticles


func _ready() -> void:
	hp = max_hp
	add_to_group("selectable_units")
	add_to_group("units")
	_setup_sprite_frames()
	_setup_shadow()
	animated_sprite.offset = sprite_offset
	await get_tree().physics_frame
	_setup_navigation_agent()


func set_ground_layer(ground_layer: TinyTilesMap) -> void:
	_ground_layer = ground_layer


func _setup_sprite_frames() -> void:
	var frames := SpriteSheetUtils.build_character_frames(
		idle_sheet,
		walk_up_sheet,
		walk_down_sheet
	)
	if frames.get_animation_names().is_empty():
		return
	animated_sprite.sprite_frames = frames
	animated_sprite.play(&"idle")


func _setup_shadow() -> void:
	var image := Image.create(64, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 64:
			var dx := (x - 32.0) / 32.0
			var dy := (y - 12.0) / 12.0
			var dist := dx * dx + dy * dy
			if dist <= 1.0:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.35 * (1.0 - dist)))
	var texture := ImageTexture.create_from_image(image)
	shadow_sprite.texture = texture
	shadow_sprite.position = Vector2.ZERO
	shadow_sprite.y_sort_enabled = false


func _setup_navigation_agent() -> void:
	navigation_agent.path_desired_distance = 6.0
	navigation_agent.target_desired_distance = 6.0
	navigation_agent.max_speed = move_speed
	navigation_agent.avoidance_enabled = false
	navigation_agent.target_position = global_position


func select() -> void:
	is_selected = true
	selection_indicator.visible = true


func deselect() -> void:
	is_selected = false
	selection_indicator.visible = false


func get_sprite_center() -> Vector2:
	return global_position + sprite_offset


func get_selection_rect() -> Rect2:
	return Rect2(get_sprite_center() - selection_half_size, selection_half_size * 2.0)


func contains_world_point(world_point: Vector2) -> bool:
	return get_selection_rect().has_point(world_point)


func intersects_world_rect(world_rect: Rect2) -> bool:
	return world_rect.intersects(get_selection_rect(), true)


func move_to(target: Vector2) -> void:
	navigation_agent.target_position = target


func _physics_process(delta: float) -> void:
	if navigation_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		_set_dust(false)
		_play_idle()
		_update_terrain_feedback(delta)
		return

	var next_position := navigation_agent.get_next_path_position()
	var direction := global_position.direction_to(next_position)

	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		_set_dust(false)
		return

	velocity = direction * move_speed
	move_and_slide()
	_play_walk_animation(direction)
	_set_dust(true)
	_update_terrain_feedback(delta)


func _play_idle() -> void:
	if animated_sprite.animation != &"idle" and animated_sprite.sprite_frames.has_animation(&"idle"):
		animated_sprite.play(&"idle")


func _play_walk_animation(direction: Vector2) -> void:
	var animation_name := &"walk_down"
	if direction.y < -0.15:
		animation_name = &"walk_up"
	elif direction.y > 0.15:
		animation_name = &"walk_down"
	elif direction.x < 0.0:
		animation_name = &"walk_up" if animated_sprite.sprite_frames.has_animation(&"walk_up") else &"walk_down"
	else:
		animation_name = &"walk_down"

	if not animated_sprite.sprite_frames.has_animation(animation_name):
		animation_name = &"idle"

	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)


func _set_dust(active: bool) -> void:
	if dust_particles == null:
		return
	dust_particles.emitting = active and (_ground_layer == null or not _ground_layer.is_water_at(global_position))
	if active and _ground_layer != null and not _ground_layer.is_water_at(global_position):
		dust_particles.modulate = Color(0.72, 0.58, 0.38, 0.75)


func _update_terrain_feedback(_delta: float) -> void:
	if _ground_layer == null:
		return

	var on_water := _ground_layer.is_water_at(global_position)
	if on_water and not _was_on_water:
		_spawn_splash()
	_was_on_water = on_water

	var current_cell := _ground_layer.get_cell_at_world(global_position)
	if current_cell != _last_grass_cell:
		if _last_grass_cell != Vector2i(999999, 999999):
			_ground_layer.release_grass_at_cell(_last_grass_cell)
		_last_grass_cell = current_cell
		if not on_water:
			_ground_layer.press_grass_at(global_position)


func _exit_tree() -> void:
	if _ground_layer != null and _last_grass_cell != Vector2i(999999, 999999):
		_ground_layer.release_grass_at_cell(_last_grass_cell)


func _spawn_splash() -> void:
	if dust_particles == null:
		return
	dust_particles.restart()
	dust_particles.modulate = Color(0.55, 0.78, 1.0, 0.85)
