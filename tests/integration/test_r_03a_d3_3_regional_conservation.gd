extends TestCase
## Formal regional economic conservation proof (R-03A D0-A04) across scenarios C01-C12.
## Uses RegionalConservationAudit (strictly read-only) on real MainScene and isolated domains.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const WOOD_DEF: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_DEF: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD_DEF: ResourceDefinition = preload("res://data/resources/food.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const CARRY_FIXTURE = preload("res://tests/framework/carry_provenance_fixture.gd")

const STANDING := ResourceSource.TreeHarvestStage.STANDING
const CHOPPING := ResourceSource.TreeHarvestStage.CHOPPING
const FELLING := ResourceSource.TreeHarvestStage.FELLING
const FALLEN := ResourceSource.TreeHarvestStage.FALLEN
const DEPLETED := ResourceSource.TreeHarvestStage.DEPLETED

var _scale: float = 1.0
var _ticks: int = 60
var _extra_managers: Array[GroundPileManager] = []


class FailingPreCommitTreeSource extends ResourceSource:
	var fail_next_commit: bool = false

	func _before_provenance_transfer_commit() -> bool:
		if fail_next_commit:
			fail_next_commit = false
			return false
		return true


class UncertainOutcomeGatherSession extends GatherTransferSession:
	var return_uncertain_once: bool = true

	func _invoke_source_transfer(source: ResourceSource, carry_load: UnitCarryLoad) -> Dictionary:
		var actual: Dictionary = super._invoke_source_transfer(source, carry_load)
		if return_uncertain_once:
			return_uncertain_once = false
			return {}
		return actual


func before_each() -> void:
	_scale = Engine.time_scale
	_ticks = Engine.physics_ticks_per_second
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = _scale
	Engine.physics_ticks_per_second = _ticks
	for mgr: GroundPileManager in _extra_managers:
		if mgr != null:
			mgr.cleanup()
	_extra_managers.clear()


func _main_fixture(provenance: bool = true) -> MainScene:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(1280, 720)
	add_test_child(view)
	var main := MAIN_SCENE.instantiate() as MainScene
	main.use_provenance_economy = provenance
	view.add_child(main)
	var nav := main.get_test_map().get_navigation()
	assert_true(await _until(func() -> bool: return nav.is_navigation_ready(), 240), "MainScene navigation ready")
	await wait_physics_frames(2)
	return main


func _until(predicate: Callable, limit: int = 1200) -> bool:
	for _frame: int in range(limit):
		if predicate.call():
			return true
		await wait_physics_frames(1)
	return predicate.call()


func _source(main: MainScene, id: StringName) -> ResourceSource:
	for node: Node in get_tree().get_nodes_in_group(ResourceSource.GROUP_RESOURCE_SOURCES):
		var candidate := node as ResourceSource
		if candidate != null and candidate.get_world_3d() == main.get_world_3d() and candidate.source_id == id:
			return candidate
	fail("MainScene source missing: %s" % String(id))
	return null


func _place_in_range(unit: Unit, source: ResourceSource, direction: Vector3) -> void:
	var radius: float = (source.get_interaction_radius() + source.get_solid_radius() + WorldNavigation.DEFAULT_AGENT_RADIUS) * 0.5
	unit.global_position = source.global_position + direction.normalized() * radius


func _gather_at(main: MainScene, source: ResourceSource, units: Array[Unit]) -> bool:
	main.get_selection_manager().set_selection(units)
	var pick := PickResult.from_resource_source(source, source.global_position, Vector3.UP)
	return main.get_command_controller().command_at(pick)


func _snap_main(main: MainScene, resource_id: StringName) -> Dictionary:
	return RegionalConservationAudit.capture(
		get_tree(),
		main.get_world_3d(),
		main.get_construction_manager().get_region_id(),
		resource_id,
		main.get_settlement_inventory()
	)


func _regional_serial(main: MainScene, region_id: StringName) -> int:
	var domains: Dictionary = main.get_world_3d().get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
	var authority := domains.get(region_id) as ReservedWithdrawalCoordinator.RegionalAuthority
	return authority.construction_transfer_serial if authority != null else 0


func _make_building_def(id: StringName, costs: Dictionary, work_sec: float = 10.0) -> BuildingDefinition:
	var def := BuildingDefinition.new()
	def.definition_id = id
	def.display_name = String(id)
	def.costs = costs.duplicate()
	def.footprint_size = Vector2(3.0, 3.0)
	def.build_work_required_sec = work_sec
	def.max_builders = 2
	def.visual_height = 2.0
	return def


func _sum_main_sources(main: MainScene, resource_id: StringName) -> int:
	var total: int = 0
	for node: Node in get_tree().get_nodes_in_group(ResourceSource.GROUP_RESOURCE_SOURCES):
		var src := node as ResourceSource
		if src != null and is_instance_valid(src) and src.is_inside_tree() and src.get_world_3d() == main.get_world_3d():
			if src.get_resource_id() == resource_id:
				total += src.get_remaining_amount()
	return total


func _arm_construct_order(site: ConstructionSite, unit: Unit, force_transporter: bool = true) -> ConstructOrder:
	unit.cancel_current_order()
	var order := ConstructOrder.new(site, null, force_transporter)
	order._unit = unit
	order.mark_running()
	unit._current_order = order
	unit.set_physics_process(false)
	site.register_worker(unit, order, force_transporter)
	return order


func _create_isolated_domain(
	world_parent: SubViewport,
	region_id: StringName,
	origin_offset: Vector3,
	wood_stock: int,
	tree_amount: int
) -> Dictionary:
	var host := Node3D.new()
	host.name = "DomainHost_%s" % String(region_id)
	host.set_meta(&"region_id", region_id)
	world_parent.add_child(host)

	var zone := CampStorageZone.new()
	zone.zone_id = StringName("camp_" + String(region_id))
	zone.position = origin_offset + Vector3(-6.0, 0.0, -6.0)
	zone.zone_bounds_half_extents = Vector2(6.0, 6.0)
	zone.set_meta(&"region_id", region_id)
	host.add_child(zone)

	var piles_root := Node3D.new()
	piles_root.name = "Piles_%s" % String(region_id)
	piles_root.set_meta(&"region_id", region_id)
	host.add_child(piles_root)

	var sites_root := Node3D.new()
	sites_root.name = "Sites_%s" % String(region_id)
	sites_root.set_meta(&"region_id", region_id)
	host.add_child(sites_root)

	var defs: Dictionary = {
		&"wood": WOOD_DEF.duplicate(),
		&"stone": STONE_DEF.duplicate(),
		&"food": FOOD_DEF.duplicate(),
	}
	var time_prov := SimulatedWorldTimeProvider.new(0.0)
	var gpm := GroundPileManager.new(defs, zone, piles_root, time_prov)
	_extra_managers.append(gpm)
	var inv := SettlementInventory.new(gpm)

	var cm := ConstructionManager.new()
	cm.name = "CM_%s" % String(region_id)
	host.add_child(cm)
	cm.configure(sites_root, inv, defs, zone, null, region_id)

	if wood_stock > 0:
		assert_true(inv.deposit(&"wood", wood_stock), "Seed wood stock in %s" % String(region_id))

	var tree := ResourceSource.new()
	tree.name = "Tree_%s" % String(region_id)
	tree.position = origin_offset + Vector3(4.0, 0.0, 0.0)
	tree.set_meta(&"region_id", region_id)
	host.add_child(tree)
	tree.configure(StringName("tree_" + String(region_id)), WOOD_DEF.duplicate(), tree_amount, 2, 2)

	var unit := UNIT_SCENE.instantiate() as Unit
	unit.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	unit.definition.character_id = StringName("worker_" + String(region_id))
	unit.definition.base_carry_capacity = 20
	unit.position = origin_offset + Vector3(2.8, 0.0, 0.0)
	unit.set_meta(&"region_id", region_id)
	host.add_child(unit)
	assert_true(unit.get_carry_load().enable_provenance(unit.definition.character_id))

	return {
		"viewport": world_parent,
		"world": host.get_world_3d(),
		"host": host,
		"region_id": region_id,
		"zone": zone,
		"piles_root": piles_root,
		"sites_root": sites_root,
		"time": time_prov,
		"gpm": gpm,
		"inventory": inv,
		"cm": cm,
		"tree": tree,
		"unit": unit,
	}


## C01 — Non-empty initial regional balance: multiple trees, pre-existing stockpile,
## pre-existing mixed carry loads, active reservations, and zero audit side effects.
func test_c01_non_empty_initial_regional_balance_and_readonly_audit() -> void:
	var main := await _main_fixture(true)
	var inv := main.get_settlement_inventory()
	var gpm := main.get_ground_pile_manager()
	var cm := main.get_construction_manager()
	var units := main.get_units()

	# Seed pre-existing community stockpile with mixed resources.
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 7))
	assert_true(inv.deposit(&"food", 9))

	# Create pre-existing reservation via a real ConstructionSite (4 wood, 2 stone reserved in piles).
	var site_res := cm.try_create_site_from_placement(
		_make_building_def(&"c01_hut", {&"wood": 4, &"stone": 2}),
		Vector3(-6.0, 0.0, 1.5)
	)
	assert_true(bool(site_res.get("ok", false)), "C01 site creation succeeds: %s" % str(site_res))

	# Seed pre-existing mixed carry loads on both units via real provenance transfers on non-wood sources
	# plus one unit holding pre-existing FREE_GATHERED wood from carry fixture.
	var rock1 := _source(main, &"stone_rock_01")
	var bush1 := _source(main, &"food_bush_01")
	assert_eq(rock1.transfer_to_carry_load_with_provenance(units[0].get_carry_load(), &"c01_op_s", &"c01_lot_s", 1).get("extracted", 0), 1)
	assert_eq(bush1.transfer_to_carry_load_with_provenance(units[1].get_carry_load(), &"c01_op_f", &"c01_lot_f", 2).get("extracted", 0), 2)
	assert_true(bool(CARRY_FIXTURE.add_lot(units[0].get_carry_load(), &"c01_seed_w", &"c01_lot_w", &"wood", 2, 3, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))

	# Independently compute expected physical totals before auditing.
	var exp_wood_sources := _sum_main_sources(main, &"wood")
	var exp_stone_sources := _sum_main_sources(main, &"stone")
	var exp_food_sources := _sum_main_sources(main, &"food")

	var inv_rev_before := inv.get_transaction_revision()
	var gpm_rev_before := gpm.get_transaction_revision()
	var load0_rev_before := units[0].get_carry_load().get_transaction_revision()
	var serial_before := _regional_serial(main, cm.get_region_id())

	var snap_w := _snap_main(main, &"wood")
	var snap_s := _snap_main(main, &"stone")
	var snap_f := _snap_main(main, &"food")

	# Strictly read-only: zero revisions, receipts, or serials mutated.
	assert_eq(inv.get_transaction_revision(), inv_rev_before, "Audit must not alter inventory revision")
	assert_eq(gpm.get_transaction_revision(), gpm_rev_before, "Audit must not alter storage revision")
	assert_eq(units[0].get_carry_load().get_transaction_revision(), load0_rev_before, "Audit must not alter carry revision")
	assert_eq(_regional_serial(main, cm.get_region_id()), serial_before, "Audit must not allocate regional serials")

	assert_true(bool(snap_w.get("ok", false)), "Wood snapshot valid: %s" % str(snap_w.get("anomalies", [])))
	assert_true(bool(snap_s.get("ok", false)), "Stone snapshot valid: %s" % str(snap_s.get("anomalies", [])))
	assert_true(bool(snap_f.get("ok", false)), "Food snapshot valid: %s" % str(snap_f.get("anomalies", [])))
	assert_true(bool(snap_w.get("stable_boundary", false)))

	# Exact independent compartment verification (reservations and mirrors NEVER added to Q).
	assert_eq(int(snap_w["compartments"]["natural_sources"]), exp_wood_sources)
	assert_eq(int(snap_w["compartments"]["unit_carry_loads"]), 3)
	assert_eq(int(snap_w["compartments"]["camp_storage"]), 12)
	assert_eq(int(snap_w["total_physical"]), exp_wood_sources + 3 + 12)
	assert_eq(int(snap_w["mirrors"]["camp_reserved"]), 4)
	assert_eq(int(snap_w["mirrors"]["camp_available"]), 8)
	assert_eq(int(snap_w["mirrors"]["inventory_physical"]), 12)
	assert_eq(int(snap_w["mirrors"]["provenance_ledger_total"]), 3)

	assert_eq(int(snap_s["compartments"]["natural_sources"]), exp_stone_sources)
	assert_eq(int(snap_s["compartments"]["unit_carry_loads"]), 1)
	assert_eq(int(snap_s["compartments"]["camp_storage"]), 7)
	assert_eq(int(snap_s["total_physical"]), exp_stone_sources + 1 + 7)
	assert_eq(int(snap_s["mirrors"]["camp_reserved"]), 2)

	assert_eq(int(snap_f["compartments"]["natural_sources"]), exp_food_sources)
	assert_eq(int(snap_f["compartments"]["unit_carry_loads"]), 2)
	assert_eq(int(snap_f["compartments"]["camp_storage"]), 9)
	assert_eq(int(snap_f["total_physical"]), exp_food_sources + 2 + 9)


## C02 — Cutting and felling stages (STANDING -> CHOPPING -> FELLING -> FALLEN):
## zero extraction, zero FREE_GATHERED lot, zero extraction operation before FALLEN.
func test_c02_cut_and_felling_preserve_zero_extraction_deltas() -> void:
	var main := await _main_fixture(true)
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 5))
	var tree := _source(main, &"wood_tree_01")
	tree.configure(tree.source_id, tree.get_definition(), 6, 2, 2)
	var unit := main.get_units()[0]
	_place_in_range(unit, tree, Vector3.LEFT)

	var snap_standing := _snap_main(main, &"wood")
	var region_id := main.get_construction_manager().get_region_id()
	var serial_before := _regional_serial(main, region_id)
	var stage_snapshots: Dictionary = {}

	tree.tree_harvest_stage_changed.connect(func(_src: ResourceSource, st: int) -> void:
		if st in [CHOPPING, FELLING, FALLEN]:
			stage_snapshots[st] = {
				"snap": _snap_main(main, &"wood"),
				"tree_remaining": tree.get_remaining_amount(),
				"regional_serial": _regional_serial(main, region_id),
			}
	)

	assert_true(_gather_at(main, tree, [unit]))
	var order := unit.get_current_order() as GatherResourceOrder
	if not assert_not_null(order):
		return
	assert_true(await _until(func() -> bool: return tree.get_tree_harvest_stage() == FALLEN, 400), "Tree reaches FALLEN")

	for st: int in [CHOPPING, FELLING, FALLEN]:
		assert_true(stage_snapshots.has(st), "Captured snapshot at stage %d" % st)
		var entry: Dictionary = stage_snapshots[st] as Dictionary
		var s: Dictionary = entry["snap"] as Dictionary
		var check := RegionalConservationAudit.verify_conservation(snap_standing, s)
		assert_true(bool(check["ok"]), "Conservation holds at stage %d: %s" % [st, str(check)])
		assert_eq(int(check["compartment_deltas"]["natural_sources"]), 0, "Zero source delta at stage %d" % st)
		assert_eq(int(check["compartment_deltas"]["unit_carry_loads"]), 0, "Zero carry delta at stage %d" % st)
		assert_eq(int(check["compartment_deltas"]["camp_storage"]), 0, "Zero storage delta at stage %d" % st)
		assert_eq(int(entry["tree_remaining"]), 6, "Tree keeps full 6 wood at stage %d" % st)
		assert_eq(int(s["mirrors"]["provenance_free_gathered"]), int(snap_standing["mirrors"]["provenance_free_gathered"]), "Zero new FREE_GATHERED at stage %d" % st)
		assert_eq(int(entry["regional_serial"]), serial_before, "Zero extraction op allocated before collection at stage %d" % st)

	unit.cancel_current_order()


## C03 — Cancellation, freeze by personal interruption, resume, cancel during FELLING,
## and reauthorization after FALLEN: zero wood created or destroyed across all transitions.
func test_c03_cancellation_freeze_resume_and_reauthorization_conserve_wood() -> void:
	var main := await _main_fixture(true)
	var tree := _source(main, &"wood_tree_01")
	tree.configure(tree.source_id, tree.get_definition(), 4, 2, 2)
	var units := main.get_units()
	var u0 := units[0]
	var u1 := units[1]
	_place_in_range(u0, tree, Vector3.LEFT)
	_place_in_range(u1, tree, Vector3.RIGHT)
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()

	var s0 := _snap_main(main, &"wood")

	# 1. Pre-fall cancellation via HUD/dispatcher resets CHOPPING -> STANDING with 0 wood delta.
	var task1 := board.register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task1):
		return
	assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() >= 0.35, 240))
	assert_eq(int(dispatcher.cancel_tasks_for_sources([tree], &"wood").get("cancelled_count", 0)), 1)
	assert_eq(tree.get_tree_harvest_stage(), STANDING)
	var s1 := _snap_main(main, &"wood")
	var c1 := RegionalConservationAudit.verify_conservation(s0, s1)
	assert_true(bool(c1["ok"]), "Pre-fall cancel conserves wood: %s" % str(c1))
	assert_eq(int(c1["compartment_deltas"]["natural_sources"]), 0)

	# 2. Freeze by personal MoveOrder interruption, then resume via second worker on same community task.
	var task2 := board.register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task2):
		return
	assert_true(await _until(func() -> bool: return tree.get_tree_cut_progress_sec() >= 0.40, 240))
	var first_worker := task2.assigned_unit
	var frozen_progress := tree.get_tree_cut_progress_sec()
	main.get_selection_manager().set_selection([first_worker])
	assert_true(main.get_command_controller().command_at(PickResult.from_ground(first_worker.global_position + Vector3(0.0, 0.0, 3.0), Vector3.UP)))
	await wait_physics_frames(4)
	assert_true(tree.get_tree_cut_progress_sec() >= frozen_progress - 0.001, "Frozen progress preserved during handoff")
	var s2 := _snap_main(main, &"wood")
	assert_true(bool(RegionalConservationAudit.verify_conservation(s0, s2)["ok"]))

	# 3. Wait for legitimate resume to commit FELLING, then cancel during FELLING -> finishes irreversibly to FALLEN.
	assert_true(await _until(func() -> bool: return tree.get_tree_harvest_stage() == FELLING, 420), "Resumed worker commits FELLING")
	assert_eq(int(dispatcher.cancel_tasks_for_sources([tree], &"wood").get("cancelled_count", 0)), 1)
	assert_true(await _until(func() -> bool: return tree.get_tree_harvest_stage() == FALLEN, 90), "Tree finishes fall into FALLEN")
	var s3 := _snap_main(main, &"wood")
	var c3 := RegionalConservationAudit.verify_conservation(s0, s3)
	assert_true(bool(c3["ok"]), "Cancel during FELLING conserves wood: %s" % str(c3))
	assert_eq(tree.get_remaining_amount(), 4)
	assert_eq(int(c3["compartment_deltas"]["natural_sources"]), 0)
	assert_eq(int(c3["compartment_deltas"]["unit_carry_loads"]), 0)
	assert_eq(int(c3["compartment_deltas"]["camp_storage"]), 0)

	# 4. Reauthorize after FALLEN -> full physical extraction and delivery.
	var task3 := board.register_gather_task(tree).get("task") as WorkTask
	if not assert_not_null(task3):
		return
	assert_true(await _until(func() -> bool: return not task3.is_active(), 1400), "Post-FALLEN task completes")
	assert_eq(task3.state, WorkTask.State.COMPLETED)
	var s4 := _snap_main(main, &"wood")
	var c4 := RegionalConservationAudit.verify_conservation(s0, s4)
	assert_true(bool(c4["ok"]), "Post-FALLEN collection conserves wood: %s" % str(c4))
	assert_eq(int(c4["compartment_deltas"]["natural_sources"]), -4)
	assert_eq(int(c4["compartment_deltas"]["unit_carry_loads"]), 0)
	assert_eq(int(c4["compartment_deltas"]["camp_storage"]), 4)


## C04 — Real multi-trip extraction clamped by backpack capacity and mixed weights.
func test_c04_multi_trip_extraction_capacity_mixed_weights_and_depletion() -> void:
	var main := await _main_fixture(true)
	var tree := _source(main, &"wood_tree_01")
	tree.configure(tree.source_id, tree.get_definition(), 11, 2, 2)
	tree.set_gather_cycle_timings(0.25, 0.1)
	var unit := main.get_units()[0]
	var load := unit.get_carry_load()
	# Capacity 14: 2 pre-existing stone (weight 3*2 = 6) leaves room for 4 wood (weight 2*4 = 8) on trip 1.
	# Remaining 7 wood after trip 1 -> trip 2 carries 7 wood? 7*2 = 14 fits in empty bag (max_extract=2 -> 2+2+2+1=7).
	# Wait: 4 + 7 = 11 -> 2 trips! Let's use 13 wood so 3 real trips occur (4 wood + 7 wood + 2 wood = 13)!
	tree.configure(tree.source_id, tree.get_definition(), 13, 2, 2)
	tree.set_gather_cycle_timings(0.20, 0.05)
	assert_true(load.set_base_capacity(14))
	var rock := _source(main, &"stone_rock_01")
	assert_eq(rock.transfer_to_carry_load_with_provenance(load, &"c04_s1", &"c04_lot_s1", 1).get("extracted", 0), 1)
	assert_eq(rock.transfer_to_carry_load_with_provenance(load, &"c04_s2", &"c04_lot_s2", 1).get("extracted", 0), 1)
	assert_eq(load.get_current_weight(), 6)

	var sw0 := _snap_main(main, &"wood")
	var ss0 := _snap_main(main, &"stone")

	_place_in_range(unit, tree, Vector3.LEFT)
	assert_true(_gather_at(main, tree, [unit]))
	var order := unit.get_current_order() as GatherResourceOrder
	if not assert_not_null(order):
		return

	var observed_max_weight: int = 0
	var trip_snapshots: Array[Dictionary] = []
	var prev_trips: int = 0
	for _frame: int in range(3600):
		observed_max_weight = maxi(observed_max_weight, load.get_current_weight())
		assert_true(load.get_current_weight() <= load.get_effective_capacity(), "Weight never exceeds capacity")
		if order.get_delivered_trips() > prev_trips:
			prev_trips = order.get_delivered_trips()
			trip_snapshots.append(_snap_main(main, &"wood"))
		if order.is_finished():
			break
		await wait_physics_frames(1)

	assert_true(order.is_succeeded(), "Multi-trip gather order succeeds")
	assert_eq(tree.get_remaining_amount(), 0)
	assert_eq(tree.get_tree_harvest_stage(), DEPLETED)
	assert_eq(order.get_delivered_trips(), 3, "Mixed weights clamp trip 1 (4 wood + 2 stone), trip 2 (7 wood), trip 3 (2 wood)")
	assert_eq(observed_max_weight, 14)

	for idx: int in range(trip_snapshots.size()):
		var c_trip := RegionalConservationAudit.verify_conservation(sw0, trip_snapshots[idx])
		assert_true(bool(c_trip["ok"]), "Conservation holds at trip %d: %s" % [idx + 1, str(c_trip)])

	var sw1 := _snap_main(main, &"wood")
	var ss1 := _snap_main(main, &"stone")
	var cw := RegionalConservationAudit.verify_conservation(sw0, sw1)
	var cs := RegionalConservationAudit.verify_conservation(ss0, ss1)
	assert_true(bool(cw["ok"]), "Final wood conservation: %s" % str(cw))
	assert_true(bool(cs["ok"]), "Final stone conservation: %s" % str(cs))
	assert_eq(int(cw["compartment_deltas"]["natural_sources"]), -13)
	assert_eq(int(cw["compartment_deltas"]["camp_storage"]), 13)
	assert_eq(int(cw["compartment_deltas"]["unit_carry_loads"]), 0)
	assert_eq(int(cs["compartment_deltas"]["unit_carry_loads"]), -2)
	assert_eq(int(cs["compartment_deltas"]["camp_storage"]), 2)


## C05 — Two workers cutting and collecting on the same tree, disputing the last odd unit.
func test_c05_two_workers_same_tree_dispute_final_units_with_exact_conservation() -> void:
	var main := await _main_fixture(true)
	var tree := _source(main, &"wood_tree_01")
	tree.configure(tree.source_id, tree.get_definition(), 5, 2, 2)
	tree.set_gather_cycle_timings(0.25, 0.05)
	var units := main.get_units()
	_place_in_range(units[0], tree, Vector3.LEFT)
	_place_in_range(units[1], tree, Vector3.RIGHT)

	var s0 := _snap_main(main, &"wood")
	assert_true(_gather_at(main, tree, units))
	var ord0 := units[0].get_current_order() as GatherResourceOrder
	var ord1 := units[1].get_current_order() as GatherResourceOrder
	if not assert_not_null(ord0) or not assert_not_null(ord1):
		return

	assert_true(await _until(func() -> bool: return ord0.is_finished() and ord1.is_finished(), 2400), "Both orders finish")
	var extracted_sum: int = ord0.get_total_extracted_units() + ord1.get_total_extracted_units()
	assert_eq(extracted_sum, 5, "Sum extracted by both workers equals exact tree balance (5)")
	assert_eq(tree.get_remaining_amount(), 0)
	assert_eq(tree.get_tree_harvest_stage(), DEPLETED)

	var s1 := _snap_main(main, &"wood")
	var check := RegionalConservationAudit.verify_conservation(s0, s1)
	assert_true(bool(check["ok"]), "Two-worker conservation: %s" % str(check))
	assert_eq(int(check["compartment_deltas"]["natural_sources"]), -5)
	assert_eq(int(check["compartment_deltas"]["camp_storage"]), 5)
	assert_eq(int(check["compartment_deltas"]["unit_carry_loads"]), 0)


## C06 — Provenance, idempotent replay, conflict, pre-commit rollback, protected busy retry,
## and uncertain outcome reconciled by receipt.
func test_c06_provenance_replay_conflict_rollback_retry_and_uncertain_reconciliation() -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	add_test_child(view)
	var dom := _create_isolated_domain(view, &"c06_region", Vector3.ZERO, 3, 0)
	# Replace default tree with FailingPreCommitTreeSource in FALLEN state for controlled transaction tests.
	var tree := FailingPreCommitTreeSource.new()
	tree.name = "FailingTree"
	tree.position = Vector3(4.0, 0.0, 0.0)
	tree.set_meta(&"region_id", &"c06_region")
	(dom["host"] as Node3D).add_child(tree)
	tree.configure(&"c06_tree", WOOD_DEF.duplicate(), 8, 2, 2)
	tree.set(&"_tree_harvest_stage", FALLEN)

	var inv: SettlementInventory = dom["inventory"] as SettlementInventory
	var zone: CampStorageZone = dom["zone"] as CampStorageZone
	var unit: Unit = dom["unit"] as Unit
	var w: World3D = dom["world"] as World3D
	var load := unit.get_carry_load()
	var s0 := RegionalConservationAudit.capture(get_tree(), w, &"c06_region", &"wood", inv)
	assert_true(bool(s0["ok"]), str(s0.get("anomalies", [])))
	assert_eq(int(s0["total_physical"]), 11) # 8 tree + 3 camp

	# 1. Legitimate extraction (-2 source, +2 carry).
	var r1 := tree.transfer_to_carry_load_with_provenance(load, &"c06_op1", &"c06_lot1", 2)
	assert_true(bool(r1.get("ok", false)) and int(r1.get("extracted", 0)) == 2)
	var s1 := RegionalConservationAudit.capture(get_tree(), w, &"c06_region", &"wood", inv)
	var c1 := RegionalConservationAudit.verify_conservation(s0, s1)
	assert_true(bool(c1["ok"]), "Legitimate provenance extraction conserves: %s" % str(c1))
	assert_eq(int(c1["compartment_deltas"]["natural_sources"]), -2)
	assert_eq(int(c1["compartment_deltas"]["unit_carry_loads"]), 2)

	# 2. Idempotent replay (0 delta).
	var r_rep := tree.transfer_to_carry_load_with_provenance(load, &"c06_op1", &"c06_lot1", 2)
	assert_true(bool(r_rep.get("ok", false)) and bool(r_rep.get("replayed", false)) and int(r_rep.get("extracted", -1)) == 0)
	var s2 := RegionalConservationAudit.capture(get_tree(), w, &"c06_region", &"wood", inv)
	assert_eq(s2["compartments"], s1["compartments"], "Replay leaves every compartment identical")

	# 3. Conflicting operation (rejected, 0 delta).
	var r_conf := tree.transfer_to_carry_load_with_provenance(load, &"c06_op1", &"c06_lot_other", 2)
	assert_false(bool(r_conf.get("ok", true)))
	assert_eq(String(r_conf.get("reason", "")), "operation_conflict")
	var s3 := RegionalConservationAudit.capture(get_tree(), w, &"c06_region", &"wood", inv)
	assert_eq(s3["compartments"], s1["compartments"], "Conflict leaves every compartment identical")

	# 4. Pre-commit failure and rollback (0 delta).
	tree.fail_next_commit = true
	var r_rb := tree.transfer_to_carry_load_with_provenance(load, &"c06_op_rb", &"c06_lot_rb", 2)
	assert_false(bool(r_rb.get("ok", true)))
	assert_eq(String(r_rb.get("reason", "")), "stale_or_aborted")
	var s4 := RegionalConservationAudit.capture(get_tree(), w, &"c06_region", &"wood", inv)
	assert_eq(s4["compartments"], s1["compartments"], "Pre-commit failure rolls back completely")
	assert_true(tree.get_provenance_receipt(&"c06_op_rb").is_empty())

	# 5. Protected retry on busy via GatherTransferSession.
	var retry_session := GatherTransferSession.new()
	assert_true(bool(retry_session.initialize_cycle(inv, zone, tree, unit, &"c06_region", 701, 1, 2).get("ok", false)))
	load._provenance_busy = true
	var busy_res := retry_session.execute_or_retry(inv, zone, tree, unit, &"c06_region", 701, true)
	load._provenance_busy = false
	assert_false(bool(busy_res.get("ok", true)))
	assert_true(retry_session.is_retry_scheduled(), "Session schedules bounded retry on busy")
	assert_true(retry_session.retry_is_due(GatherTransferSession.RETRY_INTERVAL_SEC + 0.05))
	var retry_ok := retry_session.execute_or_retry(inv, zone, tree, unit, &"c06_region", 701, true)
	assert_true(bool(retry_ok.get("ok", false)) and int(retry_ok.get("extracted", 0)) == 2)
	var s5 := RegionalConservationAudit.capture(get_tree(), w, &"c06_region", &"wood", inv)
	var c5 := RegionalConservationAudit.verify_conservation(s0, s5)
	assert_true(bool(c5["ok"]), "Protected retry conserves: %s" % str(c5))
	assert_eq(int(c5["compartment_deltas"]["natural_sources"]), -4)
	assert_eq(int(c5["compartment_deltas"]["unit_carry_loads"]), 4)

	# 6. Uncertain outcome reconciled by receipt (never double-extracts).
	var unc_session := UncertainOutcomeGatherSession.new()
	assert_true(bool(unc_session.initialize_cycle(inv, zone, tree, unit, &"c06_region", 702, 1, 2).get("ok", false)))
	var unc_res := unc_session.execute_or_retry(inv, zone, tree, unit, &"c06_region", 702, true)
	assert_true(bool(unc_res.get("ok", false)) and bool(unc_res.get("replayed", false)))
	assert_eq(int(unc_res.get("committed_amount", 0)), 2)
	var s6 := RegionalConservationAudit.capture(get_tree(), w, &"c06_region", &"wood", inv)
	var c6 := RegionalConservationAudit.verify_conservation(s0, s6)
	assert_true(bool(c6["ok"]), "Uncertain outcome reconciliation conserves: %s" % str(c6))
	assert_eq(int(c6["compartment_deltas"]["natural_sources"]), -6)
	assert_eq(int(c6["compartment_deltas"]["unit_carry_loads"]), 6)


## C07 & C08 — Legacy P-REC-1 construction flow: reservation, reserved withdrawal,
## site delivery to buffer, assembly consumption, and completion transfer to BuildingInstance.
func test_c07_c08_reservation_transport_assembly_and_building_completion() -> void:
	var main := await _main_fixture(true)
	var inv := main.get_settlement_inventory()
	var gpm := main.get_ground_pile_manager()
	var cm := main.get_construction_manager()
	var unit := main.get_units()[0]
	var load := unit.get_carry_load()
	assert_true(load.set_base_capacity(80))
	assert_true(inv.deposit(&"wood", 10))
	assert_true(inv.deposit(&"stone", 6))

	var sw0 := _snap_main(main, &"wood")
	var ss0 := _snap_main(main, &"stone")

	# C07 step 1: Reserve for ConstructionSite (4 wood, 2 stone) -> 0 physical delta!
	var nav := main.get_test_map().get_navigation()
	var def := _make_building_def(&"c07_shelter", {&"wood": 4, &"stone": 2}, 4.0)
	var create_res := cm.try_create_site_from_placement(def, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(create_res.get("ok", false)), "C07 site created: %s" % str(create_res))
	var site := create_res["site"] as ConstructionSite
	var sw_res := _snap_main(main, &"wood")
	var ss_res := _snap_main(main, &"stone")
	assert_true(bool(RegionalConservationAudit.verify_conservation(sw0, sw_res)["ok"]))
	assert_true(bool(RegionalConservationAudit.verify_conservation(ss0, ss_res)["ok"]))
	assert_eq(sw_res["compartments"], sw0["compartments"], "Reserving creates zero physical wood")
	assert_eq(ss_res["compartments"], ss0["compartments"], "Reserving creates zero physical stone")
	assert_eq(int(sw_res["mirrors"]["camp_reserved"]), 4)
	assert_eq(int(ss_res["mirrors"]["camp_reserved"]), 2)

	# C07 step 2: Reserved withdrawal from camp piles to carry load (complementary deltas).
	_arm_construct_order(site, unit, true)
	var coord := ReservedWithdrawalCoordinator.new()
	var w_entries := gpm.get_reserved_pile_entries(site.reservation_id, &"wood")
	var s_entries := gpm.get_reserved_pile_entries(site.reservation_id, &"stone")
	assert_true(not w_entries.is_empty() and not s_entries.is_empty())
	var w_pile := w_entries[0]["pile"] as GroundResourcePile
	var s_pile := s_entries[0]["pile"] as GroundResourcePile

	unit.global_position = w_pile.global_position + Vector3(0.4, 0.0, 0.0)
	assert_eq(site.claim_pickup(unit, w_pile.pile_id, &"wood", 4), 4)
	var wd_w := coord.execute_reserved_withdrawal(site, unit, w_pile.pile_id, &"wood", 4, &"c07_wd_w", &"c07_lot_w")
	assert_true(bool(wd_w.get("ok", false)) and int(wd_w.get("withdrawn", 0)) == 4)

	unit.global_position = s_pile.global_position + Vector3(0.4, 0.0, 0.0)
	assert_eq(site.claim_pickup(unit, s_pile.pile_id, &"stone", 2), 2)
	var wd_s := coord.execute_reserved_withdrawal(site, unit, s_pile.pile_id, &"stone", 2, &"c07_wd_s", &"c07_lot_s")
	assert_true(bool(wd_s.get("ok", false)) and int(wd_s.get("withdrawn", 0)) == 2)

	var sw_wd := _snap_main(main, &"wood")
	var ss_wd := _snap_main(main, &"stone")
	var cw_wd := RegionalConservationAudit.verify_conservation(sw0, sw_wd)
	var cs_wd := RegionalConservationAudit.verify_conservation(ss0, ss_wd)
	assert_true(bool(cw_wd["ok"]), "Wood withdrawal conserves: %s" % str(cw_wd))
	assert_true(bool(cs_wd["ok"]), "Stone withdrawal conserves: %s" % str(cs_wd))
	assert_eq(int(cw_wd["compartment_deltas"]["camp_storage"]), -4)
	assert_eq(int(cw_wd["compartment_deltas"]["unit_carry_loads"]), 4)
	assert_eq(int(cs_wd["compartment_deltas"]["camp_storage"]), -2)
	assert_eq(int(cs_wd["compartment_deltas"]["unit_carry_loads"]), 2)
	assert_eq(int(sw_wd["mirrors"]["sites_transit_claims"]), 4)

	# C07 step 3: Selective delivery to ConstructionSite buffer (complementary deltas).
	var dropoff := nav.snap_to_navmesh(site.global_position + Vector3(0.0, 0.0, 2.0))
	unit.global_position = dropoff
	var deliv := SelectiveSiteDeliveryCoordinator.new()
	var del_res := deliv.execute_selective_site_delivery(site, unit, &"c07_deliv")
	assert_true(bool(del_res.get("ok", false)), "Site delivery succeeds: %s" % str(del_res))

	var sw_buf := _snap_main(main, &"wood")
	var ss_buf := _snap_main(main, &"stone")
	var cw_buf := RegionalConservationAudit.verify_conservation(sw0, sw_buf)
	var cs_buf := RegionalConservationAudit.verify_conservation(ss0, ss_buf)
	assert_true(bool(cw_buf["ok"]), "Wood site delivery conserves: %s" % str(cw_buf))
	assert_true(bool(cs_buf["ok"]), "Stone site delivery conserves: %s" % str(cs_buf))
	assert_eq(int(cw_buf["compartment_deltas"]["unit_carry_loads"]), 0)
	assert_eq(int(cw_buf["compartment_deltas"]["construction_sites_buffer"]), 4)
	assert_eq(int(cw_buf["compartment_deltas"]["construction_sites_consumed"]), 0)
	assert_eq(int(cs_buf["compartment_deltas"]["construction_sites_buffer"]), 2)

	# C08 step 1: Partial assembly transfers buffer -> consumed without double-counting get_total_received_amounts().
	var helper_unit := main.get_units()[1]
	_arm_construct_order(site, helper_unit, false)
	var _build_order := _arm_construct_order(site, unit, false)
	assert_eq(site.get_worker_role(unit), ConstructionSite.WorkerRole.BUILDER)
	var slot_idx := site.get_builder_slot_index(unit)
	assert_true(site.assign_builder_slot_position(unit, slot_idx, dropoff))
	unit.global_position = dropoff

	# Advance 2.0s out of 4.0s (50%) in deterministic 0.25s steps -> consumes 2 wood, 1 stone.
	for _step: int in range(8):
		await wait_physics_frames(1)
		var work_res := site.contribute_work(unit, 0.25)
		assert_true(bool(work_res.get("ok", false)), "Work step ok: %s" % str(work_res))
	var sw_mid := _snap_main(main, &"wood")
	var ss_mid := _snap_main(main, &"stone")
	var cw_mid := RegionalConservationAudit.verify_conservation(sw0, sw_mid)
	var cs_mid := RegionalConservationAudit.verify_conservation(ss0, ss_mid)
	assert_true(bool(cw_mid["ok"]), "Mid-assembly wood conserves: %s" % str(cw_mid))
	assert_true(bool(cs_mid["ok"]), "Mid-assembly stone conserves: %s" % str(cs_mid))
	assert_eq(int(sw_mid["compartments"]["construction_sites_buffer"]), 2)
	assert_eq(int(sw_mid["compartments"]["construction_sites_consumed"]), 2)
	assert_eq(int(ss_mid["compartments"]["construction_sites_buffer"]), 1)
	assert_eq(int(ss_mid["compartments"]["construction_sites_consumed"]), 1)

	# C08 step 2: Finish remaining 2.0s -> COMPLETING -> complete_site_transaction -> BuildingInstance owns materials!
	for _step: int in range(8):
		await wait_physics_frames(1)
		var work_res := site.contribute_work(unit, 0.25)
		assert_true(bool(work_res.get("ok", false)), "Finish step ok: %s" % str(work_res))
	unit.set_physics_process(true)
	helper_unit.set_physics_process(true)
	assert_eq(site.get_site_state(), ConstructionSite.SiteState.COMPLETING)
	assert_true(cm.complete_site_transaction(site), "Site completion commits atomically")
	await wait_physics_frames(2)

	var sw_done := _snap_main(main, &"wood")
	var ss_done := _snap_main(main, &"stone")
	var cw_done := RegionalConservationAudit.verify_conservation(sw0, sw_done)
	var cs_done := RegionalConservationAudit.verify_conservation(ss0, ss_done)
	assert_true(bool(cw_done["ok"]), "Post-completion wood conserves: %s" % str(cw_done))
	assert_true(bool(cs_done["ok"]), "Post-completion stone conserves: %s" % str(cs_done))
	assert_eq(int(sw_done["compartments"]["construction_sites_buffer"]), 0)
	assert_eq(int(sw_done["compartments"]["construction_sites_consumed"]), 0)
	assert_eq(int(sw_done["compartments"]["completed_buildings"]), 4)
	assert_eq(int(ss_done["compartments"]["completed_buildings"]), 2)


## C09 — Construction cancellation with reserved, in-transit, buffer, incorporated,
## demolition loss, physical recovery (A->H), and return to camp (H->E).
func test_c09_construction_cancellation_custody_demolition_loss_and_recovery() -> void:
	var main := await _main_fixture(true)
	var inv := main.get_settlement_inventory()
	var gpm := main.get_ground_pile_manager()
	var cm := main.get_construction_manager()
	var units := main.get_units()
	var u0 := units[0]
	var u1 := units[1]
	assert_true(u0.get_carry_load().set_base_capacity(80))
	assert_true(u1.get_carry_load().set_base_capacity(80))
	assert_true(inv.deposit(&"wood", 12))

	var s0 := _snap_main(main, &"wood")

	# Site requiring 10 wood, build_work = 10.0s:
	# - 2 wood stays reserved in piles (L = 2)
	# - 2 wood stays in transit in u0's backpack (H = 2)
	# - 6 wood delivered to site, 4.0s work (40%) -> 4 incorporated, 2 buffer
	# Expected D3 refund math on 4 incorporated at 40% progress:
	#   remaining = 6_000_000, fraction = (4 * 6_000_000) / 10_000_000 = 2, recovered = 2 / 2 = 1
	#   demolition_loss = 4 - 1 = 3
	#   local_buffer_remaining = 2, local_incorporated_remaining = 1 (A = 3)
	var nav := main.get_test_map().get_navigation()
	var def := _make_building_def(&"c09_longhouse", {&"wood": 10}, 10.0)
	var create_res := cm.try_create_site_from_placement(def, Vector3(-6.0, 0.0, 1.5))
	assert_true(bool(create_res.get("ok", false)), "C09 site created: %s" % str(create_res))
	var site := create_res["site"] as ConstructionSite
	var coord := ReservedWithdrawalCoordinator.new()
	var w_pile := gpm.get_reserved_pile_entries(site.reservation_id, &"wood")[0]["pile"] as GroundResourcePile

	# u0 withdraws 2 wood first (auto worker #1 -> TRANSPORTER so auto worker #2 u1 becomes BUILDER under D9).
	_arm_construct_order(site, u0, false)
	u0.global_position = w_pile.global_position + Vector3(0.4, 0.0, 0.0)
	assert_eq(site.claim_pickup(u0, w_pile.pile_id, &"wood", 2), 2)
	assert_true(bool(coord.execute_reserved_withdrawal(site, u0, w_pile.pile_id, &"wood", 2, &"c09_wd_2", &"c09_lot_2").get("ok", false)))

	# u1 withdraws 6 and delivers 6 to site buffer.
	_arm_construct_order(site, u1, true)
	u1.global_position = w_pile.global_position + Vector3(0.4, 0.0, 0.0)
	assert_eq(site.claim_pickup(u1, w_pile.pile_id, &"wood", 6), 6)
	assert_true(bool(coord.execute_reserved_withdrawal(site, u1, w_pile.pile_id, &"wood", 6, &"c09_wd_6", &"c09_lot_6").get("ok", false)))
	var dropoff := nav.snap_to_navmesh(site.global_position + Vector3(0.0, 0.0, 2.0))
	u1.global_position = dropoff
	assert_true(bool(SelectiveSiteDeliveryCoordinator.new().execute_selective_site_delivery(site, u1, &"c09_del_6").get("ok", false)))

	# u1 switches to auto worker #2 -> BUILDER (while u0 is auto TRANSPORTER) and assembles 4.0s -> consumes 4, leaves 2 buffer.
	var _build_order := _arm_construct_order(site, u1, false)
	assert_eq(site.get_worker_role(u1), ConstructionSite.WorkerRole.BUILDER)
	assert_true(site.assign_builder_slot_position(u1, site.get_builder_slot_index(u1), dropoff))
	for _i: int in range(16):
		await wait_physics_frames(1)
		assert_true(bool(site.contribute_work(u1, 0.25).get("ok", false)))
	assert_eq(site.get_consumed_amount(&"wood"), 4)
	assert_eq(site.get_delivered_buffer_amount(&"wood"), 2)
	u0.set_physics_process(true)
	u1.set_physics_process(true)

	var s_pre_cancel := _snap_main(main, &"wood")
	assert_true(bool(RegionalConservationAudit.verify_conservation(s0, s_pre_cancel)["ok"]))
	assert_eq(int(s_pre_cancel["compartments"]["camp_storage"]), 4) # 12 initial - 8 withdrawn (2 free + 2 reserved)
	assert_eq(int(s_pre_cancel["compartments"]["unit_carry_loads"]), 2)
	assert_eq(int(s_pre_cancel["compartments"]["construction_sites_buffer"]), 2)
	assert_eq(int(s_pre_cancel["compartments"]["construction_sites_consumed"]), 4)

	# Execute D3 cancellation commit.
	var cancel_res := SiteCancellationTransaction.execute(site, &"c09_cancel_op")
	assert_true(bool(cancel_res.get("ok", false)), "Cancellation commits: %s" % str(cancel_res))
	var cancel_id: StringName = (cancel_res["receipt"] as Dictionary)["cancel_id"] as StringName

	var s_post_cancel := _snap_main(main, &"wood")
	var c_cancel := RegionalConservationAudit.verify_conservation(s0, s_post_cancel)
	assert_true(bool(c_cancel["ok"]), "Post-cancel conservation with independent demolition_loss: %s" % str(c_cancel))
	assert_eq(int(c_cancel["demolition_delta"]), 3, "Independent demolition loss equals 3")
	assert_eq(int(s_post_cancel["compartments"]["construction_sites_buffer"]), 0)
	assert_eq(int(s_post_cancel["compartments"]["construction_sites_consumed"]), 0)
	assert_eq(int(s_post_cancel["compartments"]["cancellation_local_buffer"]), 2)
	assert_eq(int(s_post_cancel["compartments"]["cancellation_local_incorporated"]), 1)
	assert_eq(int(s_post_cancel["compartments"]["unit_carry_loads"]), 2)
	assert_eq(int(s_post_cancel["compartments"]["camp_storage"]), 4)
	assert_eq(int(s_post_cancel["mirrors"]["cancellation_in_transit"]), 2)
	assert_eq(int(s_post_cancel["mirrors"]["camp_reserved"]), 0)

	# Physical recovery A -> H: u1 picks up 2 CANCEL_BUFFER + 1 CANCEL_INCORPORATED from cancelled footprint.
	u1.cancel_current_order()
	u1.global_position = dropoff
	var rec_req: Array[Dictionary] = [
		{"lot_id": &"c09_rec_buf", "resource_id": &"wood", "amount": 2, "origin": CarryProvenanceLedger.CANCEL_BUFFER},
		{"lot_id": &"c09_rec_inc", "resource_id": &"wood", "amount": 1, "origin": CarryProvenanceLedger.CANCEL_INCORPORATED},
	]
	var rec_res := CancellationRecoveryTransaction.recover(cancel_id, u1, rec_req, &"c09_rec_op", cm.get_region_id())
	assert_true(bool(rec_res.get("ok", false)), "Physical recovery A->H succeeds: %s" % str(rec_res))

	var s_post_rec := _snap_main(main, &"wood")
	var c_rec := RegionalConservationAudit.verify_conservation(s_post_cancel, s_post_rec)
	assert_true(bool(c_rec["ok"]), "Recovery A->H conserves: %s" % str(c_rec))
	assert_eq(int(c_rec["compartment_deltas"]["cancellation_local_buffer"]), -2)
	assert_eq(int(c_rec["compartment_deltas"]["cancellation_local_incorporated"]), -1)
	assert_eq(int(c_rec["compartment_deltas"]["unit_carry_loads"]), 3)
	assert_eq(int(s_post_rec["mirrors"]["cancellation_in_transit"]), 5)

	# Physical return H -> E: both u0 (2) and u1 (3) deliver recovered lots explicitly to camp storage.
	var camp := main.get_camp_storage_zone()
	var camp_deliv := SelectiveCampDeliveryCoordinator.new()
	u0.cancel_current_order()
	u0.global_position = camp.get_anchor_position()
	u1.global_position = camp.get_anchor_position()
	var d0 := camp_deliv.execute_selective_camp_delivery(
		inv, camp, u0, cm.get_region_id(), &"c09_ret_u0",
		[{"lot_id": &"c09_lot_2", "amount": 2}]
	)
	var d1 := camp_deliv.execute_selective_camp_delivery(
		inv, camp, u1, cm.get_region_id(), &"c09_ret_u1",
		[{"lot_id": &"c09_rec_buf", "amount": 2}, {"lot_id": &"c09_rec_inc", "amount": 1}]
	)
	assert_true(bool(d0.get("ok", false)), "u0 camp return succeeds: %s" % str(d0))
	assert_true(bool(d1.get("ok", false)), "u1 camp return succeeds: %s" % str(d1))

	var s_settled := _snap_main(main, &"wood")
	var c_settled := RegionalConservationAudit.verify_conservation(s0, s_settled)
	assert_true(bool(c_settled["ok"]), "Settled conservation holds: %s" % str(c_settled))
	assert_eq(int(c_settled["demolition_delta"]), 3)
	assert_eq(int(s_settled["compartments"]["camp_storage"]), 9) # 12 initial - 3 demolition loss
	assert_eq(int(s_settled["compartments"]["unit_carry_loads"]), 0)
	assert_eq(int(s_settled["compartments"]["cancellation_local_buffer"]), 0)
	assert_eq(int(s_settled["compartments"]["cancellation_local_incorporated"]), 0)
	assert_eq(int(s_settled["mirrors"]["cancellation_in_transit"]), 0)
	assert_eq(int(s_settled["mirrors"]["cancellation_delivered_history"]), 5)


## C10 — Legitimate decay losses registered independently on GroundPileManager
## (and proof that unregistered physical reductions fail conservation).
func test_c10_decay_losses_independently_evidenced_and_unregistered_loss_rejected() -> void:
	var main := await _main_fixture(true)
	var inv := main.get_settlement_inventory()
	var clock := main.get_economy_clock()
	assert_true(inv.deposit(&"food", 10))
	assert_true(inv.deposit(&"wood", 6))

	var sf0 := _snap_main(main, &"food")
	var sw0 := _snap_main(main, &"wood")
	assert_eq(int(sf0["losses"]["decay_losses"]), 0)

	# Food provisional decay: grace 180s + gradual interval 45s -> advancing 315s decays exactly 3 food (0 wood).
	var losses_step := clock.advance_simulated_time(315.0)
	assert_eq(int(losses_step.get(&"food", 0)), 3, "Clock/GPM independently reports 3 decayed food")
	assert_eq(int(losses_step.get(&"wood", 0)), 0)
	assert_eq(inv.get_total_decayed(&"food"), 3)

	var sf1 := _snap_main(main, &"food")
	var sw1 := _snap_main(main, &"wood")
	var cf := RegionalConservationAudit.verify_conservation(sf0, sf1)
	var cw := RegionalConservationAudit.verify_conservation(sw0, sw1)
	assert_true(bool(cf["ok"]), "Food conservation matches independent decay loss: %s" % str(cf))
	assert_eq(int(cf["decay_delta"]), 3)
	assert_eq(int(cf["compartment_deltas"]["camp_storage"]), -3)
	assert_eq(int(cf["q_final"]), int(cf["q_initial"]) - 3)
	assert_true(bool(cw["ok"]) and int(cw["decay_delta"]) == 0)

	# Proof against tautological loss derivation: an unrecorded direct withdrawal (no exit declared, no decay)
	# MUST fail conservation with exact discrepancy -2!
	assert_true(inv.withdraw(&"food", 2))
	var sf2 := _snap_main(main, &"food")
	var cf_unrecorded := RegionalConservationAudit.verify_conservation(sf1, sf2, 0, 0)
	assert_false(bool(cf_unrecorded["ok"]), "Unrecorded removal must fail conservation (never synthesized as loss)")
	assert_eq(int(cf_unrecorded["discrepancy"]), -2)
	# With explicit independent exit = 2 declared, conservation holds.
	var cf_explicit_exit := RegionalConservationAudit.verify_conservation(sf1, sf2, 0, 2)
	assert_true(bool(cf_explicit_exit["ok"]))


## C11 — Regional isolation across two distinct World3D MainScene instances sharing the same textual
## region_id ("default") plus a second distinct region_id ("region_north") in World 1.
func test_c11_regional_isolation_across_worlds_with_same_region_id_and_distinct_regions() -> void:
	var main1 := await _main_fixture(true)
	var main2 := await _main_fixture(true)
	var w1 := main1.get_world_3d()
	var w2 := main2.get_world_3d()
	assert_ne(w1.get_instance_id(), w2.get_instance_id(), "Isolated SubViewports must own distinct World3D instances")

	var inv1 := main1.get_settlement_inventory()
	var inv2 := main2.get_settlement_inventory()
	assert_true(inv1.deposit(&"wood", 10))
	assert_true(inv2.deposit(&"wood", 14))

	# Distinct region ("region_north") living in the SAME World3D as main1.
	var view1 := main1.get_parent() as SubViewport
	var dom_w1_north := _create_isolated_domain(view1, &"region_north", Vector3(40.0, 0.0, 0.0), 8, 5)

	var s_w1_def_0 := _snap_main(main1, &"wood")
	var s_w1_north_0 := RegionalConservationAudit.capture(get_tree(), w1, &"region_north", &"wood", dom_w1_north["inventory"] as SettlementInventory)
	var s_w2_def_0 := _snap_main(main2, &"wood")

	assert_true(bool(s_w1_def_0["ok"]), str(s_w1_def_0.get("anomalies", [])))
	assert_true(bool(s_w1_north_0["ok"]) and int(s_w1_north_0["total_physical"]) == 13)
	assert_true(bool(s_w2_def_0["ok"]), str(s_w2_def_0.get("anomalies", [])))

	# Operate exclusively in World 1 / "default": fell tree, extract 2, deliver 2 to camp, reserve 4, decay 1.
	var tree1 := _source(main1, &"wood_tree_01")
	var unit1 := main1.get_units()[0]
	var camp1 := main1.get_camp_storage_zone()
	var cm1 := main1.get_construction_manager()
	var clock1 := main1.get_economy_clock()

	tree1.set(&"_tree_harvest_stage", FALLEN)
	assert_eq(tree1.transfer_to_carry_load_with_provenance(unit1.get_carry_load(), &"c11_op1", &"c11_lot1", 2).get("extracted", 0), 2)
	unit1.global_position = camp1.get_anchor_position()
	var del_res := SelectiveCampDeliveryCoordinator.new().execute_selective_camp_delivery(
		inv1, camp1, unit1, &"default", &"c11_del1"
	)
	assert_true(bool(del_res.get("ok", false)), "World 1 camp delivery ok: %s" % str(del_res))
	assert_true(bool(cm1.try_create_site_from_placement(
		_make_building_def(&"c11_hut", {&"wood": 4}),
		Vector3(-6.0, 0.0, 1.5)
	).get("ok", false)))
	var dec := clock1.advance_simulated_time(540.0) # Wood grace 420s + 120s = 1 unit decayed.
	assert_eq(int(dec.get(&"wood", 0)), 1)

	var s_w1_def_1 := _snap_main(main1, &"wood")
	var s_w1_north_1 := RegionalConservationAudit.capture(get_tree(), w1, &"region_north", &"wood", dom_w1_north["inventory"] as SettlementInventory)
	var s_w2_def_1 := _snap_main(main2, &"wood")

	var c_w1_def := RegionalConservationAudit.verify_conservation(s_w1_def_0, s_w1_def_1)
	assert_true(bool(c_w1_def["ok"]), "Active domain conserves with decay=1: %s" % str(c_w1_def))
	assert_eq(int(c_w1_def["decay_delta"]), 1)
	assert_eq(int(c_w1_def["compartment_deltas"]["natural_sources"]), -2)
	assert_eq(int(c_w1_def["compartment_deltas"]["camp_storage"]), 1) # +2 delivered - 1 decayed

	# Both isolated domains (same World different region_id AND different World same region_id) have ZERO change.
	assert_eq(s_w1_north_1["compartments"], s_w1_north_0["compartments"], "Distinct region in same World untouched")
	assert_eq(s_w1_north_1["losses"], s_w1_north_0["losses"])
	assert_eq(s_w2_def_1["compartments"], s_w2_def_0["compartments"], "Same region_id in distinct World3D untouched")
	assert_eq(s_w2_def_1["losses"], s_w2_def_0["losses"])


## C12 — Adversarial accounting scenarios on controlled fixtures (zero production fault injection):
## proves detection of double-counting inventory+piles, carry+provenance, reservations,
## transit custody, cross-region inclusion, and missing/duplicated/unmanaged physical quantities.
func test_c12_adversarial_accounting_detection() -> void:
	var view1 := SubViewport.new()
	view1.own_world_3d = true
	add_test_child(view1)
	var view2 := SubViewport.new()
	view2.own_world_3d = true
	add_test_child(view2)

	var dom1 := _create_isolated_domain(view1, &"adv_region", Vector3.ZERO, 10, 6)
	var dom2 := _create_isolated_domain(view2, &"adv_region", Vector3.ZERO, 7, 4)
	var w1: World3D = dom1["world"] as World3D
	var w2: World3D = dom2["world"] as World3D
	var inv1: SettlementInventory = dom1["inventory"] as SettlementInventory
	var gpm1: GroundPileManager = dom1["gpm"] as GroundPileManager
	var cm1: ConstructionManager = dom1["cm"] as ConstructionManager
	var unit1: Unit = dom1["unit"] as Unit
	var tree1: ResourceSource = dom1["tree"] as ResourceSource

	# Prepare rich state: 4 reserved in site, 2 withdrawn to unit1 (in transit), 2 free gathered in unit1.
	var site_res := cm1.try_create_site_from_placement(_make_building_def(&"adv_hut", {&"wood": 4}), Vector3(10.0, 0.0, 10.0))
	assert_true(bool(site_res.get("ok", false)))
	var site := site_res["site"] as ConstructionSite
	_arm_construct_order(site, unit1, true)
	var pile := gpm1.get_reserved_pile_entries(site.reservation_id, &"wood")[0]["pile"] as GroundResourcePile
	unit1.global_position = pile.global_position + Vector3(0.4, 0.0, 0.0)
	assert_eq(site.claim_pickup(unit1, pile.pile_id, &"wood", 2), 2)
	assert_true(bool(ReservedWithdrawalCoordinator.new().execute_reserved_withdrawal(site, unit1, pile.pile_id, &"wood", 2, &"adv_wd", &"adv_lot_wd").get("ok", false)))
	tree1.set(&"_tree_harvest_stage", FALLEN)
	assert_eq(tree1.transfer_to_carry_load_with_provenance(unit1.get_carry_load(), &"adv_g", &"adv_lot_g", 2).get("extracted", 0), 2)

	var s_clean := RegionalConservationAudit.capture(get_tree(), w1, &"adv_region", &"wood", inv1)
	assert_true(bool(s_clean["ok"]), "Clean baseline valid: %s" % str(s_clean["anomalies"]))
	var true_q: int = 16 # 10 initial camp + 6 initial tree (4 tree + 4 carry + 8 camp = 16)
	assert_eq(int(s_clean["total_physical"]), true_q)

	# 1. Double counting inventory + piles produces exact overcount (+8) compared to audited Q.
	var naive_inv_plus_piles: int = int(s_clean["total_physical"]) + int(s_clean["mirrors"]["inventory_physical"])
	assert_eq(naive_inv_plus_piles - true_q, 8, "Detects inventory+piles double count (+8)")

	# 2. Double counting carry + provenance ledger produces exact overcount (+4),
	#    AND corrupted carry/ledger mismatch in a controlled fixture triggers audit anomaly!
	var naive_carry_plus_prov: int = int(s_clean["total_physical"]) + int(s_clean["mirrors"]["provenance_ledger_total"])
	assert_eq(naive_carry_plus_prov - true_q, 4, "Detects carry+provenance double count (+4)")
	var saved_amt: int = int(unit1.get_carry_load()._amounts[&"wood"])
	unit1.get_carry_load()._amounts[&"wood"] = saved_amt + 1
	var s_bad_prov := RegionalConservationAudit.capture(get_tree(), w1, &"adv_region", &"wood", inv1)
	unit1.get_carry_load()._amounts[&"wood"] = saved_amt
	assert_false(bool(s_bad_prov["ok"]), "Corrupted carry vs provenance ledger triggers anomaly")
	assert_true((s_bad_prov["anomalies"] as Array).any(func(a: String) -> bool: return a.begins_with("unreconciled_provenance_ledger:")))

	# 3. Double counting reservations produces exact overcount (+2).
	var naive_plus_reserved: int = int(s_clean["total_physical"]) + int(s_clean["mirrors"]["camp_reserved"])
	assert_eq(naive_plus_reserved - true_q, 2, "Detects reservation double count (+2)")

	# 4. Double counting in-transit claims / cancellation transit custody produces exact overcount (+2).
	var naive_plus_transit: int = int(s_clean["total_physical"]) + int(s_clean["mirrors"]["sites_transit_claims"])
	assert_eq(naive_plus_transit - true_q, 2, "Detects site transit claim double count (+2)")
	var cancel_res := SiteCancellationTransaction.execute(site, &"adv_cancel")
	assert_true(bool(cancel_res.get("ok", false)))
	var s_after_cancel := RegionalConservationAudit.capture(get_tree(), w1, &"adv_region", &"wood", inv1)
	assert_true(bool(s_after_cancel["ok"]))
	var naive_plus_cancel_transit: int = int(s_after_cancel["total_physical"]) + int(s_after_cancel["mirrors"]["cancellation_in_transit"])
	assert_eq(naive_plus_cancel_transit - true_q, 2, "Detects cancellation in_transit_remaining double count (+2)")

	# 5. Cross-region / cross-world misuse detected:
	#    (a) foreign-region source in same World3D is strictly excluded from adv_region;
	#    (b) passing dom2's storage (from view2) into view1 audit flags storage_piles_root_world_mismatch / authority_storage_mismatch;
	#    (c) comparing snapshots across domains fails domain_identity_mismatch.
	var foreign_tree := ResourceSource.new()
	foreign_tree.set_meta(&"region_id", &"foreign_region")
	view1.add_child(foreign_tree)
	foreign_tree.configure(&"foreign_wood", WOOD_DEF.duplicate(), 9, 2, 2)
	var s_with_foreign := RegionalConservationAudit.capture(get_tree(), w1, &"adv_region", &"wood", inv1)
	assert_true(bool(s_with_foreign["ok"]))
	assert_eq(int(s_with_foreign["total_physical"]), true_q, "Foreign-region source in same World3D must NOT be counted")
	foreign_tree.get_parent().remove_child(foreign_tree)
	foreign_tree.free()
	var s_cross_storage := RegionalConservationAudit.capture(get_tree(), w1, &"adv_region", &"wood", dom2["inventory"] as SettlementInventory)
	assert_false(bool(s_cross_storage["ok"]), "Mismatched cross-world storage must fail audit")
	var s_dom2 := RegionalConservationAudit.capture(get_tree(), w2, &"adv_region", &"wood", dom2["inventory"] as SettlementInventory)
	assert_true(bool(s_dom2["ok"]))
	var c_cross_diff := RegionalConservationAudit.verify_conservation(s_after_cancel, s_dom2)
	assert_false(bool(c_cross_diff["ok"]))
	assert_eq(String(c_cross_diff["reason"]), "domain_identity_mismatch")

	# 6a. Missing or duplicated physical quantity detected with exact discrepancy (-3 and +5).
	assert_true(inv1.withdraw(&"wood", 3))
	var s_missing := RegionalConservationAudit.capture(get_tree(), w1, &"adv_region", &"wood", inv1)
	var c_missing := RegionalConservationAudit.verify_conservation(s_after_cancel, s_missing)
	assert_false(bool(c_missing["ok"]))
	assert_eq(int(c_missing["discrepancy"]), -3, "Detects missing 3 physical units")

	assert_true(inv1.deposit(&"wood", 8)) # net +5 vs s_after_cancel
	var s_dup := RegionalConservationAudit.capture(get_tree(), w1, &"adv_region", &"wood", inv1)
	var c_dup := RegionalConservationAudit.verify_conservation(s_after_cancel, s_dup)
	assert_false(bool(c_dup["ok"]))
	assert_eq(int(c_dup["discrepancy"]), 5, "Detects duplicated +5 physical units")

	# 6b. Unmanaged orphan GroundResourcePile in scene tree detected as anomaly.
	var orphan := GroundResourcePile.new()
	orphan.set_meta(&"region_id", &"adv_region")
	(dom1["host"] as Node3D).add_child(orphan)
	orphan.configure_initial(999, WOOD_DEF.duplicate(), 4, Vector3(0.0, 0.0, 0.0))
	var s_orphan := RegionalConservationAudit.capture(get_tree(), w1, &"adv_region", &"wood", inv1)
	assert_false(bool(s_orphan["ok"]), "Unmanaged GroundResourcePile detected")
	assert_true((s_orphan["anomalies"] as Array).any(func(a: String) -> bool: return a.begins_with("unmanaged_ground_pile_in_world:")))
	orphan.get_parent().remove_child(orphan)
	orphan.free()

	# 6c. Shared UnitCarryLoad across two units detected as anomaly.
	var unit_dup := UNIT_SCENE.instantiate() as Unit
	unit_dup.definition = LEADER_A_DEF.duplicate() as CharacterDefinition
	unit_dup.definition.character_id = &"adv_clone"
	unit_dup.set_meta(&"region_id", &"adv_region")
	(dom1["host"] as Node3D).add_child(unit_dup)
	unit_dup.set(&"_carry_load", unit1.get_carry_load())
	var s_shared := RegionalConservationAudit.capture(get_tree(), w1, &"adv_region", &"wood", inv1)
	assert_false(bool(s_shared["ok"]), "Shared UnitCarryLoad detected")
	assert_true((s_shared["anomalies"] as Array).any(func(a: String) -> bool: return a.begins_with("shared_carry_load_instance:")))
	unit_dup.get_parent().remove_child(unit_dup)
	unit_dup.free()
