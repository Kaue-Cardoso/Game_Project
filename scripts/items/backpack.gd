extends "res://scripts/items/collectible_item.gd"

signal storage_request_finished(action: String, accepted: bool)

@export_range(1, 64, 1) var storage_slot_count: int = 6

var pending_content_drops: Array[Dictionary] = []


func can_be_stored() -> bool:
	# Primeira versao: sem mochilas dentro de mochilas e sem ciclos.
	return false


func can_access_storage(peer_id: int) -> bool:
	return (
		can_interact_with_round()
		and peer_id > 0
		and holder_peer_id == peer_id
		and is_equipped()
	)


func get_item_in_storage(slot_index: int) -> Node3D:
	if slot_index < 0 or slot_index >= storage_slot_count:
		return null
	for item in get_tree().get_nodes_in_group("collectible_items"):
		if item.get_parent() != get_parent():
			continue
		if item.get("container_name") == name and item.get("container_slot") == slot_index:
			return item as Node3D
	return null


func find_empty_storage_slot() -> int:
	for slot_index in range(storage_slot_count):
		if get_item_in_storage(slot_index) == null:
			return slot_index
	return -1


func get_stored_items() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for slot_index in range(storage_slot_count):
		var item := get_item_in_storage(slot_index)
		if item != null:
			result.append(item)
	return result


func _request_sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if sender == 0 else sender


@rpc("any_peer", "call_local", "reliable")
func request_store(source_slot: int, target_slot: int = -1) -> void:
	if not multiplayer.is_server():
		return
	var sender := _request_sender()
	var accepted := store_from_player(sender, source_slot, target_slot)
	_finish_storage_request(sender, "store", accepted)


func store_from_player(peer_id: int, source_slot: int, target_slot: int = -1) -> bool:
	if not multiplayer.is_server() or not can_access_storage(peer_id):
		return false
	var player := get_parent().get_node_or_null("Players/" + str(peer_id))
	if player == null:
		return false
	var inventory: Node = player.get_node("Inventory")
	var item: Node3D = inventory.get_item_in_slot(source_slot)
	if item == null or item == self or not item.can_be_stored():
		return false
	if target_slot == -1:
		target_slot = find_empty_storage_slot()
	if target_slot < 0 or target_slot >= storage_slot_count:
		return false
	if get_item_in_storage(target_slot) != null:
		return false

	# Os itens continuam na arvore do mapa; somente seu estado muda.
	item.set("container_name", name)
	item.set("container_slot", target_slot)
	item.set("inventory_slot", -1)
	item.set("holder_peer_id", 0)
	item.set("pending_drop_peer_id", 0)
	item._on_stored()
	return true


@rpc("any_peer", "call_local", "reliable")
func request_take(source_slot: int, target_slot: int = -1) -> void:
	if not multiplayer.is_server():
		return
	var sender := _request_sender()
	var accepted := take_to_player(sender, source_slot, target_slot)
	_finish_storage_request(sender, "take", accepted)


func take_to_player(peer_id: int, source_slot: int, target_slot: int = -1) -> bool:
	if not multiplayer.is_server() or not can_access_storage(peer_id):
		return false
	var item := get_item_in_storage(source_slot)
	var player := get_parent().get_node_or_null("Players/" + str(peer_id))
	if item == null or player == null:
		return false
	var inventory: Node = player.get_node("Inventory")
	if target_slot == -1:
		target_slot = inventory.find_empty_slot()
	if target_slot < 0 or target_slot >= 4:
		return false
	if inventory.get_item_in_slot(target_slot) != null:
		return false

	item.set("container_name", &"")
	item.set("container_slot", -1)
	item.set("inventory_slot", target_slot)
	item.set("holder_peer_id", peer_id)
	return true


@rpc("any_peer", "call_local", "reliable")
func request_drop_content(source_slot: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := _request_sender()
	var item := get_item_in_storage(source_slot)
	if not can_access_storage(sender) or item == null:
		_finish_storage_request(sender, "drop", false)
		return
	var request := {"peer_id": sender, "slot": source_slot, "item": item}
	if not pending_content_drops.has(request):
		pending_content_drops.append(request)


func _physics_process(delta: float) -> void:
	super(delta)
	if not multiplayer.is_server():
		return
	var requests: Array[Dictionary] = pending_content_drops.duplicate()
	pending_content_drops.clear()
	for request in requests:
		var peer_id: int = request["peer_id"]
		if not can_access_storage(peer_id):
			_finish_storage_request(peer_id, "drop", false)
			continue
		var item := get_item_in_storage(request["slot"])
		if item == null or item != request["item"]:
			_finish_storage_request(peer_id, "drop", false)
			continue
		var destination: Variant = item.find_drop_transform(peer_id)
		if destination != null:
			item.place_on_floor(destination)
		_finish_storage_request(peer_id, "drop", destination != null)


func _finish_storage_request(peer_id: int, action: String, accepted: bool) -> void:
	if peer_id == multiplayer.get_unique_id():
		_receive_storage_result(action, accepted)
	elif multiplayer.get_peers().has(peer_id):
		_receive_storage_result.rpc_id(peer_id, action, accepted)


@rpc("authority", "call_local", "reliable")
func _receive_storage_result(action: String, accepted: bool) -> void:
	storage_request_finished.emit(action, accepted)

func _on_round_reset() -> void:
	pending_content_drops.clear()
