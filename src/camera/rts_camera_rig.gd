class_name RtsCameraRig
extends Node3D
## Isometric perspective RTS camera rig with decoupled Yaw/Pitch/Camera pivots.
## Uses unscaled real-time delta so camera movement remains responsive regardless
## of Engine.time_scale or SceneTree pause state.

const MAX_REAL_DELTA_SEC: float = 0.1
const ZOOM_SNAP_EPSILON: float = 0.001

@export_group("Projection")
@export var fov_degrees: float = 35.0
@export var pitch_degrees: float = 55.0
@export var yaw_degrees: float = 45.0

@export_group("Zoom")
@export var min_distance: float = 22.0
@export var max_distance: float = 58.0
@export var default_distance: float = 36.0
@export var zoom_step: float = 4.0
@export var zoom_smoothing: float = 12.0

@export_group("Movement")
@export var base_pan_speed: float = 24.0
@export var reference_distance: float = 36.0
@export var pan_smoothing: float = 16.0
@export var edge_pan_enabled: bool = true
@export var edge_pan_margin_base_px: float = 6.0
@export var map_bounds: Rect2 = Rect2(-32.0, -32.0, 64.0, 64.0)

@onready var _yaw_pivot: Node3D = $YawPivot
@onready var _pitch_pivot: Node3D = $YawPivot/PitchPivot
@onready var _camera: Camera3D = $YawPivot/PitchPivot/Camera3D

var _focus_xz: Vector2 = Vector2.ZERO
var _pan_velocity_xz: Vector2 = Vector2.ZERO
var _current_distance: float = 36.0
var _target_distance: float = 36.0
var _last_tick_usec: int = 0

var _is_dragging: bool = false
var _pending_drag_pixels: Vector2 = Vector2.ZERO
var _window_has_focus: bool = false
var _mouse_inside_window: bool = false
var _last_mouse_pos: Vector2 = -Vector2.ONE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_current_distance = CameraMath.clamp_zoom_distance(default_distance, min_distance, max_distance)
	_target_distance = _current_distance
	_focus_xz = CameraMath.clamp_focus_to_bounds(Vector2(global_position.x, global_position.z), map_bounds)
	_last_tick_usec = Time.get_ticks_usec()

	var win: Window = get_window()
	if win != null:
		_window_has_focus = win.has_focus()

	_apply_rig_transforms()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_has_focus = true
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_has_focus = false
			_mouse_inside_window = false
			_is_dragging = false
			_pending_drag_pixels = Vector2.ZERO
		NOTIFICATION_WM_MOUSE_ENTER:
			_mouse_inside_window = true
		NOTIFICATION_WM_MOUSE_EXIT:
			_mouse_inside_window = false


func _input(event: InputEvent) -> void:
	if _is_dragging and event.is_action_released(InputActions.CAMERA_DRAG):
		_is_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	var viewport: Viewport = get_viewport()

	if event.is_action_pressed(InputActions.CAMERA_ZOOM_IN):
		zoom_by(-1.0)
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if event.is_action_pressed(InputActions.CAMERA_ZOOM_OUT):
		zoom_by(1.0)
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if event.is_action_pressed(InputActions.CAMERA_DRAG):
		_is_dragging = true
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_last_mouse_pos = motion.position
		if viewport != null and viewport.get_visible_rect().has_point(motion.position):
			_mouse_inside_window = true
		if _is_dragging:
			_pending_drag_pixels += motion.relative
			if viewport != null:
				viewport.set_input_as_handled()


func _process(_delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var real_delta: float = 0.0
	if _last_tick_usec > 0:
		real_delta = clampf(float(now_usec - _last_tick_usec) / 1_000_000.0, 0.0, MAX_REAL_DELTA_SEC)
	_last_tick_usec = now_usec

	step_camera(real_delta)


func step_camera(real_delta: float) -> void:
	_update_zoom(real_delta)
	_apply_pending_drag()
	_update_pan(real_delta)
	_apply_rig_transforms()


func set_map_bounds(bounds: Rect2) -> void:
	map_bounds = bounds
	_focus_xz = CameraMath.clamp_focus_to_bounds(_focus_xz, map_bounds)
	_apply_rig_transforms()


func get_map_bounds() -> Rect2:
	return map_bounds


func set_focus_position(focus_xz: Vector2) -> void:
	_focus_xz = CameraMath.clamp_focus_to_bounds(focus_xz, map_bounds)
	_pan_velocity_xz = Vector2.ZERO
	_apply_rig_transforms()


func get_focus_position() -> Vector2:
	return _focus_xz


func set_target_zoom_distance(distance: float, immediate: bool = false) -> void:
	_target_distance = CameraMath.clamp_zoom_distance(distance, min_distance, max_distance)
	if immediate:
		_current_distance = _target_distance
		_apply_rig_transforms()


func get_target_zoom_distance() -> float:
	return _target_distance


func get_current_zoom_distance() -> float:
	return _current_distance


func zoom_by(steps: float) -> void:
	set_target_zoom_distance(_target_distance + steps * zoom_step, false)


func get_camera() -> Camera3D:
	return _camera


func get_yaw_pivot() -> Node3D:
	return _yaw_pivot


func get_pitch_pivot() -> Node3D:
	return _pitch_pivot


func _update_zoom(real_delta: float) -> void:
	if absf(_current_distance - _target_distance) <= ZOOM_SNAP_EPSILON:
		_current_distance = _target_distance
		return
	var factor: float = CameraMath.compute_exp_smoothing_factor(zoom_smoothing, real_delta)
	_current_distance = lerpf(_current_distance, _target_distance, factor)
	if absf(_current_distance - _target_distance) <= ZOOM_SNAP_EPSILON:
		_current_distance = _target_distance


func _apply_pending_drag() -> void:
	if _pending_drag_pixels.is_zero_approx():
		return

	var viewport_height: float = 1080.0
	var viewport: Viewport = get_viewport()
	if viewport != null:
		var visible_height: float = viewport.get_visible_rect().size.y
		if visible_height > 0.0:
			viewport_height = visible_height

	var screen_pan: Vector2 = CameraMath.compute_drag_screen_pan(
		_pending_drag_pixels,
		_current_distance,
		fov_degrees,
		pitch_degrees,
		viewport_height
	)
	_pending_drag_pixels = Vector2.ZERO

	var world_delta: Vector2 = CameraMath.screen_pan_to_world_xz(screen_pan, deg_to_rad(yaw_degrees))
	_focus_xz = CameraMath.clamp_focus_to_bounds(_focus_xz + world_delta, map_bounds)
	_pan_velocity_xz = Vector2.ZERO


func _update_pan(real_delta: float) -> void:
	if real_delta <= 0.0:
		return

	var screen_dir: Vector2 = _collect_pan_direction()
	var current_speed: float = CameraMath.compute_zoom_proportional_speed(
		base_pan_speed,
		_current_distance,
		reference_distance
	)
	var world_dir: Vector2 = CameraMath.screen_pan_to_world_xz(screen_dir, deg_to_rad(yaw_degrees))
	var target_velocity: Vector2 = world_dir * current_speed

	var factor: float = CameraMath.compute_exp_smoothing_factor(pan_smoothing, real_delta)
	_pan_velocity_xz = _pan_velocity_xz.lerp(target_velocity, factor)
	if _pan_velocity_xz.length_squared() < 0.0001 and target_velocity.is_zero_approx():
		_pan_velocity_xz = Vector2.ZERO
		return

	var unclamped_focus: Vector2 = _focus_xz + _pan_velocity_xz * real_delta
	var clamped_focus: Vector2 = CameraMath.clamp_focus_to_bounds(unclamped_focus, map_bounds)

	if not is_equal_approx(clamped_focus.x, unclamped_focus.x):
		_pan_velocity_xz.x = 0.0
	if not is_equal_approx(clamped_focus.y, unclamped_focus.y):
		_pan_velocity_xz.y = 0.0

	_focus_xz = clamped_focus


func _collect_pan_direction() -> Vector2:
	var dir: Vector2 = Input.get_vector(
		InputActions.CAMERA_PAN_LEFT,
		InputActions.CAMERA_PAN_RIGHT,
		InputActions.CAMERA_PAN_DOWN,
		InputActions.CAMERA_PAN_UP
	)

	if edge_pan_enabled and not _is_dragging and _window_has_focus and _mouse_inside_window:
		var viewport: Viewport = get_viewport()
		if viewport != null:
			var scale_factor: float = 1.0
			var win: Window = viewport.get_window()
			if win != null and win.size.y > 64:
				scale_factor = viewport.get_visible_rect().size.y / float(win.size.y)
			var margin_px: float = edge_pan_margin_base_px * scale_factor
			var mouse_pos: Vector2 = _last_mouse_pos if _last_mouse_pos.x >= 0.0 else viewport.get_mouse_position()
			var edge_dir: Vector2 = CameraMath.compute_edge_pan_direction(
				mouse_pos,
				viewport.get_visible_rect().size,
				margin_px
			)
			dir += edge_dir

	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	return dir


func _apply_rig_transforms() -> void:
	position = Vector3(_focus_xz.x, 0.0, _focus_xz.y)

	if _yaw_pivot != null:
		_yaw_pivot.rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	if _pitch_pivot != null:
		_pitch_pivot.rotation = Vector3(deg_to_rad(-pitch_degrees), 0.0, 0.0)
	if _camera != null:
		_camera.fov = fov_degrees
		_camera.position = Vector3(0.0, 0.0, _current_distance)
