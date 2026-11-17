class_name MoveOrder
extends UnitOrder
## Order instructing a unit to move to a target world position via WorldNavigation.
## Distinguishes full reachability from partial fallback and reports explicit failure reasons.

var target_position: Vector3 = Vector3.ZERO
var requested_target: Vector3 = Vector3.ZERO
var adjusted_for_occupancy: bool = false
var resolved_target: Vector3 = Vector3.ZERO
var is_partial_unreachable: bool = false
var navigation_reason: String = ""


func _init(
	p_target_position: Vector3 = Vector3.ZERO,
	p_requested_target: Vector3 = Vector3(INF, INF, INF),
	p_adjusted_for_occupancy: bool = false
) -> void:
	target_position = p_target_position
	requested_target = p_requested_target if p_requested_target.is_finite() else p_target_position
	adjusted_for_occupancy = p_adjusted_for_occupancy
	resolved_target = p_target_position


func get_order_name() -> String:
	return "MoveOrder"


func start(unit_body: CharacterBody3D, movement: UnitMovement, world_nav: WorldNavigation) -> void:
	if is_finished():
		return

	if unit_body == null or not unit_body.is_inside_tree():
		mark_failed(REASON_UNIT_NOT_IN_TREE)
		return
	if not target_position.is_finite():
		mark_failed(REASON_INVALID_TARGET)
		return
	if movement == null:
		mark_failed(REASON_MISSING_MOVEMENT)
		return
	movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)

	var nav: WorldNavigation = world_nav if world_nav != null else movement.get_world_navigation()
	if nav == null:
		mark_failed(REASON_MISSING_NAVIGATION)
		return
	if not nav.is_navigation_ready():
		mark_failed(REASON_NAVIGATION_NOT_READY)
		return

	var path_result: WorldNavigation.PathResult = nav.find_path(unit_body.global_position, target_position)
	match path_result.status:
		WorldNavigation.QueryStatus.NOT_READY:
			navigation_reason = path_result.reason
			mark_failed(REASON_NAVIGATION_NOT_READY)
			return
		WorldNavigation.QueryStatus.INVALID_QUERY:
			mark_failed(REASON_INVALID_TARGET)
			return
		WorldNavigation.QueryStatus.OK:
			resolved_target = path_result.resolved_target
			is_partial_unreachable = false
			navigation_reason = ""
			if movement.is_at_target(resolved_target):
				movement.stop_movement()
				mark_succeeded()
				return
		WorldNavigation.QueryStatus.PARTIAL_UNREACHABLE:
			resolved_target = path_result.resolved_target
			is_partial_unreachable = true
			navigation_reason = path_result.reason
			if path_result.path.is_empty() or not resolved_target.is_finite():
				movement.stop_movement()
				mark_failed(REASON_UNREACHABLE)
				return
			if movement.is_at_target(resolved_target):
				movement.stop_movement()
				mark_failed(REASON_UNREACHABLE)
				return
		_:
			mark_failed(REASON_UNREACHABLE)
			return

	if not movement.begin_move_to(resolved_target):
		mark_failed(REASON_UNREACHABLE)
		return

	mark_running()


func physics_update(movement: UnitMovement, _delta: float) -> void:
	if status != Status.RUNNING:
		return
	if movement == null:
		mark_failed(REASON_MISSING_MOVEMENT)
		return

	match movement.get_move_state():
		UnitMovement.MoveState.MOVING:
			return
		UnitMovement.MoveState.ARRIVED:
			movement.stop_movement()
			if is_partial_unreachable:
				mark_failed(REASON_UNREACHABLE)
			else:
				mark_succeeded()
		UnitMovement.MoveState.FAILED_STUCK:
			movement.stop_movement()
			mark_failed(REASON_STUCK)
		UnitMovement.MoveState.FAILED_INVALID:
			movement.stop_movement()
			mark_failed(REASON_UNREACHABLE)
		UnitMovement.MoveState.IDLE:
			mark_failed(REASON_CANCELLED)
