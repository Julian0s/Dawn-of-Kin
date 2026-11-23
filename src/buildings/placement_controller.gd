class_name PlacementController
extends Node
## Coordinates T3.2 interactive building preview, cursor tracking, candidate confirmation,
## and cancellation without modifying inventory, navigation, or instantiating sites.

signal placement_started(definition: BuildingDefinition)
signal placement_cancelled(definition: BuildingDefinition)
signal placement_confirmed(
	definition: BuildingDefinition,
	world_position: Vector3,
	result: PlacementValidator.ValidationResult
)
signal placement_rejected(
	definition: BuildingDefinition,
	world_position: Vector3,
	result: PlacementValidator.ValidationResult
)
signal hover_state_changed(valid: bool, reason_text: String, world_position: Vector3)
signal confirm_pending_changed(pending: bool)

const DYNAMIC_HOVER_REFRESH_INTERVAL_SEC: float = 0.12

@export var use_async_confirm: bool = true

var _camera_rig: RtsCameraRig = null
var _region_root: Node = null
var _world_navigation: WorldNavigation = null
var _camp_storage_zone: CampStorageZone = null
var _ground_pile_manager: GroundPileManager = null
var _preview_parent: Node3D = null
var _units_root: Node = null
var _piles_root: Node = null
var _connectivity_checkpoints: Array[Vector3] = []

var _validator: PlacementValidator = PlacementValidator.new()
var _world_picker: WorldPicker = WorldPicker.new()
var _preview: PlacementPreview = null

var _active: bool = false
var _active_definition: BuildingDefinition = null
var _left_click_armed: bool = false
var _confirm_in_flight: bool = false
var _confirm_generation: int = 0
var _active_confirm_token: WorldNavigation.AsyncBakeToken = null
var _last_pointer_pos: Vector2 = Vector2.ZERO
var _has_pointer_pos: bool = false
var _pointer_dirty: bool = false
var _world_dirty: bool = false
var _dynamic_refresh_elapsed_sec: float = 0.0
var _last_camera_focus: Vector2 = Vector2(INF, INF)
var _last_camera_zoom: float = INF
var _last_ground_y: float = 0.0

var _last_hover_result: PlacementValidator.ValidationResult = null
var _last_confirm_result: PlacementValidator.ValidationResult = null


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func _exit_tree() -> void:
	_cancel_pending_confirm()
	_disconnect_world_signals()
	if _preview != null and is_instance_valid(_preview):
		_preview.visible = false
		_preview.queue_free()
		_preview = null
	_active = false
	_active_definition = null


func _process(delta: float) -> void:
	if not _active or _active_definition == null:
		set_process(false)
		return
	if not _has_pointer_pos:
		return

	var cam_moved: bool = false
	if _camera_rig != null and is_instance_valid(_camera_rig):
		var focus: Vector2 = _camera_rig.get_focus_position()
		var zoom: float = _camera_rig.get_current_zoom_distance()
		if not focus.is_equal_approx(_last_camera_focus) or not is_equal_approx(zoom, _last_camera_zoom):
			_last_camera_focus = focus
			_last_camera_zoom = zoom
			cam_moved = true

	_dynamic_refresh_elapsed_sec += maxf(delta, 0.0)
	var periodic_due: bool = _dynamic_refresh_elapsed_sec >= DYNAMIC_HOVER_REFRESH_INTERVAL_SEC

	if _pointer_dirty or cam_moved or _world_dirty or periodic_due:
		_pointer_dirty = false
		_world_dirty = false
		_dynamic_refresh_elapsed_sec = 0.0
		update_preview_at_screen_pos(_last_pointer_pos)


func configure(
	camera_rig: RtsCameraRig,
	region_root: Node,
	world_navigation: WorldNavigation,
	camp_storage_zone: CampStorageZone = null,
	ground_pile_manager: GroundPileManager = null,
	preview_parent: Node3D = null,
	units_root: Node = null,
	piles_root: Node = null
) -> void:
	_disconnect_world_signals()
	_camera_rig = camera_rig
	_region_root = region_root
	_world_navigation = world_navigation
	_camp_storage_zone = camp_storage_zone
	_ground_pile_manager = ground_pile_manager
	_preview_parent = preview_parent if preview_parent != null else (region_root as Node3D)
	_units_root = units_root
	_piles_root = piles_root
	_connect_world_signals()
	_ensure_preview_node()


func set_units_root(units_root: Node) -> void:
	_units_root = units_root
	_world_dirty = true


func set_piles_root(piles_root: Node) -> void:
	_piles_root = piles_root
	_world_dirty = true


func set_connectivity_checkpoints(checkpoints: Array[Vector3]) -> void:
	_connectivity_checkpoints = checkpoints.duplicate()


func set_camp_storage_zone(camp_zone: CampStorageZone) -> void:
	_camp_storage_zone = camp_zone


func start_placement(definition: BuildingDefinition) -> bool:
	if definition == null or not definition.is_valid():
		return false

	_cancel_pending_confirm()
	_ensure_preview_node()
	_active = true
	_active_definition = definition
	_left_click_armed = false
	_last_hover_result = null
	_world_dirty = false
	_dynamic_refresh_elapsed_sec = 0.0
	_last_camera_focus = Vector2(INF, INF)
	_last_camera_zoom = INF
	set_process(true)

	var viewport: Viewport = get_viewport()
	if viewport != null:
		var mouse_pos: Vector2 = viewport.get_mouse_position()
		if mouse_pos.is_finite() and viewport.get_visible_rect().has_point(mouse_pos):
			_last_pointer_pos = mouse_pos
			_has_pointer_pos = true
			_pointer_dirty = true

	placement_started.emit(definition)
	if _has_pointer_pos and _can_pick():
		_pointer_dirty = false
		update_preview_at_screen_pos(_last_pointer_pos)

	return true


func cancel_placement() -> void:
	if not _active:
		return
	_cancel_pending_confirm()
	var cancelled_def: BuildingDefinition = _active_definition
	_active = false
	_active_definition = null
	_left_click_armed = false
	_pointer_dirty = false
	_world_dirty = false
	set_process(false)
	if _preview != null and is_instance_valid(_preview):
		_preview.hide_preview()
	placement_cancelled.emit(cancelled_def)


func is_placement_active() -> bool:
	return _active and _active_definition != null


func is_confirm_pending() -> bool:
	return _confirm_in_flight


func get_active_definition() -> BuildingDefinition:
	return _active_definition


func get_preview() -> PlacementPreview:
	return _preview


func get_validator() -> PlacementValidator:
	return _validator


func get_last_hover_result() -> PlacementValidator.ValidationResult:
	return _last_hover_result


func get_last_confirm_result() -> PlacementValidator.ValidationResult:
	return _last_confirm_result


func build_validation_context() -> PlacementValidator.ValidationContext:
	return PlacementValidator.ValidationContext.from_region(
		_region_root,
		_world_navigation,
		_camp_storage_zone,
		_ground_pile_manager,
		[],
		[],
		_connectivity_checkpoints,
		_units_root,
		_piles_root
	)


func invalidate_hover() -> void:
	_world_dirty = true


func force_refresh_preview() -> PlacementValidator.ValidationResult:
	if not is_placement_active() or not _has_pointer_pos:
		return null
	_pointer_dirty = false
	_world_dirty = false
	_dynamic_refresh_elapsed_sec = 0.0
	return update_preview_at_screen_pos(_last_pointer_pos)


## Returns true if the input event was exclusively consumed by placement mode.
## Mouse motion and camera actions return false so RtsCameraRig continues operating normally.
func handle_unhandled_input(event: InputEvent) -> bool:
	if not is_placement_active():
		return false

	var viewport: Viewport = get_viewport()

	if event.is_action_pressed(InputActions.CLEAR_SELECTION) or event.is_action_pressed(InputActions.COMMAND):
		cancel_placement()
		return true

	if event.is_action_pressed(InputActions.SELECT):
		_left_click_armed = true
		_last_pointer_pos = _extract_event_position(event, viewport)
		_has_pointer_pos = true
		return true

	if event.is_action_released(InputActions.SELECT):
		var release_pos: Vector2 = _extract_event_position(event, viewport)
		_last_pointer_pos = release_pos
		_has_pointer_pos = true
		if _left_click_armed:
			_left_click_armed = false
			confirm_at_screen_pos(release_pos)
		return true

	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_last_pointer_pos = motion.position
		_has_pointer_pos = true
		_pointer_dirty = true
		return false

	return false


func update_preview_at_screen_pos(screen_pos: Vector2) -> PlacementValidator.ValidationResult:
	if not is_placement_active():
		return null
	var world_pos: Vector3 = _project_screen_to_ground(screen_pos)
	return update_preview_at_world_pos(world_pos)


func update_preview_at_world_pos(world_pos: Vector3) -> PlacementValidator.ValidationResult:
	if not is_placement_active():
		return null

	var ctx: PlacementValidator.ValidationContext = build_validation_context()
	var result: PlacementValidator.ValidationResult = _validator.validate_hover(_active_definition, world_pos, ctx)
	_last_hover_result = result

	_ensure_preview_node()
	if _preview != null:
		var display_pos: Vector3 = result.resolved_position if (result.resolved_position.is_finite() and result.reason_code != PlacementValidator.REASON_INVALID_TERRAIN) else world_pos
		if display_pos.is_finite():
			_last_ground_y = display_pos.y
			_preview.show_preview(_active_definition, display_pos, result.valid)
		else:
			_preview.hide_preview()

	hover_state_changed.emit(result.valid, result.reason_text, result.resolved_position)
	return result


func confirm_at_screen_pos(screen_pos: Vector2) -> PlacementValidator.ValidationResult:
	if not is_placement_active():
		return null
	var world_pos: Vector3 = _project_screen_to_ground(screen_pos)
	return confirm_at_world_pos(world_pos)


func confirm_at_world_pos(world_pos: Vector3) -> PlacementValidator.ValidationResult:
	if not is_placement_active() or _confirm_in_flight:
		return null

	var target_def: BuildingDefinition = _active_definition
	var ctx: PlacementValidator.ValidationContext = build_validation_context()
	if not use_async_confirm:
		var sync_result: PlacementValidator.ValidationResult = _validator.validate_confirm(target_def, world_pos, ctx)
		_apply_confirm_outcome(target_def, world_pos, sync_result)
		return sync_result

	_confirm_in_flight = true
	_confirm_generation += 1
	var req_generation: int = _confirm_generation
	var sync_returned: Array[PlacementValidator.ValidationResult] = [null]

	_active_confirm_token = _validator.validate_confirm_async(
		target_def,
		world_pos,
		ctx,
		PlacementController._on_async_confirm_complete.bind(
			weakref(self),
			req_generation,
			target_def,
			world_pos,
			sync_returned
		)
	)

	if _active_confirm_token == null:
		_confirm_in_flight = false
	elif _confirm_in_flight:
		confirm_pending_changed.emit(true)
	return sync_returned[0]


static func _on_async_confirm_complete(
	async_result: PlacementValidator.ValidationResult,
	controller_ref: WeakRef,
	req_generation: int,
	target_def: BuildingDefinition,
	world_pos: Vector3,
	sync_returned: Array[PlacementValidator.ValidationResult]
) -> void:
	sync_returned[0] = async_result
	var controller: PlacementController = controller_ref.get_ref() as PlacementController
	if controller == null or not is_instance_valid(controller) or not controller.is_inside_tree():
		return
	if req_generation != controller._confirm_generation:
		return
	var was_pending: bool = controller._confirm_in_flight and controller._active_confirm_token != null
	controller._confirm_in_flight = false
	controller._active_confirm_token = null
	if was_pending:
		controller.confirm_pending_changed.emit(false)
	if not controller.is_placement_active() or controller._active_definition != target_def:
		return
	controller._apply_confirm_outcome(target_def, world_pos, async_result)


func _apply_confirm_outcome(
	target_def: BuildingDefinition,
	world_pos: Vector3,
	result: PlacementValidator.ValidationResult
) -> void:
	_last_confirm_result = result
	if result != null and result.valid:
		_last_ground_y = result.resolved_position.y
		_active = false
		_active_definition = null
		_left_click_armed = false
		_pointer_dirty = false
		_world_dirty = false
		set_process(false)
		_ensure_preview_node()
		if _preview != null:
			_preview.show_confirmation_pulse(target_def, result.resolved_position)
		placement_confirmed.emit(target_def, result.resolved_position, result)
		return

	_ensure_preview_node()
	var reason_txt: String = result.reason_text if result != null else "Posição inválida."
	if _preview != null:
		var display_pos: Vector3 = result.resolved_position if (result != null and result.resolved_position.is_finite()) else world_pos
		if display_pos.is_finite():
			_preview.show_preview(target_def, display_pos, false)
	hover_state_changed.emit(false, reason_txt, world_pos)
	placement_rejected.emit(target_def, world_pos, result)


func _cancel_pending_confirm() -> void:
	var was_pending: bool = _confirm_in_flight
	_confirm_generation += 1
	_confirm_in_flight = false
	if _active_confirm_token != null:
		_active_confirm_token.cancel()
		_active_confirm_token = null
	if was_pending:
		confirm_pending_changed.emit(false)


func _connect_world_signals() -> void:
	if _ground_pile_manager != null and is_instance_valid(_ground_pile_manager):
		if not _ground_pile_manager.storage_changed.is_connected(_on_world_state_invalidated):
			_ground_pile_manager.storage_changed.connect(_on_world_state_invalidated)
	if _world_navigation != null and is_instance_valid(_world_navigation):
		if not _world_navigation.navigation_ready.is_connected(_on_world_state_invalidated):
			_world_navigation.navigation_ready.connect(_on_world_state_invalidated)


func _disconnect_world_signals() -> void:
	if _ground_pile_manager != null and is_instance_valid(_ground_pile_manager):
		if _ground_pile_manager.storage_changed.is_connected(_on_world_state_invalidated):
			_ground_pile_manager.storage_changed.disconnect(_on_world_state_invalidated)
	if _world_navigation != null and is_instance_valid(_world_navigation):
		if _world_navigation.navigation_ready.is_connected(_on_world_state_invalidated):
			_world_navigation.navigation_ready.disconnect(_on_world_state_invalidated)


func _on_world_state_invalidated() -> void:
	_world_dirty = true


func _ensure_preview_node() -> void:
	if _preview != null and is_instance_valid(_preview):
		return
	var parent_3d: Node3D = _preview_parent
	if parent_3d == null and _region_root is Node3D:
		parent_3d = _region_root as Node3D
	if parent_3d == null or not is_instance_valid(parent_3d):
		return
	_preview = PlacementPreview.new()
	_preview.name = "BuildingPlacementPreview"
	parent_3d.add_child(_preview)


func _project_screen_to_ground(screen_pos: Vector2) -> Vector3:
	if not _can_pick() or not screen_pos.is_finite():
		return Vector3(INF, INF, INF)

	var camera: Camera3D = _camera_rig.get_camera()
	var pick: PickResult = _world_picker.pick_terrain_at_screen_pos(camera, screen_pos)
	if pick.is_ground() and pick.position.is_finite():
		return pick.position

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var ground_plane := Plane(Vector3.UP, _last_ground_y)
	var hit: Variant = ground_plane.intersects_ray(ray_origin, ray_dir)
	if hit is Vector3 and (hit as Vector3).is_finite():
		return hit as Vector3

	return Vector3(INF, INF, INF)


func _can_pick() -> bool:
	return _camera_rig != null and is_instance_valid(_camera_rig) and _camera_rig.get_camera() != null


func _extract_event_position(event: InputEvent, viewport: Viewport) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).position
	if viewport != null:
		return viewport.get_mouse_position()
	return _last_pointer_pos
