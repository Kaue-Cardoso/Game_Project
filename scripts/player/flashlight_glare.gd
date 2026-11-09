extends CanvasLayer

@export_range(0.0, 1.0) var max_strength: float = 0.8
@export var max_distance: float = 12.0
@export var appear_speed: float = 8.0
@export var recovery_speed: float = 2.5

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var camera: Camera3D = player.get_node("Head/Camera3D")
@onready var overlay: ColorRect = $Overlay

var effect_material: ShaderMaterial
var current_strength: float = 0.0


func _ready() -> void:
	if not player.is_multiplayer_authority():
		overlay.hide()
		set_physics_process(false)
		return

	# Cada jogador usa sua propria copia do material.
	effect_material = overlay.material.duplicate() as ShaderMaterial
	overlay.material = effect_material
	effect_material.set_shader_parameter("strength", 0.0)


func _physics_process(delta: float) -> void:
	var target_strength: float = 0.0
	var best_position := Vector3.ZERO
	var best_color := Color.WHITE
	var eye_position := camera.global_position
	var camera_forward := -camera.global_transform.basis.z.normalized()

	for item in get_tree().get_nodes_in_group("flashlight_items"):
		if not item.get("is_on"):
			continue

		var holder_id: int = int(item.get("holder_peer_id"))
		if holder_id == 0 or holder_id == multiplayer.get_unique_id():
			continue

		var spot: SpotLight3D = item.get_node("SpotLight3D")
		var light_position := spot.global_position
		var light_to_eye := eye_position - light_position
		var distance := light_to_eye.length()
		var reach := minf(max_distance, spot.spot_range)

		if distance < 0.01 or distance >= reach:
			continue
		if camera.is_position_behind(light_position):
			continue

		var direction_to_eye := light_to_eye / distance
		var beam_forward := -spot.global_transform.basis.z.normalized()

		# Estamos dentro do cone iluminado?
		var beam_factor := smoothstep(
			cos(deg_to_rad(spot.spot_angle)),
			cos(deg_to_rad(spot.spot_angle * 0.35)),
			beam_forward.dot(direction_to_eye)
		)

		# Estamos olhando na direcao da fonte?
		var look_factor := smoothstep(
			cos(deg_to_rad(65.0)),
			cos(deg_to_rad(12.0)),
			camera_forward.dot(-direction_to_eye)
		)

		var distance_factor := 1.0 - smoothstep(0.0, reach, distance)
		var energy_factor := clampf(spot.light_energy / 2.0, 0.0, 1.0)
		var intensity := (
			beam_factor * look_factor * distance_factor
			* energy_factor * max_strength
		)

		if intensity <= target_strength:
			continue

		var query := PhysicsRayQueryParameters3D.create(
			eye_position, light_position
		)
		query.collision_mask = 1
		query.collide_with_areas = false

		var excluded: Array[RID] = [player.get_rid()]
		var holder: CollisionObject3D = item.get_parent().get_node_or_null(
			"Players/" + str(holder_id)
		) as CollisionObject3D
		if holder != null:
			excluded.append(holder.get_rid())
		query.exclude = excluded

		var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			continue

		target_strength = intensity
		best_position = light_position
		best_color = spot.light_color

	var speed := appear_speed if target_strength > current_strength else recovery_speed
	current_strength = move_toward(current_strength, target_strength, speed * delta)

	effect_material.set_shader_parameter("strength", current_strength)

	if target_strength > 0.0:
		var screen_size := camera.get_viewport().get_visible_rect().size
		var source_uv := camera.unproject_position(best_position) / screen_size
		effect_material.set_shader_parameter("source_uv", source_uv)
		effect_material.set_shader_parameter("aspect_ratio", screen_size.x / screen_size.y)
		effect_material.set_shader_parameter("glare_color", best_color)
