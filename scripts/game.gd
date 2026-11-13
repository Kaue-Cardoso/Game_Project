extends Node

@onready var test_map: Node3D = $TestMap
@onready var connection_hud: CanvasLayer = $ConnectionHUD
@onready var connection_label: Label = $ConnectionHUD/CenterContainer/Panel/VBoxContainer/StatusLabel
@onready var cancel_button: Button = $ConnectionHUD/CenterContainer/Panel/VBoxContainer/CancelButton


func _ready() -> void:
	test_map.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cancel_button.pressed.connect(_on_cancel_pressed)
	Session.activate_game(self)


func show_connection_status(message: String) -> void:
	test_map.hide()
	connection_label.text = message
	connection_hud.show()


func show_game() -> void:
	connection_hud.hide()
	test_map.show()


func _on_cancel_pressed() -> void:
	Session.return_to_menu("Conexão cancelada.")
