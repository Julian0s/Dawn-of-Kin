extends TestCase

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const LEADER: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const SITE_A := Vector3(-6.0, 0.0, 1.5)
const SITE_B := Vector3(0.37, 0.0, -13.19)
const FRAME_LIMIT := 3300

var _connections: Array[Array] = []
var _prior_scale: float
var _prior_ticks: int


func before_each() -> void:
	_prior_scale = Engine.time_scale
	_prior_ticks = Engine.physics_ticks_per_second
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180


func after_each() -> void:
	for connection: Array in _connections:
		var watched: Signal = connection[0]
		if is_instance_id_valid(watched.get_object_id()) and watched.is_connected(connection[1]):
			watched.disconnect(connection[1])
	_connections.clear()
	Engine.time_scale = _prior_scale
	Engine.physics_ticks_per_second = _prior_ticks


func _fixture() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	add_test_child(viewport)
	var main := MAIN_SCENE.instantiate() as MainScene
	viewport.add_child(main)
	var nav := main.get_test_map().get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 180))
	await wait_physics_frames(2)
	var worker: Unit = main.get_units()[0]
	return {"main": main, "nav": nav, "worker": worker, "inventory": main.get_settlement_inventory(),
		"storage": main.get_ground_pile_manager(), "camp": main.get_camp_storage_zone(), "cm": main.get_construction_manager()}


func _until(condition: Callable, limit: int = FRAME_LIMIT) -> bool:
	for _frame: int in range(limit):
		if condition.call():
			return true
		await wait_physics_frames(1)
	return condition.call()


func _site(fx: Dictionary, costs: Dictionary = {}, position: Vector3 = SITE_A) -> ConstructionSite:
	var definition := SHELTER.duplicate() as BuildingDefinition
	if not costs.is_empty():
		definition.costs = costs
	var result: Dictionary = fx.cm.try_create_site_from_placement(definition, position)
	assert_true(result.get("ok", false), str(result))
	return result.get("site") as ConstructionSite


func _extra_worker(fx: Dictionary, id: StringName, position: Vector3) -> Unit:
	var worker := UNIT_SCENE.instantiate() as Unit
	worker.definition = LEADER.duplicate()
	fx.main.get_node("Units").add_child(worker)
	worker.global_position = position
	worker.set_world_navigation(fx.nav)
	assert_true(worker.get_carry_load().enable_provenance(id))
	return worker


func _watch(watched: Signal, callback: Callable) -> void:
	watched.connect(callback)
	_connections.append([watched, callback])


func _authority(site: ConstructionSite) -> ReservedWithdrawalCoordinator.RegionalAuthority:
	var domains: Dictionary = site.get_world_3d().get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	return domains.get(site.region_id) as ReservedWithdrawalCoordinator.RegionalAuthority


func _conserve(fx: Dictionary, site: ConstructionSite, worker: Unit, original: Dictionary) -> void:
	var load := worker.get_carry_load()
	assert_true(load.validate_provenance())
	for resource: StringName in original:
		var physical: int = fx.inventory.get_physical_amount(resource)
		var carried: int = load.get_amount(resource)
		assert_eq(physical + carried + site.get_total_received_amount(resource), original[resource])
		assert_eq(site._read_in_transit_amount_pure(resource), carried)


func test_solo_physically_transports_wood_and_stone_then_completes_building() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	var original := {&"wood": 14, &"stone": 8}
	for resource: StringName in original:
		assert_true(fx.inventory.deposit(resource, original[resource]))
	assert_true(load.enable_provenance(&"solo"))
	var site := _site(fx)
	var site_id := site.site_id
	var order := ConstructOrder.new(site, fx.camp, false, true)
	var pickup_positions: Array[Vector3] = []
	var drop_positions: Array[Vector3] = []
	var signals: Array[String] = []
	_watch(load.load_changed, func() -> void:
		if not site._is_preparing_or_transacting:
			return
		signals.append("load")
		_conserve(fx, site, worker, original)
		var before := order.get_phase()
		order.physics_update(worker.get_movement(), 1.0)
		assert_eq(order.get_phase(), before)
		if not load.is_empty():
			pickup_positions.append(worker.global_position)
			assert_true(load.get_current_weight() <= load.get_effective_capacity())
			assert_eq(load.get_current_weight(), load.get_amount(&"wood") * WOOD.unit_weight + load.get_amount(&"stone") * STONE.unit_weight)
	)
	_watch(site.buffer_changed, func(_changed: ConstructionSite) -> void:
		if not site._is_preparing_or_transacting:
			return
		signals.append("buffer")
		drop_positions.append(worker.global_position)
		assert_true(BuildSlotPlanner.is_unit_in_site_dropoff_range(worker.global_position, site,
			ConstructionSite.DEFAULT_DROPOFF_REACH_TOLERANCE, worker.get_world_3d()))
		assert_true(load.is_empty())
		var phase := order.get_phase()
		order.physics_update(worker.get_movement(), 1.0)
		assert_eq(order.get_phase(), phase)
	)
	_watch(site.state_changed, func(_changed: ConstructionSite) -> void:
		if not site._is_preparing_or_transacting:
			return
		signals.append("state")
		var phase := order.get_phase()
		order.physics_update(worker.get_movement(), 1.0)
		order.cancel(worker.get_movement())
		assert_true(order.is_active())
		assert_eq(order.get_phase(), phase)
		assert_true(_authority(site).is_executing)
	)
	var start_position := worker.global_position
	worker.issue_order(order)
	assert_eq(order.get_worker_role(), ConstructionSite.WorkerRole.SOLO_SUPPLIER)
	assert_true(await _until(func() -> bool:
		return worker.get_state() == Unit.State.TRANSPORTING and not load.is_empty() \
			and worker.get_movement().get_current_load_multiplier() < 0.99 or order.is_finished()))
	assert_false(order.is_finished(), order.failure_reason)
	assert_gt(worker.global_position.distance_to(start_position), 0.5)
	assert_true(await _until(func() -> bool: return order.trips_completed >= 3 or order.is_finished()), order.failure_reason)
	assert_eq(order.units_delivered_total, 18)
	assert_eq(order.trips_completed, drop_positions.size())
	assert_eq(pickup_positions.size(), drop_positions.size())
	for index: int in range(drop_positions.size()):
		assert_gt(pickup_positions[index].distance_to(drop_positions[index]), 1.0)
	assert_eq(signals.count("load"), order.trips_completed * 2)
	assert_eq(signals.count("state"), order.trips_completed * 2)
	assert_eq(signals.count("buffer"), order.trips_completed)
	var authority := _authority(site)
	assert_eq(authority.receipts.size(), order.trips_completed * 2)
	assert_eq(authority.committed_lots.size(), order.trips_completed)
	for op: StringName in authority.receipts:
		var receipt: Dictionary = authority.receipts[op].receipt
		assert_eq(receipt.operation_id, op)
		assert_eq(authority.is_executing, false)
	assert_true(await _until(func() -> bool: return fx.cm.get_completed_buildings().size() == 1 or order.is_finished()))
	assert_true(await _until(func() -> bool: return order.is_finished(), 30))
	assert_true(order.is_succeeded(), order.failure_reason)
	var completed: Array[BuildingInstance] = fx.cm.get_completed_buildings()
	assert_eq(completed.size(), 1)
	if not completed.is_empty():
		assert_eq(completed[0].building_id, site_id)
		assert_eq(completed[0].incorporated_materials, {&"wood": 12, &"stone": 6})
	assert_eq(fx.inventory.get_physical_amount(&"wood"), 2)
	assert_eq(fx.inventory.get_physical_amount(&"stone"), 2)
	assert_true(load.is_empty())


func test_default_and_opt_in_admission_keep_existing_loads_and_legacy_economy() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	assert_true(fx.inventory.deposit(&"wood", 2))
	var site := _site(fx, {&"wood": 2})
	assert_true(load.add_units(WOOD, 1))
	assert_false(load.enable_provenance(&"cannot_guess_origin"))
	var rejected := ConstructOrder.new(site, fx.camp, false, true)
	worker.issue_order(rejected)
	assert_eq(rejected.failure_reason, ConstructOrder.REASON_PROVENANCE_REQUIRED)
	assert_eq(load.get_amount(&"wood"), 1)
	assert_eq(site.get_assigned_worker_entries(), [])
	assert_null(_authority(site))
	assert_eq(load.take_all(), {&"wood": 1})
	var legacy := ConstructOrder.new(site, fx.camp, true)
	worker.issue_order(legacy)
	assert_true(await _until(func() -> bool: return legacy.is_finished()))
	assert_true(legacy.is_succeeded(), legacy.failure_reason)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 2)
	assert_null(_authority(site))
	assert_false(load.is_provenance_enabled())
	assert_true(load.enable_provenance(&"explicit"))
	var incompatible := ConstructOrder.new(site, fx.camp, true)
	worker.issue_order(incompatible)
	assert_eq(incompatible.failure_reason, ConstructOrder.REASON_PROVENANCE_OPT_IN_REQUIRED)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 2)
	assert_null(_authority(site))


func test_interrupted_trip_reuses_attributed_cargo_and_preserves_unrelated_cargo() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	assert_true(fx.inventory.deposit(&"wood", 16))
	assert_true(fx.inventory.deposit(&"stone", 4))
	assert_true(load.enable_provenance(&"interruptible"))
	var site := _site(fx, {&"wood": 10})
	var other := _site(fx, {&"stone": 3}, SITE_B)
	var first := ConstructOrder.new(site, fx.camp, true, true)
	worker.issue_order(first)
	assert_true(await _until(func() -> bool: return not load.is_empty() or first.is_finished()))
	assert_false(first.is_finished(), first.failure_reason)
	var initial := load.provenance_snapshot()
	var claim := site._read_transit_claim_for_unit_pure(worker.get_instance_id())
	var held_wood := load.get_amount(&"wood")
	var authority := _authority(site)
	assert_eq(authority.receipts.size(), 1)
	assert_gt(held_wood, 0)
	worker.issue_order(MoveOrder.new(worker.global_position + Vector3(0.0, 0.0, 2.0)))
	assert_eq(first.status, UnitOrder.Status.CANCELLED)
	assert_eq(load.provenance_snapshot(), initial)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), claim)

	var wrong_site := ConstructOrder.new(other, fx.camp, true, true)
	worker.issue_order(wrong_site)
	assert_eq(wrong_site.failure_reason, ConstructOrder.REASON_SELECTIVE_CAMP_DELIVERY_REQUIRED)
	assert_eq(load.provenance_snapshot(), initial)
	assert_eq(other.get_delivered_buffer_amount(&"stone"), 0)
	assert_eq(other.get_reserved_in_piles_amount(&"stone"), 3)

	var restarted := ConstructOrder.new(site, fx.camp, true, true)
	worker.issue_order(restarted)
	worker.cancel_current_order()
	assert_eq(restarted.status, UnitOrder.Status.CANCELLED)
	assert_eq(load.provenance_snapshot(), initial)
	var free_source := ResourceSource.new()
	fx.main.add_child(free_source)
	free_source.configure(&"extra_tree", WOOD.duplicate(), 5, 2, 1)
	load.set_base_capacity(22)
	assert_eq(free_source.transfer_to_carry_load_with_provenance(load, &"gather", &"free", 1).extracted, 1)
	var expected_free: Dictionary = load.provenance_snapshot().ledger.lots[&"free"]
	var resume := ConstructOrder.new(site, fx.camp, true, true)
	worker.issue_order(resume)
	assert_true(await _until(func() -> bool: return resume.trips_completed == 1 or resume.is_finished()))
	assert_eq(resume.units_delivered_total, held_wood, resume.failure_reason)
	assert_eq(authority.receipts.size(), 2, "Resuming existing cargo must not withdraw again")
	assert_eq(load.provenance_snapshot().ledger.lots, {&"free": expected_free})
	assert_eq(other.get_reserved_in_piles_amount(&"stone"), 3)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), {})
	assert_true(await _until(func() -> bool: return resume.is_finished(), 30))
	assert_true(resume.is_succeeded(), resume.failure_reason)


func test_d9_transporter_builder_slots_and_fourth_worker_rejection() -> void:
	var fx := await _fixture()
	var a: Unit = fx.worker
	assert_true(a.get_carry_load().enable_provenance(&"transporter"))
	assert_true(fx.inventory.deposit(&"wood", 12))
	assert_true(fx.inventory.deposit(&"stone", 6))
	var site := _site(fx)
	var site_id := site.site_id
	var b := _extra_worker(fx, &"builder_b", Vector3(-3.0, 0.0, 4.0))
	var c := _extra_worker(fx, &"builder_c", Vector3(-11.0, 0.0, 4.0))
	var d := _extra_worker(fx, &"fourth", Vector3(-10.0, 0.0, 5.0))
	var a_order := ConstructOrder.new(site, fx.camp, false, true)
	var d_order := ConstructOrder.new(site, fx.camp, false, true)
	a.issue_order(a_order)
	b.issue_order(ConstructOrder.new(site, fx.camp, false, true))
	assert_eq(site.get_worker_role(a), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(site.get_worker_role(b), ConstructionSite.WorkerRole.BUILDER)
	c.issue_order(ConstructOrder.new(site, fx.camp, false, true))
	d.issue_order(d_order)
	assert_eq(site.get_worker_role(c), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(d_order.failure_reason, ConstructOrder.REASON_NO_WORKER_SLOT)
	assert_eq(site.get_assigned_worker_entries().size(), 3)
	assert_true(await _until(func() -> bool:
		return is_instance_valid(site) and site.get_work_progress_sec() > 0 and not site.is_fully_supplied() or a_order.is_finished()))
	assert_false(a_order.is_finished(), a_order.failure_reason)
	assert_gt(site.get_work_progress_sec(), 0.0)
	assert_false(site.is_fully_supplied())
	assert_true(await _until(func() -> bool: return fx.cm.get_completed_buildings().size() == 1))
	var buildings: Array[BuildingInstance] = fx.cm.get_completed_buildings()
	if not buildings.is_empty():
		assert_eq(buildings[0].building_id, site_id)
		assert_eq(buildings[0].incorporated_materials, {&"wood": 12, &"stone": 6})
	assert_eq(a_order.units_delivered_total, 18)
	assert_true(a.get_carry_load().is_empty())


func test_busy_and_replay_resume_original_intents_without_counting_a_second_trip() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	assert_true(load.enable_provenance(&"retry_worker"))
	assert_true(fx.inventory.deposit(&"wood", 4))
	var site := _site(fx, {&"wood": 4})
	var order := ConstructOrder.new(site, fx.camp, true, true)
	var transfer := order._provenance_transfer

	# Hold the backpack participant busy. The unit still walks to the pile.
	load.begin_batch()
	worker.issue_order(order)
	assert_true(await _until(func() -> bool:
		return transfer.retry_kind == ConstructionTransferSession.Kind.WITHDRAWAL or order.is_finished()))
	assert_false(order.is_finished(), order.failure_reason)
	var pickup := transfer._operation_id
	var lot := transfer._lot_id
	assert_ne(pickup, &"")
	assert_ne(lot, &"")
	assert_eq(fx.inventory.get_physical_amount(&"wood"), 4)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 4)
	assert_true(load.is_empty())
	assert_eq(_authority(site).receipts.size(), 0)
	await wait_physics_frames(3)
	assert_eq(transfer._operation_id, pickup)
	assert_eq(transfer._lot_id, lot)
	assert_eq(transfer._busy_retries, 1)
	load.end_batch()
	# Commit via another handle before the order's controlled retry to exercise
	# an actual regional replay, using the exact frozen intent and live claim.
	var other_pickup := ReservedWithdrawalCoordinator.new()
	var picked := other_pickup.execute_reserved_withdrawal(site, worker, transfer._pile_id, transfer._resource_id,
		transfer._amount, pickup, lot)
	assert_eq(picked.get("withdrawn"), 4, str(picked))
	assert_eq(other_pickup.get_receipt(pickup), picked.get("receipt"))
	assert_true(await _until(func() -> bool:
		return transfer.retry_kind == ConstructionTransferSession.Kind.NONE or order.is_finished(), 40))
	assert_eq(load.get_all_amounts(), {&"wood": 4})
	assert_eq(_authority(site).committed_lots.size(), 1)
	assert_eq(_authority(site).receipts.size(), 1)

	load.begin_batch()
	assert_true(await _until(func() -> bool:
		return transfer.retry_kind == ConstructionTransferSession.Kind.DELIVERY or order.is_finished()))
	assert_false(order.is_finished(), order.failure_reason)
	var dropoff := transfer._operation_id
	assert_ne(dropoff, &"")
	assert_ne(dropoff, pickup)
	assert_eq(order.trips_completed, 0)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(load.get_amount(&"wood"), 4)
	await wait_physics_frames(3)
	assert_eq(transfer._operation_id, dropoff)
	assert_eq(transfer._busy_retries, 1)
	load.end_batch()
	var other_dropoff := SelectiveSiteDeliveryCoordinator.new()
	var dropped := other_dropoff.execute_selective_site_delivery(site, worker, dropoff)
	assert_eq(dropped.get("delivered_now"), 4, str(dropped))
	assert_eq(other_dropoff.get_receipt(dropoff), dropped.get("receipt"))
	var conflicting := other_pickup.execute_reserved_withdrawal(site, worker, 1, &"wood", 1, dropoff, &"different_lot")
	assert_eq(conflicting.reason, "operation_conflict")
	assert_true(await _until(func() -> bool: return order.is_finished(), 80))
	assert_true(order.is_succeeded(), order.failure_reason)
	assert_eq(order.trips_completed, 0)
	assert_eq(order.units_delivered_total, 0)
	assert_eq(_authority(site).receipts.size(), 2)
	assert_eq(_authority(site).committed_lots.size(), 1)
	assert_eq(fx.inventory.get_physical_amount(&"wood"), 0)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 4)
	assert_true(load.is_empty())


func test_builder_with_interrupted_claim_keeps_cargo_until_an_authorized_order() -> void:
	var fx := await _fixture()
	var a: Unit = fx.worker
	var load := a.get_carry_load()
	assert_true(load.enable_provenance(&"loaded_builder"))
	# Leave a reservation for the replacement to claim while A carries four.
	assert_true(load.set_base_capacity(8))
	assert_true(fx.inventory.deposit(&"wood", 6))
	var site := _site(fx, {&"wood": 6})
	var carrier := ConstructOrder.new(site, fx.camp, false, true)
	a.issue_order(carrier)
	assert_true(await _until(func() -> bool: return not load.is_empty() or carrier.is_finished()))
	assert_false(carrier.is_finished(), carrier.failure_reason)
	var cargo := load.provenance_snapshot()
	a.cancel_current_order()
	var b := _extra_worker(fx, &"takes_transport_seat", Vector3(-3.0, 0.0, 4.0))
	var replacement := ConstructOrder.new(site, fx.camp, false, true)
	b.issue_order(replacement)
	assert_eq(replacement.get_worker_role(), ConstructionSite.WorkerRole.SOLO_SUPPLIER)
	var restore := ConstructOrder.new(site, fx.camp, false, true)
	a.issue_order(restore)
	assert_eq(restore.failure_reason, ConstructOrder.REASON_PROVENANCE_BUILDER_CARGO)
	assert_eq(load.provenance_snapshot(), cargo)
	assert_eq(site._read_transit_claim_for_unit_pure(a.get_instance_id()), {&"wood": 4})
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(_authority(site).receipts.size(), 1)
	b.cancel_current_order()

	var authorized := ConstructOrder.new(site, fx.camp, false, true)
	a.issue_order(authorized)
	assert_eq(authorized.get_worker_role(), ConstructionSite.WorkerRole.SOLO_SUPPLIER)
	assert_true(await _until(func() -> bool: return authorized.trips_completed == 1 or authorized.is_finished()))
	assert_eq(authorized.units_delivered_total, 4, authorized.failure_reason)
	assert_true(load.is_empty())
	assert_eq(_authority(site).receipts.size(), 2)


func test_generation_and_unreachable_dropoff_preserve_committed_cargo() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	assert_true(load.enable_provenance(&"held_on_failure"))
	assert_true(fx.inventory.deposit(&"wood", 4))
	var site := _site(fx, {&"wood": 4})
	var first := ConstructOrder.new(site, fx.camp, true, true)
	worker.issue_order(first)
	assert_true(await _until(func() -> bool: return not load.is_empty() or first.is_finished()))
	assert_false(first.is_finished(), first.failure_reason)
	var snapshot := load.provenance_snapshot()
	site._generation += 1
	assert_true(await _until(func() -> bool: return first.is_finished()))
	assert_eq(first.failure_reason, "provenance_delivery:generation_mismatch")
	assert_eq(load.provenance_snapshot(), snapshot)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), {&"wood": 4})
	assert_eq(first.trips_completed, 0)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(_authority(site).receipts.size(), 1)

	# Controlled adversarial move of the fixture outside the real navmesh.
	site._generation -= 1
	site.global_position = Vector3(150, 0, 150)
	var unreachable := ConstructOrder.new(site, fx.camp, true, true)
	worker.issue_order(unreachable)
	assert_true(await _until(func() -> bool: return unreachable.is_finished(), 120))
	assert_eq(unreachable.failure_reason, ConstructOrder.REASON_SITE_UNREACHABLE)
	assert_eq(load.provenance_snapshot(), snapshot)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), {&"wood": 4})
	assert_eq(unreachable.trips_completed, 0)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(_authority(site).receipts.size(), 1)


func test_selected_pile_expires_during_walk_without_synthetic_pickup_or_replacement() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	assert_true(load.enable_provenance(&"decay_worker"))
	assert_true(fx.inventory.deposit(&"wood", 4))
	var site := _site(fx, {&"wood": 4})
	var order := ConstructOrder.new(site, fx.camp, true, true)
	worker.issue_order(order)
	assert_eq(order.get_phase(), ConstructOrder.Phase.MOVING_TO_PILE)
	assert_gt(order.get_target_pile_id(), 0)
	assert_true(load.is_empty())
	assert_eq(_authority(site), null)
	fx.main.get_time_provider().advance(10000.0)
	fx.storage.step_decay()
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 0)
	assert_eq(site.get_missing_amount(&"wood"), 4)
	assert_true(await _until(func() -> bool: return order.is_finished(), 120))
	assert_eq(order.failure_reason, ConstructOrder.REASON_RESERVATION_UNAVAILABLE)
	assert_true(load.is_empty())
	assert_eq(load.provenance_snapshot().ledger.operations, {})
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), {})
	assert_null(_authority(site))


func test_failed_withdrawal_and_exhausted_contention_leave_the_reserved_pile_intact() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	assert_true(load.enable_provenance(&"failed_pickup"))
	assert_true(fx.inventory.deposit(&"stone", 3))
	var site := _site(fx, {&"stone": 3})
	var before := load.provenance_snapshot()
	var failed := ConstructOrder.new(site, fx.camp, true, true)
	failed._provenance_transfer._withdrawal.fault_injection_hook = func(stage: String, _context: Dictionary) -> bool:
		return stage != "after_carry_add"
	worker.issue_order(failed)
	assert_true(await _until(func() -> bool: return failed.is_finished()))
	assert_eq(failed.failure_reason, "provenance_withdrawal:aborted_after_carry_add")
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 3)
	assert_eq(fx.inventory.get_physical_amount(&"stone"), 3)
	assert_eq(_authority(site).receipts.size(), 0)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), {})
	assert_eq(site._pending_pickups, {})
	assert_eq(failed.trips_completed, 0)

	var blocked := ConstructOrder.new(site, fx.camp, true, true)
	load.begin_batch()
	worker.issue_order(blocked)
	assert_true(await _until(func() -> bool: return blocked.is_finished()))
	load.end_batch()
	assert_eq(blocked.failure_reason, "provenance_withdrawal:busy_retry_exhausted")
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 3)
	assert_eq(fx.inventory.get_physical_amount(&"stone"), 3)
	assert_eq(_authority(site).receipts.size(), 0)
	assert_eq(site._pending_pickups, {})
	assert_eq(blocked.trips_completed, 0)

	# A new generation invalidates the frozen attempt before the retry can
	# turn an old operation ID into a withdrawal for a different generation.
	var stale := ConstructOrder.new(site, fx.camp, true, true)
	load.begin_batch()
	worker.issue_order(stale)
	var transfer := stale._provenance_transfer
	assert_true(await _until(func() -> bool:
		return transfer.retry_kind == ConstructionTransferSession.Kind.WITHDRAWAL or stale.is_finished()))
	assert_false(stale.is_finished(), stale.failure_reason)
	assert_ne(transfer._operation_id, &"")
	site._generation += 1
	load.end_batch()
	assert_true(await _until(func() -> bool: return stale.is_finished(), 80))
	assert_eq(stale.failure_reason, "provenance_withdrawal:transaction_identity_changed")
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(site.get_reserved_in_piles_amount(&"stone"), 3)
	assert_eq(fx.inventory.get_physical_amount(&"stone"), 3)
	assert_eq(_authority(site).receipts.size(), 0)


func test_transient_navigation_blocker_waits_with_cargo_then_resumes_delivery() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load := worker.get_carry_load()
	var nav: WorldNavigation = fx.nav
	assert_true(load.enable_provenance(&"nav_wait_worker"))
	assert_true(fx.inventory.deposit(&"wood", 4))
	var site := _site(fx, {&"wood": 4})
	var order := ConstructOrder.new(site, fx.camp, true, true)
	worker.issue_order(order)
	assert_true(await _until(func() -> bool:
		return worker.get_state() == Unit.State.TRANSPORTING and not load.is_empty() or order.is_finished()))
	assert_false(order.is_finished(), order.failure_reason)
	# Controlled pending blocker, using the same route query and signal handling
	# as a rebake. The separate T3.4.5 suite exercises actual bake and sync.
	var start := worker.global_position
	var target := order.get_reserved_target()
	var midpoint := (start + target) * 0.5
	var rect := Rect2(midpoint.x - 0.3, -100, 0.6, 200)
	if absf(target.x - start.x) < absf(target.z - start.z):
		rect = Rect2(-100, midpoint.z - 0.3, 200, 0.6)
	nav._pending_building_blockers.append({"rect": rect, "revision": nav.get_navigation_revision(),
		"instance_id": site.get_instance_id(), "permanent_degraded": false})
	nav.building_blocker_added.emit(rect)
	var before := load.provenance_snapshot()
	var stopped := Vector2(worker.global_position.x, worker.global_position.z)
	assert_true(worker.get_movement()._awaiting_pending_nav_sync)
	assert_eq(nav.get_pending_route_reason(worker.global_position, order.get_reserved_target()), "pending_building_nav_sync")
	await wait_physics_frames(18)
	assert_true(order.is_active())
	assert_eq(order.trips_completed, 0)
	assert_eq(load.provenance_snapshot(), before)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), {&"wood": 4})
	assert_eq(_authority(site).receipts.size(), 1)
	assert_lt(stopped.distance_to(Vector2(worker.global_position.x, worker.global_position.z)), 0.15)
	nav._pending_building_blockers.clear()
	nav.navigation_ready.emit()
	assert_true(await _until(func() -> bool: return order.is_finished()))
	assert_true(order.is_succeeded(), order.failure_reason)
	assert_eq(order.trips_completed, 1)
	assert_eq(order.units_delivered_total, 4)
	assert_eq(_authority(site).receipts.size(), 2)
	assert_true(load.is_empty())
