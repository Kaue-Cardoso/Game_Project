extends CharacterBody3D

const CollectibleItem = preload("res://scripts/items/collectible_item.gd")

@export var move_speed: float = 4.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

@onready var inventory: Node = $Inventory
@onready var backpack_ui: CanvasLayer = $BackpackUI
@onready var vitals: Node = $Vitals
@onready var head: Node3D = $Head
@onready var hand_socket: Marker3D = $Head/Camera3D/HandSocket
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay

var round_spawn_transform: Transform3D

var equipped_item: CollectibleItem:
	get:
		return inventory.get_item_in_slot(inventory.active_hand) as CollectibleItem

var interaction_requested: bool = false


func _ready() -> void:
	round_spawn_transform = global_transform
	var local_player := is_multiplayer_authority()

	$Head/Camera3D.current = local_player
	$MeshInstance3D.visible = not local_player

	interaction_ray.add_exception(self)

	if local_player:
		Input.mouse_mode = (
			Input.MOUSE_MODE_CAPTURED
			if is_round_active()
			else Input.MOUSE_MODE_VISIBLE
		)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	if not is_round_active():
		return
		
	if backpack_ui.is_open:
		return
		
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event.is_action_pressed("open_backpack") and not event.is_echo():
		var item := equipped_item
		if item != null and backpack_ui.open_menu(item):
			get_viewport().set_input_as_handled()
		return
		
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not event.is_echo():
		if event.is_action_pressed("switch_hand"):
			inventory.toggle_active_hand()
			return

		for slot_index in range(4):
			if event.is_action_pressed("slot_%d" % (slot_index + 1)):
				inventory.select_slot(slot_index)
				return

		if event.is_action_pressed("inventory_next"):
			inventory.cycle_slot(1)
			return

		if event.is_action_pressed("inventory_previous"):
			inventory.cycle_slot(-1)
			return

	if event.is_action_pressed("drop_item") and not event.is_echo():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if is_instance_valid(equipped_item):
				equipped_item.request_drop.rpc_id(1)

	if event.is_action_pressed("toggle_flashlight") and not event.is_echo():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if is_instance_valid(equipped_item):
				equipped_item.request_use.rpc_id(1)

	if event.is_action_pressed("interact") and not event.is_echo():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			interaction_requested = true

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-event.relative.x * mouse_sensitivity)
			head.rotate_x(-event.relative.y * mouse_sensitivity)
			head.rotation.x = clampf(
				head.rotation.x,
				deg_to_rad(-85.0),
				deg_to_rad(85.0)
			)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
		
	if interaction_requested:
		interaction_requested = false
		if is_round_active() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not backpack_ui.is_open:
			try_pick_up()

	if not is_on_floor():
		velocity += get_gravity() * delta

	var controls_enabled: bool = (
		is_round_active()
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and not backpack_ui.is_open
	)

	var input_direction := Vector2.ZERO
	if controls_enabled:
		input_direction = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_back"
		)
	var wants_sprint: bool = controls_enabled and Input.is_action_pressed("sprint")
	vitals.submit_movement_input(wants_sprint, not input_direction.is_zero_approx(), controls_enabled)

	if controls_enabled:
		var direction := transform.basis * Vector3(
			input_direction.x,
			0.0,
			input_direction.y
		)

		var current_speed: float = move_speed * vitals.get_speed_factor(wants_sprint)
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


func try_pick_up() -> void:

	interaction_ray.force_raycast_update()
	if not interaction_ray.is_colliding():
		return

	var collider := interaction_ray.get_collider()
	if collider is Area3D:
		var item: Node = collider.get_parent()
		if item is CollectibleItem:
			item.request_pickup.rpc_id(1)

func is_round_active() -> bool:
	var manager: Node = get_parent().get_parent().get_node_or_null("RoundManager")
	return manager == null or manager.is_active()


func reset_for_round() -> void:
	if not is_multiplayer_authority():
		return

	if backpack_ui.is_open:
		backpack_ui.close_menu(false)

	interaction_requested = false
	velocity = Vector3.ZERO
	global_transform = round_spawn_transform
	head.rotation = Vector3.ZERO
	inventory.active_hand = 0
	inventory.selection_cursor = 0
	vitals.reset_for_round()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
