extends CharacterBody2D

@export var move_speed: float = 120.0
@export var max_hp: int = 100

var hp: int
var is_selected: bool = false

@onready var selection_indicator: Polygon2D = $SelectionIndicator

func _ready() -> void:
	hp = max_hp
	add_to_group("units")

func select() -> void:
	is_selected = true
	selection_indicator.visible = true

func deselect() -> void:
	is_selected = false
	selection_indicator.visible = false

func move_to(target: Vector2) -> void:
	# Placeholder — pathfinding se implementará en sprint 2/3
	pass
