extends "res://tests/framework/selective_site_delivery_fixture.gd"
## T3.6.2-C3.4.1 adversarial integration suite for pure selective camp delivery preparation & validation.
## Covers Groups A-E (Scenarios 1-53) plus regional/world isolation, busy guards, and operation conflicts.
##
## Notes on private state access in adversarial tests:
## - `_provenance._operations`, `_amounts`, `_generation`, `_site_state`, `_transit_claims`,
##   `_ledger._by_pile`, `_is_mutating`, `_is_preparing_withdrawal`, `_next_pile_id`, and
##   `RegionalAuthority.is_executing` / `receipts` / `construction_transfer_serial` are inspected or
##   perturbed strictly inside adversarial corruption/fault-injection/purity tests because public APIs
##   intentionally prevent constructing inconsistent states or exposing mutable authority internals.

const CampPlanner = preload("res://src/economy/selective_camp_delivery_planner.gd")
const DEFAULT_REGION: StringName = &"c3_region"


func _gather_res(
	fx: Dictionary,
	unit: Unit,
	res_def: ResourceDefinition,
	amount: int,
	op_id: StringName,
	lot_id: StringName
) -> void:
	var source := ResourceSource.new()
	fx.host.add_child(source)
	var cap: int = maxi(amount, 10)
	source.configure(StringName("src_" + String(lot_id)), res_def.duplicate() as ResourceDefinition, cap, cap, 2)
	# This delivery fixture seeds legitimate cargo through the extraction API.
	if source.get_category() == ResourceDefinition.Category.WOOD:
		source.set(&"_tree_harvest_stage", ResourceSource.TreeHarvestStage.FALLEN)
	var outcome: Dictionary = source.transfer_to_carry_load_with_provenance(
		unit.get_carry_load(), op_id, lot_id, amount
	)
	assert_true(bool(outcome.get("ok", false)), str(outcome))
	assert_eq(int(outcome.get("extracted", 0)), amount, str(outcome))


func _debit_free_lot_for_test(load: UnitCarryLoad, op_id: StringName, lot_id: StringName, amount: int) -> void:
	# Test-only helper: C3.4.1 intentionally does not add a public free-lot commit/debit API.
	# Simulates a reconciled post-preparation backpack debit to exercise revision & ABA checks.
	var lot: Dictionary = load._provenance.snapshot().get(lot_id, {}) as Dictionary
	assert_false(lot.is_empty(), "Expected lot to exist: " + str(lot_id))
	var res_id: StringName = StringName(lot["resource_id"])
	var w_res: Dictionary = load._provenance.withdraw(op_id, lot_id, amount)
	assert_true(bool(w_res.get("ok", false)), str(w_res))
	var next_amt: int = int(load._amounts.get(res_id, 0)) - amount
	if next_amt <= 0:
		load._amounts.erase(res_id)
		load._unit_weights.erase(res_id)
	else:
		load._amounts[res_id] = next_amt
	load._transaction_revision += 1
	assert_true(load.validate_provenance())


func _camp_snapshot(fx: Dictionary, sites: Array[ConstructionSite], unit: Unit) -> Dictionary:
	var base := _snapshot(fx, sites, unit)
	var world := unit.get_world_3d()
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var serials: Dictionary = {}
	for r_key: Variant in domains.keys():
		var auth := domains[r_key] as ReservedWithdrawalCoordinator.RegionalAuthority
		if auth != null:
			serials[r_key] = auth.construction_transfer_serial
	var load := unit.get_carry_load()
	var listener_counts: Dictionary = {
		"storage_changed": fx.manager.storage_changed.get_connections().size(),
		"reservations_changed": fx.manager.reservations_changed.get_connections().size(),
		"inv_changed": fx.inventory.inventory_changed.get_connections().size(),
		"inv_res_changed": fx.inventory.reservations_changed.get_connections().size(),
		"load_changed": load.load_changed.get_connections().size(),
		"cap_changed": load.capacity_changed.get_connections().size(),
	}
	base["next_pile_id"] = fx.manager._next_pile_id
	base["authority_serials"] = serials
	base["listener_counts"] = listener_counts
	return base


func _assert_safe_dry_run_flags(result: Dictionary, expect_ok: bool) -> void:
	assert_eq(bool(result.get("ok", not expect_ok)), expect_ok, str(result))
	assert_true(result.get("dry_run_only") is bool and bool(result["dry_run_only"]), str(result))
	assert_true(result.get("commit_supported") is bool and not bool(result["commit_supported"]), str(result))
	assert_true(result.get("physical_delivery_authorized") is bool and not bool(result["physical_delivery_authorized"]), str(result))
	assert_eq(String(result.get("validation_scope", "")), CampPlanner.VALIDATION_SCOPE, str(result))
	for required_key: String in [
		"ok", "reason", "dependency", "dry_run_only", "commit_supported",
		"physical_delivery_authorized", "validation_scope", "operation_id", "identity",
		"requested_lots", "selected_lots", "deliverable_amounts", "destination_classes",
		"before", "after", "deposit_projection", "reservation_projection",
		"blocked_lots", "revisions"
	]:
		assert_true(result.has(required_key), "Missing mandatory plan field: " + required_key)


# ------------------------------------------------------------------------------
# GROUP A — SELECTION (Scenarios 1-10)
# ------------------------------------------------------------------------------

func test_group_a_single_free_lot_full_and_partial() -> void:
	# Scenarios 1 (one full free lot) & 2 (one partial free lot)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_a1")
	_gather_res(fx, unit, WOOD, 10, &"op_g1", &"free_wood_1")

	# Scenario 1: full free lot
	var full_plan := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_camp_full",
		[{"lot_id": &"free_wood_1", "amount": 10}]
	)
	_assert_safe_dry_run_flags(full_plan, true)
	assert_eq(full_plan.selected_lots.size(), 1)
	var s1: Dictionary = full_plan.selected_lots[0]
	assert_eq(s1.lot_id, &"free_wood_1")
	assert_eq(s1.unit_id, &"worker_a1")
	assert_eq(s1.resource_id, &"wood")
	assert_eq(s1.origin, CarryProvenanceLedger.FREE_GATHERED)
	assert_eq(s1.original_quantity, 10)
	assert_eq(s1.selected_quantity, 10)
	assert_eq(s1.residual_quantity, 0)
	assert_eq(s1.destination_class, CampPlanner.DEST_CAMP_FREE_STOCK)
	assert_eq(full_plan.deliverable_amounts, {&"wood": 10})
	assert_true((full_plan.after.cargo.amounts as Dictionary).is_empty())
	assert_true((full_plan.after.cargo.ledger.lots as Dictionary).is_empty())
	assert_eq(full_plan.after.weight, 0)
	assert_eq(int(full_plan.after.camp_physical_amounts[&"wood"]), int(full_plan.before.camp_physical_amounts[&"wood"]) + 10)
	assert_eq(int(full_plan.after.camp_free_amounts[&"wood"]), int(full_plan.before.camp_free_amounts[&"wood"]) + 10)

	# Scenario 2: partial free lot (10 -> 6 in backpack, +4 in camp)
	var partial_plan := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_camp_partial",
		[{"lot_id": &"free_wood_1", "amount": 4}]
	)
	_assert_safe_dry_run_flags(partial_plan, true)
	var s2: Dictionary = partial_plan.selected_lots[0]
	assert_eq(s2.original_quantity, 10)
	assert_eq(s2.selected_quantity, 4)
	assert_eq(s2.residual_quantity, 6)
	assert_eq(partial_plan.after.cargo.amounts, {&"wood": 6})
	assert_eq(int(partial_plan.after.cargo.ledger.lots[&"free_wood_1"].quantity), 6)
	assert_eq(partial_plan.after.weight, partial_plan.before.weight - 4 * WOOD.unit_weight)
	assert_eq(int(partial_plan.after.camp_physical_amounts[&"wood"]), int(partial_plan.before.camp_physical_amounts[&"wood"]) + 4)
	assert_eq(int(partial_plan.after.camp_free_amounts[&"wood"]), int(partial_plan.before.camp_free_amounts[&"wood"]) + 4)


func test_group_a_two_free_lots_same_resource_and_multi_resource() -> void:
	# Scenarios 3 (two free lots same resource) & 4 (wood and stone)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_a3")
	_gather_res(fx, unit, WOOD, 4, &"op_gb", &"free_wood_b")
	_gather_res(fx, unit, WOOD, 6, &"op_ga", &"free_wood_a")
	_gather_res(fx, unit, STONE, 3, &"op_gs", &"free_stone_1")

	# Scenario 3: two wood lots
	var two_wood := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_two_wood",
		[{"lot_id": &"free_wood_b", "amount": 4}, {"lot_id": &"free_wood_a", "amount": 5}]
	)
	_assert_safe_dry_run_flags(two_wood, true)
	assert_eq(two_wood.selected_lots.size(), 2)
	assert_eq(two_wood.selected_lots[0].lot_id, &"free_wood_a")
	assert_eq(two_wood.selected_lots[0].selected_quantity, 5)
	assert_eq(two_wood.selected_lots[0].residual_quantity, 1)
	assert_eq(two_wood.selected_lots[1].lot_id, &"free_wood_b")
	assert_eq(two_wood.selected_lots[1].selected_quantity, 4)
	assert_eq(two_wood.selected_lots[1].residual_quantity, 0)
	assert_eq(two_wood.deliverable_amounts, {&"wood": 9})
	assert_eq(two_wood.after.cargo.amounts, {&"stone": 3, &"wood": 1})

	# Scenario 4: wood + stone together
	var multi_res := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_multi_res", []
	)
	_assert_safe_dry_run_flags(multi_res, true)
	assert_eq(multi_res.deliverable_amounts, {&"stone": 3, &"wood": 10})
	assert_eq(multi_res.selected_lots.size(), 3)
	assert_eq(multi_res.selected_lots[0].resource_id, &"stone")
	assert_eq(multi_res.selected_lots[1].lot_id, &"free_wood_a")
	assert_eq(multi_res.selected_lots[2].lot_id, &"free_wood_b")
	assert_eq(multi_res.after.weight, 0)


func test_group_a_empty_request_conservative_free_only_policy() -> void:
	# Scenario 5: empty request with multiple origins selects ONLY FREE_GATHERED;
	# pure SITE_RESERVED rejects with no_eligible_free_lots and lists blocked_lots.
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_a := _create_site(fx, &"house_a", {&"wood": 6})
	var unit := _unit(fx, &"worker_a5")
	_withdraw(fx, site_a, unit, fx.wood, 4, &"res_lot_a")

	# Only SITE_RESERVED present -> empty request refuses conservatively
	var only_reserved := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_empty_only_res", []
	)
	_assert_safe_dry_run_flags(only_reserved, false)
	assert_eq(only_reserved.reason, "no_eligible_free_lots")
	assert_eq(only_reserved.blocked_lots.size(), 1)
	assert_eq(only_reserved.blocked_lots[0].lot_id, &"res_lot_a")
	assert_eq(only_reserved.blocked_lots[0].reason, "explicit_selection_required")

	# Add FREE_GATHERED -> empty request selects ONLY FREE_GATHERED and keeps SITE_RESERVED intact
	_gather_res(fx, unit, WOOD, 5, &"op_g5", &"free_lot_5")
	var mixed_empty := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_empty_mixed", []
	)
	_assert_safe_dry_run_flags(mixed_empty, true)
	assert_eq(mixed_empty.selected_lots.size(), 1)
	assert_eq(mixed_empty.selected_lots[0].lot_id, &"free_lot_5")
	assert_eq(mixed_empty.deliverable_amounts, {&"wood": 5})
	assert_eq(mixed_empty.after.cargo.amounts, {&"wood": 4})
	assert_true((mixed_empty.after.cargo.ledger.lots as Dictionary).has(&"res_lot_a"))
	assert_eq(mixed_empty.blocked_lots.size(), 1)
	assert_eq(mixed_empty.blocked_lots[0].lot_id, &"res_lot_a")
	assert_eq(mixed_empty.blocked_lots[0].reason, "explicit_selection_required")


func test_group_a_invalid_requests_missing_excessive_nonpositive_duplicate_and_extra_fields() -> void:
	# Scenarios 6 (missing lot), 7 (excessive qty), 8 (zero/negative/bad type), 9 (duplicate)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_a6")
	_gather_res(fx, unit, WOOD, 5, &"op_g6", &"free_w6")

	# Scenario 6: nonexistent lot
	var r_missing := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_miss",
		[{"lot_id": &"does_not_exist", "amount": 1}]
	)
	_assert_safe_dry_run_flags(r_missing, false)
	assert_eq(r_missing.reason, "lot_not_found")

	# Scenario 7: excessive quantity
	var r_excess := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_excess",
		[{"lot_id": &"free_w6", "amount": 6}]
	)
	_assert_safe_dry_run_flags(r_excess, false)
	assert_eq(r_excess.reason, "requested_amount_exceeds_lot")

	# Scenario 8: zero, negative, float, string, non-array, extra forged field
	for bad_req: Variant in [
		[{"lot_id": &"free_w6", "amount": 0}],
		[{"lot_id": &"free_w6", "amount": -2}],
		[{"lot_id": &"free_w6", "amount": 2.5}],
		[{"lot_id": &"free_w6", "amount": "2"}],
		[{"lot_id": &"", "amount": 2}],
		[{"lot_id": &"free_w6", "amount": 2, "origin": CarryProvenanceLedger.FREE_GATHERED}],
		{"lot_id": &"free_w6", "amount": 2},
		"invalid",
	]:
		var r_bad := CampPlanner.prepare_selective_camp_delivery(
			fx.inventory, zone, unit, DEFAULT_REGION, &"op_bad", bad_req
		)
		_assert_safe_dry_run_flags(r_bad, false)
		assert_eq(r_bad.reason, "invalid_request", str(bad_req))

	# Scenario 9: duplicate entry (including String vs StringName alias)
	var r_dup := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_dup",
		[{"lot_id": &"free_w6", "amount": 2}, {"lot_id": "free_w6", "amount": 1}]
	)
	_assert_safe_dry_run_flags(r_dup, false)
	assert_eq(r_dup.reason, "duplicate_lot_request")


func test_group_a_deterministic_ordering_independent_of_request_and_insertion_order() -> void:
	# Scenario 10: deterministic ordering regardless of caller request order
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_a10")
	_gather_res(fx, unit, WOOD, 3, &"op_10_z", &"lot_z")
	_gather_res(fx, unit, STONE, 2, &"op_10_m", &"lot_m")
	_gather_res(fx, unit, WOOD, 4, &"op_10_a", &"lot_a")

	var plan_forward := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_det",
		[
			{"lot_id": &"lot_a", "amount": 2},
			{"lot_id": &"lot_m", "amount": 2},
			{"lot_id": &"lot_z", "amount": 3},
		]
	)
	var plan_reverse := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_det",
		[
			{"lot_id": &"lot_z", "amount": 3},
			{"lot_id": &"lot_m", "amount": 2},
			{"lot_id": &"lot_a", "amount": 2},
		]
	)
	_assert_safe_dry_run_flags(plan_forward, true)
	_assert_safe_dry_run_flags(plan_reverse, true)
	assert_true(CampPlanner._strict_equal(plan_forward, plan_reverse))


# ------------------------------------------------------------------------------
# GROUP B — PROVENANCE (Scenarios 11-20)
# ------------------------------------------------------------------------------

func test_group_b_free_and_reserved_wood_coexistence_and_combined_selection() -> void:
	# Scenario 11: FREE_GATHERED wood + SITE_RESERVED wood in the same backpack
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_a := _create_site(fx, &"site_b11", {&"wood": 8})
	var unit := _unit(fx, &"worker_b11")
	_withdraw(fx, site_a, unit, fx.wood, 4, &"res_w11")
	_gather_res(fx, unit, WOOD, 5, &"op_g11", &"free_w11")

	var combined := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b11_both",
		[{"lot_id": &"free_w11", "amount": 3}, {"lot_id": &"res_w11", "amount": 2}]
	)
	_assert_safe_dry_run_flags(combined, true)
	assert_eq(combined.deliverable_amounts, {&"wood": 5})
	assert_eq(combined.destination_classes.by_lot[&"free_w11"], CampPlanner.DEST_CAMP_FREE_STOCK)
	assert_eq(combined.destination_classes.by_lot[&"res_w11"], CampPlanner.DEST_SITE_RESERVED_RESTORATION)

	# Conservation: camp physical +5, camp free +3, camp reserved +2
	assert_eq(int(combined.after.camp_physical_amounts[&"wood"]), int(combined.before.camp_physical_amounts[&"wood"]) + 5)
	assert_eq(int(combined.after.camp_free_amounts[&"wood"]), int(combined.before.camp_free_amounts[&"wood"]) + 3)
	assert_eq(int(combined.after.camp_reserved_amounts[&"wood"]), int(combined.before.camp_reserved_amounts[&"wood"]) + 2)

	# Site A accounting: transit 4->2, reserved 4->6, buffer/consumed/required/missing unchanged
	var acc_b: Dictionary = combined.before.sites[site_a.site_id].accounting[&"wood"]
	var acc_a: Dictionary = combined.after.sites[site_a.site_id].accounting[&"wood"]
	assert_eq(int(acc_b.transit), 4)
	assert_eq(int(acc_a.transit), 2)
	assert_eq(int(acc_b.reserved), 4)
	assert_eq(int(acc_a.reserved), 6)
	assert_eq(int(acc_a.buffer), int(acc_b.buffer))
	assert_eq(int(acc_a.consumed), int(acc_b.consumed))
	assert_eq(int(acc_a.missing), int(acc_b.missing))
	assert_eq(int(acc_a.required), int(acc_b.required))
	assert_eq(combined.after.cargo.amounts, {&"wood": 4})
	assert_eq(int(combined.after.cargo.ledger.lots[&"free_w11"].quantity), 2)
	assert_eq(int(combined.after.cargo.ledger.lots[&"res_w11"].quantity), 2)
	assert_true(bool(combined.reservation_projection.requires_atomic_deposit_and_reservation))


func test_group_b_two_sites_same_resource_explicit_site_a_preserves_site_b() -> void:
	# Scenarios 12 (two sites), 13 (explicit site A), 14 (site B preserved)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_a := _create_site(fx, &"site_a", {&"wood": 6}, 6.0)
	var site_b := _create_site(fx, &"site_b", {&"wood": 5}, 12.0)
	var unit := _unit(fx, &"worker_b12")
	_withdraw(fx, site_a, unit, fx.wood, 4, &"lot_site_a")
	_withdraw(fx, site_b, unit, fx.wood, 3, &"lot_site_b")

	# Selecting more than lot_site_a must NEVER spill into lot_site_b
	var spill_attempt := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b12_spill",
		[{"lot_id": &"lot_site_a", "amount": 5}]
	)
	_assert_safe_dry_run_flags(spill_attempt, false)
	assert_eq(spill_attempt.reason, "requested_amount_exceeds_lot")

	# Explicit selection of site A returns only site A's 4 wood; site B is untouched
	var plan_a := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b13_a",
		[{"lot_id": &"lot_site_a", "amount": 4}]
	)
	_assert_safe_dry_run_flags(plan_a, true)
	assert_eq(plan_a.selected_lots.size(), 1)
	assert_eq(plan_a.selected_lots[0].lot_id, &"lot_site_a")
	assert_eq(plan_a.selected_lots[0].site_id, site_a.site_id)
	assert_eq(plan_a.deliverable_amounts, {&"wood": 4})
	assert_true((plan_a.after.sites as Dictionary).has(site_a.site_id))
	assert_false((plan_a.after.sites as Dictionary).has(site_b.site_id))
	assert_eq(plan_a.after.cargo.amounts, {&"wood": 3})
	assert_true((plan_a.after.cargo.ledger.lots as Dictionary).has(&"lot_site_b"))
	assert_eq(int(plan_a.after.cargo.ledger.lots[&"lot_site_b"].quantity), 3)
	assert_false((plan_a.after.cargo.ledger.lots as Dictionary).has(&"lot_site_a"))
	var res_merge: Dictionary = plan_a.deposit_projection.merges[0]
	assert_eq(int(res_merge.after_reservations[site_b.reservation_id]), int(res_merge.before_reservations[site_b.reservation_id]))
	assert_eq(int(res_merge.after_reservations[site_a.reservation_id]), int(res_merge.before_reservations[site_a.reservation_id]) + 4)


func test_group_b_generation_mismatch_and_insufficient_claim_and_invalid_site() -> void:
	# Scenarios 15 (generation mismatch), 16 (insufficient claim), 17 (invalid/missing site)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_a := _create_site(fx, &"site_gen", {&"wood": 6})
	var unit := _unit(fx, &"worker_b15")
	_withdraw(fx, site_a, unit, fx.wood, 4, &"lot_gen")

	# Scenario 15: generation mismatch
	var orig_gen: int = site_a._generation
	site_a._generation = orig_gen + 1
	var r_gen := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b15",
		[{"lot_id": &"lot_gen", "amount": 2}]
	)
	_assert_safe_dry_run_flags(r_gen, false)
	assert_eq(r_gen.reason, "generation_mismatch")
	site_a._generation = orig_gen

	# Scenario 16: insufficient transit claim
	var uid := unit.get_instance_id()
	var claim_amounts: Dictionary = site_a._transit_claims[uid]["amounts"]
	claim_amounts[&"wood"] = 2
	var r_claim := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b16",
		[{"lot_id": &"lot_gen", "amount": 2}]
	)
	_assert_safe_dry_run_flags(r_claim, false)
	assert_eq(r_claim.reason, "insufficient_transit_claim")
	claim_amounts[&"wood"] = 4

	# Scenario 17a: invalid/unconfigured site
	site_a._is_configured = false
	var r_inv := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b17_inv",
		[{"lot_id": &"lot_gen", "amount": 2}]
	)
	_assert_safe_dry_run_flags(r_inv, false)
	assert_eq(r_inv.reason, "invalid_site")
	site_a._is_configured = true

	# Scenario 17b: site removed from scene -> unknown_reserved_site
	var parent := site_a.get_parent()
	parent.remove_child(site_a)
	var r_unk := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b17_unk",
		[{"lot_id": &"lot_gen", "amount": 2}]
	)
	_assert_safe_dry_run_flags(r_unk, false)
	assert_eq(r_unk.reason, "unknown_reserved_site")
	parent.add_child(site_a)


func test_group_b_d3_cancellation_blocked_never_reclassified_to_free() -> void:
	# Scenario 18: material whose return depends on D3 cancellation remains blocked
	# and is NEVER auto-converted to FREE_GATHERED.
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_d3 := _create_site(fx, &"site_d3", {&"wood": 6})
	var unit := _unit(fx, &"worker_b18")
	_withdraw(fx, site_d3, unit, fx.wood, 3, &"lot_d3")
	_gather_res(fx, unit, WOOD, 4, &"op_g18", &"free_w18")

	for blocked_state: int in [
		ConstructionSite.SiteState.COMPLETED,
		ConstructionSite.SiteState.COMPLETING,
		ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE,
		ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR,
	]:
		site_d3._site_state = blocked_state as ConstructionSite.SiteState
		var r_explicit := CampPlanner.prepare_selective_camp_delivery(
			fx.inventory, zone, unit, DEFAULT_REGION, &"op_d3_exp",
			[{"lot_id": &"lot_d3", "amount": 3}]
		)
		_assert_safe_dry_run_flags(r_explicit, false)
		assert_eq(r_explicit.reason, "d3_cancellation_not_implemented")
		assert_eq(r_explicit.blocked_lots.size(), 1)
		assert_eq(r_explicit.blocked_lots[0].lot_id, &"lot_d3")

		# Empty default unloads ONLY free_w18 and keeps lot_d3 untouched as SITE_RESERVED
		var r_empty := CampPlanner.prepare_selective_camp_delivery(
			fx.inventory, zone, unit, DEFAULT_REGION, &"op_d3_empty", []
		)
		_assert_safe_dry_run_flags(r_empty, true)
		assert_eq(r_empty.selected_lots.size(), 1)
		assert_eq(r_empty.selected_lots[0].lot_id, &"free_w18")
		assert_eq(r_empty.blocked_lots.size(), 1)
		assert_eq(r_empty.blocked_lots[0].lot_id, &"lot_d3")
		assert_eq(r_empty.blocked_lots[0].reason, "d3_cancellation_not_implemented")
		assert_eq(r_empty.after.cargo.ledger.lots[&"lot_d3"].origin, CarryProvenanceLedger.SITE_RESERVED)
		assert_eq(int(r_empty.after.cargo.ledger.lots[&"lot_d3"].quantity), 3)

	site_d3._site_state = ConstructionSite.SiteState.ACTIVE


func test_group_b_corrupted_ledger_and_unreconciled_aggregate_rejected() -> void:
	# Scenarios 19 (inconsistent ledger) & 20 (aggregate mismatch with lots)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_b19")
	_gather_res(fx, unit, WOOD, 5, &"op_g19", &"free_w19")
	var load := unit.get_carry_load()

	# Scenario 19: corrupt internal ledger operations history
	var saved_ops: Dictionary = load._provenance._operations.duplicate(true)
	load._provenance._operations.clear()
	var r_ledger := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b19", []
	)
	_assert_safe_dry_run_flags(r_ledger, false)
	assert_eq(r_ledger.reason, "invalid_ledger")
	load._provenance._operations = saved_ops

	# Scenario 20: aggregate amount diverges from ledger lots
	load._amounts[&"wood"] = 7
	var r_agg := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b20", []
	)
	_assert_safe_dry_run_flags(r_agg, false)
	assert_eq(r_agg.reason, "unreconciled_cargo")
	load._amounts[&"wood"] = 5


# ------------------------------------------------------------------------------
# GROUP C — STORAGE PROJECTION (Scenarios 21-30)
# ------------------------------------------------------------------------------

func test_group_c_merge_existing_pile_and_exposure_policy() -> void:
	# Scenario 21: merge into existing pile preserving exposure policy
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	fx.wood.apply_state(10, 30.0, 4.0)
	var unit := _unit(fx, &"worker_c21")
	_gather_res(fx, unit, WOOD, 10, &"op_g21", &"free_w21")

	fx.manager.merge_exposure_policy = GroundPileManager.MergeExposurePolicy.WEIGHTED_AVERAGE
	var plan_avg := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c21_avg", []
	)
	_assert_safe_dry_run_flags(plan_avg, true)
	assert_eq(plan_avg.deposit_projection.merge_count, 1)
	assert_eq(plan_avg.deposit_projection.create_count, 0)
	var m_avg: Dictionary = plan_avg.deposit_projection.merges[0]
	assert_eq(m_avg.pile_id, fx.wood.pile_id)
	assert_eq(m_avg.before_amount, 10)
	assert_eq(m_avg.after_amount, 20)
	assert_near(float(m_avg.after_elapsed_exposure_sec), 15.0, 0.001)
	assert_near(float(m_avg.after_decay_accumulator_sec), 2.0, 0.001)

	fx.manager.merge_exposure_policy = GroundPileManager.MergeExposurePolicy.KEEP_OLDEST
	var plan_keep := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c21_keep", []
	)
	_assert_safe_dry_run_flags(plan_keep, true)
	var m_keep: Dictionary = plan_keep.deposit_projection.merges[0]
	assert_near(float(m_keep.after_elapsed_exposure_sec), 30.0, 0.001)
	assert_near(float(m_keep.after_decay_accumulator_sec), 4.0, 0.001)


func test_group_c_projected_new_pile_max_capacity_split_and_multiple_creates() -> void:
	# Scenarios 22 (new virtual pile), 23 (max_pile_amount merge+create), 24 (multiple creates in one plan)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_c22")
	var next_id_before: int = fx.manager._next_pile_id

	# Scenario 22: no existing FOOD pile -> creates virtual_pile:0
	_gather_res(fx, unit, FOOD, 5, &"op_g22_food", &"free_food_22")
	var plan_new := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c22",
		[{"lot_id": &"free_food_22", "amount": 5}]
	)
	_assert_safe_dry_run_flags(plan_new, true)
	assert_eq(plan_new.deposit_projection.merge_count, 0)
	assert_eq(plan_new.deposit_projection.create_count, 1)
	assert_eq(plan_new.deposit_projection.creates[0].virtual_pile_id, &"virtual_pile:0")
	assert_eq(plan_new.deposit_projection.creates[0].amount, 5)
	assert_eq(fx.manager._next_pile_id, next_id_before)

	# Scenario 23: max_pile_amount = 10, existing wood pile has 8 -> deliver 5 splits into merge(2) + create(3)
	zone.max_pile_amount = 10
	fx.wood.apply_state(8, 0.0, 0.0)
	_gather_res(fx, unit, WOOD, 5, &"op_g23_wood", &"free_wood_23")
	var plan_cap := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c23",
		[{"lot_id": &"free_wood_23", "amount": 5}]
	)
	_assert_safe_dry_run_flags(plan_cap, true)
	assert_eq(plan_cap.deposit_projection.merge_count, 1)
	assert_eq(plan_cap.deposit_projection.create_count, 1)
	assert_eq(plan_cap.deposit_projection.merges[0].add_amount, 2)
	assert_eq(plan_cap.deposit_projection.merges[0].after_amount, 10)
	assert_eq(plan_cap.deposit_projection.creates[0].amount, 3)
	assert_eq(plan_cap.deposit_projection.creates[0].virtual_pile_id, &"virtual_pile:0")

	# Scenario 24: multiple creates in same plan with max_pile_amount = 2 for 5 food -> 3 virtual piles with clearance
	zone.max_pile_amount = 2
	var plan_multi := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c24",
		[{"lot_id": &"free_food_22", "amount": 5}]
	)
	_assert_safe_dry_run_flags(plan_multi, true)
	assert_eq(plan_multi.deposit_projection.create_count, 3)
	assert_eq(plan_multi.deposit_projection.creates[0].virtual_pile_id, &"virtual_pile:0")
	assert_eq(plan_multi.deposit_projection.creates[0].amount, 2)
	assert_eq(plan_multi.deposit_projection.creates[1].virtual_pile_id, &"virtual_pile:1")
	assert_eq(plan_multi.deposit_projection.creates[1].amount, 2)
	assert_eq(plan_multi.deposit_projection.creates[2].virtual_pile_id, &"virtual_pile:2")
	assert_eq(plan_multi.deposit_projection.creates[2].amount, 1)
	# Verify all created virtual positions respect min_pile_clearance from one another
	for i: int in range(3):
		for j: int in range(i + 1, 3):
			var pi: Vector3 = plan_multi.deposit_projection.creates[i].world_pos
			var pj: Vector3 = plan_multi.deposit_projection.creates[j].world_pos
			var dist := Vector2(pi.x - pj.x, pi.z - pj.z).length()
			assert_true(dist >= zone.min_pile_clearance - 0.001, "Virtual slots overlap")
	assert_eq(fx.manager._next_pile_id, next_id_before)


func test_group_c_no_valid_slot_nav_not_ready_invalid_camp_and_unsupported_storage() -> void:
	# Scenarios 25 (no slot / nav not ready), 26 (invalid camp), 27 (unsupported storage source)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_c25")
	_gather_res(fx, unit, FOOD, 4, &"op_g25", &"free_food_25")

	# Scenario 25a: genuine no valid slot available (zone shrunk to anchor already occupied by wood pile)
	var saved_extents := zone.zone_bounds_half_extents
	zone.zone_bounds_half_extents = Vector2(0.5, 0.5)
	var r_noslot := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c25_slot", []
	)
	_assert_safe_dry_run_flags(r_noslot, false)
	assert_eq(r_noslot.reason, "no_valid_camp_slot")
	zone.zone_bounds_half_extents = saved_extents

	# Scenario 25b: WorldNavigation attached but not ready
	var nav := WorldNavigation.new()
	nav.auto_bake_on_ready = false
	fx.host.add_child(nav)
	zone.set_world_navigation(nav)
	var r_nav := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c25_nav", []
	)
	_assert_safe_dry_run_flags(r_nav, false)
	assert_eq(r_nav.reason, "navigation_not_ready")
	zone.set_world_navigation(null)

	# Scenario 26: invalid camp_zone (empty zone_id, null, wrong camp_zone)
	var saved_zone_id := zone.zone_id
	zone.zone_id = &""
	var r_bad_camp := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c26_a", []
	)
	_assert_safe_dry_run_flags(r_bad_camp, false)
	assert_eq(r_bad_camp.reason, "invalid_camp_zone")
	zone.zone_id = saved_zone_id

	var r_null_camp := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, null, unit, DEFAULT_REGION, &"op_c26_b", []
	)
	_assert_safe_dry_run_flags(r_null_camp, false)
	assert_eq(r_null_camp.reason, "invalid_camp_zone")

	# Scenario 27: unsupported storage source (InMemoryStorageSource)
	var in_mem := InMemoryStorageSource.new()
	var mem_inv := SettlementInventory.new(in_mem)
	var r_mem := CampPlanner.prepare_selective_camp_delivery(
		mem_inv, zone, unit, DEFAULT_REGION, &"op_c27", []
	)
	_assert_safe_dry_run_flags(r_mem, false)
	assert_eq(r_mem.reason, "unsupported_storage_source")


func test_group_c_preserves_existing_reservations_and_projects_virtual_pile_reservation() -> void:
	# Scenarios 28 (pre-existing reservations preserved) & 29 (reservation projected on newly planned virtual pile)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_a := _create_site(fx, &"site_c28_a", {&"wood": 6}, 6.0)
	var site_b := _create_site(fx, &"site_c28_b", {&"wood": 5}, 12.0)
	var unit := _unit(fx, &"worker_c28")
	_withdraw(fx, site_a, unit, fx.wood, 4, &"res_c28_a")
	_gather_res(fx, unit, WOOD, 3, &"op_g28", &"free_c28")

	# Scenario 28: merge free + site_a reserved into existing wood pile while site_b's 5 reserved are preserved
	var plan_merge := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c28",
		[{"lot_id": &"free_c28", "amount": 3}, {"lot_id": &"res_c28_a", "amount": 4}]
	)
	_assert_safe_dry_run_flags(plan_merge, true)
	var merge_entry: Dictionary = plan_merge.deposit_projection.merges[0]
	assert_eq(int(merge_entry.before_reservations[site_b.reservation_id]), 5)
	assert_eq(int(merge_entry.after_reservations[site_b.reservation_id]), 5)
	assert_eq(int(merge_entry.after_reservations[site_a.reservation_id]), int(merge_entry.before_reservations[site_a.reservation_id]) + 4)
	assert_eq(int(merge_entry.after_free_amount), int(merge_entry.before_free_amount) + 3)
	assert_eq(int(plan_merge.reservation_projection.preserved_existing_pile_reservations[fx.wood.pile_id][site_b.reservation_id]), 5)

	# Scenario 29: cap existing wood pile at current amount so site_a's 4 reserved MUST go to a new virtual pile
	zone.max_pile_amount = fx.wood.amount
	var plan_v := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c29",
		[{"lot_id": &"res_c28_a", "amount": 4}]
	)
	_assert_safe_dry_run_flags(plan_v, true)
	assert_eq(plan_v.deposit_projection.merge_count, 0)
	assert_eq(plan_v.deposit_projection.create_count, 1)
	var v_pile: Dictionary = plan_v.deposit_projection.creates[0]
	assert_eq(v_pile.virtual_pile_id, &"virtual_pile:0")
	assert_eq(v_pile.amount, 4)
	assert_eq(v_pile.reserved_amount, 4)
	assert_eq(v_pile.free_amount, 0)
	assert_eq(int(v_pile.reservations[site_a.reservation_id]), 4)
	assert_eq(plan_v.reservation_projection.restorations.size(), 1)
	var rest: Dictionary = plan_v.reservation_projection.restorations[0]
	assert_eq(rest.target_kind, &"virtual_pile")
	assert_eq(rest.virtual_pile_id, &"virtual_pile:0")
	assert_eq(rest.pile_id, 0)
	assert_eq(rest.amount, 4)
	assert_eq(rest.pile_reserved_before, 0)
	assert_eq(rest.pile_reserved_after, 4)
	assert_eq(rest.ledger_mode, &"bind_created_pile_id_on_commit")


func test_group_c_rejects_unprovable_reservation_physical_link() -> void:
	# Scenario 30: reject when physical link of reservation cannot be proven
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_a := _create_site(fx, &"site_c30_a", {&"wood": 6}, 6.0)
	var unit := _unit(fx, &"worker_c30")
	_withdraw(fx, site_a, unit, fx.wood, 3, &"res_c30")

	# 30a: overbooked pile reservation in ledger (reserved > physical amount)
	var saved_ledger: Dictionary = fx.manager._ledger.snapshot_state()
	fx.manager._ledger.allocate_on_pile(fx.wood.pile_id, &"wood", &"ghost_res", 999)
	var r_over := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c30_a",
		[{"lot_id": &"res_c30", "amount": 3}]
	)
	_assert_safe_dry_run_flags(r_over, false)
	assert_eq(r_over.reason, "reservation_restoration_unavailable")
	fx.manager._ledger.restore_state(saved_ledger)

	# 30b: orphan pile_id in reservation ledger pointing to nonexistent pile
	fx.manager._ledger.allocate_on_pile(99999, &"wood", &"orphan_res", 2)
	var r_orphan := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c30_b",
		[{"lot_id": &"res_c30", "amount": 3}]
	)
	_assert_safe_dry_run_flags(r_orphan, false)
	assert_eq(r_orphan.reason, "reservation_restoration_unavailable")
	fx.manager._ledger.restore_state(saved_ledger)

	# 30c: duplicate reservation_id across two live sites in same domain
	var site_b := _create_site(fx, &"site_c30_b", {&"stone": 2}, 12.0)
	var orig_rid_b := site_b.reservation_id
	site_b.reservation_id = site_a.reservation_id
	var r_dup_rid := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_c30_c",
		[{"lot_id": &"res_c30", "amount": 3}]
	)
	_assert_safe_dry_run_flags(r_dup_rid, false)
	assert_eq(r_dup_rid.reason, "reservation_restoration_unavailable")
	site_b.reservation_id = orig_rid_b


# ------------------------------------------------------------------------------
# GROUP D — REVISIONS & ANTI-ABA (Scenarios 31-40)
# ------------------------------------------------------------------------------

func test_group_d_immediate_validity_and_backpack_lot_and_added_resource_invalidation() -> void:
	# Scenarios 31 (valid immediately), 32 (backpack changed), 33 (lot replaced), 38 (resource added)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_d31")
	_gather_res(fx, unit, WOOD, 5, &"op_gd31", &"free_d31")

	var plan := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d31",
		[{"lot_id": &"free_d31", "amount": 3}]
	)
	_assert_safe_dry_run_flags(plan, true)

	# Scenario 31: immediately valid
	var v_ok := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan)
	assert_true(bool(v_ok.get("ok", false)), str(v_ok))
	assert_true(bool(v_ok.get("dry_run_only", false)))
	assert_false(bool(v_ok.get("commit_supported", true)))
	assert_false(bool(v_ok.get("physical_delivery_authorized", true)))

	# Scenario 38: another resource added to backpack invalidates plan
	_gather_res(fx, unit, STONE, 2, &"op_gd38", &"free_stone_38")
	var v_added := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan)
	_assert_safe_dry_run_flags(v_added, false)
	assert_eq(v_added.reason, "stale_revision")

	# Scenario 32: backpack changed (amount debited on same lot)
	var plan2 := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d32",
		[{"lot_id": &"free_d31", "amount": 2}]
	)
	_assert_safe_dry_run_flags(plan2, true)
	_debit_free_lot_for_test(unit.get_carry_load(), &"op_deb32", &"free_d31", 1)
	var v_deb := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan2)
	_assert_safe_dry_run_flags(v_deb, false)
	assert_eq(v_deb.reason, "stale_revision")

	# Scenario 33: lot replaced with another lot of equal quantity
	var plan3 := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d33",
		[{"lot_id": &"free_d31", "amount": 4}]
	)
	_assert_safe_dry_run_flags(plan3, true)
	_debit_free_lot_for_test(unit.get_carry_load(), &"op_clr33", &"free_d31", 4)
	_gather_res(fx, unit, WOOD, 4, &"op_rep33", &"free_d33_replacement")
	var v_rep := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan3)
	_assert_safe_dry_run_flags(v_rep, false)
	assert_eq(v_rep.reason, "lot_not_found")


func test_group_d_reservation_pile_slot_and_site_generation_invalidation() -> void:
	# Scenarios 34 (reservation changed), 35 (pile changed), 36 (slot invalidated), 37 (site generation changed)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_a := _create_site(fx, &"site_d34", {&"wood": 6})
	var unit := _unit(fx, &"worker_d34")
	_withdraw(fx, site_a, unit, fx.wood, 3, &"res_d34")
	_gather_res(fx, unit, FOOD, 4, &"op_gd34", &"free_food_34")

	# Scenario 34: reservation changed on camp ledger after preparation
	var plan_res := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d34",
		[{"lot_id": &"res_d34", "amount": 3}]
	)
	_assert_safe_dry_run_flags(plan_res, true)
	assert_true(fx.inventory.reserve_batch(&"other_res_34", {&"stone": 2}))
	var v_res := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan_res)
	_assert_safe_dry_run_flags(v_res, false)
	assert_eq(v_res.reason, "stale_revision")

	# Scenario 35: pile mutated after preparation
	var plan_pile := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d35",
		[{"lot_id": &"res_d34", "amount": 3}]
	)
	_assert_safe_dry_run_flags(plan_pile, true)
	assert_true(fx.manager.deposit(&"wood", 2))
	var v_pile := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan_pile)
	_assert_safe_dry_run_flags(v_pile, false)
	assert_eq(v_pile.reason, "stale_revision")

	# Scenario 36a: planned virtual slot physically occupied by a new pile after preparation
	var plan_slot := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d36",
		[{"lot_id": &"free_food_34", "amount": 4}]
	)
	_assert_safe_dry_run_flags(plan_slot, true)
	var chosen_pos: Vector3 = plan_slot.deposit_projection.creates[0].world_pos
	assert_not_null(fx.manager.try_create_pile_at(&"stone", 2, chosen_pos))
	var v_slot := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan_slot)
	_assert_safe_dry_run_flags(v_slot, false)
	assert_eq(v_slot.reason, "stale_revision")

	# Scenario 36b: planned virtual slot invalidated by shrinking camp bounds after preparation
	var plan_slot_bounds := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d36_bounds",
		[{"lot_id": &"free_food_34", "amount": 4}]
	)
	_assert_safe_dry_run_flags(plan_slot_bounds, true)
	var saved_extents := zone.zone_bounds_half_extents
	zone.zone_bounds_half_extents = Vector2(0.5, 0.5)
	var v_slot_bounds := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan_slot_bounds)
	_assert_safe_dry_run_flags(v_slot_bounds, false)
	assert_eq(v_slot_bounds.reason, "no_valid_camp_slot")
	zone.zone_bounds_half_extents = saved_extents

	# Scenario 37: site generation changed after preparation
	var plan_gen := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d37",
		[{"lot_id": &"free_food_34", "amount": 4}]
	)
	_assert_safe_dry_run_flags(plan_gen, true)
	var saved_gen: int = site_a._generation
	site_a._generation = saved_gen + 1
	var v_gen := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan_gen)
	_assert_safe_dry_run_flags(v_gen, false)
	assert_eq(v_gen.reason, "stale_revision")
	site_a._generation = saved_gen


func test_group_d_aba_protection_for_backpack_pile_reservation_and_camp_config() -> void:
	# Scenario 39: ABA cases (same final aggregates must still be rejected via revisions/IDs)
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_d39")
	_gather_res(fx, unit, WOOD, 5, &"op_g39_1", &"free_aba_1")

	# 39a: Backpack ABA (lose 2, regain 2 on a new lot, same aggregate wood=5) using empty default []
	var plan_bp := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d39_bp", []
	)
	_assert_safe_dry_run_flags(plan_bp, true)
	_debit_free_lot_for_test(unit.get_carry_load(), &"op_aba_w", &"free_aba_1", 2)
	_gather_res(fx, unit, WOOD, 2, &"op_aba_add", &"free_aba_2")
	assert_eq(unit.get_carry_load().get_amount(&"wood"), 5)
	var v_bp := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan_bp)
	_assert_safe_dry_run_flags(v_bp, false)
	assert_eq(v_bp.reason, "stale_revision")

	# 39b: Pile ABA (withdraw entire stone pile so it is removed, then recreate with exact same 8 stone)
	var plan_p := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d39_pile", []
	)
	_assert_safe_dry_run_flags(plan_p, true)
	var stone_pos: Vector3 = fx.manager.get_pile_world_position(fx.stone)
	assert_true(fx.manager.withdraw(&"stone", 8))
	assert_not_null(fx.manager.try_create_pile_at(&"stone", 8, stone_pos))
	assert_eq(fx.manager.get_physical_amount(&"stone"), 8)
	var v_p := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan_p)
	_assert_safe_dry_run_flags(v_p, false)
	assert_eq(v_p.reason, "stale_revision")

	# 39c: Reservation ABA (reserve 3 stone, then release 3 stone -> same 0 reserved, higher ledger revision)
	var plan_r := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d39_res", []
	)
	_assert_safe_dry_run_flags(plan_r, true)
	assert_true(fx.inventory.reserve_batch(&"aba_res", {&"stone": 3}))
	assert_true(fx.inventory.release_batch(&"aba_res"))
	assert_eq(fx.inventory.get_reserved_amount(&"stone"), 0)
	var v_r := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan_r)
	_assert_safe_dry_run_flags(v_r, false)
	assert_eq(v_r.reason, "stale_revision")

	# 39d: CampStorageZone config change (max_pile_amount)
	var plan_cfg := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d39_cfg", []
	)
	_assert_safe_dry_run_flags(plan_cfg, true)
	zone.max_pile_amount = 50
	var v_cfg := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan_cfg)
	_assert_safe_dry_run_flags(v_cfg, false)
	assert_eq(v_cfg.reason, "stale_revision")


func test_group_d_tampered_plan_rejection_including_flags_amounts_and_int_to_float() -> void:
	# Scenario 40: caller tampers with plan fields, safety flags, or int->float types
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_d40")
	_gather_res(fx, unit, WOOD, 6, &"op_g40", &"free_d40")

	var plan := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_d40",
		[{"lot_id": &"free_d40", "amount": 4}]
	)
	_assert_safe_dry_run_flags(plan, true)

	# Tamper commit_supported -> invalid_plan
	var t_commit := plan.duplicate(true)
	t_commit["commit_supported"] = true
	var r1 := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, t_commit)
	_assert_safe_dry_run_flags(r1, false)
	assert_eq(r1.reason, "invalid_plan")

	# Tamper physical_delivery_authorized -> invalid_plan
	var t_phys := plan.duplicate(true)
	t_phys["physical_delivery_authorized"] = true
	var r2 := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, t_phys)
	_assert_safe_dry_run_flags(r2, false)
	assert_eq(r2.reason, "invalid_plan")

	# Tamper deliverable_amounts int -> float (strict type check!)
	var t_float := plan.duplicate(true)
	t_float["deliverable_amounts"][&"wood"] = 4.0
	var r3 := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, t_float)
	_assert_safe_dry_run_flags(r3, false)
	assert_eq(r3.reason, "tampered_or_stale_plan")

	# Tamper deposit_projection add_amount
	var t_dep := plan.duplicate(true)
	t_dep["deposit_projection"]["merges"][0]["add_amount"] = 99
	var r4 := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, t_dep)
	_assert_safe_dry_run_flags(r4, false)
	assert_eq(r4.reason, "tampered_or_stale_plan")

	# Tamper identity region_id
	var t_id := plan.duplicate(true)
	t_id["identity"]["region_id"] = &"other_region"
	var r5 := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, t_id)
	_assert_safe_dry_run_flags(r5, false)
	assert_eq(r5.reason, "identity_mismatch")

	# Tamper requested_lots without updating selected_lots
	var t_req := plan.duplicate(true)
	t_req["requested_lots"][0]["amount"] = 5
	var r6 := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, t_req)
	_assert_safe_dry_run_flags(r6, false)
	assert_eq(r6.reason, "tampered_or_stale_plan")


# ------------------------------------------------------------------------------
# GROUP E — PURITY & ISOLATION (Scenarios 41-53 + Regional/World/Busy/Conflict)
# ------------------------------------------------------------------------------

func test_group_e_full_observational_purity_and_repeatability_on_prepare_and_validate() -> void:
	# Scenarios 41-53: zero mutations across backpack, ledger, piles, reservations, claims,
	# receipts, regional serials, authority creation, signals, listeners, revisions, nodes,
	# repeatability, and validate purity.
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit_free_only := _unit(fx, &"worker_e_no_auth")
	_gather_res(fx, unit_free_only, WOOD, 4, &"op_ge_free", &"free_e1")
	_gather_res(fx, unit_free_only, FOOD, 3, &"op_ge_food", &"free_e_food")

	var empty_sites: Array[ConstructionSite] = []
	var events_no_auth := _observe(fx, empty_sites, unit_free_only)
	var snap_before_no_auth := _camp_snapshot(fx, empty_sites, unit_free_only)
	assert_false(bool(snap_before_no_auth["authority_present"]))

	var p_a := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit_free_only, DEFAULT_REGION, &"op_e_repeat", []
	)
	var p_b := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit_free_only, DEFAULT_REGION, &"op_e_repeat", []
	)
	_assert_safe_dry_run_flags(p_a, true)
	assert_true(CampPlanner._strict_equal(p_a, p_b))
	assert_true(bool(CampPlanner.validate_selective_camp_delivery_plan(
		fx.inventory, zone, unit_free_only, DEFAULT_REGION, p_a
	).get("ok", false)))
	assert_eq(events_no_auth.size(), 0)
	assert_eq(_camp_snapshot(fx, empty_sites, unit_free_only), snap_before_no_auth)
	assert_false(unit_free_only.get_world_3d().has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))

	# Now test mixed FREE + SITE_RESERVED with active sites, receipts, and authority present
	var site_a := _create_site(fx, &"site_e_a", {&"wood": 8}, 6.0)
	var site_b := _create_site(fx, &"site_e_b", {&"wood": 5}, 12.0)
	var unit := _unit(fx, &"worker_e_mixed")
	_withdraw(fx, site_a, unit, fx.wood, 4, &"res_e_a")
	_withdraw(fx, site_b, unit, fx.wood, 2, &"res_e_b")
	_gather_res(fx, unit, WOOD, 5, &"op_ge_w", &"free_e_w")
	_gather_res(fx, unit, FOOD, 4, &"op_ge_f", &"free_e_f")

	var sites: Array[ConstructionSite] = [site_a, site_b]
	var events := _observe(fx, sites, unit)
	var snap_before := _camp_snapshot(fx, sites, unit)

	var plan1 := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e_full",
		[
			{"lot_id": &"free_e_w", "amount": 3},
			{"lot_id": &"free_e_f", "amount": 4},
			{"lot_id": &"res_e_a", "amount": 4},
		]
	)
	var plan2 := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e_full",
		[
			{"lot_id": &"res_e_a", "amount": 4},
			{"lot_id": &"free_e_f", "amount": 4},
			{"lot_id": &"free_e_w", "amount": 3},
		]
	)
	_assert_safe_dry_run_flags(plan1, true)
	assert_true(CampPlanner._strict_equal(plan1, plan2))

	# Also run failing preparation and failing validation to ensure failure paths are equally pure
	var fail_plan := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e_fail",
		[{"lot_id": &"nonexistent_e", "amount": 1}]
	)
	_assert_safe_dry_run_flags(fail_plan, false)

	var val_ok := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, plan1)
	assert_true(bool(val_ok.get("ok", false)))
	var tampered := plan1.duplicate(true)
	tampered["deliverable_amounts"][&"wood"] = 999
	var val_bad := CampPlanner.validate_selective_camp_delivery_plan(fx.inventory, zone, unit, DEFAULT_REGION, tampered)
	_assert_safe_dry_run_flags(val_bad, false)

	assert_eq(events.size(), 0)
	assert_eq(_camp_snapshot(fx, sites, unit), snap_before)


func test_group_e_regional_world_isolation_busy_guards_and_operation_conflict() -> void:
	# Cross-world, wrong region, authority busy/receipt conflict, storage/inventory/load/site busy,
	# ambiguous unit identity, and provenance disabled.
	var fx := _fixture(&"region_alpha")
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_a := _create_site(fx, &"site_iso_a", {&"wood": 6})
	var unit := _unit(fx, &"worker_iso")
	_withdraw(fx, site_a, unit, fx.wood, 3, &"res_iso_a")
	_gather_res(fx, unit, WOOD, 4, &"op_g_iso", &"free_iso")

	# Wrong region for this storage/domain -> region_mismatch
	var r_reg := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, &"region_beta", &"op_iso_reg", []
	)
	_assert_safe_dry_run_flags(r_reg, false)
	assert_eq(r_reg.reason, "region_mismatch")

	# Separate World3D -> world_mismatch
	var fx2 := _fixture(&"region_alpha")
	var foreign_unit := _unit(fx2, &"worker_foreign")
	_gather_res(fx2, foreign_unit, WOOD, 2, &"op_gf", &"free_foreign")
	var r_world := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, foreign_unit, &"region_alpha", &"op_iso_world", []
	)
	_assert_safe_dry_run_flags(r_world, false)
	assert_eq(r_world.reason, "world_mismatch")

	# Operation conflict against regional authority receipt (reusing withdrawal op ID)
	var r_receipt := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, &"region_alpha", &"pickup_res_iso_a", []
	)
	_assert_safe_dry_run_flags(r_receipt, false)
	assert_eq(r_receipt.reason, "operation_conflict")

	# Operation conflict against backpack ledger operation history
	var r_led_op := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, &"region_alpha", &"op_g_iso", []
	)
	_assert_safe_dry_run_flags(r_led_op, false)
	assert_eq(r_led_op.reason, "operation_conflict")

	# RegionalAuthority executing -> busy
	var domains: Dictionary = unit.get_world_3d().get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var auth := domains[&"region_alpha"] as ReservedWithdrawalCoordinator.RegionalAuthority
	auth.is_executing = true
	var r_auth_busy := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, &"region_alpha", &"op_iso_busy1", []
	)
	_assert_safe_dry_run_flags(r_auth_busy, false)
	assert_eq(r_auth_busy.reason, "busy")
	auth.is_executing = false

	# Storage locked -> busy
	fx.manager._is_mutating = true
	var r_stor_busy := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, &"region_alpha", &"op_iso_busy2", []
	)
	_assert_safe_dry_run_flags(r_stor_busy, false)
	assert_eq(r_stor_busy.reason, "busy")
	fx.manager._is_mutating = false

	# Site busy -> busy
	site_a._is_preparing_or_transacting = true
	var r_site_busy := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, &"region_alpha", &"op_iso_busy3", []
	)
	_assert_safe_dry_run_flags(r_site_busy, false)
	assert_eq(r_site_busy.reason, "busy")
	site_a._is_preparing_or_transacting = false

	# Provenance disabled -> provenance_disabled
	var legacy_unit := _unit(fx, &"worker_legacy", false)
	var r_legacy := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, legacy_unit, &"region_alpha", &"op_iso_leg", []
	)
	_assert_safe_dry_run_flags(r_legacy, false)
	assert_eq(r_legacy.reason, "provenance_disabled")

	# Ambiguous unit identity (two live units sharing same provenance unit_id in domain)
	var clone_unit := _unit(fx, &"worker_iso")
	_gather_res(fx, clone_unit, WOOD, 1, &"op_g_clone", &"free_clone")
	var r_ambig := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, clone_unit, &"region_alpha", &"op_iso_ambig", []
	)
	_assert_safe_dry_run_flags(r_ambig, false)
	assert_eq(r_ambig.reason, "ambiguous_unit_identity")


# ------------------------------------------------------------------------------
# R1 POST-AUDIT FIXES — UNTRUSTED CALLBACK BOUNDARY (§4) & RAW _piles INTEGRITY (§5)
# ------------------------------------------------------------------------------

func test_r1_untrusted_callback_storage_mutation_refused_without_execution() -> void:
	# §4.1: Custom validator attempting to mutate storage/pile amounts is refused before execution.
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_r1_41")
	_gather_res(fx, unit, FOOD, 4, &"op_r1_g41_f", &"free_r1_food_41")
	_gather_res(fx, unit, WOOD, 3, &"op_r1_g41_w", &"free_r1_wood_41")

	var empty_sites: Array[ConstructionSite] = []
	var events := _observe(fx, empty_sites, unit)
	var called := [0]
	zone.set_custom_position_validator(func(_pos: Vector3) -> bool:
		called[0] += 1
		fx.wood.apply_state(999, 0.0, 0.0)
		fx.manager.deposit(&"wood", 5)
		return true
	)
	var snap_before := _camp_snapshot(fx, empty_sites, unit)

	# Both new-pile path (food) and merge-only path (wood) refuse untrusted custom validator
	var r_create := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_41_create",
		[{"lot_id": &"free_r1_food_41", "amount": 4}]
	)
	_assert_safe_dry_run_flags(r_create, false)
	assert_eq(r_create.reason, "unsafe_custom_position_validator")

	var r_merge := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_41_merge",
		[{"lot_id": &"free_r1_wood_41", "amount": 3}]
	)
	_assert_safe_dry_run_flags(r_merge, false)
	assert_eq(r_merge.reason, "unsafe_custom_position_validator")

	assert_eq(called[0], 0, "Untrusted custom validator must never execute during preparation")
	assert_eq(fx.wood.amount, 20)
	assert_eq(events.size(), 0)
	assert_eq(_camp_snapshot(fx, empty_sites, unit), snap_before)
	zone.set_custom_position_validator(Callable())


func test_r1_untrusted_callback_pile_creation_refused_without_execution() -> void:
	# §4.2: Custom validator attempting to create a physical pile is refused before execution.
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_r1_42")
	_gather_res(fx, unit, FOOD, 3, &"op_r1_g42", &"free_r1_food_42")
	var extra_slot: Vector3 = zone.get_candidate_slots()[3]

	var empty_sites: Array[ConstructionSite] = []
	var events := _observe(fx, empty_sites, unit)
	var called := [0]
	var next_id_before: int = fx.manager._next_pile_id
	zone.set_custom_position_validator(func(_pos: Vector3) -> bool:
		called[0] += 1
		fx.manager.try_create_pile_at(&"food", 1, extra_slot)
		return true
	)
	var snap_before := _camp_snapshot(fx, empty_sites, unit)

	var res := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_42", []
	)
	_assert_safe_dry_run_flags(res, false)
	assert_eq(res.reason, "unsafe_custom_position_validator")
	assert_eq(called[0], 0)
	assert_eq(fx.manager._next_pile_id, next_id_before)
	assert_eq(fx.manager._piles.size(), 2)
	assert_eq(events.size(), 0)
	assert_eq(_camp_snapshot(fx, empty_sites, unit), snap_before)
	zone.set_custom_position_validator(Callable())


func test_r1_untrusted_callback_reservation_mutation_refused_without_execution() -> void:
	# §4.3: Custom validator attempting to alter construction reservations is refused before execution.
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var site_a := _create_site(fx, &"site_r1_43", {&"wood": 8})
	var unit := _unit(fx, &"worker_r1_43")
	_withdraw(fx, site_a, unit, fx.wood, 4, &"res_r1_43")

	var sites: Array[ConstructionSite] = [site_a]
	var events := _observe(fx, sites, unit)
	var called := [0]
	zone.set_custom_position_validator(func(_pos: Vector3) -> bool:
		called[0] += 1
		fx.inventory.release_batch(site_a.reservation_id)
		fx.inventory.reserve_batch(&"rogue_res_43", {&"stone": 2})
		return true
	)
	var snap_before := _camp_snapshot(fx, sites, unit)

	var res := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_43",
		[{"lot_id": &"res_r1_43", "amount": 4}]
	)
	_assert_safe_dry_run_flags(res, false)
	assert_eq(res.reason, "unsafe_custom_position_validator")
	assert_eq(called[0], 0)
	assert_eq(fx.inventory.get_reservation_amount(site_a.reservation_id, &"wood"), 4)
	assert_false(fx.inventory.has_reservation(&"rogue_res_43"))
	assert_eq(events.size(), 0)
	assert_eq(_camp_snapshot(fx, sites, unit), snap_before)
	zone.set_custom_position_validator(Callable())


func test_r1_untrusted_callback_self_state_and_post_prepare_validation() -> void:
	# §4.4 (callback mutating external counter), §4.5 (callback added after valid plan), §4.6 (clean path).
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_r1_44")
	_gather_res(fx, unit, FOOD, 4, &"op_r1_g44_f", &"free_r1_food_44")
	_gather_res(fx, unit, WOOD, 3, &"op_r1_g44_w", &"free_r1_wood_44")

	var empty_sites: Array[ConstructionSite] = []
	var events := _observe(fx, empty_sites, unit)

	# §4.6: Prepare valid plans without custom validator (both virtual-create and merge-only)
	var plan_create := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_45_create",
		[{"lot_id": &"free_r1_food_44", "amount": 4}]
	)
	_assert_safe_dry_run_flags(plan_create, true)
	assert_true(bool(CampPlanner.validate_selective_camp_delivery_plan(
		fx.inventory, zone, unit, DEFAULT_REGION, plan_create
	).get("ok", false)))

	var plan_merge := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_45_merge",
		[{"lot_id": &"free_r1_wood_44", "amount": 3}]
	)
	_assert_safe_dry_run_flags(plan_merge, true)
	assert_true(bool(CampPlanner.validate_selective_camp_delivery_plan(
		fx.inventory, zone, unit, DEFAULT_REGION, plan_merge
	).get("ok", false)))

	# §4.4 & §4.5: Attach a stateful external counter callback after valid preparation
	var counter := [0]
	zone.set_custom_position_validator(func(_pos: Vector3) -> bool:
		counter[0] += 1
		return true
	)
	var snap_before := _camp_snapshot(fx, empty_sites, unit)

	var r_prep := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_44_self", []
	)
	_assert_safe_dry_run_flags(r_prep, false)
	assert_eq(r_prep.reason, "unsafe_custom_position_validator")

	var v_create := CampPlanner.validate_selective_camp_delivery_plan(
		fx.inventory, zone, unit, DEFAULT_REGION, plan_create
	)
	_assert_safe_dry_run_flags(v_create, false)
	assert_eq(v_create.reason, "unsafe_custom_position_validator")

	var v_merge := CampPlanner.validate_selective_camp_delivery_plan(
		fx.inventory, zone, unit, DEFAULT_REGION, plan_merge
	)
	_assert_safe_dry_run_flags(v_merge, false)
	assert_eq(v_merge.reason, "unsafe_custom_position_validator")

	assert_eq(counter[0], 0, "External counter must not be incremented")
	assert_eq(events.size(), 0)
	assert_eq(_camp_snapshot(fx, empty_sites, unit), snap_before)

	# Confirm CampStorageZone.validate_pile_position() itself remains unchanged (§3.2) and
	# would execute the callback if called directly, proving the planner boundary blocks it.
	var direct_val: Dictionary = zone.validate_pile_position(zone.get_candidate_slots()[3], [])
	assert_true(bool(direct_val.get("valid", false)))
	assert_eq(counter[0], 1, "Direct CampStorageZone.validate_pile_position must remain intact")

	# §4.6: Clearing the custom validator restores clean planning and validation
	zone.set_custom_position_validator(Callable())
	assert_true(bool(CampPlanner.validate_selective_camp_delivery_plan(
		fx.inventory, zone, unit, DEFAULT_REGION, plan_create
	).get("ok", false)))
	assert_true(bool(CampPlanner.validate_selective_camp_delivery_plan(
		fx.inventory, zone, unit, DEFAULT_REGION, plan_merge
	).get("ok", false)))


func test_r1_physical_pile_collection_integrity_and_no_implicit_cleanup() -> void:
	# §5.2: Raw internal `_piles` integrity checks without pruning/cleanup, plus ledger consistency.
	var fx := _fixture()
	var zone: CampStorageZone = fx.manager.get_camp_zone()
	var unit := _unit(fx, &"worker_r1_52")
	_gather_res(fx, unit, WOOD, 4, &"op_r1_g52", &"free_r1_w52")

	var empty_sites: Array[ConstructionSite] = []
	var events := _observe(fx, empty_sites, unit)

	# Baseline intact collection succeeds
	var baseline := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_52_ok", []
	)
	_assert_safe_dry_run_flags(baseline, true)
	var orig_piles_len: int = fx.manager._piles.size()
	var rev_before: int = fx.manager.get_transaction_revision()

	# 5.2a: Freed / invalid reference inside `storage._piles` (invisible to `get_piles()`)
	var freed_pile := GroundResourcePile.new()
	fx.manager._piles.append(freed_pile)
	freed_pile.free()
	assert_eq(fx.manager.get_piles().size(), orig_piles_len, "get_piles() hides freed references")
	assert_eq(fx.manager._piles.size(), orig_piles_len + 1)
	var r_freed := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_52_freed", []
	)
	_assert_safe_dry_run_flags(r_freed, false)
	assert_eq(r_freed.reason, "invalid_physical_pile_collection")
	assert_eq(fx.manager._piles.size(), orig_piles_len + 1, "Planner must NOT prune `_piles`")
	assert_eq(fx.manager.get_transaction_revision(), rev_before)
	fx.manager._piles.pop_back()

	# 5.2b: Unexpected null entry inside `storage._piles`
	fx.manager._piles.append(null)
	var r_null := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_52_null", []
	)
	_assert_safe_dry_run_flags(r_null, false)
	assert_eq(r_null.reason, "invalid_physical_pile_collection")
	assert_eq(fx.manager._piles.size(), orig_piles_len + 1, "Planner must NOT erase null entries")
	fx.manager._piles.pop_back()

	# 5.2c-1: Duplicate pile reference (same instance twice in `_piles`)
	fx.manager._piles.append(fx.wood)
	var r_dup_ref := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_52_dupref", []
	)
	_assert_safe_dry_run_flags(r_dup_ref, false)
	assert_eq(r_dup_ref.reason, "invalid_physical_pile_collection")
	assert_eq(fx.manager._piles.size(), orig_piles_len + 1)
	fx.manager._piles.pop_back()

	# 5.2c-2: Two distinct valid pile nodes sharing the same `pile_id`
	var dup_id_pile := GroundResourcePile.new()
	dup_id_pile._storage_owner = weakref(fx.manager)
	fx.manager._piles_root.add_child(dup_id_pile)
	dup_id_pile.configure_initial(fx.wood.pile_id, WOOD.duplicate() as ResourceDefinition, 5, Vector3(4, 0, 4))
	fx.manager._piles.append(dup_id_pile)
	var r_dup_id := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_52_dupid", []
	)
	_assert_safe_dry_run_flags(r_dup_id, false)
	assert_eq(r_dup_id.reason, "invalid_physical_pile_collection")
	assert_eq(fx.manager._piles.size(), orig_piles_len + 1)
	fx.manager._piles.pop_back()
	fx.manager._piles_root.remove_child(dup_id_pile)
	dup_id_pile.free()

	# 5.2d: Pile with incompatible `pile_id` (>= `_next_pile_id` and <= 0)
	var orig_wood_id: int = fx.wood.pile_id
	fx.wood.pile_id = fx.manager._next_pile_id
	var r_hi_id := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_52_hiid", []
	)
	_assert_safe_dry_run_flags(r_hi_id, false)
	assert_eq(r_hi_id.reason, "invalid_physical_pile_collection")

	fx.wood.pile_id = 0
	var r_zero_id := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_52_zeroid", []
	)
	_assert_safe_dry_run_flags(r_zero_id, false)
	assert_eq(r_zero_id.reason, "invalid_physical_pile_collection")
	fx.wood.pile_id = orig_wood_id

	# 5.2e: Orphan entry in reservation ledger (nonexistent pile_id)
	var saved_ledger: Dictionary = fx.manager._ledger.snapshot_state()
	fx.manager._ledger.allocate_on_pile(77777, &"wood", &"orphan_r1_52", 3)
	var r_orphan := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_52_orphan", []
	)
	_assert_safe_dry_run_flags(r_orphan, false)
	assert_eq(r_orphan.reason, "reservation_restoration_unavailable")
	fx.manager._ledger.restore_state(saved_ledger)

	# 5.2f: Restored intact collection passes cleanly and emitted zero signals
	assert_eq(events.size(), 0)
	var restored := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_r1_52_restored", []
	)
	_assert_safe_dry_run_flags(restored, true)
	assert_true(bool(CampPlanner.validate_selective_camp_delivery_plan(
		fx.inventory, zone, unit, DEFAULT_REGION, restored
	).get("ok", false)))
