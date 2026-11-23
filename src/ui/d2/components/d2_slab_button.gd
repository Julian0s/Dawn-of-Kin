class_name D2SlabButton
extends BaseButton
## Native Godot BaseButton for Dawn of Kin D2.2 interactive surfaces and controls.
## Supports both polygonal stone silhouettes (via _has_point + Geometry2D.is_point_in_polygon)
## and crisp bordered D2.2 plaque controls (such as || and 1x).
## Prevents keyboard focus capture (FOCUS_NONE) and blocks right-click/middle-click/scroll
## leakage to the RTS world (mouse_force_pass_scroll_events = false + accept_event()).

var _base_polygon: PackedVector2Array = PackedVector2Array()
var _base_content_size: Vector2 = Vector2.ZERO
var _shadow_pad: float = 0.0
var _scaled_polygon: PackedVector2Array = PackedVector2Array()

var _is_active_state: bool = false
var _is_external_pause_indicator: bool = false
var _is_hovered_visual: bool = false
var _label: Label = null

var _normal_fill: Color = D2Tokens.COLOR_TIME_BTN_NORMAL_FILL
var _normal_border: Color = D2Tokens.COLOR_TIME_BTN_NORMAL_BORDER
var _hover_fill: Color = D2Tokens.COLOR_TIME_BTN_HOVER_FILL
var _hover_border: Color = D2Tokens.COLOR_TIME_BTN_HOVER_BORDER
var _active_fill: Color = D2Tokens.COLOR_TIME_BTN_ACTIVE_FILL
var _active_border: Color = D2Tokens.COLOR_TIME_BTN_ACTIVE_BORDER
var _pressed_fill: Color = D2Tokens.COLOR_TIME_BTN_PRESSED_FILL
var _disabled_fill: Color = D2Tokens.COLOR_DISABLED_FILL
var _disabled_border: Color = D2Tokens.COLOR_DISABLED_BORDER
var _normal_text_color: Color = D2Tokens.COLOR_TEXT_PRIMARY_IVORY
var _disabled_text_color: Color = D2Tokens.COLOR_DISABLED_TEXT
var _font_regular: Font = null
var _font_bold: Font = null
var _font_size: int = 11


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	focus_mode = Control.FOCUS_NONE
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	button_mask = MOUSE_BUTTON_MASK_LEFT
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	_ensure_label()
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not button_down.is_connected(_on_button_state_changed):
		button_down.connect(_on_button_state_changed)
	if not button_up.is_connected(_on_button_state_changed):
		button_up.connect(_on_button_state_changed)
	_sync_visuals()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_rebuild_scaled_polygon()
		if _label != null:
			_label.size = size
		queue_redraw()


func configure_polygon(
	content_polygon: Array[Vector2],
	content_size: Vector2,
	shadow_pad: float = D2Tokens.ATLAS_SHADOW_PAD
) -> void:
	_base_polygon = PackedVector2Array(content_polygon)
	_base_content_size = content_size
	_shadow_pad = maxf(0.0, shadow_pad)
	_rebuild_scaled_polygon()
	queue_redraw()


func clear_polygon() -> void:
	_base_polygon = PackedVector2Array()
	_scaled_polygon = PackedVector2Array()
	queue_redraw()


func set_scaled_size(target_size: Vector2) -> void:
	custom_minimum_size = target_size
	size = target_size
	if _label != null:
		_label.size = target_size
	_rebuild_scaled_polygon()
	queue_redraw()


func set_label_text(text_value: String) -> void:
	_ensure_label()
	_label.text = text_value


func get_label_text() -> String:
	return _label.text if _label != null else ""


func apply_typography(font_regular: Font, font_bold: Font, font_size: int) -> void:
	_font_regular = font_regular
	_font_bold = font_bold
	_font_size = maxi(9, font_size)
	_sync_visuals()


func set_active_state(active: bool) -> void:
	if _is_active_state == active:
		return
	_is_active_state = active
	_sync_visuals()


func is_active_state() -> bool:
	return _is_active_state


func set_external_pause_indicator(active: bool) -> void:
	if _is_external_pause_indicator == active:
		return
	_is_external_pause_indicator = active
	_sync_visuals()


func is_external_pause_indicator() -> bool:
	return _is_external_pause_indicator


func set_interactive_enabled(enabled: bool) -> void:
	disabled = not enabled
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	if disabled:
		_is_hovered_visual = false
	_sync_visuals()


func _has_point(point: Vector2) -> bool:
	if _scaled_polygon.size() < 3:
		return Rect2(Vector2.ZERO, size).has_point(point)
	return Geometry2D.is_point_in_polygon(point, _scaled_polygon)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		# Consume right-click, middle-click, scroll wheel, or clicks while disabled
		# so zero RTS commands or camera zoom ever leak through the control.
		if disabled or mb.button_index != MOUSE_BUTTON_LEFT:
			accept_event()


func _draw() -> void:
	var fill: Color = _normal_fill
	var border: Color = _normal_border
	if disabled:
		if _is_external_pause_indicator:
			fill = D2Tokens.COLOR_TIME_BTN_EXTERNAL_PAUSE_FILL
			border = D2Tokens.COLOR_TIME_BTN_EXTERNAL_PAUSE_BORDER
		else:
			fill = _disabled_fill
			border = _disabled_border
	elif is_pressed():
		fill = _pressed_fill
		border = _hover_border
	elif _is_active_state:
		fill = _active_fill
		border = _active_border
	elif _is_external_pause_indicator:
		fill = D2Tokens.COLOR_TIME_BTN_EXTERNAL_PAUSE_FILL
		border = D2Tokens.COLOR_TIME_BTN_EXTERNAL_PAUSE_BORDER
	elif _is_hovered_visual:
		fill = _hover_fill
		border = _hover_border

	if _scaled_polygon.size() >= 3:
		draw_colored_polygon(_scaled_polygon, fill)
		var outline := PackedVector2Array(_scaled_polygon)
		outline.append(_scaled_polygon[0])
		draw_polyline(outline, border, 1.0, true)
	else:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, fill, true)
		draw_rect(rect, border, false, 1.0)


func contains_local_point(local_point: Vector2) -> bool:
	return _has_point(local_point)


func contains_global_point(global_point: Vector2) -> bool:
	var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * global_point
	return _has_point(local_point)


func get_scaled_polygon() -> PackedVector2Array:
	return _scaled_polygon.duplicate()


func get_global_polygon() -> PackedVector2Array:
	var result := PackedVector2Array()
	var xform: Transform2D = get_global_transform_with_canvas()
	if _scaled_polygon.size() >= 3:
		result.resize(_scaled_polygon.size())
		for i: int in range(_scaled_polygon.size()):
			result[i] = xform * _scaled_polygon[i]
	else:
		result = PackedVector2Array([
			xform * Vector2(0.0, 0.0),
			xform * Vector2(size.x, 0.0),
			xform * Vector2(size.x, size.y),
			xform * Vector2(0.0, size.y),
		])
	return result


func _ensure_label() -> void:
	if _label != null and is_instance_valid(_label):
		return
	_label = Label.new()
	_label.name = "ButtonLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2.ZERO
	_label.size = size
	add_child(_label)


func _sync_visuals() -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	if _label != null and is_instance_valid(_label):
		var text_col: Color = _normal_text_color
		if disabled:
			text_col = D2Tokens.COLOR_FEEDBACK_AMBER if _is_external_pause_indicator else _disabled_text_color
		elif _is_external_pause_indicator and not _is_active_state:
			text_col = D2Tokens.COLOR_FEEDBACK_AMBER
		_label.add_theme_color_override(&"font_color", text_col)
		_label.add_theme_font_size_override(&"font_size", _font_size)
		var use_bold: bool = _is_active_state or _is_external_pause_indicator
		var font_choice: Font = _font_bold if (use_bold and _font_bold != null) else _font_regular
		if font_choice != null:
			_label.add_theme_font_override(&"font", font_choice)
	queue_redraw()


func _on_mouse_entered() -> void:
	if not disabled:
		_is_hovered_visual = true
		queue_redraw()


func _on_mouse_exited() -> void:
	_is_hovered_visual = false
	queue_redraw()


func _on_button_state_changed() -> void:
	queue_redraw()


func _rebuild_scaled_polygon() -> void:
	if _base_polygon.size() < 3:
		_scaled_polygon = PackedVector2Array()
		return
	var base_total_w: float = _base_content_size.x + 2.0 * _shadow_pad
	var base_total_h: float = _base_content_size.y + 2.0 * _shadow_pad
	if base_total_w <= 0.0 or base_total_h <= 0.0:
		_scaled_polygon = PackedVector2Array()
		return
	var target_w: float = size.x if size.x > 0.0 else base_total_w
	var target_h: float = size.y if size.y > 0.0 else base_total_h
	var sx: float = target_w / base_total_w
	var sy: float = target_h / base_total_h
	var rebuilt := PackedVector2Array()
	rebuilt.resize(_base_polygon.size())
	for i: int in range(_base_polygon.size()):
		var pt: Vector2 = _base_polygon[i]
		rebuilt[i] = Vector2((pt.x + _shadow_pad) * sx, (pt.y + _shadow_pad) * sy)
	_scaled_polygon = rebuilt
