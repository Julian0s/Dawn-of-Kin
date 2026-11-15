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

var _camera_rig: RtsCameraRig = null
var _region_root: Node = null
var _world_navigation: WorldNavigation = null
var _camp_storage_zone: CampStorageZone = null
var _ground_pile_manager: GroundPileManager = null
var _preview_parent: Node3D = null
var _connectivity_checkpoints: Array[Vector3] = []

var _validator: PlacementValidator = PlacementValidator.new()
var _world_picker: WorldPicker = WorldPicker.new()
var _preview: PlacementPreview = null

var _active: bool = false
var _active_definition: BuildingDefinition = null
var _left_click_armed: bool = false
var _last_pointer_pos: Vector2 = Vector2.ZERO
var _has_pointer_pos: bool = false
var _pointer_dirty: bool = false
var _last_camera_focus: Vector2 = Vector2(INF, INF)
var _last_camera_zoom: float = INF
var _last_ground_y: float = 0.0

var _last_hover_result: PlacementValidator.ValidationResult = null
var _last_confirm_result: PlacementValidator.ValidationResult = null


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func _exit_tree() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.visible = false
		_preview.queue_free()
		_preview = null
	_active = false
	_active_definition = null


func _process(_delta: float) -> void:
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

	if _pointer_dirty or cam_moved:
		_pointer_dirty = false
		update_preview_at_screen_pos(_last_pointer_pos)


func configure(
	camera_rig: RtsCameraRig,
	region_root: Node,
	world_navigation: WorldNavigation,
	camp_storage_zone: CampStorageZone = null,
	ground_pile_manager: GroundPileManager = null,
	preview_parent: Node3D = null
) -> void:
	_camera_rig = camera_rig
	_region_root = region_root
	_world_navigation = world_navigation
	_camp_storage_zone = camp_storage_zone
	_ground_pile_manager = ground_pile_manager
	_preview_parent = preview_parent if preview_parent != null else (region_root as Node3D)
	_ensure_preview_node()


func set_connectivity_checkpoints(checkpoints: Array[Vector3]) -> void:
	_connectivity_checkpoints = checkpoints.duplicate()


func set_camp_storage_zone(camp_zone: CampStorageZone) -> void:
	_camp_storage_zone = camp_zone


func start_placement(definition: BuildingDefinition) -> bool:
	if definition == null or not definition.is_valid():
		return false

	_ensure_preview_node()
	_active = true
	_active_definition = definition
	_left_click_armed = false
	_last_hover_result = null
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
	var cancelled_def: BuildingDefinition = _active_definition
	_active = false
	_active_definition = null
	_left_click_armed = false
	_pointer_dirty = false
	set_process(false)
	if _preview != null and is_instance_valid(_preview):
		_preview.hide_preview()
	placement_cancelled.emit(cancelled_def)


func is_placement_active() -> bool:
	return _active and _active_definition != null


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
		_connectivity_checkpoints
	)


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
	if not is_placement_active():
		return null

	var target_def: BuildingDefinition = _active_definition
	var ctx: PlacementValidator.ValidationContext = build_validation_context()
	var result: PlacementValidator.ValidationResult = _validator.validate_confirm(target_def, world_pos, ctx)
	_last_confirm_result = result

	if result.valid:
		_last_ground_y = result.resolved_position.y
		_active = false
		_active_definition = null
		_left_click_armed = false
		_pointer_dirty = false
		set_process(false)
		_ensure_preview_node()
		if _preview != null:
			_preview.show_confirmation_pulse(target_def, result.resolved_position)
		placement_confirmed.emit(target_def, result.resolved_position, result)
		return result

	_ensure_preview_node()
	if _preview != null:
		var display_pos: Vector3 = result.resolved_position if result.resolved_position.is_finite() else world_pos
		if display_pos.is_finite():
			_preview.show_preview(target_def, display_pos, false)
	hover_state_changed.emit(false, result.reason_text, world_pos)
	placement_rejected.emit(target_def, world_pos, result)
	return result


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
