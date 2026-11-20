class_name SiteCancellationTransaction
extends RefCounted
## B1.2 commits custody and reservation release. Recovery is a later operation.

enum FailureStage { NONE, RESERVATION, CARGO, SITE, RECORD }


static func prepare(site: ConstructionSite, operation: Variant, scope: ReservedWithdrawalCoordinator.CancellationScope = null) -> Dictionary:
	if not CarryProvenanceLedger._id(operation):
		return _reject("invalid_operation_id")
	if scope == null:
		var domain := ReservedWithdrawalCoordinator._inspect_site_mutation_preconditions_readonly(site, true)
		if not domain.ok:
			return domain
	elif not ReservedWithdrawalCoordinator._owns_cancellation_scope(scope) or scope.site != site or not site.is_active():
		return _reject("unauthorized_scope")
	var manager := site._construction_manager_ref.get_ref() as ConstructionManager if site._construction_manager_ref != null else null
	var world := site.get_world_3d()
	if not is_instance_valid(manager) or manager._sites_root != site.get_parent() or not manager._sites.has(site) or manager._region_id != site.region_id or manager._inventory != site.get_inventory():
		return _reject("site_not_registered")
	var uid := site.get_instance_id()
	if manager._creation_in_progress or manager._completion_in_progress or manager._queued_completions.has(uid) or manager._retry_timers.has(uid) or manager._busy_completion_timers.has(uid) or (manager._cancellation_in_progress and scope == null):
		return _reject("busy")
	if not CarryProvenanceLedger._id(site.site_id) or not CarryProvenanceLedger._id(site.reservation_id) or site.get_generation() <= 0 or site._work_progress_usec >= site._total_work_usec:
		return _reject("invalid_site_identity_or_work")
	var inv := site.get_inventory()
	var storage := inv.get_storage_source() as GroundPileManager
	if storage == null:
		return _reject("physical_storage_required")
	for node: Node in site.get_tree().get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		var other := node as ConstructionSite
		if not is_instance_valid(other) or other == site or not other.is_inside_tree():
			continue
		var same_domain: bool = other.get_world_3d() == world and other.region_id == site.region_id
		var other_inv := other.get_inventory()
		var shared_storage: bool = other_inv != null and other_inv.get_storage_source() == storage
		if (shared_storage and not same_domain) or (same_domain and other_inv != inv):
			return _reject("ambiguous_domain")
		if same_domain and (other.site_id == site.site_id or other.reservation_id == site.reservation_id):
			return _reject("ambiguous_site_identity")

	var cargo := _inspect_cargo(site, StringName(operation), scope != null)
	if not cargo.ok:
		return cargo
	var reserved := storage.get_reservation_amounts(site.reservation_id)
	if storage.has_reservation(site.reservation_id) != (not reserved.is_empty()):
		return _reject("reservation_amount_mismatch")
	for resource: Variant in reserved:
		var total: int = 0
		for entry: Dictionary in storage.get_reserved_pile_entries(site.reservation_id, resource):
			var pile_id: int = entry.pile_id
			var pile := storage.get_pile_by_id(pile_id)
			if not is_instance_valid(pile) or pile.resource_id != resource or pile.amount < storage._ledger.get_pile_reserved_amount(pile_id):
				return _reject("invalid_or_inconsistent_pile")
			total += int(entry.reserved_amount)
		if total != reserved[resource]:
			return _reject("reservation_amount_mismatch")
	var resources: Dictionary = {}
	var transit: Dictionary = cargo.totals
	for field: Dictionary in [reserved, transit, site._delivered_buffer, site._consumed_materials]:
		for resource: Variant in field:
			if not site._required_amounts.has(resource):
				return _reject("unknown_resource")
	for resource: Variant in site._required_amounts:
		var missing: int = site._required_amounts[resource]
		for quantity: Variant in [reserved.get(resource, 0), transit.get(resource, 0), site._delivered_buffer[resource], site._consumed_materials[resource]]:
			if typeof(quantity) != TYPE_INT or quantity < 0 or quantity > missing:
				return _reject("accounting_mismatch")
			missing -= quantity
		resources[resource] = {"required": site._required_amounts[resource], "reserved": reserved.get(resource, 0),
			"in_transit": transit.get(resource, 0), "buffer": site._delivered_buffer[resource],
			"incorporated": site._consumed_materials[resource], "missing": missing}
	var economics := ConstructionCancellationMath.evaluate_snapshot({"progress": site._work_progress_usec, "total_work": site._total_work_usec, "resources": resources})
	if not economics.ok:
		return economics
	return {"ok": true, "operation": StringName(operation), "manager": manager, "site": site,
		"site_id": site.site_id, "reservation_id": site.reservation_id, "generation": site.get_generation(),
		"region": site.region_id, "world": world, "inventory": inv, "storage": storage,
		"progress": site._work_progress_usec, "total_work": site._total_work_usec,
		"site_revision": site.get_transaction_revision(), "inventory_revision": inv.get_transaction_revision(),
		"storage_revision": storage.get_transaction_revision(), "ledger_revision": storage.get_pile_ledger_revision(),
		"reserved": reserved, "cargo": cargo.entries, "resources": resources, "economics": economics.resources}


static func _inspect_cargo(site: ConstructionSite, operation: StringName, under_guard: bool) -> Dictionary:
	var units: Dictionary = {}
	for node: Node in site.get_tree().get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
		var unit := node as Unit
		if is_instance_valid(unit) and unit.is_inside_tree() and unit.get_world_3d() == site.get_world_3d():
			units[unit.get_instance_id()] = unit
	for bucket: Dictionary in [site._transit_claims, site._assigned_workers, site._pending_pickups]:
		for key: Variant in bucket:
			var unit := bucket[key].get("unit") as Unit
			if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion() or unit.get_instance_id() != key or unit.get_world_3d() != site.get_world_3d():
				return _reject("missing_or_wrong_world_worker")
			units[key] = unit
	var keys := units.keys()
	keys.sort()
	var entries: Array[Dictionary] = []
	var totals: Dictionary = {}
	for uid: int in keys:
		var unit: Unit = units[uid]
		var load := unit.get_carry_load()
		var claim: Dictionary = site._transit_claims.get(uid, {})
		var assigned: bool = site._assigned_workers.has(uid) or site._pending_pickups.has(uid)
		var worker_order := unit.get_current_order() as ConstructOrder
		assigned = assigned or (worker_order != null and worker_order.site == site)
		if load == null or (not claim.is_empty() and claim.get("carry_load") != load):
			return _reject("carry_load_mismatch")
		if not claim.is_empty():
			var listener: Callable = claim.get("callback", Callable())
			if not listener.is_valid() or not load.load_changed.is_connected(listener):
				return _reject("unreconciled_transit_listener")
		var snapshot := load.provenance_snapshot()
		var lots: Dictionary = snapshot.get("ledger", {}).get("lots", {})
		var moves: Array[StringName] = []
		var amounts: Dictionary = {}
		var explicit_region: Variant = unit.get_meta(&"region_id", &"")
		if explicit_region == &"" or explicit_region == site.region_id or assigned or not claim.is_empty():
			for lot: Dictionary in lots.values():
				if lot.site_id != site.site_id or lot.origin != CarryProvenanceLedger.SITE_RESERVED:
					continue
				if lot.generation != site.get_generation() or unit.is_queued_for_deletion():
					return _reject("stale_cargo_identity")
				var qty: int = lot.quantity
				var resource: StringName = lot.resource_id
				if qty <= 0 or int(amounts.get(resource, 0)) > ConstructionCancellationMath.MAX_INT - qty or int(totals.get(resource, 0)) > ConstructionCancellationMath.MAX_INT - qty:
					return _reject("invalid_cargo_quantity")
				amounts[resource] = int(amounts.get(resource, 0)) + qty
				totals[resource] = int(totals.get(resource, 0)) + qty
				moves.append(lot.lot_id)
		if amounts != claim.get("amounts", {}):
			return _reject("unreconciled_transit_claim")
		if not assigned and claim.is_empty() and moves.is_empty():
			continue
		if explicit_region != &"" and explicit_region != site.region_id:
			return _reject("region_mismatch")
		if not under_guard and (load.is_transaction_busy() or load._coordinator_transaction_locked):
			return _reject("busy")
		if under_guard and (not load._provenance_busy or not load._coordinator_transaction_locked):
			return _reject("unlocked_carry_load")
		var identity := ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(site.get_world_3d(), site.region_id, unit, load, site.get_tree())
		if not identity.ok or not load.validate_provenance():
			return _reject("unreconciled_cargo_identity")
		var rewritten := {}
		if not moves.is_empty():
			var candidate := CarryProvenanceLedger.new()
			if not candidate.restore_transaction_state(snapshot.ledger):
				return _reject("invalid_ledger")
			moves.sort()
			for lot_id: StringName in moves:
				var reclass_op := StringName("d3/%d:%s/%s" % [String(operation).length(), operation, lot_id])
				var result := candidate.reclassify_lot(reclass_op, lot_id, CarryProvenanceLedger.CANCEL_TRANSIT, site.site_id, site.get_generation())
				if not result.ok or result.replayed:
					return _reject("lot_operation_conflict")
			rewritten = candidate.snapshot_transaction_state()
		for previous: Dictionary in entries:
			if previous.load == load:
				return _reject("shared_carry_load")
		entries.append({"unit": unit, "load": load, "assigned": assigned, "revision": load.get_transaction_revision(),
			"before": snapshot, "rewritten": rewritten, "lots": moves})
	return {"ok": true, "entries": entries, "totals": totals}


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func execute(
	site: ConstructionSite, operation: Variant, prepared: Dictionary = {},
	fail_at: FailureStage = FailureStage.NONE
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _reject("wrong_thread")
	if not is_instance_valid(site) or not site.is_inside_tree() or not CarryProvenanceLedger._id(operation):
		return _reject("invalid_site_or_operation")
	var op := StringName(operation)
	var world := site.get_world_3d()
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var previous_authority := domains.get(site.region_id) as ReservedWithdrawalCoordinator.RegionalAuthority
	if previous_authority != null and previous_authority.receipts.has(op):
		var stored: Dictionary = previous_authority.receipts[op]
		var saved: Dictionary = stored.get("receipt", {})
		if saved.get("kind") != ReservedWithdrawalCoordinator.RECEIPT_SITE_CANCELLATION or saved.get("site_instance_id") != site.get_instance_id() or saved.get("generation") != site.get_generation() or saved.get("site_id") != site.site_id:
			return _reject("operation_conflict")
		return {"ok": true, "replayed": true, "receipt": saved.duplicate(true)}
	var plan := prepare(site, op)
	if not plan.ok:
		return plan
	if not prepared.is_empty() and prepared != plan:
		return _reject("stale_plan")
	var manager: ConstructionManager = plan.manager
	var storage: GroundPileManager = plan.storage
	var site_key := StringName("%s:%d" % [plan.site_id, plan.generation])
	var cancel_id := StringName("cancel:%s" % site_key)
	if previous_authority != null and (previous_authority.cancellation_custodies.has(cancel_id) or previous_authority.cancellation_id_by_site_gen.has(site_key) or previous_authority.cancellation_operation_ids.has(op)):
		return _reject("duplicate_cancellation")
	var had_domains := world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META)
	var binding_world := storage._withdrawal_world
	var binding_region := storage._withdrawal_region
	var acquired := ReservedWithdrawalCoordinator._acquire_cancellation_scope_for_primitives(world, plan.region, plan.inventory,
		cancel_id, op, plan.site_id, plan.reservation_id, plan.generation, plan.reserved, plan.reserved.is_empty())
	if not acquired.ok:
		return acquired
	var scope: ReservedWithdrawalCoordinator.CancellationScope = acquired.scope
	scope.site = site
	for node: Node in site.get_tree().get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		var peer := node as ConstructionSite
		if is_instance_valid(peer) and peer.is_inside_tree() and peer.get_inventory() == plan.inventory:
			scope.sites.append(peer)
	scope.sites.sort_custom(func(a: ConstructionSite, b: ConstructionSite) -> bool: return a.get_instance_id() < b.get_instance_id())
	manager._cancellation_in_progress = true
	_set_participant_guards(scope, plan.cargo, true)
	var outcome := _apply(scope, plan, site_key, fail_at)
	var closed := ReservedWithdrawalCoordinator._release_cancellation_scope(scope)
	if not closed:
		return _reject("scope_finalization_failed")
	_set_participant_guards(scope, plan.cargo, false)
	manager._cancellation_in_progress = false
	if not outcome.ok and previous_authority == null:
		var live_domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
		live_domains.erase(plan.region)
		if not had_domains and live_domains.is_empty():
			world.remove_meta(ReservedWithdrawalCoordinator.DOMAIN_META)
		storage._withdrawal_world = binding_world
		storage._withdrawal_region = binding_region
	return outcome


static func _set_participant_guards(scope: ReservedWithdrawalCoordinator.CancellationScope, cargo: Array, locked: bool) -> void:
	for peer: ConstructionSite in scope.sites:
		peer._is_preparing_or_transacting = locked
		peer._suppress_coordinator_signal_echo = locked
	if is_instance_valid(scope.camp_zone):
		scope.camp_zone._coordinator_transaction_locked = locked
	for entry: Dictionary in cargo:
		var load: UnitCarryLoad = entry.load
		load._coordinator_transaction_locked = locked
		load._provenance_busy = locked


static func _apply(scope: ReservedWithdrawalCoordinator.CancellationScope, plan: Dictionary, site_key: StringName, fail_at: FailureStage) -> Dictionary:
	if not ReservedWithdrawalCoordinator._owns_cancellation_scope(scope) or not is_instance_valid(scope.site) or not scope.site._is_preparing_or_transacting:
		return _reject("unauthorized_scope")
	var fresh := prepare(scope.site, scope.operation_id, scope)
	if not fresh.ok or fresh != plan:
		return _reject("stale_plan")
	var storage := scope.storage
	var site := scope.site
	var authority := scope.authority
	var record := _make_record(scope, plan)
	var accounting := ReservedWithdrawalCoordinator.validate_custody_accounting_pure(record)
	if not accounting.ok:
		return accounting
	var release_plan := storage._prepare_cancel_release_under_guard(scope.reservation_id, plan.reserved, scope)
	if not release_plan.ok:
		return release_plan
	# Materialize detached ledgers before making the first mutation.
	var changes: Array[Dictionary] = []
	for entry: Dictionary in plan.cargo:
		if entry.rewritten.is_empty():
			continue
		var load: UnitCarryLoad = entry.load
		var candidate := CarryProvenanceLedger.new()
		if not candidate.restore_transaction_state(entry.rewritten) or not candidate.validate_aggregate(load.get_provenance_unit_id(), entry.before.amounts).ok:
			return _reject("invalid_prepared_ledger")
		changes.append({"load": load, "before": load._provenance, "after": candidate})
	var checkpoint := {
		"buffer": site._delivered_buffer, "consumed": site._consumed_materials, "claims": site._transit_claims,
		"pickups": site._pending_pickups, "workers": site._assigned_workers, "order_ids": site._worker_order_ids,
		"slots": site._builder_slot_positions,
	}
	var released := storage._apply_prepared_cancel_release_silent(release_plan, scope)
	if not released.ok:
		return released
	if fail_at == FailureStage.RESERVATION:
		return _reject("injected_precommit_failure")
	for change: Dictionary in changes:
		var load: UnitCarryLoad = change.load
		load._provenance = change.after
		load._transaction_revision += 1
	if fail_at == FailureStage.CARGO:
		_restore_cargo(changes)
		return _reject("injected_precommit_failure")
	site._site_state = ConstructionSite.SiteState.CANCELLED
	site._cancellation_custody = record
	site._delivered_buffer = {}
	site._consumed_materials = {}
	site._transit_claims = {}
	site._pending_pickups = {}
	site._assigned_workers = {}
	site._worker_order_ids = []
	site._builder_slot_positions = {}
	site._transaction_revision += 1
	if fail_at == FailureStage.SITE:
		_restore_site(site, checkpoint)
		_restore_cargo(changes)
		return _reject("injected_precommit_failure")

	var receipt := {"kind": ReservedWithdrawalCoordinator.RECEIPT_SITE_CANCELLATION,
		"cancel_id": scope.cancel_id, "operation_id": scope.operation_id, "site_id": scope.site_id,
		"generation": scope.generation, "region_id": scope.region_id, "site_instance_id": site.get_instance_id(),
		"custody": record.to_snapshot_dict()}
	authority.cancellation_custodies[scope.cancel_id] = record
	authority.cancellation_id_by_site_gen[site_key] = scope.cancel_id
	authority.cancellation_operation_ids[scope.operation_id] = scope.cancel_id
	authority.receipts[scope.operation_id] = {"receipt": receipt, "site": weakref(site)}
	_set_claim_listeners(checkpoint.claims, false)
	# All participants are final under the guard. The backend seals before its first callback.
	if fail_at == FailureStage.RECORD or not ReservedWithdrawalCoordinator._authorize_cancellation_release_commit(scope) or not storage._publish_cancel_release_committed(scope):
		authority.receipts.erase(scope.operation_id)
		authority.cancellation_operation_ids.erase(scope.operation_id)
		authority.cancellation_id_by_site_gen.erase(site_key)
		authority.cancellation_custodies.erase(scope.cancel_id)
		_restore_site(site, checkpoint)
		_restore_cargo(changes)
		_set_claim_listeners(checkpoint.claims, true)
		return _reject("injected_precommit_failure" if fail_at == FailureStage.RECORD else "commit_validation_failed")

	scope._publishing = true
	if not record.requires_local_footprint_occupation():
		site._site_collision_shape.set_deferred("disabled", true)
		site._visual_root.hide()
	for change: Dictionary in changes:
		(change.load as UnitCarryLoad).load_changed.emit()
	site.buffer_changed.emit(site)
	site.workers_changed.emit(site)
	site.state_changed.emit(site)
	for peer: ConstructionSite in scope.sites:
		if peer != site:
			peer.state_changed.emit(peer)
	scope._publishing = false
	return {"ok": true, "replayed": false, "receipt": receipt.duplicate(true)}


static func _set_claim_listeners(claims: Dictionary, connected: bool) -> void:
	for claim: Dictionary in claims.values():
		var load: UnitCarryLoad = claim.get("carry_load")
		var cb: Callable = claim.get("callback", Callable())
		if load == null or not cb.is_valid() or load.load_changed.is_connected(cb) == connected:
			continue
		if connected:
			load.load_changed.connect(cb)
		else:
			load.load_changed.disconnect(cb)


static func _restore_site(site: ConstructionSite, checkpoint: Dictionary) -> void:
	site._site_state = ConstructionSite.SiteState.ACTIVE
	site._cancellation_custody = null
	site._delivered_buffer = checkpoint.buffer
	site._consumed_materials = checkpoint.consumed
	site._transit_claims = checkpoint.claims
	site._pending_pickups = checkpoint.pickups
	site._assigned_workers = checkpoint.workers
	site._worker_order_ids = checkpoint.order_ids
	site._builder_slot_positions = checkpoint.slots
	site._transaction_revision += 1


static func _restore_cargo(changes: Array[Dictionary]) -> void:
	for change: Dictionary in changes:
		var load: UnitCarryLoad = change.load
		load._provenance = change.before
		load._transaction_revision += 1


static func _make_record(scope: ReservedWithdrawalCoordinator.CancellationScope, plan: Dictionary) -> ReservedWithdrawalCoordinator.CancellationCustodyRecord:
	var record := ReservedWithdrawalCoordinator.CancellationCustodyRecord.new()
	record.cancel_id = scope.cancel_id
	record.operation_id = scope.operation_id
	record.site_id = scope.site_id
	record.reservation_id = scope.reservation_id
	record.generation = scope.generation
	record.region_id = scope.region_id
	record.world_instance_id = scope.world.get_instance_id()
	record.work_progress_usec = plan.progress
	record.total_work_usec = plan.total_work
	record.required_amounts = scope.site._required_amounts.duplicate()
	for entry: Dictionary in plan.cargo:
		var unit_id: StringName = entry.before.unit_id
		if entry.assigned:
			record.assigned_unit_ids.append(unit_id)
		if not entry.lots.is_empty():
			record.transit_lots_by_unit[unit_id] = entry.lots.duplicate()
	for resource: Variant in plan.economics:
		var value: Dictionary = plan.economics[resource]
		record.released_on_piles[resource] = value.reservation_release
		record.local_buffer_remaining[resource] = value.buffer
		record.local_incorporated_remaining[resource] = value.incorporated_recovered
		record.in_transit_remaining[resource] = value.in_transit
		record.demolition_loss[resource] = value.demolition_loss
		record.missing_deficit[resource] = value.missing
	if not record.has_unsettled_custody():
		var sequence := ReservedWithdrawalCoordinator.plan_custody_state_sequence_pure(false)
		if sequence.ok:
			record.state = sequence.states.back()
	return record
