class_name RtsInputController
extends Node
## Translates viewport mouse and keyboard inputs into selection and hover intentions.
## Delegates raycasting to WorldPicker and selection state to SelectionManager.

signal construction_site_picked(site: ConstructionSite)

const BASE_DRAG_THRESHOLD_PX: float = 6.0

@export var selection_manager_path: NodePath = NodePath()
@export var camera_rig_path: NodePath = NodePath()
@export var selection_box_overlay_path: NodePath = NodePath()
@export var command_controller_path: NodePath = NodePath()

var _selection_manager: SelectionManager = null
var _camera_rig: RtsCameraRig = null
var _selection_box_overlay: SelectionBoxOverlay = null
var _command_controller: CommandController = null
var _placement_controller: PlacementController = null
var _world_picker: WorldPicker = WorldPicker.new()

var _left_pressed: bool = false
var _left_press_pos: Vector2 = Vector2.ZERO
var _is_drag_gesture: bool = false
var _last_pointer_pos: Vector2 = Vector2.ZERO
var _has_pointer_pos: bool = false
var _hovered_unit: Unit = null
var _last_pick_result: PickResult = PickResult.none()


func _ready() -> void:
	_resolve_dependencies()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_WM_MOUSE_EXIT:
			_cancel_active_drag()
			_set_hovered_unit(null)


func _exit_tree() -> void:
	_cancel_active_drag()
	_set_hovered_unit(null)


func _process(_delta: float) -> void:
	if _hovered_unit != null and (not is_instance_valid(_hovered_unit) or not _hovered_unit.is_inside_tree()):
		_hovered_unit = null

	if _placement_controller != null and is_instance_valid(_placement_controller) and _placement_controller.is_placement_active():
		_cancel_active_drag()
		_set_hovered_unit(null)
		return

	if _has_pointer_pos and not _is_drag_gesture and _can_pick():
		_update_hover_at(_last_pointer_pos)


func _unhandled_input(event: InputEvent) -> void:
	var viewport: Viewport = get_viewport()

	if _placement_controller != null and is_instance_valid(_placement_controller) and _placement_controller.is_placement_active():
		_cancel_active_drag()
		_set_hovered_unit(null)
		if _placement_controller.handle_unhandled_input(event):
			if viewport != null:
				viewport.set_input_as_handled()
		elif event is InputEventMouseMotion:
			var motion_ev: InputEventMouseMotion = event as InputEventMouseMotion
			_last_pointer_pos = motion_ev.position
			_has_pointer_pos = true
		return

	if event.is_action_pressed(InputActions.CLEAR_SELECTION):
		if _is_drag_gesture or _left_pressed:
			_cancel_active_drag()
			if _has_pointer_pos:
				_update_hover_at(_last_pointer_pos)
			if viewport != null:
				viewport.set_input_as_handled()
			return
		_resolve_dependencies()
		_on_clear_selection_requested()
		if _selection_manager != null:
			_selection_manager.clear_selection()
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if event.is_action_pressed(InputActions.COMMAND):
		var command_pos: Vector2 = _extract_event_position(event, viewport)
		_last_pointer_pos = command_pos
		_has_pointer_pos = true
		_handle_right_click(command_pos)
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if event.is_action_pressed(InputActions.SELECT):
		var press_pos: Vector2 = _extract_event_position(event, viewport)
		var press_shift: bool = _is_shift_held(event)
		_left_pressed = true
		_left_press_pos = press_pos
		_is_drag_gesture = false
		_last_pointer_pos = press_pos
		_has_pointer_pos = true
		_on_left_press_started_with_shift(press_pos, press_shift)
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if event.is_action_released(InputActions.SELECT):
		if not _left_pressed:
			return
		var release_pos: Vector2 = _extract_event_position(event, viewport)
		_left_pressed = false
		_last_pointer_pos = release_pos
		_has_pointer_pos = true

		var exceeded_threshold: bool = release_pos.distance_to(_left_press_pos) > get_drag_threshold_px()
		var shift_held: bool = _is_shift_held(event)
		if _is_drag_gesture or exceeded_threshold:
			if not _is_drag_gesture:
				_on_drag_threshold_crossed(_left_press_pos, release_pos, shift_held)
			_is_drag_gesture = false
			_clear_box_overlay()
			_handle_box_selection(_left_press_pos, release_pos, shift_held)
			_update_hover_at(release_pos)
			if viewport != null:
				viewport.set_input_as_handled()
			return

		_clear_box_overlay()
		_handle_left_click(release_pos, shift_held)
		_update_hover_at(release_pos)
		if viewport != null:
			viewport.set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_last_pointer_pos = motion.position
		_has_pointer_pos = true

		if _left_pressed:
			if not _is_drag_gesture and motion.position.distance_to(_left_press_pos) > get_drag_threshold_px():
				_is_drag_gesture = true
				_set_hovered_unit(null)
				_on_drag_threshold_crossed(_left_press_pos, motion.position, _is_shift_held(motion))
			if _is_drag_gesture:
				_update_box_overlay(_left_press_pos, motion.position)

		if not _is_drag_gesture:
			_update_hover_at(motion.position)


func configure(
	selection_manager: SelectionManager,
	camera_rig: RtsCameraRig,
	selection_box_overlay: SelectionBoxOverlay = null,
	command_controller: CommandController = null,
	placement_controller: PlacementController = null
) -> void:
	_selection_manager = selection_manager
	_camera_rig = camera_rig
	if selection_box_overlay != null:
		_selection_box_overlay = selection_box_overlay
	if command_controller != null:
		_command_controller = command_controller
	if placement_controller != null:
		_placement_controller = placement_controller


func set_placement_controller(placement_controller: PlacementController) -> void:
	_placement_controller = placement_controller


func set_world_picker(picker: WorldPicker) -> void:
	_world_picker = picker if picker != null else WorldPicker.new()


func get_hovered_unit() -> Unit:
	return _hovered_unit


func is_drag_gesture_active() -> bool:
	return _is_drag_gesture


func get_last_pick_result() -> PickResult:
	return _last_pick_result


func get_drag_threshold_px() -> float:
	return compute_drag_threshold_px()


static func compute_drag_threshold_px(dpi: int = -1) -> float:
	var effective_dpi: int = dpi if dpi > 0 else DisplayServer.screen_get_dpi()
	return BASE_DRAG_THRESHOLD_PX * CameraMath.get_dpi_scale(effective_dpi)


func pick_at_screen_pos(screen_pos: Vector2) -> PickResult:
	_resolve_dependencies()
	if not _can_pick():
		return PickResult.none()
	var camera: Camera3D = _camera_rig.get_camera()
	var result: PickResult = _world_picker.pick_at_screen_pos(camera, screen_pos)
	_last_pick_result = result
	return result


func _handle_left_click(screen_pos: Vector2, shift_held: bool) -> void:
	_resolve_dependencies()
	if _selection_manager == null:
		return

	var pick: PickResult = pick_at_screen_pos(screen_pos)
	if pick.is_unit():
		if shift_held:
			_selection_manager.toggle_unit(pick.unit)
		else:
			_selection_manager.select_single(pick.unit)
			construction_site_picked.emit(null)
	elif pick.is_construction_site():
		if not shift_held:
			_selection_manager.clear_selection()
		construction_site_picked.emit(pick.construction_site)
	elif not shift_held:
		_selection_manager.clear_selection()
		construction_site_picked.emit(null)


func _handle_right_click(screen_pos: Vector2) -> void:
	_resolve_dependencies()
	if _command_controller == null:
		return
	var pick: PickResult = pick_at_screen_pos(screen_pos)
	_command_controller.command_at(pick)


func _handle_box_selection(start_pos: Vector2, end_pos: Vector2, shift_held: bool) -> void:
	_resolve_dependencies()
	if _selection_manager == null or not _can_pick():
		return

	var camera: Camera3D = _camera_rig.get_camera()
	var viewport: Viewport = get_viewport()
	var viewport_rect: Rect2 = viewport.get_visible_rect() if viewport != null else Rect2()
	var tree: SceneTree = get_tree()
	var candidates: Array = tree.get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS) if tree != null else []
	var box_rect: Rect2 = SelectionBoxMath.normalize_rect(start_pos, end_pos)
	var boxed_units: Array[Unit] = SelectionBoxMath.collect_units_in_box(camera, candidates, box_rect, viewport_rect)

	if shift_held:
		_selection_manager.add_units(boxed_units)
	else:
		_selection_manager.set_selection(boxed_units)


func _update_box_overlay(start_pos: Vector2, current_pos: Vector2) -> void:
	_resolve_dependencies()
	if _selection_box_overlay != null:
		_selection_box_overlay.set_selection_box(start_pos, current_pos)


func _clear_box_overlay() -> void:
	_resolve_dependencies()
	if _selection_box_overlay != null:
		_selection_box_overlay.clear_selection_box()


func _cancel_active_drag() -> void:
	_left_pressed = false
	_is_drag_gesture = false
	_clear_box_overlay()
	_on_drag_cancelled()


func _on_left_press_started(_press_pos: Vector2) -> void:
	pass


func _on_left_press_started_with_shift(press_pos: Vector2, _shift_held: bool) -> void:
	_on_left_press_started(press_pos)


func _on_drag_threshold_crossed(_start_pos: Vector2, _current_pos: Vector2, _shift_held: bool) -> void:
	pass


func _on_drag_cancelled() -> void:
	pass


func _on_clear_selection_requested() -> void:
	pass


func _update_hover_at(screen_pos: Vector2) -> void:
	if not _can_pick():
		_set_hovered_unit(null)
		return
	var pick: PickResult = pick_at_screen_pos(screen_pos)
	if pick.is_unit():
		_set_hovered_unit(pick.unit)
	else:
		_set_hovered_unit(null)


func _set_hovered_unit(unit: Unit) -> void:
	var valid_unit: Unit = unit if (
		unit != null
		and is_instance_valid(unit)
		and unit.is_inside_tree()
		and UnitControlPermissions.can_be_selected_visually(unit)
	) else null
	if _hovered_unit == valid_unit:
		return

	if _hovered_unit != null and is_instance_valid(_hovered_unit):
		_hovered_unit.set_hovered(false)

	_hovered_unit = valid_unit
	if _hovered_unit != null:
		_hovered_unit.set_hovered(true)


func _resolve_dependencies() -> void:
	if _selection_manager == null and not selection_manager_path.is_empty():
		_selection_manager = get_node_or_null(selection_manager_path) as SelectionManager
	if _camera_rig == null and not camera_rig_path.is_empty():
		_camera_rig = get_node_or_null(camera_rig_path) as RtsCameraRig
	if _selection_box_overlay == null and not selection_box_overlay_path.is_empty():
		_selection_box_overlay = get_node_or_null(selection_box_overlay_path) as SelectionBoxOverlay
	if _command_controller == null and not command_controller_path.is_empty():
		_command_controller = get_node_or_null(command_controller_path) as CommandController


func _can_pick() -> bool:
	return _camera_rig != null and is_instance_valid(_camera_rig) and _camera_rig.get_camera() != null


func _extract_event_position(event: InputEvent, viewport: Viewport) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).position
	if viewport != null:
		return viewport.get_mouse_position()
	return _last_pointer_pos


static func _is_shift_held(event: InputEvent) -> bool:
	if event is InputEventWithModifiers:
		return (event as InputEventWithModifiers).shift_pressed
	return Input.is_action_pressed(InputActions.SELECTION_MODIFIER) or Input.is_key_pressed(KEY_SHIFT)
