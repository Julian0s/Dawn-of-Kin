extends "res://tests/framework/selective_site_delivery_fixture.gd"

const Delivery = preload("res://src/economy/selective_site_delivery_coordinator.gd")


func _at_dropoff(site: ConstructionSite, unit: Unit) -> void:
	unit.global_position = site.global_position + Vector3(1.7, 0, 0)
	assert_true(BuildSlotPlanner.is_unit_in_site_dropoff_range(unit.global_position, site,
		ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE, site.get_world_3d()))


func _transaction_snapshot(fx: Dictionary, site: ConstructionSite, unit: Unit) -> Dictionary:
	var snapshot := _snapshot(fx, [site], unit)
	var load := unit.get_carry_load()
	snapshot.site_supply = [site._was_fully_supplied, site._supply_rebalance_completed, site._starved_resources.duplicate()]
	snapshot.carry_state = [load.get_current_weight(), load._batch_depth, load._dirty_load, load._dirty_capacity]
	snapshot.signal_callbacks = load.load_changed.get_connections().map(func(entry: Dictionary) -> Callable: return entry.callable)
	snapshot.guards = [load.is_transaction_busy(), load._coordinator_transaction_locked,
		site.is_transaction_busy(), site._suppress_coordinator_signal_echo,
		fx.inventory.is_transaction_busy(), fx.manager.is_locked(), fx.coordinator.is_busy()]
	return snapshot


func test_selective_partial_and_maximum_delivery_preserve_mixed_cargo_and_peer_claims() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"a", {&"wood": 6, &"stone": 2})
	var other := _create_site(fx, &"b", {&"wood": 3}, 14)
	var unit := _unit(fx, &"carrier")
	var peer := _unit(fx, &"peer")
	_gather(fx, unit, 2)
	_withdraw(fx, site, unit, fx.wood, 3, &"z_a")
	_withdraw(fx, site, unit, fx.wood, 2, &"a_a")
	_withdraw(fx, site, unit, fx.stone, 2, &"stone_a")
	_withdraw(fx, other, unit, fx.wood, 3, &"other_b")
	_withdraw(fx, site, peer, fx.wood, 1, &"peer_a")
	_arm_order(site, unit)
	_at_dropoff(site, unit)

	var coordinator := Delivery.new()
	var load := unit.get_carry_load()
	var initial := load.provenance_snapshot()
	var reservations: Dictionary = fx.manager._ledger.snapshot_state()
	var physical: Dictionary = fx.inventory.get_all_physical_amounts()
	var events: Array[String] = []
	var state_events: Array[String] = []
	_watch(site.supply_completed, func(_site: ConstructionSite) -> void: events.append("full"))
	_watch(site.state_changed, func(_site: ConstructionSite) -> void: state_events.append("target"))
	_watch(other.state_changed, func(_site: ConstructionSite) -> void: state_events.append("peer"))
	var rejected := coordinator.execute_selective_site_delivery(site, unit, &"too_much", {&"wood": 6})
	assert_eq(rejected.get("reason"), "requested_amount_exceeds_eligible")
	assert_eq(load.provenance_snapshot(), initial)
	for invalid: Variant in [{&"wood": 1.0}, {&"wood": 0}, {&"wood": true}, [], null]:
		assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"bad", invalid).reason, "invalid_request")

	var plan := Planner.prepare_selective_site_delivery(site, unit, &"partial", {&"wood": 3, &"stone": 2})
	assert_true(plan.get("ok", false), str(plan))
	var result := coordinator.commit_prepared_selective_delivery(site, unit, plan)
	assert_eq(result.get("delivered_now"), 5, str(result))
	assert_eq(result.get("delivered_amounts"), {&"wood": 3, &"stone": 2})
	assert_eq(load.provenance_snapshot().ledger.lots, plan.after.cargo.ledger.lots)
	assert_eq(load.get_all_amounts(), {&"wood": 7})
	assert_eq(load.get_current_weight(), 7 * WOOD.unit_weight)
	assert_eq(site._read_transit_claim_for_unit_pure(unit.get_instance_id()), {&"wood": 2})
	assert_eq(site._read_transit_claim_for_unit_pure(peer.get_instance_id()), {&"wood": 1})
	assert_eq(other._read_transit_claim_for_unit_pure(unit.get_instance_id()), {&"wood": 3})
	assert_true(load.validate_provenance())
	assert_eq(state_events, ["target"])
	assert_false(site.is_fully_supplied())
	assert_eq(events, [])

	result = coordinator.execute_selective_site_delivery(site, unit, &"maximum")
	assert_eq(result.get("delivered_amounts"), {&"wood": 2}, str(result))
	assert_eq(load.get_all_amounts(), {&"wood": 5})
	assert_eq(load.provenance_snapshot().ledger.lots, {&"other_b": initial.ledger.lots[&"other_b"],
		&"free_wood": initial.ledger.lots[&"free_wood"]})
	assert_eq(site.get_delivered_buffer_amounts(), {&"wood": 5, &"stone": 2})
	assert_eq(site.get_consumed_amounts(), {&"wood": 0, &"stone": 0})
	assert_eq(site.get_work_progress_sec(), 0.0)
	assert_eq(events, [])
	_at_dropoff(site, peer)
	result = coordinator.execute_selective_site_delivery(site, peer, &"last_worker")
	assert_eq(result.get("delivered_amounts"), {&"wood": 1}, str(result))
	assert_true(site.is_fully_supplied())
	assert_eq(events, ["full"])
	assert_eq(coordinator.execute_selective_site_delivery(site, peer, &"empty").reason, "no_eligible_delivery")
	assert_eq(events, ["full"])
	assert_eq(fx.manager._ledger.snapshot_state(), reservations)
	assert_eq(fx.inventory.get_all_physical_amounts(), physical)
	assert_eq(site.get_delivered_buffer_amounts(), {&"wood": 6, &"stone": 2})
	assert_eq(state_events, ["target", "target", "target"])


func test_authorization_rechecks_range_order_role_tree_and_domain() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"a", {&"wood": 4})
	var other := _create_site(fx, &"b", {&"stone": 2}, 14)
	var unit := _unit(fx, &"carrier")
	_withdraw(fx, site, unit, fx.wood, 2, &"reserved")
	var coordinator := Delivery.new()
	var events := _observe(fx, [site, other], unit)
	_at_dropoff(site, unit)
	var plan := Planner.prepare_selective_site_delivery(site, unit, &"physical")
	unit.global_position = fx.wood.global_position
	var before := _transaction_snapshot(fx, site, unit)
	assert_eq(coordinator.commit_prepared_selective_delivery(site, unit, plan).reason, "out_of_site_dropoff_range")
	assert_eq(_transaction_snapshot(fx, site, unit), before)
	_at_dropoff(site, unit)
	var order := unit.get_current_order()
	# Controlled invalid assignment fixtures leave the underlying cargo unchanged.
	unit._current_order = null
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"physical").reason, "worker_order_not_eligible")
	var wrong_order := ConstructOrder.new(other, null, true)
	wrong_order.mark_running()
	unit._current_order = wrong_order
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"physical").reason, "worker_order_not_eligible")
	unit._current_order = order
	var worker: Dictionary = site._assigned_workers[unit.get_instance_id()]
	worker.role = ConstructionSite.WorkerRole.BUILDER
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"physical").reason, "worker_role_not_eligible")
	worker.role = ConstructionSite.WorkerRole.TRANSPORTER
	unit.cancel_current_order()
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"physical").reason, "worker_not_registered")
	assert_eq(site._read_transit_claim_for_unit_pure(unit.get_instance_id()), {&"wood": 2})
	assert_eq(unit.get_carry_load().get_amount(&"wood"), 2)
	_arm_order(site, unit, false)
	var another_world := _fixture()
	var remote_unit := _unit(another_world, &"remote")
	assert_eq(coordinator.execute_selective_site_delivery(site, remote_unit, &"physical").reason, "unit_world_mismatch")
	var region := site.region_id
	site.region_id = &"ambiguous"
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"physical").reason, "ambiguous_domain")
	site.region_id = region
	var detached := _unit(fx, &"queued")
	detached.queue_free()
	assert_eq(coordinator.execute_selective_site_delivery(site, detached, &"physical").reason, "invalid_unit")
	assert_eq(site.accept_delivery_from_carry_load(unit, unit.get_carry_load()), {})
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)
	assert_false(events.has("changed"))
	var result := coordinator.execute_selective_site_delivery(site, unit, &"physical")
	assert_eq(result.get("delivered_now"), 2, str(result))


func test_all_fault_boundaries_roll_back_and_preserve_listener_and_history() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"a", {&"wood": 2})
	var unit := _unit(fx, &"carrier")
	_withdraw(fx, site, unit, fx.wood, 2, &"reserved")
	_at_dropoff(site, unit)
	var coordinator := Delivery.new()
	var load := unit.get_carry_load()
	var uid := unit.get_instance_id()
	var listener: Callable = site._transit_claims[uid].callback
	var events := _observe(fx, [site], unit)
	var stages := ["before_ledger_debit", "after_ledger_debit", "after_carry_deduction",
		"after_claim_deduction", "after_buffer_credit", "during_final_invariants"]
	for fault: String in stages:
		var before := _transaction_snapshot(fx, site, unit)
		var plan := Planner.prepare_selective_site_delivery(site, unit, &"retry")
		var visited: Array[String] = []
		coordinator._fault_at = func(stage: String) -> bool:
			visited.append(stage)
			assert_true(load.is_transaction_busy() and site.is_transaction_busy())
			assert_eq(events, [])
			assert_eq(coordinator.get_receipt(&"retry"), {})
			return stage == fault
		var failure := coordinator.commit_prepared_selective_delivery(site, unit, plan)
		assert_eq(failure.get("reason"), "aborted_" + fault, str(failure))
		assert_eq(visited.back(), fault)
		var after := _transaction_snapshot(fx, site, unit)
		assert_eq(after.erase("load_revision"), true)
		assert_eq(before.erase("load_revision"), true)
		var before_site: Dictionary = before.sites[0]
		var after_site: Dictionary = after.sites[0]
		var prior_revision: int = before_site.revision
		var actual_revision: int = after_site.revision
		before_site.erase("revision")
		after_site.erase("revision")
		assert_eq(after, before, fault)
		assert_true(load.load_changed.is_connected(listener))
		assert_eq(events, [])
		var advances := fault != "before_ledger_debit"
		assert_eq(actual_revision > prior_revision, advances)
		assert_eq(load.get_transaction_revision() > int(plan.revisions.load), advances)
		if advances:
			assert_eq(Planner.validate_selective_site_delivery_plan(site, unit, plan).reason, "stale_revision")
	coordinator._fault_at = Callable()
	var success := coordinator.execute_selective_site_delivery(site, unit, &"retry")
	assert_eq(success.get("delivered_now"), 2, str(success))
	assert_false(load.load_changed.is_connected(listener))


func test_replay_commit_signals_and_reentry_across_coordinator_handles() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"a", {&"wood": 3})
	var unit := _unit(fx, &"carrier")
	_withdraw(fx, site, unit, fx.wood, 2, &"first")
	_withdraw(fx, site, unit, fx.wood, 1, &"second")
	_at_dropoff(site, unit)
	var coordinator := Delivery.new()
	var second_delivery := Delivery.new()
	var second_withdrawal := ReservedWithdrawalCoordinator.new()
	var unit_load := unit.get_carry_load()
	var events: Array[String] = []
	var world := unit.get_world_3d()
	var authority: ReservedWithdrawalCoordinator.RegionalAuthority = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META)[site.region_id]
	var second_worker := _unit(fx, &"another")
	var c2_calls: Array[Dictionary] = []
	_watch(unit_load.load_changed, func() -> void:
		events.append("load")
		assert_eq(unit_load.get_amount(&"wood"), 0)
		assert_eq(site.get_delivered_buffer_amount(&"wood"), 3)
		assert_eq(site._read_transit_claim_for_unit_pure(unit.get_instance_id()), {})
		assert_eq(coordinator.get_receipt(&"drop").get("delivered_amounts"), {&"wood": 3})
		assert_eq(second_delivery.execute_selective_site_delivery(site, unit, &"during").reason, "busy")
		assert_eq(Planner.prepare_selective_site_delivery(site, unit, &"during").reason, "busy")
		c2_calls.append(second_withdrawal.execute_reserved_withdrawal(
			site, unit, fx.wood.pile_id, &"wood", 1, &"during", &"later"))
		unit.cancel_current_order()
		assert_not_null(unit.get_current_order())
		assert_false(unit_load.set_base_capacity(1))
	)
	_watch(site.buffer_changed, func(_site: ConstructionSite) -> void:
		events.append("buffer")
		assert_true(site._was_fully_supplied)
		assert_true(authority.receipts.has(&"drop"))
	)
	_watch(site.state_changed, func(_site: ConstructionSite) -> void: events.append("state"))
	_watch(site.supply_completed, func(_site: ConstructionSite) -> void: events.append("supply"))
	_watch(fx.manager.reservations_changed, func() -> void: events.append("reservation"))
	_watch(fx.manager.storage_changed, func() -> void: events.append("storage"))
	var fresh := Planner.prepare_selective_site_delivery(site, unit, &"drop")
	var keys := fresh.keys()
	keys.reverse()
	var plan: Dictionary = {}
	for key: String in keys:
		plan[key] = fresh[key]
	var committed := coordinator.commit_prepared_selective_delivery(site, unit, plan)
	assert_true(committed.get("ok", false), str(committed))
	assert_eq(events, ["load", "buffer", "state", "supply"])
	assert_eq(c2_calls.size(), 1)
	assert_eq(c2_calls[0].reason, "busy")
	var state := _transaction_snapshot(fx, site, unit)
	var replay := second_delivery.commit_prepared_selective_delivery(site, unit, plan)
	assert_true(replay.get("replayed", false), str(replay))
	assert_eq(replay.get("delivered_now"), 0)
	assert_eq(replay.get("delivered_amounts"), {&"wood": 3})
	assert_eq(replay.get("receipt"), committed.get("receipt"))
	assert_true(second_delivery.execute_selective_site_delivery(site, unit, &"drop").get("replayed", false))
	var edited := plan.duplicate(true)
	edited.after.claim[&"wood"] = 3
	assert_eq(second_delivery.commit_prepared_selective_delivery(site, unit, edited).reason, "operation_conflict")
	assert_eq(second_delivery.execute_selective_site_delivery(site, unit, &"drop", {&"wood": 3}).reason, "operation_conflict")
	assert_eq(second_delivery.execute_selective_site_delivery(site, second_worker, &"drop").reason, "operation_conflict")
	assert_eq(second_delivery.execute_selective_site_delivery(site, unit, &"pickup_first").reason, "operation_conflict")
	assert_eq(second_withdrawal.execute_reserved_withdrawal(site, unit, fx.wood.pile_id,
		&"wood", 1, &"drop", &"later").reason, "operation_conflict")
	assert_eq(second_withdrawal.get_receipt(&"drop"), {})
	assert_eq(second_delivery.get_receipt(&"pickup_first"), {})
	assert_eq(_transaction_snapshot(fx, site, unit), state)
	assert_eq(events, ["load", "buffer", "state", "supply"])


func test_c2_publication_excludes_c3_and_legacy_receipts_are_validated() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"a", {&"wood": 4})
	var unit := _unit(fx, &"carrier")
	var c3 := Delivery.new()
	var replies: Array[Dictionary] = []
	var c2: ReservedWithdrawalCoordinator = fx.coordinator
	var callback := func() -> void:
		replies.append(c3.execute_selective_site_delivery(site, unit, &"drop"))
	_watch(unit.get_carry_load().load_changed, callback)
	_withdraw(fx, site, unit, fx.wood, 2, &"lot")
	assert_eq(replies.size(), 1)
	assert_eq(replies[0].reason, "busy")

	var authority: ReservedWithdrawalCoordinator.RegionalAuthority = unit.get_world_3d().get_meta(
		ReservedWithdrawalCoordinator.DOMAIN_META)[site.region_id]
	var record: Dictionary = authority.receipts[&"pickup_lot"]
	record.receipt.erase("kind")
	var result := c2.execute_reserved_withdrawal(site, unit, fx.wood.pile_id, &"wood", 2, &"pickup_lot", &"lot")
	assert_true(result.get("replayed", false), str(result) + " receipt: " + str(record.receipt))
	assert_eq(result.get("withdrawn"), 0)
	assert_eq(c3.execute_selective_site_delivery(site, unit, &"pickup_lot").reason, "operation_conflict")
	record.receipt.erase("committed_amount")
	assert_eq(c2.execute_reserved_withdrawal(site, unit, fx.wood.pile_id, &"wood", 2, &"pickup_lot", &"lot").reason,
		"operation_conflict")
	assert_eq(c2.get_receipt(&"pickup_lot"), {})
	assert_eq(replies.size(), 1)


func test_tampered_stale_and_inconsistent_preparations_cannot_commit() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"a", {&"wood": 4})
	var unit := _unit(fx, &"carrier")
	var load := unit.get_carry_load()
	_withdraw(fx, site, unit, fx.wood, 2, &"lot")
	_at_dropoff(site, unit)
	var coordinator := Delivery.new()
	var plan := Planner.prepare_selective_site_delivery(site, unit, &"plan")
	var edited := plan.duplicate(true)
	edited.lot_debits[0].lot_id = &"another"
	assert_eq(coordinator.commit_prepared_selective_delivery(site, unit, edited).reason, "tampered_or_stale_plan")
	load.set_base_capacity(79)
	load.set_base_capacity(80)
	assert_eq(coordinator.commit_prepared_selective_delivery(site, unit, plan).reason, "stale_revision")
	plan = Planner.prepare_selective_site_delivery(site, unit, &"plan")
	_gather(fx, unit, 1)
	assert_eq(coordinator.commit_prepared_selective_delivery(site, unit, plan).reason, "stale_revision")
	plan = Planner.prepare_selective_site_delivery(site, unit, &"plan")
	var peer := _unit(fx, &"peer")
	_withdraw(fx, site, peer, fx.wood, 1, &"third_party")
	assert_eq(coordinator.commit_prepared_selective_delivery(site, unit, plan).reason, "stale_revision")

	# Corrupt one internal checkpoint field at a time to exercise fail-closed admission.
	var events := _observe(fx, [site], unit)
	var ledger := load._provenance
	var record: Dictionary = ledger._operations[&"pickup_lot"].lot
	record.quantity += 1
	var before := _transaction_snapshot(fx, site, unit)
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"plan").reason, "invalid_ledger")
	assert_eq(_transaction_snapshot(fx, site, unit), before)
	record.quantity -= 1
	load._unit_weights[&"wood"] = 999
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"plan").reason, "resource_or_weight_mismatch")
	load._unit_weights[&"wood"] = WOOD.unit_weight
	site._generation += 1
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"plan").reason, "generation_mismatch")
	site._generation -= 1
	var amounts: Dictionary = site._transit_claims[unit.get_instance_id()].amounts
	amounts[&"wood"] = 3
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"plan").reason, "unreconciled_site_claim")
	amounts[&"wood"] = 2
	assert_eq(events, [])
	assert_eq(coordinator.get_receipt(&"plan"), {})
	site._delivered_buffer[&"wood"] = -1
	assert_eq(coordinator.execute_selective_site_delivery(site, unit, &"plan").reason, "accounting_invariant_violated")
	site._delivered_buffer[&"wood"] = 0


func test_simulated_and_commit_ids_probe_existing_operations_in_their_own_namespaces() -> void:
	var fx := _fixture()
	var site := _create_site(fx, &"a", {&"wood": 4})
	var unit := _unit(fx, &"carrier")
	var load := unit.get_carry_load()
	_withdraw(fx, site, unit, fx.wood, 2, &"lot")
	_at_dropoff(site, unit)
	assert_true(load.add_with_provenance(&"c3.1:4:drop:0", &"sim_collision", &"wood", WOOD.unit_weight,
		1, CarryProvenanceLedger.FREE_GATHERED).ok)
	assert_true(load.add_with_provenance(&"c3.2:4:drop:0", &"real_collision", &"wood", WOOD.unit_weight,
		1, CarryProvenanceLedger.FREE_GATHERED).ok)
	var peer := _unit(fx, &"peer")
	_arm_order(site, peer)
	var pile: GroundResourcePile = fx.wood
	peer.global_position = pile.global_position + Vector3(0.4, 0, 0)
	assert_eq(site.claim_pickup(peer, pile.pile_id, &"wood", 1), 1)
	assert_true(fx.coordinator.execute_reserved_withdrawal(site, peer, pile.pile_id, &"wood", 1,
		&"c3.2:4:drop:0:1", &"regional_collision").ok)
	var coordinator := Delivery.new()
	var plan := Planner.prepare_selective_site_delivery(site, unit, &"drop")
	assert_eq(plan.lot_debits[0].debit_operation_id, &"c3.1:4:drop:0:1")
	var result := coordinator.commit_prepared_selective_delivery(site, unit, plan)
	assert_eq(result.get("delivered_now"), 2, str(result))
	var operations: Dictionary = load.provenance_snapshot().ledger.operations
	assert_eq(operations[&"c3.2:4:drop:0:2"], {"kind": "withdraw", "lot_id": &"lot", "amount": 2})
	assert_eq(operations[&"c3.2:4:drop:0"].kind, "register")
	assert_eq(operations[&"c3.1:4:drop:0"].kind, "register")
	assert_false(operations.has(&"c3.1:4:drop:0:1"))
	assert_false(operations.has(&"c3.2:4:drop:0:1"))
	assert_eq(load.get_all_amounts(), {&"wood": 2})
	assert_eq(site._read_transit_claim_for_unit_pure(peer.get_instance_id()), {&"wood": 1})
	assert_true(load.validate_provenance())


func test_operation_ids_are_isolated_across_regions_and_worlds() -> void:
	var first := _fixture()
	var second := _fixture(&"neighbor", first.viewport)
	var third := _fixture()
	var coordinator := Delivery.new()
	var sites: Array[ConstructionSite] = []
	for fx: Dictionary in [first, second, third]:
		var site := _create_site(fx, &"a", {&"wood": 3})
		sites.append(site)
		var unit := _unit(fx, &"carrier")
		_withdraw(fx, site, unit, fx.wood, 2, &"shared_pickup")
		_at_dropoff(site, unit)
		var result := coordinator.execute_selective_site_delivery(site, unit, &"shared_delivery")
		assert_eq(result.get("delivered_now"), 2, str(result))
		assert_false(result.get("replayed", true))
		assert_eq(result.get("receipt", {}).get("identity", {}).get("site"), site.get_instance_id())
	assert_eq(sites[0].get_world_3d(), sites[1].get_world_3d())
	assert_ne(sites[0].region_id, sites[1].region_id)
	assert_ne(sites[0].get_world_3d(), sites[2].get_world_3d())
