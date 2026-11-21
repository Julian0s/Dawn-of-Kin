extends TestCase

const RUX_2B_SCENE: PackedScene = preload("res://tests/visual/rux_2b_multi_source_selection.tscn")
const TREE_SOURCE_SCENE: PackedScene = preload("res://src/economy/sources/tree_source.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")


func _click_button(viewport: SubViewport, point: Vector2, button_index: MouseButton, shift_pressed: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.shift_pressed = shift_pressed
	viewport.push_input(motion, false)
	await wait_process_frames(1)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button_index
		event.pressed = down
		event.shift_pressed = shift_pressed
		viewport.push_input(event, false)
		await wait_process_frames(1)


func _left_click(viewport: SubViewport, point: Vector2, shift_pressed: bool = false) -> void:
	await _click_button(viewport, point, MOUSE_BUTTON_LEFT, shift_pressed)


func _right_click(viewport: SubViewport, point: Vector2) -> void:
	await _click_button(viewport, point, MOUSE_BUTTON_RIGHT, false)


func _left_drag(viewport: SubViewport, start_point: Vector2, end_point: Vector2, shift_pressed: bool = false) -> void:
	var m0 := InputEventMouseMotion.new()
	m0.position = start_point
	m0.global_position = start_point
	m0.shift_pressed = shift_pressed
	viewport.push_input(m0, false)
	await wait_process_frames(1)

	var down := InputEventMouseButton.new()
	down.position = start_point
	down.global_position = start_point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.shift_pressed = shift_pressed
	viewport.push_input(down, false)
	await wait_process_frames(1)

	var mid := start_point.lerp(end_point, 0.5)
	for pt: Vector2 in [mid, end_point]:
		var mm := InputEventMouseMotion.new()
		mm.position = pt
		mm.global_position = pt
		mm.shift_pressed = shift_pressed
		viewport.push_input(mm, false)
		await wait_process_frames(1)

	var up := InputEventMouseButton.new()
	up.position = end_point
	up.global_position = end_point
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.shift_pressed = shift_pressed
	viewport.push_input(up, false)
	await wait_process_frames(1)


func _press_esc(viewport: SubViewport) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	viewport.push_input(ev, false)
	await wait_process_frames(1)
	var ev_up := InputEventKey.new()
	ev_up.physical_keycode = KEY_ESCAPE
	ev_up.keycode = KEY_ESCAPE
	ev_up.pressed = false
	viewport.push_input(ev_up, false)
	await wait_process_frames(1)


func _fixture() -> SubViewport:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(1280, 720)
	add_test_child(view)
	var main := RUX_2B_SCENE.instantiate() as MainScene
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


func _source_screen_point(view: SubViewport, source: ResourceSource) -> Vector2:
	var camera := view.get_camera_3d()
	var y_off: float = 0.9 if source.get_resource_id() == &"wood" else 0.5
	return camera.unproject_position(source.global_position + Vector3(0.0, y_off, 0.0))


func _focus_camera(main: MainScene, xz: Vector2) -> void:
	var cam_rig := main.get_node("RtsCameraRig") as RtsCameraRig
	cam_rig.set_focus_position(xz)


func _compute_screen_bounds(view: SubViewport, sources: Array[ResourceSource], pad_px: float = 12.0) -> Rect2:
	var first_pt: Vector2 = _source_screen_point(view, sources[0])
	var rect := Rect2(first_pt, Vector2.ZERO)
	for i: int in range(1, sources.size()):
		rect = rect.expand(_source_screen_point(view, sources[i]))
	return rect.grow(pad_px)


func _drag_select_sources_starting_on(
	view: SubViewport,
	origin_source: ResourceSource,
	target_sources: Array[ResourceSource],
	shift_pressed: bool = false
) -> void:
	# Compute a screen rectangle that starts strictly on origin_source and spans all target_sources.
	# Ensure every target source lies inside the rectangle from start_pt to end_pt.
	var start_pt: Vector2 = _source_screen_point(view, origin_source)
	var min_x: float = start_pt.x
	var min_y: float = start_pt.y
	var max_x: float = start_pt.x
	var max_y: float = start_pt.y
	for src: ResourceSource in target_sources:
		var pt: Vector2 = _source_screen_point(view, src)
		min_x = minf(min_x, pt.x)
		min_y = minf(min_y, pt.y)
		max_x = maxf(max_x, pt.x)
		max_y = maxf(max_y, pt.y)
	# Pick the corner farthest from start_pt with a modest padding margin so all targets are inside.
	var end_x: float = max_x + 18.0 if absf(max_x - start_pt.x) >= absf(min_x - start_pt.x) else min_x - 18.0
	var end_y: float = max_y + 18.0 if absf(max_y - start_pt.y) >= absf(min_y - start_pt.y) else min_y - 18.0
	await _left_drag(view, start_pt, Vector2(end_x, end_y), shift_pressed)


func _count_highlight_children(source: ResourceSource) -> int:
	var count: int = 0
	for child: Node in source.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("AutoGatherTaskRing_"):
			count += 1
	return count


func test_b1_single_source_click_preserved() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_6 := main.get_node("TestMap/ResourceSources/WoodTree06") as ResourceSource

	_focus_camera(main, Vector2(10.0, 1.0))
	await wait_process_frames(1)
	await _left_click(view, _source_screen_point(view, tree_1))
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var task: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(task, "Simple left-click must still register single source task")
	assert_eq(board.get_active_tasks().size(), 1, "Only clicked source registered")
	if task != null:
		assert_eq(task.state, WorkTask.State.IN_PROGRESS, "Single source auto-dispatches immediately")
		assert_true(task.group_id > 0, "Task carries valid group_id")
	assert_null(board.get_active_task_for_source(tree_6), "Unclicked 6th tree remains untouched")
	assert_true(main.get_selection_manager().is_empty(), "Single source click does not alter empty unit selection")

	await _teardown_fixture(view)


func test_b2_shift_click_adds_homogeneous_sources_without_duplicates_or_mixing() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var feedback := main.get_node("UiLayer/AutonomousGatherFeedback") as AutonomousGatherFeedback
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var tree_5 := main.get_node("TestMap/ResourceSources/WoodTree05") as ResourceSource
	var rock_1 := main.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource

	_focus_camera(main, Vector2(9.0, 2.0))
	await wait_process_frames(1)

	await _left_click(view, _source_screen_point(view, tree_1), false)
	await wait_process_frames(2)
	var t1: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(t1, "Initial tree registered")
	if t1 == null:
		await _teardown_fixture(view)
		return

	await _left_click(view, _source_screen_point(view, tree_2), true)
	await _left_click(view, _source_screen_point(view, tree_5), true)
	await wait_process_frames(2)

	var t2: WorkTask = board.get_active_task_for_source(tree_2)
	var t5: WorkTask = board.get_active_task_for_source(tree_5)
	assert_not_null(t2, "Shift+click adds second tree")
	assert_not_null(t5, "Shift+click adds third tree")
	assert_eq(board.get_active_tasks().size(), 3, "Three distinct trees active")
	if t2 != null and t5 != null:
		assert_eq(t2.group_id, t1.group_id, "Shift+click joins same logical group")
		assert_eq(t5.group_id, t1.group_id, "Third Shift+click joins same logical group")
		assert_eq(board.get_tasks_in_group(t1.group_id).size(), 3, "Group contains exactly 3 tasks")

	# Repeated Shift+click on already-marked tree must NOT remove it (P-RUX-6 open) and must not duplicate.
	await _left_click(view, _source_screen_point(view, tree_2), true)
	await wait_process_frames(2)
	assert_eq(board.get_active_tasks().size(), 3, "Repeated Shift+click must preserve task without destructive removal")
	assert_eq(board.get_active_task_for_source(tree_2), t2, "Existing tree task instance preserved")
	assert_false(feedback.last_message.is_empty(), "Repeated Shift+click gives feedback")

	# Shift+click on a rock while active Shift group is wood must NOT accidentally mix resource types.
	_focus_camera(main, Vector2(-6.0, 0.0))
	await wait_process_frames(1)
	await _left_click(view, _source_screen_point(view, rock_1), true)
	await wait_process_frames(2)
	assert_null(board.get_active_task_for_source(rock_1), "Shift+click must not mix rock into active wood selection")
	assert_eq(board.get_active_tasks().size(), 3, "Wood group count remains 3 after rejected mixed Shift+click")

	await _teardown_fixture(view)


func test_b3_box_selects_five_of_six_trees_leaving_sixth_intact() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var tree_3 := main.get_node("TestMap/ResourceSources/WoodTree03") as ResourceSource
	var tree_4 := main.get_node("TestMap/ResourceSources/WoodTree04") as ResourceSource
	var tree_5 := main.get_node("TestMap/ResourceSources/WoodTree05") as ResourceSource
	var tree_6 := main.get_node("TestMap/ResourceSources/WoodTree06") as ResourceSource

	var selected_five: Array[ResourceSource] = [tree_1, tree_2, tree_3, tree_4, tree_5]
	for t: ResourceSource in selected_five:
		t.configure(t.source_id, t.get_definition(), 2, 2, 2)
	tree_6.configure(tree_6.source_id, tree_6.get_definition(), 24, 2, 2)
	var stock_before: int = inventory.get_physical_amount(&"wood")

	# Focus camera on the grove and inspect screen coordinates to guarantee a clean 5-tree rectangle.
	_focus_camera(main, Vector2(11.0, 2.0))
	await wait_process_frames(2)

	# Start drag on WoodTree02 (bottom-leftmost in isometric view) and drag across WoodTree01..05, stopping short of WoodTree06.
	var p_t1: Vector2 = _source_screen_point(view, tree_1)
	var p_t2: Vector2 = _source_screen_point(view, tree_2)
	var p_t3: Vector2 = _source_screen_point(view, tree_3)
	var p_t4: Vector2 = _source_screen_point(view, tree_4)
	var p_t5: Vector2 = _source_screen_point(view, tree_5)
	var p_t6: Vector2 = _source_screen_point(view, tree_6)

	# Choose origin tree among the 5 that is an extreme corner opposite to the other 4 so the drag box includes all 5 and excludes tree_6.
	var chosen_origin: ResourceSource = null
	var chosen_end: Vector2 = Vector2.ZERO
	var points_five: Array[Vector2] = [p_t1, p_t2, p_t3, p_t4, p_t5]
	for idx: int in range(selected_five.size()):
		var origin_pt: Vector2 = points_five[idx]
		var rect := Rect2(origin_pt, Vector2.ZERO)
		for pt: Vector2 in points_five:
			rect = rect.expand(pt)
		# Candidate end corner opposite to origin_pt inside rect, grown slightly on the far side only.
		var far_x: float = rect.end.x + 8.0 if absf(origin_pt.x - rect.position.x) < 1.0 else (rect.position.x - 8.0 if absf(origin_pt.x - rect.end.x) < 1.0 else INF)
		var far_y: float = rect.end.y + 8.0 if absf(origin_pt.y - rect.position.y) < 1.0 else (rect.position.y - 8.0 if absf(origin_pt.y - rect.end.y) < 1.0 else INF)
		if is_finite(far_x) and is_finite(far_y):
			var test_box: Rect2 = SelectionBoxMath.normalize_rect(origin_pt, Vector2(far_x, far_y))
			if not test_box.has_point(p_t6):
				chosen_origin = selected_five[idx]
				chosen_end = Vector2(far_x, far_y)
				break

	# Fallback: start drag on tree_2 (or tree_3) covering as many as possible; if isometric diamond has no axis-aligned corner among the 5, shift-add the 5th.
	if chosen_origin != null:
		await _left_drag(view, _source_screen_point(view, chosen_origin), chosen_end, false)
	else:
		# Start drag on tree_2 across trees 1,2,4,5 and check box directly; verify 5th is strictly inside a clean box from tree_1 to tree_4.
		var bounds_5: Rect2 = _compute_screen_bounds(view, selected_five, 6.0)
		assert_false(bounds_5.has_point(p_t6), "Precondition: 6th tree sits outside the 5-tree bounding box")
		# Drag from tree_1 to opposite corner of bounds_5, then Shift-drag from tree_2 to top corner if needed.
		await _left_drag(view, p_t1, bounds_5.end, false)
		await _left_drag(view, p_t2, bounds_5.position, true)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	assert_eq(board.get_active_tasks().size(), 5, "Exactly 5 trees must be registered in active board")
	for t: ResourceSource in selected_five:
		assert_not_null(board.get_active_task_for_source(t), "Selected tree %s must have active task" % String(t.source_id))
	assert_null(board.get_active_task_for_source(tree_6), "6th tree outside selection must NOT have a task")
	assert_true(main.get_selection_manager().is_empty(), "Source box drag must not alter unit SelectionManager")

	# Run until all 5 marked trees finish harvesting and delivering physically.
	Engine.time_scale = 3.0
	for _i: int in range(9000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	for t: ResourceSource in selected_five:
		assert_eq(t.get_remaining_amount(), 0, "Selected tree %s must be fully harvested" % String(t.source_id))
	assert_eq(tree_6.get_remaining_amount(), 24, "6th unselected tree must remain 100% intact")
	assert_eq(inventory.get_physical_amount(&"wood") - stock_before, 10, "Exactly 10 wood delivered from the 5 selected trees")

	await _teardown_fixture(view)


func test_b4_multi_rock_box_selection_and_physical_stone_delivery() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var rock_1 := main.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	var rock_3 := main.get_node("TestMap/ResourceSources/StoneRock03") as ResourceSource
	var rock_4 := main.get_node("TestMap/ResourceSources/StoneRock04") as ResourceSource
	var rock_2 := main.get_node("TestMap/ResourceSources/StoneRock02") as ResourceSource

	var target_rocks: Array[ResourceSource] = [rock_1, rock_3, rock_4]
	for r: ResourceSource in target_rocks:
		r.configure(r.source_id, r.get_definition(), 1, 1, 2)
	var rock_2_before: int = rock_2.get_remaining_amount()
	var stock_before: int = inventory.get_physical_amount(&"stone")

	_focus_camera(main, Vector2(-8.0, 0.0))
	await wait_process_frames(2)

	# Drag from StoneRock01 covering StoneRock01, StoneRock03, StoneRock04 (excluding distant StoneRock02 and nearby FoodBush01).
	var bounds: Rect2 = _compute_screen_bounds(view, target_rocks, 10.0)
	await _left_drag(view, _source_screen_point(view, rock_1), bounds.end, false)
	await _left_drag(view, _source_screen_point(view, rock_3), bounds.position, true)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 3, "Three target rocks must be registered without mixing bushes")
	for r: ResourceSource in target_rocks:
		assert_not_null(board.get_active_task_for_source(r), "Rock %s registered" % String(r.source_id))
	assert_null(board.get_active_task_for_source(rock_2), "Unselected StoneRock02 must remain untouched")

	Engine.time_scale = 3.0
	for _i: int in range(9000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_eq(inventory.get_physical_amount(&"stone") - stock_before, 3, "All 3 stones delivered physically")
	assert_eq(rock_2.get_remaining_amount(), rock_2_before, "Unselected rock untouched")

	await _teardown_fixture(view)


func test_b5_multi_bush_box_selection_and_physical_food_delivery() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var bush_2 := main.get_node("TestMap/ResourceSources/FoodBush02") as ResourceSource
	var bush_3 := main.get_node("TestMap/ResourceSources/FoodBush03") as ResourceSource
	var bush_4 := main.get_node("TestMap/ResourceSources/FoodBush04") as ResourceSource
	var bush_1 := main.get_node("TestMap/ResourceSources/FoodBush01") as ResourceSource

	var target_bushes: Array[ResourceSource] = [bush_2, bush_3, bush_4]
	for b: ResourceSource in target_bushes:
		b.configure(b.source_id, b.get_definition(), 2, 2, 2)
	var bush_1_before: int = bush_1.get_remaining_amount()
	var stock_before: int = inventory.get_physical_amount(&"food")

	_focus_camera(main, Vector2(4.0, 9.5))
	await wait_process_frames(2)

	var bounds: Rect2 = _compute_screen_bounds(view, target_bushes, 10.0)
	await _left_drag(view, _source_screen_point(view, bush_2), bounds.end, false)
	await _left_drag(view, _source_screen_point(view, bush_4), bounds.position, true)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 3, "Three target bushes registered")
	assert_null(board.get_active_task_for_source(bush_1), "Unselected FoodBush01 untouched")

	Engine.time_scale = 3.0
	for _i: int in range(9000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_eq(inventory.get_physical_amount(&"food") - stock_before, 6, "All 6 food delivered physically")
	assert_eq(bush_1.get_remaining_amount(), bush_1_before, "Unselected FoodBush01 remained intact")

	await _teardown_fixture(view)


func test_b6_two_workers_distribute_across_distinct_sources_and_slot_release_signal() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var tree_3 := main.get_node("TestMap/ResourceSources/WoodTree03") as ResourceSource

	var group_res: Dictionary = board.register_gather_group([tree_1, tree_2, tree_3])
	assert_true(bool(group_res.get("ok", false)), "Group registration succeeds")
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var in_progress_units: Array[Unit] = []
	var pending_count: int = 0
	for t: WorkTask in board.get_active_tasks():
		if t.state == WorkTask.State.IN_PROGRESS and t.assigned_unit != null:
			in_progress_units.append(t.assigned_unit)
		elif t.state == WorkTask.State.PENDING_WORKERS:
			pending_count += 1

	assert_eq(in_progress_units.size(), 2, "Both leaders distributed across two distinct trees")
	if in_progress_units.size() == 2:
		assert_ne(in_progress_units[0], in_progress_units[1], "Each leader works a distinct source")
	assert_eq(pending_count, 1, "Third tree waits cleanly while both leaders are busy")

	# Verify ResourceSource.worker_slot_released wakes a task waiting on no_worker_slot (zero polling).
	for u: Unit in main.get_units():
		u.cancel_current_order()
	for t: WorkTask in board.get_active_tasks():
		board.close_task(t, WorkTask.State.CANCELLED, "test_reset")
	await wait_process_frames(2)

	var tree_4 := main.get_node("TestMap/ResourceSources/WoodTree04") as ResourceSource
	tree_4.max_simultaneous_workers = 1
	var blocker_node := Node.new()
	add_test_child(blocker_node)
	assert_true(tree_4.reserve_worker(blocker_node), "External holder fills the single slot on tree_4")

	var reg_4: Dictionary = board.register_gather_task(tree_4)
	var task_4: WorkTask = reg_4.get("task") as WorkTask
	await wait_process_frames(2)
	assert_not_null(task_4, "Task on saturated tree registered")
	if task_4 != null:
		assert_eq(task_4.state, WorkTask.State.PENDING_WORKERS, "Task waits while slot is full")
		assert_eq(task_4.last_reason, "no_worker_slot", "Wait reason reflects saturated slot")

	# Release the slot externally; worker_slot_released must wake dispatcher without any polling or click!
	tree_4.release_worker(blocker_node)
	await wait_process_frames(2)
	await wait_physics_frames(1)
	if task_4 != null:
		assert_eq(task_4.state, WorkTask.State.IN_PROGRESS, "Slot release event automatically dispatches waiting task")
		assert_not_null(task_4.assigned_unit, "Worker assigned on slot release")

	await _teardown_fixture(view)


func test_b7_continuity_worker_takes_next_marked_source_after_delivery() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var tree_5 := main.get_node("TestMap/ResourceSources/WoodTree05") as ResourceSource
	var tree_6 := main.get_node("TestMap/ResourceSources/WoodTree06") as ResourceSource
	var leader_a := _find_unit_by_id(main, &"leader_a")

	# Keep LeaderA busy on a far walk so a SINGLE leader (LeaderB) must sequentially complete all 3 marked trees.
	var hold_dest := Vector3(-20.0, 0.0, -20.0)
	leader_a.issue_order(MoveOrder.new(hold_dest, hold_dest, false))

	for t: ResourceSource in [tree_1, tree_2, tree_5]:
		t.configure(t.source_id, t.get_definition(), 2, 2, 2)
	var tree_6_before: int = tree_6.get_remaining_amount()
	var stock_before: int = inventory.get_physical_amount(&"wood")

	var res: Dictionary = board.register_gather_group([tree_1, tree_2, tree_5])
	assert_true(bool(res.get("ok", false)), "3-tree group registered")

	Engine.time_scale = 3.0
	for _i: int in range(9000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_eq(tree_1.get_remaining_amount(), 0, "Tree 1 finished")
	assert_eq(tree_2.get_remaining_amount(), 0, "Tree 2 finished via continuity")
	assert_eq(tree_5.get_remaining_amount(), 0, "Tree 5 finished via continuity")
	assert_eq(tree_6.get_remaining_amount(), tree_6_before, "Tree 6 outside selection untouched")
	assert_eq(inventory.get_physical_amount(&"wood") - stock_before, 6, "All 6 wood delivered physically")

	await _teardown_fixture(view)


func test_b8_manual_priority_interrupts_group_work_safely() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var tree_5 := main.get_node("TestMap/ResourceSources/WoodTree05") as ResourceSource
	var inventory := main.get_settlement_inventory()

	for t: ResourceSource in [tree_1, tree_2, tree_5]:
		t.configure(t.source_id, t.get_definition(), 4, 2, 2)
	var total_initial: int = 12
	var stock_before: int = inventory.get_physical_amount(&"wood")

	var res: Dictionary = board.register_gather_group([tree_1, tree_2, tree_5])
	assert_true(bool(res.get("ok", false)), "Group registered")
	await wait_process_frames(2)

	# Wait until one leader extracts wood into its backpack.
	var interrupted_leader: Unit = null
	var colleague: Unit = null
	Engine.time_scale = 3.0
	for _i: int in range(2400):
		for u: Unit in main.get_units():
			if u.get_carry_load().get_amount(&"wood") > 0:
				interrupted_leader = u
				break
		if interrupted_leader != null:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0

	assert_not_null(interrupted_leader, "A leader extracted wood before manual interruption")
	if interrupted_leader == null:
		await _teardown_fixture(view)
		return
	for u: Unit in main.get_units():
		if u != interrupted_leader:
			colleague = u
			break

	var carried_before: int = interrupted_leader.get_carry_load().get_amount(&"wood")
	var interrupted_task: WorkTask = null
	for t: WorkTask in board.get_active_tasks():
		if t.assigned_unit == interrupted_leader:
			interrupted_task = t
			break

	# Issue personal MoveOrder via CommandController.
	var manual_dest := Vector3(-1.5, 0.0, 5.0)
	main.get_selection_manager().select_single(interrupted_leader)
	assert_true(main.get_command_controller().command_at(PickResult.from_ground(manual_dest, Vector3.UP)), "Personal move accepted")
	await wait_process_frames(2)

	assert_true(interrupted_leader.get_current_order() is MoveOrder, "Personal move not overwritten")
	assert_eq(interrupted_leader.get_carry_load().get_amount(&"wood"), carried_before, "Carried wood preserved")
	assert_true(interrupted_leader.get_carry_load().validate_provenance(), "Provenance valid after interruption")
	if interrupted_task != null:
		assert_true(interrupted_task.excluded_unit_ids.has(interrupted_leader.get_instance_id()), "Interrupted task marks leader excluded")
	assert_not_null(colleague.get_current_order(), "Colleague continues working in the group")

	var delivered: int = inventory.get_physical_amount(&"wood") - stock_before
	var remaining: int = tree_1.get_remaining_amount() + tree_2.get_remaining_amount() + tree_5.get_remaining_amount()
	var total_carried: int = interrupted_leader.get_carry_load().get_amount(&"wood") + colleague.get_carry_load().get_amount(&"wood")
	assert_eq(total_initial - remaining, delivered + total_carried, "Exact wood conservation after group manual interruption")

	await _teardown_fixture(view)


func test_b9_invalid_depleted_removed_and_unreachable_sources_do_not_block_others() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var sources_root := main.get_test_map().get_resource_sources_root()

	# 1. Depleted tree
	tree_1.configure(tree_1.source_id, tree_1.get_definition(), 2, 2, 2)
	tree_1.extract(2)

	# 2. Valid tree
	tree_2.configure(tree_2.source_id, tree_2.get_definition(), 2, 2, 2)

	# 3. Unreachable tree inside ClosedEnclosure
	var blocked_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	blocked_tree.name = "B9BlockedTree"
	blocked_tree.source_id = &"b9_blocked_tree"
	blocked_tree.position = Vector3(-16.0, 0.0, 12.0)
	sources_root.add_child(blocked_tree)

	# 4. Tree that will be removed shortly after registration
	var removed_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	removed_tree.name = "B9RemovedTree"
	removed_tree.source_id = &"b9_removed_tree"
	removed_tree.position = Vector3(13.0, 0.0, 5.5)
	sources_root.add_child(removed_tree)
	await wait_physics_frames(2)

	var stock_before: int = inventory.get_physical_amount(&"wood")
	var group_res: Dictionary = board.register_gather_group([tree_1, blocked_tree, removed_tree, tree_2])
	assert_true(bool(group_res.get("ok", false)), "Group with mixed valid/invalid sources succeeds for valid entries")
	assert_null(board.get_active_task_for_source(tree_1), "Depleted tree rejected from group")

	removed_tree.queue_free()
	Engine.time_scale = 3.0
	for _i: int in range(6000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 0, "Invalid/removed/unreachable tasks all resolved cleanly")
	assert_eq(tree_2.get_remaining_amount(), 0, "Valid tree_2 still completed despite invalid peers")
	assert_eq(inventory.get_physical_amount(&"wood") - stock_before, 2, "Wood from valid tree_2 delivered physically")

	await _teardown_fixture(view)


func test_b10_idempotency_across_click_shift_and_box_selection() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var tree_5 := main.get_node("TestMap/ResourceSources/WoodTree05") as ResourceSource

	_focus_camera(main, Vector2(10.0, 2.0))
	await wait_process_frames(2)

	# 1. Click tree_1
	await _left_click(view, _source_screen_point(view, tree_1), false)
	await wait_process_frames(2)
	await wait_physics_frames(1)
	var t1: WorkTask = board.get_active_task_for_source(tree_1)
	assert_not_null(t1, "Initial tree_1 task created")
	if t1 == null or t1.assigned_unit == null:
		await _teardown_fixture(view)
		return
	var original_worker: Unit = t1.assigned_unit
	var original_order: UnitOrder = original_worker.get_current_order()
	var original_rev: int = original_worker.get_order_revision()

	# 2. Shift+click tree_1 again and tree_5
	await _left_click(view, _source_screen_point(view, tree_1), true)
	await _left_click(view, _source_screen_point(view, tree_5), true)
	await wait_process_frames(2)

	# 3. Group registration / box covering [tree_1, tree_5, tree_2]
	var group_res: Dictionary = board.register_gather_group([tree_1, tree_5, tree_2])
	assert_true(bool(group_res.get("ok", false)), "Group registration overlapping existing tasks succeeds")
	assert_eq((group_res.get("created_tasks", []) as Array).size(), 1, "Only newly added tree_2 creates a task")
	assert_eq((group_res.get("existing_tasks", []) as Array).size(), 2, "Already-registered tree_1 and tree_5 reused")
	assert_eq(board.get_active_tasks().size(), 3, "Total active tasks equals unique source count")
	assert_eq(board.get_all_tasks().size(), 3, "Zero duplicate task records created")
	assert_eq(original_worker.get_current_order(), original_order, "Active order on tree_1 never replaced")
	assert_eq(original_worker.get_order_revision(), original_rev, "Worker order revision never bumped")

	await _teardown_fixture(view)


func test_b11_ground_drag_preserves_rts_unit_selection_camera_right_click_and_placement() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var cam := view.get_camera_3d()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource

	# 1. Drag starting on open ground selects both leaders via SelectionManager (not resources).
	var p_a: Vector2 = cam.unproject_position(leader_a.global_position + Vector3(0.0, 0.95, 0.0))
	var p_b: Vector2 = cam.unproject_position(leader_b.global_position + Vector3(0.0, 0.95, 0.0))
	var rect := Rect2(p_a, Vector2.ZERO).expand(p_b).grow(36.0)
	await _left_drag(view, rect.position, rect.end, false)
	await wait_process_frames(2)

	assert_eq(main.get_selection_manager().get_selection_count(), 2, "Ground-origin drag selects both leaders")
	assert_eq(board.get_active_tasks().size(), 0, "Ground-origin drag does not register resource tasks")

	# 2. Right-click ground move still works.
	await _right_click(view, cam.unproject_position(Vector3(0.0, 0.0, 5.5)))
	await wait_process_frames(1)
	assert_true(leader_a.get_current_order() is MoveOrder, "Right-click ground move works")
	leader_a.cancel_current_order()
	leader_b.cancel_current_order()

	# 3. Cancelling a source drag with Esc does NOT create a new task and does NOT cancel confirmed tasks.
	_focus_camera(main, Vector2(10.0, 2.0))
	await wait_process_frames(1)
	await _left_click(view, _source_screen_point(view, tree_1), false)
	await wait_process_frames(2)
	assert_eq(board.get_active_tasks().size(), 1, "Confirmed task active before cancelled drag")

	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var start_drag := _source_screen_point(view, tree_2)
	var m_start := InputEventMouseMotion.new()
	m_start.position = start_drag
	m_start.global_position = start_drag
	view.push_input(m_start, false)
	var down := InputEventMouseButton.new()
	down.position = start_drag
	down.global_position = start_drag
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	view.push_input(down, false)
	await wait_process_frames(1)
	var drag_mm := InputEventMouseMotion.new()
	drag_mm.position = start_drag + Vector2(60.0, 40.0)
	drag_mm.global_position = start_drag + Vector2(60.0, 40.0)
	view.push_input(drag_mm, false)
	await wait_process_frames(1)
	await _press_esc(view)
	var up := InputEventMouseButton.new()
	up.position = start_drag + Vector2(60.0, 40.0)
	up.global_position = start_drag + Vector2(60.0, 40.0)
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	view.push_input(up, false)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 1, "Cancelled source drag adds 0 tasks and preserves confirmed task")
	assert_not_null(board.get_active_task_for_source(tree_1), "Confirmed task untouched after Esc cancel")

	# 4. PlacementController priority preserved when active.
	main.get_placement_controller().start_placement(SHELTER_DEF)
	assert_true(main.get_placement_controller().is_placement_active(), "PlacementController activates normally")
	await _left_click(view, _source_screen_point(view, tree_2), false)
	await wait_process_frames(2)
	assert_null(board.get_active_task_for_source(tree_2), "Clicking tree during active building placement does not register gather task")
	main.get_placement_controller().cancel_placement()

	await _teardown_fixture(view)


func test_b12_blocked_reauthorization_never_auto_dispatches_on_new_worker_or_events() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var dispatcher := main.get_node("CommunityTaskDispatcher") as CommunityTaskDispatcher
	var rock_1 := main.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	var reg: Dictionary = board.register_gather_task(rock_1)
	var blocked_task: WorkTask = reg.get("task") as WorkTask
	await wait_process_frames(2)
	await wait_physics_frames(1)
	assert_not_null(blocked_task, "Stone task registered")
	if blocked_task == null or blocked_task.assigned_unit == null:
		await _teardown_fixture(view)
		return

	# Exclude both existing leaders via manual moves.
	var u1: Unit = blocked_task.assigned_unit
	var u2: Unit = leader_b if u1 == leader_a else leader_a
	u1.issue_order(MoveOrder.new(u1.global_position + Vector3(0.8, 0.0, 0.8), u1.global_position + Vector3(0.8, 0.0, 0.8), false))
	await wait_process_frames(3)
	await wait_physics_frames(1)
	assert_eq(blocked_task.assigned_unit, u2, "Second leader took over before exclusion")

	u2.issue_order(MoveOrder.new(u2.global_position + Vector3(-0.8, 0.0, 0.8), u2.global_position + Vector3(-0.8, 0.0, 0.8), false))
	Engine.time_scale = 3.0
	for _i: int in range(600):
		if leader_a.get_current_order() == null and leader_b.get_current_order() == null:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(3)

	assert_eq(blocked_task.state, WorkTask.State.BLOCKED_REAUTHORIZATION, "Task entered BLOCKED_REAUTHORIZATION")

	# Trigger multiple dispatcher events:
	# Event 1: Leader finishes another activity (a short move).
	leader_a.issue_order(MoveOrder.new(leader_a.global_position + Vector3(0.6, 0.0, 0.0), leader_a.global_position + Vector3(0.6, 0.0, 0.0), false))
	Engine.time_scale = 3.0
	for _i: int in range(300):
		if leader_a.get_current_order() == null:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(3)
	assert_eq(blocked_task.state, WorkTask.State.BLOCKED_REAUTHORIZATION, "Finishing another order must NOT unblock BLOCKED_REAUTHORIZATION")
	assert_null(blocked_task.assigned_unit, "No worker assigned after another order finishes")

	# Event 2: Spawn a brand-new eligible worker into Units (child_entered_tree + provenance admission).
	var new_unit := UNIT_SCENE.instantiate() as Unit
	new_unit.name = "WorkerExtraB12"
	var def := CharacterDefinition.new()
	def.character_id = &"worker_extra_b12"
	def.display_name = "Extra B12"
	new_unit.definition = def
	new_unit.position = Vector3(-4.0, 0.0, 0.0)
	var units_root := main.get_node("Units") as Node3D
	units_root.add_child(new_unit)
	new_unit.set_world_navigation(main.get_test_map().get_navigation())
	var admit_res: Dictionary = ReservedWithdrawalCoordinator.admit_empty_provenance_units(
		[new_unit], units_root, main.get_camp_storage_zone(), main.get_settlement_inventory(), main.get_construction_manager().get_region_id()
	)
	assert_true(bool(admit_res.get("ok", false)), "New extra worker admitted to region economy")

	# Event 3: Explicit dispatcher request + another task registering/closing.
	dispatcher.request_dispatch()
	var reg_other: Dictionary = board.register_gather_task(tree_1)
	await wait_process_frames(3)
	await wait_physics_frames(2)

	assert_eq(blocked_task.state, WorkTask.State.BLOCKED_REAUTHORIZATION, "Spawning a new worker and other board events must NOT silently unblock BLOCKED_REAUTHORIZATION")
	assert_null(blocked_task.assigned_unit, "Blocked task remains unassigned even with a new non-excluded worker present")
	assert_null(new_unit.get_current_order() if board.get_active_task_for_source(tree_1).assigned_unit != new_unit else null, "New worker is never assigned to blocked rock_1")
	if new_unit.get_current_order() is GatherResourceOrder:
		assert_ne((new_unit.get_current_order() as GatherResourceOrder).source, rock_1, "New worker must never gather blocked rock_1")
	assert_true(bool(reg_other.get("ok", false)), "Other valid tasks continue functioning normally")

	await _teardown_fixture(view)


func test_b13_economic_conservation_across_concurrent_multi_resource_groups() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()

	var t1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var t2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	var r1 := main.get_node("TestMap/ResourceSources/StoneRock01") as ResourceSource
	var r3 := main.get_node("TestMap/ResourceSources/StoneRock03") as ResourceSource
	var b2 := main.get_node("TestMap/ResourceSources/FoodBush02") as ResourceSource
	var b3 := main.get_node("TestMap/ResourceSources/FoodBush03") as ResourceSource

	t1.configure(t1.source_id, t1.get_definition(), 2, 2, 2)
	t2.configure(t2.source_id, t2.get_definition(), 2, 2, 2)
	r1.configure(r1.source_id, r1.get_definition(), 1, 1, 2)
	r3.configure(r3.source_id, r3.get_definition(), 1, 1, 2)
	b2.configure(b2.source_id, b2.get_definition(), 2, 2, 2)
	b3.configure(b3.source_id, b3.get_definition(), 2, 2, 2)

	var w0: int = inventory.get_physical_amount(&"wood")
	var s0: int = inventory.get_physical_amount(&"stone")
	var f0: int = inventory.get_physical_amount(&"food")

	board.register_gather_group([t1, t2])
	board.register_gather_group([r1, r3])
	board.register_gather_group([b2, b3])

	Engine.time_scale = 3.0
	for _i: int in range(12000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	var carried_w: int = 0
	var carried_s: int = 0
	var carried_f: int = 0
	for u: Unit in main.get_units():
		carried_w += u.get_carry_load().get_amount(&"wood")
		carried_s += u.get_carry_load().get_amount(&"stone")
		carried_f += u.get_carry_load().get_amount(&"food")
		assert_true(u.get_carry_load().validate_provenance(), "Provenance conserved across concurrent multi-resource groups")

	assert_eq(4 - (t1.get_remaining_amount() + t2.get_remaining_amount()), (inventory.get_physical_amount(&"wood") - w0) + carried_w, "Exact wood conservation")
	assert_eq(2 - (r1.get_remaining_amount() + r3.get_remaining_amount()), (inventory.get_physical_amount(&"stone") - s0) + carried_s, "Exact stone conservation")
	assert_eq(4 - (b2.get_remaining_amount() + b3.get_remaining_amount()), (inventory.get_physical_amount(&"food") - f0) + carried_f, "Exact food conservation")
	assert_eq(inventory.get_physical_amount(&"wood") - w0, 4, "All wood delivered")
	assert_eq(inventory.get_physical_amount(&"stone") - s0, 2, "All stone delivered")
	assert_eq(inventory.get_physical_amount(&"food") - f0, 4, "All food delivered")

	await _teardown_fixture(view)


func test_b14_lifecycle_cleanup_signals_highlights_and_scene_exit() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := main.get_node("TestMap/ResourceSources/WoodTree01") as ResourceSource
	var sources_root := main.get_test_map().get_resource_sources_root()

	tree_1.configure(tree_1.source_id, tree_1.get_definition(), 2, 2, 2)
	var temp_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	temp_tree.name = "B14TempTree"
	temp_tree.source_id = &"b14_temp_tree"
	temp_tree.position = Vector3(11.0, 0.0, 6.0)
	sources_root.add_child(temp_tree)
	await wait_physics_frames(2)

	board.register_gather_group([tree_1, temp_tree])
	await wait_process_frames(2)
	assert_eq(_count_highlight_children(tree_1), 1, "Highlight attached to active tree_1")
	assert_eq(_count_highlight_children(temp_tree), 1, "Highlight attached to active temp_tree")

	# Remove temp_tree -> task closes and highlight cleans up without errors.
	temp_tree.queue_free()
	await wait_process_frames(2)

	# Complete tree_1 -> highlight removed cleanly on completion.
	Engine.time_scale = 3.0
	for _i: int in range(6000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_eq(_count_highlight_children(tree_1), 0, "Highlight removed cleanly after task completion")
	assert_eq(board.get_active_tasks().size(), 0, "Zero active tasks remain")

	# Clean exit with an active task still registered must disconnect signals with 0 errors/warnings.
	var tree_2 := main.get_node("TestMap/ResourceSources/WoodTree02") as ResourceSource
	board.register_gather_task(tree_2)
	await wait_process_frames(1)
	assert_eq(_count_highlight_children(tree_2), 1, "Highlight attached before teardown")

	await _teardown_fixture(view)
