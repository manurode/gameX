class_name Unit
extends CharacterBody2D

@export var move_speed: float = 120.0
@export var max_hp: int = 100
@export var selection_radius: float = 8.0
@export var unit_texture: Texture2D

var hp: int
var is_selected: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var selection_indicator: Polygon2D = $SelectionIndicator

func _ready() -> void:
	hp = max_hp
	add_to_group("selectable_units")
	add_to_group("units")
	_apply_unit_texture()
	await get_tree().physics_frame
	_setup_navigation_agent()

func _apply_unit_texture() -> void:
	if unit_texture == null:
		return

	var sprite_frames := animated_sprite.sprite_frames
	if sprite_frames == null:
		return

	animated_sprite.sprite_frames = sprite_frames.duplicate(true)
	sprite_frames = animated_sprite.sprite_frames

	for animation_name in sprite_frames.get_animation_names():
		var duration := sprite_frames.get_frame_duration(animation_name, 0)
		sprite_frames.set_frame(animation_name, 0, unit_texture, duration)

func _setup_navigation_agent() -> void:
	navigation_agent.path_desired_distance = 4.0
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.max_speed = move_speed
	navigation_agent.avoidance_enabled = false
	navigation_agent.target_position = global_position

func select() -> void:
	is_selected = true
	selection_indicator.visible = true

func deselect() -> void:
	is_selected = false
	selection_indicator.visible = false

func get_selection_rect() -> Rect2:
	var half_size := Vector2(selection_radius, selection_radius)
	return Rect2(global_position - half_size, half_size * 2.0)

func contains_world_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= selection_radius

func intersects_world_rect(world_rect: Rect2) -> bool:
	return world_rect.intersects(get_selection_rect(), true)

func move_to(target: Vector2) -> void:
	navigation_agent.target_position = target

func _physics_process(_delta: float) -> void:
	if navigation_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		if animated_sprite.animation != &"idle":
			animated_sprite.play(&"idle")
		return

	var next_position := navigation_agent.get_next_path_position()
	var direction := global_position.direction_to(next_position)

	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		return

	velocity = direction * move_speed
	move_and_slide()
	_play_walk_animation(direction)

func _play_walk_animation(direction: Vector2) -> void:
	var animation_name := &"walk_down"
	if absf(direction.x) > absf(direction.y):
		animation_name = &"walk_right" if direction.x > 0.0 else &"walk_left"
	elif direction.y < 0.0:
		animation_name = &"walk_up"

	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)
