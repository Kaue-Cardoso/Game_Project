extends Node3D

const CollectibleItem = preload("res://scripts/items/collectible_item.gd")

@export var accepting_deliveries: bool = true
@export var team_credits: int = 0
@export var delivered_count: int = 0

@onready var deposit_area: Area3D = $DepositArea
@onready var deposit_shape: CollisionShape3D = $DepositArea/CollisionShape3D
@onready var hud: CanvasLayer = $DeliveryHUD
@onready var summary: Label = $DeliveryHUD/Summary


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or not accepting_deliveries:
		return
	if not is_visible_in_tree():
		return

	var box := deposit_shape.shape as BoxShape3D
	if box == null:
		return

	for area in deposit_area.get_overlapping_areas():
		var item: Node = area.get_parent()
		if not item is CollectibleItem:
			continue
		if item.get_parent() != get_parent():
			continue
		if not item.can_extract():
			continue

		# Exige que o centro do objeto esteja dentro da caixa.
		var local_position: Vector3 = (
			deposit_shape.global_transform.affine_inverse()
			* item.global_position
		)
		var half_size := box.size * 0.5
		if (
			absf(local_position.x) > half_size.x
			or absf(local_position.y) > half_size.y
			or absf(local_position.z) > half_size.z
		):
			continue

		var value: int = item.mark_extracted()
		if value > 0:
			team_credits += value
			delivered_count += 1

func _process(_delta: float) -> void:
	# CanvasLayer precisa ser ocultado explicitamente no menu.
	hud.visible = is_visible_in_tree()
	summary.text = "Créditos da equipe: %d\nObjetos entregues: %d" % [
		team_credits, delivered_count
	]
