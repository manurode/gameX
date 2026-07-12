class_name Unit
extends CharacterBody2D

enum CombatStyle { MELEE, RANGED }
enum UnitState { IDLE, MOVING, CHASING, ATTACKING, DYING }

signal health_changed(current_hp: int, max_hp: int)
signal died

const HEALTH_BAR_VISIBLE_MS := 3000
const MELEE_DAMAGE_FRAME := 5
const RANGED_DAMAGE_FRAME := 6
const DEATH_LINGER_SECONDS := 2.8
const HIT_FLASH_DURATION := 0.14
const DEATH_FRAME_COUNT := 3

@export var move_speed: float = 95.0
@export var max_hp: int = 100
@export var selection_half_size := Vector2(40.0, 40.0)
@export var idle_sheet: Texture2D
@export var walk_up_sheet: Texture2D
@export var walk_down_sheet: Texture2D
@export var attack_up_sheet: Texture2D
@export var attack_down_sheet: Texture2D
@export var death_up_sheet: Texture2D
@export var death_down_sheet: Texture2D
@export var sprite_offset := Vector2(0.0, -36.0)
@export var combat_style: CombatStyle = CombatStyle.MELEE
@export var can_attack: bool = true
@export var attack_damage: int = 15
@export var attack_cooldown: float = 1.1
@export var melee_range: float = 52.0
@export var attack_range_min: float = 90.0
@export var attack_range_max: float = 210.0

var hp: int
var is_selected: bool = false
var attack_target: Unit = null

var _ground_layer: TinyTilesMap
var _was_on_water := false
var _unit_state: UnitState = UnitState.IDLE
var _attack_cooldown_remaining: float = 0.0
var _is_attack_animating: bool = false
var _damage_dealt_this_swing: bool = false
var _last_damage_time: int = 0
var _is_dying: bool = false
var _last_facing_direction := Vector2.DOWN
var _hit_flash_tween: Tween

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var selection_indicator: Line2D = $SelectionIndicator
@onready var shadow_sprite: Sprite2D = $Shadow
@onready var dust_particles: GPUParticles2D = $DustParticles
@onready var health_bar: Node2D = $HealthBar


func _ready() -> void:
	hp = max_hp
	add_to_group("selectable_units")
	add_to_group("units")
	_setup_sprite_frames()
	_setup_shadow()
	_setup_dust()
	_setup_selection_indicator()
	animated_sprite.offset = sprite_offset
	animated_sprite.frame_changed.connect(_on_animation_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)
	await get_tree().physics_frame
	_setup_navigation_agent()


func set_ground_layer(ground_layer: TinyTilesMap) -> void:
	_ground_layer = ground_layer


func should_show_health_bar() -> bool:
	if hp <= 0:
		return false
	if is_selected:
		return true
	return Time.get_ticks_msec() - _last_damage_time < HEALTH_BAR_VISIBLE_MS


func _setup_sprite_frames() -> void:
	var frames := SpriteSheetUtils.build_character_frames(
		idle_sheet,
		walk_up_sheet,
		walk_down_sheet,
		attack_up_sheet,
		attack_down_sheet,
		death_up_sheet,
		death_down_sheet,
		80,
		6.0,
		10.0,
		12.0,
		7.0,
		DEATH_FRAME_COUNT if death_up_sheet != null or death_down_sheet != null else -1
	)
	if frames.get_animation_names().is_empty():
		return
	animated_sprite.sprite_frames = frames
	animated_sprite.play(&"idle")


func _setup_shadow() -> void:
	var image := Image.create(48, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in 16:
		for x in 48:
			var dx := (x - 24.0) / 24.0
			var dy := (y - 8.0) / 8.0
			var dist := dx * dx + dy * dy
			if dist <= 1.0:
				var alpha := 0.3 * (1.0 - dist) * (1.0 - dist)
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	var texture := ImageTexture.create_from_image(image)
	shadow_sprite.texture = texture
	shadow_sprite.position = Vector2.ZERO
	shadow_sprite.y_sort_enabled = false
	shadow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shadow_sprite.modulate = Color(1, 1, 1, 1)


func _setup_dust() -> void:
	var size := 8
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := (size - 1) * 0.5
	for y in size:
		for x in size:
			var dist := Vector2(x - center, y - center).length() / center
			if dist <= 1.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, (1.0 - dist) * 0.9))
	dust_particles.texture = ImageTexture.create_from_image(image)
	dust_particles.position = Vector2(0, -2)
	dust_particles.y_sort_enabled = false


func _setup_selection_indicator() -> void:
	var points := PackedVector2Array()
	const SEGMENTS := 48
	const RADIUS_X := 26.0
	const RADIUS_Y := 11.0
	for i in SEGMENTS + 1:
		var angle := float(i) / float(SEGMENTS) * TAU
		points.append(Vector2(cos(angle) * RADIUS_X, sin(angle) * RADIUS_Y))
	selection_indicator.points = points
	selection_indicator.closed = true
	selection_indicator.position = Vector2.ZERO
	selection_indicator.y_sort_enabled = false


func _setup_navigation_agent() -> void:
	navigation_agent.path_desired_distance = 6.0
	navigation_agent.target_desired_distance = 6.0
	navigation_agent.max_speed = move_speed
	navigation_agent.avoidance_enabled = false
	reset_navigation()


func reset_navigation() -> void:
	navigation_agent.target_position = global_position
	velocity = Vector2.ZERO
	_unit_state = UnitState.IDLE


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
	attack_target = null
	_unit_state = UnitState.MOVING
	_is_attack_animating = false
	navigation_agent.target_desired_distance = 6.0
	navigation_agent.target_position = target


func attack_target_unit(target: Unit) -> void:
	if not can_attack or target == self or not is_instance_valid(target) or target.hp <= 0 or target._is_dying:
		move_to(target.global_position if is_instance_valid(target) else global_position)
		return

	attack_target = target
	_unit_state = UnitState.CHASING
	_is_attack_animating = false


func take_damage(amount: int, attacker: Unit = null) -> void:
	if _is_dying or hp <= 0:
		return

	hp = maxi(0, hp - amount)
	_last_damage_time = Time.get_ticks_msec()
	health_changed.emit(hp, max_hp)
	_play_hit_reaction(attacker)

	if hp <= 0:
		_die()


func _play_hit_reaction(attacker: Unit = null) -> void:
	_flash_hit()

	var world := get_parent().get_parent()
	var effect_position := get_sprite_center()
	if attacker != null and is_instance_valid(attacker) and attacker.combat_style == CombatStyle.RANGED:
		CombatEffects.spawn_ranged_impact(world, effect_position)
	else:
		CombatEffects.spawn_melee_impact(world, effect_position)


func _flash_hit() -> void:
	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()

	animated_sprite.modulate = Color(1.6, 0.45, 0.45)
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(animated_sprite, "modulate", Color.WHITE, HIT_FLASH_DURATION)


func _die() -> void:
	if _is_dying:
		return

	_is_dying = true
	attack_target = null
	_unit_state = UnitState.DYING
	_is_attack_animating = false
	velocity = Vector2.ZERO
	deselect()
	died.emit()
	_remove_from_selection()
	remove_from_group("selectable_units")
	set_collision_layer_value(2, false)
	navigation_agent.target_position = global_position

	_play_death_sequence()


func _play_death_sequence() -> void:
	var world := get_parent().get_parent()
	CombatEffects.spawn_death_burst(world, get_sprite_center())
	_play_death_animation()

	await get_tree().create_timer(DEATH_LINGER_SECONDS).timeout

	var fade_tween := create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.65)
	fade_tween.tween_property(shadow_sprite, "modulate:a", 0.0, 0.65)
	await fade_tween.finished
	queue_free()


func _play_death_animation() -> void:
	var animation_name := _get_death_animation_name()
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)
		return

	_play_procedural_death_fall()


func _get_death_animation_name() -> StringName:
	if _last_facing_direction.y < -0.15 and animated_sprite.sprite_frames.has_animation(&"death_up"):
		return &"death_up"
	if animated_sprite.sprite_frames.has_animation(&"death_down"):
		return &"death_down"
	if animated_sprite.sprite_frames.has_animation(&"death_up"):
		return &"death_up"
	return &"death_down"


func _play_procedural_death_fall() -> void:
	var fall_tween := create_tween()
	fall_tween.set_parallel(true)
	fall_tween.tween_property(animated_sprite, "rotation_degrees", 90.0, 0.5)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fall_tween.tween_property(animated_sprite, "position:y", sprite_offset.y + 20.0, 0.5)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fall_tween.tween_property(animated_sprite, "modulate", Color(0.7, 0.7, 0.7, 0.9), 0.5)


func _remove_from_selection() -> void:
	var selection_manager := get_node_or_null("/root/Main/GameWorld/SelectionManager")
	if selection_manager != null and selection_manager.has_method("remove_unit_from_selection"):
		selection_manager.remove_unit_from_selection(self)


func _physics_process(delta: float) -> void:
	if _is_dying or hp <= 0:
		return

	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)

	if attack_target != null and (not is_instance_valid(attack_target) or attack_target.hp <= 0 or attack_target._is_dying):
		attack_target = null
		_unit_state = UnitState.IDLE
		_is_attack_animating = false

	if _unit_state == UnitState.ATTACKING or _is_attack_animating:
		velocity = Vector2.ZERO
		_update_terrain_feedback(delta)
		return

	if attack_target != null:
		_process_combat(delta)
		return

	if navigation_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		_unit_state = UnitState.IDLE
		_play_idle()
		_update_terrain_feedback(delta)
		return

	if _unit_state != UnitState.MOVING:
		velocity = Vector2.ZERO
		_play_idle()
		_update_terrain_feedback(delta)
		return

	_unit_state = UnitState.MOVING
	var next_position := navigation_agent.get_next_path_position()
	var direction := global_position.direction_to(next_position)

	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		return

	velocity = direction * move_speed
	move_and_slide()
	_play_walk_animation(direction)
	_update_terrain_feedback(delta)


func _process_combat(_delta: float) -> void:
	_unit_state = UnitState.CHASING

	if _is_in_attack_range() and _attack_cooldown_remaining <= 0.0:
		_start_attack()
		return

	var standoff := _get_chase_standoff_point()
	navigation_agent.target_desired_distance = 4.0
	navigation_agent.target_position = standoff

	if not navigation_agent.is_navigation_finished():
		var next_position := navigation_agent.get_next_path_position()
		var direction := global_position.direction_to(next_position)
		if direction != Vector2.ZERO:
			velocity = direction * move_speed
			move_and_slide()
			_play_walk_animation(direction)
		else:
			velocity = Vector2.ZERO
			_play_idle()
	else:
		velocity = Vector2.ZERO
		_play_idle()

	_update_terrain_feedback(_delta)


func _is_in_attack_range() -> bool:
	if attack_target == null:
		return false

	var dist := global_position.distance_to(attack_target.global_position)
	match combat_style:
		CombatStyle.MELEE:
			return dist <= melee_range
		CombatStyle.RANGED:
			return dist >= attack_range_min and dist <= attack_range_max
	return false


func _get_desired_attack_distance() -> float:
	match combat_style:
		CombatStyle.MELEE:
			return melee_range * 0.85
		CombatStyle.RANGED:
			return (attack_range_min + attack_range_max) * 0.5
	return melee_range


func _get_chase_standoff_point() -> Vector2:
	var target_pos := attack_target.global_position
	var dir := global_position.direction_to(target_pos)
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN

	var dist := global_position.distance_to(target_pos)
	var desired := _get_desired_attack_distance()

	if combat_style == CombatStyle.RANGED:
		if dist > attack_range_max:
			desired = attack_range_max * 0.92
		elif dist < attack_range_min:
			desired = attack_range_min * 1.02
		elif _is_in_attack_range():
			return global_position

	return target_pos - dir * desired


func _start_attack() -> void:
	_unit_state = UnitState.ATTACKING
	_is_attack_animating = true
	_damage_dealt_this_swing = false
	velocity = Vector2.ZERO
	navigation_agent.target_position = global_position
	_play_attack_animation(_direction_to_target())


func _direction_to_target() -> Vector2:
	if attack_target == null:
		return Vector2.DOWN
	return global_position.direction_to(attack_target.global_position)


func _play_attack_animation(direction: Vector2) -> void:
	_last_facing_direction = direction
	var animation_name := &"attack_down"
	if direction.y < -0.15:
		animation_name = &"attack_up"
	elif direction.y > 0.15:
		animation_name = &"attack_down"
	elif direction.x < 0.0:
		animation_name = &"attack_up" if animated_sprite.sprite_frames.has_animation(&"attack_up") else &"attack_down"
	else:
		animation_name = &"attack_down"

	if not animated_sprite.sprite_frames.has_animation(animation_name):
		animation_name = &"attack_down" if animated_sprite.sprite_frames.has_animation(&"attack_down") else &"idle"

	animated_sprite.play(animation_name)


func _on_animation_frame_changed() -> void:
	if not _is_attack_animating:
		return

	var hit_frame := MELEE_DAMAGE_FRAME if combat_style == CombatStyle.MELEE else RANGED_DAMAGE_FRAME
	if animated_sprite.frame == hit_frame and not _damage_dealt_this_swing:
		_damage_dealt_this_swing = true
		_deal_attack()


func _deal_attack() -> void:
	if attack_target == null or not is_instance_valid(attack_target) or attack_target.hp <= 0 or attack_target._is_dying:
		return

	match combat_style:
		CombatStyle.MELEE:
			if global_position.distance_to(attack_target.global_position) <= melee_range * 1.15:
				attack_target.take_damage(attack_damage, self)
		CombatStyle.RANGED:
			_spawn_arrow()


func _spawn_arrow() -> void:
	if attack_target == null:
		return

	var arrow_scene: PackedScene = preload("res://scenes/combat/arrow.tscn")
	var arrow: Arrow = arrow_scene.instantiate()
	var origin := get_sprite_center()
	var target_point := attack_target.get_sprite_center()
	var dir := origin.direction_to(target_point)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	arrow.shooter = self
	arrow.target = attack_target
	arrow.damage = attack_damage
	arrow.direction = dir
	var world := get_parent().get_parent()
	world.add_child(arrow)
	arrow.global_position = origin + dir * 12.0


func _on_animation_finished() -> void:
	if _is_dying:
		_freeze_death_pose()
		return

	if not _is_attack_animating:
		return

	_is_attack_animating = false
	_attack_cooldown_remaining = attack_cooldown
	_play_idle()

	if attack_target != null and is_instance_valid(attack_target) and attack_target.hp > 0 and not attack_target._is_dying:
		_unit_state = UnitState.CHASING
	else:
		attack_target = null
		_unit_state = UnitState.IDLE


func _freeze_death_pose() -> void:
	var animation_name := animated_sprite.animation
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return

	var last_frame := animated_sprite.sprite_frames.get_frame_count(animation_name) - 1
	animated_sprite.stop()
	animated_sprite.frame = last_frame


func _play_idle() -> void:
	if _is_attack_animating:
		return
	if animated_sprite.animation != &"idle" and animated_sprite.sprite_frames.has_animation(&"idle"):
		animated_sprite.play(&"idle")


func _play_walk_animation(direction: Vector2) -> void:
	_last_facing_direction = direction
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


func _update_terrain_feedback(_delta: float) -> void:
	if _ground_layer == null:
		return

	var on_water := _ground_layer.is_water_at(global_position)
	if on_water and not _was_on_water:
		_spawn_splash()
	_was_on_water = on_water


func _spawn_splash() -> void:
	if dust_particles == null:
		return
	dust_particles.modulate = Color(0.55, 0.78, 1.0, 0.85)
	dust_particles.restart()
	dust_particles.emitting = true
