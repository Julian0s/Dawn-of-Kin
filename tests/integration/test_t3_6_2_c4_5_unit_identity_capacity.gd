class_name TestT362C45UnitIdentityCapacity
extends TestCase

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")
## Focused integration suite for T3.6.2-C4.5 (P3):
## - P3-A: Economic unit identity uniqueness & shared-backpack rejection across all live
##   units in the domain (even without ConstructionSite participation), preserving legitimate
##   multi-region isolation in the same World3D and failing closed on ambiguous association.
## - P3-B: Atomic CharacterDefinition <-> UnitCarryLoad capacity coherence under transaction lock
##   and invalid capacity values, preserving modifiers, overload, movement, visuals, and legacy flow.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const CampPlanner = preload("res://src/economy/selective_camp_delivery_planner.gd")
const SitePlanner = preload("res://src/economy/selective_site_delivery_planner.gd")

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


func _boot_main() -> Dictionary:
	var main: MainScene = MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = false
	get_tree().root.add_child(main)
	_active_mains.append(main)
	await get_tree().process_frame
	await get_tree().physics_frame

	var nav: WorldNavigation = main.get_test_map().get_navigation()
	var deadline: int = Time.get_ticks_msec() + 8000
	while not nav.is_navigation_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame

	var units_root: Node3D = main.get_node("Units") as Node3D
	return {
		"main": main,
		"world": main.get_world_3d(),
		"nav": nav,
		"camp": main.get_camp_storage_zone(),
		"manager": main.get_ground_pile_manager(),
		"inventory": main.get_settlement_inventory(),
		"cm": main.get_construction_manager(),
		"sites_root": main.get_construction_sites_root(),
		"units_root": units_root,
		"leader_a": units_root.get_node("LeaderA") as Unit,
		"leader_b": units_root.get_node("LeaderB") as Unit,
		"workers_ctrl": main.get_placement_test_overlay().get_temporary_workers_controller(),
	}


func _spawn_bush(parent: Node, pos: Vector3, id: StringName) -> ResourceSource:
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.source_id = id
	bush.initial_amount = 10
	parent.add_child(bush)
	_extra_nodes.append(bush)
	bush.global_position = pos
	return bush


func _make_char_def(id: StringName, cap: int, speed: float, silhouette: CharacterDefinition.SilhouetteKind) -> CharacterDefinition:
	var d := CharacterDefinition.new()
	d.character_id = id
	d.display_name = String(id)
	d.base_carry_capacity = cap
	d.move_speed = speed
	d.work_approach_speed = 2.5
	d.max_load_speed_multiplier = 0.60
	d.turn_rate = 10.0
	d.silhouette_kind = silhouette
	return d


func _make_region_fixture(parent: Node, region_id: StringName, offset: Vector3, nav: WorldNavigation) -> Dictionary:
	var host := Node3D.new()
	host.name = "RegionHost_%s" % String(region_id)
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
	unit.global_position = camp.global_position

	return {
		"host": host,
		"world": host.get_world_3d(),
		"region": region_id,
		"camp": camp,
		"manager": manager,
		"inventory": inv,
		"unit": unit,
		"defs": defs,
	}


func test_01_p3a_duplicate_provenance_id_same_domain_without_sites_rejected() -> void:
	var ctx: Dictionary = await _boot_main()
	var main: MainScene = ctx["main"] as MainScene
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var manager: GroundPileManager = ctx["manager"] as GroundPileManager
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	# Different character_ids (&"leader_a" vs &"leader_b"), SAME provenance_unit_id (&"dup_worker"),
	# and ZERO ConstructionSites in the world!
	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	var load_b: UnitCarryLoad = leader_b.get_carry_load()
	assert_true(load_a.enable_provenance(&"dup_worker"))
	assert_true(load_b.enable_provenance(&"dup_worker"))

	# 1. GatherTransferSession + GatherResourceOrder opt-in must reject duplicate identity without any site.
	var bush: ResourceSource = _spawn_bush(main, Vector3(-2.5, 0.0, -3.5), &"c45_bush_dup")
	leader_a.global_position = bush.global_position
	var g_session := GatherTransferSession.new()
	var g_init: Dictionary = g_session.initialize_cycle(inv, camp, bush, leader_a, &"default", 1001, 1, 2)
	assert_false(bool(g_init.get("ok", true)), "GatherTransferSession must reject duplicate provenance_unit_id without sites: %s" % str(g_init))
	assert_eq(String(g_init.get("reason", "")), "ambiguous_unit_identity")
	assert_eq(bush.get_remaining_amount(), 10, "Source untouched on rejected gather admission")

	var g_order := GatherResourceOrder.new(bush, camp, inv, 0.05, 0.0, true, &"default")
	leader_a.issue_order(g_order)
	assert_true(g_order.is_finished(), "Opt-in GatherResourceOrder must reject duplicate identity immediately")
	assert_eq(g_order.failure_reason, "ambiguous_unit_identity")
	assert_eq(bush.get_active_worker_count(), 0, "Rejected gather order must not leak worker slot")

	# 2. SelectiveCampDeliveryPlanner + Coordinator must reject duplicate identity without any site.
	assert_true(bool(CarryFixture.add_lot(load_a, &"c45_g_dup", &"c45_l_dup", &"wood", WOOD.unit_weight, 3, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	leader_a.global_position = camp.global_position
	var camp_plan: Dictionary = CampPlanner.prepare_selective_camp_delivery(inv, camp, leader_a, &"default", &"c45_cp_dup", [])
	assert_false(bool(camp_plan.get("ok", true)), "CampPlanner must reject duplicate provenance_unit_id without sites: %s" % str(camp_plan))
	assert_eq(String(camp_plan.get("reason", "")), "ambiguous_unit_identity")
	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var camp_exec: Dictionary = camp_coord.execute_selective_camp_delivery(inv, camp, leader_a, &"default", &"c45_ce_dup", [])
	assert_false(bool(camp_exec.get("ok", true)), "CampCoordinator must reject duplicate provenance_unit_id without sites: %s" % str(camp_exec))
	assert_eq(String(camp_exec.get("reason", "")), "ambiguous_unit_identity")
	assert_eq(inv.get_physical_amount(&"wood"), 0, "Zero camp credit on rejected delivery")
	assert_eq(load_a.get_amount(&"wood"), 3, "Carry load preserved")

	# 3. With a ConstructionSite where ONLY LeaderA is registered and LeaderB is completely unregistered:
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site_res: Dictionary = cm.try_create_site_from_placement(SHELTER, Vector3(-6.0, 0.0, 2.0))
	assert_true(bool(site_res.get("ok", false)))
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	var pile: GroundResourcePile = manager.get_piles_for_resource(&"wood")[0]
	var c_order := ConstructOrder.new(site, camp, 1.45, 0.1, true)
	leader_a.issue_order(c_order)
	assert_eq(site.claim_pickup(leader_a, pile.pile_id, &"wood", 2), 2)
	leader_a.global_position = manager.get_pile_world_position(pile)

	var prep_wd: Dictionary = site.prepare_reserved_withdrawal(leader_a, pile.pile_id, &"wood", 2, &"c45_wd_dup", &"c45_wl_dup")
	assert_false(bool(prep_wd.get("ok", true)), "Reserved withdrawal prep must catch unregistered duplicate unit: %s" % str(prep_wd))
	assert_eq(String(prep_wd.get("reason", "")), "ambiguous_unit_identity")

	var w_coord := ReservedWithdrawalCoordinator.new()
	var exec_wd: Dictionary = w_coord.execute_reserved_withdrawal(site, leader_a, pile.pile_id, &"wood", 2, &"c45_wd_dup", &"c45_wl_dup")
	assert_false(bool(exec_wd.get("ok", true)), "ReservedWithdrawalCoordinator must reject unregistered duplicate unit: %s" % str(exec_wd))
	assert_eq(String(exec_wd.get("reason", "")), "ambiguous_unit_identity")

	var prep_sd: Dictionary = SitePlanner.prepare_selective_site_delivery(site, leader_a, &"c45_sd_dup", {})
	assert_false(bool(prep_sd.get("ok", true)), "SelectiveSiteDeliveryPlanner must reject unregistered duplicate unit: %s" % str(prep_sd))
	assert_eq(String(prep_sd.get("reason", "")), "ambiguous_unit_identity")
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 0)


func test_02_p3a_distinct_ids_same_domain_and_distinct_regions_same_world() -> void:
	var ctx: Dictionary = await _boot_main()
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	# 1. Two units with the SAME character_id (&"leader_a") but DISTINCT provenance_unit_ids in same domain -> BOTH succeed!
	leader_b.apply_definition(LEADER_A_DEF.duplicate() as CharacterDefinition)
	assert_eq(leader_a.get_character_id(), leader_b.get_character_id())
	assert_true(leader_a.get_carry_load().enable_provenance(&"distinct_u1"))
	assert_true(leader_b.get_carry_load().enable_provenance(&"distinct_u2"))
	assert_true(bool(CarryFixture.add_lot(leader_a.get_carry_load(), &"c45_d1", &"c45_dl1", &"wood", WOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	assert_true(bool(CarryFixture.add_lot(leader_b.get_carry_load(), &"c45_d2", &"c45_dl2", &"wood", WOOD.unit_weight, 3, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	leader_a.global_position = camp.global_position
	leader_b.global_position = camp.global_position
	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	assert_true(bool(camp_coord.execute_selective_camp_delivery(inv, camp, leader_a, &"default", &"c45_cd1", []).get("ok", false)))
	assert_true(bool(camp_coord.execute_selective_camp_delivery(inv, camp, leader_b, &"default", &"c45_cd2", []).get("ok", false)))
	assert_eq(inv.get_physical_amount(&"wood"), 5)

	# 2. Two distinct regions (&"reg_alpha" and &"reg_beta") inside the SAME World3D,
	#    BOTH using provenance_unit_id == &"regional_carrier" with proven regional association -> BOTH succeed!
	var fx_a: Dictionary = _make_region_fixture(get_tree().root, &"reg_alpha", Vector3(10.0, 0.0, 10.0), nav)
	var fx_b: Dictionary = _make_region_fixture(get_tree().root, &"reg_beta", Vector3(-10.0, 0.0, 10.0), nav)
	var ua: Unit = fx_a["unit"] as Unit
	var ub: Unit = fx_b["unit"] as Unit
	ua.set_meta(&"region_id", &"reg_alpha")
	ub.set_meta(&"region_id", &"reg_beta")
	assert_true(ua.get_carry_load().enable_provenance(&"regional_carrier"))
	assert_true(ub.get_carry_load().enable_provenance(&"regional_carrier"))
	assert_true(bool(CarryFixture.add_lot(ua.get_carry_load(), &"c45_ra_g", &"c45_ra_l", &"wood", WOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	assert_true(bool(CarryFixture.add_lot(ub.get_carry_load(), &"c45_rb_g", &"c45_rb_l", &"wood", WOOD.unit_weight, 3, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	var res_a: Dictionary = camp_coord.execute_selective_camp_delivery(
		fx_a["inventory"] as SettlementInventory, fx_a["camp"] as CampStorageZone, ua, &"reg_alpha", &"c45_ra_del", []
	)
	var res_b: Dictionary = camp_coord.execute_selective_camp_delivery(
		fx_b["inventory"] as SettlementInventory, fx_b["camp"] as CampStorageZone, ub, &"reg_beta", &"c45_rb_del", []
	)
	assert_true(bool(res_a.get("ok", false)), "Region alpha must succeed: %s" % str(res_a))
	assert_true(bool(res_b.get("ok", false)), "Region beta must succeed with isolated same ID: %s" % str(res_b))
	assert_eq((fx_a["inventory"] as SettlementInventory).get_physical_amount(&"wood"), 2)
	assert_eq((fx_b["inventory"] as SettlementInventory).get_physical_amount(&"wood"), 3)

	# 3. Unbound/ambiguous stray unit in the SAME World3D with &"regional_carrier" -> conservatively rejected!
	var stray: Unit = UNIT_SCENE.instantiate() as Unit
	stray.name = "StrayAmbiguousUnit"
	stray.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	get_tree().root.add_child(stray)
	_extra_nodes.append(stray)
	assert_true(stray.get_carry_load().enable_provenance(&"regional_carrier"))
	assert_true(bool(CarryFixture.add_lot(ua.get_carry_load(), &"c45_ra_g2", &"c45_ra_l2", &"wood", WOOD.unit_weight, 1, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	var ambig_res: Dictionary = camp_coord.execute_selective_camp_delivery(
		fx_a["inventory"] as SettlementInventory, fx_a["camp"] as CampStorageZone, ua, &"reg_alpha", &"c45_ra_del2", []
	)
	assert_false(bool(ambig_res.get("ok", true)), "Stray unit with ambiguous region and duplicate ID must be rejected: %s" % str(ambig_res))
	assert_eq(String(ambig_res.get("reason", "")), "ambiguous_unit_identity")
	assert_eq((fx_a["inventory"] as SettlementInventory).get_physical_amount(&"wood"), 2, "Inventory untouched")


func test_03_p3a_empty_id_shared_carry_load_and_busy_admission() -> void:
	var ctx: Dictionary = await _boot_main()
	var main: MainScene = ctx["main"] as MainScene
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	# 1. Empty / whitespace provenance_unit_id rejected
	assert_false(leader_a.get_carry_load().enable_provenance(&""))
	assert_false(leader_a.get_carry_load().enable_provenance(&"   "))
	assert_false(leader_a.get_carry_load().is_provenance_enabled())

	# 2. Shared UnitCarryLoad instance between two live units (no ConstructionSites!) rejected everywhere
	assert_true(leader_a.get_carry_load().enable_provenance(&"shared_bag_owner"))
	var orig_b_load: UnitCarryLoad = leader_b.get_carry_load()
	leader_b._carry_load = leader_a.get_carry_load()
	assert_true(bool(CarryFixture.add_lot(leader_a.get_carry_load(), &"c45_sb_g", &"c45_sb_l", &"wood", WOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	leader_a.global_position = camp.global_position

	var camp_plan: Dictionary = CampPlanner.prepare_selective_camp_delivery(inv, camp, leader_a, &"default", &"c45_sb_cp", [])
	assert_false(bool(camp_plan.get("ok", true)), "Shared UnitCarryLoad must be rejected by CampPlanner: %s" % str(camp_plan))
	assert_eq(String(camp_plan.get("reason", "")), "ambiguous_unit_identity")

	var bush: ResourceSource = _spawn_bush(main, Vector3(-2.5, 0.0, -3.5), &"c45_bush_sb")
	var g_session := GatherTransferSession.new()
	var g_init: Dictionary = g_session.initialize_cycle(inv, camp, bush, leader_a, &"default", 2001, 1, 2)
	assert_false(bool(g_init.get("ok", true)), "Shared UnitCarryLoad must be rejected by GatherTransferSession: %s" % str(g_init))
	assert_eq(String(g_init.get("reason", "")), "ambiguous_unit_identity")

	var src_direct: Dictionary = bush.transfer_to_carry_load_with_provenance(leader_a.get_carry_load(), &"c45_sb_src", &"c45_sb_src_lot", 2)
	assert_false(bool(src_direct.get("ok", true)), "Shared UnitCarryLoad must be rejected by ResourceSource: %s" % str(src_direct))
	assert_eq(String(src_direct.get("reason", "")), "ambiguous_unit_identity")
	assert_eq(bush.get_remaining_amount(), 10)

	# Restore distinct bag on LeaderB -> admission now succeeds, and nested admission during active tx fails with busy!
	leader_b._carry_load = orig_b_load
	assert_true(leader_b.get_carry_load().enable_provenance(&"distinct_b_bag"))
	var busy_probes: Array[Dictionary] = []
	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var on_load_changed := func() -> void:
		busy_probes.append(CampPlanner.prepare_selective_camp_delivery(inv, camp, leader_b, &"default", &"c45_nested_b", []))
	leader_a.get_carry_load().load_changed.connect(on_load_changed, CONNECT_ONE_SHOT)
	_connections.append([leader_a.get_carry_load().load_changed, on_load_changed])

	var del_ok: Dictionary = camp_coord.execute_selective_camp_delivery(inv, camp, leader_a, &"default", &"c45_sb_ok", [])
	assert_true(bool(del_ok.get("ok", false)), str(del_ok))
	assert_eq(busy_probes.size(), 1)
	assert_false(bool(busy_probes[0].get("ok", true)))
	assert_eq(String(busy_probes[0].get("reason", "")), "busy")
	assert_eq(inv.get_physical_amount(&"wood"), 2)


func test_04_p3b_definition_change_blocked_under_real_transaction_lock() -> void:
	var ctx: Dictionary = await _boot_main()
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var load_a: UnitCarryLoad = leader_a.get_carry_load()

	var orig_def: CharacterDefinition = _make_char_def(&"p3b_orig", 20, 4.8, CharacterDefinition.SilhouetteKind.EXPLORER_PACK)
	var alt_def: CharacterDefinition = _make_char_def(&"p3b_alt", 35, 6.2, CharacterDefinition.SilhouetteKind.CLOAK_SCOUT)
	leader_a.apply_definition(orig_def)
	assert_eq(leader_a.definition, orig_def)
	assert_true(load_a.set_capacity_modifier(&"pack_bonus", 4))
	assert_eq(load_a.get_base_capacity(), 20)
	assert_eq(load_a.get_effective_capacity(), 24)
	assert_true(load_a.enable_provenance(&"p3b_unit_a"))
	assert_true(bool(CarryFixture.add_lot(load_a, &"p3b_g1", &"p3b_l1", &"wood", WOOD.unit_weight, 4, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	leader_a.global_position = camp.global_position

	var cap_events: Array[int] = [0]
	var on_cap := func() -> void:
		cap_events[0] += 1
	load_a.capacity_changed.connect(on_cap)
	_connections.append([load_a.capacity_changed, on_cap])

	var observed: Array[Dictionary] = []
	var on_load_changed := func() -> void:
		leader_a.definition = alt_def
		leader_a.apply_definition(alt_def)
		leader_a.definition = null
		leader_a._sync_definition()
		observed.append({
			"def": leader_a.definition,
			"base_cap": load_a.get_base_capacity(),
			"eff_cap": load_a.get_effective_capacity(),
			"speed": leader_a.get_movement()._move_speed,
			"explorer_vis": leader_a._explorer_visual.visible,
			"cloak_vis": leader_a._cloak_visual.visible,
			"still_locked": load_a._coordinator_transaction_locked,
		})
	load_a.load_changed.connect(on_load_changed, CONNECT_ONE_SHOT)
	_connections.append([load_a.load_changed, on_load_changed])

	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var del_res: Dictionary = camp_coord.execute_selective_camp_delivery(inv, camp, leader_a, &"default", &"p3b_del", [])
	assert_true(bool(del_res.get("ok", false)), str(del_res))
	assert_eq(observed.size(), 1)
	var obs: Dictionary = observed[0]
	assert_eq(obs["def"], orig_def, "Unit.definition MUST NOT diverge when carry load rejects capacity change under lock")
	assert_eq(int(obs["base_cap"]), 20, "Base capacity preserved under lock")
	assert_eq(int(obs["eff_cap"]), 24, "Effective capacity + modifier preserved under lock")
	assert_true(is_equal_approx(float(obs["speed"]), 4.8), "Movement profile must remain coherent with original definition")
	assert_true(bool(obs["explorer_vis"]) and not bool(obs["cloak_vis"]), "Visuals must remain coherent with original definition")
	assert_true(bool(obs["still_locked"]), "Transaction lock must NOT be released prematurely")
	assert_eq(cap_events[0], 0, "capacity_changed must NOT emit when capacity update was rejected")

	# Negative capacity definition rejected cleanly even when unlocked
	var bad_def: CharacterDefinition = _make_char_def(&"p3b_bad", -5, 7.0, CharacterDefinition.SilhouetteKind.CLOAK_SCOUT)
	leader_a.definition = bad_def
	assert_eq(leader_a.definition, orig_def, "Invalid negative base_carry_capacity must not alter Unit.definition")
	assert_eq(load_a.get_base_capacity(), 20)
	assert_eq(cap_events[0], 0)


func test_05_p3b_normal_definition_change_overload_modifiers_temp_workers_and_legacy() -> void:
	var ctx: Dictionary = await _boot_main()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	var ctrl: TemporaryTestWorkersController = ctx["workers_ctrl"] as TemporaryTestWorkersController

	# Legacy RTS default remains provenance-disabled
	assert_false(leader_a.get_carry_load().is_provenance_enabled())
	assert_false(leader_b.get_carry_load().is_provenance_enabled())

	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	var orig_def: CharacterDefinition = _make_char_def(&"p3b_n1", 20, 4.8, CharacterDefinition.SilhouetteKind.EXPLORER_PACK)
	var smaller_def: CharacterDefinition = _make_char_def(&"p3b_n2", 10, 5.2, CharacterDefinition.SilhouetteKind.CLOAK_SCOUT)
	leader_a.apply_definition(orig_def)
	assert_eq(leader_a.definition, orig_def)
	assert_true(load_a.set_capacity_modifier(&"satchel", 2))
	assert_true(load_a.add_units(WOOD, 8)) # 8 * 2 = 16 weight <= 22

	var cap_events: Array[int] = [0]
	var on_cap := func() -> void:
		cap_events[0] += 1
	load_a.capacity_changed.connect(on_cap)
	_connections.append([load_a.capacity_changed, on_cap])

	leader_a.apply_definition(smaller_def)
	assert_eq(leader_a.definition, smaller_def)
	assert_eq(load_a.get_base_capacity(), 10)
	assert_eq(load_a.get_effective_capacity(), 12, "Legitimate modifier preserved (+2)")
	assert_eq(load_a.get_amount(&"wood"), 8, "Carried amount preserved")
	assert_eq(load_a.get_current_weight(), 16, "Carried weight preserved")
	assert_true(load_a.is_overloaded(), "Overloaded state preserved honestly")
	assert_true(is_equal_approx(leader_a.get_movement()._move_speed, 5.2))
	assert_true(leader_a._cloak_visual.visible and not leader_a._explorer_visual.visible)
	assert_eq(cap_events[0], 1, "capacity_changed emitted once on actual change")

	# Temporary workers compatibility
	var spawn_res: Dictionary = ctrl.spawn_temporary_workers()
	assert_true(bool(spawn_res.get("ok", false)), str(spawn_res))
	var w3: Unit = (spawn_res["workers"] as Array)[0] as Unit
	var w4: Unit = (spawn_res["workers"] as Array)[1] as Unit
	assert_false(w3.get_carry_load().is_provenance_enabled())
	assert_false(w4.get_carry_load().is_provenance_enabled())
	assert_eq(w3.get_carry_load().get_base_capacity(), 20)
	assert_eq(w4.get_carry_load().get_base_capacity(), 20)
	var rem_res: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_true(bool(rem_res.get("ok", false)), str(rem_res))
