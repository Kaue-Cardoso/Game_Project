extends Node3D

@export var item_data: ItemData
@export var floor_transform: Transform3D = Transform3D.IDENTITY
@export var holder_peer_id: int = 0
@export var ground_clearance: float = 0.05

@onready var pickup_area: Area3D = $PickupArea

var starting_transform: Transform3D
var previous_holder: Node3D = null
var pending_drop_peer_id: int = 0


func _ready() -> void:
	add_to_group("collectible_items")
	starting_transform = global_transform
	floor_transform = starting_transform


func _process(_delta: float) -> void:
	var holder: Node3D = get_parent().get_node_or_null(
		"Players/" + str(holder_peer_id)
	) as Node3D

	if multiplayer.is_server() and holder_peer_id != 0 and holder == null:
		floor_transform = starting_transform
		holder_peer_id = 0
		_on_released()

	if is_instance_valid(previous_holder) and previous_holder != holder:
		if previous_holder.get("equipped_item") == self:
			previous_holder.set("equipped_item", null)

	if holder_peer_id == 0:
		global_transform = floor_transform
	elif is_instance_valid(holder):
		var socket: Marker3D = holder.get_node("Head/Camera3D/HandSocket")
		global_transform = socket.global_transform
		holder.set("equipped_item", self)

	previous_holder = holder
	pickup_area.collision_layer = 2 if holder_peer_id == 0 else 0

@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if holder_peer_id != 0:
		return

	var player: CharacterBody3D = get_parent().get_node_or_null(
		"Players/" + str(sender_id)
	) as CharacterBody3D

	if player == null:
		return

		# Limite temporario de um item, ate implementarmos o inventario.
	for item in get_tree().get_nodes_in_group("collectible_items"):
		if item.get("holder_peer_id") == sender_id:
			return

	var camera: Camera3D = player.get_node("Head/Camera3D")
	if camera.global_position.distance_to(global_position) > 2.8:
		return

	# Confere se existe uma parede ou outro obstaculo no caminho.
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position, global_position
	)
	query.collision_mask = 3
	query.collide_with_areas = true
	query.exclude = [player.get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider") != pickup_area:
		return

	holder_peer_id = sender_id


@rpc("any_peer", "call_local", "reliable")
func request_use() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if holder_peer_id == sender_id:
		_use()


func _use() -> void:
	pass


func _on_released() -> void:
	pass

@rpc("any_peer", "call_local", "reliable")
func request_drop() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if holder_peer_id == sender_id:
		pending_drop_peer_id = sender_id


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or pending_drop_peer_id == 0:
		return

	var peer_id := pending_drop_peer_id
	pending_drop_peer_id = 0

	# Confere novamente se essa pessoa ainda esta segurando o item.
	if holder_peer_id == peer_id:
		_try_drop(peer_id)


func _try_drop(peer_id: int) -> void:
	var player: CharacterBody3D = get_parent().get_node_or_null(
		"Players/" + str(peer_id)
	) as CharacterBody3D

	if player == null:
		return

	var camera: Camera3D = player.get_node("Head/Camera3D")
	var origin := camera.global_position
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var target := origin + forward * 1.2
	var space := get_world_3d().direct_space_state

	# Procura uma parede ou outro corpo no caminho.
	var forward_query := PhysicsRayQueryParameters3D.create(origin, target)
	forward_query.collision_mask = 1
	forward_query.exclude = [player.get_rid()]

	var obstacle := space.intersect_ray(forward_query)
	if not obstacle.is_empty():
		var obstacle_position: Vector3 = obstacle["position"]

		if origin.distance_to(obstacle_position) < 0.4:
			return

		target = obstacle_position - forward * 0.35

	# A partir desse ponto, procura uma superficie abaixo.
	var floor_query := PhysicsRayQueryParameters3D.create(
		target + Vector3.UP * 0.1,
		target + Vector3.DOWN * 4.0
	)
	floor_query.collision_mask = 1
	floor_query.exclude = [player.get_rid()]

	var floor_hit := space.intersect_ray(floor_query)
	if floor_hit.is_empty():
		return

	var floor_normal: Vector3 = floor_hit["normal"]
	if floor_normal.y < 0.7:
		return

	var floor_position: Vector3 = floor_hit["position"]
	floor_transform = Transform3D(
		Basis.IDENTITY,
		floor_position + Vector3.UP * ground_clearance
	)

	holder_peer_id = 0
	_on_released()
