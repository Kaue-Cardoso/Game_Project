class_name ItemData
extends Resource

enum Size {
	SMALL,
	MEDIUM,
	LARGE
}

@export var display_name: String = "Item"
@export var size: Size = Size.SMALL
@export_range(0.0, 10000.0, 0.1) var weight_kg: float = 1.0
@export_range(0, 1000000, 1) var sale_value: int = 0
