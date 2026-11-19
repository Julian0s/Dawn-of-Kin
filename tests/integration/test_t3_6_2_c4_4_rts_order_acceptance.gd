class_name TestT362C44RtsOrderAcceptance
extends TestCase
## Focused integration suite for T3.6.2-C4.4 (R3):
## - Orders silently ignored by Unit.issue_order() under transactional lock must NEVER be
##   counted as accepted/issued by CommandController across Move, Gather, and Construct paths.
## - Partial group acceptance must count only units that actually accepted the order.
## - Instantaneous synchronous success remains accepted; synchronous failures are rejected.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const WOOD: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE: ResourceDefinition = preload("res://data/resources/stone.tres")
const FOOD: ResourceDefinition = preload("res://data/resources/food.tres")
const SHELTER: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")

var _active_mains: Array[MainScene] = []
var _extra_nodes: Array[Node] = []
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
		"nav": nav,
		"camp": main.get_camp_storage_zone(),
		"manager": main.get_ground_pile_manager(),
		"inventory": main.get_settlement_inventory(),
		"cm": main.get_construction_manager(),
		"sites_root": main.get_construction_sites_root(),
		"sel": main.get_selection_manager(),
		"cmd": main.get_command_controller(),
		"marker": main.get_destination_marker(),
		"leader_a": units_root.get_node("LeaderA") as Unit,
		"leader_b": units_root.get_node("LeaderB") as Unit,
	}


func _attach_signal_spies(cmd: CommandController) -> Dictionary:
	var issued: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	var on_issued := func(pick: PickResult, anchor: Vector3, unit_count: int, all_reachable: bool) -> void:
		issued.append({
			"pick": pick,
			"anchor": anchor,
			"unit_count": unit_count,
			"all_reachable": all_reachable,
		})
	var on_rejected := func(pick: PickResult, reason: String) -> void:
		rejected.append({
			"pick": pick,
			"reason": reason,
		})
	cmd.command_issued.connect(on_issued)
	cmd.command_rejected.connect(on_rejected)
	_connections.append([cmd.command_issued, on_issued])
	_connections.append([cmd.command_rejected, on_rejected])
	return {"issued": issued, "rejected": rejected}


func _spawn_bush(main: MainScene, pos: Vector3, id: StringName) -> ResourceSource:
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.source_id = id
	bush.initial_amount = 8
	main.add_child(bush)
	_extra_nodes.append(bush)
	bush.global_position = pos
	return bush


func test_01_gather_command_rejected_under_real_transactional_lock() -> void:
	var ctx: Dictionary = await _boot_main()
	var main: MainScene = ctx["main"] as MainScene
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var sel: SelectionManager = ctx["sel"] as SelectionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var marker: DestinationMarker = ctx["marker"] as DestinationMarker
	var leader_a: Unit = ctx["leader_a"] as Unit

	var bush: ResourceSource = _spawn_bush(main, Vector3(-2.5, 0.0, -3.5), &"c44_bush_1")
	var spies: Dictionary = _attach_signal_spies(cmd)
	var issued: Array[Dictionary] = spies["issued"] as Array[Dictionary]
	var rejected: Array[Dictionary] = spies["rejected"] as Array[Dictionary]

	# Seed opt-in provenance cargo on LeaderA and give it a prior MoveOrder so we verify it is NOT cancelled.
	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	assert_true(load_a.enable_provenance(&"c44_la_01"))
	assert_true(bool(load_a.add_with_provenance(&"c44_g1", &"c44_l1", &"wood", WOOD.unit_weight, 4, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	leader_a.global_position = camp.global_position
	var prior_order := MoveOrder.new(Vector3(3.0, 0.0, 3.0))
	leader_a.issue_order(prior_order)
	assert_eq(leader_a.get_current_order(), prior_order)

	sel.select_single(leader_a)
	var pick := PickResult.from_resource_source(bush, bush.global_position, Vector3.UP)
	var cmd_results: Array[bool] = []
	var marker_active_during: Array[bool] = []
	var on_load_changed := func() -> void:
		cmd_results.append(cmd.command_at(pick))
		marker_active_during.append(marker.is_marker_active())
	load_a.load_changed.connect(on_load_changed, CONNECT_ONE_SHOT)
	_connections.append([load_a.load_changed, on_load_changed])

	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var del_res: Dictionary = camp_coord.execute_selective_camp_delivery(inv, camp, leader_a, &"default", &"c44_del_1", [])
	assert_true(bool(del_res.get("ok", false)), str(del_res))

	assert_eq(cmd_results.size(), 1, "Callback must have executed once during post-commit signal")
	assert_false(cmd_results[0], "Gather command during transactional lock MUST return false")
	assert_eq(issued.size(), 0, "command_issued must NOT be emitted when order is rejected by lock")
	assert_eq(rejected.size(), 1, "command_rejected must be emitted when all units are rejected")
	assert_eq(String(rejected[0]["reason"]), "unit_transaction_locked")
	assert_eq(cmd.get_last_command_reason(), "unit_transaction_locked")
	assert_false(marker_active_during[0], "DestinationMarker must NOT activate on rejected gather command")
	assert_false(marker.is_marker_active())
	assert_eq(leader_a.get_current_order(), prior_order, "Prior order must NOT be cancelled by rejected command")
	assert_true(prior_order.is_active())
	assert_eq(bush.get_active_worker_count(), 0, "Rejected gather must not reserve source slot")
	assert_eq(inv.get_physical_amount(&"wood"), 4, "Committed delivery preserved")


func test_02_construct_command_rejected_under_real_transactional_lock() -> void:
	var ctx: Dictionary = await _boot_main()
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var manager: GroundPileManager = ctx["manager"] as GroundPileManager
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var marker: DestinationMarker = ctx["marker"] as DestinationMarker
	var leader_a: Unit = ctx["leader_a"] as Unit

	assert_true(inv.deposit(&"wood", 24))
	assert_true(inv.deposit(&"stone", 12))
	var site_a_res: Dictionary = cm.try_create_site_from_placement(SHELTER, Vector3(-6.0, 0.0, 2.0))
	var site_b_res: Dictionary = cm.try_create_site_from_placement(SHELTER, Vector3(6.0, 0.0, 2.0))
	assert_true(bool(site_a_res.get("ok", false)) and bool(site_b_res.get("ok", false)))
	var site_a: ConstructionSite = site_a_res["site"] as ConstructionSite
	var site_b: ConstructionSite = site_b_res["site"] as ConstructionSite

	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	assert_true(load_a.enable_provenance(&"c44_la_02"))
	var order_a := ConstructOrder.new(site_a, camp, 1.45, 0.1, true)
	leader_a.issue_order(order_a)
	assert_eq(leader_a.get_current_order(), order_a)

	var pile: GroundResourcePile = manager.get_piles_for_resource(&"wood")[0]
	var claimed: int = site_a.claim_pickup(leader_a, pile.pile_id, &"wood", 2)
	assert_eq(claimed, 2)
	leader_a.global_position = manager.get_pile_world_position(pile)

	var spies: Dictionary = _attach_signal_spies(cmd)
	var issued: Array[Dictionary] = spies["issued"] as Array[Dictionary]
	var rejected: Array[Dictionary] = spies["rejected"] as Array[Dictionary]
	var cmd_results: Array[bool] = []
	var marker_active_during: Array[bool] = []

	var on_load_changed := func() -> void:
		cmd_results.append(cmd.command_units_to_site(site_b, [leader_a]))
		marker_active_during.append(marker.is_marker_active())
	load_a.load_changed.connect(on_load_changed, CONNECT_ONE_SHOT)
	_connections.append([load_a.load_changed, on_load_changed])

	var w_coord := ReservedWithdrawalCoordinator.new()
	var wd_res: Dictionary = w_coord.execute_reserved_withdrawal(site_a, leader_a, pile.pile_id, &"wood", 2, &"c44_wd_2", &"c44_lot_2")
	assert_true(bool(wd_res.get("ok", false)), str(wd_res))

	assert_eq(cmd_results.size(), 1)
	assert_false(cmd_results[0], "Construct command during transactional lock MUST return false")
	assert_eq(issued.size(), 0, "command_issued must NOT be emitted when construct order is rejected")
	assert_eq(rejected.size(), 1, "command_rejected must be emitted")
	assert_eq(String(rejected[0]["reason"]), "unit_transaction_locked")
	assert_eq(cmd.get_last_command_reason(), "unit_transaction_locked")
	assert_false(marker_active_during[0], "DestinationMarker must NOT activate on rejected construct command")
	assert_eq(leader_a.get_current_order(), order_a, "Original ConstructOrder must remain active")
	assert_eq(site_a.get_transit_claim_for_unit(leader_a), {&"wood": 2}, "Original transit claim preserved")
	assert_eq(site_b.get_assigned_worker_entries().size(), 0, "Target site_b must not receive any worker")


func test_03_move_command_rejected_under_real_transactional_lock() -> void:
	var ctx: Dictionary = await _boot_main()
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var sel: SelectionManager = ctx["sel"] as SelectionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var marker: DestinationMarker = ctx["marker"] as DestinationMarker
	var leader_a: Unit = ctx["leader_a"] as Unit

	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	assert_true(load_a.enable_provenance(&"c44_la_03"))
	assert_true(bool(load_a.add_with_provenance(&"c44_g3", &"c44_l3", &"wood", WOOD.unit_weight, 4, CarryProvenanceLedger.FREE_GATHERED).get("ok", false)))
	leader_a.global_position = camp.global_position
	var prior_order := MoveOrder.new(Vector3(4.0, 0.0, 4.0))
	leader_a.issue_order(prior_order)
	assert_eq(leader_a.get_current_order(), prior_order)

	var spies: Dictionary = _attach_signal_spies(cmd)
	var issued: Array[Dictionary] = spies["issued"] as Array[Dictionary]
	var rejected: Array[Dictionary] = spies["rejected"] as Array[Dictionary]
	sel.select_single(leader_a)
	var move_pick := PickResult.from_ground(Vector3(-4.0, 0.0, 4.0), Vector3.UP)
	var cmd_results: Array[bool] = []
	var marker_active_during: Array[bool] = []

	var on_load_changed := func() -> void:
		cmd_results.append(cmd.command_at(move_pick))
		marker_active_during.append(marker.is_marker_active())
	load_a.load_changed.connect(on_load_changed, CONNECT_ONE_SHOT)
	_connections.append([load_a.load_changed, on_load_changed])

	var camp_coord := SelectiveCampDeliveryCoordinator.new()
	var del_res: Dictionary = camp_coord.execute_selective_camp_delivery(inv, camp, leader_a, &"default", &"c44_del_3", [])
	assert_true(bool(del_res.get("ok", false)), str(del_res))

	assert_eq(cmd_results.size(), 1)
	assert_false(cmd_results[0], "Move command during transactional lock MUST return false")
	assert_eq(issued.size(), 0, "command_issued must NOT be emitted when move order is rejected")
	assert_eq(rejected.size(), 1, "command_rejected must be emitted")
	assert_eq(String(rejected[0]["reason"]), "unit_transaction_locked")
	assert_eq(cmd.get_last_command_reason(), "unit_transaction_locked")
	assert_false(marker_active_during[0], "DestinationMarker must NOT activate on rejected move command")
	assert_eq(leader_a.get_current_order(), prior_order, "Prior order must NOT be cancelled")
	assert_true(prior_order.is_active())
	assert_eq(inv.get_physical_amount(&"wood"), 4)


func test_04_group_partial_acceptance_counts_only_accepting_units_across_all_paths() -> void:
	var ctx: Dictionary = await _boot_main()
	var main: MainScene = ctx["main"] as MainScene
	var camp: CampStorageZone = ctx["camp"] as CampStorageZone
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var sel: SelectionManager = ctx["sel"] as SelectionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var marker: DestinationMarker = ctx["marker"] as DestinationMarker
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site_res: Dictionary = cm.try_create_site_from_placement(SHELTER, Vector3(-6.0, 0.0, 2.0))
	assert_true(bool(site_res.get("ok", false)))
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	var bush: ResourceSource = _spawn_bush(main, Vector3(-2.5, 0.0, -3.5), &"c44_bush_group")

	var load_a: UnitCarryLoad = leader_a.get_carry_load()
	assert_true(load_a.enable_provenance(&"c44_la_04"))
	leader_a.global_position = bush.global_position
	var prior_a := MoveOrder.new(Vector3(3.0, 0.0, 3.0))
	leader_a.issue_order(prior_a)

	sel.set_selection([leader_a, leader_b])
	var spies: Dictionary = _attach_signal_spies(cmd)
	var issued: Array[Dictionary] = spies["issued"] as Array[Dictionary]
	var rejected: Array[Dictionary] = spies["rejected"] as Array[Dictionary]

	var group_results: Array[bool] = []
	var on_load_changed := func() -> void:
		# 1. Group Move
		group_results.append(cmd.command_at(PickResult.from_ground(Vector3(2.0, 0.0, -2.0), Vector3.UP)))
		# 2. Group Gather
		group_results.append(cmd.command_at(PickResult.from_resource_source(bush, bush.global_position, Vector3.UP)))
		# 3. Group Construct
		group_results.append(cmd.command_units_to_site(site, [leader_a, leader_b]))
	load_a.load_changed.connect(on_load_changed, CONNECT_ONE_SHOT)
	_connections.append([load_a.load_changed, on_load_changed])

	var gather_tx_res: Dictionary = bush.transfer_to_carry_load_with_provenance(load_a, &"c44_g_op4", &"c44_g_lot4", 2)
	assert_true(bool(gather_tx_res.get("ok", false)), str(gather_tx_res))

	assert_eq(group_results, [true, true, true], "Partial group acceptance must succeed for the unlocked unit")
	assert_eq(rejected.size(), 0, "Partial acceptance must not emit command_rejected")
	assert_eq(issued.size(), 3)
	for ev: Dictionary in issued:
		assert_eq(int(ev["unit_count"]), 1, "Only the 1 unlocked unit (LeaderB) must be counted: %s" % str(ev))
	assert_true(marker.is_marker_active(), "Marker must show when at least 1 unit accepted")
	assert_eq(leader_a.get_current_order(), prior_a, "Locked LeaderA must keep its prior order untouched")
	assert_true(leader_b.get_current_order() is ConstructOrder, "Unlocked LeaderB must have received the final ConstructOrder")
	assert_eq(site.get_assigned_worker_entries().size(), 1, "Only LeaderB must be registered at site")


func test_05_instant_success_sync_failure_and_unlocked_replacement() -> void:
	var ctx: Dictionary = await _boot_main()
	var inv: SettlementInventory = ctx["inventory"] as SettlementInventory
	var cm: ConstructionManager = ctx["cm"] as ConstructionManager
	var sel: SelectionManager = ctx["sel"] as SelectionManager
	var cmd: CommandController = ctx["cmd"] as CommandController
	var marker: DestinationMarker = ctx["marker"] as DestinationMarker
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var spies: Dictionary = _attach_signal_spies(cmd)
	var issued: Array[Dictionary] = spies["issued"] as Array[Dictionary]
	var rejected: Array[Dictionary] = spies["rejected"] as Array[Dictionary]

	# 1. Instantaneous synchronous success: MoveOrder to unit's exact current position
	sel.select_single(leader_a)
	var instant_pick := PickResult.from_ground(leader_a.global_position, Vector3.UP)
	assert_true(cmd.command_at(instant_pick), "Instantaneous MoveOrder at current position must succeed")
	assert_eq(issued.size(), 1)
	assert_eq(int(issued[0]["unit_count"]), 1)
	assert_eq(rejected.size(), 0)
	assert_null(leader_a.get_current_order(), "Instantaneous order finishes immediately")

	# 2. Synchronous failure: ConstructOrder when site is already full/no worker slot (or invalid provenance)
	assert_true(inv.deposit(&"wood", 12))
	assert_true(inv.deposit(&"stone", 6))
	var site_res: Dictionary = cm.try_create_site_from_placement(SHELTER, Vector3(-6.0, 0.0, 2.0))
	assert_true(bool(site_res.get("ok", false)))
	var site: ConstructionSite = site_res["site"] as ConstructionSite
	# Enable provenance on LeaderB so legacy ConstructOrder fails synchronously with provenance_opt_in_required
	assert_true(leader_b.get_carry_load().enable_provenance(&"c44_lb_sync_fail"))
	marker.hide_marker() if marker.has_method("hide_marker") else null
	var issued_before: int = issued.size()
	assert_false(cmd.command_units_to_site(site, [leader_b]), "Synchronous order failure must return false")
	assert_eq(issued.size(), issued_before, "Synchronous failure must NOT emit command_issued")
	assert_eq(rejected.size(), 1)
	assert_eq(String(rejected[0]["reason"]), ConstructOrder.REASON_PROVENANCE_OPT_IN_REQUIRED)
	assert_eq(cmd.get_last_command_reason(), ConstructOrder.REASON_PROVENANCE_OPT_IN_REQUIRED)

	# 3. Normal unlocked order replacement still works cleanly
	var first_move := PickResult.from_ground(Vector3(3.0, 0.0, 3.0), Vector3.UP)
	var second_move := PickResult.from_ground(Vector3(-3.0, 0.0, 3.0), Vector3.UP)
	assert_true(cmd.command_at(first_move))
	var order_1: UnitOrder = leader_a.get_current_order()
	assert_not_null(order_1)
	assert_true(cmd.command_at(second_move))
	var order_2: UnitOrder = leader_a.get_current_order()
	assert_not_null(order_2)
	assert_ne(order_1, order_2)
	assert_eq(order_1.status, UnitOrder.Status.CANCELLED)
	assert_eq(order_1.failure_reason, UnitOrder.REASON_REPLACED)
	assert_true(order_2.is_active())
