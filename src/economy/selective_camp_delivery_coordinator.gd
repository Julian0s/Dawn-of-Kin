class_name SelectiveCampDeliveryCoordinator
extends RefCounted
## Explicit opt-in transactional coordinator for atomic selective camp delivery.
## Shares ReservedWithdrawalCoordinator.RegionalAuthority and fixed cooperative guard ordering
## with C2-R1 and C3.2. Orders (DeliverToCampOrder / ConstructOrder) never invoke this API in C3.4.2.
##
## Provisional signal policy (DEC-T3.6-SIGNALS-01 remains pending):
## Publishes coherent notifications strictly post-commit while cooperative guards remain held,
## matching C2-R1 and C3.2 compatibility.

const Planner = preload("res://src/economy/selective_camp_delivery_planner.gd")
const TxHelpers = preload("res://src/economy/selective_camp_delivery_tx_helpers.gd")
const CampDeliveryScope = ReservedWithdrawalCoordinator.CampDeliveryScope
const RegionalAuthority = ReservedWithdrawalCoordinator.RegionalAuthority
const RECEIPT_KIND := ReservedWithdrawalCoordinator.RECEIPT_CAMP_DELIVERY

# Test-only synchronous fault injection. Receives only the stage name (never mutable plan state).
var _fault_at: Callable = Callable()
var _domain := ReservedWithdrawalCoordinator.new()


func execute_selective_camp_delivery(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	operation_id: Variant,
	requested_lots: Variant = []
) -> Dictionary:
	return _execute(inventory, camp_zone, unit, region_id, operation_id, requested_lots, {})


func commit_prepared_selective_camp_delivery(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	plan: Variant
) -> Dictionary:
	if typeof(plan) != TYPE_DICTIONARY:
		return _failure("invalid_plan", "preparation")
	var typed_plan: Dictionary = plan as Dictionary
	var shape := Planner._validate_plan_shape(typed_plan)
	if not bool(shape.get("ok", false)):
		return _failure(String(shape.get("reason", "invalid_plan")), "preparation")
	return _execute(
		inventory,
		camp_zone,
		unit,
		region_id,
		typed_plan["operation_id"],
		typed_plan["requested_lots"],
		typed_plan
	)


func get_receipt(operation_id: Variant) -> Dictionary:
	if not CarryProvenanceLedger._id(operation_id):
		return {}
	var authority := _domain._last_authority()
	if authority == null:
		return {}
	return TxHelpers.validate_camp_receipt(authority, StringName(operation_id)).duplicate(true)


func get_receipt_in_domain(world: World3D, region_id: Variant, operation_id: Variant) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or world == null:
		return {}
	if not CarryProvenanceLedger._id(region_id) or not CarryProvenanceLedger._id(operation_id):
		return {}
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var authority := domains.get(StringName(region_id)) as RegionalAuthority
	if authority == null:
		return {}
	return TxHelpers.validate_camp_receipt(authority, StringName(operation_id)).duplicate(true)


func _execute(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	operation_id: Variant,
	requested_lots: Variant,
	plan: Dictionary
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _failure("wrong_thread", "thread")
	if not CarryProvenanceLedger._id(operation_id):
		return _failure("invalid_operation", "preparation")
	var op := StringName(operation_id)
	if not CarryProvenanceLedger._id(region_id):
		return _failure("invalid_region", "preparation")
	var region := StringName(region_id)

	var parsed := Planner._parse_lot_request(requested_lots, op)
	if not bool(parsed.get("ok", false)):
		return _failure(String(parsed.get("reason", "invalid_request")), "preparation")
	var normalized_request: Array[Dictionary] = parsed["requests"] as Array[Dictionary]

	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _failure("invalid_unit", "authorization")
	var world := unit.get_world_3d()
	var tree := unit.get_tree()
	if world == null or tree == null:
		return _failure("invalid_domain", "authorization")

	if inventory == null:
		return _failure("invalid_inventory", "authorization")
	var storage := inventory.get_storage_source() as GroundPileManager
	if storage == null:
		return _failure("unsupported_storage_source", "storage")

	if (
		camp_zone == null
		or not is_instance_valid(camp_zone)
		or not camp_zone.is_inside_tree()
		or camp_zone.is_queued_for_deletion()
		or not camp_zone.is_valid()
		or camp_zone.max_pile_amount < 0
	):
		return _failure("invalid_camp_zone", "camp_zone")
	if camp_zone.get_world_3d() != world:
		return _failure("world_mismatch", "camp_zone")
	if storage.get_camp_zone() != camp_zone:
		return _failure("invalid_camp_zone", "camp_zone")

	var load := unit.get_carry_load()
	var existing_domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var existing_authority: RegionalAuthority = existing_domains.get(region) as RegionalAuthority
	if existing_authority != null:
		var domain_probe := ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(
			world, region, inventory, storage, &"", tree
		)
		if not bool(domain_probe.get("ok", false)) and String(domain_probe.get("reason", "")) != "busy":
			return _failure(String(domain_probe.get("reason", "ambiguous_domain")), String(domain_probe.get("dependency", "coordinator")))
		if existing_authority.is_executing:
			return _failure("busy", "coordinator")
		if existing_authority.receipts.has(op):
			_domain._last_world = weakref(world)
			_domain._last_region = region
			return _replay(existing_authority, op, world, region, inventory, storage, camp_zone, unit, load, normalized_request, plan)

	if Planner._has_untrusted_custom_position_validator(camp_zone):
		return _failure("unsafe_custom_position_validator", "camp_zone")
	if storage.pile_creator_override.is_valid() or not storage.pile_creator_override.is_null():
		return _failure("unsafe_pile_creator_override", "storage")
	if load == null or not load.is_provenance_enabled() or not CarryProvenanceLedger._id(load.get_provenance_unit_id()):
		return _failure("provenance_disabled", "carry_load")

	var auth_res: Dictionary = _domain._resolve_camp_authority(world, region, inventory, storage, tree)
	if not bool(auth_res.get("ok", false)):
		return _failure(String(auth_res.get("reason", "ambiguous_domain")), String(auth_res.get("dependency", "coordinator")))
	var authority: RegionalAuthority = auth_res["authority"] as RegionalAuthority
	if authority.is_executing:
		return _failure("busy", "coordinator")
	if authority.receipts.has(op):
		return _replay(authority, op, world, region, inventory, storage, camp_zone, unit, load, normalized_request, plan)

	var scope := CampDeliveryScope.new()
	scope.world = world
	scope.region_id = region
	scope.camp_zone = camp_zone
	scope.unit = unit
	scope.load = load
	scope.inventory = inventory
	scope.storage = storage
	scope.sites = _collect_domain_sites_sorted(tree, world, region)
	if not _acquire(authority, scope):
		return _failure("busy", "participants")

	var result := _commit_under_guards(authority, scope, op, normalized_request, plan)
	_release(authority, scope)
	return result


func _commit_under_guards(
	authority: RegionalAuthority,
	scope: CampDeliveryScope,
	op: StringName,
	normalized_request: Array[Dictionary],
	plan: Dictionary
) -> Dictionary:
	var fresh := Planner._prepare_under_camp_delivery_scope(scope, op, normalized_request)
	if not plan.is_empty():
		var comparison := Planner._compare_plan(fresh, plan)
		if not bool(comparison.get("ok", false)):
			return _failure(String(comparison.get("reason", "stale_revision")), String(comparison.get("dependency", "plan")))
	if not bool(fresh.get("ok", false)):
		return _failure(String(fresh.get("reason", "preparation_failed")), String(fresh.get("dependency", "preparation")))

	var auth_check := TxHelpers.check_physical_authorization(scope)
	if not bool(auth_check.get("ok", false)):
		return _failure(String(auth_check.get("reason", "authorization_failed")), String(auth_check.get("dependency", "authorization")))

	var debited_ledger := TxHelpers.prepare_commit_debits(authority, fresh)
	if debited_ledger == null:
		return _failure("debit_preparation_failed", "preparation")

	var checkpoint := TxHelpers.capture_checkpoints(scope, fresh, debited_ledger)
	if not bool(checkpoint.get("ok", false)):
		return _failure(String(checkpoint.get("reason", "checkpoint_failed")), "preparation")

	var plan_digest := _plan_digest(fresh if plan.is_empty() else plan)

	if _aborted("before_carry_debit"):
		return _failure("aborted_before_carry_debit", "transaction")
	if _fault_at.is_valid():
		var reauth := TxHelpers.check_physical_authorization(scope)
		if not bool(reauth.get("ok", false)):
			return _failure(String(reauth.get("reason", "authorization_failed")), String(reauth.get("dependency", "authorization")))

	var apply_res := _apply_silent(scope, fresh, debited_ledger, checkpoint)
	if not bool(apply_res.get("ok", false)):
		TxHelpers.restore_silent(scope, checkpoint)
		return _failure(String(apply_res.get("reason", "transaction_aborted")), "transaction")

	# Irreversible commit boundary: disconnect exhausted transit listeners, advance revisions,
	# record regional receipt, attach created piles & sync visuals, then publish notifications.
	var site_ckpts: Dictionary = checkpoint["site_ckpts"] as Dictionary
	var after_sites: Dictionary = fresh["after"]["sites"] as Dictionary
	var involved_sites_sorted: Array[ConstructionSite] = []
	for sid: StringName in Planner._sorted_string_names(after_sites.keys()):
		var sc: Dictionary = site_ckpts[sid] as Dictionary
		var site: ConstructionSite = sc["site"] as ConstructionSite
		involved_sites_sorted.append(site)
		if (after_sites[sid]["claim"] as Dictionary).is_empty():
			var cb: Callable = sc["callback"] as Callable
			if scope.load.load_changed.is_connected(cb):
				scope.load.load_changed.disconnect(cb)

	scope.load._transaction_revision += 1
	scope.storage._transaction_revision += 1
	scope.inventory._transaction_revision += 1
	for site: ConstructionSite in involved_sites_sorted:
		site._transaction_revision += 1

	var created_pile_ids: Array[int] = apply_res["created_pile_ids"] as Array[int]
	var resolved_restorations: Array[Dictionary] = apply_res["resolved_restorations"] as Array[Dictionary]
	var receipt := {
		"kind": RECEIPT_KIND,
		"operation_id": op,
		"identity": (fresh["identity"] as Dictionary).duplicate(true),
		"requested_lots": normalized_request.duplicate(true),
		"selected_lots": _build_receipt_selected_summary(fresh["selected_lots"] as Array),
		"delivered_amounts": (fresh["deliverable_amounts"] as Dictionary).duplicate(true),
		"created_pile_ids": created_pile_ids.duplicate(),
		"restored_reservations": resolved_restorations.duplicate(true),
		"plan_digest": plan_digest,
	}
	authority.receipts[op] = {
		"receipt": receipt,
		"camp_zone": weakref(scope.camp_zone),
		"unit": weakref(scope.unit),
		"load": weakref(scope.load),
		"inventory": weakref(scope.inventory),
		"storage": weakref(scope.storage),
	}

	# Attach created detached piles and sync visuals after receipt is recorded.
	scope.storage._finalize_camp_delivery_after_commit_silent(checkpoint["storage_ckpt"] as Dictionary)

	_publish(scope, involved_sites_sorted, not resolved_restorations.is_empty())
	return _success(receipt, false)


func _apply_silent(
	scope: CampDeliveryScope,
	plan: Dictionary,
	debited_ledger: CarryProvenanceLedger,
	checkpoint: Dictionary
) -> Dictionary:
	if not ReservedWithdrawalCoordinator._owns_camp_delivery_scope(scope):
		return {"ok": false, "reason": "busy"}

	var load := scope.load
	var storage := scope.storage
	var storage_ckpt: Dictionary = checkpoint["storage_ckpt"] as Dictionary
	var uid := scope.unit.get_instance_id()

	# 1. Carry ledger & amounts debit
	load._provenance = debited_ledger
	checkpoint["carry_mutated"] = true
	if _aborted("after_ledger_debit"):
		return {"ok": false, "reason": "aborted_after_ledger_debit"}
	load._amounts = (plan["after"]["cargo"]["amounts"] as Dictionary).duplicate()
	load._unit_weights = (plan["after"]["cargo"]["weights"] as Dictionary).duplicate()
	if _aborted("after_carry_debit"):
		return {"ok": false, "reason": "aborted_after_carry_debit"}

	# 2. Existing pile merges
	if _aborted("before_pile_merge"):
		return {"ok": false, "reason": "aborted_before_pile_merge"}
	var merges: Array = plan["deposit_projection"]["merges"] as Array
	for idx: int in range(merges.size()):
		var merge_res := storage._apply_camp_delivery_merge_silent(merges[idx] as Dictionary, storage_ckpt)
		if not bool(merge_res.get("ok", false)):
			return {"ok": false, "reason": String(merge_res.get("reason", "pile_merge_failed"))}
		if idx == 0 and _aborted("after_pile_merge"):
			return {"ok": false, "reason": "aborted_after_pile_merge"}
	if merges.is_empty() and _aborted("after_pile_merge"):
		return {"ok": false, "reason": "aborted_after_pile_merge"}

	# 3. Detached new pile creations
	if _aborted("before_pile_create"):
		return {"ok": false, "reason": "aborted_before_pile_create"}
	var creates: Array = plan["deposit_projection"]["creates"] as Array
	var virtual_to_real_pile_ids: Dictionary = {}
	var created_pile_ids: Array[int] = []
	for idx: int in range(creates.size()):
		if idx > 0 and _aborted("during_pile_create"):
			return {"ok": false, "reason": "aborted_during_pile_create"}
		var create_entry: Dictionary = creates[idx] as Dictionary
		var create_res := storage._apply_camp_delivery_create_detached_silent(create_entry, storage_ckpt)
		if not bool(create_res.get("ok", false)):
			return {"ok": false, "reason": String(create_res.get("reason", "pile_create_failed"))}
		var real_pid: int = int(create_res["pile_id"])
		virtual_to_real_pile_ids[create_entry["virtual_pile_id"] as StringName] = real_pid
		created_pile_ids.append(real_pid)
	if _aborted("after_pile_create"):
		return {"ok": false, "reason": "aborted_after_pile_create"}

	# 4. Physical pile reservation restorations (binding virtual_pile_id -> real pile_id atomically)
	if _aborted("before_reservation_restore"):
		return {"ok": false, "reason": "aborted_before_reservation_restore"}
	var restorations: Array = plan["reservation_projection"]["restorations"] as Array
	var resolved_restorations: Array[Dictionary] = []
	for idx: int in range(restorations.size()):
		if idx > 0 and _aborted("during_reservation_restore"):
			return {"ok": false, "reason": "aborted_during_reservation_restore"}
		var r: Dictionary = restorations[idx] as Dictionary
		var target_kind: StringName = r["target_kind"] as StringName
		var target_pid: int = int(r["pile_id"]) if target_kind == &"existing_pile" else int(virtual_to_real_pile_ids.get(r["virtual_pile_id"], 0))
		if target_pid <= 0:
			return {"ok": false, "reason": "reservation_target_pile_unresolved"}
		var res_apply := storage._apply_camp_delivery_reservation_restore_silent(
			target_pid,
			r["resource_id"] as StringName,
			r["reservation_id"] as StringName,
			int(r["amount"]),
			storage_ckpt
		)
		if not bool(res_apply.get("ok", false)):
			return {"ok": false, "reason": String(res_apply.get("reason", "reservation_restore_failed"))}
		resolved_restorations.append({
			"site_id": r["site_id"],
			"reservation_id": r["reservation_id"],
			"lot_id": r["lot_id"],
			"resource_id": r["resource_id"],
			"amount": int(r["amount"]),
			"pile_id": target_pid,
		})
	if _aborted("after_reservation_restore"):
		return {"ok": false, "reason": "aborted_after_reservation_restore"}

	# 5. ConstructionSite transit claim updates
	if _aborted("before_claim_update"):
		return {"ok": false, "reason": "aborted_before_claim_update"}
	var site_ckpts: Dictionary = checkpoint["site_ckpts"] as Dictionary
	var after_sites: Dictionary = plan["after"]["sites"] as Dictionary
	for sid: StringName in Planner._sorted_string_names(after_sites.keys()):
		var sc: Dictionary = site_ckpts[sid] as Dictionary
		var site: ConstructionSite = sc["site"] as ConstructionSite
		var next_claim_amounts: Dictionary = after_sites[sid]["claim"] as Dictionary
		if next_claim_amounts.is_empty():
			site._transit_claims.erase(uid)
		else:
			var updated_claim: Dictionary = (sc["claim"] as Dictionary).duplicate()
			updated_claim["amounts"] = next_claim_amounts.duplicate()
			site._transit_claims[uid] = updated_claim
		sc["mutated"] = true
	if _aborted("after_claim_update"):
		return {"ok": false, "reason": "aborted_after_claim_update"}

	# 6. Final invariants & global conservation verification
	if _aborted("during_final_invariants"):
		return {"ok": false, "reason": "aborted_during_final_invariants"}
	if not TxHelpers.verify_final_invariants(scope, plan, checkpoint, virtual_to_real_pile_ids):
		return {"ok": false, "reason": "invariant_violation_aborted"}

	if _aborted("before_receipt_commit"):
		return {"ok": false, "reason": "aborted_before_receipt_commit"}

	return {
		"ok": true,
		"created_pile_ids": created_pile_ids,
		"resolved_restorations": resolved_restorations,
	}


static func _collect_domain_sites_sorted(tree: SceneTree, world: World3D, region: StringName) -> Array[ConstructionSite]:
	var sites: Array[ConstructionSite] = []
	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		if not (node is ConstructionSite):
			continue
		var site: ConstructionSite = node as ConstructionSite
		if is_instance_valid(site) and site.is_inside_tree() and site.get_world_3d() == world and site.region_id == region:
			sites.append(site)
	sites.sort_custom(func(left: ConstructionSite, right: ConstructionSite) -> bool:
		if left.site_id == right.site_id:
			return left.get_instance_id() < right.get_instance_id()
		return String(left.site_id) < String(right.site_id))
	return sites


static func _acquire(authority: RegionalAuthority, scope: CampDeliveryScope) -> bool:
	if (
		authority.is_executing
		or scope.inventory.is_transaction_busy()
		or scope.storage.is_locked()
		or scope.storage.is_batch_active()
		or scope.camp_zone.is_transaction_locked()
		or scope.load.is_transaction_busy()
	):
		return false
	for site: ConstructionSite in scope.sites:
		if site.is_transaction_busy():
			return false
	authority.is_executing = true
	authority.active_camp_delivery = scope
	for site: ConstructionSite in scope.sites:
		site._is_preparing_or_transacting = true
	scope.inventory._is_delivering = true
	scope.storage._is_preparing_withdrawal = true
	scope.camp_zone._coordinator_transaction_locked = true
	scope.load._provenance_busy = true
	scope.load._coordinator_transaction_locked = true
	return true


static func _release(authority: RegionalAuthority, scope: CampDeliveryScope) -> void:
	scope.load._coordinator_transaction_locked = false
	scope.load._provenance_busy = false
	if is_instance_valid(scope.camp_zone):
		scope.camp_zone._coordinator_transaction_locked = false
	scope.storage._is_preparing_withdrawal = false
	scope.inventory._is_delivering = false
	for idx: int in range(scope.sites.size() - 1, -1, -1):
		var site := scope.sites[idx]
		if is_instance_valid(site):
			site._is_preparing_or_transacting = false
	authority.active_camp_delivery = null
	authority.is_executing = false


static func _publish(
	scope: CampDeliveryScope,
	involved_sites: Array[ConstructionSite],
	reservations_modified: bool
) -> void:
	var echo_flags: Dictionary = {}
	for site: ConstructionSite in scope.sites:
		if is_instance_valid(site):
			echo_flags[site.get_instance_id()] = site._suppress_coordinator_signal_echo
			site._suppress_coordinator_signal_echo = true
	if reservations_modified:
		scope.storage._dispatch_reservations_changed()
	scope.storage._dispatch_storage_changed()
	scope.load.load_changed.emit()
	for site: ConstructionSite in involved_sites:
		if is_instance_valid(site):
			site.state_changed.emit(site)
	for site: ConstructionSite in scope.sites:
		if is_instance_valid(site) and echo_flags.has(site.get_instance_id()):
			site._suppress_coordinator_signal_echo = bool(echo_flags[site.get_instance_id()])


static func _replay(
	authority: RegionalAuthority,
	op: StringName,
	world: World3D,
	region: StringName,
	inventory: SettlementInventory,
	storage: GroundPileManager,
	camp_zone: CampStorageZone,
	unit: Unit,
	load: UnitCarryLoad,
	normalized_request: Array[Dictionary],
	plan: Dictionary
) -> Dictionary:
	var receipt := TxHelpers.validate_camp_receipt(authority, op)
	if receipt.is_empty() or load == null:
		return _failure("operation_conflict", "receipt")
	var record: Dictionary = authority.receipts[op] as Dictionary
	if (
		record["camp_zone"].get_ref() != camp_zone
		or record["unit"].get_ref() != unit
		or record["load"].get_ref() != load
		or record["inventory"].get_ref() != inventory
		or record["storage"].get_ref() != storage
	):
		return _failure("operation_conflict", "receipt")
	var id: Dictionary = receipt["identity"] as Dictionary
	if (
		int(id["world"]) != world.get_instance_id()
		or (id["region_id"] as StringName) != region
		or int(id["inventory"]) != inventory.get_instance_id()
		or int(id["storage"]) != storage.get_instance_id()
		or int(id["camp_zone"]) != camp_zone.get_instance_id()
		or (id["camp_zone_id"] as StringName) != camp_zone.zone_id
		or not is_instance_valid(storage._piles_root)
		or int(id["piles_root"]) != storage._piles_root.get_instance_id()
		or int(id["unit"]) != unit.get_instance_id()
		or (id["unit_id"] as StringName) != load.get_provenance_unit_id()
		or int(id["load"]) != load.get_instance_id()
	):
		return _failure("operation_conflict", "receipt")
	if not Planner._strict_equal(receipt["requested_lots"], normalized_request):
		return _failure("operation_conflict", "receipt")
	if not plan.is_empty() and _plan_digest(plan) != String(receipt["plan_digest"]):
		return _failure("operation_conflict", "receipt")
	return _success(receipt, true)


static func _build_receipt_selected_summary(selected_lots: Array) -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	for item_var: Variant in selected_lots:
		var item: Dictionary = item_var as Dictionary
		summary.append({
			"lot_id": item["lot_id"],
			"resource_id": item["resource_id"],
			"origin": item["origin"],
			"site_id": item["site_id"],
			"generation": int(item["generation"]),
			"selected_quantity": int(item["selected_quantity"]),
			"destination_class": item["destination_class"],
		})
	return summary


static func _plan_digest(plan: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(plan))
	return context.finish().hex_encode()


func _aborted(stage: String) -> bool:
	return _fault_at.is_valid() and _fault_at.call(stage) == true


static func _success(receipt: Dictionary, replayed: bool) -> Dictionary:
	var delivered_amounts: Dictionary = receipt["delivered_amounts"] as Dictionary
	var total_units: int = 0
	for qty: Variant in delivered_amounts.values():
		total_units += int(qty)
	return {
		"ok": true,
		"reason": "",
		"dependency": "",
		"replayed": replayed,
		"delivered_now": 0 if replayed else total_units,
		"delivered_amounts": delivered_amounts.duplicate(true),
		"created_pile_ids": (receipt["created_pile_ids"] as Array).duplicate(),
		"receipt": receipt.duplicate(true),
	}


static func _failure(reason: String, dependency: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"dependency": dependency,
		"replayed": false,
		"delivered_now": 0,
		"delivered_amounts": {},
		"created_pile_ids": [],
		"receipt": {},
	}
