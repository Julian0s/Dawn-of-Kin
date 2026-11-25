class_name GatherResourceOrder
extends UnitOrder
## Worker cycle order orchestrating approach -> periodic atomic extraction ->
## automatic transport when full (or unable to fit +1 unit) -> camp delivery -> repeat.
## Supports two strictly separated modes:
## - Legacy mode (default): preserves T2 behavior via ResourceSource.transfer_to_carry_load()
##   and legacy DeliverToCampOrder.
## - Opt-in provenance mode: uses ResourceSource.transfer_to_carry_load_with_provenance() via
##   GatherTransferSession (FREE_GATHERED lots) and selective DeliverToCampOrder (C3.4.2/C3.4.3).

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
const REASON_PROVENANCE_OPT_IN_REQUIRED: String = DeliverToCampOrder.REASON_PROVENANCE_OPT_IN_REQUIRED
const REASON_PROVENANCE_REQUIRED: String = DeliverToCampOrder.REASON_PROVENANCE_REQUIRED
const REASON_COMMUNITY_WORK_CANCELLED: String = "community_work_cancelled"

var source: ResourceSource = null
var camp_zone: CampStorageZone = null
var inventory: SettlementInventory = null
var gather_interval_sec: float = DEFAULT_GATHER_INTERVAL_SEC
var use_provenance_transactions: bool = false
var region_id: StringName = &""
var resolved_target: Vector3 = Vector3(INF, INF, INF)
var last_extraction_receipt: Dictionary = {}
var last_extracted_units: int = 0
var last_extraction_replayed: bool = false
var total_extracted_units: int = 0
var extraction_cycles_completed: int = 0
var last_delivery_receipt: Dictionary = {}

var _unit: Unit = null
var _movement: UnitMovement = null
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
var _active_gather_session: GatherTransferSession = null
var _gather_cycle_serial: int = 0
var _last_nav_revision: int = -1
var _waiting_for_navigation: bool = false
var _replan_requested: bool = false
var _deferred_navigation_failure: bool = false
var _nav_signals_bound: bool = false
var _stop_after_delivery: bool = false
var _community_cancel_requested: bool = false


func _init(
	p_source: ResourceSource = null,
	p_camp_zone: CampStorageZone = null,
	p_inventory: SettlementInventory = null,
	p_gather_interval_sec: float = -1.0,
	p_prepare_duration_sec: float = -1.0,
	p_use_provenance_transactions: bool = false,
	p_region_id: StringName = &""
) -> void:
	source = p_source
	camp_zone = p_camp_zone
	inventory = p_inventory
	use_provenance_transactions = p_use_provenance_transactions
	region_id = p_region_id
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


func is_provenance_mode() -> bool:
	return use_provenance_transactions


func get_phase() -> Phase:
	return _phase


func is_preparing_gather() -> bool:
	return _phase == Phase.GATHERING and _preparing_cycle


func is_preparing_work() -> bool:
	return is_preparing_gather()


func is_community_cancel_requested() -> bool:
	return _community_cancel_requested


func is_stop_after_delivery_requested() -> bool:
	return _stop_after_delivery


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


func get_total_extracted_units() -> int:
	return total_extracted_units


func get_extraction_cycles_completed() -> int:
	return extraction_cycles_completed


func get_active_gather_session() -> GatherTransferSession:
	return _active_gather_session


func is_provenance_transfer_executing() -> bool:
	if not use_provenance_transactions or status != Status.RUNNING:
		return false
	if _active_gather_session != null and _active_gather_session.is_executing:
		return true
	if _deliver_order != null and _deliver_order.is_selective_transfer_executing():
		return true
	if _unit != null and is_instance_valid(_unit):
		var load: UnitCarryLoad = _unit.get_carry_load()
		if load != null and (load._coordinator_transaction_locked or load._provenance_busy):
			return true
	return false


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
	_movement = movement
	var nav: WorldNavigation = world_nav if world_nav != null else movement.get_world_navigation()
	if nav == null:
		_finish_failed(REASON_MISSING_NAVIGATION)
		return
	if not nav.is_navigation_ready():
		_finish_failed(REASON_NAVIGATION_NOT_READY)
		return
	_world_nav = nav
	_last_nav_revision = _world_nav.get_navigation_revision()

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

	if not use_provenance_transactions:
		if carry_load.is_provenance_enabled():
			_finish_failed(REASON_PROVENANCE_OPT_IN_REQUIRED)
			return
	else:
		var unit_world: World3D = _unit.get_world_3d()
		if not carry_load.is_provenance_enabled():
			_finish_failed(REASON_PROVENANCE_REQUIRED)
			return
		if not carry_load.validate_provenance():
			_finish_failed("unreconciled_cargo")
			return
		if unit_world == null or source.get_world_3d() != unit_world or camp_zone.get_world_3d() != unit_world:
			_finish_failed("world_mismatch")
			return
		if region_id.is_empty():
			region_id = _world_nav.get_region_id()
		if not CarryProvenanceLedger._id(region_id):
			_finish_failed("invalid_region")
			return
		if not CarryProvenanceLedger._id(source.source_id):
			_finish_failed(REASON_INVALID_SOURCE)
			return
		var storage: GroundPileManager = inventory.get_storage_source() as GroundPileManager
		if storage == null:
			_finish_failed("unsupported_storage_source")
			return
		if storage.get_camp_zone() != camp_zone:
			_finish_failed("invalid_camp_zone")
			return
		var id_check: Dictionary = ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(
			unit_world, region_id, _unit, carry_load, _unit.get_tree()
		)
		if not bool(id_check.get("ok", false)):
			_finish_failed(String(id_check.get("reason", "ambiguous_unit_identity")))
			return

	if carry_load.is_empty() and not carry_load.can_fit_one(def):
		_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
		return

	# If already full or unable to fit +1 unit of this resource while carrying cargo,
	# verify the source currently allows entry and deliver eligible cargo FIRST without
	# holding a source slot during the delivery walk.
	if not carry_load.is_empty() and not carry_load.can_fit_one(def):
		if use_provenance_transactions and not _has_eligible_free_lots(carry_load):
			_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
			return
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
	if use_provenance_transactions and is_provenance_transfer_executing():
		_replan_requested = true
		return
	if _unit == null or not is_instance_valid(_unit) or not _unit.is_inside_tree():
		_finish_failed(REASON_UNIT_NOT_IN_TREE)
		return
	if movement == null:
		_finish_failed(REASON_MISSING_MOVEMENT)
		return
	_movement = movement

	if not use_provenance_transactions:
		var legacy_load: UnitCarryLoad = _unit.get_carry_load()
		if legacy_load != null and legacy_load.is_provenance_enabled():
			movement.stop_movement()
			_finish_failed(REASON_PROVENANCE_OPT_IN_REQUIRED)
			return
		if _phase != Phase.DELIVERING_TO_CAMP and _community_cancel_requested:
			_apply_deferred_community_cancel(movement)
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
		return

	if _phase == Phase.DELIVERING_TO_CAMP:
		_update_delivering(movement, delta)
		return

	if _community_cancel_requested and not is_provenance_transfer_executing():
		_apply_deferred_community_cancel(movement)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if carry_load == null or not carry_load.is_provenance_enabled():
		movement.stop_movement()
		_finish_failed(REASON_PROVENANCE_REQUIRED)
		return
	if _world_nav == null or not is_instance_valid(_world_nav) or not _world_nav.is_inside_tree() or _world_nav.is_queued_for_deletion():
		movement.stop_movement()
		_finish_failed(REASON_MISSING_NAVIGATION)
		return
	if _deferred_navigation_failure:
		movement.stop_movement()
		_finish_failed(REASON_NAVIGATION_NOT_READY)
		return
	if not _world_nav.is_navigation_ready():
		if _world_nav._is_syncing or _world_nav._active_rebake_token != null:
			_wait_for_navigation()
			return
		movement.stop_movement()
		_finish_failed(REASON_NAVIGATION_NOT_READY)
		return
	if _waiting_for_navigation:
		return

	var current_nav_rev: int = _world_nav.get_navigation_revision()
	if current_nav_rev != _last_nav_revision or _replan_requested:
		_last_nav_revision = current_nav_rev
		_replan_requested = false
		if _phase == Phase.APPROACHING_SOURCE and movement.get_move_state() == UnitMovement.MoveState.MOVING:
			if not resolved_target.is_finite() or not _world_nav.is_position_reachable(_unit.global_position, resolved_target):
				_start_approaching_source(movement)
				return

	match _phase:
		Phase.APPROACHING_SOURCE:
			_update_approaching(movement)
		Phase.GATHERING:
			_update_gathering(movement, delta)


func cancel(movement: UnitMovement, reason: String = REASON_CANCELLED) -> void:
	if use_provenance_transactions and is_provenance_transfer_executing():
		return
	_disconnect_navigation_signals()
	if use_provenance_transactions and _active_gather_session != null:
		var recovered: Dictionary = _active_gather_session.cancel_intent(source, _unit)
		if not recovered.is_empty():
			last_extraction_receipt = recovered.duplicate(true)
			last_extracted_units = 0
			last_extraction_replayed = true
		_active_gather_session = null
	if _deliver_order != null and _deliver_order.is_active():
		_deliver_order.cancel(movement, reason)
	_deliver_order = null
	_awaiting_felling_before_delivery = false
	resolved_target = Vector3(INF, INF, INF)
	_release_source_reservation()
	if movement != null:
		movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	super.cancel(movement, reason)


func request_community_cancel(movement: UnitMovement = null) -> Dictionary:
	## Cooperative selective community work cancellation (R-03A D2 / D2-B).
	## Never aborts an active provenance transfer, never mutates cargo/inventory/source directly,
	## preserves eligible carried cargo via a single legitimate final delivery, and never returns to source.
	if status != Status.RUNNING:
		return {"ok": false, "action": "not_running"}

	var resolved_movement: UnitMovement = movement if movement != null else _movement
	if resolved_movement != null:
		_movement = resolved_movement

	_community_cancel_requested = true
	_stop_after_delivery = true

	if _phase == Phase.DELIVERING_TO_CAMP:
		return {"ok": true, "action": "finish_current_delivery"}

	if use_provenance_transactions and is_provenance_transfer_executing():
		return {"ok": true, "action": "deferred_during_transfer"}

	if use_provenance_transactions and _active_gather_session != null:
		var recovered: Dictionary = _active_gather_session.cancel_intent(source, _unit)
		if not recovered.is_empty():
			last_extraction_receipt = recovered.duplicate(true)
			last_extracted_units = 0
			last_extraction_replayed = true
		_active_gather_session = null

	var carry_load: UnitCarryLoad = _unit.get_carry_load() if (_unit != null and is_instance_valid(_unit)) else null
	if _can_start_delivery_with_current_cargo(carry_load):
		_awaiting_felling_before_delivery = false
		_disconnect_navigation_signals()
		if resolved_movement != null:
			resolved_movement.stop_movement()
		_start_delivering(resolved_movement)
		return {"ok": true, "action": "transitioned_to_final_delivery"}

	return {"ok": true, "action": "cancel_immediately"}


func _apply_deferred_community_cancel(movement: UnitMovement) -> void:
	if status != Status.RUNNING:
		return
	if _phase == Phase.DELIVERING_TO_CAMP:
		_stop_after_delivery = true
		return
	if use_provenance_transactions and is_provenance_transfer_executing():
		return

	if use_provenance_transactions and _active_gather_session != null:
		var recovered: Dictionary = _active_gather_session.cancel_intent(source, _unit)
		if not recovered.is_empty():
			last_extraction_receipt = recovered.duplicate(true)
			last_extracted_units = 0
			last_extraction_replayed = true
		_active_gather_session = null

	_awaiting_felling_before_delivery = false
	_disconnect_navigation_signals()
	var resolved_movement: UnitMovement = movement if movement != null else _movement
	if resolved_movement != null:
		_movement = resolved_movement
	var carry_load: UnitCarryLoad = _unit.get_carry_load() if (_unit != null and is_instance_valid(_unit)) else null
	if _can_start_delivery_with_current_cargo(carry_load):
		if resolved_movement != null:
			resolved_movement.stop_movement()
		_start_delivering(resolved_movement)
		return

	if resolved_movement != null:
		resolved_movement.stop_movement()
	_finish_cancelled(REASON_COMMUNITY_WORK_CANCELLED)


func _create_gather_session() -> GatherTransferSession:
	return GatherTransferSession.new()


func _create_selective_deliver_order() -> DeliverToCampOrder:
	return DeliverToCampOrder.new(camp_zone, inventory, true, region_id, [])


func _start_approaching_source(movement: UnitMovement) -> void:
	_awaiting_felling_before_delivery = false
	if movement != null:
		movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	if not _is_source_usable():
		_handle_source_unavailable(movement)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if not carry_load.can_fit_one(source.get_definition()):
		if _can_start_delivery_with_current_cargo(carry_load):
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
		if use_provenance_transactions and _world_nav.get_pending_route_reason(_unit.global_position, source.global_position) == "pending_building_nav_sync":
			_wait_for_navigation()
			return
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
			if use_provenance_transactions:
				_start_approaching_source(movement)
			else:
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
	var dt: float = maxf(delta, 0.0)
	if use_provenance_transactions and _active_gather_session != null:
		if _active_gather_session.is_retry_scheduled():
			if source != null and is_instance_valid(source) and source.is_inside_tree():
				movement.face_towards(source.global_position, dt)
			if _active_gather_session.retry_is_due(dt):
				_execute_active_gather_session(movement)
			return
		if _active_gather_session.is_outcome_uncertain():
			_finish_failed("unknown_transaction_outcome")
			return

	if not _is_source_usable():
		_awaiting_felling_before_delivery = false
		_handle_source_unavailable(movement)
		return

	if _awaiting_felling_before_delivery:
		movement.face_towards(source.global_position, dt)
		if source.is_felling():
			return
		_awaiting_felling_before_delivery = false
		var felling_load: UnitCarryLoad = _unit.get_carry_load()
		if _can_start_delivery_with_current_cargo(felling_load):
			_start_delivering(movement)
		else:
			_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	var def: ResourceDefinition = source.get_definition()
	if not carry_load.can_fit_one(def):
		if _can_start_delivery_with_current_cargo(carry_load):
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
	if not use_provenance_transactions:
		_execute_legacy_gather_extraction(movement, carry_load, def)
		return

	if source.max_extract_per_operation <= 0:
		_finish_failed(REASON_INVALID_SOURCE)
		return

	_gather_cycle_serial += 1
	var session: GatherTransferSession = _create_gather_session()
	var init_res: Dictionary = session.initialize_cycle(
		inventory,
		camp_zone,
		source,
		_unit,
		region_id,
		get_instance_id(),
		_gather_cycle_serial,
		source.max_extract_per_operation
	)
	if not bool(init_res.get("ok", false)):
		_finish_failed(String(init_res.get("reason", REASON_INVALID_SOURCE)))
		return

	_active_gather_session = session
	_execute_active_gather_session(movement)


func _execute_legacy_gather_extraction(
	movement: UnitMovement,
	carry_load: UnitCarryLoad,
	def: ResourceDefinition
) -> void:
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


func _execute_active_gather_session(movement: UnitMovement) -> void:
	if _active_gather_session == null:
		return
	var in_range: bool = _is_unit_in_working_range(_unit.global_position)
	var result: Dictionary = _active_gather_session.execute_or_retry(
		inventory,
		camp_zone,
		source,
		_unit,
		region_id,
		get_instance_id(),
		in_range
	)
	if status != Status.RUNNING:
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	var def: ResourceDefinition = source.get_definition() if is_instance_valid(source) else null
	if bool(result.get("ok", false)):
		last_extraction_replayed = bool(result.get("replayed", false))
		last_extracted_units = int(result.get("extracted", 0))
		last_extraction_receipt = (result.get("receipt", {}) as Dictionary).duplicate(true)
		if not last_extraction_replayed and last_extracted_units > 0:
			total_extracted_units += last_extracted_units
			extraction_cycles_completed += 1
		_active_gather_session = null

		if _community_cancel_requested:
			_apply_deferred_community_cancel(movement)
			return

		var source_gone_or_depleted: bool = not _is_source_usable()
		var needs_delivery: bool = (
			carry_load == null
			or carry_load.is_full()
			or def == null
			or not carry_load.can_fit_one(def)
			or source_gone_or_depleted
		)
		if needs_delivery:
			if source != null and is_instance_valid(source) and source.is_felling():
				_awaiting_felling_before_delivery = true
			elif _can_start_delivery_with_current_cargo(carry_load):
				_start_delivering(movement)
			elif source_gone_or_depleted:
				_handle_source_unavailable(movement)
			else:
				_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
		return

	var reason: String = String(result.get("reason", REASON_INVALID_SOURCE))
	if _community_cancel_requested:
		_apply_deferred_community_cancel(movement)
		return
	if reason == "busy" and _active_gather_session.is_retry_scheduled():
		return

	_active_gather_session = null
	if reason == "capacity":
		if _can_start_delivery_with_current_cargo(carry_load):
			if source != null and is_instance_valid(source) and source.is_felling():
				_awaiting_felling_before_delivery = true
			else:
				_start_delivering(movement)
		elif not _is_source_usable():
			_handle_source_unavailable(movement)
		else:
			_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
		return
	if (reason == "source_depleted" or reason == "unavailable" or reason == "invalid_source") and not _is_source_usable():
		_handle_source_unavailable(movement)
		return
	_finish_failed(reason)


func _start_delivering(movement: UnitMovement) -> void:
	# Free the source slot while transporting so other workers can approach or gather.
	_release_source_reservation()
	_phase = Phase.DELIVERING_TO_CAMP
	resolved_target = Vector3(INF, INF, INF)
	_unit.set_order_state(self, Unit.State.TRANSPORTING)

	if use_provenance_transactions:
		_deliver_order = _create_selective_deliver_order()
	else:
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
		if use_provenance_transactions:
			_delivered_trips += _deliver_order.trips_completed
			last_delivery_receipt = _deliver_order.last_receipt.duplicate(true)
		else:
			_delivered_trips += 1
		_deliver_order = null
		if _stop_after_delivery or not _is_source_usable():
			_finish_succeeded()
			return

		var carry_load: UnitCarryLoad = _unit.get_carry_load()
		if carry_load == null or not carry_load.can_fit_one(source.get_definition()):
			_finish_failed(REASON_INSUFFICIENT_CARRY_CAPACITY)
			return
		if use_provenance_transactions and not carry_load.validate_provenance():
			_finish_failed("unreconciled_cargo")
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
	if _can_start_delivery_with_current_cargo(carry_load):
		_start_delivering(movement)
		return
	if _delivered_trips > 0:
		_finish_succeeded()
	elif use_provenance_transactions and (source == null or not is_instance_valid(source) or not source.is_inside_tree()):
		_finish_failed(REASON_INVALID_SOURCE)
	else:
		_finish_failed(REASON_SOURCE_DEPLETED)


func _can_start_delivery_with_current_cargo(carry_load: UnitCarryLoad) -> bool:
	if carry_load == null or carry_load.is_empty():
		return false
	if not use_provenance_transactions:
		return true
	return _has_eligible_free_lots(carry_load)


func _has_eligible_free_lots(carry_load: UnitCarryLoad) -> bool:
	if carry_load == null or not carry_load.is_provenance_enabled() or not carry_load.validate_provenance():
		return false
	var snap: Dictionary = carry_load.provenance_snapshot()
	var ledger_dict: Dictionary = snap.get("ledger", {}) as Dictionary
	var lots: Dictionary = ledger_dict.get("lots", {}) as Dictionary
	for lot_v: Variant in lots.values():
		if not (lot_v is Dictionary):
			continue
		var lot: Dictionary = lot_v as Dictionary
		if StringName(lot.get("origin", &"")) == CarryProvenanceLedger.FREE_GATHERED and int(lot.get("quantity", 0)) > 0:
			return true
	return false


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


func _wait_for_navigation() -> void:
	_waiting_for_navigation = true
	if _movement != null:
		_movement.stop_movement()
	if _nav_signals_bound or _world_nav == null or not is_instance_valid(_world_nav):
		return
	if not _world_nav.navigation_ready.is_connected(_on_pending_navigation_ready):
		_world_nav.navigation_ready.connect(_on_pending_navigation_ready)
	if not _world_nav.navigation_failed.is_connected(_on_pending_navigation_failed):
		_world_nav.navigation_failed.connect(_on_pending_navigation_failed)
	if not _world_nav.navigation_rebake_degraded.is_connected(_on_pending_navigation_degraded):
		_world_nav.navigation_rebake_degraded.connect(_on_pending_navigation_degraded)
	_nav_signals_bound = true


func _disconnect_navigation_signals() -> void:
	_waiting_for_navigation = false
	_deferred_navigation_failure = false
	if not _nav_signals_bound:
		return
	if _world_nav != null and is_instance_valid(_world_nav):
		if _world_nav.navigation_ready.is_connected(_on_pending_navigation_ready):
			_world_nav.navigation_ready.disconnect(_on_pending_navigation_ready)
		if _world_nav.navigation_failed.is_connected(_on_pending_navigation_failed):
			_world_nav.navigation_failed.disconnect(_on_pending_navigation_failed)
		if _world_nav.navigation_rebake_degraded.is_connected(_on_pending_navigation_degraded):
			_world_nav.navigation_rebake_degraded.disconnect(_on_pending_navigation_degraded)
	_nav_signals_bound = false


func _on_pending_navigation_ready() -> void:
	_waiting_for_navigation = false
	_replan_requested = true


func _on_pending_navigation_failed(_reason: String) -> void:
	if _waiting_for_navigation:
		_waiting_for_navigation = false
		if use_provenance_transactions and is_provenance_transfer_executing():
			_deferred_navigation_failure = true
			return
		_finish_failed(REASON_NAVIGATION_NOT_READY)


func _on_pending_navigation_degraded(_count: int, _reason: String) -> void:
	if _waiting_for_navigation:
		_waiting_for_navigation = false
		if use_provenance_transactions and is_provenance_transfer_executing():
			_deferred_navigation_failure = true
			return
		_finish_failed(REASON_SOURCE_UNREACHABLE)


func _finish_succeeded() -> void:
	_disconnect_navigation_signals()
	_active_gather_session = null
	resolved_target = Vector3(INF, INF, INF)
	_deliver_order = null
	_release_source_reservation()
	if _movement != null:
		_movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	mark_succeeded()


func _finish_failed(reason: String) -> void:
	_disconnect_navigation_signals()
	if use_provenance_transactions and _active_gather_session != null:
		_active_gather_session.cancel_intent(source, _unit)
		_active_gather_session = null
	resolved_target = Vector3(INF, INF, INF)
	_deliver_order = null
	_release_source_reservation()
	if _movement != null:
		if use_provenance_transactions:
			_movement.stop_movement()
		_movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	mark_failed(reason)


func _finish_cancelled(reason: String) -> void:
	_disconnect_navigation_signals()
	if use_provenance_transactions and _active_gather_session != null:
		_active_gather_session.cancel_intent(source, _unit)
		_active_gather_session = null
	resolved_target = Vector3(INF, INF, INF)
	_deliver_order = null
	_release_source_reservation()
	if _movement != null:
		_movement.stop_movement()
		_movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
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
