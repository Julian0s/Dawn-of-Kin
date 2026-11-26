class_name RegionalConservationAudit
extends RefCounted
## Test-only, strictly read-only physical conservation auditor for R-03A D0-A04.
##
## Formal regional conservation identity per (World3D, region_id, resource_id):
##   Q_final = Q_initial + Entries - Exits - Delta(Legitimate_Losses)
##
## Where Q is the exact sum of 8 mutually exclusive physical compartments:
##   1. natural_sources                 (ResourceSource.get_remaining_amount())
##   2. unit_carry_loads                (UnitCarryLoad.get_amount())
##   3. camp_storage                    (SettlementStorageSource.get_physical_amount())
##   4. construction_sites_buffer       (ConstructionSite.get_delivered_buffer_amount(), non-COMPLETED/CANCELLED)
##   5. construction_sites_consumed     (ConstructionSite.get_consumed_amount(), non-COMPLETED/CANCELLED)
##   6. completed_buildings             (BuildingInstance.incorporated_materials)
##   7. cancellation_local_buffer       (CancellationCustodyRecord.local_buffer_remaining)
##   8. cancellation_local_incorporated (CancellationCustodyRecord.local_incorporated_remaining)
##
## Independent cumulative legitimate losses (NEVER derived from Q_initial - Q_final):
##   - decay_losses      (GroundPileManager / SettlementStorageSource.get_total_decayed())
##   - demolition_losses (CancellationCustodyRecord.demolition_loss)
##
## Never creates RegionalAuthority, allocates IDs, modifies reservations, advances revisions,
## or calls mutating getters (e.g., ConstructionSite._prune_stale_state()).

const COMPARTMENT_KEYS: Array[String] = [
	"natural_sources",
	"unit_carry_loads",
	"camp_storage",
	"construction_sites_buffer",
	"construction_sites_consumed",
	"completed_buildings",
	"cancellation_local_buffer",
	"cancellation_local_incorporated",
]

const CANCEL_ORIGINS: Array[StringName] = [
	CarryProvenanceLedger.CANCEL_TRANSIT,
	CarryProvenanceLedger.CANCEL_BUFFER,
	CarryProvenanceLedger.CANCEL_INCORPORATED,
]


static func capture(
	tree: SceneTree,
	world: World3D,
	region_id: StringName,
	resource_id: StringName,
	inventory: SettlementInventory = null,
	storage_override: SettlementStorageSource = null
) -> Dictionary:
	var anomalies: Array[String] = []
	if tree == null or world == null or not is_instance_valid(world) or region_id.is_empty() or resource_id.is_empty():
		return {
			"ok": false,
			"reason": "invalid_domain_arguments",
			"anomalies": ["invalid_domain_arguments"],
		}

	var world_id: int = world.get_instance_id()
	var authority: ReservedWithdrawalCoordinator.RegionalAuthority = _lookup_authority_readonly(world, region_id)
	var storage: SettlementStorageSource = storage_override
	if storage == null and inventory != null:
		storage = inventory.get_storage_source()
	if storage == null and authority != null and authority.storage != null:
		storage = authority.storage.get_ref() as SettlementStorageSource

	# Validate storage domain isolation without mutating anything.
	var storage_busy: bool = false
	if storage != null:
		if storage.is_batch_active():
			storage_busy = true
		if storage is GroundPileManager:
			var gpm: GroundPileManager = storage as GroundPileManager
			if gpm.is_locked():
				storage_busy = true
			var bound_world: World3D = gpm.get_bound_withdrawal_world()
			var bound_region: StringName = gpm.get_bound_withdrawal_region()
			if bound_world != null and (bound_world != world or bound_region != region_id):
				anomalies.append("storage_bound_to_other_domain:%s" % String(bound_region))
			if is_instance_valid(gpm._piles_root) and gpm._piles_root.is_inside_tree():
				if gpm._piles_root.get_world_3d() != world:
					anomalies.append("storage_piles_root_world_mismatch")
				elif _resolve_node_region_readonly(gpm._piles_root) != region_id:
					anomalies.append("storage_piles_root_region_mismatch:%s" % String(_resolve_node_region_readonly(gpm._piles_root)))
		elif storage is InMemoryStorageSource:
			if (storage as InMemoryStorageSource).is_locked():
				storage_busy = true

	if authority != null and authority.storage != null and storage != null:
		var auth_storage: Object = authority.storage.get_ref()
		if auth_storage != null and auth_storage != storage:
			anomalies.append("authority_storage_mismatch")

	var inventory_busy: bool = inventory != null and inventory.is_transaction_busy()
	var authority_busy: bool = authority != null and authority.has_active_operation()
	var stable_boundary: bool = not storage_busy and not inventory_busy and not authority_busy

	# 1. Natural sources in (world, region_id)
	var natural_total: int = 0
	var natural_details: Dictionary = {}
	var seen_source_ids: Dictionary = {}
	for node: Node in tree.get_nodes_in_group(ResourceSource.GROUP_RESOURCE_SOURCES):
		var src: ResourceSource = node as ResourceSource
		if src == null or not is_instance_valid(src) or not src.is_inside_tree() or src.is_queued_for_deletion():
			continue
		if src.get_world_3d() != world:
			continue
		var src_region: StringName = _resolve_node_region_readonly(src)
		if src_region != region_id:
			continue
		var sid: int = src.get_instance_id()
		if seen_source_ids.has(sid):
			continue
		seen_source_ids[sid] = true
		if src.get_resource_id() != resource_id:
			continue
		var rem: int = src.get_remaining_amount()
		if rem < 0:
			anomalies.append("negative_source_amount:%s" % String(src.source_id))
		natural_total += rem
		natural_details[sid] = {
			"source_id": src.source_id,
			"remaining": rem,
			"stage": int(src.get_tree_harvest_stage()) if src.get_category() == ResourceDefinition.Category.WOOD else -1,
		}

	# 2. Unit carry loads in (world, region_id)
	var carry_total: int = 0
	var carry_details: Dictionary = {}
	var seen_unit_ids: Dictionary = {}
	var seen_load_ids: Dictionary = {}
	var provenance_enabled_carry_total: int = 0
	var provenance_ledger_total: int = 0
	var provenance_site_reserved_total: int = 0
	var provenance_cancel_total: int = 0
	var provenance_free_gathered_total: int = 0

	for node: Node in tree.get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
		var unit: Unit = node as Unit
		if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
			continue
		if unit.get_world_3d() != world:
			continue
		var unit_region: StringName = _resolve_node_region_readonly(unit)
		if unit_region != region_id:
			continue
		var uid: int = unit.get_instance_id()
		if seen_unit_ids.has(uid):
			continue
		seen_unit_ids[uid] = true
		var load: UnitCarryLoad = unit.get_carry_load()
		if load == null:
			continue
		var lid: int = load.get_instance_id()
		if seen_load_ids.has(lid):
			anomalies.append("shared_carry_load_instance:%d" % lid)
			continue
		seen_load_ids[lid] = true
		if load.is_transaction_busy() or load._coordinator_transaction_locked:
			stable_boundary = false
		var qty: int = load.get_amount(resource_id)
		if qty < 0:
			anomalies.append("negative_carry_amount:%s" % String(unit.get_character_id()))
		carry_total += qty

		var ledger_sum: int = 0
		var prov_enabled: bool = load.is_provenance_enabled()
		if prov_enabled:
			provenance_enabled_carry_total += qty
			if not load.validate_provenance():
				anomalies.append("unreconciled_provenance_ledger:%s" % String(unit.get_character_id()))
			var snap: Dictionary = load.provenance_snapshot()
			var lots: Dictionary = snap.get("ledger", {}).get("lots", {}) as Dictionary
			for lot: Dictionary in lots.values():
				if StringName(lot.get("resource_id", &"")) != resource_id:
					continue
				var lq: int = int(lot.get("quantity", 0))
				ledger_sum += lq
				var origin: StringName = StringName(lot.get("origin", &""))
				if origin == CarryProvenanceLedger.FREE_GATHERED:
					provenance_free_gathered_total += lq
				elif origin == CarryProvenanceLedger.SITE_RESERVED:
					provenance_site_reserved_total += lq
				elif CANCEL_ORIGINS.has(origin):
					provenance_cancel_total += lq
			provenance_ledger_total += ledger_sum
			if ledger_sum != qty:
				anomalies.append("carry_vs_ledger_mismatch:%s:%d!=%d" % [String(unit.get_character_id()), qty, ledger_sum])

		carry_details[uid] = {
			"unit_id": unit.get_character_id(),
			"amount": qty,
			"provenance_enabled": prov_enabled,
			"ledger_amount": ledger_sum,
		}

	# 3. Camp storage (single physical authority: GroundPileManager or SettlementStorageSource)
	var camp_storage_total: int = 0
	var camp_reserved_mirror: int = 0
	var camp_available_mirror: int = 0
	var inventory_physical_mirror: int = 0
	var decay_losses: int = 0
	var managed_pile_ids: Dictionary = {}
	var pile_count: int = 0

	if storage != null:
		camp_storage_total = storage.get_physical_amount(resource_id)
		camp_reserved_mirror = storage.get_reserved_amount(resource_id)
		camp_available_mirror = storage.get_available_amount(resource_id)
		decay_losses = storage.get_total_decayed(resource_id)
		if camp_reserved_mirror > camp_storage_total:
			anomalies.append("reserved_exceeds_physical:%d>%d" % [camp_reserved_mirror, camp_storage_total])
		if camp_available_mirror != camp_storage_total - camp_reserved_mirror:
			anomalies.append("available_mismatch:%d!=%d-%d" % [camp_available_mirror, camp_storage_total, camp_reserved_mirror])
		if storage is GroundPileManager:
			var gpm: GroundPileManager = storage as GroundPileManager
			var manual_pile_sum: int = 0
			for pile: GroundResourcePile in gpm.get_piles():
				managed_pile_ids[pile.get_instance_id()] = true
				if pile.resource_id == resource_id:
					manual_pile_sum += pile.amount
					pile_count += 1
			if manual_pile_sum != camp_storage_total:
				anomalies.append("gpm_pile_sum_mismatch:%d!=%d" % [manual_pile_sum, camp_storage_total])

	if inventory != null:
		inventory_physical_mirror = inventory.get_physical_amount(resource_id)
		if storage != null and inventory.get_storage_source() == storage and inventory_physical_mirror != camp_storage_total:
			anomalies.append("inventory_storage_mirror_mismatch:%d!=%d" % [inventory_physical_mirror, camp_storage_total])

	# Detect any unmanaged GroundResourcePile nodes in the same (world, region_id).
	var orphan_pile_amount: int = 0
	if storage is GroundPileManager:
		for node: Node in tree.get_nodes_in_group(GroundResourcePile.GROUP_GROUND_PILES):
			var pile: GroundResourcePile = node as GroundResourcePile
			if pile == null or not is_instance_valid(pile) or not pile.is_inside_tree() or pile.is_queued_for_deletion():
				continue
			if pile.get_world_3d() != world:
				continue
			var pile_region: StringName = _resolve_node_region_readonly(pile)
			if pile_region != region_id:
				continue
			if not managed_pile_ids.has(pile.get_instance_id()) and pile.resource_id == resource_id and pile.amount > 0:
				orphan_pile_amount += pile.amount
				anomalies.append("unmanaged_ground_pile_in_world:%d:%d" % [pile.pile_id, pile.amount])

	# 4 & 5. Construction sites (delivered buffer & consumed/incorporated — ONLY live non-COMPLETED/CANCELLED sites)
	var sites_buffer_total: int = 0
	var sites_consumed_total: int = 0
	var sites_transit_claims_mirror: int = 0
	var sites_reserved_mirror: int = 0
	var site_details: Dictionary = {}
	var seen_site_ids: Dictionary = {}

	for node: Node in tree.get_nodes_in_group(ConstructionSite.GROUP_CONSTRUCTION_SITES):
		var site: ConstructionSite = node as ConstructionSite
		if site == null or not is_instance_valid(site) or not site.is_inside_tree() or site.is_queued_for_deletion():
			continue
		if site.get_world_3d() != world:
			continue
		if site.region_id != region_id:
			continue
		var sid: int = site.get_instance_id()
		if seen_site_ids.has(sid):
			continue
		seen_site_ids[sid] = true
		if site.is_transaction_busy():
			stable_boundary = false
		var st: ConstructionSite.SiteState = site.get_site_state()
		if st == ConstructionSite.SiteState.UNCONFIGURED or st == ConstructionSite.SiteState.COMPLETED or st == ConstructionSite.SiteState.CANCELLED:
			continue
		var buf: int = site.get_delivered_buffer_amount(resource_id)
		var cons: int = site.get_consumed_amount(resource_id)
		var tot_recv: int = site.get_total_received_amount(resource_id)
		if buf + cons != tot_recv:
			anomalies.append("site_total_received_mismatch:%s" % String(site.site_id))
		sites_buffer_total += buf
		sites_consumed_total += cons
		sites_reserved_mirror += site.get_reserved_in_piles_amount(resource_id)
		var transit_readonly: int = _read_site_transit_claims_readonly(site, resource_id)
		sites_transit_claims_mirror += transit_readonly
		site_details[sid] = {
			"site_id": site.site_id,
			"state": int(st),
			"buffer": buf,
			"consumed": cons,
			"reserved_mirror": site.get_reserved_in_piles_amount(resource_id),
			"in_transit_mirror": transit_readonly,
		}

	# 6. Completed buildings in (world, region_id)
	var buildings_total: int = 0
	var building_details: Dictionary = {}
	var seen_building_ids: Dictionary = {}
	for node: Node in tree.get_nodes_in_group(BuildingInstance.GROUP_COMPLETED_BUILDINGS):
		var bldg: BuildingInstance = node as BuildingInstance
		if bldg == null or not is_instance_valid(bldg) or not bldg.is_inside_tree() or bldg.is_queued_for_deletion():
			continue
		if bldg.get_world_3d() != world:
			continue
		if bldg.region_id != region_id:
			continue
		var bid: int = bldg.get_instance_id()
		if seen_building_ids.has(bid):
			continue
		seen_building_ids[bid] = true
		var inc: int = int(bldg.incorporated_materials.get(resource_id, 0))
		if inc < 0:
			anomalies.append("negative_building_incorporated:%s" % String(bldg.building_id))
		buildings_total += inc
		building_details[bid] = {
			"building_id": bldg.building_id,
			"incorporated": inc,
		}

	# 7 & 8. Cancellation local custody (A = A_buf + A_inc) & independent demolition_loss (D)
	var cancel_local_buf_total: int = 0
	var cancel_local_inc_total: int = 0
	var cancel_in_transit_mirror: int = 0
	var cancel_delivered_history: int = 0
	var demolition_losses: int = 0
	var custody_details: Dictionary = {}

	if authority != null:
		for cancel_key: Variant in authority.cancellation_custodies.keys():
			var rec: ReservedWithdrawalCoordinator.CancellationCustodyRecord = authority.cancellation_custodies[cancel_key] as ReservedWithdrawalCoordinator.CancellationCustodyRecord
			if rec == null:
				continue
			if rec.world_instance_id != world_id or rec.region_id != region_id:
				anomalies.append("custody_domain_mismatch:%s" % String(rec.cancel_id))
				continue
			var acc_check: Dictionary = ReservedWithdrawalCoordinator.validate_custody_accounting_pure(rec)
			if not bool(acc_check.get("ok", false)):
				anomalies.append("custody_accounting_invalid:%s:%s" % [String(rec.cancel_id), String(acc_check.get("reason", ""))])
			var l_buf: int = int(rec.local_buffer_remaining.get(resource_id, 0))
			var l_inc: int = int(rec.local_incorporated_remaining.get(resource_id, 0))
			var h_tr: int = int(rec.in_transit_remaining.get(resource_id, 0))
			var d_loss: int = int(rec.demolition_loss.get(resource_id, 0))
			var e_deliv: int = int(rec.delivered_to_camp.get(resource_id, 0))
			cancel_local_buf_total += l_buf
			cancel_local_inc_total += l_inc
			cancel_in_transit_mirror += h_tr
			demolition_losses += d_loss
			cancel_delivered_history += e_deliv
			custody_details[rec.cancel_id] = {
				"state": rec.state,
				"local_buffer": l_buf,
				"local_incorporated": l_inc,
				"in_transit_mirror": h_tr,
				"demolition_loss": d_loss,
				"delivered_to_camp_history": e_deliv,
			}

	# Cross-check transit mirrors against provenance lots when provenance is active on carriers.
	if cancel_in_transit_mirror != provenance_cancel_total and (cancel_in_transit_mirror > 0 or provenance_cancel_total > 0):
		anomalies.append("cancel_transit_mirror_mismatch:%d!=%d" % [cancel_in_transit_mirror, provenance_cancel_total])
	if provenance_site_reserved_total > 0 and sites_transit_claims_mirror != provenance_site_reserved_total:
		anomalies.append("site_transit_mirror_mismatch:%d!=%d" % [sites_transit_claims_mirror, provenance_site_reserved_total])

	var compartments: Dictionary = {
		"natural_sources": natural_total,
		"unit_carry_loads": carry_total,
		"camp_storage": camp_storage_total,
		"construction_sites_buffer": sites_buffer_total,
		"construction_sites_consumed": sites_consumed_total,
		"completed_buildings": buildings_total,
		"cancellation_local_buffer": cancel_local_buf_total,
		"cancellation_local_incorporated": cancel_local_inc_total,
	}

	var total_physical: int = 0
	for k: String in COMPARTMENT_KEYS:
		total_physical += int(compartments[k])

	var total_legitimate_losses: int = decay_losses + demolition_losses

	return {
		"ok": anomalies.is_empty(),
		"reason": "" if anomalies.is_empty() else anomalies[0],
		"anomalies": anomalies,
		"stable_boundary": stable_boundary,
		"domain": {
			"world_instance_id": world_id,
			"region_id": region_id,
			"resource_id": resource_id,
			"has_authority": authority != null,
			"storage_instance_id": storage.get_instance_id() if storage != null else 0,
		},
		"compartments": compartments,
		"total_physical": total_physical,
		"losses": {
			"decay_losses": decay_losses,
			"demolition_losses": demolition_losses,
			"total_legitimate_losses": total_legitimate_losses,
		},
		"mirrors": {
			"inventory_physical": inventory_physical_mirror,
			"camp_reserved": camp_reserved_mirror,
			"camp_available": camp_available_mirror,
			"camp_pile_count": pile_count,
			"orphan_pile_amount": orphan_pile_amount,
			"provenance_enabled_carry": provenance_enabled_carry_total,
			"provenance_ledger_total": provenance_ledger_total,
			"provenance_free_gathered": provenance_free_gathered_total,
			"provenance_site_reserved": provenance_site_reserved_total,
			"provenance_cancel": provenance_cancel_total,
			"sites_reserved": sites_reserved_mirror,
			"sites_transit_claims": sites_transit_claims_mirror,
			"cancellation_in_transit": cancel_in_transit_mirror,
			"cancellation_delivered_history": cancel_delivered_history,
		},
		"details": {
			"natural_sources": natural_details,
			"unit_carry_loads": carry_details,
			"construction_sites": site_details,
			"completed_buildings": building_details,
			"cancellation_custodies": custody_details,
		},
	}


static func diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var comp_deltas: Dictionary = {}
	var b_comp: Dictionary = before.get("compartments", {}) as Dictionary
	var a_comp: Dictionary = after.get("compartments", {}) as Dictionary
	for k: String in COMPARTMENT_KEYS:
		comp_deltas[k] = int(a_comp.get(k, 0)) - int(b_comp.get(k, 0))

	var b_losses: Dictionary = before.get("losses", {}) as Dictionary
	var a_losses: Dictionary = after.get("losses", {}) as Dictionary
	var decay_delta: int = int(a_losses.get("decay_losses", 0)) - int(b_losses.get("decay_losses", 0))
	var demolition_delta: int = int(a_losses.get("demolition_losses", 0)) - int(b_losses.get("demolition_losses", 0))
	var losses_delta: int = int(a_losses.get("total_legitimate_losses", 0)) - int(b_losses.get("total_legitimate_losses", 0))

	var q_initial: int = int(before.get("total_physical", 0))
	var q_final: int = int(after.get("total_physical", 0))

	return {
		"q_initial": q_initial,
		"q_final": q_final,
		"q_delta": q_final - q_initial,
		"compartment_deltas": comp_deltas,
		"decay_delta": decay_delta,
		"demolition_delta": demolition_delta,
		"losses_delta": losses_delta,
	}


static func verify_conservation(
	before: Dictionary,
	after: Dictionary,
	expected_entries: int = 0,
	expected_exits: int = 0
) -> Dictionary:
	var b_dom: Dictionary = before.get("domain", {}) as Dictionary
	var a_dom: Dictionary = after.get("domain", {}) as Dictionary
	var d: Dictionary = diff(before, after)

	if not bool(before.get("ok", false)):
		return _fail_result("before_snapshot_anomaly", d, expected_entries, expected_exits, before.get("anomalies", []))
	if not bool(after.get("ok", false)):
		return _fail_result("after_snapshot_anomaly", d, expected_entries, expected_exits, after.get("anomalies", []))

	# Require explicit transactional stability evidence on both snapshots (D3.3-A01-A).
	var has_b_stable: bool = before.has("stable_boundary") and (before.get("stable_boundary") is bool)
	var has_a_stable: bool = after.has("stable_boundary") and (after.get("stable_boundary") is bool)
	if not has_b_stable and not has_a_stable:
		return _fail_result("missing_initial_and_final_stability_evidence", d, expected_entries, expected_exits, [])
	if not has_b_stable:
		return _fail_result("missing_initial_stability_evidence", d, expected_entries, expected_exits, [])
	if not has_a_stable:
		return _fail_result("missing_final_stability_evidence", d, expected_entries, expected_exits, [])
	var b_stable: bool = bool(before.get("stable_boundary", false))
	var a_stable: bool = bool(after.get("stable_boundary", false))
	if not b_stable and not a_stable:
		return _fail_result("unstable_initial_and_final_snapshots", d, expected_entries, expected_exits, [])
	if not b_stable:
		return _fail_result("unstable_initial_snapshot", d, expected_entries, expected_exits, [])
	if not a_stable:
		return _fail_result("unstable_final_snapshot", d, expected_entries, expected_exits, [])

	if (
		int(b_dom.get("world_instance_id", 0)) != int(a_dom.get("world_instance_id", 0))
		or StringName(b_dom.get("region_id", &"")) != StringName(a_dom.get("region_id", &""))
		or StringName(b_dom.get("resource_id", &"")) != StringName(a_dom.get("resource_id", &""))
	):
		return _fail_result("domain_identity_mismatch", d, expected_entries, expected_exits, [])

	# Require complete and continuous storage identity across snapshots (D3.3-A01-B).
	# Note: in Godot 4, valid 64-bit Object.get_instance_id() values can have bit 63 set (signed < 0);
	# 0 is the only valid sentinel for a storage-less domain.
	var has_b_stor: bool = b_dom.has("storage_instance_id") and (b_dom.get("storage_instance_id") is int)
	var has_a_stor: bool = a_dom.has("storage_instance_id") and (a_dom.get("storage_instance_id") is int)
	if not has_b_stor or not has_a_stor:
		return _fail_result("missing_storage_identity", d, expected_entries, expected_exits, [])
	var b_stor_id: int = int(b_dom.get("storage_instance_id", 0))
	var a_stor_id: int = int(a_dom.get("storage_instance_id", 0))
	if b_stor_id != a_stor_id:
		return _fail_result("storage_identity_mismatch", d, expected_entries, expected_exits, [])

	if int(d["decay_delta"]) < 0 or int(d["demolition_delta"]) < 0 or int(d["losses_delta"]) < 0:
		return _fail_result("negative_loss_delta", d, expected_entries, expected_exits, [])

	var expected_q_final: int = int(d["q_initial"]) + expected_entries - expected_exits - int(d["losses_delta"])
	var discrepancy: int = int(d["q_final"]) - expected_q_final
	var ok: bool = discrepancy == 0
	return {
		"ok": ok,
		"reason": "" if ok else "conservation_discrepancy:%+d" % discrepancy,
		"q_initial": int(d["q_initial"]),
		"q_final": int(d["q_final"]),
		"expected_q_final": expected_q_final,
		"entries": expected_entries,
		"exits": expected_exits,
		"losses_delta": int(d["losses_delta"]),
		"decay_delta": int(d["decay_delta"]),
		"demolition_delta": int(d["demolition_delta"]),
		"discrepancy": discrepancy,
		"compartment_deltas": d["compartment_deltas"],
		"anomalies": [],
	}


static func _fail_result(
	reason: String,
	d: Dictionary,
	expected_entries: int,
	expected_exits: int,
	anomalies: Array
) -> Dictionary:
	var expected_q_final: int = int(d["q_initial"]) + expected_entries - expected_exits - int(d["losses_delta"])
	return {
		"ok": false,
		"reason": reason,
		"q_initial": int(d["q_initial"]),
		"q_final": int(d["q_final"]),
		"expected_q_final": expected_q_final,
		"entries": expected_entries,
		"exits": expected_exits,
		"losses_delta": int(d["losses_delta"]),
		"decay_delta": int(d["decay_delta"]),
		"demolition_delta": int(d["demolition_delta"]),
		"discrepancy": int(d["q_final"]) - expected_q_final,
		"compartment_deltas": d["compartment_deltas"],
		"anomalies": anomalies.duplicate(),
	}


static func _lookup_authority_readonly(world: World3D, region_id: StringName) -> ReservedWithdrawalCoordinator.RegionalAuthority:
	if not world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META):
		return null
	var raw: Variant = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META)
	if not (raw is Dictionary):
		return null
	return (raw as Dictionary).get(region_id) as ReservedWithdrawalCoordinator.RegionalAuthority


static func _resolve_node_region_readonly(node: Node) -> StringName:
	var cursor: Node = node
	while cursor != null:
		if cursor.has_meta(&"region_id"):
			var raw: Variant = cursor.get_meta(&"region_id")
			if raw is StringName or raw is String:
				var sn := StringName(raw)
				if not sn.is_empty():
					return sn
		cursor = cursor.get_parent()
	return &"default"


static func _read_site_transit_claims_readonly(site: ConstructionSite, resource_id: StringName) -> int:
	var total: int = 0
	for claim_var: Variant in site._transit_claims.values():
		if not (claim_var is Dictionary):
			continue
		var claim: Dictionary = claim_var as Dictionary
		var unit_var: Variant = claim.get("unit")
		if not is_instance_valid(unit_var):
			continue
		var amounts_var: Variant = claim.get("amounts")
		if amounts_var is Dictionary:
			total += int((amounts_var as Dictionary).get(resource_id, 0))
	return total
