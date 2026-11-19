extends TestCase

const MAIN: PackedScene = preload("res://src/main/main.tscn")
const HARNESS = preload("res://tests/visual/t3_6_2_c3_4_3_manual_harness.gd")
const TREE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const BUSH: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const AWAY := Vector3(-9.5, 0.0, 6.5)
const LIMIT := 1800

var _prior_scale: float
var _prior_ticks: int


func before_each() -> void:
	_prior_scale = Engine.time_scale
	_prior_ticks = Engine.physics_ticks_per_second
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180


func after_each() -> void:
	Engine.time_scale = _prior_scale
	Engine.physics_ticks_per_second = _prior_ticks


func _until(condition: Callable, limit: int = LIMIT) -> bool:
	for _frame in range(limit):
		if condition.call():
			return true
		await wait_physics_frames()
	return condition.call()


func _fixture() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	add_test_child(viewport)
	var main := MAIN.instantiate() as MainScene
	viewport.add_child(main)
	var nav := main.get_test_map().get_navigation()
	assert_true(await _until(nav.is_navigation_ready, 240))
	await wait_physics_frames(2)
	var worker: Unit = main.get_units()[0]
	worker.global_position = nav.snap_to_navmesh(AWAY)
	var selection := main.get_node("SelectionManager") as SelectionManager
	selection.select_single(worker)
	var harness := HARNESS.HarnessController.new()
	harness.main = main
	harness.nav = nav
	main.add_child(harness)
	return {
		"main": main, "nav": nav, "worker": worker, "harness": harness,
		"camp": main.get_camp_storage_zone(), "inv": main.get_settlement_inventory(),
	}


func test_m2_loaded_legacy_opt_in_is_economically_inert() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	var inv: SettlementInventory = fx.inv
	assert_true(inv.deposit(&"wood", 12))
	assert_true(load.add_units(WOOD, 1))
	var before: Dictionary = load.provenance_snapshot()
	var stock_before := inv.get_all_physical_amounts()
	fx.harness._enable_opt_in_on_selected()
	assert_false(load.is_provenance_enabled())
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(load.get_all_amounts(), {&"wood": 1})
	assert_eq(load.get_current_weight(), 2)
	assert_eq(inv.get_all_physical_amounts(), stock_before)
	assert_eq(load.remove_units(&"wood", 1), 1)
	fx.harness._enable_opt_in_on_selected()
	assert_true(load.is_provenance_enabled())
	assert_true(load.is_empty())
	assert_eq(load.provenance_snapshot()["ledger"]["lots"], {})
	assert_eq(inv.get_all_physical_amounts(), stock_before)


func test_m3_harness_repeat_during_and_after_physical_delivery() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	var inv: SettlementInventory = fx.inv
	var harness: HARNESS.HarnessController = fx.harness
	assert_true(inv.deposit(&"wood", 12))
	harness._enable_opt_in_on_selected()
	harness._add_free_test_cargo()
	assert_eq(load.get_current_weight(), 8)
	assert_eq(load.get_effective_capacity(), 20)
	var before: Dictionary = load.provenance_snapshot()["ledger"]["lots"]
	assert_eq(before.size(), 1)
	var start := worker.global_position
	harness._issue_conservative_selective_camp_return()
	var first := harness.last_order as DeliverToCampOrder
	assert_eq(first.status, UnitOrder.Status.RUNNING)
	await wait_physics_frames(12)
	assert_eq(first.status, UnitOrder.Status.RUNNING)
	assert_eq(inv.get_physical_amount(&"wood"), 12)
	harness._issue_conservative_selective_camp_return()
	var replacement := harness.last_order as DeliverToCampOrder
	assert_eq(first.status, UnitOrder.Status.CANCELLED)
	assert_eq(first.failure_reason, UnitOrder.REASON_REPLACED)
	assert_eq(replacement.status, UnitOrder.Status.RUNNING)
	var credit_events: Array = []
	var observe_credit := func() -> void:
		credit_events.append([inv.get_physical_amount(&"wood"), load.get_amount(&"wood")])
	inv.inventory_changed.connect(observe_credit)

	for _frame in range(LIMIT):
		var stock := inv.get_physical_amount(&"wood")
		assert_eq(stock + load.get_amount(&"wood"), 16)
		if replacement.is_finished():
			break
		assert_eq(stock, 12)
		assert_eq(load.provenance_snapshot()["ledger"]["lots"], before)
		await wait_physics_frames()

	inv.inventory_changed.disconnect(observe_credit)
	assert_true(replacement.is_succeeded(), replacement.failure_reason)
	assert_gt(worker.global_position.distance_to(start), 3.0)
	assert_eq(first.trips_completed, 0)
	assert_eq(replacement.trips_completed, 1)
	assert_eq(inv.get_available_amount(&"wood"), 16)
	assert_eq(credit_events, [[16, 0]])
	assert_eq(load.get_current_weight(), 0)
	assert_eq(load.provenance_snapshot()["ledger"]["lots"], {})
	harness._issue_conservative_selective_camp_return()
	var repeat := harness.last_order as DeliverToCampOrder
	assert_eq(repeat.status, UnitOrder.Status.FAILED)
	assert_eq(repeat.failure_reason, DeliverToCampOrder.REASON_EMPTY_LOAD)
	assert_eq(repeat.trips_completed, 0)
	assert_true(worker.get_current_order() == null)
	await wait_physics_frames(24)
	assert_eq(inv.get_physical_amount(&"wood"), 16)
	print("[AUDIT M3] first=%d replacement=%d new_empty=%d/%s credit_events=%s" % [
		first.status, replacement.status, repeat.status, repeat.failure_reason, credit_events,
	])


func test_m4_four_wood_preserved_after_manual_replacement() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	var inv: SettlementInventory = fx.inv
	var harness: HARNESS.HarnessController = fx.harness
	assert_true(inv.deposit(&"wood", 12))
	harness._enable_opt_in_on_selected()
	harness._add_free_test_cargo()
	var before := load.provenance_snapshot()
	var start := worker.global_position
	harness._issue_conservative_selective_camp_return()
	var delivery := harness.last_order as DeliverToCampOrder
	assert_true(await _until(func() -> bool: return worker.global_position.distance_to(start) > 0.5, 90))
	assert_eq(delivery.status, UnitOrder.Status.RUNNING)
	assert_eq(inv.get_physical_amount(&"wood"), 12)
	var nav: WorldNavigation = fx.nav
	var move := MoveOrder.new(nav.snap_to_navmesh(AWAY))
	worker.issue_order(move)
	assert_eq(delivery.status, UnitOrder.Status.CANCELLED)
	assert_eq(delivery.failure_reason, UnitOrder.REASON_REPLACED)
	assert_true(await _until(move.is_finished))
	assert_true(move.is_succeeded(), move.failure_reason)
	await wait_physics_frames(180)
	assert_true(worker.get_current_order() == null)
	assert_eq(worker.get_state(), Unit.State.IDLE)
	assert_eq(inv.get_physical_amount(&"wood"), 12)
	assert_eq(load.get_current_weight(), 8)
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(delivery.trips_completed, 0)


func _mixed_fixture() -> Dictionary:
	var fx := await _fixture()
	var inv: SettlementInventory = fx.inv
	var harness: HARNESS.HarnessController = fx.harness
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 8))
	harness._enable_opt_in_on_selected()
	harness._setup_mixed_cargo_scenario()
	return fx


func _reserved_lots(load: UnitCarryLoad) -> Dictionary:
	var lots: Dictionary = load.provenance_snapshot()["ledger"]["lots"]
	var reserved := {}
	for key: Variant in lots:
		if lots[key]["origin"] == CarryProvenanceLedger.SITE_RESERVED:
			reserved[key] = lots[key]
	return reserved


func test_m5_exact_harness_mixed_cargo_and_site_b_return() -> void:
	var fx := await _mixed_fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	var inv: SettlementInventory = fx.inv
	var harness: HARNESS.HarnessController = fx.harness
	var site := harness.site_b
	if not assert_true(is_instance_valid(site)):
		return
	assert_eq(load.get_all_amounts(), {&"wood": 2, &"food": 3})
	var reserved := _reserved_lots(load)
	assert_eq(reserved.size(), 1)
	var claim := site._read_transit_claim_for_unit_pure(worker.get_instance_id())
	assert_false(claim.is_empty())
	var wood_free := inv.get_available_amount(&"wood")
	var wood_physical := inv.get_physical_amount(&"wood")
	var site_reserved := site.get_reserved_in_piles_amount(&"wood")
	var start := worker.global_position
	harness._issue_conservative_selective_camp_return()
	var free_delivery := harness.last_order as DeliverToCampOrder
	assert_true(await _until(free_delivery.is_finished))
	assert_true(free_delivery.is_succeeded(), free_delivery.failure_reason)
	assert_gt(worker.global_position.distance_to(start), 3.0)
	assert_eq(free_delivery.last_delivered, {&"food": 3})
	assert_eq(inv.get_available_amount(&"food"), 3)
	assert_eq(inv.get_available_amount(&"wood"), wood_free)
	assert_eq(inv.get_physical_amount(&"wood"), wood_physical)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), site_reserved)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), claim)
	assert_eq(load.provenance_snapshot()["ledger"]["lots"], reserved)
	var nav: WorldNavigation = fx.nav
	var move := MoveOrder.new(nav.snap_to_navmesh(AWAY))
	worker.issue_order(move)
	assert_true(await _until(move.is_finished))
	assert_true(move.is_succeeded(), move.failure_reason)
	start = worker.global_position
	harness._issue_explicit_site_b_reserved_return()
	var reserved_delivery := harness.last_order as DeliverToCampOrder
	assert_ne(reserved_delivery, free_delivery, "The harness must issue a new order for Site B.")
	assert_true(await _until(reserved_delivery.is_finished))
	assert_true(reserved_delivery.is_succeeded(), reserved_delivery.failure_reason)
	assert_gt(worker.global_position.distance_to(start), 3.0)
	assert_eq(reserved_delivery.last_delivered, {&"wood": 2})
	assert_eq(inv.get_available_amount(&"wood"), wood_free)
	assert_eq(inv.get_physical_amount(&"wood"), wood_physical + 2)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), site_reserved + 2)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), {})
	assert_true(load.is_empty())
	assert_eq(load.provenance_snapshot()["ledger"]["lots"], {})


func test_m6_exact_harness_stone_supply_preserves_site_b() -> void:
	var fx := await _mixed_fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	var inv: SettlementInventory = fx.inv
	var harness: HARNESS.HarnessController = fx.harness
	var a := harness.site_a
	var b := harness.site_b
	if not assert_true(is_instance_valid(a) and is_instance_valid(b)):
		return
	assert_eq(load.get_all_amounts(), {&"wood": 2, &"food": 3})
	var b_lots := _reserved_lots(load)
	var claim := b._read_transit_claim_for_unit_pure(worker.get_instance_id())
	var stock := inv.get_physical_amount(&"stone")
	var start := worker.global_position
	harness._issue_opt_in_construct_order_site_a()
	var order := harness.last_order as ConstructOrder
	assert_eq(order.get_phase(), ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO)
	var saw_stone_in_transit := false
	for _frame in range(LIMIT):
		var carried := load.get_amount(&"stone")
		var delivered := a.get_delivered_buffer_amount(&"stone")
		assert_eq(inv.get_physical_amount(&"stone") + carried + delivered, stock)
		if carried == 3:
			saw_stone_in_transit = true
			assert_eq(inv.get_available_amount(&"food"), 3)
			assert_eq(delivered, 0)
		if order.is_finished():
			break
		await wait_physics_frames()
	assert_true(saw_stone_in_transit)
	assert_true(order.is_succeeded(), order.failure_reason)
	assert_gt(worker.global_position.distance_to(start), 3.0)
	assert_eq(order.camp_return_trips_completed, 1)
	assert_eq(order.units_delivered_total, 3)
	assert_eq(a.get_delivered_buffer_amounts(), {&"stone": 3})
	assert_eq(load.get_all_amounts(), {&"wood": 2})
	assert_eq(load.provenance_snapshot()["ledger"]["lots"], b_lots)
	assert_eq(b._read_transit_claim_for_unit_pure(worker.get_instance_id()), claim)


func test_m8_replace_before_and_after_first_extraction() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var inv: SettlementInventory = fx.inv
	var camp: CampStorageZone = fx.camp
	var nav: WorldNavigation = fx.nav
	var main: MainScene = fx.main
	var load := worker.get_carry_load()
	assert_true(load.enable_provenance(&"audit_m8"))
	var tree := TREE.instantiate() as ResourceSource
	tree.position = Vector3(3.5, 0.0, 2.0)
	main.get_test_map().add_child(tree)
	tree.configure(&"audit_m8_tree", tree.get_definition(), 12, 4, 1)
	tree.set_gather_cycle_timings(0.08, 0.25)
	tree.felling_duration_sec = 0.25
	await wait_physics_frames(2)
	nav.request_rebake()
	assert_true(await _until(nav.is_navigation_ready, 240))
	await wait_physics_frames(2)

	var pre_extract := GatherResourceOrder.new(tree, camp, inv, 0.08, 0.25, true, nav.get_region_id())
	var empty_snapshot := load.provenance_snapshot()
	worker.issue_order(pre_extract)
	assert_true(await _until(pre_extract.is_preparing_gather))
	assert_true(tree.is_worker_reserved(worker))
	var first_move := MoveOrder.new(nav.snap_to_navmesh(AWAY))
	worker.issue_order(first_move)
	assert_eq(pre_extract.status, UnitOrder.Status.CANCELLED)
	assert_eq(pre_extract.failure_reason, UnitOrder.REASON_REPLACED)
	assert_true(await _until(first_move.is_finished))
	assert_true(first_move.is_succeeded(), first_move.failure_reason)
	assert_eq(tree.get_active_worker_count(), 0)
	assert_eq(tree.get_remaining_amount(), 12)
	assert_eq(load.provenance_snapshot(), empty_snapshot)
	assert_eq(inv.get_physical_amount(&"wood"), 0)

	var post_extract := GatherResourceOrder.new(tree, camp, inv, 0.08, 0.25, true, nav.get_region_id())
	worker.issue_order(post_extract)
	assert_true(await _until(func() -> bool: return load.get_amount(&"wood") > 0))
	assert_eq(load.get_amount(&"wood"), 4)
	assert_eq(load.get_current_weight(), 8)
	assert_eq(tree.get_remaining_amount(), 8)
	assert_true(tree.is_felling())
	var loaded_snapshot := load.provenance_snapshot()
	var lots: Dictionary = loaded_snapshot["ledger"]["lots"]
	assert_eq(lots.size(), 1)
	for lot: Dictionary in lots.values():
		assert_eq(lot["origin"], CarryProvenanceLedger.FREE_GATHERED)
	var second_move := MoveOrder.new(nav.snap_to_navmesh(AWAY))
	worker.issue_order(second_move)
	assert_eq(post_extract.status, UnitOrder.Status.CANCELLED)
	assert_eq(post_extract.failure_reason, UnitOrder.REASON_REPLACED)
	assert_eq(tree.get_active_worker_count(), 0)
	assert_true(await _until(second_move.is_finished))
	assert_true(second_move.is_succeeded(), second_move.failure_reason)
	await wait_physics_frames(60)
	assert_true(tree.is_fallen())
	assert_eq(tree.get_active_worker_count(), 0)
	assert_eq(tree.get_remaining_amount(), 8)
	assert_eq(load.provenance_snapshot(), loaded_snapshot)
	assert_eq(load.get_current_weight(), 8)
	assert_eq(inv.get_physical_amount(&"wood"), 0)


func test_m9_replace_real_gather_during_walk_then_deliver_preserved_lots() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var inv: SettlementInventory = fx.inv
	var camp: CampStorageZone = fx.camp
	var nav: WorldNavigation = fx.nav
	var main: MainScene = fx.main
	var load := worker.get_carry_load()
	assert_true(load.enable_provenance(&"audit_m9"))
	var tree := TREE.instantiate() as ResourceSource
	tree.position = Vector3(3.5, 0.0, 2.0)
	main.get_test_map().add_child(tree)
	tree.configure(&"audit_m9_tree", tree.get_definition(), 14, 5, 1)
	tree.set_gather_cycle_timings(0.08, 0.16)
	tree.felling_duration_sec = 0.14
	await wait_physics_frames(2)
	nav.request_rebake()
	assert_true(await _until(nav.is_navigation_ready, 240))
	await wait_physics_frames(2)

	var gather := GatherResourceOrder.new(tree, camp, inv, 0.08, 0.16, true, nav.get_region_id())
	worker.issue_order(gather)
	if not assert_true(await _until(func() -> bool:
		return gather.get_phase() == GatherResourceOrder.Phase.DELIVERING_TO_CAMP or gather.is_finished()
	)):
		return
	assert_true(gather.is_active(), gather.failure_reason)
	await wait_physics_frames(6)
	assert_true(gather.is_active())
	assert_eq(worker.get_state(), Unit.State.TRANSPORTING)
	assert_eq(worker.get_movement().get_move_state(), UnitMovement.MoveState.MOVING)
	assert_eq(tree.get_active_worker_count(), 0)
	var lots: Dictionary = load.provenance_snapshot()["ledger"]["lots"]
	assert_true(not lots.is_empty())
	for lot: Dictionary in lots.values():
		assert_eq(lot["origin"], CarryProvenanceLedger.FREE_GATHERED)
	var amount := load.get_amount(&"wood")
	var weight := load.get_current_weight()
	var remaining := tree.get_remaining_amount()
	assert_eq(amount, 10)
	assert_eq(weight, 20)
	assert_eq(remaining + amount, 14)
	assert_eq(inv.get_physical_amount(&"wood"), 0)

	var move := MoveOrder.new(nav.snap_to_navmesh(AWAY))
	worker.issue_order(move)
	assert_eq(gather.status, UnitOrder.Status.CANCELLED)
	assert_eq(gather.failure_reason, UnitOrder.REASON_REPLACED)
	assert_true(await _until(move.is_finished))
	assert_true(move.is_succeeded(), move.failure_reason)
	assert_eq(tree.get_active_worker_count(), 0)
	assert_eq(tree.get_remaining_amount(), remaining)
	assert_eq(load.get_current_weight(), weight)
	assert_eq(load.provenance_snapshot()["ledger"]["lots"], lots)
	assert_eq(inv.get_physical_amount(&"wood"), 0)
	assert_true(worker.get_current_order() == null)

	var start := worker.global_position
	var delivery := DeliverToCampOrder.new(camp, inv, true, nav.get_region_id(), [])
	worker.issue_order(delivery)
	for _frame in range(LIMIT):
		var stock := inv.get_physical_amount(&"wood")
		assert_eq(tree.get_remaining_amount() + load.get_amount(&"wood") + stock, 14)
		if delivery.is_finished():
			break
		assert_eq(stock, 0)
		await wait_physics_frames()
	assert_true(delivery.is_succeeded(), delivery.failure_reason)
	assert_gt(worker.global_position.distance_to(start), 3.0)
	assert_eq(delivery.trips_completed, 1)
	assert_eq(inv.get_available_amount(&"wood"), amount)
	assert_eq(tree.get_remaining_amount(), remaining)
	assert_eq(load.get_current_weight(), 0)
	assert_eq(load.provenance_snapshot()["ledger"]["lots"], {})
	print("[AUDIT M9] extracted=%d retained_lots=%d source_remaining=%d camp_after=%d" % [
		amount, lots.size(), remaining, inv.get_physical_amount(&"wood"),
	])


func test_m10_food_gather_respects_residual_capacity_and_site_b_claim() -> void:
	var fx := await _mixed_fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	var inv: SettlementInventory = fx.inv
	var nav: WorldNavigation = fx.nav
	var main: MainScene = fx.main
	var harness: HARNESS.HarnessController = fx.harness
	var site := harness.site_b
	if not assert_true(is_instance_valid(site)):
		return
	var b_lots := _reserved_lots(load)
	var claim := site._read_transit_claim_for_unit_pure(worker.get_instance_id())
	var wood_free := inv.get_available_amount(&"wood")
	var wood_reserved := site.get_reserved_in_piles_amount(&"wood")
	assert_eq(load.get_current_weight(), 7)
	assert_eq(load.get_all_amounts(), {&"wood": 2, &"food": 3})
	var bush := BUSH.instantiate() as ResourceSource
	bush.position = Vector3(3.5, 0.0, 2.0)
	main.get_test_map().add_child(bush)
	bush.configure(&"audit_m10_bush", bush.get_definition(), 15, 5, 1)
	bush.set_gather_cycle_timings(0.08, 0.10)
	await wait_physics_frames(2)
	nav.request_rebake()
	assert_true(await _until(nav.is_navigation_ready, 240))
	await wait_physics_frames(2)
	var order := GatherResourceOrder.new(bush, fx.camp, inv, 0.08, 0.10, true, nav.get_region_id())
	worker.issue_order(order)
	var saw_full := false
	for _frame in range(LIMIT):
		var carried := load.get_amount(&"food")
		assert_true(load.get_current_weight() <= load.get_effective_capacity())
		assert_eq(bush.get_remaining_amount() + carried + inv.get_physical_amount(&"food"), 18)
		if carried == 16 and order.get_delivered_trips() == 0:
			saw_full = true
			assert_eq(load.get_current_weight(), 20)
			assert_eq(bush.get_remaining_amount(), 2)
			assert_eq(inv.get_available_amount(&"food"), 0)
		if order.is_finished():
			break
		await wait_physics_frames()
	assert_true(saw_full)
	assert_true(order.is_succeeded(), order.failure_reason)
	assert_eq(order.get_delivered_trips(), 2)
	assert_eq(order.get_total_extracted_units(), 15)
	assert_eq(bush.get_remaining_amount(), 0)
	assert_eq(bush.get_active_worker_count(), 0)
	assert_eq(inv.get_available_amount(&"food"), 18)
	assert_eq(inv.get_available_amount(&"wood"), wood_free)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), wood_reserved)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), claim)
	assert_eq(load.get_all_amounts(), {&"wood": 2})
	assert_eq(load.provenance_snapshot()["ledger"]["lots"], b_lots)
