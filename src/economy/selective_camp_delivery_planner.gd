class_name SelectiveCampDeliveryPlanner
extends RefCounted
## Pure read-only planner and validator for selective camp delivery of provenance-tracked cargo.
## Projects lot debits, physical pile merges/creations, and active-site reservation restorations
## without mutating any economic participant, ledger, pile, claim, revision, receipt, or signal.

const DEST_CAMP_FREE_STOCK: StringName = &"camp_free_stock"
const DEST_SITE_RESERVED_RESTORATION: StringName = &"site_reserved_restoration"
const VALIDATION_SCOPE: String = "accounting_and_storage_projection_only"


## Prepares a pure dry-run plan for selective camp delivery.
## Explicit `requested_lots` entries are exact: `[{"lot_id": StringName, "amount": int}]`.
## An empty `requested_lots` array conservatively selects ONLY eligible `FREE_GATHERED` lots;
## `SITE_RESERVED` lots always require explicit selection and full active-site reconciliation.
static func prepare_selective_camp_delivery(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	operation_id: Variant,
	requested_lots: Variant = []
) -> Dictionary:
	return _prepare(inventory, camp_zone, unit, region_id, operation_id, requested_lots, null)


## Internal revalidation entry point restricted to an owned SelectiveCampDeliveryCoordinator scope.
## Never exposed as a public busy bypass: rejects any scope not actively held by the regional authority.
static func _prepare_under_camp_delivery_scope(
	scope: ReservedWithdrawalCoordinator.CampDeliveryScope,
	operation_id: StringName,
	requested_lots: Array[Dictionary]
) -> Dictionary:
	if not ReservedWithdrawalCoordinator._owns_camp_delivery_scope(scope):
		return _reject("busy", "coordinator", operation_id)
	return _prepare(scope.inventory, scope.camp_zone, scope.unit, scope.region_id, operation_id, requested_lots, scope)


static func _prepare(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	operation_id: Variant,
	requested_lots: Variant,
	scope: ReservedWithdrawalCoordinator.CampDeliveryScope
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _reject("wrong_thread", "thread")
	if not CarryProvenanceLedger._id(operation_id):
		return _reject("invalid_operation", "input")
	var op := StringName(operation_id)
	if not CarryProvenanceLedger._id(region_id):
		return _reject("invalid_region", "input", op)
	var region := StringName(region_id)

	var parsed := _parse_lot_request(requested_lots, op)
	if not bool(parsed.get("ok", false)):
		return parsed
	var normalized_request: Array[Dictionary] = parsed["requests"] as Array[Dictionary]

	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return _reject("invalid_unit", "unit", op, normalized_request)
	var world := unit.get_world_3d()
	if world == null:
		return _reject("invalid_domain", "unit", op, normalized_request)

	if inventory == null:
		return _reject("invalid_inventory", "inventory", op, normalized_request)
	var storage_source: SettlementStorageSource = inventory.get_storage_source()
	if storage_source == null or not (storage_source is GroundPileManager):
		return _reject("unsupported_storage_source", "storage", op, normalized_request)
	var storage: GroundPileManager = storage_source as GroundPileManager

	if (
		camp_zone == null
		or not is_instance_valid(camp_zone)
		or not camp_zone.is_inside_tree()
		or camp_zone.is_queued_for_deletion()
		or not camp_zone.is_valid()
		or camp_zone.max_pile_amount < 0
	):
		return _reject("invalid_camp_zone", "camp_zone", op, normalized_request)
	if camp_zone.get_world_3d() != world:
		return _reject("world_mismatch", "camp_zone", op, normalized_request)
	if storage.get_camp_zone() != camp_zone:
		return _reject("invalid_camp_zone", "camp_zone", op, normalized_request)
	if _has_untrusted_custom_position_validator(camp_zone):
		return _reject("unsafe_custom_position_validator", "camp_zone", op, normalized_request)

	if storage._piles_root == null or not is_instance_valid(storage._piles_root) or not storage._piles_root.is_inside_tree():
		return _reject("invalid_piles_root", "storage", op, normalized_request)
	if storage._piles_root.get_world_3d() != world:
		return _reject("world_mismatch", "storage", op, normalized_request)

	var nav: WorldNavigation = camp_zone.get_world_navigation()
	if nav != null:
		if not is_instance_valid(nav) or not nav.is_inside_tree() or nav.is_queued_for_deletion():
			return _reject("invalid_camp_zone", "camp_zone", op, normalized_request)
		if nav.get_world_3d() != world:
			return _reject("world_mismatch", "camp_zone", op, normalized_request)

	var load: UnitCarryLoad = unit.get_carry_load()
	if load == null or not load.is_provenance_enabled() or not CarryProvenanceLedger._id(load.get_provenance_unit_id()):
		return _reject("provenance_disabled", "carry_load", op, normalized_request)

	var tree := unit.get_tree()
	if tree == null:
		return _reject("invalid_domain", "unit", op, normalized_request)
	if scope == null:
		if inventory.is_transaction_busy() or storage.is_locked() or storage.is_batch_active() or camp_zone.is_transaction_locked() or load.is_transaction_busy():
			return _reject("busy", "participants", op, normalized_request)
		var domain_check := ReservedWithdrawalCoordinator.inspect_camp_domain_for_preparation(
			world, region, inventory, storage, op, tree
		)
		if not bool(domain_check.get("ok", false)):
			return _reject(
				String(domain_check.get("reason", "ambiguous_domain")),
				String(domain_check.get("dependency", "coordinator")),
				op,
				normalized_request
			)
	else:
		if (
			not ReservedWithdrawalCoordinator._owns_camp_delivery_scope(scope)
			or scope.inventory != inventory
			or scope.camp_zone != camp_zone
			or scope.unit != unit
			or scope.load != load
			or scope.storage != storage
			or scope.region_id != region
		):
			return _reject("busy", "coordinator", op, normalized_request)
		if storage._is_mutating or storage._is_notifying or storage.is_batch_active() or load._provenance_applying or load._batch_depth > 0:
			return _reject("busy", "participants", op, normalized_request)
		var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
		var authority: ReservedWithdrawalCoordinator.RegionalAuthority = domains.get(region) as ReservedWithdrawalCoordinator.RegionalAuthority
		if authority == null or authority.active_camp_delivery != scope:
			return _reject("busy", "coordinator", op, normalized_request)
		if authority.receipts.has(op):
			return _reject("operation_conflict", "receipt", op, normalized_request)

	var site_scan := _scan_sites_pure(tree, world, region, unit, load, op, normalized_request, scope)
	if not bool(site_scan.get("ok", false)):
		return site_scan
	var domain_sites_by_id: Dictionary = site_scan["domain_sites_by_id"] as Dictionary
	var duplicate_site_ids: Dictionary = site_scan["duplicate_site_ids"] as Dictionary
	var duplicate_reservation_ids: Dictionary = site_scan["duplicate_reservation_ids"] as Dictionary
	var other_region_site_ids: Dictionary = site_scan["other_region_site_ids"] as Dictionary
	var other_world_site_ids: Dictionary = site_scan["other_world_site_ids"] as Dictionary
	var site_revisions: Dictionary = site_scan["site_revisions"] as Dictionary

	var cargo := load.provenance_snapshot()
	var ledger := CarryProvenanceLedger.new()
	if not ledger.restore_transaction_state(cargo.get("ledger")):
		return _reject("invalid_ledger", "carry_load", op, normalized_request)
	var unit_id: StringName = StringName(cargo.get("unit_id", &""))
	var cargo_amounts: Dictionary = cargo.get("amounts", {}) as Dictionary
	var cargo_weights: Dictionary = cargo.get("weights", {}) as Dictionary
	var cargo_ledger: Dictionary = cargo.get("ledger", {}) as Dictionary
	var cargo_lots: Dictionary = cargo_ledger.get("lots", {}) as Dictionary
	var cargo_ops: Dictionary = cargo_ledger.get("operations", {}) as Dictionary

	if not bool(ledger.validate_aggregate(unit_id, cargo_amounts).get("ok", false)):
		return _reject("unreconciled_cargo", "carry_load", op, normalized_request)
	if cargo_ops.has(op):
		return _reject("operation_conflict", "provenance_ledger", op, normalized_request)
	for lot_key: Variant in cargo_lots.keys():
		var lot_dict: Dictionary = cargo_lots[lot_key] as Dictionary
		if StringName(lot_dict.get("unit_id", &"")) != unit_id:
			return _reject("ambiguous_unit_identity", "carry_load", op, normalized_request)

	var before_weight_check := _measure_cargo(cargo_amounts, cargo_weights, storage, op, normalized_request)
	if not bool(before_weight_check.get("ok", false)):
		return before_weight_check
	var before_weight: int = int(before_weight_check["value"])
	if before_weight != load.get_current_weight():
		return _reject("resource_or_weight_mismatch", "carry_load", op, normalized_request)

	var storage_check := _inspect_storage_state_pure(storage, world, op, normalized_request)
	if not bool(storage_check.get("ok", false)):
		return storage_check
	var ordered_piles: Array[GroundResourcePile] = storage_check["ordered_piles"] as Array[GroundResourcePile]
	var camp_physical_before: Dictionary = storage_check["physical_amounts"] as Dictionary
	var camp_reserved_before: Dictionary = storage_check["reserved_amounts"] as Dictionary
	var camp_free_before: Dictionary = storage_check["free_amounts"] as Dictionary
	var pile_revisions: Dictionary = storage_check["pile_revisions"] as Dictionary

	var classification := _classify_lots_pure(
		cargo_lots,
		cargo_weights,
		unit,
		load,
		storage,
		domain_sites_by_id,
		duplicate_site_ids,
		duplicate_reservation_ids,
		other_region_site_ids,
		other_world_site_ids
	)
	var lot_info_by_id: Dictionary = classification["lot_info_by_id"] as Dictionary
	var site_contexts: Dictionary = classification["site_contexts"] as Dictionary

	var selection := _resolve_selection_pure(
		normalized_request,
		cargo_lots,
		lot_info_by_id,
		op
	)
	if not bool(selection.get("ok", false)):
		return selection
	var selected_entries: Array[Dictionary] = selection["selected_entries"] as Array[Dictionary]
	var blocked_lots: Array[Dictionary] = selection["blocked_lots"] as Array[Dictionary]

	var ledger_proj := _simulate_ledger_debits_pure(
		cargo,
		ledger,
		selected_entries,
		storage,
		op,
		normalized_request,
		blocked_lots
	)
	if not bool(ledger_proj.get("ok", false)):
		return ledger_proj
	var deliverable_amounts: Dictionary = ledger_proj["deliverable_amounts"] as Dictionary
	var after_cargo: Dictionary = ledger_proj["after_cargo"] as Dictionary
	var after_weight: int = int(ledger_proj["after_weight"])
	var debit_ops_by_lot: Dictionary = ledger_proj["debit_ops_by_lot"] as Dictionary

	var physical_proj := _project_camp_deposit_and_reservations_pure(
		storage,
		camp_zone,
		ordered_piles,
		selected_entries,
		deliverable_amounts,
		site_contexts,
		camp_physical_before,
		camp_reserved_before,
		camp_free_before,
		op,
		normalized_request,
		blocked_lots
	)
	if not bool(physical_proj.get("ok", false)):
		return physical_proj

	var selected_lots_out: Array[Dictionary] = []
	var dest_by_lot: Dictionary = {}
	var dest_free_by_res: Dictionary = {}
	var dest_reserved_by_site: Dictionary = {}
	var physical_targets_by_lot: Dictionary = physical_proj["physical_targets_by_lot"] as Dictionary

	for entry: Dictionary in selected_entries:
		var lid: StringName = entry["lot_id"] as StringName
		var res_id: StringName = entry["resource_id"] as StringName
		var origin: StringName = entry["origin"] as StringName
		var sid: StringName = entry["site_id"] as StringName
		var gen: int = int(entry["generation"])
		var rid: StringName = entry["reservation_id"] as StringName
		var orig_qty: int = int(entry["original_quantity"])
		var sel_qty: int = int(entry["selected_quantity"])
		var dest_cls: StringName = entry["destination_class"] as StringName
		var targets: Array[Dictionary] = physical_targets_by_lot.get(lid, []) as Array[Dictionary]
		selected_lots_out.append({
			"lot_id": lid,
			"unit_id": unit_id,
			"resource_id": res_id,
			"origin": origin,
			"site_id": sid,
			"generation": gen,
			"reservation_id": rid,
			"unit_weight": int(cargo_weights[res_id]),
			"original_quantity": orig_qty,
			"selected_quantity": sel_qty,
			"residual_quantity": orig_qty - sel_qty,
			"destination_class": dest_cls,
			"debit_operation_id": debit_ops_by_lot[lid] as StringName,
			"physical_targets": targets,
		})
		dest_by_lot[lid] = dest_cls
		if dest_cls == DEST_CAMP_FREE_STOCK:
			dest_free_by_res[res_id] = int(dest_free_by_res.get(res_id, 0)) + sel_qty
		else:
			if not dest_reserved_by_site.has(sid):
				dest_reserved_by_site[sid] = {}
			var site_map: Dictionary = dest_reserved_by_site[sid] as Dictionary
			site_map[res_id] = int(site_map.get(res_id, 0)) + sel_qty

	var dest_by_class: Dictionary = {}
	if not dest_free_by_res.is_empty():
		dest_by_class[DEST_CAMP_FREE_STOCK] = _sort_dict_by_string_key(dest_free_by_res)
	if not dest_reserved_by_site.is_empty():
		var sorted_site_dest: Dictionary = {}
		var sids := _sorted_string_names(dest_reserved_by_site.keys())
		for sid: StringName in sids:
			sorted_site_dest[sid] = _sort_dict_by_string_key(dest_reserved_by_site[sid] as Dictionary)
		dest_by_class[DEST_SITE_RESERVED_RESTORATION] = sorted_site_dest

	var involved_sites_identity: Dictionary = {}
	var before_sites: Dictionary = {}
	var after_sites: Dictionary = {}
	var site_deltas_by_id: Dictionary = physical_proj["site_deltas_by_id"] as Dictionary
	var involved_site_ids := _sorted_string_names(site_deltas_by_id.keys())
	for sid: StringName in involved_site_ids:
		var ctx: Dictionary = site_contexts[sid] as Dictionary
		var site: ConstructionSite = ctx["site"] as ConstructionSite
		involved_sites_identity[sid] = {
			"site": site.get_instance_id(),
			"site_id": site.site_id,
			"generation": site.get_generation(),
			"reservation_id": site.reservation_id,
			"region_id": site.region_id,
			"world": site.get_world_3d().get_instance_id(),
		}
		var delta_info: Dictionary = site_deltas_by_id[sid] as Dictionary
		before_sites[sid] = delta_info["before"]
		after_sites[sid] = delta_info["after"]

	var camp_config_rev: Dictionary = {
		"zone_id": camp_zone.zone_id,
		"config_revision": camp_zone.get_config_revision(),
		"anchor": camp_zone.get_anchor_position(),
		"half_extents": camp_zone.zone_bounds_half_extents,
		"slot_spacing": camp_zone.slot_spacing,
		"min_pile_clearance": camp_zone.min_pile_clearance,
		"max_pile_amount": camp_zone.max_pile_amount,
		"decay_multiplier": camp_zone.decay_multiplier,
		"max_nav_snap_distance": camp_zone.max_nav_snap_distance,
		"merge_exposure_policy": int(storage.merge_exposure_policy),
		"piles_root_global_pos": storage._piles_root.global_position,
		"nav_instance_id": nav.get_instance_id() if nav != null else 0,
		"nav_ready": nav.is_navigation_ready() if nav != null else false,
		"nav_revision": nav.get_navigation_revision() if nav != null else 0,
		"has_custom_validator": _has_untrusted_custom_position_validator(camp_zone),
	}

	return {
		"ok": true,
		"reason": "",
		"dependency": "",
		"dry_run_only": true,
		"commit_supported": false,
		"physical_delivery_authorized": false,
		"validation_scope": VALIDATION_SCOPE,
		"operation_id": op,
		"identity": {
			"world": world.get_instance_id(),
			"region_id": region,
			"inventory": inventory.get_instance_id(),
			"storage": storage.get_instance_id(),
			"camp_zone": camp_zone.get_instance_id(),
			"camp_zone_id": camp_zone.zone_id,
			"piles_root": storage._piles_root.get_instance_id(),
			"unit": unit.get_instance_id(),
			"unit_id": unit_id,
			"load": load.get_instance_id(),
			"sites": involved_sites_identity,
		},
		"requested_lots": normalized_request,
		"selected_lots": selected_lots_out,
		"deliverable_amounts": deliverable_amounts,
		"destination_classes": {
			"by_lot": dest_by_lot,
			"by_class": dest_by_class,
		},
		"before": {
			"cargo": cargo,
			"weight": before_weight,
			"capacity": load.get_effective_capacity(),
			"camp_physical_amounts": camp_physical_before,
			"camp_reserved_amounts": camp_reserved_before,
			"camp_free_amounts": camp_free_before,
			"sites": before_sites,
		},
		"after": {
			"cargo": after_cargo,
			"weight": after_weight,
			"capacity": load.get_effective_capacity(),
			"camp_physical_amounts": physical_proj["camp_physical_after"],
			"camp_reserved_amounts": physical_proj["camp_reserved_after"],
			"camp_free_amounts": physical_proj["camp_free_after"],
			"sites": after_sites,
		},
		"deposit_projection": physical_proj["deposit_projection"],
		"reservation_projection": physical_proj["reservation_projection"],
		"blocked_lots": blocked_lots,
		"revisions": {
			"load": load.get_transaction_revision(),
			"inventory": inventory.get_transaction_revision(),
			"storage": storage.get_transaction_revision(),
			"pile_ledger": storage.get_pile_ledger_revision(),
			"next_pile_id": storage._next_pile_id,
			"piles": pile_revisions,
			"sites": site_revisions,
			"camp_config": camp_config_rev,
			"ledger_operation_count": cargo_ops.size(),
			"ledger_used_lot_count": (cargo_ledger.get("used_lots", {}) as Dictionary).size(),
		},
	}


## Validates a previously prepared selective camp delivery plan against live state.
## Independently recomputes the plan and rejects stale revisions, identity drift, or tampering.
static func validate_selective_camp_delivery_plan(
	inventory: SettlementInventory,
	camp_zone: CampStorageZone,
	unit: Unit,
	region_id: Variant,
	plan: Variant
) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _reject("wrong_thread", "thread")
	var shape := _validate_plan_shape(plan)
	if not bool(shape.get("ok", false)):
		return shape
	var typed_plan: Dictionary = plan as Dictionary
	var op: StringName = typed_plan["operation_id"] as StringName
	var req_lots: Array = typed_plan["requested_lots"] as Array
	var fresh := prepare_selective_camp_delivery(inventory, camp_zone, unit, region_id, op, req_lots)
	var comparison := _compare_plan(fresh, typed_plan)
	if not bool(comparison.get("ok", false)):
		return comparison
	return {
		"ok": true,
		"reason": "",
		"dependency": "",
		"dry_run_only": true,
		"commit_supported": false,
		"physical_delivery_authorized": false,
		"validation_scope": VALIDATION_SCOPE,
	}


static func _validate_plan_shape(plan: Variant) -> Dictionary:
	if typeof(plan) != TYPE_DICTIONARY:
		return _reject("invalid_plan", "plan")
	var p: Dictionary = plan as Dictionary
	if p.size() != 19:
		return _reject("invalid_plan", "plan")
	if not (p.get("ok") is bool and bool(p["ok"])):
		return _reject("invalid_plan", "plan")
	if not (p.get("reason") is String and String(p["reason"]).is_empty()):
		return _reject("invalid_plan", "plan")
	if not (p.get("dependency") is String and String(p["dependency"]).is_empty()):
		return _reject("invalid_plan", "plan")
	if not (p.get("dry_run_only") is bool and bool(p["dry_run_only"])):
		return _reject("invalid_plan", "plan")
	if not (p.get("commit_supported") is bool and not bool(p["commit_supported"])):
		return _reject("invalid_plan", "plan")
	if not (p.get("physical_delivery_authorized") is bool and not bool(p["physical_delivery_authorized"])):
		return _reject("invalid_plan", "plan")
	if not (p.get("validation_scope") is String and String(p["validation_scope"]) == VALIDATION_SCOPE):
		return _reject("invalid_plan", "plan")
	if typeof(p.get("operation_id")) != TYPE_STRING_NAME or not CarryProvenanceLedger._id(p.get("operation_id")):
		return _reject("invalid_plan", "plan")
	for array_key: String in ["requested_lots", "selected_lots", "blocked_lots"]:
		if typeof(p.get(array_key)) != TYPE_ARRAY:
			return _reject("invalid_plan", "plan")
	for dict_key: String in [
		"identity", "deliverable_amounts", "destination_classes",
		"before", "after", "deposit_projection", "reservation_projection", "revisions"
	]:
		if typeof(p.get(dict_key)) != TYPE_DICTIONARY:
			return _reject("invalid_plan", "plan")
	var parsed := _parse_lot_request(p["requested_lots"], p["operation_id"] as StringName)
	if not bool(parsed.get("ok", false)):
		return _reject("invalid_plan", "plan")
	return {"ok": true}


static func _compare_plan(fresh: Dictionary, plan: Dictionary) -> Dictionary:
	if not bool(fresh.get("ok", false)):
		return fresh
	var op: StringName = plan["operation_id"] as StringName
	if not _strict_equal(fresh["identity"], plan["identity"]):
		return _reject("identity_mismatch", "plan", op)
	if not _strict_equal(fresh["revisions"], plan["revisions"]):
		return _reject("stale_revision", "plan", op)
	if not _strict_equal(fresh, plan):
		return _reject("tampered_or_stale_plan", "plan", op)
	return {"ok": true}


static func _parse_lot_request(input: Variant, op: StringName) -> Dictionary:
	if typeof(input) != TYPE_ARRAY:
		return _reject("invalid_request", "request", op)
	var arr: Array = input as Array
	var by_lot: Dictionary = {}
	for raw_item: Variant in arr:
		if typeof(raw_item) != TYPE_DICTIONARY:
			return _reject("invalid_request", "request", op)
		var item: Dictionary = raw_item as Dictionary
		if item.size() != 2 or not item.has("lot_id") or not item.has("amount"):
			return _reject("invalid_request", "request", op)
		var raw_lot_id: Variant = item["lot_id"]
		var raw_amount: Variant = item["amount"]
		if not CarryProvenanceLedger._id(raw_lot_id):
			return _reject("invalid_request", "request", op)
		if typeof(raw_amount) != TYPE_INT or int(raw_amount) <= 0:
			return _reject("invalid_request", "request", op)
		var lot_id := StringName(raw_lot_id)
		if by_lot.has(lot_id):
			return _reject("duplicate_lot_request", "request", op)
		by_lot[lot_id] = int(raw_amount)

	var sorted_ids := _sorted_string_names(by_lot.keys())
	var normalized: Array[Dictionary] = []
	for lot_id: StringName in sorted_ids:
		normalized.append({"lot_id": lot_id, "amount": int(by_lot[lot_id])})
	return {"ok": true, "requests": normalized}


static func _scan_sites_pure(
	tree: SceneTree,
	world: World3D,
	region: StringName,
	unit: Unit,
	load: UnitCarryLoad,
	op: StringName,
	normalized_request: Array[Dictionary],
	scope: ReservedWithdrawalCoordinator.CampDeliveryScope = null
) -> Dictionary:
	var domain_sites: Array[ConstructionSite] = []
	var domain_sites_by_id: Dictionary = {}
	var duplicate_site_ids: Dictionary = {}
	var reservation_owner_by_id: Dictionary = {}
	var duplicate_reservation_ids: Dictionary = {}
	var other_region_site_ids: Dictionary = {}
	var other_world_site_ids: Dictionary = {}
	var site_revisions_unsorted: Dictionary = {}
	var target_prov_id: StringName = load.get_provenance_unit_id()

	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		if not (node is ConstructionSite):
			continue
		var site: ConstructionSite = node as ConstructionSite
		if not is_instance_valid(site) or not site.is_inside_tree():
			continue
		var site_world := site.get_world_3d()
		if site_world != world:
			if CarryProvenanceLedger._id(site.site_id):
				other_world_site_ids[site.site_id] = true
			continue
		if site.region_id != region:
			if CarryProvenanceLedger._id(site.site_id):
				other_region_site_ids[site.site_id] = true
			continue

		if scope == null:
			if site.is_transaction_busy():
				return _reject("busy", "site", op, normalized_request)
		else:
			if not scope.sites.has(site) or not site._is_preparing_or_transacting or site._work_transaction_in_progress or site._is_complementing:
				return _reject("busy", "site", op, normalized_request)
		domain_sites.append(site)

		if CarryProvenanceLedger._id(site.site_id):
			if domain_sites_by_id.has(site.site_id):
				duplicate_site_ids[site.site_id] = true
			else:
				domain_sites_by_id[site.site_id] = site
			site_revisions_unsorted[site.site_id] = {
				"instance_id": site.get_instance_id(),
				"generation": site.get_generation(),
				"state": int(site.get_site_state()),
				"revision": site.get_transaction_revision(),
				"work_serial": site._work_cycle_serial,
			}

		if site.is_valid() and CarryProvenanceLedger._id(site.reservation_id):
			if reservation_owner_by_id.has(site.reservation_id):
				duplicate_reservation_ids[site.reservation_id] = true
			else:
				reservation_owner_by_id[site.reservation_id] = site.site_id

	for site: ConstructionSite in domain_sites:
		for uid_key: Variant in site._assigned_workers.keys():
			var w: Dictionary = site._assigned_workers[uid_key] as Dictionary
			var other_u: Unit = w.get("unit") as Unit
			if ConstructionSite._unit_conflicts_with_target(other_u, unit, load, target_prov_id):
				return _reject("ambiguous_unit_identity", "unit", op, normalized_request)
		for uid_key: Variant in site._transit_claims.keys():
			var c: Dictionary = site._transit_claims[uid_key] as Dictionary
			var other_u: Unit = c.get("unit") as Unit
			if ConstructionSite._unit_conflicts_with_target(other_u, unit, load, target_prov_id):
				return _reject("ambiguous_unit_identity", "unit", op, normalized_request)
		for uid_key: Variant in site._pending_pickups.keys():
			var p: Dictionary = site._pending_pickups[uid_key] as Dictionary
			var other_u: Unit = p.get("unit") as Unit
			if ConstructionSite._unit_conflicts_with_target(other_u, unit, load, target_prov_id):
				return _reject("ambiguous_unit_identity", "unit", op, normalized_request)

	var site_revisions: Dictionary = {}
	for sid: StringName in _sorted_string_names(site_revisions_unsorted.keys()):
		site_revisions[sid] = site_revisions_unsorted[sid]

	return {
		"ok": true,
		"domain_sites_by_id": domain_sites_by_id,
		"duplicate_site_ids": duplicate_site_ids,
		"duplicate_reservation_ids": duplicate_reservation_ids,
		"other_region_site_ids": other_region_site_ids,
		"other_world_site_ids": other_world_site_ids,
		"site_revisions": site_revisions,
	}


static func _measure_cargo(
	amounts: Dictionary,
	weights: Dictionary,
	storage: GroundPileManager,
	op: StringName,
	normalized_request: Array[Dictionary]
) -> Dictionary:
	var total: int = 0
	if amounts.size() != weights.size():
		return _reject("resource_or_weight_mismatch", "carry_load", op, normalized_request)
	for resource: Variant in amounts:
		if not CarryProvenanceLedger._id(resource) or typeof(amounts[resource]) != TYPE_INT or int(amounts[resource]) <= 0:
			return _reject("unreconciled_cargo", "carry_load", op, normalized_request)
		var res_sn := StringName(resource)
		var definition := storage.get_resource_definition_pure(res_sn)
		var weight: Variant = weights.get(resource)
		if definition == null or typeof(weight) != TYPE_INT or int(weight) != definition.unit_weight or int(weight) <= 0:
			return _reject("resource_or_weight_mismatch", "carry_load", op, normalized_request)
		var qty: int = int(amounts[resource])
		@warning_ignore("integer_division")
		if int(weight) > (CarryProvenanceLedger.MAX_INT - total) / qty:
			return _reject("weight_overflow", "carry_load", op, normalized_request)
		total += int(weight) * qty
	return {"ok": true, "value": total}


static func _has_untrusted_custom_position_validator(camp_zone: CampStorageZone) -> bool:
	var validator: Callable = camp_zone._custom_position_validator
	return validator.is_valid() or not validator.is_null()


static func _inspect_storage_state_pure(
	storage: GroundPileManager,
	world: World3D,
	op: StringName,
	normalized_request: Array[Dictionary]
) -> Dictionary:
	if storage._next_pile_id <= 0:
		return _reject("invalid_physical_pile_collection", "storage", op, normalized_request)

	# Inspect the raw internal `_piles` array directly (never via `get_piles()`, which silently skips
	# invalid references) without pruning, erasing, or modifying the underlying collection.
	var ordered_piles: Array[GroundResourcePile] = []
	var seen_instances: Dictionary = {}
	for raw_entry: Variant in storage._piles:
		if raw_entry == null or not is_instance_valid(raw_entry) or not (raw_entry is GroundResourcePile):
			return _reject("invalid_physical_pile_collection", "storage", op, normalized_request)
		var raw_pile: GroundResourcePile = raw_entry as GroundResourcePile
		if (
			raw_pile.is_queued_for_deletion()
			or not raw_pile.is_valid()
			or not raw_pile.is_inside_tree()
			or raw_pile.get_parent() != storage._piles_root
			or raw_pile.pile_id <= 0
			or raw_pile.pile_id >= storage._next_pile_id
		):
			return _reject("invalid_physical_pile_collection", "storage", op, normalized_request)
		var owner_ref: Object = raw_pile._storage_owner.get_ref() if raw_pile._storage_owner != null else null
		if owner_ref != storage:
			return _reject("invalid_physical_pile_collection", "storage", op, normalized_request)
		var inst_id: int = raw_pile.get_instance_id()
		if seen_instances.has(inst_id):
			return _reject("invalid_physical_pile_collection", "storage", op, normalized_request)
		seen_instances[inst_id] = true
		ordered_piles.append(raw_pile)
	ordered_piles.sort_custom(func(a: GroundResourcePile, b: GroundResourcePile) -> bool: return a.pile_id < b.pile_id)

	var pile_by_id: Dictionary = {}
	var physical_unsorted: Dictionary = {}
	var reserved_unsorted: Dictionary = {}
	var pile_revisions: Dictionary = {}

	for pile: GroundResourcePile in ordered_piles:
		if pile.get_world_3d() != world:
			return _reject("world_mismatch", "storage", op, normalized_request)
		if pile_by_id.has(pile.pile_id):
			return _reject("invalid_physical_pile_collection", "storage", op, normalized_request)
		var def := storage.get_resource_definition_pure(pile.resource_id)
		if def == null or def.unit_weight != pile.definition.unit_weight:
			return _reject("resource_or_weight_mismatch", "storage", op, normalized_request)

		var pile_res_map := storage.get_pile_reservations(pile.pile_id)
		var pile_reserved: int = 0
		for rid_key: Variant in pile_res_map.keys():
			var r_amt: Variant = pile_res_map[rid_key]
			if not CarryProvenanceLedger._id(rid_key) or typeof(r_amt) != TYPE_INT or int(r_amt) <= 0:
				return _reject("reservation_restoration_unavailable", "reservations", op, normalized_request)
			if int(r_amt) > CarryProvenanceLedger.MAX_INT - pile_reserved:
				return _reject("amount_overflow", "reservations", op, normalized_request)
			pile_reserved += int(r_amt)
		if pile_reserved > pile.amount:
			return _reject("reservation_restoration_unavailable", "reservations", op, normalized_request)

		pile_by_id[pile.pile_id] = pile
		var prev_phys: int = int(physical_unsorted.get(pile.resource_id, 0))
		if pile.amount > CarryProvenanceLedger.MAX_INT - prev_phys:
			return _reject("amount_overflow", "storage", op, normalized_request)
		physical_unsorted[pile.resource_id] = prev_phys + pile.amount
		if pile_reserved > 0:
			var prev_res: int = int(reserved_unsorted.get(pile.resource_id, 0))
			if pile_reserved > CarryProvenanceLedger.MAX_INT - prev_res:
				return _reject("amount_overflow", "reservations", op, normalized_request)
			reserved_unsorted[pile.resource_id] = prev_res + pile_reserved

		pile_revisions[pile.pile_id] = {
			"instance_id": pile.get_instance_id(),
			"revision": pile.get_transaction_revision(),
			"resource_id": pile.resource_id,
			"amount": pile.amount,
			"position": pile.position,
			"world_pos": storage.get_pile_world_position(pile),
			"elapsed": pile.elapsed_exposure_sec,
			"accum": pile.decay_accumulator_sec,
			"reserved": pile_reserved,
		}

	var ledger_snap: Dictionary = storage._ledger.snapshot_state()
	var by_pile: Dictionary = ledger_snap.get("by_pile", {}) as Dictionary
	for pid_key: Variant in by_pile.keys():
		if typeof(pid_key) != TYPE_INT or not pile_by_id.has(int(pid_key)):
			return _reject("reservation_restoration_unavailable", "reservations", op, normalized_request)
		var pile: GroundResourcePile = pile_by_id[int(pid_key)] as GroundResourcePile
		var entry: Dictionary = by_pile[pid_key] as Dictionary
		if StringName(entry.get("resource_id", &"")) != pile.resource_id:
			return _reject("reservation_restoration_unavailable", "reservations", op, normalized_request)

	var physical_amounts := _sort_dict_by_string_key(physical_unsorted)
	var reserved_amounts := _sort_dict_by_string_key(reserved_unsorted)
	var free_unsorted: Dictionary = {}
	for res_id: StringName in physical_amounts.keys():
		var free_val: int = int(physical_amounts[res_id]) - int(reserved_amounts.get(res_id, 0))
		if free_val < 0:
			return _reject("reservation_restoration_unavailable", "reservations", op, normalized_request)
		if free_val > 0:
			free_unsorted[res_id] = free_val
	var free_amounts := _sort_dict_by_string_key(free_unsorted)

	return {
		"ok": true,
		"ordered_piles": ordered_piles,
		"physical_amounts": physical_amounts,
		"reserved_amounts": reserved_amounts,
		"free_amounts": free_amounts,
		"pile_revisions": pile_revisions,
	}


static func _classify_lots_pure(
	cargo_lots: Dictionary,
	cargo_weights: Dictionary,
	unit: Unit,
	load: UnitCarryLoad,
	storage: GroundPileManager,
	domain_sites_by_id: Dictionary,
	duplicate_site_ids: Dictionary,
	duplicate_reservation_ids: Dictionary,
	other_region_site_ids: Dictionary,
	other_world_site_ids: Dictionary
) -> Dictionary:
	var uid: int = unit.get_instance_id()
	var site_lot_totals: Dictionary = {}
	var site_lot_generations: Dictionary = {}

	for lot_key: Variant in cargo_lots.keys():
		var lot: Dictionary = cargo_lots[lot_key] as Dictionary
		var origin: StringName = StringName(lot.get("origin", &""))
		if origin != CarryProvenanceLedger.SITE_RESERVED:
			continue
		var sid: StringName = StringName(lot.get("site_id", &""))
		var res_id: StringName = StringName(lot.get("resource_id", &""))
		var gen: int = int(lot.get("generation", 0))
		var qty: int = int(lot.get("quantity", 0))
		if not site_lot_totals.has(sid):
			site_lot_totals[sid] = {}
		var res_map: Dictionary = site_lot_totals[sid] as Dictionary
		res_map[res_id] = int(res_map.get(res_id, 0)) + qty
		if not site_lot_generations.has(sid):
			site_lot_generations[sid] = {}
		(site_lot_generations[sid] as Dictionary)[gen] = true

	var site_contexts: Dictionary = {}
	for sid: StringName in _sorted_string_names(site_lot_totals.keys()):
		if duplicate_site_ids.has(sid):
			site_contexts[sid] = {"eligible": false, "reason": "conflicting_site_claims", "dependency": "site"}
			continue
		if not domain_sites_by_id.has(sid):
			if other_region_site_ids.has(sid):
				site_contexts[sid] = {"eligible": false, "reason": "region_mismatch", "dependency": "site"}
			elif other_world_site_ids.has(sid):
				site_contexts[sid] = {"eligible": false, "reason": "world_mismatch", "dependency": "site"}
			else:
				site_contexts[sid] = {"eligible": false, "reason": "unknown_reserved_site", "dependency": "site"}
			continue

		var site: ConstructionSite = domain_sites_by_id[sid] as ConstructionSite
		if not site.is_valid() or site.get_generation() <= 0 or site.get_site_state() == ConstructionSite.SiteState.UNCONFIGURED or not CarryProvenanceLedger._id(site.reservation_id):
			site_contexts[sid] = {"eligible": false, "reason": "invalid_site", "dependency": "site"}
			continue
		if site.get_site_state() != ConstructionSite.SiteState.ACTIVE:
			site_contexts[sid] = {"eligible": false, "reason": "d3_cancellation_not_implemented", "dependency": "cancellation_d3"}
			continue
		if duplicate_reservation_ids.has(site.reservation_id):
			site_contexts[sid] = {"eligible": false, "reason": "reservation_restoration_unavailable", "dependency": "reservations"}
			continue
		if (site_lot_generations[sid] as Dictionary).size() > 1:
			site_contexts[sid] = {"eligible": false, "reason": "generation_mismatch", "dependency": "site"}
			continue

		var claim_entry_ok: bool = true
		var claim_entry_reason: String = ""
		var claim_entry_dep: String = "claims"
		if not site._transit_claims.has(uid):
			claim_entry_ok = false
			claim_entry_reason = "insufficient_transit_claim"
		else:
			var raw_claim: Dictionary = site._transit_claims[uid] as Dictionary
			var claim_unit: Unit = raw_claim.get("unit") as Unit
			var claim_load: UnitCarryLoad = raw_claim.get("carry_load") as UnitCarryLoad
			if claim_unit != unit or claim_load != load:
				claim_entry_ok = false
				claim_entry_reason = "carry_load_mismatch"
				claim_entry_dep = "carry_load"

		var accounts: Dictionary = SelectiveSiteDeliveryPlanner._read_accounting(site)
		var claim_amounts: Dictionary = site._read_transit_claim_for_unit_pure(uid)
		var site_res_before: Dictionary = _sort_dict_by_string_key(storage.get_reservation_amounts(site.reservation_id))

		site_contexts[sid] = {
			"eligible": claim_entry_ok and bool(accounts.get("ok", false)),
			"reason": claim_entry_reason if not claim_entry_ok else String(accounts.get("reason", "")),
			"dependency": claim_entry_dep if not claim_entry_ok else String(accounts.get("dependency", "accounting")),
			"site": site,
			"claim": claim_amounts,
			"accounting": accounts.get("by_resource", {}),
			"reservation_amounts": site_res_before,
			"site_lot_totals": site_lot_totals[sid],
		}

	var lot_info_by_id: Dictionary = {}
	for lot_key: Variant in cargo_lots.keys():
		var lot: Dictionary = cargo_lots[lot_key] as Dictionary
		var lid: StringName = StringName(lot["lot_id"])
		var res_id: StringName = StringName(lot["resource_id"])
		var origin: StringName = StringName(lot["origin"])
		var sid: StringName = StringName(lot["site_id"])
		var gen: int = int(lot["generation"])
		var qty: int = int(lot["quantity"])

		if origin == CarryProvenanceLedger.FREE_GATHERED:
			lot_info_by_id[lid] = {
				"lot_id": lid,
				"resource_id": res_id,
				"origin": origin,
				"site_id": &"",
				"generation": 0,
				"reservation_id": &"",
				"quantity": qty,
				"eligible": true,
				"destination_class": DEST_CAMP_FREE_STOCK,
				"reason": "",
				"dependency": "",
			}
			continue

		if origin != CarryProvenanceLedger.SITE_RESERVED:
			lot_info_by_id[lid] = {
				"lot_id": lid,
				"resource_id": res_id,
				"origin": origin,
				"site_id": sid,
				"generation": gen,
				"reservation_id": &"",
				"quantity": qty,
				"eligible": false,
				"destination_class": &"",
				"reason": "unsupported_origin",
				"dependency": "provenance_ledger",
			}
			continue

		var ctx: Dictionary = site_contexts[sid] as Dictionary
		if not ctx.has("site"):
			lot_info_by_id[lid] = _blocked_lot_info(lot, String(ctx["reason"]), String(ctx["dependency"]))
			continue

		var site: ConstructionSite = ctx["site"] as ConstructionSite
		if site.get_generation() != gen:
			lot_info_by_id[lid] = _blocked_lot_info(lot, "generation_mismatch", "site")
			continue
		if not bool(ctx["eligible"]):
			lot_info_by_id[lid] = _blocked_lot_info(lot, String(ctx["reason"]), String(ctx["dependency"]))
			continue

		var accounting: Dictionary = ctx["accounting"] as Dictionary
		if not accounting.has(res_id):
			lot_info_by_id[lid] = _blocked_lot_info(lot, "resource_not_required", "site")
			continue
		var site_def := site._resolve_resource_definition_pure(res_id)
		if site_def == null or not site_def.is_valid() or site_def.unit_weight != int(cargo_weights[res_id]):
			lot_info_by_id[lid] = _blocked_lot_info(lot, "resource_or_weight_mismatch", "site")
			continue

		var claim_map: Dictionary = ctx["claim"] as Dictionary
		var claimed_for_res: int = int(claim_map.get(res_id, 0))
		var total_site_lots_for_res: int = int((ctx["site_lot_totals"] as Dictionary).get(res_id, 0))
		if claimed_for_res < total_site_lots_for_res:
			lot_info_by_id[lid] = _blocked_lot_info(lot, "insufficient_transit_claim", "claims")
			continue
		if claimed_for_res != total_site_lots_for_res:
			lot_info_by_id[lid] = _blocked_lot_info(lot, "unreconciled_site_claim", "claims")
			continue

		lot_info_by_id[lid] = {
			"lot_id": lid,
			"resource_id": res_id,
			"origin": origin,
			"site_id": sid,
			"generation": gen,
			"reservation_id": site.reservation_id,
			"quantity": qty,
			"eligible": true,
			"destination_class": DEST_SITE_RESERVED_RESTORATION,
			"reason": "",
			"dependency": "",
		}

	return {
		"lot_info_by_id": lot_info_by_id,
		"site_contexts": site_contexts,
	}


static func _blocked_lot_info(lot: Dictionary, reason: String, dependency: String) -> Dictionary:
	return {
		"lot_id": StringName(lot["lot_id"]),
		"resource_id": StringName(lot["resource_id"]),
		"origin": StringName(lot["origin"]),
		"site_id": StringName(lot["site_id"]),
		"generation": int(lot["generation"]),
		"reservation_id": &"",
		"quantity": int(lot["quantity"]),
		"eligible": false,
		"destination_class": &"",
		"reason": reason,
		"dependency": dependency,
	}


static func _resolve_selection_pure(
	normalized_request: Array[Dictionary],
	cargo_lots: Dictionary,
	lot_info_by_id: Dictionary,
	op: StringName
) -> Dictionary:
	var selected_entries: Array[Dictionary] = []
	var blocked_lots: Array[Dictionary] = []

	if normalized_request.is_empty():
		var sorted_all := _sort_lot_infos(lot_info_by_id.values())
		for info: Dictionary in sorted_all:
			var origin: StringName = info["origin"] as StringName
			if origin == CarryProvenanceLedger.FREE_GATHERED and bool(info["eligible"]):
				selected_entries.append({
					"lot_id": info["lot_id"],
					"resource_id": info["resource_id"],
					"origin": origin,
					"site_id": &"",
					"generation": 0,
					"reservation_id": &"",
					"original_quantity": int(info["quantity"]),
					"selected_quantity": int(info["quantity"]),
					"destination_class": DEST_CAMP_FREE_STOCK,
				})
			else:
				var blk_reason: String = "explicit_selection_required" if bool(info["eligible"]) else String(info["reason"])
				var blk_dep: String = "selection_policy" if bool(info["eligible"]) else String(info["dependency"])
				var raw_lot: Dictionary = cargo_lots[info["lot_id"]] as Dictionary
				blocked_lots.append(_make_blocked_entry(raw_lot, blk_reason, blk_dep))
		if selected_entries.is_empty():
			return _reject("no_eligible_free_lots", "selection", op, normalized_request, blocked_lots)
		return {"ok": true, "selected_entries": selected_entries, "blocked_lots": blocked_lots}

	var requested_ids: Dictionary = {}
	var first_block_reason: String = ""
	var first_block_dep: String = ""
	var failed_blocked: Array[Dictionary] = []

	for req: Dictionary in normalized_request:
		var lid: StringName = req["lot_id"] as StringName
		var req_amt: int = int(req["amount"])
		requested_ids[lid] = true
		if not lot_info_by_id.has(lid):
			return _reject("lot_not_found", "request", op, normalized_request)
		var info: Dictionary = lot_info_by_id[lid] as Dictionary
		if req_amt > int(info["quantity"]):
			return _reject("requested_amount_exceeds_lot", "request", op, normalized_request)
		if not bool(info["eligible"]):
			var raw_lot: Dictionary = cargo_lots[lid] as Dictionary
			failed_blocked.append(_make_blocked_entry(raw_lot, String(info["reason"]), String(info["dependency"])))
			if first_block_reason.is_empty():
				first_block_reason = String(info["reason"])
				first_block_dep = String(info["dependency"])
			continue
		selected_entries.append({
			"lot_id": lid,
			"resource_id": info["resource_id"],
			"origin": info["origin"],
			"site_id": info["site_id"],
			"generation": int(info["generation"]),
			"reservation_id": info["reservation_id"],
			"original_quantity": int(info["quantity"]),
			"selected_quantity": req_amt,
			"destination_class": info["destination_class"],
		})

	if not first_block_reason.is_empty():
		failed_blocked.sort_custom(_sort_lot_dict_by_res_and_id)
		return _reject(first_block_reason, first_block_dep, op, normalized_request, failed_blocked)

	for info: Dictionary in _sort_lot_infos(lot_info_by_id.values()):
		var lid: StringName = info["lot_id"] as StringName
		if requested_ids.has(lid):
			continue
		if not bool(info["eligible"]):
			var raw_lot: Dictionary = cargo_lots[lid] as Dictionary
			blocked_lots.append(_make_blocked_entry(raw_lot, String(info["reason"]), String(info["dependency"])))

	selected_entries.sort_custom(_sort_lot_dict_by_res_and_id)
	blocked_lots.sort_custom(_sort_lot_dict_by_res_and_id)
	return {"ok": true, "selected_entries": selected_entries, "blocked_lots": blocked_lots}


static func _make_blocked_entry(raw_lot: Dictionary, reason: String, dependency: String) -> Dictionary:
	return {
		"lot_id": StringName(raw_lot["lot_id"]),
		"unit_id": StringName(raw_lot["unit_id"]),
		"resource_id": StringName(raw_lot["resource_id"]),
		"origin": StringName(raw_lot["origin"]),
		"site_id": StringName(raw_lot["site_id"]),
		"generation": int(raw_lot["generation"]),
		"quantity": int(raw_lot["quantity"]),
		"reason": reason,
		"dependency": dependency,
	}


static func _simulate_ledger_debits_pure(
	cargo: Dictionary,
	ledger: CarryProvenanceLedger,
	selected_entries: Array[Dictionary],
	storage: GroundPileManager,
	op: StringName,
	normalized_request: Array[Dictionary],
	blocked_lots: Array[Dictionary]
) -> Dictionary:
	var after_amounts: Dictionary = (cargo["amounts"] as Dictionary).duplicate()
	var after_weights: Dictionary = (cargo["weights"] as Dictionary).duplicate()
	var unit_id: StringName = StringName(cargo["unit_id"])
	var deliverable_unsorted: Dictionary = {}
	var debit_ops_by_lot: Dictionary = {}

	for idx: int in range(selected_entries.size()):
		var entry: Dictionary = selected_entries[idx]
		var lid: StringName = entry["lot_id"] as StringName
		var res_id: StringName = entry["resource_id"] as StringName
		var qty: int = int(entry["selected_quantity"])

		var base_id: String = "c3.4.1:%d:%s:%d" % [String(op).length(), String(op), idx]
		var debit_op := StringName(base_id)
		var suffix: int = 0
		while ledger._operations.has(debit_op):
			suffix += 1
			debit_op = StringName("%s:%d" % [base_id, suffix])

		var withdraw_res := ledger.withdraw(debit_op, lid, qty)
		if not bool(withdraw_res.get("ok", false)) or bool(withdraw_res.get("replayed", false)):
			return _reject("lot_debit_conflict", "provenance_ledger", op, normalized_request, blocked_lots)
		debit_ops_by_lot[lid] = debit_op

		var prev_deliv: int = int(deliverable_unsorted.get(res_id, 0))
		if qty > CarryProvenanceLedger.MAX_INT - prev_deliv:
			return _reject("amount_overflow", "projection", op, normalized_request, blocked_lots)
		deliverable_unsorted[res_id] = prev_deliv + qty

		var rem_res: int = int(after_amounts.get(res_id, 0)) - qty
		if rem_res < 0:
			return _reject("unreconciled_projection", "carry_load", op, normalized_request, blocked_lots)
		if rem_res == 0:
			after_amounts.erase(res_id)
			after_weights.erase(res_id)
		else:
			after_amounts[res_id] = rem_res

	if not bool(ledger.validate_aggregate(unit_id, after_amounts).get("ok", false)):
		return _reject("unreconciled_projection", "carry_load", op, normalized_request, blocked_lots)

	var after_weight_check := _measure_cargo(after_amounts, after_weights, storage, op, normalized_request)
	if not bool(after_weight_check.get("ok", false)):
		return after_weight_check

	var sorted_after_amounts := _sort_dict_by_string_key(after_amounts)
	var sorted_after_weights := _sort_dict_by_string_key(after_weights)

	return {
		"ok": true,
		"deliverable_amounts": _sort_dict_by_string_key(deliverable_unsorted),
		"debit_ops_by_lot": debit_ops_by_lot,
		"after_weight": int(after_weight_check["value"]),
		"after_cargo": {
			"unit_id": unit_id,
			"amounts": sorted_after_amounts,
			"weights": sorted_after_weights,
			"ledger": ledger.snapshot_transaction_state(),
		},
	}


static func _project_camp_deposit_and_reservations_pure(
	storage: GroundPileManager,
	camp_zone: CampStorageZone,
	ordered_piles: Array[GroundResourcePile],
	selected_entries: Array[Dictionary],
	deliverable_amounts: Dictionary,
	site_contexts: Dictionary,
	camp_physical_before: Dictionary,
	camp_reserved_before: Dictionary,
	camp_free_before: Dictionary,
	op: StringName,
	normalized_request: Array[Dictionary],
	blocked_lots: Array[Dictionary]
) -> Dictionary:
	var virtual_amounts: Dictionary = {}
	var occupied: Array[Vector3] = []
	for pile: GroundResourcePile in ordered_piles:
		virtual_amounts[pile.pile_id] = pile.amount
		occupied.append(storage.get_pile_world_position(pile))

	var candidate_slots: Array[Vector3] = camp_zone.get_candidate_slots()
	var max_per_pile: int = camp_zone.max_pile_amount
	var virtual_pile_seq: int = 0

	var merges_out: Array[Dictionary] = []
	var creates_out: Array[Dictionary] = []
	var restorations_out: Array[Dictionary] = []
	var preserved_existing: Dictionary = {}
	var physical_targets_by_lot: Dictionary = {}
	var camp_physical_after_unsorted: Dictionary = camp_physical_before.duplicate()
	var camp_reserved_after_unsorted: Dictionary = camp_reserved_before.duplicate()
	var site_restored_by_site: Dictionary = {}

	var sorted_resources := _sorted_string_names(deliverable_amounts.keys())
	for res_id: StringName in sorted_resources:
		var def := storage.get_resource_definition_pure(res_id)
		if def == null or not def.is_valid():
			return _reject("resource_or_weight_mismatch", "storage", op, normalized_request, blocked_lots)
		var total_res_qty: int = int(deliverable_amounts[res_id])
		var prev_phys_total: int = int(camp_physical_after_unsorted.get(res_id, 0))
		if total_res_qty > CarryProvenanceLedger.MAX_INT - prev_phys_total:
			return _reject("amount_overflow", "storage", op, normalized_request, blocked_lots)

		# 1. Build physical chunks mirroring GroundPileManager._build_deposit_plan deterministically.
		var chunks: Array[Dictionary] = []
		var remaining: int = total_res_qty

		for pile: GroundResourcePile in ordered_piles:
			if remaining <= 0:
				break
			if pile.resource_id != res_id:
				continue
			var v_amt: int = int(virtual_amounts[pile.pile_id])
			var cap_left: int = CarryProvenanceLedger.MAX_INT - v_amt
			if max_per_pile > 0:
				cap_left = maxi(0, max_per_pile - v_amt)
			var add_here: int = mini(remaining, cap_left)
			if add_here <= 0:
				continue
			var before_res_map := _sort_dict_by_string_key(storage.get_pile_reservations(pile.pile_id))
			var before_reserved_total: int = storage.get_pile_reserved_amount(pile.pile_id)
			var world_pos := storage.get_pile_world_position(pile)
			chunks.append({
				"target_kind": &"existing_pile",
				"pile": pile,
				"pile_id": pile.pile_id,
				"pile_instance_id": pile.get_instance_id(),
				"virtual_pile_id": &"",
				"world_pos": world_pos,
				"local_pos": pile.position,
				"capacity": add_here,
				"used": 0,
				"free_added": 0,
				"reserved_added": 0,
				"before_amount": pile.amount,
				"before_reserved": before_reserved_total,
				"running_reserved": before_reserved_total,
				"before_reservations": before_res_map,
				"running_reservations": before_res_map.duplicate(),
			})
			virtual_amounts[pile.pile_id] = v_amt + add_here
			remaining -= add_here

		while remaining > 0:
			if _has_untrusted_custom_position_validator(camp_zone):
				return _reject("unsafe_custom_position_validator", "camp_zone", op, normalized_request, blocked_lots)
			var placed: bool = false
			var saw_nav_not_ready: bool = false
			for slot_world: Vector3 in candidate_slots:
				var validation: Dictionary = camp_zone.validate_pile_position(slot_world, occupied)
				if not bool(validation.get("valid", false)):
					if String(validation.get("reason", "")) == "navigation_not_ready":
						saw_nav_not_ready = true
					continue
				var resolved_world: Vector3 = validation["position"] as Vector3
				var take: int = mini(remaining, max_per_pile) if max_per_pile > 0 else remaining
				var v_id := StringName("virtual_pile:%d" % virtual_pile_seq)
				virtual_pile_seq += 1
				chunks.append({
					"target_kind": &"virtual_pile",
					"pile": null,
					"pile_id": 0,
					"pile_instance_id": 0,
					"virtual_pile_id": v_id,
					"world_pos": resolved_world,
					"local_pos": storage._world_to_piles_local(resolved_world),
					"capacity": take,
					"used": 0,
					"free_added": 0,
					"reserved_added": 0,
					"before_amount": 0,
					"before_reserved": 0,
					"running_reserved": 0,
					"before_reservations": {},
					"running_reservations": {},
				})
				occupied.append(resolved_world)
				remaining -= take
				placed = true
				break
			if not placed:
				var slot_err: String = "navigation_not_ready" if saw_nav_not_ready else "no_valid_camp_slot"
				return _reject(slot_err, "camp_zone", op, normalized_request, blocked_lots)

		# 2. Map selected lots for this resource deterministically onto the planned physical chunks.
		# SITE_RESERVED lots are allocated first (by site_id, lot_id) followed by FREE_GATHERED (by lot_id).
		var res_lots: Array[Dictionary] = []
		for entry: Dictionary in selected_entries:
			if (entry["resource_id"] as StringName) == res_id:
				res_lots.append(entry)
		res_lots.sort_custom(_sort_selected_for_chunk_allocation)

		var chunk_idx: int = 0
		var res_reserved_added: int = 0

		for entry: Dictionary in res_lots:
			var lid: StringName = entry["lot_id"] as StringName
			var lot_rem: int = int(entry["selected_quantity"])
			var origin: StringName = entry["origin"] as StringName
			var targets_for_lot: Array[Dictionary] = []

			while lot_rem > 0:
				while chunk_idx < chunks.size() and int(chunks[chunk_idx]["used"]) >= int(chunks[chunk_idx]["capacity"]):
					chunk_idx += 1
				if chunk_idx >= chunks.size():
					return _reject("reservation_restoration_unavailable", "projection", op, normalized_request, blocked_lots)
				var chunk: Dictionary = chunks[chunk_idx]
				var chunk_space: int = int(chunk["capacity"]) - int(chunk["used"])
				var slice_amt: int = mini(lot_rem, chunk_space)
				chunk["used"] = int(chunk["used"]) + slice_amt
				lot_rem -= slice_amt

				var target_kind: StringName = chunk["target_kind"] as StringName
				targets_for_lot.append({
					"target_kind": target_kind,
					"pile_id": int(chunk["pile_id"]),
					"pile_instance_id": int(chunk["pile_instance_id"]),
					"virtual_pile_id": chunk["virtual_pile_id"] as StringName,
					"amount": slice_amt,
					"world_pos": chunk["world_pos"] as Vector3,
				})

				if origin == CarryProvenanceLedger.SITE_RESERVED:
					var sid: StringName = entry["site_id"] as StringName
					var rid: StringName = entry["reservation_id"] as StringName
					var ctx: Dictionary = site_contexts[sid] as Dictionary
					var site: ConstructionSite = ctx["site"] as ConstructionSite
					var running_res_map: Dictionary = chunk["running_reservations"] as Dictionary
					var pile_res_before_step: int = int(chunk["running_reserved"])
					var site_res_before_step: int = int(running_res_map.get(rid, 0))
					var pile_res_after_step: int = pile_res_before_step + slice_amt
					var site_res_after_step: int = site_res_before_step + slice_amt
					chunk["running_reserved"] = pile_res_after_step
					chunk["reserved_added"] = int(chunk["reserved_added"]) + slice_amt
					running_res_map[rid] = site_res_after_step
					res_reserved_added += slice_amt

					if not site_restored_by_site.has(sid):
						site_restored_by_site[sid] = {}
					var sr_map: Dictionary = site_restored_by_site[sid] as Dictionary
					sr_map[res_id] = int(sr_map.get(res_id, 0)) + slice_amt

					restorations_out.append({
						"site_id": sid,
						"site_instance_id": site.get_instance_id(),
						"generation": site.get_generation(),
						"reservation_id": rid,
						"lot_id": lid,
						"resource_id": res_id,
						"amount": slice_amt,
						"target_kind": target_kind,
						"pile_id": int(chunk["pile_id"]),
						"pile_instance_id": int(chunk["pile_instance_id"]),
						"virtual_pile_id": chunk["virtual_pile_id"] as StringName,
						"target_world_pos": chunk["world_pos"] as Vector3,
						"pile_reserved_before": pile_res_before_step,
						"pile_reserved_after": pile_res_after_step,
						"site_reserved_on_pile_before": site_res_before_step,
						"site_reserved_on_pile_after": site_res_after_step,
						"ledger_mode": &"existing_pile_id" if target_kind == &"existing_pile" else &"bind_created_pile_id_on_commit",
					})
				else:
					chunk["free_added"] = int(chunk["free_added"]) + slice_amt

			physical_targets_by_lot[lid] = targets_for_lot

		# 3. Verify per-chunk conservation and emit merges/creates.
		for chunk: Dictionary in chunks:
			var cap: int = int(chunk["capacity"])
			var used: int = int(chunk["used"])
			var free_added: int = int(chunk["free_added"])
			var reserved_added: int = int(chunk["reserved_added"])
			var before_amt: int = int(chunk["before_amount"])
			var after_amt: int = before_amt + cap
			var before_res_total: int = int(chunk["before_reserved"])
			var after_res_total: int = int(chunk["running_reserved"])
			if used != cap or free_added + reserved_added != cap or after_res_total != before_res_total + reserved_added or after_res_total > after_amt:
				return _reject("reservation_restoration_unavailable", "projection", op, normalized_request, blocked_lots)

			var after_res_map := _sort_dict_by_string_key(chunk["running_reservations"] as Dictionary)
			var before_res_map: Dictionary = chunk["before_reservations"] as Dictionary
			for prev_rid: Variant in before_res_map.keys():
				if int(after_res_map.get(prev_rid, 0)) < int(before_res_map[prev_rid]):
					return _reject("reservation_restoration_unavailable", "reservations", op, normalized_request, blocked_lots)

			if (chunk["target_kind"] as StringName) == &"existing_pile":
				var pile: GroundResourcePile = chunk["pile"] as GroundResourcePile
				var merged_state: Dictionary = storage._compute_merged_state(pile, cap)
				var before_free: int = before_amt - before_res_total
				var after_free: int = after_amt - after_res_total
				if after_free != before_free + free_added:
					return _reject("reservation_restoration_unavailable", "projection", op, normalized_request, blocked_lots)
				preserved_existing[pile.pile_id] = before_res_map.duplicate()
				merges_out.append({
					"target_kind": &"existing_pile",
					"pile_id": pile.pile_id,
					"pile_instance_id": pile.get_instance_id(),
					"resource_id": res_id,
					"unit_weight": def.unit_weight,
					"add_amount": cap,
					"free_add_amount": free_added,
					"reserved_add_amount": reserved_added,
					"before_amount": before_amt,
					"after_amount": after_amt,
					"before_elapsed_exposure_sec": pile.elapsed_exposure_sec,
					"after_elapsed_exposure_sec": float(merged_state["elapsed"]),
					"before_decay_accumulator_sec": pile.decay_accumulator_sec,
					"after_decay_accumulator_sec": float(merged_state["accum"]),
					"merge_exposure_policy": int(storage.merge_exposure_policy),
					"world_pos": chunk["world_pos"] as Vector3,
					"local_pos": chunk["local_pos"] as Vector3,
					"before_reservations": before_res_map,
					"after_reservations": after_res_map,
					"before_free_amount": before_free,
					"after_free_amount": after_free,
				})
			else:
				creates_out.append({
					"target_kind": &"virtual_pile",
					"virtual_pile_id": chunk["virtual_pile_id"] as StringName,
					"resource_id": res_id,
					"unit_weight": def.unit_weight,
					"amount": cap,
					"free_amount": free_added,
					"reserved_amount": reserved_added,
					"initial_elapsed_exposure_sec": 0.0,
					"initial_decay_accumulator_sec": 0.0,
					"world_pos": chunk["world_pos"] as Vector3,
					"local_pos": chunk["local_pos"] as Vector3,
					"reservations": after_res_map,
				})

		camp_physical_after_unsorted[res_id] = prev_phys_total + total_res_qty
		if res_reserved_added > 0:
			var prev_res_total: int = int(camp_reserved_after_unsorted.get(res_id, 0))
			if res_reserved_added > CarryProvenanceLedger.MAX_INT - prev_res_total:
				return _reject("amount_overflow", "reservations", op, normalized_request, blocked_lots)
			camp_reserved_after_unsorted[res_id] = prev_res_total + res_reserved_added

	# 4. Build and verify per-site before/after accounting conservation.
	var site_deltas_by_id: Dictionary = {}
	var reservation_by_site: Dictionary = {}
	for sid: StringName in _sorted_string_names(site_restored_by_site.keys()):
		var ctx: Dictionary = site_contexts[sid] as Dictionary
		var site: ConstructionSite = ctx["site"] as ConstructionSite
		var before_claim: Dictionary = (ctx["claim"] as Dictionary).duplicate(true)
		var after_claim: Dictionary = before_claim.duplicate(true)
		var before_acc: Dictionary = (ctx["accounting"] as Dictionary).duplicate(true)
		var after_acc: Dictionary = before_acc.duplicate(true)
		var before_res_amts: Dictionary = (ctx["reservation_amounts"] as Dictionary).duplicate(true)
		var after_res_amts: Dictionary = before_res_amts.duplicate(true)
		var restored_map: Dictionary = site_restored_by_site[sid] as Dictionary
		var res_deltas: Dictionary = {}

		for res_id: StringName in _sorted_string_names(restored_map.keys()):
			var ret_qty: int = int(restored_map[res_id])
			var acc_before: Dictionary = before_acc[res_id] as Dictionary
			var acc_after: Dictionary = after_acc[res_id] as Dictionary
			var claimed_before: int = int(before_claim.get(res_id, 0))
			var claimed_after: int = claimed_before - ret_qty
			if claimed_after < 0:
				return _reject("insufficient_transit_claim", "claims", op, normalized_request, blocked_lots)
			if claimed_after == 0:
				after_claim.erase(res_id)
			else:
				after_claim[res_id] = claimed_after

			var transit_before: int = int(acc_before["transit"])
			var reserved_before: int = int(acc_before["reserved"])
			var buffer_before: int = int(acc_before["buffer"])
			var consumed_before: int = int(acc_before["consumed"])
			var missing_before: int = int(acc_before["missing"])
			var required_amt: int = int(acc_before["required"])
			var transit_after: int = transit_before - ret_qty
			var reserved_after: int = reserved_before + ret_qty
			var ledger_res_before: int = int(before_res_amts.get(res_id, 0))
			if (
				transit_after < 0
				or reserved_after < 0
				or ledger_res_before != reserved_before
				or reserved_after + transit_after + buffer_before + consumed_before + missing_before != required_amt
			):
				return _reject("reservation_restoration_unavailable", "accounting", op, normalized_request, blocked_lots)

			acc_after["transit"] = transit_after
			acc_after["reserved"] = reserved_after
			after_res_amts[res_id] = reserved_after
			res_deltas[res_id] = {
				"returned": ret_qty,
				"transit_before": transit_before,
				"transit_after": transit_after,
				"reserved_before": reserved_before,
				"reserved_after": reserved_after,
			}

		site_deltas_by_id[sid] = {
			"before": {
				"claim": _sort_dict_by_string_key(before_claim),
				"accounting": _sort_dict_by_string_key(before_acc),
				"reservation_amounts": _sort_dict_by_string_key(before_res_amts),
			},
			"after": {
				"claim": _sort_dict_by_string_key(after_claim),
				"accounting": _sort_dict_by_string_key(after_acc),
				"reservation_amounts": _sort_dict_by_string_key(after_res_amts),
			},
		}
		reservation_by_site[sid] = {
			"reservation_id": site.reservation_id,
			"generation": site.get_generation(),
			"resource_deltas": res_deltas,
		}

	var camp_physical_after := _sort_dict_by_string_key(camp_physical_after_unsorted)
	var camp_reserved_after := _sort_dict_by_string_key(camp_reserved_after_unsorted)
	var camp_free_after_unsorted: Dictionary = {}
	for res_id: StringName in camp_physical_after.keys():
		var f_after: int = int(camp_physical_after[res_id]) - int(camp_reserved_after.get(res_id, 0))
		if f_after < 0:
			return _reject("reservation_restoration_unavailable", "projection", op, normalized_request, blocked_lots)
		if f_after > 0:
			camp_free_after_unsorted[res_id] = f_after
	var camp_free_after := _sort_dict_by_string_key(camp_free_after_unsorted)

	# Verify global camp conservation for every delivered resource.
	for res_id: StringName in sorted_resources:
		var q: int = int(deliverable_amounts[res_id])
		var phys_b: int = int(camp_physical_before.get(res_id, 0))
		var phys_a: int = int(camp_physical_after.get(res_id, 0))
		var res_b: int = int(camp_reserved_before.get(res_id, 0))
		var res_a: int = int(camp_reserved_after.get(res_id, 0))
		var free_b: int = int(camp_free_before.get(res_id, 0))
		var free_a: int = int(camp_free_after.get(res_id, 0))
		if phys_a != phys_b + q or (free_a - free_b) + (res_a - res_b) != q:
			return _reject("reservation_restoration_unavailable", "projection", op, normalized_request, blocked_lots)

	return {
		"ok": true,
		"camp_physical_after": camp_physical_after,
		"camp_reserved_after": camp_reserved_after,
		"camp_free_after": camp_free_after,
		"physical_targets_by_lot": physical_targets_by_lot,
		"site_deltas_by_id": site_deltas_by_id,
		"deposit_projection": {
			"merges": merges_out,
			"creates": creates_out,
			"total_added_by_resource": deliverable_amounts.duplicate(),
			"merge_count": merges_out.size(),
			"create_count": creates_out.size(),
			"requires_atomic_commit": true,
		},
		"reservation_projection": {
			"requires_atomic_deposit_and_reservation": not restorations_out.is_empty(),
			"preserved_existing_pile_reservations": preserved_existing,
			"restorations": restorations_out,
			"by_site": reservation_by_site,
		},
	}


static func _sort_lot_infos(values: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Variant in values:
		out.append(item as Dictionary)
	out.sort_custom(_sort_lot_dict_by_res_and_id)
	return out


static func _sort_lot_dict_by_res_and_id(a: Dictionary, b: Dictionary) -> bool:
	var ra: String = String(a["resource_id"])
	var rb: String = String(b["resource_id"])
	if ra != rb:
		return ra < rb
	return String(a["lot_id"]) < String(b["lot_id"])


static func _sort_selected_for_chunk_allocation(a: Dictionary, b: Dictionary) -> bool:
	var a_res: bool = (a["origin"] as StringName) == CarryProvenanceLedger.SITE_RESERVED
	var b_res: bool = (b["origin"] as StringName) == CarryProvenanceLedger.SITE_RESERVED
	if a_res != b_res:
		return a_res
	var sa: String = String(a["site_id"])
	var sb: String = String(b["site_id"])
	if sa != sb:
		return sa < sb
	return String(a["lot_id"]) < String(b["lot_id"])


static func _sorted_string_names(raw_keys: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: Variant in raw_keys:
		out.append(StringName(k))
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


static func _sort_dict_by_string_key(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for k: StringName in _sorted_string_names(source.keys()):
		result[k] = source[k]
	return result


static func _strict_equal(a: Variant, b: Variant) -> bool:
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if ta != tb:
		return false
	match ta:
		TYPE_FLOAT:
			var fa: float = a as float
			var fb: float = b as float
			if is_nan(fa) or is_nan(fb):
				return false
			return fa == fb
		TYPE_VECTOR2:
			var v2a: Vector2 = a as Vector2
			var v2b: Vector2 = b as Vector2
			if not v2a.is_finite() or not v2b.is_finite():
				return false
			return v2a == v2b
		TYPE_VECTOR3:
			var v3a: Vector3 = a as Vector3
			var v3b: Vector3 = b as Vector3
			if not v3a.is_finite() or not v3b.is_finite():
				return false
			return v3a == v3b
		TYPE_ARRAY:
			var aa: Array = a as Array
			var ab: Array = b as Array
			if aa.size() != ab.size():
				return false
			for i: int in range(aa.size()):
				if not _strict_equal(aa[i], ab[i]):
					return false
			return true
		TYPE_DICTIONARY:
			var da: Dictionary = a as Dictionary
			var db: Dictionary = b as Dictionary
			if da.size() != db.size():
				return false
			var keys_a: Array = da.keys()
			var keys_b: Array = db.keys()
			for ka: Variant in keys_a:
				var found_key: bool = false
				for kb: Variant in keys_b:
					if typeof(ka) == typeof(kb) and ka == kb:
						found_key = true
						break
				if not found_key:
					return false
				if not _strict_equal(da[ka], db[ka]):
					return false
			return true
		_:
			return a == b


static func _reject(
	reason: String,
	dependency: String,
	operation_id: StringName = &"",
	requested_lots: Array[Dictionary] = [],
	blocked_lots: Array[Dictionary] = []
) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"dependency": dependency,
		"dry_run_only": true,
		"commit_supported": false,
		"physical_delivery_authorized": false,
		"validation_scope": VALIDATION_SCOPE,
		"operation_id": operation_id,
		"identity": {},
		"requested_lots": requested_lots,
		"selected_lots": [],
		"deliverable_amounts": {},
		"destination_classes": {},
		"before": {},
		"after": {},
		"deposit_projection": {},
		"reservation_projection": {},
		"blocked_lots": blocked_lots,
		"revisions": {},
	}
