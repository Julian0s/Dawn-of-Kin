class_name TestT362C42LifecycleReadiness
extends TestCase

const CarryFixture = preload("res://tests/framework/carry_provenance_fixture.gd")
## Integration suite for T3.6.2-C4.2:
## - P1: Controlled RegionalAuthority lifecycle on economic session shutdown (MainScene._exit_tree)
## - P5: Transactional & domain-wide guards in TemporaryTestWorkersController safe removal

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")

var _active_mains: Array[MainScene] = []
var _extra_nodes: Array[Node] = []
var _extra_managers: Array[GroundPileManager] = []
var _extra_releases: Array[Dictionary] = []
var _connections: Array[Array] = []
var _prior_scale: float = 1.0
var _prior_ticks: int = 60


class NonCancellableOrder extends UnitOrder:
	var cancel_attempts: int = 0

	func start(_unit_body: CharacterBody3D, _movement: UnitMovement, _world_nav: WorldNavigation) -> void:
		mark_running()

	func cancel(_movement: UnitMovement, _reason: String = REASON_CANCELLED) -> void:
		cancel_attempts += 1
		# Deliberately refuses cancellation without finishing.


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


func _boot_main_on_root() -> Dictionary:
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


func _shutdown_main(main: MainScene) -> Dictionary:
	_active_mains.erase(main)
	var release_res: Dictionary = {}
	if main != null and is_instance_valid(main):
		if main.get_parent() != null:
			main.get_parent().remove_child(main)
		release_res = main.get_last_domain_release_result()
		main.free()
	await get_tree().process_frame
	return release_res


func _make_custom_building_def(id: StringName, cost_map: Dictionary) -> BuildingDefinition:
	var def := BuildingDefinition.new()
	def.definition_id = id
	def.display_name = String(id)
	def.footprint_size = Vector2(3.0, 3.0)
	def.visual_height = 2.0
	def.build_work_required_sec = 4.0
	def.max_builders = 2
	def.costs = cost_map.duplicate()
	return def


func _create_external_region_fixture(parent: Node, region_id: StringName, offset: Vector3, nav: WorldNavigation = null) -> Dictionary:
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
	if nav != null:
		camp.set_world_navigation(nav)

	var piles_root := Node3D.new()
	piles_root.name = "PilesRoot"
	host.add_child(piles_root)

	var time_prov := SimulatedWorldTimeProvider.new(0.0)
	var defs: Dictionary = {&"wood": WOOD, &"stone": STONE, &"food": FOOD}
	var manager := GroundPileManager.new(defs, camp, piles_root, time_prov)
	var token := RefCounted.new()
	assert_true(manager.bind_domain_owner(token), "Fresh GroundPileManager must accept owner token")
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
	unit.definition = LEADER_A_DEF
	host.add_child(unit)
	if nav != null:
		unit.set_world_navigation(nav)
	unit.global_position = camp.global_position

	return {
		"host": host,
		"world": host.get_world_3d(),
		"region": region_id,
		"camp": camp,
		"piles_root": piles_root,
		"manager": manager,
		"inventory": inv,
		"token": token,
		"unit": unit,
		"defs": defs,
	}


func _site_dropoff_pos(site: ConstructionSite) -> Vector3:
	return site.global_position + Vector3(0.0, 0.0, site.definition.footprint_size.y * 0.5 + 0.5)


func _run_opt_in_cycle_on_main(ctx: Dictionary, tag: String) -> void:
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var manager: GroundPileManager = ctx["manager"] as GroundPileManager
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var sites_root: Node3D = ctx["sites_root"] as Node3D
	var u: Unit = ctx["leader_a"] as Unit
	var load: UnitCarryLoad = u.get_carry_load()
	var uid: StringName = StringName("%s_leader_a" % tag)
	assert_true(load.enable_provenance(uid), "Enable provenance for %s" % tag)

	# 1. Opt-in camp delivery (FREE_GATHERED -> camp pile)
	var add_res: Dictionary = CarryFixture.add_lot(load,
		StringName("%s_gather_op" % tag),
		StringName("%s_gather_lot" % tag),
		&"wood",
		WOOD.unit_weight,
		4,
		CarryProvenanceLedger.FREE_GATHERED
	)
	assert_true(bool(add_res.get("ok", false)), str(add_res))
	u.global_position = camp.global_position
	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var camp_del: Dictionary = camp_coord.execute_selective_camp_delivery(
		inv, camp, u, &"default", StringName("%s_camp_del" % tag), []
	)
	assert_true(bool(camp_del.get("ok", false)), "Camp delivery must succeed for %s: %s" % [tag, str(camp_del)])
	assert_eq(inv.get_physical_amount(&"wood"), 4)
	assert_true(load.is_empty())

	# 2. Site reservation + opt-in reserved withdrawal -> transit claim
	var site := ConstructionSite.new()
	sites_root.add_child(site)
	site.global_position = Vector3(-6.0, 0.0, 2.0)
	var defs: Dictionary = {&"wood": WOOD, &"stone": STONE, &"food": FOOD}
	var site_id: StringName = StringName("%s_site" % tag)
	var res_id: StringName = StringName("%s_res" % tag)
	assert_true(site.configure(site_id, res_id, _make_custom_building_def(StringName("%s_def" % tag), {&"wood": 4}), inv, defs, &"default"))
	assert_true(inv.reserve_batch(res_id, {&"wood": 4}))
	var piles: Array[GroundResourcePile] = manager.get_piles_for_resource(&"wood")
	assert_false(piles.is_empty())
	var pile: GroundResourcePile = piles[0]
	var c_order := ConstructOrder.new(site, camp, 1.45, 0.1, true)
	u.issue_order(c_order)
	assert_eq(site.claim_pickup(u, pile.pile_id, &"wood", 4), 4)
	u.global_position = manager.get_pile_world_position(pile)
	var w_coord := ReservedWithdrawalCoordinator.new()
	var wd_res: Dictionary = w_coord.execute_reserved_withdrawal(
		site, u, pile.pile_id, &"wood", 4, StringName("%s_wd_op" % tag), StringName("%s_wd_lot" % tag)
	)
	assert_true(bool(wd_res.get("ok", false)), "Reserved withdrawal must succeed for %s: %s" % [tag, str(wd_res)])
	assert_eq(load.get_amount(&"wood"), 4)
	assert_eq(site.get_transit_claim_for_unit(u), {&"wood": 4})

	# 3. Opt-in selective site delivery -> delivered buffer
	u.global_position = _site_dropoff_pos(site)
	var site_coord := SelectiveSiteDeliveryCoordinator.new()
	var sd_res: Dictionary = site_coord.execute_selective_site_delivery(
		site, u, StringName("%s_sd_op" % tag), {&"wood": 4}
	)
	assert_true(bool(sd_res.get("ok", false)), "Selective site delivery must succeed for %s: %s" % [tag, str(sd_res)])
	assert_true(load.is_empty())
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 4)
	assert_true(site.verify_accounting_invariant())
	u.cancel_current_order("test_done")


# ==============================================================================
# P1 TESTS — Controlled RegionalAuthority Lifecycle
# ==============================================================================

func test_p1_01_two_sequential_main_scenes_same_world_3d_full_opt_in_cycle() -> void:
	var s1: Dictionary = await _boot_main_on_root()
	var world_1: World3D = s1["world"] as World3D
	# Confirm legacy RTS remains default on MainScene boot.
	assert_false((s1["leader_a"] as Unit).get_carry_load().is_provenance_enabled(), "RTS default must remain legacy (provenance off)")
	assert_false((s1["leader_b"] as Unit).get_carry_load().is_provenance_enabled(), "RTS default must remain legacy (provenance off)")

	_run_opt_in_cycle_on_main(s1, "s1")
	assert_true(world_1.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META), "Session 1 must register RegionalAuthority in World3D")

	var rel_1: Dictionary = await _shutdown_main(s1["main"] as MainScene)
	assert_true(bool(rel_1.get("ok", false)), "Session 1 shutdown must succeed: %s" % str(rel_1))
	assert_true(bool(rel_1.get("released", false)), "Session 1 shutdown must release its RegionalAuthority: %s" % str(rel_1))
	assert_false(world_1.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META), "DOMAIN_META must be removed when last region releases")

	# Mount second MainScene directly on the exact same root World3D (no SubViewport).
	var s2: Dictionary = await _boot_main_on_root()
	var world_2: World3D = s2["world"] as World3D
	assert_eq(world_2, world_1, "Second MainScene must share the exact same root World3D")
	_run_opt_in_cycle_on_main(s2, "s2")

	var rel_2: Dictionary = await _shutdown_main(s2["main"] as MainScene)
	assert_true(bool(rel_2.get("ok", false)), "Session 2 shutdown must succeed: %s" % str(rel_2))
	assert_true(bool(rel_2.get("released", false)), "Session 2 shutdown must release its RegionalAuthority: %s" % str(rel_2))
	assert_false(world_2.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))


func test_p1_02_active_storage_replacement_and_mid_session_release_still_rejected() -> void:
	var s1: Dictionary = await _boot_main_on_root()
	var world: World3D = s1["world"] as World3D
	var camp_1: CampStorageZone = s1["camp"] as CampStorageZone
	var inv_1: SettlementInventory = s1["inventory"] as SettlementInventory
	var u1: Unit = s1["leader_a"] as Unit
	assert_true(u1.get_carry_load().enable_provenance(&"p102_u1"))
	assert_true(bool(CarryFixture.add_lot(u1.get_carry_load(), &"p102_g1", &"p102_l1", &"wood", WOOD.unit_weight, 4, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	u1.global_position = camp_1.global_position
	var coord_1 := SelectiveCampDeliveryCoordinator.new()
	var del_1: Dictionary = coord_1.execute_selective_camp_delivery(inv_1, camp_1, u1, &"default", &"p102_op1", [])
	assert_true(bool(del_1.get("ok", false)), str(del_1))

	# Attempt to substitute another active storage in the same (world, &"default") while Session 1 is active.
	var rogue_fx: Dictionary = _create_external_region_fixture(get_tree().root, &"default", Vector3(10.0, 0.0, 10.0), s1["nav"] as WorldNavigation)
	var rogue_u: Unit = rogue_fx["unit"] as Unit
	assert_true(rogue_u.get_carry_load().enable_provenance(&"p102_rogue"))
	assert_true(bool(CarryFixture.add_lot(rogue_u.get_carry_load(), &"p102_rg", &"p102_rl", &"wood", WOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	var rogue_coord := SelectiveCampDeliveryCoordinator.new()
	var rogue_res: Dictionary = rogue_coord.execute_selective_camp_delivery(
		rogue_fx["inventory"] as SettlementInventory,
		rogue_fx["camp"] as CampStorageZone,
		rogue_u,
		&"default",
		&"p102_rogue_op",
		[]
	)
	assert_false(bool(rogue_res.get("ok", true)), "Storage replacement during active domain must fail")
	assert_eq(String(rogue_res.get("reason", "")), "ambiguous_domain", "Must preserve ambiguous_domain protection: %s" % str(rogue_res))

	# Legitimate owner trying to release while session is still active must fail and preserve receipts.
	var active_rel: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(
		world, &"default", rogue_fx["manager"] as GroundPileManager, rogue_fx["token"] as RefCounted, get_tree()
	)
	assert_false(bool(active_rel.get("ok", true)))
	assert_eq(String(active_rel.get("reason", "")), "storage_mismatch")

	# Replay on Session 1 must still succeed (receipts & serials untouched).
	var replay_1: Dictionary = coord_1.execute_selective_camp_delivery(inv_1, camp_1, u1, &"default", &"p102_op1", [])
	assert_true(bool(replay_1.get("ok", false)) and bool(replay_1.get("replayed", false)), "Receipts must remain intact after rejected attempts: %s" % str(replay_1))


func test_p1_03_wrong_owner_storage_region_world_busy_and_repeated_release_guards() -> void:
	var boot: Dictionary = await _boot_main_on_root()
	var nav: WorldNavigation = boot["nav"] as WorldNavigation
	var fx_a: Dictionary = _create_external_region_fixture(get_tree().root, &"reg_p103_a", Vector3(10.0, 0.0, 10.0), nav)
	var fx_b: Dictionary = _create_external_region_fixture(get_tree().root, &"reg_p103_b", Vector3(-10.0, 0.0, 10.0), nav)
	var world: World3D = fx_a["world"] as World3D
	var mgr_a: GroundPileManager = fx_a["manager"] as GroundPileManager
	var inv_a: SettlementInventory = fx_a["inventory"] as SettlementInventory
	var camp_a: CampStorageZone = fx_a["camp"] as CampStorageZone
	var tok_a: RefCounted = fx_a["token"] as RefCounted
	var u_a: Unit = fx_a["unit"] as Unit

	# Re-binding owner token on an already-owned GroundPileManager must fail.
	assert_false(mgr_a.bind_domain_owner(RefCounted.new()), "Owner token cannot be overwritten")

	# Execute a real transaction on reg_p103_a and attempt release DURING post-commit signal (authority.is_executing == true).
	assert_true(u_a.get_carry_load().enable_provenance(&"p103_ua"))
	assert_true(bool(CarryFixture.add_lot(u_a.get_carry_load(), &"p103_ga", &"p103_la", &"wood", WOOD.unit_weight, 4, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	var busy_attempts: Array[Dictionary] = []
	var on_storage_changed := func() -> void:
		busy_attempts.append(ReservedWithdrawalCoordinator.release_regional_domain(world, &"reg_p103_a", mgr_a, tok_a, get_tree(), inv_a))
	mgr_a.storage_changed.connect(on_storage_changed)
	_connections.append([mgr_a.storage_changed, on_storage_changed])

	var coord_a := SelectiveCampDeliveryCoordinator.new()
	var del_a: Dictionary = coord_a.execute_selective_camp_delivery(inv_a, camp_a, u_a, &"reg_p103_a", &"p103_op_a", [])
	assert_true(bool(del_a.get("ok", false)), str(del_a))
	assert_eq(busy_attempts.size(), 1)
	assert_false(bool(busy_attempts[0].get("ok", true)), "Release during active transaction must fail: %s" % str(busy_attempts[0]))
	assert_eq(String(busy_attempts[0].get("reason", "")), "busy")

	# Wrong owner token -> unauthorized_owner.
	var wrong_tok_res: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(world, &"reg_p103_a", mgr_a, RefCounted.new(), get_tree(), inv_a)
	assert_false(bool(wrong_tok_res.get("ok", true)))
	assert_eq(String(wrong_tok_res.get("reason", "")), "unauthorized_owner")

	# Wrong storage (with its own valid token) -> storage_mismatch.
	var wrong_storage_res: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(
		world, &"reg_p103_a", fx_b["manager"] as GroundPileManager, fx_b["token"] as RefCounted, get_tree()
	)
	assert_false(bool(wrong_storage_res.get("ok", true)))
	assert_eq(String(wrong_storage_res.get("reason", "")), "storage_mismatch")

	# Wrong region -> region_mismatch.
	var wrong_region_res: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(world, &"reg_p103_b", mgr_a, tok_a, get_tree(), inv_a)
	assert_false(bool(wrong_region_res.get("ok", true)))
	assert_eq(String(wrong_region_res.get("reason", "")), "region_mismatch")

	# Wrong world -> world_mismatch.
	var other_vp := SubViewport.new()
	other_vp.own_world_3d = true
	add_test_child(other_vp)
	var other_world: World3D = other_vp.find_world_3d()
	var wrong_world_res: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(other_world, &"reg_p103_a", mgr_a, tok_a, get_tree(), inv_a)
	assert_false(bool(wrong_world_res.get("ok", true)))
	assert_eq(String(wrong_world_res.get("reason", "")), "world_mismatch")
	assert_false(other_world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META), "Failed check must never write DOMAIN_META to another world")

	# Session still active (piles_root & camp still inside tree) -> session_still_active.
	var still_active_res: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(world, &"reg_p103_a", mgr_a, tok_a, get_tree(), inv_a)
	assert_false(bool(still_active_res.get("ok", true)))
	assert_eq(String(still_active_res.get("reason", "")), "session_still_active")

	# Detach scene host without cleanup() -> storage_not_cleaned_up (piles still present).
	var host_a: Node3D = fx_a["host"] as Node3D
	host_a.get_parent().remove_child(host_a)
	var not_cleaned_res: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(world, &"reg_p103_a", mgr_a, tok_a, get_tree(), inv_a)
	assert_false(bool(not_cleaned_res.get("ok", true)))
	assert_eq(String(not_cleaned_res.get("reason", "")), "storage_not_cleaned_up")

	# Now cleanup() + release succeeds cleanly.
	mgr_a.cleanup()
	var ok_rel: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(world, &"reg_p103_a", mgr_a, tok_a, get_tree(), inv_a)
	assert_true(bool(ok_rel.get("ok", false)) and bool(ok_rel.get("released", false)), str(ok_rel))
	assert_true(mgr_a.is_shut_down())

	# Repeated release call on already-released storage is a safe idempotent no-op.
	var repeat_rel: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(world, &"reg_p103_a", mgr_a, tok_a, get_tree(), inv_a)
	assert_true(bool(repeat_rel.get("ok", false)))
	assert_false(bool(repeat_rel.get("released", true)))
	assert_eq(String(repeat_rel.get("reason", "")), "not_bound")

	# A new storage taking reg_p103_a cannot be released by the old storage's repeated call.
	var fx_a2: Dictionary = _create_external_region_fixture(get_tree().root, &"reg_p103_a", Vector3(10.0, 0.0, -10.0), nav)
	var u_a2: Unit = fx_a2["unit"] as Unit
	assert_true(u_a2.get_carry_load().enable_provenance(&"p103_ua2"))
	assert_true(bool(CarryFixture.add_lot(u_a2.get_carry_load(), &"p103_ga2", &"p103_la2", &"wood", WOOD.unit_weight, 2, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	var coord_a2 := SelectiveCampDeliveryCoordinator.new()
	var del_a2: Dictionary = coord_a2.execute_selective_camp_delivery(
		fx_a2["inventory"] as SettlementInventory, fx_a2["camp"] as CampStorageZone, u_a2, &"reg_p103_a", &"p103_op_a2", []
	)
	assert_true(bool(del_a2.get("ok", false)), str(del_a2))
	var stale_repeat: Dictionary = ReservedWithdrawalCoordinator.release_regional_domain(world, &"reg_p103_a", mgr_a, tok_a, get_tree(), inv_a)
	assert_false(bool(stale_repeat.get("ok", true)), "Old session must not release new session's authority")
	assert_eq(String(stale_repeat.get("reason", "")), "storage_mismatch")


func test_p1_04_other_regions_independent_and_main_exit_during_busy_is_conservative() -> void:
	# Part A: Two independent regions in the same World3D.
	var s1: Dictionary = await _boot_main_on_root()
	var world: World3D = s1["world"] as World3D
	var fx_b: Dictionary = _create_external_region_fixture(get_tree().root, &"region_independent_b", Vector3(10.0, 0.0, 10.0), s1["nav"] as WorldNavigation)

	_run_opt_in_cycle_on_main(s1, "p104_a")

	var u_b: Unit = fx_b["unit"] as Unit
	var inv_b: SettlementInventory = fx_b["inventory"] as SettlementInventory
	var camp_b: CampStorageZone = fx_b["camp"] as CampStorageZone
	assert_true(u_b.get_carry_load().enable_provenance(&"p104_ub"))
	assert_true(bool(CarryFixture.add_lot(u_b.get_carry_load(), &"p104_gb", &"p104_lb", &"wood", WOOD.unit_weight, 3, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	var coord_b := SelectiveCampDeliveryCoordinator.new()
	var del_b: Dictionary = coord_b.execute_selective_camp_delivery(inv_b, camp_b, u_b, &"region_independent_b", &"p104_op_b", [])
	assert_true(bool(del_b.get("ok", false)), str(del_b))

	# Shutdown MainScene (&"default"): &"region_independent_b" must remain completely intact!
	var rel_a: Dictionary = await _shutdown_main(s1["main"] as MainScene)
	assert_true(bool(rel_a.get("ok", false)) and bool(rel_a.get("released", false)), str(rel_a))
	assert_true(world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META), "DOMAIN_META must still retain region_independent_b")
	var replay_b: Dictionary = coord_b.execute_selective_camp_delivery(inv_b, camp_b, u_b, &"region_independent_b", &"p104_op_b", [])
	assert_true(bool(replay_b.get("ok", false)) and bool(replay_b.get("replayed", false)), "Other region receipts must remain valid: %s" % str(replay_b))

	# Pure read-only checks on an unbound region must NEVER create a RegionalAuthority.
	var domains_before: Dictionary = (world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META) as Dictionary).duplicate()
	assert_false(ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, &"never_bound_region"))
	var probe_unbound: Dictionary = ReservedWithdrawalCoordinator.inspect_domain_for_worker_removal_readonly(world, &"never_bound_region", null, null)
	assert_true(bool(probe_unbound.get("ok", false)))
	var domains_after: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META) as Dictionary
	assert_eq(domains_after.keys(), domains_before.keys(), "Read-only inspection must never create authorities")

	# Part B: MainScene._exit_tree() triggered while a transaction is active fails conservatively without destroying receipts.
	var s2: Dictionary = await _boot_main_on_root()
	var main_2: MainScene = s2["main"] as MainScene
	var inv_2: SettlementInventory = s2["inventory"] as SettlementInventory
	var camp_2: CampStorageZone = s2["camp"] as CampStorageZone
	var mgr_2: GroundPileManager = s2["manager"] as GroundPileManager
	var u_2: Unit = s2["leader_a"] as Unit
	assert_true(u_2.get_carry_load().enable_provenance(&"p104_u2"), "p104 enable_provenance u_2")
	var add_2_res: Dictionary = CarryFixture.add_lot(u_2.get_carry_load(), &"p104_g2", &"p104_l2", &"wood", WOOD.unit_weight, 4, CarryProvenanceLedger.FREE_GATHERED)
	assert_true(bool(add_2_res.get("ok", false)), "p104 add_2: %s" % str(add_2_res))
	u_2.global_position = camp_2.global_position

	var triggered_exit: Array[bool] = [false]
	var on_mid_tx_exit := func() -> void:
		if not triggered_exit[0]:
			triggered_exit[0] = true
			if main_2.get_parent() != null:
				main_2.get_parent().remove_child(main_2)
	mgr_2.storage_changed.connect(on_mid_tx_exit, CONNECT_ONE_SHOT)
	_connections.append([mgr_2.storage_changed, on_mid_tx_exit])

	var coord_2 := SelectiveCampDeliveryCoordinator.new()
	var del_2: Dictionary = coord_2.execute_selective_camp_delivery(inv_2, camp_2, u_2, &"default", &"p104_op_2", [])
	assert_true(bool(del_2.get("ok", false)), "p104 del_2: %s" % str(del_2))
	assert_true(triggered_exit[0], "p104 triggered_exit must be true")
	var conservative_res: Dictionary = main_2.get_last_domain_release_result()
	assert_false(bool(conservative_res.get("ok", true)), "Exit during active transaction must refuse release conservatively: %s" % str(conservative_res))
	assert_eq(String(conservative_res.get("reason", "")), "busy")
	assert_false(coord_2.get_receipt(&"p104_op_2").is_empty(), "Receipt must NOT be destroyed when exit occurred during active transaction")
	assert_eq(mgr_2.get_physical_amount(&"wood"), 4, "Piles must NOT be forcibly destroyed during active transaction")

	# Clean up the preserved domain safely after transaction ends so root World3D stays clean.
	mgr_2.cleanup()
	var domains_live: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {}) as Dictionary
	domains_live.erase(&"default")
	if domains_live.is_empty():
		world.remove_meta(ReservedWithdrawalCoordinator.DOMAIN_META)
	else:
		world.set_meta(ReservedWithdrawalCoordinator.DOMAIN_META, domains_live)
	_active_mains.erase(main_2)
	main_2.free()


# ==============================================================================
# P5 TESTS — Safe Temporary Worker Removal
# ==============================================================================

func test_p5_01_normal_removal_cargo_refusal_and_recovery_after_delivery() -> void:
	var ctx: Dictionary = await _boot_main_on_root()
	var world: World3D = ctx["world"] as World3D
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var units_root: Node3D = ctx["units_root"] as Node3D
	var ctrl: TemporaryTestWorkersController = ctx["workers_ctrl"] as TemporaryTestWorkersController

	# 1. Normal removal of idle empty Worker3/Worker4 (must also NOT create DOMAIN_META).
	var spawn_1: Dictionary = ctrl.spawn_temporary_workers()
	assert_true(bool(spawn_1.get("ok", false)), str(spawn_1))
	assert_eq(units_root.get_child_count(), 4)
	var check_idle: Dictionary = ctrl.can_remove_temporary_workers()
	assert_true(bool(check_idle.get("can_remove", false)), str(check_idle))
	assert_false(world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META), "can_remove check must never create RegionalAuthority")
	var rem_1: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_true(bool(rem_1.get("ok", false)), str(rem_1))
	await get_tree().process_frame
	assert_eq(units_root.get_child_count(), 2)
	assert_false(world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))

	# 2. Refusal when Worker3 carries provenance cargo -> then succeeds after delivery.
	var spawn_2: Dictionary = ctrl.spawn_temporary_workers()
	assert_true(bool(spawn_2.get("ok", false)), str(spawn_2))
	var w3: Unit = (spawn_2["workers"] as Array)[0] as Unit
	var w4: Unit = (spawn_2["workers"] as Array)[1] as Unit
	assert_true(w3.get_carry_load().enable_provenance(&"p501_w3"))
	assert_true(w4.get_carry_load().enable_provenance(&"p501_w4"))
	assert_true(bool(CarryFixture.add_lot(w3.get_carry_load(), &"p501_g", &"p501_l", &"wood", WOOD.unit_weight, 3, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))

	var blocked: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_false(bool(blocked.get("ok", true)))
	assert_eq(String(blocked.get("reason", "")), "cargo_in_backpack")
	assert_eq(units_root.get_child_count(), 4)
	assert_eq(w3.get_carry_load().get_amount(&"wood"), 3)

	w3.global_position = camp.global_position
	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var del_res: Dictionary = camp_coord.execute_selective_camp_delivery(inv, camp, w3, &"default", &"p501_del", [])
	assert_true(bool(del_res.get("ok", false)), str(del_res))
	assert_true(w3.get_carry_load().is_empty())

	var rem_2: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_true(bool(rem_2.get("ok", false)), str(rem_2))
	await get_tree().process_frame
	assert_eq(units_root.get_child_count(), 2)
	assert_eq(inv.get_physical_amount(&"wood"), 3, "Delivered wood preserved in camp")


func test_p5_02_transit_claim_refusal_inside_and_outside_default_sites_root() -> void:
	var ctx: Dictionary = await _boot_main_on_root()
	var main: MainScene = ctx["main"] as MainScene
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var manager: GroundPileManager = ctx["manager"] as GroundPileManager
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var sites_root: Node3D = ctx["sites_root"] as Node3D
	var units_root: Node3D = ctx["units_root"] as Node3D
	var ctrl: TemporaryTestWorkersController = ctx["workers_ctrl"] as TemporaryTestWorkersController

	assert_true(inv.deposit(&"wood", 8))
	var spawn_res: Dictionary = ctrl.spawn_temporary_workers()
	assert_true(bool(spawn_res.get("ok", false)), str(spawn_res))
	var w3: Unit = (spawn_res["workers"] as Array)[0] as Unit
	var w4: Unit = (spawn_res["workers"] as Array)[1] as Unit
	assert_true(w3.get_carry_load().enable_provenance(&"p502_w3"))
	assert_true(w4.get_carry_load().enable_provenance(&"p502_w4"))
	var defs: Dictionary = {&"wood": WOOD, &"stone": STONE, &"food": FOOD}

	# A. Claim on valid ConstructionSite INSIDE _construction_sites_root
	var inside_site := ConstructionSite.new()
	sites_root.add_child(inside_site)
	inside_site.global_position = Vector3(-6.0, 0.0, 2.0)
	assert_true(inside_site.configure(&"p502_in_site", &"p502_in_res", _make_custom_building_def(&"p502_in_def", {&"wood": 4}), inv, defs, &"default"))
	assert_true(inv.reserve_batch(&"p502_in_res", {&"wood": 4}))
	var pile_1: GroundResourcePile = manager.get_piles_for_resource(&"wood")[0]
	w3.issue_order(ConstructOrder.new(inside_site, camp, 1.45, 0.1, true))
	assert_eq(inside_site.claim_pickup(w3, pile_1.pile_id, &"wood", 4), 4)
	w3.global_position = manager.get_pile_world_position(pile_1)
	var w_coord := ReservedWithdrawalCoordinator.new()
	assert_true(bool(w_coord.execute_reserved_withdrawal(inside_site, w3, pile_1.pile_id, &"wood", 4, &"p502_wd_in", &"p502_lot_in").get("ok", false)))

	var check_in: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_false(bool(check_in.get("ok", true)), "Must refuse removal with transit claim inside default sites root")
	assert_eq(String(check_in.get("reason", "")), "transit_claim_active", str(check_in))
	assert_eq(inside_site.get_transit_claim_for_unit(w3), {&"wood": 4})
	assert_eq(units_root.get_child_count(), 4)

	# Deliver inside_site so w3 is free again.
	w3.global_position = _site_dropoff_pos(inside_site)
	var site_coord := SelectiveSiteDeliveryCoordinator.new()
	assert_true(bool(site_coord.execute_selective_site_delivery(inside_site, w3, &"p502_sd_in", {&"wood": 4}).get("ok", false)))
	w3.cancel_current_order("test_switch")

	# B. Claim on valid ConstructionSite mounted OUTSIDE _construction_sites_root
	var external_parent := Node3D.new()
	external_parent.name = "OutsideSitesContainer"
	main.add_child(external_parent)
	_extra_nodes.append(external_parent)
	var outside_site := ConstructionSite.new()
	external_parent.add_child(outside_site)
	outside_site.global_position = Vector3(6.0, 0.0, 2.0)
	assert_true(outside_site.configure(&"p502_out_site", &"p502_out_res", _make_custom_building_def(&"p502_out_def", {&"wood": 4}), inv, defs, &"default"))
	assert_true(inv.reserve_batch(&"p502_out_res", {&"wood": 4}))
	var pile_2: GroundResourcePile = manager.get_piles_for_resource(&"wood")[0]
	w4.issue_order(ConstructOrder.new(outside_site, camp, 1.45, 0.1, true))
	assert_eq(outside_site.claim_pickup(w4, pile_2.pile_id, &"wood", 4), 4)
	w4.global_position = manager.get_pile_world_position(pile_2)
	assert_true(bool(w_coord.execute_reserved_withdrawal(outside_site, w4, pile_2.pile_id, &"wood", 4, &"p502_wd_out", &"p502_lot_out").get("ok", false)))

	var check_out: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_false(bool(check_out.get("ok", true)), "Must refuse removal with transit claim OUTSIDE default sites root")
	assert_eq(String(check_out.get("reason", "")), "transit_claim_active", str(check_out))
	assert_eq(outside_site.get_transit_claim_for_unit(w4), {&"wood": 4})
	assert_eq(w4.get_carry_load().get_amount(&"wood"), 4)
	assert_eq(units_root.get_child_count(), 4)

	# Deliver outside_site -> obligations cleared -> removal now succeeds cleanly!
	w4.global_position = _site_dropoff_pos(outside_site)
	var sd_out_res: Dictionary = site_coord.execute_selective_site_delivery(outside_site, w4, &"p502_sd_out", {&"wood": 4})
	assert_true(bool(sd_out_res.get("ok", false)), "p502 sd_out: %s" % str(sd_out_res))
	var rem_ok: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_true(bool(rem_ok.get("ok", false)), "Removal must succeed once obligations are cleared: %s" % str(rem_ok))
	await get_tree().process_frame
	assert_eq(units_root.get_child_count(), 2)
	assert_eq(inside_site.get_delivered_buffer_amount(&"wood"), 4)
	assert_eq(outside_site.get_delivered_buffer_amount(&"wood"), 4)


func test_p5_03_transactional_lock_and_post_commit_reentrancy_with_empty_backpack() -> void:
	var ctx: Dictionary = await _boot_main_on_root()
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var manager: GroundPileManager = ctx["manager"] as GroundPileManager
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var sites_root: Node3D = ctx["sites_root"] as Node3D
	var units_root: Node3D = ctx["units_root"] as Node3D
	var leader_a: Unit = ctx["leader_a"] as Unit
	var ctrl: TemporaryTestWorkersController = ctx["workers_ctrl"] as TemporaryTestWorkersController

	var spawn_res: Dictionary = ctrl.spawn_temporary_workers()
	assert_true(bool(spawn_res.get("ok", false)), str(spawn_res))
	var w3: Unit = (spawn_res["workers"] as Array)[0] as Unit
	var w4: Unit = (spawn_res["workers"] as Array)[1] as Unit
	assert_true(w3.get_carry_load().enable_provenance(&"p503_w3"))
	assert_true(w4.get_carry_load().enable_provenance(&"p503_w4"))
	assert_true(leader_a.get_carry_load().enable_provenance(&"p503_la"))

	# 1. Reentrant removal during post-commit signal when w3's backpack JUST became empty!
	assert_true(bool(CarryFixture.add_lot(w3.get_carry_load(), &"p503_g", &"p503_l", &"wood", WOOD.unit_weight, 4, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	w3.global_position = camp.global_position
	var reentrant_preflight: Array[Dictionary] = []
	var reentrant_remove: Array[Dictionary] = []
	var on_w3_load := func() -> void:
		if w3.get_carry_load().is_empty():
			reentrant_preflight.append(ctrl.can_remove_temporary_workers())
			reentrant_remove.append(ctrl.remove_temporary_workers_safely())
	w3.get_carry_load().load_changed.connect(on_w3_load)
	_connections.append([w3.get_carry_load().load_changed, on_w3_load])

	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var del_res: Dictionary = camp_coord.execute_selective_camp_delivery(inv, camp, w3, &"default", &"p503_camp_del", [])
	assert_true(bool(del_res.get("ok", false)), str(del_res))
	assert_eq(reentrant_preflight.size(), 1)
	assert_eq(reentrant_remove.size(), 1)
	assert_false(bool(reentrant_preflight[0].get("can_remove", true)), "Preflight during post-commit signal must refuse: %s" % str(reentrant_preflight[0]))
	assert_false(bool(reentrant_remove[0].get("ok", true)), "Removal during post-commit signal must refuse: %s" % str(reentrant_remove[0]))
	assert_true(is_instance_valid(w3) and w3.is_inside_tree() and not w3.is_queued_for_deletion())
	assert_true(is_instance_valid(w4) and w4.is_inside_tree() and not w4.is_queued_for_deletion())
	assert_eq(units_root.get_child_count(), 4)
	assert_eq(inv.get_physical_amount(&"wood"), 4)

	# 2. Refusal while RegionalAuthority is executing a transaction for ANOTHER unit (LeaderA)
	#    even though Worker3 and Worker4 are both completely empty and idle!
	var site := ConstructionSite.new()
	sites_root.add_child(site)
	site.global_position = Vector3(-6.0, 0.0, 2.0)
	var defs: Dictionary = {&"wood": WOOD, &"stone": STONE, &"food": FOOD}
	assert_true(site.configure(&"p503_site", &"p503_res", _make_custom_building_def(&"p503_def", {&"wood": 4}), inv, defs, &"default"))
	assert_true(inv.reserve_batch(&"p503_res", {&"wood": 4}))
	var pile: GroundResourcePile = manager.get_piles_for_resource(&"wood")[0]
	leader_a.issue_order(ConstructOrder.new(site, camp, 1.45, 0.1, true))
	assert_eq(site.claim_pickup(leader_a, pile.pile_id, &"wood", 4), 4)
	leader_a.global_position = manager.get_pile_world_position(pile)

	var regional_busy_results: Array[Dictionary] = []
	var on_site_state := func(_s: ConstructionSite) -> void:
		regional_busy_results.append(ctrl.remove_temporary_workers_safely())
	site.state_changed.connect(on_site_state, CONNECT_ONE_SHOT)
	_connections.append([site.state_changed, on_site_state])

	var w_coord := ReservedWithdrawalCoordinator.new()
	var wd_res: Dictionary = w_coord.execute_reserved_withdrawal(site, leader_a, pile.pile_id, &"wood", 4, &"p503_wd", &"p503_wd_lot")
	assert_true(bool(wd_res.get("ok", false)), str(wd_res))
	assert_eq(regional_busy_results.size(), 1)
	assert_false(bool(regional_busy_results[0].get("ok", true)), "Removal while RegionalAuthority is executing must be refused: %s" % str(regional_busy_results[0]))
	assert_eq(units_root.get_child_count(), 4)

	# 3. After transactions finish, idle empty Worker3/Worker4 can be removed normally.
	var ok_after: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_true(bool(ok_after.get("ok", false)), "Removal must succeed once transactions finish: %s" % str(ok_after))
	await get_tree().process_frame
	assert_eq(units_root.get_child_count(), 2)
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), 4)
	assert_eq(site.get_transit_claim_for_unit(leader_a), {&"wood": 4})


func test_p5_04_uncancellable_order_no_partial_removal_and_multi_region_isolation() -> void:
	var ctx: Dictionary = await _boot_main_on_root()
	var main: MainScene = ctx["main"] as MainScene
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var units_root: Node3D = ctx["units_root"] as Node3D
	var ctrl: TemporaryTestWorkersController = ctx["workers_ctrl"] as TemporaryTestWorkersController

	var spawn_res: Dictionary = ctrl.spawn_temporary_workers()
	assert_true(bool(spawn_res.get("ok", false)), str(spawn_res))
	var w3: Unit = (spawn_res["workers"] as Array)[0] as Unit
	var w4: Unit = (spawn_res["workers"] as Array)[1] as Unit
	assert_true(w3.get_carry_load().enable_provenance(&"p504_w3"))
	assert_true(w4.get_carry_load().enable_provenance(&"p504_w4"))

	# 1. Worker3 holds a cancellable order while Worker4 holds a NonCancellableOrder ->
	#    safe failure, w4's order stays intact, ZERO partial removal (both w3 and w4 remain in tree).
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.source_id = &"p504_bush"
	bush.initial_amount = 6
	main.add_child(bush)
	_extra_nodes.append(bush)
	bush.global_position = Vector3(-2.5, 0.0, -3.5)
	w3.global_position = Vector3(-4.0, 0.0, -3.5)
	w3.issue_order(GatherResourceOrder.new(bush, camp, inv, 0.25, 0.25, true, &"default"))
	assert_true(bush.is_worker_reserved(w3))

	var stuck := NonCancellableOrder.new()
	w4.issue_order(stuck)
	assert_true(stuck.is_active())

	var fail_res: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_false(bool(fail_res.get("ok", true)), "Must fail when Worker4 order cannot cancel: %s" % str(fail_res))
	assert_eq(String(fail_res.get("reason", "")), "order_cancel_failed")
	assert_eq(stuck.cancel_attempts, 1)
	assert_eq(w4.get_current_order(), stuck, "Unit.cancel_current_order must preserve uncancelled active order")
	assert_true(is_instance_valid(w3) and w3.is_inside_tree() and not w3.is_queued_for_deletion(), "No partial removal of Worker3")
	assert_true(is_instance_valid(w4) and w4.is_inside_tree() and not w4.is_queued_for_deletion(), "Worker4 must remain alive")
	assert_eq(units_root.get_child_count(), 4)

	# Finish stuck order so w4 becomes clean.
	stuck.mark_cancelled("test_release_stuck")
	w4.cancel_current_order("test_clear_stuck")
	assert_null(w4.get_current_order())

	# 2. Reentrant cargo injection during w3's order_finished callback -> Phase 3 revalidation aborts with ZERO partial removal!
	w3.issue_order(GatherResourceOrder.new(bush, camp, inv, 0.25, 0.25, true, &"default"))
	var injected_cargo: Array[bool] = [false]
	var on_w3_order_finished := func(_ord: UnitOrder) -> void:
		if not injected_cargo[0]:
			injected_cargo[0] = true
			CarryFixture.add_lot(w4.get_carry_load(), &"p504_inj_g", &"p504_inj_l", &"wood", WOOD.unit_weight, 1, CarryProvenanceLedger.FREE_GATHERED)
	w3.order_finished.connect(on_w3_order_finished, CONNECT_ONE_SHOT)
	_connections.append([w3.order_finished, on_w3_order_finished])

	var reval_fail: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_true(injected_cargo[0], "Post-cancel cargo injection callback must have run")
	assert_false(bool(reval_fail.get("ok", true)), "Post-cancel revalidation must block removal if cargo appeared: %s" % str(reval_fail))
	assert_eq(String(reval_fail.get("reason", "")), "cargo_in_backpack")
	assert_eq(units_root.get_child_count(), 4, "Zero partial removal when post-cancel revalidation fails")
	assert_eq(w4.get_carry_load().get_amount(&"wood"), 1, "Injected cargo preserved")

	# Deliver w4's 1 wood to camp so w3 & w4 are empty again.
	w4.global_position = camp.global_position
	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	assert_true(bool(camp_coord.execute_selective_camp_delivery(inv, camp, w4, &"default", &"p504_clear_w4", []).get("ok", false)))

	# 3. Duplicate provenance_unit_id in the same World3D -> conservative refusal (ambiguous_unit_identity).
	var other_fx: Dictionary = _create_external_region_fixture(get_tree().root, &"p504_other_region", Vector3(10.0, 0.0, 10.0), ctx["nav"] as WorldNavigation)
	var other_u: Unit = other_fx["unit"] as Unit
	assert_true(other_u.get_carry_load().enable_provenance(&"p504_w3"))
	var dup_id_check: Dictionary = ctrl.can_remove_temporary_workers()
	assert_false(bool(dup_id_check.get("can_remove", true)), "Duplicate provenance_unit_id in same World3D must fail conservatively")
	assert_eq(String(dup_id_check.get("reason", "")), "ambiguous_unit_identity")

	# 4. Separate region with its OWN distinct unit & active site claim does NOT falsely confuse/block Region A removal.
	var other_u2: Unit = UNIT_SCENE.instantiate() as Unit
	other_u2.name = "DistinctOtherRegionUnit"
	other_u2.definition = LEADER_A_DEF
	(other_fx["host"] as Node3D).add_child(other_u2)
	other_u2.set_world_navigation(ctx["nav"] as WorldNavigation)
	other_u2.global_position = (other_fx["camp"] as CampStorageZone).global_position
	assert_true(other_u2.get_carry_load().enable_provenance(&"p504_other_unique_unit"))
	# Free the duplicate-ID unit so identity is unambiguous.
	other_u.get_parent().remove_child(other_u)
	other_u.free()

	var other_inv: SettlementInventory = other_fx["inventory"] as SettlementInventory
	var other_mgr: GroundPileManager = other_fx["manager"] as GroundPileManager
	var other_camp: CampStorageZone = other_fx["camp"] as CampStorageZone
	assert_true(other_inv.deposit(&"wood", 4))
	var other_site := ConstructionSite.new()
	(other_fx["host"] as Node3D).add_child(other_site)
	other_site.global_position = Vector3(12.0, 0.0, 6.0)
	assert_true(other_site.configure(&"p504_osite", &"p504_ores", _make_custom_building_def(&"p504_odef", {&"wood": 4}), other_inv, other_fx["defs"] as Dictionary, &"p504_other_region"))
	assert_true(other_inv.reserve_batch(&"p504_ores", {&"wood": 4}))
	var other_pile: GroundResourcePile = other_mgr.get_piles_for_resource(&"wood")[0]
	other_u2.issue_order(ConstructOrder.new(other_site, other_camp, 1.45, 0.1, true))
	assert_eq(other_site.claim_pickup(other_u2, other_pile.pile_id, &"wood", 4), 4)
	other_u2.global_position = other_mgr.get_pile_world_position(other_pile)
	var other_wcoord := ReservedWithdrawalCoordinator.new()
	var other_wd_res: Dictionary = other_wcoord.execute_reserved_withdrawal(other_site, other_u2, other_pile.pile_id, &"wood", 4, &"p504_owd", &"p504_olot")
	assert_true(bool(other_wd_res.get("ok", false)), "p504 other_wd: %s" % str(other_wd_res))
	assert_eq(other_site.get_transit_claim_for_unit(other_u2), {&"wood": 4})

	# Region A's idle empty Worker3/Worker4 must still be removable despite other_region's active site claim on other_u2!
	var final_rem: Dictionary = ctrl.remove_temporary_workers_safely()
	assert_true(bool(final_rem.get("ok", false)), "Other region's claim on another unit must not block Region A removal: %s" % str(final_rem))
	await get_tree().process_frame
	assert_eq(units_root.get_child_count(), 2)
	assert_eq(other_site.get_transit_claim_for_unit(other_u2), {&"wood": 4}, "Other region claim preserved untouched")
	assert_eq(bush.get_active_worker_count(), 0, "Source slot cleanly released")
