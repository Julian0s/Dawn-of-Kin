class_name TestT362C48SiteCreationAuthority
extends TestCase

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")
## Focused integration suite for T3.6.2-C4.8 (P6-B1):
## Regional transactional boundary for ConstructionManager.try_create_site_from_placement():
## - Normal creation, legacy InMemoryStorageSource compatibility, and economic conservation.
## - Refuses creation during active regional transactions and P6-A completions without mutating state.
## - Blocks reentrancy and tampering during reservation signals, site_creator_override,
##   child_entered_tree, and site_created; releases all guards immediately after return.
## - Silent rollback on override/configure/post-tree failures with zero intermediate signals,
##   zero orphan reservations, and full preservation of peer site reservations.
## - Independent multi-region creation in the same World3D and refusal of incompatible authority bindings.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const DOMAIN_META := ReservedWithdrawalCoordinator.DOMAIN_META

const POS_A := Vector3(-6.0, 0.0, 1.5)
const POS_B := Vector3(-6.0, 0.0, -5.0)
const POS_C := Vector3(0.37, 0.0, -13.19)
const FRAME_LIMIT := 2400

var _active_mains: Array[MainScene] = []
var _extra_nodes: Array[Node] = []
var _extra_managers: Array[GroundPileManager] = []
var _extra_releases: Array[Dictionary] = []
var _connections: Array[Array] = []
var _prior_scale: float = 1.0
var _prior_ticks: int = 60


class FailingConfigureSite extends ConstructionSite:
	func configure(
		_p_site_id: StringName,
		_p_reservation_id: StringName,
		_p_definition: BuildingDefinition,
		_p_inventory: SettlementInventory,
		_p_resource_defs: Dictionary = {},
		_p_region_id: StringName = &"default"
	) -> bool:
		return false


class InvalidInTreeSite extends ConstructionSite:
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


func _until(cond: Callable, limit: int = FRAME_LIMIT) -> bool:
	for _i: int in range(limit):
		if cond.call():
			return true
		await wait_physics_frames(1)
	return cond.call()


func _def(wood_cost: int = 2, stone_cost: int = 1, work_sec: float = 0.25) -> BuildingDefinition:
	var d := SHELTER.duplicate() as BuildingDefinition
	d.costs = {&"wood": wood_cost, &"stone": stone_cost}
	d.build_work_required_sec = work_sec
	return d


func _spawn_main() -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(1280, 720)
	add_test_child(vp)

	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	vp.add_child(main)
	_active_mains.append(main)

	var nav: WorldNavigation = main.get_test_map().get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 180))
	await wait_physics_frames(2)

	var units: Array[Unit] = main.get_units()
	return {
		"vp": vp,
		"main": main,
		"world": main.get_test_map().get_world_3d(),
		"nav": nav,
		"cm": main.get_construction_manager(),
		"sites_root": main.get_construction_sites_root(),
		"inventory": main.get_settlement_inventory(),
		"storage": main.get_ground_pile_manager(),
		"camp": main.get_camp_storage_zone(),
		"units": units,
	}


func _prepare_provenance_unit(u: Unit, prov_id: StringName) -> UnitCarryLoad:
	var load: UnitCarryLoad = u.get_carry_load()
	if not load.is_provenance_enabled():
		assert_true(load.enable_provenance(prov_id))
	return load


func _create_second_region_in_world(
	main: MainScene,
	world: World3D,
	region_id: StringName,
	camp_pos: Vector3
) -> Dictionary:
	var host := Node3D.new()
	host.name = "RegionHost_%s" % String(region_id)
	main.add_child(host)
	_extra_nodes.append(host)

	var camp := CampStorageZone.new()
	camp.zone_id = StringName("camp_%s" % String(region_id))
	camp.position = camp_pos
	camp.zone_bounds_half_extents = Vector2(3.0, 3.0)
	camp.slot_spacing = 1.2
	camp.min_pile_clearance = 0.85
	camp.max_pile_amount = 20
	host.add_child(camp)

	var piles_root := Node3D.new()
	piles_root.name = "Piles_%s" % String(region_id)
	host.add_child(piles_root)

	var sites_root := Node3D.new()
	sites_root.name = "Sites_%s" % String(region_id)
	host.add_child(sites_root)

	var defs: Dictionary = {
		&"wood": WOOD.duplicate(),
		&"stone": STONE.duplicate(),
	}
	var storage := GroundPileManager.new(defs, camp, piles_root, SimulatedWorldTimeProvider.new(0.0))
	var owner_token := RefCounted.new()
	assert_true(storage.bind_domain_owner(owner_token))
	_extra_managers.append(storage)
	_extra_releases.append({"world": world, "region": region_id, "storage": storage, "token": owner_token})

	var inventory := SettlementInventory.new(storage)
	var cm := ConstructionManager.new()
	cm.name = "CM_%s" % String(region_id)
	host.add_child(cm)
	cm.configure(sites_root, inventory, defs, camp, null, region_id)

	return {
		"host": host,
		"camp": camp,
		"piles_root": piles_root,
		"sites_root": sites_root,
		"storage": storage,
		"inventory": inventory,
		"cm": cm,
		"region": region_id,
	}


func _supply_and_assemble_to_completing(
	site: ConstructionSite,
	inventory: SettlementInventory,
	builder: Unit
) -> void:
	builder.set_physics_process(false)
	builder.global_position = site.global_position + Vector3(0.0, 0.0, 2.85)
	var load := builder.get_carry_load()
	var req_wood: int = site.get_required_amount(&"wood")
	var req_stone: int = site.get_required_amount(&"stone")
	if req_wood > 0:
		assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(
			inventory.get_reserved_pile_entries(site.reservation_id, &"wood")[0]["pile_id"] as int,
			site.reservation_id, WOOD, req_wood, load), req_wood)
		site.record_withdrawn_for_site(builder, &"wood", req_wood)
	if req_stone > 0:
		assert_eq(inventory.withdraw_reserved_from_pile_to_carry_load(
			inventory.get_reserved_pile_entries(site.reservation_id, &"stone")[0]["pile_id"] as int,
			site.reservation_id, STONE, req_stone, load), req_stone)
		site.record_withdrawn_for_site(builder, &"stone", req_stone)
	assert_false(site.accept_delivery_from_carry_load(builder, load).is_empty())

	builder.issue_order(BackendBuildOrder.new(site))
	assert_true(site.try_promote_solo_to_builder(builder))
	var b_idx: int = site.get_builder_slot_index(builder)
	assert_true(site.assign_builder_slot_position(builder, b_idx, builder.global_position))
	var steps: int = 0
	while site.get_site_state() == ConstructionSite.SiteState.ACTIVE and steps < 20:
		await wait_physics_frames(1)
		site.contribute_work(builder, 0.25)
		steps += 1
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETING)


## 1. Normal creation, peer reservation preservation, legacy InMemoryStorageSource compatibility,
##    and zero-mutation conservation on rejected placements.
func test_01_normal_creation_legacy_compat_and_conservation() -> void:
	var fx: Dictionary = await _spawn_main()
	var world: World3D = fx["world"] as World3D
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var storage: GroundPileManager = fx["storage"] as GroundPileManager
	var camp: CampStorageZone = fx["camp"] as CampStorageZone

	assert_true(inv.deposit(&"wood", 10))
	assert_true(inv.deposit(&"stone", 6))

	var signal_log: Array[String] = []
	var observed_coherence: Array[bool] = []
	_watch(storage.reservations_changed, func() -> void:
		signal_log.append("storage_res")
		observed_coherence.append(cm.get_sites().size() >= 1 and cm.get_sites()[-1].is_valid())
	)
	_watch(inv.reservations_changed, func() -> void:
		signal_log.append("inv_res")
		observed_coherence.append(cm.get_sites().size() >= 1 and cm.get_sites()[-1].is_valid())
	)
	_watch(inv.inventory_changed, func() -> void:
		signal_log.append("inv_chg")
		observed_coherence.append(cm.get_sites().size() >= 1 and cm.get_sites()[-1].is_valid())
	)
	_watch(cm.site_created, func(s: ConstructionSite) -> void:
		signal_log.append("site_created")
		observed_coherence.append(s.is_valid() and cm.get_sites().has(s) and inv.has_reservation(s.reservation_id))
	)

	var def_a := _def(4, 2)
	var res_a: Dictionary = cm.try_create_site_from_placement(def_a, POS_A)
	assert_true(bool(res_a["ok"]), str(res_a))
	var site_a: ConstructionSite = res_a["site"] as ConstructionSite
	assert_not_null(site_a)
	assert_true(site_a.is_valid())
	assert_eq(site_a.get_site_state(), ConstructionSite.SiteState.ACTIVE)
	assert_eq(inv.get_physical_amount(&"wood"), 10)
	assert_eq(inv.get_reserved_amount(&"wood"), 4)
	assert_eq(inv.get_available_amount(&"wood"), 6)
	assert_eq(inv.get_reserved_amount(&"stone"), 2)
	assert_eq(site_a.get_consumed_amount(&"wood"), 0)
	assert_eq(site_a.get_delivered_buffer_amount(&"wood"), 0)
	assert_false(world.has_meta(DOMAIN_META), "Normal legacy creation must not materialize RegionalAuthority")
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, cm.get_region_id()))
	assert_false(inv.is_transaction_busy())
	assert_false(storage.is_locked())
	assert_false(camp.is_transaction_locked())
	assert_false(site_a.is_transaction_busy())
	assert_eq(signal_log.count("site_created"), 1)
	assert_eq(signal_log.count("inv_res"), 1)
	assert_eq(signal_log.count("inv_chg"), 1)
	for ok_obs: bool in observed_coherence:
		assert_true(ok_obs, "Every post-commit observer must see coherent site + reservation")

	# Second creation preserves Site A reservations and rejects insufficient / camp overlap with zero mutations.
	var res_b: Dictionary = cm.try_create_site_from_placement(_def(3, 2), POS_B)
	assert_true(bool(res_b["ok"]), str(res_b))
	var site_b: ConstructionSite = res_b["site"] as ConstructionSite
	assert_eq(inv.get_reservation_amounts(site_a.reservation_id), {&"wood": 4, &"stone": 2})
	assert_eq(inv.get_reservation_amounts(site_b.reservation_id), {&"wood": 3, &"stone": 2})

	var rev_inv_before: int = inv.get_transaction_revision()
	var rev_storage_before: int = storage.get_transaction_revision()
	var ledger_before: int = storage.get_pile_ledger_revision()
	var rej_insuff: Dictionary = cm.try_create_site_from_placement(_def(10, 1), POS_C)
	assert_false(bool(rej_insuff["ok"]))
	assert_eq(rej_insuff["reason"], "insufficient_resources")
	var rej_camp: Dictionary = cm.try_create_site_from_placement(_def(1, 1), camp.get_anchor_position())
	assert_false(bool(rej_camp["ok"]))
	assert_eq(rej_camp["reason"], "camp_overlap")
	assert_eq(inv.get_transaction_revision(), rev_inv_before)
	assert_eq(storage.get_transaction_revision(), rev_storage_before)
	assert_eq(storage.get_pile_ledger_revision(), ledger_before)
	assert_eq(cm.get_sites().size(), 2)

	# Legacy InMemoryStorageSource compatibility + silent rollback on configure failure.
	var mem_host := Node3D.new()
	fx["main"].add_child(mem_host)
	_extra_nodes.append(mem_host)
	var mem_sites := Node3D.new()
	mem_host.add_child(mem_sites)
	var mem_source := InMemoryStorageSource.new()
	var mem_inv := SettlementInventory.new(mem_source)
	assert_true(mem_inv.deposit(&"wood", 6))
	assert_true(mem_inv.deposit(&"stone", 4))
	var mem_cm := ConstructionManager.new()
	mem_host.add_child(mem_cm)
	mem_cm.configure(mem_sites, mem_inv, {&"wood": WOOD.duplicate(), &"stone": STONE.duplicate()}, null, null, &"mem_legacy_c48")

	var mem_signals: Array[String] = []
	_watch(mem_inv.reservations_changed, func() -> void:
		mem_signals.append("mem_res")
		assert_false(mem_inv.release_batch(&"res_site_mem_legacy_c48_0001"), "Observer during InMemory reservation signal must not release")
	)
	var mem_ok: Dictionary = mem_cm.try_create_site_from_placement(_def(2, 1), Vector3(12.0, 0.0, 12.0))
	assert_true(bool(mem_ok["ok"]), str(mem_ok))
	assert_eq(mem_inv.get_reserved_amount(&"wood"), 2)
	assert_eq(mem_signals.size(), 1)

	mem_signals.clear()
	mem_cm.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		return FailingConfigureSite.new()
	var mem_fail: Dictionary = mem_cm.try_create_site_from_placement(_def(2, 1), Vector3(18.0, 0.0, 12.0))
	assert_false(bool(mem_fail["ok"]))
	assert_eq(mem_fail["reason"], "site_instantiation_failed")
	assert_eq(mem_signals.size(), 0, "Failed InMemory creation must not emit intermediate reservation signals")
	assert_eq(mem_inv.get_reserved_amount(&"wood"), 2)
	assert_eq(mem_inv.get_available_amount(&"wood"), 4)
	assert_false(mem_inv.is_transaction_busy())


## 2. Refusal during active regional economic transactions (camp delivery / reserved withdrawal)
##    and during P6-A construction completion without mutating state or corrupting T3.4.4 overlap contract.
func test_02_blocked_during_active_regional_tx_and_completion_p6a() -> void:
	var fx: Dictionary = await _spawn_main()
	var world: World3D = fx["world"] as World3D
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var storage: GroundPileManager = fx["storage"] as GroundPileManager
	var camp: CampStorageZone = fx["camp"] as CampStorageZone
	var units: Array[Unit] = fx["units"] as Array[Unit]

	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 8))

	# A. Active SelectiveCampDeliveryCoordinator transaction in same (World3D, region_id).
	var u0: Unit = units[0]
	var load0 := _prepare_provenance_unit(u0, &"c48_camp_carrier")
	assert_true(bool(CarryFixture.add_lot(load0,
		&"c48_add_free_1", &"c48_free_lot_1", &"wood", WOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED
	).get("ok", false)))
	u0.global_position = camp.get_anchor_position() + Vector3(1.0, 0.0, 0.0)

	var probe := {
		"camp_tx_reject": {},
		"created_during_tx": 0,
		"wd_tx_reject": {},
		"create_in_override": {},
		"create_in_completed_free": {},
		"create_in_completed_overlap": {},
	}
	var rejected_during_tx: Array[String] = []
	_watch(cm.site_created, func(_s: ConstructionSite) -> void: probe["created_during_tx"] = int(probe["created_during_tx"]) + 1)
	_watch(cm.site_creation_rejected, func(r: String, _m: String, _d: BuildingDefinition, _p: Vector3) -> void:
		rejected_during_tx.append(r)
	)
	_watch(load0.load_changed, func() -> void:
		if (probe["camp_tx_reject"] as Dictionary).is_empty():
			probe["camp_tx_reject"] = cm.try_create_site_from_placement(_def(2, 1), POS_A)
	)
	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var camp_res: Dictionary = camp_coord.execute_selective_camp_delivery(
		inv, camp, u0, cm.get_region_id(), &"c48_op_camp_1", []
	)
	assert_true(bool(camp_res["ok"]), str(camp_res))
	var camp_tx_reject: Dictionary = probe["camp_tx_reject"] as Dictionary
	assert_false(bool(camp_tx_reject.get("ok", true)), "Site creation during active camp delivery must be refused")
	assert_eq(String(camp_tx_reject.get("reason", "")), "busy")
	assert_eq(int(probe["created_during_tx"]), 0)
	assert_eq(rejected_during_tx, ["busy"])
	assert_eq(cm.get_sites().size(), 0)
	assert_eq(inv.get_reserved_amount(&"wood"), 0)
	assert_eq(inv.get_physical_amount(&"wood"), 14)

	# B. Active ReservedWithdrawalCoordinator transaction on Site A blocks creating Site B.
	var site_a_res: Dictionary = cm.try_create_site_from_placement(_def(2, 1), POS_A)
	assert_true(bool(site_a_res["ok"]), str(site_a_res))
	var site_a: ConstructionSite = site_a_res["site"] as ConstructionSite
	var entries: Array[Dictionary] = inv.get_reserved_pile_entries(site_a.reservation_id, &"wood")
	assert_false(entries.is_empty())
	var pile_id: int = int(entries[0]["pile_id"])
	u0.global_position = (entries[0]["pile"] as GroundResourcePile).global_position
	var wd_order := BackendBuildOrder.new(site_a)
	u0.issue_order(wd_order)
	assert_eq(site_a.claim_pickup(u0, pile_id, &"wood", 2), 2)

	_watch(load0.load_changed, func() -> void:
		if (probe["wd_tx_reject"] as Dictionary).is_empty():
			probe["wd_tx_reject"] = cm.try_create_site_from_placement(_def(2, 1), POS_B)
	)
	var wd_coord := ReservedWithdrawalCoordinator.new()
	var wd_res: Dictionary = wd_coord.execute_reserved_withdrawal(
		site_a, u0, pile_id, &"wood", 2, &"c48_op_wd_1", &"c48_lot_wd_1"
	)
	assert_true(bool(wd_res["ok"]), str(wd_res))
	var wd_tx_reject: Dictionary = probe["wd_tx_reject"] as Dictionary
	assert_false(bool(wd_tx_reject.get("ok", true)), "Site creation during active withdrawal must be refused")
	assert_eq(String(wd_tx_reject.get("reason", "")), "busy")
	assert_eq(cm.get_sites().size(), 1)
	assert_eq(inv.get_reservation_amounts(site_a.reservation_id), {&"stone": 1})

	# C. Active P6-A completion blocks non-overlapping creation with "busy",
	#    while overlapping creation during site_completed still reports "building_overlap".
	var site_c_res: Dictionary = cm.try_create_site_from_placement(_def(2, 1, 0.25), POS_C)
	assert_true(bool(site_c_res["ok"]), str(site_c_res))
	var site_c: ConstructionSite = site_c_res["site"] as ConstructionSite
	var u1: Unit = units[1]
	await _supply_and_assemble_to_completing(site_c, inv, u1)

	cm.building_creator_override = func(_s: ConstructionSite) -> BuildingInstance:
		probe["create_in_override"] = cm.try_create_site_from_placement(_def(2, 1), POS_B)
		return BuildingInstance.new()
	_watch(site_c.site_completed, func(done: ConstructionSite, _b: BuildingInstance) -> void:
		probe["create_in_completed_free"] = cm.try_create_site_from_placement(_def(2, 1), POS_B)
		probe["create_in_completed_overlap"] = cm.try_create_site_from_placement(_def(2, 1), done.global_position)
	)
	assert_true(cm.complete_site_transaction(site_c))
	cm.building_creator_override = Callable()

	var create_in_override: Dictionary = probe["create_in_override"] as Dictionary
	var create_in_completed_free: Dictionary = probe["create_in_completed_free"] as Dictionary
	var create_in_completed_overlap: Dictionary = probe["create_in_completed_overlap"] as Dictionary
	assert_false(bool(create_in_override.get("ok", true)))
	assert_eq(String(create_in_override.get("reason", "")), "busy")
	assert_false(bool(create_in_completed_free.get("ok", true)))
	assert_eq(String(create_in_completed_free.get("reason", "")), "busy")
	assert_false(bool(create_in_completed_overlap.get("ok", true)))
	assert_eq(String(create_in_completed_overlap.get("reason", "")), "building_overlap")
	assert_eq(cm.get_completed_buildings().size(), 1)
	assert_eq(cm.get_sites().size(), 1)

	# After completion releases guards, creating at POS_B succeeds cleanly.
	var post_ok: Dictionary = cm.try_create_site_from_placement(_def(2, 1), POS_B)
	assert_true(bool(post_ok["ok"]), str(post_ok))
	assert_eq(cm.get_sites().size(), 2)


## 3. Reentrancy and tampering blocked at every callback point:
##    site_creator_override, child_entered_tree, reservation/storage signals, and site_created;
##    guards released immediately after return.
func test_03_reentrancy_in_reservation_override_tree_and_site_created() -> void:
	var fx: Dictionary = await _spawn_main()
	var world: World3D = fx["world"] as World3D
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var sites_root: Node3D = fx["sites_root"] as Node3D
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var storage: GroundPileManager = fx["storage"] as GroundPileManager
	var camp: CampStorageZone = fx["camp"] as CampStorageZone
	var units: Array[Unit] = fx["units"] as Array[Unit]

	assert_true(inv.deposit(&"wood", 14))
	assert_true(inv.deposit(&"stone", 8))

	# Create an existing peer site (Site Peer) to test peer protection and reentrant withdrawal/completion.
	var peer_res: Dictionary = cm.try_create_site_from_placement(_def(2, 1, 0.25), POS_C)
	assert_true(bool(peer_res["ok"]), str(peer_res))
	var peer_site: ConstructionSite = peer_res["site"] as ConstructionSite
	var u0: Unit = units[0]
	var load0 := _prepare_provenance_unit(u0, &"c48_reentry_worker")
	var peer_entries: Array[Dictionary] = inv.get_reserved_pile_entries(peer_site.reservation_id, &"wood")
	var peer_pile_id: int = int(peer_entries[0]["pile_id"])
	u0.global_position = (peer_entries[0]["pile"] as GroundResourcePile).global_position
	u0.issue_order(BackendBuildOrder.new(peer_site))
	assert_eq(peer_site.claim_pickup(u0, peer_pile_id, &"wood", 1), 1)

	# Create a second peer ready for completion to confirm completion is blocked during site creation.
	var comp_res: Dictionary = cm.try_create_site_from_placement(_def(2, 1, 0.25), Vector3(6.0, 0.0, 5.0))
	assert_true(bool(comp_res["ok"]), str(comp_res))
	var comp_site: ConstructionSite = comp_res["site"] as ConstructionSite
	await _supply_and_assemble_to_completing(comp_site, inv, units[1])
	# Prevent deferred auto-completion before our test assertion by keeping comp_site COMPLETING only if not yet completed.
	# Wait: _supply_and_assemble_to_completing just left comp_site in COMPLETING before deferred runs!

	var signals_seen: Array[String] = []
	var override_checks: Dictionary = {}
	var tree_checks: Dictionary = {}
	var inv_res_checks: Dictionary = {}
	var storage_res_checks: Dictionary = {}
	var site_created_checks: Dictionary = {}
	var target_def := _def(3, 2)
	var probe_flag := {"active": true}

	cm.site_creator_override = func(sid: StringName, rid: StringName, d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		if not bool(probe_flag["active"]):
			return ConstructionSite.new()
		override_checks["signals_before"] = signals_seen.duplicate()
		override_checks["region_active"] = ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, cm.get_region_id())
		override_checks["removal_check"] = ReservedWithdrawalCoordinator.inspect_domain_for_worker_removal_readonly(
			world, cm.get_region_id(), storage, camp
		)
		override_checks["peer_busy"] = peer_site.is_transaction_busy()
		override_checks["double_same"] = cm.try_create_site_from_placement(d, POS_A)
		override_checks["double_other"] = cm.try_create_site_from_placement(d, POS_B)
		override_checks["inv_release"] = inv.release_batch(rid)
		override_checks["inv_withdraw"] = inv.withdraw_reserved(rid, &"wood", 1)
		override_checks["inv_complement"] = inv.complement_reservation(rid, {&"wood": 1})
		override_checks["storage_release"] = storage.release_batch(rid)
		override_checks["storage_withdraw"] = storage.withdraw_reserved(rid, &"wood", 1)
		override_checks["reentrant_wd"] = ReservedWithdrawalCoordinator.new().execute_reserved_withdrawal(
			peer_site, u0, peer_pile_id, &"wood", 1, &"c48_reent_wd_1", &"c48_reent_lot_1"
		)
		override_checks["reentrant_complete"] = cm.complete_site_transaction(comp_site)
		override_checks["sid"] = sid
		override_checks["rid"] = rid
		return ConstructionSite.new()

	_watch(sites_root.child_entered_tree, func(child: Node) -> void:
		if not bool(probe_flag["active"]) or not (child is ConstructionSite) or not tree_checks.is_empty():
			return
		var s: ConstructionSite = child as ConstructionSite
		tree_checks["signals_before"] = signals_seen.duplicate()
		tree_checks["is_valid"] = s.is_valid()
		tree_checks["site_id"] = s.site_id
		tree_checks["reservation_id"] = s.reservation_id
		tree_checks["busy_self"] = s.is_transaction_busy()
		tree_checks["double_other"] = cm.try_create_site_from_placement(target_def, POS_B)
		tree_checks["inv_release"] = inv.release_batch(s.reservation_id)
		tree_checks["inv_withdraw"] = inv.withdraw_reserved(s.reservation_id, &"wood", 1)
		tree_checks["reentrant_wd"] = ReservedWithdrawalCoordinator.new().execute_reserved_withdrawal(
			peer_site, u0, peer_pile_id, &"wood", 1, &"c48_reent_wd_2", &"c48_reent_lot_2"
		)
	)

	_watch(storage.reservations_changed, func() -> void:
		if not bool(probe_flag["active"]):
			return
		signals_seen.append("storage_res")
		if storage_res_checks.is_empty():
			var s_found: ConstructionSite = cm.get_site_by_id(override_checks.get("sid", &"") as StringName)
			storage_res_checks["site_registered"] = s_found != null and s_found.is_valid()
			storage_res_checks["double_same"] = cm.try_create_site_from_placement(target_def, POS_A)
			storage_res_checks["double_other"] = cm.try_create_site_from_placement(target_def, POS_B)
			storage_res_checks["inv_release"] = inv.release_batch(override_checks.get("rid", &"") as StringName)
	)

	_watch(inv.reservations_changed, func() -> void:
		if not bool(probe_flag["active"]):
			return
		signals_seen.append("inv_res")
		if inv_res_checks.is_empty():
			var s_found: ConstructionSite = cm.get_site_by_id(override_checks.get("sid", &"") as StringName)
			inv_res_checks["site_registered"] = s_found != null and s_found.is_valid()
			inv_res_checks["double_same"] = cm.try_create_site_from_placement(target_def, POS_A)
			inv_res_checks["double_other"] = cm.try_create_site_from_placement(target_def, POS_B)
			inv_res_checks["inv_release"] = inv.release_batch(override_checks.get("rid", &"") as StringName)
			inv_res_checks["reentrant_wd"] = ReservedWithdrawalCoordinator.new().execute_reserved_withdrawal(
				peer_site, u0, peer_pile_id, &"wood", 1, &"c48_reent_wd_3", &"c48_reent_lot_3"
			)
	)

	_watch(cm.site_created, func(s: ConstructionSite) -> void:
		if not bool(probe_flag["active"]):
			return
		signals_seen.append("site_created")
		if site_created_checks.is_empty():
			site_created_checks["is_valid"] = s.is_valid()
			site_created_checks["registered"] = cm.get_sites().has(s)
			site_created_checks["res_match"] = inv.get_reservation_amounts(s.reservation_id) == {&"wood": 3, &"stone": 2}
			site_created_checks["region_active"] = ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, cm.get_region_id())
			site_created_checks["double_same"] = cm.try_create_site_from_placement(target_def, POS_A)
			site_created_checks["double_other"] = cm.try_create_site_from_placement(target_def, POS_B)
			site_created_checks["inv_release"] = inv.release_batch(s.reservation_id)
			site_created_checks["reentrant_wd"] = ReservedWithdrawalCoordinator.new().execute_reserved_withdrawal(
				peer_site, u0, peer_pile_id, &"wood", 1, &"c48_reent_wd_4", &"c48_reent_lot_4"
			)
			site_created_checks["reentrant_complete"] = cm.complete_site_transaction(comp_site)
	)

	var create_res: Dictionary = cm.try_create_site_from_placement(target_def, POS_A)
	probe_flag["active"] = false
	cm.site_creator_override = Callable()

	assert_true(bool(create_res["ok"]), str(create_res))
	var created_site: ConstructionSite = create_res["site"] as ConstructionSite
	assert_not_null(created_site)
	assert_true(created_site.is_valid())

	# Verify override checks
	assert_eq(override_checks.get("signals_before"), [], "No reservation/site signals before commit (override)")
	assert_true(bool(override_checks.get("region_active", false)))
	assert_eq(String((override_checks.get("removal_check", {}) as Dictionary).get("reason", "")), "regional_transaction_active")
	assert_true(bool(override_checks.get("peer_busy", false)))
	assert_false(bool((override_checks.get("double_same", {}) as Dictionary).get("ok", true)))
	assert_false(bool((override_checks.get("double_other", {}) as Dictionary).get("ok", true)))
	assert_eq(String((override_checks.get("double_other", {}) as Dictionary).get("reason", "")), "busy")
	assert_false(bool(override_checks.get("inv_release", true)))
	assert_false(bool(override_checks.get("inv_withdraw", true)))
	assert_false(bool(override_checks.get("inv_complement", true)))
	assert_false(bool(override_checks.get("storage_release", true)))
	assert_false(bool(override_checks.get("storage_withdraw", true)))
	assert_eq(String((override_checks.get("reentrant_wd", {}) as Dictionary).get("reason", "")), "busy")
	assert_false(bool(override_checks.get("reentrant_complete", true)))

	# Verify child_entered_tree checks
	assert_eq(tree_checks.get("signals_before"), [], "No reservation/site signals before commit (child_entered_tree)")
	assert_true(bool(tree_checks.get("is_valid", false)), "Site entering tree must already be configured and valid")
	assert_eq(tree_checks.get("site_id"), created_site.site_id)
	assert_eq(tree_checks.get("reservation_id"), created_site.reservation_id)
	assert_true(bool(tree_checks.get("busy_self", false)))
	assert_eq(String((tree_checks.get("double_other", {}) as Dictionary).get("reason", "")), "busy")
	assert_false(bool(tree_checks.get("inv_release", true)))
	assert_false(bool(tree_checks.get("inv_withdraw", true)))
	assert_eq(String((tree_checks.get("reentrant_wd", {}) as Dictionary).get("reason", "")), "busy")

	# Verify reservation signal checks
	assert_true(bool(storage_res_checks.get("site_registered", false)), "Site must already be registered when storage.reservations_changed fires")
	assert_eq(String((storage_res_checks.get("double_same", {}) as Dictionary).get("reason", "")), "site_overlap")
	assert_eq(String((storage_res_checks.get("double_other", {}) as Dictionary).get("reason", "")), "busy")
	assert_false(bool(storage_res_checks.get("inv_release", true)))

	assert_true(bool(inv_res_checks.get("site_registered", false)), "Site must already be registered when inventory.reservations_changed fires")
	assert_eq(String((inv_res_checks.get("double_same", {}) as Dictionary).get("reason", "")), "site_overlap")
	assert_eq(String((inv_res_checks.get("double_other", {}) as Dictionary).get("reason", "")), "busy")
	assert_false(bool(inv_res_checks.get("inv_release", true)))
	assert_eq(String((inv_res_checks.get("reentrant_wd", {}) as Dictionary).get("reason", "")), "busy")

	# Verify site_created checks
	assert_true(bool(site_created_checks.get("is_valid", false)))
	assert_true(bool(site_created_checks.get("registered", false)))
	assert_true(bool(site_created_checks.get("res_match", false)))
	assert_true(bool(site_created_checks.get("region_active", false)))
	assert_eq(String((site_created_checks.get("double_same", {}) as Dictionary).get("reason", "")), "site_overlap")
	assert_eq(String((site_created_checks.get("double_other", {}) as Dictionary).get("reason", "")), "busy")
	assert_false(bool(site_created_checks.get("inv_release", true)))
	assert_eq(String((site_created_checks.get("reentrant_wd", {}) as Dictionary).get("reason", "")), "busy")
	assert_false(bool(site_created_checks.get("reentrant_complete", true)))

	# Verify post-return guard release & subsequent operations succeed cleanly.
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, cm.get_region_id()))
	assert_false(created_site.is_transaction_busy())
	assert_false(peer_site.is_transaction_busy())
	assert_false(inv.is_transaction_busy())
	assert_false(storage.is_locked())
	assert_false(camp.is_transaction_locked())
	assert_eq(inv.get_reservation_amounts(created_site.reservation_id), {&"wood": 3, &"stone": 2})
	assert_eq(inv.get_reservation_amounts(peer_site.reservation_id), {&"wood": 2, &"stone": 1})
	assert_eq(load0.get_amount(&"wood"), 0, "Blocked reentrant withdrawals must not move wood")

	# Duplicate footprint after return -> site_overlap; distinct spot POS_B -> ok!
	var dup_after: Dictionary = cm.try_create_site_from_placement(target_def, POS_A)
	assert_false(bool(dup_after["ok"]))
	assert_eq(dup_after["reason"], "site_overlap")
	var second_ok: Dictionary = cm.try_create_site_from_placement(_def(2, 1), POS_B)
	assert_true(bool(second_ok["ok"]), str(second_ok))
	# Wait for deferred completion of comp_site to finish cleanly without errors.
	assert_true(await _until(func() -> bool: return cm.get_completed_buildings().size() == 1, 240))


## 4. Failure rollback (null override, failing configure, invalid-in-tree site, hostile existing site):
##    zero intermediate signals, zero orphan reservations, zero node leaks, exact peer preservation.
func test_04_failures_rollback_zero_intermediate_signals_and_peer_preservation() -> void:
	var fx: Dictionary = await _spawn_main()
	var world: World3D = fx["world"] as World3D
	var cm: ConstructionManager = fx["cm"] as ConstructionManager
	var sites_root: Node3D = fx["sites_root"] as Node3D
	var inv: SettlementInventory = fx["inventory"] as SettlementInventory
	var storage: GroundPileManager = fx["storage"] as GroundPileManager
	var camp: CampStorageZone = fx["camp"] as CampStorageZone

	assert_true(inv.deposit(&"wood", 10))
	assert_true(inv.deposit(&"stone", 6))

	var peer_res: Dictionary = cm.try_create_site_from_placement(_def(2, 1), POS_C)
	assert_true(bool(peer_res["ok"]), str(peer_res))
	var peer_site: ConstructionSite = peer_res["site"] as ConstructionSite

	var intermediate_signals: Array[String] = []
	var rejected_reasons: Array[String] = []
	_watch(storage.reservations_changed, func() -> void: intermediate_signals.append("storage_res"))
	_watch(storage.storage_changed, func() -> void: intermediate_signals.append("storage_chg"))
	_watch(inv.reservations_changed, func() -> void: intermediate_signals.append("inv_res"))
	_watch(inv.inventory_changed, func() -> void: intermediate_signals.append("inv_chg"))
	_watch(cm.site_created, func(_s: ConstructionSite) -> void: intermediate_signals.append("site_created"))
	_watch(cm.site_creation_rejected, func(r: String, _m: String, _d: BuildingDefinition, _p: Vector3) -> void:
		rejected_reasons.append(r)
	)

	var inv_rev_0: int = inv.get_transaction_revision()
	var storage_rev_0: int = storage.get_transaction_revision()
	var ledger_rev_0: int = storage.get_pile_ledger_revision()
	var peer_rev_0: int = peer_site.get_transaction_revision()
	var children_0: int = sites_root.get_child_count()

	# A. site_creator_override returns null
	cm.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> Variant:
		return null
	var r_null: Dictionary = cm.try_create_site_from_placement(_def(3, 2), POS_A)
	assert_false(bool(r_null["ok"]))
	assert_eq(r_null["reason"], "site_instantiation_failed")

	# B. site.configure() returns false (never even enters tree)
	cm.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		return FailingConfigureSite.new()
	var r_cfg: Dictionary = cm.try_create_site_from_placement(_def(3, 2), POS_A)
	assert_false(bool(r_cfg["ok"]))
	assert_eq(r_cfg["reason"], "site_instantiation_failed")

	# C. Post-tree validation failure (InvalidInTreeSite fails is_valid() after entering _sites_root)
	cm.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		return InvalidInTreeSite.new()
	var r_tree: Dictionary = cm.try_create_site_from_placement(_def(3, 2), POS_A)
	assert_false(bool(r_tree["ok"]))
	assert_eq(r_tree["reason"], "site_instantiation_failed")

	# D. Hostile override returning already-registered peer_site must NEVER free peer_site!
	cm.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		return peer_site
	var r_hostile: Dictionary = cm.try_create_site_from_placement(_def(3, 2), POS_A)
	assert_false(bool(r_hostile["ok"]))
	assert_eq(r_hostile["reason"], "site_instantiation_failed")
	cm.site_creator_override = Callable()

	assert_eq(intermediate_signals, [], "Failed creations must emit ZERO intermediate reservation/storage/site_created signals")
	assert_eq(rejected_reasons, [
		"site_instantiation_failed",
		"site_instantiation_failed",
		"site_instantiation_failed",
		"site_instantiation_failed",
	])
	assert_eq(inv.get_transaction_revision(), inv_rev_0, "Failed creations must not drift inventory revision")
	assert_eq(storage.get_transaction_revision(), storage_rev_0, "Failed creations must not drift storage revision")
	assert_eq(storage.get_pile_ledger_revision(), ledger_rev_0, "Failed creations must not drift ledger revision")
	assert_true(is_instance_valid(peer_site), "Hostile override returning peer_site must NEVER free peer_site")
	if is_instance_valid(peer_site):
		assert_eq(peer_site.get_transaction_revision(), peer_rev_0, "Failed creations must not drift peer site revision")
		assert_true(peer_site.is_valid())
		assert_eq(inv.get_all_reservation_ids(), [peer_site.reservation_id])
		assert_eq(inv.get_reservation_amounts(peer_site.reservation_id), {&"wood": 2, &"stone": 1})
		assert_false(peer_site.is_transaction_busy())
	assert_eq(sites_root.get_child_count(), children_0)
	assert_eq(inv.get_available_amount(&"wood"), 8)
	assert_eq(inv.get_available_amount(&"stone"), 5)
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, cm.get_region_id()))
	assert_false(inv.is_transaction_busy())
	assert_false(storage.is_locked())
	assert_false(camp.is_transaction_locked())

	# E. Subsequent valid creation succeeds cleanly and reuses clean IDs / full stock.
	var r_ok: Dictionary = cm.try_create_site_from_placement(_def(3, 2), POS_A)
	assert_true(bool(r_ok["ok"]), str(r_ok))
	assert_eq(cm.get_sites().size(), 2)
	assert_eq(inv.get_reserved_amount(&"wood"), 5)
	assert_eq(inv.get_reserved_amount(&"stone"), 3)
	assert_eq(inv.get_available_amount(&"wood"), 5)
	assert_eq(inv.get_available_amount(&"stone"), 3)


## 5. Multi-region isolation in the same World3D and refusal of incompatible authority binding.
func test_05_multi_region_isolation_and_domain_binding_safety() -> void:
	var fx: Dictionary = await _spawn_main()
	var main: MainScene = fx["main"] as MainScene
	var world: World3D = fx["world"] as World3D
	var cm_a: ConstructionManager = fx["cm"] as ConstructionManager
	var inv_a: SettlementInventory = fx["inventory"] as SettlementInventory
	var storage_a: GroundPileManager = fx["storage"] as GroundPileManager
	var camp_a: CampStorageZone = fx["camp"] as CampStorageZone
	var units: Array[Unit] = fx["units"] as Array[Unit]

	var reg_b: Dictionary = _create_second_region_in_world(main, world, &"reg_b_c48", Vector3(16.0, 0.0, 12.0))
	var cm_b: ConstructionManager = reg_b["cm"] as ConstructionManager
	var inv_b: SettlementInventory = reg_b["inventory"] as SettlementInventory

	assert_true(inv_a.deposit(&"wood", 10))
	assert_true(inv_a.deposit(&"stone", 6))
	assert_true(inv_b.deposit(&"wood", 10))
	assert_true(inv_b.deposit(&"stone", 6))

	# A. While Region A has an active RegionalAuthority transaction (camp delivery), Region B creates cleanly.
	var u0: Unit = units[0]
	var load0 := _prepare_provenance_unit(u0, &"c48_region_a_worker")
	assert_true(bool(CarryFixture.add_lot(load0,
		&"c48_add_reg_a_1", &"c48_reg_a_lot_1", &"wood", WOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED
	).get("ok", false)))
	u0.global_position = camp_a.get_anchor_position() + Vector3(1.0, 0.0, 0.0)

	var reg_probe := {
		"res_a_during_a_tx": {},
		"res_b_during_a_tx": {},
		"ran_b_override": false,
		"res_a_during_b_create": {},
	}
	_watch(load0.load_changed, func() -> void:
		if (reg_probe["res_b_during_a_tx"] as Dictionary).is_empty():
			reg_probe["res_a_during_a_tx"] = cm_a.try_create_site_from_placement(_def(2, 1), POS_A)
			reg_probe["res_b_during_a_tx"] = cm_b.try_create_site_from_placement(_def(2, 1), POS_A)
	)
	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var tx_a: Dictionary = camp_coord.execute_selective_camp_delivery(
		inv_a, camp_a, u0, cm_a.get_region_id(), &"c48_op_reg_a_1", []
	)
	assert_true(bool(tx_a["ok"]), str(tx_a))
	var res_a_during_a_tx: Dictionary = reg_probe["res_a_during_a_tx"] as Dictionary
	var res_b_during_a_tx: Dictionary = reg_probe["res_b_during_a_tx"] as Dictionary
	assert_false(bool(res_a_during_a_tx.get("ok", true)))
	assert_eq(String(res_a_during_a_tx.get("reason", "")), "busy")
	assert_true(bool(res_b_during_a_tx.get("ok", false)), "Distinct region B must create site during region A tx: %s" % str(res_b_during_a_tx))
	assert_eq(cm_b.get_sites().size(), 1)
	assert_eq(inv_b.get_reserved_amount(&"wood"), 2)
	assert_eq(cm_a.get_sites().size(), 0)
	assert_eq(inv_a.get_reserved_amount(&"wood"), 0)

	# B. While Region B is executing site creation (inside site_creator_override), Region A creates cleanly.
	cm_b.site_creator_override = func(_sid: StringName, _rid: StringName, _d: BuildingDefinition, _p: Vector3) -> ConstructionSite:
		if not bool(reg_probe["ran_b_override"]):
			reg_probe["ran_b_override"] = true
			reg_probe["res_a_during_b_create"] = cm_a.try_create_site_from_placement(_def(2, 1), POS_A)
		return ConstructionSite.new()
	var res_b2: Dictionary = cm_b.try_create_site_from_placement(_def(2, 1), POS_B)
	cm_b.site_creator_override = Callable()
	assert_true(bool(res_b2["ok"]), str(res_b2))
	var res_a_during_b_create: Dictionary = reg_probe["res_a_during_b_create"] as Dictionary
	assert_true(bool(res_a_during_b_create.get("ok", false)), "Region A must create site independently during Region B creation")
	assert_eq(cm_a.get_sites().size(), 1)
	assert_eq(cm_b.get_sites().size(), 2)

	# C. Rogue ConstructionManager configured with a conflicting region_id sharing Region A's bound storage
	#    must be rejected with ambiguous_domain and must never regenerate or hijack Region A's authority.
	var rogue_host := Node3D.new()
	main.add_child(rogue_host)
	_extra_nodes.append(rogue_host)
	var rogue_sites := Node3D.new()
	rogue_host.add_child(rogue_sites)
	var rogue_cm := ConstructionManager.new()
	rogue_host.add_child(rogue_cm)
	rogue_cm.configure(rogue_sites, inv_a, {&"wood": WOOD.duplicate(), &"stone": STONE.duplicate()}, camp_a, null, &"rogue_region_c48")

	var domains_before: Dictionary = (world.get_meta(DOMAIN_META, {}) as Dictionary).duplicate()
	var res_rogue: Dictionary = rogue_cm.try_create_site_from_placement(_def(2, 1), POS_C)
	assert_false(bool(res_rogue["ok"]), "Conflicting region sharing bound RegionalAuthority storage must be rejected")
	assert_eq(String(res_rogue.get("reason", "")), "ambiguous_domain")
	var domains_after: Dictionary = world.get_meta(DOMAIN_META, {}) as Dictionary
	assert_false(domains_after.has(&"rogue_region_c48"), "Must not materialize incompatible RegionalAuthority")
	assert_eq(domains_after.get(cm_a.get_region_id()), domains_before.get(cm_a.get_region_id()))
	assert_eq(rogue_cm.get_sites().size(), 0)
	assert_eq(inv_a.get_reserved_amount(&"wood"), 2)
