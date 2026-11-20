class_name CancellationRecoveryDispatcher
extends Node
## Event-driven regional dispatch. No per-frame scan, worker creation or RTS command.

var _inventory: SettlementInventory
var _camp: CampStorageZone
var _nav: WorldNavigation
var _region: StringName
var _entries: Dictionary = {}
var _pending: Array[Dictionary] = []
var _flush_queued: bool = false
var _assigning: bool = false


func configure(inventory: SettlementInventory, camp: CampStorageZone, nav: WorldNavigation, region: StringName) -> void:
	_inventory = inventory
	_camp = camp
	_nav = nav
	_region = region
	_inventory.inventory_changed.connect(_on_safe_event)
	_nav.navigation_ready.connect(_on_safe_event)
	set_process(false)
	set_physics_process(false)


func schedule_committed(cancel_id: StringName, cargo: Array) -> void:
	var record := _record(cancel_id)
	if record == null or not record.has_unsettled_custody():
		return
	for entry: Dictionary in cargo:
		var uid: StringName = entry.before.unit_id
		if record.assigned_unit_ids.has(uid) or record.transit_lots_by_unit.has(uid):
			_pending.append({"cancel_id": cancel_id, "unit_id": uid, "revision": entry.order_revision})
	_queue_flush()


func assign(cancel_id: StringName, units: Array[Unit]) -> Dictionary:
	if _assigning or _busy():
		return {"ok": false, "reason": "busy", "assigned": 0}
	var count := 0
	var seen: Dictionary = {}
	for unit: Unit in units:
		if not is_instance_valid(unit) or seen.has(unit.get_instance_id()):
			continue
		seen[unit.get_instance_id()] = true
		if _assign(cancel_id, unit, unit.get_order_revision(), true):
			count += 1
	return {"ok": count > 0, "reason": "" if count > 0 else "no_eligible_worker", "assigned": count}


func _record(cancel_id: StringName) -> ReservedWithdrawalCoordinator.CancellationCustodyRecord:
	if not is_instance_valid(_camp) or not _camp.is_inside_tree():
		return null
	return CancellationRecoveryTransaction._record(_camp.get_world_3d(), _region, cancel_id)


func _busy() -> bool:
	return not is_instance_valid(_camp) or not _camp.is_inside_tree() or ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(_camp.get_world_3d(), _region) or _inventory.is_transaction_busy()


func _assign(cancel_id: StringName, unit: Unit, expected_revision: int, explicit: bool) -> bool:
	if _assigning or _busy() or not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion() or unit.get_order_revision() != expected_revision:
		return false
	var uid := unit.get_character_id()
	var prior: Dictionary = _entries.get(uid, {})
	if not explicit and prior.get("manual", false):
		return false
	var record := _record(cancel_id)
	if record == null or not record.has_unsettled_custody() or not ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(_camp.get_world_3d(), _region, unit, unit.get_carry_load(), get_tree()).ok:
		return false
	var current := unit.get_current_order()
	if current is RecoveryOrder:
		return current.cancel_id == cancel_id and current.is_active()
	if current != null and current.is_active():
		if not current is ConstructOrder or not is_instance_valid(current.site) or current.site.site_id != record.site_id or current.site.get_site_state() != ConstructionSite.SiteState.CANCELLED:
			return false
	if not prior.is_empty() and prior.get("unit") is WeakRef:
		var previous := prior.unit.get_ref() as Unit
		if is_instance_valid(previous) and previous.order_finished.is_connected(prior.callback):
			previous.order_finished.disconnect(prior.callback)
	var order := RecoveryOrder.new(cancel_id, _region, _camp, _inventory, self)
	var callback := _on_order_finished.bind(uid)
	_entries[uid] = {"unit": weakref(unit), "order": order, "callback": callback, "cancel_id": cancel_id, "revision": expected_revision + 1, "manual": false}
	if not unit.order_finished.is_connected(callback):
		unit.order_finished.connect(callback)
	_assigning = true
	unit.issue_order(order)
	_assigning = false
	if unit.get_current_order() != order:
		if not order.is_finished():
			order.mark_cancelled(UnitOrder.REASON_REPLACED)
		_entries[uid].manual = true
		_entries[uid].order = null
		_entries[uid].revision = unit.get_order_revision()
	if unit.get_current_order() == order and order.is_active() and not record.recovery_unit_ids.has(uid):
		record.recovery_unit_ids.append(uid)
		record.revision += 1
	return unit.get_current_order() == order and order.is_active()


func _on_order_finished(order: UnitOrder, uid: StringName) -> void:
	var entry: Dictionary = _entries.get(uid, {})
	if entry.is_empty() or entry.order != order:
		return
	entry.order = null
	entry.manual = order is RecoveryOrder and order.manual_interruption
	var unit := entry.unit.get_ref() as Unit
	if is_instance_valid(unit):
		entry.revision = unit.get_order_revision()
	notify_progress(entry.cancel_id)


func notify_progress(cancel_id: StringName) -> void:
	for entry: Dictionary in _entries.values():
		if entry.cancel_id == cancel_id and entry.order is RecoveryOrder:
			entry.order.wake_up()


func _on_safe_event() -> void:
	# Only previously assigned technical failures are eligible. Manual overrides persist.
	for uid: StringName in _entries:
		var entry: Dictionary = _entries[uid]
		if entry.order is RecoveryOrder:
			entry.order.wake_up()
		elif not entry.manual:
			_pending.append({"cancel_id": entry.cancel_id, "unit_id": uid, "revision": entry.revision})
	_queue_flush()


func _queue_flush() -> void:
	if not _flush_queued and is_inside_tree():
		_flush_queued = true
		call_deferred("_flush")


func _flush() -> void:
	_flush_queued = false
	if not is_inside_tree():
		return
	var pending := _pending
	_pending = []
	for request: Dictionary in pending:
		for node: Node in get_tree().get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
			var unit := node as Unit
			if is_instance_valid(unit) and unit.is_inside_tree() and unit.get_character_id() == request.unit_id and unit.get_world_3d() == _camp.get_world_3d():
				_assign(request.cancel_id, unit, request.revision, false)


func _exit_tree() -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_on_safe_event):
		_inventory.inventory_changed.disconnect(_on_safe_event)
	if is_instance_valid(_nav) and _nav.navigation_ready.is_connected(_on_safe_event):
		_nav.navigation_ready.disconnect(_on_safe_event)
	for entry: Dictionary in _entries.values():
		var unit := entry.unit.get_ref() as Unit
		if is_instance_valid(unit) and unit.order_finished.is_connected(entry.callback):
			unit.order_finished.disconnect(entry.callback)
	_entries.clear()
	_pending.clear()
