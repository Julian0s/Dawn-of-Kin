class_name ConstructionSite
extends Node3D
## Modular T3.3/T3.4.3 construction site holding reservation identity, delivered/consumed buffers,
## per-unit transit/pickup tracking, D9 worker role assignments/promotions, guarded deterministic
## assembly, and footprint picking collision.
## Does not instantiate BuildingInstance (T3.4.4) or trigger active NavMesh rebakes (T3.4.5).

const GROUP_CONSTRUCTION_SITES: StringName = &"construction_sites"

enum WorkerRole {
	UNASSIGNED,
	SOLO_SUPPLIER,
	TRANSPORTER,
	BUILDER,
}

enum SiteState {
	UNCONFIGURED,
	ACTIVE,
	COMPLETING,
	COMPLETION_FAILED_RETRYABLE,
	COMPLETION_BLOCKED_ERROR,
	COMPLETED,
	CANCELLED,
}

enum AssemblySubstate {
	NONE,
	WAITING_ASSEMBLY,
	ASSEMBLING,
	PAUSED_STARVED,
	PAUSED_NO_WORKERS,
}

const DEFAULT_COLLIDER_MIN_HEIGHT: float = 1.2
const DEFAULT_DROPOFF_OUTWARD_MARGIN: float = 0.85
const DEFAULT_DROPOFF_REACH_TOLERANCE: float = 1.35
const DEFAULT_PILE_PICKUP_REACH: float = 1.45
const MAX_WORK_DELTA_SEC: float = 0.25
const USEC_PER_SEC: int = 1_000_000

const MAX_COMPLETION_RETRIES: int = 3
const RETRY_COOLDOWN_SEC: float = 1.0
signal site_completed(site: ConstructionSite, building: BuildingInstance)
signal site_completion_failed(site: ConstructionSite, reason: String)
signal state_changed(site: ConstructionSite)
signal buffer_changed(site: ConstructionSite)
signal workers_changed(site: ConstructionSite)
signal supply_completed(site: ConstructionSite)
signal reservation_lost(site: ConstructionSite, resource_id: StringName, lost_amount: int)

var site_id: StringName = &"":
	set(value):
		if not _is_preparing_or_transacting:
			site_id = value
var reservation_id: StringName = &"":
	set(value):
		if not _is_preparing_or_transacting:
			reservation_id = value
var region_id: StringName = &"default":
	set(value):
		if not _is_preparing_or_transacting:
			region_id = value
var definition: BuildingDefinition = null:
	set(value):
		if not _is_preparing_or_transacting:
			definition = value

var _inventory: SettlementInventory = null
var _construction_manager_ref: WeakRef = null
var _cancellation_custody: ReservedWithdrawalCoordinator.CancellationCustodyRecord = null
var _resource_defs: Dictionary = {}
var _required_amounts: Dictionary = {}
var _delivered_buffer: Dictionary = {}
var _consumed_materials: Dictionary = {}
var _pending_pickups: Dictionary = {}
var _transit_claims: Dictionary = {}
var _assigned_workers: Dictionary = {}
var _worker_order_ids: Array[int] = []

var _site_body: StaticBody3D = null
var _site_collision_shape: CollisionShape3D = null
var _visual_root: Node3D = null
var _is_configured: bool = false
var _signals_bound: bool = false
var _was_fully_supplied: bool = false
var _site_state: SiteState = SiteState.UNCONFIGURED
var _assembly_substate: AssemblySubstate = AssemblySubstate.NONE
var _is_complementing: bool = false
var _work_progress_usec: int = 0
var _total_work_usec: int = 1
var _builder_slot_positions: Dictionary = {}
var _work_cycle_serial: int = 0
var _work_transaction_in_progress: bool = false
var _completion_retry_count: int = 0
var _retry_cooldown_remaining_sec: float = 0.0
var _last_completion_error: String = ""
var _completion_retry_timer: Timer = null
var _starved_resources: Array[StringName] = []
var _supply_rebalance_completed: bool = false
var _generation: int = 0
var _transaction_revision: int = 0
var _is_preparing_or_transacting: bool = false
var _suppress_coordinator_signal_echo: bool = false


func _exit_tree() -> void:
	_transaction_revision += 1
	if _site_state == SiteState.COMPLETED:
		# Existing observers (including the temporary inspector) must drop the old site.
		_is_configured = false
		state_changed.emit(self)
	_unbind_inventory()
	_clear_all_transit_listeners()
	_pending_pickups.clear()
	_assigned_workers.clear()
	_worker_order_ids.clear()
	_builder_slot_positions.clear()
	_supply_rebalance_completed = false


func get_generation() -> int:
	return _generation


func get_transaction_revision() -> int:
	return _transaction_revision


func is_transaction_busy() -> bool:
	return _work_transaction_in_progress or _is_complementing or _is_preparing_or_transacting


func configure(
	p_site_id: StringName,
	p_reservation_id: StringName,
	p_definition: BuildingDefinition,
	p_inventory: SettlementInventory,
	p_resource_defs: Dictionary = {},
	p_region_id: StringName = &"default"
) -> bool:
	if _is_configured:
		return false
	if p_site_id.is_empty() or p_reservation_id.is_empty():
		return false
	if p_definition == null or not p_definition.is_valid():
		return false
	if p_inventory == null or p_inventory.get_storage_source() == null:
		return false

	var parsed_costs: Dictionary = _normalize_costs(p_definition.costs)
	if parsed_costs.is_empty():
		return false

	site_id = p_site_id
	reservation_id = p_reservation_id
	region_id = p_region_id if not p_region_id.is_empty() else &"default"
	definition = p_definition
	_total_work_usec = maxi(1, roundi(definition.build_work_required_sec * USEC_PER_SEC))
	_inventory = p_inventory
	_resource_defs = p_resource_defs.duplicate()
	_required_amounts = parsed_costs
	_delivered_buffer.clear()
	_consumed_materials.clear()
	for res_id: StringName in _required_amounts.keys():
		_delivered_buffer[res_id] = 0
		_consumed_materials[res_id] = 0

	name = String(site_id)
	add_to_group(GROUP_CONSTRUCTION_SITES)
	set_meta(&"construction_site_id", site_id)
	set_meta(&"region_id", region_id)

	if not _build_collision_body():
		return false
	_build_foundation_visual()
	_bind_inventory()
	_generation += 1
	_site_state = SiteState.ACTIVE
	_assembly_substate = AssemblySubstate.WAITING_ASSEMBLY
	_is_configured = true
	_was_fully_supplied = is_fully_supplied()
	_transaction_revision += 1
	return true


func is_valid() -> bool:
	return (
		_is_configured
		and _site_state != SiteState.UNCONFIGURED
		and definition != null
		and definition.is_valid()
		and not site_id.is_empty()
		and not reservation_id.is_empty()
		and _inventory != null
		and is_instance_valid(_site_body)
	)


func get_site_state() -> SiteState:
	return _site_state


func get_assembly_substate() -> AssemblySubstate:
	if _site_state != SiteState.ACTIVE:
		return AssemblySubstate.NONE
	return _assembly_substate


func is_active() -> bool:
	return _site_state == SiteState.ACTIVE


func occupies_construction_footprint() -> bool:
	return _site_state != SiteState.CANCELLED or _cancellation_custody == null or _cancellation_custody.requires_local_footprint_occupation()


func is_completion_ready() -> bool:
	if not is_valid() or _work_progress_usec != _total_work_usec:
		return false
	for key: StringName in _get_sorted_required_keys():
		if get_consumed_amount(key) != get_required_amount(key) or get_delivered_buffer_amount(key) != 0:
			return false
	return verify_accounting_invariant()


func get_completion_diagnostic() -> Dictionary:
	return {"attempts_failed": _completion_retry_count, "cooldown_sec": _completion_retry_timer.time_left if is_instance_valid(_completion_retry_timer) else _retry_cooldown_remaining_sec, "reason": _last_completion_error}


func record_completion_failure(reason: String) -> void:
	if _is_preparing_or_transacting:
		return
	_apply_completion_failure(reason)


func _record_completion_failure_under_guard(
	reason: String,
	completion_scope: ReservedWithdrawalCoordinator.CompletionScope
) -> void:
	if completion_scope == null or completion_scope.site != self:
		return
	if not ReservedWithdrawalCoordinator._owns_completion_scope(completion_scope):
		return
	_apply_completion_failure(reason)


func _apply_completion_failure(reason: String) -> void:
	_transaction_revision += 1
	_completion_retry_count += 1
	_last_completion_error = reason
	_retry_cooldown_remaining_sec = RETRY_COOLDOWN_SEC if _completion_retry_count < MAX_COMPLETION_RETRIES else 0.0
	_site_state = SiteState.COMPLETION_FAILED_RETRYABLE if _completion_retry_count < MAX_COMPLETION_RETRIES else SiteState.COMPLETION_BLOCKED_ERROR
	state_changed.emit(self)
	if _site_state == SiteState.COMPLETION_BLOCKED_ERROR:
		site_completion_failed.emit(self, reason)


func commit_completed_building(building: BuildingInstance) -> void:
	if _is_preparing_or_transacting:
		return
	_apply_completed_building(building)


func _commit_completed_building_under_guard(
	building: BuildingInstance,
	completion_scope: ReservedWithdrawalCoordinator.CompletionScope
) -> bool:
	if completion_scope == null or completion_scope.site != self:
		return false
	if not ReservedWithdrawalCoordinator._owns_completion_scope(completion_scope):
		return false
	_apply_completed_building(building)
	return true


func _apply_completed_building(building: BuildingInstance) -> void:
	_transaction_revision += 1
	_site_state = SiteState.COMPLETED
	_assembly_substate = AssemblySubstate.NONE
	# Snapshot active orders and unbind inventory/carry listeners before callbacks.
	var orders: Array[UnitOrder] = []
	for entry: Dictionary in _assigned_workers.values():
		var order: UnitOrder = entry.get("order") as UnitOrder
		if order != null and not orders.has(order):
			orders.append(order)
	_unbind_inventory()
	_clear_all_transit_listeners()
	site_completed.emit(self, building)
	for order: UnitOrder in orders:
		if order is ConstructOrder and order.is_active() and (order as ConstructOrder).site == self:
			(order as ConstructOrder)._finish_succeeded()
	_pending_pickups.clear()
	_assigned_workers.clear()
	_worker_order_ids.clear()
	_builder_slot_positions.clear()


func is_completed_or_completing() -> bool:
	return _site_state == SiteState.COMPLETING or _site_state == SiteState.COMPLETED


func has_any_received_materials() -> bool:
	for res_id: StringName in _required_amounts.keys():
		if get_total_received_amount(res_id) > 0:
			return true
	return false


func has_consumable_work_available() -> bool:
	if not is_active() or not has_any_received_materials():
		return false
	return _can_unblock_starvation()


func get_work_progress_sec() -> float:
	return float(_work_progress_usec) / float(USEC_PER_SEC)


func get_progress_ratio() -> float:
	return float(_work_progress_usec) / float(_total_work_usec)


# Pure production evaluator. Inputs and returned debit plan never alias mutable site state.
# The caller supplies a positive delta; public seconds validation belongs to guard 2.
static func evaluate_work_transaction_usec(
	progress_usec: int, total_usec: int, delta_usec: int,
	costs: Dictionary, incorporated: Dictionary, buffer: Dictionary
) -> Dictionary:
	var result: Dictionary = _work_rejection("insufficient_buffer_transaction_aborted")
	result["progress_usec"] = progress_usec
	result["advanced_usec"] = 0
	result["starved_resources"] = []
	if total_usec <= 0 or progress_usec < 0 or progress_usec > total_usec or delta_usec <= 0 or costs.is_empty():
		return result
	var ceiling: int = total_usec
	var ceilings: Dictionary = {}
	for key: Variant in costs:
		var cost: int = int(costs[key])
		var used: int = int(incorporated.get(key, 0))
		var available: int = int(buffer.get(key, 0))
		# Bound integer products before evaluating them (signed 64-bit arithmetic).
		if cost <= 0 or total_usec > 9223372036854775807 / cost:
			return result
		if used < 0 or available < 0 or used > cost or available > cost - used:
			return result
		var capacity: int = used + available
		var resource_ceiling: int = total_usec
		if capacity < cost:
			resource_ceiling = ((capacity + 1) * total_usec - 1) / cost
		ceilings[key] = resource_ceiling
		ceiling = mini(ceiling, resource_ceiling)
	var candidate: int = progress_usec + mini(delta_usec, total_usec - progress_usec)
	var effective: int = mini(candidate, ceiling)
	if effective < progress_usec:
		return result
	var debits: Dictionary = {}
	for key: Variant in costs:
		var target: int = (effective * int(costs[key])) / total_usec
		var debit: int = target - int(incorporated.get(key, 0))
		if debit < 0 or debit > int(buffer.get(key, 0)):
			return result
		debits[key] = debit
	var starved: bool = candidate > ceiling
	var blocked: Array[StringName] = []
	if starved:
		for key: Variant in ceilings:
			if int(ceilings[key]) == ceiling:
				blocked.append(StringName(key))
	result.merge({"ok": true, "reason": "", "progress_usec": effective,
		"advanced_usec": effective - progress_usec,
		"advanced_sec": float(effective - progress_usec) / float(USEC_PER_SEC),
		"consumed": debits, "starved": starved, "starved_resources": blocked,
		"completed": effective == total_usec}, true)
	return result


static func _work_rejection(reason: String) -> Dictionary:
	return {"ok": false, "advanced_sec": 0.0, "consumed": {},
		"starved": false, "completed": false, "reason": reason}


func assign_builder_slot_position(unit: Unit, slot_idx: int, resolved_slot_pos: Vector3) -> bool:
	if is_transaction_busy() or unit == null or not is_instance_valid(unit) or not unit.is_inside_tree() or not is_valid():
		return false
	if get_worker_role(unit) != WorkerRole.BUILDER or slot_idx != get_builder_slot_index(unit):
		return false
	if slot_idx < 0 or slot_idx >= mini(2, maxi(0, definition.max_builders)):
		return false
	if not resolved_slot_pos.is_finite() or get_footprint_rect().has_point(Vector2(resolved_slot_pos.x, resolved_slot_pos.z)):
		return false
	if not BuildSlotPlanner.is_unit_in_site_dropoff_range(resolved_slot_pos, self, DEFAULT_DROPOFF_REACH_TOLERANCE, get_world_3d()):
		return false
	_builder_slot_positions[unit.get_instance_id()] = {"slot_idx": slot_idx, "position": resolved_slot_pos}
	_transaction_revision += 1
	_refresh_assembly_substate()
	return true


func get_assigned_builder_slot_position(unit: Unit) -> Dictionary:
	_prune_stale_state()
	if unit == null or not is_instance_valid(unit):
		return {}
	var uid: int = unit.get_instance_id()
	if not _builder_slot_positions.has(uid):
		return {}
	return (_builder_slot_positions[uid] as Dictionary).duplicate()


func contribute_work(unit: Unit, delta_sec: float) -> Dictionary:
	if _work_transaction_in_progress:
		return _work_rejection("duplicate_cycle_contribution")
	if _is_preparing_or_transacting:
		if is_inside_tree() and ReservedWithdrawalCoordinator._has_active_work_in_domain(get_world_3d(), region_id):
			return _work_rejection("busy")
		return _work_rejection("duplicate_cycle_contribution")
	# Nine ordered guards; no progress, economic state or signals change on rejection.
	if _site_state == SiteState.COMPLETION_FAILED_RETRYABLE:
		return _work_rejection("completion_pending_retry")
	if not is_valid() or not is_inside_tree() or _site_state != SiteState.ACTIVE:
		return _work_rejection("site_completing_or_completed" if _site_state in [SiteState.COMPLETING, SiteState.COMPLETED] else "invalid_site_state")
	if not is_finite(delta_sec) or delta_sec <= 0.0 or delta_sec > MAX_WORK_DELTA_SEC:
		return _work_rejection("invalid_delta")
	if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
		return _work_rejection("invalid_unit")
	var acquired := ReservedWithdrawalCoordinator._acquire_work_scope(self)
	if not acquired.ok:
		return _work_rejection(acquired.reason)
	_work_transaction_in_progress = true
	_prune_stale_state()
	var frame: int = Engine.get_physics_frames()
	var evaluation := _evaluate_work_contribution(unit, delta_sec, frame)
	if evaluation["ok"]:
		var prev_site_state: SiteState = _site_state
		var prev_substate: AssemblySubstate = _assembly_substate
		var prev_starved_resources: Array[StringName] = _starved_resources.duplicate()
		_work_cycle_serial += 1
		_transaction_revision += 1
		unit._last_construction_work_frame = frame
		var debits: Dictionary = evaluation["consumed"]
		var buffer_mutated: bool = false
		for res_id: StringName in _get_sorted_required_keys():
			var debit: int = int(debits[res_id])
			if debit > 0:
				buffer_mutated = true
			_delivered_buffer[res_id] = int(_delivered_buffer[res_id]) - debit
			_consumed_materials[res_id] = int(_consumed_materials[res_id]) + debit
		_work_progress_usec = int(evaluation["progress_usec"])
		_starved_resources.assign(evaluation["starved_resources"])
		if evaluation["completed"]:
			_site_state = SiteState.COMPLETING
			_assembly_substate = AssemblySubstate.NONE
		else:
			_assembly_substate = AssemblySubstate.PAUSED_STARVED if evaluation["starved"] else AssemblySubstate.ASSEMBLING
		if int(evaluation["advanced_usec"]) > 0:
			buffer_changed.emit(self)
			state_changed.emit(self)
		else:
			if buffer_mutated:
				buffer_changed.emit(self)
			if _site_state != prev_site_state or _assembly_substate != prev_substate or _starved_resources != prev_starved_resources:
				state_changed.emit(self)
	_work_transaction_in_progress = false
	ReservedWithdrawalCoordinator._release_work_scope(acquired.scope, self)
	return evaluation


func _evaluate_work_contribution(unit: Unit, delta_sec: float, frame: int) -> Dictionary:
	var uid: int = unit.get_instance_id()
	if not _assigned_workers.has(uid):
		return _work_rejection("worker_not_registered")
	if get_worker_role(unit) != WorkerRole.BUILDER:
		return _work_rejection("worker_not_builder")
	var slot_idx: int = get_builder_slot_index(unit)
	if slot_idx < 0 or slot_idx >= mini(2, maxi(0, definition.max_builders)):
		return _work_rejection("invalid_builder_slot")
	var anchor: Dictionary = _builder_slot_positions.get(uid, {})
	if anchor.is_empty() or int(anchor["slot_idx"]) != slot_idx or not (anchor["position"] as Vector3).is_finite():
		return _work_rejection("builder_slot_position_not_assigned")
	var order: UnitOrder = unit.get_current_order()
	if not (order is ConstructOrder) or not order.is_active() or (order as ConstructOrder).site != self or order != _assigned_workers[uid]["order"]:
		return _work_rejection("invalid_active_order")
	if not BuildSlotPlanner.is_unit_at_assigned_builder_slot(unit.global_position, self, anchor["position"]):
		return _work_rejection("worker_not_in_assigned_slot")
	if not BuildSlotPlanner.is_unit_in_site_dropoff_range(unit.global_position, self, DEFAULT_DROPOFF_REACH_TOLERANCE, get_world_3d()):
		return _work_rejection("worker_out_of_reach")
	if unit._last_construction_work_frame == frame:
		return _work_rejection("duplicate_cycle_contribution")
	return evaluate_work_transaction_usec(_work_progress_usec, _total_work_usec,
		maxi(1, roundi(delta_sec * USEC_PER_SEC)), _required_amounts, _consumed_materials, _delivered_buffer)


func _can_unblock_starvation() -> bool:
	var evaluation: Dictionary = evaluate_work_transaction_usec(_work_progress_usec, _total_work_usec,
		1, _required_amounts, _consumed_materials, _delivered_buffer)
	return bool(evaluation["ok"]) and int(evaluation["advanced_usec"]) > 0


func _refresh_assembly_substate() -> void:
	if not is_active():
		return
	if _assembly_substate == AssemblySubstate.PAUSED_STARVED:
		if not _can_unblock_starvation():
			return
		_starved_resources.clear()
	var has_builder: bool = false
	var has_ready_builder: bool = false
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid) or int(_assigned_workers[uid]["role"]) != WorkerRole.BUILDER:
			continue
		has_builder = true
		var worker: Unit = _assigned_workers[uid]["unit"] as Unit
		var anchor: Dictionary = _builder_slot_positions.get(uid, {})
		if is_instance_valid(worker) and worker.is_inside_tree() and not anchor.is_empty():
			has_ready_builder = has_ready_builder or (BuildSlotPlanner.is_unit_at_assigned_builder_slot(worker.global_position, self, anchor["position"]) and BuildSlotPlanner.is_unit_in_site_dropoff_range(worker.global_position, self, DEFAULT_DROPOFF_REACH_TOLERANCE, get_world_3d()))
	if _work_progress_usec > 0 and not has_builder:
		_assembly_substate = AssemblySubstate.PAUSED_NO_WORKERS
	else:
		_assembly_substate = AssemblySubstate.ASSEMBLING if has_ready_builder else AssemblySubstate.WAITING_ASSEMBLY


func get_footprint_rect() -> Rect2:
	if definition == null:
		return Rect2()
	var pos: Vector3 = global_position if is_inside_tree() else position
	return definition.get_footprint_rect_at(Vector2(pos.x, pos.z))


func get_footprint_aabb() -> AABB:
	if definition == null:
		return AABB()
	var pos: Vector3 = global_position if is_inside_tree() else position
	return definition.get_footprint_aabb_at(pos)


func get_inventory() -> SettlementInventory:
	return _inventory


func get_resource_definition(resource_id: StringName) -> ResourceDefinition:
	if _resource_defs.has(resource_id):
		var def_val: Variant = _resource_defs[resource_id]
		if def_val is ResourceDefinition and (def_val as ResourceDefinition).is_valid():
			return def_val as ResourceDefinition
	var fallback_path: String = "res://data/resources/%s.tres" % String(resource_id)
	if ResourceLoader.exists(fallback_path):
		var loaded: Resource = ResourceLoader.load(fallback_path)
		if loaded is ResourceDefinition and (loaded as ResourceDefinition).is_valid():
			_resource_defs[resource_id] = loaded
			return loaded as ResourceDefinition
	return null


func get_required_amounts() -> Dictionary:
	return _required_amounts.duplicate()


func get_required_amount(resource_id: StringName) -> int:
	return int(_required_amounts.get(resource_id, 0))


func get_delivered_buffer_amounts() -> Dictionary:
	return _delivered_buffer.duplicate()


func get_delivered_buffer_amount(resource_id: StringName) -> int:
	return maxi(0, int(_delivered_buffer.get(resource_id, 0)))


func get_consumed_amounts() -> Dictionary:
	return _consumed_materials.duplicate()


func get_consumed_amount(resource_id: StringName) -> int:
	return maxi(0, int(_consumed_materials.get(resource_id, 0)))


func get_total_received_amounts() -> Dictionary:
	var result: Dictionary = {}
	for res_id: StringName in _required_amounts.keys():
		result[res_id] = get_total_received_amount(res_id)
	return result


func get_total_received_amount(resource_id: StringName) -> int:
	return get_delivered_buffer_amount(resource_id) + get_consumed_amount(resource_id)


func get_remaining_need_for_dropoff(resource_id: StringName) -> int:
	return maxi(0, get_required_amount(resource_id) - get_total_received_amount(resource_id))


func get_reserved_in_piles_amounts() -> Dictionary:
	var result: Dictionary = {}
	for res_id: StringName in _required_amounts.keys():
		result[res_id] = get_reserved_in_piles_amount(res_id)
	return result


func get_reserved_in_piles_amount(resource_id: StringName) -> int:
	if _inventory == null or reservation_id.is_empty() or resource_id.is_empty():
		return 0
	return maxi(0, _inventory.get_reservation_amount(reservation_id, resource_id))


func get_in_transit_amounts() -> Dictionary:
	_prune_stale_state()
	var totals: Dictionary = {}
	for res_id: StringName in _required_amounts.keys():
		totals[res_id] = 0
	for uid_key: Variant in _transit_claims.keys():
		var claim: Dictionary = _transit_claims[uid_key] as Dictionary
		var amounts: Dictionary = claim["amounts"] as Dictionary
		for res_key: Variant in amounts.keys():
			var res_id: StringName = res_key as StringName
			totals[res_id] = int(totals.get(res_id, 0)) + int(amounts[res_id])
	return totals


func get_in_transit_amount(resource_id: StringName) -> int:
	var totals: Dictionary = get_in_transit_amounts()
	return int(totals.get(resource_id, 0))


func get_transit_claim_for_unit(unit: Unit) -> Dictionary:
	_prune_stale_state()
	if unit == null or not is_instance_valid(unit):
		return {}
	var uid: int = unit.get_instance_id()
	if not _transit_claims.has(uid):
		return {}
	var claim: Dictionary = _transit_claims[uid] as Dictionary
	return (claim["amounts"] as Dictionary).duplicate()


func get_missing_amounts() -> Dictionary:
	var result: Dictionary = {}
	for res_id: StringName in _required_amounts.keys():
		result[res_id] = get_missing_amount(res_id)
	return result


func get_missing_amount(resource_id: StringName) -> int:
	var required: int = get_required_amount(resource_id)
	var received: int = get_total_received_amount(resource_id)
	var reserved: int = get_reserved_in_piles_amount(resource_id)
	var in_transit: int = get_in_transit_amount(resource_id)
	return maxi(0, required - received - reserved - in_transit)


func is_fully_supplied() -> bool:
	if _required_amounts.is_empty():
		return false
	for res_id: StringName in _required_amounts.keys():
		if get_total_received_amount(res_id) < get_required_amount(res_id):
			return false
	return true


func get_accounting_breakdown(resource_id: StringName) -> Dictionary:
	var required: int = get_required_amount(resource_id)
	var reserved: int = get_reserved_in_piles_amount(resource_id)
	var in_transit: int = get_in_transit_amount(resource_id)
	var delivered_buffer: int = get_delivered_buffer_amount(resource_id)
	var consumed: int = get_consumed_amount(resource_id)
	var uncovered_missing: int = get_missing_amount(resource_id)
	return {
		"required": required,
		"reserved": reserved,
		"in_transit": in_transit,
		"delivered_buffer": delivered_buffer,
		"consumed": consumed,
		"uncovered_missing": uncovered_missing,
		"sum": reserved + in_transit + delivered_buffer + consumed + uncovered_missing,
	}


func verify_accounting_invariant() -> bool:
	for res_id: StringName in _required_amounts.keys():
		var b: Dictionary = get_accounting_breakdown(res_id)
		if (
			int(b["reserved"]) < 0
			or int(b["in_transit"]) < 0
			or int(b["delivered_buffer"]) < 0
			or int(b["consumed"]) < 0
			or int(b["uncovered_missing"]) < 0
		):
			return false
		if int(b["sum"]) != int(b["required"]):
			return false
	return true


func get_complementable_missing_amounts() -> Dictionary:
	var result: Dictionary = {}
	for res_id: StringName in _get_sorted_required_keys():
		var missing: int = get_missing_amount(res_id)
		if missing > 0:
			result[res_id] = missing
	return result


func can_authorize_manual_complement(
	requested_amounts: Dictionary = {},
	allow_partial: bool = false
) -> Dictionary:
	if not is_valid() or _site_state != SiteState.ACTIVE or _inventory == null:
		return {"ok": false, "complemented": {}, "remaining_missing": {}, "reason": "site_not_active"}
	var pre: Dictionary = ReservedWithdrawalCoordinator._inspect_manual_complement_preconditions_readonly(self)
	if not bool(pre.get("ok", false)):
		return {"ok": false, "complemented": {}, "remaining_missing": get_complementable_missing_amounts(), "reason": String(pre.get("reason", "busy"))}
	return _plan_manual_complement_internal(requested_amounts, allow_partial, null)


func _finish_manual_complement_guards(scope: ReservedWithdrawalCoordinator.ManualComplementScope) -> void:
	_is_complementing = false
	ReservedWithdrawalCoordinator._release_manual_complement_scope(scope)


func authorize_manual_complement(
	intent: ManualComplementIntent,
	requested_amounts: Dictionary = {},
	allow_partial: bool = false
) -> Dictionary:
	if intent == null or not is_instance_valid(intent) or not intent.is_structurally_valid_for(self):
		return {"ok": false, "complemented": {}, "remaining_missing": get_complementable_missing_amounts(), "reason": "unauthorized_or_missing_intent"}

	if _is_complementing or _is_preparing_or_transacting:
		intent.consumed = true
		return {"ok": false, "complemented": {}, "remaining_missing": get_complementable_missing_amounts(), "reason": "reentrant_complement_blocked"}

	# One-shot consumption occurs immediately after structural intent validation,
	# including when downstream preconditions, regional busyness, or free stock validation fail.
	intent.consumed = true

	if _work_transaction_in_progress:
		return {"ok": false, "complemented": {}, "remaining_missing": get_complementable_missing_amounts(), "reason": "busy"}

	if not is_valid() or _site_state != SiteState.ACTIVE or _inventory == null:
		return {"ok": false, "complemented": {}, "remaining_missing": get_complementable_missing_amounts(), "reason": "site_not_active"}

	var scope_res: Dictionary = ReservedWithdrawalCoordinator._acquire_manual_complement_scope(self)
	if not bool(scope_res.get("ok", false)):
		return {
			"ok": false,
			"complemented": {},
			"remaining_missing": get_complementable_missing_amounts(),
			"reason": String(scope_res.get("reason", "busy")),
		}

	var scope: ReservedWithdrawalCoordinator.ManualComplementScope = scope_res["scope"] as ReservedWithdrawalCoordinator.ManualComplementScope
	_is_complementing = true

	var plan: Dictionary = _plan_manual_complement_internal(requested_amounts, allow_partial, scope)
	if not (plan["ok"] as bool):
		_finish_manual_complement_guards(scope)
		return {
			"ok": false,
			"complemented": {},
			"remaining_missing": plan.get("remaining_missing", get_complementable_missing_amounts()),
			"reason": String(plan.get("reason", "insufficient_free_stock")),
		}

	var target_batch: Dictionary = plan["target_batch"] as Dictionary
	if target_batch.is_empty():
		_finish_manual_complement_guards(scope)
		return {
			"ok": true,
			"complemented": {},
			"remaining_missing": {},
			"reason": String(plan.get("reason", "nothing_missing")),
		}

	var committed: bool = false
	var checkpoint: Dictionary = {}
	if scope.storage != null:
		var entries: Array[Dictionary] = plan.get("entries", []) as Array[Dictionary]
		var applied_gpm: Dictionary = scope.storage._apply_prepared_manual_complement_silent(reservation_id, entries, scope)
		committed = bool(applied_gpm.get("ok", false))
		checkpoint = applied_gpm.get("checkpoint", {}) as Dictionary
	elif scope.storage_source is InMemoryStorageSource:
		var mem_src: InMemoryStorageSource = scope.storage_source as InMemoryStorageSource
		var applied_mem: Dictionary = mem_src._apply_manual_complement_silent(reservation_id, target_batch, scope)
		committed = bool(applied_mem.get("ok", false))
		checkpoint = applied_mem.get("checkpoint", {}) as Dictionary

	if not committed:
		_finish_manual_complement_guards(scope)
		return {
			"ok": false,
			"complemented": {},
			"remaining_missing": get_complementable_missing_amounts(),
			"reason": "insufficient_free_stock",
		}

	if not verify_accounting_invariant() or not ReservedWithdrawalCoordinator._owns_manual_complement_scope(scope):
		ReservedWithdrawalCoordinator._authorize_manual_complement_rollback(scope)
		if scope.storage != null:
			scope.storage._restore_manual_complement_checkpoint_silent(checkpoint, scope)
		elif scope.storage_source is InMemoryStorageSource:
			(scope.storage_source as InMemoryStorageSource)._restore_manual_complement_checkpoint_silent(checkpoint, scope)
		_finish_manual_complement_guards(scope)
		return {
			"ok": false,
			"complemented": {},
			"remaining_missing": get_complementable_missing_amounts(),
			"reason": "accounting_invariant_failed",
		}

	_transaction_revision += 1
	_inventory._transaction_revision += 1

	ReservedWithdrawalCoordinator._authorize_manual_complement_commit(scope)
	if scope.storage != null:
		scope.storage._publish_manual_complement_committed(scope)
	elif scope.storage_source is InMemoryStorageSource:
		(scope.storage_source as InMemoryStorageSource)._publish_manual_complement_committed(scope)
	if not _signals_bound:
		state_changed.emit(self)

	_finish_manual_complement_guards(scope)
	return {
		"ok": true,
		"complemented": target_batch.duplicate(),
		"remaining_missing": get_complementable_missing_amounts(),
		"reason": "",
	}


func _plan_manual_complement_internal(
	requested_amounts: Dictionary,
	allow_partial: bool,
	scope: ReservedWithdrawalCoordinator.ManualComplementScope
) -> Dictionary:
	var missing: Dictionary = get_complementable_missing_amounts()
	if missing.is_empty():
		return {
			"ok": true,
			"target_batch": {},
			"remaining_missing": {},
			"reason": "nothing_missing",
		}

	var normalized: Dictionary = {}
	if requested_amounts.is_empty():
		normalized = missing.duplicate()
	else:
		for raw_key: Variant in requested_amounts.keys():
			if not (raw_key is StringName or raw_key is String):
				return {"ok": false, "target_batch": {}, "remaining_missing": missing, "reason": "invalid_requested_amounts"}
			var res_id: StringName = StringName(raw_key)
			var raw_val: Variant = requested_amounts[raw_key]
			if res_id.is_empty() or not (raw_val is int) or (raw_val as int) <= 0:
				return {"ok": false, "target_batch": {}, "remaining_missing": missing, "reason": "invalid_requested_amounts"}
			var req_amt: int = raw_val as int
			var cur_missing: int = int(missing.get(res_id, 0))
			var capped: int = mini(req_amt, cur_missing)
			if capped > 0:
				normalized[res_id] = capped
		if normalized.is_empty():
			return {"ok": false, "target_batch": {}, "remaining_missing": missing, "reason": "invalid_requested_amounts"}

	var target_batch: Dictionary = {}
	if not allow_partial:
		target_batch = normalized
	else:
		for res_id: StringName in _get_sorted_required_keys():
			if not normalized.has(res_id):
				continue
			var want: int = int(normalized[res_id])
			var avail: int = _inventory.get_available_amount(res_id)
			var take: int = mini(want, avail)
			if take > 0:
				target_batch[res_id] = take
		if target_batch.is_empty():
			return {"ok": false, "target_batch": {}, "remaining_missing": missing, "reason": "insufficient_free_stock"}

	var entries: Array[Dictionary] = []
	if scope == null:
		if not _inventory.can_complement_reservation(reservation_id, target_batch):
			return {"ok": false, "target_batch": {}, "remaining_missing": missing, "reason": "insufficient_free_stock"}
	elif scope.storage != null:
		var prep_gpm: Dictionary = scope.storage._prepare_manual_complement_under_guard(reservation_id, target_batch, scope)
		if not bool(prep_gpm.get("ok", false)):
			var gpm_reason: String = String(prep_gpm.get("reason", "insufficient_free_stock"))
			if gpm_reason == "insufficient_resources":
				gpm_reason = "insufficient_free_stock"
			return {"ok": false, "target_batch": {}, "remaining_missing": missing, "reason": gpm_reason}
		entries = prep_gpm["entries"] as Array[Dictionary]
	elif scope.storage_source is InMemoryStorageSource:
		var mem_src: InMemoryStorageSource = scope.storage_source as InMemoryStorageSource
		var prep_mem: Dictionary = mem_src._prepare_manual_complement_under_guard(reservation_id, target_batch, scope)
		if not bool(prep_mem.get("ok", false)):
			var mem_reason: String = String(prep_mem.get("reason", "insufficient_free_stock"))
			if mem_reason == "insufficient_resources":
				mem_reason = "insufficient_free_stock"
			return {"ok": false, "target_batch": {}, "remaining_missing": missing, "reason": mem_reason}
	else:
		return {"ok": false, "target_batch": {}, "remaining_missing": missing, "reason": "unsupported_storage_source"}

	var projected_remaining: Dictionary = missing.duplicate()
	for res_key: Variant in target_batch.keys():
		var res_id: StringName = res_key as StringName
		var left: int = maxi(0, int(projected_remaining.get(res_id, 0)) - int(target_batch[res_id]))
		if left <= 0:
			projected_remaining.erase(res_id)
		else:
			projected_remaining[res_id] = left

	return {
		"ok": true,
		"target_batch": target_batch,
		"entries": entries,
		"remaining_missing": projected_remaining,
		"reason": "",
	}


func get_pending_pickup_amount(pile_id: int, resource_id: StringName, exclude_unit: Unit = null) -> int:
	_prune_stale_state()
	var exclude_id: int = exclude_unit.get_instance_id() if exclude_unit != null and is_instance_valid(exclude_unit) else -1
	var total: int = 0
	for uid_key: Variant in _pending_pickups.keys():
		var uid: int = int(uid_key)
		if uid == exclude_id:
			continue
		var entry: Dictionary = _pending_pickups[uid_key] as Dictionary
		if int(entry["pile_id"]) == pile_id and (entry["resource_id"] as StringName) == resource_id:
			total += int(entry["amount"])
	return total


func get_total_pending_pickup_for_resource(resource_id: StringName, exclude_unit: Unit = null) -> int:
	_prune_stale_state()
	var exclude_id: int = exclude_unit.get_instance_id() if exclude_unit != null and is_instance_valid(exclude_unit) else -1
	var total: int = 0
	for uid_key: Variant in _pending_pickups.keys():
		var uid: int = int(uid_key)
		if uid == exclude_id:
			continue
		var entry: Dictionary = _pending_pickups[uid_key] as Dictionary
		if (entry["resource_id"] as StringName) == resource_id:
			total += int(entry["amount"])
	return total


func get_remaining_supply_to_claim(resource_id: StringName, exclude_unit: Unit = null) -> int:
	var remaining_dropoff: int = get_remaining_need_for_dropoff(resource_id)
	var in_transit: int = get_in_transit_amount(resource_id)
	var pending_other: int = get_total_pending_pickup_for_resource(resource_id, exclude_unit)
	return maxi(0, remaining_dropoff - in_transit - pending_other)


func claim_pickup(unit: Unit, pile_id: int, resource_id: StringName, desired_amount: int, pile_reserved_total: int = -1) -> int:
	if is_transaction_busy() or _site_state == SiteState.CANCELLED:
		return 0
	_prune_stale_state()
	if unit == null or not is_instance_valid(unit) or desired_amount <= 0:
		return 0
	if is_fully_supplied():
		return 0

	var uid: int = unit.get_instance_id()
	var had_pending: bool = _pending_pickups.has(uid)
	_pending_pickups.erase(uid)

	var remaining_for_site: int = get_remaining_supply_to_claim(resource_id, unit)
	if remaining_for_site <= 0:
		if had_pending:
			_transaction_revision += 1
		return 0

	var pile_cap: int = pile_reserved_total
	if pile_cap < 0:
		pile_cap = get_reserved_in_piles_amount(resource_id)
	var other_on_pile: int = get_pending_pickup_amount(pile_id, resource_id, unit)
	var pile_available_to_claim: int = maxi(0, pile_cap - other_on_pile)
	var claim_amt: int = mini(desired_amount, mini(remaining_for_site, pile_available_to_claim))
	if claim_amt <= 0:
		if had_pending:
			_transaction_revision += 1
		return 0

	_pending_pickups[uid] = {
		"unit": unit,
		"pile_id": pile_id,
		"resource_id": resource_id,
		"amount": claim_amt,
	}
	_transaction_revision += 1
	return claim_amt


func release_pickup_claim(unit: Unit) -> void:
	if is_transaction_busy():
		return
	if unit == null or not is_instance_valid(unit):
		_prune_stale_state()
		return
	var uid: int = unit.get_instance_id()
	if _pending_pickups.has(uid):
		_pending_pickups.erase(uid)
		_transaction_revision += 1


func record_withdrawn_for_site(unit: Unit, resource_id: StringName, amount: int) -> void:
	if is_transaction_busy():
		return
	_prune_stale_state()
	if not is_active() or unit == null or not is_instance_valid(unit) or resource_id.is_empty() or amount <= 0:
		return
	var carry_load: UnitCarryLoad = unit.get_carry_load()
	if carry_load == null or carry_load.is_provenance_enabled() or carry_load.is_transaction_busy():
		return

	var uid: int = unit.get_instance_id()
	var had_pending: bool = _pending_pickups.has(uid)
	_pending_pickups.erase(uid)

	var accounting_headroom: int = maxi(
		0,
		get_required_amount(resource_id)
		- get_total_received_amount(resource_id)
		- get_reserved_in_piles_amount(resource_id)
		- get_in_transit_amount(resource_id)
	)
	var allowed_add: int = mini(amount, accounting_headroom)
	if allowed_add <= 0:
		if had_pending:
			_transaction_revision += 1
		return

	_ensure_transit_listener(unit, carry_load)
	var claim: Dictionary = _transit_claims[uid] as Dictionary
	var amounts: Dictionary = claim["amounts"] as Dictionary
	amounts[resource_id] = int(amounts.get(resource_id, 0)) + allowed_add
	_clamp_unit_transit_claim(uid)
	_transaction_revision += 1
	state_changed.emit(self)


func get_unneeded_cargo_for_unit(unit: Unit, carry_load: UnitCarryLoad) -> Dictionary:
	_prune_stale_state()
	var unneeded: Dictionary = {}
	if unit == null or not is_instance_valid(unit) or carry_load == null or carry_load.is_empty():
		return unneeded

	var all_cargo: Dictionary = carry_load.get_all_amounts()
	var unit_claim: Dictionary = get_transit_claim_for_unit(unit)
	for res_key: Variant in all_cargo.keys():
		var res_id: StringName = res_key as StringName
		var carried: int = int(all_cargo[res_id])
		if carried <= 0:
			continue
		var needed_for_site: int = get_remaining_need_for_dropoff(res_id)
		var attributed: int = int(unit_claim.get(res_id, 0))
		var usable: int = mini(carried, mini(needed_for_site, attributed))
		var extra: int = carried - usable
		if extra > 0:
			unneeded[res_id] = extra
	return unneeded


func has_active_peer_transport_for_site(exclude_unit: Unit = null) -> bool:
	_prune_stale_state()
	var exclude_id: int = exclude_unit.get_instance_id() if exclude_unit != null and is_instance_valid(exclude_unit) else -1
	for uid: int in _worker_order_ids:
		if uid == exclude_id or not _assigned_workers.has(uid):
			continue
		var entry: Dictionary = _assigned_workers[uid] as Dictionary
		var unit: Unit = entry.get("unit") as Unit
		var order: UnitOrder = entry.get("order") as UnitOrder
		if unit == null or not is_instance_valid(unit) or order == null or not order.is_active():
			continue
		var role: WorkerRole = entry.get("role", WorkerRole.UNASSIGNED) as WorkerRole
		if role != WorkerRole.SOLO_SUPPLIER and role != WorkerRole.TRANSPORTER:
			continue
		if _pending_pickups.has(uid):
			return true
		if _transit_claims.has(uid):
			var claim: Dictionary = _transit_claims[uid] as Dictionary
			var amounts: Dictionary = claim.get("amounts", {}) as Dictionary
			for res_key: Variant in amounts.keys():
				var res_id: StringName = res_key as StringName
				if int(amounts[res_id]) > 0 and get_remaining_need_for_dropoff(res_id) > 0:
					return true
	return false


func accept_delivery_from_carry_load(unit: Unit, carry_load: UnitCarryLoad) -> Dictionary:
	if is_transaction_busy() or carry_load == null or carry_load.is_provenance_enabled() or carry_load.is_transaction_busy():
		return {}
	_prune_stale_state()
	if not is_valid() or not is_active() or unit == null or not is_instance_valid(unit) or carry_load.is_empty():
		return {}

	var unit_claim: Dictionary = get_transit_claim_for_unit(unit)
	if unit_claim.is_empty():
		return {}

	var accepted: Dictionary = {}
	var sorted_keys: Array[StringName] = _get_sorted_required_keys()
	for res_id: StringName in sorted_keys:
		var claimed: int = maxi(0, int(unit_claim.get(res_id, 0)))
		if claimed <= 0:
			continue
		var need: int = get_remaining_need_for_dropoff(res_id)
		var carried: int = carry_load.get_amount(res_id)
		var other_in_transit: int = maxi(0, get_in_transit_amount(res_id) - claimed)
		var invariant_cap: int = maxi(
			0,
			get_required_amount(res_id)
			- get_total_received_amount(res_id)
			- get_reserved_in_piles_amount(res_id)
			- other_in_transit
		)
		var take: int = mini(claimed, mini(need, mini(carried, invariant_cap)))
		if take > 0:
			accepted[res_id] = take

	if accepted.is_empty():
		return {}

	var snapshot_amounts: Dictionary = carry_load.get_all_amounts()
	var snapshot_weights: Dictionary = carry_load.get_all_unit_weights()
	carry_load.begin_batch()

	for res_key: Variant in accepted.keys():
		var res_id: StringName = res_key as StringName
		var take_amt: int = int(accepted[res_id])
		var removed: int = carry_load.remove_units(res_id, take_amt)
		if removed != take_amt:
			carry_load.restore_load_snapshot(snapshot_amounts, snapshot_weights)
			carry_load.end_batch(true)
			return {}

	for res_key: Variant in accepted.keys():
		var res_id: StringName = res_key as StringName
		var take_amt: int = int(accepted[res_id])
		_delivered_buffer[res_id] = get_delivered_buffer_amount(res_id) + take_amt
		if unit != null and is_instance_valid(unit):
			var uid: int = unit.get_instance_id()
			if _transit_claims.has(uid):
				var claim: Dictionary = _transit_claims[uid] as Dictionary
				var amounts: Dictionary = claim["amounts"] as Dictionary
				var prev_claim: int = int(amounts.get(res_id, 0))
				var next_claim: int = maxi(0, prev_claim - take_amt)
				if next_claim <= 0:
					amounts.erase(res_id)
				else:
					amounts[res_id] = next_claim
				_clamp_unit_transit_claim(uid)

	carry_load.end_batch(false)
	_transaction_revision += 1
	_refresh_assembly_substate()
	buffer_changed.emit(self)
	state_changed.emit(self)

	var full_now: bool = is_fully_supplied()
	if full_now and not _was_fully_supplied:
		_was_fully_supplied = true
		supply_completed.emit(self)
	else:
		_was_fully_supplied = full_now

	return accepted.duplicate()


func register_worker(
	unit: Unit,
	order: UnitOrder,
	force_transporter: bool = false
) -> WorkerRole:
	if is_transaction_busy() or _site_state == SiteState.CANCELLED:
		return WorkerRole.UNASSIGNED
	_prune_stale_state()
	if unit == null or not is_instance_valid(unit) or order == null or definition == null:
		return WorkerRole.UNASSIGNED

	var uid: int = unit.get_instance_id()
	if _assigned_workers.has(uid):
		var existing: Dictionary = _assigned_workers[uid] as Dictionary
		existing["order"] = order
		existing["force_transporter"] = force_transporter
		existing["solo_promoted_builder"] = false
		_transaction_revision += 1
		_rebalance_worker_roles(true)
		return get_worker_role(unit)

	if not force_transporter:
		var auto_count: int = _count_auto_workers()
		var max_auto: int = 1 + maxi(0, definition.max_builders)
		if auto_count >= max_auto:
			return WorkerRole.UNASSIGNED

	_assigned_workers[uid] = {
		"unit": unit,
		"order": order,
		"role": WorkerRole.UNASSIGNED,
		"force_transporter": force_transporter,
		"solo_promoted_builder": false,
	}
	if not _worker_order_ids.has(uid):
		_worker_order_ids.append(uid)

	_transaction_revision += 1
	_rebalance_worker_roles(true)
	return get_worker_role(unit)


func has_deliverable_transit_claim_for_unit(unit: Unit) -> bool:
	_prune_stale_state()
	if unit == null or not is_instance_valid(unit):
		return false
	var carry_load: UnitCarryLoad = unit.get_carry_load()
	if carry_load == null or carry_load.is_empty():
		return false
	var site_claim: Dictionary = get_transit_claim_for_unit(unit)
	if site_claim.is_empty():
		return false
	for res_key: Variant in site_claim.keys():
		var res_id: StringName = res_key as StringName
		if int(site_claim[res_id]) > 0 and carry_load.get_amount(res_id) > 0 and get_remaining_need_for_dropoff(res_id) > 0:
			return true
	return false


func try_promote_solo_to_builder(unit: Unit) -> bool:
	if is_transaction_busy():
		return false
	_prune_stale_state()
	if not is_active() or unit == null or not is_instance_valid(unit) or not unit.is_inside_tree() or definition == null:
		return false
	var uid: int = unit.get_instance_id()
	if not _assigned_workers.has(uid):
		return false
	var entry: Dictionary = _assigned_workers[uid] as Dictionary
	if bool(entry.get("force_transporter", false)):
		return false
	var cur_role: WorkerRole = entry.get("role", WorkerRole.UNASSIGNED) as WorkerRole
	if cur_role == WorkerRole.BUILDER:
		return true
	if cur_role != WorkerRole.SOLO_SUPPLIER:
		return false
	if mini(2, maxi(0, definition.max_builders)) < 1:
		return false
	if has_deliverable_transit_claim_for_unit(unit):
		return false
	var can_promote: bool = is_fully_supplied() or (not _has_claimable_reserved_piles_for(unit) and has_consumable_work_available())
	if not can_promote:
		return false

	entry["role"] = WorkerRole.BUILDER
	entry["solo_promoted_builder"] = true
	if is_fully_supplied():
		_supply_rebalance_completed = true
	_builder_slot_positions.erase(uid)
	_transaction_revision += 1
	_refresh_assembly_substate()
	workers_changed.emit(self)
	state_changed.emit(self)
	return true


func rebalance_for_assembly_on_supply_complete(unit: Unit) -> WorkerRole:
	if is_transaction_busy():
		return WorkerRole.UNASSIGNED
	_prune_stale_state()
	if unit == null or not is_instance_valid(unit):
		return WorkerRole.UNASSIGNED
	var uid: int = unit.get_instance_id()
	if not _assigned_workers.has(uid):
		return WorkerRole.UNASSIGNED
	var entry: Dictionary = _assigned_workers[uid] as Dictionary
	var cur_role: WorkerRole = entry.get("role", WorkerRole.UNASSIGNED) as WorkerRole
	if not is_active() or not is_fully_supplied():
		return cur_role
	if bool(entry.get("force_transporter", false)):
		return WorkerRole.TRANSPORTER
	if cur_role == WorkerRole.BUILDER:
		_supply_rebalance_completed = true
		return WorkerRole.BUILDER
	if cur_role == WorkerRole.SOLO_SUPPLIER:
		if try_promote_solo_to_builder(unit):
			return WorkerRole.BUILDER
		return get_worker_role(unit)

	_supply_rebalance_completed = true
	var max_b: int = mini(2, maxi(0, definition.max_builders if definition != null else 2))
	var current_builders: int = _count_builders()
	if current_builders < max_b:
		# Place newly promoted builder after existing builders so slot 0's anchor remains stable.
		_worker_order_ids.erase(uid)
		_worker_order_ids.append(uid)
		entry["role"] = WorkerRole.BUILDER
		entry["solo_promoted_builder"] = true
		_clear_mismatched_builder_anchors()
		_transaction_revision += 1
		_refresh_assembly_substate()
		workers_changed.emit(self)
		state_changed.emit(self)
		return WorkerRole.BUILDER

	unregister_worker(unit)
	return WorkerRole.UNASSIGNED


func unregister_worker(unit: Unit, order: UnitOrder = null) -> void:
	if is_transaction_busy():
		return
	if unit == null or not is_instance_valid(unit):
		_prune_stale_state()
		return
	var uid: int = unit.get_instance_id()
	release_pickup_claim(unit)
	if not _assigned_workers.has(uid):
		_prune_stale_state()
		return
	if order != null:
		var entry: Dictionary = _assigned_workers[uid] as Dictionary
		if entry.get("order") != order:
			return
	_assigned_workers.erase(uid)
	_builder_slot_positions.erase(uid)
	_worker_order_ids.erase(uid)
	_transaction_revision += 1
	_rebalance_worker_roles(true)


func get_worker_role(unit: Unit) -> WorkerRole:
	_prune_stale_state()
	if unit == null or not is_instance_valid(unit):
		return WorkerRole.UNASSIGNED
	var uid: int = unit.get_instance_id()
	if not _assigned_workers.has(uid):
		return WorkerRole.UNASSIGNED
	var entry: Dictionary = _assigned_workers[uid] as Dictionary
	return entry.get("role", WorkerRole.UNASSIGNED) as WorkerRole


func get_assigned_worker_entries() -> Array[Dictionary]:
	_prune_stale_state()
	var entries: Array[Dictionary] = []
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid):
			continue
		var raw: Dictionary = _assigned_workers[uid] as Dictionary
		var unit: Unit = raw.get("unit") as Unit
		var role: WorkerRole = raw.get("role", WorkerRole.UNASSIGNED) as WorkerRole
		var unit_name: String = unit.name if unit != null and is_instance_valid(unit) else "?"
		if unit != null and is_instance_valid(unit) and unit.definition != null and not unit.definition.display_name.is_empty():
			unit_name = "%s (%s)" % [unit.definition.display_name, unit.name]
		entries.append({
			"unit": unit,
			"unit_id": uid,
			"name": unit_name,
			"role": role,
			"role_label": role_to_label(role),
			"force_transporter": bool(raw.get("force_transporter", false)),
		})
	return entries


func get_builder_slot_index(unit: Unit) -> int:
	_prune_stale_state()
	if unit == null or not is_instance_valid(unit):
		return -1
	var target_uid: int = unit.get_instance_id()
	var builder_idx: int = 0
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid):
			continue
		var raw: Dictionary = _assigned_workers[uid] as Dictionary
		var role: WorkerRole = raw.get("role", WorkerRole.UNASSIGNED) as WorkerRole
		if role == WorkerRole.BUILDER:
			if uid == target_uid:
				return builder_idx
			builder_idx += 1
	return -1


func get_status_snapshot() -> Dictionary:
	return {
		"site_id": site_id,
		"reservation_id": reservation_id,
		"region_id": region_id,
		"definition_id": definition.definition_id if definition != null else &"",
		"display_name": definition.display_name if definition != null else "",
		"site_state": _site_state,
		"assembly_substate": get_assembly_substate(),
		"required": get_required_amounts(),
		"reserved_in_piles": get_reserved_in_piles_amounts(),
		"in_transit": get_in_transit_amounts(),
		"delivered_buffer": get_delivered_buffer_amounts(),
		"consumed": get_consumed_amounts(),
		"total_received": get_total_received_amounts(),
		"missing": get_missing_amounts(),
		"is_fully_supplied": is_fully_supplied(),
		"workers": get_assigned_worker_entries(),
		"max_builders": definition.max_builders if definition != null else 0,
	}


static func role_to_label(role: WorkerRole) -> String:
	match role:
		WorkerRole.SOLO_SUPPLIER:
			return "Supridor solo (transporte)"
		WorkerRole.TRANSPORTER:
			return "Transportador"
		WorkerRole.BUILDER:
			return "Construtor (prontidão)"
		_:
			return "Sem função"


static func resolve_from_collider(collider: Object) -> ConstructionSite:
	if collider == null:
		return null
	if collider is ConstructionSite:
		return collider as ConstructionSite
	if collider is Node:
		var current: Node = collider as Node
		while current != null:
			if current is ConstructionSite:
				return current as ConstructionSite
			current = current.get_parent()
	return null


func _build_collision_body() -> bool:
	if definition == null:
		return false
	var body := StaticBody3D.new()
	body.name = "SiteBody"
	body.collision_layer = CollisionLayers.MASK_BUILDINGS
	body.collision_mask = 0

	var shape_node := CollisionShape3D.new()
	shape_node.name = "FootprintShape"
	var box := BoxShape3D.new()
	var height: float = maxf(definition.visual_height * 0.45, DEFAULT_COLLIDER_MIN_HEIGHT)
	box.size = Vector3(definition.footprint_size.x, height, definition.footprint_size.y)
	shape_node.shape = box
	shape_node.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(shape_node)
	add_child(body)

	_site_body = body
	_site_collision_shape = shape_node
	return true


func _build_foundation_visual() -> void:
	if definition == null:
		return
	var visual_root := Node3D.new()
	visual_root.name = "FoundationVisual"
	add_child(visual_root)
	_visual_root = visual_root

	var pad_mat := StandardMaterial3D.new()
	pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad_mat.albedo_color = Color(0.66, 0.54, 0.34, 0.28)
	pad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.56, 0.40, 0.22, 1.0)
	beam_mat.roughness = 0.88

	var stake_mat := StandardMaterial3D.new()
	stake_mat.albedo_color = Color(0.84, 0.67, 0.32, 1.0)
	stake_mat.roughness = 0.72

	var half_x: float = definition.footprint_size.x * 0.5
	var half_z: float = definition.footprint_size.y * 0.5

	# Discrete unbuilt ground pad clearly distinguished from a completed structure.
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(maxf(0.2, definition.footprint_size.x - 0.16), 0.05, maxf(0.2, definition.footprint_size.y - 0.16))
	var pad_inst := MeshInstance3D.new()
	pad_inst.name = "GroundPad"
	pad_inst.mesh = pad_mesh
	pad_inst.material_override = pad_mat
	pad_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad_inst.position = Vector3(0.0, 0.03, 0.0)
	visual_root.add_child(pad_inst)

	# Perimeter foundation rails + corner stakes.
	var rail_thickness: float = 0.12
	var rail_specs: Array[Dictionary] = [
		{"name": "NorthRail", "size": Vector3(definition.footprint_size.x, rail_thickness, rail_thickness), "pos": Vector3(0.0, rail_thickness * 0.5 + 0.04, -half_z + rail_thickness * 0.5)},
		{"name": "SouthRail", "size": Vector3(definition.footprint_size.x, rail_thickness, rail_thickness), "pos": Vector3(0.0, rail_thickness * 0.5 + 0.04, half_z - rail_thickness * 0.5)},
		{"name": "WestRail", "size": Vector3(rail_thickness, rail_thickness, definition.footprint_size.y), "pos": Vector3(-half_x + rail_thickness * 0.5, rail_thickness * 0.5 + 0.04, 0.0)},
		{"name": "EastRail", "size": Vector3(rail_thickness, rail_thickness, definition.footprint_size.y), "pos": Vector3(half_x - rail_thickness * 0.5, rail_thickness * 0.5 + 0.04, 0.0)},
	]
	for spec: Dictionary in rail_specs:
		var mesh := BoxMesh.new()
		mesh.size = spec["size"] as Vector3
		var mi := MeshInstance3D.new()
		mi.name = spec["name"] as String
		mi.mesh = mesh
		mi.material_override = beam_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = spec["pos"] as Vector3
		visual_root.add_child(mi)

	var stake_height: float = 0.65
	var stake_mesh := BoxMesh.new()
	stake_mesh.size = Vector3(0.16, stake_height, 0.16)
	var stake_corners: Array[Vector2] = [
		Vector2(-half_x + 0.12, -half_z + 0.12),
		Vector2(half_x - 0.12, -half_z + 0.12),
		Vector2(-half_x + 0.12, half_z - 0.12),
		Vector2(half_x - 0.12, half_z - 0.12),
	]
	for idx: int in range(stake_corners.size()):
		var c: Vector2 = stake_corners[idx]
		var stake := MeshInstance3D.new()
		stake.name = "CornerStake%d" % idx
		stake.mesh = stake_mesh
		stake.material_override = stake_mat
		stake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stake.position = Vector3(c.x, stake_height * 0.5, c.y)
		visual_root.add_child(stake)


func _bind_inventory() -> void:
	if _inventory == null or _signals_bound:
		return
	if not _inventory.reservations_changed.is_connected(_on_inventory_reservations_changed):
		_inventory.reservations_changed.connect(_on_inventory_reservations_changed)
	if not _inventory.reservation_lost_to_decay.is_connected(_on_inventory_reservation_lost_to_decay):
		_inventory.reservation_lost_to_decay.connect(_on_inventory_reservation_lost_to_decay)
	_signals_bound = true


func _unbind_inventory() -> void:
	if _inventory == null or not _signals_bound:
		return
	if _inventory.reservations_changed.is_connected(_on_inventory_reservations_changed):
		_inventory.reservations_changed.disconnect(_on_inventory_reservations_changed)
	if _inventory.reservation_lost_to_decay.is_connected(_on_inventory_reservation_lost_to_decay):
		_inventory.reservation_lost_to_decay.disconnect(_on_inventory_reservation_lost_to_decay)
	_signals_bound = false


func _on_inventory_reservations_changed() -> void:
	if _suppress_coordinator_signal_echo:
		return
	_transaction_revision += 1
	var demoted: bool = false
	if is_active() and not is_fully_supplied() and _count_auto_workers() == 1:
		for uid: int in _worker_order_ids:
			if not _assigned_workers.has(uid):
				continue
			var entry: Dictionary = _assigned_workers[uid] as Dictionary
			if bool(entry.get("force_transporter", false)):
				continue
			if int(entry.get("role", WorkerRole.UNASSIGNED)) == WorkerRole.BUILDER and bool(entry.get("solo_promoted_builder", false)):
				var unit: Unit = entry.get("unit") as Unit
				if unit != null and is_instance_valid(unit) and _has_claimable_reserved_piles_for(unit):
					_rebalance_worker_roles(true)
					demoted = true
					break
	if not demoted:
		state_changed.emit(self)


func _on_inventory_reservation_lost_to_decay(
	p_reservation_id: StringName,
	resource_id: StringName,
	lost_amount: int
) -> void:
	if p_reservation_id != reservation_id:
		return
	_transaction_revision += 1
	# Alternative B: lost reserved units stay lost without automatic reallocation.
	reservation_lost.emit(self, resource_id, lost_amount)
	state_changed.emit(self)


func _ensure_transit_listener(unit: Unit, carry_load: UnitCarryLoad) -> void:
	var uid: int = unit.get_instance_id()
	if _transit_claims.has(uid):
		return
	var cb := Callable(self, "_on_unit_carry_load_changed").bind(uid)
	if not carry_load.load_changed.is_connected(cb):
		carry_load.load_changed.connect(cb)
	_transit_claims[uid] = {
		"unit": unit,
		"carry_load": carry_load,
		"amounts": {},
		"callback": cb,
	}


func _clear_all_transit_listeners() -> void:
	for uid_key: Variant in _transit_claims.keys():
		var claim: Dictionary = _transit_claims[uid_key] as Dictionary
		var cl: UnitCarryLoad = claim.get("carry_load") as UnitCarryLoad
		var cb: Variant = claim.get("callback")
		if cl != null and cb is Callable and cl.load_changed.is_connected(cb as Callable):
			cl.load_changed.disconnect(cb as Callable)
	_transit_claims.clear()


func _on_unit_carry_load_changed(uid: int) -> void:
	if _suppress_coordinator_signal_echo:
		return
	if _clamp_unit_transit_claim(uid):
		state_changed.emit(self)


func _clamp_unit_transit_claim(uid: int) -> bool:
	if not _transit_claims.has(uid):
		return false
	var claim: Dictionary = _transit_claims[uid] as Dictionary
	var unit: Unit = claim.get("unit") as Unit
	var carry_load: UnitCarryLoad = claim.get("carry_load") as UnitCarryLoad
	if unit == null or not is_instance_valid(unit) or carry_load == null:
		if carry_load != null and claim.get("callback") is Callable:
			var cb: Callable = claim["callback"] as Callable
			if carry_load.load_changed.is_connected(cb):
				carry_load.load_changed.disconnect(cb)
		_transit_claims.erase(uid)
		_transaction_revision += 1
		return true

	var amounts: Dictionary = claim["amounts"] as Dictionary
	var to_erase: Array[StringName] = []
	var mutated: bool = false
	for res_key: Variant in amounts.keys():
		var res_id: StringName = res_key as StringName
		var claimed: int = int(amounts[res_id])
		var held_now: int = carry_load.get_amount(res_id)
		var clamped: int = mini(claimed, held_now)
		if clamped <= 0:
			to_erase.append(res_id)
			mutated = true
		elif clamped != claimed:
			amounts[res_id] = clamped
			mutated = true
	for res_id: StringName in to_erase:
		amounts.erase(res_id)
	if amounts.is_empty():
		var cb_variant: Variant = claim.get("callback")
		if cb_variant is Callable and carry_load.load_changed.is_connected(cb_variant as Callable):
			carry_load.load_changed.disconnect(cb_variant as Callable)
		_transit_claims.erase(uid)
		mutated = true
	if mutated:
		_transaction_revision += 1
	return mutated


func _prune_stale_state() -> void:
	if _is_preparing_or_transacting:
		return
	var dead_pending: Array[int] = []
	for uid_key: Variant in _pending_pickups.keys():
		var uid: int = int(uid_key)
		var entry: Dictionary = _pending_pickups[uid_key] as Dictionary
		var unit: Unit = entry.get("unit") as Unit
		if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
			dead_pending.append(uid)
	for uid: int in dead_pending:
		_pending_pickups.erase(uid)
	if not dead_pending.is_empty():
		_transaction_revision += 1

	var dead_transit: Array[int] = []
	for uid_key: Variant in _transit_claims.keys():
		var uid: int = int(uid_key)
		var claim: Dictionary = _transit_claims[uid_key] as Dictionary
		var unit: Unit = claim.get("unit") as Unit
		if unit == null or not is_instance_valid(unit):
			dead_transit.append(uid)
	for uid: int in dead_transit:
		_clamp_unit_transit_claim(uid)

	var dead_workers: Array[int] = []
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid):
			dead_workers.append(uid)
			continue
		var w: Dictionary = _assigned_workers[uid] as Dictionary
		var unit: Unit = w.get("unit") as Unit
		var order: UnitOrder = w.get("order") as UnitOrder
		if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
			dead_workers.append(uid)
		elif order == null or not order.is_active():
			dead_workers.append(uid)
	if not dead_workers.is_empty():
		for uid: int in dead_workers:
			_assigned_workers.erase(uid)
			_builder_slot_positions.erase(uid)
			_worker_order_ids.erase(uid)
		_transaction_revision += 1
		_rebalance_worker_roles(false)


func _count_auto_workers() -> int:
	var count: int = 0
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid):
			continue
		var raw: Dictionary = _assigned_workers[uid] as Dictionary
		if not bool(raw.get("force_transporter", false)):
			count += 1
	return count


func _count_builders() -> int:
	var count: int = 0
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid):
			continue
		if int((_assigned_workers[uid] as Dictionary).get("role", WorkerRole.UNASSIGNED)) == WorkerRole.BUILDER:
			count += 1
	return count


func _has_claimable_reserved_piles_for(unit: Unit) -> bool:
	if _inventory == null or reservation_id.is_empty() or not is_active():
		return false
	for res_id: StringName in _required_amounts.keys():
		var remaining_claim: int = get_remaining_supply_to_claim(res_id, unit)
		if remaining_claim <= 0:
			continue
		var entries: Array[Dictionary] = _inventory.get_reserved_pile_entries(reservation_id, res_id)
		for entry: Dictionary in entries:
			var pile_id: int = int(entry.get("pile_id", 0))
			var reserved_amt: int = int(entry.get("reserved_amount", 0))
			var other_pending: int = get_pending_pickup_amount(pile_id, res_id, unit)
			if maxi(0, reserved_amt - other_pending) > 0:
				return true
	return false


func _clear_mismatched_builder_anchors() -> void:
	var builder_idx: int = 0
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid):
			continue
		var is_builder: bool = int(_assigned_workers[uid]["role"]) == WorkerRole.BUILDER
		var anchor: Dictionary = _builder_slot_positions.get(uid, {})
		if not is_builder or (not anchor.is_empty() and int(anchor["slot_idx"]) != builder_idx):
			_builder_slot_positions.erase(uid)
		if is_builder:
			builder_idx += 1


func _rebalance_worker_roles(emit_changes: bool) -> void:
	var auto_ids: Array[int] = []
	var prev_roles: Dictionary = {}
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid):
			continue
		var raw: Dictionary = _assigned_workers[uid] as Dictionary
		prev_roles[uid] = raw.get("role", WorkerRole.UNASSIGNED)
		if bool(raw.get("force_transporter", false)):
			raw["role"] = WorkerRole.TRANSPORTER
		else:
			auto_ids.append(uid)

	var fully_supplied: bool = is_fully_supplied()
	if not fully_supplied:
		_supply_rebalance_completed = false

	var max_b: int = mini(2, maxi(0, definition.max_builders if definition != null else 2))
	if auto_ids.size() == 1:
		var sole_uid: int = auto_ids[0]
		var sole_entry: Dictionary = _assigned_workers[sole_uid] as Dictionary
		var sole_unit: Unit = sole_entry.get("unit") as Unit
		var keep_solo_builder: bool = (
			bool(sole_entry.get("solo_promoted_builder", false))
			and max_b >= 1
			and (
				fully_supplied
				or (not _has_claimable_reserved_piles_for(sole_unit) and not has_deliverable_transit_claim_for_unit(sole_unit))
			)
		)
		if (
			not keep_solo_builder
			and _supply_rebalance_completed
			and fully_supplied
			and max_b >= 1
			and int(prev_roles.get(sole_uid, WorkerRole.UNASSIGNED)) == WorkerRole.BUILDER
			and not has_deliverable_transit_claim_for_unit(sole_unit)
		):
			keep_solo_builder = true
			sole_entry["solo_promoted_builder"] = true
		if keep_solo_builder:
			sole_entry["role"] = WorkerRole.BUILDER
		else:
			sole_entry["role"] = WorkerRole.SOLO_SUPPLIER
			sole_entry["solo_promoted_builder"] = false
	elif auto_ids.size() >= 2:
		if _supply_rebalance_completed and fully_supplied:
			# Supply completed & rebalanced: keep existing builders first and assign remaining slots up to max_b.
			var existing_builders: Array[int] = []
			var other_autos: Array[int] = []
			for uid: int in auto_ids:
				if int(prev_roles.get(uid, WorkerRole.UNASSIGNED)) == WorkerRole.BUILDER:
					existing_builders.append(uid)
				else:
					other_autos.append(uid)
			var ordered_autos: Array[int] = []
			ordered_autos.append_array(existing_builders)
			ordered_autos.append_array(other_autos)
			var assigned_builders: int = 0
			for uid: int in ordered_autos:
				var entry: Dictionary = _assigned_workers[uid] as Dictionary
				if assigned_builders < max_b:
					entry["role"] = WorkerRole.BUILDER
					assigned_builders += 1
				else:
					entry["role"] = WorkerRole.UNASSIGNED
					entry["solo_promoted_builder"] = false
		else:
			# Keep an existing transporter/solo_supplier in the transporter seat if present
			# so adding a 2nd or 3rd worker does not flip the first worker off its trip.
			var transporter_uid: int = -1
			for uid: int in auto_ids:
				var prev: int = int(prev_roles.get(uid, WorkerRole.UNASSIGNED))
				if prev == WorkerRole.TRANSPORTER or prev == WorkerRole.SOLO_SUPPLIER:
					transporter_uid = uid
					break
			if transporter_uid == -1:
				transporter_uid = auto_ids[0]

			var assigned_builders: int = 0
			for uid: int in auto_ids:
				var entry: Dictionary = _assigned_workers[uid] as Dictionary
				entry["solo_promoted_builder"] = false
				if uid == transporter_uid:
					entry["role"] = WorkerRole.TRANSPORTER
				elif assigned_builders < max_b:
					entry["role"] = WorkerRole.BUILDER
					assigned_builders += 1
				else:
					entry["role"] = WorkerRole.UNASSIGNED

	# Anchors survive stable roles, but never a role/ordered slot change.
	_clear_mismatched_builder_anchors()
	_refresh_assembly_substate()
	var changed: bool = false
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid):
			continue
		var entry: Dictionary = _assigned_workers[uid] as Dictionary
		if int(entry.get("role", WorkerRole.UNASSIGNED)) != int(prev_roles.get(uid, WorkerRole.UNASSIGNED)):
			changed = true
			break

	if emit_changes or changed:
		_transaction_revision += 1
		workers_changed.emit(self)
		state_changed.emit(self)


func _get_sorted_required_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for k: Variant in _required_amounts.keys():
		keys.append(k as StringName)
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return keys


static func _normalize_costs(costs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in costs.keys():
		var amt: int = int(costs[key])
		if amt <= 0:
			continue
		var res_id: StringName = StringName(String(key))
		if res_id.is_empty():
			return {}
		result[res_id] = amt
	return result


static func _prep_rejection(reason: String, dependency: String = "") -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"dependency": dependency,
	}


func _has_stale_participants_pure() -> bool:
	for uid_key: Variant in _pending_pickups.keys():
		var entry: Dictionary = _pending_pickups[uid_key] as Dictionary
		var entry_unit: Unit = entry.get("unit") as Unit
		if entry_unit == null or not is_instance_valid(entry_unit) or not entry_unit.is_inside_tree():
			return true
	for uid_key: Variant in _transit_claims.keys():
		var claim: Dictionary = _transit_claims[uid_key] as Dictionary
		var claim_unit: Unit = claim.get("unit") as Unit
		if claim_unit == null or not is_instance_valid(claim_unit):
			return true
	for uid: int in _worker_order_ids:
		if not _assigned_workers.has(uid):
			return true
		var w: Dictionary = _assigned_workers[uid] as Dictionary
		var w_unit: Unit = w.get("unit") as Unit
		var order: UnitOrder = w.get("order") as UnitOrder
		if w_unit == null or not is_instance_valid(w_unit) or not w_unit.is_inside_tree():
			return true
		if order == null or not order.is_active():
			return true
	return false


func _resolve_resource_definition_pure(resource_id: StringName) -> ResourceDefinition:
	if _resource_defs.has(resource_id):
		var def_val: Variant = _resource_defs[resource_id]
		if def_val is ResourceDefinition and (def_val as ResourceDefinition).is_valid():
			return def_val as ResourceDefinition
	if _inventory != null:
		var src: SettlementStorageSource = _inventory.get_storage_source()
		if src is GroundPileManager:
			var mgr_def: ResourceDefinition = (src as GroundPileManager).get_resource_definition_pure(resource_id)
			if mgr_def != null:
				return mgr_def
	var fallback_path: String = "res://data/resources/%s.tres" % String(resource_id)
	if ResourceLoader.exists(fallback_path):
		var loaded: Resource = ResourceLoader.load(fallback_path)
		if loaded is ResourceDefinition and (loaded as ResourceDefinition).is_valid():
			return loaded as ResourceDefinition
	return null


func _read_in_transit_amounts_pure() -> Dictionary:
	var totals: Dictionary = {}
	for res_id: StringName in _required_amounts.keys():
		totals[res_id] = 0
	for uid_key: Variant in _transit_claims.keys():
		var claim: Dictionary = _transit_claims[uid_key] as Dictionary
		var amounts: Dictionary = claim.get("amounts", {}) as Dictionary
		for res_key: Variant in amounts.keys():
			var res_id: StringName = res_key as StringName
			totals[res_id] = int(totals.get(res_id, 0)) + int(amounts[res_id])
	return totals


func _read_in_transit_amount_pure(resource_id: StringName) -> int:
	var totals: Dictionary = _read_in_transit_amounts_pure()
	return int(totals.get(resource_id, 0))


func _read_transit_claim_for_unit_pure(uid: int) -> Dictionary:
	if not _transit_claims.has(uid):
		return {}
	var claim: Dictionary = _transit_claims[uid] as Dictionary
	var raw: Dictionary = claim.get("amounts", {}) as Dictionary
	var cleaned: Dictionary = {}
	for res_key: Variant in raw.keys():
		var res_id: StringName = res_key as StringName
		var amt: int = int(raw[res_id])
		if amt > 0:
			cleaned[res_id] = amt
	return cleaned


func _read_pending_pickup_amount_pure(pile_id_val: int, resource_id: StringName, exclude_uid: int = -1) -> int:
	var total: int = 0
	for uid_key: Variant in _pending_pickups.keys():
		var uid: int = int(uid_key)
		if uid == exclude_uid:
			continue
		var entry: Dictionary = _pending_pickups[uid_key] as Dictionary
		if int(entry["pile_id"]) == pile_id_val and (entry["resource_id"] as StringName) == resource_id:
			total += int(entry["amount"])
	return total


func _read_total_pending_pickup_for_resource_pure(resource_id: StringName, exclude_uid: int = -1) -> int:
	var total: int = 0
	for uid_key: Variant in _pending_pickups.keys():
		var uid: int = int(uid_key)
		if uid == exclude_uid:
			continue
		var entry: Dictionary = _pending_pickups[uid_key] as Dictionary
		if (entry["resource_id"] as StringName) == resource_id:
			total += int(entry["amount"])
	return total


func _read_remaining_supply_to_claim_pure(resource_id: StringName, exclude_uid: int = -1) -> int:
	var remaining_dropoff: int = get_remaining_need_for_dropoff(resource_id)
	var in_transit: int = _read_in_transit_amount_pure(resource_id)
	var pending_other: int = _read_total_pending_pickup_for_resource_pure(resource_id, exclude_uid)
	return maxi(0, remaining_dropoff - in_transit - pending_other)


func _read_accounting_breakdown_pure(resource_id: StringName) -> Dictionary:
	var required: int = get_required_amount(resource_id)
	var reserved: int = get_reserved_in_piles_amount(resource_id)
	var in_transit: int = _read_in_transit_amount_pure(resource_id)
	var delivered_buffer: int = get_delivered_buffer_amount(resource_id)
	var consumed: int = get_consumed_amount(resource_id)
	var uncovered_missing: int = maxi(0, required - (delivered_buffer + consumed) - reserved - in_transit)
	return {
		"required": required,
		"reserved": reserved,
		"in_transit": in_transit,
		"delivered_buffer": delivered_buffer,
		"consumed": consumed,
		"uncovered_missing": uncovered_missing,
		"sum": reserved + in_transit + delivered_buffer + consumed + uncovered_missing,
	}


func _verify_accounting_invariant_pure() -> bool:
	for res_id: StringName in _required_amounts.keys():
		var b: Dictionary = _read_accounting_breakdown_pure(res_id)
		if (
			int(b["reserved"]) < 0
			or int(b["in_transit"]) < 0
			or int(b["delivered_buffer"]) < 0
			or int(b["consumed"]) < 0
			or int(b["uncovered_missing"]) < 0
		):
			return false
		if int(b["sum"]) != int(b["required"]):
			return false
	return true


func _collect_known_other_sites_pure() -> Array[ConstructionSite]:
	var result: Array[ConstructionSite] = []
	# Only live sites in this world and region can attest a claim. Caller hints
	# cannot extend that authority.
	if is_inside_tree():
		var world: World3D = get_world_3d()
		for node: Node in get_tree().get_nodes_in_group(GROUP_CONSTRUCTION_SITES):
			if node is ConstructionSite and node != self:
				var other := node as ConstructionSite
				if other.is_inside_tree() and other.region_id == region_id and other.get_world_3d() == world:
					result.append(other)
	return result


func _has_conflicting_unit_identity_pure(target_unit: Unit, target_load: UnitCarryLoad) -> bool:
	if is_inside_tree() and get_world_3d() != null and get_tree() != null:
		var id_check: Dictionary = ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(
			get_world_3d(),
			region_id,
			target_unit,
			target_load,
			get_tree()
		)
		if not bool(id_check.get("ok", false)):
			return true
	var target_prov_id: StringName = target_load.get_provenance_unit_id()
	var sites_to_check: Array[ConstructionSite] = [self]
	sites_to_check.append_array(_collect_known_other_sites_pure())
	for s: ConstructionSite in sites_to_check:
		for uid_key: Variant in s._assigned_workers.keys():
			var w: Dictionary = s._assigned_workers[uid_key] as Dictionary
			var u: Unit = w.get("unit") as Unit
			if _unit_conflicts_with_target(u, target_unit, target_load, target_prov_id):
				return true
		for uid_key: Variant in s._transit_claims.keys():
			var c: Dictionary = s._transit_claims[uid_key] as Dictionary
			var u: Unit = c.get("unit") as Unit
			if _unit_conflicts_with_target(u, target_unit, target_load, target_prov_id):
				return true
		for uid_key: Variant in s._pending_pickups.keys():
			var p: Dictionary = s._pending_pickups[uid_key] as Dictionary
			var u: Unit = p.get("unit") as Unit
			if _unit_conflicts_with_target(u, target_unit, target_load, target_prov_id):
				return true
	return false


static func _unit_conflicts_with_target(
	other_unit: Unit,
	target_unit: Unit,
	target_load: UnitCarryLoad,
	target_prov_id: StringName
) -> bool:
	if other_unit == null or not is_instance_valid(other_unit) or other_unit == target_unit:
		return false
	var other_load: UnitCarryLoad = other_unit.get_carry_load()
	if other_load == null:
		return false
	if other_load == target_load:
		return true
	if other_load.is_provenance_enabled() and other_load.get_provenance_unit_id() == target_prov_id:
		return true
	return false


func _verify_unit_claims_reconciled_with_provenance_pure(
	typed_unit: Unit,
	carry_load: UnitCarryLoad
) -> Dictionary:
	var uid: int = typed_unit.get_instance_id()
	var snap: Dictionary = carry_load.provenance_snapshot()
	if snap.is_empty() or not snap.has("ledger"):
		return _prep_rejection("provenance_disabled", "carry_load")

	var ledger_snap: Dictionary = snap["ledger"] as Dictionary
	var lots: Dictionary = ledger_snap.get("lots", {}) as Dictionary
	var unit_prov_id: StringName = carry_load.get_provenance_unit_id()
	var site_reserved_lots: Dictionary = {}
	var site_generations: Dictionary = {}

	for lot_key: Variant in lots.keys():
		var lot: Dictionary = lots[lot_key] as Dictionary
		if StringName(lot.get("unit_id", &"")) != unit_prov_id:
			return _prep_rejection("ambiguous_unit_identity", "provenance_ledger")
		var lot_res: StringName = StringName(lot.get("resource_id", &""))
		var lot_qty: int = int(lot.get("quantity", 0))
		var lot_origin: StringName = StringName(lot.get("origin", &""))
		var lot_site: StringName = StringName(lot.get("site_id", &""))
		var lot_gen: int = int(lot.get("generation", -1))
		if lot_origin == CarryProvenanceLedger.FREE_GATHERED:
			continue
		if lot_origin == CarryProvenanceLedger.SITE_RESERVED:
			if lot_site == site_id and lot_gen != _generation:
				return _prep_rejection("generation_mismatch", "provenance_ledger")
			if site_generations.has(lot_site) and int(site_generations[lot_site]) != lot_gen:
				return _prep_rejection("conflicting_site_claims", "provenance_ledger")
			site_generations[lot_site] = lot_gen
			if not site_reserved_lots.has(lot_site):
				site_reserved_lots[lot_site] = {}
			var per_site: Dictionary = site_reserved_lots[lot_site] as Dictionary
			per_site[lot_res] = int(per_site.get(lot_res, 0)) + lot_qty
		else:
			return _prep_rejection("invalid_lot_origin", "provenance_ledger")

	if _transit_claims.has(uid):
		var self_claim_entry: Dictionary = _transit_claims[uid] as Dictionary
		if self_claim_entry.get("unit") != typed_unit or self_claim_entry.get("carry_load") != carry_load:
			return _prep_rejection("carry_load_mismatch", "claims")
	var self_claim: Dictionary = _read_transit_claim_for_unit_pure(uid)
	var self_lots: Dictionary = site_reserved_lots.get(site_id, {}) as Dictionary
	if self_claim != self_lots:
		return _prep_rejection("unreconciled_site_claim", "claims")

	var sites_by_id: Dictionary = {site_id: self}
	var peer_claim_revisions: Dictionary = {}
	for other_site: ConstructionSite in _collect_known_other_sites_pure():
		if other_site.site_id.is_empty():
			continue
		if sites_by_id.has(other_site.site_id):
			return _prep_rejection("conflicting_site_claims", "claims")
		sites_by_id[other_site.site_id] = other_site

		var other_claim: Dictionary = other_site._read_transit_claim_for_unit_pure(uid)
		var other_lots: Dictionary = site_reserved_lots.get(other_site.site_id, {}) as Dictionary
		if other_claim.is_empty() and other_lots.is_empty():
			continue
		if not other_site.is_valid() or other_site.get_generation() <= 0:
			return _prep_rejection("unknown_reserved_site", "claims")
		var other_entry: Dictionary = other_site._transit_claims.get(uid, {}) as Dictionary
		if (
			other_claim != other_lots
			or other_entry.get("unit") != typed_unit
			or other_entry.get("carry_load") != carry_load
		):
			return _prep_rejection("conflicting_site_claims", "claims")
		if int(site_generations.get(other_site.site_id, -1)) != other_site.get_generation():
			return _prep_rejection("generation_mismatch", "claims")
		peer_claim_revisions[other_site.site_id] = {
			"instance_id": other_site.get_instance_id(),
			"generation": other_site.get_generation(),
			"revision": other_site.get_transaction_revision(),
		}

	for lot_site: Variant in site_reserved_lots:
		if not sites_by_id.has(lot_site):
			return _prep_rejection("unknown_reserved_site", "claims")

	# validate_provenance already reconciled the aggregate, including free lots.
	return {"ok": true, "ledger_snapshot": ledger_snap, "peer_claim_revisions": peer_claim_revisions}


## Pure opt-in preparation of a site-reserved pile withdrawal to carry load with provenance and claim.
## Strictly side-effect-free. This is an accounting diagnostic, not physical authorization.
## Operation IDs stay unreserved until a future coordinator commits the withdrawal.
func prepare_reserved_withdrawal(
	unit: Variant,
	pile_id: Variant,
	resource_id: Variant,
	requested_amount: Variant,
	operation_id: Variant,
	lot_id: Variant,
	options: Dictionary = {}
) -> Dictionary:
	if is_transaction_busy():
		return _prep_rejection("busy", "site")
	if _inventory != null and _inventory.is_transaction_busy():
		return _prep_rejection("busy", "inventory")
	var storage_source: SettlementStorageSource = _inventory.get_storage_source() if _inventory != null else null
	if storage_source != null and storage_source.is_batch_active():
		return _prep_rejection("busy", "storage")
	if storage_source is GroundPileManager and (storage_source as GroundPileManager).is_locked():
		return _prep_rejection("busy", "storage")
	if unit is Unit and is_instance_valid(unit):
		var pre_cl: UnitCarryLoad = (unit as Unit).get_carry_load()
		if pre_cl != null and pre_cl.is_transaction_busy():
			return _prep_rejection("busy", "carry_load")
	if options.has("carry_load") and options["carry_load"] is UnitCarryLoad:
		if (options["carry_load"] as UnitCarryLoad).is_transaction_busy():
			return _prep_rejection("busy", "carry_load")

	var parsed: Dictionary = _validate_prepare_preconditions_and_parse(
		unit, pile_id, resource_id, requested_amount, operation_id, lot_id, options
	)
	if not bool(parsed.get("ok", false)):
		return parsed

	# Validate a supplied prior plan as a full current plan before taking guards.
	# Revalidation reconstructs without prior_plan, so it never follows a chain.
	if options.has("prior_plan"):
		var prior_check: Dictionary = validate_reserved_withdrawal_plan(options["prior_plan"])
		if not prior_check["ok"]:
			return prior_check

	var typed_unit: Unit = parsed["typed_unit"] as Unit
	var carry_load: UnitCarryLoad = parsed["carry_load"] as UnitCarryLoad
	var pile_manager: GroundPileManager = parsed["pile_manager"] as GroundPileManager

	# Cooperative guard acquisition in fixed R2 order: (1) site -> (2) storage -> (3) carry_load.
	_is_preparing_or_transacting = true
	pile_manager._is_preparing_withdrawal = true
	carry_load._provenance_busy = true

	var outcome: Dictionary = _prepare_reserved_withdrawal_guarded(
		typed_unit,
		carry_load,
		pile_manager,
		int(parsed["pile_id_int"]),
		parsed["res_id_sn"] as StringName,
		int(parsed["req_amount"]),
		parsed["op_id_sn"] as StringName,
		parsed["lot_id_sn"] as StringName,
		options
	)

	carry_load._provenance_busy = false
	pile_manager._is_preparing_withdrawal = false
	_is_preparing_or_transacting = false
	return outcome


func _prepare_reserved_withdrawal_under_coordinator_guards(
	unit: Variant,
	pile_id: Variant,
	resource_id: Variant,
	requested_amount: Variant,
	operation_id: Variant,
	lot_id: Variant,
	options: Dictionary = {}
) -> Dictionary:
	if not _is_preparing_or_transacting:
		return _prep_rejection("missing_coordinator_guard", "site")
	var parsed: Dictionary = _validate_prepare_preconditions_and_parse(
		unit, pile_id, resource_id, requested_amount, operation_id, lot_id, options
	)
	if not bool(parsed.get("ok", false)):
		return parsed
	var typed_unit: Unit = parsed["typed_unit"] as Unit
	var carry_load: UnitCarryLoad = parsed["carry_load"] as UnitCarryLoad
	var pile_manager: GroundPileManager = parsed["pile_manager"] as GroundPileManager
	if not pile_manager._is_preparing_withdrawal or not carry_load._provenance_busy:
		return _prep_rejection("missing_coordinator_guard", "coordinator")
	return _prepare_reserved_withdrawal_guarded(
		typed_unit,
		carry_load,
		pile_manager,
		int(parsed["pile_id_int"]),
		parsed["res_id_sn"] as StringName,
		int(parsed["req_amount"]),
		parsed["op_id_sn"] as StringName,
		parsed["lot_id_sn"] as StringName,
		options
	)


func _validate_prepare_preconditions_and_parse(
	unit: Variant,
	pile_id: Variant,
	resource_id: Variant,
	requested_amount: Variant,
	operation_id: Variant,
	lot_id: Variant,
	options: Dictionary = {}
) -> Dictionary:
	if not is_valid() or not is_inside_tree() or _site_state != SiteState.ACTIVE or _generation <= 0:
		return _prep_rejection("site_not_active", "site")
	if _has_stale_participants_pure():
		return _prep_rejection("stale_site_participants", "site")

	if options.has("site_id"):
		if not CarryProvenanceLedger._id(options["site_id"]) or StringName(options["site_id"]) != site_id:
			return _prep_rejection("site_mismatch", "site")
	if options.has("generation"):
		if typeof(options["generation"]) != TYPE_INT or int(options["generation"]) != _generation:
			return _prep_rejection("invalid_generation", "site")
	if options.has("reservation_id"):
		if not CarryProvenanceLedger._id(options["reservation_id"]) or StringName(options["reservation_id"]) != reservation_id:
			return _prep_rejection("reservation_mismatch", "site")

	var storage_source: SettlementStorageSource = _inventory.get_storage_source() if _inventory != null else null
	if storage_source == null or not (storage_source is GroundPileManager):
		return _prep_rejection("unsupported_storage_source", "storage")
	var pile_manager: GroundPileManager = storage_source as GroundPileManager

	if not (unit is Unit) or not is_instance_valid(unit) or not (unit as Unit).is_inside_tree():
		return _prep_rejection("invalid_unit", "unit")
	var typed_unit: Unit = unit as Unit
	if typed_unit.get_world_3d() != get_world_3d():
		return _prep_rejection("unit_world_mismatch", "unit")
	var carry_load: UnitCarryLoad = typed_unit.get_carry_load()
	if carry_load == null:
		return _prep_rejection("invalid_carry_load", "carry_load")
	if options.has("carry_load") and options["carry_load"] != carry_load:
		return _prep_rejection("carry_load_mismatch", "carry_load")
	if not carry_load.is_provenance_enabled() or not CarryProvenanceLedger._id(carry_load.get_provenance_unit_id()):
		return _prep_rejection("provenance_disabled", "carry_load")
	if not carry_load.validate_provenance():
		return _prep_rejection("unreconciled_cargo", "carry_load")
	if options.has("unit_id"):
		if not CarryProvenanceLedger._id(options["unit_id"]) or StringName(options["unit_id"]) != carry_load.get_provenance_unit_id():
			return _prep_rejection("unit_mismatch", "unit")
	if _has_conflicting_unit_identity_pure(typed_unit, carry_load):
		return _prep_rejection("ambiguous_unit_identity", "unit")

	if not CarryProvenanceLedger._id(operation_id):
		return _prep_rejection("invalid_operation", "input")
	if not CarryProvenanceLedger._id(lot_id):
		return _prep_rejection("invalid_lot", "input")
	if not CarryProvenanceLedger._id(resource_id):
		return _prep_rejection("invalid_resource", "input")
	if typeof(pile_id) != TYPE_INT or int(pile_id) <= 0:
		return _prep_rejection("invalid_pile", "input")
	if typeof(requested_amount) != TYPE_INT or int(requested_amount) <= 0:
		return _prep_rejection("invalid_amount", "input")
	if options.has("require_assigned_worker") and typeof(options["require_assigned_worker"]) != TYPE_BOOL:
		return _prep_rejection("invalid_worker_requirement", "input")

	var op_id_sn: StringName = StringName(operation_id)
	var lot_id_sn: StringName = StringName(lot_id)
	var res_id_sn: StringName = StringName(resource_id)
	var pile_id_int: int = int(pile_id)
	var req_amount: int = int(requested_amount)
	if not _required_amounts.has(res_id_sn) or get_required_amount(res_id_sn) <= 0:
		return _prep_rejection("resource_not_required", "site")

	return {
		"ok": true,
		"typed_unit": typed_unit,
		"carry_load": carry_load,
		"pile_manager": pile_manager,
		"pile_id_int": pile_id_int,
		"res_id_sn": res_id_sn,
		"req_amount": req_amount,
		"op_id_sn": op_id_sn,
		"lot_id_sn": lot_id_sn,
	}


func _prepare_reserved_withdrawal_guarded(
	typed_unit: Unit,
	carry_load: UnitCarryLoad,
	pile_manager: GroundPileManager,
	pile_id_int: int,
	res_id_sn: StringName,
	req_amount: int,
	op_id_sn: StringName,
	lot_id_sn: StringName,
	options: Dictionary
) -> Dictionary:
	var uid: int = typed_unit.get_instance_id()
	var pile: GroundResourcePile = pile_manager.get_pile_by_id(pile_id_int)
	var current_revisions := {
		"site_revision": _transaction_revision,
		"site_work_serial": _work_cycle_serial,
		"inventory_revision": _inventory.get_transaction_revision(),
		"storage_revision": pile_manager.get_transaction_revision(),
		"pile_ledger_revision": pile_manager.get_pile_ledger_revision(),
		"pile_revision": pile.get_transaction_revision() if is_instance_valid(pile) else -1,
		"carry_load_revision": carry_load.get_transaction_revision(),
	}

	if options.has("expected_revisions"):
		var expected: Variant = options["expected_revisions"]
		if not (expected is Dictionary) or expected.size() != current_revisions.size():
			return _prep_rejection("stale_revision", "revisions")
		for rev_key: Variant in current_revisions:
			if not expected.has(rev_key) or typeof(expected[rev_key]) != TYPE_INT or current_revisions[rev_key] != expected[rev_key]:
				return _prep_rejection("stale_revision", "revisions")

	if options.has("prior_plan"):
		var prior: Dictionary = options["prior_plan"]
		if prior.operation_id == op_id_sn:
			if (
				prior.lot_id != lot_id_sn
				or prior.pile_id != pile_id_int
				or prior.resource_id != res_id_sn
				or prior.requested_amount != req_amount
				or prior.unit_instance_id != uid
				or prior.unit_id != carry_load.get_provenance_unit_id()
			):
				return _prep_rejection("operation_conflict", "revisions")
		elif prior.lot_id == lot_id_sn:
			return _prep_rejection("duplicate_lot", "provenance_ledger")

	var claim_check: Dictionary = _verify_unit_claims_reconciled_with_provenance_pure(typed_unit, carry_load)
	if not bool(claim_check.get("ok", false)):
		return claim_check
	var ledger_snap: Dictionary = claim_check["ledger_snapshot"] as Dictionary
	var ledger_ops: Dictionary = ledger_snap.get("operations", {}) as Dictionary
	var ledger_used_lots: Dictionary = ledger_snap.get("used_lots", {}) as Dictionary
	if ledger_ops.has(op_id_sn):
		return _prep_rejection("operation_conflict", "provenance_ledger")
	if ledger_used_lots.has(lot_id_sn):
		return _prep_rejection("duplicate_lot", "provenance_ledger")

	if not _verify_accounting_invariant_pure():
		return _prep_rejection("accounting_invariant_violated", "accounting")

	if _assigned_workers.has(uid):
		var worker_entry: Dictionary = _assigned_workers[uid] as Dictionary
		var worker_role: WorkerRole = worker_entry.get("role", WorkerRole.UNASSIGNED) as WorkerRole
		if worker_role != WorkerRole.SOLO_SUPPLIER and worker_role != WorkerRole.TRANSPORTER:
			return _prep_rejection("claim_not_eligible", "claims")
		var worker_order: ConstructOrder = worker_entry.get("order") as ConstructOrder
		if (
			worker_entry.get("unit") != typed_unit
			or worker_order == null
			or worker_order.site != self
			or worker_order != typed_unit.get_current_order()
			or not worker_order.is_active()
		):
			return _prep_rejection("claim_not_eligible", "claims")
	elif bool(options.get("require_assigned_worker", false)):
		return _prep_rejection("worker_not_registered", "claims")

	if _pending_pickups.has(uid):
		var pending_entry: Dictionary = _pending_pickups[uid] as Dictionary
		if (
			pending_entry.get("unit") != typed_unit
			or int(pending_entry.get("pile_id", 0)) != pile_id_int
			or (pending_entry.get("resource_id") as StringName) != res_id_sn
			or int(pending_entry.get("amount", 0)) < req_amount
		):
			return _prep_rejection("claim_not_eligible", "claims")

	if is_fully_supplied():
		return _prep_rejection("site_already_supplied", "site")
	if _read_remaining_supply_to_claim_pure(res_id_sn, uid) < req_amount:
		return _prep_rejection("claim_not_eligible", "claims")

	var pile_plan: Dictionary = pile_manager._prepare_reserved_pile_withdrawal(
		pile_id_int,
		reservation_id,
		res_id_sn,
		req_amount
	)
	if not bool(pile_plan.get("ok", false)):
		return _prep_rejection(String(pile_plan.get("reason", "pile_preparation_failed")), "pile")

	var reserved_on_pile: int = int((pile_plan["before"] as Dictionary).get("pile_reserved_for_site", 0))
	var other_pending_on_pile: int = _read_pending_pickup_amount_pure(pile_id_int, res_id_sn, uid)
	if reserved_on_pile - other_pending_on_pile < req_amount:
		return _prep_rejection("claim_not_eligible", "claims")

	var pile_unit_weight: int = int(pile_plan["unit_weight"])
	var site_def: ResourceDefinition = _resolve_resource_definition_pure(res_id_sn)
	if site_def != null:
		if not site_def.is_valid() or site_def.resource_id != res_id_sn or site_def.unit_weight != pile_unit_weight:
			return _prep_rejection("resource_or_weight_mismatch", "pile")
	if options.has("unit_weight"):
		if typeof(options["unit_weight"]) != TYPE_INT or int(options["unit_weight"]) != pile_unit_weight:
			return _prep_rejection("resource_or_weight_mismatch", "input")

	var carry_plan: Dictionary = carry_load._prepare_provenance_add(
		op_id_sn,
		lot_id_sn,
		res_id_sn,
		pile_unit_weight,
		req_amount,
		CarryProvenanceLedger.SITE_RESERVED,
		site_id,
		_generation
	)
	if not bool(carry_plan.get("ok", false)):
		var fail_reason: String = String(carry_plan.get("reason", "carry_preparation_failed"))
		if fail_reason == "invalid_resource" and not carry_load._is_weight_consistent(res_id_sn, pile_unit_weight):
			fail_reason = "resource_or_weight_mismatch"
		return _prep_rejection(fail_reason, "carry_load")
	if bool(carry_plan.get("replayed", false)):
		return _prep_rejection("operation_conflict", "provenance_ledger")

	var before_unit_claim: Dictionary = _read_transit_claim_for_unit_pure(uid)
	var after_unit_claim: Dictionary = before_unit_claim.duplicate(true)
	after_unit_claim[res_id_sn] = int(after_unit_claim.get(res_id_sn, 0)) + req_amount

	var before_pending: Dictionary = (_pending_pickups[uid] as Dictionary).duplicate(true) if _pending_pickups.has(uid) else {}
	var after_pending: Dictionary = {}
	var before_in_transit: Dictionary = _read_in_transit_amounts_pure()
	var after_in_transit: Dictionary = before_in_transit.duplicate(true)
	after_in_transit[res_id_sn] = int(after_in_transit.get(res_id_sn, 0)) + req_amount

	var before_accounting: Dictionary = _read_accounting_breakdown_pure(res_id_sn)
	var after_reserved: int = int(before_accounting["reserved"]) - req_amount
	var after_in_transit_amt: int = int(before_accounting["in_transit"]) + req_amount
	var after_buffer: int = int(before_accounting["delivered_buffer"])
	var after_consumed: int = int(before_accounting["consumed"])
	var after_missing: int = int(before_accounting["uncovered_missing"])
	var after_sum: int = after_reserved + after_in_transit_amt + after_buffer + after_consumed + after_missing

	var after_ledger_lots: Dictionary = (carry_plan["ledger"] as Dictionary).get("lots", {}) as Dictionary
	var after_site_res_lot_sum: int = 0
	for l_key: Variant in after_ledger_lots.keys():
		var l_dict: Dictionary = after_ledger_lots[l_key] as Dictionary
		if (
			StringName(l_dict.get("origin", &"")) == CarryProvenanceLedger.SITE_RESERVED
			and StringName(l_dict.get("site_id", &"")) == site_id
			and StringName(l_dict.get("resource_id", &"")) == res_id_sn
		):
			after_site_res_lot_sum += int(l_dict.get("quantity", 0))

	if (
		after_reserved < 0
		or after_reserved != int((pile_plan["after"] as Dictionary)["site_total_reserved_resource"])
		or after_in_transit_amt != int(after_in_transit[res_id_sn])
		or after_sum != int(before_accounting["required"])
		or after_site_res_lot_sum != int(after_unit_claim[res_id_sn])
		or int((carry_plan["amounts"] as Dictionary).get(res_id_sn, -1)) != carry_load.get_amount(res_id_sn) + req_amount
	):
		return _prep_rejection("projected_invariant_violation", "accounting")

	return {
		"ok": true,
		"reason": "",
		"dependency": "",
		"dry_run_only": true,
		"commit_supported": false,
		"validation_scope": "accounting_only",
		"physical_pickup_authorized": false,
		"worker_registered": _assigned_workers.has(uid),
		"operation_id": op_id_sn,
		"lot_id": lot_id_sn,
		"site_instance_id": get_instance_id(),
		"site_id": site_id,
		"generation": _generation,
		"reservation_id": reservation_id,
		"region_id": region_id,
		"pile_id": pile_id_int,
		"pile_instance_id": int(pile_plan["pile_instance_id"]),
		"resource_id": res_id_sn,
		"unit_weight": pile_unit_weight,
		"requested_amount": req_amount,
		"unit_instance_id": uid,
		"unit_id": carry_load.get_provenance_unit_id(),
		"revisions": current_revisions,
		"peer_claim_revisions": claim_check["peer_claim_revisions"],
		"lock_order": ["site", "inventory_storage", "carry_load"],
		"pile_plan": pile_plan,
		"carry_plan": {
			"before_snapshot": carry_plan["base"],
			"before_capacity": carry_plan["capacity"],
			"before_weight": carry_load.get_current_weight(),
			"after_weight": carry_load.get_current_weight() + req_amount * pile_unit_weight,
			"after_amounts": carry_plan["amounts"],
			"after_ledger": carry_plan["ledger"],
			"new_lot": {
				"lot_id": lot_id_sn,
				"unit_id": carry_load.get_provenance_unit_id(),
				"resource_id": res_id_sn,
				"quantity": req_amount,
				"origin": CarryProvenanceLedger.SITE_RESERVED,
				"site_id": site_id,
				"generation": _generation,
			},
			"raw_add_plan": carry_plan,
		},
		"claim_plan": {
			"unit_instance_id": uid,
			"before_transit_claim": before_unit_claim,
			"after_transit_claim": after_unit_claim,
			"before_pending_pickup": before_pending,
			"after_pending_pickup": after_pending,
			"before_site_in_transit": before_in_transit,
			"after_site_in_transit": after_in_transit,
			"before_accounting": before_accounting,
			"after_accounting": {
				"required": int(before_accounting["required"]),
				"reserved": after_reserved,
				"in_transit": after_in_transit_amt,
				"delivered_buffer": after_buffer,
				"consumed": after_consumed,
				"uncovered_missing": after_missing,
				"sum": after_sum,
			},
		},
	}


## Validates an uncommitted plan produced by prepare_reserved_withdrawal, rejecting any
## stale or ABA revision, tampered payload, missing participant, or busy reentrancy.
func validate_reserved_withdrawal_plan(plan: Variant, options: Dictionary = {}) -> Dictionary:
	if not (plan is Dictionary):
		return _prep_rejection("invalid_plan", "plan")
	var p: Dictionary = plan as Dictionary
	if not p.get("ok") is bool or not p["ok"] or not p.get("dry_run_only") is bool or not p["dry_run_only"]:
		return _prep_rejection("invalid_plan", "plan")
	if not p.get("commit_supported") is bool or p["commit_supported"]:
		return _prep_rejection("invalid_plan", "plan")
	if not p.get("physical_pickup_authorized") is bool or p["physical_pickup_authorized"]:
		return _prep_rejection("invalid_plan", "plan")
	for key: String in ["operation_id", "lot_id", "site_id", "reservation_id", "resource_id", "unit_id"]:
		if not CarryProvenanceLedger._id(p.get(key)):
			return _prep_rejection("invalid_plan", "plan")
	for key: String in ["site_instance_id", "generation", "pile_id", "pile_instance_id", "unit_weight", "requested_amount", "unit_instance_id"]:
		if typeof(p.get(key)) != TYPE_INT or p[key] <= 0:
			return _prep_rejection("invalid_plan", "plan")
	for key: String in ["revisions", "peer_claim_revisions", "pile_plan", "carry_plan", "claim_plan"]:
		if not p.get(key) is Dictionary:
			return _prep_rejection("invalid_plan", "plan")
	if int(p["site_instance_id"]) != get_instance_id():
		return _prep_rejection("site_mismatch", "site")

	if is_transaction_busy():
		return _prep_rejection("busy", "site")
	if _inventory != null and _inventory.is_transaction_busy():
		return _prep_rejection("busy", "inventory")

	var storage_source: SettlementStorageSource = _inventory.get_storage_source() if _inventory != null else null
	if storage_source == null or not (storage_source is GroundPileManager):
		return _prep_rejection("unsupported_storage_source", "storage")
	var pile_manager: GroundPileManager = storage_source as GroundPileManager
	if pile_manager.is_locked() or pile_manager.is_batch_active():
		return _prep_rejection("busy", "storage")

	var unit_obj: Object = instance_from_id(int(p["unit_instance_id"]))
	if not (unit_obj is Unit) or not is_instance_valid(unit_obj):
		return _prep_rejection("invalid_unit", "unit")
	var typed_unit: Unit = unit_obj as Unit
	var carry_load: UnitCarryLoad = typed_unit.get_carry_load()
	if carry_load == null:
		return _prep_rejection("invalid_carry_load", "carry_load")
	if carry_load.is_transaction_busy():
		return _prep_rejection("busy", "carry_load")

	var pile: GroundResourcePile = pile_manager.get_pile_by_id(int(p["pile_id"]))
	if pile == null or not is_instance_valid(pile) or pile.get_instance_id() != int(p["pile_instance_id"]):
		return _prep_rejection("stale_revision", "pile")

	var plan_revs: Dictionary = p["revisions"] as Dictionary
	var live_revs := {
		"site_revision": _transaction_revision,
		"site_work_serial": _work_cycle_serial,
		"inventory_revision": _inventory.get_transaction_revision(),
		"storage_revision": pile_manager.get_transaction_revision(),
		"pile_ledger_revision": pile_manager.get_pile_ledger_revision(),
		"pile_revision": pile.get_transaction_revision(),
		"carry_load_revision": carry_load.get_transaction_revision(),
	}
	if plan_revs != live_revs:
		return _prep_rejection("stale_revision", "revisions")

	var check_opts := {
		"site_id": p["site_id"],
		"generation": p["generation"],
		"reservation_id": p["reservation_id"],
		"unit_id": p["unit_id"],
		"unit_weight": p["unit_weight"],
		"expected_revisions": plan_revs,
	}
	if options.has("require_assigned_worker"):
		check_opts["require_assigned_worker"] = options["require_assigned_worker"]

	var recomputed: Dictionary = prepare_reserved_withdrawal(
		typed_unit,
		p["pile_id"],
		p["resource_id"],
		p["requested_amount"],
		p["operation_id"],
		p["lot_id"],
		check_opts
	)
	if not bool(recomputed.get("ok", false)):
		return recomputed
	if recomputed != p:
		return _prep_rejection("tampered_or_stale_plan", "plan")
	return {"ok": true, "reason": "", "dependency": "", "dry_run_only": true,
		"commit_supported": false, "validation_scope": "accounting_only", "physical_pickup_authorized": false}


static func _validate_plan_shape_pure(plan: Variant, expected_site_instance_id: int) -> Dictionary:
	if not (plan is Dictionary):
		return _prep_rejection("invalid_plan", "plan")
	var p: Dictionary = plan as Dictionary
	if not p.get("ok") is bool or not p["ok"] or not p.get("dry_run_only") is bool or not p["dry_run_only"]:
		return _prep_rejection("invalid_plan", "plan")
	if not p.get("commit_supported") is bool or p["commit_supported"]:
		return _prep_rejection("invalid_plan", "plan")
	if not p.get("physical_pickup_authorized") is bool or p["physical_pickup_authorized"]:
		return _prep_rejection("invalid_plan", "plan")
	for key: String in ["operation_id", "lot_id", "site_id", "reservation_id", "resource_id", "unit_id"]:
		if not CarryProvenanceLedger._id(p.get(key)):
			return _prep_rejection("invalid_plan", "plan")
	for key: String in ["site_instance_id", "generation", "pile_id", "pile_instance_id", "unit_weight", "requested_amount", "unit_instance_id"]:
		if typeof(p.get(key)) != TYPE_INT or int(p[key]) <= 0:
			return _prep_rejection("invalid_plan", "plan")
	for key: String in ["revisions", "peer_claim_revisions", "pile_plan", "carry_plan", "claim_plan"]:
		if not (p.get(key) is Dictionary):
			return _prep_rejection("invalid_plan", "plan")
	if int(p["site_instance_id"]) != expected_site_instance_id:
		return _prep_rejection("site_mismatch", "site")
	return {"ok": true}


func _validate_plan_under_coordinator_guards(
	typed_unit: Unit,
	plan: Variant,
	options: Dictionary = {}
) -> Dictionary:
	if not _is_preparing_or_transacting:
		return _prep_rejection("missing_coordinator_guard", "site")
	var shape_check: Dictionary = _validate_plan_shape_pure(plan, get_instance_id())
	if not bool(shape_check.get("ok", false)):
		return shape_check
	var p: Dictionary = plan as Dictionary
	if typed_unit == null or not is_instance_valid(typed_unit) or int(p["unit_instance_id"]) != typed_unit.get_instance_id():
		return _prep_rejection("unit_mismatch", "unit")

	var storage_source: SettlementStorageSource = _inventory.get_storage_source() if _inventory != null else null
	if not (storage_source is GroundPileManager):
		return _prep_rejection("unsupported_storage_source", "storage")
	var pile_manager: GroundPileManager = storage_source as GroundPileManager
	var carry_load: UnitCarryLoad = typed_unit.get_carry_load()
	if carry_load == null:
		return _prep_rejection("invalid_carry_load", "carry_load")
	if not pile_manager._is_preparing_withdrawal or not carry_load._provenance_busy:
		return _prep_rejection("missing_coordinator_guard", "coordinator")

	var pile: GroundResourcePile = pile_manager.get_pile_by_id(int(p["pile_id"]))
	if pile == null or not is_instance_valid(pile) or pile.get_instance_id() != int(p["pile_instance_id"]):
		return _prep_rejection("stale_revision", "pile")

	var peer_claim_revs: Dictionary = p["peer_claim_revisions"] as Dictionary
	var live_peers_by_id: Dictionary = {}
	for other_site: ConstructionSite in _collect_known_other_sites_pure():
		if not other_site.site_id.is_empty():
			live_peers_by_id[other_site.site_id] = other_site
	for peer_key: Variant in peer_claim_revs.keys():
		if not (peer_key is StringName or peer_key is String):
			return _prep_rejection("invalid_plan", "plan")
		var peer_id: StringName = StringName(peer_key)
		var entry_var: Variant = peer_claim_revs[peer_key]
		if not (entry_var is Dictionary):
			return _prep_rejection("invalid_plan", "plan")
		var entry: Dictionary = entry_var as Dictionary
		if not live_peers_by_id.has(peer_id):
			return _prep_rejection("stale_peer_site_revision", "claims")
		var live_peer: ConstructionSite = live_peers_by_id[peer_id] as ConstructionSite
		if (
			live_peer.get_instance_id() != int(entry.get("instance_id", -1))
			or live_peer.get_generation() != int(entry.get("generation", -1))
			or live_peer.get_transaction_revision() != int(entry.get("revision", -1))
		):
			return _prep_rejection("stale_peer_site_revision", "claims")

	var plan_revs: Dictionary = p["revisions"] as Dictionary
	var live_revs := {
		"site_revision": _transaction_revision,
		"site_work_serial": _work_cycle_serial,
		"inventory_revision": _inventory.get_transaction_revision(),
		"storage_revision": pile_manager.get_transaction_revision(),
		"pile_ledger_revision": pile_manager.get_pile_ledger_revision(),
		"pile_revision": pile.get_transaction_revision(),
		"carry_load_revision": carry_load.get_transaction_revision(),
	}
	if plan_revs != live_revs:
		return _prep_rejection("stale_revision", "revisions")

	var check_opts := {
		"site_id": p["site_id"],
		"generation": p["generation"],
		"reservation_id": p["reservation_id"],
		"unit_id": p["unit_id"],
		"unit_weight": p["unit_weight"],
		"expected_revisions": plan_revs,
	}
	if options.has("require_assigned_worker"):
		check_opts["require_assigned_worker"] = options["require_assigned_worker"]

	var recomputed: Dictionary = _prepare_reserved_withdrawal_under_coordinator_guards(
		typed_unit,
		p["pile_id"],
		p["resource_id"],
		p["requested_amount"],
		p["operation_id"],
		p["lot_id"],
		check_opts
	)
	if not bool(recomputed.get("ok", false)):
		return recomputed
	if recomputed != p:
		return _prep_rejection("tampered_or_stale_plan", "plan")
	return {"ok": true, "plan": recomputed}


func _capture_claim_checkpoint(uid: int) -> Dictionary:
	var has_pending: bool = _pending_pickups.has(uid)
	var pending_copy: Dictionary = (_pending_pickups[uid] as Dictionary).duplicate(true) if has_pending else {}
	var has_claim: bool = _transit_claims.has(uid)
	var claim_amounts_copy: Dictionary = {}
	var claim_unit: Unit = null
	var claim_load: UnitCarryLoad = null
	if has_claim:
		var claim_dict: Dictionary = _transit_claims[uid] as Dictionary
		claim_amounts_copy = (claim_dict.get("amounts", {}) as Dictionary).duplicate(true)
		claim_unit = claim_dict.get("unit") as Unit
		claim_load = claim_dict.get("carry_load") as UnitCarryLoad
	return {
		"uid": uid,
		"has_pending": has_pending,
		"pending": pending_copy,
		"has_claim": has_claim,
		"claim_amounts": claim_amounts_copy,
		"claim_unit": claim_unit,
		"claim_load": claim_load,
		"revision": _transaction_revision,
		"mutated": false,
	}


func _apply_prepared_claim_silent(
	unit: Unit,
	carry_load: UnitCarryLoad,
	resource_id: StringName,
	amount: int,
	claim_plan: Dictionary,
	checkpoint: Dictionary
) -> bool:
	if not _is_preparing_or_transacting or not is_active():
		return false
	if unit == null or not is_instance_valid(unit) or carry_load == null or resource_id.is_empty() or amount <= 0:
		return false
	var uid: int = unit.get_instance_id()
	if int(claim_plan.get("unit_instance_id", -1)) != uid:
		return false
	if _read_transit_claim_for_unit_pure(uid) != (claim_plan.get("before_transit_claim", {}) as Dictionary):
		return false
	var accounting_headroom: int = maxi(
		0,
		get_required_amount(resource_id)
		- get_total_received_amount(resource_id)
		- get_reserved_in_piles_amount(resource_id)
		- _read_in_transit_amount_pure(resource_id)
	)
	if accounting_headroom < amount:
		return false

	checkpoint["mutated"] = true
	_pending_pickups.erase(uid)
	_ensure_transit_listener(unit, carry_load)
	var claim: Dictionary = _transit_claims[uid] as Dictionary
	var amounts: Dictionary = claim["amounts"] as Dictionary
	amounts[resource_id] = int(amounts.get(resource_id, 0)) + amount
	if _read_transit_claim_for_unit_pure(uid) != (claim_plan.get("after_transit_claim", {}) as Dictionary):
		return false
	_transaction_revision += 1
	return true


func _restore_claim_checkpoint_silent(checkpoint: Dictionary) -> void:
	if checkpoint.is_empty() or not bool(checkpoint.get("mutated", false)):
		return
	var uid: int = int(checkpoint.get("uid", -1))
	if uid <= 0:
		return
	if bool(checkpoint.get("has_pending", false)):
		_pending_pickups[uid] = (checkpoint["pending"] as Dictionary).duplicate(true)
	else:
		_pending_pickups.erase(uid)

	if bool(checkpoint.get("has_claim", false)):
		var claim_unit: Unit = checkpoint.get("claim_unit") as Unit
		var claim_load: UnitCarryLoad = checkpoint.get("claim_load") as UnitCarryLoad
		if claim_unit != null and is_instance_valid(claim_unit) and claim_load != null:
			_ensure_transit_listener(claim_unit, claim_load)
			var claim_dict: Dictionary = _transit_claims[uid] as Dictionary
			claim_dict["amounts"] = (checkpoint["claim_amounts"] as Dictionary).duplicate(true)
	else:
		if _transit_claims.has(uid):
			var cur_claim: Dictionary = _transit_claims[uid] as Dictionary
			var cl: UnitCarryLoad = cur_claim.get("carry_load") as UnitCarryLoad
			var cb: Variant = cur_claim.get("callback")
			if cl != null and cb is Callable and cl.load_changed.is_connected(cb as Callable):
				cl.load_changed.disconnect(cb as Callable)
			_transit_claims.erase(uid)
	checkpoint["mutated"] = false
	_transaction_revision += 1
