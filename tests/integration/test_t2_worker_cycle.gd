extends TestCase
## Integration tests for T2.3 Worker Cycle in real navigation + physics + RVO scenes:
## - Full cycle: click ResourceSource -> MOVING -> WORKING -> TRANSPORTING (100% / <100% if +1 doesn't fit) -> delivery -> repeat
## - Conservation & zero premature inventory credit before arrival at camp
## - Depletion mid-gather auto-returns partial cargo
## - Concurrent workers (normal RVO gather+deliver, competing for last unit, max_simultaneous_workers cap)
## - Approach clearance outside SolidBody geometry (solid_radius + agent_radius)
## - Cancel/MoveOrder replacement preserving CarryLoad without loss
## - Edge failures (depleted source, unreachable source/camp, low capacity, overloaded load, rejected delivery).

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const ROCK_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const BUSH_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")
const FOOD_RES: ResourceDefinition = preload("res://data/resources/food.tres")
const WOOD_RES: ResourceDefinition = preload("res://data/resources/wood.tres")
const STONE_RES: ResourceDefinition = preload("res://data/resources/stone.tres")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")

const MAX_WAIT_FRAMES: int = 120
const MAX_CYCLE_FRAMES: int = 1200

var _managers_to_cleanup: Array[GroundPileManager] = []


func _accelerate_work_walk(units: Array) -> void:
	for u: Variant in units:
		if u is Unit:
			var unit_node: Unit = u as Unit
			var fast_def: CharacterDefinition = unit_node.get_definition().duplicate() as CharacterDefinition
			fast_def.work_approach_speed = 4.8
			fast_def.max_load_speed_multiplier = 1.0
			unit_node.apply_definition(fast_def)


func after_each() -> void:
	_release_all_inputs()
	for manager: GroundPileManager in _managers_to_cleanup:
		if manager != null:
			manager.cleanup()
	_managers_to_cleanup.clear()


func _release_all_inputs() -> void:
	for btn: MouseButton in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if Input.is_mouse_button_pressed(btn):
			var ev := InputEventMouseButton.new()
			ev.button_index = btn
			ev.pressed = false
			get_viewport().push_input(ev, true)


func _spawn_economy_world(camp_pos: Vector3 = Vector3(-4.0, 0.0, 4.0)) -> Dictionary:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	add_test_child(main_root)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	if nav != null:
		var frames: int = 0
		while not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
			await wait_physics_frames(1)
			frames += 1

	await wait_process_frames(2)
	await wait_physics_frames(2)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var camp_zone := CampStorageZone.new()
	camp_zone.zone_id = &"camp_t23_test"
	camp_zone.position = camp_pos
	camp_zone.zone_bounds_half_extents = Vector2(3.6, 3.6)
	camp_zone.slot_spacing = 1.2
	camp_zone.set_world_navigation(nav)
	test_map.add_child(camp_zone)

	var piles_root := Node3D.new()
	piles_root.name = "T23PilesRoot"
	test_map.add_child(piles_root)

	var defs: Dictionary = {
		&"food": FOOD_RES.duplicate(),
		&"wood": WOOD_RES.duplicate(),
		&"stone": STONE_RES.duplicate(),
	}
	var time_provider := SimulatedWorldTimeProvider.new(0.0)
	var manager := GroundPileManager.new(defs, camp_zone, piles_root, time_provider)
	_managers_to_cleanup.append(manager)

	var inventory := SettlementInventory.new(manager)
	var cmd: CommandController = main_root.get_command_controller()
	cmd.configure_economy(inventory, camp_zone)

	var leader_a: Unit = null
	var leader_b: Unit = null
	for u: Unit in main_root.get_units():
		if u.get_character_id() == &"leader_a":
			leader_a = u
		elif u.get_character_id() == &"leader_b":
			leader_b = u

	return {
		"main": main_root,
		"test_map": test_map,
		"nav": nav,
		"rig": rig,
		"camera": rig.get_camera() if rig != null else null,
		"selection": main_root.get_selection_manager(),
		"command_controller": cmd,
		"controller": main_root.get_input_controller(),
		"camp_zone": camp_zone,
		"manager": manager,
		"inventory": inventory,
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _rebake_test_map(_test_map: TestMap, nav: WorldNavigation) -> void:
	nav.request_rebake()
	var frames: int = 0
	while not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	await wait_physics_frames(2)


func _simulate_right_click(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	get_viewport().push_input(motion, true)
	await wait_process_frames(1)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.position = screen_pos
	press.global_position = screen_pos
	press.pressed = true
	get_viewport().push_input(press, true)
	await wait_process_frames(1)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.position = screen_pos
	release.global_position = screen_pos
	release.pressed = false
	get_viewport().push_input(release, true)


func _reject_all_positions(_pos: Vector3) -> bool:
	return false


func test_01_full_wood_cycle_right_click_states_and_exact_conservation() -> void:
	var ctx: Dictionary = await _spawn_economy_world(Vector3(-4.0, 0.0, 2.0))
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var manager: GroundPileManager = ctx["manager"] as GroundPileManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	_accelerate_work_walk([leader_a])
	var manager_source_total: int = 12 # 10 units on trip 1 (20/20 = 100%) + 2 remaining on trip 2

	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	tree.position = Vector3(2.0, 0.0, 2.0)
	tree.initial_amount = manager_source_total
	tree.max_extract_per_operation = 2
	tree.set_gather_cycle_timings(0.15, 0.0)
	test_map.add_child(tree)
	await wait_physics_frames(2)
	await _rebake_test_map(test_map, nav)

	leader_a.global_position = Vector3(-1.5, 0.0, 2.0)
	selection.select_single(leader_a)
	await wait_physics_frames(2)

	var state_history: Array[Unit.State] = []
	leader_a.state_changed.connect(func(new_s: Unit.State, _old_s: Unit.State) -> void:
		state_history.append(new_s)
	)

	rig.set_focus_position(Vector2(tree.global_position.x, tree.global_position.z))
	await wait_process_frames(1)
	var tree_screen: Vector2 = cam.unproject_position(tree.global_position + Vector3(0.0, 1.4, 0.0))
	await _simulate_right_click(tree_screen)

	assert_eq(cmd.get_last_command_reason(), "")
	assert_true(leader_a.get_current_order() is GatherResourceOrder)

	var seen_working: bool = false
	var seen_transporting: bool = false
	var verified_zero_inv_while_carrying: bool = false
	var verified_first_delivery: bool = false
	var frames: int = 0

	while frames < MAX_CYCLE_FRAMES and leader_a.get_state() != Unit.State.IDLE:
		await wait_physics_frames(1)
		frames += 1
		var st: Unit.State = leader_a.get_state()
		if st == Unit.State.WORKING:
			seen_working = true
		if st == Unit.State.TRANSPORTING:
			seen_transporting = true
			if not verified_first_delivery and leader_a.get_carry_load().get_amount(&"wood") > 0:
				assert_eq(inventory.get_amount(&"wood"), 0, "Inventory must NOT be credited before arriving at camp")
				verified_zero_inv_while_carrying = true
		if not verified_first_delivery and inventory.get_amount(&"wood") == 10:
			verified_first_delivery = true
			assert_eq(leader_a.get_carry_load().get_amount(&"wood"), 0)

		var total_conserved: int = tree.get_remaining_amount() + leader_a.get_carry_load().get_amount(&"wood") + inventory.get_amount(&"wood")
		assert_eq(total_conserved, manager_source_total, "Total wood must remain strictly conserved every frame")

	assert_true(seen_working, "Must enter Unit.State.WORKING at source")
	assert_true(seen_transporting, "Must enter Unit.State.TRANSPORTING back to camp")
	assert_true(verified_zero_inv_while_carrying)
	assert_true(verified_first_delivery, "Must auto-return at 100% (10 wood) and deposit on trip 1")
	assert_eq(leader_a.get_state(), Unit.State.IDLE, "Must finish IDLE when source depletes")
	assert_true(tree.is_depleted())
	assert_eq(inventory.get_amount(&"wood"), manager_source_total)
	assert_true(leader_a.get_carry_load().is_empty())
	assert_eq(tree.get_active_worker_count(), 0)
	assert_gt(manager.get_piles().size(), 0, "Camp piles must materialize delivered stock")
	assert_true(camp_zone.is_position_in_bounds(manager.get_piles()[0].global_position))
	assert_true(state_history.has(Unit.State.WORKING))
	assert_true(state_history.has(Unit.State.TRANSPORTING))


func test_02_stone_non_divisible_capacity_returns_at_90_percent_and_loops() -> void:
	var ctx: Dictionary = await _spawn_economy_world(Vector3(-3.0, 0.0, 2.0))
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	_accelerate_work_walk([leader_a])

	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	rock.position = Vector3(2.0, 0.0, 2.0)
	rock.initial_amount = 8 # trip 1 takes 6 (18/20=90%, remaining cap=2 < stone weight 3); trip 2 takes remaining 2
	rock.max_extract_per_operation = 1
	test_map.add_child(rock)
	await wait_physics_frames(2)
	await _rebake_test_map(test_map, nav)

	(ctx["leader_b"] as Unit).global_position = Vector3(12.0, 0.0, 2.0)
	leader_a.global_position = Vector3(0.0, 0.0, 2.0)
	var order := GatherResourceOrder.new(rock, camp_zone, inventory, 0.05)
	leader_a.issue_order(order)

	var max_first_load: int = 0
	var returned_at_90_percent: bool = false
	var frames: int = 0

	while frames < MAX_CYCLE_FRAMES and leader_a.get_state() != Unit.State.IDLE:
		await wait_physics_frames(1)
		frames += 1
		var carried_stone: int = leader_a.get_carry_load().get_amount(&"stone")
		if carried_stone > max_first_load:
			max_first_load = carried_stone
		if leader_a.get_state() == Unit.State.TRANSPORTING and inventory.get_amount(&"stone") == 0 and carried_stone == 6:
			assert_near(leader_a.get_carry_load().get_fill_percentage(), 90.0, 0.01)
			assert_false(leader_a.get_carry_load().can_fit_one(STONE_RES))
			returned_at_90_percent = true

	assert_eq(max_first_load, 6, "Must never overload beyond 6 stone (weight 18/20)")
	assert_true(returned_at_90_percent, "Must auto-return at 90% when +1 unit weight (3) exceeds remaining 2")
	assert_true(order.is_succeeded(), "Expected stone gather to succeed, failure_reason=%s, unit_pos=%s, target=%s, leader_b=%s" % [order.failure_reason, str(leader_a.global_position), str(order.resolved_target), str(ctx["leader_b"].global_position)])
	assert_eq(order.get_delivered_trips(), 2)
	assert_eq(inventory.get_amount(&"stone"), 8)
	assert_true(rock.is_depleted())


func test_03_solid_obstacle_approach_clearance_and_two_concurrent_workers_no_deadlock() -> void:
	var ctx: Dictionary = await _spawn_economy_world(Vector3(-4.0, 0.0, 4.0))
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	_accelerate_work_walk([leader_a, leader_b])

	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	rock.position = Vector3(3.0, 0.0, 4.0)
	rock.initial_amount = 14 # two workers gather & deliver concurrently across 2+ trips cleanly
	rock.max_extract_per_operation = 2
	rock.max_simultaneous_workers = 2
	rock.set_gather_cycle_timings(0.15, 0.0)
	test_map.add_child(rock)
	await wait_physics_frames(2)
	await _rebake_test_map(test_map, nav)

	leader_a.global_position = Vector3(1.0, 0.0, 2.5)
	leader_b.global_position = Vector3(1.0, 0.0, 5.5)
	selection.set_selection([leader_a, leader_b])

	var solid_min: float = rock.get_solid_radius() + WorldNavigation.DEFAULT_AGENT_RADIUS
	var pick := PickResult.new()
	pick.kind = PickResult.Kind.RESOURCE_SOURCE
	pick.resource_source = rock
	pick.position = rock.global_position

	assert_true(cmd.command_at(pick))
	assert_eq(rock.get_active_worker_count(), 2)

	var order_a: GatherResourceOrder = leader_a.get_current_order() as GatherResourceOrder
	var order_b: GatherResourceOrder = leader_b.get_current_order() as GatherResourceOrder
	assert_not_null(order_a)
	assert_not_null(order_b)
	assert_true(Vector2(order_a.resolved_target.x - rock.global_position.x, order_a.resolved_target.z - rock.global_position.z).length() >= solid_min)
	assert_true(Vector2(order_b.resolved_target.x - rock.global_position.x, order_b.resolved_target.z - rock.global_position.z).length() >= solid_min)

	var checked_working_clearance: bool = false
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES and (leader_a.get_state() != Unit.State.IDLE or leader_b.get_state() != Unit.State.IDLE):
		await wait_physics_frames(1)
		frames += 1
		for w: Unit in [leader_a, leader_b]:
			if w.get_state() == Unit.State.WORKING:
				var d: float = Vector2(w.global_position.x - rock.global_position.x, w.global_position.z - rock.global_position.z).length()
				assert_true(d >= solid_min - 0.06, "Working unit must stay outside rock solid + agent radius (d=%.3f)" % d)
				assert_true(d <= rock.get_interaction_radius() + 0.08, "Working unit must be inside interaction radius (d=%.3f > %.3f, pos=%s, target=%s)" % [d, rock.get_interaction_radius() + 0.08, str(w.global_position), str((w.get_current_order() as GatherResourceOrder).resolved_target)])
				checked_working_clearance = true

	assert_true(checked_working_clearance)
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(leader_b.get_state(), Unit.State.IDLE)
	assert_true(rock.is_depleted(), "remaining=%d a_status=%d a_reason=%s a_carry=%d b_status=%d b_reason=%s b_carry=%d" % [
		rock.get_remaining_amount(),
		int(order_a.status),
		order_a.failure_reason,
		leader_a.get_carry_load().get_amount(&"stone"),
		int(order_b.status),
		order_b.failure_reason,
		leader_b.get_carry_load().get_amount(&"stone"),
	])
	assert_eq(inventory.get_amount(&"stone"), 14, "Concurrent gather+deliver must conserve all 14 units without deadlock")
	assert_eq(rock.get_active_worker_count(), 0)


func test_04_two_workers_competing_for_last_unit_and_max_worker_cap() -> void:
	var ctx: Dictionary = await _spawn_economy_world(Vector3(-4.0, 0.0, 2.0))
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.position = Vector3(1.0, 0.0, 2.0)
	bush.initial_amount = 1
	bush.max_extract_per_operation = 1
	bush.max_simultaneous_workers = 2
	test_map.add_child(bush)
	await wait_physics_frames(2)

	# Part 1: Race for single remaining unit
	leader_a.global_position = Vector3(0.0, 0.0, 2.0)
	leader_b.global_position = Vector3(2.0, 0.0, 2.0)
	var order_a := GatherResourceOrder.new(bush, camp_zone, inventory, 0.05)
	var order_b := GatherResourceOrder.new(bush, camp_zone, inventory, 0.05)
	leader_a.issue_order(order_a)
	leader_b.issue_order(order_b)

	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES and (leader_a.get_state() != Unit.State.IDLE or leader_b.get_state() != Unit.State.IDLE):
		await wait_physics_frames(1)
		frames += 1

	assert_eq(inventory.get_amount(&"food"), 1, "Only 1 unit may ever enter camp storage")
	assert_true(leader_a.get_carry_load().is_empty())
	assert_true(leader_b.get_carry_load().is_empty())
	assert_true(bush.is_depleted())
	assert_eq(bush.get_active_worker_count(), 0)
	var succeeded_count: int = int(order_a.is_succeeded()) + int(order_b.is_succeeded())
	assert_eq(succeeded_count, 1, "Exactly the worker who got the last unit succeeds; loser closes cleanly")

	# Part 2: max_simultaneous_workers cap rejects 3rd unit without dropping 3rd unit's active MoveOrder
	var full_bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	full_bush.position = Vector3(6.0, 0.0, 2.0)
	full_bush.initial_amount = 10
	full_bush.max_simultaneous_workers = 2
	test_map.add_child(full_bush)

	var unit_c: Unit = UNIT_SCENE.instantiate() as Unit
	unit_c.definition = LEADER_A_DEF
	unit_c.position = Vector3(4.0, 0.0, 6.0)
	main_root_add_unit(ctx["main"] as MainScene, unit_c, nav)
	await wait_physics_frames(2)

	leader_a.global_position = Vector3(5.0, 0.0, 1.0)
	leader_b.global_position = Vector3(5.0, 0.0, 3.0)
	leader_a.issue_order(GatherResourceOrder.new(full_bush, camp_zone, inventory, 0.2))
	leader_b.issue_order(GatherResourceOrder.new(full_bush, camp_zone, inventory, 0.2))
	assert_eq(full_bush.get_active_worker_count(), 2)

	var move_c := MoveOrder.new(Vector3(6.0, 0.0, 6.0))
	unit_c.issue_order(move_c)
	selection.select_single(unit_c)
	var pick := PickResult.new()
	pick.kind = PickResult.Kind.RESOURCE_SOURCE
	pick.resource_source = full_bush
	pick.position = full_bush.global_position
	assert_false(cmd.command_at(pick))
	assert_eq(cmd.get_last_command_reason(), GatherResourceOrder.REASON_NO_WORKER_SLOT)
	assert_eq(unit_c.get_current_order(), move_c, "Rejected 3rd unit must keep its existing MoveOrder")


func main_root_add_unit(main_root: MainScene, unit: Unit, nav: WorldNavigation) -> void:
	var units_node: Node3D = main_root.get_node_or_null("Units") as Node3D
	units_node.add_child(unit)
	unit.set_world_navigation(nav)


func test_05_cancel_or_move_replacement_preserves_carry_load_and_allows_subsequent_delivery() -> void:
	var ctx: Dictionary = await _spawn_economy_world(Vector3(-4.0, 0.0, 2.0))
	var test_map: TestMap = ctx["test_map"] as TestMap
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit

	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.position = Vector3(5.0, 0.0, 2.0)
	bush.initial_amount = 4
	bush.max_extract_per_operation = 4
	test_map.add_child(bush)
	await wait_physics_frames(2)

	(ctx["leader_b"] as Unit).global_position = Vector3(12.0, 0.0, 2.0)
	leader_a.global_position = Vector3(4.1, 0.0, 2.0)
	leader_a.issue_order(GatherResourceOrder.new(bush, camp_zone, inventory, 0.05))

	# Wait until unit switches into TRANSPORTING with all 4 food carried
	var frames: int = 0
	while frames < 60 and leader_a.get_state() != Unit.State.TRANSPORTING:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(leader_a.get_state(), Unit.State.TRANSPORTING)
	assert_eq(leader_a.get_carry_load().get_amount(&"food"), 4)
	assert_eq(inventory.get_amount(&"food"), 0)

	# Interrupt by replacing with MoveOrder -> carry load MUST stay intact, inventory MUST stay 0, slot released
	leader_a.issue_order(MoveOrder.new(Vector3(3.0, 0.0, 6.0)))
	await wait_physics_frames(3)
	assert_eq(leader_a.get_carry_load().get_amount(&"food"), 4)
	assert_eq(inventory.get_amount(&"food"), 0)
	assert_eq(bush.get_active_worker_count(), 0)

	# Delivering later deposits exact preserved cargo
	var deliver := DeliverToCampOrder.new(camp_zone, inventory)
	leader_a.issue_order(deliver)
	frames = 0
	while frames < MAX_CYCLE_FRAMES and leader_a.get_state() != Unit.State.IDLE:
		await wait_physics_frames(1)
		frames += 1

	assert_true(deliver.is_succeeded(), "Expected standalone delivery to succeed, state=%s, failure_reason=%s, unit_pos=%s, target=%s" % [leader_a.get_state_name(), deliver.failure_reason, str(leader_a.global_position), str(deliver.resolved_target)])
	assert_true(leader_a.get_carry_load().is_empty())
	assert_eq(inventory.get_amount(&"food"), 4)


func test_06_edge_failures_unreachable_low_capacity_overloaded_and_rejected_delivery() -> void:
	var ctx: Dictionary = await _spawn_economy_world(Vector3(-4.0, 0.0, 2.0))
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var manager: GroundPileManager = ctx["manager"] as GroundPileManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit

	# 1. Depleted source right-click fails cleanly & leaves unit idle
	var empty_bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	empty_bush.position = Vector3(2.0, 0.0, 2.0)
	empty_bush.initial_amount = 1
	test_map.add_child(empty_bush)
	await wait_physics_frames(2)
	assert_eq(empty_bush.extract(1), 1)

	selection.select_single(leader_a)
	var dep_pick := PickResult.new()
	dep_pick.kind = PickResult.Kind.RESOURCE_SOURCE
	dep_pick.resource_source = empty_bush
	dep_pick.position = empty_bush.global_position
	assert_false(cmd.command_at(dep_pick))
	assert_eq(cmd.get_last_command_reason(), "resource_source_depleted")
	assert_eq(leader_a.get_state(), Unit.State.IDLE)

	# 2. Unreachable source inside TestMap's closed enclosure (-16, 0, 12)
	var enclosed_bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	enclosed_bush.position = Vector3(-16.0, 0.0, 12.0)
	enclosed_bush.initial_amount = 5
	test_map.add_child(enclosed_bush)
	await wait_physics_frames(2)

	var unreach_order := GatherResourceOrder.new(enclosed_bush, camp_zone, inventory)
	leader_a.issue_order(unreach_order)
	assert_true(unreach_order.is_finished())
	assert_eq(unreach_order.failure_reason, GatherResourceOrder.REASON_SOURCE_UNREACHABLE)
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(enclosed_bush.get_active_worker_count(), 0)

	# 3. Capacity smaller than unit_weight (cap 1 < stone weight 3)
	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	rock.position = Vector3(2.0, 0.0, -2.0)
	rock.initial_amount = 5
	test_map.add_child(rock)
	await wait_physics_frames(2)
	await _rebake_test_map(test_map, nav)

	var tiny_def: CharacterDefinition = LEADER_A_DEF.duplicate() as CharacterDefinition
	tiny_def.base_carry_capacity = 1
	leader_a.apply_definition(tiny_def)
	var low_cap_order := GatherResourceOrder.new(rock, camp_zone, inventory)
	leader_a.issue_order(low_cap_order)
	assert_true(low_cap_order.is_finished())
	assert_eq(low_cap_order.failure_reason, GatherResourceOrder.REASON_INSUFFICIENT_CARRY_CAPACITY)
	assert_eq(rock.get_remaining_amount(), 5)
	assert_eq(rock.get_active_worker_count(), 0)

	# 4. Overloaded existing load: auto-delivers pre-existing load FIRST without loss, then fails on impossible stone cap
	leader_a.apply_definition(LEADER_A_DEF)
	assert_true(leader_a.get_carry_load().add_units(FOOD_RES, 3))
	leader_a.apply_definition(tiny_def)
	assert_true(leader_a.get_carry_load().is_overloaded())
	var overload_order := GatherResourceOrder.new(rock, camp_zone, inventory, 0.05)
	leader_a.issue_order(overload_order)
	assert_eq(leader_a.get_state(), Unit.State.TRANSPORTING)

	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES and leader_a.get_state() != Unit.State.IDLE:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(inventory.get_amount(&"food"), 3, "Overloaded cargo must be delivered safely without loss (pos=%s, target=%s, phase=%s)" % [str(leader_a.global_position), str(overload_order.resolved_target), str(overload_order.get_phase())])
	assert_true(leader_a.get_carry_load().is_empty())
	assert_eq(overload_order.failure_reason, GatherResourceOrder.REASON_INSUFFICIENT_CARRY_CAPACITY)

	# 5. Camp unreachable fails DeliverToCampOrder cleanly keeping carry load intact
	leader_a.apply_definition(LEADER_A_DEF)
	assert_true(leader_a.get_carry_load().add_units(WOOD_RES, 3))
	var original_camp_pos: Vector3 = camp_zone.position
	camp_zone.position = Vector3(-16.0, 0.0, 12.0) # closed enclosure
	var blocked_deliver := DeliverToCampOrder.new(camp_zone, inventory)
	leader_a.issue_order(blocked_deliver)
	assert_true(blocked_deliver.is_finished())
	assert_eq(blocked_deliver.failure_reason, DeliverToCampOrder.REASON_CAMP_UNREACHABLE)
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), 3, "Carry load must persist on unreachable camp")
	camp_zone.position = original_camp_pos

	# 6. Storage rejecting deposit (e.g. validator refuses new pile spot) preserves carry load completely
	assert_eq(manager.get_piles().size(), 1)
	camp_zone.set_custom_position_validator(Callable(self, "_reject_all_positions"))
	var locked_deliver := DeliverToCampOrder.new(camp_zone, inventory)
	leader_a.global_position = original_camp_pos
	leader_a.issue_order(locked_deliver)
	frames = 0
	while frames < MAX_CYCLE_FRAMES and leader_a.get_state() != Unit.State.IDLE:
		await wait_physics_frames(1)
		frames += 1
	assert_true(locked_deliver.is_finished())
	assert_eq(locked_deliver.failure_reason, DeliverToCampOrder.REASON_DELIVERY_REJECTED)
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), 3, "Rejected delivery must preserve 100% of carry load")
	assert_eq(inventory.get_amount(&"wood"), 0)
	assert_eq(inventory.get_amount(&"food"), 3)


func test_07_transport_releases_slot_for_third_worker_and_handles_full_return_without_loss() -> void:
	# Scenarios A, B, C, D, F under real physics, navigation, and RVO.
	var ctx: Dictionary = await _spawn_economy_world(Vector3(-3.0, 0.0, 2.0))
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var unit_c: Unit = UNIT_SCENE.instantiate() as Unit
	unit_c.definition = LEADER_A_DEF
	unit_c.position = Vector3(2.0, 0.0, 5.2)
	main_root_add_unit(main_root, unit_c, nav)
	_accelerate_work_walk([leader_a, leader_b, unit_c])

	var initial_total: int = 18
	var rock: ResourceSource = ROCK_SCENE.instantiate() as ResourceSource
	rock.position = Vector3(2.5, 0.0, 2.0)
	rock.initial_amount = initial_total
	rock.max_extract_per_operation = 1
	rock.max_simultaneous_workers = 2
	test_map.add_child(rock)
	await wait_physics_frames(2)
	await _rebake_test_map(test_map, nav)

	# Scenario A: 2 workers occupy all 2 slots; 3rd worker is rejected cleanly.
	leader_a.global_position = Vector3(1.0, 0.0, 2.0)
	leader_b.global_position = Vector3(4.0, 0.0, 2.0)
	var order_a := GatherResourceOrder.new(rock, camp_zone, inventory, 0.05)
	var order_b := GatherResourceOrder.new(rock, camp_zone, inventory, 0.35)
	leader_a.issue_order(order_a)
	leader_b.issue_order(order_b)

	assert_eq(rock.get_active_worker_count(), 2)
	assert_true(rock.is_worker_reserved(leader_a))
	assert_true(rock.is_worker_reserved(leader_b))
	assert_true(order_a.has_reservation())
	assert_true(order_b.has_reservation())

	selection.select_single(unit_c)
	var pick := PickResult.new()
	pick.kind = PickResult.Kind.RESOURCE_SOURCE
	pick.resource_source = rock
	pick.position = rock.global_position
	assert_false(cmd.command_at(pick), "Scenario A: 3rd worker must be rejected while 2 slots are occupied")
	assert_eq(cmd.get_last_command_reason(), GatherResourceOrder.REASON_NO_WORKER_SLOT)

	# Scenario B: once leader_a finishes gathering 6 stone and switches to TRANSPORTING, its slot is freed.
	var frames: int = 0
	while frames < 300 and leader_a.get_state() != Unit.State.TRANSPORTING:
		await wait_physics_frames(1)
		frames += 1
		assert_true(rock.get_active_worker_count() <= 2)

	assert_eq(leader_a.get_state(), Unit.State.TRANSPORTING, "leader_a should begin transport back to camp")
	assert_false(order_a.has_reservation(), "Scenario B: reservation must be released when entering delivery")
	assert_false(rock.is_worker_reserved(leader_a))
	assert_eq(rock.get_active_worker_count(), 1, "Scenario B: active worker count must drop from 2 to 1")
	assert_true(rock.has_worker_slot(unit_c))

	# Scenario C: 3rd worker takes the freed slot and gathers without duplicating resources.
	assert_true(cmd.command_at(pick), "Scenario C: 3rd worker must take freed slot while leader_a transports")
	assert_true(unit_c.get_current_order() is GatherResourceOrder)
	var order_c: GatherResourceOrder = unit_c.get_current_order() as GatherResourceOrder
	assert_true(order_c.has_reservation())
	assert_true(rock.is_worker_reserved(unit_c))
	assert_eq(rock.get_active_worker_count(), 2)

	# Scenario D & F: leader_a finishes delivering at camp while leader_b & unit_c occupy both slots.
	# Wait for order_a to complete delivery and finish cleanly, keeping exact global conservation.
	var saw_a_return_blocked: bool = false
	frames = 0
	while frames < MAX_CYCLE_FRAMES and (leader_a.get_state() != Unit.State.IDLE or leader_b.get_state() != Unit.State.IDLE or unit_c.get_state() != Unit.State.IDLE):
		await wait_physics_frames(1)
		frames += 1
		assert_true(rock.get_active_worker_count() <= 2, "Never exceed max_simultaneous_workers at any frame")
		var sum_stone: int = (
			rock.get_remaining_amount()
			+ leader_a.get_carry_load().get_amount(&"stone")
			+ leader_b.get_carry_load().get_amount(&"stone")
			+ unit_c.get_carry_load().get_amount(&"stone")
			+ inventory.get_amount(&"stone")
		)
		assert_eq(sum_stone, initial_total, "Scenario F: exact conservation must hold every frame")
		if not saw_a_return_blocked and order_a.is_finished():
			saw_a_return_blocked = true
			assert_eq(int(order_a.status), int(UnitOrder.Status.FAILED), "Scenario D: returning with full slots should finish explicitly without infinite retry")
			assert_eq(order_a.failure_reason, GatherResourceOrder.REASON_NO_WORKER_SLOT)
			assert_eq(order_a.get_delivered_trips(), 1)
			assert_eq(leader_a.get_state(), Unit.State.IDLE)
			assert_true(leader_a.get_carry_load().is_empty())

	assert_true(saw_a_return_blocked, "leader_a should have terminated cleanly after finding no free slot on return")
	assert_true(rock.is_depleted())
	assert_eq(rock.get_active_worker_count(), 0)
	assert_eq(inventory.get_amount(&"stone"), initial_total, "All 18 stone conserved cleanly across 3 workers")
	assert_true(leader_a.get_carry_load().is_empty())
	assert_true(leader_b.get_carry_load().is_empty())
	assert_true(unit_c.get_carry_load().is_empty())


func test_08_slot_concurrency_preexisting_load_mid_transport_depletion_and_lifecycle_edges() -> void:
	# Scenarios E & F + S4 edge cases: concurrent race for 1 freed slot, pre-existing full load,
	# source depleted during transport, cancel in all phases, and tree exit (remove_child).
	var ctx: Dictionary = await _spawn_economy_world(Vector3(-3.5, 0.0, 2.0))
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var unit_c: Unit = UNIT_SCENE.instantiate() as Unit
	unit_c.definition = LEADER_A_DEF
	unit_c.position = Vector3(1.5, 0.0, 5.0)
	main_root_add_unit(main_root, unit_c, nav)
	_accelerate_work_walk([leader_a, leader_b, unit_c])

	# Part 1 (Scenario E + F): Single-slot tree; leader_a carries full pre-existing wood (10)
	# -> delivers first WITHOUT locking the tree slot, letting leader_b gather right away!
	var tree_initial: int = 10
	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	tree.position = Vector3(2.5, 0.0, 2.0)
	tree.initial_amount = tree_initial
	tree.max_extract_per_operation = 2
	tree.max_simultaneous_workers = 1
	test_map.add_child(tree)
	await wait_physics_frames(2)
	await _rebake_test_map(test_map, nav)

	assert_true(leader_a.get_carry_load().add_units(WOOD_RES, 10))
	leader_a.global_position = Vector3(1.0, 0.0, 2.0)
	var pre_order := GatherResourceOrder.new(tree, camp_zone, inventory, 0.15)
	leader_a.issue_order(pre_order)
	assert_eq(leader_a.get_state(), Unit.State.TRANSPORTING)
	assert_false(pre_order.has_reservation(), "Pre-existing cargo delivery must not hold source slot while transporting")
	assert_eq(tree.get_active_worker_count(), 0)

	# Scenario E: leader_b and unit_c simultaneously right-click the 1-slot tree -> strictly 1 wins!
	leader_b.global_position = Vector3(1.5, 0.0, 0.2)
	unit_c.global_position = Vector3(3.5, 0.0, 3.8)
	selection.set_selection([leader_b, unit_c])
	var tree_pick := PickResult.new()
	tree_pick.kind = PickResult.Kind.RESOURCE_SOURCE
	tree_pick.resource_source = tree
	tree_pick.position = tree.global_position
	assert_true(cmd.command_at(tree_pick))
	assert_eq(tree.get_active_worker_count(), 1, "Scenario E: concurrent multi-unit command must cap strictly at max_simultaneous_workers=1")
	assert_true(leader_b.get_current_order() is GatherResourceOrder)
	assert_null(unit_c.get_current_order(), "Loser of 1-slot race must not enter conflicting order")

	# Wait for pre-existing wood delivery + tree depletion -> total wood = 10 pre + 10 tree = 20
	var frames: int = 0
	while frames < MAX_CYCLE_FRAMES and (leader_a.get_state() != Unit.State.IDLE or leader_b.get_state() != Unit.State.IDLE):
		await wait_physics_frames(1)
		frames += 1
		assert_true(tree.get_active_worker_count() <= 1)
		var wood_sum: int = (
			tree.get_remaining_amount()
			+ leader_a.get_carry_load().get_amount(&"wood")
			+ leader_b.get_carry_load().get_amount(&"wood")
			+ unit_c.get_carry_load().get_amount(&"wood")
			+ inventory.get_amount(&"wood")
		)
		assert_eq(wood_sum, 20, "Wood must be strictly conserved throughout concurrent run")

	assert_eq(inventory.get_amount(&"wood"), 20)
	assert_true(tree.is_depleted())
	assert_eq(tree.get_active_worker_count(), 0)
	assert_eq(pre_order.get_delivered_trips(), 1)

	# Part 2: Source depletes while worker is mid-transport -> finishes SUCCEEDED after depositing cargo.
	var bush: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush.position = Vector3(2.5, 0.0, -2.0)
	bush.initial_amount = 22
	bush.max_extract_per_operation = 20
	bush.max_simultaneous_workers = 1
	test_map.add_child(bush)
	await wait_physics_frames(2)

	leader_a.global_position = Vector3(2.0, 0.0, -2.0)
	var depleting_order := GatherResourceOrder.new(bush, camp_zone, inventory, 0.05)
	leader_a.issue_order(depleting_order)
	assert_true(bush.is_worker_reserved(leader_a))

	frames = 0
	while frames < 60 and leader_a.get_state() != Unit.State.TRANSPORTING:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(leader_a.get_state(), Unit.State.TRANSPORTING)
	assert_false(depleting_order.has_reservation())
	assert_eq(bush.get_active_worker_count(), 0)
	assert_eq(bush.get_remaining_amount(), 2)
	assert_eq(bush.extract(2), 2) # deplete remaining 2 food while leader_a is actively transporting!
	assert_true(bush.is_depleted())

	frames = 0
	while frames < MAX_CYCLE_FRAMES and not depleting_order.is_finished():
		await wait_physics_frames(1)
		frames += 1

	assert_true(depleting_order.is_succeeded(), "Source depleted during transport must still finish SUCCEEDED on deposit")
	assert_eq(inventory.get_amount(&"food"), 20)
	assert_eq(bush.get_active_worker_count(), 0)

	# Part 3: Cancellation in APPROACHING_SOURCE, GATHERING, DELIVERING_TO_CAMP + tree exit (remove_child)
	var bush2: ResourceSource = BUSH_SCENE.instantiate() as ResourceSource
	bush2.position = Vector3(6.0, 0.0, -2.0)
	bush2.initial_amount = 25
	bush2.max_extract_per_operation = 20
	bush2.max_simultaneous_workers = 2
	test_map.add_child(bush2)
	await wait_physics_frames(2)

	leader_b.global_position = Vector3(2.0, 0.0, -2.0)
	leader_b.issue_order(GatherResourceOrder.new(bush2, camp_zone, inventory, 0.25))
	assert_eq(bush2.get_active_worker_count(), 1)
	leader_b.cancel_current_order() # cancel during APPROACHING_SOURCE
	assert_eq(bush2.get_active_worker_count(), 0)

	# Gather into TRANSPORTING, then replace with MoveOrder during DELIVERING_TO_CAMP
	leader_b.global_position = Vector3(5.3, 0.0, -2.0)
	leader_b.issue_order(GatherResourceOrder.new(bush2, camp_zone, inventory, 0.05))
	frames = 0
	while frames < 60 and leader_b.get_state() != Unit.State.TRANSPORTING:
		await wait_physics_frames(1)
		frames += 1
	assert_eq(leader_b.get_state(), Unit.State.TRANSPORTING)
	assert_eq(bush2.get_active_worker_count(), 0)
	leader_b.issue_order(MoveOrder.new(Vector3(4.0, 0.0, -2.0)))
	assert_eq(leader_b.get_carry_load().get_amount(&"food"), 20, "MoveOrder during DELIVERING_TO_CAMP must preserve carry load")
	assert_eq(bush2.get_active_worker_count(), 0)

	unit_c.global_position = Vector3(5.3, 0.0, -2.0)
	unit_c.issue_order(GatherResourceOrder.new(bush2, camp_zone, inventory, 0.25))
	assert_eq(unit_c.get_state(), Unit.State.WORKING)
	assert_eq(bush2.get_active_worker_count(), 1)
	unit_c.get_parent().remove_child(unit_c) # exit tree during GATHERING!
	await wait_physics_frames(1)
	assert_eq(bush2.get_active_worker_count(), 0, "Removing working unit from tree must release reservation")
	unit_c.queue_free()
