extends Node3D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

@onready var players: Node3D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner


func _ready() -> void:
	player_spawner.spawn_path = player_spawner.get_path_to(players)
	player_spawner.spawn_function = _create_player


func add_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if players.has_node(str(peer_id)):
		return

	var slot := players.get_child_count()

	player_spawner.spawn({
		"peer_id": peer_id,
		"position": Vector3(-1.5 + slot, 0.1, 2.0)
	})


func remove_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player := players.get_node_or_null(str(peer_id))

	if player != null:
		player.queue_free()


func _create_player(data: Variant) -> Node:
	var player := PLAYER_SCENE.instantiate()

	player.name = str(data["peer_id"])
	player.position = data["position"]
	player.set_multiplayer_authority(data["peer_id"])

	return player
