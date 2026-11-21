class_name CommunityTaskDispatcher
extends Node
## Minimal RUX-1 event-driven community task dispatcher.
## Zero per-frame polling: reacts to board, unit, and navigation signals via deferred coalesced passes.
## Never holds economic balances or overwrites active manual orders.

signal task_assigned(task: WorkTask, unit: Unit, order: GatherResourceOrder)
signal task_waiting(task: WorkTask, reason: String)
signal task_feedback(message: String)

var _board: CommunityWorkBoard = null
var _command_controller: CommandController = null
var _world_nav: WorldNavigation = null
var _units_root: Node = null
var _camp_zone: CampStorageZone = null
var _inventory: SettlementInventory = null
var _region_id: StringName = &"default"
var _use_provenance: bool = true

var _unit_callbacks: Dictionary = {}
var _flush_queued: bool = false
var _dispatching: bool = false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func _exit_tree() -> void:
	_unbind_all()


func configure(
	p_board: CommunityWorkBoard,
	p_command_controller: CommandController,
	p_world_nav: WorldNavigation,
	p_units_root: Node,
	p_camp_zone: CampStorageZone,
	p_inventory: SettlementInventory,
	p_region_id: StringName = &"default",
	p_use_provenance: bool = true
) -> void:
	_unbind_all()
	_board = p_board
	_command_controller = p_command_controller
	_world_nav = p_world_nav
	_units_root = p_units_root
	_camp_zone = p_camp_zone
	_inventory = p_inventory
	_region_id = p_region_id if not p_region_id.is_empty() else &"default"
	_use_provenance = p_use_provenance

	if _board != null and is_instance_valid(_board):
		_board.task_registered.connect(_on_board_task_registered)
		_board.task_updated.connect(_on_board_task_updated)
		_board.task_closed.connect(_on_board_task_closed)
	if _world_nav != null and is_instance_valid(_world_nav):
		_world_nav.navigation_ready.connect(_on_navigation_ready)
	if _inventory != null:
		if not _inventory.inventory_changed.is_connected(_on_inventory_changed):
			_inventory.inventory_changed.connect(_on_inventory_changed)
	if _units_root != null and is_instance_valid(_units_root):
		_units_root.child_entered_tree.connect(_on_units_child_entered)
		_units_root.child_exiting_tree.connect(_on_units_child_exiting)
		for child: Node in _units_root.get_children():
			if child is Unit:
				_bind_unit(child as Unit)

	request_dispatch()


func request_dispatch() -> void:
	if not is_inside_tree():
		return
	if _flush_queued:
		return
	_flush_queued = true
	call_deferred("_flush_dispatch")


func _unbind_all() -> void:
	_flush_queued = false
	if _board != null and is_instance_valid(_board):
		if _board.task_registered.is_connected(_on_board_task_registered):
			_board.task_registered.disconnect(_on_board_task_registered)
		if _board.task_updated.is_connected(_on_board_task_updated):
			_board.task_updated.disconnect(_on_board_task_updated)
		if _board.task_closed.is_connected(_on_board_task_closed):
			_board.task_closed.disconnect(_on_board_task_closed)
	if _world_nav != null and is_instance_valid(_world_nav):
		if _world_nav.navigation_ready.is_connected(_on_navigation_ready):
			_world_nav.navigation_ready.disconnect(_on_navigation_ready)
	if _inventory != null:
		if _inventory.inventory_changed.is_connected(_on_inventory_changed):
			_inventory.inventory_changed.disconnect(_on_inventory_changed)
	if _units_root != null and is_instance_valid(_units_root):
		if _units_root.child_entered_tree.is_connected(_on_units_child_entered):
			_units_root.child_entered_tree.disconnect(_on_units_child_entered)
		if _units_root.child_exiting_tree.is_connected(_on_units_child_exiting):
			_units_root.child_exiting_tree.disconnect(_on_units_child_exiting)
	for uid_key: Variant in _unit_callbacks.keys():
		var uid: int = int(uid_key)
		var entry: Dictionary = _unit_callbacks[uid] as Dictionary
		var unit_ref: WeakRef = entry.get("unit_ref") as WeakRef
		var unit: Unit = (unit_ref.get_ref() as Unit) if unit_ref != null else null
		_disconnect_unit_entry(unit, entry)
	_unit_callbacks.clear()


func _bind_unit(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var uid: int = unit.get_instance_id()
	if _unit_callbacks.has(uid):
		return
	var on_finished: Callable = Callable(self, "_on_unit_order_finished").bind(uid)
	var on_state: Callable = Callable(self, "_on_unit_state_changed").bind(uid)
	var on_exit: Callable = Callable(self, "_on_unit_tree_exited").bind(uid)
	unit.order_finished.connect(on_finished)
	unit.state_changed.connect(on_state)
	unit.tree_exited.connect(on_exit)
	_unit_callbacks[uid] = {
		"unit_ref": weakref(unit),
		"on_finished": on_finished,
		"on_state": on_state,
		"on_exit": on_exit,
	}


func _unbind_unit(uid: int, unit: Unit = null) -> void:
	if not _unit_callbacks.has(uid):
		return
	var entry: Dictionary = _unit_callbacks[uid] as Dictionary
	_unit_callbacks.erase(uid)
	var resolved: Unit = unit
	if resolved == null or not is_instance_valid(resolved):
		var unit_ref: WeakRef = entry.get("unit_ref") as WeakRef
		resolved = (unit_ref.get_ref() as Unit) if unit_ref != null else null
	_disconnect_unit_entry(resolved, entry)


func _disconnect_unit_entry(unit: Unit, entry: Dictionary) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var on_finished: Callable = entry.get("on_finished", Callable()) as Callable
	var on_state: Callable = entry.get("on_state", Callable()) as Callable
	var on_exit: Callable = entry.get("on_exit", Callable()) as Callable
	if on_finished.is_valid() and unit.order_finished.is_connected(on_finished):
		unit.order_finished.disconnect(on_finished)
	if on_state.is_valid() and unit.state_changed.is_connected(on_state):
		unit.state_changed.disconnect(on_state)
	if on_exit.is_valid() and unit.tree_exited.is_connected(on_exit):
		unit.tree_exited.disconnect(on_exit)


func _on_units_child_entered(child: Node) -> void:
	if child is Unit:
		_bind_unit(child as Unit)
		request_dispatch()


func _on_units_child_exiting(child: Node) -> void:
	if child is Unit:
		var unit: Unit = child as Unit
		_handle_unit_unavailable(unit.get_instance_id())
		_unbind_unit(unit.get_instance_id(), unit)


func _on_unit_tree_exited(uid: int) -> void:
	_handle_unit_unavailable(uid)
	_unbind_unit(uid, null)


func _handle_unit_unavailable(uid: int) -> void:
	if _board == null or not is_instance_valid(_board):
		return
	for task: WorkTask in _board.get_active_tasks():
		if task.assigned_unit != null and task.assigned_unit.get_instance_id() == uid:
			task.clear_assignment()
			if task.is_source_usable():
				task.state = WorkTask.State.PENDING_WORKERS
				_board.notify_task_updated(task)
			else:
				_board.close_task(task, WorkTask.State.FAILED, "invalid_source")
	request_dispatch()


func _on_board_task_registered(_task: WorkTask) -> void:
	request_dispatch()


func _on_board_task_updated(_task: WorkTask) -> void:
	request_dispatch()


func _on_board_task_closed(_task: WorkTask) -> void:
	request_dispatch()


func _on_navigation_ready() -> void:
	request_dispatch()


func _on_inventory_changed() -> void:
	request_dispatch()


func _on_unit_state_changed(new_state: Unit.State, _previous_state: Unit.State, _uid: int) -> void:
	if new_state == Unit.State.IDLE:
		request_dispatch()


func _on_unit_order_finished(finished_order: UnitOrder, uid: int) -> void:
	if _board != null and is_instance_valid(_board):
		for task: WorkTask in _board.get_active_tasks():
			if task.assigned_order == finished_order:
				_handle_assigned_order_finished(task, finished_order, uid)
				break
	# Always defer dispatch so Unit.issue_order() finishes installing any replacing manual order first.
	request_dispatch()


func _handle_assigned_order_finished(task: WorkTask, finished_order: UnitOrder, uid: int) -> void:
	task.clear_assignment()

	if finished_order.is_succeeded():
		if not task.is_source_usable():
			_board.close_task(task, WorkTask.State.COMPLETED, "")
			task_feedback.emit("Corte de madeira concluído.")
		else:
			task.state = WorkTask.State.PENDING_WORKERS
			task.last_reason = ""
			_board.notify_task_updated(task)
		return

	if finished_order.status == UnitOrder.Status.CANCELLED:
		# A manual order replaced or explicitly cancelled this worker's task participation:
		# never silently reassign the same interrupted task back onto this worker.
		if finished_order.failure_reason == UnitOrder.REASON_REPLACED or finished_order.failure_reason == UnitOrder.REASON_CANCELLED:
			task.excluded_unit_ids[uid] = true
		if task.is_source_usable():
			task.state = WorkTask.State.PENDING_WORKERS
			task.last_reason = finished_order.failure_reason
			_board.notify_task_updated(task)
		else:
			_board.close_task(task, WorkTask.State.FAILED, "invalid_source")
		return

	var reason: String = finished_order.failure_reason
	if (
		reason == GatherResourceOrder.REASON_SOURCE_UNREACHABLE
		or reason == UnitOrder.REASON_STUCK
		or reason == GatherResourceOrder.REASON_SOURCE_DEPLETED
		or reason == GatherResourceOrder.REASON_INVALID_SOURCE
	):
		_board.close_task(task, WorkTask.State.FAILED, reason)
		if reason == GatherResourceOrder.REASON_SOURCE_UNREACHABLE or reason == UnitOrder.REASON_STUCK:
			task_feedback.emit("Árvore inacessível.")
		return

	if not task.is_source_usable():
		_board.close_task(task, WorkTask.State.FAILED, "invalid_source")
		return

	task.state = WorkTask.State.PENDING_WORKERS
	task.last_reason = reason
	_board.notify_task_updated(task)


func _flush_dispatch() -> void:
	if _dispatching:
		return
	_flush_queued = false
	if not is_inside_tree() or _board == null or not is_instance_valid(_board) or _command_controller == null or not is_instance_valid(_command_controller):
		return

	_dispatching = true
	var active_tasks: Array[WorkTask] = _board.get_active_tasks()
	for task: WorkTask in active_tasks:
		if not task.is_active():
			continue
		_process_single_task(task)
	_dispatching = false

	if _flush_queued and is_inside_tree():
		call_deferred("_flush_dispatch")


func _process_single_task(task: WorkTask) -> void:
	if task.assigned_unit != null:
		var u: Unit = task.assigned_unit
		var order_still_valid: bool = (
			is_instance_valid(u)
			and u.is_inside_tree()
			and task.assigned_order != null
			and task.assigned_order.is_active()
			and u.get_current_order() == task.assigned_order
			and u.get_order_revision() == task.assigned_order_revision
		)
		if order_still_valid:
			return
		task.clear_assignment()
		task.state = WorkTask.State.PENDING_WORKERS

	if not task.is_source_usable():
		var unusable_reason: String = "source_depleted" if (task.is_source_valid() and task.source.is_depleted()) else "invalid_source"
		_board.close_task(task, WorkTask.State.FAILED, unusable_reason)
		return

	if _world_nav == null or not is_instance_valid(_world_nav) or not _world_nav.is_navigation_ready():
		_mark_task_waiting(task, "navigation_not_ready", "")
		return

	if _is_economy_busy(task.source):
		_mark_task_waiting(task, "economy_busy", "")
		return

	var candidates: Array[Unit] = _collect_sorted_candidates(task.source.global_position)
	if candidates.is_empty():
		_mark_task_waiting(task, "no_workers", "Aguardando trabalhador disponível.")
		return

	var chosen_unit: Unit = null
	var has_temporary_wait: bool = false
	var any_unreachable: bool = false
	var first_reason: String = ""

	for unit: Unit in candidates:
		var pre_reason: String = _check_pre_nav_eligibility(unit, task)
		if not pre_reason.is_empty():
			if pre_reason in ["busy", "not_idle", "transaction_locked", "no_worker_slot"]:
				has_temporary_wait = true
			if first_reason.is_empty():
				first_reason = pre_reason
			continue

		var occupied: Array[Vector3] = GatherSlotPlanner.collect_other_unit_positions(unit, true)
		var slot: Dictionary = GatherSlotPlanner.compute_source_approach_slot(
			unit.global_position,
			task.source,
			_world_nav,
			occupied
		)
		if bool(slot.get("valid", false)):
			chosen_unit = unit
			break

		any_unreachable = true
		if first_reason.is_empty():
			first_reason = "source_unreachable"

	if chosen_unit == null:
		if any_unreachable and not has_temporary_wait:
			_board.close_task(task, WorkTask.State.FAILED, "source_unreachable")
			task_feedback.emit("Árvore inacessível.")
			return
		var wait_reason: String = first_reason if not first_reason.is_empty() else "no_eligible_worker"
		var wait_msg: String = "Aguardando trabalhador disponível." if wait_reason in ["busy", "not_idle", "no_worker_slot"] else ""
		_mark_task_waiting(task, wait_reason, wait_msg)
		return

	# Final revalidation immediately before issuing command (guards against reentrancy).
	if not _check_pre_nav_eligibility(chosen_unit, task).is_empty():
		_mark_task_waiting(task, "busy", "")
		return

	var dispatch_res: Dictionary = _command_controller.command_units_to_gather(task.source, [chosen_unit], false)
	if not bool(dispatch_res.get("ok", false)):
		var reject_reason: String = String(dispatch_res.get("reason", "dispatch_rejected"))
		if reject_reason in [
			GatherResourceOrder.REASON_SOURCE_UNREACHABLE,
			GatherResourceOrder.REASON_SOURCE_DEPLETED,
			"resource_source_depleted",
			"invalid_resource_source",
		]:
			_board.close_task(task, WorkTask.State.FAILED, reject_reason)
		else:
			_mark_task_waiting(task, reject_reason, "")
		return

	var assigned_orders: Dictionary = dispatch_res.get("assigned_orders", {}) as Dictionary
	var order: GatherResourceOrder = assigned_orders.get(chosen_unit.get_instance_id()) as GatherResourceOrder
	if order == null:
		_mark_task_waiting(task, "dispatch_rejected", "")
		return
	if order.is_succeeded():
		if not task.is_source_usable():
			_board.close_task(task, WorkTask.State.COMPLETED, "")
		return
	if not order.is_active():
		_mark_task_waiting(task, order.failure_reason if not order.failure_reason.is_empty() else "order_not_active", "")
		return

	task.assigned_unit = chosen_unit
	task.assigned_order = order
	task.assigned_order_revision = chosen_unit.get_order_revision()
	task.state = WorkTask.State.IN_PROGRESS
	task.last_reason = ""
	_board.notify_task_updated(task)
	task_assigned.emit(task, chosen_unit, order)

	var unit_label: String = chosen_unit.get_definition().display_name if chosen_unit.get_definition() != null else String(chosen_unit.get_character_id())
	task_feedback.emit("%s indo cortar madeira." % unit_label)


func _mark_task_waiting(task: WorkTask, reason: String, feedback_text: String) -> void:
	var changed: bool = task.state != WorkTask.State.PENDING_WORKERS or task.last_reason != reason
	task.state = WorkTask.State.PENDING_WORKERS
	task.last_reason = reason
	if changed:
		task_waiting.emit(task, reason)
		if not feedback_text.is_empty():
			task_feedback.emit(feedback_text)


func _collect_sorted_candidates(target_pos: Vector3) -> Array[Unit]:
	var units: Array[Unit] = []
	if _units_root == null or not is_instance_valid(_units_root):
		return units
	for child: Node in _units_root.get_children():
		if child is Unit:
			var unit: Unit = child as Unit
			if is_instance_valid(unit) and unit.is_inside_tree() and not unit.is_queued_for_deletion():
				units.append(unit)
	units.sort_custom(func(a: Unit, b: Unit) -> bool:
		var da: float = a.global_position.distance_squared_to(target_pos)
		var db: float = b.global_position.distance_squared_to(target_pos)
		if not is_equal_approx(da, db):
			return da < db
		var ida: String = String(a.get_character_id())
		var idb: String = String(b.get_character_id())
		if ida != idb:
			return ida < idb
		return a.get_instance_id() < b.get_instance_id()
	)
	return units


func _check_pre_nav_eligibility(unit: Unit, task: WorkTask) -> String:
	if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return "invalid_unit"
	if task.excluded_unit_ids.has(unit.get_instance_id()):
		return "manually_overridden"
	if unit.get_current_order() != null and unit.get_current_order().is_active():
		return "busy"
	if unit.get_state() != Unit.State.IDLE:
		return "not_idle"
	if unit._is_reserved_withdrawal_locked():
		return "transaction_locked"

	var carry_load: UnitCarryLoad = unit.get_carry_load()
	var def: ResourceDefinition = task.source.get_definition()
	if carry_load == null or def == null or not def.is_valid():
		return "invalid_carry_load"
	if carry_load.is_transaction_busy():
		return "transaction_locked"
	if carry_load.get_effective_capacity() < def.unit_weight:
		return "insufficient_carry_capacity"

	if _use_provenance:
		if not carry_load.is_provenance_enabled() or not carry_load.validate_provenance():
			return "unreconciled_cargo"
		if _has_non_free_provenance_lots(carry_load):
			return "reserved_or_recovery_cargo"
		if unit.get_meta(&"region_id", &"") != _region_id:
			return "unit_not_admitted"
		var world: World3D = task.source.get_world_3d()
		if world == null or unit.get_world_3d() != world:
			return "world_mismatch"
		var id_check: Dictionary = ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(
			world, _region_id, unit, carry_load, get_tree()
		)
		if not bool(id_check.get("ok", false)):
			return String(id_check.get("reason", "ambiguous_unit_identity"))

	if not task.source.has_worker_slot(unit):
		return "no_worker_slot"
	return ""


func _is_economy_busy(source: ResourceSource) -> bool:
	if _inventory == null or _camp_zone == null or not is_instance_valid(_camp_zone) or not _camp_zone.is_valid():
		return true
	if _inventory.is_transaction_busy():
		return true
	if _use_provenance:
		var world: World3D = source.get_world_3d()
		if world == null or _camp_zone.get_world_3d() != world:
			return true
		if ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, _region_id):
			return true
	return false


static func _has_non_free_provenance_lots(carry_load: UnitCarryLoad) -> bool:
	var snap: Dictionary = carry_load.provenance_snapshot()
	var ledger_dict: Dictionary = snap.get("ledger", {}) as Dictionary
	var lots: Dictionary = ledger_dict.get("lots", {}) as Dictionary
	for lot_var: Variant in lots.values():
		if not (lot_var is Dictionary):
			continue
		var lot: Dictionary = lot_var as Dictionary
		if int(lot.get("quantity", 0)) <= 0:
			continue
		if StringName(lot.get("origin", &"")) != CarryProvenanceLedger.FREE_GATHERED:
			return true
	return false
