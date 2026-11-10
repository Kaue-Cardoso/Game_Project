extends "res://scripts/items/collectible_item.gd"

@export var light_energy: float = 2.0
@export var light_range: float = 15.0
@export var light_angle: float = 35.0
@export var is_on: bool = false

@onready var light: SpotLight3D = $SpotLight3D


func _ready() -> void:
	super()
	add_to_group("flashlight_items")
	light.light_energy = light_energy
	light.spot_range = light_range
	light.spot_angle = light_angle
	light.visible = false


func _process(delta: float) -> void:
	super(delta)
	light.visible = is_equipped() and is_on


func _use() -> void:
	is_on = not is_on


func _on_released() -> void:
	is_on = false
