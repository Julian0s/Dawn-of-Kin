extends TestCase

const SCENE: PackedScene = preload("res://tests/visual/rux_1_auto_gather.tscn")
const TREE_SOURCE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")


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


func _click_hud_authorize(viewport: SubViewport, resource_id: StringName) -> void:
	# R-03A D1 reconciliation: source selection is decoupled from task creation;
	# explicit authorization happens via the contextual HUD category button.
	var main := viewport.get_child(0) as MainScene
	var hud := main.get_community_selection_actions_hud()
	if hud != null:
		var btn: Button = hud.get_category_button(resource_id)
		if btn != null and btn.visible:
			var rect: Rect2 = btn.get_global_rect()
			await _left_click(viewport, rect.position + rect.size * 0.5)
			await wait_process_frames(2)


func _select_and_authorize_wood(viewport: SubViewport, point: Vector2) -> void:
	await _left_click(viewport, point)
	await wait_process_frames(1)
	await _click_hud_authorize(viewport, &"wood")


func _fixture() -> SubViewport:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(1280, 720)
	add_test_child(view)
	var main := SCENE.instantiate() as MainScene
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


func test_r1_left_click_tree_auto_dispatches_nearest_eligible_leader() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var camera := view.get_camera_3d()
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var dispatcher := main.get_node("CommunityTaskDispatcher") as CommunityTaskDispatcher
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource

	assert_false(board.is_processing(), "CommunityWorkBoard must not poll in _process")
	assert_false(board.is_physics_processing(), "CommunityWorkBoard must not poll in _physics_process")
	assert_false(dispatcher.is_processing(), "CommunityTaskDispatcher must not poll in _process")
	assert_false(dispatcher.is_physics_processing(), "CommunityTaskDispatcher must not poll in _physics_process")

	var expected_worker: Unit = _nearest_unit_to(main, tree_1.global_position)
	var other_worker: Unit = null
	for u: Unit in main.get_units():
		if u != expected_worker:
			other_worker = u
			break

	var tree_point: Vector2 = camera.unproject_position(tree_1.global_position + Vector3.UP)
	await _select_and_authorize_wood(view, tree_point)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	assert_eq(board.get_active_tasks().size(), 1, "Left-click must register exactly 1 active wood task")
	var task: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(task, "Active task must be indexed by clicked tree")
	if task == null:
		await _teardown_fixture(view)
		return

	assert_eq(task.state, WorkTask.State.IN_PROGRESS, "Task must transition to IN_PROGRESS immediately when a leader is free")
	assert_eq(task.assigned_unit, expected_worker, "Nearest eligible leader must be dispatched automatically")
	assert_true(main.get_selection_manager().is_empty(), "Automatic gather must not overwrite empty RTS unit selection")

	var order := expected_worker.get_current_order() as GatherResourceOrder
	assert_not_null(order, "Nearest leader must receive a real GatherResourceOrder")
	if order != null:
		assert_eq(order.source, tree_1, "Order must target clicked tree")
		assert_true(order.is_active(), "Order must be active")

	assert_null(other_worker.get_current_order(), "Second leader must remain idle")
	assert_null(board.get_active_task_for_source(tree_2), "Unclicked tree must not have a task")
	assert_eq(tree_2.get_active_worker_count(), 0, "Unclicked tree must remain untouched")

	await _teardown_fixture(view)


func test_r2_physical_extraction_carry_deposit_and_provenance_conservation() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var camera := view.get_camera_3d()
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var inventory := main.get_settlement_inventory()

	# Keep the tree finite and compact so the full gather -> carry -> deliver -> complete cycle finishes deterministically.
	tree_1.configure(tree_1.source_id, tree_1.get_definition(), 4, 2, 2)
	var initial_wood: int = tree_1.get_remaining_amount()
	var other_tree_wood: int = tree_2.get_remaining_amount()
	var stock_before: int = inventory.get_physical_amount(&"wood")

	var tree_point: Vector2 = camera.unproject_position(tree_1.global_position + Vector3.UP)
	await _select_and_authorize_wood(view, tree_point)
	await wait_process_frames(2)

	var task: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(task, "Task must be registered for clicked tree")
	if task == null or task.assigned_unit == null:
		await _teardown_fixture(view)
		return

	var worker: Unit = task.assigned_unit
	Engine.time_scale = 3.0
	var saw_carry_before_deposit: bool = false
	var saw_valid_provenance_in_transit: bool = false
	for _i: int in range(4200):
		var carried: int = worker.get_carry_load().get_amount(&"wood")
		if carried > 0 and inventory.get_physical_amount(&"wood") == stock_before:
			saw_carry_before_deposit = true
			saw_valid_provenance_in_transit = worker.get_carry_load().validate_provenance()
		if task.state == WorkTask.State.COMPLETED:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	var delivered: int = inventory.get_physical_amount(&"wood") - stock_before
	var still_carried: int = worker.get_carry_load().get_amount(&"wood")
	assert_true(saw_carry_before_deposit, "Wood must enter physical carry load before stockpile increases")
	assert_true(saw_valid_provenance_in_transit, "Carry provenance must remain valid in transit")
	assert_eq(delivered, initial_wood, "All extracted wood must arrive at stockpile only via physical deposit")
	assert_eq(still_carried, 0, "Worker backpack must be empty after final deposit")
	assert_eq(tree_1.get_remaining_amount(), 0, "Clicked tree must be fully harvested")
	assert_eq(initial_wood - tree_1.get_remaining_amount(), delivered + still_carried, "Exact wood conservation invariant")
	assert_eq(tree_2.get_remaining_amount(), other_tree_wood, "Unclicked tree must remain intact")
	assert_eq(task.state, WorkTask.State.COMPLETED, "Task must complete after final physical delivery")
	assert_eq(board.get_active_tasks().size(), 0, "Completed task must leave active board")
	assert_true(worker.get_carry_load().validate_provenance(), "Worker provenance must remain valid after completion")

	await _teardown_fixture(view)


func test_r3_repeated_clicks_are_idempotent() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var camera := view.get_camera_3d()
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var feedback := main.get_node("UiLayer/AutonomousGatherFeedback") as AutonomousGatherFeedback
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var inventory := main.get_settlement_inventory()

	var initial_wood: int = tree_1.get_remaining_amount()
	var stock_before: int = inventory.get_physical_amount(&"wood")
	var tree_point: Vector2 = camera.unproject_position(tree_1.global_position + Vector3.UP)

	await _select_and_authorize_wood(view, tree_point)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var task: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(task, "Initial click + HUD authorization must register task")
	if task == null or task.assigned_unit == null:
		await _teardown_fixture(view)
		return

	var worker: Unit = task.assigned_unit
	var initial_order: UnitOrder = worker.get_current_order()
	var initial_revision: int = worker.get_order_revision()
	var other_worker: Unit = null
	for u: Unit in main.get_units():
		if u != worker:
			other_worker = u
			break

	# R-03A D1: repeated explicit HUD authorization clicks on already-authorized selection are strictly idempotent.
	for _click_idx: int in range(4):
		await _click_hud_authorize(view, &"wood")
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 1, "Repeated clicks must not create duplicate active tasks")
	assert_eq(board.get_all_tasks().size(), 1, "Repeated clicks must not accumulate duplicate task records")
	assert_eq(board.get_active_task_for_source(tree_1), task, "Same task instance must remain active")
	assert_eq(worker.get_current_order(), initial_order, "Repeated clicks must not replace or duplicate order")
	assert_eq(worker.get_order_revision(), initial_revision, "Repeated clicks must not bump worker order revision")
	assert_null(other_worker.get_current_order(), "Repeated clicks must not dispatch a second worker")
	assert_eq(tree_1.get_remaining_amount(), initial_wood, "Repeated clicks must not mutate tree stock")
	assert_eq(inventory.get_physical_amount(&"wood"), stock_before, "Repeated clicks must not credit stockpile")
	assert_false(feedback.last_message.is_empty(), "Repeated click should provide minimal feedback")

	await _teardown_fixture(view)


func test_r4_waits_when_both_leaders_busy_and_auto_dispatches_on_free() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var camera := view.get_camera_3d()
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	assert_not_null(leader_a, "LeaderA must exist")
	assert_not_null(leader_b, "LeaderB must exist")
	if leader_a == null or leader_b == null:
		await _teardown_fixture(view)
		return

	# LeaderB gets a short move; LeaderA gets a longer move.
	var short_move := MoveOrder.new(leader_b.global_position + Vector3(1.5, 0.0, 0.0), leader_b.global_position + Vector3(1.5, 0.0, 0.0), false)
	var long_move := MoveOrder.new(leader_a.global_position + Vector3(-8.0, 0.0, 0.0), leader_a.global_position + Vector3(-8.0, 0.0, 0.0), false)
	leader_b.issue_order(short_move)
	leader_a.issue_order(long_move)
	await wait_physics_frames(1)

	assert_true(short_move.is_active(), "LeaderB manual move must be active")
	assert_true(long_move.is_active(), "LeaderA manual move must be active")

	var tree_point: Vector2 = camera.unproject_position(tree_1.global_position + Vector3.UP)
	await _select_and_authorize_wood(view, tree_point)
	await wait_process_frames(2)

	var task: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(task, "Task must still be registered while both leaders are busy")
	if task == null:
		await _teardown_fixture(view)
		return

	assert_eq(task.state, WorkTask.State.PENDING_WORKERS, "Task must wait while both leaders are busy")
	assert_null(task.assigned_unit, "No leader should be assigned while both are busy")
	assert_eq(leader_b.get_current_order(), short_move, "LeaderB active move must not be overwritten")
	assert_eq(leader_a.get_current_order(), long_move, "LeaderA active move must not be overwritten")

	# Advance without any extra click until LeaderB finishes its short move.
	Engine.time_scale = 3.0
	for _i: int in range(600):
		if task.state == WorkTask.State.IN_PROGRESS:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_eq(task.state, WorkTask.State.IN_PROGRESS, "Waiting task must start automatically once a leader becomes free")
	assert_eq(task.assigned_unit, leader_b, "LeaderB should automatically claim the waiting task upon finishing its move")
	var gather_order := leader_b.get_current_order() as GatherResourceOrder
	assert_not_null(gather_order, "Auto-dispatched leader must run GatherResourceOrder")
	if gather_order != null:
		assert_eq(gather_order.source, tree_1, "Auto-dispatched order must target the waiting tree")

	await _teardown_fixture(view)


func test_r5_manual_order_protection_and_cargo_conservation() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var camera := view.get_camera_3d()
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var inventory := main.get_settlement_inventory()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	var initial_wood: int = tree_1.get_remaining_amount()
	var stock_before: int = inventory.get_physical_amount(&"wood")

	# Part A: Closer leader (LeaderB) already has an active manual order; dispatcher must respect it and assign LeaderA.
	var b_manual := MoveOrder.new(Vector3(-8.0, 0.0, 12.0), Vector3(-8.0, 0.0, 12.0), false)
	leader_b.issue_order(b_manual)
	await wait_physics_frames(1)

	var tree_point: Vector2 = camera.unproject_position(tree_1.global_position + Vector3.UP)
	await _select_and_authorize_wood(view, tree_point)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var task: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(task, "Task must be registered")
	if task == null:
		await _teardown_fixture(view)
		return
	assert_eq(leader_b.get_current_order(), b_manual, "Existing manual order on closer leader must never be overwritten")
	assert_eq(task.assigned_unit, leader_a, "Free eligible leader must take the task instead")

	# Wait until LeaderA extracts wood into its backpack.
	Engine.time_scale = 3.0
	for _i: int in range(1800):
		if leader_a.get_carry_load().get_amount(&"wood") > 0:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0

	var carried_before: int = leader_a.get_carry_load().get_amount(&"wood")
	assert_true(carried_before > 0, "LeaderA must have extracted wood before manual interruption")

	# Keep LeaderB busy so only LeaderA is tested for improper auto-resume.
	var b_hold_move := MoveOrder.new(Vector3(-10.0, 0.0, 4.0), Vector3(-10.0, 0.0, 4.0), false)
	leader_b.issue_order(b_hold_move)

	# Part B: Player issues a new personal MoveOrder to LeaderA during active gathering.
	var manual_dest: Vector3 = leader_a.global_position + Vector3(-2.0, 0.0, 2.0)
	main.get_selection_manager().select_single(leader_a)
	var ground_pick := PickResult.from_ground(manual_dest, Vector3.UP)
	var issued: bool = main.get_command_controller().command_at(ground_pick)
	assert_true(issued, "Personal manual MoveOrder during gathering must be accepted")
	await wait_process_frames(2)

	assert_true(leader_a.get_current_order() is MoveOrder, "Personal MoveOrder must remain active and not be hijacked during order_finished")
	assert_false(tree_1.is_worker_reserved(leader_a), "Interrupted worker must release tree reservation slot")
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), carried_before, "Manual interruption must not lose or duplicate carried wood")
	assert_true(leader_a.get_carry_load().validate_provenance(), "Provenance must stay valid after manual interruption")

	# Wait for LeaderA's short manual move to finish, then confirm no improper automatic resumption of the interrupted task.
	Engine.time_scale = 3.0
	for _i: int in range(600):
		if leader_a.get_current_order() == null:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(4)
	await wait_physics_frames(4)

	assert_null(leader_a.get_current_order(), "Interrupted leader must not silently resume the interrupted gather task after finishing personal move")
	assert_eq(leader_a.get_state(), Unit.State.IDLE, "LeaderA must remain IDLE at manual destination")
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), carried_before, "Carried wood must stay intact after manual move finishes")
	assert_true(leader_a.get_carry_load().validate_provenance(), "Carry provenance must stay intact after manual move finishes")
	var delivered: int = inventory.get_physical_amount(&"wood") - stock_before
	assert_eq(initial_wood - tree_1.get_remaining_amount(), delivered + leader_a.get_carry_load().get_amount(&"wood"), "Exact wood conservation after manual interruption")

	await _teardown_fixture(view)


func test_r6_invalid_depleted_removed_and_unreachable_sources_safe() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var camera := view.get_camera_3d()
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var sources_root := main.get_test_map().get_resource_sources_root()

	# Subcase A: Depleted tree cannot register an active task or dispatch workers.
	tree_1.configure(tree_1.source_id, tree_1.get_definition(), 2, 2, 2)
	tree_1.set(&"_tree_harvest_stage", ResourceSource.TreeHarvestStage.FALLEN)
	tree_1.extract(2)
	assert_true(tree_1.is_depleted(), "Precondition: WoodTree01 is depleted")
	var depleted_point: Vector2 = camera.unproject_position(tree_1.global_position + Vector3.UP)
	await _left_click(view, depleted_point)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 0, "Depleted tree must not create an active task")
	for u: Unit in main.get_units():
		assert_null(u.get_current_order(), "Depleted tree must not dispatch any worker")

	# Subcase B: Unreachable tree inside TestMap ClosedEnclosure fails cleanly without hanging or infinite loops.
	var blocked_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	blocked_tree.name = "BlockedTreeEnclosure"
	blocked_tree.source_id = &"wood_tree_blocked_enclosure"
	blocked_tree.position = Vector3(-16.0, 0.0, 12.0)
	sources_root.add_child(blocked_tree)
	await wait_physics_frames(2)

	var reg_blocked: Dictionary = board.register_wood_gather_task(blocked_tree)
	assert_true(bool(reg_blocked.get("ok", false)), "Registering structurally valid unreachable tree returns task for evaluation")
	var blocked_task: WorkTask = reg_blocked.get("task") as WorkTask
	await wait_process_frames(3)
	await wait_physics_frames(2)

	assert_not_null(blocked_task, "Blocked task handle exists")
	if blocked_task != null:
		assert_eq(blocked_task.state, WorkTask.State.FAILED, "Unreachable tree task must fail cleanly instead of hanging forever")
		assert_eq(blocked_task.last_reason, "source_unreachable", "Failure reason must report source_unreachable")
	assert_eq(board.get_active_tasks().size(), 0, "Failed unreachable task must be cleared from active tasks")
	for u: Unit in main.get_units():
		assert_null(u.get_current_order(), "Unreachable tree must leave workers idle")

	# Subcase C: Source removed from scene while waiting closes task cleanly without errors.
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var hold_a := MoveOrder.new(leader_a.global_position + Vector3(-5.0, 0.0, 0.0), leader_a.global_position + Vector3(-5.0, 0.0, 0.0), false)
	var hold_b := MoveOrder.new(leader_b.global_position + Vector3(5.0, 0.0, 0.0), leader_b.global_position + Vector3(5.0, 0.0, 0.0), false)
	leader_a.issue_order(hold_a)
	leader_b.issue_order(hold_b)

	var temp_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	temp_tree.name = "RemovedTreeTemp"
	temp_tree.source_id = &"wood_tree_removed_temp"
	temp_tree.position = Vector3(4.0, 0.0, -2.0)
	sources_root.add_child(temp_tree)
	await wait_physics_frames(1)

	var reg_temp: Dictionary = board.register_wood_gather_task(temp_tree)
	var temp_task: WorkTask = reg_temp.get("task") as WorkTask
	await wait_process_frames(2)
	assert_not_null(temp_task, "Temp task created while workers busy")
	if temp_task != null:
		assert_eq(temp_task.state, WorkTask.State.PENDING_WORKERS, "Temp task waiting while both leaders busy")

	temp_tree.queue_free()
	await wait_process_frames(2)
	if temp_task != null:
		assert_eq(temp_task.state, WorkTask.State.FAILED, "Removed source must close waiting task cleanly")
	assert_eq(board.get_active_tasks().size(), 0, "Removed source task must leave active board")

	# Confirm dispatcher remains completely healthy after all invalid/removed/unreachable cases.
	leader_a.cancel_current_order()
	leader_b.cancel_current_order()
	await wait_process_frames(1)
	var valid_point: Vector2 = camera.unproject_position(tree_2.global_position + Vector3.UP)
	await _select_and_authorize_wood(view, valid_point)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var healthy_task: WorkTask = board.get_active_task_for_source(tree_2)
	assert_not_null(healthy_task, "Dispatcher must still accept valid trees after invalid source handling")
	if healthy_task != null:
		assert_eq(healthy_task.state, WorkTask.State.IN_PROGRESS, "Valid tree must dispatch cleanly after recovery")

	await _teardown_fixture(view)


func test_r7_preserves_existing_selection_and_skips_reserved_cargo_worker() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var camera := view.get_camera_3d()
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	# Select LeaderA manually before clicking the tree; automatic gather must preserve SelectionManager.
	main.get_selection_manager().select_single(leader_a)

	# Give closer LeaderB a SITE_RESERVED provenance lot so it has an active construction material obligation.
	var b_load: UnitCarryLoad = leader_b.get_carry_load()
	var plan: Dictionary = b_load._prepare_provenance_add(&"op_rux1_res_test", &"lot_rux1_res_test", &"wood", 2, 2, CarryProvenanceLedger.SITE_RESERVED, &"site_dummy", 1)
	assert_true(bool(plan.get("ok", false)), "Precondition: SITE_RESERVED lot prepared on LeaderB")
	b_load._provenance_busy = true
	b_load._provenance_applying = true
	var applied: bool = b_load._apply_prepared_provenance_add(plan)
	b_load._provenance_applying = false
	b_load._provenance_busy = false
	assert_true(applied, "Precondition: SITE_RESERVED lot applied on LeaderB")

	var tree_point: Vector2 = camera.unproject_position(tree_1.global_position + Vector3.UP)
	await _select_and_authorize_wood(view, tree_point)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var task: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(task, "Task must be registered")
	if task != null:
		assert_eq(task.state, WorkTask.State.IN_PROGRESS, "Eligible LeaderA must take task while LeaderB holds SITE_RESERVED cargo")
		assert_eq(task.assigned_unit, leader_a, "Worker carrying SITE_RESERVED cargo must be skipped in favor of eligible worker")
	assert_null(leader_b.get_current_order(), "Worker carrying SITE_RESERVED cargo must not receive automatic gather order")
	assert_eq(main.get_selection_manager().get_selected_units(), [leader_a], "Existing RTS selection must remain intact")

	await _teardown_fixture(view)
