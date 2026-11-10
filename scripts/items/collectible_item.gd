extends Node3D

@export var item_data: ItemData
@export var floor_transform: Transform3D = Transform3D.IDENTITY
@export var holder_peer_id: int = 0
@export var ground_clearance: float = 0.05
@export var inventory_slot: int = -1
# O nome identifica a mochila irma na cena, sem mudar o caminho do item.
@export var container_name: StringName = &""
@export var container_slot: int = -1

@onready var pickup_area: Area3D = $PickupArea

var starting_transform: Transform3D
var pending_drop_peer_id: int = 0
var pending_pickups: Array[int] = []


func _ready() -> void:
	add_to_group("collectible_items")
	starting_transform = global_transform
	floor_transform = starting_transform


func _process(_delta: float) -> void:
	if container_name != &"":
		var container := get_container()
		if container == null and multiplayer.is_server():
			place_on_floor(starting_transform)
		else:
			hide()
			pickup_area.collision_layer = 0
			if container != null:
				global_transform = container.global_transform
			return

	var holder: Node3D = get_parent().get_node_or_null(
		"Players/" + str(holder_peer_id)
	) as Node3D

	if multiplayer.is_server() and holder_peer_id != 0 and holder == null:
		floor_transform = starting_transform
		holder_peer_id = 0
		inventory_slot = -1
		_on_released()

	pickup_area.collision_layer = 2 if holder_peer_id == 0 else 0

	if holder_peer_id == 0:
		show()
		global_transform = floor_transform
		return

	# O jogador pode ainda estar sendo criado nesta sessao.
	if holder == null:
		hide()
		return

	if is_equipped():
		show()
		var socket_path := "Head/Camera3D/HandSocket"
		if item_data != null and item_data.size == ItemData.Size.LARGE:
			socket_path = "Head/Camera3D/TwoHandSocket"
		elif inventory_slot == 1:
			socket_path = "Head/Camera3D/HandSocketLeft"

		var socket: Marker3D = holder.get_node(socket_path)
		global_transform = socket.global_transform
	else:
		hide()

@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	# As consultas fisicas ficam para a atualizacao da fisica.
	if not pending_pickups.has(sender_id):
		pending_pickups.append(sender_id)


func _try_pickup(sender_id: int) -> void:
	if holder_peer_id != 0 or container_name != &"":
		return

	var player: CharacterBody3D = get_parent().get_node_or_null(
		"Players/" + str(sender_id)
	) as CharacterBody3D

	if player == null:
		return

	if item_data == null:
		return

	var inventory: Node = player.get_node("Inventory")

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

	if item_data.size == ItemData.Size.LARGE:
		inventory.try_equip_large(self)
		return

	var free_slot: int = inventory.find_empty_slot()
	if free_slot == -1:
		return

	inventory_slot = free_slot
	holder_peer_id = sender_id


@rpc("any_peer", "call_local", "reliable")
func request_use() -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if holder_peer_id == sender_id and is_equipped():
		_use()

func is_equipped() -> bool:
	return container_name == &"" and holder_peer_id != 0 and inventory_slot in [0, 1]


func get_container() -> Node3D:
	if container_name == &"":
		return null
	return get_parent().get_node_or_null(NodePath(String(container_name))) as Node3D


func can_be_stored() -> bool:
	return item_data != null and item_data.size in [ItemData.Size.SMALL, ItemData.Size.MEDIUM]

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

	if holder_peer_id == sender_id and is_equipped():
		pending_drop_peer_id = sender_id

func _on_stored() -> void:
	_on_released()

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return

	var requests: Array[int] = pending_pickups.duplicate()
	pending_pickups.clear()
	for sender_id in requests:
		_try_pickup(sender_id)

	if pending_drop_peer_id == 0:
		return

	var peer_id := pending_drop_peer_id
	pending_drop_peer_id = 0

	# Confere novamente se essa pessoa ainda esta segurando o item.
	if holder_peer_id == peer_id and is_equipped():
		_try_drop(peer_id)


func _try_drop(peer_id: int) -> void:
	var result: Variant = find_drop_transform(peer_id)
	if result != null:
		place_on_floor(result)


func place_on_floor(destination: Transform3D) -> void:
	if not multiplayer.is_server():
		return

	floor_transform = destination
	container_name = &""
	container_slot = -1
	inventory_slot = -1
	holder_peer_id = 0
	pending_drop_peer_id = 0
	_on_released()


func find_drop_transform(peer_id: int, side_offset: float = 0.0) -> Variant:
	var player: CharacterBody3D = get_parent().get_node_or_null(
		"Players/" + str(peer_id)
	) as CharacterBody3D

	if player == null:
		return null

	var camera: Camera3D = player.get_node("Head/Camera3D")
	var origin := camera.global_position
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := player.global_transform.basis.x.normalized()
	var target := origin + forward * 1.2 + right * side_offset
	var ray_direction := (target - origin).normalized()
	var space := get_world_3d().direct_space_state

	# Procura uma parede ou outro corpo no caminho.
	var forward_query := PhysicsRayQueryParameters3D.create(origin, target)
	forward_query.collision_mask = 1
	forward_query.exclude = [player.get_rid()]

	var obstacle := space.intersect_ray(forward_query)
	if not obstacle.is_empty():
		var obstacle_position: Vector3 = obstacle["position"]

		if origin.distance_to(obstacle_position) < 0.4:
			return null

		target = obstacle_position - ray_direction * 0.35

	# A partir desse ponto, procura uma superficie abaixo.
	var floor_query := PhysicsRayQueryParameters3D.create(
		target + Vector3.UP * 0.1,
		target + Vector3.DOWN * 4.0
	)
	floor_query.collision_mask = 1
	floor_query.exclude = [player.get_rid()]

	var floor_hit := space.intersect_ray(floor_query)
	if floor_hit.is_empty():
		return null

	var floor_normal: Vector3 = floor_hit["normal"]
	if floor_normal.y < 0.7:
		return null

	var floor_position: Vector3 = floor_hit["position"]
	return Transform3D(
		Basis.IDENTITY,
		floor_position + Vector3.UP * ground_clearance
	)
