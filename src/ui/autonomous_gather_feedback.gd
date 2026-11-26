class_name AutonomousGatherFeedback
extends PanelContainer
## Minimal non-blocking RUX-1 status feedback banner.
## Uses a one-shot Timer and MOUSE_FILTER_IGNORE so it never polls or blocks RTS input.

const AUTO_HIDE_SEC: float = 3.0
const BASE_TOP_OFFSET: float = 14.0
const AVOIDANCE_GAP_PX: float = 8.0

var last_message: String = ""

var _label: Label = null
var _hide_timer: Timer = null
var _top_avoidance_targets: Array[Control] = []
var _bound_viewport: Viewport = null


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	add_theme_stylebox_override(&"panel", HudStyle.create_panel_style())
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END

	var margin := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	add_child(margin)

	_label = Label.new()
	_label.add_theme_color_override(&"font_color", HudStyle.TEXT_PRIMARY_COLOR)
	_label.add_theme_font_size_override(&"font_size", 13)
	margin.add_child(_label)

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = AUTO_HIDE_SEC
	_hide_timer.ignore_time_scale = true
	_hide_timer.timeout.connect(_on_hide_timeout)
	add_child(_hide_timer)

	HudStyle.apply_mouse_filter_ignore_recursive(self)
	_bind_viewport_resize()
	_recenter_top()
	hide()


func _exit_tree() -> void:
	_unbind_viewport_resize()
	unbind_top_avoidance_target()


func bind_top_avoidance_target(target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not _top_avoidance_targets.has(target):
		_top_avoidance_targets.append(target)
		var refresh_cb := Callable(self, "_on_avoidance_target_changed")
		if not target.visibility_changed.is_connected(refresh_cb):
			target.visibility_changed.connect(refresh_cb)
		if not target.resized.is_connected(refresh_cb):
			target.resized.connect(refresh_cb)
		if not target.item_rect_changed.is_connected(refresh_cb):
			target.item_rect_changed.connect(refresh_cb)
		var exit_cb := Callable(self, "_on_avoidance_target_tree_exited").bind(target)
		if not target.tree_exited.is_connected(exit_cb):
			target.tree_exited.connect(exit_cb)
	_recenter_top()


func unbind_top_avoidance_target(target: Control = null) -> void:
	if target == null:
		for existing: Control in _top_avoidance_targets.duplicate():
			_disconnect_avoidance_target(existing)
		_top_avoidance_targets.clear()
	else:
		_disconnect_avoidance_target(target)
		_top_avoidance_targets.erase(target)
	if is_inside_tree():
		_recenter_top()


func get_top_offset() -> float:
	return offset_top


func show_message(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	last_message = text
	if _label != null:
		_label.text = text
	_bind_viewport_resize()
	show()
	reset_size()
	_recenter_top()
	if _hide_timer != null and is_inside_tree():
		_hide_timer.start(AUTO_HIDE_SEC)


func _recenter_top() -> void:
	var min_sz: Vector2 = get_combined_minimum_size()
	var half_w: float = min_sz.x * 0.5
	var top_y: float = _compute_top_offset(min_sz, half_w)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -half_w
	offset_right = half_w
	offset_top = top_y
	offset_bottom = top_y + min_sz.y


func _compute_top_offset(min_sz: Vector2, half_w: float) -> float:
	var top_y: float = BASE_TOP_OFFSET
	var viewport_w: float = get_viewport_rect().size.x if get_viewport() != null else 1280.0
	var center_x: float = viewport_w * 0.5
	var my_left: float = center_x - half_w
	var my_right: float = center_x + half_w

	for target: Control in _top_avoidance_targets:
		if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
			continue
		var target_rect: Rect2 = _resolve_effective_target_rect(target, center_x)
		if target_rect.size.x <= 0.0 or target_rect.size.y <= 0.0:
			continue
		var horiz_overlap: bool = my_right > target_rect.position.x and my_left < target_rect.end.x
		if not horiz_overlap:
			continue
		if target_rect.end.y > top_y and target_rect.position.y < top_y + min_sz.y:
			top_y = maxf(top_y, target_rect.end.y + AVOIDANCE_GAP_PX)
	return top_y


func _resolve_effective_target_rect(target: Control, center_x: float) -> Rect2:
	var rect: Rect2 = target.get_global_rect()
	var min_sz: Vector2 = target.get_combined_minimum_size()
	var eff_w: float = maxf(rect.size.x, min_sz.x)
	var eff_h: float = maxf(rect.size.y, min_sz.y)
	var pos: Vector2 = rect.position
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		if is_equal_approx(target.anchor_left, 0.5):
			pos.x = center_x + target.offset_left
			eff_w = maxf(eff_w, target.offset_right - target.offset_left)
		else:
			pos.x = target.offset_left
		pos.y = target.offset_top
		eff_h = maxf(eff_h, target.offset_bottom - target.offset_top)
	return Rect2(pos, Vector2(eff_w, eff_h))


func _bind_viewport_resize() -> void:
	var vp: Viewport = get_viewport()
	if vp == _bound_viewport:
		return
	_unbind_viewport_resize()
	if vp != null and is_instance_valid(vp):
		_bound_viewport = vp
		if not _bound_viewport.size_changed.is_connected(_on_avoidance_target_changed):
			_bound_viewport.size_changed.connect(_on_avoidance_target_changed)


func _unbind_viewport_resize() -> void:
	if _bound_viewport != null and is_instance_valid(_bound_viewport):
		if _bound_viewport.size_changed.is_connected(_on_avoidance_target_changed):
			_bound_viewport.size_changed.disconnect(_on_avoidance_target_changed)
	_bound_viewport = null


func _disconnect_avoidance_target(target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	var refresh_cb := Callable(self, "_on_avoidance_target_changed")
	if target.visibility_changed.is_connected(refresh_cb):
		target.visibility_changed.disconnect(refresh_cb)
	if target.resized.is_connected(refresh_cb):
		target.resized.disconnect(refresh_cb)
	if target.item_rect_changed.is_connected(refresh_cb):
		target.item_rect_changed.disconnect(refresh_cb)
	var exit_cb := Callable(self, "_on_avoidance_target_tree_exited").bind(target)
	if target.tree_exited.is_connected(exit_cb):
		target.tree_exited.disconnect(exit_cb)


func _on_avoidance_target_changed() -> void:
	if is_inside_tree():
		_recenter_top()


func _on_avoidance_target_tree_exited(target: Control) -> void:
	unbind_top_avoidance_target(target)


func _on_hide_timeout() -> void:
	hide()
