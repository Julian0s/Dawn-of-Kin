extends TestCase
## Integration tests for T2.4.2 real gathering pace, arrival preparation delay,
## continuous load-aware movement, smooth transitions, stuck safety, visual feedback,
## concurrent 2-worker execution, and clean visual/state restoration.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const TREE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const MAX_WAIT_FRAMES: int = 120
const MAX_SIM_FRAMES: int = 2400


func _spawn_main_scene() -> Dictionary:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	main_root.use_provenance_economy = false
	add_test_child(main_root)

	var test_map: TestMap = main_root.get_test_map()
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
		"camp_zone": main_root.get_camp_storage_zone(),
		"inventory": main_root.get_settlement_inventory(),
		"cmd": main_root.get_command_controller(),
		"selection": main_root.get_selection_manager(),
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _find_source(test_map: TestMap, source_id: StringName) -> ResourceSource:
	for src: ResourceSource in test_map.get_resource_sources():
		if src.source_id == source_id:
			return src
	return null


func _issue_gather(cmd: CommandController, selection: SelectionManager, workers: Array[Unit], source: ResourceSource) -> GatherResourceOrder:
	selection.set_selection(workers)
	var pick := PickResult.new()
	pick.kind = PickResult.Kind.RESOURCE_SOURCE
	pick.resource_source = source
	pick.position = source.global_position
	assert_true(cmd.command_at(pick))
	return workers[0].get_current_order() as GatherResourceOrder


func test_01_prepare_delay_prevents_premature_extraction_and_orders_food_wood_stone() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var cmd: CommandController = ctx["cmd"] as CommandController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var unit_c: Unit = UNIT_SCENE.instantiate() as Unit
	unit_c.definition = LEADER_A_DEF
	main_root.get_node("Units").add_child(unit_c)
	unit_c.set_world_navigation(nav)
	await wait_physics_frames(2)

	var bush: ResourceSource = _find_source(test_map, &"food_bush_01")
	var tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	var rock: ResourceSource = _find_source(test_map, &"stone_rock_01")

	var workers: Array[Unit] = [leader_a, leader_b, unit_c]
	var sources: Array[ResourceSource] = [bush, tree, rock]
	var orders: Array[GatherResourceOrder] = []
	var start_rem: Array[int] = []
	var prep_frames: Array[int] = [0, 0, 0]
	var total_frames: Array[int] = [0, 0, 0]
	var prep_done: Array[bool] = [false, false, false]
	var extracted: Array[bool] = [false, false, false]

	for i: int in range(3):
		var src: ResourceSource = sources[i]
		var w: Unit = workers[i]
		w.global_position = src.global_position + Vector3(-(src.get_solid_radius() + WorldNavigation.DEFAULT_AGENT_RADIUS + 0.15), 0.0, 0.0)
	await wait_physics_frames(1)

	for i: int in range(3):
		start_rem.append(sources[i].get_remaining_amount())
		var order: GatherResourceOrder = _issue_gather(cmd, selection, [workers[i]], sources[i])
		assert_not_null(order)
		assert_eq(workers[i].get_state(), Unit.State.WORKING)
		assert_true(order.is_preparing_gather(), "Arrival must enter brief preparation before first extraction")
		orders.append(order)

	var saw_zero_during_prep: bool = true
	var ticks: int = 0
	while (not extracted[0] or not extracted[1] or not extracted[2]) and ticks < 400:
		for i: int in range(3):
			if extracted[i]:
				continue
			if orders[i].is_preparing_gather():
				prep_frames[i] += 1
				if sources[i].get_remaining_amount() != start_rem[i]:
					saw_zero_during_prep = false
			else:
				prep_done[i] = true
		await wait_physics_frames(1)
		ticks += 1
		for i: int in range(3):
			if not extracted[i]:
				total_frames[i] = ticks
				if sources[i].get_remaining_amount() < start_rem[i]:
					extracted[i] = true

	assert_true(saw_zero_during_prep, "No extraction may happen during preparation pause")
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var expected_op: Array[float] = [1.5, 2.5, 3.5]
	var min_prep: Array[float] = [0.15, 0.25, 0.30]
	var gather_secs: Array[float] = []
	for i: int in range(3):
		assert_true(prep_done[i], "Preparation pause must finish before first extraction")
		assert_true(extracted[i], "First extraction must complete at real production timing")
		assert_gt(float(prep_frames[i]) * dt, min_prep[i])
		var g_sec: float = float(total_frames[i] - prep_frames[i]) * dt
		assert_near(g_sec, expected_op[i], 0.15)
		gather_secs.append(g_sec)

	assert_lt(gather_secs[0], gather_secs[1])
	assert_lt(gather_secs[1], gather_secs[2])


func test_02_source_feedback_tween_pulses_on_extract_with_zero_process_and_resets_cleanly() -> void:
	var tree: ResourceSource = TREE_SCENE.instantiate() as ResourceSource
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.definition = LEADER_A_DEF
	add_test_child(tree)
	add_test_child(unit)
	# Flush teardown frame spikes from prior test before sampling a short 0.22s Tween pulse.
	await wait_process_frames(3)
	await wait_physics_frames(2)

	var visual: Node3D = tree.get_node("AvailableVisual") as Node3D
	var rest_tf: Transform3D = visual.transform

	assert_false(tree.is_processing())
	assert_false(tree.is_physics_processing())

	var got: int = tree.transfer_to_carry_load(unit.get_carry_load(), 1)
	assert_eq(got, 1)
	assert_false(tree.is_processing())
	assert_false(tree.is_physics_processing())

	# Tween should perturb AvailableVisual during pulse then return smoothly to rest.
	# Sample every process frame from frame 1 so a slow host frame cannot skip past the 0.08s peak.
	var saw_pulse: bool = false
	var wait_f: int = 0
	while wait_f < 40:
		await wait_process_frames(1)
		wait_f += 1
		if not visual.transform.is_equal_approx(rest_tf):
			saw_pulse = true
		elif saw_pulse:
			break
	assert_true(saw_pulse, "Extraction must trigger visible zero-_process Tween feedback on source")
	assert_true(visual.transform.is_equal_approx(rest_tf), "Source visual must return to exact rest transform")

	# Depletion while mid-tween must cancel tween cleanly and hide AvailableVisual without residual offset
	unit.get_carry_load().take_all()
	assert_gt(tree.extract(tree.max_extract_per_operation), 0)
	while not tree.is_depleted():
		assert_gt(tree.extract(tree.max_extract_per_operation), 0)
	assert_true(tree.is_depleted())
	assert_false(visual.visible)
	assert_true(visual.transform.is_equal_approx(rest_tf))


func test_03_empty_t1_move_order_preserves_48_speed_and_immediate_start() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var movement: UnitMovement = leader_a.get_movement()
	leader_a.get_carry_load().take_all()
	leader_a.global_position = Vector3(-2.5, 0.0, -3.5)
	await wait_physics_frames(2)

	var target := Vector3(2.5, 0.0, -3.5)
	leader_a.issue_order(MoveOrder.new(target))
	assert_near(movement.get_target_move_speed(), 4.8, 0.02)

	var frames: int = 0
	while leader_a.get_state() == Unit.State.MOVING and frames < 120:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_true(leader_a.global_position.distance_to(target) <= 0.35)
	# 5.0m at 4.8m/s ~= 1.04s ~= 63 frames
	assert_lt(frames, 85, "Empty T1 MoveOrder must maintain full ~4.8 m/s pace")


func test_04_manual_move_order_with_load_slows_proportionally_and_applies_posture() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var carry: UnitCarryLoad = leader_a.get_carry_load()
	var movement: UnitMovement = leader_a.get_movement()
	var visual_root: Node3D = leader_a.get_node("VisualRoot") as Node3D
	var food_def: ResourceDefinition = load("res://data/resources/food.tres") as ResourceDefinition

	var measured_speeds: Array[float] = []
	for units_count: int in [0, 5, 10, 15, 20]:
		carry.take_all()
		if units_count > 0:
			assert_true(carry.add_units(food_def, units_count))
		leader_a.global_position = Vector3(-1.5, 0.0, -3.5)
		await wait_physics_frames(2)

		var target := Vector3(0.3, 0.0, -3.5)
		leader_a.issue_order(MoveOrder.new(target))
		var speed_sum: float = 0.0
		var speed_samples: int = 0
		var saw_lean: bool = false
		var frames: int = 0
		while leader_a.get_state() == Unit.State.MOVING and frames < 240:
			await wait_physics_frames(1)
			frames += 1
			if frames >= 6:
				speed_sum += Vector2(leader_a.velocity.x, leader_a.velocity.z).length()
				speed_samples += 1
				if absf(visual_root.rotation.x) > 0.02:
					saw_lean = true

		assert_eq(leader_a.get_state(), Unit.State.IDLE)
		assert_gt(speed_samples, 5)
		measured_speeds.append(speed_sum / float(speed_samples))
		if units_count >= 15:
			assert_true(saw_lean, "Heavy manual MoveOrder should show loaded effort lean on VisualRoot")
		assert_true(is_finite(movement.get_effective_move_speed()))

	for i: int in range(measured_speeds.size() - 1):
		assert_gt(
			measured_speeds[i],
			measured_speeds[i + 1] + 0.25,
			"Higher carry weight tier must monotonically slow manual MoveOrder (%s)" % str(measured_speeds)
		)


func test_05_dynamic_load_capacity_change_and_unload_smoothly_transition_active_speed() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var carry: UnitCarryLoad = leader_a.get_carry_load()
	var movement: UnitMovement = leader_a.get_movement()
	var agent: NavigationAgent3D = leader_a.get_navigation_agent()
	var wood_def: ResourceDefinition = load("res://data/resources/wood.tres") as ResourceDefinition

	leader_a.global_position = Vector3(-6.0, 0.0, -3.5)
	await wait_physics_frames(2)
	leader_a.issue_order(MoveOrder.new(Vector3(6.0, 0.0, -3.5)))
	await wait_physics_frames(4)
	assert_near(movement.get_effective_move_speed(), 4.8, 0.05)

	# Add 100% wood mid-walk: target drops to 2.88, effective smoothly decelerates across frames (not instant jump)
	assert_true(carry.add_units(wood_def, 10))
	assert_near(movement.get_target_move_speed(), 2.88, 0.05)
	await wait_physics_frames(1)
	var after_1f: float = movement.get_effective_move_speed()
	assert_lt(after_1f, 4.79)
	assert_gt(after_1f, 3.0, "Mid-walk deceleration must transition smoothly rather than snap instantaneously")

	for _i: int in range(25):
		await wait_physics_frames(1)
	assert_near(movement.get_effective_move_speed(), 2.88, 0.12)
	assert_near(agent.max_speed, movement.get_effective_move_speed(), 0.05)

	# Raise capacity mid-walk -> target increases smoothly
	assert_true(carry.set_capacity_modifier(&"pack", 20)) # 20/40 = 50% -> 4.8 * 0.8 = 3.84
	assert_near(movement.get_target_move_speed(), 3.84, 0.05)
	for _i: int in range(25):
		await wait_physics_frames(1)
	assert_near(movement.get_effective_move_speed(), 3.84, 0.12)

	# Clear load mid-walk -> smooth recovery to 4.80
	carry.take_all()
	assert_near(movement.get_target_move_speed(), 4.80, 0.05)
	for _i: int in range(25):
		await wait_physics_frames(1)
	assert_near(movement.get_effective_move_speed(), 4.80, 0.12)


func test_06_overloaded_unit_continues_moving_without_freezing_or_nan() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var carry: UnitCarryLoad = leader_a.get_carry_load()
	var movement: UnitMovement = leader_a.get_movement()
	var food_def: ResourceDefinition = load("res://data/resources/food.tres") as ResourceDefinition

	assert_true(carry.add_units(food_def, 20))
	assert_true(carry.set_capacity_modifier(&"fatigue", -15)) # 20/5 -> overloaded!
	assert_true(carry.is_overloaded())

	leader_a.global_position = Vector3(-2.0, 0.0, -3.5)
	await wait_physics_frames(2)
	var target := Vector3(0.5, 0.0, -3.5)
	leader_a.issue_order(MoveOrder.new(target))

	var frames: int = 0
	while leader_a.get_state() == Unit.State.MOVING and frames < 240:
		assert_gt(movement.get_effective_move_speed(), 0.5)
		assert_true(is_finite(movement.get_effective_move_speed()))
		await wait_physics_frames(1)
		frames += 1

	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_true(leader_a.global_position.distance_to(target) <= 0.35)


func test_07_real_pace_full_cycle_approach_work_slow_loaded_return_and_unload_recovery() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var cmd: CommandController = ctx["cmd"] as CommandController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var movement: UnitMovement = leader_a.get_movement()
	var tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	tree.max_extract_per_operation = 5 # 2 ops at real 2.5s = 5.35s working to hit 100% load cleanly
	var initial_wood: int = tree.get_remaining_amount()

	leader_a.global_position = tree.global_position + Vector3(-4.5, 0.0, 0.0)
	await wait_physics_frames(2)

	var order: GatherResourceOrder = _issue_gather(cmd, selection, [leader_a], tree)
	var approach_speeds: Array[float] = []
	var transport_speeds: Array[float] = []
	var work_frames: int = 0
	var returned_unloaded_speed: float = 0.0
	var frames: int = 0

	while inventory.get_amount(&"wood") == 0 and frames < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		var spd: float = Vector2(leader_a.velocity.x, leader_a.velocity.z).length()
		match leader_a.get_state():
			Unit.State.MOVING:
				if order.get_phase() == GatherResourceOrder.Phase.APPROACHING_SOURCE and spd > 0.5:
					approach_speeds.append(spd)
			Unit.State.WORKING:
				work_frames += 1
			Unit.State.TRANSPORTING:
				if spd > 0.5:
					transport_speeds.append(spd)

	assert_gt(inventory.get_amount(&"wood"), 0, "Real-pace cycle must complete camp delivery")
	assert_gt(work_frames, 120, "Working phase on wood must feel substantial (>= 2s before trip ends)")
	assert_gt(approach_speeds.size(), 5)
	assert_gt(transport_speeds.size(), 5)

	var avg_approach: float = _avg_float(approach_speeds)
	var avg_transport: float = _avg_float(transport_speeds)
	assert_near(avg_approach, 4.8, 0.65, "Work approach pace without load must match normal travel at ~4.8 m/s")
	assert_lt(avg_transport, avg_approach - 0.8, "Loaded return must be distinctly slower than empty approach")
	assert_near(avg_transport, 2.88, 0.40, "Fully loaded wood return must be around 2.88 m/s")

	# Step a few frames on next unloaded trip to confirm speed restored to 4.8 m/s after camp unload
	await wait_physics_frames(10)
	returned_unloaded_speed = movement.get_effective_move_speed()
	assert_near(returned_unloaded_speed, 4.8, 0.20, "Unloaded speed must recover cleanly to 4.8 m/s after delivery")
	assert_eq(
		tree.get_remaining_amount() + leader_a.get_carry_load().get_amount(&"wood") + inventory.get_amount(&"wood"),
		initial_wood
	)


func test_08_slow_loaded_walk_does_not_falsely_trigger_failed_stuck() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var leader_a: Unit = ctx["leader_a"] as Unit
	var movement: UnitMovement = leader_a.get_movement()
	var carry: UnitCarryLoad = leader_a.get_carry_load()
	var stone_def: ResourceDefinition = load("res://data/resources/stone.tres") as ResourceDefinition

	# Force slow WORK + 100% weight + walk > 2.5s loaded stuck window across the map
	leader_a.global_position = Vector3(-2.5, 0.0, -3.5)
	await wait_physics_frames(2)
	assert_true(carry.add_units(stone_def, 6))
	var order := MoveOrder.new(Vector3(2.5, 0.0, -3.5))
	leader_a.issue_order(order)
	movement.set_speed_context(UnitMovement.SpeedContext.WORK)

	var frames: int = 0
	while order.is_active() and frames < 600:
		assert_true(movement.get_move_state() != UnitMovement.MoveState.FAILED_STUCK)
		await wait_physics_frames(1)
		frames += 1

	assert_true(order.is_succeeded(), "Slow loaded walk must never falsely trigger FAILED_STUCK (reason=%s)" % order.failure_reason)
	assert_eq(movement.get_repath_attempts(), 0)


func test_09_two_concurrent_workers_real_pace_no_deadlock_or_slot_leak() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var cmd: CommandController = ctx["cmd"] as CommandController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var rock: ResourceSource = _find_source(test_map, &"stone_rock_01")
	# Keep real stone timings (3.5s op, 0.4s prep) but cap stock to 4 so both workers extract, haul & finish cleanly
	rock.initial_amount = 4
	assert_eq(rock.get_remaining_amount(), 4)
	assert_near(rock.get_gather_operation_duration_sec(), 3.5, 0.01)
	leader_a.global_position = rock.global_position + Vector3(-2.2, 0.0, -1.2)
	leader_b.global_position = rock.global_position + Vector3(-2.2, 0.0, 1.2)
	await wait_physics_frames(2)

	var order: GatherResourceOrder = _issue_gather(cmd, selection, [leader_a, leader_b], rock)
	assert_not_null(order)
	assert_eq(rock.get_active_worker_count(), 2)

	var frames: int = 0
	while (leader_a.get_state() != Unit.State.IDLE or leader_b.get_state() != Unit.State.IDLE) and frames < MAX_SIM_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(leader_b.get_state(), Unit.State.IDLE)
	assert_true(rock.is_depleted())
	assert_eq(inventory.get_amount(&"stone"), 4, "Both concurrent workers must conserve and deliver all stone at real pace")
	assert_eq(rock.get_active_worker_count(), 0, "All source worker slots must be released after completion")


func test_10_working_visual_cadence_distinct_per_category_and_transport_posture() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var cmd: CommandController = ctx["cmd"] as CommandController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var visual_root: Node3D = leader_a.get_node("VisualRoot") as Node3D

	var saw_category_motion: Dictionary = {}
	for sid: StringName in [&"wood_tree_01", &"stone_rock_01", &"food_bush_01"]:
		var src: ResourceSource = _find_source(test_map, sid)
		leader_a.cancel_current_order()
		leader_a.get_carry_load().take_all()
		leader_a.global_position = src.global_position + Vector3(-(src.get_solid_radius() + WorldNavigation.DEFAULT_AGENT_RADIUS + 0.15), 0.0, 0.0)
		await wait_physics_frames(2)

		var order: GatherResourceOrder = _issue_gather(cmd, selection, [leader_a], src)
		var max_pitch: float = 0.0
		var frames: int = 0
		while frames < 55 and order.get_phase() == GatherResourceOrder.Phase.GATHERING:
			await wait_physics_frames(1)
			frames += 1
			if not order.is_preparing_gather():
				max_pitch = maxf(max_pitch, absf(visual_root.rotation.x))
		saw_category_motion[sid] = max_pitch
		assert_gt(max_pitch, 0.03, "Expected visible working cadence tilt on %s" % str(sid))

	assert_gt(saw_category_motion.size(), 2)


func test_11_cancel_replace_depletion_and_exit_tree_leave_zero_residual_transforms() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var test_map: TestMap = ctx["test_map"] as TestMap
	var cmd: CommandController = ctx["cmd"] as CommandController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var visual_root: Node3D = leader_a.get_node("VisualRoot") as Node3D
	var col_shape: CollisionShape3D = leader_a.get_node("CollisionShape3D") as CollisionShape3D
	var nav_agent: NavigationAgent3D = leader_a.get_navigation_agent()

	var rest_visual: Transform3D = visual_root.transform
	var rest_col: Transform3D = col_shape.transform
	var bush: ResourceSource = _find_source(test_map, &"food_bush_01")
	leader_a.global_position = bush.global_position + Vector3(-1.0, 0.0, 0.0)
	await wait_physics_frames(2)

	# 1. Start working -> deform VisualRoot -> cancel_current_order resets rest transform immediately
	var order: GatherResourceOrder = _issue_gather(cmd, selection, [leader_a], bush)
	assert_not_null(order)
	for _i: int in range(30):
		await wait_physics_frames(1)
	assert_false(visual_root.transform.is_equal_approx(rest_visual), "VisualRoot should animate during WORKING")
	assert_true(col_shape.transform.is_equal_approx(rest_col), "Collider transform must never be modified by work visuals")
	assert_not_null(nav_agent)

	leader_a.cancel_current_order()
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_true(visual_root.transform.is_equal_approx(rest_visual), "Cancel must leave zero residual VisualRoot transform")

	# 2. Replace active order with MoveOrder and complete -> IDLE resets rest transform
	leader_a.issue_order(MoveOrder.new(Vector3(-2.0, 0.0, -3.5)))
	var f: int = 0
	while leader_a.get_state() != Unit.State.IDLE and f < 180:
		await wait_physics_frames(1)
		f += 1
	await wait_physics_frames(5)
	assert_true(visual_root.transform.is_equal_approx(rest_visual), "Arrival after replacement must leave zero residual transform")

	# 3. Exit tree during active WORK leaves zero errors
	leader_a.global_position = bush.global_position + Vector3(-1.0, 0.0, 0.0)
	await wait_physics_frames(1)
	_issue_gather(cmd, selection, [leader_a], bush)
	for _i: int in range(25):
		await wait_physics_frames(1)
	main_root.queue_free()
	await wait_process_frames(2)


func test_12_gather_and_deliver_travel_speeds_at_various_load_tiers() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var leader_a: Unit = ctx["leader_a"] as Unit
	var movement: UnitMovement = leader_a.get_movement()
	var carry: UnitCarryLoad = leader_a.get_carry_load()
	var food_def: ResourceDefinition = load("res://data/resources/food.tres") as ResourceDefinition
	var stone_def: ResourceDefinition = load("res://data/resources/stone.tres") as ResourceDefinition
	var bush: ResourceSource = _find_source(test_map, &"food_bush_01")

	# 1. Empty approach to source via GatherResourceOrder uses normal travel speed (4.8 m/s)
	leader_a.global_position = bush.global_position + Vector3(-5.0, 0.0, 0.0)
	await wait_physics_frames(2)
	var gather_order := GatherResourceOrder.new(bush, camp_zone, inventory)
	leader_a.issue_order(gather_order)
	assert_eq(movement.get_speed_context(), UnitMovement.SpeedContext.NORMAL)
	assert_near(movement.get_target_move_speed(), 4.80, 0.01, "Empty gather approach must target 4.8 m/s")
	leader_a.cancel_current_order()

	# 2. DeliverToCampOrder target speeds at 25%, 50%, 75%, 100% food and 90% stone
	var tiers: Array[Dictionary] = [
		{"res": food_def, "units": 5, "expected": 4.32, "desc": "25% load"},
		{"res": food_def, "units": 10, "expected": 3.84, "desc": "50% load"},
		{"res": food_def, "units": 15, "expected": 3.36, "desc": "75% load"},
		{"res": food_def, "units": 20, "expected": 2.88, "desc": "100% load"},
		{"res": stone_def, "units": 6, "expected": 3.072, "desc": "90% load (stone 18/20)"},
	]

	for tier: Dictionary in tiers:
		carry.take_all()
		assert_true(carry.add_units(tier["res"] as ResourceDefinition, int(tier["units"])))
		var deliver_order := DeliverToCampOrder.new(camp_zone, inventory)
		leader_a.issue_order(deliver_order)
		assert_eq(movement.get_speed_context(), UnitMovement.SpeedContext.NORMAL)
		assert_near(
			movement.get_target_move_speed(),
			float(tier["expected"]),
			0.02,
			"%s target speed must match weight-scaled normal speed" % str(tier["desc"])
		)
		leader_a.cancel_current_order()

	# 3. Full execution of stone delivery at 90% capacity:
	# Verifies arrival at camp, delivery into inventory, and clean recovery to 4.8 m/s
	carry.take_all()
	assert_true(carry.add_units(stone_def, 6))
	leader_a.global_position = Vector3(5.0, 0.0, -3.5)
	await wait_physics_frames(2)
	var active_delivery := DeliverToCampOrder.new(camp_zone, inventory)
	leader_a.issue_order(active_delivery)
	assert_near(movement.get_target_move_speed(), 3.072, 0.02)

	var frames: int = 0
	while active_delivery.is_active() and frames < 300:
		await wait_physics_frames(1)
		frames += 1

	assert_true(active_delivery.is_succeeded(), "Stone delivery must succeed")
	assert_true(carry.is_empty(), "Carry load must be empty after camp deposit")
	assert_eq(inventory.get_amount(&"stone"), 6, "Inventory must receive all 6 stone")
	assert_near(movement.get_target_move_speed(), 4.80, 0.01, "Speed must immediately recover to 4.8 m/s after unload")


func test_13_second_cycle_and_interrupted_manual_move_with_preserved_load() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var test_map: TestMap = ctx["test_map"] as TestMap
	var cmd: CommandController = ctx["cmd"] as CommandController
	var selection: SelectionManager = ctx["selection"] as SelectionManager
	var inventory: SettlementInventory = ctx["inventory"] as SettlementInventory
	var camp_zone: CampStorageZone = ctx["camp_zone"] as CampStorageZone
	var leader_a: Unit = ctx["leader_a"] as Unit
	var movement: UnitMovement = leader_a.get_movement()
	var carry: UnitCarryLoad = leader_a.get_carry_load()
	var wood_def: ResourceDefinition = load("res://data/resources/wood.tres") as ResourceDefinition
	var tree: ResourceSource = _find_source(test_map, &"wood_tree_01")
	tree.initial_amount = 30
	tree.max_extract_per_operation = 5

	# 1. Run first trip to camp, let it deliver and begin second approach cycle
	leader_a.global_position = tree.global_position + Vector3(-3.5, 0.0, 0.0)
	await wait_physics_frames(2)
	var gather_order: GatherResourceOrder = _issue_gather(cmd, selection, [leader_a], tree)
	assert_not_null(gather_order)

	# Wait until first delivery trip completes
	var frames: int = 0
	while gather_order.get_delivered_trips() == 0 and frames < 1200:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(gather_order.get_delivered_trips(), 1, "First delivery trip must complete")
	assert_eq(inventory.get_amount(&"wood"), 10)
	assert_true(carry.is_empty())

	# Now wait a few frames for the second approach to establish
	await wait_physics_frames(5)
	assert_eq(gather_order.get_phase(), GatherResourceOrder.Phase.APPROACHING_SOURCE)
	assert_eq(movement.get_speed_context(), UnitMovement.SpeedContext.NORMAL, "Second cycle approach must use NORMAL speed context")
	assert_near(movement.get_target_move_speed(), 4.80, 0.01, "Second cycle approach must target 4.8 m/s")
	assert_near(movement.get_effective_move_speed(), 4.80, 0.25, "Second cycle effective speed must be 4.8 m/s")

	# 2. Interrupted task with preserved load:
	# Add 10 wood (100% capacity) and issue manual MoveOrder
	assert_true(carry.add_units(wood_def, 10))
	var manual_target := Vector3(-2.0, 0.0, -3.5)
	var manual_move := MoveOrder.new(manual_target)
	leader_a.issue_order(manual_move)

	assert_true(leader_a.get_current_order() is MoveOrder)
	assert_eq(carry.get_amount(&"wood"), 10, "Manual order must not wipe carried load")
	assert_eq(movement.get_speed_context(), UnitMovement.SpeedContext.NORMAL)
	assert_near(movement.get_target_move_speed(), 2.88, 0.02, "Manual move with 100% load must target 2.88 m/s")

	frames = 0
	while manual_move.is_active() and frames < 300:
		await wait_physics_frames(1)
		frames += 1

	assert_true(manual_move.is_succeeded())
	assert_eq(carry.get_amount(&"wood"), 10, "Carried load must remain intact upon arrival")

	# 3. New gather order after manual move: with existing full load, worker immediately delivers at 2.88 m/s
	var new_gather := GatherResourceOrder.new(tree, camp_zone, inventory)
	leader_a.issue_order(new_gather)
	assert_eq(new_gather.get_phase(), GatherResourceOrder.Phase.DELIVERING_TO_CAMP)
	assert_near(movement.get_target_move_speed(), 2.88, 0.02, "Initial delivery of preserved load must move at 2.88 m/s")

	frames = 0
	while new_gather.get_delivered_trips() == 0 and frames < 300:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(new_gather.get_delivered_trips(), 1)
	assert_eq(inventory.get_amount(&"wood"), 20, "Total wood delivered must now be 20")
	assert_true(carry.is_empty())
	await wait_physics_frames(5)
	assert_near(movement.get_target_move_speed(), 4.80, 0.01, "Speed must recover to 4.8 m/s after delivering preserved load")


func _avg_float(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var s: float = 0.0
	for v: float in values:
		s += v
	return s / float(values.size())
