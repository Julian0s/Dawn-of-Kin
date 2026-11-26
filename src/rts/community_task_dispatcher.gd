class_name CommunityTaskDispatcher
extends Node
## Unified event-driven community task dispatcher for single and logically grouped gather tasks (wood, stone, food).
## Zero per-frame polling: reacts to board, unit, navigation, slot-release, and inventory signals via deferred coalesced passes.
## Never holds economic balances, never overwrites active manual orders, and never silently unblocks BLOCKED_REAUTHORIZATION.

signal task_assigned(task: WorkTask, unit: Unit, order: GatherResourceOrder)
signal task_waiting(task: WorkTask, reason: String)
signal task_blocked(task: WorkTask, reason: String)
signal task_feedback(message: String)

var _board: CommunityWorkBoard = null
var _command_controller: CommandController = null
var _world_nav: WorldNavigation = null
var _units_root: Node = null
var _camp_zone: CampStorageZone = null
var _inventory: SettlementInventory = null
var _region_id: StringName = &"default"
var _use_provenance: bool = true
var _economy_admission_reason: String = ""

var _unit_callbacks: Dictionary = {}
var _flush_queued: bool = false
var _dispatching: bool = false
var _cancelling_batch_depth: int = 0
var _is_tearing_down: bool = false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)


func _exit_tree() -> void:
	teardown()


func teardown() -> void:
	_is_tearing_down = true
	_cancelling_batch_depth = 0
	_unbind_all()
	_board = null
	_command_controller = null
	_world_nav = null
	_units_root = null
	_camp_zone = null
	_inventory = null


func configure(
	p_board: CommunityWorkBoard,
	p_command_controller: CommandController,
	p_world_nav: WorldNavigation,
	p_units_root: Node,
	p_camp_zone: CampStorageZone,
	p_inventory: SettlementInventory,
	p_region_id: StringName = &"default",
	p_use_provenance: bool = true,
	p_economy_admission_reason: String = ""
) -> void:
	_unbind_all()
	_is_tearing_down = false
	_board = p_board
	_command_controller = p_command_controller
	_world_nav = p_world_nav
	_units_root = p_units_root
	_camp_zone = p_camp_zone
	_inventory = p_inventory
	_region_id = p_region_id if not p_region_id.is_empty() else &"default"
	_use_provenance = p_use_provenance
	_economy_admission_reason = p_economy_admission_reason

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
	if _is_tearing_down or not is_inside_tree():
		return
	if _flush_queued:
		return
	_flush_queued = true
	call_deferred("_flush_dispatch")


func cancel_tasks_for_sources(
	sources: Array[ResourceSource],
	resource_id: StringName,
	reason: String = WorkTask.REASON_PLAYER_CANCELLED
) -> Dictionary:
	## Selective community work cancellation (R-03A D2 / D2-B).
	## Scope: strictly (sources ∩ resource_id ∩ valid regional domain ∩ active tasks).
	## Closes tasks on the board first (under batch reentrancy guard), then cooperatively
	## reconciles each worker's GatherResourceOrder without breaking provenance transactions
	## or overwriting personal orders.
	var empty_result: Dictionary = {
		"ok": false,
		"reason": "",
		"resource_id": resource_id,
		"cancelled_count": 0,
		"cancelled_task_ids": [],
		"delivering_count": 0,
		"stopped_immediately_count": 0,
		"deferred_transfer_count": 0,
		"preserved_personal_orders_count": 0,
		"rejected_domain_count": 0,
	}
	if _is_tearing_down or _board == null or not is_instance_valid(_board):
		empty_result["reason"] = "missing_board"
		return empty_result
	if not CommunityWorkBoard.SUPPORTED_RESOURCE_IDS.has(resource_id):
		empty_result["reason"] = "unsupported_resource"
		return empty_result

	var rejected_domain_count: int = 0
	var seen_sids: Dictionary = {}
	for src: ResourceSource in sources:
		if src == null or not is_instance_valid(src):
			continue
		var sid: int = src.get_instance_id()
		if seen_sids.has(sid):
			continue
		seen_sids[sid] = true
		if not _board.is_source_in_region_domain(src):
			rejected_domain_count += 1

	var cancellable_tasks: Array[WorkTask] = _board.get_cancellable_tasks_for_sources(sources, resource_id)
	if cancellable_tasks.is_empty():
		empty_result["rejected_domain_count"] = rejected_domain_count
		empty_result["reason"] = "region_mismatch" if rejected_domain_count > 0 else "no_cancellable_tasks"
		return empty_result

	var snapshot: Array[Dictionary] = []
	for task: WorkTask in cancellable_tasks:
		snapshot.append({
			"task": task,
			"task_id": task.task_id,
			"group_id": task.group_id,
			"source": task.source,
			"source_id": task.source_id,
			"resource_id": task.resource_id,
			"region_id": task.region_id,
			"unit": task.assigned_unit,
			"order": task.assigned_order,
			"order_revision": task.assigned_order_revision,
		})

	var cancelled_task_ids: Array[int] = []
	var delivering_count: int = 0
	var stopped_immediately_count: int = 0
	var deferred_transfer_count: int = 0
	var preserved_personal_orders_count: int = 0

	_cancelling_batch_depth += 1

	# Phase 1 (board-first): close tasks as CANCELLED before touching any worker order so
	# order_finished callbacks cannot resurrect tasks or mark workers as excluded.
	for entry: Dictionary in snapshot:
		var task: WorkTask = entry["task"] as WorkTask
		if task != null and task.is_active():
			_board.close_task(task, WorkTask.State.CANCELLED, reason)
			cancelled_task_ids.append(int(entry["task_id"]))

	# Phase 2 (cooperative order reconciliation): reconcile only orders that still match
	# the exact snapshot identity & revision, preserving personal/replacement orders.
	for entry: Dictionary in snapshot:
		var unit: Unit = entry["unit"] as Unit
		var snap_order: GatherResourceOrder = entry["order"] as GatherResourceOrder
		var snap_rev: int = int(entry["order_revision"])
		if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree() or snap_order == null:
			continue
		if (
			snap_order.is_active()
			and unit.get_current_order() == snap_order
			and unit.get_order_revision() == snap_rev
		):
			var action: String = _apply_community_cancel_to_order(unit, snap_order)
			match action:
				"finish_current_delivery", "transitioned_to_final_delivery":
					delivering_count += 1
				"cancelled_immediately":
					stopped_immediately_count += 1
					if unit.get_current_order() != null and unit.get_current_order() != snap_order:
						preserved_personal_orders_count += 1
				"deferred_during_transfer":
					deferred_transfer_count += 1
				"superseded_by_newer_order":
					preserved_personal_orders_count += 1
		elif unit.get_current_order() != null and unit.get_current_order() != snap_order:
			preserved_personal_orders_count += 1

	_cancelling_batch_depth = maxi(_cancelling_batch_depth - 1, 0)
	if _cancelling_batch_depth == 0:
		request_dispatch()

	return {
		"ok": not cancelled_task_ids.is_empty(),
		"reason": "" if not cancelled_task_ids.is_empty() else "already_closed",
		"resource_id": resource_id,
		"cancelled_count": cancelled_task_ids.size(),
		"cancelled_task_ids": cancelled_task_ids,
		"delivering_count": delivering_count,
		"stopped_immediately_count": stopped_immediately_count,
		"deferred_transfer_count": deferred_transfer_count,
		"preserved_personal_orders_count": preserved_personal_orders_count,
		"rejected_domain_count": rejected_domain_count,
	}


func _apply_community_cancel_to_order(unit: Unit, order: GatherResourceOrder) -> String:
	if unit == null or not is_instance_valid(unit) or order == null or not order.is_active():
		return "not_running"
	var order_res: Dictionary = order.request_community_cancel(unit.get_movement())
	var action: String = String(order_res.get("action", "not_running"))
	if action == "cancel_immediately":
		if unit.get_current_order() == order and order.is_active():
			unit.cancel_current_order(GatherResourceOrder.REASON_COMMUNITY_WORK_CANCELLED)
		return "cancelled_immediately"
	return action


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


func _on_board_task_updated(task: WorkTask) -> void:
	if task != null and task.is_blocked_reauthorization():
		return
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
			task_feedback.emit(_completed_feedback(task.resource_id))
		else:
			task.state = WorkTask.State.PENDING_WORKERS
			task.last_reason = ""
			_board.notify_task_updated(task)
		return

	if finished_order.status == UnitOrder.Status.CANCELLED:
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
			task_feedback.emit(_unreachable_feedback(task.resource_id))
		return

	if not task.is_source_usable():
		_board.close_task(task, WorkTask.State.FAILED, "invalid_source")
		return

	task.state = WorkTask.State.PENDING_WORKERS
	task.last_reason = reason
	_board.notify_task_updated(task)


func _flush_dispatch() -> void:
	if _dispatching or _is_tearing_down:
		return
	if _cancelling_batch_depth > 0:
		_flush_queued = true
		return
	_flush_queued = false
	if not is_inside_tree() or _board == null or not is_instance_valid(_board) or _command_controller == null or not is_instance_valid(_command_controller):
		return

	_dispatching = true

	# Pass 1: validate active tasks (preserve valid running tasks, never silently unblock BLOCKED_REAUTHORIZATION, close unusable sources).
	var pending_tasks: Array[WorkTask] = []
	for task: WorkTask in _board.get_active_tasks():
		if not task.is_active():
			continue
		if task.is_blocked_reauthorization():
			if not task.is_source_usable():
				var blocked_unusable: String = "source_depleted" if (task.is_source_valid() and task.source.is_depleted()) else "invalid_source"
				_board.close_task(task, WorkTask.State.FAILED, blocked_unusable)
			continue
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
				continue
			task.clear_assignment()
			task.state = WorkTask.State.PENDING_WORKERS
		if not task.is_source_usable():
			var unusable_reason: String = "source_depleted" if (task.is_source_valid() and task.source.is_depleted()) else "invalid_source"
			_board.close_task(task, WorkTask.State.FAILED, unusable_reason)
			continue
		pending_tasks.append(task)

	# Pass 2: deterministic fair group-FIFO + spatial nearest dispatch across pending tasks.
	var ordered_groups: Array[Array] = _partition_pending_tasks_by_group_fifo(pending_tasks)
	for group_tasks: Array in ordered_groups:
		_dispatch_group_tasks(group_tasks)

	_dispatching = false

	if _flush_queued and is_inside_tree():
		call_deferred("_flush_dispatch")


func _partition_pending_tasks_by_group_fifo(pending_tasks: Array[WorkTask]) -> Array[Array]:
	var buckets: Dictionary = {}
	var group_order: Array[int] = []
	for task: WorkTask in pending_tasks:
		var gid: int = task.group_id if task.group_id > 0 else -task.task_id
		if not buckets.has(gid):
			var arr: Array[WorkTask] = []
			buckets[gid] = arr
			group_order.append(gid)
		(buckets[gid] as Array[WorkTask]).append(task)

	var result: Array[Array] = []
	for gid: int in group_order:
		result.append(buckets[gid] as Array)
	return result


func _dispatch_group_tasks(group_tasks: Array) -> void:
	# Repeatedly pair the closest available (unit, pending task) inside the group so
	# multiple workers naturally spread across distinct sources with zero starvation.
	var remaining: Array[WorkTask] = []
	for item: Variant in group_tasks:
		if item is WorkTask:
			var t: WorkTask = item as WorkTask
			if t.is_active() and t.state == WorkTask.State.PENDING_WORKERS:
				remaining.append(t)

	while not remaining.is_empty():
		var best_task: WorkTask = null
		var best_unit: Unit = null
		var best_dist_sq: float = INF
		var evaluated_any_pair: bool = false

		for task: WorkTask in remaining:
			if not task.is_active() or task.state != WorkTask.State.PENDING_WORKERS:
				continue
			if not task.is_source_usable():
				continue
			if _world_nav == null or not is_instance_valid(_world_nav) or not _world_nav.is_navigation_ready():
				continue
			if _is_economy_busy(task.source):
				continue

			var candidates: Array[Unit] = _collect_sorted_candidates(task.source.global_position)
			for unit: Unit in candidates:
				if not _check_pre_nav_eligibility(unit, task).is_empty():
					continue
				var dist_sq: float = unit.global_position.distance_squared_to(task.source.global_position)
				if dist_sq >= best_dist_sq and best_task != null:
					break
				var occupied: Array[Vector3] = GatherSlotPlanner.collect_other_unit_positions(unit, true)
				var slot: Dictionary = GatherSlotPlanner.compute_source_approach_slot(
					unit.global_position,
					task.source,
					_world_nav,
					occupied
				)
				if bool(slot.get("valid", false)):
					evaluated_any_pair = true
					if dist_sq < best_dist_sq or best_task == null:
						best_dist_sq = dist_sq
						best_task = task
						best_unit = unit
					break

		if not evaluated_any_pair or best_task == null or best_unit == null:
			break

		var dispatched: bool = _try_dispatch_unit_to_task(best_task, best_unit)
		remaining.erase(best_task)
		if not dispatched and best_task.is_active() and best_task.state == WorkTask.State.PENDING_WORKERS:
			# Fall through to final status evaluation below so this task records its wait/fail state cleanly.
			_evaluate_unassigned_task(best_task)

	# Any tasks in this group that did not receive a worker get their exact waiting / blocked / failed status.
	for task: WorkTask in remaining:
		if task.is_active() and task.state == WorkTask.State.PENDING_WORKERS and task.assigned_unit == null:
			_evaluate_unassigned_task(task)


func _try_dispatch_unit_to_task(task: WorkTask, chosen_unit: Unit) -> bool:
	if task == null or not task.is_active() or task.state != WorkTask.State.PENDING_WORKERS:
		return false
	if not _check_pre_nav_eligibility(chosen_unit, task).is_empty():
		return false

	var pre_order_rev: int = chosen_unit.get_order_revision()
	var dispatch_res: Dictionary = _command_controller.command_units_to_gather(task.source, [chosen_unit], false)
	if not bool(dispatch_res.get("ok", false)):
		if not task.is_active():
			return false
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
		return false

	var assigned_orders: Dictionary = dispatch_res.get("assigned_orders", {}) as Dictionary
	var order: GatherResourceOrder = assigned_orders.get(chosen_unit.get_instance_id()) as GatherResourceOrder
	if not task.is_active():
		# Reentrancy guard (R-03A D2 / E11): task was closed during dispatch; never resurrect it.
		if (
			order != null
			and order.is_active()
			and is_instance_valid(chosen_unit)
			and chosen_unit.is_inside_tree()
			and chosen_unit.get_current_order() == order
			and chosen_unit.get_order_revision() > pre_order_rev
		):
			_apply_community_cancel_to_order(chosen_unit, order)
		return false
	if order == null:
		_mark_task_waiting(task, "dispatch_rejected", "")
		return false
	if order.is_succeeded():
		if not task.is_source_usable():
			_board.close_task(task, WorkTask.State.COMPLETED, "")
		return true
	if not order.is_active():
		_mark_task_waiting(task, order.failure_reason if not order.failure_reason.is_empty() else "order_not_active", "")
		return false
	if chosen_unit.get_current_order() != order:
		return false

	task.assigned_unit = chosen_unit
	task.assigned_order = order
	task.assigned_order_revision = chosen_unit.get_order_revision()
	task.state = WorkTask.State.IN_PROGRESS
	task.last_reason = ""
	_board.notify_task_updated(task)
	if not task.is_active() or task.assigned_order != order:
		return false
	task_assigned.emit(task, chosen_unit, order)

	var unit_label: String = chosen_unit.get_definition().display_name if chosen_unit.get_definition() != null else String(chosen_unit.get_character_id())
	task_feedback.emit(_dispatch_feedback(task.resource_id, unit_label))
	return true


func _evaluate_unassigned_task(task: WorkTask) -> void:
	if not task.is_active() or task.is_blocked_reauthorization() or task.assigned_unit != null:
		return
	if not task.is_source_usable():
		var unusable_reason: String = "source_depleted" if (task.is_source_valid() and task.source.is_depleted()) else "invalid_source"
		_board.close_task(task, WorkTask.State.FAILED, unusable_reason)
		return
	if _world_nav == null or not is_instance_valid(_world_nav) or not _world_nav.is_navigation_ready():
		_mark_task_waiting(task, "navigation_not_ready", "")
		return
	if _use_provenance and not _economy_admission_reason.is_empty():
		_mark_task_waiting(task, _economy_admission_reason, "")
		return
	if _is_economy_busy(task.source):
		_mark_task_waiting(task, "economy_busy", "")
		return

	var candidates: Array[Unit] = _collect_sorted_candidates(task.source.global_position)
	if candidates.is_empty():
		_mark_task_waiting(task, "no_workers", "Aguardando trabalhador disponível.")
		return

	var has_temporary_wait: bool = false
	var any_unreachable: bool = false
	var excluded_count: int = 0
	var first_reason: String = ""

	for unit: Unit in candidates:
		var pre_reason: String = _check_pre_nav_eligibility(unit, task)
		if not pre_reason.is_empty():
			if pre_reason == "manually_overridden":
				excluded_count += 1
			elif pre_reason in ["busy", "not_idle", "transaction_locked", "no_worker_slot", "reserved_or_recovery_cargo"]:
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
		if not bool(slot.get("valid", false)):
			any_unreachable = true
			if first_reason.is_empty():
				first_reason = "source_unreachable"

	if any_unreachable and not has_temporary_wait:
		_board.close_task(task, WorkTask.State.FAILED, "source_unreachable")
		task_feedback.emit(_unreachable_feedback(task.resource_id))
		return
	if excluded_count > 0 and not has_temporary_wait:
		_mark_task_blocked_reauthorization(task)
		return

	var wait_reason: String = first_reason if not first_reason.is_empty() else "no_eligible_worker"
	var wait_msg: String = "Aguardando trabalhador disponível." if wait_reason in ["busy", "not_idle", "no_worker_slot"] else ""
	_mark_task_waiting(task, wait_reason, wait_msg)


func _mark_task_waiting(task: WorkTask, reason: String, feedback_text: String) -> void:
	var changed: bool = task.state != WorkTask.State.PENDING_WORKERS or task.last_reason != reason
	task.state = WorkTask.State.PENDING_WORKERS
	task.last_reason = reason
	if changed:
		task_waiting.emit(task, reason)
		if not feedback_text.is_empty():
			task_feedback.emit(feedback_text)


func _mark_task_blocked_reauthorization(task: WorkTask) -> void:
	var reason: String = WorkTask.REASON_ALL_WORKERS_EXCLUDED
	var changed: bool = task.state != WorkTask.State.BLOCKED_REAUTHORIZATION or task.last_reason != reason
	task.state = WorkTask.State.BLOCKED_REAUTHORIZATION
	task.last_reason = reason
	if changed:
		_board.notify_task_updated(task)
		task_blocked.emit(task, reason)
		task_feedback.emit("Tarefa aguardando nova autorização.")


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
	if _use_provenance and not _economy_admission_reason.is_empty():
		return true
	if _inventory == null or _camp_zone == null or not is_instance_valid(_camp_zone) or not _camp_zone.is_valid():
		return true
	if _inventory.is_transaction_busy():
		return true
	if _board != null and is_instance_valid(_board) and not _board.is_source_in_region_domain(source):
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


static func _dispatch_feedback(resource_id: StringName, unit_label: String) -> String:
	match resource_id:
		&"stone":
			return "%s indo extrair pedra." % unit_label
		&"food":
			return "%s indo colher frutos." % unit_label
		_:
			return "%s indo cortar madeira." % unit_label


static func _completed_feedback(resource_id: StringName) -> String:
	match resource_id:
		&"stone":
			return "Extração de pedra concluída."
		&"food":
			return "Colheita de frutos concluída."
		_:
			return "Corte de madeira concluído."


static func _unreachable_feedback(resource_id: StringName) -> String:
	match resource_id:
		&"stone":
			return "Rocha inacessível."
		&"food":
			return "Arbusto inacessível."
		_:
			return "Árvore inacessível."
