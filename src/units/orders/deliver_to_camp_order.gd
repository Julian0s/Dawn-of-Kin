class_name DeliverToCampOrder
extends UnitOrder
## Order instructing a unit carrying physical materials to move to an accessible
## CampStorageZone slot and deposit its load into SettlementInventory.
## Supports two explicitly separated modes:
## - Legacy mode (default): preserves T2 behavior via SettlementInventory.deliver_from_carry_load().
## - Selective provenance mode (opt-in): walks physically to camp and executes
##   SelectiveCampDeliveryCoordinator through a frozen CampDeliveryTransferSession.

const TxHelpers = preload("res://src/economy/selective_camp_delivery_tx_helpers.gd")

const REASON_MISSING_ECONOMY: String = "missing_economy"
const REASON_EMPTY_LOAD: String = "empty_load"
const REASON_CAMP_UNREACHABLE: String = "camp_unreachable"
const REASON_DELIVERY_REJECTED: String = "delivery_rejected"
const REASON_PROVENANCE_OPT_IN_REQUIRED: String = "provenance_opt_in_required"
const REASON_PROVENANCE_REQUIRED: String = "provenance_required"
const MAX_APPROACH_RETRIES: int = 2

var camp_zone: CampStorageZone = null
var inventory: SettlementInventory = null
var use_selective_provenance: bool = false
var region_id: StringName = &""
var resolved_target: Vector3 = Vector3(INF, INF, INF)
var last_delivered: Dictionary = {}
var last_delivered_units: int = 0
var last_receipt: Dictionary = {}
var last_created_pile_ids: Array[int] = []
var last_replayed: bool = false
var trips_completed: int = 0

var _unit: Unit = null
var _movement: UnitMovement = null
var _world_nav: WorldNavigation = null
var _requested_lots: Variant = []
var _selective_session: CampDeliveryTransferSession = null
var _last_nav_revision: int = -1
var _last_camp_config_revision: int = -1
var _approach_retries: int = 0
var _arrived_at_slot: bool = false
var _waiting_for_navigation: bool = false
var _replan_requested: bool = false
var _deferred_navigation_failure: bool = false
var _nav_signals_bound: bool = false


func _init(
	p_camp_zone: CampStorageZone = null,
	p_inventory: SettlementInventory = null,
	p_use_selective_provenance: bool = false,
	p_region_id: StringName = &"",
	p_requested_lots: Variant = []
) -> void:
	camp_zone = p_camp_zone
	inventory = p_inventory
	use_selective_provenance = p_use_selective_provenance
	region_id = p_region_id
	_requested_lots = p_requested_lots.duplicate(true) if p_requested_lots is Array else p_requested_lots
	if use_selective_provenance:
		_selective_session = CampDeliveryTransferSession.new()


func get_order_name() -> String:
	return "DeliverToCampOrder"


func is_selective_mode() -> bool:
	return use_selective_provenance


func get_delivered_trips() -> int:
	return trips_completed


func get_selective_session() -> CampDeliveryTransferSession:
	return _selective_session


func is_selective_transfer_executing() -> bool:
	if not use_selective_provenance or status != Status.RUNNING:
		return false
	if _selective_session != null and _selective_session.is_executing:
		return true
	if _unit != null and is_instance_valid(_unit):
		var load: UnitCarryLoad = _unit.get_carry_load()
		if load != null and load._coordinator_transaction_locked:
			return true
	return false


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
	_movement = movement
	var nav: WorldNavigation = world_nav if world_nav != null else movement.get_world_navigation()
	if nav == null:
		mark_failed(REASON_MISSING_NAVIGATION)
		return
	if not nav.is_navigation_ready():
		mark_failed(REASON_NAVIGATION_NOT_READY)
		return
	_world_nav = nav
	_last_nav_revision = _world_nav.get_navigation_revision()

	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid() or inventory == null:
		mark_failed(REASON_MISSING_ECONOMY)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if carry_load == null:
		mark_failed(REASON_EMPTY_LOAD if not use_selective_provenance else REASON_MISSING_ECONOMY)
		return

	if not use_selective_provenance:
		if carry_load.is_provenance_enabled():
			mark_failed(REASON_PROVENANCE_OPT_IN_REQUIRED)
			return
		if carry_load.is_empty():
			mark_failed(REASON_EMPTY_LOAD)
			return
		_start_legacy_walk(movement)
		return

	if not carry_load.is_provenance_enabled():
		mark_failed(REASON_PROVENANCE_REQUIRED)
		return
	if carry_load.is_empty():
		mark_failed(REASON_EMPTY_LOAD)
		return

	if region_id.is_empty():
		region_id = _world_nav.get_region_id()

	var init_res: Dictionary = _selective_session.initialize_intent(
		inventory, camp_zone, _unit, region_id, get_instance_id(), _requested_lots
	)
	if not bool(init_res.get("ok", false)):
		mark_failed(String(init_res.get("reason", REASON_DELIVERY_REJECTED)))
		return

	var preflight: Dictionary = CampDeliveryTransferSession.probe_preflight(
		inventory, camp_zone, _unit, region_id, _selective_session.get_requested_lots()
	)
	if not bool(preflight.get("ok", false)):
		var pre_reason: String = String(preflight.get("reason", REASON_DELIVERY_REJECTED))
		if pre_reason != "busy":
			mark_failed(pre_reason)
			return

	_approach_retries = 0
	_arrived_at_slot = false
	_last_camp_config_revision = camp_zone.get_config_revision()
	_start_selective_walk(movement, true)


func _still_owns_delivery_execution(expected_rev: int) -> bool:
	if status != Status.RUNNING:
		return false
	if _unit == null or not is_instance_valid(_unit) or not _unit.is_inside_tree() or _unit.is_queued_for_deletion():
		return false
	return expected_rev < 0 or _unit.get_order_revision() == expected_rev


func _start_legacy_walk(movement: UnitMovement) -> void:
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

	var entry_rev: int = _unit.get_order_revision() if (_unit != null and is_instance_valid(_unit)) else -1
	mark_running()
	_unit.set_order_state(self, Unit.State.TRANSPORTING)
	if not _still_owns_delivery_execution(entry_rev):
		return

	if movement.get_move_state() == UnitMovement.MoveState.ARRIVED:
		movement.stop_movement()
		_execute_delivery()


func _start_selective_walk(movement: UnitMovement, initial_start: bool) -> void:
	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_inside_tree() or camp_zone.is_queued_for_deletion():
		movement.stop_movement()
		_finish_selective_failed(REASON_CAMP_UNREACHABLE)
		return
	var occupied: Array[Vector3] = GatherSlotPlanner.collect_other_unit_positions(_unit, true)
	var slot_res: Dictionary = GatherSlotPlanner.compute_camp_dropoff_slot(
		_unit.global_position,
		camp_zone,
		_world_nav,
		occupied
	)
	if not bool(slot_res.get("valid", false)):
		if _world_nav.get_pending_route_reason(_unit.global_position, camp_zone.get_anchor_position()) == "pending_building_nav_sync":
			if initial_start:
				mark_running()
			_wait_for_navigation()
			return
		_finish_selective_failed(REASON_CAMP_UNREACHABLE)
		return

	resolved_target = slot_res["position"] as Vector3
	if not movement.begin_move_to(resolved_target):
		_finish_selective_failed(REASON_CAMP_UNREACHABLE)
		return

	var entry_rev: int = _unit.get_order_revision() if (_unit != null and is_instance_valid(_unit)) else -1
	if initial_start:
		mark_running()
	_unit.set_order_state(self, Unit.State.TRANSPORTING)
	if not _still_owns_delivery_execution(entry_rev):
		return

	# Defer the selective economic commit to physics_update rather than firing signals inside start().
	if movement.get_move_state() == UnitMovement.MoveState.ARRIVED:
		movement.stop_movement()
		_arrived_at_slot = true


func physics_update(movement: UnitMovement, delta: float) -> void:
	if status != Status.RUNNING:
		return
	if use_selective_provenance and is_selective_transfer_executing():
		_replan_requested = true
		return
	if _unit == null or not is_instance_valid(_unit) or not _unit.is_inside_tree():
		_finish_failed_any(REASON_UNIT_NOT_IN_TREE)
		return
	if movement == null:
		_finish_failed_any(REASON_MISSING_MOVEMENT)
		return
	_movement = movement

	if not use_selective_provenance:
		var legacy_load: UnitCarryLoad = _unit.get_carry_load()
		if legacy_load != null and legacy_load.is_provenance_enabled():
			movement.stop_movement()
			mark_failed(REASON_PROVENANCE_OPT_IN_REQUIRED)
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
		return

	_physics_update_selective(movement, delta)


func _physics_update_selective(movement: UnitMovement, delta: float) -> void:
	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if carry_load == null or not carry_load.is_provenance_enabled():
		movement.stop_movement()
		_finish_selective_failed(REASON_PROVENANCE_REQUIRED)
		return
	if _world_nav == null or not is_instance_valid(_world_nav) or not _world_nav.is_inside_tree() or _world_nav.is_queued_for_deletion():
		movement.stop_movement()
		_finish_selective_failed(REASON_MISSING_NAVIGATION)
		return
	if _deferred_navigation_failure:
		movement.stop_movement()
		_finish_selective_failed(REASON_CAMP_UNREACHABLE)
		return
	if not _world_nav.is_navigation_ready():
		if _world_nav._is_syncing or _world_nav._active_rebake_token != null:
			_wait_for_navigation()
			return
		movement.stop_movement()
		_finish_selective_failed(REASON_NAVIGATION_NOT_READY)
		return
	if _waiting_for_navigation:
		return

	if _selective_session.is_retry_scheduled():
		if _selective_session.retry_is_due(delta):
			_execute_selective_delivery(movement)
		return

	var current_rev: int = _world_nav.get_navigation_revision()
	var current_camp_rev: int = camp_zone.get_config_revision() if is_instance_valid(camp_zone) else -1
	if current_rev != _last_nav_revision or current_camp_rev != _last_camp_config_revision or _replan_requested:
		_last_nav_revision = current_rev
		_last_camp_config_revision = current_camp_rev
		_replan_requested = false
		if movement.get_move_state() == UnitMovement.MoveState.MOVING:
			if not _is_planned_slot_still_valid():
				if _approach_retries < MAX_APPROACH_RETRIES:
					_approach_retries += 1
					_start_selective_walk(movement, false)
					return
				movement.stop_movement()
				_finish_selective_failed(REASON_CAMP_UNREACHABLE)
				return

	match movement.get_move_state():
		UnitMovement.MoveState.MOVING:
			return
		UnitMovement.MoveState.ARRIVED:
			movement.stop_movement()
			_handle_selective_arrival(movement)
		UnitMovement.MoveState.IDLE:
			if _arrived_at_slot:
				_handle_selective_arrival(movement)
			else:
				_start_selective_walk(movement, false)
		UnitMovement.MoveState.FAILED_STUCK:
			movement.stop_movement()
			_finish_selective_failed(REASON_STUCK)
		UnitMovement.MoveState.FAILED_INVALID:
			movement.stop_movement()
			_finish_selective_failed(REASON_CAMP_UNREACHABLE)


func _is_planned_slot_still_valid() -> bool:
	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid():
		return false
	if not resolved_target.is_finite() or not camp_zone.is_position_in_bounds(resolved_target):
		return false
	var path_res: WorldNavigation.PathResult = _world_nav.find_path(_unit.global_position, resolved_target)
	return path_res.status == WorldNavigation.QueryStatus.OK and not path_res.path.is_empty()


func _handle_selective_arrival(movement: UnitMovement) -> void:
	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid() or inventory == null:
		_finish_selective_failed(REASON_MISSING_ECONOMY)
		return
	var storage: GroundPileManager = inventory.get_storage_source() as GroundPileManager
	if storage == null:
		_finish_selective_failed("unsupported_storage_source")
		return
	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	var phys_check: Dictionary = TxHelpers.check_physical_authorization_participants(
		_unit, carry_load, camp_zone, storage, _unit.get_world_3d()
	)
	if bool(phys_check.get("ok", false)):
		_arrived_at_slot = true
		_execute_selective_delivery(movement)
		return

	var phys_reason: String = String(phys_check.get("reason", "out_of_camp_dropoff_range"))
	if phys_reason != "out_of_camp_dropoff_range":
		_finish_selective_failed(phys_reason)
		return

	# If the unit already arrived and was subsequently displaced out of range, fail immediately
	# rather than authorizing a remote commit or endlessly chasing displacement.
	if _arrived_at_slot:
		_finish_selective_failed("out_of_camp_dropoff_range")
		return

	if _approach_retries < MAX_APPROACH_RETRIES:
		_approach_retries += 1
		var occupied: Array[Vector3] = GatherSlotPlanner.collect_other_unit_positions(_unit, true)
		var slot_res: Dictionary = GatherSlotPlanner.compute_camp_dropoff_slot(
			_unit.global_position, camp_zone, _world_nav, occupied
		)
		if bool(slot_res.get("valid", false)):
			var next_target: Vector3 = slot_res["position"] as Vector3
			if next_target.distance_to(_unit.global_position) > UnitMovement.ARRIVAL_TOLERANCE_XZ:
				resolved_target = next_target
				if movement.begin_move_to(resolved_target):
					_unit.set_order_state(self, Unit.State.TRANSPORTING)
					return

	_finish_selective_failed("out_of_camp_dropoff_range")


func _execute_selective_delivery(movement: UnitMovement) -> void:
	var result: Dictionary = _selective_session.execute_or_retry(
		inventory, camp_zone, _unit, region_id, get_instance_id()
	)
	if bool(result.get("ok", false)):
		last_replayed = bool(result.get("replayed", false))
		last_receipt = (result.get("receipt", {}) as Dictionary).duplicate(true)
		last_delivered = (result.get("delivered_amounts", {}) as Dictionary).duplicate(true)
		last_created_pile_ids.clear()
		for pid: Variant in (result.get("created_pile_ids", []) as Array):
			last_created_pile_ids.append(int(pid))
		last_delivered_units = int(result.get("delivered_now", 0))
		if not last_replayed and last_delivered_units > 0:
			trips_completed += 1
		resolved_target = Vector3(INF, INF, INF)
		_disconnect_navigation_signals()
		if movement != null:
			movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
		mark_succeeded()
		return

	var reason: String = String(result.get("reason", REASON_DELIVERY_REJECTED))
	if reason == "busy" and _selective_session.is_retry_scheduled():
		return

	_finish_selective_failed(reason)


func can_cancel_now() -> bool:
	return not (use_selective_provenance and is_selective_transfer_executing())


func cancel(movement: UnitMovement, reason: String = REASON_CANCELLED) -> void:
	if use_selective_provenance and is_selective_transfer_executing():
		return
	var entry_rev: int = _unit.get_order_revision() if (_unit != null and is_instance_valid(_unit)) else -1
	_disconnect_navigation_signals()
	if use_selective_provenance and _selective_session != null:
		var recovered: Dictionary = _selective_session.cancel_intent(inventory, camp_zone, _unit, region_id)
		if not recovered.is_empty():
			last_receipt = recovered.duplicate(true)
			last_delivered = (recovered.get("delivered_amounts", {}) as Dictionary).duplicate(true)
			last_created_pile_ids.clear()
			for pid: Variant in (recovered.get("created_pile_ids", []) as Array):
				last_created_pile_ids.append(int(pid))
			last_replayed = true
			last_delivered_units = 0
	resolved_target = Vector3(INF, INF, INF)
	var owns_movement: bool = (
		_unit == null
		or not is_instance_valid(_unit)
		or (
			(entry_rev < 0 or _unit.get_order_revision() == entry_rev)
			and (_unit.get_current_order() == self or _unit.get_current_order() == null)
		)
	)
	if movement != null and owns_movement:
		movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
		super.cancel(movement, reason)
	else:
		super.cancel(null, reason)


func _execute_delivery() -> void:
	if camp_zone == null or not is_instance_valid(camp_zone) or not camp_zone.is_valid() or inventory == null:
		mark_failed(REASON_MISSING_ECONOMY)
		return

	var carry_load: UnitCarryLoad = _unit.get_carry_load()
	if carry_load == null or carry_load.is_empty():
		mark_failed(REASON_EMPTY_LOAD)
		return
	if carry_load.is_provenance_enabled():
		mark_failed(REASON_PROVENANCE_OPT_IN_REQUIRED)
		return

	var delivered: Dictionary = inventory.deliver_from_carry_load(carry_load)
	if delivered.is_empty() or not carry_load.is_empty():
		last_delivered = {}
		last_delivered_units = 0
		mark_failed(REASON_DELIVERY_REJECTED)
		return

	last_delivered = delivered
	var delivered_total: int = 0
	for qty: Variant in delivered.values():
		delivered_total += int(qty)
	last_delivered_units = delivered_total
	if delivered_total > 0:
		trips_completed += 1
	resolved_target = Vector3(INF, INF, INF)
	mark_succeeded()


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
		if is_selective_transfer_executing():
			_deferred_navigation_failure = true
			return
		_finish_selective_failed(REASON_NAVIGATION_NOT_READY)


func _on_pending_navigation_degraded(_count: int, _reason: String) -> void:
	if _waiting_for_navigation:
		_waiting_for_navigation = false
		if is_selective_transfer_executing():
			_deferred_navigation_failure = true
			return
		_finish_selective_failed(REASON_CAMP_UNREACHABLE)


func _finish_selective_failed(reason: String) -> void:
	_disconnect_navigation_signals()
	last_delivered = {}
	last_delivered_units = 0
	last_receipt = {}
	last_created_pile_ids.clear()
	last_replayed = false
	resolved_target = Vector3(INF, INF, INF)
	if _movement != null:
		_movement.stop_movement()
		_movement.set_speed_context(UnitMovement.SpeedContext.NORMAL)
	mark_failed(reason)


func _finish_failed_any(reason: String) -> void:
	if use_selective_provenance:
		_finish_selective_failed(reason)
	else:
		mark_failed(reason)
