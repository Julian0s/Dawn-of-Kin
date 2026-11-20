extends TestCase
## T3.6.3-B1.1 — Unit and integration tests for D3 provenance lot primitives,
## scope-guarded silent reservation release with monotonic rollback revisions,
## and regional custody contracts (CancellationScope / CancellationCustodyRecord).

const Ledger = preload("res://src/economy/carry_provenance_ledger.gd")
const CancelMath = preload("res://src/buildings/construction_cancellation_math.gd")
const CampPlanner = preload("res://src/economy/selective_camp_delivery_planner.gd")
const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")

const WOOD_DEF: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEF: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_DEF: ResourceDefinition = preload("res://data/resources/food.tres")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")

var _cleanup_nodes: Array[Node] = []
var _cleanup_managers: Array[GroundPileManager] = []
var _cleanup_releases: Array[Dictionary] = []
var _connections: Array[Array] = []


func after_each() -> void:
	for conn: Array in _connections:
		var sig: Signal = conn[0] as Signal
		var cb: Callable = conn[1] as Callable
		if cb.is_valid() and not sig.is_null() and sig.is_connected(cb):
			sig.disconnect(cb)
	_connections.clear()
	for i: int in range(_cleanup_nodes.size() - 1, -1, -1):
		var n: Node = _cleanup_nodes[i]
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_cleanup_nodes.clear()
	for mgr: GroundPileManager in _cleanup_managers:
		if mgr != null and not mgr.is_shut_down():
			mgr.cleanup()
	_cleanup_managers.clear()
	for rel: Dictionary in _cleanup_releases:
		var w: World3D = rel["world"] as World3D
		if w == null or not is_instance_valid(w):
			continue
		var res: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(
			w, rel["region"], rel["storage"], rel["token"], get_tree(), rel["inventory"]
		)
		if not bool(res.get("ok", false)):
			push_error("B1.1 teardown: regional domain release failed: %s" % str(res))
	_cleanup_releases.clear()


func _connect_tracked(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_connections.append([sig, cb])


func _make_lot(
	lot_id: Variant,
	unit_id: Variant,
	resource_id: Variant,
	quantity: Variant,
	origin: Variant,
	site_id: Variant = &"",
	generation: Variant = 0
) -> Dictionary:
	return {
		"lot_id": lot_id,
		"unit_id": unit_id,
		"resource_id": resource_id,
		"quantity": quantity,
		"origin": origin,
		"site_id": site_id,
		"generation": generation,
	}


func _create_gpm_fixture(region_id: StringName = &"b1_1_region") -> Dictionary:
	var root := Node3D.new()
	root.name = "B11TestRoot_" + String(region_id)
	get_tree().root.add_child(root)
	_cleanup_nodes.append(root)

	var camp := CampStorageZone.new()
	camp.name = "CampStorageZone"
	camp.zone_id = StringName("camp_" + String(region_id))
	camp.zone_bounds_half_extents = Vector2(4.0, 4.0)
	camp.slot_spacing = 1.2
	camp.min_pile_clearance = 0.85
	camp.max_pile_amount = 50
	root.add_child(camp)

	var piles_root := Node3D.new()
	piles_root.name = "CampPiles"
	root.add_child(piles_root)

	var clock := SimulatedWorldTimeProvider.new(0.0)
	var defs: Dictionary = {
		&"wood": WOOD_DEF.duplicate(),
		&"stone": STONE_DEF.duplicate(),
		&"food": FOOD_DEF.duplicate(),
	}
	var gpm := GroundPileManager.new(defs, camp, piles_root, clock)
	_cleanup_managers.append(gpm)
	var token := RefCounted.new()
	assert_true(gpm.bind_domain_owner(token))
	var inv := SettlementInventory.new(gpm)
	_cleanup_releases.append({
		"world": root.get_world_3d(),
		"region": region_id,
		"storage": gpm,
		"token": token,
		"inventory": inv,
	})
	return {
		"root": root,
		"world": root.get_world_3d(),
		"region_id": region_id,
		"camp": camp,
		"piles_root": piles_root,
		"clock": clock,
		"defs": defs,
		"gpm": gpm,
		"token": token,
		"inventory": inv,
	}


func test_01_provenance_d3_origins_reclassify_replay_and_mixed_history() -> void:
	var ledger := Ledger.new()
	var const_map: Dictionary = (Ledger as GDScript).get_script_constant_map()
	assert_true(const_map.has("CANCEL_TRANSIT"), "CANCEL_TRANSIT constant required")
	assert_true(const_map.has("CANCEL_BUFFER"), "CANCEL_BUFFER constant required")
	assert_true(const_map.has("CANCEL_INCORPORATED"), "CANCEL_INCORPORATED constant required")
	if not ledger.has_method("reclassify_lot"):
		assert_true(false, "CarryProvenanceLedger.reclassify_lot() not implemented")
		return

	var c_transit: StringName = const_map.get("CANCEL_TRANSIT", &"CANCEL_TRANSIT") as StringName
	var c_buffer: StringName = const_map.get("CANCEL_BUFFER", &"CANCEL_BUFFER") as StringName
	var c_inc: StringName = const_map.get("CANCEL_INCORPORATED", &"CANCEL_INCORPORATED") as StringName

	# Seed FREE_GATHERED and SITE_RESERVED for Site A (gen 2) and Site B (gen 1)
	assert_true(bool(ledger.register_lot(&"op_free", _make_lot(&"lot_free", &"w1", &"wood", 4, Ledger.FREE_GATHERED, &"", 0)).get("ok", false)))
	assert_true(bool(ledger.register_lot(&"op_a1", _make_lot(&"lot_a1", &"w1", &"wood", 6, Ledger.SITE_RESERVED, &"site_a", 2)).get("ok", false)))
	assert_true(bool(ledger.register_lot(&"op_b1", _make_lot(&"lot_b1", &"w1", &"wood", 3, Ledger.SITE_RESERVED, &"site_b", 1)).get("ok", false)))
	assert_true(bool(ledger.validate_aggregate(&"w1", {&"wood": 13}).get("ok", false)))

	# Split lot_a1 -> lot_a1 (4) + lot_a2 (2) before reclassifying
	assert_true(bool(ledger.split_lot(&"op_split_a", &"lot_a1", &"lot_a2", 2).get("ok", false)))
	assert_true(bool(ledger.validate_aggregate(&"w1", {&"wood": 13}).get("ok", false)))

	# Reclassify lot_a1 and lot_a2 from SITE_RESERVED -> CANCEL_TRANSIT
	var rec1: Dictionary = ledger.call("reclassify_lot", &"op_rec_1", &"lot_a1", c_transit, &"site_a", 2)
	assert_true(bool(rec1.get("ok", false)), str(rec1))
	assert_false(bool(rec1.get("replayed", true)))
	var rec2: Dictionary = ledger.call("reclassify_lot", &"op_rec_2", &"lot_a2", c_transit, &"site_a", 2)
	assert_true(bool(rec2.get("ok", false)), str(rec2))
	assert_false(bool(rec2.get("replayed", true)))

	# Aggregate and Site B / FREE_GATHERED remain intact
	assert_true(bool(ledger.validate_aggregate(&"w1", {&"wood": 13}).get("ok", false)))
	assert_eq(ledger.query(&"w1", &"wood", Ledger.SITE_RESERVED, &"site_a").size(), 0)
	assert_eq(ledger.query(&"w1", &"wood", Ledger.SITE_RESERVED, &"site_b").size(), 1)
	assert_eq(ledger.query(&"w1", &"wood", c_transit, &"site_a").size(), 2)
	assert_eq(ledger.query(&"w1", &"wood", c_transit, &"site_b").size(), 0)

	# Register CANCEL_BUFFER and CANCEL_INCORPORATED lots and withdraw partial
	assert_true(bool(ledger.register_lot(&"op_cbuf", _make_lot(&"lot_cbuf", &"w1", &"stone", 3, c_buffer, &"site_a", 2)).get("ok", false)))
	assert_true(bool(ledger.register_lot(&"op_cinc", _make_lot(&"lot_cinc", &"w1", &"stone", 1, c_inc, &"site_a", 2)).get("ok", false)))
	assert_true(bool(ledger.validate_aggregate(&"w1", {&"wood": 13, &"stone": 4}).get("ok", false)))

	# Idempotent replay of reclassify_lot
	var snap_before_replay: Dictionary = ledger.snapshot_transaction_state()
	var replay1: Dictionary = ledger.call("reclassify_lot", &"op_rec_1", &"lot_a1", c_transit, &"site_a", 2)
	assert_true(bool(replay1.get("ok", false)))
	assert_true(bool(replay1.get("replayed", false)))
	assert_eq(ledger.snapshot_transaction_state(), snap_before_replay)

	# Conflicting reuse of operation_id fails closed
	var conflict1: Dictionary = ledger.call("reclassify_lot", &"op_rec_1", &"lot_a2", c_transit, &"site_a", 2)
	assert_false(bool(conflict1.get("ok", true)))
	assert_eq(String(conflict1.get("reason", "")), "operation_conflict")
	var conflict2: Dictionary = ledger.call("reclassify_lot", &"op_a1", &"lot_b1", c_transit, &"site_b", 1)
	assert_false(bool(conflict2.get("ok", true)))
	assert_eq(String(conflict2.get("reason", "")), "operation_conflict")
	assert_eq(ledger.snapshot_transaction_state(), snap_before_replay)

	# Partial split and withdrawal of CANCEL_TRANSIT and CANCEL_BUFFER lots
	assert_true(bool(ledger.split_lot(&"op_split_ct", &"lot_a1", &"lot_a1_part", 1).get("ok", false)))
	assert_true(bool(ledger.withdraw(&"op_wd_ct", &"lot_a1_part", 1).get("ok", false)))
	assert_true(bool(ledger.withdraw(&"op_wd_cb", &"lot_cbuf", 2).get("ok", false)))
	assert_true(bool(ledger.validate_aggregate(&"w1", {&"wood": 12, &"stone": 2}).get("ok", false)))

	# Full mixed history restore_transaction_state() round-trip
	var mixed_state: Dictionary = ledger.snapshot_transaction_state()
	var restored := Ledger.new()
	assert_true(restored.restore_transaction_state(mixed_state))
	assert_eq(restored.snapshot_transaction_state(), mixed_state)
	assert_true(bool(restored.validate_aggregate(&"w1", {&"wood": 12, &"stone": 2}).get("ok", false)))

	# Tampered reclassify history in restore_transaction_state() must fail closed
	var bad_state: Dictionary = mixed_state.duplicate(true)
	(bad_state["operations"][&"op_rec_1"] as Dictionary)["site_id"] = &"wrong_site"
	var bad_restored := Ledger.new()
	assert_false(bad_restored.restore_transaction_state(bad_state))


func test_02_provenance_rejections_and_no_direct_physical_credit() -> void:
	var ledger := Ledger.new()
	var const_map: Dictionary = (Ledger as GDScript).get_script_constant_map()
	if not ledger.has_method("reclassify_lot"):
		assert_true(false, "CarryProvenanceLedger.reclassify_lot() not implemented")
		return

	var c_transit: StringName = const_map.get("CANCEL_TRANSIT", &"CANCEL_TRANSIT") as StringName
	var c_buffer: StringName = const_map.get("CANCEL_BUFFER", &"CANCEL_BUFFER") as StringName
	var c_inc: StringName = const_map.get("CANCEL_INCORPORATED", &"CANCEL_INCORPORATED") as StringName

	assert_true(bool(ledger.register_lot(&"op_free", _make_lot(&"lot_free", &"w1", &"wood", 2, Ledger.FREE_GATHERED, &"", 0)).get("ok", false)))
	assert_true(bool(ledger.register_lot(&"op_res", _make_lot(&"lot_res", &"w1", &"wood", 3, Ledger.SITE_RESERVED, &"site_a", 1)).get("ok", false)))
	var baseline: Dictionary = ledger.snapshot_transaction_state()

	# 1. CANCEL_TRANSIT cannot be directly registered as a new lot (must originate from SITE_RESERVED via reclassify_lot)
	assert_false(bool(ledger.register_lot(&"op_direct_ct", _make_lot(&"lot_ct", &"w1", &"wood", 2, c_transit, &"site_a", 1)).get("ok", true)))
	# 2. CANCEL_BUFFER and CANCEL_INCORPORATED require valid site_id and generation > 0
	assert_false(bool(ledger.register_lot(&"op_cb_nosite", _make_lot(&"lot_cb1", &"w1", &"wood", 2, c_buffer, &"", 1)).get("ok", true)))
	assert_false(bool(ledger.register_lot(&"op_cb_gen0", _make_lot(&"lot_cb2", &"w1", &"wood", 2, c_buffer, &"site_a", 0)).get("ok", true)))
	assert_false(bool(ledger.register_lot(&"op_ci_nosite", _make_lot(&"lot_ci1", &"w1", &"wood", 2, c_inc, &"", 1)).get("ok", true)))
	assert_false(bool(ledger.register_lot(&"op_ci_genneg", _make_lot(&"lot_ci2", &"w1", &"wood", 2, c_inc, &"site_a", -1)).get("ok", true)))
	# 3. Duplicate lot IDs rejected
	assert_false(bool(ledger.register_lot(&"op_dup", _make_lot(&"lot_res", &"w1", &"wood", 1, c_buffer, &"site_a", 1)).get("ok", true)))

	# 4. Invalid reclassifications rejected without mutating state
	assert_false(bool((ledger.call("reclassify_lot", &"op_r_missing", &"no_such_lot", c_transit, &"site_a", 1) as Dictionary).get("ok", true)))
	assert_false(bool((ledger.call("reclassify_lot", &"op_r_free", &"lot_free", c_transit, &"site_a", 1) as Dictionary).get("ok", true)))
	assert_false(bool((ledger.call("reclassify_lot", &"op_r_wrong_site", &"lot_res", c_transit, &"site_b", 1) as Dictionary).get("ok", true)))
	assert_false(bool((ledger.call("reclassify_lot", &"op_r_wrong_gen", &"lot_res", c_transit, &"site_a", 2) as Dictionary).get("ok", true)))
	assert_false(bool((ledger.call("reclassify_lot", &"op_r_bad_target", &"lot_res", c_buffer, &"site_a", 1) as Dictionary).get("ok", true)))
	assert_false(bool((ledger.call("reclassify_lot", &"op_r_to_free", &"lot_res", Ledger.FREE_GATHERED, &"site_a", 1) as Dictionary).get("ok", true)))
	assert_eq(ledger.snapshot_transaction_state(), baseline)

	# 5. Once reclassified to CANCEL_TRANSIT, a lot cannot be reclassified again under a new operation_id
	assert_true(bool((ledger.call("reclassify_lot", &"op_r_ok", &"lot_res", c_transit, &"site_a", 1) as Dictionary).get("ok", false)))
	var after_one: Dictionary = ledger.snapshot_transaction_state()
	assert_false(bool((ledger.call("reclassify_lot", &"op_r_again", &"lot_res", c_transit, &"site_a", 1) as Dictionary).get("ok", true)))
	assert_false(bool((ledger.call("reclassify_lot", &"op_r_back", &"lot_res", Ledger.SITE_RESERVED, &"site_a", 1) as Dictionary).get("ok", true)))
	assert_eq(ledger.snapshot_transaction_state(), after_one)

	# 6. UnitCarryLoad must reject direct physical credit for CANCEL_TRANSIT, CANCEL_BUFFER, CANCEL_INCORPORATED
	var load := UnitCarryLoad.new(20)
	assert_true(load.enable_provenance(&"worker_1"))
	var empty_snap: Dictionary = load.provenance_snapshot()
	for cancel_origin: StringName in [c_transit, c_buffer, c_inc]:
		var pub_res: Dictionary = load.add_with_provenance(&"op_pub", &"lot_pub", &"wood", 2, 1, cancel_origin, &"site_a", 1)
		assert_false(bool(pub_res.get("ok", true)))
		var prep_res: Dictionary = load._prepare_provenance_add(&"op_prep", &"lot_prep", &"wood", 2, 1, cancel_origin, &"site_a", 1)
		assert_false(bool(prep_res.get("ok", true)))
		var fix_res: Dictionary = CarryFixture.add_lot(load, &"op_fix", &"lot_fix", &"wood", 2, 1, cancel_origin, &"site_a", 1)
		assert_false(bool(fix_res.get("ok", true)))
	assert_eq(load.get_amount(&"wood"), 0)
	assert_eq(load.provenance_snapshot(), empty_snap)


func test_03_scoped_reservation_release_ground_piles_and_rollback_revisions() -> void:
	var fx: Dictionary = _create_gpm_fixture(&"b11_gpm_release")
	var gpm: GroundPileManager = fx["gpm"]
	var inv: SettlementInventory = fx["inventory"]
	var world: World3D = fx["world"]
	var region: StringName = fx["region_id"]
	var coord := ReservedWithdrawalCoordinator.new()

	if not gpm.has_method("_prepare_cancel_release_under_guard") or not coord.has_method("_acquire_cancellation_scope_for_primitives"):
		assert_true(false, "CancellationScope reservation release primitives not implemented")
		return

	# Deposit 10 wood and 6 stone; reserve Site A (4 wood, 2 stone) and Site B (3 wood, 2 stone)
	assert_true(inv.deposit(&"wood", 10))
	assert_true(inv.deposit(&"stone", 6))
	assert_true(inv.reserve_batch(&"res_site_a", {&"wood": 4, &"stone": 2}))
	assert_true(inv.reserve_batch(&"res_site_b", {&"wood": 3, &"stone": 2}))
	assert_eq(inv.get_available_amount(&"wood"), 3)
	assert_eq(inv.get_available_amount(&"stone"), 2)

	var signals_emitted: Array[String] = []
	var reentrant_outcomes: Array[bool] = []
	_connect_tracked(gpm.reservations_changed, func() -> void:
		signals_emitted.append("gpm_reservations")
		reentrant_outcomes.append(gpm.deposit(&"wood", 1))
		reentrant_outcomes.append(gpm.release_batch(&"res_site_b"))
		reentrant_outcomes.append(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, region))
	)
	_connect_tracked(gpm.storage_changed, func() -> void:
		signals_emitted.append("gpm_storage")
	)

	# 1. Calling helpers without valid owned CancellationScope fails closed
	var prep_no_scope: Dictionary = gpm.call("_prepare_cancel_release_under_guard", &"res_site_a", {&"wood": 4, &"stone": 2}, null)
	assert_false(bool(prep_no_scope.get("ok", true)))
	assert_eq(String(prep_no_scope.get("reason", "")), "unauthorized_scope")

	# 2. Acquire scope for Site A, prepare, apply silently, then inject pre-commit fault and rollback!
	var s_rev_0: int = gpm.get_transaction_revision()
	var l_rev_0: int = gpm.get_pile_ledger_revision()
	var ledger_snap_0: Dictionary = gpm._ledger.snapshot_state()

	var acq_fail: Dictionary = coord.call(
		"_acquire_cancellation_scope_for_primitives",
		world, region, inv, &"cancel_a_try1", &"op_cancel_a_1", &"site_a", &"res_site_a", 1,
		{&"wood": 4, &"stone": 2}, false
	)
	assert_true(bool(acq_fail.get("ok", false)), str(acq_fail))
	var scope_fail = acq_fail["scope"]

	# Preparation does not mutate state or revisions
	var plan_1: Dictionary = gpm.call("_prepare_cancel_release_under_guard", &"res_site_a", {&"wood": 4, &"stone": 2}, scope_fail)
	assert_true(bool(plan_1.get("ok", false)), str(plan_1))
	assert_false(bool(plan_1.get("noop", true)))
	assert_eq(gpm.get_transaction_revision(), s_rev_0)
	assert_eq(gpm.get_pile_ledger_revision(), l_rev_0)

	# Wrong reservation_id or wrong expected amount under scope fails closed
	var bad_id_plan: Dictionary = gpm.call("_prepare_cancel_release_under_guard", &"res_site_b", {&"wood": 3, &"stone": 2}, scope_fail)
	assert_false(bool(bad_id_plan.get("ok", true)))
	var bad_amt_plan: Dictionary = gpm.call("_prepare_cancel_release_under_guard", &"res_site_a", {&"wood": 2, &"stone": 2}, scope_fail)
	assert_false(bool(bad_amt_plan.get("ok", true)))

	# Silent apply releases Site A reservations in memory without emitting signals
	var apply_1: Dictionary = gpm.call("_apply_prepared_cancel_release_silent", plan_1, scope_fail)
	assert_true(bool(apply_1.get("ok", false)), str(apply_1))
	assert_eq(signals_emitted.size(), 0, "Zero signals before commit publication")
	assert_false(gpm.has_reservation(&"res_site_a"))
	assert_eq(gpm.get_reservation_amounts(&"res_site_b"), {&"wood": 3, &"stone": 2})
	var s_rev_applied: int = gpm.get_transaction_revision()
	var l_rev_applied: int = gpm.get_pile_ledger_revision()
	assert_gt(s_rev_applied, s_rev_0)
	assert_gt(l_rev_applied, l_rev_0)

	# Unauthorized publish without _authorize_cancellation_release_commit is rejected
	assert_false(bool(gpm.call("_publish_cancel_release_committed", scope_fail)))
	assert_eq(signals_emitted.size(), 0)

	# Authorize rollback and restore checkpoint silently
	assert_true(bool(coord.call("_authorize_cancellation_release_rollback", scope_fail)))
	assert_true(bool(gpm.call("_restore_cancel_release_checkpoint_silent", apply_1["checkpoint"], scope_fail)))
	coord.call("_release_cancellation_scope", scope_fail)

	# Verify exact ledger state, order, physical amounts, zero signals, and STRICT MONOTONIC revision advancement (Ajuste 1)
	assert_eq(signals_emitted.size(), 0, "Rollback must emit zero signals")
	assert_eq(gpm._ledger.snapshot_state(), ledger_snap_0, "Exact reservation allocations and order must be restored")
	assert_eq(inv.get_reservation_amounts(&"res_site_a"), {&"wood": 4, &"stone": 2})
	assert_eq(inv.get_reservation_amounts(&"res_site_b"), {&"wood": 3, &"stone": 2})
	assert_eq(inv.get_physical_amount(&"wood"), 10)
	assert_eq(inv.get_physical_amount(&"stone"), 6)
	var s_rev_rolled_back: int = gpm.get_transaction_revision()
	var l_rev_rolled_back: int = gpm.get_pile_ledger_revision()
	assert_gt(s_rev_rolled_back, s_rev_applied, "Storage revision must advance monotonically on rollback")
	assert_gt(l_rev_rolled_back, l_rev_applied, "Pile ledger revision must advance monotonically on rollback")

	# 3. Attempting to reuse the stale plan_1 (captured at s_rev_0 / l_rev_0) in a new scope MUST fail closed with stale_revision!
	var acq_ok: Dictionary = coord.call(
		"_acquire_cancellation_scope_for_primitives",
		world, region, inv, &"cancel_a_try2", &"op_cancel_a_2", &"site_a", &"res_site_a", 1,
		{&"wood": 4, &"stone": 2}, false
	)
	assert_true(bool(acq_ok.get("ok", false)))
	var scope_ok = acq_ok["scope"]
	var stale_apply: Dictionary = gpm.call("_apply_prepared_cancel_release_silent", plan_1, scope_ok)
	assert_false(bool(stale_apply.get("ok", true)), "Old plan from before rollback must be rejected as stale")
	assert_eq(String(stale_apply.get("reason", "")), "stale_revision")

	# Prepare fresh plan_2 at current revisions, apply, authorize commit, and publish under guards
	var plan_2: Dictionary = gpm.call("_prepare_cancel_release_under_guard", &"res_site_a", {&"wood": 4, &"stone": 2}, scope_ok)
	assert_true(bool(plan_2.get("ok", false)))
	var apply_2: Dictionary = gpm.call("_apply_prepared_cancel_release_silent", plan_2, scope_ok)
	assert_true(bool(apply_2.get("ok", false)))
	assert_true(bool(coord.call("_authorize_cancellation_release_commit", scope_ok)))
	# Rollback after commit authorization must be refused
	assert_false(bool(gpm.call("_restore_cancel_release_checkpoint_silent", apply_2["checkpoint"], scope_ok)))
	assert_true(bool(gpm.call("_publish_cancel_release_committed", scope_ok)))
	coord.call("_release_cancellation_scope", scope_ok)

	assert_eq(signals_emitted, ["gpm_reservations", "gpm_storage"])
	# Reentrant mutations during post-commit signal were blocked while regional transaction was active (D-INT-02/A)
	assert_eq(reentrant_outcomes, [false, false, true])
	assert_false(inv.has_reservation(&"res_site_a"))
	assert_eq(inv.get_reservation_amounts(&"res_site_b"), {&"wood": 3, &"stone": 2})
	assert_eq(inv.get_available_amount(&"wood"), 7)
	assert_eq(inv.get_available_amount(&"stone"), 4)

	# 4. S = 0 legitimate no-op when Site A has no active reservation left
	var acq_noop: Dictionary = coord.call(
		"_acquire_cancellation_scope_for_primitives",
		world, region, inv, &"cancel_a_noop", &"op_cancel_a_noop", &"site_a", &"res_site_a", 2,
		{&"wood": 0, &"stone": 0}, true
	)
	assert_true(bool(acq_noop.get("ok", false)))
	var scope_noop = acq_noop["scope"]
	# Passing S = 0 against Site B (which actually has active reservations!) must fail closed
	var bogus_noop: Dictionary = gpm.call("_prepare_cancel_release_under_guard", &"res_site_b", {&"wood": 0, &"stone": 0}, scope_noop)
	assert_false(bool(bogus_noop.get("ok", true)))
	var plan_noop: Dictionary = gpm.call("_prepare_cancel_release_under_guard", &"res_site_a", {&"wood": 0, &"stone": 0}, scope_noop)
	assert_true(bool(plan_noop.get("ok", false)), str(plan_noop))
	assert_true(bool(plan_noop.get("noop", false)))
	var apply_noop: Dictionary = gpm.call("_apply_prepared_cancel_release_silent", plan_noop, scope_noop)
	assert_true(bool(apply_noop.get("ok", false)))
	assert_true(bool(coord.call("_authorize_cancellation_release_commit", scope_noop)))
	assert_true(bool(gpm.call("_publish_cancel_release_committed", scope_noop)))
	coord.call("_release_cancellation_scope", scope_noop)
	assert_eq(inv.get_reservation_amounts(&"res_site_b"), {&"wood": 3, &"stone": 2})


func test_04_scoped_reservation_release_in_memory_storage_source() -> void:
	var fx: Dictionary = _create_gpm_fixture(&"b11_mem_host")
	var world: World3D = fx["world"]
	var mem := InMemoryStorageSource.new()
	var inv := SettlementInventory.new(mem)
	var region := &"b11_mem_region"
	var coord := ReservedWithdrawalCoordinator.new()

	if not mem.has_method("_prepare_cancel_release_under_guard") or not coord.has_method("_acquire_cancellation_scope_for_primitives"):
		assert_true(false, "InMemoryStorageSource cancellation release primitives not implemented")
		return

	assert_true(inv.deposit(&"wood", 8))
	assert_true(inv.deposit(&"stone", 5))
	assert_true(inv.reserve_batch(&"res_m_a", {&"wood": 5, &"stone": 3}))
	assert_true(inv.reserve_batch(&"res_m_b", {&"wood": 2, &"stone": 1}))

	var rev_0: int = mem.get_transaction_revision()
	var acq_1: Dictionary = coord.call(
		"_acquire_cancellation_scope_for_primitives",
		world, region, inv, &"cancel_m_1", &"op_m_1", &"site_m_a", &"res_m_a", 1,
		{&"wood": 5, &"stone": 3}, false
	)
	assert_true(bool(acq_1.get("ok", false)), str(acq_1))
	var scope_1 = acq_1["scope"]
	assert_true(mem.is_locked(), "InMemoryStorageSource must report locked while CancellationScope is active")
	assert_false(mem.deposit(&"wood", 1), "Direct mutators must fail closed while CancellationScope is active")

	var plan_1: Dictionary = mem.call("_prepare_cancel_release_under_guard", &"res_m_a", {&"wood": 5, &"stone": 3}, scope_1)
	assert_true(bool(plan_1.get("ok", false)))
	var apply_1: Dictionary = mem.call("_apply_prepared_cancel_release_silent", plan_1, scope_1)
	assert_true(bool(apply_1.get("ok", false)))
	var rev_applied: int = mem.get_transaction_revision()
	assert_gt(rev_applied, rev_0)
	assert_false(mem.has_reservation(&"res_m_a"))

	# Rollback restores reservation and order and advances revision monotonically
	assert_true(bool(coord.call("_authorize_cancellation_release_rollback", scope_1)))
	assert_true(bool(mem.call("_restore_cancel_release_checkpoint_silent", apply_1["checkpoint"], scope_1)))
	coord.call("_release_cancellation_scope", scope_1)
	assert_false(mem.is_locked())
	assert_gt(mem.get_transaction_revision(), rev_applied)
	assert_eq(mem.get_reservation_amounts(&"res_m_a"), {&"wood": 5, &"stone": 3})
	assert_eq(mem.get_all_reservation_ids(), [&"res_m_a", &"res_m_b"])


func test_06_release_scope_rolls_back_unpublished_reservations() -> void:
	var coord := ReservedWithdrawalCoordinator.new()
	var fx := _create_gpm_fixture()
	for physical: bool in [true, false]:
		var storage: SettlementStorageSource = fx.gpm if physical else InMemoryStorageSource.new()
		var inv := SettlementInventory.new(storage) if not physical else fx.inventory as SettlementInventory
		assert_true(inv.deposit(&"wood", 8))
		assert_true(inv.reserve_batch(&"guard_a", {&"wood": 4}))
		assert_true(inv.reserve_batch(&"guard_b", {&"wood": 2}))
		var acquired: Dictionary = coord.call("_acquire_cancellation_scope_for_primitives",
			fx.world, fx.region_id, inv, &"guard_cancel", &"guard_op", &"guard_site", &"guard_a", 1, {&"wood": 4}, false)
		assert_true(acquired.ok, str(acquired))
		if not acquired.ok:
			continue
		var scope = acquired.scope
		assert_false(coord.call("_authorize_cancellation_release_commit", scope), "Premature authorization")
		var events: Array[bool] = []
		var observer := func() -> void: events.append(true)
		storage.reservations_changed.connect(observer)
		var plan: Dictionary = storage.call("_prepare_cancel_release_under_guard", &"guard_a", {&"wood": 4}, scope)
		var applied: Dictionary = storage.call("_apply_prepared_cancel_release_silent", plan, scope)
		assert_true(applied.ok, str(applied))
		assert_eq(inv.get_reservation_amount(&"guard_a", &"wood"), 0)
		assert_true(coord.call("_authorize_cancellation_release_commit", scope))
		var applied_revision := storage.get_transaction_revision()
		assert_true(coord.call("_release_cancellation_scope", scope))
		storage.reservations_changed.disconnect(observer)
		assert_eq(inv.get_reservation_amount(&"guard_a", &"wood"), 4)
		assert_eq(inv.get_reservation_amount(&"guard_b", &"wood"), 2)
		assert_eq(inv.get_physical_amount(&"wood"), 8)
		assert_gt(storage.get_transaction_revision(), applied_revision)
		assert_eq(events.size(), 0)
		assert_false(inv.is_transaction_busy())
		assert_false(coord.call("_owns_cancellation_scope", scope))
		var retry: Dictionary = coord.call("_acquire_cancellation_scope_for_primitives",
			fx.world, fx.region_id, inv, &"guard_cancel", &"guard_op", &"guard_site", &"guard_a", 1, {&"wood": 4}, false)
		assert_true(retry.ok, str(retry))
		var next_scope = retry.scope
		assert_eq(storage.call("_apply_prepared_cancel_release_silent", plan, next_scope).reason, "stale_revision")
		var fresh: Dictionary = storage.call("_prepare_cancel_release_under_guard", &"guard_a", {&"wood": 4}, next_scope)
		assert_true(storage.call("_apply_prepared_cancel_release_silent", fresh, next_scope).ok)
		assert_true(coord.call("_authorize_cancellation_release_commit", next_scope))
		var during_publish: Array = []
		var reenter := func() -> void:
			during_publish.append(coord.call("_release_cancellation_scope", next_scope))
			during_publish.append(coord.call("_authorize_cancellation_release_rollback", next_scope))
			during_publish.append(inv.is_transaction_busy())
			during_publish.append(storage.release_batch(&"guard_b"))
		storage.reservations_changed.connect(reenter)
		assert_true(storage.call("_publish_cancel_release_committed", next_scope))
		storage.reservations_changed.disconnect(reenter)
		assert_eq(during_publish, [false, false, true, false])
		assert_false(storage.call("_publish_cancel_release_committed", next_scope))
		assert_true(coord.call("_release_cancellation_scope", next_scope))
		assert_false(inv.is_transaction_busy())
		assert_eq(inv.get_reservation_amount(&"guard_b", &"wood"), 2)


func test_07_regional_release_checks_pending_and_settled_custody() -> void:
	var coord := ReservedWithdrawalCoordinator.new()
	for idx: int in range(5):
		var region := StringName("b11_release_%d" % idx)
		var fx := _create_gpm_fixture(region)
		var acquired: Dictionary = coord.call("_acquire_cancellation_scope_for_primitives",
			fx.world, region, fx.inventory, &"release_cancel", &"release_op", &"release_site", &"release_res", 1, {&"wood": 0}, true)
		assert_true(acquired.ok, str(acquired))
		if not acquired.ok:
			continue
		var scope = acquired.scope
		var authority = scope.authority
		coord.call("_release_cancellation_scope", scope)
		if idx < 4:
			var record := ReservedWithdrawalCoordinator.CancellationCustodyRecord.new()
			record.cancel_id = &"release_cancel"
			record.operation_id = &"release_op"
			record.site_id = &"release_site"
			record.reservation_id = &"release_res"
			record.region_id = region
			record.world_instance_id = fx.world.get_instance_id()
			record.generation = 1
			record.required_amounts = {&"wood": 2}
			record.state = [CancelMath.State.RECOVERY_PENDING, CancelMath.State.RETURNING,
				CancelMath.State.RETURN_BLOCKED, CancelMath.State.SETTLED][idx]
			record.local_buffer_remaining = {&"wood": 2} if idx in [0, 2] else {}
			record.in_transit_remaining = {&"wood": 2} if idx == 1 else {}
			record.delivered_to_camp = {&"wood": 2} if idx == 3 else {}
			authority.cancellation_custodies[record.cancel_id] = record
		fx.root.get_parent().remove_child(fx.root)
		fx.gpm.cleanup()
		var result := ReservedWithdrawalCoordinator.release_regional_domain(
			fx.world, region, fx.gpm, fx.token, get_tree(), fx.inventory)
		if idx < 3:
			assert_false(result.ok, str(result))
			assert_eq(result.reason, "pending_cancellation_custody")
			assert_true(coord.call("get_cancellation_custody_readonly", fx.world, region, &"release_cancel").ok)
		else:
			assert_true(result.ok and result.released, str(result))
		# Test records are isolated from the operational registration path.
		authority.cancellation_custodies.clear()


func test_05_regional_custody_contracts_state_machine_and_d3_gate() -> void:
	var coord := ReservedWithdrawalCoordinator.new()
	if not coord.has_method("validate_custody_accounting_pure"):
		assert_true(false, "ReservedWithdrawalCoordinator custody contracts not implemented")
		return

	# 1. Pure validation of Q = L + A + H + E + D + M (50% shelter example: required 12/6, S=L=0, T=H=2/1, B=4/2, C=6/3 -> K=1/0, D=5/3, M=0)
	var valid_spec: Dictionary = {
		"cancel_id": &"cancel_site_1_gen_1",
		"operation_id": &"op_cancel_1",
		"site_id": &"site_1",
		"reservation_id": &"res_site_1",
		"generation": 1,
		"region_id": &"b11_custody_reg_a",
		"world_instance_id": 1001,
		"work_progress_usec": 15_000_000,
		"total_work_usec": 30_000_000,
		"state": CancelMath.State.RECOVERY_PENDING,
		"required_amounts": {&"wood": 12, &"stone": 6},
		"released_on_piles": {&"wood": 0, &"stone": 0},
		"local_buffer_remaining": {&"wood": 4, &"stone": 2},
		"local_incorporated_remaining": {&"wood": 1, &"stone": 0},
		"in_transit_remaining": {&"wood": 2, &"stone": 1},
		"delivered_to_camp": {&"wood": 0, &"stone": 0},
		"demolition_loss": {&"wood": 5, &"stone": 3},
		"missing_deficit": {&"wood": 0, &"stone": 0},
	}
	var check_ok: Dictionary = coord.call("validate_custody_accounting_pure", valid_spec)
	assert_true(bool(check_ok.get("ok", false)), str(check_ok))

	# 2. Accounting mismatch, negative quantity, overflow, and SETTLED with pending A/H rejected
	var bad_sum: Dictionary = valid_spec.duplicate(true)
	(bad_sum["in_transit_remaining"] as Dictionary)[&"wood"] = 3
	var res_bad_sum: Dictionary = coord.call("validate_custody_accounting_pure", bad_sum)
	assert_false(bool(res_bad_sum.get("ok", true)))
	assert_eq(String(res_bad_sum.get("reason", "")), "accounting_mismatch")

	var bad_neg: Dictionary = valid_spec.duplicate(true)
	(bad_neg["local_buffer_remaining"] as Dictionary)[&"wood"] = -1
	(bad_neg["in_transit_remaining"] as Dictionary)[&"wood"] = 3
	var res_bad_neg: Dictionary = coord.call("validate_custody_accounting_pure", bad_neg)
	assert_false(bool(res_bad_neg.get("ok", true)))

	var bad_ovf: Dictionary = valid_spec.duplicate(true)
	(bad_ovf["required_amounts"] as Dictionary)[&"wood"] = CancelMath.MAX_INT
	(bad_ovf["local_buffer_remaining"] as Dictionary)[&"wood"] = CancelMath.MAX_INT
	(bad_ovf["in_transit_remaining"] as Dictionary)[&"wood"] = 1
	var res_bad_ovf: Dictionary = coord.call("validate_custody_accounting_pure", bad_ovf)
	assert_false(bool(res_bad_ovf.get("ok", true)))
	assert_eq(String(res_bad_ovf.get("reason", "")), "overflow")

	var bad_settled: Dictionary = valid_spec.duplicate(true)
	bad_settled["state"] = CancelMath.State.SETTLED
	var res_bad_settled: Dictionary = coord.call("validate_custody_accounting_pure", bad_settled)
	assert_false(bool(res_bad_settled.get("ok", true)))
	assert_eq(String(res_bad_settled.get("reason", "")), "unsettled_custody_remaining")

	# 3. State machine compatibility (Ajuste 2): direct FREEZING -> SETTLED forbidden;
	# zero-custody cancellation must chain FREEZING -> RECOVERY_PENDING -> SETTLED.
	assert_false(bool(CancelMath.plan_transition(CancelMath.State.FREEZING, CancelMath.State.SETTLED).get("ok", true)))
	var seq_zero: Dictionary = coord.call("plan_custody_state_sequence_pure", false)
	assert_true(bool(seq_zero.get("ok", false)), str(seq_zero))
	assert_eq(seq_zero["states"], [
		CancelMath.State.ACTIVE,
		CancelMath.State.REQUESTED,
		CancelMath.State.PREVALIDATING,
		CancelMath.State.FREEZING,
		CancelMath.State.RECOVERY_PENDING,
		CancelMath.State.SETTLED,
	])
	var seq_pending: Dictionary = coord.call("plan_custody_state_sequence_pure", true)
	assert_true(bool(seq_pending.get("ok", false)))
	assert_eq(seq_pending["states"], [
		CancelMath.State.ACTIVE,
		CancelMath.State.REQUESTED,
		CancelMath.State.PREVALIDATING,
		CancelMath.State.FREEZING,
		CancelMath.State.RECOVERY_PENDING,
	])

	# 4. Regional registration under owned scope, duplicate protection, regional isolation, D-CANC-02/A & Ajustes 3/4
	var fx_a: Dictionary = _create_gpm_fixture(&"b11_custody_reg_a")
	var fx_b: Dictionary = _create_gpm_fixture(&"b11_custody_reg_b")
	var world_a: World3D = fx_a["world"]
	valid_spec["world_instance_id"] = world_a.get_instance_id()

	# Registration without an active owned CancellationScope fails closed
	var unauth_reg: Dictionary = coord.call("_register_cancellation_custody_under_scope", null, valid_spec)
	assert_false(bool(unauth_reg.get("ok", true)))
	assert_eq(String(unauth_reg.get("reason", "")), "unauthorized_scope")

	var acq_a: Dictionary = coord.call(
		"_acquire_cancellation_scope_for_primitives",
		world_a, &"b11_custody_reg_a", fx_a["inventory"],
		&"cancel_site_1_gen_1", &"op_cancel_1", &"site_1", &"res_site_1", 1,
		{&"wood": 0, &"stone": 0}, true
	)
	assert_true(bool(acq_a.get("ok", false)))
	var scope_a = acq_a["scope"]
	assert_false(coord.call("_authorize_cancellation_release_commit", scope_a))
	assert_false(coord.call("_register_cancellation_custody_under_scope", scope_a, valid_spec).ok)
	var storage: GroundPileManager = fx_a.gpm
	var empty_plan: Dictionary = storage.call("_prepare_cancel_release_under_guard", scope_a.reservation_id, {&"wood": 0, &"stone": 0}, scope_a)
	assert_true(empty_plan.ok)
	assert_true(storage.call("_apply_prepared_cancel_release_silent", empty_plan, scope_a).ok)
	assert_true(coord.call("_authorize_cancellation_release_commit", scope_a))
	assert_true(storage.call("_publish_cancel_release_committed", scope_a))
	assert_false(coord.call("_authorize_cancellation_release_rollback", scope_a))
	assert_eq(coord.call("_register_cancellation_custody_under_scope", scope_a, valid_spec).reason, "d3_cancellation_not_implemented")
	var authority = scope_a.authority
	assert_true(authority.cancellation_custodies.is_empty())
	assert_true(authority.cancellation_id_by_site_gen.is_empty())
	assert_true(authority.cancellation_operation_ids.is_empty())
	assert_true(coord.call("_release_cancellation_scope", scope_a))

	# Test-only record for read and accounting contracts, with no operational indexes.
	var record := ReservedWithdrawalCoordinator.CancellationCustodyRecord.new()
	for key: String in valid_spec:
		record.set(key, valid_spec[key])
	authority.cancellation_custodies[record.cancel_id] = record

	# Verify custody query, D-CANC-02/A footprint occupation (A > 0 -> occupied; A == 0 -> released even if H > 0), and obligation status (Ajuste 4)
	assert_eq(record.get_local_custody_total(), 7)
	assert_eq(record.get_in_transit_custody_total(), 3)
	assert_true(record.requires_local_footprint_occupation(false))
	assert_eq(record.get_obligation_status(), &"pending")

	# Regional isolation: region B in the same World3D has zero custody records from region A
	var found_a: Dictionary = coord.call("get_cancellation_custody_readonly", world_a, &"b11_custody_reg_a", &"cancel_site_1_gen_1")
	assert_true(bool(found_a.get("ok", false)))
	var found_b: Dictionary = coord.call("get_cancellation_custody_readonly", fx_b["world"], &"b11_custody_reg_b", &"cancel_site_1_gen_1")
	assert_false(bool(found_b.get("ok", true)))

	authority.cancellation_custodies.clear()

	# 5. Operational D3 cancellation remains strictly gated/inaccessible in B1.1
	var op_d3: Dictionary = coord.call("execute_site_cancellation", null, &"op_d3_blocked")
	assert_false(bool(op_d3.get("ok", true)))
	assert_eq(String(op_d3.get("reason", "")), "d3_cancellation_not_implemented")
