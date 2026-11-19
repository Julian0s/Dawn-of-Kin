extends RefCounted
## Private transaction helpers for SelectiveCampDeliveryCoordinator.
## Not registered as a global class_name to avoid exposing internal mutator/checkpoint helpers.

const Planner = preload("res://src/economy/selective_camp_delivery_planner.gd")
const SitePlanner = preload("res://src/economy/selective_site_delivery_planner.gd")
const CampDeliveryScope = ReservedWithdrawalCoordinator.CampDeliveryScope
const RegionalAuthority = ReservedWithdrawalCoordinator.RegionalAuthority
const RECEIPT_KIND := ReservedWithdrawalCoordinator.RECEIPT_CAMP_DELIVERY

const CAMP_DROPOFF_REACH_TOLERANCE_XZ: float = UnitMovement.ARRIVAL_TOLERANCE_XZ + 0.10


static func check_physical_authorization(scope: CampDeliveryScope) -> Dictionary:
	var unit := scope.unit
	var camp_zone := scope.camp_zone
	var storage := scope.storage
	var world := scope.world

	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return {"ok": false, "reason": "invalid_unit", "dependency": "authorization"}
	if unit.get_world_3d() != world or unit.get_carry_load() != scope.load:
		return {"ok": false, "reason": "participant_mismatch", "dependency": "authorization"}
	var unit_pos: Vector3 = unit.global_position
	if not unit_pos.is_finite():
		return {"ok": false, "reason": "invalid_unit", "dependency": "authorization"}

	if (
		not is_instance_valid(camp_zone)
		or not camp_zone.is_inside_tree()
		or camp_zone.is_queued_for_deletion()
		or not camp_zone.is_valid()
		or camp_zone.get_world_3d() != world
		or storage.get_camp_zone() != camp_zone
	):
		return {"ok": false, "reason": "invalid_camp_zone", "dependency": "authorization"}

	if Planner._has_untrusted_custom_position_validator(camp_zone):
		return {"ok": false, "reason": "unsafe_custom_position_validator", "dependency": "camp_zone"}
	if storage.pile_creator_override.is_valid() or not storage.pile_creator_override.is_null():
		return {"ok": false, "reason": "unsafe_pile_creator_override", "dependency": "storage"}

	if not is_instance_valid(storage._piles_root) or not storage._piles_root.is_inside_tree() or storage._piles_root.get_world_3d() != world:
		return {"ok": false, "reason": "invalid_piles_root", "dependency": "storage"}

	var nav: WorldNavigation = camp_zone.get_world_navigation()
	if nav == null or not is_instance_valid(nav) or not nav.is_inside_tree() or nav.is_queued_for_deletion():
		return {"ok": false, "reason": "navigation_not_ready", "dependency": "navigation"}
	if nav.get_world_3d() != world:
		return {"ok": false, "reason": "world_mismatch", "dependency": "navigation"}
	var movement := unit.get_movement()
	if movement != null:
		var unit_nav := movement.get_world_navigation()
		if unit_nav != null and unit_nav != nav:
			return {"ok": false, "reason": "navigation_mismatch", "dependency": "navigation"}
	if not nav.is_navigation_ready():
		return {"ok": false, "reason": "navigation_not_ready", "dependency": "navigation"}

	var slot_res: Dictionary = GatherSlotPlanner.compute_camp_dropoff_slot(unit_pos, camp_zone, nav, [])
	if not bool(slot_res.get("valid", false)):
		return {
			"ok": false,
			"reason": String(slot_res.get("reason", "camp_unreachable")),
			"dependency": "authorization",
		}
	var slot_pos: Vector3 = slot_res["position"] as Vector3
	if not slot_pos.is_finite() or not camp_zone.is_position_in_bounds(slot_pos):
		return {"ok": false, "reason": "out_of_camp_dropoff_range", "dependency": "authorization"}

	var dist_xz: float = Vector2(unit_pos.x - slot_pos.x, unit_pos.z - slot_pos.z).length()
	var dy: float = absf(unit_pos.y - slot_pos.y)
	if dist_xz > CAMP_DROPOFF_REACH_TOLERANCE_XZ or dy > BuildSlotPlanner.HEIGHT_TOLERANCE:
		return {"ok": false, "reason": "out_of_camp_dropoff_range", "dependency": "authorization"}
	if not BuildSlotPlanner.has_clear_physical_access(unit_pos, slot_pos, world):
		return {"ok": false, "reason": "out_of_camp_dropoff_range", "dependency": "authorization"}

	return {"ok": true, "slot_position": slot_pos}


static func prepare_commit_debits(authority: RegionalAuthority, plan: Dictionary) -> CarryProvenanceLedger:
	var candidate := CarryProvenanceLedger.new()
	if not candidate.restore_transaction_state(plan["before"]["cargo"]["ledger"]):
		return null
	var op: StringName = plan["operation_id"] as StringName
	var selected_lots: Array = plan["selected_lots"] as Array
	for idx: int in range(selected_lots.size()):
		var lot_entry: Dictionary = selected_lots[idx] as Dictionary
		var base_id: String = "c3.4.2:%d:%s:%d" % [String(op).length(), String(op), idx]
		var debit_id := StringName(base_id)
		var suffix: int = 0
		while candidate._operations.has(debit_id) or authority.receipts.has(debit_id) or debit_id == op:
			suffix += 1
			debit_id = StringName("%s:%d" % [base_id, suffix])
		var applied := candidate.withdraw(debit_id, lot_entry["lot_id"], int(lot_entry["selected_quantity"]))
		if not bool(applied.get("ok", false)) or bool(applied.get("replayed", false)):
			return null
	var projected_ledger: Dictionary = plan["after"]["cargo"]["ledger"] as Dictionary
	if candidate.snapshot() != projected_ledger["lots"] or candidate._used_lots != projected_ledger["used_lots"]:
		return null
	if not bool(candidate.validate_aggregate(plan["identity"]["unit_id"], plan["after"]["cargo"]["amounts"]).get("ok", false)):
		return null
	return candidate


static func capture_checkpoints(
	scope: CampDeliveryScope,
	plan: Dictionary,
	debited_ledger: CarryProvenanceLedger
) -> Dictionary:
	var load := scope.load
	var storage := scope.storage
	var uid := scope.unit.get_instance_id()

	var merge_pile_ids: Array[int] = []
	for m: Variant in (plan["deposit_projection"]["merges"] as Array):
		var m_dict: Dictionary = m as Dictionary
		var pid: int = int(m_dict["pile_id"])
		if not merge_pile_ids.has(pid):
			merge_pile_ids.append(pid)
	var storage_ckpt: Dictionary = storage._capture_camp_delivery_checkpoint(merge_pile_ids)

	var involved_sites_map: Dictionary = plan["after"]["sites"] as Dictionary
	var site_by_id: Dictionary = {}
	for s: ConstructionSite in scope.sites:
		if CarryProvenanceLedger._id(s.site_id):
			site_by_id[s.site_id] = s

	var site_ckpts: Dictionary = {}
	var peer_baselines: Dictionary = {}
	for sid_key: Variant in involved_sites_map.keys():
		var sid := StringName(sid_key)
		var site: ConstructionSite = site_by_id.get(sid) as ConstructionSite
		if site == null or not site._transit_claims.has(uid):
			return {"ok": false, "reason": "transit_listener_missing"}
		var claim: Dictionary = site._transit_claims[uid] as Dictionary
		var listener: Variant = claim.get("callback")
		if not (listener is Callable) or not load.load_changed.is_connected(listener as Callable):
			return {"ok": false, "reason": "transit_listener_missing"}
		site_ckpts[sid] = {
			"site": site,
			"claim": claim,
			"callback": listener as Callable,
			"buffer": site.get_delivered_buffer_amounts(),
			"consumed": site.get_consumed_amounts(),
			"progress": site._work_progress_usec,
			"site_state": site.get_site_state(),
			"substate": site.get_assembly_substate(),
			"was_full": site._was_fully_supplied,
			"mutated": false,
		}

	for s: ConstructionSite in scope.sites:
		if CarryProvenanceLedger._id(s.site_id) and site_ckpts.has(s.site_id):
			continue
		peer_baselines[s.get_instance_id()] = {
			"site": s,
			"buffer": s.get_delivered_buffer_amounts(),
			"consumed": s.get_consumed_amounts(),
			"claim": s._read_transit_claim_for_unit_pure(uid),
			"revision": s.get_transaction_revision(),
			"reservations": storage.get_reservation_amounts(s.reservation_id) if CarryProvenanceLedger._id(s.reservation_id) else {},
			"progress": s._work_progress_usec,
			"site_state": s.get_site_state(),
		}

	return {
		"ok": true,
		"ledger": load._provenance,
		"amounts": load._amounts,
		"weights": load._unit_weights,
		"debited_ledger_snap": debited_ledger.snapshot_transaction_state(),
		"carry_mutated": false,
		"storage_ckpt": storage_ckpt,
		"site_ckpts": site_ckpts,
		"peer_baselines": peer_baselines,
	}


static func verify_final_invariants(
	scope: CampDeliveryScope,
	plan: Dictionary,
	checkpoint: Dictionary,
	virtual_to_real_pile_ids: Dictionary
) -> bool:
	var unit := scope.unit
	var load := scope.load
	var storage := scope.storage
	var camp_zone := scope.camp_zone
	var world := scope.world
	var uid := unit.get_instance_id()

	if not is_instance_valid(unit) or not unit.is_inside_tree() or unit.get_world_3d() != world:
		return false
	if not is_instance_valid(camp_zone) or not camp_zone.is_inside_tree() or camp_zone.get_world_3d() != world:
		return false
	if not is_instance_valid(storage._piles_root) or not storage._piles_root.is_inside_tree() or storage._piles_root.get_world_3d() != world:
		return false

	# 1. Carry load & provenance conservation
	var cargo := load.provenance_snapshot()
	if (
		not Planner._strict_equal(cargo["ledger"], checkpoint["debited_ledger_snap"])
		or not Planner._strict_equal(cargo["amounts"], plan["after"]["cargo"]["amounts"])
		or not Planner._strict_equal(cargo["weights"], plan["after"]["cargo"]["weights"])
		or not load.validate_provenance()
	):
		return false
	if load.get_current_weight() != int(plan["after"]["weight"]) or load.get_effective_capacity() != int(plan["before"]["capacity"]):
		return false

	# 2. Raw `_piles` & `PileReservationLedger` integrity (created piles remain detached until commit boundary)
	var storage_ckpt: Dictionary = checkpoint["storage_ckpt"] as Dictionary
	var created_list: Array[GroundResourcePile] = storage_ckpt["created_piles"] as Array[GroundResourcePile]
	var created_ids: Dictionary = {}
	for cp: GroundResourcePile in created_list:
		if not is_instance_valid(cp) or cp.is_queued_for_deletion() or cp.is_inside_tree() or cp.get_parent() != null or not cp.is_valid():
			return false
		created_ids[cp.get_instance_id()] = true

	var pile_by_id: Dictionary = {}
	var physical_actual: Dictionary = {}
	var reserved_actual: Dictionary = {}
	for raw_entry: Variant in storage._piles:
		if raw_entry == null or not is_instance_valid(raw_entry) or not (raw_entry is GroundResourcePile):
			return false
		var pile: GroundResourcePile = raw_entry as GroundResourcePile
		if pile.is_queued_for_deletion() or not pile.is_valid() or pile.pile_id <= 0 or pile.pile_id >= storage._next_pile_id:
			return false
		var owner_ref: Object = pile._storage_owner.get_ref() if pile._storage_owner != null else null
		if owner_ref != storage or pile_by_id.has(pile.pile_id):
			return false
		if not created_ids.has(pile.get_instance_id()):
			if not pile.is_inside_tree() or pile.get_parent() != storage._piles_root or pile.get_world_3d() != world:
				return false
		var p_res: int = storage.get_pile_reserved_amount(pile.pile_id)
		if p_res < 0 or p_res > pile.amount:
			return false
		pile_by_id[pile.pile_id] = pile
		physical_actual[pile.resource_id] = int(physical_actual.get(pile.resource_id, 0)) + pile.amount
		if p_res > 0:
			reserved_actual[pile.resource_id] = int(reserved_actual.get(pile.resource_id, 0)) + p_res

	var ledger_snap: Dictionary = storage._ledger.snapshot_state()
	var by_pile: Dictionary = ledger_snap.get("by_pile", {}) as Dictionary
	for pid_key: Variant in by_pile.keys():
		if typeof(pid_key) != TYPE_INT or not pile_by_id.has(int(pid_key)):
			return false
		var lp: GroundResourcePile = pile_by_id[int(pid_key)] as GroundResourcePile
		var entry: Dictionary = by_pile[pid_key] as Dictionary
		if StringName(entry.get("resource_id", &"")) != lp.resource_id:
			return false

	# 3. Verify every merge and virtual->real creation exact state
	for m_var: Variant in (plan["deposit_projection"]["merges"] as Array):
		var m: Dictionary = m_var as Dictionary
		var pid: int = int(m["pile_id"])
		if not pile_by_id.has(pid):
			return false
		var mp: GroundResourcePile = pile_by_id[pid] as GroundResourcePile
		if (
			mp.amount != int(m["after_amount"])
			or not is_equal_approx(mp.elapsed_exposure_sec, float(m["after_elapsed_exposure_sec"]))
			or not is_equal_approx(mp.decay_accumulator_sec, float(m["after_decay_accumulator_sec"]))
		):
			return false
		var live_res := Planner._sort_dict_by_string_key(storage.get_pile_reservations(pid))
		if not Planner._strict_equal(live_res, m["after_reservations"]):
			return false

	for c_var: Variant in (plan["deposit_projection"]["creates"] as Array):
		var c: Dictionary = c_var as Dictionary
		var v_id: StringName = c["virtual_pile_id"] as StringName
		var real_pid: int = int(virtual_to_real_pile_ids.get(v_id, 0))
		if real_pid <= 0 or not pile_by_id.has(real_pid):
			return false
		var np: GroundResourcePile = pile_by_id[real_pid] as GroundResourcePile
		if np.resource_id != (c["resource_id"] as StringName) or np.amount != int(c["amount"]) or np.position != (c["local_pos"] as Vector3):
			return false
		var live_new_res := Planner._sort_dict_by_string_key(storage.get_pile_reservations(real_pid))
		if not Planner._strict_equal(live_new_res, c["reservations"]):
			return false

	# 4. Global physical conservation across camp + backpack
	var phys_sorted := Planner._sort_dict_by_string_key(physical_actual)
	var res_sorted := Planner._sort_dict_by_string_key(reserved_actual)
	var free_actual: Dictionary = {}
	for rk: Variant in phys_sorted.keys():
		var f_val: int = int(phys_sorted[rk]) - int(res_sorted.get(rk, 0))
		if f_val < 0:
			return false
		if f_val > 0:
			free_actual[rk] = f_val
	var free_sorted := Planner._sort_dict_by_string_key(free_actual)

	if (
		not Planner._strict_equal(phys_sorted, plan["after"]["camp_physical_amounts"])
		or not Planner._strict_equal(res_sorted, plan["after"]["camp_reserved_amounts"])
		or not Planner._strict_equal(free_sorted, plan["after"]["camp_free_amounts"])
	):
		return false

	var before_camp_phys: Dictionary = plan["before"]["camp_physical_amounts"] as Dictionary
	var before_carry_amts: Dictionary = plan["before"]["cargo"]["amounts"] as Dictionary
	var after_carry_amts: Dictionary = plan["after"]["cargo"]["amounts"] as Dictionary
	var all_res_keys: Dictionary = {}
	for d: Dictionary in [before_camp_phys, phys_sorted, before_carry_amts, after_carry_amts]:
		for rk: Variant in d.keys():
			all_res_keys[rk] = true
	for rk: Variant in all_res_keys.keys():
		var total_before: int = int(before_camp_phys.get(rk, 0)) + int(before_carry_amts.get(rk, 0))
		var total_after: int = int(phys_sorted.get(rk, 0)) + int(after_carry_amts.get(rk, 0))
		if total_before != total_after:
			return false

	# 5. Involved sites accounting, claims, reservations, and untouched fields
	var site_ckpts: Dictionary = checkpoint["site_ckpts"] as Dictionary
	var after_sites: Dictionary = plan["after"]["sites"] as Dictionary
	for sid_key: Variant in after_sites.keys():
		var sid := StringName(sid_key)
		var sc: Dictionary = site_ckpts[sid] as Dictionary
		var site: ConstructionSite = sc["site"] as ConstructionSite
		var expected_site: Dictionary = after_sites[sid] as Dictionary
		var acc := SitePlanner._read_accounting(site)
		if not bool(acc.get("ok", false)) or not Planner._strict_equal(Planner._sort_dict_by_string_key(acc["by_resource"] as Dictionary), expected_site["accounting"]):
			return false
		if not Planner._strict_equal(Planner._sort_dict_by_string_key(site._read_transit_claim_for_unit_pure(uid)), expected_site["claim"]):
			return false
		var live_site_res := Planner._sort_dict_by_string_key(storage.get_reservation_amounts(site.reservation_id))
		if not Planner._strict_equal(live_site_res, expected_site["reservation_amounts"]):
			return false
		if (
			site.get_delivered_buffer_amounts() != (sc["buffer"] as Dictionary)
			or site.get_consumed_amounts() != (sc["consumed"] as Dictionary)
			or site._work_progress_usec != int(sc["progress"])
			or site.get_site_state() != (sc["site_state"] as ConstructionSite.SiteState)
			or site.get_assembly_substate() != (sc["substate"] as ConstructionSite.AssemblySubstate)
			or site._was_fully_supplied != bool(sc["was_full"])
			or not load.load_changed.is_connected(sc["callback"] as Callable)
		):
			return false

	# 6. Non-involved peer sites must remain completely unchanged
	var peer_baselines: Dictionary = checkpoint["peer_baselines"] as Dictionary
	for peer_inst: Variant in peer_baselines.keys():
		var pb: Dictionary = peer_baselines[peer_inst] as Dictionary
		var peer: ConstructionSite = pb["site"] as ConstructionSite
		var peer_res := storage.get_reservation_amounts(peer.reservation_id) if CarryProvenanceLedger._id(peer.reservation_id) else {}
		if (
			peer.get_delivered_buffer_amounts() != (pb["buffer"] as Dictionary)
			or peer.get_consumed_amounts() != (pb["consumed"] as Dictionary)
			or peer._read_transit_claim_for_unit_pure(uid) != (pb["claim"] as Dictionary)
			or peer.get_transaction_revision() != int(pb["revision"])
			or peer_res != (pb["reservations"] as Dictionary)
			or peer._work_progress_usec != int(pb["progress"])
			or peer.get_site_state() != (pb["site_state"] as ConstructionSite.SiteState)
		):
			return false

	return true


static func restore_silent(scope: CampDeliveryScope, checkpoint: Dictionary) -> void:
	var uid := scope.unit.get_instance_id()
	var site_ckpts: Dictionary = checkpoint.get("site_ckpts", {}) as Dictionary
	for sid_key: Variant in site_ckpts.keys():
		var sc: Dictionary = site_ckpts[sid_key] as Dictionary
		if bool(sc.get("mutated", false)):
			var site: ConstructionSite = sc["site"] as ConstructionSite
			if is_instance_valid(site):
				site._transit_claims[uid] = sc["claim"]
				site._transaction_revision += 1
			sc["mutated"] = false

	var storage_ckpt: Dictionary = checkpoint.get("storage_ckpt", {}) as Dictionary
	if bool(storage_ckpt.get("mutated", false)):
		scope.storage._restore_camp_delivery_checkpoint_silent(storage_ckpt)

	if bool(checkpoint.get("carry_mutated", false)):
		var load := scope.load
		load._provenance = checkpoint["ledger"] as CarryProvenanceLedger
		load._amounts = checkpoint["amounts"] as Dictionary
		load._unit_weights = checkpoint["weights"] as Dictionary
		load._transaction_revision += 1
		checkpoint["carry_mutated"] = false


static func validate_camp_receipt(authority: RegionalAuthority, op: StringName) -> Dictionary:
	var receipt := ReservedWithdrawalCoordinator._read_receipt(authority.receipts.get(op), op, RECEIPT_KIND)
	if receipt.size() != 9:
		return {}
	if not (receipt.get("identity") is Dictionary and receipt.get("plan_digest") is String):
		return {}
	var digest: String = receipt["plan_digest"] as String
	if digest.length() != 64 or not digest.is_valid_hex_number(false):
		return {}
	var identity: Dictionary = receipt["identity"] as Dictionary
	if identity.size() != 11 or not (identity.get("sites") is Dictionary):
		return {}
	for sn_key: String in ["region_id", "camp_zone_id", "unit_id"]:
		if typeof(identity.get(sn_key)) != TYPE_STRING_NAME or not CarryProvenanceLedger._id(identity[sn_key]):
			return {}
	for int_key: String in ["world", "inventory", "storage", "camp_zone", "piles_root", "unit", "load"]:
		if typeof(identity.get(int_key)) != TYPE_INT or int(identity[int_key]) == 0:
			return {}
	if not (receipt.get("requested_lots") is Array and receipt.get("selected_lots") is Array):
		return {}
	if not (receipt.get("created_pile_ids") is Array and receipt.get("restored_reservations") is Array):
		return {}
	if not (receipt.get("delivered_amounts") is Dictionary) or (receipt["delivered_amounts"] as Dictionary).is_empty():
		return {}
	var total: int = 0
	for res_key: Variant in (receipt["delivered_amounts"] as Dictionary).keys():
		var qty_var: Variant = (receipt["delivered_amounts"] as Dictionary)[res_key]
		if not CarryProvenanceLedger._id(res_key) or typeof(qty_var) != TYPE_INT or int(qty_var) <= 0:
			return {}
		if int(qty_var) > CarryProvenanceLedger.MAX_INT - total:
			return {}
		total += int(qty_var)
	for pid_var: Variant in (receipt["created_pile_ids"] as Array):
		if typeof(pid_var) != TYPE_INT or int(pid_var) <= 0:
			return {}
	return receipt
