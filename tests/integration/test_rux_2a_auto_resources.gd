extends TestCase

const RUX_2A_SCENE: PackedScene = preload("res://tests/visual/rux_2a_auto_resources.tscn")
const RUX_1_SCENE: PackedScene = preload("res://tests/visual/rux_1_auto_gather.tscn")
const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const ROCK_SOURCE_SCENE: PackedScene = preload("res://src/economy/sources/rock_source.tscn")
const BUSH_SOURCE_SCENE: PackedScene = preload("res://src/economy/sources/bush_source.tscn")


func _click_button(viewport: SubViewport, point: Vector2, button_index: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, false)
	await wait_process_frames(1)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button_index
		event.pressed = down
		viewport.push_input(event, false)
		await wait_process_frames(1)


func _left_click(viewport: SubViewport, point: Vector2) -> void:
	await _click_button(viewport, point, MOUSE_BUTTON_LEFT)


func _right_click(viewport: SubViewport, point: Vector2) -> void:
	await _click_button(viewport, point, MOUSE_BUTTON_RIGHT)


func _fixture(scene_res: PackedScene = RUX_2A_SCENE) -> SubViewport:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(1280, 720)
	add_test_child(view)
	var main := scene_res.instantiate() as MainScene
	view.add_child(main)
	for _i: int in range(120):
		if main.get_test_map().get_navigation().is_navigation_ready():
			break
		await wait_physics_frames(1)
	await wait_process_frames(3)
	return view


func _teardown_fixture(view: SubViewport) -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(view):
		var main := view.get_child(0) as MainScene
		if main != null and is_instance_valid(main):
			for unit: Unit in main.get_units():
				if is_instance_valid(unit) and unit.get_current_order() != null:
					unit.cancel_current_order()
		view.queue_free()
		await wait_process_frames(2)


func _find_unit_by_id(main: MainScene, char_id: StringName) -> Unit:
	for unit: Unit in main.get_units():
		if unit.get_character_id() == char_id:
			return unit
	return null


func _nearest_unit_to(main: MainScene, target_pos: Vector3) -> Unit:
	var best: Unit = null
	var best_dist_sq: float = INF
	for unit: Unit in main.get_units():
		var d2: float = unit.global_position.distance_squared_to(target_pos)
		if d2 < best_dist_sq:
			best_dist_sq = d2
			best = unit
	return best


func _screen_point_for_source(view: SubViewport, main: MainScene, source: ResourceSource) -> Vector2:
	var cam_rig := main.get_node("RtsCameraRig") as RtsCameraRig
	cam_rig.set_focus_position(Vector2(source.global_position.x * 0.5, source.global_position.z * 0.5))
	var camera := view.get_camera_3d()
	var offset_y: float = 0.9 if source.get_resource_id() == &"wood" else 0.5
	return camera.unproject_position(source.global_position + Vector3(0.0, offset_y, 0.0))


func _verify_full_resource_cycle(
	source_path: String,
	untouched_path: String,
	expected_resource_id: StringName,
	expected_kind: WorkTask.Kind,
	expected_unit_weight: int,
	amount_to_configure: int,
	extract_per_op: int
) -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var dispatcher := main.get_node("CommunityTaskDispatcher") as CommunityTaskDispatcher
	var source := main.get_node(source_path) as ResourceSource
	var untouched := main.get_node(untouched_path) as ResourceSource
	var inventory := main.get_settlement_inventory()

	assert_false(board.is_processing(), "Board must not poll in _process")
	assert_false(dispatcher.is_processing(), "Dispatcher must not poll in _process")
	assert_false(dispatcher.is_physics_processing(), "Dispatcher must not poll in _physics_process")

	source.configure(source.source_id, source.get_definition(), amount_to_configure, extract_per_op, 2)
	var initial_amount: int = source.get_remaining_amount()
	var untouched_before: int = untouched.get_remaining_amount()
	var stock_before: int = inventory.get_physical_amount(expected_resource_id)
	var expected_worker: Unit = _nearest_unit_to(main, source.global_position)

	var click_pt: Vector2 = _screen_point_for_source(view, main, source)
	await _left_click(view, click_pt)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var task: WorkTask = board.get_active_task_for_source(source)
	assert_not_null(task, "Left-click on %s must register a task" % String(expected_resource_id))
	if task == null or task.assigned_unit == null:
		await _teardown_fixture(view)
		return

	assert_eq(task.resource_id, expected_resource_id, "Task must record real resource_id")
	assert_eq(task.kind, expected_kind, "Task must record matching kind")
	assert_eq(task.state, WorkTask.State.IN_PROGRESS, "Task must auto-start with nearest eligible leader")
	assert_eq(task.assigned_unit, expected_worker, "Nearest eligible leader must be chosen")
	assert_true(main.get_selection_manager().is_empty(), "Automatic gather must not overwrite empty selection")

	var worker: Unit = task.assigned_unit
	Engine.time_scale = 3.0
	var saw_carry_before_deposit: bool = false
	var saw_exact_weight: bool = false
	var saw_valid_provenance: bool = false
	for _i: int in range(5400):
		var carried: int = worker.get_carry_load().get_amount(expected_resource_id)
		if carried > 0 and inventory.get_physical_amount(expected_resource_id) == stock_before:
			saw_carry_before_deposit = true
			saw_exact_weight = (worker.get_carry_load().get_current_weight() == carried * expected_unit_weight)
			saw_valid_provenance = worker.get_carry_load().validate_provenance()
		if task.state == WorkTask.State.COMPLETED:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	var delivered: int = inventory.get_physical_amount(expected_resource_id) - stock_before
	var still_carried: int = worker.get_carry_load().get_amount(expected_resource_id)
	assert_true(saw_carry_before_deposit, "%s must enter carry load before stockpile increases" % String(expected_resource_id))
	assert_true(saw_exact_weight, "%s carry weight must match ResourceDefinition.unit_weight" % String(expected_resource_id))
	assert_true(saw_valid_provenance, "%s provenance must stay valid in transit" % String(expected_resource_id))
	assert_eq(delivered, initial_amount, "All extracted %s must reach stockpile physically" % String(expected_resource_id))
	assert_eq(still_carried, 0, "Carry load must be empty after final deposit")
	assert_eq(source.get_remaining_amount(), 0, "Target source must be exhausted")
	assert_eq(initial_amount - source.get_remaining_amount(), delivered + still_carried, "Exact conservation for %s" % String(expected_resource_id))
	assert_eq(untouched.get_remaining_amount(), untouched_before, "Second source of same type must remain untouched")
	assert_eq(task.state, WorkTask.State.COMPLETED, "Task must complete after physical delivery")
	assert_eq(board.get_active_tasks().size(), 0, "Completed task must leave active board")

	await _teardown_fixture(view)


func test_a1_wood_gather_auto_dispatches_and_delivers() -> void:
	await _verify_full_resource_cycle(
		"TestMap/ResourceSources/WoodTree01",
		"TestMap/ResourceSources/WoodTree02",
		&"wood",
		WorkTask.Kind.GATHER_WOOD,
		2,
		4,
		2
	)


func test_a2_stone_extraction_auto_dispatches_respects_weight_and_delivers() -> void:
	await _verify_full_resource_cycle(
		"TestMap/ResourceSources/StoneRock01",
		"TestMap/ResourceSources/StoneRock02",
		&"stone",
		WorkTask.Kind.GATHER_STONE,
		3,
		2,
		1
	)


func test_a3_food_harvest_auto_dispatches_respects_weight_and_delivers() -> void:
	await _verify_full_resource_cycle(
		"TestMap/ResourceSources/FoodBush01",
		"TestMap/ResourceSources/FoodBush02",
		&"food",
		WorkTask.Kind.GATHER_FOOD,
		1,
		4,
		2
	)


func test_a4_identity_idempotency_and_independent_tasks_across_sources() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var rock_1 := main.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	var bush_1 := main.get_node("TestMap/ResourceSources/FoodBush01") as ResourceSource

	var rock_pt: Vector2 = _screen_point_for_source(view, main, rock_1)
	await _left_click(view, rock_pt)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var rock_task: WorkTask = board.get_active_task_for_source(rock_1)
	assert_not_null(rock_task, "Stone rock click must register task")
	if rock_task == null or rock_task.assigned_unit == null:
		await _teardown_fixture(view)
		return

	var first_worker: Unit = rock_task.assigned_unit
	var first_order: UnitOrder = first_worker.get_current_order()
	var first_rev: int = first_worker.get_order_revision()

	for _i: int in range(3):
		await _left_click(view, rock_pt)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 1, "Repeated clicks on rock must not duplicate task")
	assert_eq(board.get_all_tasks().size(), 1, "Repeated clicks on rock must not duplicate task history")
	assert_eq(first_worker.get_current_order(), first_order, "Repeated clicks must not replace active order")
	assert_eq(first_worker.get_order_revision(), first_rev, "Repeated clicks must not bump order revision")

	# Clicking a distinct resource source registers a second independent task for the second leader.
	var tree_pt: Vector2 = _screen_point_for_source(view, main, tree_1)
	await _left_click(view, tree_pt)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var tree_task: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(tree_task, "Distinct wood source must register independent task")
	assert_eq(board.get_active_tasks().size(), 2, "Two distinct sources must yield two independent active tasks")
	if tree_task != null:
		assert_ne(tree_task.task_id, rock_task.task_id, "Distinct tasks must have distinct IDs")
		assert_eq(tree_task.state, WorkTask.State.IN_PROGRESS, "Second leader must pick up independent wood task")
		assert_ne(tree_task.assigned_unit, first_worker, "Each independent task gets a distinct worker")

	# Third distinct source (food bush) waits cleanly because both leaders are now active on rock and tree.
	var bush_pt: Vector2 = _screen_point_for_source(view, main, bush_1)
	await _left_click(view, bush_pt)
	await wait_process_frames(2)

	var bush_task: WorkTask = board.get_active_task_for_source(bush_1)
	assert_not_null(bush_task, "Third distinct source must register independently")
	assert_eq(board.get_active_tasks().size(), 3, "Board must hold all three independent tasks")
	if bush_task != null:
		assert_eq(bush_task.state, WorkTask.State.PENDING_WORKERS, "Third task waits while both leaders are working")

	await _teardown_fixture(view)


func test_a5_waits_when_both_leaders_busy_and_starts_stone_task_on_free() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var rock_1 := main.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	var short_move := MoveOrder.new(leader_a.global_position + Vector3(-1.5, 0.0, 0.0), leader_a.global_position + Vector3(-1.5, 0.0, 0.0), false)
	var long_move := MoveOrder.new(leader_b.global_position + Vector3(8.0, 0.0, 0.0), leader_b.global_position + Vector3(8.0, 0.0, 0.0), false)
	leader_a.issue_order(short_move)
	leader_b.issue_order(long_move)
	await wait_physics_frames(1)

	var rock_pt: Vector2 = _screen_point_for_source(view, main, rock_1)
	await _left_click(view, rock_pt)
	await wait_process_frames(2)

	var task: WorkTask = board.get_active_task_for_source(rock_1)
	assert_not_null(task, "Stone task must register while both leaders are busy")
	if task == null:
		await _teardown_fixture(view)
		return
	assert_eq(task.state, WorkTask.State.PENDING_WORKERS, "Stone task must wait while both leaders are busy")
	assert_eq(leader_a.get_current_order(), short_move, "LeaderA manual order must remain untouched")
	assert_eq(leader_b.get_current_order(), long_move, "LeaderB manual order must remain untouched")

	Engine.time_scale = 3.0
	for _i: int in range(600):
		if task.state == WorkTask.State.IN_PROGRESS:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_eq(task.state, WorkTask.State.IN_PROGRESS, "Waiting stone task must start automatically once LeaderA finishes")
	assert_eq(task.assigned_unit, leader_a, "Newly free LeaderA must take the waiting stone task")
	var gather_order := leader_a.get_current_order() as GatherResourceOrder
	assert_not_null(gather_order, "Auto-dispatched order must be GatherResourceOrder")
	if gather_order != null:
		assert_eq(gather_order.source, rock_1, "Order must target StoneRock01")

	await _teardown_fixture(view)


func _exercise_manual_interruption_for_resource(
	source_path: String,
	resource_id: StringName
) -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var source := main.get_node(source_path) as ResourceSource
	var inventory := main.get_settlement_inventory()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	var initial_amount: int = source.get_remaining_amount()
	var stock_before: int = inventory.get_physical_amount(resource_id)

	# Keep the other leader busy initially so the chosen worker is deterministic.
	var first_worker: Unit = _nearest_unit_to(main, source.global_position)
	var second_worker: Unit = leader_b if first_worker == leader_a else leader_a
	var second_busy := MoveOrder.new(second_worker.global_position + Vector3(0.0, 0.0, 12.0), second_worker.global_position + Vector3(0.0, 0.0, 12.0), false)
	second_worker.issue_order(second_busy)
	await wait_physics_frames(1)

	var click_pt: Vector2 = _screen_point_for_source(view, main, source)
	await _left_click(view, click_pt)
	await wait_process_frames(2)

	var task: WorkTask = board.get_active_task_for_source(source)
	assert_not_null(task, "Task for %s must register" % String(resource_id))
	if task == null or task.assigned_unit != first_worker:
		assert_true(false, "Expected nearest free worker on %s" % String(resource_id))
		await _teardown_fixture(view)
		return

	# Wait until the worker actually extracts resource into backpack.
	Engine.time_scale = 3.0
	for _i: int in range(2400):
		if first_worker.get_carry_load().get_amount(resource_id) > 0:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0

	var carried_before: int = first_worker.get_carry_load().get_amount(resource_id)
	assert_true(carried_before > 0, "Worker must carry %s before manual interruption" % String(resource_id))

	# Keep second_worker actively moving while we verify first_worker does not silently resume after its personal move.
	var second_hold_dest: Vector3 = Vector3(-10.0, 0.0, -10.0)
	var second_hold := MoveOrder.new(second_hold_dest, second_hold_dest, false)
	second_worker.issue_order(second_hold)

	# Interrupt with personal MoveOrder via CommandController.
	var manual_dest: Vector3 = first_worker.global_position + Vector3(-1.8, 0.0, 1.8)
	main.get_selection_manager().select_single(first_worker)
	var issued: bool = main.get_command_controller().command_at(PickResult.from_ground(manual_dest, Vector3.UP))
	assert_true(issued, "Personal move during %s gather must be accepted" % String(resource_id))
	await wait_process_frames(2)

	assert_true(first_worker.get_current_order() is MoveOrder, "Manual move must not be overwritten for %s" % String(resource_id))
	assert_false(source.is_worker_reserved(first_worker), "Source slot must be released on interruption for %s" % String(resource_id))
	assert_eq(first_worker.get_carry_load().get_amount(resource_id), carried_before, "No %s cargo loss/duplication on interruption" % String(resource_id))
	assert_true(first_worker.get_carry_load().validate_provenance(), "Provenance valid after %s interruption" % String(resource_id))

	# Wait for manual move to finish; interrupted worker must NOT silently resume the task.
	Engine.time_scale = 3.0
	for _i: int in range(900):
		if first_worker.get_current_order() == null:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(3)
	await wait_physics_frames(3)

	assert_null(first_worker.get_current_order(), "Interrupted worker must not auto-resume %s task" % String(resource_id))
	assert_eq(first_worker.get_carry_load().get_amount(resource_id), carried_before, "Carried %s preserved after move finishes" % String(resource_id))
	assert_true(first_worker.get_carry_load().validate_provenance(), "Provenance preserved after move finishes for %s" % String(resource_id))

	# Freeing the other non-excluded leader (if still on its hold move) allows that colleague to take over the waiting task.
	if second_worker.get_current_order() == second_hold:
		second_worker.cancel_current_order()
	await wait_process_frames(3)
	await wait_physics_frames(1)

	assert_eq(task.state, WorkTask.State.IN_PROGRESS, "Non-excluded colleague must pick up interrupted %s task" % String(resource_id))
	assert_eq(task.assigned_unit, second_worker, "Colleague must take over %s task while interrupted leader stays idle" % String(resource_id))
	assert_null(first_worker.get_current_order(), "Interrupted leader remains free and undisturbed")

	var delivered: int = inventory.get_physical_amount(resource_id) - stock_before
	var total_carried: int = first_worker.get_carry_load().get_amount(resource_id) + second_worker.get_carry_load().get_amount(resource_id)
	assert_eq(initial_amount - source.get_remaining_amount(), delivered + total_carried, "Exact conservation during takeover for %s" % String(resource_id))

	await _teardown_fixture(view)


func test_a6_manual_priority_and_interruption_across_wood_stone_food() -> void:
	await _exercise_manual_interruption_for_resource("TestMap/ResourceSources/WoodTree01", &"wood")
	await _exercise_manual_interruption_for_resource("TestMap/ResourceSources/StoneRock01", &"stone")
	await _exercise_manual_interruption_for_resource("TestMap/ResourceSources/FoodBush01", &"food")


func test_a7_depleted_removed_and_unreachable_across_rock_and_bush() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var rock_1 := main.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	var bush_1 := main.get_node("TestMap/ResourceSources/FoodBush01") as ResourceSource
	var bush_2 := main.get_node("TestMap/ResourceSources/FoodBush02") as ResourceSource
	var sources_root := main.get_test_map().get_resource_sources_root()

	# Depleted rock and bush rejected cleanly.
	rock_1.configure(rock_1.source_id, rock_1.get_definition(), 1, 1, 2)
	rock_1.extract(1)
	bush_1.configure(bush_1.source_id, bush_1.get_definition(), 2, 2, 2)
	bush_1.extract(2)
	await _left_click(view, _screen_point_for_source(view, main, rock_1))
	await _left_click(view, _screen_point_for_source(view, main, bush_1))
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 0, "Depleted rock and bush must not create active tasks")
	for u: Unit in main.get_units():
		assert_null(u.get_current_order(), "Depleted sources must not dispatch workers")

	# Unreachable rock inside ClosedEnclosure fails cleanly without hanging.
	var blocked_rock := ROCK_SOURCE_SCENE.instantiate() as ResourceSource
	blocked_rock.name = "BlockedRockEnclosure"
	blocked_rock.source_id = &"stone_rock_blocked_enclosure"
	blocked_rock.position = Vector3(-16.0, 0.0, 12.0)
	sources_root.add_child(blocked_rock)
	await wait_physics_frames(2)

	var reg_rock: Dictionary = board.register_gather_task(blocked_rock)
	assert_true(bool(reg_rock.get("ok", false)), "Structurally valid unreachable rock registers for evaluation")
	var blocked_task: WorkTask = reg_rock.get("task") as WorkTask
	await wait_process_frames(3)
	await wait_physics_frames(2)

	assert_not_null(blocked_task, "Blocked rock task exists")
	if blocked_task != null:
		assert_eq(blocked_task.state, WorkTask.State.FAILED, "Unreachable rock must fail cleanly")
		assert_eq(blocked_task.last_reason, "source_unreachable", "Failure reason must be source_unreachable")
	assert_eq(board.get_active_tasks().size(), 0, "Failed rock task must leave active board")

	# Removed bush while waiting closes cleanly.
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	leader_a.issue_order(MoveOrder.new(leader_a.global_position + Vector3(-5.0, 0.0, 0.0), leader_a.global_position + Vector3(-5.0, 0.0, 0.0), false))
	leader_b.issue_order(MoveOrder.new(leader_b.global_position + Vector3(5.0, 0.0, 0.0), leader_b.global_position + Vector3(5.0, 0.0, 0.0), false))

	var temp_bush := BUSH_SOURCE_SCENE.instantiate() as ResourceSource
	temp_bush.name = "RemovedBushTemp"
	temp_bush.source_id = &"food_bush_removed_temp"
	temp_bush.position = Vector3(-4.0, 0.0, 4.0)
	sources_root.add_child(temp_bush)
	await wait_physics_frames(1)

	var reg_bush: Dictionary = board.register_gather_task(temp_bush)
	var temp_task: WorkTask = reg_bush.get("task") as WorkTask
	await wait_process_frames(2)
	assert_not_null(temp_task, "Temp bush task created while leaders busy")
	if temp_task != null:
		assert_eq(temp_task.state, WorkTask.State.PENDING_WORKERS, "Temp bush task waits while leaders busy")

	temp_bush.queue_free()
	await wait_process_frames(2)
	if temp_task != null:
		assert_eq(temp_task.state, WorkTask.State.FAILED, "Removed bush must close task cleanly")
	assert_eq(board.get_active_tasks().size(), 0, "Removed bush task must leave active board")

	# Dispatcher remains healthy for valid FoodBush02 afterwards.
	leader_a.cancel_current_order()
	leader_b.cancel_current_order()
	await wait_process_frames(1)
	await _left_click(view, _screen_point_for_source(view, main, bush_2))
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var healthy_task: WorkTask = board.get_active_task_for_source(bush_2)
	assert_not_null(healthy_task, "Dispatcher must recover cleanly and accept FoodBush02")
	if healthy_task != null:
		assert_eq(healthy_task.state, WorkTask.State.IN_PROGRESS, "Valid bush dispatches cleanly after errors")

	await _teardown_fixture(view)


func test_a8_manual_exclusion_block_detectable_without_silent_reassignment() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var dispatcher := main.get_node("CommunityTaskDispatcher") as CommunityTaskDispatcher
	var feedback := main.get_node("UiLayer/AutonomousGatherFeedback") as AutonomousGatherFeedback
	var rock_1 := main.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	var rock_pt: Vector2 = _screen_point_for_source(view, main, rock_1)
	await _left_click(view, rock_pt)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var task: WorkTask = board.get_active_task_for_source(rock_1)
	assert_not_null(task, "Stone task must register")
	if task == null or task.assigned_unit == null:
		await _teardown_fixture(view)
		return

	# Interrupt first assigned leader with a personal move -> second leader automatically picks up task.
	var first_unit: Unit = task.assigned_unit
	var second_unit: Unit = leader_b if first_unit == leader_a else leader_a
	first_unit.issue_order(MoveOrder.new(first_unit.global_position + Vector3(1.0, 0.0, 1.0), first_unit.global_position + Vector3(1.0, 0.0, 1.0), false))
	await wait_process_frames(3)
	await wait_physics_frames(1)

	assert_eq(task.assigned_unit, second_unit, "Second non-excluded leader should pick up stone task")

	# Interrupt second leader as well -> now ALL workers are manually excluded!
	second_unit.issue_order(MoveOrder.new(second_unit.global_position + Vector3(-1.0, 0.0, 1.0), second_unit.global_position + Vector3(-1.0, 0.0, 1.0), false))
	await wait_process_frames(3)
	await wait_physics_frames(1)

	# Let both short moves finish so both leaders are genuinely IDLE.
	Engine.time_scale = 3.0
	for _i: int in range(600):
		if leader_a.get_current_order() == null and leader_b.get_current_order() == null:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(4)
	await wait_physics_frames(4)

	assert_eq(task.state, WorkTask.State.BLOCKED_REAUTHORIZATION, "Task with all workers excluded must transition to BLOCKED_REAUTHORIZATION")
	assert_eq(task.last_reason, WorkTask.REASON_ALL_WORKERS_EXCLUDED, "Task must expose clear manual-exclusion block reason")
	assert_string_contains(feedback.last_message, "nova autorização", "Feedback must inform task awaits new authorization")
	assert_null(leader_a.get_current_order(), "Excluded LeaderA must not be silently reassigned")
	assert_null(leader_b.get_current_order(), "Excluded LeaderB must not be silently reassigned")
	assert_eq(board.get_pending_tasks().size(), 0, "Blocked task must be distinguished from temporary PENDING_WORKERS wait")
	assert_eq(board.get_active_task_for_source(rock_1), task, "Blocked task stays indexed on source to preserve idempotency")
	assert_false(dispatcher.is_processing(), "Dispatcher must remain zero-polling when blocked")
	assert_false(dispatcher.is_physics_processing(), "Dispatcher must remain zero-physics-polling when blocked")

	# Clicking the blocked source again does not duplicate task or force excluded leaders back.
	await _left_click(view, rock_pt)
	await wait_process_frames(2)
	assert_eq(board.get_all_tasks().size(), 1, "Clicking blocked source must remain idempotent")
	assert_null(leader_a.get_current_order(), "Clicking blocked source must not silently reassign excluded LeaderA")
	assert_null(leader_b.get_current_order(), "Clicking blocked source must not silently reassign excluded LeaderB")
	assert_string_contains(feedback.last_message, "nova autorização", "Clicking blocked source repeats clear authorization feedback")

	await _teardown_fixture(view)


func test_a9_economic_conservation_across_all_three_resources() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var rock_1 := main.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	var bush_1 := main.get_node("TestMap/ResourceSources/FoodBush01") as ResourceSource
	var inventory := main.get_settlement_inventory()

	tree_1.configure(tree_1.source_id, tree_1.get_definition(), 4, 2, 2)
	rock_1.configure(rock_1.source_id, rock_1.get_definition(), 2, 1, 2)
	bush_1.configure(bush_1.source_id, bush_1.get_definition(), 4, 2, 2)

	var init_wood: int = tree_1.get_remaining_amount()
	var init_stone: int = rock_1.get_remaining_amount()
	var init_food: int = bush_1.get_remaining_amount()
	var stock_wood_0: int = inventory.get_physical_amount(&"wood")
	var stock_stone_0: int = inventory.get_physical_amount(&"stone")
	var stock_food_0: int = inventory.get_physical_amount(&"food")

	var reg_w: Dictionary = board.register_gather_task(tree_1)
	var reg_s: Dictionary = board.register_gather_task(rock_1)
	var reg_f: Dictionary = board.register_gather_task(bush_1)
	assert_true(bool(reg_w.get("ok", false)), "Wood task registered")
	assert_true(bool(reg_s.get("ok", false)), "Stone task registered")
	assert_true(bool(reg_f.get("ok", false)), "Food task registered")

	Engine.time_scale = 3.0
	for _i: int in range(9000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	var units := main.get_units()
	var carried_wood: int = 0
	var carried_stone: int = 0
	var carried_food: int = 0
	for u: Unit in units:
		carried_wood += u.get_carry_load().get_amount(&"wood")
		carried_stone += u.get_carry_load().get_amount(&"stone")
		carried_food += u.get_carry_load().get_amount(&"food")
		assert_true(u.get_carry_load().validate_provenance(), "Provenance valid across multi-resource sequence")

	var delivered_wood: int = inventory.get_physical_amount(&"wood") - stock_wood_0
	var delivered_stone: int = inventory.get_physical_amount(&"stone") - stock_stone_0
	var delivered_food: int = inventory.get_physical_amount(&"food") - stock_food_0

	assert_eq(init_wood - tree_1.get_remaining_amount(), delivered_wood + carried_wood, "Exact wood conservation")
	assert_eq(init_stone - rock_1.get_remaining_amount(), delivered_stone + carried_stone, "Exact stone conservation")
	assert_eq(init_food - bush_1.get_remaining_amount(), delivered_food + carried_food, "Exact food conservation")
	assert_eq(delivered_wood, init_wood, "All wood delivered physically")
	assert_eq(delivered_stone, init_stone, "All stone delivered physically")
	assert_eq(delivered_food, init_food, "All food delivered physically")
	assert_eq(board.get_active_tasks().size(), 0, "All three sequential/parallel resource tasks completed cleanly")

	await _teardown_fixture(view)


func test_a10_preserves_rts_controls_and_previous_scenes() -> void:
	# 1. In RUX-2A scene: unit selection and right-click ground move still work normally.
	var view_2a := await _fixture(RUX_2A_SCENE)
	var main_2a := view_2a.get_child(0) as MainScene
	var cam_2a := view_2a.get_camera_3d()
	var leader_a_2a := _find_unit_by_id(main_2a, &"leader_a")
	await _left_click(view_2a, cam_2a.unproject_position(leader_a_2a.global_position + Vector3.UP))
	assert_eq(main_2a.get_selection_manager().get_selected_units(), [leader_a_2a], "Unit left-click selection preserved in RUX-2A")

	await _right_click(view_2a, cam_2a.unproject_position(Vector3(0.0, 0.0, 5.5)))
	await wait_process_frames(1)
	assert_true(leader_a_2a.get_current_order() is MoveOrder, "Right-click ground move preserved in RUX-2A")
	await _teardown_fixture(view_2a)

	# 2. In RUX-1 scene: stone click does NOT create a task (RUX-1 remains wood-only), wood click still works.
	var view_1 := await _fixture(RUX_1_SCENE)
	var main_1 := view_1.get_child(0) as MainScene
	var board_1 := main_1.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var rock_in_1 := main_1.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	await _left_click(view_1, _screen_point_for_source(view_1, main_1, rock_in_1))
	await wait_process_frames(2)
	assert_eq(board_1.get_active_tasks().size(), 0, "RUX-1 scene preserves wood-only scope")
	await _teardown_fixture(view_1)

	# 3. In MainScene: classic right-click gather on stone rock still works unchanged.
	var view_main := await _fixture(MAIN_SCENE)
	var main_orig := view_main.get_child(0) as MainScene
	var leader_a_orig := _find_unit_by_id(main_orig, &"leader_a")
	var rock_orig := main_orig.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	main_orig.get_selection_manager().select_single(leader_a_orig)
	var ok_rc: bool = main_orig.get_command_controller().command_at(PickResult.from_resource_source(rock_orig, rock_orig.global_position, Vector3.UP))
	assert_true(ok_rc, "MainScene preserves classic right-click gather on stone")
	assert_true(leader_a_orig.get_current_order() is GatherResourceOrder, "MainScene issues GatherResourceOrder via right-click")
	await _teardown_fixture(view_main)
