extends TestCase

const Fixtures := preload("res://tests/integration/test_t3_6_3_b1_3_physical_recovery.gd")
var fixture: Fixtures
const C := preload("res://src/economy/reserved_withdrawal_coordinator.gd")
const SHELTER := preload("res://data/buildings/shelter_basic.tres")


func _prepared(workers: int = 1, automatic: bool = true) -> Dictionary:
	var main := await fixture.fixture._fixture(automatic)
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site := fixture.fixture._site(main, Vector3(-6, 0, 1.5))
	var units: Array[Unit] = []
	for index: int in range(workers):
		units.append(main.get_units()[index])
	assert_true(main.get_command_controller().command_units_to_site(site, units))
	assert_true(await fixture.fixture._until(func() -> bool: return site._work_progress_usec >= 15_000_000, 10000))
	return {"main": main, "site": site, "units": units}


func _cancel(ctx: Dictionary) -> ReservedWithdrawalCoordinator.CancellationCustodyRecord:
	var cancelled := C.execute_site_cancellation(ctx.site, &"b14_cancel")
	assert_true(cancelled.ok, str(cancelled))
	return fixture._record(ctx.main, cancelled.receipt.cancel_id)


func _settled(record: ReservedWithdrawalCoordinator.CancellationCustodyRecord, limit: int = 10000) -> void:
	# Resume events enqueue dispatch; observe the queue before deciding it is blocked.
	await wait_physics_frames(2)
	await fixture.fixture._until(func() -> bool:
		if record.state == ConstructionCancellationMath.State.SETTLED:
			return true
		if record.state != ConstructionCancellationMath.State.RETURN_BLOCKED:
			return false
		for node: Node in get_tree().get_nodes_in_group(Unit.GROUP_SELECTABLE_UNITS):
			if node is Unit and node.get_world_3d().get_instance_id() == record.world_instance_id and node.get_current_order() is RecoveryOrder and node.get_current_order().is_active():
				return false
		return true
	, limit)
	assert_eq(record.state, ConstructionCancellationMath.State.SETTLED, str(record.to_snapshot_dict()))
	fixture._balanced(record)


func before_each() -> void:
	fixture = Fixtures.new()
	add_test_child(fixture)
	fixture.before_each()


func after_each() -> void:
	fixture.after_each()
	fixture.cleanup_tracked_nodes()


func test_internal_assignment_is_available_for_pending_custody() -> void:
	var ctx := await fixture._local()
	assert_true(ctx.main.get_construction_manager().has_method("assign_cancellation_recovery"), "B1.4 requires internal recovery dispatch")


func test_storage_cleanup_cannot_erase_piles_with_pending_custody() -> void:
	var ctx := await fixture._local()
	var main: MainScene = ctx.main
	assert_true(main.get_settlement_inventory().deposit(&"wood", 2))
	var before := main.get_settlement_inventory().get_all_physical_amounts()
	main.get_ground_pile_manager().cleanup()
	assert_eq(main.get_settlement_inventory().get_all_physical_amounts(), before, "Controlled cleanup must refuse pending cancellation custody")


func test_single_worker_automatic_multitrip_and_controlled_teardown() -> void:
	var ctx := await _prepared()
	var main: MainScene = ctx.main
	var record := _cancel(ctx)
	var unit: Unit = ctx.units[0]
	assert_true(unit.get_carry_load().set_base_capacity(6))
	assert_false(main.preflight_economic_teardown().ok)
	assert_false(main.request_controlled_teardown().ok)
	assert_true(main.is_inside_tree())
	await wait_physics_frames(1)
	var recovery := unit.get_current_order() as RecoveryOrder
	assert_true(recovery != null)
	if recovery == null:
		return
	await _settled(record)
	assert_true(recovery.trips_completed > 1)
	assert_true(recovery.pickups_completed > 1)
	assert_true(unit.get_carry_load().is_empty())
	assert_true(main.preflight_economic_teardown().ok)
	assert_true(main.request_controlled_teardown().ok)
	assert_false(main.is_inside_tree())
	assert_true(main.get_last_domain_release_result().get("released", false), "Controlled teardown must also release the settled authority")
	await wait_physics_frames(1)
	assert_false(is_instance_valid(main))


func test_two_workers_use_distinct_operations_and_settle_once() -> void:
	var ctx := await _prepared(2)
	var main: MainScene = ctx.main
	var record := _cancel(ctx)
	for unit: Unit in ctx.units:
		assert_true(unit.get_carry_load().set_base_capacity(6))
	await wait_physics_frames(1)
	var orders: Array[RecoveryOrder] = []
	for unit: Unit in ctx.units:
		var order := unit.get_current_order() as RecoveryOrder
		assert_true(order != null)
		if order != null:
			orders.append(order)
	var consistent: Array[bool] = []
	var cb := func() -> void: consistent.append(C.validate_custody_accounting_pure(record).ok)
	main.get_settlement_inventory().inventory_changed.connect(cb)
	await _settled(record)
	main.get_settlement_inventory().inventory_changed.disconnect(cb)
	assert_false(consistent.is_empty())
	assert_false(consistent.has(false))
	assert_eq(record.get_local_custody_total(), 0)
	assert_eq(record.get_in_transit_custody_total(), 0)
	for order: RecoveryOrder in orders:
		assert_true(order.pickups_completed + order.trips_completed > 0)
	for unit: Unit in ctx.units:
		assert_true(unit.get_carry_load().validate_provenance())
		assert_true(unit.get_carry_load().is_empty())


func test_manual_order_in_replacement_callback_has_priority() -> void:
	var ctx := await _prepared(1, false)
	var main: MainScene = ctx.main
	var record := _cancel(ctx)
	var unit: Unit = ctx.units[0]
	var old := unit.get_current_order()
	var manual := MoveOrder.new(Vector3(-10, 0, 3))
	var callback := func(finished: UnitOrder) -> void:
		if finished == old:
			unit.issue_order(manual)
	unit.order_finished.connect(callback)
	main.get_construction_manager().enable_cancellation_recovery()
	var assigned := main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [unit])
	unit.order_finished.disconnect(callback)
	assert_eq(unit.get_current_order(), manual, "A newer manual command from a callback must survive automatic replacement")
	assert_false(assigned.ok)


func test_manual_order_from_start_state_callback_has_priority() -> void:
	var ctx := await _prepared(1, false)
	var main: MainScene = ctx.main
	var record := _cancel(ctx)
	var unit: Unit = ctx.units[0]
	var manual := MoveOrder.new(Vector3(-10, 0, 3))
	var callback := func(state: Unit.State, _previous: Unit.State) -> void:
		if state == Unit.State.TRANSPORTING:
			unit.issue_order(manual)
	unit.state_changed.connect(callback)
	main.get_construction_manager().enable_cancellation_recovery()
	var assigned := main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [unit])
	unit.state_changed.disconnect(callback)
	assert_eq(unit.get_current_order(), manual, "A callback during start must not lose the newest command")
	assert_false(assigned.ok)


func test_manual_override_keeps_cargo_no_automatic_hijack_and_explicit_resume() -> void:
	var ctx := await _prepared()
	var main: MainScene = ctx.main
	var record := _cancel(ctx)
	var unit: Unit = ctx.units[0]
	assert_true(await fixture.fixture._until(func() -> bool: return unit.get_current_order() is RecoveryOrder and not unit.get_carry_load().is_empty(), 3000))
	var recovery := unit.get_current_order() as RecoveryOrder
	var before := unit.get_carry_load().provenance_snapshot()
	var manual := MoveOrder.new(Vector3(-10, 0, 3))
	unit.issue_order(manual)
	assert_eq(unit.get_current_order(), manual)
	assert_eq(unit.get_carry_load().provenance_snapshot(), before)
	assert_true(recovery.manual_interruption)
	assert_false(main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [unit]).ok, "Active manual order cannot be replaced")
	assert_true(main.get_settlement_inventory().deposit(&"food", 1))
	await wait_physics_frames(90)
	assert_false(unit.get_current_order() is RecoveryOrder)
	assert_true(await fixture.fixture._until(func() -> bool: return manual.is_finished(), 3000))
	assert_true(manual.is_succeeded(), manual.failure_reason)
	assert_true(main.get_settlement_inventory().deposit(&"food", 1))
	await wait_physics_frames(30)
	assert_eq(unit.get_current_order(), null, "Safe events cannot reclaim a manually overridden unit")
	assert_true(main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [unit]).ok)
	var current := unit.get_current_order()
	main.get_construction_manager()._recovery_dispatcher._on_order_finished(recovery, unit.get_character_id())
	assert_eq(unit.get_current_order(), current, "An obsolete completion callback cannot replace the new order")
	await _settled(record)


func test_stale_deferred_dispatch_cannot_replace_newer_manual_command() -> void:
	var ctx := await _prepared()
	var main: MainScene = ctx.main
	var record := _cancel(ctx)
	var unit: Unit = ctx.units[0]
	var manual := MoveOrder.new(Vector3(-10, 0, 3))
	unit.issue_order(manual)
	await wait_physics_frames(2)
	assert_eq(unit.get_current_order(), manual)
	assert_eq(record.get_in_transit_custody_total(), 0)
	assert_true(record.get_local_custody_total() > 0)
	assert_true(main.get_settlement_inventory().deposit(&"food", 1))
	await wait_physics_frames(30)
	assert_false(unit.get_current_order() is RecoveryOrder)
	fixture._balanced(record)


func test_no_workers_preserves_custody_then_late_assignment_recovers() -> void:
	var ctx := await _prepared()
	var main: MainScene = ctx.main
	var unit: Unit = ctx.units[0]
	unit.cancel_current_order()
	var record := _cancel(ctx)
	var before := record.to_snapshot_dict()
	assert_eq(record.assigned_unit_ids.size(), 0)
	await wait_physics_frames(10)
	assert_eq(record.to_snapshot_dict(), before)
	assert_false(main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, []).ok)
	assert_false(main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [null]).ok)
	var assignment := main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [unit, unit])
	assert_true(assignment.ok)
	assert_eq(assignment.assigned, 1, "Repeated worker identity cannot create or report two assignments")
	assert_true(record.recovery_unit_ids.has(unit.get_character_id()))
	assert_false(CancellationLifecycleGuard.inspect_worker(unit, &"default").ok)
	await _settled(record)


func test_real_navigation_region_unavailable_then_restored_event_retries() -> void:
	var ctx := await _prepared()
	var main: MainScene = ctx.main
	var nav := main.get_test_map().get_navigation()
	var unit: Unit = ctx.units[0]
	nav.enabled = false
	await wait_physics_frames(3)
	var record := _cancel(ctx)
	var before := unit.get_carry_load().provenance_snapshot()
	await wait_physics_frames(2)
	var failed_order := unit.get_current_order() as RecoveryOrder
	assert_true(failed_order != null)
	assert_true(await fixture.fixture._until(func() -> bool: return record.state == ConstructionCancellationMath.State.RETURN_BLOCKED and unit.get_current_order() == null, 3000))
	if failed_order != null:
		assert_eq(failed_order.retries, RecoveryOrder.MAX_RETRIES)
	assert_eq(unit.get_carry_load().provenance_snapshot(), before)
	assert_eq(record.get_in_transit_custody_total(), 0)
	assert_eq(record.delivered_to_camp, {})
	fixture._balanced(record)
	nav.enabled = true
	nav.request_rebake()
	assert_true(await fixture.fixture._until(func() -> bool: return nav.is_navigation_ready(), 240))
	assert_true(await fixture.fixture._until(func() -> bool: return unit.get_current_order() is RecoveryOrder, 30), "Navigation ready event must reassign the failed task")
	await _settled(record)


func test_camp_capacity_block_preserves_load_and_restored_stock_event_resumes() -> void:
	var ctx := await _prepared()
	var main: MainScene = ctx.main
	var camp := main.get_camp_storage_zone()
	var record := _cancel(ctx)
	var unit: Unit = ctx.units[0]
	var bounds := camp.zone_bounds_half_extents
	var cap := camp.max_pile_amount
	camp.zone_bounds_half_extents = Vector2(0.05, 0.05)
	camp.max_pile_amount = 1
	assert_true(await fixture.fixture._until(func() -> bool: return record.state == ConstructionCancellationMath.State.RETURN_BLOCKED and unit.get_current_order() == null, 5000))
	assert_false(unit.get_carry_load().is_empty())
	assert_true(record.get_in_transit_custody_total() > 0)
	assert_eq(record.delivered_to_camp, {})
	fixture._balanced(record)
	var held := unit.get_carry_load().provenance_snapshot()
	await wait_physics_frames(90)
	assert_eq(unit.get_carry_load().provenance_snapshot(), held)
	camp.zone_bounds_half_extents = bounds
	camp.max_pile_amount = cap
	assert_true(main.get_settlement_inventory().deposit(&"food", 1))
	assert_true(await fixture.fixture._until(func() -> bool: return unit.get_current_order() is RecoveryOrder, 30), "Storage event must reassign the failed task")
	await _settled(record)


func test_mixed_other_site_and_free_lots_are_not_delivered_by_recovery() -> void:
	var ctx := await _prepared(1, false)
	var main: MainScene = ctx.main
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var other := fixture.fixture._site(main, Vector3(0.37, 0, -13.19))
	var unit: Unit = ctx.units[0]
	fixture.fixture._withdraw(main, other, unit, &"b14_take_b", &"b14_b")
	unit.cancel_current_order()
	for source: ResourceSource in main.get_test_map().get_resource_sources():
		if source.definition.resource_id == &"food":
			assert_true(source.transfer_to_carry_load_with_provenance(unit.get_carry_load(), &"b14_gather", &"b14_free", 1).ok)
			break
	var record := _cancel(ctx)
	var before := unit.get_carry_load().provenance_snapshot()
	var claim := other._transit_claims.duplicate(true)
	var reservation := inv.get_reservation_amounts(other.reservation_id)
	var capacity := unit.get_carry_load().get_base_capacity()
	assert_true(unit.get_carry_load().set_base_capacity(unit.get_carry_load().get_current_weight()))
	main.get_construction_manager().enable_cancellation_recovery()
	assert_true(main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [unit]).ok)
	assert_true(await fixture.fixture._until(func() -> bool: return record.state == ConstructionCancellationMath.State.RETURN_BLOCKED and unit.get_current_order() == null, 3000))
	assert_eq(unit.get_carry_load().provenance_snapshot(), before, "A full backpack of other obligations must remain untouched")
	assert_eq(record.get_in_transit_custody_total(), 0)
	assert_eq(record.delivered_to_camp, {})
	assert_true(unit.get_carry_load().set_base_capacity(capacity))
	assert_true(main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [unit]).ok)
	await _settled(record)
	var after := unit.get_carry_load().provenance_snapshot()
	assert_eq(after.ledger.lots[&"b14_b"], before.ledger.lots[&"b14_b"])
	assert_eq(after.ledger.lots[&"b14_free"], before.ledger.lots[&"b14_free"])
	assert_eq(other._transit_claims, claim)
	assert_eq(inv.get_reservation_amounts(other.reservation_id), reservation)
	assert_false(main.preflight_economic_teardown().ok, "Settled A must not allow destruction of B's remaining physical cargo")


func test_reserved_transit_returns_before_any_new_local_pickup_and_guards_hold() -> void:
	var main := await fixture.fixture._fixture(true)
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site := fixture.fixture._site(main, Vector3(-6, 0, 1.5))
	var unit := main.get_units()[0]
	fixture.fixture._withdraw(main, site, unit, &"b14_transit", &"b14_transit_lot")
	var ctx := {"main": main, "site": site}
	var record := _cancel(ctx)
	var observations: Array = []
	var callback := func() -> void:
		observations.append(record.get_local_custody_total() == 0)
		observations.append(main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [unit]).ok)
		observations.append(main.request_controlled_teardown().ok)
		observations.append(C.validate_custody_accounting_pure(record).ok)
	inv.inventory_changed.connect(callback)
	await _settled(record)
	inv.inventory_changed.disconnect(callback)
	assert_eq(observations, [true, false, false, true])
	assert_eq(record.delivered_to_camp[&"wood"], 2)


func test_temporary_removal_blocks_empty_assigned_worker_until_settlement() -> void:
	var ctx := await fixture._local()
	var main: MainScene = ctx.main
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = ctx.record
	var controller := main._test_workers_controller
	var spawned := controller.spawn_temporary_workers()
	assert_true(spawned.ok)
	var worker: Unit = spawned.workers[0]
	main.get_construction_manager().enable_cancellation_recovery()
	assert_true(main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [worker]).ok)
	assert_true(worker.get_carry_load().is_empty())
	assert_false(controller.remove_temporary_workers_safely().ok)
	worker.cancel_current_order()
	assert_false(controller.remove_temporary_workers_safely().ok, "Empty manually interrupted worker still has a recovery identity obligation")
	assert_true(main.get_construction_manager().assign_cancellation_recovery(record.cancel_id, [worker]).ok)
	await _settled(record)
	assert_true(await fixture.fixture._until(func() -> bool: return worker.get_current_order() == null, 30))
	assert_true(controller.remove_temporary_workers_safely().ok)
	await wait_physics_frames(1)
	assert_false(is_instance_valid(worker))


func test_external_tree_removal_cannot_be_vetoed_and_d3_has_no_command() -> void:
	var ctx := await fixture._local()
	var main: MainScene = ctx.main
	var record: ReservedWithdrawalCoordinator.CancellationCustodyRecord = ctx.record
	assert_false(main.preflight_economic_teardown().ok)
	assert_false(main.get_command_controller().has_method("command_cancel_construction"))
	assert_false(main.get_placement_test_overlay().has_method("cancel_construction"))
	# Demonstrate the limit: arbitrary external destruction bypasses the cooperative gate.
	main.get_parent().remove_child(main)
	assert_false(main.is_inside_tree())
	assert_true(record.has_unsettled_custody())
	main.queue_free()
	await wait_physics_frames(1)
	assert_false(is_instance_valid(main))


func test_controlled_teardown_excludes_reentrant_economic_commit() -> void:
	var ctx := await _prepared(1, false)
	var main: MainScene = ctx.main
	var unit: Unit = ctx.units[0]
	unit.cancel_current_order()
	assert_true(main.preflight_economic_teardown().ok)
	var probe := Node.new()
	main.add_child(probe)
	var commits: Array = []
	probe.tree_exiting.connect(func() -> void: commits.append(C.execute_site_cancellation(ctx.site, &"teardown_callback").ok))
	assert_true(main.request_controlled_teardown().ok)
	assert_eq(commits, [false], "A callback during controlled destruction must not create a new economic obligation after preflight")
	assert_true(main.get_last_domain_release_result().get("released", false), "Quiescence guards cannot remain held after controlled teardown")
	await wait_physics_frames(1)
