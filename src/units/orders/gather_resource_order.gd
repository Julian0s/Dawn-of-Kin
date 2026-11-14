class_name GatherResourceOrder
extends UnitOrder
## Worker cycle order orchestrating approach -> periodic atomic extraction ->
## automatic transport when full (or unable to fit +1 unit) -> camp delivery -> repeat.

enum Phase {
	APPROACHING_SOURCE,
	GATHERING,
	DELIVERING_TO_CAMP,
}

const DEFAULT_GATHER_INTERVAL_SEC: float = 0.25
const MAX_APPROACH_RETRIES: int = 2

const REASON_INVALID_SOURCE: String = "invalid_source"
const REASON_SOURCE_DEPLETED: String = "source_depleted"
const REASON_NO_WORKER_SLOT: String = "no_worker_slot"
const REASON_INSUFFICIENT_CARRY_CAPACITY: String = "insufficient_carry_capacity"
const REASON_MISSING_ECONOMY: String = "missing_economy"
const REASON_SOURCE_UNREACHABLE: String = "source_unreachable"
const REASON_CAMP_UNREACHABLE: String = DeliverToCampOrder.REASON_CAMP_UNREACHABLE
const REASON_DELIVERY_REJECTED: String = DeliverToCampOrder.REASON_DELIVERY_REJECTED

var source: ResourceSource = null
var camp_zone: CampStorageZone = null
var inventory: SettlementInventory = null
var gather_interval_sec: float = DEFAULT_GATHER_INTERVAL_SEC
var resolved_target: Vector3 = Vector3(INF, INF, INF)

var _unit: Unit = null
var _world_nav: WorldNavigation = null
var _phase: Phase = Phase.APPROACHING_SOURCE
var _gather_elapsed: float = 0.0
var _prepare_elapsed: float = 0.0
var _preparing_cycle: bool = false
var _use_explicit_interval: bool = false
var _explicit_prepare_duration_sec: float = -1.0
var _approach_retries: int = 0
var _delivered_trips: int = 0
var _has_reservation: bool = false
var _awaiting_felling_before_delivery: bool = false
var _deliver_order: DeliverToCampOrder = null


func _init(
	p_source: ResourceSource = null,
	p_camp_zone: CampStorageZone = null,
	p_inventory: SettlementInventory = null,
	p_gather_interval_sec: float = -1.0,
	p_prepare_duration_sec: float = -1.0
) -> void:
	source = p_source
	camp_zone = p_camp_zone
	inventory = p_inventory
	if p_gather_interval_sec > 0.0 and is_finite(p_gather_interval_sec):
		_use_explicit_interval = true
		gather_interval_sec = maxf(p_gather_interval_sec, 0.01)
		_explicit_prepare_duration_sec = maxf(p_prepare_duration_sec, 0.0) if p_prepare_duration_sec >= 0.0 else 0.0
	else:
		_use_explicit_interval = false
		_explicit_prepare_duration_sec = maxf(p_prepare_duration_sec, 0.0) if p_prepare_duration_sec >= 0.0 else -1.0
		gather_interval_sec = _resolve_operation_duration_sec()


func get_order_name() -> String:
	return "GatherResourceOrder"


func get_phase() -> Phase:
	return _phase


func is_preparing_gather() -> bool:
	return _phase == Phase.GATHERING and _preparing_cycle


func is_preparing_work() -> bool:
	return is_preparing_gather()


func get_work_category() -> int:
	return get_source_category()


func get_gather_prepare_duration_sec() -> float:
	return _resolve_prepare_duration_sec()


func get_gather_operation_duration_sec() -> float:
	return _resolve_operation_duration_sec()


func get_gather_progress() -> float:
	if _phase != Phase.GATHERING or _preparing_cycle or gather_interval_sec <= 0.0:
		return 0.0
	return clampf(_gather_elapsed / gather_interval_sec, 0.0, 1.0)


func get_source_category() -> int:
	if source == null or not is_instance_valid(source):
		return -1
	return source.get_category()


func get_delivered_trips() -> int:
	return _delivered_trips


func has_reservation() -> bool:
	return _has_reservation


func get_reserved_target() -> Vector3:
	if not is_active():
		return Vector3(INF, INF, INF)
	if _phase == Phase.DELIVERING_TO_CAMP and _deliver_order != null:
		return _deliver_order.resolved_target
	return resolved_target


func start(unit_body: CharacterBody3D, movement: UnitMovement, world_nav: WorldNavigation) -> void:
	if is_finished():
		return

	if not (unit_body is Unit) or not unit_body.is_inside_tree():
		_finish_failed(REASON_UNIT_NOT_IN_TREE)
		return
	if movement == null:
		_finish_failed(REASON_MISSING_MOVEMENT)
		return
	movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)

	_unit = unit_body as Unit
	var nav: WorldNavigation = world_nav if world_nav != null else movement.get_world_navigation()
	if nav == null:
		_finish_failed(REASON_MISSING_NAVIGATION)
		return
	if not nav.is_navigation_ready():
		_finish_failed(REASON_NAVIGATION_NOT_READY)
		return
	_world_nav = nav

	if source == null or not is_instance_valid(source) or not source.is_inside_tree():
		_finish_failed(REASON_INVALID_SOURCE)
		return
	if source.is_depleted():
		_finish_failed(REASON_SOURCE_DEPLETED)
		return
	if not source.is_available():
		_finish_failed(REASON_INVALID_SOURCE)
		return

	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid() or inventory == null:
		_finish_failed(REASON_MISSING_ECONOMY)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	var def: ResourceDefinition = source.get_definition()
	if carry_load == null or def == null or not def.is_valid():
		_finish_failed(REASON_INVALID_SOURCE)
		return

	if carry_load.is_empty() and not carry_load.can_fit_one(def):
		_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
		return

	# If already full or unable to fit +1 unit of this resource while carrying cargo,
	# verify the source currently allows entry and deliver existing cargo FIRST without
	# holding a source slot during the delivery walk.
	if not carry_load.is_empty() and not carry_load.can_fit_one(def):
		if not source.has_worker_slot(_unit):
			_finish_failed(REASON_NO_WORKER_SLOT)
			return
		mark_running()
		_start_delivering(movement)
		return

	if not _acquire_source_reservation():
		_finish_failed(REASON_NO_WORKER_SLOT)
		return

	mark_running()
	_start_approaching_source(movement)


func physics_update(movement: UnitMovement, delta: float) -> void:
	if status != Status.RUNNING:
		return
	if _unit == null or not is_instance_valid(_unit) or not _unit.is_inside_tree():
		_finish_failed(REASON_UNIT_NOT_IN_TREE)
		return
	if movement == null:
		_finish_failed(REASON_MISSING_MOVEMENT)
		return
	if _world_nav == null or not _world_nav.is_navigation_ready():
		_finish_failed(REASON_NAVIGATION_NOT_READY)
		return

	match _phase:
		Phase.APPROACHING_SOURCE:
			_update_approaching(movement)
		Phase.GATHERING:
			_update_gathering(movement, delta)
		Phase.DELIVERING_TO_CAMP:
			_update_delivering(movement, delta)


func cancel(movement: UnitMovement, reason: String = REASON_CANCELLED) -> void:
	if _deliver_order != null and _deliver_order.is_active():
		_deliver_order.cancel(movement, reason)
	_deliver_order = null
	_awaiting_felling_before_delivery = false
	resolved_target = Vector3(INF, INF, INF)
	_release_source_reservation()
	if movement != null:
		movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	super.cancel(movement, reason)


func _start_approaching_source(movement: UnitMovement) -> void:
	_awaiting_felling_before_delivery = false
	if movement != null:
		movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	if not _is_source_usable():
		_handle_source_unavailable(movement)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if not carry_load.can_fit_one(source.get_definition()):
		if not carry_load.is_empty():
			_start_delivering(movement)
		else:
			_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
		return

	if _is_unit_in_working_range(_unit.global_position):
		_enter_gathering_phase(movement)
		return

	var occupied: Array[Vector3] = GatherSlotPlanner.collect_other_unit_positions(_unit, true)
	var slot_res: Dictionary = GatherSlotPlanner.compute_source_approach_slot(
		_unit.global_position,
		source,
		_world_nav,
		occupied
	)
	if not bool(slot_res.get("valid", false)):
		_finish_failed(REASON_SOURCE_UNREACHABLE)
		return

	resolved_target = slot_res["position"] as Vector3
	if not movement.begin_move_to(resolved_target):
		_finish_failed(REASON_SOURCE_UNREACHABLE)
		return

	_phase = Phase.APPROACHING_SOURCE
	_unit.set_order_state(self, Unit.State.MOVING)

	if movement.get_move_state() == UnitMovement.MoveState.ARRIVED:
		movement.stop_movement()
		if _is_unit_in_working_range(_unit.global_position):
			_approach_retries = 0
			_enter_gathering_phase(movement)
		elif not _try_step_inward_approach(movement):
			_finish_failed(REASON_SOURCE_UNREACHABLE)


func _update_approaching(movement: UnitMovement) -> void:
	if not _is_source_usable():
		movement.stop_movement()
		_handle_source_unavailable(movement)
		return

	match movement.get_move_state():
		UnitMovement.MoveState.MOVING:
			return
		UnitMovement.MoveState.ARRIVED:
			movement.stop_movement()
			if _is_unit_in_working_range(_unit.global_position):
				_approach_retries = 0
				_enter_gathering_phase(movement)
			elif _approach_retries < MAX_APPROACH_RETRIES:
				_approach_retries += 1
				if not _try_step_inward_approach(movement):
					_start_approaching_source(movement)
			else:
				_finish_failed(REASON_SOURCE_UNREACHABLE)
		UnitMovement.MoveState.FAILED_STUCK:
			movement.stop_movement()
			_finish_failed(REASON_STUCK)
		UnitMovement.MoveState.FAILED_INVALID:
			movement.stop_movement()
			_finish_failed(REASON_SOURCE_UNREACHABLE)
		UnitMovement.MoveState.IDLE:
			_finish_cancelled(REASON_CANCELLED)


func _enter_gathering_phase(movement: UnitMovement) -> void:
	movement.stop_movement()
	resolved_target = _unit.global_position
	_refresh_cycle_timings()
	_gather_elapsed = 0.0
	_prepare_elapsed = 0.0
	_preparing_cycle = (_resolve_prepare_duration_sec() > 0.0)
	_awaiting_felling_before_delivery = false
	_phase = Phase.GATHERING
	_unit.set_order_state(self, Unit.State.WORKING)


func _update_gathering(movement: UnitMovement, delta: float) -> void:
	if not _is_source_usable():
		_awaiting_felling_before_delivery = false
		_handle_source_unavailable(movement)
		return

	var dt: float = maxf(delta, 0.0)
	if _awaiting_felling_before_delivery:
		movement.face_towards(source.global_position, dt)
		if source.is_felling():
			return
		_awaiting_felling_before_delivery = false
		_start_delivering(movement)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	var def: ResourceDefinition = source.get_definition()
	if not carry_load.can_fit_one(def):
		if not carry_load.is_empty():
			if source.is_felling():
				movement.face_towards(source.global_position, dt)
				_awaiting_felling_before_delivery = true
			else:
				_start_delivering(movement)
		else:
			_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
		return

	if not _is_unit_in_working_range(_unit.global_position):
		_start_approaching_source(movement)
		return

	movement.face_towards(source.global_position, dt)

	if _preparing_cycle:
		var prep_sec: float = _resolve_prepare_duration_sec()
		_prepare_elapsed += dt
		if _prepare_elapsed < prep_sec:
			return
		_gather_elapsed += (_prepare_elapsed - prep_sec)
		_preparing_cycle = false
	else:
		_gather_elapsed += dt

	if _gather_elapsed < gather_interval_sec:
		return

	_gather_elapsed -= gather_interval_sec
	var extracted: int = source.transfer_to_carry_load(carry_load, source.max_extract_per_operation)

	if extracted <= 0:
		if not carry_load.is_empty() and (source.is_depleted() or not carry_load.can_fit_one(def)):
			if source.is_felling():
				_awaiting_felling_before_delivery = true
			else:
				_start_delivering(movement)
		elif source.is_depleted():
			_handle_source_unavailable(movement)
		else:
			_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
		return

	if carry_load.is_full() or not carry_load.can_fit_one(def) or source.is_depleted():
		if source.is_felling():
			_awaiting_felling_before_delivery = true
		else:
			_start_delivering(movement)


func _start_delivering(movement: UnitMovement) -> void:
	# Free the source slot while transporting so other workers can approach or gather.
	_release_source_reservation()
	_phase = Phase.DELIVERING_TO_CAMP
	resolved_target = Vector3(INF, INF, INF)
	_unit.set_order_state(self, Unit.State.TRANSPORTING)

	_deliver_order = DeliverToCampOrder.new(camp_zone, inventory)
	_deliver_order.start(_unit, movement, _world_nav)
	if _deliver_order.is_finished():
		_handle_deliver_finished(movement)


func _update_delivering(movement: UnitMovement, delta: float) -> void:
	if _deliver_order == null:
		_finish_failed(REASON_CAMP_UNREACHABLE)
		return

	_deliver_order.physics_update(movement, delta)
	if _deliver_order.is_finished():
		_handle_deliver_finished(movement)


func _handle_deliver_finished(movement: UnitMovement) -> void:
	if _deliver_order == null:
		_finish_failed(REASON_CAMP_UNREACHABLE)
		return

	if _deliver_order.is_succeeded():
		_delivered_trips += 1
		_deliver_order = null
		if not _is_source_usable():
			_finish_succeeded()
			return

		var carry_load: UnitCarryLoad = _unit.get_carry_load()
		if not carry_load.can_fit_one(source.get_definition()):
			_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
			return

		if not _acquire_source_reservation():
			_finish_failed(REASON_NO_WORKER_SLOT)
			return

		_start_approaching_source(movement)
		return

	var err_reason: String = _deliver_order.failure_reason
	if err_reason.is_empty():
		err_reason = REASON_DELIVERY_REJECTED
	_deliver_order = null
	_finish_failed(err_reason)


func _handle_source_unavailable(movement: UnitMovement) -> void:
	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if carry_load != null and not carry_load.is_empty():
		_start_delivering(movement)
		return
	if _delivered_trips > 0:
		_finish_succeeded()
	else:
		_finish_failed(REASON_SOURCE_DEPLETED)


func _is_source_usable() -> bool:
	return (
		source != null
		and is_instance_valid(source)
		and source.is_inside_tree()
		and source.is_available()
	)


func _is_unit_in_working_range(unit_pos: Vector3) -> bool:
	if not _is_source_usable() or not unit_pos.is_finite():
		return false
	var source_pos: Vector3 = source.global_position
	var flat_dist: float = Vector2(unit_pos.x - source_pos.x, unit_pos.z - source_pos.z).length()
	var solid_radius: float = maxf(source.get_solid_radius(), 0.0)
	var min_safe: float = solid_radius + WorldNavigation.DEFAULT_AGENT_RADIUS - 0.05 if solid_radius > 0.0 else 0.0
	var max_reach: float = source.get_interaction_radius() + 0.05
	return flat_dist >= min_safe and flat_dist <= max_reach


func _try_step_inward_approach(movement: UnitMovement) -> bool:
	if not _is_source_usable() or _world_nav == null:
		return false
	var source_pos: Vector3 = source.global_position
	var unit_pos: Vector3 = _unit.global_position
	var dir_xz := Vector2(unit_pos.x - source_pos.x, unit_pos.z - source_pos.z)
	if dir_xz.length_squared() < 0.0001:
		dir_xz = Vector2(1.0, 0.0)
	else:
		dir_xz = dir_xz.normalized()

	var solid_radius: float = maxf(source.get_solid_radius(), 0.0)
	var inter_radius: float = maxf(source.get_interaction_radius(), 0.1)
	var min_safe: float = (solid_radius + WorldNavigation.DEFAULT_AGENT_RADIUS) if solid_radius > 0.0 else 0.45
	var target_r: float = minf(min_safe + 0.02, inter_radius - 0.10)
	var candidate := Vector3(
		source_pos.x + dir_xz.x * target_r,
		source_pos.y,
		source_pos.z + dir_xz.y * target_r
	)
	var snapped: Vector3 = _world_nav.snap_to_navmesh(candidate)
	if not snapped.is_finite() or not _world_nav.is_position_reachable(unit_pos, snapped):
		return false
	var snapped_dist: float = Vector2(snapped.x - source_pos.x, snapped.z - source_pos.z).length()
	if snapped_dist < min_safe or snapped_dist > inter_radius:
		return false
	resolved_target = snapped
	if not movement.begin_move_to(resolved_target):
		return false
	if movement.get_move_state() == UnitMovement.MoveState.ARRIVED:
		return false
	_phase = Phase.APPROACHING_SOURCE
	_unit.set_order_state(self, Unit.State.MOVING)
	return true


func _acquire_source_reservation() -> bool:
	if source == null or not is_instance_valid(source) or not source.is_available() or _unit == null or not is_instance_valid(_unit):
		_has_reservation = false
		return false
	if not source.reserve_worker(_unit):
		_has_reservation = false
		return false
	_has_reservation = true
	return true


func _release_source_reservation() -> void:
	if _has_reservation and source != null and is_instance_valid(source) and _unit != null and is_instance_valid(_unit):
		source.release_worker(_unit)
	_has_reservation = false


func _finish_succeeded() -> void:
	resolved_target = Vector3(INF, INF, INF)
	_deliver_order = null
	_release_source_reservation()
	mark_succeeded()


func _finish_failed(reason: String) -> void:
	resolved_target = Vector3(INF, INF, INF)
	_deliver_order = null
	_release_source_reservation()
	mark_failed(reason)


func _finish_cancelled(reason: String) -> void:
	resolved_target = Vector3(INF, INF, INF)
	_deliver_order = null
	_release_source_reservation()
	mark_cancelled(reason)


func _refresh_cycle_timings() -> void:
	if not _use_explicit_interval:
		gather_interval_sec = _resolve_operation_duration_sec()


func _resolve_operation_duration_sec() -> float:
	if _use_explicit_interval:
		return gather_interval_sec
	if source != null and is_instance_valid(source):
		var duration: float = source.get_gather_operation_duration_sec()
		if duration > 0.0 and is_finite(duration):
			return duration
	return DEFAULT_GATHER_INTERVAL_SEC


func _resolve_prepare_duration_sec() -> float:
	if _explicit_prepare_duration_sec >= 0.0:
		return _explicit_prepare_duration_sec
	if not _use_explicit_interval and source != null and is_instance_valid(source):
		var prep: float = source.get_gather_prepare_duration_sec()
		if prep >= 0.0 and is_finite(prep):
			return prep
	return 0.0
