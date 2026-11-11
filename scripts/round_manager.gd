extends Node

enum Phase { WAITING, ACTIVE, FINISHED, RESETTING }

@export_range(1, 100000, 1) var target_credits: int = 150
@export_range(1.0, 3600.0, 1.0) var round_duration: float = 180.0
@export var phase: Phase = Phase.WAITING
@export var time_left: float = 0.0
@export var goal_met: bool = false

@onready var map: Node3D = get_parent() as Node3D
@onready var players: Node3D = $"../Players"
@onready var extraction: Node = $"../ExtractionZone"
@onready var hud: CanvasLayer = $RoundHUD
@onready var state_label: Label = $RoundHUD/Panel/VBoxContainer/StateLabel
@onready var summary: Label = $RoundHUD/Panel/VBoxContainer/Summary
@onready var start_button: Button = $RoundHUD/Panel/VBoxContainer/StartButton

var local_play_allowed: bool = false
var previous_local_active: bool = false
var reset_epoch: int = 0
var pending_reset_peers: Array[int] = []


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.is_server():
		extraction.accepting_deliveries = false


func is_active() -> bool:
	return phase == Phase.ACTIVE and local_play_allowed


func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	if phase == Phase.WAITING:
		request_start()
	elif phase == Phase.FINISHED:
		request_new_round()


func request_start() -> void:
	if not multiplayer.is_server() or phase != Phase.WAITING:
		return
	if players.get_child_count() == 0:
		return

	extraction.team_credits = 0
	extraction.delivered_count = 0
	goal_met = false
	time_left = round_duration
	phase = Phase.ACTIVE
	extraction.accepting_deliveries = true
	_set_controls_allowed.rpc(true)


@rpc("authority", "call_local", "reliable")
func _set_controls_allowed(allowed: bool) -> void:
	local_play_allowed = allowed
	if not allowed:
		previous_local_active = false


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not is_active():
		return
	if not map.is_visible_in_tree():
		return

	time_left = maxf(0.0, time_left - delta)
	if extraction.team_credits >= target_credits:
		_finish(true)
	elif time_left <= 0.0:
		_finish(false)


func _finish(success: bool) -> void:
	goal_met = success
	phase = Phase.FINISHED
	extraction.accepting_deliveries = false
	_set_controls_allowed.rpc(false)


func request_new_round() -> void:
	if not multiplayer.is_server() or phase != Phase.FINISHED:
		return

	phase = Phase.RESETTING
	_set_controls_allowed.rpc(false)
	reset_epoch += 1
	pending_reset_peers.clear()
	pending_reset_peers.append(multiplayer.get_unique_id())
	for peer_id in multiplayer.get_peers():
		pending_reset_peers.append(peer_id)

	_reset_world()
	_restore_local_player.rpc(reset_epoch)


func _reset_world() -> void:
	extraction.accepting_deliveries = false
	for item in get_tree().get_nodes_in_group("collectible_items"):
		if item.get_parent() == map:
			item.reset_for_round()
	for player in players.get_children():
		if not player.is_queued_for_deletion():
			player.get_node("Vitals").reset_for_round()
	extraction.team_credits = 0
	extraction.delivered_count = 0
	goal_met = false
	time_left = 0.0


@rpc("authority", "call_local", "reliable")
func _restore_local_player(epoch: int) -> void:
	local_play_allowed = false
	previous_local_active = false
	var local_id: int = multiplayer.get_unique_id()
	var player: Node = players.get_node_or_null(str(local_id))

	# Quem acabou de conectar pode ainda estar recebendo seu personagem.
	while player == null or player.is_queued_for_deletion():
		await get_tree().process_frame
		if multiplayer.get_unique_id() != local_id:
			return
		if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		player = players.get_node_or_null(str(local_id))

	player.reset_for_round()
	await get_tree().physics_frame
	if multiplayer.get_unique_id() != local_id:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_confirm_reset.rpc_id(1, epoch)


@rpc("any_peer", "call_local", "reliable")
func _confirm_reset(epoch: int) -> void:
	if not multiplayer.is_server() or phase != Phase.RESETTING:
		return
	if epoch != reset_epoch:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not pending_reset_peers.has(sender):
		return
	pending_reset_peers.erase(sender)
	_finish_reset_if_ready()


func _finish_reset_if_ready() -> void:
	if phase == Phase.RESETTING and pending_reset_peers.is_empty():
		phase = Phase.WAITING


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if phase == Phase.RESETTING:
		if not pending_reset_peers.has(peer_id):
			pending_reset_peers.append(peer_id)
		_restore_local_player.rpc_id(peer_id, reset_epoch)
	else:
		_set_controls_allowed.rpc_id(peer_id, phase == Phase.ACTIVE)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	pending_reset_peers.erase(peer_id)
	_finish_reset_if_ready()


func prepare_new_session() -> void:
	if not multiplayer.is_server():
		return
	phase = Phase.WAITING
	reset_epoch = 0
	pending_reset_peers.clear()
	clear_local_session()
	_reset_world()


func clear_local_session() -> void:
	local_play_allowed = false
	previous_local_active = false


func _process(_delta: float) -> void:
	hud.visible = map.is_visible_in_tree()
	if not hud.visible:
		previous_local_active = false
		return

	start_button.visible = phase == Phase.WAITING or phase == Phase.FINISHED
	start_button.disabled = not multiplayer.is_server()
	if not multiplayer.is_server():
		start_button.text = "Aguardando o host"
	else:
		start_button.text = "Nova rodada" if phase == Phase.FINISHED else "Iniciar missão"

	match phase:
		Phase.WAITING:
			state_label.text = "Aguardando início"
			summary.text = "Meta: %d créditos\nDuração: %d segundos" % [
				target_credits, roundi(round_duration)
			]
		Phase.ACTIVE:
			state_label.text = "Missão em andamento"
			summary.text = "Meta: %d | Entregue: %d\nTempo: %d segundos" % [
				target_credits, extraction.team_credits, ceili(time_left)
			]
		Phase.FINISHED:
			state_label.text = "Meta alcançada!" if goal_met else "Tempo esgotado"
			summary.text = "Resultado: %d créditos\nObjetos entregues: %d" % [
				extraction.team_credits, extraction.delivered_count
			]
		Phase.RESETTING:
			state_label.text = "Preparando nova rodada"
			summary.text = "Aguardando os jogadores..."

	for player in players.get_children():
		if not player.is_multiplayer_authority() or player.is_queued_for_deletion():
			continue
		var active: bool = is_active()
		if not active:
			var backpack_ui: Node = player.get_node("BackpackUI")
			if backpack_ui.is_open:
				backpack_ui.close_menu(false)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif not previous_local_active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		previous_local_active = active
		break
