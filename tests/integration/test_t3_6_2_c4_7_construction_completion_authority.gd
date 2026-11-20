class_name TestT362C47ConstructionCompletionAuthority
extends TestCase

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")
## Focused integration suite for T3.6.2-C4.7 (P6-A):
## Regional transactional boundary for construction completion:
## - Respects (World3D, region_id) RegionalAuthority and cooperative guards.
## - Blocks completion during active regional transactions / peer site mutations and
##   blocks reentrant economic/completion mutations inside completion callbacks
##   (building_creator_override, child_entered_tree, building_blocker_added, site_completed).
## - Prevents duplicate completion/BuildingInstance while keeping footprint, navigation,
##   existing retry mechanics (without counting transient busy as failure), and distinct
##   regions in the same World3D intact.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const DOMAIN_META := ReservedWithdrawalCoordinator.DOMAIN_META

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


class InvalidInTreeBuilding extends BuildingInstance:
	func is_valid() -> bool:
		return not is_inside_tree() and super.is_valid()


class BackendBuildOrder extends ConstructOrder:
	func start(body: CharacterBody3D, _move: UnitMovement, _nav: WorldNavigation) -> void:
		_unit = body as Unit
		mark_running()
		site.register_worker(_unit, self)

	func physics_update(_move: UnitMovement, _delta: float) -> void:
		pass


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


func _fast_shelter(id: StringName, costs: Dictionary, work_sec: float = 0.5) -> BuildingDefinition:
	var def: BuildingDefinition = SHELTER.duplicate() as BuildingDefinition
	def.definition_id = id
	def.costs = costs
	def.build_work_required_sec = work_sec
	return def


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
	return {
		"main": main,
		"world": main.get_world_3d(),
		"nav": nav,
		"region": nav.get_region_id(),
		"camp": main.get_camp_storage_zone(),
		"manager": main.get_ground_pile_manager(),
		"inventory": main.get_settlement_inventory(),
		"cm": main.get_construction_manager(),
		"sites_root": main.get_construction_sites_root(),
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _supply_and_assemble_site_legacy(
	site: ConstructionSite,
	inv: SettlementInventory,
	manager: GroundPileManager,
	carrier: Unit,
	builder: Unit,
	work_sec: float = 0.5,
	stop_one_step_before_complete: bool = false
) -> void:
	carrier.set_physics_process(false)
	builder.set_physics_process(false)
	var c_order := BackendBuildOrder.new(site)
	var b_order := BackendBuildOrder.new(site)
	carrier.issue_order(c_order)
	builder.issue_order(b_order)
	builder.global_position = site.global_position + Vector3(0.0, 0.0, 2.85)
	var b_idx: int = site.get_builder_slot_index(builder)
	assert_true(site.assign_builder_slot_position(builder, b_idx, builder.global_position))

	var reqs: Dictionary = site.get_required_amounts()
	for res_key: Variant in reqs.keys():
		var res_id: StringName = res_key as StringName
		var left: int = int(reqs[res_id])
		var res_def: ResourceDefinition = WOOD if res_id == &"wood" else STONE
		while left > 0:
			var pile: GroundResourcePile = manager.get_piles_for_resource(res_id)[0]
			var take: int = mini(left, carrier.get_carry_load().get_max_additional_units(res_def))
			var wd: int = inv.withdraw_reserved_from_pile_to_carry_load(pile.pile_id, site.reservation_id, res_def, take, carrier.get_carry_load())
			assert_eq(wd, take)
			site.record_withdrawn_for_site(carrier, res_id, take)
			var acc: Dictionary = site.accept_delivery_from_carry_load(carrier, carrier.get_carry_load())
			assert_eq(int(acc.get(res_id, 0)), take)
			left -= take

	# Ensure builder runs deterministic assembly contribution until COMPLETING (without flushing deferred yet).
	site._rebalance_worker_roles(false)
	var steps: int = maxi(1, ceili(work_sec / 0.25))
	var target_steps: int = maxi(0, steps - 1) if stop_one_step_before_complete else steps
	for _i: int in range(target_steps):
		await wait_physics_frames(1)
		if site.get_site_state() == ConstructionSite.SiteState.COMPLETING:
			break
		var w_res: Dictionary = site.contribute_work(builder, 0.25)
		assert_true(bool(w_res.get("ok", false)), str(w_res))
	if not stop_one_step_before_complete:
		assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETING)


func _make_region_env(parent: Node, region_id: StringName, offset: Vector3, nav: WorldNavigation) -> Dictionary:
	var host := Node3D.new()
	host.name = "C47RegionHost_%s" % String(region_id)
	host.position = offset
	parent.add_child(host)
	host.set_meta(&"region_id", region_id)
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

	var sites_root := Node3D.new()
	sites_root.name = "ConstructionSites"
	host.add_child(sites_root)

	var defs: Dictionary = {&"wood": WOOD, &"stone": STONE}
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

	var cm := ConstructionManager.new()
	host.add_child(cm)
	cm.configure(sites_root, inv, defs, camp, nav, region_id)

	var u1: Unit = UNIT_SCENE.instantiate() as Unit
	u1.name = "U1_%s" % String(region_id)
	u1.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	host.add_child(u1)
	u1.set_world_navigation(nav)
	u1.global_position = nav.snap_to_navmesh(camp.global_position)
	u1.set_meta(&"region_id", region_id)

	var u2: Unit = UNIT_SCENE.instantiate() as Unit
	u2.name = "U2_%s" % String(region_id)
	u2.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	host.add_child(u2)
	u2.set_world_navigation(nav)
	u2.global_position = nav.snap_to_navmesh(camp.global_position)
	u2.set_meta(&"region_id", region_id)

	return {
		"host": host,
		"world": host.get_world_3d(),
		"region": region_id,
		"camp": camp,
		"manager": manager,
		"inventory": inv,
		"cm": cm,
		"sites_root": sites_root,
		"u1": u1,
		"u2": u2,
	}


func test_01_completion_blocked_during_active_regional_tx_and_reentrant_post_commit() -> void:
	var fx: Dictionary = await _boot_main()
	var world: World3D = fx["world"] as World3D
	var region: StringName = fx["region"] as StringName
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var camp: CampStorageZone = fx["camp"] as CampStorageZone
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var leader_a: Unit = fx["leader_a"] as Unit
	var leader_b: Unit = fx["leader_b"] as Unit

	assert_true(inv.deposit(&"wood", 6))
	assert_true(inv.deposit(&"stone", 3))
	var def: BuildingDefinition = _fast_shelter(&"c47_s1", {&"wood": 4, &"stone": 2}, 0.5)
	var created: Dictionary = cm.try_create_site_from_placement(def, SITE_A_POS)
	assert_true(bool(created.get("ok", false)), str(created))
	var site: ConstructionSite = created["site"] as ConstructionSite

	await _supply_and_assemble_site_legacy(site, inv, manager, leader_a, leader_b, 0.5)
	# Unbind Builder/Carrier to free them for provenance peer tx while leaving site in COMPLETING.
	# Disable deferred auto-completion just by setting _queued_completions guard check after we test:
	var rev_ready: int = site.get_transaction_revision()

	# Spawn peer unit with provenance FREE_GATHERED cargo in same region.
	var peer: Unit = UNIT_SCENE.instantiate() as Unit
	peer.name = "PeerGatherer"
	peer.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	(fx["main"] as MainScene).get_node("Units").add_child(peer)
	peer.set_world_navigation(fx["nav"] as WorldNavigation)
	peer.global_position = camp.global_position
	assert_true(peer.get_carry_load().enable_provenance(&"c47_peer"))
	assert_true(bool(CarryFixture.add_lot(peer.get_carry_load(), &"c47_pg", &"c47_pl", &"wood", WOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))

	var probe := {
		"fired": false,
		"reentrant_ret": true,
		"retry_ret": true,
		"state_in_cb": -1,
		"buildings_in_cb": -1,
		"sites_in_cb": -1,
		"retry_cnt_in_cb": -1,
	}
	_watch(peer.get_carry_load().load_changed, func() -> void:
		if bool(probe["fired"]):
			return
		probe["fired"] = true
		probe["reentrant_ret"] = cm.complete_site_transaction(site)
		probe["retry_ret"] = cm.retry_failed_site_completion(site)
		probe["state_in_cb"] = site.get_site_state()
		probe["buildings_in_cb"] = cm.get_completed_buildings().size()
		probe["sites_in_cb"] = cm.get_sites().size()
		probe["retry_cnt_in_cb"] = int(site.get_completion_diagnostic().get("attempts_failed", -1))
	)

	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var camp_res: Dictionary = camp_coord.execute_selective_camp_delivery(inv, camp, peer, region, &"c47_peer_camp", [])
	assert_true(bool(camp_res.get("ok", false)), str(camp_res))
	assert_true(bool(probe["fired"]))

	# Case 1 & 2: During post-commit load_changed (RegionalAuthority.is_executing == true),
	# complete_site_transaction MUST return false without mutating site or burning retry count!
	assert_false(bool(probe["reentrant_ret"]), "complete_site_transaction MUST be refused while RegionalAuthority is executing")
	assert_false(bool(probe["retry_ret"]))
	assert_eq(int(probe["state_in_cb"]), ConstructionSite.SiteState.COMPLETING)
	assert_eq(int(probe["buildings_in_cb"]), 0)
	assert_eq(int(probe["sites_in_cb"]), 1)
	assert_eq(int(probe["retry_cnt_in_cb"]), 0, "Regional busy contention must NOT increment attempts_failed")

	# Also test explicit active authority lock BEFORE completion:
	var auth: ReservedWithdrawalCoordinator.RegionalAuthority = (world.get_meta(DOMAIN_META, {}) as Dictionary).get(region) as ReservedWithdrawalCoordinator.RegionalAuthority
	assert_not_null(auth)
	assert_false(auth.is_executing)
	auth.is_executing = true
	var blocked_explicit: bool = cm.complete_site_transaction(site)
	auth.is_executing = false
	assert_false(blocked_explicit, "Completion must refuse when RegionalAuthority.is_executing == true")
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETING)
	assert_eq(int(site.get_completion_diagnostic().get("attempts_failed", -1)), 0)
	assert_eq(cm.get_completed_buildings().size(), 0)
	assert_true(cm.get_sites().has(site))
	assert_eq(site.get_transaction_revision(), rev_ready)

	# After authority releases, completion succeeds cleanly and clears all guards!
	assert_true(cm.complete_site_transaction(site), "Completion must succeed once RegionalAuthority is idle")
	assert_false(auth.is_executing)
	assert_null(auth.get("active_completion"))
	assert_eq(cm.get_completed_buildings().size(), 1)
	assert_eq(cm.get_sites().size(), 0)
	assert_eq(inv.get_available_amount(&"wood"), 4)
	assert_eq(inv.get_available_amount(&"stone"), 1)
	assert_eq(cm.get_completed_buildings()[0].incorporated_materials, {&"wood": 4, &"stone": 2})


func test_02_reentrant_economic_tx_and_duplicate_completion_blocked_during_completion_callbacks() -> void:
	var fx: Dictionary = await _boot_main()
	var world: World3D = fx["world"] as World3D
	var region: StringName = fx["region"] as StringName
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var camp: CampStorageZone = fx["camp"] as CampStorageZone
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var nav: WorldNavigation = fx["nav"] as WorldNavigation
	var leader_a: Unit = fx["leader_a"] as Unit
	var leader_b: Unit = fx["leader_b"] as Unit

	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var def_a: BuildingDefinition = _fast_shelter(&"c47_s2a", {&"wood": 4, &"stone": 2}, 0.5)
	var def_b: BuildingDefinition = _fast_shelter(&"c47_s2b", {&"wood": 4, &"stone": 2}, 0.5)
	var site_a: ConstructionSite = cm.try_create_site_from_placement(def_a, SITE_A_POS)["site"] as ConstructionSite
	var site_b: ConstructionSite = cm.try_create_site_from_placement(def_b, SITE_B_POS)["site"] as ConstructionSite
	await _supply_and_assemble_site_legacy(site_a, inv, manager, leader_a, leader_b, 0.5)

	# Prepare peer provenance worker ready at camp to test reentrant economic transactions!
	var peer: Unit = UNIT_SCENE.instantiate() as Unit
	peer.name = "PeerReentrant"
	peer.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	(fx["main"] as MainScene).get_node("Units").add_child(peer)
	peer.set_world_navigation(nav)
	peer.global_position = camp.global_position
	assert_true(peer.get_carry_load().enable_provenance(&"c47_peer_re"))
	assert_true(bool(CarryFixture.add_lot(peer.get_carry_load(), &"c47_rg", &"c47_rl", &"wood", WOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))

	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var wd_coord := ReservedWithdrawalCoordinator.new()
	var peer_wood_pile: GroundResourcePile = manager.get_piles_for_resource(&"wood")[0]

	var obs := {
		"factory_camp_ok": true,
		"factory_dup_complete": true,
		"tree_camp_ok": true,
		"tree_pos_matches": false,
		"blocker_camp_ok": true,
		"completed_camp_ok": true,
		"completed_wd_ok": true,
		"completed_dup_complete": true,
		"completed_site_b_work_ok": true,
		"completed_inv_busy": false,
		"completed_storage_locked": false,
		"completed_auth_busy": false,
		"site_completed_count": 0,
	}

	cm.building_creator_override = func(s: ConstructionSite) -> BuildingInstance:
		obs["factory_dup_complete"] = cm.complete_site_transaction(s)
		obs["factory_camp_ok"] = bool(camp_coord.execute_selective_camp_delivery(inv, camp, peer, region, &"c47_re_fac_camp", []).get("ok", false))
		return BuildingInstance.new()

	var buildings_root: Node3D = cm._buildings_root
	_watch(buildings_root.child_entered_tree, func(child: Node) -> void:
		if child is BuildingInstance:
			var b: BuildingInstance = child as BuildingInstance
			obs["tree_pos_matches"] = b.global_position.is_equal_approx(site_a.global_position)
			obs["tree_camp_ok"] = bool(camp_coord.execute_selective_camp_delivery(inv, camp, peer, region, &"c47_re_tree_camp", []).get("ok", false))
	)
	_watch(nav.building_blocker_added, func(_rect: Rect2) -> void:
		obs["blocker_camp_ok"] = bool(camp_coord.execute_selective_camp_delivery(inv, camp, peer, region, &"c47_re_blk_camp", []).get("ok", false))
	)
	_watch(site_a.site_completed, func(s: ConstructionSite, _b: BuildingInstance) -> void:
		obs["site_completed_count"] = int(obs["site_completed_count"]) + 1
		var doms: Dictionary = world.get_meta(DOMAIN_META, {}) as Dictionary
		var auth_now: ReservedWithdrawalCoordinator.RegionalAuthority = doms.get(region) as ReservedWithdrawalCoordinator.RegionalAuthority
		obs["completed_auth_busy"] = auth_now != null and auth_now.is_executing
		obs["completed_inv_busy"] = inv.is_transaction_busy()
		obs["completed_storage_locked"] = manager.is_locked()
		obs["completed_dup_complete"] = cm.complete_site_transaction(s)
		obs["completed_camp_ok"] = bool(camp_coord.execute_selective_camp_delivery(inv, camp, peer, region, &"c47_re_comp_camp", []).get("ok", false))
		obs["completed_wd_ok"] = bool(wd_coord.execute_reserved_withdrawal(site_b, peer, peer_wood_pile.pile_id, &"wood", 1, &"c47_re_wd", &"c47_re_wl").get("ok", false))
		obs["completed_site_b_work_ok"] = bool(site_b.contribute_work(leader_b, 0.1).get("ok", false))
	)

	assert_true(cm.complete_site_transaction(site_a))
	assert_eq(int(obs["site_completed_count"]), 1)
	assert_false(bool(obs["factory_dup_complete"]))
	assert_false(bool(obs["factory_camp_ok"]), "Camp delivery MUST be blocked inside building_creator_override")
	assert_true(bool(obs["tree_pos_matches"]), "Building position must already match site BEFORE child_entered_tree")
	assert_false(bool(obs["tree_camp_ok"]), "Camp delivery MUST be blocked inside child_entered_tree")
	assert_false(bool(obs["blocker_camp_ok"]), "Camp delivery MUST be blocked inside building_blocker_added")
	assert_true(bool(obs["completed_auth_busy"]), "RegionalAuthority.is_executing must be held during site_completed")
	assert_true(bool(obs["completed_inv_busy"]), "Inventory must be locked during site_completed")
	assert_true(bool(obs["completed_storage_locked"]), "GroundPileManager must be locked during site_completed")
	assert_false(bool(obs["completed_dup_complete"]))
	assert_false(bool(obs["completed_camp_ok"]), "Camp delivery MUST be blocked inside site_completed")
	assert_false(bool(obs["completed_wd_ok"]), "ReservedWithdrawal MUST be blocked inside site_completed")
	assert_false(bool(obs["completed_site_b_work_ok"]), "Peer site in same region must be guarded against work during completion")

	# After completion exits, all guards MUST be clear and peer economic tx now succeeds!
	var auth_after: ReservedWithdrawalCoordinator.RegionalAuthority = (world.get_meta(DOMAIN_META, {}) as Dictionary).get(region) as ReservedWithdrawalCoordinator.RegionalAuthority
	assert_not_null(auth_after)
	assert_false(auth_after.is_executing)
	assert_null(auth_after.get("active_completion"))
	assert_false(inv.is_transaction_busy())
	assert_false(manager.is_locked())
	assert_false(site_b.is_transaction_busy())
	assert_eq(cm.get_completed_buildings().size(), 1)
	assert_true(bool(camp_coord.execute_selective_camp_delivery(inv, camp, peer, region, &"c47_post_camp", []).get("ok", false)))
	assert_eq(inv.get_available_amount(&"wood"), 6) # 12 - 4(siteA) - 4(siteB) + 2(peer free) = 6


func test_03_peer_site_busy_blocks_completion_while_distinct_region_completes_independently() -> void:
	var fx: Dictionary = await _boot_main()
	var nav: WorldNavigation = fx["nav"] as WorldNavigation
	var world: World3D = fx["world"] as World3D

	var reg_a: Dictionary = _make_region_env(get_tree().root, &"c47_reg_a", Vector3(0.0, 0.0, 6.0), nav)
	var reg_b: Dictionary = _make_region_env(get_tree().root, &"c47_reg_b", Vector3(6.5, 0.0, 6.0), nav)
	var inv_a: SettlementInventory = reg_a["inventory"] as SettlementInventory
	var mgr_a: GroundPileManager = reg_a["manager"] as GroundPileManager
	var cm_a: ConstructionManager = reg_a["cm"] as ConstructionManager
	var inv_b: SettlementInventory = reg_b["inventory"] as SettlementInventory
	var mgr_b: GroundPileManager = reg_b["manager"] as GroundPileManager
	var cm_b: ConstructionManager = reg_b["cm"] as ConstructionManager

	assert_true(inv_a.deposit(&"wood", 8))
	assert_true(inv_a.deposit(&"stone", 4))
	assert_true(inv_b.deposit(&"wood", 4))
	assert_true(inv_b.deposit(&"stone", 2))

	var def_a1: BuildingDefinition = _fast_shelter(&"c47_ra1", {&"wood": 4, &"stone": 2}, 0.5)
	var def_a2: BuildingDefinition = _fast_shelter(&"c47_ra2", {&"wood": 4, &"stone": 2}, 0.5)
	var def_b1: BuildingDefinition = _fast_shelter(&"c47_rb1", {&"wood": 4, &"stone": 2}, 0.5)

	var res_a1: Dictionary = cm_a.try_create_site_from_placement(def_a1, SITE_A_POS)
	assert_true(bool(res_a1.get("ok", false)), str(res_a1))
	var res_a2: Dictionary = cm_a.try_create_site_from_placement(def_a2, Vector3(-6.0, 0.0, -5.0))
	assert_true(bool(res_a2.get("ok", false)), str(res_a2))
	var res_b1: Dictionary = cm_b.try_create_site_from_placement(def_b1, SITE_B_POS)
	assert_true(bool(res_b1.get("ok", false)), str(res_b1))
	var site_a1: ConstructionSite = res_a1["site"] as ConstructionSite
	var site_a2: ConstructionSite = res_a2["site"] as ConstructionSite
	var site_b1: ConstructionSite = res_b1["site"] as ConstructionSite

	await _supply_and_assemble_site_legacy(site_a1, inv_a, mgr_a, reg_a["u1"] as Unit, reg_a["u2"] as Unit, 0.5, true)
	await _supply_and_assemble_site_legacy(site_b1, inv_b, mgr_b, reg_b["u1"] as Unit, reg_b["u2"] as Unit, 0.5, true)
	await wait_physics_frames(1)
	assert_true(bool(site_a1.contribute_work(reg_a["u2"] as Unit, 0.25).get("completed", false)))
	assert_true(bool(site_b1.contribute_work(reg_b["u2"] as Unit, 0.25).get("completed", false)))
	assert_eq(site_a1.get_site_state(), ConstructionSite.SiteState.COMPLETING)
	assert_eq(site_b1.get_site_state(), ConstructionSite.SiteState.COMPLETING)

	# Case 4: Another site (site_a2) in SAME reg_a has an active transaction (simulated via active work/complement guard) ->
	# completion of site_a1 MUST be blocked without corrupting site_a1!
	site_a2._work_transaction_in_progress = true
	var blocked_by_peer: bool = cm_a.complete_site_transaction(site_a1)
	site_a2._work_transaction_in_progress = false
	assert_false(blocked_by_peer, "Completion must refuse while a peer site in the SAME region is transacting")
	assert_eq(site_a1.get_site_state(), ConstructionSite.SiteState.COMPLETING)
	assert_eq(int(site_a1.get_completion_diagnostic().get("attempts_failed", -1)), 0)
	assert_eq(cm_a.get_completed_buildings().size(), 0)

	# Case 5: Active transaction / completion in reg_a MUST NOT block independent completion in reg_b in the SAME World3D!
	var b_done_during_a := {"ok": false, "res": false}
	_watch(site_a1.site_completed, func(_s: ConstructionSite, _b: BuildingInstance) -> void:
		b_done_during_a["ok"] = true
		b_done_during_a["res"] = cm_b.complete_site_transaction(site_b1)
	)
	assert_true(cm_a.complete_site_transaction(site_a1))
	assert_true(bool(b_done_during_a["ok"]))
	assert_true(bool(b_done_during_a["res"]), "Distinct region reg_b in the SAME World3D must complete independently during reg_a completion")
	assert_eq(cm_a.get_completed_buildings().size(), 1)
	assert_eq(cm_b.get_completed_buildings().size(), 1)

	# Verify separate RegionalAuthorities exist per region without cross-contamination.
	var domains: Dictionary = world.get_meta(DOMAIN_META, {}) as Dictionary
	var auth_a: ReservedWithdrawalCoordinator.RegionalAuthority = domains.get(&"c47_reg_a") as ReservedWithdrawalCoordinator.RegionalAuthority
	var auth_b: ReservedWithdrawalCoordinator.RegionalAuthority = domains.get(&"c47_reg_b") as ReservedWithdrawalCoordinator.RegionalAuthority
	assert_not_null(auth_a)
	assert_not_null(auth_b)
	assert_ne(auth_a, auth_b)
	assert_false(auth_a.is_executing)
	assert_false(auth_b.is_executing)
	assert_eq(auth_a.construction_transfer_serial, 0, "Completion must NOT consume regional transfer serials")
	assert_eq(auth_b.construction_transfer_serial, 0)
	assert_true(auth_a.receipts.is_empty())


func test_04_failure_cleanup_retry_preservation_footprint_and_legacy_navigation() -> void:
	var fx: Dictionary = await _boot_main()
	var world: World3D = fx["world"] as World3D
	var region: StringName = fx["region"] as StringName
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var manager: GroundPileManager = fx["manager"] as GroundPileManager
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var nav: WorldNavigation = fx["nav"] as WorldNavigation
	var leader_a: Unit = fx["leader_a"] as Unit
	var leader_b: Unit = fx["leader_b"] as Unit

	assert_true(inv.deposit(&"wood", 4))
	assert_true(inv.deposit(&"stone", 2))
	var def: BuildingDefinition = _fast_shelter(&"c47_s4", {&"wood": 4, &"stone": 2}, 0.5)
	var site: ConstructionSite = cm.try_create_site_from_placement(def, SITE_A_POS)["site"] as ConstructionSite
	await _supply_and_assemble_site_legacy(site, inv, manager, leader_a, leader_b, 0.5)

	# Case 6 & 7: InvalidInTreeBuilding fails AFTER add_child; then 2 more null failures reach
	# COMPLETION_BLOCKED_ERROR; guards MUST clear on every failure and footprint remain intact!
	var attempts := [0]
	var partial_ids: Array[int] = []
	cm.building_creator_override = func(_s: ConstructionSite) -> Variant:
		attempts[0] += 1
		if attempts[0] == 1:
			var bad := InvalidInTreeBuilding.new()
			partial_ids.append(bad.get_instance_id())
			return bad
		return null

	assert_false(cm.complete_site_transaction(site))
	assert_false(is_instance_id_valid(partial_ids[0]), "Failed in-tree InvalidBuilding must be freed")
	assert_eq(cm._buildings_root.get_child_count(), 0)
	assert_eq(cm.get_completed_buildings().size(), 0)
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETION_FAILED_RETRYABLE)
	assert_true(cm.has_footprint_overlapping_rect(site.get_footprint_rect()), "Footprint must stay occupied by site after completion failure")
	var auth: ReservedWithdrawalCoordinator.RegionalAuthority = (world.get_meta(DOMAIN_META, {}) as Dictionary).get(region) as ReservedWithdrawalCoordinator.RegionalAuthority
	assert_not_null(auth)
	if auth != null:
		assert_false(auth.is_executing, "Guards must clear after in-tree validation failure")
		assert_null(auth.get("active_completion"))
	assert_false(site.is_transaction_busy())
	assert_false(inv.is_transaction_busy())
	assert_false(manager.is_locked())

	# Wait through automatic retries until COMPLETION_BLOCKED_ERROR (attempts == 3)
	assert_true(await _until(func() -> bool: return site.get_site_state() == ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR, 1800))
	assert_eq(attempts[0], 3)
	assert_eq(int(site.get_completion_diagnostic().get("attempts_failed", 0)), 3)
	if auth != null:
		assert_false(auth.is_executing)

	# Calling retry_failed_site_completion while RegionalAuthority is active must refuse safely!
	if auth != null:
		auth.is_executing = true
		assert_false(cm.retry_failed_site_completion(site))
		assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETION_BLOCKED_ERROR)
		auth.is_executing = false

	# Recover with real BuildingInstance and confirm Case 8: footprint, nav blocker + async rebake, stock conservation.
	cm.building_creator_override = Callable()
	assert_true(cm.retry_failed_site_completion(site))
	assert_true(await _until(func() -> bool: return cm.get_completed_buildings().size() == 1, 600))
	var building: BuildingInstance = cm.get_completed_buildings()[0]
	assert_true(building.is_valid())
	assert_eq(building.incorporated_materials, {&"wood": 4, &"stone": 2})
	assert_eq(cm.try_create_site_from_placement(def, SITE_A_POS).get("reason", ""), "building_overlap")
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready() and nav._active_rebake_token == null and nav._pending_building_blockers.is_empty(), 600))
	if auth != null:
		assert_false(auth.is_executing)
	assert_eq(inv.get_available_amount(&"wood"), 0)
	assert_eq(inv.get_available_amount(&"stone"), 0)
