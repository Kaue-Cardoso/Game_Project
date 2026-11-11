extends Node

const SLOT_COUNT: int = 4
const SLOT_NAMES = ["Mao direita", "Mao esquerda", "Bolso 1", "Bolso 2"]

@onready var player: Node3D = get_parent() as Node3D
@onready var hud: CanvasLayer = $"../InventoryHUD"
@onready var slots_label: Label = $"../InventoryHUD/SlotsLabel"
var active_hand: int = 0
var selection_cursor: int = 0

func _ready() -> void:
	var local_player := player.is_multiplayer_authority()
	hud.visible = local_player
	set_process(local_player)


func get_item_in_slot(slot_index: int) -> Node3D:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return null

	var peer_id := player.get_multiplayer_authority()

	for item in get_tree().get_nodes_in_group("collectible_items"):
		if item.get("container_name") != &"":
			continue
		if item.get("holder_peer_id") != peer_id:
			continue
		var slot: int = int(item.get("inventory_slot"))
		if slot == slot_index:
			return item as Node3D

		# O mesmo objeto Large reserva as duas maos, sem ser duplicado.
		if slot_index == 1 and slot == 0 and is_large(item as Node3D):
			return item as Node3D

	return null


func find_empty_slot() -> int:
	for slot_index in range(SLOT_COUNT):
		if get_item_in_slot(slot_index) == null:
			return slot_index

	return -1


func get_carried_items() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var pending: Array[Node3D] = []
	var counted: Dictionary = {}
	for slot in range(SLOT_COUNT):
		var item := get_item_in_slot(slot)
		if item != null:
			pending.append(item)

	# Visita cada objeto uma vez, inclusive o conteudo das mochilas.
	while not pending.is_empty():
		var item: Node3D = pending.pop_back()
		if not is_instance_valid(item) or counted.has(item):
			continue
		counted[item] = true
		result.append(item)
		if item.has_method("get_stored_items"):
			for stored in item.get_stored_items():
				pending.append(stored)
	return result


func get_total_weight_kg() -> float:
	var total: float = 0.0
	for item in get_carried_items():
		var data: ItemData = item.get("item_data")
		if data != null:
			total += maxf(data.weight_kg, 0.0)
	return total


func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	var hand_name := "Direita" if active_hand == 0 else "Esquerda"
	lines.append("Mao ativa: %s [Tab]" % hand_name)

	for slot_index in range(SLOT_COUNT):
		var item := get_item_in_slot(slot_index)
		var item_name := "Vazio"

		if item != null:
			var data: ItemData = item.get("item_data")
			item_name = data.display_name if data != null else item.name

		var marker := ">" if slot_index == active_hand else " "
		lines.append("%s [%d] %s: %s" % [
			marker, slot_index + 1, SLOT_NAMES[slot_index], item_name
		])

	slots_label.text = "\n".join(lines)

func toggle_active_hand() -> void:
	if not player.is_multiplayer_authority():
		return

	active_hand = 1 - active_hand
	selection_cursor = active_hand


func select_slot(slot_index: int) -> void:
	if not player.is_multiplayer_authority():
		return
		
	if not player.is_round_active():
		return

	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return

	selection_cursor = slot_index
	request_select_slot.rpc_id(1, active_hand, slot_index)


func cycle_slot(direction: int) -> void:
	var next_slot := wrapi(selection_cursor + direction, 0, SLOT_COUNT)
	select_slot(next_slot)


@rpc("authority", "call_local", "reliable")
func request_select_slot(hand_index: int, source_slot: int) -> void:
	if not multiplayer.is_server():
		return
	if hand_index not in [0, 1]:
		return
	if source_slot < 0 or source_slot >= SLOT_COUNT:
		return
	if source_slot == hand_index:
		return

	var item_in_hand := get_item_in_slot(hand_index)
	var selected_item := get_item_in_slot(source_slot)
	if is_large(item_in_hand) or is_large(selected_item):
		return

	# O servidor troca os dois lugares sem esperar outro frame.
	if item_in_hand != null:
		item_in_hand.set("inventory_slot", source_slot)

	if selected_item != null:
		selected_item.set("inventory_slot", hand_index)

	# Guardar numa posicao de bolso encerra o uso do equipamento.
	if item_in_hand != null and source_slot >= 2:
		item_in_hand._on_stored()


func is_large(item: Node3D) -> bool:
	if item == null:
		return false
	var data: ItemData = item.get("item_data")
	return data != null and data.size == ItemData.Size.LARGE


func try_equip_large(incoming: Node3D) -> bool:
	if not multiplayer.is_server():
		return false
	if not is_large(incoming) or incoming.get("holder_peer_id") != 0:
		return false
	if is_large(get_item_in_slot(0)):
		return false

	var free_pockets: Array[int] = []
	for slot in [2, 3]:
		if get_item_in_slot(slot) == null:
			free_pockets.append(slot)

	var plan: Array[Dictionary] = []
	var drop_count: int = 0
	var peer_id := player.get_multiplayer_authority()

	# Primeiro planeja. Uma falha nao pode esvaziar parcialmente as maos.
	for hand in [0, 1]:
		var held := get_item_in_slot(hand)
		if held == null:
			continue

		if not free_pockets.is_empty():
			var pocket: int = free_pockets.pop_front()
			plan.append({"item": held, "slot": pocket})
		else:
			var offset := -0.35 + drop_count * 0.7
			var destination: Variant = held.find_drop_transform(peer_id, offset)
			if destination == null:
				return false
			plan.append({"item": held, "destination": destination})
			drop_count += 1

	# Aplica o plano completo, sem pausas entre as alteracoes.
	for operation in plan:
		var held: Node3D = operation["item"]
		if operation.has("slot"):
			held.set("inventory_slot", operation["slot"])
			held._on_stored()
		else:
			held.place_on_floor(operation["destination"])

	incoming.set("inventory_slot", 0)
	incoming.set("holder_peer_id", peer_id)
	return true
