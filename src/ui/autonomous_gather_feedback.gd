class_name AutonomousGatherFeedback
extends PanelContainer
## Minimal non-blocking RUX-1 status feedback banner.
## Uses a one-shot Timer and MOUSE_FILTER_IGNORE so it never polls or blocks RTS input.

const AUTO_HIDE_SEC: float = 3.0

var last_message: String = ""

var _label: Label = null
var _hide_timer: Timer = null


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
	_recenter_top()
	hide()


func show_message(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	last_message = text
	if _label != null:
		_label.text = text
	show()
	reset_size()
	_recenter_top()
	if _hide_timer != null and is_inside_tree():
		_hide_timer.start(AUTO_HIDE_SEC)


func _recenter_top() -> void:
	var min_sz: Vector2 = get_combined_minimum_size()
	var half_w: float = min_sz.x * 0.5
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -half_w
	offset_right = half_w
	offset_top = 14.0
	offset_bottom = 14.0 + min_sz.y


func _on_hide_timeout() -> void:
	hide()
