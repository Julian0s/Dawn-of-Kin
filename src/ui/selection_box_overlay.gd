class_name SelectionBoxOverlay
extends Control
## Non-blocking UI overlay that renders the active RTS box-selection rectangle.
## Uses mouse_filter = IGNORE so it never intercepts mouse input or DebugOverlay.

const FILL_COLOR: Color = Color(0.90, 0.76, 0.30, 0.14)
const BORDER_COLOR: Color = Color(0.92, 0.78, 0.34, 0.86)
const SOURCE_FILL_COLOR: Color = Color(0.62, 0.82, 0.46, 0.14)
const SOURCE_BORDER_COLOR: Color = Color(0.875, 0.737, 0.447, 0.90)
const BASE_BORDER_WIDTH_PX: float = 1.5

var _box_active: bool = false
var _box_rect: Rect2 = Rect2()
var _is_source_mode: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _draw() -> void:
	if not _box_active:
		return
	if _box_rect.size.x < 1.0 and _box_rect.size.y < 1.0:
		return

	var border_width: float = BASE_BORDER_WIDTH_PX * CameraMath.get_dpi_scale(DisplayServer.screen_get_dpi())
	var fill_col: Color = SOURCE_FILL_COLOR if _is_source_mode else FILL_COLOR
	var border_col: Color = SOURCE_BORDER_COLOR if _is_source_mode else BORDER_COLOR
	draw_rect(_box_rect, fill_col, true)
	draw_rect(_box_rect, border_col, false, border_width)


func set_box_style(is_source_mode: bool) -> void:
	if _is_source_mode == is_source_mode:
		return
	_is_source_mode = is_source_mode
	if _box_active:
		queue_redraw()


func is_source_mode() -> bool:
	return _is_source_mode


func set_selection_box(start_pos: Vector2, current_pos: Vector2) -> void:
	_box_rect = SelectionBoxMath.normalize_rect(start_pos, current_pos)
	_box_active = true
	visible = true
	queue_redraw()


func clear_selection_box() -> void:
	_is_source_mode = false
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
