extends CanvasLayer

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var inventory: Node = $"../Inventory"
@onready var basic_hud: CanvasLayer = $"../InventoryHUD"
@onready var title: Label = $Screen/Margin/Panel/Padding/Layout/Header/Title
@onready var basic_list: VBoxContainer = $Screen/Margin/Panel/Padding/Layout/Columns/Basic/Slots
@onready var storage_list: VBoxContainer = $Screen/Margin/Panel/Padding/Layout/Columns/Storage/Slots
@onready var store_button: Button = $Screen/Margin/Panel/Padding/Layout/Actions/Store
@onready var take_button: Button = $Screen/Margin/Panel/Padding/Layout/Actions/Take
@onready var drop_button: Button = $Screen/Margin/Panel/Padding/Layout/Actions/Drop
@onready var status: Label = $Screen/Margin/Panel/Padding/Layout/Status
@onready var load_label: Label = $Screen/Margin/Panel/Padding/Layout/LoadLabel

var is_open: bool = false
var backpack: Node3D = null
var selected_basic: int = -1
var selected_storage: int = -1
var basic_buttons: Array[Button] = []
var storage_buttons: Array[Button] = []
var pending: Dictionary = {}
var basic_hud_was_visible: bool = false


func _ready() -> void:
	hide()
	if not player.is_multiplayer_authority():
		set_process(false)
		return
	for slot in range(4):
		basic_buttons.append(_add_slot_button(basic_list, _select_basic.bind(slot)))
	store_button.pressed.connect(_store_selected)
	take_button.pressed.connect(_take_selected)
	drop_button.pressed.connect(_drop_selected)
	$Screen/Margin/Panel/Padding/Layout/Header/Close.pressed.connect(close_menu)


func _add_slot_button(list: VBoxContainer, callback: Callable) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 38
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.pressed.connect(callback)
	list.add_child(button)
	return button


func open_menu(item: Node3D) -> bool:
	if not player.is_multiplayer_authority() or is_open:
		return false
	if item == null or not item.has_method("can_access_storage"):
		return false
	if player.equipped_item != item or not item.can_access_storage(multiplayer.get_unique_id()):
		return false
	backpack = item
	selected_basic = -1
	selected_storage = -1
	pending.clear()
	for button in storage_buttons:
		button.free()
	storage_buttons.clear()
	for slot in range(int(backpack.get("storage_slot_count"))):
		storage_buttons.append(_add_slot_button(storage_list, _select_storage.bind(slot)))
	backpack.connect("storage_request_finished", _on_storage_result)
	is_open = true
	basic_hud_was_visible = basic_hud.visible
	basic_hud.hide()
	show()
	player.interaction_requested = false
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status.text = "Selecione um item para guardar, retirar ou soltar."
	_refresh()
	return true


func close_menu(capture_mouse: bool = true) -> void:
	if not is_open:
		return
	if is_instance_valid(backpack) and backpack.is_connected("storage_request_finished", _on_storage_result):
		backpack.disconnect("storage_request_finished", _on_storage_result)
	is_open = false
	backpack = null
	pending.clear()
	hide()
	if is_instance_valid(basic_hud) and not player.is_queued_for_deletion():
		basic_hud.visible = basic_hud_was_visible
	if player.is_multiplayer_authority():
		var capture := capture_mouse and not player.is_queued_for_deletion()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	if is_open:
		close_menu(false)


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel") and not event.is_echo():
		close_menu()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_open:
		return
	if not is_instance_valid(backpack) or player.is_queued_for_deletion():
		close_menu(not player.is_queued_for_deletion())
		return
	if player.equipped_item != backpack or not backpack.can_access_storage(multiplayer.get_unique_id()):
		close_menu()
		return
	_poll_pending()
	_refresh()


func _select_basic(slot: int) -> void:
	selected_basic = -1 if selected_basic == slot else slot
	_refresh()


func _select_storage(slot: int) -> void:
	selected_storage = -1 if selected_storage == slot else slot
	_refresh()


func _item_name(item: Node3D) -> String:
	if item == null:
		return "Vazio"
	var data: ItemData = item.get("item_data")
	return data.display_name if data != null else String(item.name)


func _refresh() -> void:
	if not is_open:
		return
	var contents: Array = backpack.get_stored_items()
	var vitals: Node = player.get_node("Vitals")
	load_label.text = vitals.get_load_text()
	if vitals.is_over_capacity():
		load_label.text += " — Sobrecarga: sprint bloqueado"
	title.text = "%s — %d/%d" % [_item_name(backpack), contents.size(), storage_buttons.size()]
	for slot in range(basic_buttons.size()):
		basic_buttons[slot].text = "[%d] %s: %s" % [slot + 1, inventory.SLOT_NAMES[slot], _item_name(inventory.get_item_in_slot(slot))]
		basic_buttons[slot].set_pressed_no_signal(slot == selected_basic)
	for slot in range(storage_buttons.size()):
		storage_buttons[slot].text = "[%d] %s" % [slot + 1, _item_name(backpack.get_item_in_storage(slot))]
		storage_buttons[slot].set_pressed_no_signal(slot == selected_storage)

	var basic: Node3D = inventory.get_item_in_slot(selected_basic)
	var stored: Node3D = backpack.get_item_in_storage(selected_storage)
	var storage_destination: int = selected_storage if selected_storage >= 0 else backpack.find_empty_storage_slot()
	var basic_destination: int = selected_basic if selected_basic >= 0 else inventory.find_empty_slot()
	var busy := not pending.is_empty()
	store_button.disabled = busy or basic == null or basic == backpack
	if not store_button.disabled:
		store_button.disabled = not basic.can_be_stored() or storage_destination < 0 or backpack.get_item_in_storage(storage_destination) != null
	take_button.disabled = busy or stored == null or basic_destination < 0 or inventory.get_item_in_slot(basic_destination) != null
	drop_button.disabled = busy or stored == null


func _begin_request(action: String, item: Node3D) -> void:
	pending = {"action": action, "item": item, "started": Time.get_ticks_msec(), "confirmed": false}
	status.text = "Aguardando confirmação do servidor..."
	_refresh()


func _store_selected() -> void:
	if not is_open or store_button.disabled:
		return
	var item: Node3D = inventory.get_item_in_slot(selected_basic)
	_begin_request("store", item)
	backpack.request_store.rpc_id(1, selected_basic, selected_storage)


func _take_selected() -> void:
	if not is_open or take_button.disabled:
		return
	var item: Node3D = backpack.get_item_in_storage(selected_storage)
	_begin_request("take", item)
	backpack.request_take.rpc_id(1, selected_storage, selected_basic)


func _drop_selected() -> void:
	if not is_open or drop_button.disabled:
		return
	var item: Node3D = backpack.get_item_in_storage(selected_storage)
	_begin_request("drop", item)
	backpack.request_drop_content.rpc_id(1, selected_storage)


func _on_storage_result(action: String, accepted: bool) -> void:
	if not is_open or pending.get("action") != action:
		return
	if accepted:
		pending["confirmed"] = true
	else:
		pending.clear()
		status.text = "Operação recusada. Confira o espaço de destino e, ao soltar, se há chão disponível."


func _poll_pending() -> void:
	if pending.is_empty():
		return
	var item: Node3D = pending["item"]
	var applied := false
	if is_instance_valid(item) and pending["confirmed"]:
		match pending["action"]:
			"store":
				applied = item.get("container_name") == backpack.name
			"take":
				applied = item.get("container_name") == &"" and item.get("holder_peer_id") == multiplayer.get_unique_id()
			"drop":
				applied = item.get("container_name") == &"" and item.get("holder_peer_id") == 0
	if applied:
		status.text = {"store": "Item guardado.", "take": "Item retirado.", "drop": "Item solto no chão."}[pending["action"]]
		pending.clear()
	elif Time.get_ticks_msec() - int(pending["started"]) > 4000:
		pending.clear()
		status.text = "Sem confirmação da operação. Confira os itens antes de tentar novamente."
