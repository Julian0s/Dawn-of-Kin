extends TestCase

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const ROCK_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const LEADER: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")

const SITE_A_POS := Vector3(-6.0, 0.0, 1.5)
const SITE_B_POS := Vector3(0.37, 0.0, -13.19)
const FAR_WALK_POS := Vector3(-9.5, 0.0, 6.5)
const FRAME_LIMIT := 3600

var _connections: Array[Array] = []
var _nodes_to_free: Array[Node] = []
var _prior_scale: float
var _prior_ticks: int


class UncertainOnceGatherSession extends GatherTransferSession:
	var commit_before_uncertain: bool = false
	var remove_source_during_uncertain: bool = false
	var uncertain_triggered: bool = false
	var invoke_count: int = 0

	func _invoke_source_transfer(source: ResourceSource, carry_load: UnitCarryLoad) -> Dictionary:
		invoke_count += 1
		if not uncertain_triggered:
			uncertain_triggered = true
			if commit_before_uncertain and is_instance_valid(source):
				source.transfer_to_carry_load_with_provenance(
					carry_load, _operation_id, _lot_id, _requested_amount
				)
			if remove_source_during_uncertain and is_instance_valid(source) and source.get_parent() != null:
				source.get_parent().remove_child(source)
			return {}
		return super._invoke_source_transfer(source, carry_load)


class TestGatherResourceOrder extends GatherResourceOrder:
	var custom_session_factory: Callable = Callable()
	var custom_deliver_factory: Callable = Callable()

	func _create_gather_session() -> GatherTransferSession:
		if custom_session_factory.is_valid():
			return custom_session_factory.call() as GatherTransferSession
		return super._create_gather_session()

	func _create_selective_deliver_order() -> DeliverToCampOrder:
		if custom_deliver_factory.is_valid():
			return custom_deliver_factory.call() as DeliverToCampOrder
		return super._create_selective_deliver_order()


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
	for node: Node in _nodes_to_free:
		if is_instance_valid(node):
			node.queue_free()
	_nodes_to_free.clear()
	Engine.time_scale = _prior_scale
	Engine.physics_ticks_per_second = _prior_ticks


func _fixture(fast_walk: bool = true) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	add_test_child(viewport)
	var main := MAIN_SCENE.instantiate() as MainScene
	viewport.add_child(main)
	var test_map: TestMap = main.get_test_map()
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 180))
	await wait_physics_frames(2)

	var units: Array[Unit] = main.get_units()
	var worker: Unit = units[0]
	var peer: Unit = units[1]
	if fast_walk:
		_accelerate([worker, peer])
	_place_worker_raw(nav, peer, Vector3(12.0, 0.0, 10.0))

	return {
		"vp": viewport,
		"main": main,
		"test_map": test_map,
		"nav": nav,
		"worker": worker,
		"peer": peer,
		"inventory": main.get_settlement_inventory(),
		"storage": main.get_ground_pile_manager(),
		"camp": main.get_camp_storage_zone(),
		"cm": main.get_construction_manager(),
		"cmd": main.get_node("CommandController") as CommandController,
		"sel": main.get_node("SelectionManager") as SelectionManager,
		"region": nav.get_region_id(),
	}


func _accelerate(units: Array) -> void:
	for u_var: Variant in units:
		if u_var is Unit:
			var u: Unit = u_var as Unit
			var fast_def := (u.get_definition().duplicate() as CharacterDefinition)
			fast_def.move_speed = 7.5
			fast_def.work_approach_speed = 7.5
			fast_def.max_load_speed_multiplier = 1.0
			u.apply_definition(fast_def)


func _until(condition: Callable, limit: int = FRAME_LIMIT) -> bool:
	for _frame: int in range(limit):
		if condition.call():
			return true
		await wait_physics_frames(1)
	return condition.call()


func _watch(watched: Signal, callback: Callable) -> void:
	watched.connect(callback)
	_connections.append([watched, callback])


func _place_worker_raw(nav: WorldNavigation, worker: Unit, target_pos: Vector3) -> void:
	var snapped: Vector3 = nav.snap_to_navmesh(target_pos)
	worker.global_position = snapped
	worker.get_movement().stop_movement()


func _place_worker(fx: Dictionary, worker: Unit, target_pos: Vector3) -> void:
	_place_worker_raw(fx.nav as WorldNavigation, worker, target_pos)


func _rebake(fx: Dictionary) -> void:
	var nav: WorldNavigation = fx.nav
	nav.request_rebake()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 180))
	await wait_physics_frames(2)


func _spawn_source(
	fx: Dictionary,
	scene: PackedScene,
	source_id: StringName,
	pos: Vector3,
	amount: int,
	max_extract: int,
	max_workers: int = 2,
	op_sec: float = 0.06,
	prep_sec: float = 0.0,
	rebake_nav: bool = true
) -> ResourceSource:
	var src := scene.instantiate() as ResourceSource
	src.position = pos
	(fx.test_map as TestMap).add_child(src)
	src.configure(source_id, src.get_definition(), amount, max_extract, max_workers)
	src.set_gather_cycle_timings(op_sec, prep_sec)
	if src.get_category() == ResourceDefinition.Category.WOOD:
		src.felling_duration_sec = 0.14
	await wait_physics_frames(2)
	if rebake_nav:
		await _rebake(fx)
	return src


func _extra_worker(fx: Dictionary, id: StringName, pos: Vector3, enable_prov: bool = true, fast_walk: bool = true) -> Unit:
	var worker := UNIT_SCENE.instantiate() as Unit
	worker.definition = LEADER.duplicate()
	fx.main.get_node("Units").add_child(worker)
	worker.set_world_navigation(fx.nav)
	if fast_walk:
		_accelerate([worker])
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
	var res: Dictionary = load.add_with_provenance(
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


func _assert_all_guards_clear(
	fx: Dictionary,
	sources: Array[ResourceSource],
	workers: Array[Unit],
	orders: Array[GatherResourceOrder] = []
) -> void:
	var auth := _authority(fx)
	if auth != null:
		assert_false(auth.is_executing, "RegionalAuthority.is_executing leaked")
	var storage: GroundPileManager = fx.storage
	var inv: SettlementInventory = fx.inventory
	assert_false(storage._is_preparing_withdrawal)
	assert_false(inv._is_delivering)
	assert_false(fx.camp._coordinator_transaction_locked)
	for src: ResourceSource in sources:
		if is_instance_valid(src):
			assert_false(src._is_transferring)
	for w: Unit in workers:
		if is_instance_valid(w):
			var load: UnitCarryLoad = w.get_carry_load()
			assert_false(load._provenance_busy)
			assert_false(load._provenance_applying)
			assert_false(load._coordinator_transaction_locked)
			assert_eq(load._batch_depth, 0)
	for ord: GatherResourceOrder in orders:
		if ord != null:
			assert_false(ord.is_provenance_transfer_executing())
			if ord.is_finished():
				assert_false(ord.has_reservation(), "Finished GatherResourceOrder left slot reservation active")


func _assert_economy_and_sites_consistent(
	fx: Dictionary,
	workers: Array[Unit],
	sites: Array[ConstructionSite],
	expected_site_reserves: Dictionary = {}
) -> void:
	var storage: GroundPileManager = fx.storage
	var inv: SettlementInventory = fx.inventory
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
		var res_on_pile: int = storage.get_pile_reserved_amount(pile.pile_id)
		assert_true(res_on_pile >= 0 and res_on_pile <= pile.amount)

	var ledger_by_pile: Dictionary = storage._ledger.snapshot_state().get("by_pile", {}) as Dictionary
	for pid_var: Variant in ledger_by_pile.keys():
		assert_true(seen_ids.has(int(pid_var)), "Orphan reservation ledger entry for pile %s" % str(pid_var))

	for w: Unit in workers:
		var load: UnitCarryLoad = w.get_carry_load()
		if load.is_provenance_enabled():
			assert_true(load.validate_provenance(), "CarryLoad provenance invalid during invariant check")
			var expected_w: int = 0
			var amts: Dictionary = load.get_all_amounts()
			var wts: Dictionary = load.get_all_unit_weights()
			for rk: Variant in amts.keys():
				expected_w += int(amts[rk]) * int(wts[rk])
			assert_eq(load.get_current_weight(), expected_w)

	for s: ConstructionSite in sites:
		if not is_instance_valid(s) or not s.is_active():
			continue
		if expected_site_reserves.has(s):
			assert_eq(s.get_reserved_in_piles_amounts(), expected_site_reserves[s])
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


# ==============================================================================
# GROUP A — COMPATIBILITY (Scenarios 1–6)
# ==============================================================================
func test_group_a_compatibility_opt_in_default_off_and_strict_isolation() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	var cmd: CommandController = fx.cmd
	var sel: SelectionManager = fx.sel

	# 3. Default constructor keeps opt-in disabled
	var default_order := GatherResourceOrder.new(null, camp, inv)
	assert_false(default_order.is_provenance_mode())

	# 1 & 2. Legacy gather + legacy delivery remain unchanged
	var legacy_tree := await _spawn_source(fx, TREE_SCENE, &"c35_leg_tree", Vector3(3.2, 0.0, 2.0), 4, 2)
	_place_worker(fx, worker, Vector3(1.5, 0.0, 2.0))
	var legacy_order := GatherResourceOrder.new(legacy_tree, camp, inv, 0.05, 0.0)
	assert_false(legacy_order.is_provenance_mode())
	worker.issue_order(legacy_order)
	assert_true(await _until(func() -> bool: return legacy_order.is_finished()))
	assert_true(legacy_order.is_succeeded(), legacy_order.failure_reason)
	assert_eq(inv.get_amount(&"wood"), 4)
	assert_false(load.is_provenance_enabled())
	assert_eq(legacy_tree.get_active_worker_count(), 0)

	assert_true(load.add_units(FOOD, 2))
	var legacy_deliv := DeliverToCampOrder.new(camp, inv)
	assert_false(legacy_deliv.is_selective_mode())
	worker.issue_order(legacy_deliv)
	assert_true(await _until(func() -> bool: return legacy_deliv.is_finished()))
	assert_true(legacy_deliv.is_succeeded())
	assert_eq(inv.get_amount(&"food"), 2)

	# 4. Legacy backpack refused in opt-in mode without touching cargo or acquiring slot
	var bush := await _spawn_source(fx, BUSH_SCENE, &"c35_leg_bush", Vector3(3.2, 0.0, -2.0), 5, 2)
	assert_true(load.add_units(FOOD, 3))
	var optin_rejected := GatherResourceOrder.new(bush, camp, inv, 0.05, 0.0, true, fx.region)
	assert_true(optin_rejected.is_provenance_mode())
	worker.issue_order(optin_rejected)
	assert_true(optin_rejected.is_finished())
	assert_eq(optin_rejected.failure_reason, GatherResourceOrder.REASON_PROVENANCE_REQUIRED)
	assert_false(load.is_provenance_enabled())
	assert_eq(load.get_all_amounts(), {&"food": 3})
	assert_eq(bush.get_remaining_amount(), 5)
	assert_eq(bush.get_active_worker_count(), 0)
	assert_null(_authority(fx))

	# Deliver legacy food so worker can enable opt-in provenance
	var clear_legacy := DeliverToCampOrder.new(camp, inv)
	worker.issue_order(clear_legacy)
	assert_true(await _until(func() -> bool: return clear_legacy.is_finished()))
	assert_true(clear_legacy.is_succeeded())
	assert_eq(inv.get_amount(&"food"), 5)

	# 5 & 6. Provenance-enabled backpack refused by legacy order & CommandController stays legacy
	var prov_worker := _extra_worker(fx, &"prov_worker_a", Vector3(1.5, 0.0, -2.0), true)
	_add_free_lot(prov_worker, WOOD, 3, &"op_a5", &"lot_a5")
	var snap_before: Dictionary = prov_worker.get_carry_load().provenance_snapshot()
	var legacy_rejected := GatherResourceOrder.new(bush, camp, inv, 0.05, 0.0)
	prov_worker.issue_order(legacy_rejected)
	assert_true(legacy_rejected.is_finished())
	assert_eq(legacy_rejected.failure_reason, GatherResourceOrder.REASON_PROVENANCE_OPT_IN_REQUIRED)
	assert_eq(prov_worker.get_carry_load().provenance_snapshot(), snap_before)
	assert_eq(bush.get_active_worker_count(), 0)

	# 6. Right-click CommandController stays strictly legacy by default
	sel.select_single(worker)
	var pick_legacy := PickResult.from_resource_source(bush, bush.global_position, Vector3.UP)
	assert_true(cmd.command_at(pick_legacy))
	assert_true(worker.get_current_order() is GatherResourceOrder)
	assert_false((worker.get_current_order() as GatherResourceOrder).is_provenance_mode())
	worker.cancel_current_order()

	sel.select_single(prov_worker)
	assert_false(cmd.command_at(pick_legacy), "CommandController must stay legacy and reject provenance worker")
	assert_eq(cmd.get_last_command_reason(), GatherResourceOrder.REASON_PROVENANCE_OPT_IN_REQUIRED)
	assert_eq(prov_worker.get_carry_load().provenance_snapshot(), snap_before)
	_assert_all_guards_clear(fx, [legacy_tree, bush], [worker, prov_worker], [optin_rejected, legacy_rejected])


# ==============================================================================
# GROUP B — REAL CYCLE, SLOTS, WEIGHTS, FELLING & DEPLETION (Scenarios 7–20)
# ==============================================================================
func test_group_b_real_cycle_slots_weights_felling_and_depletion() -> void:
	var fx := await _fixture(false)
	var worker: Unit = fx.worker
	var peer: Unit = fx.peer
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(load.enable_provenance(&"worker_b_wood"))
	assert_true(peer.get_carry_load().enable_provenance(&"worker_b_peer"))

	# Remote extraction via GatherTransferSession must fail with out_of_gather_range (7)
	var tree := await _spawn_source(fx, TREE_SCENE, &"c35_tree_b", Vector3(3.5, 0.0, 2.0), 14, 5, 1, 0.08, 0.16)
	_place_worker(fx, worker, FAR_WALK_POS)
	var remote_sess := GatherTransferSession.new()
	assert_true(bool(remote_sess.initialize_cycle(inv, camp, tree, worker, fx.region, 9901, 1, 2).get("ok", false)))
	var remote_res: Dictionary = remote_sess.execute_or_retry(inv, camp, tree, worker, fx.region, 9901, false)
	assert_false(bool(remote_res.get("ok", true)))
	assert_eq(String(remote_res.get("reason", "")), "out_of_gather_range")
	assert_eq(tree.get_remaining_amount(), 14)
	assert_true(load.is_empty())

	# Standing wood tree: prepare timing (9), slot contention (8), felling animation (20),
	# exact source/load deltas (10,11,12), speed reduction by weight (13), no premature credit (15),
	# selective physical camp dropoff (14,16), multi-trip return (17,18), final depletion (19).
	var wood_order := GatherResourceOrder.new(tree, camp, inv, 0.08, 0.16, true, fx.region)
	worker.issue_order(wood_order)
	assert_true(wood_order.is_active(), wood_order.failure_reason)
	assert_eq(wood_order.get_phase(), GatherResourceOrder.Phase.APPROACHING_SOURCE)
	assert_true(wood_order.has_reservation())
	assert_true(tree.is_worker_reserved(worker))
	assert_eq(tree.get_active_worker_count(), 1)

	# 8. Competing 2nd worker fails with REASON_NO_WORKER_SLOT while 1-slot tree is reserved
	var blocked_peer := GatherResourceOrder.new(tree, camp, inv, 0.08, 0.0, true, fx.region)
	peer.issue_order(blocked_peer)
	assert_true(blocked_peer.is_finished())
	assert_eq(blocked_peer.failure_reason, GatherResourceOrder.REASON_NO_WORKER_SLOT)

	# 9. Observe prepare phase before extraction
	assert_true(await _until(func() -> bool: return wood_order.is_preparing_gather() or wood_order.is_finished()))
	assert_eq(worker.get_state(), Unit.State.WORKING)
	assert_eq(tree.get_remaining_amount(), 14, "Must not extract during prepare window")
	assert_true(load.is_empty())

	# 10, 11, 12, 20. Observe first chop triggering FELLING animation while awaiting felling cleanly
	var saw_felling: bool = false
	var entered_transport_during_felling: bool = false
	var saw_fallen_before_transport: bool = false
	var checked_transport_invariants: bool = false
	var unloaded_speed: float = worker.get_definition().move_speed
	var seen_loaded_slowdown: bool = false
	var lot_ids_seen: Dictionary = {}
	var seen_wood_10: bool = false

	var frames: int = 0
	while frames < FRAME_LIMIT and not wood_order.is_finished():
		await wait_physics_frames(1)
		frames += 1
		if tree.is_felling():
			saw_felling = true
			if worker.get_state() == Unit.State.TRANSPORTING:
				entered_transport_during_felling = true
		if tree.is_fallen() and worker.get_state() == Unit.State.TRANSPORTING:
			saw_fallen_before_transport = true

		if load.get_amount(&"wood") > 0:
			var lots_now: Dictionary = load.provenance_snapshot()["ledger"]["lots"] as Dictionary
			for lid: Variant in lots_now.keys():
				var l: Dictionary = lots_now[lid] as Dictionary
				assert_eq(StringName(l["origin"]), CarryProvenanceLedger.FREE_GATHERED)
				assert_eq(StringName(l["site_id"]), &"")
				assert_eq(int(l["generation"]), 0)
				assert_true(String(lid).begins_with("lot:gather:"))
				lot_ids_seen[StringName(lid)] = true

		# 13 & 15. During first transport back (carrying 10 wood = weight 20/20), speed is reduced & camp inv = 0
		if worker.get_state() == Unit.State.TRANSPORTING and wood_order.get_delivered_trips() == 0:
			assert_false(wood_order.has_reservation(), "Slot must be freed while transporting to camp")
			assert_eq(inv.get_physical_amount(&"wood"), 0, "Camp inventory must NOT be credited before arrival")
			if load.get_amount(&"wood") == 10:
				seen_wood_10 = true
				assert_eq(load.get_current_weight(), 20)
				if worker.get_movement().get_effective_move_speed() < unloaded_speed - 0.5:
					seen_loaded_slowdown = true
				checked_transport_invariants = true

		var total_w: int = tree.get_remaining_amount() + load.get_amount(&"wood") + inv.get_physical_amount(&"wood")
		assert_eq(total_w, 14)

	assert_true(saw_felling, "Must play tree felling animation on first extraction")
	assert_false(entered_transport_during_felling, "Worker must wait for felling before entering TRANSPORTING")
	assert_true(saw_fallen_before_transport)
	assert_true(checked_transport_invariants and seen_wood_10)
	assert_true(seen_loaded_slowdown, "Loaded worker speed must decrease proportionally to cargo weight")
	assert_true(wood_order.is_succeeded(), wood_order.failure_reason)
	assert_eq(wood_order.get_delivered_trips(), 2)
	assert_eq(wood_order.get_total_extracted_units(), 14)
	assert_eq(wood_order.get_extraction_cycles_completed(), 3)
	assert_eq(lot_ids_seen.size(), 3, "Each extraction cycle must register a unique FREE_GATHERED lot_id")
	assert_true(tree.is_depleted())
	assert_true(tree.is_fallen(), "Depleted tree must remain fallen/stump without premature DEC-09 removal")
	assert_true(tree.is_inside_tree())
	assert_eq(inv.get_available_amount(&"wood"), 14)
	assert_true(load.is_empty())
	assert_eq(worker.get_state(), Unit.State.IDLE)
	assert_eq(tree.get_active_worker_count(), 0)
	assert_false(wood_order.last_delivery_receipt.is_empty())
	# Verify shared RegionalAuthority did NOT pollute authority.receipts with gather ops
	var auth := _authority(fx)
	for op_k: Variant in auth.receipts.keys():
		assert_false(String(op_k).begins_with("gather:"), "Gather receipt must stay on ResourceSource, not RegionalAuthority")

	# 20b. Standing tree depleting on single last cycle transitions to FALLEN stump and deposits cleanly without double count
	var small_tree := await _spawn_source(fx, TREE_SCENE, &"c35_tree_last_chop", Vector3(3.5, 0.0, -3.5), 4, 4, 2, 0.05, 0.0)
	_place_worker(fx, worker, Vector3(1.5, 0.0, -3.5))
	var single_chop := GatherResourceOrder.new(small_tree, camp, inv, 0.05, 0.0, true, fx.region)
	worker.issue_order(single_chop)
	assert_true(await _until(func() -> bool: return single_chop.is_finished()))
	assert_true(single_chop.is_succeeded(), single_chop.failure_reason)
	assert_true(small_tree.is_depleted())
	assert_true(small_tree.is_fallen())
	assert_true((small_tree.get_node("DepletedVisual") as Node3D).visible)
	assert_eq(inv.get_available_amount(&"wood"), 18)

	# 20c. Stone (weight=3 -> 90% auto-return at 6/20=18 weight) & Food bush (fruits reduce & green foliage preserved)
	_accelerate([worker])
	var rock := await _spawn_source(fx, ROCK_SCENE, &"c35_rock_b", Vector3(-2.5, 0.0, -4.5), 8, 2, 2, 0.04, 0.0)
	_place_worker(fx, worker, Vector3(-4.0, 0.0, -4.5))
	var stone_order := GatherResourceOrder.new(rock, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(stone_order)
	var saw_90_pct: bool = false
	while not stone_order.is_finished():
		await wait_physics_frames(1)
		if worker.get_state() == Unit.State.TRANSPORTING and inv.get_physical_amount(&"stone") == 0 and load.get_amount(&"stone") == 6:
			assert_eq(load.get_current_weight(), 18)
			saw_90_pct = true
	assert_true(stone_order.is_succeeded(), stone_order.failure_reason)
	assert_true(saw_90_pct, "Stone weight=3 must auto-return at 18/20 (90%) when +1 doesn't fit")
	assert_eq(stone_order.get_delivered_trips(), 2)
	assert_eq(inv.get_available_amount(&"stone"), 8)
	assert_true(rock.is_depleted())

	var bush := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_b", Vector3(2.2, 0.0, -5.5), 6, 3, 2, 0.04, 0.0, false)
	var fruits_before: int = bush.get_visible_fruit_count()
	assert_gt(fruits_before, 0)
	var food_order := GatherResourceOrder.new(bush, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(food_order)
	assert_true(await _until(func() -> bool: return food_order.is_finished()))
	assert_true(food_order.is_succeeded(), food_order.failure_reason)
	assert_true(bush.is_depleted())
	assert_eq(bush.get_visible_fruit_count(), 0)
	assert_true((bush.get_node("DepletedVisual") as Node3D).visible)
	assert_eq(inv.get_available_amount(&"food"), 6)
	_assert_all_guards_clear(fx, [tree, small_tree, rock, bush], [worker, peer], [wood_order, single_chop, stone_order, food_order])


# ==============================================================================
# GROUP C — MIXED CARGO & ANTI-LOOP (Scenarios 21–28)
# ==============================================================================
func test_group_c_mixed_cargo_selective_delivery_and_anti_loop() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(load.enable_provenance(&"worker_c_mix"))
	assert_true(inv.deposit(&"stone", 6))
	assert_true(inv.deposit(&"wood", 8))

	var site_a := _create_site(fx, {&"stone": 4}, SITE_A_POS)
	var site_b := _create_site(fx, {&"wood": 5}, SITE_B_POS)
	# Withdraw Site A (2 stone = w6) and Site B (3 wood = w6) + free food (2 = w2) + free stone (1 = w3) => 17/20
	_withdraw_site_lot_physically(fx, site_a, worker, &"stone", 2, &"op_cm_sa", &"lot_cm_sa")
	_withdraw_site_lot_physically(fx, site_b, worker, &"wood", 3, &"op_cm_sb", &"lot_cm_sb")
	_add_free_lot(worker, FOOD, 2, &"op_cm_ff", &"lot_cm_ff")
	_add_free_lot(worker, STONE, 1, &"op_cm_fs", &"lot_cm_fs")
	assert_eq(load.get_current_weight(), 17)

	var claim_a_before: Dictionary = site_a._read_transit_claim_for_unit_pure(worker.get_instance_id())
	var claim_b_before: Dictionary = site_b._read_transit_claim_for_unit_pure(worker.get_instance_id())
	var free_wood_before: int = inv.get_available_amount(&"wood")
	var free_stone_before: int = inv.get_available_amount(&"stone")
	var free_food_before: int = inv.get_available_amount(&"food")

	var tree := await _spawn_source(fx, TREE_SCENE, &"c35_tree_mix", Vector3(3.5, 0.0, 2.0), 6, 1, 2, 0.04, 0.0)
	_place_worker(fx, worker, FAR_WALK_POS)

	# 21–25: Gathers 1 wood (w=19/20 -> cannot fit +1), selectively unloads ONLY FREE lots (1 wood, 2 food, 1 stone),
	# keeps Site A & Site B reserved lots/claims untouched, resumes tree with 8 residual weight space, finishes all 6 wood!
	var mix_order := GatherResourceOrder.new(tree, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(mix_order)
	assert_true(await _until(func() -> bool: return mix_order.is_finished()))
	assert_true(mix_order.is_succeeded(), mix_order.failure_reason)
	assert_eq(mix_order.get_delivered_trips(), 3)
	assert_eq(inv.get_available_amount(&"wood"), free_wood_before + 6)
	assert_eq(inv.get_available_amount(&"stone"), free_stone_before + 1)
	assert_eq(inv.get_available_amount(&"food"), free_food_before + 2)

	# Site A & Site B reservations, claims, and buffers remain 100% intact
	assert_eq(site_a._read_transit_claim_for_unit_pure(worker.get_instance_id()), claim_a_before)
	assert_eq(site_b._read_transit_claim_for_unit_pure(worker.get_instance_id()), claim_b_before)
	assert_eq(site_a.get_delivered_buffer_amount(&"stone"), 0)
	assert_eq(site_b.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(load.get_all_amounts(), {&"stone": 2, &"wood": 3})
	assert_eq(load.get_current_weight(), 12)
	var lots_after: Dictionary = load.provenance_snapshot()["ledger"]["lots"] as Dictionary
	assert_true(lots_after.has(&"lot_cm_sa") and lots_after.has(&"lot_cm_sb"))
	assert_eq(lots_after.size(), 2)
	_assert_economy_and_sites_consistent(fx, [worker], [site_a, site_b])

	# 26–28: No loop when residual SITE_RESERVED fills backpack beyond room for +1 wood (19/20)
	var worker2 := _extra_worker(fx, &"worker_c_full", FAR_WALK_POS, true)
	assert_true(inv.deposit(&"stone", 3))
	assert_true(inv.deposit(&"wood", 5))
	var site_a2 := _create_site(fx, {&"stone": 3}, Vector3(-12.0, 0.0, -8.0))
	var site_b2 := _create_site(fx, {&"wood": 5}, Vector3(-12.0, 0.0, 4.0))
	_withdraw_site_lot_physically(fx, site_a2, worker2, &"stone", 3, &"op_c2_sa", &"lot_c2_sa") # 9
	_withdraw_site_lot_physically(fx, site_b2, worker2, &"wood", 5, &"op_c2_sb", &"lot_c2_sb") # 10 => 19/20

	var tree2 := await _spawn_source(fx, TREE_SCENE, &"c35_tree_loop", Vector3(3.5, 0.0, -3.5), 4, 1, 2, 0.04, 0.0)
	var snap_w2_only_res: Dictionary = worker2.get_carry_load().provenance_snapshot()
	var lots_w2_only_res: Dictionary = (snap_w2_only_res["ledger"] as Dictionary)["lots"] as Dictionary
	var immediate_stop := GatherResourceOrder.new(tree2, camp, inv, 0.04, 0.0, true, fx.region)
	worker2.issue_order(immediate_stop)
	assert_true(immediate_stop.is_finished())
	assert_eq(immediate_stop.failure_reason, GatherResourceOrder.REASON_INSUFFICIENT_CARRY_CAPACITY)
	assert_eq(immediate_stop.get_delivered_trips(), 0, "Must never walk to camp when only ineligible reserved lots exist")
	assert_eq(worker2.get_carry_load().provenance_snapshot(), snap_w2_only_res)
	assert_eq(tree2.get_active_worker_count(), 0)

	# 26–28b: Add 1 FREE food (20/20). Walks to camp ONCE, selectively delivers ONLY 1 free food (leaving 19/20),
	# detects remaining cap=1 < wood weight=2, fails conservatively WITHOUT looping back to camp!
	_add_free_lot(worker2, FOOD, 1, &"op_c2_ff", &"lot_c2_ff")
	assert_eq(worker2.get_carry_load().get_current_weight(), 20)
	var food_before_trip: int = inv.get_available_amount(&"food")
	_place_worker(fx, worker2, FAR_WALK_POS)
	var anti_loop := GatherResourceOrder.new(tree2, camp, inv, 0.04, 0.0, true, fx.region)
	worker2.issue_order(anti_loop)
	assert_true(await _until(func() -> bool: return anti_loop.is_finished()))
	assert_eq(anti_loop.status, UnitOrder.Status.FAILED)
	assert_eq(anti_loop.failure_reason, GatherResourceOrder.REASON_INSUFFICIENT_CARRY_CAPACITY)
	assert_eq(anti_loop.get_delivered_trips(), 1, "Must unload eligible free lot exactly once and stop without looping")
	assert_eq(inv.get_available_amount(&"food"), food_before_trip + 1)
	assert_eq(worker2.get_carry_load().get_all_amounts(), {&"stone": 3, &"wood": 5})
	assert_eq(worker2.get_carry_load().get_current_weight(), 19)
	assert_eq((worker2.get_carry_load().provenance_snapshot()["ledger"] as Dictionary)["lots"], lots_w2_only_res)
	assert_eq(tree2.get_remaining_amount(), 4)
	assert_eq(tree2.get_active_worker_count(), 0)
	_assert_economy_and_sites_consistent(fx, [worker, worker2], [site_a, site_b, site_a2, site_b2])
	_assert_all_guards_clear(fx, [tree, tree2], [worker, worker2], [mix_order, immediate_stop, anti_loop])


# ==============================================================================
# GROUP D — IDEMPOTENCY, RETRIES, REPLAY & IDENTITY (Scenarios 29–38)
# ==============================================================================
func test_group_d_idempotency_busy_retries_uncertain_outcome_depleted_replay_and_conflicts() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(load.enable_provenance(&"worker_d_idemp"))

	# 29, 30, 31, 32, 36. First commit, replay on depleted source, repeated op, conflicting op
	var bush := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_d", Vector3(2.5, 0.0, 2.0), 3, 3, 2, 0.04, 0.0, false)
	_place_worker(fx, worker, Vector3(1.8, 0.0, 2.0))
	var first_order := GatherResourceOrder.new(bush, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(first_order)
	assert_true(await _until(func() -> bool: return first_order.get_extraction_cycles_completed() >= 1 or first_order.is_finished()))
	assert_true(bush.is_depleted())
	var rec: Dictionary = first_order.last_extraction_receipt
	assert_false(rec.is_empty())
	var first_op: StringName = StringName(rec["operation_id"])
	var first_lot: StringName = StringName(rec["lot_id"])
	assert_eq(int(rec["committed_amount"]), 3)
	assert_true(await _until(func() -> bool: return first_order.is_finished()))
	assert_true(first_order.is_succeeded(), first_order.failure_reason)
	assert_eq(inv.get_available_amount(&"food"), 3)

	# 30, 31, 36: Replay same frozen operation on depleted source -> ok=true, replayed=true, extracted=0
	var snap_after_deliv: Dictionary = load.provenance_snapshot()
	var replay_res: Dictionary = bush.transfer_to_carry_load_with_provenance(load, first_op, first_lot, 3)
	assert_true(bool(replay_res.get("ok", false)))
	assert_true(bool(replay_res.get("replayed", false)))
	assert_eq(int(replay_res.get("extracted", -1)), 0)
	assert_eq(int(replay_res.get("committed_amount", 0)), 3)
	assert_eq(load.provenance_snapshot(), snap_after_deliv)
	assert_eq(bush.get_remaining_amount(), 0)

	# 32: Conflicting lot_id, requested_amount, another source, and another unit's CarryLoad rejected
	assert_false(bool(bush.transfer_to_carry_load_with_provenance(load, first_op, &"wrong_lot", 3).get("ok", true)))
	assert_false(bool(bush.transfer_to_carry_load_with_provenance(load, first_op, first_lot, 4).get("ok", true)))
	var other_bush := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_other", Vector3(4.0, 0.0, 2.0), 4, 2, 2, 0.04, 0.0, false)
	assert_false(bool(other_bush.transfer_to_carry_load_with_provenance(load, first_op, &"fresh_lot", 2).get("ok", true)))
	var peer_load: UnitCarryLoad = (fx.peer as Unit).get_carry_load()
	assert_true(peer_load.enable_provenance(&"worker_d_peer"))
	assert_false(bool(bush.transfer_to_carry_load_with_provenance(peer_load, first_op, first_lot, 3).get("ok", true)))

	# 33 & 31b: Busy preserves exact operation_id & lot_id; external commit during busy retry -> replayed cleanly without double count
	var bush_busy := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_busy", Vector3(2.5, 0.0, -2.5), 4, 2, 2, 0.04, 0.0, false)
	_place_worker(fx, worker, Vector3(1.8, 0.0, -2.5))
	var busy_order := GatherResourceOrder.new(bush_busy, camp, inv, 0.04, 0.0, true, fx.region)
	load.begin_batch()
	worker.issue_order(busy_order)
	assert_true(await _until(func() -> bool:
		return (busy_order.get_active_gather_session() != null and busy_order.get_active_gather_session().is_retry_scheduled()) or busy_order.is_finished()
	))
	assert_true(busy_order.is_active(), busy_order.failure_reason)
	var busy_sess: GatherTransferSession = busy_order.get_active_gather_session()
	var frozen_op: StringName = busy_sess.get_operation_id()
	var frozen_lot: StringName = busy_sess.get_lot_id()
	assert_ne(frozen_op, &"")
	assert_eq(busy_sess.get_busy_retries(), 1)
	await wait_physics_frames(3)
	assert_eq(busy_sess.get_busy_retries(), 1, "Must not spin retries every frame")
	assert_eq(busy_sess.get_operation_id(), frozen_op)
	assert_eq(busy_sess.get_lot_id(), frozen_lot)
	load.end_batch()
	# External commit using exact same frozen IDs during busy wait -> retry sees replay with extracted=0!
	var ext_first: Dictionary = bush_busy.transfer_to_carry_load_with_provenance(load, frozen_op, frozen_lot, 2)
	assert_true(bool(ext_first.get("ok", false)) and not bool(ext_first.get("replayed", true)))
	assert_eq(bush_busy.get_remaining_amount(), 2)
	assert_true(await _until(func() -> bool: return busy_order.is_finished()))
	assert_true(busy_order.is_succeeded(), busy_order.failure_reason)
	# Cycle 1 was replayed (extracted=0, so cycles=1 from cycle 2 only), physical stock conserved cleanly:
	assert_eq(busy_order.get_extraction_cycles_completed(), 1)
	assert_eq(busy_order.get_total_extracted_units(), 2)
	assert_eq(inv.get_available_amount(&"food"), 7, "Initial 3 + 4 from bush_busy = 7 (zero double count)")
	assert_true(bush_busy.is_depleted())

	# 34: Retry limit exhausted (MAX_BUSY_RETRIES = 4 -> busy_retry_exhausted)
	var bush_exhaust := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_exhaust", Vector3(2.5, 0.0, -4.5), 4, 2, 2, 0.04, 0.0, false)
	_place_worker(fx, worker, Vector3(1.8, 0.0, -4.5))
	var exhaust_order := GatherResourceOrder.new(bush_exhaust, camp, inv, 0.04, 0.0, true, fx.region)
	load.begin_batch()
	worker.issue_order(exhaust_order)
	assert_true(await _until(func() -> bool: return exhaust_order.is_finished(), 600))
	load.end_batch()
	assert_eq(exhaust_order.status, UnitOrder.Status.FAILED)
	assert_eq(exhaust_order.failure_reason, "busy_retry_exhausted")
	assert_eq(bush_exhaust.get_remaining_amount(), 4)
	assert_eq(bush_exhaust.get_active_worker_count(), 0)
	assert_true(load.is_empty())

	# 35a & 36: Uncertain outcome WITH real commit (depletes source on that commit!) -> queries receipt & replays without new ID
	var bush_unc_ok := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_unc_ok", Vector3(2.5, 0.0, -6.5), 2, 2, 2, 0.04, 0.0, false)
	_place_worker(fx, worker, Vector3(1.8, 0.0, -6.5))
	var unc_order_ok := TestGatherResourceOrder.new(bush_unc_ok, camp, inv, 0.04, 0.0, true, fx.region)
	var unc_sess_ok := UncertainOnceGatherSession.new()
	unc_sess_ok.commit_before_uncertain = true
	unc_order_ok.custom_session_factory = func() -> GatherTransferSession: return unc_sess_ok
	var serial_before: int = _authority(fx).construction_transfer_serial
	worker.issue_order(unc_order_ok)
	assert_true(await _until(func() -> bool: return unc_order_ok.get_phase() == GatherResourceOrder.Phase.DELIVERING_TO_CAMP or unc_order_ok.is_finished()))
	assert_eq(_authority(fx).construction_transfer_serial, serial_before + 1, "Uncertain gather reconciliation must consume ONLY 1 gather serial")
	assert_true(await _until(func() -> bool: return unc_order_ok.is_finished()))
	assert_true(unc_order_ok.is_succeeded(), unc_order_ok.failure_reason)
	assert_eq(_authority(fx).construction_transfer_serial, serial_before + 2, "Gather (1) + selective camp delivery (1) = 2 total serials")
	assert_eq(unc_sess_ok.invoke_count, 2)
	assert_eq(unc_order_ok.get_total_extracted_units(), 0, "Replay path must not double-count uncertain replayed commit")
	assert_eq(inv.get_available_amount(&"food"), 9)
	assert_true(bush_unc_ok.is_depleted())

	# 35b: Uncertain outcome WITHOUT real commit -> fails with unknown_transaction_outcome, never starts cycle 2
	var bush_unc_fail := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_unc_fail", Vector3(2.5, 0.0, -8.5), 4, 2, 2, 0.04, 0.0, false)
	_place_worker(fx, worker, Vector3(1.8, 0.0, -8.5))
	var unc_order_fail := TestGatherResourceOrder.new(bush_unc_fail, camp, inv, 0.04, 0.0, true, fx.region)
	var unc_sess_fail := UncertainOnceGatherSession.new()
	unc_sess_fail.commit_before_uncertain = false
	unc_order_fail.custom_session_factory = func() -> GatherTransferSession: return unc_sess_fail
	var serial_before_2: int = _authority(fx).construction_transfer_serial
	worker.issue_order(unc_order_fail)
	assert_true(await _until(func() -> bool: return unc_order_fail.is_finished(), 120))
	assert_eq(unc_order_fail.status, UnitOrder.Status.FAILED)
	assert_eq(unc_order_fail.failure_reason, "unknown_transaction_outcome")
	assert_eq(_authority(fx).construction_transfer_serial, serial_before_2 + 1)
	assert_eq(bush_unc_fail.get_remaining_amount(), 4)
	assert_eq(bush_unc_fail.get_active_worker_count(), 0)
	assert_true(load.is_empty())

	# 37: Identity change between retry attempts fails with transaction_identity_changed
	var id_order := GatherResourceOrder.new(bush_unc_fail, camp, inv, 0.04, 0.0, true, fx.region)
	load.begin_batch()
	worker.issue_order(id_order)
	assert_true(await _until(func() -> bool:
		return id_order.get_active_gather_session() != null and id_order.get_active_gather_session().is_retry_scheduled()
	))
	bush_unc_fail.source_id = &"c35_mutated_source_id"
	load.end_batch()
	assert_true(await _until(func() -> bool: return id_order.is_finished(), 120))
	assert_eq(id_order.status, UnitOrder.Status.FAILED)
	assert_eq(id_order.failure_reason, "transaction_identity_changed")
	assert_eq(bush_unc_fail.get_remaining_amount(), 4)
	assert_eq(bush_unc_fail.get_active_worker_count(), 0)
	bush_unc_fail.source_id = &"c35_bush_unc_fail"

	# 37b: Moving unit out of gather range during a busy retry fails cleanly without remote extract or loop
	_place_worker(fx, worker, Vector3(1.8, 0.0, -8.5))
	var range_order := GatherResourceOrder.new(bush_unc_fail, camp, inv, 0.04, 0.0, true, fx.region)
	load.begin_batch()
	worker.issue_order(range_order)
	assert_true(await _until(func() -> bool:
		return range_order.get_active_gather_session() != null and range_order.get_active_gather_session().is_retry_scheduled()
	))
	_place_worker(fx, worker, FAR_WALK_POS)
	load.end_batch()
	assert_true(await _until(func() -> bool: return range_order.is_finished(), 120))
	assert_eq(range_order.status, UnitOrder.Status.FAILED)
	assert_eq(range_order.failure_reason, "out_of_gather_range")
	assert_eq(bush_unc_fail.get_remaining_amount(), 4)
	assert_eq(bush_unc_fail.get_active_worker_count(), 0)
	assert_true(load.is_empty())

	# 38: Replacing order right after extraction preserves lot once and next order creates fresh non-duplicating lot
	var bush_swap := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_swap", Vector3(4.5, 0.0, 2.0), 4, 2, 2, 0.04, 0.0, false)
	_place_worker(fx, worker, Vector3(3.8, 0.0, 2.0))
	var ord1 := GatherResourceOrder.new(bush_swap, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(ord1)
	assert_true(await _until(func() -> bool: return load.get_amount(&"food") == 2))
	var lot_1_key: StringName = (load.provenance_snapshot()["ledger"]["lots"] as Dictionary).keys()[0]
	var ord2 := GatherResourceOrder.new(bush_swap, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(ord2)
	assert_eq(ord1.status, UnitOrder.Status.CANCELLED)
	assert_eq(ord1.failure_reason, UnitOrder.REASON_REPLACED)
	assert_true(await _until(func() -> bool: return ord2.is_finished()))
	assert_true(ord2.is_succeeded(), ord2.failure_reason)
	assert_eq(inv.get_available_amount(&"food"), 13, "9 prior + 4 from bush_swap = 13 without duplicating cycle 1")
	assert_eq(bush_swap.get_remaining_amount(), 0)
	assert_false(lot_1_key.is_empty())
	_assert_all_guards_clear(fx, [bush, bush_busy, bush_exhaust, bush_unc_ok, bush_unc_fail, bush_swap], [worker, fx.peer], [first_order, busy_order, exhaust_order, unc_order_ok, unc_order_fail, id_order, range_order, ord1, ord2])


# ==============================================================================
# GROUP E — CANCELLATIONS, FAILURES & REENTRANCY (Scenarios 39–50)
# ==============================================================================
func test_group_e_cancellations_removals_navigation_callbacks_and_guards() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var load: UnitCarryLoad = worker.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var camp: CampStorageZone = fx.camp
	assert_true(load.enable_provenance(&"worker_e"))

	# 39 & 50. Cancel during APPROACHING, PREPARING, and RETRY_SCHEDULED (pre-extract): 0 cargo, 0 delayed commit, 0 slots
	var tree_e := await _spawn_source(fx, TREE_SCENE, &"c35_tree_e", Vector3(3.5, 0.0, 2.0), 10, 4, 2, 0.08, 0.25)
	_place_worker(fx, worker, FAR_WALK_POS)
	var cancel_app := GatherResourceOrder.new(tree_e, camp, inv, 0.08, 0.25, true, fx.region)
	worker.issue_order(cancel_app)
	await wait_physics_frames(4)
	assert_eq(cancel_app.get_phase(), GatherResourceOrder.Phase.APPROACHING_SOURCE)
	assert_eq(tree_e.get_active_worker_count(), 1)
	worker.cancel_current_order()
	assert_eq(cancel_app.status, UnitOrder.Status.CANCELLED)
	assert_eq(tree_e.get_active_worker_count(), 0)
	assert_true(load.is_empty())

	_place_worker(fx, worker, Vector3(1.5, 0.0, 2.0))
	var cancel_prep := GatherResourceOrder.new(tree_e, camp, inv, 0.08, 0.30, true, fx.region)
	worker.issue_order(cancel_prep)
	assert_true(await _until(func() -> bool: return cancel_prep.is_preparing_gather()))
	worker.cancel_current_order()
	assert_eq(cancel_prep.status, UnitOrder.Status.CANCELLED)
	assert_eq(tree_e.get_remaining_amount(), 10)
	assert_eq(tree_e.get_active_worker_count(), 0)
	assert_true(load.is_empty())

	# 39b & 50: Cancel while gather session is RETRY_SCHEDULED -> permanently blocks delayed execution
	var cancel_retry := GatherResourceOrder.new(tree_e, camp, inv, 0.04, 0.0, true, fx.region)
	load.begin_batch()
	worker.issue_order(cancel_retry)
	assert_true(await _until(func() -> bool:
		return cancel_retry.get_active_gather_session() != null and cancel_retry.get_active_gather_session().is_retry_scheduled()
	))
	var locked_sess: GatherTransferSession = cancel_retry.get_active_gather_session()
	worker.cancel_current_order()
	load.end_batch()
	assert_eq(cancel_retry.status, UnitOrder.Status.CANCELLED)
	assert_eq(tree_e.get_active_worker_count(), 0)
	cancel_retry.physics_update(worker.get_movement(), 1.0)
	var after_cancel_res: Dictionary = locked_sess.execute_or_retry(inv, camp, tree_e, worker, fx.region, cancel_retry.get_instance_id(), true)
	assert_false(bool(after_cancel_res.get("ok", true)))
	assert_eq(String(after_cancel_res.get("reason", "")), "order_cancelled")
	assert_eq(tree_e.get_remaining_amount(), 10)
	assert_true(load.is_empty())

	# 40a. Cancel DURING tree felling animation -> preserves extracted 10 wood, releases slot, tree finishes falling
	tree_e.configure(&"c35_tree_e", tree_e.get_definition(), 20, 10, 2)
	tree_e.felling_duration_sec = 0.25
	var felling_chop := GatherResourceOrder.new(tree_e, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(felling_chop)
	assert_true(await _until(func() -> bool: return load.get_amount(&"wood") == 10 and tree_e.is_felling()))
	worker.cancel_current_order()
	assert_eq(felling_chop.status, UnitOrder.Status.CANCELLED)
	assert_eq(load.get_amount(&"wood"), 10)
	assert_true(load.validate_provenance())
	assert_eq(inv.get_physical_amount(&"wood"), 0)
	assert_eq(tree_e.get_active_worker_count(), 0)
	assert_true(await _until(func() -> bool: return tree_e.is_fallen(), 120))

	# 40b. Cancel DURING transport (DELIVERING_TO_CAMP) -> lot preserved, 0 camp credit, 0 slots
	_place_worker(fx, worker, FAR_WALK_POS)
	var mid_transport := GatherResourceOrder.new(tree_e, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(mid_transport)
	assert_eq(mid_transport.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP)
	assert_eq(tree_e.get_active_worker_count(), 0)
	await wait_physics_frames(6)
	assert_true(mid_transport.is_active())
	worker.cancel_current_order()
	assert_eq(mid_transport.status, UnitOrder.Status.CANCELLED)
	assert_eq(load.get_amount(&"wood"), 10)
	assert_true(load.validate_provenance())
	assert_eq(inv.get_physical_amount(&"wood"), 0)

	# 41. Cancel right before camp dropoff while delivery is RETRY_SCHEDULED -> preserves lot & locks delivery session
	_place_worker(fx, worker, Vector3(0.0, 0.0, 0.5))
	var pre_dropoff := GatherResourceOrder.new(tree_e, camp, inv, 0.04, 0.0, true, fx.region)
	load.begin_batch()
	worker.issue_order(pre_dropoff)
	assert_true(await _until(func() -> bool:
		return pre_dropoff._deliver_order != null and pre_dropoff._deliver_order.get_selective_session().is_retry_scheduled()
	))
	var deliv_sess_locked: CampDeliveryTransferSession = pre_dropoff._deliver_order.get_selective_session()
	worker.cancel_current_order()
	load.end_batch()
	assert_eq(pre_dropoff.status, UnitOrder.Status.CANCELLED)
	assert_eq(load.get_amount(&"wood"), 10)
	assert_eq(inv.get_physical_amount(&"wood"), 0)
	assert_eq(tree_e.get_active_worker_count(), 0)
	var delayed_deliv_try: Dictionary = deliv_sess_locked.execute_or_retry(
		inv, camp, worker, fx.region, pre_dropoff.get_instance_id()
	)
	assert_false(bool(delayed_deliv_try.get("ok", true)))
	assert_eq(String(delayed_deliv_try.get("reason", "")), "order_cancelled")

	# Deliver existing 10 wood so worker is clean for next checks
	var clean_deliv := DeliverToCampOrder.new(camp, inv, true, fx.region, [])
	worker.issue_order(clean_deliv)
	assert_true(await _until(func() -> bool: return clean_deliv.is_finished()))
	assert_true(clean_deliv.is_succeeded(), clean_deliv.failure_reason)
	assert_eq(inv.get_physical_amount(&"wood"), 10)

	# 42a. Source removed from scene tree mid-approach -> terminates cleanly, 0 leak, 0 crash
	var rem_tree := await _spawn_source(fx, TREE_SCENE, &"c35_tree_rem", Vector3(3.5, 0.0, -5.0), 6, 2, 2, 0.05, 0.0, false)
	_place_worker(fx, worker, FAR_WALK_POS)
	var rem_order := GatherResourceOrder.new(rem_tree, camp, inv, 0.05, 0.0, true, fx.region)
	worker.issue_order(rem_order)
	await wait_physics_frames(4)
	fx.test_map.remove_child(rem_tree)
	_nodes_to_free.append(rem_tree)
	assert_true(await _until(func() -> bool: return rem_order.is_finished(), 60))
	assert_eq(rem_order.status, UnitOrder.Status.FAILED)
	assert_eq(rem_order.failure_reason, GatherResourceOrder.REASON_INVALID_SOURCE)
	assert_false(rem_order.has_reservation())

	# 42b. Source removed during uncertain outcome -> NEVER invents extraction success
	var rem_unc_tree := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_rem_unc", Vector3(2.2, 0.0, -5.0), 4, 2, 2, 0.04, 0.0, false)
	_place_worker(fx, worker, Vector3(1.5, 0.0, -5.0))
	var rem_unc_order := TestGatherResourceOrder.new(rem_unc_tree, camp, inv, 0.04, 0.0, true, fx.region)
	var rem_unc_sess := UncertainOnceGatherSession.new()
	rem_unc_sess.commit_before_uncertain = false
	rem_unc_sess.remove_source_during_uncertain = true
	rem_unc_order.custom_session_factory = func() -> GatherTransferSession: return rem_unc_sess
	worker.issue_order(rem_unc_order)
	_nodes_to_free.append(rem_unc_tree)
	assert_true(await _until(func() -> bool: return rem_unc_order.is_finished(), 60))
	assert_eq(rem_unc_order.status, UnitOrder.Status.FAILED)
	assert_eq(rem_unc_order.failure_reason, "unknown_transaction_outcome")
	assert_true(load.is_empty())

	# 43. Controlled worker removal via TemporaryTestWorkersController
	var temp_ctrl := TemporaryTestWorkersController.new()
	temp_ctrl.configure(fx.main.get_node("Units") as Node3D, fx.nav, camp, fx.sel, fx.main.get_construction_sites_root())
	var spawn_res: Dictionary = temp_ctrl.spawn_temporary_workers()
	assert_true(bool(spawn_res.get("ok", false)), str(spawn_res))
	var w3: Unit = (spawn_res["workers"] as Array)[0] as Unit
	var w4: Unit = (spawn_res["workers"] as Array)[1] as Unit
	_accelerate([w3, w4])
	assert_true(w3.get_carry_load().enable_provenance(&"temp_w3"))
	assert_true(w4.get_carry_load().enable_provenance(&"temp_w4"))

	var slot_bush := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_temp", Vector3(-1.5, 0.0, -3.5), 6, 2, 2, 0.25, 0.25, false)
	_place_worker(fx, w3, Vector3(-3.0, 0.0, -3.5))
	w3.issue_order(GatherResourceOrder.new(slot_bush, camp, inv, 0.25, 0.25, true, fx.region))
	assert_true(slot_bush.is_worker_reserved(w3))
	# w4 gathers 2 food into backpack -> removal MUST be refused with cargo_in_backpack
	_place_worker(fx, w4, Vector3(-1.0, 0.0, -3.5))
	var w4_order := GatherResourceOrder.new(slot_bush, camp, inv, 0.04, 0.0, true, fx.region)
	w4.issue_order(w4_order)
	assert_true(await _until(func() -> bool: return w4.get_carry_load().get_amount(&"food") == 2))
	var check_blocked: Dictionary = temp_ctrl.can_remove_temporary_workers()
	assert_false(bool(check_blocked.get("can_remove", true)))
	assert_eq(String(check_blocked.get("reason", "")), "cargo_in_backpack")
	assert_true(await _until(func() -> bool: return w4_order.is_finished()))
	assert_true(w4_order.is_succeeded(), w4_order.failure_reason)
	assert_true(w4.get_carry_load().is_empty())
	# Keep w3 holding slot on slot_bush while both temp backpacks are empty -> controlled removal releases w3 slot cleanly!
	var check_ok: Dictionary = temp_ctrl.remove_temporary_workers_safely()
	assert_true(bool(check_ok.get("ok", false)), str(check_ok))
	await wait_physics_frames(2)
	assert_eq(slot_bush.get_active_worker_count(), 0, "Controlled worker removal must release source slot")

	# 44. Navigation unavailable -> fails cleanly without premature stock credit or slot leak;
	#     transient navigation sync -> pauses reactively without fail/credit, resumes cleanly on navigation_ready
	var nav_bush := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_nav", Vector3(-1.5, 0.0, -3.5), 10, 2, 2, 0.08, 0.0, false)
	_place_worker(fx, worker, FAR_WALK_POS)
	var nav_order := GatherResourceOrder.new(nav_bush, camp, inv, 0.08, 0.0, true, fx.region)
	worker.issue_order(nav_order)
	await wait_physics_frames(4)
	assert_true(nav_order.is_active())
	(fx.nav as WorldNavigation)._is_ready = false
	assert_true(await _until(func() -> bool: return nav_order.is_finished(), 30))
	assert_eq(nav_order.failure_reason, UnitOrder.REASON_NAVIGATION_NOT_READY)
	assert_eq(nav_bush.get_active_worker_count(), 0)
	(fx.nav as WorldNavigation)._is_ready = true

	var inv_food_before_sync: int = inv.get_available_amount(&"food")
	_place_worker(fx, worker, FAR_WALK_POS)
	var sync_order := GatherResourceOrder.new(nav_bush, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(sync_order)
	await wait_physics_frames(4)
	assert_true(sync_order.is_active())
	(fx.nav as WorldNavigation)._is_ready = false
	(fx.nav as WorldNavigation)._is_syncing = true
	await wait_physics_frames(8)
	assert_true(sync_order.is_active(), "Transient nav sync must wait reactively instead of failing prematurely")
	assert_eq(inv.get_available_amount(&"food"), inv_food_before_sync)
	(fx.nav as WorldNavigation)._is_syncing = false
	(fx.nav as WorldNavigation)._is_ready = true
	(fx.nav as WorldNavigation).navigation_ready.emit()
	assert_true(await _until(func() -> bool: return sync_order.is_finished()))
	assert_true(sync_order.is_succeeded(), sync_order.failure_reason)
	assert_eq(inv.get_available_amount(&"food"), inv_food_before_sync + 10)

	# 45, 46, 47. Reentrancy callbacks inside amount_changed, depleted, and load_changed
	var re_bush := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_reentry", Vector3(-1.5, 0.0, -5.5), 4, 2, 2, 0.04, 0.0, false)
	var re_order := GatherResourceOrder.new(re_bush, camp, inv, 0.04, 0.0, true, fx.region)
	var re_checks: Dictionary = {
		"load_cap_mutated": true,
		"load_mod_mutated": true,
		"load_add_ok": true,
		"load_take_nonempty": true,
		"amt_transfer_prov_ok": true,
		"amt_transfer_leg": 1,
		"depleted_cancelled_unit": false,
		"depleted_saw_locked": false,
		"load_calls": 0,
		"amt_calls": 0,
		"dep_calls": 0,
	}
	_watch(load.load_changed, func() -> void:
		if re_order.is_active() and re_order.get_phase() == GatherResourceOrder.Phase.GATHERING:
			re_checks["load_calls"] = int(re_checks["load_calls"]) + 1
			re_checks["load_cap_mutated"] = load.set_base_capacity(9)
			re_checks["load_mod_mutated"] = load.set_capacity_modifier(&"bad_cb", -5)
			load.begin_batch()
			re_checks["load_add_ok"] = bool(load.add_with_provenance(&"bad_cb_op", &"bad_cb_lot", &"food", 1, 1, CarryProvenanceLedger.FREE_GATHERED).get("ok", false))
			re_checks["load_take_nonempty"] = not load.take_all().is_empty()
	)
	_watch(re_bush.amount_changed, func(_s: ResourceSource, _left: int, _delta: int) -> void:
		re_checks["amt_calls"] = int(re_checks["amt_calls"]) + 1
		re_checks["amt_transfer_prov_ok"] = bool(re_bush.transfer_to_carry_load_with_provenance(load, &"re_amt_op", &"re_amt_lot", 1).get("ok", false))
		re_checks["amt_transfer_leg"] = re_bush.transfer_to_carry_load(load, 1)
		re_order.physics_update(worker.get_movement(), 0.05)
	)
	_watch(re_bush.depleted, func(_s: ResourceSource) -> void:
		re_checks["dep_calls"] = int(re_checks["dep_calls"]) + 1
		re_checks["depleted_saw_locked"] = re_order.is_provenance_transfer_executing()
		worker.cancel_current_order()
		re_order.cancel(worker.get_movement(), "cb_cancel")
		re_checks["depleted_cancelled_unit"] = worker.get_current_order() != re_order
	)

	_place_worker(fx, worker, Vector3(-2.0, 0.0, -5.5))
	var food_before_re: int = inv.get_available_amount(&"food")
	worker.issue_order(re_order)
	assert_true(await _until(func() -> bool: return re_order.is_finished()))
	assert_true(re_order.is_succeeded(), re_order.failure_reason)
	assert_eq(int(re_checks["amt_calls"]), 2)
	assert_eq(int(re_checks["dep_calls"]), 1)
	assert_true(int(re_checks["load_calls"]) >= 2)
	assert_false(bool(re_checks["load_cap_mutated"]), "47. Callback must NOT mutate base_capacity mid-signal")
	assert_false(bool(re_checks["load_mod_mutated"]), "47. Callback must NOT mutate capacity modifiers mid-signal")
	assert_false(bool(re_checks["load_add_ok"]), "47. Callback must NOT add lot during load_changed")
	assert_false(bool(re_checks["load_take_nonempty"]), "47. Callback must NOT wipe cargo during load_changed")
	assert_eq(load.get_base_capacity(), 20)
	assert_false(bool(re_checks["amt_transfer_prov_ok"]), "45. Reentrant provenance transfer in amount_changed must be refused")
	assert_eq(int(re_checks["amt_transfer_leg"]), 0, "45. Reentrant legacy transfer in amount_changed must be refused")
	assert_true(bool(re_checks["depleted_saw_locked"]), "46. Order lock must be held during depleted")
	assert_false(bool(re_checks["depleted_cancelled_unit"]), "46. depleted callback must NOT cancel active order mid-transaction")
	assert_eq(inv.get_available_amount(&"food"), food_before_re + 4)

	# Re-verify _assert_all_guards_clear includes nav_bush
	# 48. Camp delivery failure preserves all extracted FREE_GATHERED and SITE_RESERVED lots cleanly
	assert_true(inv.deposit(&"stone", 3))
	var site_e := _create_site(fx, {&"stone": 3}, SITE_A_POS)
	_withdraw_site_lot_physically(fx, site_e, worker, &"stone", 2, &"op_e48_res", &"lot_e48_res")
	var fail_bush := await _spawn_source(fx, BUSH_SCENE, &"c35_bush_fail_deliv", Vector3(-1.5, 0.0, -7.5), 4, 2, 2, 0.04, 0.0, false)
	_place_worker(fx, worker, Vector3(-2.0, 0.0, -7.5))
	var fail_deliv_order := GatherResourceOrder.new(fail_bush, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(fail_deliv_order)
	assert_true(await _until(func() -> bool: return fail_deliv_order.get_phase() == GatherResourceOrder.Phase.DELIVERING_TO_CAMP and worker.get_carry_load().get_amount(&"food") >= 2))
	var override_calls: int = 0
	(fx.storage as GroundPileManager).pile_creator_override = func(_id: int, _def: ResourceDefinition, _amt: int, _pos: Vector3) -> GroundResourcePile:
		override_calls += 1
		return null
	assert_true(await _until(func() -> bool: return fail_deliv_order.is_finished()))
	(fx.storage as GroundPileManager).pile_creator_override = Callable()
	assert_eq(override_calls, 0)
	assert_eq(fail_deliv_order.status, UnitOrder.Status.FAILED)
	assert_eq(fail_deliv_order.failure_reason, "unsafe_pile_creator_override")
	assert_true(worker.get_carry_load().get_amount(&"food") >= 2, "Extracted FREE_GATHERED lots must be preserved on camp delivery failure")
	assert_eq(worker.get_carry_load().get_amount(&"stone"), 2, "SITE_RESERVED lot must also be preserved on failure")
	assert_eq(site_e._read_transit_claim_for_unit_pure(worker.get_instance_id()), {&"stone": 2})
	_assert_all_guards_clear(fx, [tree_e, slot_bush, nav_bush, re_bush, fail_bush], [worker], [cancel_app, cancel_prep, cancel_retry, felling_chop, mid_transport, pre_dropoff, rem_order, rem_unc_order, nav_order, sync_order, re_order, fail_deliv_order])


# ==============================================================================
# GROUP F — CONSERVATION, ATOMIC SIGNAL OBSERVATION & GUARDS (Scenarios 51–60)
# ==============================================================================
func test_group_f_conservation_invariants_observer_atomicity_and_guard_cleanup() -> void:
	var fx := await _fixture()
	var worker: Unit = fx.worker
	var peer: Unit = fx.peer
	var load_a: UnitCarryLoad = worker.get_carry_load()
	var load_b: UnitCarryLoad = peer.get_carry_load()
	var inv: SettlementInventory = fx.inventory
	var storage: GroundPileManager = fx.storage
	var camp: CampStorageZone = fx.camp
	assert_true(load_a.enable_provenance(&"worker_f_a"))
	assert_true(load_b.enable_provenance(&"worker_f_b"))

	# Uninvolved Sites A & B + partial reserved holdings on peer (57)
	assert_true(inv.deposit(&"wood", 6))
	assert_true(inv.deposit(&"stone", 6))
	var site_a := _create_site(fx, {&"wood": 4}, SITE_A_POS)
	var site_b := _create_site(fx, {&"stone": 4}, SITE_B_POS)
	_withdraw_site_lot_physically(fx, site_b, worker, &"stone", 2, &"op_f_sb", &"lot_f_sb")

	var tree_f := await _spawn_source(fx, TREE_SCENE, &"c35_tree_f", Vector3(3.5, 0.0, 2.0), 12, 3, 2, 0.04, 0.0)
	var rock_f := await _spawn_source(fx, ROCK_SCENE, &"c35_rock_f", Vector3(3.5, 0.0, -3.5), 7, 2, 2, 0.04, 0.0)

	var expected_wood: int = inv.get_physical_amount(&"wood") + load_a.get_amount(&"wood") + load_b.get_amount(&"wood") + tree_f.get_remaining_amount()
	var expected_stone: int = inv.get_physical_amount(&"stone") + load_a.get_amount(&"stone") + load_b.get_amount(&"stone") + rock_f.get_remaining_amount()
	var observer_state := {"errors": [] as Array[String], "signals_verified": 0}

	var check_snapshot_atomicity := func(tag: String) -> void:
		observer_state["signals_verified"] = int(observer_state["signals_verified"]) + 1
		var cur_wood: int = inv.get_physical_amount(&"wood") + load_a.get_amount(&"wood") + load_b.get_amount(&"wood") + tree_f.get_remaining_amount()
		var cur_stone: int = inv.get_physical_amount(&"stone") + load_a.get_amount(&"stone") + load_b.get_amount(&"stone") + rock_f.get_remaining_amount()
		var errors_arr: Array[String] = observer_state["errors"] as Array[String]
		if cur_wood != expected_wood or cur_stone != expected_stone:
			errors_arr.append("%s: wood %d!=%d stone %d!=%d" % [tag, cur_wood, expected_wood, cur_stone, expected_stone])
		if not load_a.validate_provenance() or not load_b.validate_provenance():
			errors_arr.append("%s: invalid provenance ledger during signal" % tag)
		if inv.get_reservation_amounts(site_a.reservation_id) != {&"wood": 4}:
			errors_arr.append("%s: site_a reservation mutated" % tag)
		if inv.get_reservation_amounts(site_b.reservation_id) != {&"stone": 2}:
			errors_arr.append("%s: site_b reservation mutated" % tag)
		if site_b._read_transit_claim_for_unit_pure(worker.get_instance_id()) != {&"stone": 2}:
			errors_arr.append("%s: site_b transit claim mutated" % tag)

	# 59. Connect to ALL economic signals across extraction and camp delivery
	_watch(load_a.load_changed, func() -> void: check_snapshot_atomicity.call("load_a_changed"))
	_watch(load_b.load_changed, func() -> void: check_snapshot_atomicity.call("load_b_changed"))
	_watch(tree_f.amount_changed, func(_s: ResourceSource, _r: int, _d: int) -> void: check_snapshot_atomicity.call("tree_amount"))
	_watch(tree_f.depleted, func(_s: ResourceSource) -> void: check_snapshot_atomicity.call("tree_depleted"))
	_watch(rock_f.amount_changed, func(_s: ResourceSource, _r: int, _d: int) -> void: check_snapshot_atomicity.call("rock_amount"))
	_watch(rock_f.depleted, func(_s: ResourceSource) -> void: check_snapshot_atomicity.call("rock_depleted"))
	_watch(storage.storage_changed, func() -> void: check_snapshot_atomicity.call("storage_changed"))
	_watch(inv.inventory_changed, func() -> void: check_snapshot_atomicity.call("inventory_changed"))

	_place_worker(fx, worker, Vector3(1.5, 0.0, 2.0))
	_place_worker(fx, peer, Vector3(1.5, 0.0, -3.5))
	var ord_a := GatherResourceOrder.new(tree_f, camp, inv, 0.04, 0.0, true, fx.region)
	var ord_b := GatherResourceOrder.new(rock_f, camp, inv, 0.04, 0.0, true, fx.region)
	worker.issue_order(ord_a)
	peer.issue_order(ord_b)

	assert_true(await _until(func() -> bool: return ord_a.is_finished() and ord_b.is_finished()))
	assert_true(ord_a.is_succeeded(), ord_a.failure_reason)
	assert_true(ord_b.is_succeeded(), ord_b.failure_reason)
	var recorded_errors: Array[String] = observer_state["errors"] as Array[String]
	assert_true(recorded_errors.is_empty(), "Intermediate state observed inside signals: %s" % str(recorded_errors))
	assert_gt(int(observer_state["signals_verified"]), 8)

	# 51–58. Final conservation, zero duplicates/fictitious resources on replay, unrelated sites untouched
	assert_true(tree_f.is_depleted())
	assert_true(rock_f.is_depleted())
	assert_eq(inv.get_available_amount(&"wood"), 14, "2 free + 12 gathered = 14")
	assert_eq(inv.get_available_amount(&"stone"), 9, "2 free + 7 gathered = 9")
	assert_eq(load_a.get_all_amounts(), {&"stone": 2})
	assert_true(load_b.is_empty())
	assert_eq(site_a.get_delivered_buffer_amount(&"wood"), 0)
	assert_eq(site_b.get_delivered_buffer_amount(&"stone"), 0)

	# 55 & 58. Verify unique source receipts sum to exact extracted totals and replays produce 0 new material
	var receipt_sum_tree: int = 0
	for op_k: Variant in tree_f._provenance_receipts.keys():
		var r_dict: Dictionary = tree_f.get_provenance_receipt(op_k)
		receipt_sum_tree += int(r_dict.get("committed_amount", 0))
		var rep: Dictionary = tree_f.transfer_to_carry_load_with_provenance(
			load_a, r_dict["operation_id"], r_dict["lot_id"], int(r_dict["requested_amount"])
		)
		assert_true(bool(rep.get("ok", false)) and bool(rep.get("replayed", false)))
		assert_eq(int(rep.get("extracted", -1)), 0)
	assert_eq(receipt_sum_tree, 12)

	var receipt_sum_rock: int = 0
	for op_k2: Variant in rock_f._provenance_receipts.keys():
		var r_dict2: Dictionary = rock_f.get_provenance_receipt(op_k2)
		receipt_sum_rock += int(r_dict2.get("committed_amount", 0))
	assert_eq(receipt_sum_rock, 7)

	var total_wood_final: int = inv.get_physical_amount(&"wood") + load_a.get_amount(&"wood") + load_b.get_amount(&"wood") + tree_f.get_remaining_amount()
	var total_stone_final: int = inv.get_physical_amount(&"stone") + load_a.get_amount(&"stone") + load_b.get_amount(&"stone") + rock_f.get_remaining_amount()
	assert_eq(total_wood_final, expected_wood)
	assert_eq(total_stone_final, expected_stone)

	_assert_economy_and_sites_consistent(fx, [worker, peer], [site_a, site_b], {site_a: {&"wood": 4}, site_b: {&"stone": 2}})
	_assert_all_guards_clear(fx, [tree_f, rock_f], [worker, peer], [ord_a, ord_b])
