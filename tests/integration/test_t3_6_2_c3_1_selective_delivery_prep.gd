extends "res://tests/framework/selective_site_delivery_fixture.gd"

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")


func _prepare(site: ConstructionSite, unit: Unit, amounts: Variant = {}, op: Variant = &"drop") -> Dictionary:
	return Planner.prepare_selective_site_delivery(site, unit, op, amounts)


func _validate(site: ConstructionSite, unit: Unit, plan: Variant) -> Dictionary:
	return Planner.validate_selective_site_delivery_plan(site, unit, plan)


func test_c2_cargo_mixed_origins_and_deterministic_partial_multiresource_plan() -> void:
	var fx := _fixture()
	var a := _create_site(fx, &"a", {&"wood": 8, &"stone": 3})
	var b := _create_site(fx, &"b", {&"wood": 5}, 14)
	var unit := _unit(fx, &"mixed")
	_gather(fx, unit, 2)
	_withdraw(fx, a, unit, fx.wood, 3, &"z_wood")
	_withdraw(fx, a, unit, fx.wood, 2, &"a_wood")
	_withdraw(fx, a, unit, fx.stone, 2, &"a_stone")
	_withdraw(fx, b, unit, fx.wood, 4, &"b_wood")
	var peer := _unit(fx, &"peer_worker")
	_withdraw(fx, a, peer, fx.wood, 1, &"peer_wood")
	unit.cancel_current_order()
	unit.global_position = Vector3(40, 0, 40)
	assert_false(BuildSlotPlanner.is_unit_in_site_dropoff_range(unit.global_position, a,
		ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE, unit.get_world_3d()))
	var events := _observe(fx, [a, b], unit)
	var before := _snapshot(fx, [a, b], unit)
	var plan := _prepare(a, unit, {&"wood": 3, &"stone": 2})
	assert_true(plan.get("ok", false), str(plan))
	assert_eq(plan.get("deliverable"), {&"wood": 3, &"stone": 2})
	assert_true(plan.get("dry_run_only", false))
	assert_false(plan.get("commit_supported", true))
	assert_false(plan.get("physical_delivery_authorized", true))
	if plan.ok:
		assert_eq(plan.lot_debits.map(func(debit: Dictionary) -> Variant: return debit.lot_id),
			[&"a_stone", &"a_wood", &"z_wood"])
		assert_eq(plan.lot_debits[2].before, 3)
		assert_eq(plan.lot_debits[2].delivered, 1)
		assert_eq(plan.lot_debits[2].after, 2)
		assert_eq(plan.after.cargo.amounts, {&"wood": 8})
		assert_eq(plan.after.claim, {&"wood": 2})
		assert_eq(plan.after.cargo.ledger.lots[&"free_wood"], plan.before.cargo.ledger.lots[&"free_wood"])
		assert_eq(plan.after.cargo.ledger.lots[&"b_wood"], plan.before.cargo.ledger.lots[&"b_wood"])
		assert_eq(plan.before.accounting[&"wood"].transit, 6)
		assert_eq(plan.after.accounting[&"wood"], {"required": 8, "reserved": 2, "transit": 3, "buffer": 3, "consumed": 0, "missing": 0})
		assert_eq(_prepare(a, unit, {&"stone": 2, &"wood": 3}), plan)
		assert_true(_validate(a, unit, plan).ok)
	var maximum := _prepare(a, unit)
	assert_eq(maximum.get("deliverable"), {&"wood": 5, &"stone": 2})
	assert_eq(_prepare(a, unit, {&"wood": 6}).get("reason"), "requested_amount_exceeds_eligible")
	assert_eq(_prepare(b, unit).get("deliverable"), {&"wood": 4})
	assert_eq(_snapshot(fx, [a, b], unit), before)
	assert_eq(events, [])


func test_bad_requests_id_conflicts_and_legacy_delivery() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 8})
	var unit := _unit(fx, &"carrier")
	assert_false(unit.get_world_3d().has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))
	var fresh := _snapshot(fx, [site], unit)
	assert_eq(_prepare(site, unit).reason, "no_eligible_delivery")
	assert_eq(_snapshot(fx, [site], unit), fresh)
	_withdraw(fx, site, unit, fx.wood, 2, &"reserved")
	var events := _observe(fx, [site], unit)
	var before := _snapshot(fx, [site], unit)
	for amounts: Variant in [[], null, {&"wood": -1}, {&"wood": 0}, {&"wood": 1.0}, {&"wood": true}, {123: 1}, {" ": 1}]:
		assert_eq(_prepare(site, unit, amounts).reason, "invalid_request")
	assert_eq(_prepare(site, unit, {&"stone": 1}).reason, "resource_not_required")
	assert_eq(_prepare(site, unit, {}, &" ").reason, "invalid_operation")
	assert_eq(_prepare(site, unit, {}, &"pickup_reserved").reason, "operation_conflict")
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_eq(events, [])
	var duplicate := _unit(fx, &"carrier")
	assert_eq(site.claim_pickup(duplicate, fx.wood.pile_id, &"wood", 1), 1)
	before = _snapshot(fx, [site], unit)
	assert_eq(_prepare(site, unit).reason, "ambiguous_unit_identity")
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_eq(events, [])
	site.release_pickup_claim(duplicate)
	var legacy := _unit(fx, &"legacy", false)
	var inventory: SettlementInventory = fx.inventory
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(fx.wood.pile_id, site.reservation_id,
		WOOD, 2, legacy.get_carry_load()), 2)
	site.record_withdrawn_for_site(legacy, &"wood", 2)
	assert_eq(_prepare(site, legacy).reason, "provenance_disabled")
	assert_eq(site.accept_delivery_from_carry_load(legacy, legacy.get_carry_load()), {&"wood": 2})
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 2)
	assert_false(legacy.get_carry_load().is_provenance_enabled())


func test_claim_generation_world_and_balance_rejections_are_pure() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 8})
	var unit := _unit(fx, &"carrier")
	_withdraw(fx, site, unit, fx.wood, 2, &"reserved")
	var remote := _fixture()
	var remote_unit := _unit(remote, &"remote")
	var load := unit.get_carry_load()
	var events := _observe(fx, [site], unit)
	assert_eq(_prepare(site, remote_unit).reason, "unit_world_mismatch")
	var entry: Dictionary = site._transit_claims[unit.get_instance_id()]
	for amount: int in [1, 3]:
		entry.amounts[&"wood"] = amount
		var before := _snapshot(fx, [site], unit)
		assert_eq(_prepare(site, unit).reason, "unreconciled_site_claim")
		assert_eq(_snapshot(fx, [site], unit), before)
	entry.amounts[&"wood"] = 2
	entry.carry_load = remote_unit.get_carry_load()
	assert_eq(_prepare(site, unit).reason, "carry_load_mismatch")
	entry.carry_load = load
	load._amounts[&"wood"] = 3
	assert_eq(_prepare(site, unit).reason, "unreconciled_cargo")
	load._amounts[&"wood"] = 2
	load._unit_weights[&"wood"] = 1
	assert_eq(_prepare(site, unit).reason, "resource_or_weight_mismatch")
	load._unit_weights[&"wood"] = WOOD.unit_weight
	site._generation += 1
	assert_eq(_prepare(site, unit).reason, "generation_mismatch")
	site._generation -= 1
	var region := site.region_id
	site.region_id = &"another_region"
	assert_eq(_prepare(site, unit).reason, "ambiguous_domain")
	site.region_id = region
	site._site_state = ConstructionSite.SiteState.COMPLETING
	assert_eq(_prepare(site, unit).reason, "site_not_active")
	site._site_state = ConstructionSite.SiteState.ACTIVE
	assert_true(_prepare(site, unit).ok)
	assert_eq(events, [])
	assert_true(CarryFixture.add_lot(load, &"unknown", &"unknown_lot", &"wood", WOOD.unit_weight, 1,
		CarryProvenanceLedger.SITE_RESERVED, &"unknown_site", 1).ok)
	events.clear()
	var snapshot := _snapshot(fx, [site], unit)
	assert_eq(_prepare(site, unit).reason, "unknown_reserved_site")
	assert_eq(_snapshot(fx, [site], unit), snapshot)
	assert_eq(events, [])


func test_plan_revalidation_rejects_payload_changes_and_participant_aba() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"a", {&"wood": 8})
	var peer := _create_site(fx, &"b", {&"wood": 4}, 14)
	var unit := _unit(fx, &"carrier")
	_withdraw(fx, site, unit, fx.wood, 3, &"lot_a")
	_withdraw(fx, peer, unit, fx.wood, 2, &"lot_b")
	var load := unit.get_carry_load()
	var events := _observe(fx, [site, peer], unit)
	var before := _snapshot(fx, [site, peer], unit)
	var plan := _prepare(site, unit, {&"wood": 1})
	assert_true(plan.ok)
	assert_true(_validate(site, unit, plan).ok)
	var edited := plan.duplicate(true)
	edited.lot_debits[0].lot_id = &"lot_b"
	assert_eq(_validate(site, unit, edited).reason, "tampered_or_stale_plan")
	edited = plan.duplicate(true)
	edited.identity.world = 123
	assert_eq(_validate(site, unit, edited).reason, "identity_mismatch")
	edited = plan.duplicate(true)
	edited.after.accounting[&"wood"].buffer = 1.0
	assert_false(_validate(site, unit, edited).ok)
	edited = plan.duplicate(true)
	edited.erase("before")
	assert_eq(_validate(site, unit, edited).reason, "invalid_plan")
	assert_eq(_snapshot(fx, [site, peer], unit), before)
	assert_eq(events, [])

	load.set_base_capacity(79)
	load.set_base_capacity(80)
	assert_eq(_validate(site, unit, plan).reason, "stale_revision")
	plan = _prepare(site, unit)
	_gather(fx, unit, 1)
	assert_eq(_validate(site, unit, plan).reason, "stale_revision")
	plan = _prepare(site, unit)
	peer._transaction_revision += 1
	assert_eq(_validate(site, unit, plan).reason, "stale_revision")
	plan = _prepare(site, unit)
	site._transit_claims[unit.get_instance_id()].amounts[&"wood"] = 2
	assert_eq(_validate(site, unit, plan).reason, "unreconciled_site_claim")
	site._transit_claims[unit.get_instance_id()].amounts[&"wood"] = 3
	site._generation += 1
	assert_eq(_validate(site, unit, plan).reason, "generation_mismatch")
	site._generation -= 1

	# A different worker races with preparation through the real legacy buffer API.
	plan = _prepare(site, unit)
	var legacy := _unit(fx, &"legacy", false)
	var inventory: SettlementInventory = fx.inventory
	assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(fx.wood.pile_id, site.reservation_id,
		WOOD, 1, legacy.get_carry_load()), 1)
	site.record_withdrawn_for_site(legacy, &"wood", 1)
	assert_eq(site.accept_delivery_from_carry_load(legacy, legacy.get_carry_load()), {&"wood": 1})
	var after_external_change := _snapshot(fx, [site, peer], unit)
	events.clear()
	assert_eq(_validate(site, unit, plan).reason, "stale_revision")
	assert_eq(_snapshot(fx, [site, peer], unit), after_external_change)
	assert_eq(events, [])


func test_simulated_id_collision_is_avoided_and_buffer_overbooking_is_refused() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 5})
	var unit := _unit(fx, &"carrier")
	_withdraw(fx, site, unit, fx.wood, 2, &"reserved")
	var load := unit.get_carry_load()
	assert_true(CarryFixture.add_lot(load, &"c3.1:4:drop:0", &"unrelated", &"wood",
		WOOD.unit_weight, 1, CarryProvenanceLedger.FREE_GATHERED).ok)
	var events := _observe(fx, [site], unit)
	var before := _snapshot(fx, [site], unit)
	var plan := _prepare(site, unit)
	assert_eq(plan.get("deliverable"), {&"wood": 2})
	assert_eq(plan.lot_debits[0].debit_operation_id, &"c3.1:4:drop:0:1")
	assert_true(_validate(site, unit, plan).ok)
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_eq(_prepare(site, unit, {}, &"distinct").get("deliverable"), {&"wood": 2})
	assert_eq(_snapshot(fx, [site], unit), before)
	# Inject inconsistent accounting while the ledger and current worker's claim still agree.
	site._delivered_buffer[&"wood"] = 1
	before = _snapshot(fx, [site], unit)
	assert_eq(_prepare(site, unit, {}, &"distinct").reason, "accounting_invariant_violated")
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_eq(events, [])


func test_valid_plan_can_be_prepared_without_creating_an_authority() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"site", {&"wood": 5})
	var unit := _unit(fx, &"carrier")
	var load := unit.get_carry_load()
	# Controlled bootstrap of an existing reconciled cargo without registering a C2 receipt.
	assert_true(fx.manager.withdraw_reserved_from_pile(fx.wood.pile_id, site.reservation_id, &"wood", 2))
	assert_true(CarryFixture.add_lot(load, &"historical", &"lot", &"wood", WOOD.unit_weight, 2,
		CarryProvenanceLedger.SITE_RESERVED, site.site_id, site.get_generation()).ok)
	site._ensure_transit_listener(unit, load)
	site._transit_claims[unit.get_instance_id()].amounts[&"wood"] = 2
	var events := _observe(fx, [site], unit)
	var before := _snapshot(fx, [site], unit)
	var plan := _prepare(site, unit)
	assert_eq(plan.get("deliverable"), {&"wood": 2})
	assert_true(_validate(site, unit, plan).ok)
	assert_eq(_snapshot(fx, [site], unit), before)
	assert_false(unit.get_world_3d().has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))
	assert_eq(events, [])
