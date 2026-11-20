class_name CancellationRecoveryTransaction
extends RefCounted
## Internal B1.3 primitives. No order dispatch or gameplay entry point.
## Uses the existing regional/camp participant lock order for both A->H and H->E.

const RECOVERY_KIND := &"cancellation_recovery"
const CANCEL_ORIGINS := [CarryProvenanceLedger.CANCEL_TRANSIT, CarryProvenanceLedger.CANCEL_BUFFER, CarryProvenanceLedger.CANCEL_INCORPORATED]
const MUTABLE_FIELDS := ["local_buffer_remaining", "local_incorporated_remaining", "in_transit_remaining", "delivered_to_camp", "transit_lots_by_unit", "state", "diagnostic_reason"]


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _authority(world: World3D, region: StringName) -> ReservedWithdrawalCoordinator.RegionalAuthority:
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	return domains.get(region) as ReservedWithdrawalCoordinator.RegionalAuthority


static func _record(world: World3D, region: StringName, cancel_id: StringName) -> ReservedWithdrawalCoordinator.CancellationCustodyRecord:
	var authority := _authority(world, region)
	return authority.cancellation_custodies.get(cancel_id) as ReservedWithdrawalCoordinator.CancellationCustodyRecord if authority != null else null


## Reconcile all physical cancellation lots, including units with missing assignments.
static func validate_transit(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord, unit: Unit, storage: GroundPileManager) -> bool:
	if record == null or record.world_instance_id != unit.get_world_3d().get_instance_id() or record.region_id != storage._withdrawal_region or not ReservedWithdrawalCoordinator.validate_custody_accounting_pure(record).ok:
		return false
	var authority := _authority(unit.get_world_3d(), record.region_id)
	var key := StringName("%s:%d" % [record.site_id, record.generation])
	if authority == null or authority.cancellation_id_by_site_gen.get(key) != record.cancel_id or authority.cancellation_custodies.get(record.cancel_id) != record or not record.anchor_position.is_finite() or not record.footprint_size.is_finite() or record.footprint_size.x <= 0 or record.footprint_size.y <= 0:
		return false
	for resource: StringName in record.required_amounts:
		var definition := storage.get_resource_definition_pure(resource)
		if definition == null or not definition.is_valid() or definition.unit_weight != record.resource_weights.get(resource):
			return false
	var totals: Dictionary = {}
	var links: Dictionary = {}
	for node: Node in unit.get_tree().get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
		var peer := node as Unit
		if not is_instance_valid(peer) or not peer.is_inside_tree() or peer.get_world_3d() != unit.get_world_3d():
			continue
		var load := peer.get_carry_load()
		var snapshot := load.provenance_snapshot()
		var found: Array[StringName] = []
		for lot: Dictionary in snapshot.get("ledger", {}).get("lots", {}).values():
			if lot.site_id != record.site_id or not CANCEL_ORIGINS.has(lot.origin):
				continue
			if lot.generation != record.generation or peer.is_queued_for_deletion() or not load.validate_provenance():
				return false
			if not ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(peer.get_world_3d(), record.region_id, peer, load, peer.get_tree()).ok or int(snapshot.weights.get(lot.resource_id, 0)) != int(record.resource_weights.get(lot.resource_id, -1)):
				return false
			totals[lot.resource_id] = int(totals.get(lot.resource_id, 0)) + int(lot.quantity)
			found.append(lot.lot_id)
		if not found.is_empty():
			found.sort()
			var uid := load.get_provenance_unit_id()
			if links.has(uid):
				return false
			links[uid] = found
	if links.size() != record.transit_lots_by_unit.size():
		return false
	for uid: Variant in links:
		var expected: Array = record.transit_lots_by_unit.get(uid, []).duplicate()
		expected.sort()
		if links[uid] != expected:
			return false
	for resource: Variant in record.required_amounts:
		if int(totals.get(resource, 0)) != int(record.in_transit_remaining.get(resource, 0)):
			return false
	return true


static func classify_lot(unit: Unit, storage: GroundPileManager, lot: Dictionary) -> Dictionary:
	var region := storage._withdrawal_region
	var authority := _authority(unit.get_world_3d(), region)
	var key := StringName("%s:%d" % [lot.site_id, lot.generation])
	var cancel_id: StringName = authority.cancellation_id_by_site_gen.get(key, &"") if authority != null else &""
	var record := _record(unit.get_world_3d(), region, cancel_id)
	if record == null or record.state == ConstructionCancellationMath.State.SETTLED or not validate_transit(record, unit, storage):
		return _reject("unreconciled_cancellation_custody")
	return {"ok": true, "record": record, "snapshot": record.to_snapshot_dict()}


static func _physical_pickup(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord, unit: Unit, nav: WorldNavigation) -> bool:
	if not is_instance_valid(nav) or nav.get_world_3d() != unit.get_world_3d() or not nav.is_navigation_ready():
		return false
	if unit.get_movement().get_world_navigation() != nav or not unit.global_position.is_finite():
		return false
	var pos := unit.global_position
	var rect := Rect2(Vector2(record.anchor_position.x, record.anchor_position.z) - record.footprint_size * 0.5, record.footprint_size)
	if rect.has_point(Vector2(pos.x, pos.z)) or absf(pos.y - record.anchor_position.y) > BuildSlotPlanner.HEIGHT_TOLERANCE:
		return false
	var edge := Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.z, rect.position.y, rect.end.y))
	var delta := Vector2(pos.x, pos.z) - edge
	if delta.length() > ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE:
		return false
	var map := nav.get_navigation_map()
	if not NavigationServer3D.map_get_closest_point_owner(map, pos).is_valid() or NavigationServer3D.map_get_closest_point(map, pos).distance_to(pos) > BuildSlotPlanner.NAV_SURFACE_Y_TOLERANCE:
		return false
	# Stop outside the occupied rectangle, as in physical site perimeter access.
	var approach := Vector3(edge.x, record.anchor_position.y, edge.y) + Vector3(delta.normalized().x, 0, delta.normalized().y) * 0.05
	return BuildSlotPlanner.has_clear_physical_access(pos, approach, unit.get_world_3d())


static func prepare(cancel_id: Variant, unit: Unit, requests: Variant, operation: Variant, region: StringName, under_guard: bool = false) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not CarryProvenanceLedger._id(cancel_id) or not CarryProvenanceLedger._id(operation) or not CarryProvenanceLedger._id(region):
		return _reject("invalid_identity")
	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _reject("invalid_unit")
	var world := unit.get_world_3d()
	var authority := _authority(world, region)
	var record := _record(world, region, StringName(cancel_id))
	if authority == null or record == null or record.state == ConstructionCancellationMath.State.SETTLED:
		return _reject("unknown_or_settled_custody")
	var storage := authority.storage.get_ref() as GroundPileManager
	var camp := storage.get_camp_zone() if storage != null else null
	var load := unit.get_carry_load()
	if not is_instance_valid(camp) or not camp.is_inside_tree() or camp.get_world_3d() != world or not camp.is_valid() or load == null or not load.validate_provenance():
		return _reject("invalid_participant")
	var inventory := record.inventory_ref.get_ref() as SettlementInventory if record.inventory_ref != null else null
	if inventory == null or inventory.get_storage_source() != storage:
		return _reject("inventory_unavailable")
	if not under_guard and not ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(world, region, inventory, storage, &"", unit.get_tree()).ok:
		return _reject("busy_or_wrong_domain")
	if (not under_guard and (authority.has_active_operation() or load.is_transaction_busy() or load._coordinator_transaction_locked)) or not ReservedWithdrawalCoordinator.validate_unit_identity_in_domain_readonly(world, region, unit, load, unit.get_tree()).ok:
		return _reject("busy_or_wrong_domain")
	if not validate_transit(record, unit, storage):
		return _reject("unreconciled_cancellation_custody")
	if not _physical_pickup(record, unit, camp.get_world_navigation()):
		return _reject("out_of_recovery_range_or_navigation")
	if not requests is Array or requests.is_empty():
		return _reject("invalid_request")
	var normalized: Array[Dictionary] = []
	var ids: Dictionary = {}
	for raw: Variant in requests:
		if not raw is Dictionary or raw.size() != 4 or not CarryProvenanceLedger._id(raw.get("lot_id")) or not CarryProvenanceLedger._id(raw.get("resource_id")) or typeof(raw.get("amount")) != TYPE_INT or raw.amount <= 0 or not [CarryProvenanceLedger.CANCEL_BUFFER, CarryProvenanceLedger.CANCEL_INCORPORATED].has(raw.get("origin")):
			return _reject("invalid_request")
		if ids.has(raw.lot_id):
			return _reject("duplicate_lot")
		ids[raw.lot_id] = true
		normalized.append(raw.duplicate())
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.lot_id) < String(b.lot_id))
	var before := load.provenance_snapshot()
	var after := before.duplicate(true)
	var candidate := CarryProvenanceLedger.new()
	if not candidate.restore_transaction_state(before.ledger):
		return _reject("invalid_ledger")
	var custody := record.to_snapshot_dict()
	var remaining := load.get_remaining_capacity()
	var collected: Dictionary = {}
	var links: Array = custody.transit_lots_by_unit.get(before.unit_id, []).duplicate()
	for req: Dictionary in normalized:
		if authority.committed_lots.has(req.lot_id):
			return _reject("lot_operation_conflict")
		for node: Node in unit.get_tree().get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
			var peer := node as Unit
			if is_instance_valid(peer) and peer.is_inside_tree() and peer.get_world_3d() == world and peer.get_meta(&"region_id", &"") == region and peer.get_carry_load().provenance_snapshot().get("ledger", {}).get("used_lots", {}).has(req.lot_id):
				return _reject("lot_operation_conflict")
		var field := "local_buffer_remaining" if req.origin == CarryProvenanceLedger.CANCEL_BUFFER else "local_incorporated_remaining"
		var available: int = custody[field].get(req.resource_id, 0)
		var weight: int = record.resource_weights.get(req.resource_id, 0)
		if req.amount > available or weight <= 0 or (after.weights.has(req.resource_id) and after.weights[req.resource_id] != weight):
			return _reject("unavailable_or_weight_mismatch")
		@warning_ignore("integer_division")
		var qty: int = mini(req.amount, remaining / weight)
		if qty == 0:
			continue
		var lot := {"lot_id": StringName(req.lot_id), "unit_id": before.unit_id, "resource_id": StringName(req.resource_id), "quantity": qty, "origin": req.origin, "site_id": record.site_id, "generation": record.generation}
		var registered := candidate.register_lot(StringName("recovery/%d:%s/%s" % [String(operation).length(), operation, req.lot_id]), lot)
		if not registered.ok or registered.replayed:
			return _reject("lot_operation_conflict")
		after.amounts[req.resource_id] = int(after.amounts.get(req.resource_id, 0)) + qty
		after.weights[req.resource_id] = weight
		custody[field][req.resource_id] = available - qty
		custody.in_transit_remaining[req.resource_id] = int(custody.in_transit_remaining.get(req.resource_id, 0)) + qty
		links.append(StringName(req.lot_id))
		collected[req.resource_id] = int(collected.get(req.resource_id, 0)) + qty
		remaining -= qty * weight
	if collected.is_empty():
		return _reject("capacity_exhausted")
	links.sort()
	custody.transit_lots_by_unit[before.unit_id] = links
	after.ledger = candidate.snapshot_transaction_state()
	if not candidate.validate_aggregate(before.unit_id, after.amounts).ok or not ReservedWithdrawalCoordinator.validate_custody_accounting_pure(custody).ok:
		return _reject("conservation_failed")
	return {"ok": true, "cancel_id": StringName(cancel_id), "operation_id": StringName(operation), "unit": unit.get_instance_id(), "load": load.get_instance_id(), "request": normalized, "before": before, "after": after, "before_custody": record.to_snapshot_dict(), "after_custody": custody, "collected": collected, "revision": load.get_transaction_revision(), "capacity": load.get_effective_capacity(), "nav_revision": camp.get_world_navigation().get_navigation_revision()}


static func _restore_record(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord, snapshot: Dictionary) -> void:
	for field: String in MUTABLE_FIELDS:
		var value: Variant = snapshot[field]
		record.set(field, value.duplicate(true) if value is Dictionary else value)
	record.revision += 1


static func _advance(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord) -> void:
	ReservedWithdrawalCoordinator.transition_custody_record(record, ConstructionCancellationMath.State.RETURNING)
	record.diagnostic_reason = ""
	if not record.has_unsettled_custody():
		ReservedWithdrawalCoordinator.transition_custody_record(record, ConstructionCancellationMath.State.SETTLED)


static func recover(cancel_id: Variant, unit: Unit, requests: Variant, operation: Variant, region: StringName, prepared: Dictionary = {}, fail_at: String = "") -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not is_instance_valid(unit) or not unit.is_inside_tree() or not CarryProvenanceLedger._id(operation):
		return _reject("invalid_identity")
	var authority := _authority(unit.get_world_3d(), region)
	if authority == null or authority.has_active_operation():
		return _reject("busy_or_unknown_domain")
	if not requests is Array:
		return _reject("invalid_request")
	for raw: Variant in requests:
		if not raw is Dictionary or not CarryProvenanceLedger._id(raw.get("lot_id")):
			return _reject("invalid_request")
	if authority.receipts.has(operation):
		var old: Dictionary = authority.receipts[operation]
		var saved: Dictionary = old.get("receipt", {})
		var normalized: Array = requests.duplicate(true) if requests is Array else []
		normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("lot_id", "")) < String(b.get("lot_id", "")))
		if saved.get("kind") != RECOVERY_KIND or saved.cancel_id != cancel_id or saved.unit != unit.get_instance_id() or old.get("load").get_ref() != unit.get_carry_load() or saved.request != normalized:
			return _reject("operation_conflict")
		return {"ok": true, "replayed": true, "receipt": saved.duplicate(true)}
	var plan := prepare(cancel_id, unit, requests, operation, region)
	if not plan.ok:
		return plan
	if not prepared.is_empty() and prepared != plan:
		return _reject("stale_plan")
	var storage := authority.storage.get_ref() as GroundPileManager
	var record := _record(unit.get_world_3d(), region, StringName(cancel_id))
	var inventory := record.inventory_ref.get_ref() as SettlementInventory if record.inventory_ref != null else null
	if inventory == null:
		return _reject("inventory_unavailable")
	var scope := ReservedWithdrawalCoordinator.CampDeliveryScope.new()
	scope.world = unit.get_world_3d()
	scope.region_id = region
	scope.unit = unit
	scope.load = unit.get_carry_load()
	scope.storage = storage
	scope.inventory = inventory
	scope.camp_zone = storage.get_camp_zone()
	scope.sites = SelectiveCampDeliveryCoordinator._collect_domain_sites_sorted(unit.get_tree(), scope.world, region)
	if not SelectiveCampDeliveryCoordinator._acquire(authority, scope):
		return _reject("busy")
	var fresh := prepare(cancel_id, unit, requests, operation, region, true)
	var result := _reject("stale_plan")
	if fresh == plan:
		result = _apply_recovery(authority, scope, plan, fail_at)
	SelectiveCampDeliveryCoordinator._release(authority, scope)
	return result


## Read-only H->E projection. Called again under the existing delivery scope.
static func prepare_delivery(unit: Unit, storage: GroundPileManager, selected: Array) -> Dictionary:
	var changes: Dictionary = {}
	for lot: Dictionary in selected:
		if not CANCEL_ORIGINS.has(lot.origin):
			continue
		var classified := classify_lot(unit, storage, lot)
		if not classified.ok:
			return classified
		var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = classified.record
		if not changes.has(record.cancel_id):
			changes[record.cancel_id] = {"record": record, "before": classified.snapshot, "after": classified.snapshot.duplicate(true)}
		var after: Dictionary = changes[record.cancel_id].after
		var qty: int = lot.selected_quantity
		var resource: StringName = lot.resource_id
		if qty <= 0 or qty > int(after.in_transit_remaining.get(resource, 0)):
			return _reject("unreconciled_cancellation_custody")
		after.in_transit_remaining[resource] -= qty
		after.delivered_to_camp[resource] = int(after.delivered_to_camp.get(resource, 0)) + qty
		if lot.residual_quantity == 0:
			var uid := unit.get_carry_load().get_provenance_unit_id()
			after.transit_lots_by_unit[uid].erase(lot.lot_id)
			if after.transit_lots_by_unit[uid].is_empty():
				after.transit_lots_by_unit.erase(uid)
		if not ReservedWithdrawalCoordinator.validate_custody_accounting_pure(after).ok:
			return _reject("conservation_failed")
	return {"ok": true, "changes": changes}


static func _apply_delivery(scope: ReservedWithdrawalCoordinator.CampDeliveryScope, changes: Dictionary) -> bool:
	if not ReservedWithdrawalCoordinator._owns_camp_delivery_scope(scope) or scope._custody_commit_sealed:
		return false
	for entry: Dictionary in changes.values():
		_restore_record(entry.record, entry.after)
	return true


static func _rollback_delivery(scope: ReservedWithdrawalCoordinator.CampDeliveryScope, changes: Dictionary) -> bool:
	if not ReservedWithdrawalCoordinator._owns_camp_delivery_scope(scope) or scope._custody_commit_sealed:
		return false
	for entry: Dictionary in changes.values():
		_restore_record(entry.record, entry.before)
	return true


static func _finalize_delivery(scope: ReservedWithdrawalCoordinator.CampDeliveryScope, changes: Dictionary) -> void:
	if not ReservedWithdrawalCoordinator._owns_camp_delivery_scope(scope) or scope._custody_commit_sealed:
		return
	for entry: Dictionary in changes.values():
		_advance(entry.record)
	scope._custody_commit_sealed = true


static func _apply_recovery(authority: ReservedWithdrawalCoordinator.RegionalAuthority, scope: ReservedWithdrawalCoordinator.CampDeliveryScope, plan: Dictionary, fail_at: String) -> Dictionary:
	if not ReservedWithdrawalCoordinator._owns_camp_delivery_scope(scope):
		return _reject("unauthorized_scope")
	if scope._custody_commit_sealed or authority.receipts.has(plan.get("operation_id")) or prepare(plan.get("cancel_id"), scope.unit, plan.get("request"), plan.get("operation_id"), scope.region_id, true) != plan:
		return _reject("stale_plan")
	var record := _record(scope.world, scope.region_id, plan.cancel_id)
	var checkpoint := scope.load._capture_provenance_checkpoint()
	var candidate := CarryProvenanceLedger.new()
	if not candidate.restore_transaction_state(plan.after.ledger) or fail_at == "before_apply":
		return _reject("injected_precommit_failure")
	scope.load._provenance = candidate
	scope.load._amounts = plan.after.amounts.duplicate()
	scope.load._unit_weights = plan.after.weights.duplicate()
	scope.load._transaction_revision += 1
	if fail_at != "after_carry":
		_restore_record(record, plan.after_custody)
	if fail_at in ["after_carry", "after_custody", "before_commit"] or not scope.load.validate_provenance() or not validate_transit(record, scope.unit, scope.storage):
		scope.load._restore_provenance_checkpoint_silent(checkpoint)
		_restore_record(record, plan.before_custody)
		return _reject("injected_precommit_failure")
	_advance(record)
	var receipt := {"kind": RECOVERY_KIND, "cancel_id": plan.cancel_id, "operation_id": plan.operation_id, "unit": plan.unit, "request": plan.request.duplicate(true), "collected": plan.collected.duplicate(), "custody": record.to_snapshot_dict()}
	# Definitive commit precedes all callbacks. No subsequent rollback path exists.
	scope._custody_commit_sealed = true
	for lot_id: StringName in plan.after.ledger.lots:
		if not plan.before.ledger.lots.has(lot_id):
			authority.committed_lots[lot_id] = plan.operation_id
	authority.receipts[plan.operation_id] = {"receipt": receipt, "load": weakref(scope.load)}
	sync_footprint(record, scope.world)
	scope.load.load_changed.emit()
	return {"ok": true, "replayed": false, "receipt": receipt.duplicate(true)}


static func sync_footprint(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord, world: World3D) -> void:
	var site := record.visual_site.get_ref() as ConstructionSite if record.visual_site != null else null
	var body := record.custody_body.get_ref() as StaticBody3D if record.custody_body != null else null
	if record.requires_local_footprint_occupation() and body == null and is_instance_valid(site):
		body = StaticBody3D.new()
		body.name = "CancellationCustodyFootprint"
		body.collision_layer = CollisionLayers.MASK_BUILDINGS
		body.collision_mask = 0
		body.set_meta(&"_cancellation_region", record.region_id)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(record.footprint_size.x, record.collider_height, record.footprint_size.y)
		shape.shape = box
		shape.position.y = record.collider_height * 0.5
		body.add_child(shape)
		body.position = (site.get_parent() as Node3D).to_local(record.anchor_position)
		site.get_parent().add_child(body)
		record.custody_body = weakref(body)
	if is_instance_valid(site):
		site._site_body.collision_layer = 0
		if not record.requires_local_footprint_occupation():
			site._visual_root.hide()
	if not record.requires_local_footprint_occupation() and is_instance_valid(body):
		body.collision_layer = 0
		body.queue_free()
	if world != null and record.inventory_ref != null:
		var inventory := record.inventory_ref.get_ref() as SettlementInventory
		var nav := inventory.get_storage_source().get_camp_zone().get_world_navigation() as WorldNavigation if inventory != null else null
		if is_instance_valid(nav):
			nav.invalidate_static_geometry_cache()


static func overlaps(world: World3D, region: StringName, rect: Rect2) -> bool:
	if world == null:
		return false
	var authority := _authority(world, region)
	if authority == null:
		return false
	for record: ReservedWithdrawalCoordinator.CancellationCustodyRecord in authority.cancellation_custodies.values():
		if record.requires_local_footprint_occupation() and Rect2(Vector2(record.anchor_position.x, record.anchor_position.z) - record.footprint_size * 0.5, record.footprint_size).intersects(rect, true):
			return true
	return false
