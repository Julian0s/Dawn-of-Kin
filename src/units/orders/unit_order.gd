class_name UnitOrder
extends RefCounted
## Base lifecycle object for unit commands (start -> physics_update -> finish/cancel).
## Separates command state and outcomes from Unit and UnitMovement nodes.

enum Status {
	PENDING,
	RUNNING,
	SUCCEEDED,
	FAILED,
	CANCELLED,
}

const REASON_NONE: String = ""
const REASON_CANCELLED: String = "cancelled"
const REASON_REPLACED: String = "replaced"
const REASON_INVALID_TARGET: String = "invalid_target"
const REASON_NAVIGATION_NOT_READY: String = "navigation_not_ready"
const REASON_MISSING_NAVIGATION: String = "missing_navigation"
const REASON_MISSING_MOVEMENT: String = "missing_movement"
const REASON_UNIT_NOT_IN_TREE: String = "unit_not_in_tree"
const REASON_UNREACHABLE: String = "unreachable"
const REASON_STUCK: String = "stuck"
const REASON_UNIT_EXITED: String = "unit_exited"

var status: Status = Status.PENDING
var failure_reason: String = REASON_NONE


func get_order_name() -> String:
	return "UnitOrder"


func is_preparing_work() -> bool:
	return false


func get_work_category() -> int:
	return -1


func is_active() -> bool:
	return status == Status.PENDING or status == Status.RUNNING


func is_finished() -> bool:
	return status == Status.SUCCEEDED or status == Status.FAILED or status == Status.CANCELLED


func is_succeeded() -> bool:
	return status == Status.SUCCEEDED


func start(_unit_body: CharacterBody3D, _movement: UnitMovement, _world_nav: WorldNavigation) -> void:
	mark_succeeded()


func physics_update(_movement: UnitMovement, _delta: float) -> void:
	pass


func cancel(movement: UnitMovement, reason: String = REASON_CANCELLED) -> void:
	if is_finished():
		return
	if movement != null:
		movement.stop_movement()
	mark_cancelled(reason)


func mark_running() -> void:
	if is_finished():
		return
	status = Status.RUNNING
	failure_reason = REASON_NONE


func mark_succeeded() -> void:
	if is_finished():
		return
	status = Status.SUCCEEDED
	failure_reason = REASON_NONE


func mark_failed(reason: String) -> void:
	if is_finished():
		return
	status = Status.FAILED
	failure_reason = reason


func mark_cancelled(reason: String = REASON_CANCELLED) -> void:
	if is_finished():
		return
	status = Status.CANCELLED
	failure_reason = reason
