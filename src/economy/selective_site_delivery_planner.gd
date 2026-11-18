class_name SelectiveSiteDeliveryPlanner
extends RefCounted
## Accounting-only plan for transferring already attributed cargo into a site buffer.
## Explicit requests are exact. An empty request selects all eligible quantities.


static func prepare_selective_site_delivery(
	site: ConstructionSite, unit: Unit, operation_id: Variant, requested_amounts: Variant = {}
) -> Dictionary:
	return _prepare(site, unit, operation_id, requested_amounts, null)


static func _prepare_under_delivery_scope(
	scope: ReservedWithdrawalCoordinator.DeliveryScope, operation_id: StringName, requested_amounts: Dictionary
) -> Dictionary:
	if not ReservedWithdrawalCoordinator._owns_delivery_scope(scope):
		return _reject("busy", "coordinator")
	return _prepare(scope.site, scope.unit, operation_id, requested_amounts, scope)


static func _prepare(
	site: ConstructionSite, unit: Unit, operation_id: Variant, requested_amounts: Variant,
	scope: ReservedWithdrawalCoordinator.DeliveryScope
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _reject("wrong_thread", "thread")
	if not is_instance_valid(site) or not site.is_inside_tree() or site.is_queued_for_deletion() or not site.is_valid() or not site.is_active() or site.get_generation() <= 0:
		return _reject("site_not_active", "site")
	if not CarryProvenanceLedger._id(operation_id):
		return _reject("invalid_operation", "input")
	var op := StringName(operation_id)
	var parsed := _parse_request(requested_amounts)
	if not parsed.ok:
		return parsed
	var requested: Dictionary = parsed.amounts
	var world := site.get_world_3d()
	if world == null or not CarryProvenanceLedger._id(site.region_id):
		return _reject("invalid_domain", "site")
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _reject("invalid_unit", "unit")
	if unit.get_world_3d() != world:
		return _reject("unit_world_mismatch", "unit")
	var inventory := site.get_inventory()
	var storage := (inventory.get_storage_source() as GroundPileManager) if inventory != null else null
	if storage == null:
		return _reject("unsupported_storage_source", "storage")
	var load := unit.get_carry_load()
	if load == null or not load.is_provenance_enabled() or not CarryProvenanceLedger._id(load.get_provenance_unit_id()):
		return _reject("provenance_disabled", "carry_load")
	if scope == null:
		if site.is_transaction_busy() or inventory.is_transaction_busy() or load.is_transaction_busy() or storage.is_locked() or storage.is_batch_active():
			return _reject("busy", "participants")
		var domain := ReservedWithdrawalCoordinator.inspect_domain_for_preparation(site, storage, op)
		if not domain.ok:
			return domain
	elif not ReservedWithdrawalCoordinator._owns_delivery_scope(scope) or scope.site != site or scope.unit != unit or scope.load != load:
		return _reject("busy", "coordinator")
	if site._has_conflicting_unit_identity_pure(unit, load):
		return _reject("ambiguous_unit_identity", "unit")
	for peer: ConstructionSite in site._collect_known_other_sites_pure():
		if scope == null and peer.is_transaction_busy():
			return _reject("busy", "peer_site")
		if scope != null and (not scope.sites.has(peer) or not peer._is_preparing_or_transacting):
			return _reject("busy", "peer_site")

	var cargo := load.provenance_snapshot()
	var ledger := CarryProvenanceLedger.new()
	if not ledger.restore_transaction_state(cargo.ledger):
		return _reject("invalid_ledger", "carry_load")
	if not ledger.validate_aggregate(cargo.unit_id, cargo.amounts).ok:
		return _reject("unreconciled_cargo", "carry_load")
	if cargo.ledger.operations.has(op):
		return _reject("operation_conflict", "provenance_ledger")
	var weight := _measure_cargo(cargo.amounts, cargo.weights, storage)
	if not weight.ok:
		return weight

	var reconciled := site._verify_unit_claims_reconciled_with_provenance_pure(unit, load)
	if not reconciled.ok:
		return reconciled
	var accounts := _read_accounting(site)
	if not accounts.ok:
		return accounts
	for resource: StringName in requested:
		if not accounts.by_resource.has(resource):
			return _reject("resource_not_required", "request")

	var uid := unit.get_instance_id()
	var claim := site._read_transit_claim_for_unit_pure(uid)
	var projection := _project(site, cargo, ledger, op, requested, claim, accounts.by_resource)
	if not projection.ok:
		return projection

	return {
		"ok": true,
		"dry_run_only": true,
		"commit_supported": false,
		"physical_delivery_authorized": false,
		"validation_scope": "accounting_only",
		"operation_id": op,
		"requested_amounts": requested,
		"identity": {
			"site": site.get_instance_id(), "site_id": site.site_id, "generation": site.get_generation(),
			"reservation_id": site.reservation_id, "region_id": site.region_id, "world": world.get_instance_id(),
			"unit": uid, "unit_id": cargo.unit_id, "load": load.get_instance_id(),
			"inventory": inventory.get_instance_id(), "storage": storage.get_instance_id(),
		},
		"revisions": {
			"site": site.get_transaction_revision(), "load": load.get_transaction_revision(),
			"inventory": inventory.get_transaction_revision(), "storage": storage.get_transaction_revision(),
			"pile_ledger": storage.get_pile_ledger_revision(), "peer_claims": reconciled.peer_claim_revisions,
		},
		"before": {
			"cargo": cargo, "weight": weight.value, "capacity": load.get_effective_capacity(),
			"claim": claim, "accounting": accounts.by_resource,
		},
		"after": projection.after,
		"deliverable": projection.deliverable,
		"lot_debits": projection.lot_debits,
	}


static func validate_selective_site_delivery_plan(site: ConstructionSite, unit: Unit, plan: Variant) -> Dictionary:
	if not plan is Dictionary:
		return _reject("invalid_plan", "plan")
	if not (plan.get("ok") is bool and plan.ok and plan.get("dry_run_only") is bool and plan.dry_run_only):
		return _reject("invalid_plan", "plan")
	if not (plan.get("commit_supported") is bool and not plan.commit_supported
		and plan.get("physical_delivery_authorized") is bool and not plan.physical_delivery_authorized):
		return _reject("invalid_plan", "plan")
	if not (plan.get("operation_id") is StringName and plan.get("validation_scope") is String
		and plan.validation_scope == "accounting_only" and plan.get("lot_debits") is Array):
		return _reject("invalid_plan", "plan")
	for key: String in ["identity", "revisions", "requested_amounts", "before", "after", "deliverable"]:
		if not plan.get(key) is Dictionary:
			return _reject("invalid_plan", "plan")
	var fresh := prepare_selective_site_delivery(site, unit, plan.operation_id, plan.requested_amounts)
	var comparison := _compare_plan(fresh, plan)
	if not comparison.ok:
		return comparison
	return {"ok": true, "dry_run_only": true, "commit_supported": false,
		"physical_delivery_authorized": false, "validation_scope": "accounting_only"}


static func _compare_plan(fresh: Dictionary, plan: Dictionary) -> Dictionary:
	if not fresh.ok:
		return fresh
	if fresh.identity != plan.identity:
		return _reject("identity_mismatch", "plan")
	if fresh.revisions != plan.revisions:
		return _reject("stale_revision", "plan")
	if fresh != plan:
		return _reject("tampered_or_stale_plan", "plan")
	return {"ok": true}


static func _parse_request(input: Variant) -> Dictionary:
	if not input is Dictionary:
		return _reject("invalid_request", "request")
	var amounts: Dictionary = {}
	for key: Variant in input:
		if not CarryProvenanceLedger._id(key) or typeof(input[key]) != TYPE_INT or input[key] <= 0:
			return _reject("invalid_request", "request")
		var resource := StringName(key)
		if amounts.has(resource):
			return _reject("invalid_request", "request")
		amounts[resource] = input[key]
	return {"ok": true, "amounts": amounts}


static func _measure_cargo(amounts: Dictionary, weights: Dictionary, storage: GroundPileManager) -> Dictionary:
	var total: int = 0
	if amounts.size() != weights.size():
		return _reject("resource_or_weight_mismatch", "carry_load")
	for resource: Variant in amounts:
		if not CarryProvenanceLedger._id(resource) or typeof(amounts[resource]) != TYPE_INT or amounts[resource] <= 0:
			return _reject("unreconciled_cargo", "carry_load")
		var definition := storage.get_resource_definition_pure(StringName(resource))
		var weight: Variant = weights.get(resource)
		if definition == null or typeof(weight) != TYPE_INT or weight != definition.unit_weight:
			return _reject("resource_or_weight_mismatch", "carry_load")
		@warning_ignore("integer_division")
		if weight > (CarryProvenanceLedger.MAX_INT - total) / int(amounts[resource]):
			return _reject("weight_overflow", "carry_load")
		total += int(weight) * int(amounts[resource])
	return {"ok": true, "value": total}


static func _read_accounting(site: ConstructionSite) -> Dictionary:
	var required := site.get_required_amounts()
	var by_resource: Dictionary = {}
	var buffers := site.get_delivered_buffer_amounts()
	var incorporated := site.get_consumed_amounts()
	if buffers.size() != required.size() or incorporated.size() != required.size():
		return _reject("accounting_invariant_violated", "accounting")
	for resource: StringName in required:
		var need: int = required[resource]
		var buffer: Variant = buffers.get(resource)
		var consumed: Variant = incorporated.get(resource)
		var reserved := site.get_inventory().get_reservation_amount(site.reservation_id, resource)
		if typeof(buffer) != TYPE_INT or typeof(consumed) != TYPE_INT \
			or need <= 0 or buffer < 0 or buffer > need or consumed < 0 or consumed > need - buffer:
			return _reject("accounting_invariant_violated", "accounting")
		var room := need - int(buffer) - int(consumed)
		if reserved < 0 or reserved > room:
			return _reject("accounting_invariant_violated", "accounting")
		by_resource[resource] = {"required": need, "reserved": reserved, "transit": 0,
			"buffer": buffer, "consumed": consumed, "missing": room - reserved}

	for uid: Variant in site._transit_claims:
		var entry: Dictionary = site._transit_claims[uid]
		var holder: Unit = entry.get("unit") as Unit
		if not is_instance_valid(holder) or not holder.is_inside_tree() or holder.is_queued_for_deletion() or holder.get_world_3d() != site.get_world_3d() or holder.get_instance_id() != uid:
			return _reject("invalid_transit_claim", "claims")
		var load := holder.get_carry_load()
		if load == null or entry.get("carry_load") != load or not entry.get("amounts") is Dictionary:
			return _reject("invalid_transit_claim", "claims")
		var amounts: Dictionary = entry.amounts
		for resource: Variant in amounts:
			if not by_resource.has(resource) or typeof(amounts[resource]) != TYPE_INT or amounts[resource] <= 0 or amounts[resource] > load.get_amount(StringName(resource)):
				return _reject("invalid_transit_claim", "claims")
			var account: Dictionary = by_resource[resource]
			var quantity: int = amounts[resource]
			if quantity > int(account.missing):
				return _reject("accounting_invariant_violated", "accounting")
			account.transit += quantity
			account.missing -= quantity
	return {"ok": true, "by_resource": by_resource}


static func _project(
	site: ConstructionSite, cargo: Dictionary, ledger: CarryProvenanceLedger, operation: StringName,
	requested: Dictionary, claim: Dictionary, before: Dictionary
) -> Dictionary:
	var amounts: Dictionary = cargo.amounts.duplicate()
	var weights: Dictionary = cargo.weights.duplicate()
	var after_claim := claim.duplicate()
	var after_accounts := before.duplicate(true)
	var deliverable: Dictionary = {}
	var debits: Array[Dictionary] = []
	var resources: Array[StringName] = []
	resources.assign(before.keys() if requested.is_empty() else requested.keys())
	resources.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for resource: StringName in resources:
		var account: Dictionary = before[resource]
		var claimed: int = claim.get(resource, 0)
		var need := int(account.required) - int(account.buffer) - int(account.consumed)
		var other_transit := int(account.transit) - claimed
		var room := need - int(account.reserved) - other_transit
		# Reconciliation proves this worker's destination lots total exactly its claim.
		var maximum := mini(claimed, mini(need, mini(int(amounts.get(resource, 0)), room)))
		var count: int = requested.get(resource, maximum)
		if count > maximum:
			return _reject("requested_amount_exceeds_eligible", "request")
		if count <= 0:
			continue
		var definition: ResourceDefinition = site._resolve_resource_definition_pure(resource)
		if definition == null or definition.unit_weight != weights[resource]:
			return _reject("resource_or_weight_mismatch", "site")
		var lots := ledger.query(cargo.unit_id, resource, CarryProvenanceLedger.SITE_RESERVED, site.site_id)
		lots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.lot_id) < String(b.lot_id))
		var remaining := count
		for lot: Dictionary in lots:
			var take := mini(remaining, int(lot.quantity))
			# These IDs only identify steps in the detached ledger simulation.
			var base_id := "c3.1:%d:%s:%d" % [String(operation).length(), operation, debits.size()]
			var debit_op := StringName(base_id)
			var suffix := 0
			while ledger._operations.has(debit_op):
				suffix += 1
				debit_op = StringName("%s:%d" % [base_id, suffix])
			var result := ledger.withdraw(debit_op, lot.lot_id, take)
			if not result.ok or result.replayed:
				return _reject("lot_debit_conflict", "provenance_ledger")
			debits.append({"lot_id": lot.lot_id, "resource_id": resource, "before": lot.quantity,
				"delivered": take, "after": int(lot.quantity) - take, "operation_id": operation,
				"debit_operation_id": debit_op})
			remaining -= take
			if remaining == 0:
				break
		if remaining != 0:
			return _reject("unreconciled_site_claim", "claims")
		deliverable[resource] = count
		amounts[resource] -= count
		if amounts[resource] == 0:
			amounts.erase(resource)
			weights.erase(resource)
		after_claim[resource] -= count
		if after_claim[resource] == 0:
			after_claim.erase(resource)
		var updated: Dictionary = after_accounts[resource]
		updated.transit -= count
		updated.buffer += count
	if deliverable.is_empty():
		return _reject("no_eligible_delivery", "request")
	if not ledger.validate_aggregate(cargo.unit_id, amounts).ok:
		return _reject("unreconciled_projection", "carry_load")
	return {"ok": true, "deliverable": deliverable, "lot_debits": debits, "after": {
		"cargo": {"unit_id": cargo.unit_id, "amounts": amounts, "weights": weights, "ledger": ledger.snapshot_transaction_state()},
		"claim": after_claim, "accounting": after_accounts,
	}}


static func _reject(reason: String, dependency: String) -> Dictionary:
	return {"ok": false, "reason": reason, "dependency": dependency}
