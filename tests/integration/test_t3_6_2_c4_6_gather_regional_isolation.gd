class_name TestT362C46GatherRegionalIsolation
extends TestCase

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")
## Focused integration suite for T3.6.2-C4.6 (R1):
## - R1-A: GatherTransferSession retries with an already-allocated operation_id must
##   check RegionalAuthority activity read-only before calling ResourceSource transfer,
##   without creating an authority, generating a second ID, blocking distinct regions,
##   or breaking committed replays and retry limits.
## - R1-B: Free-lot gathering while holding an unrelated ConstructionSite transit claim
##   must not increment site _transaction_revision or emit spurious site.state_changed
##   when the site's claims and economic state did not change, while still notifying on
##   real claim reductions, real deliveries, load_changed/weight HUD observers, and
##   preserving legacy T3.3-T3.5 flows.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const ROCK_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const DOMAIN_META := ReservedWithdrawalCoordinator.DOMAIN_META
const SitePlanner = preload("res://src/economy/selective_site_delivery_planner.gd")

const SITE_A_POS := Vector3(-6.0, 0.0, 1.5)
const SITE_B_POS := Vector3(0.37, 0.0, -13.19)
const FRAME_LIMIT := 2400

var _active_mains: Array[MainScene] = []
var _extra_nodes: Array[Node] = []
var _extra_managers: Array[GroundPileManager] = []
var _extra_releases: Array[Dictionary] = []
var _connections: Array[Array] = []
var _prior_scale: float = 1.0
var _prior_ticks: int = 60


func before_each() -> void:
	_prior_scale = Engine.time_scale
	_prior_ticks = Engine.physics_ticks_per_second
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180


func after_each() -> void:
	for conn: Array in _connections:
		var sig: Signal = conn[0]
		if is_instance_id_valid(sig.get_object_id()) and sig.is_connected(conn[1]):
			sig.disconnect(conn[1])
	_connections.clear()

	for node: Node in _extra_nodes:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_extra_nodes.clear()

	for mgr: GroundPileManager in _extra_managers:
		if mgr != null:
			mgr.cleanup()
	_extra_managers.clear()

	for rel: Dictionary in _extra_releases:
		var w: World3D = rel["world"] as World3D
		var r: StringName = rel["region"] as StringName
		var s: GroundPileManager = rel["storage"] as GroundPileManager
		var tok: RefCounted = rel["token"] as RefCounted
		if w != null and is_instance_valid(w) and s != null and tok != null:
			ReservedWithdrawalCoordinator.release_regional_domain(w, r, s, tok, get_tree())
	_extra_releases.clear()

	var mains_copy: Array[MainScene] = _active_mains.duplicate()
	_active_mains.clear()
	for main: MainScene in mains_copy:
		if is_instance_valid(main):
			if main.get_parent() != null:
				main.get_parent().remove_child(main)
			main.free()

	Engine.time_scale = _prior_scale
	Engine.physics_ticks_per_second = _prior_ticks
	await get_tree().process_frame


func _watch(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_connections.append([sig, cb])


func _until(condition: Callable, limit: int = FRAME_LIMIT) -> bool:
	for _i: int in range(limit):
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func _boot_main() -> Dictionary:
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	get_tree().root.add_child(main)
	_active_mains.append(main)
	await get_tree().process_frame
	await get_tree().physics_frame

	var nav: WorldNavigation = main.get_test_map().get_navigation()
	var deadline: int = Time.get_ticks_msec() + 8000
	while not nav.is_navigation_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame

	var units_root: Node3D = main.get_node("Units") as Node3D
	var leader_a: Unit = units_root.get_node("LeaderA") as Unit
	var leader_b: Unit = units_root.get_node("LeaderB") as Unit
	_accelerate([leader_a, leader_b])
	return {
		"main": main,
		"world": main.get_world_3d(),
		"nav": nav,
		"region": nav.get_region_id(),
		"camp": main.get_camp_storage_zone(),
		"manager": main.get_ground_pile_manager(),
		"inventory": main.get_settlement_inventory(),
		"cm": main.get_construction_manager(),
		"units_root": units_root,
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _accelerate(units: Array) -> void:
	for u_var: Variant in units:
		if u_var is Unit:
			var u: Unit = u_var as Unit
			var d: CharacterDefinition = u.get_definition().duplicate() as CharacterDefinition
			d.move_speed = 7.5
			d.work_approach_speed = 7.5
			d.max_load_speed_multiplier = 0.70
			u.apply_definition(d)


func _spawn_source(
	parent: Node,
	scene: PackedScene,
	source_id: StringName,
	pos: Vector3,
	amount: int,
	max_extract: int,
	op_sec: float = 0.04,
	prep_sec: float = 0.0
) -> ResourceSource:
	var src: ResourceSource = scene.instantiate() as ResourceSource
	src.position = pos
	parent.add_child(src)
	_extra_nodes.append(src)
	src.configure(source_id, src.get_definition(), amount, max_extract, 2)
	src.set_gather_cycle_timings(op_sec, prep_sec)
	if src.get_category() == ResourceDefinition.Category.WOOD:
		src.felling_duration_sec = 0.05
	return src


func _make_region_fixture(parent: Node, region_id: StringName, offset: Vector3, nav: WorldNavigation) -> Dictionary:
	var host := Node3D.new()
	host.name = "C46RegionHost_%s" % String(region_id)
	host.position = offset
	parent.add_child(host)
	_extra_nodes.append(host)

	var camp := CampStorageZone.new()
	camp.zone_id = StringName("camp_%s" % String(region_id))
	camp.zone_bounds_half_extents = Vector2(2.5, 2.5)
	camp.slot_spacing = 1.4
	camp.max_pile_amount = 10
	host.add_child(camp)
	camp.set_world_navigation(nav)

	var piles_root := Node3D.new()
	piles_root.name = "PilesRoot"
	host.add_child(piles_root)

	var defs: Dictionary = {&"wood": WOOD, &"stone": STONE, &"food": FOOD}
	var manager := GroundPileManager.new(defs, camp, piles_root, SimulatedWorldTimeProvider.new(0.0))
	var token := RefCounted.new()
	assert_true(manager.bind_domain_owner(token))
	var inv := SettlementInventory.new(manager)
	_extra_managers.append(manager)
	_extra_releases.append({
		"world": host.get_world_3d(),
		"region": region_id,
		"storage": manager,
		"token": token,
	})

	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.name = "Unit_%s" % String(region_id)
	unit.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	host.add_child(unit)
	unit.set_world_navigation(nav)
	unit.global_position = nav.snap_to_navmesh(camp.global_position)
	unit.set_meta(&"region_id", region_id)

	return {
		"host": host,
		"world": host.get_world_3d(),
		"region": region_id,
		"camp": camp,
		"manager": manager,
		"inventory": inv,
		"unit": unit,
	}


func _create_site(fx: Dictionary, costs: Dictionary, pos: Vector3) -> ConstructionSite:
	var def: BuildingDefinition = SHELTER.duplicate() as BuildingDefinition
	def.costs = costs
	var res: Dictionary = (fx["cm"] as ConstructionManager).try_create_site_from_placement(def, pos)
	assert_true(bool(res.get("ok", false)), str(res))
	return res["site"] as ConstructionSite


func _withdraw_reserved_to_unit(
	fx: Dictionary,
	site: ConstructionSite,
	worker: Unit,
	res_id: StringName,
	amount: int,
	op_id: StringName,
	lot_id: StringName
) -> void:
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var entries: Array[Dictionary] = inv.get_reserved_pile_entries(site.reservation_id, res_id)
	assert_false(entries.is_empty(), "Missing reserved pile for %s" % String(res_id))
	var entry: Dictionary = entries[0]
	var pid: int = int(entry["pile_id"])
	var pile_pos: Vector3 = entry["world_pos"] as Vector3
	var saved_pos: Vector3 = worker.global_position

	var temp_order := ConstructOrder.new(site, fx["camp"] as CampStorageZone, true, true, true)
	temp_order._unit = worker
	temp_order.mark_running()
	worker._current_order = temp_order
	var role: ConstructionSite.WorkerRole = site.register_worker(worker, temp_order, true)
	assert_ne(role, ConstructionSite.WorkerRole.UNASSIGNED)
	assert_eq(site.claim_pickup(worker, pid, res_id, amount, int(entry["reserved_amount"])), amount)
	worker.global_position = pile_pos
	var coord := ReservedWithdrawalCoordinator.new()
	var res: Dictionary = coord.execute_reserved_withdrawal(site, worker, pid, res_id, amount, op_id, lot_id)
	assert_true(bool(res.get("ok", false)), str(res))
	site.unregister_worker(worker, temp_order)
	worker._current_order = null
	worker.global_position = saved_pos


func test_01_r1a_normal_gather_and_preallocated_retry_blocked_by_active_authority() -> void:
	var fx: Dictionary = await _boot_main()
	var world: World3D = fx["world"] as World3D
	var region: StringName = fx["region"] as StringName
	var nav: WorldNavigation = fx["nav"] as WorldNavigation
	var camp: CampStorageZone = fx["camp"] as CampStorageZone
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var leader_a: Unit = fx["leader_a"] as Unit
	var leader_b: Unit = fx["leader_b"] as Unit
	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	var load_b: UnitCarryLoad = leader_b.get_carry_load()
	assert_true(load_a.enable_provenance(&"c46_a"))
	assert_true(load_b.enable_provenance(&"c46_b"))

	# Read-only check must NEVER create a RegionalAuthority when none exists yet.
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, region))
	assert_false((world.get_meta(DOMAIN_META, {}) as Dictionary).has(region))

	# Case 1: Normal opt-in gather works cleanly (bush, 4 food).
	var bush: ResourceSource = _spawn_source(fx["main"], BUSH_SCENE, &"c46_bush_1", Vector3(2.5, 0.0, 2.0), 4, 4)
	leader_a.global_position = nav.snap_to_navmesh(Vector3(1.6, 0.0, 2.0))
	var normal_order := GatherResourceOrder.new(bush, camp, inv, 0.04, 0.0, true, region)
	leader_a.issue_order(normal_order)
	assert_true(await _until(func() -> bool: return normal_order.is_finished()))
	assert_true(normal_order.is_succeeded(), normal_order.failure_reason)
	assert_eq(inv.get_available_amount(&"food"), 4)
	assert_eq(bush.get_remaining_amount(), 0)

	# Case 2 & 3: Pre-allocated GatherTransferSession retry attempted during another participant's
	# active RegionalAuthority transaction post-commit callback must be refused as "busy", preserve
	# exact operation_id/lot_id and source/cargo invariants, and succeed once guard releases.
	var tree: ResourceSource = _spawn_source(fx["main"], TREE_SCENE, &"c46_tree_r1a", Vector3(3.2, 0.0, -2.5), 6, 3)
	leader_a.global_position = nav.snap_to_navmesh(Vector3(2.2, 0.0, -2.5))
	var gather_order := GatherResourceOrder.new(tree, camp, inv, 0.04, 0.0, true, region)
	load_a.begin_batch()
	leader_a.issue_order(gather_order)
	assert_true(await _until(func() -> bool:
		var s: GatherTransferSession = gather_order.get_active_gather_session()
		return s != null and s.is_retry_scheduled()
	))
	load_a.end_batch()

	var session: GatherTransferSession = gather_order.get_active_gather_session()
	var frozen_op: StringName = session.get_operation_id()
	var frozen_lot: StringName = session.get_lot_id()
	assert_ne(frozen_op, &"")
	assert_ne(frozen_lot, &"")
	assert_eq(session.get_busy_retries(), 1)
	assert_eq(tree.get_remaining_amount(), 6)

	var domains: Dictionary = world.get_meta(DOMAIN_META, {}) as Dictionary
	var auth: ReservedWithdrawalCoordinator.RegionalAuthority = domains.get(region) as ReservedWithdrawalCoordinator.RegionalAuthority
	assert_not_null(auth)
	var serial_before: int = auth.construction_transfer_serial
	var receipts_before: int = auth.receipts.size()
	var load_a_snap_before: Dictionary = load_a.provenance_snapshot()

	# Peer LeaderB initiates a real regional transaction (camp delivery) in the SAME region.
	assert_true(bool(CarryFixture.add_lot(load_b, &"c46_peer_g", &"c46_peer_l", &"stone", STONE.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	leader_b.global_position = camp.global_position

	var probe := {
		"callback_fired": false,
		"auth_executing_in_cb": false,
		"retry_res": {},
		"tree_rem_in_cb": -1,
		"load_a_amt_in_cb": -1,
		"src_receipt_empty_in_cb": false,
		"op_after_cb": &"",
		"lot_after_cb": &"",
		"serial_in_cb": -1,
		"receipts_in_cb": -1,
	}
	_watch(load_b.load_changed, func() -> void:
		if bool(probe["callback_fired"]):
			return
		probe["callback_fired"] = true
		probe["auth_executing_in_cb"] = auth.is_executing
		# Force retry due while authority.is_executing is active for LeaderB!
		assert_true(session.retry_is_due(GatherTransferSession.RETRY_INTERVAL_SEC + 0.01))
		var r_res: Dictionary = session.execute_or_retry(inv, camp, tree, leader_a, region, gather_order.get_instance_id(), true)
		probe["retry_res"] = r_res
		probe["tree_rem_in_cb"] = tree.get_remaining_amount()
		probe["load_a_amt_in_cb"] = load_a.get_amount(&"wood")
		probe["src_receipt_empty_in_cb"] = tree.get_provenance_receipt(frozen_op).is_empty()
		probe["op_after_cb"] = session.get_operation_id()
		probe["lot_after_cb"] = session.get_lot_id()
		probe["serial_in_cb"] = auth.construction_transfer_serial
		probe["receipts_in_cb"] = auth.receipts.size()
	)

	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var peer_del: Dictionary = camp_coord.execute_selective_camp_delivery(inv, camp, leader_b, region, &"c46_peer_camp_op", [])
	assert_true(bool(peer_del.get("ok", false)), str(peer_del))
	assert_true(bool(probe["callback_fired"]))
	assert_true(bool(probe["auth_executing_in_cb"]))

	var retry_res: Dictionary = probe["retry_res"] as Dictionary
	assert_false(bool(retry_res.get("ok", true)), "Pre-allocated gather retry MUST be refused while RegionalAuthority is active: %s" % str(retry_res))
	assert_eq(String(retry_res.get("reason", "")), "busy")
	assert_eq(StringName(probe["op_after_cb"]), frozen_op, "Blocked retry must keep exact frozen operation_id")
	assert_eq(StringName(probe["lot_after_cb"]), frozen_lot, "Blocked retry must keep exact frozen lot_id")
	assert_eq(int(probe["tree_rem_in_cb"]), 6, "Source must not be extracted while authority is busy")
	assert_eq(int(probe["load_a_amt_in_cb"]), 0, "CarryLoad must not receive material while authority is busy")
	assert_true(bool(probe["src_receipt_empty_in_cb"]))
	assert_eq(int(probe["serial_in_cb"]), serial_before, "Blocked retry must not allocate a new serial")
	assert_eq(int(probe["receipts_in_cb"]), receipts_before + 1, "Only LeaderB camp_delivery receipt added, zero gather receipt")
	assert_false(auth.receipts.has(frozen_op))
	assert_eq(load_a.provenance_snapshot(), load_a_snap_before)
	assert_true(session.is_retry_scheduled(), "Session must stay RETRY_SCHEDULED after busy refusal")
	assert_eq(session.get_busy_retries(), 2)

	# Case 3: Once authority guard is released, GatherResourceOrder retries cleanly using SAME frozen IDs!
	assert_false(auth.is_executing)
	assert_true(await _until(func() -> bool: return gather_order.is_finished()))
	assert_true(gather_order.is_succeeded(), gather_order.failure_reason)
	assert_eq(StringName(tree.get_provenance_receipt(frozen_op).get("operation_id", &"")), frozen_op)
	assert_eq(StringName(tree.get_provenance_receipt(frozen_op).get("lot_id", &"")), frozen_lot)
	assert_eq(tree.get_remaining_amount(), 0)
	assert_eq(inv.get_available_amount(&"wood"), 6)
	assert_eq(inv.get_available_amount(&"stone"), 2)
	assert_eq(inv.get_available_amount(&"food"), 4)
	assert_true(load_a.is_empty())
	assert_true(load_b.is_empty())


func test_02_r1a_distinct_regions_unblocked_committed_replay_and_retry_limit() -> void:
	var fx: Dictionary = await _boot_main()
	var nav: WorldNavigation = fx["nav"] as WorldNavigation
	var world: World3D = fx["world"] as World3D

	var reg_a: Dictionary = _make_region_fixture(get_tree().root, &"c46_reg_a", Vector3(-3.0, 0.0, 4.0), nav)
	var reg_b: Dictionary = _make_region_fixture(get_tree().root, &"c46_reg_b", Vector3(3.0, 0.0, -4.0), nav)
	var ua: Unit = reg_a["unit"] as Unit
	var ub: Unit = reg_b["unit"] as Unit
	var inv_a: SettlementInventory = reg_a["inventory"] as SettlementInventory
	var camp_a: CampStorageZone = reg_a["camp"] as CampStorageZone
	var inv_b: SettlementInventory = reg_b["inventory"] as SettlementInventory
	var camp_b: CampStorageZone = reg_b["camp"] as CampStorageZone
	assert_true(ua.get_carry_load().enable_provenance(&"c46_ua"))
	assert_true(ub.get_carry_load().enable_provenance(&"c46_ub"))

	var rock_a: ResourceSource = _spawn_source(reg_a["host"] as Node, ROCK_SCENE, &"c46_rock_a", Vector3.ZERO, 6, 3)
	ua.global_position = rock_a.global_position

	# Allocate operation_id in reg_a and enter RETRY_SCHEDULED via local batch lock.
	var sess_a := GatherTransferSession.new()
	assert_true(bool(sess_a.initialize_cycle(inv_a, camp_a, rock_a, ua, &"c46_reg_a", 5001, 1, 3).get("ok", false)))
	ua.get_carry_load().begin_batch()
	var first_busy: Dictionary = sess_a.execute_or_retry(inv_a, camp_a, rock_a, ua, &"c46_reg_a", 5001, true)
	assert_false(bool(first_busy.get("ok", true)))
	assert_eq(String(first_busy.get("reason", "")), "busy")
	assert_true(sess_a.is_retry_scheduled())
	ua.get_carry_load().end_batch()
	var frozen_op_a: StringName = sess_a.get_operation_id()

	# Read-only check must NOT create RegionalAuthority on uninitialized &"c46_uninit_reg".
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, &"c46_uninit_reg"))
	assert_false((world.get_meta(DOMAIN_META, {}) as Dictionary).has(&"c46_uninit_reg"))

	# Case 4: While reg_b authority is executing, reg_a pre-allocated retry MUST SUCCEED immediately!
	assert_true(bool(CarryFixture.add_lot(ub.get_carry_load(), &"c46_rb_g", &"c46_rb_l", &"food", FOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	var cross_reg := {"fired": false, "res": {}}
	_watch(ub.get_carry_load().load_changed, func() -> void:
		if bool(cross_reg["fired"]):
			return
		cross_reg["fired"] = true
		var doms: Dictionary = world.get_meta(DOMAIN_META, {}) as Dictionary
		var auth_b: ReservedWithdrawalCoordinator.RegionalAuthority = doms.get(&"c46_reg_b") as ReservedWithdrawalCoordinator.RegionalAuthority
		assert_not_null(auth_b)
		assert_true(auth_b.is_executing)
		cross_reg["res"] = sess_a.execute_or_retry(inv_a, camp_a, rock_a, ua, &"c46_reg_a", 5001, true)
	)
	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var del_b: Dictionary = camp_coord.execute_selective_camp_delivery(inv_b, camp_b, ub, &"c46_reg_b", &"c46_rb_del", [])
	assert_true(bool(del_b.get("ok", false)), str(del_b))
	assert_true(bool(cross_reg["fired"]))
	var res_a: Dictionary = cross_reg["res"] as Dictionary
	assert_true(bool(res_a.get("ok", false)), "Distinct reg_a must NOT be blocked while reg_b is executing: %s" % str(res_a))
	assert_eq(int(res_a.get("extracted", 0)), 3)
	assert_eq(StringName(res_a.get("operation_id", &"")), frozen_op_a)
	assert_eq(rock_a.get_remaining_amount(), 3)
	assert_eq(ua.get_carry_load().get_amount(&"stone"), 3)

	# Case 5: Already-committed replay in SAME reg_a succeeds with replayed=true, extracted=0
	# even while another participant executes on reg_a's RegionalAuthority!
	var ua_peer: Unit = UNIT_SCENE.instantiate() as Unit
	ua_peer.name = "UnitPeer_RegA"
	ua_peer.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	(reg_a["host"] as Node).add_child(ua_peer)
	ua_peer.set_world_navigation(nav)
	ua_peer.global_position = camp_a.global_position
	ua_peer.set_meta(&"region_id", &"c46_reg_a")
	assert_true(ua_peer.get_carry_load().enable_provenance(&"c46_ua_peer"))
	assert_true(bool(CarryFixture.add_lot(ua_peer.get_carry_load(), &"c46_rap_g", &"c46_rap_l", &"food", FOOD.unit_weight, 1, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))

	var replay_sess := GatherTransferSession.new()
	assert_true(bool(replay_sess.initialize_cycle(inv_a, camp_a, rock_a, ua, &"c46_reg_a", 5001, 1, 3).get("ok", false)))
	replay_sess._operation_id = frozen_op_a
	replay_sess._lot_id = sess_a.get_lot_id()

	var snap_ua_before_replay: Dictionary = ua.get_carry_load().provenance_snapshot()
	var replay_probe := {"fired": false, "res": {}}
	_watch(ua_peer.get_carry_load().load_changed, func() -> void:
		if bool(replay_probe["fired"]):
			return
		replay_probe["fired"] = true
		var doms: Dictionary = world.get_meta(DOMAIN_META, {}) as Dictionary
		var auth_a: ReservedWithdrawalCoordinator.RegionalAuthority = doms.get(&"c46_reg_a") as ReservedWithdrawalCoordinator.RegionalAuthority
		assert_true(auth_a.is_executing)
		replay_probe["res"] = replay_sess.execute_or_retry(inv_a, camp_a, rock_a, ua, &"c46_reg_a", 5001, true)
	)
	assert_true(bool(camp_coord.execute_selective_camp_delivery(inv_a, camp_a, ua_peer, &"c46_reg_a", &"c46_rap_del", []).get("ok", false)))
	assert_true(bool(replay_probe["fired"]))
	var rep_res: Dictionary = replay_probe["res"] as Dictionary
	assert_true(bool(rep_res.get("ok", false)), "Committed replay must remain valid even when peer runs in authority: %s" % str(rep_res))
	assert_true(bool(rep_res.get("replayed", false)))
	assert_eq(int(rep_res.get("extracted", -1)), 0)
	assert_eq(int(rep_res.get("committed_amount", 0)), 3)
	assert_eq(rock_a.get_remaining_amount(), 3)
	assert_eq(ua.get_carry_load().provenance_snapshot(), snap_ua_before_replay)

	# Retry limit preservation: while authority.is_executing remains active, MAX_BUSY_RETRIES terminates cleanly.
	var lim_sess := GatherTransferSession.new()
	assert_true(bool(lim_sess.initialize_cycle(inv_a, camp_a, rock_a, ua, &"c46_reg_a", 5002, 1, 3).get("ok", false)))
	var doms_a: Dictionary = world.get_meta(DOMAIN_META, {}) as Dictionary
	var auth_a_ref: ReservedWithdrawalCoordinator.RegionalAuthority = doms_a.get(&"c46_reg_a") as ReservedWithdrawalCoordinator.RegionalAuthority
	# Pre-allocate ID while unlocked via load batch, then keep auth_a_ref.is_executing = true across retries.
	ua.get_carry_load().begin_batch()
	var lim_init: Dictionary = lim_sess.execute_or_retry(inv_a, camp_a, rock_a, ua, &"c46_reg_a", 5002, true)
	assert_eq(String(lim_init.get("reason", "")), "busy")
	assert_eq(lim_sess.get_busy_retries(), 1)
	ua.get_carry_load().end_batch()
	var lim_op: StringName = lim_sess.get_operation_id()

	auth_a_ref.is_executing = true
	for _r: int in range(3):
		var step_res: Dictionary = lim_sess.execute_or_retry(inv_a, camp_a, rock_a, ua, &"c46_reg_a", 5002, true)
		assert_false(bool(step_res.get("ok", true)))
		assert_eq(String(step_res.get("reason", "")), "busy")
		assert_eq(lim_sess.get_operation_id(), lim_op)
	var final_lim: Dictionary = lim_sess.execute_or_retry(inv_a, camp_a, rock_a, ua, &"c46_reg_a", 5002, true)
	auth_a_ref.is_executing = false
	assert_false(bool(final_lim.get("ok", true)))
	assert_eq(String(final_lim.get("reason", "")), "busy_retry_exhausted")
	assert_true(lim_sess.is_closed())
	assert_eq(rock_a.get_remaining_amount(), 3)


func test_03_r1b_free_gather_preserves_site_a_revision_signals_claims_and_site_b() -> void:
	var fx: Dictionary = await _boot_main()
	var region: StringName = fx["region"] as StringName
	var nav: WorldNavigation = fx["nav"] as WorldNavigation
	var camp: CampStorageZone = fx["camp"] as CampStorageZone
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var leader_a: Unit = fx["leader_a"] as Unit
	var leader_b: Unit = fx["leader_b"] as Unit
	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	var load_b: UnitCarryLoad = leader_b.get_carry_load()
	assert_true(load_a.enable_provenance(&"c46_site_worker_a"))
	assert_true(load_b.enable_provenance(&"c46_site_worker_b"))

	assert_true(inv.deposit(&"wood", 6))
	assert_true(inv.deposit(&"stone", 6))
	var site_a: ConstructionSite = _create_site(fx, {&"wood": 4, &"stone": 2}, SITE_A_POS)
	var site_b: ConstructionSite = _create_site(fx, {&"stone": 4}, SITE_B_POS)

	# LeaderA holds 2 wood reserved for Site A (weight 4/20).
	_withdraw_reserved_to_unit(fx, site_a, leader_a, &"wood", 2, &"c46_wd_a1", &"c46_wl_a1")
	# LeaderB holds 2 stone reserved for Site A AND 2 stone reserved for Site B!
	_withdraw_reserved_to_unit(fx, site_a, leader_b, &"stone", 2, &"c46_wd_a2", &"c46_wl_a2")
	_withdraw_reserved_to_unit(fx, site_b, leader_b, &"stone", 2, &"c46_wd_b1", &"c46_wl_b1")

	# Prepare a concurrent SelectiveSiteDeliveryPlan for LeaderB on Site A before LeaderA gathers free lots!
	leader_b.global_position = site_a.global_position
	var b_order := ConstructOrder.new(site_a, camp, true, true, true)
	b_order._unit = leader_b
	b_order.mark_running()
	leader_b._current_order = b_order
	leader_b.set_physics_process(false)
	site_a.register_worker(leader_b, b_order, true)
	var concurrent_plan: Dictionary = SitePlanner.prepare_selective_site_delivery(site_a, leader_b, &"c46_concurrent_b_op", {})
	assert_true(bool(concurrent_plan.get("ok", false)), str(concurrent_plan))

	var site_a_signals := {"state": 0, "buffer": 0, "workers": 0}
	var site_b_signals := {"state": 0, "buffer": 0, "workers": 0}
	var load_a_signals := [0]
	_watch(site_a.state_changed, func(_s: ConstructionSite) -> void: site_a_signals["state"] = int(site_a_signals["state"]) + 1)
	_watch(site_a.buffer_changed, func(_s: ConstructionSite) -> void: site_a_signals["buffer"] = int(site_a_signals["buffer"]) + 1)
	_watch(site_a.workers_changed, func(_s: ConstructionSite) -> void: site_a_signals["workers"] = int(site_a_signals["workers"]) + 1)
	_watch(site_b.state_changed, func(_s: ConstructionSite) -> void: site_b_signals["state"] = int(site_b_signals["state"]) + 1)
	_watch(site_b.buffer_changed, func(_s: ConstructionSite) -> void: site_b_signals["buffer"] = int(site_b_signals["buffer"]) + 1)
	_watch(site_b.workers_changed, func(_s: ConstructionSite) -> void: site_b_signals["workers"] = int(site_b_signals["workers"]) + 1)
	_watch(load_a.load_changed, func() -> void: load_a_signals[0] += 1)

	var rev_a_before: int = site_a.get_transaction_revision()
	var rev_b_before: int = site_b.get_transaction_revision()
	var claim_a_before: Dictionary = site_a.get_transit_claim_for_unit(leader_a)
	var claim_b_before: Dictionary = site_b.get_transit_claim_for_unit(leader_b)
	var reserves_a_before: Dictionary = site_a.get_reserved_in_piles_amounts()
	var reserves_b_before: Dictionary = site_b.get_reserved_in_piles_amounts()
	var state_a_before: int = site_a.get_site_state()
	var work_a_before: float = site_a.get_work_progress_sec()
	var speed_before: float = leader_a.get_movement().get_effective_move_speed()

	# Spawn a free wood tree (4 wood = weight 8; 4 + 8 = 12/20) and free bush (3 food = weight 3).
	var tree_free: ResourceSource = _spawn_source(fx["main"], TREE_SCENE, &"c46_free_tree", Vector3(3.2, 0.0, 2.0), 4, 2)
	var bush_free: ResourceSource = _spawn_source(fx["main"], BUSH_SCENE, &"c46_free_bush", Vector3(3.2, 0.0, -2.0), 3, 3)

	# Gather FREE wood into LeaderA (same resource_id as Site A's claim!) WITHOUT completing camp dropoff yet.
	leader_a.global_position = nav.snap_to_navmesh(Vector3(2.2, 0.0, 2.0))
	var g_sess_w := GatherTransferSession.new()
	assert_true(bool(g_sess_w.initialize_cycle(inv, camp, tree_free, leader_a, region, 6101, 1, 2).get("ok", false)))
	var ext_w: Dictionary = g_sess_w.execute_or_retry(inv, camp, tree_free, leader_a, region, 6101, true)
	assert_true(bool(ext_w.get("ok", false)), str(ext_w))
	assert_eq(int(ext_w.get("extracted", 0)), 2)

	# Gather FREE food via full opt-in GatherResourceOrder (which also exercises periodic ticks + selective camp delivery!).
	var free_wood_before: int = inv.get_available_amount(&"wood")
	var free_food_before: int = inv.get_available_amount(&"food")
	leader_a.global_position = nav.snap_to_navmesh(Vector3(2.2, 0.0, -2.0))
	var bush_order := GatherResourceOrder.new(bush_free, camp, inv, 0.04, 0.0, true, region)
	leader_a.issue_order(bush_order)
	assert_true(await _until(func() -> bool: return load_a.get_amount(&"food") == 3 or bush_order.is_finished()))
	leader_a.cancel_current_order()

	# HUD/weight load_changed observers fired & movement slowed down properly, YET Site A & Site B had ZERO spurious bumps/signals!
	assert_true(load_a_signals[0] >= 2, "load_changed must keep firing normally for HUD & movement")
	assert_lt(leader_a.get_movement().get_effective_move_speed(), speed_before - 0.1)
	assert_eq(site_a.get_transaction_revision(), rev_a_before, "Site A revision must NOT bump when gathering free lots preserves claim")
	assert_eq(int(site_a_signals["state"]), 0, "Site A must NOT emit spurious state_changed")
	assert_eq(int(site_a_signals["buffer"]), 0)
	assert_eq(int(site_a_signals["workers"]), 0)
	assert_eq(site_a.get_transit_claim_for_unit(leader_a), claim_a_before)
	assert_eq(site_a.get_reserved_in_piles_amounts(), reserves_a_before)
	assert_eq(site_a.get_site_state(), state_a_before)
	assert_eq(site_a.get_work_progress_sec(), work_a_before)

	# Site B stays 100% untouched.
	assert_eq(site_b.get_transaction_revision(), rev_b_before)
	assert_eq(int(site_b_signals["state"]), 0)
	assert_eq(site_b.get_transit_claim_for_unit(leader_b), claim_b_before)
	assert_eq(site_b.get_reserved_in_piles_amounts(), reserves_b_before)

	# Concurrent prepared plan on Site A for LeaderB MUST still commit cleanly (NO false stale_revision!).
	var site_coord := SelectiveSiteDeliveryCoordinator.new()
	var b_commit: Dictionary = site_coord.commit_prepared_selective_delivery(site_a, leader_b, concurrent_plan)
	assert_true(bool(b_commit.get("ok", false)), "Concurrent plan on Site A must NOT suffer stale_revision from LeaderA free gather: %s" % str(b_commit))
	assert_eq(site_a.get_delivered_buffer_amount(&"stone"), 2)
	site_a.unregister_worker(leader_b, b_order)
	leader_b._current_order = null
	leader_b.set_physics_process(true)

	# Selective camp delivery of LeaderA's FREE lots delivers free wood & food while preserving Site A's reserved wood lot & Site B's reserved stone lot.
	var camp_del := DeliverToCampOrder.new(camp, inv, true, region, [])
	leader_a.issue_order(camp_del)
	assert_true(await _until(func() -> bool: return camp_del.is_finished()))
	assert_true(camp_del.is_succeeded(), camp_del.failure_reason)
	assert_eq(inv.get_available_amount(&"wood"), free_wood_before + 2)
	assert_eq(inv.get_available_amount(&"food"), free_food_before + 3)
	assert_eq(load_a.get_all_amounts(), {&"wood": 2})
	assert_eq(site_a.get_transit_claim_for_unit(leader_a), {&"wood": 2})
	assert_eq(site_b.get_transit_claim_for_unit(leader_b), {&"stone": 2})
	assert_true(load_a.validate_provenance())
	assert_true(load_b.validate_provenance())
	assert_true(site_a.verify_accounting_invariant())
	assert_true(site_b.verify_accounting_invariant())


func test_04_r1b_real_claim_decrease_and_real_deliveries_still_notify() -> void:
	var fx: Dictionary = await _boot_main()
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var camp: CampStorageZone = fx["camp"] as CampStorageZone
	var leader_a: Unit = fx["leader_a"] as Unit
	var leader_b: Unit = fx["leader_b"] as Unit
	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	var load_b: UnitCarryLoad = leader_b.get_carry_load()

	assert_true(inv.deposit(&"wood", 6))
	assert_true(inv.deposit(&"stone", 6))
	var site_a: ConstructionSite = _create_site(fx, {&"wood": 4, &"stone": 2}, SITE_A_POS)

	# 8a. Legacy lost-cargo reduction on Site A MUST still clamp claim, increment revision, and emit state_changed!
	var legacy_w_pile: GroundResourcePile = (fx["manager"] as GroundPileManager).get_piles_for_resource(&"wood")[0]
	var leg_res: int = inv.withdraw_reserved_from_pile_to_carry_load(legacy_w_pile.pile_id, site_a.reservation_id, WOOD, 3, load_a)
	assert_eq(leg_res, 3)
	site_a.record_withdrawn_for_site(leader_a, &"wood", 3)

	var state_cnt := [0]
	var buf_cnt := [0]
	_watch(site_a.state_changed, func(_s: ConstructionSite) -> void: state_cnt[0] += 1)
	_watch(site_a.buffer_changed, func(_s: ConstructionSite) -> void: buf_cnt[0] += 1)

	# Adding extra free wood in legacy mode does NOT shrink claim -> zero state_changed bump!
	var rev_before_gain: int = site_a.get_transaction_revision()
	assert_true(load_a.add_units(WOOD, 2))
	assert_eq(site_a.get_transaction_revision(), rev_before_gain)
	assert_eq(state_cnt[0], 0)
	assert_eq(site_a.get_transit_claim_for_unit(leader_a), {&"wood": 3})

	# Losing 4 wood drops held amount from 5 to 1 (< 3 claimed) -> MUST clamp claim to 1, bump revision, emit state_changed!
	assert_eq(load_a.remove_units(&"wood", 4), 4)
	assert_eq(site_a.get_transit_claim_for_unit(leader_a), {&"wood": 1})
	assert_gt(site_a.get_transaction_revision(), rev_before_gain)
	assert_eq(state_cnt[0], 1, "Real claim reduction must emit state_changed")

	# Delivering remaining 1 legacy wood to Site A MUST emit buffer_changed + state_changed!
	state_cnt[0] = 0
	buf_cnt[0] = 0
	var rev_before_leg_del: int = site_a.get_transaction_revision()
	var leg_acc: Dictionary = site_a.accept_delivery_from_carry_load(leader_a, load_a)
	assert_eq(leg_acc, {&"wood": 1})
	assert_gt(site_a.get_transaction_revision(), rev_before_leg_del)
	assert_eq(buf_cnt[0], 1)
	assert_eq(state_cnt[0], 1)
	assert_true(site_a.get_transit_claim_for_unit(leader_a).is_empty())

	# 8b. Opt-in provenance delivery via SelectiveSiteDeliveryCoordinator MUST emit buffer_changed + state_changed!
	assert_true(load_b.enable_provenance(&"c46_real_deliv_b"))
	_withdraw_reserved_to_unit(fx, site_a, leader_b, &"stone", 2, &"c46_r8_wd", &"c46_r8_wl")
	leader_b.global_position = site_a.global_position
	var b_order := ConstructOrder.new(site_a, camp, true, true, true)
	b_order._unit = leader_b
	b_order.mark_running()
	leader_b._current_order = b_order
	site_a.register_worker(leader_b, b_order, true)
	state_cnt[0] = 0
	buf_cnt[0] = 0
	var rev_before_opt_del: int = site_a.get_transaction_revision()
	var opt_del: Dictionary = SelectiveSiteDeliveryCoordinator.new().execute_selective_site_delivery(site_a, leader_b, &"c46_r8_sd", {})
	assert_true(bool(opt_del.get("ok", false)), str(opt_del))
	assert_gt(site_a.get_transaction_revision(), rev_before_opt_del)
	assert_eq(buf_cnt[0], 1)
	assert_eq(state_cnt[0], 1)
	assert_true(site_a.get_transit_claim_for_unit(leader_b).is_empty())
	site_a.unregister_worker(leader_b, b_order)
	leader_b._current_order = null


func test_05_reentrancy_in_gather_signals_and_legacy_gather_construct_compatibility() -> void:
	var fx: Dictionary = await _boot_main()
	var region: StringName = fx["region"] as StringName
	var nav: WorldNavigation = fx["nav"] as WorldNavigation
	var camp: CampStorageZone = fx["camp"] as CampStorageZone
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var leader_a: Unit = fx["leader_a"] as Unit
	var leader_b: Unit = fx["leader_b"] as Unit
	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	var load_b: UnitCarryLoad = leader_b.get_carry_load()

	# Case 11: Reentrancy during ResourceSource / GatherTransferSession post-commit signals (no duplicate transfer!).
	assert_true(load_a.enable_provenance(&"c46_reentry_a"))
	var bush: ResourceSource = _spawn_source(fx["main"], BUSH_SCENE, &"c46_bush_re", Vector3(2.4, 0.0, 2.0), 4, 2)
	leader_a.global_position = nav.snap_to_navmesh(Vector3(1.5, 0.0, 2.0))
	var re_sess := GatherTransferSession.new()
	assert_true(bool(re_sess.initialize_cycle(inv, camp, bush, leader_a, region, 7001, 1, 2).get("ok", false)))

	var re_obs := {"load_re": {}, "amt_re": {}, "dep_re": {}}
	_watch(load_a.load_changed, func() -> void:
		if re_sess.is_executing:
			re_obs["load_re"] = re_sess.execute_or_retry(inv, camp, bush, leader_a, region, 7001, true)
	)
	_watch(bush.amount_changed, func(_s: ResourceSource, _left: int, _delta: int) -> void:
		re_obs["amt_re"] = bush.transfer_to_carry_load_with_provenance(load_a, &"c46_re_src_op", &"c46_re_src_lot", 1)
	)
	_watch(bush.depleted, func(_s: ResourceSource) -> void:
		re_obs["dep_re"] = bush.transfer_to_carry_load_with_provenance(load_a, &"c46_re_dep_op", &"c46_re_dep_lot", 1)
	)

	var r1: Dictionary = re_sess.execute_or_retry(inv, camp, bush, leader_a, region, 7001, true)
	assert_true(bool(r1.get("ok", false)), str(r1))
	assert_eq(int(r1.get("extracted", 0)), 2)
	assert_eq(bush.get_remaining_amount(), 2)
	assert_eq(load_a.get_amount(&"food"), 2)
	assert_false(bool((re_obs["load_re"] as Dictionary).get("ok", true)))
	assert_eq(String((re_obs["load_re"] as Dictionary).get("reason", "")), "busy")
	assert_false(bool((re_obs["amt_re"] as Dictionary).get("ok", true)))
	assert_eq(String((re_obs["amt_re"] as Dictionary).get("reason", "")), "busy")

	# Deplete second half and confirm depleted reentrancy is also refused without duplicate transfer.
	var re_sess_2 := GatherTransferSession.new()
	assert_true(bool(re_sess_2.initialize_cycle(inv, camp, bush, leader_a, region, 7001, 2, 2).get("ok", false)))
	var r2: Dictionary = re_sess_2.execute_or_retry(inv, camp, bush, leader_a, region, 7001, true)
	assert_true(bool(r2.get("ok", false)), str(r2))
	assert_eq(bush.get_remaining_amount(), 0)
	assert_eq(load_a.get_amount(&"food"), 4)
	assert_false(bool((re_obs["dep_re"] as Dictionary).get("ok", true)))
	assert_eq(String((re_obs["dep_re"] as Dictionary).get("reason", "")), "busy")

	# Case 12: Legacy compatibility (LeaderB stays completely legacy: gather + site withdrawal + free gather + deliver).
	assert_false(load_b.is_provenance_enabled())
	var legacy_tree: ResourceSource = _spawn_source(fx["main"], TREE_SCENE, &"c46_leg_tree", Vector3(3.0, 0.0, -3.0), 4, 2)
	leader_b.global_position = nav.snap_to_navmesh(Vector3(2.0, 0.0, -3.0))
	var leg_gather := GatherResourceOrder.new(legacy_tree, camp, inv, 0.04, 0.0, false)
	leader_b.issue_order(leg_gather)
	assert_true(await _until(func() -> bool: return leg_gather.is_finished()))
	assert_true(leg_gather.is_succeeded(), leg_gather.failure_reason)
	assert_eq(inv.get_available_amount(&"wood"), 4)
	assert_true(load_b.is_empty())

	var leg_site: ConstructionSite = _create_site(fx, {&"wood": 2}, SITE_A_POS)
	var leg_pile: GroundResourcePile = (fx["manager"] as GroundPileManager).get_piles_for_resource(&"wood")[0]
	var leg_wd: int = inv.withdraw_reserved_from_pile_to_carry_load(leg_pile.pile_id, leg_site.reservation_id, WOOD, 2, load_b)
	assert_eq(leg_wd, 2)
	leg_site.record_withdrawn_for_site(leader_b, &"wood", 2)
	var leg_rev_before: int = leg_site.get_transaction_revision()
	var leg_state_cnt := [0]
	_watch(leg_site.state_changed, func(_s: ConstructionSite) -> void: leg_state_cnt[0] += 1)
	# Legacy free gather while carrying legacy site claim does NOT generate spurious site revision/signal either.
	assert_eq(legacy_tree.get_remaining_amount(), 0)
	var leg_bush: ResourceSource = _spawn_source(fx["main"], BUSH_SCENE, &"c46_leg_bush", Vector3(-2.5, 0.0, -2.5), 2, 2)
	assert_eq(leg_bush.transfer_to_carry_load(load_b, 2), 2)
	assert_eq(leg_site.get_transaction_revision(), leg_rev_before)
	assert_eq(leg_state_cnt[0], 0)
	var leg_deliv: Dictionary = leg_site.accept_delivery_from_carry_load(leader_b, load_b)
	assert_eq(leg_deliv, {&"wood": 2})
	assert_gt(leg_site.get_transaction_revision(), leg_rev_before)
	assert_eq(leg_state_cnt[0], 1)
