extends TestCase

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const LEADER: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")
const SITE_A_POS := Vector3(-6.0, 0.0, 1.5)
const SITE_B_POS := Vector3(0.37, 0.0, -13.19)
const SITE_C_POS := Vector3(-12.0, 0.0, -8.0)
const FAR_WALK_POS := Vector3(-9.5, 0.0, 6.5)
const FRAME_LIMIT := 3600

var _connections: Array[Array] = []
var _prior_scale: float
var _prior_ticks: int


class UncertainOnceSession extends CampDeliveryTransferSession:
	var commit_before_uncertain: bool = false
	var uncertain_triggered: bool = false
	var invoke_count: int = 0

	func _invoke_coordinator(
		inventory: SettlementInventory,
		camp_zone: CampStorageZone,
		unit: Unit,
		region: StringName
	) -> Dictionary:
		invoke_count += 1
		if not uncertain_triggered:
			uncertain_triggered = true
			if commit_before_uncertain:
				_coordinator.execute_selective_camp_delivery(
					inventory, camp_zone, unit, region, _operation_id, _requested_lots
				)
			return {}
		return super._invoke_coordinator(inventory, camp_zone, unit, region)


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
	return {
		"vp": viewport,
		"main": main,
		"nav": nav,
		"worker": worker,
		"inventory": main.get_settlement_inventory(),
		"storage": main.get_ground_pile_manager(),
		"camp": main.get_camp_storage_zone(),
		"cm": main.get_construction_manager(),
		"cmd": main.get_node("CommandController") as CommandController,
		"sel": main.get_node("SelectionManager") as SelectionManager,
		"region": nav.get_region_id(),
	}


func _until(condition: Callable, limit: int = FRAME_LIMIT) -> bool:
	for _frame: int in range(limit):
		if condition.call():
			return true
		await wait_physics_frames(1)
	return condition.call()


func _watch(watched: Signal, callback: Callable) -> void:
	watched.connect(callback)
	_connections.append([watched, callback])


func _place_worker(fx: Dictionary, worker: Unit, target_pos: Vector3) -> void:
	var nav: WorldNavigation = fx.nav
	var snapped: Vector3 = nav.snap_to_navmesh(target_pos)
	worker.global_position = snapped
	worker.get_movement().stop_movement()


func _extra_worker(fx: Dictionary, id: StringName, pos: Vector3, enable_prov: bool = true) -> Unit:
	var worker := UNIT_SCENE.instantiate() as Unit
	worker.definition = LEADER.duplicate()
	fx.main.get_node("Units").add_child(worker)
	worker.set_world_navigation(fx.nav)
	_place_worker(fx, worker, pos)
	if enable_prov:
		assert_true(worker.get_carry_load().enable_provenance(id))
	return worker


func _create_site(fx: Dictionary, costs: Dictionary, pos: Vector3 = SITE_A_POS) -> ConstructionSite:
	var definition := SHELTER.duplicate() as BuildingDefinition
	definition.costs = costs
	var result: Dictionary = fx.cm.try_create_site_from_placement(definition, pos)
	assert_true(bool(result.get("ok", false)), str(result))
	return result.get("site") as ConstructionSite


func _add_free_lot(
	worker: Unit,
	def: ResourceDefinition,
	amount: int,
	op_id: StringName,
	lot_id: StringName
) -> void:
	var load: UnitCarryLoad = worker.get_carry_load()
	var res: Dictionary = CarryFixture.add_lot(load,
		op_id, lot_id, def.resource_id, def.unit_weight, amount, CarryProvenanceLedger.FREE_GATHERED
	)
	assert_true(bool(res.get("ok", false)), str(res))


func _withdraw_site_lot_physically(
	fx: Dictionary,
	site: ConstructionSite,
	worker: Unit,
	resource_id: StringName,
	amount: int,
	op_id: StringName,
	lot_id: StringName
) -> void:
	var inv: SettlementInventory = fx.inventory
	var entries: Array[Dictionary] = inv.get_reserved_pile_entries(site.reservation_id, resource_id)
	assert_false(entries.is_empty(), "Expected reserved pile for %s on %s" % [String(resource_id), String(site.site_id)])
	var entry: Dictionary = entries[0]
	var pile_id: int = int(entry["pile_id"])
	var pile_pos: Vector3 = entry["world_pos"] as Vector3
	var saved_pos: Vector3 = worker.global_position
	var temp_order := ConstructOrder.new(site, fx.camp, true, true)
	temp_order._unit = worker
	temp_order.mark_running()
	worker._current_order = temp_order
	var role: ConstructionSite.WorkerRole = site.register_worker(worker, temp_order, true)
	assert_ne(role, ConstructionSite.WorkerRole.UNASSIGNED)
	var claimed: int = site.claim_pickup(worker, pile_id, resource_id, amount, int(entry["reserved_amount"]))
	assert_eq(claimed, amount)
	_place_worker(fx, worker, pile_pos)
	var coord := ReservedWithdrawalCoordinator.new()
	var res: Dictionary = coord.execute_reserved_withdrawal(site, worker, pile_id, resource_id, amount, op_id, lot_id)
	assert_true(bool(res.get("ok", false)), str(res))
	site.unregister_worker(worker, temp_order)
	worker._current_order = null
	_place_worker(fx, worker, saved_pos)


func _authority(fx: Dictionary) -> ReservedWithdrawalCoordinator.RegionalAuthority:
	var world: World3D = (fx.worker as Unit).get_world_3d()
	if world == null:
		return null
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	return domains.get(fx.region) as ReservedWithdrawalCoordinator.RegionalAuthority


func _assert_global_conservation(
	fx: Dictionary,
	workers: Array[Unit],
	sites: Array[ConstructionSite],
	expected_totals: Dictionary
) -> void:
	var storage: GroundPileManager = fx.storage
	var inv: SettlementInventory = fx.inventory
	# 54. Zero orphan piles in raw storage._piles
	var seen_ids: Dictionary = {}
	for raw_p: Variant in storage._piles:
		assert_not_null(raw_p)
		assert_true(is_instance_valid(raw_p))
		var pile := raw_p as GroundResourcePile
		assert_true(pile.is_valid())
		assert_true(pile.is_inside_tree())
		assert_eq(pile.get_parent(), storage._piles_root)
		assert_true(pile.is_in_group(GroundResourcePile.GROUP_GROUND_PILES))
		assert_false(seen_ids.has(pile.pile_id))
		seen_ids[pile.pile_id] = true
		# 52. Reservations backed by physical pile
		var res_on_pile: int = storage.get_pile_reserved_amount(pile.pile_id)
		assert_true(res_on_pile >= 0 and res_on_pile <= pile.amount)

	var ledger_by_pile: Dictionary = storage._ledger.snapshot_state().get("by_pile", {}) as Dictionary
	for pid_var: Variant in ledger_by_pile.keys():
		assert_true(seen_ids.has(int(pid_var)), "Orphan reservation ledger entry for pile %s" % str(pid_var))

	# 58. Residual backpack amounts and weights match provenance ledger
	for w: Unit in workers:
		var load: UnitCarryLoad = w.get_carry_load()
		if load.is_provenance_enabled():
			assert_true(load.validate_provenance())
			var expected_w: int = 0
			var amts: Dictionary = load.get_all_amounts()
			var wts: Dictionary = load.get_all_unit_weights()
			for rk: Variant in amts.keys():
				expected_w += int(amts[rk]) * int(wts[rk])
			assert_eq(load.get_current_weight(), expected_w)

	# 53. Transit claims reconciled with provenance ledger lots per active site
	for s: ConstructionSite in sites:
		if not is_instance_valid(s) or not s.is_active():
			continue
		for w: Unit in workers:
			var load: UnitCarryLoad = w.get_carry_load()
			if not load.is_provenance_enabled():
				continue
			var claim: Dictionary = s._read_transit_claim_for_unit_pure(w.get_instance_id())
			var lot_sum: Dictionary = {}
			var lots: Dictionary = load.provenance_snapshot()["ledger"]["lots"] as Dictionary
			for l_var: Variant in lots.values():
				var l: Dictionary = l_var as Dictionary
				if StringName(l["origin"]) == CarryProvenanceLedger.SITE_RESERVED and StringName(l["site_id"]) == s.site_id:
					var rid := StringName(l["resource_id"])
					lot_sum[rid] = int(lot_sum.get(rid, 0)) + int(l["quantity"])
			assert_eq(claim, lot_sum)

	# 51. Total matter conservation across camp + all carried + all sites buffer/consumed
	for rk: Variant in expected_totals.keys():
		var res_id := StringName(rk)
		var total: int = inv.get_physical_amount(res_id)
		for w: Unit in workers:
			total += w.get_carry_load().get_amount(res_id)
		for s: ConstructionSite in sites:
			if is_instance_valid(s) and s.is_active():
				total += s.get_delivered_buffer_amount(res_id) + s.get_consumed_amount(res_id)
		assert_eq(total, int(expected_totals[res_id]), "Conservation mismatch for %s" % String(res_id))


# ==============================================================================
# GROUP A — COMPATIBILITY (Scenarios 1–6)
# ==============================================================================
func test_group_a_legacy_compatibility_and_strict_opt_in_admission() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp

	# 4. Selective DeliverToCampOrder requires provenance and never auto-converts legacy load (3)
	assert_true(load.add_units(WOOD, 3))
	assert_false(load.is_provenance_enabled())
	var rejected_sel := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(rejected_sel)
	assert_true(rejected_sel.is_finished())
	assert_eq(rejected_sel.failure_reason, DeliverToCampOrder.REASON_PROVENANCE_REQUIRED)
	assert_false(load.is_provenance_enabled(), "Legacy load must never be auto-converted")
	assert_eq(load.get_amount(&"wood"), 3)
	assert_eq(rejected_sel.trips_completed, 0)
	assert_null(_authority(fx), "Rejected selective order must not create RegionalAuthority")

	# 1 & 5. Legacy DeliverToCampOrder walks physically and delivers without selective coordinator
	_place_worker(fx, worker, FAR_WALK_POS)
	var wood_before: int = inv.get_physical_amount(&"wood")
	var legacy_deliver := DeliverToCampOrder.new(camp, inv)
	assert_false(legacy_deliver.is_selective_mode())
	worker.issue_order(legacy_deliver)
	assert_true(legacy_deliver.is_active())
	assert_true(await _until(func() -> bool: return legacy_deliver.is_finished()))
	assert_true(legacy_deliver.is_succeeded(), legacy_deliver.failure_reason)
	assert_eq(legacy_deliver.trips_completed, 1)
	assert_eq(legacy_deliver.last_delivered, {&"wood": 3})
	assert_eq(inv.get_physical_amount(&"wood"), wood_before + 3)
	assert_true(load.is_empty())
	assert_null(_authority(fx), "Legacy DeliverToCampOrder must not touch RegionalAuthority")

	# 2. Legacy GatherResourceOrder gathers and delivers through legacy DeliverToCampOrder
	var source := ResourceSource.new()
	fx.main.add_child(source)
	source.global_position = Vector3(-4.0, 0.0, 5.0)
	source.configure(&"c343_legacy_bush", FOOD.duplicate(), 4, 2, 1)
	load.set_base_capacity(2)
	var food_before: int = inv.get_physical_amount(&"food")
	var gather_order := GatherResourceOrder.new(source, camp, inv, 0.05, 0.0)
	worker.issue_order(gather_order)
	assert_true(await _until(func() -> bool: return gather_order.get_delivered_trips() >= 1 or gather_order.is_finished()))
	assert_true(gather_order.get_delivered_trips() >= 1, gather_order.failure_reason)
	assert_gt(inv.get_physical_amount(&"food"), food_before)
	worker.cancel_current_order()
	assert_null(_authority(fx), "Legacy GatherResourceOrder must not create RegionalAuthority")
	assert_false(load.is_provenance_enabled())
	load.set_base_capacity(20)
	if not load.is_empty():
		load.take_all()

	# 6. RTS CommandController issues ConstructOrder with opt-in disabled by default
	assert_true(inv.deposit(&"wood", 4))
	var site := _create_site(fx, {&"wood": 4})
	var cmd: CommandController = fx.cmd
	assert_true(cmd.command_units_to_site(site, [worker]))
	var issued := worker.get_current_order() as ConstructOrder
	assert_not_null(issued)
	assert_null(issued._provenance_transfer, "RTS CommandController must keep opt-in disabled by default")
	worker.cancel_current_order()

	# 5b. Legacy DeliverToCampOrder fails fail-closed on provenance-enabled load (no silent bypass)
	var prov_worker := _extra_worker(fx, &"prov_legacy_reject", FAR_WALK_POS, true)
	_add_free_lot(prov_worker, WOOD, 2, &"op_a5_g", &"lot_a5_free")
	var legacy_on_prov := DeliverToCampOrder.new(camp, inv, false)
	prov_worker.issue_order(legacy_on_prov)
	assert_true(legacy_on_prov.is_finished())
	assert_eq(legacy_on_prov.failure_reason, DeliverToCampOrder.REASON_PROVENANCE_OPT_IN_REQUIRED)
	assert_eq(prov_worker.get_carry_load().get_amount(&"wood"), 2)
	assert_eq(legacy_on_prov.trips_completed, 0)


# ==============================================================================
# GROUP B — SELECTIVE DELIVERY WITH REAL WALKING (Scenarios 7–16)
# ==============================================================================
func test_group_b_physical_walk_free_partial_reserved_mixed_and_replay_trips() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(load.enable_provenance(&"worker_b"))

	# 7, 8, 9, 10, 16 + §6.1 (no ConstructionSite needed to allocate regional operation_id!)
	_place_worker(fx, worker, FAR_WALK_POS)
	var start_pos: Vector3 = worker.global_position
	_add_free_lot(worker, WOOD, 4, &"op_b_g1", &"lot_b_free_1")
	var wood_before: int = inv.get_physical_amount(&"wood")
	var order_full := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(order_full)
	assert_true(order_full.is_active(), order_full.failure_reason)
	assert_eq(worker.get_state(), Unit.State.TRANSPORTING)

	# Observe mid-walk frames: zero premature credit during walk!
	var saw_moving_without_credit: bool = false
	for _i: int in range(60):
		await wait_physics_frames(1)
		if order_full.is_active() and worker.get_movement().get_move_state() == UnitMovement.MoveState.MOVING:
			saw_moving_without_credit = true
			assert_eq(inv.get_physical_amount(&"wood"), wood_before, "No premature credit during walk")
			assert_eq(order_full.trips_completed, 0)
			assert_eq(load.get_amount(&"wood"), 4)
			break
	assert_true(saw_moving_without_credit, "Worker must physically walk to camp")
	assert_true(await _until(func() -> bool: return order_full.is_finished()))
	assert_true(order_full.is_succeeded(), order_full.failure_reason)
	assert_gt(worker.global_position.distance_to(start_pos), 3.0, "Worker must have physically moved to camp")
	assert_eq(inv.get_physical_amount(&"wood"), wood_before + 4)
	assert_true(load.is_empty())
	assert_eq(order_full.trips_completed, 1)
	assert_eq(order_full.last_delivered, {&"wood": 4})
	assert_eq(order_full.last_delivered_units, 4)
	assert_false(order_full.last_replayed)
	var first_op: StringName = order_full.get_selective_session().get_operation_id()
	assert_true(String(first_op).begins_with("camp_delivery:"), "Regional op id must work without any ConstructionSite")

	# 15. Replay of committed operation_id via coordinator returns replayed=true, delivered_now=0
	var replay_coord := SelectiveCampDeliveryCoordinator.new()
	var rep: Dictionary = replay_coord.execute_selective_camp_delivery(inv, camp, worker, fx.region, first_op, [])
	assert_true(bool(rep.get("ok", false)) and bool(rep.get("replayed", false)))
	assert_eq(int(rep.get("delivered_now", -1)), 0)
	assert_eq(inv.get_physical_amount(&"wood"), wood_before + 4)

	# 11, 13, 14. Mixed load: two FREE_GATHERED lots + SITE_RESERVED for Site A + SITE_RESERVED for Site B
	assert_true(inv.deposit(&"wood", 10))
	assert_true(inv.deposit(&"stone", 6))
	var site_a := _create_site(fx, {&"wood": 4}, SITE_A_POS)
	var site_b := _create_site(fx, {&"stone": 3}, SITE_B_POS)
	_withdraw_site_lot_physically(fx, site_a, worker, &"wood", 3, &"op_b_wa", &"lot_b_site_a")
	_withdraw_site_lot_physically(fx, site_b, worker, &"stone", 2, &"op_b_wb", &"lot_b_site_b")
	_add_free_lot(worker, WOOD, 3, &"op_b_gf1", &"lot_b_free_partial")
	_add_free_lot(worker, FOOD, 2, &"op_b_gf2", &"lot_b_free_food")
	_place_worker(fx, worker, FAR_WALK_POS)

	# Partial unload of 2 out of 3 from lot_b_free_partial: preserves remaining 1 free wood, 2 free food, Site A, Site B
	var camp_wood_pre: int = inv.get_physical_amount(&"wood")
	var camp_free_wood_pre: int = inv.get_available_amount(&"wood")
	var order_partial := DeliverToCampOrder.new(
		camp, inv, true, fx.region, [{"lot_id": &"lot_b_free_partial", "amount": 2}]
	)
	worker.issue_order(order_partial)
	assert_true(await _until(func() -> bool: return order_partial.is_finished()))
	assert_true(order_partial.is_succeeded(), order_partial.failure_reason)
	assert_eq(order_partial.trips_completed, 1)
	assert_eq(order_partial.last_delivered, {&"wood": 2})
	assert_eq(inv.get_physical_amount(&"wood"), camp_wood_pre + 2)
	assert_eq(inv.get_available_amount(&"wood"), camp_free_wood_pre + 2)
	assert_false(load.is_empty(), "Partial unload must succeed with residual lots preserved")
	var lots_after_partial: Dictionary = load.provenance_snapshot()["ledger"]["lots"] as Dictionary
	assert_eq(int(lots_after_partial[&"lot_b_free_partial"]["quantity"]), 1)
	assert_eq(int(lots_after_partial[&"lot_b_free_food"]["quantity"]), 2)
	assert_eq(int(lots_after_partial[&"lot_b_site_a"]["quantity"]), 3)
	assert_eq(int(lots_after_partial[&"lot_b_site_b"]["quantity"]), 2)
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), 1)
	assert_eq(site_b.get_reserved_in_piles_amount(&"stone"), 1)

	# 14. Conservative empty request on mixed cargo unloads ONLY remaining FREE_GATHERED (1 wood + 2 food),
	#     NEVER converting Site A or Site B reserved lots into free stock!
	_place_worker(fx, worker, FAR_WALK_POS)
	var free_wood_before_cons: int = inv.get_available_amount(&"wood")
	var order_cons := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(order_cons)
	assert_true(await _until(func() -> bool: return order_cons.is_finished()))
	assert_true(order_cons.is_succeeded(), order_cons.failure_reason)
	assert_eq(order_cons.trips_completed, 1)
	assert_eq(order_cons.last_delivered, {&"food": 2, &"wood": 1})
	assert_eq(inv.get_available_amount(&"wood"), free_wood_before_cons + 1)
	var lots_after_cons: Dictionary = load.provenance_snapshot()["ledger"]["lots"] as Dictionary
	assert_eq(lots_after_cons.size(), 2)
	assert_true(lots_after_cons.has(&"lot_b_site_a") and lots_after_cons.has(&"lot_b_site_b"))

	# 12. Explicit selection of SITE_RESERVED lot_b_site_a restores Site A's physical reservation without touching Site B or free stock!
	_place_worker(fx, worker, FAR_WALK_POS)
	var free_wood_before_res: int = inv.get_available_amount(&"wood")
	var site_a_res_before: int = site_a.get_reserved_in_piles_amount(&"wood")
	var site_b_claim_before: Dictionary = site_b._read_transit_claim_for_unit_pure(worker.get_instance_id())
	var order_site_a := DeliverToCampOrder.new(
		camp, inv, true, fx.region, [{"lot_id": &"lot_b_site_a", "amount": 3}]
	)
	worker.issue_order(order_site_a)
	assert_true(await _until(func() -> bool: return order_site_a.is_finished()))
	assert_true(order_site_a.is_succeeded(), order_site_a.failure_reason)
	assert_eq(order_site_a.trips_completed, 1)
	assert_eq(inv.get_available_amount(&"wood"), free_wood_before_res, "Reserved return must not convert to free stock")
	assert_eq(site_a.get_reserved_in_piles_amount(&"wood"), site_a_res_before + 3)
	assert_eq(site_a._read_transit_claim_for_unit_pure(worker.get_instance_id()), {})
	assert_eq(site_b._read_transit_claim_for_unit_pure(worker.get_instance_id()), site_b_claim_before)
	assert_eq(load.get_all_amounts(), {&"stone": 2})

	# No eligible free lots left -> conservative empty request fails cleanly without walking
	var no_free := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(no_free)
	assert_true(no_free.is_finished())
	assert_eq(no_free.failure_reason, "no_eligible_free_lots")
	assert_eq(no_free.trips_completed, 0)
	assert_eq(load.get_all_amounts(), {&"stone": 2})


# ==============================================================================
# GROUP C — CONSTRUCTORDER INTEGRATION (Scenarios 17–26)
# ==============================================================================
func test_group_c_construct_order_returns_unneeded_free_and_resumes_building() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(load.enable_provenance(&"worker_c1"))
	assert_true(inv.deposit(&"wood", 6))
	assert_true(inv.deposit(&"stone", 4))

	var site_a := _create_site(fx, {&"wood": 4, &"stone": 2}, SITE_A_POS)
	_place_worker(fx, worker, FAR_WALK_POS)
	_add_free_lot(worker, WOOD, 3, &"op_c1_g", &"lot_c1_free_wood")
	var free_wood_before: int = inv.get_available_amount(&"wood")

	# 17, 18, 19, 20, 22, 25, 26: previously blocked by selective_camp_delivery_required;
	# now walks physically to camp, unloads free wood, resumes site_a supply, promotes to BUILDER, completes site_a!
	var order := ConstructOrder.new(site_a, camp, false, true)
	worker.issue_order(order)
	assert_true(order.is_active(), order.failure_reason)
	assert_eq(order.get_phase(), ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO)
	assert_eq(order.get_worker_role(), ConstructionSite.WorkerRole.SOLO_SUPPLIER)

	# Confirm no premature credit while walking back with unneeded cargo
	var saw_walk: bool = false
	for _i: int in range(60):
		await wait_physics_frames(1)
		if order.get_phase() == ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO and order.camp_return_trips_completed == 0:
			saw_walk = true
			assert_eq(inv.get_available_amount(&"wood"), free_wood_before)
			break
	assert_true(saw_walk, "Worker must physically walk to camp with unneeded cargo")

	assert_true(await _until(func() -> bool: return order.camp_return_trips_completed >= 1 or order.is_finished()))
	assert_false(order.is_finished(), order.failure_reason)
	assert_eq(order.camp_return_trips_completed, 1)
	assert_eq(inv.get_available_amount(&"wood"), free_wood_before + 3)

	# Now finishes supplying and building site_a under D9
	assert_true(await _until(func() -> bool: return fx.cm.get_completed_buildings().size() == 1 or order.is_finished()))
	assert_true(await _until(func() -> bool: return order.is_finished(), 60))
	assert_true(order.is_succeeded(), order.failure_reason)
	assert_eq(order.camp_return_trips_completed, 1)
	assert_eq(order.units_delivered_total, 6)
	assert_true(order.trips_completed >= 1)
	assert_true(load.is_empty())
	var completed: Array[BuildingInstance] = fx.cm.get_completed_buildings()
	assert_eq(completed.size(), 1)
	assert_eq(completed[0].incorporated_materials, {&"wood": 4, &"stone": 2})
	assert_eq(inv.get_physical_amount(&"wood"), 5)
	assert_eq(inv.get_physical_amount(&"stone"), 2)

	# 25 & §9. Multi-worker D9 team (3 workers + 4th rejected) + BUILDER returning unneeded free cargo +
	#          BUILDER stopping cleanly on D3 residual without looping + lost worker link during return!
	var fx_d9 := await _fixture()
	var t_worker: Unit = fx_d9.worker
	assert_true(t_worker.get_carry_load().enable_provenance(&"d9_t"))
	assert_true(fx_d9.inventory.deposit(&"wood", 6))
	assert_true(fx_d9.inventory.deposit(&"stone", 4))
	var d9_site := _create_site(fx_d9, {&"wood": 4, &"stone": 2}, SITE_A_POS)
	var b1 := _extra_worker(fx_d9, &"d9_b1", Vector3(-3.0, 0.0, 4.0), true)
	var b2 := _extra_worker(fx_d9, &"d9_b2", Vector3(-11.0, 0.0, 4.0), true)
	var w4 := _extra_worker(fx_d9, &"d9_w4", Vector3(-10.0, 0.0, 5.0), true)
	_add_free_lot(t_worker, FOOD, 2, &"op_d9_ft", &"lot_d9_ft")
	_add_free_lot(b1, FOOD, 1, &"op_d9_fb1", &"lot_d9_fb1")
	_place_worker(fx_d9, t_worker, FAR_WALK_POS)

	var o_t := ConstructOrder.new(d9_site, fx_d9.camp, false, true)
	var o_b1 := ConstructOrder.new(d9_site, fx_d9.camp, false, true)
	var o_b2 := ConstructOrder.new(d9_site, fx_d9.camp, false, true)
	var o_w4 := ConstructOrder.new(d9_site, fx_d9.camp, false, true)
	t_worker.issue_order(o_t)
	b1.issue_order(o_b1)
	b2.issue_order(o_b2)
	w4.issue_order(o_w4)
	assert_eq(d9_site.get_worker_role(t_worker), ConstructionSite.WorkerRole.TRANSPORTER)
	assert_eq(d9_site.get_worker_role(b1), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(d9_site.get_worker_role(b2), ConstructionSite.WorkerRole.BUILDER)
	assert_eq(o_w4.failure_reason, ConstructOrder.REASON_NO_WORKER_SLOT)

	# Transporter returns free food, supplies d9_site, and finishes SUCCEEDED without becoming a 3rd builder!
	# Builder b1 returns free food, then moves to builder slot and helps assemble!
	assert_true(await _until(func() -> bool: return o_t.is_finished()))
	assert_true(o_t.is_succeeded(), o_t.failure_reason)
	assert_eq(o_t.camp_return_trips_completed, 1)
	assert_eq(o_b1.camp_return_trips_completed, 1)
	assert_true(await _until(func() -> bool: return fx_d9.cm.get_completed_buildings().size() == 1))
	assert_eq(fx_d9.inventory.get_physical_amount(&"food"), 3)

	# Worker loses site link mid-return -> fails cleanly with REASON_NO_WORKER_SLOT without looping
	var fx_link := await _fixture()
	var wl: Unit = fx_link.worker
	assert_true(wl.get_carry_load().enable_provenance(&"lost_link"))
	assert_true(fx_link.inventory.deposit(&"wood", 4))
	var link_site := _create_site(fx_link, {&"wood": 4}, SITE_A_POS)
	_add_free_lot(wl, FOOD, 2, &"op_ll_g", &"lot_ll_free")
	_place_worker(fx_link, wl, FAR_WALK_POS)
	var ll_order := ConstructOrder.new(link_site, fx_link.camp, false, true)
	wl.issue_order(ll_order)
	await wait_physics_frames(6)
	assert_eq(ll_order.get_phase(), ConstructOrder.Phase.RETURNING_UNNEEDED_CARGO)
	link_site.unregister_worker(wl, ll_order)
	assert_true(await _until(func() -> bool: return ll_order.is_finished(), 60))
	assert_eq(ll_order.failure_reason, ConstructOrder.REASON_NO_WORKER_SLOT)
	assert_eq(wl.get_carry_load().get_amount(&"food"), 2)
	assert_eq(fx_link.inventory.get_physical_amount(&"food"), 0)


func test_group_c_construct_order_site_b_preservation_explicit_return_d3_block_and_anti_loop() -> void:
	# Subcase 1 (20, 21, 22, 24): Conservative default unloads FREE_GATHERED once, preserves Site B's lot,
	# NEVER loops, and still supplies Site A using remaining backpack capacity!
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(load.enable_provenance(&"worker_c2"))
	assert_true(inv.deposit(&"wood", 10))
	assert_true(inv.deposit(&"stone", 6))

	var site_a := _create_site(fx, {&"stone": 3}, SITE_A_POS)
	var site_b := _create_site(fx, {&"wood": 4}, SITE_B_POS)
	_withdraw_site_lot_physically(fx, site_b, worker, &"wood", 2, &"op_c2_wb", &"lot_c2_site_b")
	_add_free_lot(worker, WOOD, 3, &"op_c2_gf", &"lot_c2_free")
	_place_worker(fx, worker, FAR_WALK_POS)

	var order_cons := ConstructOrder.new(site_a, camp, true, true)
	worker.issue_order(order_cons)
	assert_true(await _until(func() -> bool: return order_cons.is_finished()))
	assert_true(order_cons.is_succeeded(), order_cons.failure_reason)
	assert_eq(order_cons.camp_return_trips_completed, 1, "Must unload free lot once without looping on Site B residual")
	assert_eq(order_cons.trips_completed, 1)
	assert_eq(order_cons.units_delivered_total, 3)
	assert_eq(site_a.get_delivered_buffer_amount(&"stone"), 3)
	assert_eq(site_a.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), 2)
	assert_eq(site_b._read_transit_claim_for_unit_pure(worker.get_instance_id()), {&"wood": 2})
	assert_eq(load.get_all_amounts(), {&"wood": 2})
	assert_true((load.provenance_snapshot()["ledger"]["lots"] as Dictionary).has(&"lot_c2_site_b"))

	# Subcase 2 (21, 25): Explicit opt-in return_other_site_reserved=true restores Site B's own physical reservation
	# (never converting to free stock or transferring to Site A), then builds Site A!
	var worker2 := _extra_worker(fx, &"worker_c2_explicit", FAR_WALK_POS, true)
	var site_a2 := _create_site(fx, {&"stone": 2}, SITE_C_POS)
	_withdraw_site_lot_physically(fx, site_b, worker2, &"wood", 2, &"op_c2_wb2", &"lot_c2_site_b2")
	_add_free_lot(worker2, FOOD, 2, &"op_c2_gf2", &"lot_c2_free_food")
	var free_wood_before_b2: int = inv.get_available_amount(&"wood")
	var site_b_res_before_b2: int = site_b.get_reserved_in_piles_amount(&"wood")

	var order_explicit := ConstructOrder.new(site_a2, camp, false, true, true)
	worker2.issue_order(order_explicit)
	assert_true(await _until(func() -> bool: return order_explicit.camp_return_trips_completed >= 1 or order_explicit.is_finished()))
	assert_false(order_explicit.is_finished(), order_explicit.failure_reason)
	assert_eq(order_explicit.camp_return_trips_completed, 1)
	assert_eq(inv.get_available_amount(&"wood"), free_wood_before_b2, "Site B lot must not become free stock")
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), site_b_res_before_b2 + 2)
	assert_eq(site_b._read_transit_claim_for_unit_pure(worker2.get_instance_id()), {})
	assert_true(worker2.get_carry_load().is_empty())
	assert_true(await _until(func() -> bool: return order_explicit.is_finished()))
	assert_true(order_explicit.is_succeeded(), order_explicit.failure_reason)
	assert_eq(order_explicit.units_delivered_total, 2)

	# Subcase 3 (23, 24, 25): D3-blocked lot (non-active site) + FREE_GATHERED:
	# unloads ONLY FREE_GATHERED once, NEVER consumes D3 lot, NEVER promotes worker to BUILDER, NEVER loops!
	var fx_d3 := await _fixture()
	var wd3: Unit = fx_d3.worker
	var ld3: UnitCarryLoad = wd3.get_carry_load()
	assert_true(ld3.enable_provenance(&"worker_d3"))
	assert_true(fx_d3.inventory.deposit(&"wood", 10))
	assert_true(fx_d3.inventory.deposit(&"stone", 6))
	var site_done := _create_site(fx_d3, {&"wood": 2}, SITE_B_POS)
	var site_target := _create_site(fx_d3, {&"stone": 2}, SITE_A_POS)
	_withdraw_site_lot_physically(fx_d3, site_done, wd3, &"wood", 2, &"op_d3_w", &"lot_d3_done")
	site_done._site_state = ConstructionSite.SiteState.COMPLETED
	_add_free_lot(wd3, FOOD, 2, &"op_d3_gf", &"lot_d3_free")
	_place_worker(fx_d3, wd3, FAR_WALK_POS)

	var d3_order := ConstructOrder.new(site_target, fx_d3.camp, false, true, true)
	wd3.issue_order(d3_order)
	assert_true(await _until(func() -> bool: return d3_order.is_finished()))
	assert_eq(d3_order.status, UnitOrder.Status.FAILED)
	assert_eq(d3_order.failure_reason, "d3_cancellation_not_implemented")
	assert_eq(d3_order.camp_return_trips_completed, 1, "Must unload free lot once and stop without looping on D3 lot")
	assert_eq(d3_order.trips_completed, 1, "Supplied target site stone before hitting non-promotable D3 residual")
	assert_eq(site_target.get_delivered_buffer_amount(&"stone"), 2)
	assert_eq(site_target.get_worker_role(wd3), ConstructionSite.WorkerRole.UNASSIGNED, "Must not leave worker promoted as BUILDER")
	assert_eq(ld3.get_all_amounts(), {&"wood": 2}, "D3 lot must be preserved untouched")
	assert_true((ld3.provenance_snapshot()["ledger"]["lots"] as Dictionary).has(&"lot_d3_done"))


# ==============================================================================
# GROUP D — CANCELLATION AND FAILURES (Scenarios 27–40)
# ==============================================================================
func test_group_d_cancellation_during_walk_before_commit_after_commit_and_manual_replace() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(load.enable_provenance(&"worker_d_cancel"))
	assert_true(inv.deposit(&"wood", 6))
	var site := _create_site(fx, {&"wood": 4}, SITE_A_POS)
	_withdraw_site_lot_physically(fx, site, worker, &"wood", 3, &"op_dc_w", &"lot_dc_res")
	_add_free_lot(worker, FOOD, 2, &"op_dc_gf", &"lot_dc_free")
	var snap_initial: Dictionary = load.provenance_snapshot()
	var claim_initial: Dictionary = site._read_transit_claim_for_unit_pure(worker.get_instance_id())
	var food_before: int = inv.get_physical_amount(&"food")

	# 27. Cancellation during walk preserves cargo, lots, claims, 0 credit, 0 receipts
	_place_worker(fx, worker, FAR_WALK_POS)
	var order_walk := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(order_walk)
	await wait_physics_frames(10)
	assert_true(order_walk.is_active())
	worker.cancel_current_order()
	assert_eq(order_walk.status, UnitOrder.Status.CANCELLED)
	assert_eq(load.provenance_snapshot(), snap_initial)
	assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), claim_initial)
	assert_eq(inv.get_physical_amount(&"food"), food_before)
	assert_eq(order_walk.trips_completed, 0)

	# 30. Manual order replacement mid-walk cancels camp delivery cleanly and executes MoveOrder
	var order_replace := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(order_replace)
	await wait_physics_frames(8)
	var move_target := Vector3(-11.0, 0.0, 4.0)
	var manual_move := MoveOrder.new(move_target)
	worker.issue_order(manual_move)
	assert_eq(order_replace.status, UnitOrder.Status.CANCELLED)
	assert_eq(order_replace.failure_reason, UnitOrder.REASON_REPLACED)
	assert_true(await _until(func() -> bool: return manual_move.is_finished()))
	assert_true(manual_move.is_succeeded(), manual_move.failure_reason)
	assert_eq(load.provenance_snapshot(), snap_initial)
	assert_eq(inv.get_physical_amount(&"food"), food_before)

	# 28. Cancel BEFORE commit (during busy retry): permanently blocks delayed commits!
	_place_worker(fx, worker, FAR_WALK_POS)
	var order_pre := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	load.begin_batch()
	worker.issue_order(order_pre)
	assert_true(await _until(func() -> bool: return order_pre.get_selective_session().is_retry_scheduled() or order_pre.is_finished()))
	assert_true(order_pre.is_active(), order_pre.failure_reason)
	var pre_op: StringName = order_pre.get_selective_session().get_operation_id()
	assert_ne(pre_op, &"")
	worker.cancel_current_order()
	load.end_batch()
	assert_eq(order_pre.status, UnitOrder.Status.CANCELLED)
	assert_true(order_pre.last_receipt.is_empty())
	# Attempting delayed update or direct execute on cancelled session must NEVER commit
	order_pre.physics_update(worker.get_movement(), 1.0)
	var delayed_res: Dictionary = order_pre.get_selective_session().execute_or_retry(inv, camp, worker, fx.region, order_pre.get_instance_id())
	assert_false(bool(delayed_res.get("ok", true)))
	assert_eq(String(delayed_res.get("reason", "")), "order_cancelled")
	assert_eq(inv.get_physical_amount(&"food"), food_before)
	assert_eq(load.provenance_snapshot(), snap_initial)

	# 29. Cancel AFTER commit already occurred (externally during busy window): recognizes receipt, preserves result!
	_place_worker(fx, worker, FAR_WALK_POS)
	var order_post := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	load.begin_batch()
	worker.issue_order(order_post)
	assert_true(await _until(func() -> bool: return order_post.get_selective_session().is_retry_scheduled() or order_post.is_finished()))
	assert_true(order_post.is_active(), order_post.failure_reason)
	var post_op: StringName = order_post.get_selective_session().get_operation_id()
	load.end_batch()
	var ext_coord := SelectiveCampDeliveryCoordinator.new()
	var ext_res: Dictionary = ext_coord.execute_selective_camp_delivery(inv, camp, worker, fx.region, post_op, [])
	assert_true(bool(ext_res.get("ok", false)), str(ext_res))
	worker.cancel_current_order()
	assert_eq(order_post.status, UnitOrder.Status.CANCELLED)
	assert_eq(order_post.last_receipt, ext_res["receipt"])
	assert_eq(order_post.last_delivered, {&"food": 2})
	assert_true(order_post.last_replayed)
	assert_eq(order_post.trips_completed, 0, "External commit must not double-count trip on cancel")
	assert_eq(inv.get_physical_amount(&"food"), food_before + 2)
	assert_eq(load.get_all_amounts(), {&"wood": 3})


func test_group_d_movement_nav_slot_position_backpack_reservation_gen_capacity_and_callback_failures() -> void:
	# 31. Movement fails by obstacle / unreachable camp
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	var nav: WorldNavigation = fx.nav
	assert_true(load.enable_provenance(&"worker_d_fail"))
	_add_free_lot(worker, FOOD, 3, &"op_df_g", &"lot_df_food")
	var snap_food: Dictionary = load.provenance_snapshot()
	var orig_camp_pos: Vector3 = camp.global_position

	# 31. Movement fails by solid physical obstacle blocking the worker along the path -> stuck, worker keeps cargo!
	_place_worker(fx, worker, FAR_WALK_POS)
	var cage := StaticBody3D.new()
	cage.collision_layer = CollisionLayers.MASK_WORLD_SOLID
	cage.collision_mask = 0
	var dir_to_camp: Vector3 = (camp.global_position - worker.global_position)
	dir_to_camp.y = 0.0
	dir_to_camp = dir_to_camp.normalized()
	var right_dir := Vector3(-dir_to_camp.z, 0.0, dir_to_camp.x)
	for offset_spec: Array in [
		[dir_to_camp * 0.9, Vector3(3.0, 2.5, 0.35)],
		[-dir_to_camp * 0.9, Vector3(3.0, 2.5, 0.35)],
		[right_dir * 0.9, Vector3(0.35, 2.5, 3.0)],
		[-right_dir * 0.9, Vector3(0.35, 2.5, 3.0)],
	]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = offset_spec[1] as Vector3
		cs.shape = bs
		cs.position = (offset_spec[0] as Vector3) + Vector3(0.0, 1.0, 0.0)
		cage.add_child(cs)
	fx.main.add_child(cage)
	cage.global_position = worker.global_position
	await wait_physics_frames(2)
	var obs_order := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(obs_order)
	assert_true(await _until(func() -> bool: return obs_order.is_finished(), 1200))
	assert_eq(obs_order.status, UnitOrder.Status.FAILED)
	assert_eq(obs_order.failure_reason, UnitOrder.REASON_STUCK)
	assert_eq(load.provenance_snapshot(), snap_food)
	assert_eq(inv.get_physical_amount(&"food"), 0)
	assert_eq(obs_order.trips_completed, 0)
	cage.queue_free()
	await wait_physics_frames(2)

	# 32. Navigation becomes unavailable mid-walk (no active bake -> fails cleanly, zero infinite loop)
	_place_worker(fx, worker, FAR_WALK_POS)
	var nav_order := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(nav_order)
	await wait_physics_frames(6)
	assert_true(nav_order.is_active())
	nav._is_ready = false
	assert_true(await _until(func() -> bool: return nav_order.is_finished(), 30))
	assert_eq(nav_order.failure_reason, UnitOrder.REASON_NAVIGATION_NOT_READY)
	assert_eq(load.provenance_snapshot(), snap_food)
	assert_eq(inv.get_physical_amount(&"food"), 0)
	assert_eq(nav_order.trips_completed, 0)
	nav._is_ready = true

	# 33. Dropoff slot invalidated mid-walk (camp zone shifted out of navmesh during walk)
	_place_worker(fx, worker, FAR_WALK_POS)
	var slot_inv_order := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(slot_inv_order)
	await wait_physics_frames(6)
	assert_true(slot_inv_order.is_active())
	camp.global_position = Vector3(150.0, 0.0, 150.0)
	assert_true(await _until(func() -> bool: return slot_inv_order.is_finished(), 60))
	assert_eq(slot_inv_order.failure_reason, DeliverToCampOrder.REASON_CAMP_UNREACHABLE)
	assert_eq(load.provenance_snapshot(), snap_food)
	assert_eq(inv.get_physical_amount(&"food"), 0)
	camp.global_position = orig_camp_pos

	# 34. Unit displaced out of authorized position before commit (during busy retry)
	_place_worker(fx, worker, FAR_WALK_POS)
	var moved_order := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	load.begin_batch()
	worker.issue_order(moved_order)
	assert_true(await _until(func() -> bool: return moved_order.get_selective_session().is_retry_scheduled() or moved_order.is_finished()))
	assert_true(moved_order.is_active(), moved_order.failure_reason)
	load.end_batch()
	_place_worker(fx, worker, FAR_WALK_POS)
	assert_true(await _until(func() -> bool: return moved_order.is_finished(), 120))
	assert_eq(moved_order.failure_reason, "out_of_camp_dropoff_range")
	assert_eq(load.provenance_snapshot(), snap_food)
	assert_eq(inv.get_physical_amount(&"food"), 0)

	# 35. Backpack lot removed/changed mid-walk before arrival
	_place_worker(fx, worker, FAR_WALK_POS)
	var bp_order := DeliverToCampOrder.new(
		camp, inv, true, fx.region, [{"lot_id": &"lot_df_food", "amount": 3}]
	)
	worker.issue_order(bp_order)
	await wait_physics_frames(6)
	assert_true(bp_order.is_active())
	# Mutate backpack lot directly to simulate unexpected loss before arrival
	var debited_ledger := CarryProvenanceLedger.new()
	assert_true(debited_ledger.restore_transaction_state(load.provenance_snapshot()["ledger"]))
	var wd_res: Dictionary = debited_ledger.withdraw(&"op_mid_walk_loss", &"lot_df_food", 2)
	assert_true(bool(wd_res.get("ok", false)))
	load._provenance = debited_ledger
	load._amounts = {&"food": 1}
	load._transaction_revision += 1
	var snap_after_loss: Dictionary = load.provenance_snapshot()
	assert_true(await _until(func() -> bool: return bp_order.is_finished()))
	assert_eq(bp_order.failure_reason, "requested_amount_exceeds_lot")
	assert_eq(load.provenance_snapshot(), snap_after_loss)
	assert_eq(inv.get_physical_amount(&"food"), 0)

	# 36 & 37. Site reservation/claim altered & site generation changed mid-walk
	var fx_s := await _fixture()
	var ws: Unit = fx_s.worker
	var ls: UnitCarryLoad = ws.get_carry_load()
	assert_true(ls.enable_provenance(&"worker_d_site"))
	assert_true(fx_s.inventory.deposit(&"wood", 6))
	var site := _create_site(fx_s, {&"wood": 4}, SITE_A_POS)
	_withdraw_site_lot_physically(fx_s, site, ws, &"wood", 3, &"op_ds_w", &"lot_ds_res")
	var snap_site_res: Dictionary = ls.provenance_snapshot()

	# 37. Generation changes mid-walk
	_place_worker(fx_s, ws, FAR_WALK_POS)
	var gen_order := DeliverToCampOrder.new(
		fx_s.camp, fx_s.inventory, true, fx_s.region, [{"lot_id": &"lot_ds_res", "amount": 3}]
	)
	ws.issue_order(gen_order)
	await wait_physics_frames(6)
	assert_true(gen_order.is_active())
	site._generation += 1
	assert_true(await _until(func() -> bool: return gen_order.is_finished()))
	assert_eq(gen_order.failure_reason, "generation_mismatch")
	assert_eq(ls.provenance_snapshot(), snap_site_res)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 1)
	site._generation -= 1

	# 36. Reservation/claim altered mid-walk (transit claim reduced below lot quantity)
	_place_worker(fx_s, ws, FAR_WALK_POS)
	var claim_order := DeliverToCampOrder.new(
		fx_s.camp, fx_s.inventory, true, fx_s.region, [{"lot_id": &"lot_ds_res", "amount": 3}]
	)
	ws.issue_order(claim_order)
	await wait_physics_frames(6)
	assert_true(claim_order.is_active())
	var uid_s: int = ws.get_instance_id()
	(site._transit_claims[uid_s]["amounts"] as Dictionary)[&"wood"] = 1
	site._transaction_revision += 1
	assert_true(await _until(func() -> bool: return claim_order.is_finished()))
	assert_eq(claim_order.failure_reason, "insufficient_transit_claim")
	assert_eq(ls.provenance_snapshot(), snap_site_res)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 1)

	# 38. Physical camp capacity disappears mid-walk (no_valid_camp_slot)
	var fx_cap := await _fixture()
	var wcap: Unit = fx_cap.worker
	var lcap: UnitCarryLoad = wcap.get_carry_load()
	var zcap: CampStorageZone = fx_cap.camp
	assert_true(lcap.enable_provenance(&"worker_d_cap"))
	_add_free_lot(wcap, FOOD, 3, &"op_dcap_g", &"lot_dcap_food")
	var snap_cap: Dictionary = lcap.provenance_snapshot()
	_place_worker(fx_cap, wcap, FAR_WALK_POS)
	var cap_order := DeliverToCampOrder.new(zcap, fx_cap.inventory, true, fx_cap.region, [])
	wcap.issue_order(cap_order)
	await wait_physics_frames(6)
	assert_true(cap_order.is_active())
	# Shrink zone bounds to fit only 1 slot and occupy it with stone pile at max_pile_amount=1
	zcap.zone_bounds_half_extents = Vector2(0.4, 0.4)
	zcap.slot_spacing = 1.2
	zcap.min_pile_clearance = 0.85
	zcap.max_pile_amount = 1
	assert_true(fx_cap.inventory.deposit(&"stone", 1))
	assert_true(await _until(func() -> bool: return cap_order.is_finished()))
	assert_true(
		cap_order.failure_reason == "no_valid_camp_slot" or cap_order.failure_reason == DeliverToCampOrder.REASON_CAMP_UNREACHABLE,
		"Unexpected failure reason: %s" % cap_order.failure_reason
	)
	assert_eq(lcap.provenance_snapshot(), snap_cap)
	assert_eq(fx_cap.inventory.get_physical_amount(&"food"), 0)

	# 39 & 40. Unsafe callbacks refused with 0 invocations and worker keeps material
	var fx_cb := await _fixture()
	var wcb: Unit = fx_cb.worker
	var lcb: UnitCarryLoad = wcb.get_carry_load()
	var zcb: CampStorageZone = fx_cb.camp
	var scb: GroundPileManager = fx_cb.storage
	assert_true(lcb.enable_provenance(&"worker_d_cb"))
	_add_free_lot(wcb, FOOD, 2, &"op_dcb_g", &"lot_dcb_food")
	var snap_cb: Dictionary = lcb.provenance_snapshot()
	var cb_calls: Array[int] = []
	zcb.set_custom_position_validator(func(_p: Vector3) -> bool:
		cb_calls.append(1)
		return true
	)
	var bad_val := DeliverToCampOrder.new(zcb, fx_cb.inventory, true, fx_cb.region, [])
	wcb.issue_order(bad_val)
	assert_true(bad_val.is_finished())
	assert_eq(bad_val.failure_reason, "unsafe_custom_position_validator")
	assert_eq(cb_calls.size(), 0)
	assert_eq(lcb.provenance_snapshot(), snap_cb)
	zcb.set_custom_position_validator(Callable())

	scb.pile_creator_override = func(_id: int, _def: ResourceDefinition, _amt: int, _pos: Vector3) -> GroundResourcePile:
		cb_calls.append(2)
		return null
	var bad_creator := DeliverToCampOrder.new(zcb, fx_cb.inventory, true, fx_cb.region, [])
	wcb.issue_order(bad_creator)
	assert_true(bad_creator.is_finished())
	assert_eq(bad_creator.failure_reason, "unsafe_pile_creator_override")
	assert_eq(cb_calls.size(), 0)
	assert_eq(lcb.provenance_snapshot(), snap_cb)
	scb.pile_creator_override = Callable()

	# Also verify transient navigation blocker wait & resume cleanly (zero polling)
	_place_worker(fx_cb, wcb, FAR_WALK_POS)
	var tr_order := DeliverToCampOrder.new(zcb, fx_cb.inventory, true, fx_cb.region, [])
	wcb.issue_order(tr_order)
	await wait_physics_frames(6)
	assert_true(tr_order.is_active())
	var tr_nav: WorldNavigation = fx_cb.nav
	var start_tr: Vector3 = wcb.global_position
	var tgt_tr: Vector3 = tr_order.get_reserved_target()
	var mid_tr: Vector3 = (start_tr + tgt_tr) * 0.5
	var blocker := Rect2(mid_tr.x - 0.3, -100.0, 0.6, 200.0)
	if absf(tgt_tr.x - start_tr.x) < absf(tgt_tr.z - start_tr.z):
		blocker = Rect2(-100.0, mid_tr.z - 0.3, 200.0, 0.6)
	tr_nav._pending_building_blockers.append({
		"rect": blocker,
		"revision": tr_nav.get_navigation_revision(),
		"instance_id": 999999,
		"permanent_degraded": false,
	})
	tr_nav.building_blocker_added.emit(blocker)
	await wait_physics_frames(12)
	assert_true(tr_order.is_active())
	assert_eq(fx_cb.inventory.get_physical_amount(&"food"), 0)
	tr_nav._pending_building_blockers.clear()
	tr_nav.navigation_ready.emit()
	assert_true(await _until(func() -> bool: return tr_order.is_finished()))
	assert_true(tr_order.is_succeeded(), tr_order.failure_reason)
	assert_eq(fx_cb.inventory.get_physical_amount(&"food"), 2)
	assert_eq(tr_order.trips_completed, 1)


# ==============================================================================
# GROUP E — IDEMPOTENCY, RETRIES, REPLAY & CONCURRENCY (Scenarios 41–50)
# ==============================================================================
func test_group_e_busy_retries_uncertain_outcome_replay_two_orders_reentrancy_and_cancel_lock() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(load.enable_provenance(&"worker_e"))
	assert_true(inv.deposit(&"wood", 6))
	var site := _create_site(fx, {&"wood": 4}, SITE_A_POS)

	# 41 & 42. busy preserves same operation_id across interval without firing every frame, then commits once
	_add_free_lot(worker, FOOD, 3, &"op_e1_g", &"lot_e1_food")
	_place_worker(fx, worker, FAR_WALK_POS)
	var order_busy := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	var sess_busy: CampDeliveryTransferSession = order_busy.get_selective_session()
	load.begin_batch()
	worker.issue_order(order_busy)
	assert_true(await _until(func() -> bool: return sess_busy.is_retry_scheduled() or order_busy.is_finished()))
	assert_true(order_busy.is_active(), order_busy.failure_reason)
	var frozen_op: StringName = sess_busy.get_operation_id()
	assert_ne(frozen_op, &"")
	assert_eq(sess_busy.get_busy_retries(), 1)
	assert_eq(inv.get_physical_amount(&"food"), 0)
	await wait_physics_frames(3)
	assert_eq(sess_busy.get_busy_retries(), 1, "Must not retry on every physics frame")
	assert_eq(sess_busy.get_operation_id(), frozen_op)
	load.end_batch()
	assert_true(await _until(func() -> bool: return order_busy.is_finished(), 120))
	assert_true(order_busy.is_succeeded(), order_busy.failure_reason)
	assert_eq(sess_busy.get_operation_id(), frozen_op)
	assert_eq(order_busy.trips_completed, 1)
	assert_eq(order_busy.last_delivered_units, 3)
	assert_eq(inv.get_physical_amount(&"food"), 3)

	# 43. Retry limit respected (MAX_BUSY_RETRIES = 4 -> busy_retry_exhausted)
	_add_free_lot(worker, FOOD, 2, &"op_e2_g", &"lot_e2_food")
	var order_exhaust := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	load.begin_batch()
	worker.issue_order(order_exhaust)
	assert_true(await _until(func() -> bool: return order_exhaust.is_finished(), 400))
	load.end_batch()
	assert_eq(order_exhaust.status, UnitOrder.Status.FAILED)
	assert_eq(order_exhaust.failure_reason, "busy_retry_exhausted")
	assert_eq(order_exhaust.get_selective_session().get_busy_retries(), CampDeliveryTransferSession.MAX_BUSY_RETRIES)
	assert_eq(inv.get_physical_amount(&"food"), 3)
	assert_eq(load.get_amount(&"food"), 2)

	# 44a. Uncertain outcome when commit DID happen -> queries receipt & replays idempotently without new ID!
	var order_unc_ok := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	var unc_sess_ok := UncertainOnceSession.new()
	unc_sess_ok.commit_before_uncertain = true
	order_unc_ok._selective_session = unc_sess_ok
	var serial_before_unc: int = _authority(fx).construction_transfer_serial
	worker.issue_order(order_unc_ok)
	assert_true(await _until(func() -> bool: return order_unc_ok.is_finished(), 60))
	assert_true(order_unc_ok.is_succeeded(), order_unc_ok.failure_reason)
	assert_true(order_unc_ok.last_replayed)
	assert_eq(order_unc_ok.last_delivered, {&"food": 2})
	assert_eq(order_unc_ok.trips_completed, 0, "Replay from uncertain outcome must not double-count")
	assert_eq(inv.get_physical_amount(&"food"), 5)
	assert_eq(_authority(fx).construction_transfer_serial, serial_before_unc + 1, "Must NOT allocate second ID")
	assert_eq(unc_sess_ok.invoke_count, 2)

	# 44b. Uncertain outcome when commit did NOT happen -> fails with unknown_transaction_outcome, 0 duplication!
	_add_free_lot(worker, FOOD, 2, &"op_e4b_g", &"lot_e4b_food")
	var order_unc_fail := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	var unc_sess_fail := UncertainOnceSession.new()
	unc_sess_fail.commit_before_uncertain = false
	order_unc_fail._selective_session = unc_sess_fail
	var serial_before_unc2: int = _authority(fx).construction_transfer_serial
	worker.issue_order(order_unc_fail)
	assert_true(await _until(func() -> bool: return order_unc_fail.is_finished(), 60))
	assert_eq(order_unc_fail.status, UnitOrder.Status.FAILED)
	assert_eq(order_unc_fail.failure_reason, "unknown_transaction_outcome")
	assert_eq(inv.get_physical_amount(&"food"), 5)
	assert_eq(load.get_amount(&"food"), 2)
	assert_eq(_authority(fx).construction_transfer_serial, serial_before_unc2 + 1)

	# 45. Replay with a second coordinator committing frozen intent during busy retry
	var order_rep := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	var sess_rep: CampDeliveryTransferSession = order_rep.get_selective_session()
	load.begin_batch()
	worker.issue_order(order_rep)
	assert_true(await _until(func() -> bool: return sess_rep.is_retry_scheduled() or order_rep.is_finished(), 60))
	var rep_op: StringName = sess_rep.get_operation_id()
	load.end_batch()
	var second_coord := SelectiveCampDeliveryCoordinator.new()
	var ext_commit: Dictionary = second_coord.execute_selective_camp_delivery(inv, camp, worker, fx.region, rep_op, [])
	assert_true(bool(ext_commit.get("ok", false)) and not bool(ext_commit.get("replayed", true)))
	assert_true(await _until(func() -> bool: return order_rep.is_finished(), 120))
	assert_true(order_rep.is_succeeded(), order_rep.failure_reason)
	assert_true(order_rep.last_replayed)
	assert_eq(order_rep.trips_completed, 0)
	assert_eq(order_rep.last_delivered_units, 0)
	assert_eq(inv.get_physical_amount(&"food"), 7)

	# 46 & 50. Two orders cannot double-commit same cargo; cancelled intent never commits afterward
	_add_free_lot(worker, FOOD, 3, &"op_e6_g", &"lot_e6_food")
	var ord_first := DeliverToCampOrder.new(camp, inv, true, fx.region, [{"lot_id": &"lot_e6_food", "amount": 3}])
	var ord_second := DeliverToCampOrder.new(camp, inv, true, fx.region, [{"lot_id": &"lot_e6_food", "amount": 3}])
	worker.issue_order(ord_first)
	worker.issue_order(ord_second)
	assert_eq(ord_first.status, UnitOrder.Status.CANCELLED)
	assert_true(await _until(func() -> bool: return ord_second.is_finished(), 60))
	assert_true(ord_second.is_succeeded(), ord_second.failure_reason)
	assert_eq(inv.get_physical_amount(&"food"), 10)
	# Cancelled first order must NEVER commit later even if poked directly
	var post_cancel_try: Dictionary = ord_first.get_selective_session().execute_or_retry(
		inv, camp, worker, fx.region, ord_first.get_instance_id()
	)
	assert_false(bool(post_cancel_try.get("ok", true)))
	assert_eq(String(post_cancel_try.get("reason", "")), "order_cancelled")
	assert_eq(inv.get_physical_amount(&"food"), 10)

	# 47, 48, 49. Reentrancy during load_changed, storage/inventory_changed, and reservations_changed + site.state_changed
	_withdraw_site_lot_physically(fx, site, worker, &"wood", 3, &"op_e_re_w", &"lot_e_re_res")
	_add_free_lot(worker, FOOD, 2, &"op_e_re_gf", &"lot_e_re_free")
	_place_worker(fx, worker, FAR_WALK_POS)
	var re_order := DeliverToCampOrder.new(
		camp, inv, true, fx.region,
		[{"lot_id": &"lot_e_re_free", "amount": 2}, {"lot_id": &"lot_e_re_res", "amount": 3}]
	)
	var re_events: Array[String] = []
	var re_probe := func(sig_name: String) -> void:
		if not re_order.is_selective_transfer_executing():
			return
		re_events.append(sig_name)
		# Verify final committed state is already visible and zero intermediate accounting leaks
		assert_true(load.is_empty(), "Intermediate cargo leaked in %s" % sig_name)
		assert_eq(site.get_reserved_in_piles_amount(&"wood"), 4, "Intermediate reservation leaked in %s" % sig_name)
		assert_eq(site._read_transit_claim_for_unit_pure(worker.get_instance_id()), {})
		# Reentrant physics_update, cancel, issue_order, and second coordinator must all be safely deflected!
		re_order.physics_update(worker.get_movement(), 0.25)
		re_order.cancel(worker.get_movement())
		worker.cancel_current_order()
		worker.issue_order(MoveOrder.new(FAR_WALK_POS))
		assert_eq(re_order.status, UnitOrder.Status.RUNNING, "Order must not self-cancel during %s" % sig_name)
		var r_re: Dictionary = second_coord.execute_selective_camp_delivery(inv, camp, worker, fx.region, &"op_reentrant_blocked", [])
		assert_eq(String(r_re.get("reason", "")), "busy")

	_watch(load.load_changed, func() -> void: re_probe.call("load_changed"))
	_watch(fx.storage.storage_changed, func() -> void: re_probe.call("storage_changed"))
	_watch(inv.inventory_changed, func() -> void: re_probe.call("inventory_changed"))
	_watch(fx.storage.reservations_changed, func() -> void: re_probe.call("storage.reservations_changed"))
	_watch(inv.reservations_changed, func() -> void: re_probe.call("inventory.reservations_changed"))
	_watch(site.state_changed, func(_s: ConstructionSite) -> void: re_probe.call("site.state_changed"))

	worker.issue_order(re_order)
	assert_true(await _until(func() -> bool: return re_order.is_finished()))
	assert_true(re_order.is_succeeded(), re_order.failure_reason)
	assert_eq(re_order.trips_completed, 1, "Reentrancy must not double-count trips")
	assert_eq(re_events.size(), 6, "Expected reentrancy checks across all 6 signals: %s" % str(re_events))
	assert_eq(inv.get_physical_amount(&"food"), 12)
	assert_eq(site.get_reserved_in_piles_amount(&"wood"), 4)

	# §6.2. Identity change (camp_zone.zone_id mutated during busy retry) -> transaction_identity_changed!
	_add_free_lot(worker, FOOD, 2, &"op_e_id_g", &"lot_e_id_food")
	var orig_zone_id: StringName = camp.zone_id
	var id_order := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	load.begin_batch()
	worker.issue_order(id_order)
	assert_true(await _until(func() -> bool: return id_order.get_selective_session().is_retry_scheduled() or id_order.is_finished(), 60))
	assert_true(id_order.is_active(), id_order.failure_reason)
	camp.zone_id = &"mutated_zone_during_retry"
	load.end_batch()
	assert_true(await _until(func() -> bool: return id_order.is_finished(), 120))
	assert_eq(id_order.status, UnitOrder.Status.FAILED)
	assert_eq(id_order.failure_reason, "transaction_identity_changed")
	assert_eq(inv.get_physical_amount(&"food"), 12)
	assert_eq(load.get_amount(&"food"), 2)
	camp.zone_id = orig_zone_id

	# §8. Reentrancy on ConstructOrder during its selective camp return suborder commit signals
	var co_re_events: Array[String] = []
	_place_worker(fx, worker, FAR_WALK_POS)
	var co_re := ConstructOrder.new(site, camp, true, true)
	var co_re_probe := func(sig_name: String) -> void:
		if co_re._deliver_suborder == null or not co_re._deliver_suborder.is_selective_transfer_executing():
			return
		co_re_events.append(sig_name)
		var ph := co_re.get_phase()
		co_re.physics_update(worker.get_movement(), 0.25)
		co_re.cancel(worker.get_movement())
		assert_true(co_re.is_active(), "ConstructOrder must not self-cancel during suborder %s" % sig_name)
		assert_eq(co_re.get_phase(), ph)
	_watch(load.load_changed, func() -> void: co_re_probe.call("co.load_changed"))
	_watch(fx.storage.storage_changed, func() -> void: co_re_probe.call("co.storage_changed"))
	worker.issue_order(co_re)
	assert_true(await _until(func() -> bool: return co_re.camp_return_trips_completed >= 1 or co_re.is_finished()))
	assert_eq(co_re.camp_return_trips_completed, 1)
	assert_eq(co_re_events.size(), 2, "Expected ConstructOrder reentrancy probes during suborder commit")
	assert_eq(inv.get_physical_amount(&"food"), 14)
	worker.cancel_current_order()


# ==============================================================================
# GROUP F — GLOBAL CONSERVATION & MULTI-SITE INVARIANTS (Scenarios 51–60)
# ==============================================================================
func test_group_f_global_conservation_invariants_across_mixed_cycles_and_failures() -> void:
	var fx := await _fixture()
	var w1: Unit = fx.worker
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(w1.get_carry_load().enable_provenance(&"cons_w1"))
	var w2 := _extra_worker(fx, &"cons_w2", Vector3(-8.0, 0.0, 4.0), true)
	var workers: Array[Unit] = [w1, w2]

	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 8))
	assert_true(inv.deposit(&"food", 4))

	var site_a := _create_site(fx, {&"wood": 4, &"stone": 2}, SITE_A_POS)
	var site_b := _create_site(fx, {&"wood": 4, &"stone": 2}, SITE_B_POS)
	var sites: Array[ConstructionSite] = [site_a, site_b]

	# Give w1 mixed load: Site B reserved wood (2) + free wood (2) + free food (3)
	_withdraw_site_lot_physically(fx, site_b, w1, &"wood", 2, &"op_f_wb", &"lot_f_site_b")
	_add_free_lot(w1, WOOD, 2, &"op_f_g1", &"lot_f_free_wood")
	_add_free_lot(w1, FOOD, 3, &"op_f_g2", &"lot_f_free_food")
	# Give w2 free stone (2)
	_add_free_lot(w2, STONE, 2, &"op_f_g3", &"lot_f_free_stone")

	var expected_totals: Dictionary = {
		&"wood": 14, # 12 initial camp + 2 free gathered
		&"stone": 10, # 8 initial camp + 2 free gathered
		&"food": 7, # 4 initial camp + 3 free gathered
	}
	_assert_global_conservation(fx, workers, sites, expected_totals)

	# 59. Signal observer verifies conservation on EVERY economic notification (never intermediate accounting)
	var signal_checks: Array[int] = []
	var verify_on_signal := func() -> void:
		signal_checks.append(1)
		_assert_global_conservation(fx, workers, sites, expected_totals)
	_watch(inv.inventory_changed, verify_on_signal)
	_watch(inv.reservations_changed, verify_on_signal)
	_watch(w1.get_carry_load().load_changed, verify_on_signal)
	_watch(w2.get_carry_load().load_changed, verify_on_signal)

	# Step 1 (55, 56): Failed delivery preserves exact backpack and global conservation
	var snap_w2_pre_fail: Dictionary = w2.get_carry_load().provenance_snapshot()
	var bad_req := DeliverToCampOrder.new(camp, inv, true, fx.region, [{"lot_id": &"missing_lot", "amount": 1}])
	w2.issue_order(bad_req)
	assert_true(bad_req.is_finished())
	assert_eq(bad_req.failure_reason, "lot_not_found")
	assert_eq(w2.get_carry_load().provenance_snapshot(), snap_w2_pre_fail)
	_assert_global_conservation(fx, workers, sites, expected_totals)

	# Step 2 (51–60): w1 supplies Site A via ConstructOrder (returns free wood+food, keeps Site B untouched, supplies Site A);
	#                 w2 walks to camp and unloads free stone!
	_place_worker(fx, w1, FAR_WALK_POS)
	_place_worker(fx, w2, Vector3(-10.0, 0.0, 3.0))
	var site_b_res_before: int = site_b.get_reserved_in_piles_amount(&"wood")
	var site_b_buf_before: Dictionary = site_b.get_delivered_buffer_amounts()
	var w1_order := ConstructOrder.new(site_a, camp, true, true)
	var w2_order := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	w1.issue_order(w1_order)
	w2.issue_order(w2_order)

	assert_true(await _until(func() -> bool: return w1_order.is_finished() and w2_order.is_finished()))
	assert_true(w1_order.is_succeeded(), w1_order.failure_reason)
	assert_true(w2_order.is_succeeded(), w2_order.failure_reason)
	assert_eq(w1_order.camp_return_trips_completed, 1)
	assert_eq(w1_order.units_delivered_total, 6)
	assert_eq(w2_order.trips_completed, 1)
	assert_eq(w2_order.last_delivered, {&"stone": 2})

	# 57. Site B untouched by Site A operations
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), site_b_res_before)
	assert_eq(site_b.get_delivered_buffer_amounts(), site_b_buf_before)
	assert_eq(site_b._read_transit_claim_for_unit_pure(w1.get_instance_id()), {&"wood": 2})
	assert_eq(w1.get_carry_load().get_all_amounts(), {&"wood": 2})
	assert_true(w2.get_carry_load().is_empty())
	assert_gt(signal_checks.size(), 0)
	_assert_global_conservation(fx, workers, sites, expected_totals)

	# Step 3: Explicit return of Site B's lot restores Site B reservation to 4/4, 100% conserved!
	var return_b := DeliverToCampOrder.new(
		camp, inv, true, fx.region, [{"lot_id": &"lot_f_site_b", "amount": 2}]
	)
	w1.issue_order(return_b)
	assert_true(await _until(func() -> bool: return return_b.is_finished()))
	assert_true(return_b.is_succeeded(), return_b.failure_reason)
	assert_eq(return_b.trips_completed, 1)
	assert_eq(site_b.get_reserved_in_piles_amount(&"wood"), 4)
	assert_true(w1.get_carry_load().is_empty())
	_assert_global_conservation(fx, workers, sites, expected_totals)
