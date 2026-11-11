extends Control

const PORT: int = 7000
const MAX_CLIENTS: int = 3

@onready var address_input: LineEdit = $CenterContainer/VBoxContainer/AddressInput
@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var menu: CenterContainer = $CenterContainer
@onready var test_map = $TestMap

func _ready() -> void:
	test_map.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Conecta os cliques dos botoes as nossas funcoes.
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	# Eventos enviados pelo sistema de rede do Godot.
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _on_host_pressed() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)

	if error != OK:
		status_label.text = "Erro ao criar partida: %s" % error_string(error)
		return

	multiplayer.multiplayer_peer = peer
	test_map.get_node("RoundManager").prepare_new_session()
	_enter_map()

	test_map.add_player(multiplayer.get_unique_id())
	_set_menu_locked(true)
	status_label.text = "Partida criada. Aguardando jogadores..."


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()

	if address.is_empty():
		status_label.text = "Digite o endereco do servidor."
		return

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)

	if error != OK:
		status_label.text = "Erro ao iniciar conexao: %s" % error_string(error)
		return

	multiplayer.multiplayer_peer = peer
	_set_menu_locked(true)
	status_label.text = "Conectando..."


func _on_connected_to_server() -> void:
	status_label.text = "Conectado! Seu ID: %d" % multiplayer.get_unique_id()
	_enter_map()

func _on_connection_failed() -> void:
	_reset_connection()
	status_label.text = "Nao foi possivel conectar. Confira o endereco e o host."


func _on_server_disconnected() -> void:
	_reset_connection()
	status_label.text = "O host encerrou a partida."


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		test_map.add_player(peer_id)

	print("Jogador conectado: ", peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		test_map.remove_player(peer_id)

	print("Jogador desconectado: ", peer_id)


func _set_menu_locked(locked: bool) -> void:
	host_button.disabled = locked
	join_button.disabled = locked
	address_input.editable = not locked


func _reset_connection() -> void:
	test_map.get_node("RoundManager").clear_local_session()
	multiplayer.multiplayer_peer = null

	# Remove os personagens que ficaram da sessao anterior.
	for player in test_map.get_node("Players").get_children():
		player.queue_free()

	test_map.hide()
	menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_menu_locked(false)

func _enter_map() -> void:
	menu.hide()
	test_map.show()
