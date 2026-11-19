class_name SelectiveSiteDeliveryCoordinator
extends RefCounted
## Explicit delivery of attributed cargo through the construction transfer session.

const Planner = preload("res://src/economy/selective_site_delivery_planner.gd")
const DeliveryScope = ReservedWithdrawalCoordinator.DeliveryScope
const RegionalAuthority = ReservedWithdrawalCoordinator.RegionalAuthority
const RECEIPT_KIND := ReservedWithdrawalCoordinator.RECEIPT_DELIVERY

# Test-only, synchronous fault injection. The hook receives the stage, no mutable plan.
var _fault_at: Callable
var _domain := ReservedWithdrawalCoordinator.new()


func execute_selective_site_delivery(
	site: ConstructionSite, unit: Unit, operation_id: Variant, requested_amounts: Variant = {}
) -> Dictionary:
	return _execute(site, unit, operation_id, requested_amounts, {})


func commit_prepared_selective_delivery(site: ConstructionSite, unit: Unit, plan: Variant) -> Dictionary:
	if not plan is Dictionary or not plan.get("operation_id") is StringName or not plan.get("requested_amounts") is Dictionary:
		return _failure("invalid_plan", "preparation")
	return _execute(site, unit, plan.operation_id, plan.requested_amounts, plan)


func get_receipt(operation_id: Variant) -> Dictionary:
	if not CarryProvenanceLedger._id(operation_id):
		return {}
	var authority := _domain._last_authority()
	if authority == null:
		return {}
	return _delivery_receipt(authority, StringName(operation_id)).duplicate(true)


func get_receipt_in_domain(world: World3D, region_id: Variant, operation_id: Variant) -> Dictionary:
	var authority := ReservedWithdrawalCoordinator._receipt_authority_in_domain(world, region_id, operation_id)
	if authority == null:
		return {}
	var receipt := _delivery_receipt(authority, StringName(operation_id))
	if receipt.is_empty() or receipt.identity.world != world.get_instance_id() or receipt.identity.region_id != StringName(region_id):
		return {}
	return receipt.duplicate(true)


func _execute(
	site: ConstructionSite, unit: Unit, operation_id: Variant, requested_amounts: Variant, plan: Dictionary
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _failure("wrong_thread", "thread")
	if not CarryProvenanceLedger._id(operation_id):
		return _failure("invalid_operation", "preparation")
	var parsed := Planner._parse_request(requested_amounts)
	if not parsed.ok:
		return _failure(parsed.reason, "preparation")
	if not is_instance_valid(site) or not site.is_inside_tree() or site.is_queued_for_deletion() or not site.is_valid():
		return _failure("invalid_site", "authorization")
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _failure("invalid_unit", "authorization")
	var world := site.get_world_3d()
	if world == null or unit.get_world_3d() != world:
		return _failure("unit_world_mismatch", "authorization")
	var inventory := site.get_inventory()
	var storage := (inventory.get_storage_source() as GroundPileManager) if inventory != null else null
	if storage == null or not CarryProvenanceLedger._id(site.region_id):
		return _failure("invalid_domain", "authorization")
	var authority := _domain._resolve_authority(site, world, storage)
	if authority == null:
		return _failure("ambiguous_domain", "authorization")
	if authority.is_executing:
		return _failure("busy", "coordinator")

	var op := StringName(operation_id)
	var load := unit.get_carry_load()
	var requested: Dictionary = parsed.amounts
	if authority.receipts.has(op):
		return _replay(authority, op, site, unit, load, requested, plan)
	if load == null or not load.is_provenance_enabled():
		return _failure("provenance_disabled", "preparation")
	var scope := DeliveryScope.new()
	scope.site = site
	scope.unit = unit
	scope.load = load
	scope.inventory = inventory
	scope.storage = storage
	scope.sites = site._collect_known_other_sites_pure()
	scope.sites.append(site)
	scope.sites.sort_custom(func(left: ConstructionSite, right: ConstructionSite) -> bool:
		if left.site_id == right.site_id:
			return left.get_instance_id() < right.get_instance_id()
		return String(left.site_id) < String(right.site_id))
	if not _acquire(authority, scope):
		return _failure("busy", "participants")

	var result := _commit_under_guards(authority, scope, op, requested, plan)
	_release(authority, scope)
	return result


func _commit_under_guards(
	authority: RegionalAuthority, scope: DeliveryScope, op: StringName, requested: Dictionary, plan: Dictionary
) -> Dictionary:
	var fresh := Planner._prepare_under_delivery_scope(scope, op, requested)
	if not plan.is_empty():
		var comparison := Planner._compare_plan(fresh, plan)
		if not comparison.ok:
			return _failure(comparison.reason, "preparation")
	if not fresh.ok:
		return _failure(fresh.reason, "preparation")
	var reason := _check_authorization(scope)
	if not reason.is_empty():
		return _failure(reason, "authorization")

	var site := scope.site
	var load := scope.load
	var uid := scope.unit.get_instance_id()
	var claim: Dictionary = site._transit_claims[uid]
	var listener: Callable = claim.callback
	if not load.load_changed.is_connected(listener):
		return _failure("transit_listener_missing", "preparation")

	var debited_ledger := _prepare_commit_debits(authority, fresh)
	if debited_ledger == null:
		return _failure("debit_preparation_failed", "preparation")
	# Bind prepared replays to the exact accepted payload, including serialization order.
	var plan_digest := _plan_digest(fresh if plan.is_empty() else plan)
	var checkpoint := {
		# Only the detached candidate ledger is debited. Keep the exact live
		# ledger and cargo values so restoration needs no allocations or replay.
		"ledger": load._provenance, "amounts": load._amounts, "weights": load._unit_weights,
		"debited_ledger": debited_ledger.snapshot_transaction_state(),
		"claim": claim, "buffer": site._delivered_buffer.duplicate(),
		"consumed": site.get_consumed_amounts(), "progress": site._work_progress_usec,
		"site_state": site.get_site_state(), "substate": site._assembly_substate,
		"starved": site._starved_resources.duplicate(), "was_full": site._was_fully_supplied,
		"supply_rebalanced": site._supply_rebalance_completed,
	}
	if _aborted("before_ledger_debit"):
		return _failure("aborted_before_ledger_debit", "transaction")
	if _fault_at.is_valid():
		reason = _check_authorization(scope)
		if not reason.is_empty():
			return _failure(reason, "authorization")

	reason = _apply_silent(scope, uid, fresh, debited_ledger, checkpoint)
	if not reason.is_empty():
		_restore_silent(scope, uid, checkpoint)
		return _failure(reason, "transaction")

	# No callbacks intervene between final validation and commit. Leave the
	# connection in its original position on every pre-commit rollback.
	if fresh.after.claim.is_empty():
		load.load_changed.disconnect(listener)
	site._transaction_revision += 1
	load._transaction_revision += 1
	var receipt := {
		"kind": RECEIPT_KIND, "operation_id": op,
		"identity": fresh.identity, "requested_amounts": requested.duplicate(),
		"delivered_amounts": fresh.deliverable, "plan_digest": plan_digest,
	}
	authority.receipts[op] = {
		"receipt": receipt, "site": weakref(site), "unit": weakref(scope.unit), "load": weakref(load),
	}
	_publish(scope, site._was_fully_supplied and not checkpoint.was_full)
	return _success(receipt, false)


static func _check_authorization(scope: DeliveryScope) -> String:
	var site := scope.site
	var unit := scope.unit
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return "invalid_unit"
	if not is_instance_valid(site) or not site.is_inside_tree() or site.is_queued_for_deletion() or not site.is_active():
		return "site_not_active"
	if site.get_world_3d() != unit.get_world_3d() or unit.get_carry_load() != scope.load:
		return "participant_mismatch"
	var worker: Dictionary = site._assigned_workers.get(unit.get_instance_id(), {})
	if worker.get("unit") != unit:
		return "worker_not_registered"
	var role: int = worker.get("role", ConstructionSite.WorkerRole.UNASSIGNED)
	if role != ConstructionSite.WorkerRole.TRANSPORTER and role != ConstructionSite.WorkerRole.SOLO_SUPPLIER:
		return "worker_role_not_eligible"
	var order := unit.get_current_order() as ConstructOrder
	if order == null or not order.is_active() or order.site != site or worker.get("order") != order:
		return "worker_order_not_eligible"
	if not BuildSlotPlanner.is_unit_in_site_dropoff_range(
		unit.global_position, site, ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE, site.get_world_3d()
	):
		return "out_of_site_dropoff_range"
	return ""


static func _prepare_commit_debits(authority: RegionalAuthority, plan: Dictionary) -> CarryProvenanceLedger:
	var candidate := CarryProvenanceLedger.new()
	if not candidate.restore_transaction_state(plan.before.cargo.ledger):
		return null
	var op: StringName = plan.operation_id
	for index: int in range(plan.lot_debits.size()):
		var debit: Dictionary = plan.lot_debits[index]
		var base_id := "c3.2:%d:%s:%d" % [String(op).length(), op, index]
		var debit_id := StringName(base_id)
		var suffix := 0
		# Check the actual ledger and the regional operation namespace. Prefixes
		# are deterministic candidates, not guarantees of uniqueness.
		while candidate._operations.has(debit_id) or authority.receipts.has(debit_id) or debit_id == op:
			suffix += 1
			debit_id = StringName("%s:%d" % [base_id, suffix])
		var applied := candidate.withdraw(debit_id, debit.lot_id, debit.delivered)
		if not applied.ok or applied.replayed:
			return null
	var projected: Dictionary = plan.after.cargo.ledger
	if candidate.snapshot() != projected.lots or candidate._used_lots != projected.used_lots:
		return null
	if not candidate.validate_aggregate(plan.identity.unit_id, plan.after.cargo.amounts).ok:
		return null
	return candidate


func _apply_silent(
	scope: DeliveryScope, uid: int, plan: Dictionary, ledger: CarryProvenanceLedger, checkpoint: Dictionary
) -> String:
	if not ReservedWithdrawalCoordinator._owns_delivery_scope(scope):
		return "busy"
	var site := scope.site
	var load := scope.load
	load._provenance = ledger
	if _aborted("after_ledger_debit"):
		return "aborted_after_ledger_debit"
	load._amounts = plan.after.cargo.amounts.duplicate()
	load._unit_weights = plan.after.cargo.weights.duplicate()
	if _aborted("after_carry_deduction"):
		return "aborted_after_carry_deduction"

	var claim: Dictionary = checkpoint.claim
	if plan.after.claim.is_empty():
		site._transit_claims.erase(uid)
	else:
		var remaining := claim.duplicate()
		remaining.amounts = plan.after.claim.duplicate()
		site._transit_claims[uid] = remaining
	if _aborted("after_claim_deduction"):
		return "aborted_after_claim_deduction"

	for resource: StringName in plan.deliverable:
		site._delivered_buffer[resource] = plan.after.accounting[resource].buffer
	site._refresh_assembly_substate()
	site._was_fully_supplied = site.is_fully_supplied()
	if _aborted("after_buffer_credit"):
		return "aborted_after_buffer_credit"
	if _aborted("during_final_invariants"):
		return "aborted_during_final_invariants"
	if not _verify_final(scope, uid, plan, checkpoint):
		return "invariant_violation_aborted"
	return ""


static func _verify_final(
	scope: DeliveryScope, uid: int, plan: Dictionary, checkpoint: Dictionary
) -> bool:
	var site := scope.site
	var load := scope.load
	var accounts := Planner._read_accounting(site)
	if not accounts.ok or accounts.by_resource != plan.after.accounting:
		return false
	if site._read_transit_claim_for_unit_pure(uid) != plan.after.claim:
		return false
	if not load.load_changed.is_connected(checkpoint.claim.callback) or site._was_fully_supplied != site.is_fully_supplied():
		return false
	if site.get_consumed_amounts() != checkpoint.consumed or site._work_progress_usec != checkpoint.progress \
		or site.get_site_state() != checkpoint.site_state or site._supply_rebalance_completed != checkpoint.supply_rebalanced:
		return false
	var cargo := load.provenance_snapshot()
	if cargo.ledger != checkpoint.debited_ledger or cargo.amounts != plan.after.cargo.amounts \
		or cargo.weights != plan.after.cargo.weights or not load.validate_provenance():
		return false
	var measured := Planner._measure_cargo(cargo.amounts, cargo.weights, scope.storage)
	if not measured.ok or load.get_effective_capacity() != plan.before.capacity or load.get_current_weight() != measured.value:
		return false
	if scope.inventory.get_transaction_revision() != plan.revisions.inventory \
		or scope.storage.get_transaction_revision() != plan.revisions.storage \
		or scope.storage.get_pile_ledger_revision() != plan.revisions.pile_ledger:
		return false
	var reconciled := site._verify_unit_claims_reconciled_with_provenance_pure(scope.unit, load)
	return reconciled.ok and reconciled.peer_claim_revisions == plan.revisions.peer_claims


static func _restore_silent(scope: DeliveryScope, uid: int, checkpoint: Dictionary) -> void:
	var site := scope.site
	var load := scope.load
	var claim: Dictionary = checkpoint.claim
	site._delivered_buffer = checkpoint.buffer
	site._assembly_substate = checkpoint.substate
	site._starved_resources = checkpoint.starved
	site._was_fully_supplied = checkpoint.was_full
	site._transit_claims[uid] = claim
	load._amounts = checkpoint.amounts
	load._unit_weights = checkpoint.weights
	load._provenance = checkpoint.ledger
	# Keep revisions monotonic after an applied stage, including after rollback.
	site._transaction_revision += 1
	load._transaction_revision += 1


static func _acquire(authority: RegionalAuthority, scope: DeliveryScope) -> bool:
	if authority.is_executing or scope.inventory.is_transaction_busy() or scope.storage.is_locked() \
		or scope.storage.is_batch_active() or scope.load.is_transaction_busy():
		return false
	for site: ConstructionSite in scope.sites:
		if site.is_transaction_busy():
			return false
	authority.is_executing = true
	authority.active_delivery = scope
	for site: ConstructionSite in scope.sites:
		site._is_preparing_or_transacting = true
	scope.inventory._is_delivering = true
	scope.storage._is_preparing_withdrawal = true
	scope.load._provenance_busy = true
	scope.load._coordinator_transaction_locked = true
	return true


static func _release(authority: RegionalAuthority, scope: DeliveryScope) -> void:
	scope.load._coordinator_transaction_locked = false
	scope.load._provenance_busy = false
	scope.storage._is_preparing_withdrawal = false
	scope.inventory._is_delivering = false
	for index: int in range(scope.sites.size() - 1, -1, -1):
		var site := scope.sites[index]
		if is_instance_valid(site):
			site._is_preparing_or_transacting = false
	authority.active_delivery = null
	authority.is_executing = false


static func _publish(scope: DeliveryScope, supply_completed: bool) -> void:
	var echo_flags: Dictionary = {}
	for site: ConstructionSite in scope.sites:
		echo_flags[site.get_instance_id()] = site._suppress_coordinator_signal_echo
		site._suppress_coordinator_signal_echo = true
	var target := scope.site
	scope.load.load_changed.emit()
	if is_instance_valid(target):
		target.buffer_changed.emit(target)
	if is_instance_valid(target):
		target.state_changed.emit(target)
	if supply_completed and is_instance_valid(target):
		target.supply_completed.emit(target)
	for site: ConstructionSite in scope.sites:
		if is_instance_valid(site):
			site._suppress_coordinator_signal_echo = echo_flags[site.get_instance_id()]


static func _replay(
	authority: RegionalAuthority, op: StringName, site: ConstructionSite, unit: Unit, load: UnitCarryLoad,
	requested: Dictionary, plan: Dictionary
) -> Dictionary:
	var receipt := _delivery_receipt(authority, op)
	if receipt.is_empty() or load == null:
		return _failure("operation_conflict", "receipt")
	var record: Dictionary = authority.receipts[op]
	var identity := {
		"site": site.get_instance_id(), "site_id": site.site_id, "generation": site.get_generation(),
		"reservation_id": site.reservation_id, "region_id": site.region_id, "world": site.get_world_3d().get_instance_id(),
		"unit": unit.get_instance_id(), "unit_id": load.get_provenance_unit_id(), "load": load.get_instance_id(),
		"inventory": site.get_inventory().get_instance_id(), "storage": site.get_inventory().get_storage_source().get_instance_id(),
	}
	if record.site.get_ref() != site or record.unit.get_ref() != unit or record.load.get_ref() != load \
		or receipt.identity != identity or receipt.requested_amounts != requested:
		return _failure("operation_conflict", "receipt")
	if not plan.is_empty() and _plan_digest(plan) != receipt.plan_digest:
		return _failure("operation_conflict", "receipt")
	return _success(receipt, true)


static func _delivery_receipt(authority: RegionalAuthority, op: StringName) -> Dictionary:
	var receipt := ReservedWithdrawalCoordinator._read_receipt(authority.receipts.get(op), op, RECEIPT_KIND)
	if receipt.size() != 6 or not receipt.get("identity") is Dictionary or not receipt.get("plan_digest") is String:
		return {}
	var identity: Dictionary = receipt.identity
	if identity.size() != 11 or receipt.plan_digest.length() != 64 or not receipt.plan_digest.is_valid_hex_number(false):
		return {}
	for key: String in ["site_id", "reservation_id", "region_id", "unit_id"]:
		if typeof(identity.get(key)) != TYPE_STRING_NAME or not CarryProvenanceLedger._id(identity[key]):
			return {}
	for key: String in ["site", "world", "unit", "load", "inventory", "storage", "generation"]:
		if typeof(identity.get(key)) != TYPE_INT or identity[key] == 0:
			return {}
	if identity.generation < 0:
		return {}
	var requested := Planner._parse_request(receipt.get("requested_amounts"))
	var delivered := Planner._parse_request(receipt.get("delivered_amounts"))
	if not requested.ok or not delivered.ok or delivered.amounts.is_empty():
		return {}
	if receipt.requested_amounts != requested.amounts or receipt.delivered_amounts != delivered.amounts:
		return {}
	if not requested.amounts.is_empty() and requested.amounts != delivered.amounts:
		return {}
	var total: int = 0
	for quantity: int in delivered.amounts.values():
		if quantity > CarryProvenanceLedger.MAX_INT - total:
			return {}
		total += quantity
	return receipt


static func _plan_digest(plan: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(plan))
	return context.finish().hex_encode()


func _aborted(stage: String) -> bool:
	return _fault_at.is_valid() and _fault_at.call(stage) == true


static func _success(receipt: Dictionary, replayed: bool) -> Dictionary:
	var units: int = 0
	for quantity: int in receipt.delivered_amounts.values():
		units += quantity
	return {"ok": true, "replayed": replayed, "delivered_now": 0 if replayed else units,
		"delivered_amounts": receipt.delivered_amounts.duplicate(), "receipt": receipt.duplicate(true)}


static func _failure(reason: String, dependency: String) -> Dictionary:
	return {"ok": false, "reason": reason, "dependency": dependency, "replayed": false, "delivered_now": 0}
