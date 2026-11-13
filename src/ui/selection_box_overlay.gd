class_name SelectionBoxOverlay
extends Control
## Non-blocking UI overlay that renders the active RTS box-selection rectangle.
## Uses mouse_filter = IGNORE so it never intercepts mouse input or DebugOverlay.

const FILL_COLOR: Color = Color(0.90, 0.76, 0.30, 0.14)
const BORDER_COLOR: Color = Color(0.92, 0.78, 0.34, 0.86)
const BASE_BORDER_WIDTH_PX: float = 1.5

var _box_active: bool = false
var _box_rect: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _draw() -> void:
	if not _box_active:
		return
	if _box_rect.size.x < 1.0 and _box_rect.size.y < 1.0:
		return

	var border_width: float = BASE_BORDER_WIDTH_PX * CameraMath.get_dpi_scale(DisplayServer.screen_get_dpi())
	draw_rect(_box_rect, FILL_COLOR, true)
	draw_rect(_box_rect, BORDER_COLOR, false, border_width)


func set_selection_box(start_pos: Vector2, current_pos: Vector2) -> void:
	_box_rect = SelectionBoxMath.normalize_rect(start_pos, current_pos)
	_box_active = true
	visible = true
	queue_redraw()


func clear_selection_box() -> void:
	if not _box_active and not visible:
		return
	_box_active = false
	_box_rect = Rect2()
	visible = false
	queue_redraw()


func is_box_active() -> bool:
	return _box_active


func get_box_rect() -> Rect2:
	return _box_rect
