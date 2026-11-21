class_name AutonomousGatherFeedback
extends PanelContainer
## Minimal non-blocking RUX-1 status feedback banner (stub for RED phase).

var last_message: String = ""


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func show_message(text: String) -> void:
	last_message = text
