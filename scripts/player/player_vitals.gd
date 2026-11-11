extends Node

@export_group("Carga")
@export_range(0.1, 1000.0, 0.1) var max_carry_weight_kg: float = 40.0
@export_range(0.0, 0.95, 0.01) var speed_penalty_at_capacity: float = 0.35
@export_range(0.05, 1.0, 0.01) var minimum_speed_factor: float = 0.35

@export_group("Sprint e stamina")
@export_range(1.0, 3.0, 0.05) var sprint_multiplier: float = 1.6
@export_range(1.0, 1000.0, 1.0) var max_stamina: float = 100.0
@export_range(0.0, 1000.0, 0.5) var stamina_drain_per_second: float = 25.0
@export_range(0.0, 1000.0, 0.5) var stamina_recovery_per_second: float = 20.0
@export_range(0.0, 10.0, 0.1) var recovery_delay: float = 1.0
@export_range(0.0, 1000.0, 1.0) var stamina_to_resume: float = 20.0

@export_group("Estado recebido do servidor")
@export var carried_weight_kg: float = 0.0
@export var current_stamina: float = 100.0
@export var is_sprinting: bool = false
@export var sprint_exhausted: bool = false

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var inventory: Node = $"../Inventory"
@onready var load_label: Label = $"../InventoryHUD/Status/LoadLabel"
@onready var stamina_label: Label = $"../InventoryHUD/Status/StaminaLabel"
@onready var stamina_bar: ProgressBar = $"../InventoryHUD/Status/StaminaBar"
@onready var movement_label: Label = $"../InventoryHUD/Status/MovementLabel"

var _wants_sprint: bool = false
var _moving: bool = false
var _controls_enabled: bool = false
var _input_age: float = 1.0
var _recovery_remaining: float = 0.0
var _last_sent_state := Vector3i(-1, -1, -1)
var _last_sent_msec: int = -1000


func _enter_tree() -> void:
	# O personagem pertence ao jogador; este componente e seu sincronizador,
	# ao servidor. A atribuicao acontece antes de os filhos entrarem na arvore.
	set_multiplayer_authority(1)


func _ready() -> void:
	if multiplayer.is_server():
		current_stamina = max_stamina
	set_process(player.is_multiplayer_authority())


func submit_movement_input(wants_sprint: bool, moving: bool, controls_enabled: bool) -> void:
	if not player.is_multiplayer_authority():
		return
	if multiplayer.is_server():
		request_movement_state(wants_sprint, moving, controls_enabled)
		return
	var state := Vector3i(int(wants_sprint), int(moving), int(controls_enabled))
	var now := Time.get_ticks_msec()
	if state != _last_sent_state or now - _last_sent_msec >= 200:
		_last_sent_state = state
		_last_sent_msec = now
		request_movement_state.rpc_id(1, wants_sprint, moving, controls_enabled)


@rpc("any_peer", "call_local", "reliable")
func request_movement_state(wants_sprint: bool, moving: bool, controls_enabled: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != player.get_multiplayer_authority():
		return
	_wants_sprint = wants_sprint
	_moving = moving
	_controls_enabled = controls_enabled
	_input_age = 0.0


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	carried_weight_kg = inventory.get_total_weight_kg()
	current_stamina = clampf(current_stamina, 0.0, max_stamina)
	_input_age += delta
	if sprint_exhausted and current_stamina >= minf(stamina_to_resume, max_stamina):
		sprint_exhausted = false

	is_sprinting = (
		player.is_round_active()
		and _input_age <= 0.75 and _controls_enabled and _moving and _wants_sprint
		and not is_over_capacity() and not sprint_exhausted and current_stamina > 0.0
	)
	if is_sprinting:
		current_stamina = maxf(0.0, current_stamina - stamina_drain_per_second * delta)
		_recovery_remaining = recovery_delay
		if current_stamina <= 0.0:
			sprint_exhausted = true
			is_sprinting = false
	else:
		_recovery_remaining = maxf(0.0, _recovery_remaining - delta)
		if _recovery_remaining <= 0.0:
			current_stamina = minf(max_stamina, current_stamina + stamina_recovery_per_second * delta)


func is_over_capacity() -> bool:
	# Tolerancia apenas para arredondamento na soma dos pesos.
	return carried_weight_kg > max_carry_weight_kg + 0.0001


func get_weight_speed_factor() -> float:
	var ratio := carried_weight_kg / maxf(max_carry_weight_kg, 0.1)
	return clampf(1.0 - ratio * speed_penalty_at_capacity, minimum_speed_factor, 1.0)


func get_speed_factor(wants_sprint: bool = true) -> float:
	var sprint_allowed := is_sprinting and wants_sprint and not is_over_capacity() and not sprint_exhausted
	return get_weight_speed_factor() * (sprint_multiplier if sprint_allowed else 1.0)


func get_load_text() -> String:
	return ("Carga: %.1f / %.1f kg" % [carried_weight_kg, max_carry_weight_kg]).replace(".", ",")


func _process(_delta: float) -> void:
	load_label.text = get_load_text()
	load_label.modulate = Color(1.0, 0.65, 0.3) if is_over_capacity() else Color.WHITE
	stamina_label.text = "Stamina: %d / %d" % [roundi(current_stamina), roundi(max_stamina)]
	stamina_bar.max_value = max_stamina
	stamina_bar.value = current_stamina
	if is_over_capacity():
		movement_label.text = "Sobrecarga: sprint bloqueado"
	elif sprint_exhausted:
		movement_label.text = "Sem fôlego: recuperando stamina"
	elif is_sprinting:
		movement_label.text = "Correndo"
	else:
		movement_label.text = "Caminhando — Shift para correr"


func reset_for_round() -> void:
	_last_sent_state = Vector3i(-1, -1, -1)
	_last_sent_msec = -1000

	if not multiplayer.is_server():
		return

	carried_weight_kg = 0.0
	current_stamina = max_stamina
	is_sprinting = false
	sprint_exhausted = false
	_wants_sprint = false
	_moving = false
	_controls_enabled = false
	_input_age = 1.0
	_recovery_remaining = 0.0
