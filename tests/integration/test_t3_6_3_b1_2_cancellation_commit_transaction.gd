extends TestCase

const MAIN := preload("res://src/main/main.tscn")
const SHELTER := preload("res://data/buildings/shelter_basic.tres")
const COORD := preload("res://src/economy/reserved_withdrawal_coordinator.gd")


func _fixture(automatic_recovery: bool = false) -> MainScene:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_test_child(viewport)
	var main := MAIN.instantiate() as MainScene
	# These primitive transaction tests control transport explicitly. B1.4 opts in.
	main.automatic_cancellation_recovery = automatic_recovery
	viewport.add_child(main)
	main.get_economy_clock().set_process(false)
	var nav := main.get_test_map().get_navigation()
	for frame: int in range(180):
		if nav.is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(nav.is_navigation_ready())
	return main


func _site(main: MainScene, pos: Vector3) -> ConstructionSite:
	var result := main.get_construction_manager().try_create_site_from_placement(SHELTER, pos)
	assert_true(result.ok, str(result))
	return result.get("site") as ConstructionSite


func before_each() -> void:
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0


func after_each() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


func _until(condition: Callable, limit: int = 3600) -> bool:
	for frame: int in range(limit):
		if condition.call():
			return true
		await wait_physics_frames(1)
	return false


func _withdraw(main: MainScene, site: ConstructionSite, worker: Unit, op: StringName, lot: StringName) -> void:
	var entries := main.get_settlement_inventory().get_reserved_pile_entries(site.reservation_id, &"wood")
	assert_false(entries.is_empty())
	if entries.is_empty():
		return
	var entry := entries[0]
	worker.global_position = entry.world_pos
	var order := ConstructOrder.new(site, main.get_camp_storage_zone(), true, true, false)
	worker.issue_order(order)
	assert_true(order.is_active(), order.failure_reason)
	assert_eq(site.claim_pickup(worker, entry.pile_id, &"wood", 2, entry.reserved_amount), 2)
	var taken := COORD.new().execute_reserved_withdrawal(site, worker, entry.pile_id, &"wood", 2, op, lot)
	assert_true(taken.ok, str(taken))


func test_cancel_active_site_without_crediting_unrecovered_cargo() -> void:
	var main := await _fixture()
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 24))
	assert_true(inv.deposit(&"stone", 12))
	var site := _site(main, Vector3(-6.0, 0, 1.5))
	var peer := _site(main, Vector3(0.37, 0, -13.19))
	if site == null or peer == null:
		return
	var physical := inv.get_all_physical_amounts()
	var other := inv.get_reservation_amounts(peer.reservation_id)
	var target_id := site.reservation_id
	var peer_region := peer.region_id
	peer.region_id = &"other_region_with_shared_storage"
	assert_eq(COORD.prepare_site_cancellation(site, &"b12_test_release").reason, "ambiguous_domain")
	assert_eq(inv.get_all_physical_amounts(), physical)
	assert_true(inv.has_reservation(target_id))
	peer.region_id = peer_region
	var result := COORD.execute_site_cancellation(site, &"b12_test_release")
	assert_true(result.ok, str(result))
	if not result.ok:
		return
	assert_false(inv.has_reservation(target_id))
	assert_eq(inv.get_all_physical_amounts(), physical)
	assert_eq(inv.get_reservation_amounts(peer.reservation_id), other)
	assert_false(main.get_construction_manager().has_site_overlapping_rect(site.get_footprint_rect()))
	var again := COORD.execute_site_cancellation(site, &"b12_test_release")
	assert_true(again.ok and again.replayed)
	assert_eq(again.receipt, result.receipt)
	assert_false(COORD.execute_site_cancellation(peer, &"b12_test_release").ok)
	assert_false(COORD.execute_site_cancellation(site, &"b12_second").ok)
	assert_true(main.get_command_controller().command_units_to_site(peer, [main.get_units()[0]]))


func test_mixed_cargo_and_every_precommit_rollback() -> void:
	var main := await _fixture()
	var inv := main.get_settlement_inventory()
	var gpm := main.get_ground_pile_manager()
	assert_true(inv.deposit(&"wood", 24))
	assert_true(inv.deposit(&"stone", 12))
	var a := _site(main, Vector3(-6.0, 0, 1.5))
	var b := _site(main, Vector3(0.37, 0, -13.19))
	if a == null or b == null:
		return
	var unit := main.get_units()[0]
	var load := unit.get_carry_load()
	for source: ResourceSource in main.get_test_map().get_resource_sources():
		if source.definition.resource_id == &"food":
			var harvested := source.transfer_to_carry_load_with_provenance(load, &"b12_crop", &"b12_free", 1)
			assert_true(harvested.ok, str(harvested))
			break
	_withdraw(main, a, unit, &"b12_take_a", &"b12_lot_a")
	_withdraw(main, b, unit, &"b12_take_b", &"b12_lot_b")
	unit.issue_order(MoveOrder.new(unit.global_position + Vector3(1.0, 0, 0)))
	var move := unit.get_current_order()
	assert_true(move is MoveOrder)
	var colleague := main.get_units()[1]
	assert_true(main.get_command_controller().command_units_to_site(a, [colleague]))
	var before := load.provenance_snapshot()
	var claims_a := a._transit_claims.duplicate(true)
	var claims_b := b._transit_claims.duplicate(true)
	var buffer_before := a.get_delivered_buffer_amounts()
	var workers_before := a._assigned_workers.duplicate(true)
	var reserved_before := gpm._ledger.snapshot_state()
	var physical := inv.get_all_physical_amounts()
	var events: Array[String] = []
	var signal_probe := func() -> void: events.append("cargo")
	var reserve_probe := func() -> void: events.append("reserves")
	var site_probe := func(_site: ConstructionSite) -> void: events.append("site")
	load.load_changed.connect(signal_probe)
	inv.reservations_changed.connect(reserve_probe)
	a.state_changed.connect(site_probe)
	for stage: SiteCancellationTransaction.FailureStage in [
		SiteCancellationTransaction.FailureStage.RESERVATION, SiteCancellationTransaction.FailureStage.CARGO,
		SiteCancellationTransaction.FailureStage.SITE, SiteCancellationTransaction.FailureStage.RECORD
	]:
		var plan := COORD.prepare_site_cancellation(a, &"b12_atomic")
		assert_true(plan.ok, str(plan))
		assert_eq(load.provenance_snapshot(), before)
		var result := SiteCancellationTransaction.execute(a, &"b12_atomic", plan, stage)
		assert_eq(result.reason, "injected_precommit_failure")
		assert_eq(load.provenance_snapshot(), before)
		assert_eq(gpm._ledger.snapshot_state(), reserved_before)
		assert_eq(inv.get_all_physical_amounts(), physical)
		assert_eq(a._transit_claims, claims_a)
		assert_eq(b._transit_claims, claims_b)
		assert_eq(a.get_delivered_buffer_amounts(), buffer_before)
		assert_eq(a._assigned_workers, workers_before)
		assert_eq(unit.get_current_order(), move)
		assert_true(a.is_active())
		assert_false(a.is_transaction_busy())
		assert_false(inv.is_transaction_busy())
		assert_false(load.is_transaction_busy())
		assert_eq(events, [])
		for claim: Dictionary in claims_a.values():
			assert_true(load.load_changed.is_connected(claim.callback))
		assert_eq(COORD.execute_site_cancellation(a, &"b12_atomic", plan).reason, "stale_plan")
	load.load_changed.disconnect(signal_probe)
	inv.reservations_changed.disconnect(reserve_probe)
	a.state_changed.disconnect(site_probe)
	var observations: Array = []
	var reenter := func() -> void:
		observations.append(COORD.execute_site_cancellation(a, &"b12_atomic").get("replayed", false))
		observations.append(COORD.execute_site_cancellation(b, &"b12_other").ok)
		observations.append(inv.release_batch(b.reservation_id))
		observations.append(main.get_construction_manager().complete_site_transaction(a))
	inv.reservations_changed.connect(reenter)
	var committed := COORD.execute_site_cancellation(a, &"b12_atomic")
	inv.reservations_changed.disconnect(reenter)
	assert_true(committed.ok, str(committed))
	if not committed.ok:
		return
	assert_eq(observations, [true, false, false, false])
	assert_eq(committed.receipt.custody.in_transit_remaining[&"wood"], 2)
	assert_eq(committed.receipt.custody.transit_lots_by_unit[unit.get_character_id()], [&"b12_lot_a"])
	assert_eq(committed.receipt.custody.assigned_unit_ids, [colleague.get_character_id()])
	assert_false(a.occupies_construction_footprint())
	assert_eq(a.get_site_state(), ConstructionSite.SiteState.CANCELLED)
	assert_eq(a.claim_pickup(unit, 1, &"wood", 1), 0)
	assert_false(a.can_authorize_manual_complement({&"wood": 1}).ok)
	assert_false(a.contribute_work(unit, 0.1).ok)
	var after := load.provenance_snapshot()
	assert_eq(after.amounts, before.amounts)
	assert_eq(after.weights, before.weights)
	assert_eq(after.ledger.lots[&"b12_lot_a"].origin, CarryProvenanceLedger.CANCEL_TRANSIT)
	assert_eq(after.ledger.lots[&"b12_lot_b"], before.ledger.lots[&"b12_lot_b"])
	assert_eq(after.ledger.lots[&"b12_free"], before.ledger.lots[&"b12_free"])
	assert_eq(b._transit_claims, claims_b)
	assert_eq(inv.get_all_physical_amounts(), physical)
	for claim: Dictionary in claims_a.values():
		assert_false(load.load_changed.is_connected(claim.callback))
	var world := a.get_world_3d()
	var region := a.region_id
	a.queue_free()
	await wait_process_frames(2)
	assert_false(is_instance_valid(a))
	assert_eq(COORD.get_site_cancellation_receipt_readonly(world, region, &"b12_atomic"), committed.receipt)
	assert_true(COORD.get_cancellation_custody_readonly(world, region, committed.receipt.cancel_id).ok)


func test_real_assembly_custody_at_half_and_ninety_percent() -> void:
	for threshold: int in [15_000_000, 27_000_000]:
		var main := await _fixture()
		var inv := main.get_settlement_inventory()
		assert_true(inv.deposit(&"wood", 12))
		assert_true(inv.deposit(&"stone", 6))
		var site := _site(main, Vector3(-6.0, 0, 1.5))
		if site == null:
			return
		var manager := main.get_construction_manager()
		assert_true(main.get_command_controller().command_units_to_site(site, main.get_units()))
		assert_true(await _until(func() -> bool: return site._work_progress_usec >= threshold, 6500))
		assert_true(site._work_progress_usec >= threshold and site._work_progress_usec <= threshold + 25_000)
		var plan := COORD.prepare_site_cancellation(site, &"b12_progress")
		assert_true(plan.ok, str(plan))
		if not plan.ok:
			return
		assert_true(plan.reserved.is_empty(), "Production assembly supplied the entire shelter")
		if threshold == 27_000_000:
			assert_eq(plan.resources[&"wood"].incorporated, 10)
			assert_eq(plan.resources[&"stone"].incorporated, 5)
		var physical := inv.get_all_physical_amounts()
		var result := COORD.execute_site_cancellation(site, &"b12_progress", plan)
		assert_true(result.ok, str(result))
		if not result.ok:
			return
		var custody: Dictionary = result.receipt.custody
		assert_eq(custody.state, ConstructionCancellationMath.State.RECOVERY_PENDING)
		assert_true(manager.has_site_overlapping_rect(site.get_footprint_rect()))
		assert_false(manager.complete_site_transaction(site))
		for resource: StringName in [&"wood", &"stone"]:
			var line: Dictionary = plan.resources[resource]
			var refund := ConstructionCancellationMath.evaluate_refund(line.incorporated, plan.progress, plan.total_work)
			assert_eq(custody.local_buffer_remaining[resource], line.buffer)
			assert_eq(custody.local_incorporated_remaining[resource], refund.value)
			assert_eq(custody.demolition_loss[resource], line.incorporated - refund.value)
			assert_eq(custody.delivered_to_camp.get(resource, 0), 0)
		assert_eq(inv.get_all_physical_amounts(), physical)
		assert_true(COORD.get_cancellation_custody_readonly(site.get_world_3d(), site.region_id, custody.cancel_id).ok)
		await wait_physics_frames(3)
		for worker: Unit in main.get_units():
			assert_false(worker.get_current_order() is ConstructOrder)


func test_decay_and_completion_states_are_conservative() -> void:
	var main := await _fixture()
	var inv := main.get_settlement_inventory()
	var storage := main.get_ground_pile_manager()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site := _site(main, Vector3(-6.0, 0, 1.5))
	if site == null:
		return
	for pile: GroundResourcePile in storage.get_piles():
		if pile.resource_id == &"wood":
			pile.apply_state(pile.amount, 420.0, 0.0)
	main.get_time_provider().advance(1200.0)
	var losses := storage.step_decay()
	assert_gt(int(losses.get(&"wood", 0)), 0)
	assert_eq(losses.get(&"stone", 0), 0)
	var plan := COORD.prepare_site_cancellation(site, &"b12_decay")
	assert_true(plan.ok, str(plan))
	if not plan.ok:
		return
	for state: ConstructionSite.SiteState in [ConstructionSite.SiteState.COMPLETING, ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE, ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR, ConstructionSite.SiteState.COMPLETED]:
		site._site_state = state
		var diagnostic := site.get_completion_diagnostic()
		assert_false(COORD.execute_site_cancellation(site, &"b12_decay").ok)
		assert_eq(site.get_site_state(), state)
		assert_eq(site.get_completion_diagnostic(), diagnostic)
	site._site_state = ConstructionSite.SiteState.ACTIVE
	var result := COORD.execute_site_cancellation(site, &"b12_decay", plan)
	assert_true(result.ok, str(result))
	if result.ok:
		assert_eq(result.receipt.custody.missing_deficit[&"wood"], losses.wood)
		assert_eq(result.receipt.custody.released_on_piles[&"stone"], 6)
