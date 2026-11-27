class_name RecoveryOrder
extends UnitOrder
## Internal composite order. Economic mutations remain in B1.3 coordinators.

const MAX_RETRIES: int = 3
const RETRY_COOLDOWN_SEC: float = 1.0
var cancel_id: StringName
var region_id: StringName
var trips_completed: int = 0
var pickups_completed: int = 0
var retries: int = 0
var manual_interruption: bool = false
var waiting_for_settlement: bool = false
var _unit: Unit
var _nav: WorldNavigation
var _camp: CampStorageZone
var _inventory: SettlementInventory
var _dispatcher: WeakRef
var _delegate: UnitOrder
var _at_pickup: bool = false
var _needs_step: bool = true
var _cooldown: float = 0.0
var _cycle: int = 0
var _updating: bool = false


func _init(id: StringName, region: StringName, camp: CampStorageZone, inventory: SettlementInventory, dispatcher: Node) -> void:
	cancel_id = id
	region_id = region
	_camp = camp
	_inventory = inventory
	_dispatcher = weakref(dispatcher)


func get_order_name() -> String:
	return "RecoveryOrder"


func get_dispatcher() -> CancellationRecoveryDispatcher:
	if _dispatcher == null:
		return null
	return _dispatcher.get_ref() as CancellationRecoveryDispatcher


func get_reserved_target() -> Vector3:
	if _delegate != null:
		return _delegate.get("resolved_target") as Vector3
	return Vector3(INF, INF, INF)


func start(unit_body: CharacterBody3D, movement: UnitMovement, nav: WorldNavigation) -> void:
	_unit = unit_body as Unit
	_nav = nav
	if not is_instance_valid(_unit) or movement == null or not is_instance_valid(_camp) or _inventory == null:
		mark_failed("invalid_recovery_participant")
		return
	mark_running()
	_unit.set_order_state(self, Unit.State.TRANSPORTING)


func wake_up() -> void:
	if not is_active():
		return
	_needs_step = true
	if waiting_for_settlement:
		waiting_for_settlement = false
	_cooldown = 0.0


func _record() -> ReservedWithdrawalCoordinator.CancellationCustodyRecord:
	if not is_instance_valid(_unit) or not _unit.is_inside_tree():
		return null
	return CancellationRecoveryTransaction._record(_unit.get_world_3d(), region_id, cancel_id)


func _blocked(reason: String, movement: UnitMovement) -> void:
	if _delegate != null and _delegate.is_active():
		_delegate.cancel(movement, reason)
	_delegate = null
	_at_pickup = false
	if movement != null:
		movement.stop_movement()
	var record := _record()
	if record != null and record.state != ConstructionCancellationMath.State.SETTLED and ReservedWithdrawalCoordinator.validate_custody_accounting_pure(record).ok:
		ReservedWithdrawalCoordinator.transition_custody_record(record, ConstructionCancellationMath.State.RETURN_BLOCKED, reason)
	retries += 1
	if retries >= MAX_RETRIES:
		mark_failed(reason)
	else:
		_cooldown = RETRY_COOLDOWN_SEC
		_needs_step = true


func physics_update(movement: UnitMovement, delta: float) -> void:
	if _updating or not is_instance_valid(_unit) or _unit._is_reserved_withdrawal_locked():
		return
	_updating = true
	_update(movement, delta)
	_updating = false


func _update(movement: UnitMovement, delta: float) -> void:
	if status != Status.RUNNING:
		return
	if not is_instance_valid(_unit) or not _unit.is_inside_tree():
		mark_failed(REASON_UNIT_EXITED)
		return
	if _cooldown > 0:
		_cooldown = maxf(0.0, _cooldown - delta)
		return
	if _delegate != null:
		_delegate.physics_update(movement, delta)
		if not _delegate.is_finished():
			return
		if not _delegate.is_succeeded():
			_blocked(_delegate.failure_reason, movement)
			return
		if _delegate is DeliverToCampOrder:
			trips_completed += 1
			_cycle += 1
			_notify_progress()
		_delegate = null
		_needs_step = true
	if not _needs_step:
		return
	_needs_step = false
	var record := _record()
	if record == null or not CancellationRecoveryTransaction.validate_transit(record, _unit, _inventory.get_storage_source() as GroundPileManager):
		_blocked("unreconciled_cancellation_custody", movement)
		return
	if record.state == ConstructionCancellationMath.State.SETTLED:
		mark_succeeded()
		return
	if _nav == null or not _nav.is_navigation_ready():
		_blocked(REASON_NAVIGATION_NOT_READY, movement)
		return
	var selection := _owned_lots(record)
	if not selection.is_empty():
		_at_pickup = false
		_delegate = DeliverToCampOrder.new(_camp, _inventory, true, region_id, selection)
		_delegate.start(_unit, movement, _nav)
		_unit.set_order_state(self, Unit.State.TRANSPORTING)
		return
	if record.get_local_custody_total() == 0:
		waiting_for_settlement = true
		return
	if _at_pickup:
		_at_pickup = false
		_pickup(record, movement)
		return
	var slot := _pickup_slot(record)
	if not slot.is_finite():
		_blocked("recovery_unreachable_or_slot_occupied", movement)
		return
	_delegate = MoveOrder.new(slot)
	_delegate.start(_unit, movement, _nav)
	_at_pickup = true


func _owned_lots(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for lot: Dictionary in _unit.get_carry_load().provenance_snapshot().get("ledger", {}).get("lots", {}).values():
		if lot.site_id == record.site_id and lot.generation == record.generation and CancellationRecoveryTransaction.CANCEL_ORIGINS.has(lot.origin):
			selected.append({"lot_id": lot.lot_id, "amount": lot.quantity})
	return selected


func _pickup_slot(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord) -> Vector3:
	var occupied := BuildSlotPlanner.collect_other_unit_positions(_unit, true)
	var best := Vector3(INF, INF, INF)
	var distance: float = INF
	var half := record.footprint_size * 0.5
	for offset: Vector2 in [Vector2(-half.x - 0.4, 0), Vector2(half.x + 0.4, 0), Vector2(0, -half.y - 0.4), Vector2(0, half.y + 0.4), Vector2(-half.x - 0.4, -half.y), Vector2(half.x + 0.4, half.y)]:
		var raw := record.anchor_position + Vector3(offset.x, 0, offset.y)
		var target := _nav.snap_to_navmesh(raw)
		if not target.is_finite() or Vector2(target.x - raw.x, target.z - raw.z).length() > 0.3 or absf(target.y - raw.y) > BuildSlotPlanner.HEIGHT_TOLERANCE:
			continue
		var separated := true
		for pos: Vector3 in occupied:
			if Vector2(pos.x - target.x, pos.z - target.z).length() < BuildSlotPlanner.BUILDER_SLOT_OCCUPANCY_RADIUS:
				separated = false
		if not separated:
			continue
		var path := _nav.find_path(_unit.global_position, target)
		if path.status != WorldNavigation.QueryStatus.OK or not BuildSlotPlanner.has_clear_physical_access(target, raw, _unit.get_world_3d()):
			continue
		var travel := _unit.global_position.distance_squared_to(target)
		if travel < distance:
			distance = travel
			best = target
	return best


func _pickup(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord, movement: UnitMovement) -> void:
	var op := StringName("recovery:%s:%s:%d:%d" % [cancel_id, _unit.get_character_id(), get_instance_id(), _cycle])
	var requests: Array[Dictionary] = []
	for origin: StringName in [CarryProvenanceLedger.CANCEL_BUFFER, CarryProvenanceLedger.CANCEL_INCORPORATED]:
		var amounts := record.local_buffer_remaining if origin == CarryProvenanceLedger.CANCEL_BUFFER else record.local_incorporated_remaining
		for resource: StringName in amounts:
			if amounts[resource] > 0:
				requests.append({"lot_id": StringName("%s:%s:%s" % [op, origin, resource]), "resource_id": resource, "amount": amounts[resource], "origin": origin})
	if requests.is_empty():
		_needs_step = true
		return
	var result := ReservedWithdrawalCoordinator.recover_cancellation_materials(cancel_id, _unit, requests, op, region_id)
	if not result.ok:
		_blocked(result.reason, movement)
		return
	pickups_completed += 1
	_cycle += 1
	retries = 0
	_needs_step = true
	_notify_progress()


func _notify_progress() -> void:
	var dispatcher: Node = _dispatcher.get_ref()
	if is_instance_valid(dispatcher) and dispatcher.is_inside_tree():
		dispatcher.call_deferred("notify_progress", cancel_id)


func cancel(movement: UnitMovement, reason: String = REASON_CANCELLED) -> void:
	if is_finished():
		return
	manual_interruption = reason == REASON_REPLACED or reason == REASON_CANCELLED
	if _delegate != null and _delegate.is_active():
		_delegate.cancel(movement, reason)
	_delegate = null
	var record := _record()
	if record != null and record.state != ConstructionCancellationMath.State.SETTLED:
		ReservedWithdrawalCoordinator.transition_custody_record(record, ConstructionCancellationMath.State.RETURN_BLOCKED, "manual_override" if manual_interruption else reason)
	super.cancel(movement, reason)
