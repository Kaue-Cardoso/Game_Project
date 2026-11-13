extends Node

const PORT: int = 7000
const MAX_CLIENTS: int = 3
const GAME_SCENE_PATH: String = "res://scenes/game.tscn"
const MENU_SCENE_PATH: String = "res://scenes/main.tscn"
const CONNECTION_TIMEOUT: float = 10.0

var server_address: String = "127.0.0.1"
var menu_message: String = "Escolha uma opção"

var _pending_peer: ENetMultiplayerPeer
var _game: Node
var _connecting: bool = false
var _connection_time: float = 0.0
var _returning_to_menu: bool = false


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func host_game() -> Error:
	if _pending_peer != null or is_instance_valid(_game) or _returning_to_menu:
		return ERR_BUSY
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		return error
	return _open_game(peer, false)


func join_game(address: String) -> Error:
	if _pending_peer != null or is_instance_valid(_game) or _returning_to_menu:
		return ERR_BUSY
	address = address.strip_edges()
	if address.is_empty():
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)
	if error != OK:
		return error
	server_address = address
	return _open_game(peer, true)


func _open_game(peer: ENetMultiplayerPeer, connecting: bool) -> Error:
	_pending_peer = peer
	_connecting = connecting
	_connection_time = 0.0
	# O caminho é carregado apenas ao entrar; o menu não instancia o mapa.
	var error := get_tree().change_scene_to_file(GAME_SCENE_PATH)
	if error != OK:
		_pending_peer.close()
		_pending_peer = null
		_connecting = false
	return error


func activate_game(game: Node) -> void:
	_game = game
	if _pending_peer == null:
		return_to_menu("Crie uma partida ou entre em um servidor pelo menu.")
		return

	# Só ativamos a rede com o mapa e o MultiplayerSpawner já na árvore.
	# Assim, os personagens recebidos encontram os mesmos caminhos nos peers.
	multiplayer.multiplayer_peer = _pending_peer
	_pending_peer = null
	if multiplayer.is_server():
		_game.test_map.get_node("RoundManager").prepare_new_session()
		_game.test_map.add_player(multiplayer.get_unique_id())
		_game.show_game()
	else:
		_game.show_connection_status("Conectando a %s..." % server_address)


func _process(delta: float) -> void:
	if not _connecting or not is_instance_valid(_game) or _returning_to_menu:
		return
	_connection_time += delta
	if _connection_time >= CONNECTION_TIMEOUT:
		return_to_menu("O servidor não respondeu. Confira o endereço e tente novamente.")


func _on_connected_to_server() -> void:
	if _returning_to_menu or not is_instance_valid(_game):
		return
	_connecting = false
	_game.show_game()


func _on_connection_failed() -> void:
	return_to_menu("Não foi possível conectar. Confira o endereço e o host.")


func _on_server_disconnected() -> void:
	return_to_menu("O host encerrou a partida.")


func _on_peer_connected(peer_id: int) -> void:
	if not _returning_to_menu and multiplayer.is_server() and is_instance_valid(_game):
		_game.test_map.add_player(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not _returning_to_menu and multiplayer.is_server() and is_instance_valid(_game):
		_game.test_map.remove_player(peer_id)


func return_to_menu(message: String = "Escolha uma opção") -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
	_connecting = false
	menu_message = message
	# Sinais de rede podem chegar durante o processamento de pacotes.
	# A troca fica para depois desse processamento.
	_finish_return_to_menu.call_deferred()


func _finish_return_to_menu() -> void:
	var peer := multiplayer.multiplayer_peer
	# Uma sessão offline mantém a API válida enquanto as cenas são trocadas.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if peer is ENetMultiplayerPeer:
		peer.close()
	if _pending_peer != null:
		_pending_peer.close()
		_pending_peer = null
	_game = null
	_connection_time = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var error := get_tree().change_scene_to_file(MENU_SCENE_PATH)
	if error != OK:
		push_error("Não foi possível abrir o menu: %s" % error_string(error))
	_returning_to_menu = false
