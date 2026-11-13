extends Control

@onready var address_input: LineEdit = $CenterContainer/VBoxContainer/AddressInput
@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	address_input.text = Session.server_address
	status_label.text = Session.menu_message
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)


func _on_host_pressed() -> void:
	_set_menu_locked(true)
	var error: Error = Session.host_game()
	if error != OK:
		status_label.text = "Erro ao criar partida: %s" % error_string(error)
		_set_menu_locked(false)


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		status_label.text = "Digite o endereço do servidor."
		return

	_set_menu_locked(true)
	var error: Error = Session.join_game(address)
	if error != OK:
		status_label.text = "Erro ao iniciar conexão: %s" % error_string(error)
		_set_menu_locked(false)


func _set_menu_locked(locked: bool) -> void:
	host_button.disabled = locked
	join_button.disabled = locked
	address_input.editable = not locked
