class_name DeliverToCampOrder
extends UnitOrder
## Order instructing a unit carrying physical materials to move to an accessible
## CampStorageZone slot and deposit its load atomically into SettlementInventory.

const REASON_MISSING_ECONOMY: String = "missing_economy"
const REASON_EMPTY_LOAD: String = "empty_load"
const REASON_CAMP_UNREACHABLE: String = "camp_unreachable"
const REASON_DELIVERY_REJECTED: String = "delivery_rejected"

var camp_zone: CampStorageZone = null
var inventory: SettlementInventory = null
var resolved_target: Vector3 = Vector3(INF, INF, INF)
var last_delivered: Dictionary = {}

var _unit: Unit = null
var _world_nav: WorldNavigation = null


func _init(
	p_camp_zone: CampStorageZone = null,
	p_inventory: SettlementInventory = null
) -> void:
	camp_zone = p_camp_zone
	inventory = p_inventory


func get_order_name() -> String:
	return "DeliverToCampOrder"


func get_reserved_target() -> Vector3:
	if is_active():
		return resolved_target
	return Vector3(INF, INF, INF)


func start(unit_body: CharacterBody3D, movement: UnitMovement, world_nav: WorldNavigation) -> void:
	if is_finished():
		return

	if not (unit_body is Unit) or not unit_body.is_inside_tree():
		mark_failed(REASON_UNIT_NOT_IN_TREE)
		return
	if movement == null:
		mark_failed(REASON_MISSING_MOVEMENT)
		return
	movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)

	_unit = unit_body as Unit
	var nav: WorldNavigation = world_nav if world_nav != null else movement.get_world_navigation()
	if nav == null:
		mark_failed(REASON_MISSING_NAVIGATION)
		return
	if not nav.is_navigation_ready():
		mark_failed(REASON_NAVIGATION_NOT_READY)
		return
	_world_nav = nav

	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid() or inventory == null:
		mark_failed(REASON_MISSING_ECONOMY)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if carry_load == null or carry_load.is_empty():
		mark_failed(REASON_EMPTY_LOAD)
		return

	var occupied: Array[Vector3] = GatherSlotPlanner.collect_other_unit_positions(_unit, true)
	var slot_res: Dictionary = GatherSlotPlanner.compute_camp_dropoff_slot(
		_unit.global_position,
		camp_zone,
		_world_nav,
		occupied
	)
	if not bool(slot_res.get("valid", false)):
		mark_failed(REASON_CAMP_UNREACHABLE)
		return

	resolved_target = slot_res["position"] as Vector3
	if not movement.begin_move_to(resolved_target):
		mark_failed(REASON_CAMP_UNREACHABLE)
		return

	mark_running()
	_unit.set_order_state(self, Unit.State.TRANSPORTING)

	if movement.get_move_state() == UnitMovement.MoveState.ARRIVED:
		movement.stop_movement()
		_execute_delivery()


func physics_update(movement: UnitMovement, _delta: float) -> void:
	if status != Status.RUNNING:
		return
	if _unit == null or not is_instance_valid(_unit) or not _unit.is_inside_tree():
		mark_failed(REASON_UNIT_NOT_IN_TREE)
		return
	if movement == null:
		mark_failed(REASON_MISSING_MOVEMENT)
		return

	match movement.get_move_state():
		UnitMovement.MoveState.MOVING:
			return
		UnitMovement.MoveState.ARRIVED:
			movement.stop_movement()
			_execute_delivery()
		UnitMovement.MoveState.FAILED_STUCK:
			movement.stop_movement()
			mark_failed(REASON_STUCK)
		UnitMovement.MoveState.FAILED_INVALID:
			movement.stop_movement()
			mark_failed(REASON_CAMP_UNREACHABLE)
		UnitMovement.MoveState.IDLE:
			mark_failed(REASON_CANCELLED)


func cancel(movement: UnitMovement, reason: String = REASON_CANCELLED) -> void:
	resolved_target = Vector3(INF, INF, INF)
	if movement != null:
		movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	super.cancel(movement, reason)


func _execute_delivery() -> void:
	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid() or inventory == null:
		mark_failed(REASON_MISSING_ECONOMY)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if carry_load == null or carry_load.is_empty():
		mark_failed(REASON_EMPTY_LOAD)
		return

	var delivered: Dictionary = inventory.deliver_from_carry_load(carry_load)
	if delivered.is_empty() or not carry_load.is_empty():
		last_delivered = {}
		mark_failed(REASON_DELIVERY_REJECTED)
		return

	last_delivered = delivered
	resolved_target = Vector3(INF, INF, INF)
	mark_succeeded()
