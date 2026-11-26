extends "res://tests/framework/selective_site_delivery_fixture.gd"
## T3.6.2-C3.4.2 adversarial integration suite for atomic selective camp delivery commits.
## Covers Groups A-F (Scenarios 1-70), global physical/accounting conservation, CampStorageZone
## config-revision anti-ABA, detached node lifecycle safety, and cross-coordinator isolation.
##
## Notes on private state access in adversarial tests:
## - `_fault_at`, `_piles`, `_next_pile_id`, `_ledger`, `_is_preparing_withdrawal`, `_is_delivering`,
##   `_provenance_busy`, `_coordinator_transaction_locked`, `_is_preparing_or_transacting`, `_site_state`,
##   `_generation`, and `RegionalAuthority` fields are accessed strictly to inject faults, verify guard
##   release, and confirm exact state/revision invariants.

const CampPlanner = preload("res://src/economy/selective_camp_delivery_planner.gd")
const CampCoordinator = preload("res://src/economy/selective_camp_delivery_coordinator.gd")
const SiteCoordinator = preload("res://src/economy/selective_site_delivery_coordinator.gd")
const DEFAULT_REGION: StringName = &"c342_region"
const MAX_NAV_WAIT_FRAMES: int = 120


func _nav_fixture(region: StringName = DEFAULT_REGION) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_test_child(viewport)

	var host := Node3D.new()
	viewport.add_child(host)

	# Real flat terrain collider so WorldNavigation bakes an authentic NavigationMesh in this World3D.
	var terrain := StaticBody3D.new()
	terrain.collision_layer = CollisionLayers.MASK_TERRAIN
	terrain.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(44.0, 1.0, 44.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	terrain.add_child(floor_shape)
	host.add_child(terrain)

	var nav := WorldNavigation.new()
	nav.source_root_path = ^".."
	nav.auto_bake_on_ready = true
	nav.map_bounds = Rect2(-22.0, -22.0, 44.0, 44.0)
	host.add_child(nav)

	var frames: int = 0
	while not nav.is_navigation_ready() and frames < MAX_NAV_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	assert_true(nav.is_navigation_ready(), "WorldNavigation must bake cleanly in fixture")

	var zone := CampStorageZone.new()
	zone.position = Vector3(-8.0, 0.0, -8.0)
	zone.zone_bounds_half_extents = Vector2(6.0, 6.0)
	zone.set_world_navigation(nav)
	host.add_child(zone)

	var pile_root := Node3D.new()
	var site_root := Node3D.new()
	host.add_child(pile_root)
	host.add_child(site_root)

	var definitions := {&"wood": WOOD.duplicate(), &"stone": STONE.duplicate(), &"food": FOOD.duplicate()}
	var manager := GroundPileManager.new(definitions, zone, pile_root, SimulatedWorldTimeProvider.new(0))
	_managers.append(manager)
	var inventory := SettlementInventory.new(manager)
	var construction := ConstructionManager.new()
	host.add_child(construction)
	construction.configure(site_root, inventory, definitions, zone, nav, region)

	var slots := zone.get_candidate_slots()
	var wood := manager.try_create_pile_at(&"wood", 20, slots[0])
	var stone := manager.try_create_pile_at(&"stone", 8, slots[1])
	assert_not_null(wood)
	assert_not_null(stone)

	return {
		"host": host,
		"viewport": viewport,
		"nav": nav,
		"zone": zone,
		"pile_root": pile_root,
		"manager": manager,
		"inventory": inventory,
		"cm": construction,
		"wood": wood,
		"stone": stone,
		"coordinator": ReservedWithdrawalCoordinator.new(),
		"camp_coord": CampCoordinator.new(),
		"site_coord": SiteCoordinator.new(),
		"region": region,
	}


func _nav_unit(fx: Dictionary, id: StringName, use_provenance: bool = true) -> Unit:
	var unit := _unit(fx, id, use_provenance)
	unit.set_world_navigation(fx.nav as WorldNavigation)
	_place_at_camp(fx, unit)
	return unit


func _place_at_camp(fx: Dictionary, unit: Unit, offset: Vector3 = Vector3.ZERO) -> void:
	var zone: CampStorageZone = fx.zone as CampStorageZone
	var slot0: Vector3 = zone.get_candidate_slots()[0]
	unit.global_position = slot0 + offset


func _gather_res(
	fx: Dictionary,
	unit: Unit,
	res_def: ResourceDefinition,
	amount: int,
	op_id: StringName,
	lot_id: StringName
) -> void:
	var source := ResourceSource.new()
	fx.host.add_child(source)
	var cap: int = maxi(amount, 10)
	source.configure(StringName("src_" + String(lot_id)), res_def.duplicate() as ResourceDefinition, cap, cap, 2)
	# This delivery fixture seeds legitimate cargo through the extraction API.
	if source.get_category() == ResourceDefinition.Category.WOOD:
		source.set(&"_tree_harvest_stage", ResourceSource.TreeHarvestStage.FALLEN)
	var outcome: Dictionary = source.transfer_to_carry_load_with_provenance(
		unit.get_carry_load(), op_id, lot_id, amount
	)
	assert_true(bool(outcome.get("ok", false)), str(outcome))
	assert_eq(int(outcome.get("extracted", 0)), amount, str(outcome))


func _withdraw_then_camp(fx: Dictionary, site: ConstructionSite, unit: Unit, pile: GroundResourcePile, quantity: int, lot: StringName) -> void:
	_withdraw(fx, site, unit, pile, quantity, lot)
	_place_at_camp(fx, unit)


func _full_snapshot(fx: Dictionary, sites: Array[ConstructionSite], unit: Unit) -> Dictionary:
	var base := _snapshot(fx, sites, unit)
	var world := unit.get_world_3d()
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var serials: Dictionary = {}
	for r_key: Variant in domains.keys():
		var auth := domains[r_key] as ReservedWithdrawalCoordinator.RegionalAuthority
		if auth != null:
			serials[r_key] = auth.construction_transfer_serial
	var load := unit.get_carry_load()
	base["next_pile_id"] = fx.manager._next_pile_id
	base["raw_piles_count"] = fx.manager._piles.size()
	base["authority_serials"] = serials
	base["load_connections"] = load.load_changed.get_connections().size()
	base["pile_root_children"] = (fx.pile_root as Node3D).get_child_count()
	return base


func _assert_economic_equal_ignoring_revisions(actual: Dictionary, expected: Dictionary, label: String = "") -> void:
	assert_eq(actual["physical"], expected["physical"], label + " physical")
	assert_eq(actual["reservations"], expected["reservations"], label + " reservations")
	assert_eq(actual["cargo"], expected["cargo"], label + " cargo")
	assert_eq(actual["next_pile_id"], expected["next_pile_id"], label + " next_pile_id")
	assert_eq(actual["raw_piles_count"], expected["raw_piles_count"], label + " raw_piles_count")
	assert_eq(actual["pile_root_children"], expected["pile_root_children"], label + " pile_root_children")
	assert_eq(actual["nodes"], expected["nodes"], label + " nodes")
	assert_eq(actual["receipts"], expected["receipts"], label + " receipts")
	assert_eq(actual["authority_serials"], expected["authority_serials"], label + " authority_serials")
	assert_eq(actual["load_connections"], expected["load_connections"], label + " load_connections")
	var actual_piles: Array = actual["piles"]
	var expected_piles: Array = expected["piles"]
	assert_eq(actual_piles.size(), expected_piles.size(), label + " piles count")
	for i: int in range(mini(actual_piles.size(), expected_piles.size())):
		# Compare [instance_id, amount, elapsed, accum] ignoring revision at index 4
		assert_eq(actual_piles[i][0], expected_piles[i][0], label + " pile inst")
		assert_eq(actual_piles[i][1], expected_piles[i][1], label + " pile amount")
		assert_near(float(actual_piles[i][2]), float(expected_piles[i][2]), 0.0001, label + " pile elapsed")
		assert_near(float(actual_piles[i][3]), float(expected_piles[i][3]), 0.0001, label + " pile accum")
	var actual_sites: Array = actual["sites"]
	var expected_sites: Array = expected["sites"]
	assert_eq(actual_sites.size(), expected_sites.size(), label + " sites count")
	for i: int in range(mini(actual_sites.size(), expected_sites.size())):
		for k: String in ["state", "substate", "generation", "progress", "buffer", "consumed", "claims", "pending", "workers"]:
			assert_eq(actual_sites[i][k], expected_sites[i][k], label + " site." + k)


func _assert_guards_released(fx: Dictionary, sites: Array[ConstructionSite], unit: Unit) -> void:
	var world := unit.get_world_3d()
	var domains: Dictionary = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var auth := domains.get(fx.region) as ReservedWithdrawalCoordinator.RegionalAuthority
	if auth != null:
		assert_false(auth.is_executing, "authority.is_executing must be false")
		assert_null(auth.active_camp_delivery, "authority.active_camp_delivery must be null")
		assert_null(auth.active_delivery, "authority.active_delivery must be null")
	assert_false(fx.inventory._is_delivering, "inventory._is_delivering must be false")
	assert_false(fx.manager._is_preparing_withdrawal, "storage._is_preparing_withdrawal must be false")
	assert_false(fx.manager._is_mutating, "storage._is_mutating must be false")
	assert_false(fx.manager._is_notifying, "storage._is_notifying must be false")
	var load := unit.get_carry_load()
	assert_false(load._provenance_busy, "load._provenance_busy must be false")
	assert_false(load._coordinator_transaction_locked, "load._coordinator_transaction_locked must be false")
	for site: ConstructionSite in sites:
		assert_false(site._is_preparing_or_transacting, "site._is_preparing_or_transacting must be false")
		assert_false(site._suppress_coordinator_signal_echo, "site._suppress_coordinator_signal_echo must be false")


func _assert_global_conservation(
	before_snap: Dictionary,
	after_snap: Dictionary,
	fx: Dictionary,
	sites: Array[ConstructionSite]
) -> void:
	var before_phys: Dictionary = before_snap["physical"] as Dictionary
	var after_phys: Dictionary = after_snap["physical"] as Dictionary
	var before_carry: Dictionary = before_snap["cargo"]["amounts"] as Dictionary
	var after_carry: Dictionary = after_snap["cargo"]["amounts"] as Dictionary
	var res_keys: Dictionary = {}
	for d: Dictionary in [before_phys, after_phys, before_carry, after_carry]:
		for k: Variant in d.keys():
			res_keys[k] = true
	for k: Variant in res_keys.keys():
		var total_b: int = int(before_phys.get(k, 0)) + int(before_carry.get(k, 0))
		var total_a: int = int(after_phys.get(k, 0)) + int(after_carry.get(k, 0))
		assert_eq(total_a, total_b, "Global physical conservation violated for " + str(k))
	for site: ConstructionSite in sites:
		if not site.is_active():
			continue
		var acc := Planner._read_accounting(site)
		assert_true(bool(acc.get("ok", false)), "Site accounting broken: " + str(acc))
		var by_res: Dictionary = acc["by_resource"] as Dictionary
		for res_id: Variant in by_res.keys():
			var row: Dictionary = by_res[res_id] as Dictionary
			var sum_row: int = int(row["reserved"]) + int(row["transit"]) + int(row["buffer"]) + int(row["consumed"]) + int(row["missing"])
			assert_eq(sum_row, int(row["required"]), "Site equation broken for " + str(res_id))
	# Verify no pile reservation exceeds physical amount
	for pile: GroundResourcePile in fx.manager.get_piles():
		assert_true(fx.manager.get_pile_reserved_amount(pile.pile_id) <= pile.amount)


# ------------------------------------------------------------------------------
# GROUP A — FREE DELIVERY (Scenarios 1-10)
# ------------------------------------------------------------------------------

func test_group_a_free_delivery_full_partial_multi_resource_two_lots_and_conservative_default() -> void:
	# Scenarios 1 (full wood), 2 (partial wood), 3 (wood+stone), 4 (two wood lots),
	# 5 (conservative empty default), 6 (residual backpack), 7 (residual weight), 8 (physical merge + exposure)
	var fx: Dictionary = await _nav_fixture()
	var site_a := _create_site(fx, &"site_a_group_a", {&"wood": 6})
	var unit := _nav_unit(fx, &"worker_a1")
	var empty_sites: Array[ConstructionSite] = [site_a]

	# Give unit a SITE_RESERVED wood lot AND free wood/stone lots
	_withdraw_then_camp(fx, site_a, unit, fx.wood, 3, &"res_a_keep")
	_gather_res(fx, unit, WOOD, 4, &"op_g_w1", &"free_w1")
	_gather_res(fx, unit, WOOD, 6, &"op_g_w2", &"free_w2")
	_gather_res(fx, unit, STONE, 3, &"op_g_s1", &"free_s1")
	fx.wood.apply_state(17, 20.0, 2.0)

	# Scenario 2 + 6 + 7 + 8: partial wood delivery (3 of 6 from free_w2) merges into existing wood pile
	var snap1 := _full_snapshot(fx, empty_sites, unit)
	var res_partial: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, DEFAULT_REGION, &"op_a_partial",
		[{"lot_id": &"free_w2", "amount": 3}]
	)
	assert_true(bool(res_partial.get("ok", false)), str(res_partial))
	assert_false(bool(res_partial.get("replayed", true)))
	assert_eq(int(res_partial.get("delivered_now", 0)), 3)
	assert_eq(res_partial.get("delivered_amounts"), {&"wood": 3})
	assert_eq(fx.wood.amount, 20)
	assert_near(fx.wood.elapsed_exposure_sec, 20.0 * (17.0 / 20.0), 0.001)
	assert_eq(unit.get_carry_load().get_amount(&"wood"), 10)
	assert_eq(unit.get_carry_load().get_amount(&"stone"), 3)
	var expected_weight := 10 * WOOD.unit_weight + 3 * STONE.unit_weight
	assert_eq(unit.get_carry_load().get_current_weight(), expected_weight)
	assert_true(unit.get_carry_load().validate_provenance())
	var after1 := _full_snapshot(fx, empty_sites, unit)
	_assert_global_conservation(snap1, after1, fx, empty_sites)
	_assert_guards_released(fx, empty_sites, unit)

	# Scenarios 1 + 3 + 4 + 5: empty request [] delivers BOTH remaining free wood lots (4 + 3 = 7)
	# AND stone (3) while leaving SITE_RESERVED res_a_keep (3 wood) untouched in backpack!
	var snap2 := _full_snapshot(fx, empty_sites, unit)
	var res_default: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, DEFAULT_REGION, &"op_a_default", []
	)
	assert_true(bool(res_default.get("ok", false)), str(res_default))
	assert_eq(int(res_default.get("delivered_now", 0)), 10)
	assert_eq(res_default.get("delivered_amounts"), {&"stone": 3, &"wood": 7})
	assert_eq(fx.wood.amount, 27)
	assert_eq(fx.stone.amount, 11)
	assert_eq(unit.get_carry_load().get_amount(&"wood"), 3)
	assert_eq(unit.get_carry_load().get_amount(&"stone"), 0)
	var rem_lots: Dictionary = unit.get_carry_load().provenance_snapshot()["ledger"]["lots"]
	assert_eq(rem_lots.size(), 1)
	assert_true(rem_lots.has(&"res_a_keep"))
	assert_eq(int(rem_lots[&"res_a_keep"]["quantity"]), 3)
	assert_eq(site_a._read_transit_claim_for_unit_pure(unit.get_instance_id()), {&"wood": 3})
	var after2 := _full_snapshot(fx, empty_sites, unit)
	_assert_global_conservation(snap2, after2, fx, empty_sites)
	_assert_guards_released(fx, empty_sites, unit)


func test_group_a_free_delivery_new_pile_and_multiple_new_piles_and_commit_prepared() -> void:
	# Scenarios 9 (new pile creation), 10 (multiple new piles) + commit_prepared_selective_camp_delivery
	# + §14.1 CampStorageZone config_revision ABA protection
	var fx: Dictionary = await _nav_fixture()
	var zone: CampStorageZone = fx.zone
	var unit := _nav_unit(fx, &"worker_a9")
	var empty_sites: Array[ConstructionSite] = []
	_gather_res(fx, unit, FOOD, 9, &"op_g_f9", &"free_food_9")

	# Scenario 9: commit_prepared creates 1 new physical food pile attached to _piles_root
	var prep1 := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_a9_one",
		[{"lot_id": &"free_food_9", "amount": 4}]
	)
	assert_true(bool(prep1.get("ok", false)), str(prep1))
	var snap_before := _full_snapshot(fx, empty_sites, unit)
	var commit1: Dictionary = fx.camp_coord.commit_prepared_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, prep1
	)
	assert_true(bool(commit1.get("ok", false)), str(commit1))
	assert_eq(int(commit1.get("delivered_now", 0)), 4)
	assert_eq((commit1["created_pile_ids"] as Array).size(), 1)
	var new_pid: int = int(commit1["created_pile_ids"][0])
	var new_pile: GroundResourcePile = fx.manager.get_pile_by_id(new_pid)
	assert_not_null(new_pile)
	assert_true(new_pile.is_inside_tree())
	assert_eq(new_pile.get_parent(), fx.pile_root)
	assert_true(new_pile.is_in_group(GroundResourcePile.GROUP_GROUND_PILES))
	assert_eq(new_pile.amount, 4)
	assert_true(new_pile.get_visible_mesh_count() > 0)
	_assert_global_conservation(snap_before, _full_snapshot(fx, empty_sites, unit), fx, empty_sites)

	# Scenario 10: cap max_pile_amount = 2 -> remaining 5 food splits across 3 brand-new piles (since pile already has 4 >= 2)
	zone.max_pile_amount = 2
	var snap2 := _full_snapshot(fx, empty_sites, unit)
	var commit2: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_a10_multi",
		[{"lot_id": &"free_food_9", "amount": 5}]
	)
	assert_true(bool(commit2.get("ok", false)), str(commit2))
	assert_eq((commit2["created_pile_ids"] as Array).size(), 3)
	var created_sum: int = 0
	for pid_var: Variant in commit2["created_pile_ids"]:
		var cp: GroundResourcePile = fx.manager.get_pile_by_id(int(pid_var))
		assert_not_null(cp)
		assert_true(cp.is_inside_tree())
		assert_eq(cp.get_parent(), fx.pile_root)
		created_sum += cp.amount
	assert_eq(created_sum, 5)
	assert_eq(fx.inventory.get_physical_amount(&"food"), 9)
	assert_true(unit.get_carry_load().is_empty())
	_assert_global_conservation(snap2, _full_snapshot(fx, empty_sites, unit), fx, empty_sites)
	_assert_guards_released(fx, empty_sites, unit)


# ------------------------------------------------------------------------------
# GROUP B — RESERVED DELIVERY (Scenarios 11-24)
# ------------------------------------------------------------------------------

func test_group_b_reserved_delivery_site_a_atomic_restoration_and_site_b_preservation() -> void:
	# Scenarios 11-18, 20, 21: return site A lot -> claim A reduced, reservation A restored on existing pile,
	# buffer/progress/consumed of A preserved, site B reservation & backpack lot preserved.
	var fx: Dictionary = await _nav_fixture()
	var site_a := _create_site(fx, &"site_b_a", {&"wood": 8}, 6.0)
	var site_b := _create_site(fx, &"site_b_b", {&"wood": 5}, 12.0)
	var sites: Array[ConstructionSite] = [site_a, site_b]
	var unit := _nav_unit(fx, &"worker_b11")

	# Deliver 2 wood to site A's buffer and advance work progress with a real builder to verify buffer/consumed/progress preservation
	unit.set_physics_process(false)
	_arm_order(site_a, unit, false)
	_withdraw(fx, site_a, unit, fx.wood, 2, &"res_a_pre")
	unit.global_position = site_a.global_position + Vector3(0.0, 0.0, 2.2)
	var pre_del: Dictionary = fx.site_coord.execute_selective_site_delivery(site_a, unit, &"op_pre_del_a", {&"wood": 2})
	assert_true(bool(pre_del.get("ok", false)), str(pre_del))
	var builder := _nav_unit(fx, &"builder_b11", false)
	builder.set_physics_process(false)
	builder.global_position = site_a.global_position + Vector3(2.2, 0.0, 0.0)
	var b_order := ConstructOrder.new(site_a, null, false)
	b_order._unit = builder
	b_order.mark_running()
	builder._current_order = b_order
	assert_eq(site_a.register_worker(builder, b_order, false), ConstructionSite.WorkerRole.BUILDER)
	assert_true(site_a.assign_builder_slot_position(builder, site_a.get_builder_slot_index(builder), builder.global_position))
	for _step: int in range(6):
		await wait_physics_frames(1)
		var work_res: Dictionary = site_a.contribute_work(builder, 0.25)
		assert_true(bool(work_res.get("ok", false)), str(work_res))
	builder.set_physics_process(true)
	unit.set_physics_process(true)
	assert_true(site_a._work_progress_usec > 0)
	assert_true(site_a.get_consumed_amount(&"wood") > 0)
	assert_true(site_a.get_delivered_buffer_amount(&"wood") > 0)

	# Withdraw 4 wood for site A and 3 wood for site B, then move to camp
	_withdraw(fx, site_a, unit, fx.wood, 4, &"res_a_ret")
	_withdraw_then_camp(fx, site_b, unit, fx.wood, 3, &"res_b_keep")

	var buf_a_before := site_a.get_delivered_buffer_amounts()
	var cons_a_before := site_a.get_consumed_amounts()
	var prog_a_before: int = site_a._work_progress_usec
	var res_a_before: int = fx.inventory.get_reservation_amount(site_a.reservation_id, &"wood")
	var res_b_before: int = fx.inventory.get_reservation_amount(site_b.reservation_id, &"wood")
	var snap_before := _full_snapshot(fx, sites, unit)

	var outcome: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, DEFAULT_REGION, &"op_b_ret_a",
		[{"lot_id": &"res_a_ret", "amount": 4}]
	)
	assert_true(bool(outcome.get("ok", false)), str(outcome))
	assert_eq(int(outcome.get("delivered_now", 0)), 4)
	assert_eq(fx.inventory.get_reservation_amount(site_a.reservation_id, &"wood"), res_a_before + 4)
	assert_true(site_a._read_transit_claim_for_unit_pure(unit.get_instance_id()).is_empty())
	assert_eq(site_a.get_delivered_buffer_amounts(), buf_a_before)
	assert_eq(site_a.get_consumed_amounts(), cons_a_before)
	assert_eq(site_a._work_progress_usec, prog_a_before)

	# Site B completely untouched
	assert_eq(fx.inventory.get_reservation_amount(site_b.reservation_id, &"wood"), res_b_before)
	assert_eq(site_b._read_transit_claim_for_unit_pure(unit.get_instance_id()), {&"wood": 3})
	var lots_after: Dictionary = unit.get_carry_load().provenance_snapshot()["ledger"]["lots"]
	assert_eq(lots_after.size(), 1)
	assert_true(lots_after.has(&"res_b_keep"))
	assert_eq(int(lots_after[&"res_b_keep"]["quantity"]), 3)

	_assert_global_conservation(snap_before, _full_snapshot(fx, sites, unit), fx, sites)
	_assert_guards_released(fx, sites, unit)


func test_group_b_mixed_free_and_reserved_partial_and_virtual_pile_and_d3_blocked() -> void:
	# Scenarios 19 (free + reserved same resource), 22 (restoration on newly created pile),
	# 23 (partial reserved lot), 24 (non-active/D3 site blocked)
	var fx: Dictionary = await _nav_fixture()
	var zone: CampStorageZone = fx.zone
	var site_a := _create_site(fx, &"site_b22", {&"wood": 8}, 6.0)
	var site_d3 := _create_site(fx, &"site_b24", {&"wood": 4}, 12.0)
	var sites: Array[ConstructionSite] = [site_a, site_d3]
	var unit := _nav_unit(fx, &"worker_b22")

	_withdraw(fx, site_a, unit, fx.wood, 5, &"res_a22")
	_withdraw(fx, site_d3, unit, fx.wood, 2, &"res_d3_24")
	_gather_res(fx, unit, WOOD, 4, &"op_g_b22", &"free_w22")
	_place_at_camp(fx, unit)

	# Scenario 24: completed site lot cannot be returned (D3 not implemented)
	site_d3._site_state = ConstructionSite.SiteState.COMPLETED
	var r_d3: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b24_d3",
		[{"lot_id": &"res_d3_24", "amount": 2}]
	)
	assert_false(bool(r_d3.get("ok", true)))
	assert_eq(String(r_d3.get("reason", "")), "d3_cancellation_not_implemented")
	site_d3._site_state = ConstructionSite.SiteState.ACTIVE

	# Scenarios 19 + 22 + 23: cap existing wood pile at current amount so BOTH free (2) and partial reserved (3 of 5)
	# MUST land on a newly created physical pile, restoring site_a's reservation onto the new real pile_id!
	zone.max_pile_amount = fx.wood.amount
	var res_a_before: int = fx.inventory.get_reservation_amount(site_a.reservation_id, &"wood")
	var free_before: int = fx.inventory.get_available_amount(&"wood")
	var snap_before := _full_snapshot(fx, sites, unit)

	var res_mix: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_b22_mix",
		[{"lot_id": &"res_a22", "amount": 3}, {"lot_id": &"free_w22", "amount": 2}]
	)
	assert_true(bool(res_mix.get("ok", false)), str(res_mix))
	assert_eq(int(res_mix.get("delivered_now", 0)), 5)
	assert_eq((res_mix["created_pile_ids"] as Array).size(), 1)
	var new_pid: int = int(res_mix["created_pile_ids"][0])
	var new_pile: GroundResourcePile = fx.manager.get_pile_by_id(new_pid)
	assert_not_null(new_pile)
	assert_true(new_pile.is_inside_tree())
	assert_eq(new_pile.amount, 5)
	assert_eq(fx.manager.get_pile_reservations(new_pid), {site_a.reservation_id: 3})
	assert_eq(fx.inventory.get_reservation_amount(site_a.reservation_id, &"wood"), res_a_before + 3)
	assert_eq(fx.inventory.get_available_amount(&"wood"), free_before + 2)
	# Partial reserved lot keeps remaining 2 in backpack and claim = 2 with listener still connected
	assert_eq(site_a._read_transit_claim_for_unit_pure(unit.get_instance_id()), {&"wood": 2})
	var claim_cb: Callable = site_a._transit_claims[unit.get_instance_id()]["callback"]
	assert_true(unit.get_carry_load().load_changed.is_connected(claim_cb))
	var after_lots: Dictionary = unit.get_carry_load().provenance_snapshot()["ledger"]["lots"]
	assert_eq(int(after_lots[&"res_a22"]["quantity"]), 2)
	assert_eq(int(after_lots[&"free_w22"]["quantity"]), 2)
	assert_eq(int(after_lots[&"res_d3_24"]["quantity"]), 2)

	# Ensure zero virtual IDs ever entered PileReservationLedger
	var ledger_by_pile: Dictionary = fx.manager._ledger.snapshot_state()["by_pile"]
	for pid_key: Variant in ledger_by_pile.keys():
		assert_eq(typeof(pid_key), TYPE_INT)
		assert_true(int(pid_key) > 0)

	_assert_global_conservation(snap_before, _full_snapshot(fx, sites, unit), fx, sites)
	_assert_guards_released(fx, sites, unit)


# ------------------------------------------------------------------------------
# GROUP C — TRANSACTIONAL FAULTS & COMPLETE ROLLBACK (Scenarios 25-40)
# ------------------------------------------------------------------------------

func test_group_c_all_pre_commit_fault_boundaries_roll_back_cleanly() -> void:
	# Scenarios 25-34, 37-40: inject failure at EVERY pre-commit boundary and verify full rollback,
	# zero signals, zero receipts, zero orphan nodes, zero consumed pile IDs, listeners preserved, guards released.
	var stages: Array[String] = [
		"before_carry_debit",
		"after_ledger_debit",
		"after_carry_debit",
		"before_pile_merge",
		"after_pile_merge",
		"before_pile_create",
		"during_pile_create",
		"after_pile_create",
		"before_reservation_restore",
		"during_reservation_restore",
		"after_reservation_restore",
		"before_claim_update",
		"after_claim_update",
		"during_final_invariants",
		"before_receipt_commit",
	]

	for stage: String in stages:
		var fx: Dictionary = await _nav_fixture(StringName("reg_fault_" + stage))
		var zone: CampStorageZone = fx.zone
		zone.max_pile_amount = 14
		var site_a := _create_site(fx, StringName("sa_" + stage), {&"wood": 8}, 6.0)
		var site_b := _create_site(fx, StringName("sb_" + stage), {&"wood": 5}, 12.0)
		var sites: Array[ConstructionSite] = [site_a, site_b]
		var unit := _nav_unit(fx, StringName("u_" + stage))

		# Setup: wood pile has 11 (room for 3 before split), unit holds 4 for site_a + 3 for site_b + 4 free food
		# Returning res_a (4) + res_b (3) + free_food (4) triggers:
		# - merge (wood +3 to cap 14)
		# - multiple creates (new wood pile +4, new food pile +4)
		# - multiple reservation restorations (existing wood pile + new wood pile across 2 sites)
		# - multiple site claim updates
		_withdraw(fx, site_a, unit, fx.wood, 4, &"la")
		_withdraw(fx, site_b, unit, fx.wood, 3, &"lb")
		fx.wood.apply_state(11, 12.0, 1.5)
		_gather_res(fx, unit, FOOD, 4, &"ogf", &"lfood")
		_place_at_camp(fx, unit)

		var events := _observe(fx, sites, unit)
		var tree_added := [0]
		var tree_cb := func(node: Node) -> void:
			if node is GroundResourcePile:
				tree_added[0] += 1
		get_tree().node_added.connect(tree_cb)

		var snap_before := _full_snapshot(fx, sites, unit)
		var coord: CampCoordinator = fx.camp_coord
		coord._fault_at = func(s: String) -> bool: return s == stage

		var op_id := StringName("op_fault_" + stage)
		var outcome: Dictionary = coord.execute_selective_camp_delivery(
			fx.inventory, zone, unit, fx.region, op_id,
			[
				{"lot_id": &"la", "amount": 4},
				{"lot_id": &"lb", "amount": 3},
				{"lot_id": &"lfood", "amount": 4},
			]
		)
		get_tree().node_added.disconnect(tree_cb)
		coord._fault_at = Callable()

		assert_false(bool(outcome.get("ok", true)), "Stage %s must fail" % stage)
		assert_eq(String(outcome.get("reason", "")), "aborted_" + stage)
		assert_eq(events.size(), 0, "Stage %s must emit zero signals" % stage)
		assert_eq(tree_added[0], 0, "Stage %s must attach zero provisional piles to scene tree" % stage)
		assert_true(coord.get_receipt(op_id).is_empty(), "Stage %s must not record receipt" % stage)

		var snap_after := _full_snapshot(fx, sites, unit)
		_assert_economic_equal_ignoring_revisions(snap_after, snap_before, "Stage " + stage)
		if stage == "before_carry_debit":
			assert_eq(snap_after["load_revision"], snap_before["load_revision"])
			assert_eq(snap_after["storage_revision"], snap_before["storage_revision"])
		else:
			assert_true(int(snap_after["load_revision"]) > int(snap_before["load_revision"]), "Monotonic load revision after rollback at " + stage)
		_assert_global_conservation(snap_before, snap_after, fx, sites)
		_assert_guards_released(fx, sites, unit)


func test_group_c_combined_merge_create_multi_site_rollback_and_post_abort_retry() -> void:
	# Scenarios 35 (multi-pile/multi-site fault), 36 (undo merge + create in same tx), 49 (retry after abort)
	var fx: Dictionary = await _nav_fixture()
	var zone: CampStorageZone = fx.zone
	zone.max_pile_amount = 15
	var site_a := _create_site(fx, &"sa_retry", {&"wood": 8}, 6.0)
	var site_b := _create_site(fx, &"sb_retry", {&"wood": 4}, 12.0)
	var sites: Array[ConstructionSite] = [site_a, site_b]
	var unit := _nav_unit(fx, &"u_retry")

	_withdraw(fx, site_a, unit, fx.wood, 5, &"la_r")
	_withdraw(fx, site_b, unit, fx.wood, 2, &"lb_r")
	fx.wood.apply_state(12, 10.0, 1.0)
	_place_at_camp(fx, unit)

	var req := [{"lot_id": &"la_r", "amount": 5}, {"lot_id": &"lb_r", "amount": 2}]
	var snap0 := _full_snapshot(fx, sites, unit)

	# Abort after merge (+3 -> 15) AND detached create (+4) AND reservation restoration
	fx.camp_coord._fault_at = func(s: String) -> bool: return s == "after_reservation_restore"
	var aborted: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_retry_same_id", req
	)
	fx.camp_coord._fault_at = Callable()
	assert_false(bool(aborted.get("ok", true)))
	assert_eq(String(aborted.get("reason", "")), "aborted_after_reservation_restore")
	_assert_economic_equal_ignoring_revisions(_full_snapshot(fx, sites, unit), snap0, "post-abort")
	_assert_guards_released(fx, sites, unit)

	# Scenario 49: retry with the EXACT SAME operation_id succeeds cleanly!
	var succeeded: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_retry_same_id", req
	)
	assert_true(bool(succeeded.get("ok", false)), str(succeeded))
	assert_false(bool(succeeded.get("replayed", true)))
	assert_eq(int(succeeded.get("delivered_now", 0)), 7)
	assert_eq(fx.wood.amount, 15)
	assert_eq((succeeded["created_pile_ids"] as Array).size(), 1)
	assert_eq(fx.manager.get_pile_by_id(int(succeeded["created_pile_ids"][0])).amount, 4)
	assert_eq(fx.inventory.get_reservation_amount(site_a.reservation_id, &"wood"), 8)
	assert_eq(fx.inventory.get_reservation_amount(site_b.reservation_id, &"wood"), 4)
	_assert_global_conservation(snap0, _full_snapshot(fx, sites, unit), fx, sites)
	_assert_guards_released(fx, sites, unit)


# ------------------------------------------------------------------------------
# GROUP D — IDEMPOTENCY & RECEIPT CONFLICTS (Scenarios 41-50)
# ------------------------------------------------------------------------------

func test_group_d_idempotency_replay_cross_coordinator_and_all_conflict_cases() -> void:
	# Scenarios 41-48, 50: first commit, immediate replay, replay with another coordinator instance,
	# same ID different selection/unit/region, C2-R1 conflict, C3.2 conflict, zero signals on replay.
	var fx: Dictionary = await _nav_fixture(&"reg_idem_a")
	var site_a := _create_site(fx, &"site_idem", {&"wood": 8})
	var sites: Array[ConstructionSite] = [site_a]
	var unit := _nav_unit(fx, &"worker_idem_1")
	var unit2 := _nav_unit(fx, &"worker_idem_2")
	_withdraw(fx, site_a, unit, fx.wood, 2, &"c2_lot")
	# Commit a C3.2 site delivery to create a C3.2 receipt in the same regional authority
	unit.global_position = site_a.global_position + Vector3(0.0, 0.0, 2.2)
	var c32_res: Dictionary = fx.site_coord.execute_selective_site_delivery(site_a, unit, &"op_c32_existing", {&"wood": 2})
	assert_true(bool(c32_res.get("ok", false)), str(c32_res))

	_gather_res(fx, unit, WOOD, 6, &"op_g_idem", &"free_idem")
	_gather_res(fx, unit2, WOOD, 4, &"op_g_idem2", &"free_idem2")
	_place_at_camp(fx, unit)
	_place_at_camp(fx, unit2)

	var prep := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, &"op_idem_1",
		[{"lot_id": &"free_idem", "amount": 4}]
	)
	assert_true(bool(prep.get("ok", false)), str(prep))

	# Scenario 41: first valid commit via commit_prepared
	var first: Dictionary = fx.camp_coord.commit_prepared_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, prep
	)
	assert_true(bool(first.get("ok", false)), str(first))
	assert_false(bool(first.get("replayed", true)))
	assert_eq(int(first.get("delivered_now", 0)), 4)

	var events := _observe(fx, sites, unit)
	var snap_after_first := _full_snapshot(fx, sites, unit)

	# Scenario 42 + 50: immediate replay on same coordinator emits 0 signals and 0 mutations
	var replay1: Dictionary = fx.camp_coord.commit_prepared_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, prep
	)
	assert_true(bool(replay1.get("ok", false)), str(replay1))
	assert_true(bool(replay1.get("replayed", false)))
	assert_eq(int(replay1.get("delivered_now", -1)), 0)
	assert_eq(replay1["receipt"], first["receipt"])
	assert_eq(events.size(), 0)
	assert_eq(_full_snapshot(fx, sites, unit), snap_after_first)

	# Scenario 43: replay using a brand-new SelectiveCampDeliveryCoordinator instance
	var second_coord := CampCoordinator.new()
	var replay2: Dictionary = second_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, &"op_idem_1",
		[{"lot_id": &"free_idem", "amount": 4}]
	)
	assert_true(bool(replay2.get("ok", false)), str(replay2))
	assert_true(bool(replay2.get("replayed", false)))
	assert_eq(int(replay2.get("delivered_now", -1)), 0)
	assert_eq(second_coord.get_receipt(&"op_idem_1"), first["receipt"])
	assert_eq(events.size(), 0)
	assert_eq(_full_snapshot(fx, sites, unit), snap_after_first)

	# Scenario 44: same ID with different selection -> operation_conflict
	var c_sel: Dictionary = second_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, &"op_idem_1",
		[{"lot_id": &"free_idem", "amount": 2}]
	)
	assert_false(bool(c_sel.get("ok", true)))
	assert_eq(String(c_sel.get("reason", "")), "operation_conflict")

	# Scenario 44b: same ID with tampered prepared plan digest -> operation_conflict
	var bad_prep := prep.duplicate(true)
	bad_prep["deliverable_amounts"][&"wood"] = 99
	var c_digest: Dictionary = second_coord.commit_prepared_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, bad_prep
	)
	assert_false(bool(c_digest.get("ok", true)))
	assert_eq(String(c_digest.get("reason", "")), "operation_conflict")

	# Scenario 45: same ID with different unit -> operation_conflict
	var c_unit: Dictionary = second_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit2, fx.region, &"op_idem_1",
		[{"lot_id": &"free_idem", "amount": 4}]
	)
	assert_false(bool(c_unit.get("ok", true)))
	assert_eq(String(c_unit.get("reason", "")), "operation_conflict")

	# Scenario 46: same ID with another region on same storage -> region_mismatch (no cross-region replay)
	var c_reg: Dictionary = second_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, &"reg_idem_other", &"op_idem_1",
		[{"lot_id": &"free_idem", "amount": 4}]
	)
	assert_false(bool(c_reg.get("ok", true)))
	assert_eq(String(c_reg.get("reason", "")), "region_mismatch")

	# Scenario 47: conflict with C2-R1 withdrawal receipt (`pickup_c2_lot`)
	var c_c2: Dictionary = second_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, &"pickup_c2_lot", []
	)
	assert_false(bool(c_c2.get("ok", true)))
	assert_eq(String(c_c2.get("reason", "")), "operation_conflict")

	# Scenario 48: conflict with C3.2 site delivery receipt (`op_c32_existing`)
	var c_c32: Dictionary = second_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, &"op_c32_existing", []
	)
	assert_false(bool(c_c32.get("ok", true)))
	assert_eq(String(c_c32.get("reason", "")), "operation_conflict")

	# Reverse check: C3.2 and C2-R1 cannot reuse C3.4.2 receipt `op_idem_1`
	var rev_c32: Dictionary = fx.site_coord.execute_selective_site_delivery(site_a, unit, &"op_idem_1", {})
	assert_false(bool(rev_c32.get("ok", true)))
	assert_eq(String(rev_c32.get("reason", "")), "operation_conflict")

	assert_eq(events.size(), 0)
	assert_eq(_full_snapshot(fx, sites, unit), snap_after_first)


# ------------------------------------------------------------------------------
# GROUP E — PHYSICAL SECURITY, CALLBACKS, STALE/ABA & ISOLATION (Scenarios 51-62)
# ------------------------------------------------------------------------------

func test_group_e_physical_authorization_range_nav_zone_capacity_and_wall_blocker() -> void:
	# Scenarios 51 (far outside camp), 52 (near slot but outside tolerance), 53 (valid slot reached),
	# 54 (navigation unavailable/not ready), 55 (invalid zone), 56 (insufficient camp capacity)
	var fx: Dictionary = await _nav_fixture()
	var zone: CampStorageZone = fx.zone
	var unit := _nav_unit(fx, &"worker_e51")
	_gather_res(fx, unit, FOOD, 5, &"op_g_e51", &"free_food_e51")
	var empty_sites: Array[ConstructionSite] = []

	# Scenario 51: unit far outside camp
	unit.global_position = Vector3(14.0, 0.0, 14.0)
	var r_far: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e51_far", []
	)
	assert_false(bool(r_far.get("ok", true)))
	assert_eq(String(r_far.get("reason", "")), "out_of_camp_dropoff_range")

	# Scenario 52: unit inside zone bounds near slot 0, but 0.55 m away (> 0.35 m reach tolerance; slot_spacing=1.2 m)
	_place_at_camp(fx, unit, Vector3(0.55, 0.0, 0.0))
	var r_near: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e52_near", []
	)
	assert_false(bool(r_near.get("ok", true)))
	assert_eq(String(r_near.get("reason", "")), "out_of_camp_dropoff_range")

	# Scenario 54a: navigation detached (`null`)
	_place_at_camp(fx, unit)
	zone.set_world_navigation(null)
	var r_no_nav: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e54_null", []
	)
	assert_false(bool(r_no_nav.get("ok", true)))
	assert_eq(String(r_no_nav.get("reason", "")), "navigation_not_ready")

	# Scenario 54b: navigation attached but not ready
	var unready_nav := WorldNavigation.new()
	unready_nav.auto_bake_on_ready = false
	fx.host.add_child(unready_nav)
	zone.set_world_navigation(unready_nav)
	var r_unready: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e54_unready", []
	)
	assert_false(bool(r_unready.get("ok", true)))
	assert_eq(String(r_unready.get("reason", "")), "navigation_not_ready")
	zone.set_world_navigation(fx.nav as WorldNavigation)

	# Scenario 55: invalid camp_zone
	var saved_id := zone.zone_id
	zone.zone_id = &""
	var r_bad_zone: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e55_zone", []
	)
	assert_false(bool(r_bad_zone.get("ok", true)))
	assert_eq(String(r_bad_zone.get("reason", "")), "invalid_camp_zone")
	zone.zone_id = saved_id

	# Scenario 56: insufficient camp capacity (zone shrunk to occupied slot + cap=2)
	var saved_ext := zone.zone_bounds_half_extents
	zone.zone_bounds_half_extents = Vector2(0.5, 0.5)
	var r_cap: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e56_cap", []
	)
	assert_false(bool(r_cap.get("ok", true)))
	assert_eq(String(r_cap.get("reason", "")), "no_valid_camp_slot")
	zone.zone_bounds_half_extents = saved_ext

	# Scenario 52b: solid obstacle wall between unit (at +0.30 m) and slot 0 blocks clear physical access
	var wall := StaticBody3D.new()
	wall.collision_layer = CollisionLayers.MASK_OBSTACLES
	wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(0.08, 2.0, 2.0)
	wall_shape.shape = wbox
	wall.add_child(wall_shape)
	var slot0: Vector3 = zone.get_candidate_slots()[0]
	wall.position = slot0 + Vector3(0.15, 0.5, 0.0)
	fx.host.add_child(wall)
	await wait_physics_frames(2)
	_place_at_camp(fx, unit, Vector3(0.30, 0.0, 0.0))
	var r_wall: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e52_wall", []
	)
	assert_false(bool(r_wall.get("ok", true)))
	assert_eq(String(r_wall.get("reason", "")), "out_of_camp_dropoff_range")
	fx.host.remove_child(wall)
	wall.free()
	await wait_physics_frames(2)

	# Scenario 53: unit reaches valid slot within tolerance -> commit succeeds!
	_place_at_camp(fx, unit, Vector3(0.20, 0.0, 0.0))
	var r_ok: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, DEFAULT_REGION, &"op_e53_ok", []
	)
	assert_true(bool(r_ok.get("ok", false)), str(r_ok))
	assert_eq(int(r_ok.get("delivered_now", 0)), 5)
	_assert_guards_released(fx, empty_sites, unit)


func test_group_e_unsafe_callbacks_removed_pile_tampered_stale_and_world_region_isolation() -> void:
	# Scenarios 57 (unsafe custom validator), 58 (unsafe pile_creator_override), 59 (pile removed before commit),
	# 60 (tampered plan), 61 (stale revision + CampStorageZone ABA), 62 (world/region mismatch)
	var fx: Dictionary = await _nav_fixture(&"reg_e57")
	var zone: CampStorageZone = fx.zone
	var unit := _nav_unit(fx, &"worker_e57")
	var empty_sites: Array[ConstructionSite] = []
	_gather_res(fx, unit, FOOD, 4, &"op_g_e57_f", &"free_food_57")
	_gather_res(fx, unit, WOOD, 4, &"op_g_e57_w", &"free_wood_57")

	# Scenario 57: untrusted custom position validator refused without executing or creating authority
	var cb_calls := [0]
	zone.set_custom_position_validator(func(_pos: Vector3) -> bool:
		cb_calls[0] += 1
		return true
	)
	var r_cb: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, fx.region, &"op_e57_cb", []
	)
	assert_false(bool(r_cb.get("ok", true)))
	assert_eq(String(r_cb.get("reason", "")), "unsafe_custom_position_validator")
	assert_eq(cb_calls[0], 0)
	assert_false(unit.get_world_3d().has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))
	zone.set_custom_position_validator(Callable())

	# Scenario 58: untrusted pile_creator_override refused without executing or creating authority
	var ov_calls := [0]
	fx.manager.pile_creator_override = func(_id: int, _def: ResourceDefinition, _amt: int, _pos: Vector3) -> GroundResourcePile:
		ov_calls[0] += 1
		return null
	var r_ov: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, unit, fx.region, &"op_e58_ov", []
	)
	assert_false(bool(r_ov.get("ok", true)))
	assert_eq(String(r_ov.get("reason", "")), "unsafe_pile_creator_override")
	assert_eq(ov_calls[0], 0)
	assert_false(unit.get_world_3d().has_meta(ReservedWithdrawalCoordinator.DOMAIN_META))
	fx.manager.pile_creator_override = Callable()

	# Scenario 60: tampered prepared plan rejected
	var plan_w := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, fx.region, &"op_e60",
		[{"lot_id": &"free_wood_57", "amount": 4}]
	)
	assert_true(bool(plan_w.get("ok", false)))
	var tampered := plan_w.duplicate(true)
	tampered["deliverable_amounts"][&"wood"] = 4.0
	var r_tamp: Dictionary = fx.camp_coord.commit_prepared_selective_camp_delivery(
		fx.inventory, zone, unit, fx.region, tampered
	)
	assert_false(bool(r_tamp.get("ok", true)))
	assert_eq(String(r_tamp.get("reason", "")), "tampered_or_stale_plan")

	# Scenario 61 (§14.1 ABA): CampStorageZone config ABA (max_pile_amount 0 -> 10 -> 0) invalidates prepared plan!
	var orig_max: int = zone.max_pile_amount
	zone.max_pile_amount = 10
	zone.max_pile_amount = orig_max
	var r_aba_cfg: Dictionary = fx.camp_coord.commit_prepared_selective_camp_delivery(
		fx.inventory, zone, unit, fx.region, plan_w
	)
	assert_false(bool(r_aba_cfg.get("ok", true)))
	assert_eq(String(r_aba_cfg.get("reason", "")), "stale_revision")

	# Scenario 61b (§14.1 ABA): CampStorageZone position ABA (A -> B -> A) invalidates prepared plan!
	var plan_w2 := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, fx.region, &"op_e61_pos",
		[{"lot_id": &"free_wood_57", "amount": 4}]
	)
	assert_true(bool(plan_w2.get("ok", false)))
	var orig_pos := zone.position
	zone.position = orig_pos + Vector3(1.0, 0.0, 0.0)
	zone.position = orig_pos
	var r_aba_pos: Dictionary = fx.camp_coord.commit_prepared_selective_camp_delivery(
		fx.inventory, zone, unit, fx.region, plan_w2
	)
	assert_false(bool(r_aba_pos.get("ok", true)))
	assert_eq(String(r_aba_pos.get("reason", "")), "stale_revision")

	# Scenario 59: target merge pile removed before commit -> stale_revision
	var plan_rm := CampPlanner.prepare_selective_camp_delivery(
		fx.inventory, zone, unit, fx.region, &"op_e59_rm",
		[{"lot_id": &"free_wood_57", "amount": 4}]
	)
	assert_true(bool(plan_rm.get("ok", false)))
	assert_true(fx.manager.withdraw(&"wood", fx.wood.amount))
	var r_rm: Dictionary = fx.camp_coord.commit_prepared_selective_camp_delivery(
		fx.inventory, zone, unit, fx.region, plan_rm
	)
	assert_false(bool(r_rm.get("ok", true)))
	assert_eq(String(r_rm.get("reason", "")), "stale_revision")

	# Scenario 62: foreign World3D rejected with world_mismatch; legacy unit rejected with provenance_disabled
	var fx2: Dictionary = await _nav_fixture(&"reg_e57")
	var foreign_u := _nav_unit(fx2, &"u_foreign")
	_gather_res(fx2, foreign_u, WOOD, 2, &"op_gf", &"lf_for")
	var r_world: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, foreign_u, fx.region, &"op_e62_w", []
	)
	assert_false(bool(r_world.get("ok", true)))
	assert_eq(String(r_world.get("reason", "")), "world_mismatch")

	var legacy_u := _nav_unit(fx, &"u_legacy", false)
	var r_leg: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, zone, legacy_u, fx.region, &"op_e62_leg", []
	)
	assert_false(bool(r_leg.get("ok", true)))
	assert_eq(String(r_leg.get("reason", "")), "provenance_disabled")
	_assert_guards_released(fx, empty_sites, unit)


# ------------------------------------------------------------------------------
# GROUP F — CONCURRENCY, REENTRANCY & GUARD LIFECYCLE (Scenarios 63-70)
# ------------------------------------------------------------------------------

func test_group_f_concurrency_reentrancy_in_all_signals_and_guard_release() -> void:
	# Scenarios 63-70: concurrent operations, re-entry from load/storage/inventory/reservations/site signals
	# attempting C3.4.2 (same & diff ID), C3.2 site delivery, C2-R1 withdrawal, inventory/storage/load/site mutators,
	# observer sees final state + committed receipt + attached piles, and guards released on both failure and success.
	var fx: Dictionary = await _nav_fixture(&"reg_f63")
	var site_a := _create_site(fx, &"site_f63", {&"wood": 8})
	var sites: Array[ConstructionSite] = [site_a]
	var unit := _nav_unit(fx, &"worker_f63")
	_withdraw_then_camp(fx, site_a, unit, fx.wood, 4, &"res_f63")
	_gather_res(fx, unit, FOOD, 3, &"op_gf63", &"free_food_63")

	var reentrant_log: Array[Dictionary] = []
	var second_coord := CampCoordinator.new()
	var probe_reentry := func(source_sig: String) -> void:
		var r_same: Dictionary = second_coord.execute_selective_camp_delivery(
			fx.inventory, fx.zone, unit, fx.region, &"op_f63_commit", []
		)
		var r_diff: Dictionary = second_coord.execute_selective_camp_delivery(
			fx.inventory, fx.zone, unit, fx.region, &"op_f63_reentrant", []
		)
		var r_c32: Dictionary = fx.site_coord.execute_selective_site_delivery(site_a, unit, &"op_f63_c32", {})
		var r_c2: Dictionary = fx.coordinator.execute_reserved_withdrawal(
			site_a, unit, fx.wood.pile_id, &"wood", 1, &"op_f63_c2", &"lot_f63_c2"
		)
		var inv_dep: bool = fx.inventory.deposit(&"wood", 1)
		var stor_dep: bool = fx.manager.deposit(&"wood", 1)
		var cap_mut: bool = unit.get_carry_load().set_base_capacity(999)
		var rec: Dictionary = fx.camp_coord.get_receipt(&"op_f63_commit")
		var food_piles: Array[GroundResourcePile] = fx.manager.get_piles_for_resource(&"food")
		reentrant_log.append({
			"sig": source_sig,
			"same_reason": String(r_same.get("reason", "")),
			"diff_reason": String(r_diff.get("reason", "")),
			"c32_reason": String(r_c32.get("reason", "")),
			"c2_reason": String(r_c2.get("reason", "")),
			"inv_dep": inv_dep,
			"stor_dep": stor_dep,
			"cap_mut": cap_mut,
			"has_receipt": not rec.is_empty(),
			"carry_empty": unit.get_carry_load().is_empty(),
			"wood_res": fx.inventory.get_reservation_amount(site_a.reservation_id, &"wood"),
			"food_attached": food_piles.size() == 1 and food_piles[0].is_inside_tree(),
		})

	_watch(fx.manager.reservations_changed, func() -> void: probe_reentry.call("storage.reservations_changed"))
	_watch(fx.inventory.reservations_changed, func() -> void: probe_reentry.call("inventory.reservations_changed"))
	_watch(fx.manager.storage_changed, func() -> void: probe_reentry.call("storage.storage_changed"))
	_watch(fx.inventory.inventory_changed, func() -> void: probe_reentry.call("inventory.inventory_changed"))
	_watch(unit.get_carry_load().load_changed, func() -> void: probe_reentry.call("load.load_changed"))
	_watch(site_a.state_changed, func(_s: ConstructionSite) -> void: probe_reentry.call("site.state_changed"))
	var node_added_observed: Array[Dictionary] = []
	var node_cb := func(node: Node) -> void:
		if node is GroundResourcePile:
			node_added_observed.append({
				"has_receipt": not fx.camp_coord.get_receipt(&"op_f63_commit").is_empty(),
				"carry_empty": unit.get_carry_load().is_empty(),
				"wood_res": fx.inventory.get_reservation_amount(site_a.reservation_id, &"wood"),
				"busy": String(second_coord.execute_selective_camp_delivery(
					fx.inventory, fx.zone, unit, fx.region, &"op_f63_node_added", []
				).get("reason", "")),
			})
	get_tree().node_added.connect(node_cb)

	var snap_before := _full_snapshot(fx, sites, unit)
	var outcome: Dictionary = fx.camp_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, &"op_f63_commit",
		[{"lot_id": &"res_f63", "amount": 4}, {"lot_id": &"free_food_63", "amount": 3}]
	)
	get_tree().node_added.disconnect(node_cb)
	assert_true(bool(outcome.get("ok", false)), str(outcome))
	assert_eq(node_added_observed.size(), 1, "New pile must attach exactly once at post-commit boundary")
	assert_true(bool(node_added_observed[0]["has_receipt"]))
	assert_true(bool(node_added_observed[0]["carry_empty"]))
	assert_eq(int(node_added_observed[0]["wood_res"]), 8)
	assert_eq(String(node_added_observed[0]["busy"]), "busy")
	assert_eq(reentrant_log.size(), 6, "Expected all 6 participant signals to fire once")
	for entry: Dictionary in reentrant_log:
		assert_eq(entry["same_reason"], "busy", str(entry))
		assert_eq(entry["diff_reason"], "busy", str(entry))
		assert_eq(entry["c32_reason"], "busy", str(entry))
		assert_eq(entry["c2_reason"], "busy", str(entry))
		assert_false(bool(entry["inv_dep"]), str(entry))
		assert_false(bool(entry["stor_dep"]), str(entry))
		assert_false(bool(entry["cap_mut"]), str(entry))
		assert_true(bool(entry["has_receipt"]), str(entry))
		assert_true(bool(entry["carry_empty"]), str(entry))
		assert_eq(int(entry["wood_res"]), 8, str(entry))
		assert_true(bool(entry["food_attached"]), str(entry))

	_assert_global_conservation(snap_before, _full_snapshot(fx, sites, unit), fx, sites)
	_assert_guards_released(fx, sites, unit)

	# Scenario 63: explicit busy authority rejects concurrent camp delivery cleanly
	var domains: Dictionary = unit.get_world_3d().get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var auth := domains[fx.region] as ReservedWithdrawalCoordinator.RegionalAuthority
	auth.is_executing = true
	var r_busy: Dictionary = second_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, &"op_f63_concurrent", []
	)
	auth.is_executing = false
	assert_false(bool(r_busy.get("ok", true)))
	assert_eq(String(r_busy.get("reason", "")), "busy")

	# Scenario 70: after guards are released, a subsequent transaction executes normally
	_gather_res(fx, unit, STONE, 2, &"op_g_after", &"free_stone_after")
	var r_after: Dictionary = second_coord.execute_selective_camp_delivery(
		fx.inventory, fx.zone, unit, fx.region, &"op_f70_next", []
	)
	assert_true(bool(r_after.get("ok", false)), str(r_after))
	assert_eq(int(r_after.get("delivered_now", 0)), 2)
	_assert_guards_released(fx, sites, unit)


func test_post_commit_node_added_observer_lifecycle_and_integrity_boundaries() -> void:
	# Audit §2.1: verify all 4 SceneTree.node_added observer behaviors on multi-pile post-commit creation:
	# 1) Query-only observer sees valid committed pile + GROUP_GROUND_PILES membership and final visuals post-attach.
	# 2) Reentrant transaction / storage mutation is blocked ("busy" / false).
	# 3) CampStorageZone config mutation is blocked while transaction guards hold, then succeeds legitimately after commit.
	# 4) Legitimate API pile removal is blocked during node_added and succeeds legitimately after commit;
	#    hostile raw remove_child / queue_free / remove_child+free during node_added does NOT crash or abort pile #2
	#    and is detected fail-closed ("invalid_physical_pile_collection") on the next prepare/commit.

	# Subcase A: query-only + reentrant transaction + camp config lock + legitimate post-commit API removal/config change
	var fx_a: Dictionary = await _nav_fixture(&"reg_node_added_a")
	var zone_a: CampStorageZone = fx_a.zone
	zone_a.max_pile_amount = 5
	var unit_a := _nav_unit(fx_a, &"u_na_a")
	_gather_res(fx_a, unit_a, WOOD, 7, &"op_na_ga", &"free_na_a")
	var base_wood_a: int = fx_a.inventory.get_physical_amount(&"wood")
	var orig_zone_id: StringName = zone_a.zone_id
	var orig_cfg_rev: int = zone_a.get_config_revision()
	var seen_a: Array[Dictionary] = []
	var cb_a := func(node: Node) -> void:
		if not (node is GroundResourcePile):
			return
		var pile := node as GroundResourcePile
		var reenter_r: Dictionary = fx_a.camp_coord.execute_selective_camp_delivery(
			fx_a.inventory, zone_a, unit_a, fx_a.region, &"op_na_reenter", []
		)
		var api_w: bool = fx_a.manager.withdraw(&"wood", 1)
		fx_a.manager.cleanup()
		zone_a.max_pile_amount = 2
		zone_a.zone_id = &"mutated_during_node_added"
		zone_a.set_custom_position_validator(func(_p: Vector3) -> bool: return false)
		seen_a.append({
			"pile_id": pile.pile_id,
			"amount": pile.amount,
			"valid": pile.is_valid(),
			"in_group": pile.is_in_group(GroundResourcePile.GROUP_GROUND_PILES),
			"reenter_reason": String(reenter_r.get("reason", "")),
			"api_w": api_w,
			"zone_locked": zone_a.is_transaction_locked(),
		})
	get_tree().node_added.connect(cb_a)
	var res_a: Dictionary = fx_a.camp_coord.execute_selective_camp_delivery(
		fx_a.inventory, zone_a, unit_a, fx_a.region, &"op_na_a", []
	)
	get_tree().node_added.disconnect(cb_a)
	assert_true(bool(res_a.get("ok", false)), str(res_a))
	assert_eq(seen_a.size(), 2, "Both created piles must trigger node_added")
	for entry: Dictionary in seen_a:
		assert_true(bool(entry["valid"]), str(entry))
		assert_true(bool(entry["in_group"]), str(entry))
		assert_eq(String(entry["reenter_reason"]), "busy", str(entry))
		assert_false(bool(entry["api_w"]), str(entry))
		assert_true(bool(entry["zone_locked"]), str(entry))
	assert_false(zone_a.is_transaction_locked())
	assert_eq(zone_a.max_pile_amount, 5)
	assert_eq(zone_a.zone_id, orig_zone_id)
	assert_eq(zone_a.get_config_revision(), orig_cfg_rev)
	assert_false(zone_a._custom_position_validator.is_valid())
	for pid_var: Variant in (res_a["created_pile_ids"] as Array):
		var cp: GroundResourcePile = fx_a.manager.get_pile_by_id(int(pid_var))
		assert_not_null(cp)
		assert_gt(cp.get_visible_mesh_count(), 0)
	# Replay succeeds with unchanged identity
	var rep_a: Dictionary = fx_a.camp_coord.execute_selective_camp_delivery(
		fx_a.inventory, zone_a, unit_a, fx_a.region, &"op_na_a", []
	)
	assert_true(bool(rep_a.get("ok", false)) and bool(rep_a.get("replayed", false)), str(rep_a))
	# Legitimate post-commit config change and API removal now work cleanly and keep storage valid
	zone_a.max_pile_amount = 8
	assert_eq(zone_a.max_pile_amount, 8)
	assert_gt(zone_a.get_config_revision(), orig_cfg_rev)
	assert_true(fx_a.inventory.withdraw(&"wood", 2))
	assert_eq(fx_a.inventory.get_physical_amount(&"wood"), base_wood_a + 5)
	_gather_res(fx_a, unit_a, WOOD, 2, &"op_na_ga2", &"free_na_a2")
	var post_ok: Dictionary = fx_a.camp_coord.execute_selective_camp_delivery(
		fx_a.inventory, zone_a, unit_a, fx_a.region, &"op_na_a2", []
	)
	assert_true(bool(post_ok.get("ok", false)), str(post_ok))
	assert_eq(fx_a.inventory.get_physical_amount(&"wood"), base_wood_a + 7)

	# Subcase B: hostile remove_child + free() on pile #1 during node_added must NOT crash or abort pile #2,
	# and subsequent preparation must detect storage corruption fail-closed.
	var fx_b: Dictionary = await _nav_fixture(&"reg_node_added_b")
	var zone_b: CampStorageZone = fx_b.zone
	zone_b.max_pile_amount = 5
	var unit_b := _nav_unit(fx_b, &"u_na_b")
	_gather_res(fx_b, unit_b, WOOD, 7, &"op_na_gb", &"free_na_b")
	var seen_b_ids: Array[int] = []
	var cb_b := func(node: Node) -> void:
		if not (node is GroundResourcePile):
			return
		var pile := node as GroundResourcePile
		seen_b_ids.append(pile.pile_id)
		if seen_b_ids.size() == 1:
			if pile.get_parent() != null:
				pile.get_parent().remove_child(pile)
			pile.free()
	get_tree().node_added.connect(cb_b)
	var res_b: Dictionary = fx_b.camp_coord.execute_selective_camp_delivery(
		fx_b.inventory, zone_b, unit_b, fx_b.region, &"op_na_b", []
	)
	get_tree().node_added.disconnect(cb_b)
	assert_true(bool(res_b.get("ok", false)), str(res_b))
	assert_eq(seen_b_ids.size(), 2, "Pile #2 must still attach cleanly even if observer freed pile #1")
	var pile_2: GroundResourcePile = fx_b.manager.get_pile_by_id(seen_b_ids[1])
	assert_not_null(pile_2)
	assert_true(pile_2.is_inside_tree())
	assert_gt(pile_2.get_visible_mesh_count(), 0)
	assert_false(zone_b.is_transaction_locked())
	_gather_res(fx_b, unit_b, WOOD, 1, &"op_na_gb2", &"free_na_b2")
	var prep_corrupt_b: Dictionary = SelectiveCampDeliveryPlanner.prepare_selective_camp_delivery(
		fx_b.inventory, zone_b, unit_b, fx_b.region, &"op_na_b_next", []
	)
	assert_false(bool(prep_corrupt_b.get("ok", true)))
	assert_eq(String(prep_corrupt_b.get("reason", "")), "invalid_physical_pile_collection")

	# Subcase C: hostile queue_free() and remove_child() without free() detected fail-closed
	var fx_c: Dictionary = await _nav_fixture(&"reg_node_added_c")
	var zone_c: CampStorageZone = fx_c.zone
	zone_c.max_pile_amount = 5
	var unit_c := _nav_unit(fx_c, &"u_na_c")
	_gather_res(fx_c, unit_c, WOOD, 7, &"op_na_gc", &"free_na_c")
	var seen_c: Array[int] = []
	var detached_for_cleanup: Array[GroundResourcePile] = []
	var cb_c := func(node: Node) -> void:
		if not (node is GroundResourcePile):
			return
		var pile := node as GroundResourcePile
		seen_c.append(pile.pile_id)
		if seen_c.size() == 1:
			pile.queue_free()
		elif seen_c.size() == 2 and pile.get_parent() != null:
			pile.get_parent().remove_child(pile)
			detached_for_cleanup.append(pile)
	get_tree().node_added.connect(cb_c)
	var res_c: Dictionary = fx_c.camp_coord.execute_selective_camp_delivery(
		fx_c.inventory, zone_c, unit_c, fx_c.region, &"op_na_c", []
	)
	get_tree().node_added.disconnect(cb_c)
	assert_true(bool(res_c.get("ok", false)), str(res_c))
	assert_eq(seen_c.size(), 2)
	_gather_res(fx_c, unit_c, WOOD, 1, &"op_na_gc2", &"free_na_c2")
	var prep_corrupt_c: Dictionary = SelectiveCampDeliveryPlanner.prepare_selective_camp_delivery(
		fx_c.inventory, zone_c, unit_c, fx_c.region, &"op_na_c_next", []
	)
	assert_false(bool(prep_corrupt_c.get("ok", true)))
	assert_eq(String(prep_corrupt_c.get("reason", "")), "invalid_physical_pile_collection")
	for dp: GroundResourcePile in detached_for_cleanup:
		if is_instance_valid(dp) and dp.get_parent() == null:
			dp.free()
