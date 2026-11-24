extends TestCase
## Integration suite for R-03A: Playable multi-source selection and automatic
## community gathering directly inside the real MainScene (res://src/main/main.tscn).
## Covers contracts A01-A20 (19 core tests; A09+A10 combined in sequential wait->resume test)
## plus R-03A R1 corrective/coverage suites (F01, F02, T01, T02, T03, T04, R01).

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const D2_SANDBOX_SCENE: PackedScene = preload("res://tests/visual/ui_1_d2_2_sandbox.tscn")
const RUX_1_SCENE: PackedScene = preload("res://tests/visual/rux_1_auto_gather.tscn")
const RUX_2A_SCENE: PackedScene = preload("res://tests/visual/rux_2a_auto_resources.tscn")
const RUX_2B_SCENE: PackedScene = preload("res://tests/visual/rux_2b_multi_source_selection.tscn")
const UX_1_SCENE: PackedScene = preload("res://tests/visual/ux_1_tree.tscn")
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


func _fixture(scene_res: PackedScene = MAIN_SCENE) -> SubViewport:
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
	assert_true(main.get_test_map().get_navigation().is_navigation_ready(), "Fixture: WorldNavigation ready")
	await wait_process_frames(3)
	var rig := main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false
	return view


func _teardown_fixture(view: SubViewport) -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(view):
		var main := view.get_child(0) as MainScene if view.get_child_count() > 0 else null
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


func _find_source_by_id(main: MainScene, source_id: StringName) -> ResourceSource:
	var world := main.get_world_3d()
	for node: Node in main.get_tree().get_nodes_in_group(ResourceSource.GROUP_RESOURCE_SOURCES):
		if node is ResourceSource:
			var src := node as ResourceSource
			if is_instance_valid(src) and src.is_inside_tree() and src.get_world_3d() == world and src.source_id == source_id:
				return src
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


func _count_nodes_of_script(root: Node, script_path: String) -> int:
	var total: int = 0
	var sc: Script = root.get_script() as Script
	if sc != null and sc.resource_path == script_path:
		total += 1
	for child: Node in root.get_children():
		total += _count_nodes_of_script(child, script_path)
	return total


func _count_highlight_children(source: ResourceSource) -> int:
	var count: int = 0
	for child: Node in source.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("AutoGatherTaskRing_"):
			count += 1
	return count


func test_a01_main_scene_real_community_integration_and_flags() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene

	assert_true(main.use_provenance_economy, "A01: MainScene must keep use_provenance_economy = true")
	assert_true(main.automatic_cancellation_recovery, "A01: MainScene must keep automatic_cancellation_recovery = true")
	assert_false(main.use_d2_2_hud, "A01: MainScene must keep use_d2_2_hud = false until R-05B")

	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var dispatcher := main.get_node_or_null("CommunityTaskDispatcher") as CommunityTaskDispatcher
	var feedback := main.get_node_or_null("UiLayer/AutonomousGatherFeedback") as AutonomousGatherFeedback
	var input_ctrl := main.get_input_controller()

	assert_not_null(board, "A01: MainScene must compose CommunityWorkBoard")
	assert_not_null(dispatcher, "A01: MainScene must compose CommunityTaskDispatcher")
	assert_not_null(feedback, "A01: MainScene must compose UiLayer/AutonomousGatherFeedback")
	assert_true(input_ctrl is AutonomousGatherInput, "A01: MainScene RtsInputController must specialize AutonomousGatherInput")

	assert_eq(_count_nodes_of_script(main, "res://src/rts/community_work_board.gd"), 1, "A01: Exactly one CommunityWorkBoard")
	assert_eq(_count_nodes_of_script(main, "res://src/rts/community_task_dispatcher.gd"), 1, "A01: Exactly one CommunityTaskDispatcher")
	assert_eq(_count_nodes_of_script(main, "res://src/rts/autonomous_gather_input.gd"), 1, "A01: Exactly one AutonomousGatherInput authority")

	if board != null and dispatcher != null:
		assert_false(board.is_processing(), "A01: Board zero _process polling")
		assert_false(board.is_physics_processing(), "A01: Board zero _physics_process polling")
		assert_false(dispatcher.is_processing(), "A01: Dispatcher zero _process polling")
		assert_false(dispatcher.is_physics_processing(), "A01: Dispatcher zero _physics_process polling")

	if input_ctrl is AutonomousGatherInput:
		var agi := input_ctrl as AutonomousGatherInput
		assert_true(agi.multi_source_enabled, "A01: MainScene enables multi-source community selection")
		assert_true(agi.supported_resource_ids.has("wood"), "A01: Supports wood")
		assert_true(agi.supported_resource_ids.has("stone"), "A01: Supports stone")
		assert_true(agi.supported_resource_ids.has("food"), "A01: Supports food")

	# Playable grove provides 6 trees, 4 rocks, 4 bushes while TestMap keeps its 6 canonical sources intact.
	assert_eq(main.get_test_map().get_resource_sources().size(), 6, "A01: TestMap canonical 6-source contract preserved")
	for sid: StringName in [&"wood_tree_01", &"wood_tree_02", &"wood_tree_03", &"wood_tree_04", &"wood_tree_05", &"wood_tree_06"]:
		assert_not_null(_find_source_by_id(main, sid), "A01: Playable MainScene exposes tree %s" % String(sid))
	for sid: StringName in [&"stone_rock_01", &"stone_rock_02", &"stone_rock_03", &"stone_rock_04"]:
		assert_not_null(_find_source_by_id(main, sid), "A01: Playable MainScene exposes rock %s" % String(sid))
	for sid: StringName in [&"food_bush_01", &"food_bush_02", &"food_bush_03", &"food_bush_04"]:
		assert_not_null(_find_source_by_id(main, sid), "A01: Playable MainScene exposes bush %s" % String(sid))

	await _teardown_fixture(view)


func test_a02_single_click_registers_dispatches_and_is_idempotent() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := _find_source_by_id(main, &"wood_tree_01")

	assert_not_null(board, "A02: Board present in MainScene")
	assert_not_null(tree_1, "A02: WoodTree01 present")
	if board == null or tree_1 == null:
		await _teardown_fixture(view)
		return

	_focus_camera(main, Vector2(9.5, 0.0))
	await wait_process_frames(1)
	var pt := _source_screen_point(view, tree_1)
	await _left_click(view, pt, false)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var task := board.get_active_task_for_source(tree_1)
	assert_not_null(task, "A02: Single left-click without unit selection registers community task")
	assert_true(main.get_selection_manager().is_empty(), "A02: Does not overwrite empty RTS selection")
	if task == null:
		await _teardown_fixture(view)
		return
	assert_not_null(task.assigned_unit, "A02: Single click must dispatch an idle worker immediately")
	if task.assigned_unit == null:
		await _teardown_fixture(view)
		return

	assert_eq(task.state, WorkTask.State.IN_PROGRESS, "A02: Auto-dispatches free leader immediately")
	var worker := task.assigned_unit
	var initial_order := worker.get_current_order()
	var initial_rev := worker.get_order_revision()

	for _i: int in range(3):
		await _left_click(view, pt, false)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 1, "A02: Repeated click does not duplicate active task")
	assert_eq(board.get_all_tasks().size(), 1, "A02: Repeated click does not duplicate task history")
	assert_eq(worker.get_current_order(), initial_order, "A02: Repeated click does not restart active order")
	assert_eq(worker.get_order_revision(), initial_rev, "A02: Repeated click does not bump order revision")

	await _teardown_fixture(view)


func test_a03_shift_click_homogeneous_idempotent_and_rejects_mixed_types() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var feedback := main.get_node_or_null("UiLayer/AutonomousGatherFeedback") as AutonomousGatherFeedback
	var tree_1 := _find_source_by_id(main, &"wood_tree_01")
	var tree_2 := _find_source_by_id(main, &"wood_tree_02")
	var tree_5 := _find_source_by_id(main, &"wood_tree_05")
	var rock_1 := _find_source_by_id(main, &"stone_rock_01")

	assert_not_null(board, "A03: Board present")
	assert_not_null(feedback, "A03: Feedback banner present")
	assert_not_null(tree_1, "A03: WoodTree01 present")
	assert_not_null(tree_2, "A03: WoodTree02 present")
	assert_not_null(tree_5, "A03: WoodTree05 present")
	assert_not_null(rock_1, "A03: StoneRock01 present")
	if board == null or feedback == null or tree_1 == null or tree_2 == null or tree_5 == null or rock_1 == null:
		await _teardown_fixture(view)
		return

	_focus_camera(main, Vector2(9.0, 2.0))
	await wait_process_frames(1)

	await _left_click(view, _source_screen_point(view, tree_1), false)
	await wait_process_frames(2)
	var t1 := board.get_active_task_for_source(tree_1)
	assert_not_null(t1, "A03: First tree registered")
	if t1 == null:
		await _teardown_fixture(view)
		return

	await _left_click(view, _source_screen_point(view, tree_2), true)
	await _left_click(view, _source_screen_point(view, tree_5), true)
	await wait_process_frames(2)

	var t2 := board.get_active_task_for_source(tree_2)
	var t5 := board.get_active_task_for_source(tree_5)
	assert_not_null(t2, "A03: Shift adds second tree")
	assert_not_null(t5, "A03: Shift adds third tree")
	assert_eq(board.get_active_tasks().size(), 3, "A03: Exactly 3 trees active")
	if t2 != null and t5 != null:
		assert_eq(t2.group_id, t1.group_id, "A03: Same homogeneous group_id")
		assert_eq(t5.group_id, t1.group_id, "A03: Third tree joins same group_id")

	# Non-destructive repeated Shift+click
	await _left_click(view, _source_screen_point(view, tree_2), true)
	await wait_process_frames(2)
	assert_eq(board.get_active_tasks().size(), 3, "A03: Repeated Shift+click is non-destructive")
	if feedback != null:
		assert_false(feedback.last_message.is_empty(), "A03: Feedback informs already selected")

	# Mixed type rejected under Shift
	_focus_camera(main, Vector2(-6.0, 0.0))
	await wait_process_frames(1)
	await _left_click(view, _source_screen_point(view, rock_1), true)
	await wait_process_frames(2)
	assert_null(board.get_active_task_for_source(rock_1), "A03: Mixed Shift+click on stone rejected")
	assert_eq(board.get_active_tasks().size(), 3, "A03: Previous wood group preserved")

	await _teardown_fixture(view)


func test_a04_box_select_five_of_six_trees_preserves_sixth_through_completion() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var t3 := _find_source_by_id(main, &"wood_tree_03")
	var t4 := _find_source_by_id(main, &"wood_tree_04")
	var t5 := _find_source_by_id(main, &"wood_tree_05")
	var t6 := _find_source_by_id(main, &"wood_tree_06")

	assert_not_null(board, "A04: Board present")
	assert_not_null(t1, "A04: WoodTree01 present")
	assert_not_null(t2, "A04: WoodTree02 present")
	assert_not_null(t3, "A04: WoodTree03 present")
	assert_not_null(t4, "A04: WoodTree04 present")
	assert_not_null(t5, "A04: WoodTree05 present")
	assert_not_null(t6, "A04: 6th tree present in MainScene")
	if board == null or t1 == null or t2 == null or t3 == null or t4 == null or t5 == null or t6 == null:
		await _teardown_fixture(view)
		return

	var selected_five: Array[ResourceSource] = [t1, t2, t3, t4, t5]
	for t: ResourceSource in selected_five:
		t.configure(t.source_id, t.get_definition(), 2, 2, 2)
	t6.configure(t6.source_id, t6.get_definition(), 24, 2, 2)
	var stock_before := inventory.get_physical_amount(&"wood")

	_focus_camera(main, Vector2(12.5, 1.0))
	await wait_process_frames(2)

	var p_t1 := _source_screen_point(view, t1)
	var p_t2 := _source_screen_point(view, t2)
	var p_t5 := _source_screen_point(view, t5)
	var p_t6 := _source_screen_point(view, t6)
	var drag_end := Vector2(p_t2.x - 24.0, p_t1.y - 24.0)
	assert_false(SelectionBoxMath.normalize_rect(p_t5, drag_end).has_point(p_t6), "A04: 6th tree strictly outside box")

	await _left_drag(view, p_t5, drag_end, false)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	assert_eq(board.get_active_tasks().size(), 5, "A04: Exactly 5 marked trees registered")
	for t: ResourceSource in selected_five:
		assert_not_null(board.get_active_task_for_source(t), "A04: Marked tree %s registered" % String(t.source_id))
	assert_null(board.get_active_task_for_source(t6), "A04: 6th tree NOT registered")
	assert_eq(t6.get_active_worker_count(), 0, "A04: 6th tree has zero workers")

	Engine.time_scale = 3.0
	for _i: int in range(9000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(3)

	assert_true(board.get_active_tasks().is_empty(), "A04: All 5 marked tree tasks completed without timeout")
	for t: ResourceSource in selected_five:
		assert_eq(t.get_remaining_amount(), 0, "A04: Selected tree %s fully harvested" % String(t.source_id))
	assert_eq(t6.get_remaining_amount(), 24, "A04: 6th unselected tree remains 100% intact after completion")
	assert_null(board.get_active_task_for_source(t6), "A04: No spontaneous expansion to 6th tree")
	assert_eq(inventory.get_physical_amount(&"wood") - stock_before, 10, "A04: Exactly 10 wood delivered physically")

	await _teardown_fixture(view)


func test_a05_multi_stone_extraction_weight_and_delivery() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	var r3 := _find_source_by_id(main, &"stone_rock_03")
	var r4 := _find_source_by_id(main, &"stone_rock_04")
	var r2 := _find_source_by_id(main, &"stone_rock_02")

	assert_not_null(board, "A05: Board present")
	assert_not_null(r1, "A05: StoneRock01 present")
	assert_not_null(r2, "A05: StoneRock02 present")
	assert_not_null(r3, "A05: StoneRock03 present")
	assert_not_null(r4, "A05: StoneRock04 present")
	if board == null or r1 == null or r2 == null or r3 == null or r4 == null:
		await _teardown_fixture(view)
		return

	var targets: Array[ResourceSource] = [r1, r3, r4]
	for r: ResourceSource in targets:
		r.configure(r.source_id, r.get_definition(), 1, 1, 2)
	var r2_before := r2.get_remaining_amount()
	var stock_before := inventory.get_physical_amount(&"stone")

	_focus_camera(main, Vector2(-13.8, 2.1))
	await wait_process_frames(2)
	var bounds := _compute_screen_bounds(view, targets, 18.0)
	var p_r1 := _source_screen_point(view, r1)
	var drag_end := bounds.position
	await _left_drag(view, p_r1, drag_end, false)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 3, "A05: Three target rocks marked")
	assert_null(board.get_active_task_for_source(r2), "A05: Unselected rock untouched")

	var saw_stone_weight: bool = false
	Engine.time_scale = 3.0
	for _i: int in range(9000):
		for u: Unit in main.get_units():
			var amt := u.get_carry_load().get_amount(&"stone")
			if amt > 0 and u.get_carry_load().get_current_weight() == amt * 3:
				saw_stone_weight = true
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_true(board.get_active_tasks().is_empty(), "A05: All 3 rock tasks completed without timeout")
	assert_true(saw_stone_weight, "A05: Stone carried with physical weight 3 per unit")
	assert_eq(inventory.get_physical_amount(&"stone") - stock_before, 3, "A05: All 3 stones delivered physically")
	assert_eq(r2.get_remaining_amount(), r2_before, "A05: Unselected StoneRock02 intact")

	await _teardown_fixture(view)


func test_a06_multi_food_bushes_extraction_and_delivery() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var b2 := _find_source_by_id(main, &"food_bush_02")
	var b3 := _find_source_by_id(main, &"food_bush_03")
	var b4 := _find_source_by_id(main, &"food_bush_04")
	var b1 := _find_source_by_id(main, &"food_bush_01")

	assert_not_null(board, "A06: Board present")
	assert_not_null(b1, "A06: FoodBush01 present")
	assert_not_null(b2, "A06: FoodBush02 present")
	assert_not_null(b3, "A06: FoodBush03 present")
	assert_not_null(b4, "A06: FoodBush04 present")
	if board == null or b1 == null or b2 == null or b3 == null or b4 == null:
		await _teardown_fixture(view)
		return

	var targets: Array[ResourceSource] = [b2, b3, b4]
	for b: ResourceSource in targets:
		b.configure(b.source_id, b.get_definition(), 2, 2, 2)
	var b1_before := b1.get_remaining_amount()
	var stock_before := inventory.get_physical_amount(&"food")

	_focus_camera(main, Vector2(4.0, 9.5))
	await wait_process_frames(2)
	var bounds := _compute_screen_bounds(view, targets, 10.0)
	await _left_drag(view, _source_screen_point(view, b2), bounds.end, false)
	await _left_drag(view, _source_screen_point(view, b4), bounds.position, true)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 3, "A06: Three target bushes marked")
	assert_null(board.get_active_task_for_source(b1), "A06: Unselected bush untouched")

	Engine.time_scale = 3.0
	for _i: int in range(9000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_true(board.get_active_tasks().is_empty(), "A06: All 3 bush tasks completed without timeout")
	assert_eq(inventory.get_physical_amount(&"food") - stock_before, 6, "A06: All 6 food delivered physically")
	assert_eq(b1.get_remaining_amount(), b1_before, "A06: Unselected FoodBush01 intact")

	await _teardown_fixture(view)


func test_a07_ground_box_crossing_sources_preserves_classic_rts_selection() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var cam := view.get_camera_3d()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var tree_1 := _find_source_by_id(main, &"wood_tree_01")

	assert_not_null(board, "A07: Board present")
	assert_not_null(leader_a, "A07: LeaderA present")
	assert_not_null(leader_b, "A07: LeaderB present")
	assert_not_null(tree_1, "A07: WoodTree01 present")
	if board == null or leader_a == null or leader_b == null or tree_1 == null:
		await _teardown_fixture(view)
		return

	# Start drag strictly on open ground (0,0,0.5 camp clearing) and drag across both leaders AND WoodTree01.
	var p_ground := cam.unproject_position(Vector3(-4.0, 0.0, 4.5))
	var p_t1 := _source_screen_point(view, tree_1)
	var end_pt := Vector2(p_t1.x + 24.0, p_t1.y - 24.0)
	await _left_drag(view, p_ground, end_pt, false)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 0, "A07: Ground-origin drag crossing sources creates 0 community tasks")
	assert_true(main.get_selection_manager().get_selection_count() >= 1, "A07: Ground-origin drag selects units")

	# Right-click ground move works cleanly for selected units.
	await _right_click(view, cam.unproject_position(Vector3(0.0, 0.0, 5.5)))
	await wait_process_frames(1)
	var any_moving: bool = (leader_a.get_current_order() is MoveOrder) or (leader_b.get_current_order() is MoveOrder)
	assert_true(any_moving, "A07: Right-click ground MoveOrder preserved")

	await _teardown_fixture(view)


func test_a08_distribution_busy_protection_and_slot_release_event() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var t3 := _find_source_by_id(main, &"wood_tree_03")
	var t4 := _find_source_by_id(main, &"wood_tree_04")

	assert_not_null(board, "A08: Board present")
	assert_not_null(t1, "A08: WoodTree01 present")
	assert_not_null(t2, "A08: WoodTree02 present")
	assert_not_null(t3, "A08: WoodTree03 present")
	assert_not_null(t4, "A08: WoodTree04 present")
	if board == null or t1 == null or t2 == null or t3 == null or t4 == null:
		await _teardown_fixture(view)
		return

	board.register_gather_group([t1, t2, t3])
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var assigned_units: Array[Unit] = []
	var waiting_count: int = 0
	for task: WorkTask in board.get_active_tasks():
		if task.state == WorkTask.State.IN_PROGRESS and task.assigned_unit != null:
			assigned_units.append(task.assigned_unit)
		elif task.state == WorkTask.State.PENDING_WORKERS:
			waiting_count += 1

	assert_eq(assigned_units.size(), 2, "A08: Two free leaders spread across two distinct sources")
	if assigned_units.size() == 2:
		assert_ne(assigned_units[0], assigned_units[1], "A08: Distinct leaders per source")
	assert_eq(waiting_count, 1, "A08: Third source waits cleanly")

	# Reset and verify worker_slot_released wakes waiting task without polling.
	for u: Unit in main.get_units():
		u.cancel_current_order()
	for task: WorkTask in board.get_active_tasks():
		board.close_task(task, WorkTask.State.CANCELLED, "reset")
	await wait_process_frames(2)

	t4.max_simultaneous_workers = 1
	var holder := Node.new()
	add_test_child(holder)
	assert_true(t4.reserve_worker(holder), "A08: Holder reserves single slot")
	var reg := board.register_gather_task(t4)
	var task_4 := reg.get("task") as WorkTask
	await wait_process_frames(2)
	assert_not_null(task_4, "A08: Task registered on saturated source")
	if task_4 != null:
		assert_eq(task_4.state, WorkTask.State.PENDING_WORKERS, "A08: Waits while slot saturated")
		assert_eq(task_4.last_reason, "no_worker_slot", "A08: Wait reason is no_worker_slot")

	t4.release_worker(holder)
	await wait_process_frames(2)
	await wait_physics_frames(1)
	if task_4 != null:
		assert_eq(task_4.state, WorkTask.State.IN_PROGRESS, "A08: Slot release wakes waiting task")

	await _teardown_fixture(view)


func test_a09_a10_continuity_and_waiting_without_workers() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var t6 := _find_source_by_id(main, &"wood_tree_06")
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	assert_not_null(board, "A09/A10: Board present")
	assert_not_null(t1, "A09/A10: WoodTree01 present")
	assert_not_null(t2, "A09/A10: WoodTree02 present")
	assert_not_null(t6, "A09/A10: WoodTree06 present")
	assert_not_null(leader_a, "A09/A10: LeaderA present")
	assert_not_null(leader_b, "A09/A10: LeaderB present")
	if board == null or t1 == null or t2 == null or t6 == null or leader_a == null or leader_b == null:
		await _teardown_fixture(view)
		return

	t1.configure(t1.source_id, t1.get_definition(), 2, 2, 2)
	t2.configure(t2.source_id, t2.get_definition(), 2, 2, 2)
	var t6_before := t6.get_remaining_amount()
	var stock_before := inventory.get_physical_amount(&"wood")

	# Make both leaders busy first (A10).
	leader_a.issue_order(MoveOrder.new(Vector3(-18.0, 0.0, -18.0), Vector3(-18.0, 0.0, -18.0), false))
	var short_b := MoveOrder.new(leader_b.global_position + Vector3(1.2, 0.0, 0.0), leader_b.global_position + Vector3(1.2, 0.0, 0.0), false)
	leader_b.issue_order(short_b)
	await wait_physics_frames(1)

	board.register_gather_group([t1, t2])
	await wait_process_frames(2)

	assert_eq(board.get_pending_tasks().size(), 2, "A10: Both tasks wait while all workers busy")
	assert_eq(leader_b.get_current_order(), short_b, "A10: Existing manual order not overwritten")

	# Let LeaderB finish short move and sequentially complete BOTH marked trees (A09).
	Engine.time_scale = 3.0
	for _i: int in range(9000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_true(board.get_active_tasks().is_empty(), "A09: Both tasks completed without timeout")
	assert_eq(t1.get_remaining_amount(), 0, "A09: Tree 1 harvested")
	assert_eq(t2.get_remaining_amount(), 0, "A09: Tree 2 harvested via continuity")
	assert_eq(t6.get_remaining_amount(), t6_before, "A09: Unmarked tree 6 preserved")
	assert_eq(inventory.get_physical_amount(&"wood") - stock_before, 4, "A09: All 4 wood delivered physically")

	await _teardown_fixture(view)


func test_a11_personal_order_interrupts_preserving_cargo_provenance_and_slot() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := _find_source_by_id(main, &"wood_tree_01")
	var inventory := main.get_settlement_inventory()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	assert_not_null(board, "A11: Board present")
	assert_not_null(tree_1, "A11: WoodTree01 present")
	assert_not_null(leader_a, "A11: LeaderA present")
	assert_not_null(leader_b, "A11: LeaderB present")
	if board == null or tree_1 == null or leader_a == null or leader_b == null:
		await _teardown_fixture(view)
		return

	var initial_wood := tree_1.get_remaining_amount()
	var stock_before := inventory.get_physical_amount(&"wood")

	# Hold LeaderA busy so LeaderB takes tree_1 deterministically.
	leader_a.issue_order(MoveOrder.new(Vector3(-12.0, 0.0, 12.0), Vector3(-12.0, 0.0, 12.0), false))
	await wait_physics_frames(1)

	var reg := board.register_gather_task(tree_1)
	var task := reg.get("task") as WorkTask
	await wait_process_frames(2)
	assert_not_null(task, "A11: Task registered")
	if task == null:
		await _teardown_fixture(view)
		return

	Engine.time_scale = 3.0
	for _i: int in range(2000):
		if leader_b.get_carry_load().get_amount(&"wood") > 0:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0

	var carried_before := leader_b.get_carry_load().get_amount(&"wood")
	assert_true(carried_before > 0, "A11: LeaderB extracted wood before interruption")

	# Keep LeaderA busy while checking LeaderB doesn't silently resume.
	leader_a.issue_order(MoveOrder.new(Vector3(-14.0, 0.0, 4.0), Vector3(-14.0, 0.0, 4.0), false))

	main.get_selection_manager().select_single(leader_b)
	var dest := leader_b.global_position + Vector3(-2.0, 0.0, 2.0)
	assert_true(main.get_command_controller().command_at(PickResult.from_ground(dest, Vector3.UP)), "A11: Personal MoveOrder accepted")
	await wait_process_frames(2)

	assert_true(leader_b.get_current_order() is MoveOrder, "A11: Personal MoveOrder active")
	assert_false(tree_1.is_worker_reserved(leader_b), "A11: Tree reservation released")
	assert_eq(leader_b.get_carry_load().get_amount(&"wood"), carried_before, "A11: Backpack wood preserved")
	assert_true(leader_b.get_carry_load().validate_provenance(), "A11: Provenance valid after interruption")

	Engine.time_scale = 3.0
	for _i: int in range(600):
		if leader_b.get_current_order() == null:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(3)
	assert_null(leader_b.get_current_order(), "A11: No improper automatic resume after personal move")

	# Free colleague LeaderA -> takes over waiting task cleanly.
	leader_a.cancel_current_order()
	await wait_process_frames(3)
	await wait_physics_frames(1)
	assert_eq(task.assigned_unit, leader_a, "A11: Non-excluded colleague continues task")
	var delivered := inventory.get_physical_amount(&"wood") - stock_before
	var total_carried := leader_a.get_carry_load().get_amount(&"wood") + leader_b.get_carry_load().get_amount(&"wood")
	assert_eq(initial_wood - tree_1.get_remaining_amount(), delivered + total_carried, "A11: Exact wood conservation")

	await _teardown_fixture(view)


func test_a12_economic_conservation_across_concurrent_groups() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	var b2 := _find_source_by_id(main, &"food_bush_02")

	assert_not_null(board, "A12: Board present")
	assert_not_null(t1, "A12: WoodTree01 present")
	assert_not_null(r1, "A12: StoneRock01 present")
	assert_not_null(b2, "A12: FoodBush02 present")
	if board == null or t1 == null or r1 == null or b2 == null:
		await _teardown_fixture(view)
		return

	t1.configure(t1.source_id, t1.get_definition(), 2, 2, 2)
	r1.configure(r1.source_id, r1.get_definition(), 1, 1, 2)
	b2.configure(b2.source_id, b2.get_definition(), 2, 2, 2)
	var w0 := inventory.get_physical_amount(&"wood")
	var s0 := inventory.get_physical_amount(&"stone")
	var f0 := inventory.get_physical_amount(&"food")

	board.register_gather_task(t1)
	board.register_gather_task(r1)
	board.register_gather_task(b2)
	# Zero premature stock credit on registration.
	assert_eq(inventory.get_physical_amount(&"wood"), w0, "A12: Zero premature wood credit")
	assert_eq(inventory.get_physical_amount(&"stone"), s0, "A12: Zero premature stone credit")
	assert_eq(inventory.get_physical_amount(&"food"), f0, "A12: Zero premature food credit")

	Engine.time_scale = 3.0
	for _i: int in range(9000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_true(board.get_active_tasks().is_empty(), "A12: All 3 concurrent resource tasks completed without timeout")
	for u: Unit in main.get_units():
		assert_true(u.get_carry_load().validate_provenance(), "A12: Valid provenance on every unit")
	assert_eq(inventory.get_physical_amount(&"wood") - w0, 2, "A12: Wood conserved")
	assert_eq(inventory.get_physical_amount(&"stone") - s0, 1, "A12: Stone conserved")
	assert_eq(inventory.get_physical_amount(&"food") - f0, 2, "A12: Food conserved")

	await _teardown_fixture(view)


func test_a13_regional_and_world3d_isolation() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var sources_root := main.get_test_map().get_resource_sources_root()

	assert_not_null(board, "A13: Board present")
	assert_not_null(sources_root, "A13: ResourceSources root present")
	if board == null or sources_root == null:
		await _teardown_fixture(view)
		return

	# 1. Source tagged with incompatible region_id must be rejected by board.
	var foreign_region_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	foreign_region_tree.name = "ForeignRegionTreeA13"
	foreign_region_tree.source_id = &"foreign_region_tree_a13"
	foreign_region_tree.position = Vector3(5.0, 0.0, -3.0)
	foreign_region_tree.set_meta(&"region_id", &"other_region")
	sources_root.add_child(foreign_region_tree)
	await wait_physics_frames(1)

	var reg_foreign := board.register_gather_task(foreign_region_tree)
	assert_false(bool(reg_foreign.get("ok", false)), "A13: Foreign-region source must be rejected by board")
	assert_eq(board.get_active_tasks().size(), 0, "A13: Zero active tasks from foreign region")

	# 2. Source in a completely separate World3D must NOT be picked up by box selection in main's viewport.
	var other_view := SubViewport.new()
	other_view.own_world_3d = true
	other_view.size = Vector2i(320, 240)
	add_test_child(other_view)
	var other_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	other_tree.name = "OtherWorldTreeA13"
	other_tree.source_id = &"other_world_tree_a13"
	other_tree.position = Vector3(9.5, 0.0, -1.5) # Same coordinates as WoodTree01!
	other_view.add_child(other_tree)
	await wait_physics_frames(2)

	var t1 := _find_source_by_id(main, &"wood_tree_01")
	assert_not_null(t1, "A13: WoodTree01 present")
	if t1 == null:
		other_view.queue_free()
		await _teardown_fixture(view)
		return
	_focus_camera(main, Vector2(9.5, -1.5))
	await wait_process_frames(2)
	var p1 := _source_screen_point(view, t1)
	await _left_drag(view, p1, p1 + Vector2(30.0, 30.0), false)
	await wait_process_frames(2)

	assert_null(board.get_active_task_for_source(other_tree), "A13: Source in another World3D must NEVER be registered by box drag")
	assert_eq(other_tree.get_remaining_amount(), other_tree.initial_amount, "A13: Foreign World3D source untouched")

	# 3. Unadmitted unit from foreign region must never receive community work.
	var foreign_unit := UNIT_SCENE.instantiate() as Unit
	foreign_unit.name = "ForeignUnitA13"
	var udef := CharacterDefinition.new()
	udef.character_id = &"foreign_unit_a13"
	udef.display_name = "Foreign A13"
	foreign_unit.definition = udef
	foreign_unit.position = Vector3(8.5, 0.0, -1.5)
	foreign_unit.set_meta(&"region_id", &"other_region")
	main.get_node("Units").add_child(foreign_unit)
	foreign_unit.set_world_navigation(main.get_test_map().get_navigation())
	await wait_process_frames(3)
	assert_null(foreign_unit.get_current_order(), "A13: Foreign-region unadmitted unit never dispatched")

	other_view.queue_free()
	await _teardown_fixture(view)


func test_a14_concurrency_with_construction_and_reserved_cargo() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := _find_source_by_id(main, &"wood_tree_01")
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	assert_not_null(board, "A14: Board present")
	assert_not_null(tree_1, "A14: WoodTree01 present")
	assert_not_null(leader_a, "A14: LeaderA present")
	assert_not_null(leader_b, "A14: LeaderB present")
	if board == null or tree_1 == null or leader_a == null or leader_b == null:
		await _teardown_fixture(view)
		return

	# Deposit real camp stock and place an active construction site concurrently.
	var inv := main.get_settlement_inventory()
	assert_true(inv.deposit(&"wood", 12), "A14: Deposit wood for real site creation")
	assert_true(inv.deposit(&"stone", 6), "A14: Deposit stone for real site creation")
	var site_res := main.get_construction_manager().try_create_site_from_placement(SHELTER_DEF, Vector3(-4.0, 0.0, -10.0))
	assert_true(bool(site_res.get("ok", false)), "A14: Real ConstructionSite created concurrently")
	assert_true(site_res.get("site") is ConstructionSite, "A14: Created site instance valid")

	# Give closer LeaderB a SITE_RESERVED provenance lot -> must be skipped safely.
	var b_load := leader_b.get_carry_load()
	var plan := b_load._prepare_provenance_add(&"op_r03a_a14", &"lot_r03a_a14", &"wood", 2, 2, CarryProvenanceLedger.SITE_RESERVED, &"site_a14", 1)
	assert_true(bool(plan.get("ok", false)), "A14: SITE_RESERVED lot prepared")
	b_load._provenance_busy = true
	b_load._provenance_applying = true
	assert_true(b_load._apply_prepared_provenance_add(plan), "A14: SITE_RESERVED lot applied")
	b_load._provenance_applying = false
	b_load._provenance_busy = false

	board.register_gather_task(tree_1)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var task := board.get_active_task_for_source(tree_1)
	assert_not_null(task, "A14: Gather task registered alongside active construction")
	if task != null:
		assert_eq(task.assigned_unit, leader_a, "A14: Eligible LeaderA dispatched; LeaderB with SITE_RESERVED cargo skipped")
	assert_null(leader_b.get_current_order(), "A14: LeaderB with reserved cargo untouched")
	assert_true(b_load.validate_provenance(), "A14: Reserved cargo provenance intact")

	await _teardown_fixture(view)


func test_a15_invalid_depleted_removed_and_unreachable_do_not_block_peers() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var inventory := main.get_settlement_inventory()
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var sources_root := main.get_test_map().get_resource_sources_root()

	assert_not_null(board, "A15: Board present")
	assert_not_null(t1, "A15: WoodTree01 present")
	assert_not_null(t2, "A15: WoodTree02 present")
	assert_not_null(sources_root, "A15: ResourceSources root present")
	if board == null or t1 == null or t2 == null or sources_root == null:
		await _teardown_fixture(view)
		return

	t1.configure(t1.source_id, t1.get_definition(), 2, 2, 2)
	t1.extract(2) # depleted
	t2.configure(t2.source_id, t2.get_definition(), 2, 2, 2)

	var blocked_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	blocked_tree.name = "A15BlockedTree"
	blocked_tree.source_id = &"a15_blocked_tree"
	blocked_tree.position = Vector3(-16.0, 0.0, 12.0)
	sources_root.add_child(blocked_tree)

	var removed_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	removed_tree.name = "A15RemovedTree"
	removed_tree.source_id = &"a15_removed_tree"
	removed_tree.position = Vector3(13.0, 0.0, 5.5)
	sources_root.add_child(removed_tree)
	await wait_physics_frames(2)

	var stock_before := inventory.get_physical_amount(&"wood")
	var group_res := board.register_gather_group([t1, blocked_tree, removed_tree, t2])
	assert_true(bool(group_res.get("ok", false)), "A15: Group accepts valid peers")
	assert_null(board.get_active_task_for_source(t1), "A15: Depleted tree rejected")

	removed_tree.queue_free()
	Engine.time_scale = 3.0
	for _i: int in range(6000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 0, "A15: All invalid/valid tasks resolved")
	assert_eq(t2.get_remaining_amount(), 0, "A15: Valid tree completed despite invalid peers")
	assert_eq(inventory.get_physical_amount(&"wood") - stock_before, 2, "A15: Valid wood delivered")

	await _teardown_fixture(view)


func test_a16_placement_priority_ui_consumption_and_esc_drag_cancel() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")

	assert_not_null(board, "A16: Board present")
	assert_not_null(t1, "A16: WoodTree01 present")
	assert_not_null(t2, "A16: WoodTree02 present")
	if board == null or t1 == null or t2 == null:
		await _teardown_fixture(view)
		return

	_focus_camera(main, Vector2(10.0, 2.0))
	await wait_process_frames(2)

	# 1. Active placement preview blocks accidental community source marking.
	main.get_placement_controller().start_placement(SHELTER_DEF)
	assert_true(main.get_placement_controller().is_placement_active(), "A16: Placement active")
	await _left_click(view, _source_screen_point(view, t1), false)
	await wait_process_frames(2)
	assert_null(board.get_active_task_for_source(t1), "A16: Click during placement does not register gather task")
	main.get_placement_controller().cancel_placement()

	# 2. Register confirmed task on t1, then cancel an unconfirmed drag starting on t2 with Esc.
	await _left_click(view, _source_screen_point(view, t1), false)
	await wait_process_frames(2)
	assert_eq(board.get_active_tasks().size(), 1, "A16: Confirmed task on t1 registered")

	var start_drag := _source_screen_point(view, t2)
	var m0 := InputEventMouseMotion.new()
	m0.position = start_drag
	m0.global_position = start_drag
	view.push_input(m0, false)
	var down := InputEventMouseButton.new()
	down.position = start_drag
	down.global_position = start_drag
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	view.push_input(down, false)
	await wait_process_frames(1)
	var mm := InputEventMouseMotion.new()
	mm.position = start_drag + Vector2(60.0, 36.0)
	mm.global_position = start_drag + Vector2(60.0, 36.0)
	view.push_input(mm, false)
	await wait_process_frames(1)
	await _press_esc(view)
	var up := InputEventMouseButton.new()
	up.position = start_drag + Vector2(60.0, 36.0)
	up.global_position = start_drag + Vector2(60.0, 36.0)
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	view.push_input(up, false)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 1, "A16: Esc cancels drag only and preserves confirmed task")
	assert_not_null(board.get_active_task_for_source(t1), "A16: Confirmed task on t1 intact")
	assert_null(board.get_active_task_for_source(t2), "A16: Cancelled drag on t2 registered 0 tasks")

	# 3. Opaque UI panel blocking a tree prevents click-through task registration.
	var blocker := Panel.new()
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	var pt2 := _source_screen_point(view, t2)
	blocker.position = pt2 - Vector2(30.0, 30.0)
	blocker.size = Vector2(60.0, 60.0)
	main.get_node("UiLayer").add_child(blocker)
	await wait_process_frames(1)
	await _left_click(view, pt2, false)
	await wait_process_frames(2)
	assert_null(board.get_active_task_for_source(t2), "A16: UI-consumed click does not register task beneath")

	await _teardown_fixture(view)


func test_a17_blocked_reauthorization_remains_inert() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var dispatcher := main.get_node_or_null("CommunityTaskDispatcher") as CommunityTaskDispatcher
	var rock_1 := _find_source_by_id(main, &"stone_rock_01")
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")

	assert_not_null(board, "A17: Board present")
	assert_not_null(dispatcher, "A17: Dispatcher present")
	assert_not_null(rock_1, "A17: StoneRock01 present")
	assert_not_null(leader_a, "A17: LeaderA present")
	assert_not_null(leader_b, "A17: LeaderB present")
	if board == null or dispatcher == null or rock_1 == null or leader_a == null or leader_b == null:
		await _teardown_fixture(view)
		return

	var reg := board.register_gather_task(rock_1)
	var task := reg.get("task") as WorkTask
	await wait_process_frames(2)
	await wait_physics_frames(1)
	if task == null or task.assigned_unit == null:
		assert_true(false, "A17: Initial task assigned")
		await _teardown_fixture(view)
		return

	var u1 := task.assigned_unit
	var u2 := leader_b if u1 == leader_a else leader_a
	u1.issue_order(MoveOrder.new(u1.global_position + Vector3(0.8, 0.0, 0.8), u1.global_position + Vector3(0.8, 0.0, 0.8), false))
	await wait_process_frames(3)
	await wait_physics_frames(1)
	u2.issue_order(MoveOrder.new(u2.global_position + Vector3(-0.8, 0.0, 0.8), u2.global_position + Vector3(-0.8, 0.0, 0.8), false))

	Engine.time_scale = 3.0
	for _i: int in range(600):
		if leader_a.get_current_order() == null and leader_b.get_current_order() == null:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(3)

	assert_null(leader_a.get_current_order(), "A17: LeaderA personal move completed without timeout")
	assert_null(leader_b.get_current_order(), "A17: LeaderB personal move completed without timeout")
	assert_eq(task.state, WorkTask.State.BLOCKED_REAUTHORIZATION, "A17: Task enters BLOCKED_REAUTHORIZATION")

	# Spawn a brand-new admitted worker -> blocked task must remain inert.
	var extra := UNIT_SCENE.instantiate() as Unit
	extra.name = "ExtraWorkerA17"
	var def := CharacterDefinition.new()
	def.character_id = &"extra_worker_a17"
	def.display_name = "Extra A17"
	extra.definition = def
	extra.position = Vector3(-4.0, 0.0, 0.0)
	main.get_node("Units").add_child(extra)
	extra.set_world_navigation(main.get_test_map().get_navigation())
	ReservedWithdrawalCoordinator.admit_empty_provenance_units(
		[extra], main.get_node("Units"), main.get_camp_storage_zone(), main.get_settlement_inventory(), main.get_construction_manager().get_region_id()
	)
	dispatcher.request_dispatch()
	await wait_process_frames(3)

	assert_eq(task.state, WorkTask.State.BLOCKED_REAUTHORIZATION, "A17: New worker does not silently unblock task")
	assert_null(task.assigned_unit, "A17: Blocked task stays unassigned")
	assert_null(extra.get_current_order(), "A17: New worker not assigned to blocked task")

	await _teardown_fixture(view)


func test_a18_lifecycle_worker_removal_and_controlled_teardown() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var tree_1 := _find_source_by_id(main, &"wood_tree_01")

	assert_not_null(board, "A18: Board present")
	assert_not_null(tree_1, "A18: WoodTree01 present")
	if board == null or tree_1 == null:
		await _teardown_fixture(view)
		return

	var world := main.get_world_3d()
	var reg := board.register_gather_task(tree_1)
	var task := reg.get("task") as WorkTask
	await wait_process_frames(2)
	await wait_physics_frames(1)
	assert_not_null(task, "A18: Active task registered")
	assert_eq(_count_highlight_children(tree_1), 1, "A18: Highlight attached to active source")
	if task == null:
		await _teardown_fixture(view)
		return
	assert_not_null(task.assigned_unit, "A18: Task must dispatch an active worker before removal test")
	if task.assigned_unit == null:
		await _teardown_fixture(view)
		return

	# Remove assigned worker while task is active -> remaining leader picks up safely.
	var first_worker := task.assigned_unit
	first_worker.cancel_current_order()
	first_worker.get_parent().remove_child(first_worker)
	first_worker.queue_free()
	await wait_process_frames(3)
	await wait_physics_frames(1)
	assert_not_null(task.assigned_unit, "A18: Surviving worker reassigned after worker exit")
	assert_ne(task.assigned_unit, first_worker, "A18: Reassigned to surviving distinct worker")

	# Cancel active orders so controlled teardown preflight succeeds with empty backpacks.
	for u: Unit in main.get_units():
		u.cancel_current_order()
	await wait_process_frames(2)

	var preflight := main.preflight_economic_teardown()
	assert_true(bool(preflight.get("ok", false)), "A18: Controlled teardown preflight succeeds")
	var teardown := main.request_controlled_teardown()
	assert_true(bool(teardown.get("ok", false)), "A18: Controlled teardown succeeds cleanly with active board tasks")
	# Capture domain release synchronously before queue_free() destroys main.
	var release_res := main.get_last_domain_release_result()
	assert_true(bool(release_res.get("ok", false)), "A18: Regional domain release reported ok=true")
	await wait_process_frames(3)
	assert_false(world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META), "A18: World3D regional authority metadata cleared after release")
	view.queue_free()
	await wait_process_frames(2)


func test_a19_invalid_economic_admission_blocks_community_dispatch() -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(1280, 720)
	add_test_child(view)

	# Instantiate MainScene and corrupt unit carry load before _ready so provenance admission fails cleanly.
	var main := MAIN_SCENE.instantiate() as MainScene
	var leader_a := main.get_node("Units/LeaderA") as Unit
	var wood_def: ResourceDefinition = load("res://data/resources/wood.tres") as ResourceDefinition
	leader_a.get_carry_load().add_units(wood_def, 1) # Non-empty pre-admission carry triggers admission failure!
	view.add_child(main)

	for _i: int in range(120):
		if main.get_test_map().get_navigation().is_navigation_ready():
			break
		await wait_physics_frames(1)
	await wait_process_frames(3)

	var board := main.get_node_or_null("CommunityWorkBoard") as CommunityWorkBoard
	var feedback := main.get_node_or_null("UiLayer/AutonomousGatherFeedback") as AutonomousGatherFeedback
	var tree_1 := _find_source_by_id(main, &"wood_tree_01")
	var inventory := main.get_settlement_inventory()
	var stock_before := inventory.get_physical_amount(&"wood")

	assert_not_null(board, "A19: Board present even when admission blocked")
	assert_not_null(feedback, "A19: Feedback banner present")
	assert_not_null(tree_1, "A19: WoodTree01 present")
	assert_false(main.get_economy_admission_reason().is_empty(), "A19: Economic admission must be blocked")
	if board == null or feedback == null or tree_1 == null:
		await _teardown_fixture(view)
		return

	_focus_camera(main, Vector2(9.5, -1.5))
	await wait_process_frames(1)
	await _left_click(view, _source_screen_point(view, tree_1), false)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 0, "A19: Click while economy admission failed must not register tasks")
	for u: Unit in main.get_units():
		assert_null(u.get_current_order(), "A19: No worker dispatched under failed economic admission")
	assert_eq(inventory.get_physical_amount(&"wood"), stock_before, "A19: Zero resources created")
	if feedback != null:
		assert_false(feedback.last_message.is_empty(), "A19: Honest feedback exposed on blocked admission")

	# Direct board registration also must NOT dispatch workers while admission is blocked.
	board.register_gather_task(tree_1)
	await wait_process_frames(3)
	for u: Unit in main.get_units():
		assert_null(u.get_current_order(), "A19: Dispatcher refuses to dispatch under failed admission")

	await _teardown_fixture(view)


func test_a20_d2_2_sandbox_and_inherited_rux_scenes_compatibility() -> void:
	# 1. D2.2 Sandbox preserves D2.2 HUD and single community nodes.
	var view_d2 := await _fixture(D2_SANDBOX_SCENE)
	var main_d2 := view_d2.get_child(0) as MainScene
	assert_true(main_d2.use_d2_2_hud, "A20: D2.2 sandbox keeps use_d2_2_hud = true")
	assert_not_null(main_d2.get_d2_hud_root(), "A20: D2.2 HUD root instantiated")
	assert_eq(_count_nodes_of_script(main_d2, "res://src/rts/community_work_board.gd"), 1, "A20: D2.2 sandbox has single board")
	assert_eq(_count_nodes_of_script(main_d2, "res://src/rts/community_task_dispatcher.gd"), 1, "A20: D2.2 sandbox has single dispatcher")
	await _teardown_fixture(view_d2)

	# 2. RUX-1 inherited scene keeps wood-only, single-source scope without duplicate nodes.
	var view_r1 := await _fixture(RUX_1_SCENE)
	var main_r1 := view_r1.get_child(0) as MainScene
	var agi_r1 := main_r1.get_input_controller() as AutonomousGatherInput
	assert_not_null(agi_r1, "A20: RUX-1 uses AutonomousGatherInput")
	if agi_r1 != null:
		assert_false(agi_r1.multi_source_enabled, "A20: RUX-1 preserves multi_source_enabled = false")
		assert_eq(agi_r1.supported_resource_ids, PackedStringArray(["wood"]), "A20: RUX-1 preserves wood-only scope")
	assert_eq(_count_nodes_of_script(main_r1, "res://src/rts/community_work_board.gd"), 1, "A20: RUX-1 has zero duplicate boards")
	assert_eq(_count_nodes_of_script(main_r1, "res://src/rts/community_task_dispatcher.gd"), 1, "A20: RUX-1 has zero duplicate dispatchers")
	await _teardown_fixture(view_r1)

	# 3. RUX-2A inherited scene keeps single-source 3-resource scope without duplicate nodes.
	var view_r2a := await _fixture(RUX_2A_SCENE)
	var main_r2a := view_r2a.get_child(0) as MainScene
	var agi_r2a := main_r2a.get_input_controller() as AutonomousGatherInput
	assert_not_null(agi_r2a, "A20: RUX-2A uses AutonomousGatherInput")
	if agi_r2a != null:
		assert_false(agi_r2a.multi_source_enabled, "A20: RUX-2A preserves multi_source_enabled = false")
	assert_eq(_count_nodes_of_script(main_r2a, "res://src/rts/community_work_board.gd"), 1, "A20: RUX-2A has zero duplicate boards")
	await _teardown_fixture(view_r2a)

	# 4. RUX-2B inherited scene has zero duplicate community nodes and zero duplicate WoodTree03.
	var view_r2b := await _fixture(RUX_2B_SCENE)
	var main_r2b := view_r2b.get_child(0) as MainScene
	assert_eq(_count_nodes_of_script(main_r2b, "res://src/rts/community_work_board.gd"), 1, "A20: RUX-2B has zero duplicate boards")
	assert_eq(_count_nodes_of_script(main_r2b, "res://src/rts/community_task_dispatcher.gd"), 1, "A20: RUX-2B has zero duplicate dispatchers")
	var wood_tree_03_count: int = 0
	var world_r2b := main_r2b.get_world_3d()
	for node: Node in main_r2b.get_tree().get_nodes_in_group(ResourceSource.GROUP_RESOURCE_SOURCES):
		if node is ResourceSource and (node as ResourceSource).get_world_3d() == world_r2b and (node as ResourceSource).source_id == &"wood_tree_03":
			wood_tree_03_count += 1
	assert_eq(wood_tree_03_count, 1, "A20: RUX-2B has zero duplicate WoodTree03 instances")
	await _teardown_fixture(view_r2b)

	# 5. UX-1 inherited scene continues instantiating cleanly with TreeWorkInput.
	var view_ux1 := await _fixture(UX_1_SCENE)
	var main_ux1 := view_ux1.get_child(0) as MainScene
	assert_false(main_ux1.get_input_controller() is AutonomousGatherInput, "A20: UX-1 keeps TreeWorkInput override")
	await _teardown_fixture(view_ux1)
# ==============================================================================
# R-03A R1 — Corrective & Coverage Suites (F01, F02, T02, T03, T04, R01)
# ==============================================================================

func _make_static_wall(wall_name: String, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = CollisionLayers.MASK_OBSTACLES
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = pos
	return body


func test_r1_f01_placement_connectivity_all_14_sources_and_badges() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var test_map := main.get_test_map()
	var placement := main.get_placement_controller()
	var nav := test_map.get_navigation()
	assert_not_null(placement, "F01: PlacementController present")
	if placement == null:
		await _teardown_fixture(view)
		return

	# 1. Context from real MainScene must include all 14 unique playable sources while preserving 6 canonical sources.
	assert_eq(test_map.get_resource_sources().size(), 6, "F01: Canonical TestMap.get_resource_sources() stays 6")
	var ctx := placement.build_validation_context()
	assert_eq(ctx.resource_sources.size(), 14, "F01: Placement ValidationContext must enumerate all 14 playable sources")
	var seen_ids: Dictionary = {}
	var counts: Dictionary = {&"wood": 0, &"stone": 0, &"food": 0}
	for src: ResourceSource in ctx.resource_sources:
		assert_false(seen_ids.has(src.get_instance_id()), "F01: No duplicate source instance in context")
		seen_ids[src.get_instance_id()] = true
		counts[src.get_resource_id()] = int(counts.get(src.get_resource_id(), 0)) + 1
	assert_eq(int(counts[&"wood"]), 6, "F01: Context includes all 6 wood sources")
	assert_eq(int(counts[&"stone"]), 4, "F01: Context includes all 4 stone sources")
	assert_eq(int(counts[&"food"]), 4, "F01: Context includes all 4 food sources")

	# 2. Sources from another region or another World3D must be excluded from context.
	var foreign_src := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	foreign_src.name = "ForeignRegionSourceF01"
	foreign_src.source_id = &"foreign_region_source_f01"
	foreign_src.position = Vector3(-22.0, 0.0, 22.0)
	foreign_src.set_meta(&"region_id", &"other_region")
	test_map.add_child(foreign_src)

	var other_view := SubViewport.new()
	other_view.own_world_3d = true
	other_view.size = Vector2i(256, 256)
	add_test_child(other_view)
	var other_world_src := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	other_world_src.name = "OtherWorldSourceF01"
	other_world_src.source_id = &"other_world_source_f01"
	other_world_src.position = Vector3(20.0, 0.0, 10.0)
	other_view.add_child(other_world_src)
	await wait_physics_frames(2)

	var ctx_scoped := placement.build_validation_context()
	assert_eq(ctx_scoped.resource_sources.size(), 14, "F01: Foreign region and other World3D sources excluded")
	assert_false(ctx_scoped.resource_sources.has(foreign_src), "F01: Foreign-region source excluded")
	assert_false(ctx_scoped.resource_sources.has(other_world_src), "F01: Other-World3D source excluded")
	foreign_src.queue_free()
	other_view.queue_free()
	await wait_process_frames(2)

	# 3. Dynamic connectivity proof on an ADDITIONAL source (FoodBush04 at (1.5, 0.0, 11.5)):
	#    Enclose FoodBush04 on 3 sides (N, W, E) leaving a single south entrance (~4.3m inner width);
	#    placing SHELTER_DEF (4x4m) directly across the south entrance seals FoodBush04 without overlapping it or walls.
	var b4 := _find_source_by_id(main, &"food_bush_04")
	assert_not_null(b4, "F01: Additional source FoodBush04 present")
	if b4 == null:
		await _teardown_fixture(view)
		return

	var alcove_root := Node3D.new()
	alcove_root.name = "F01AlcoveWalls"
	var p4: Vector3 = b4.global_position
	# Inner clear pocket: x in [p4.x - 2.15, p4.x + 2.15], z >= p4.z - 1.35; open south (+Z).
	alcove_root.add_child(_make_static_wall("WallN", Vector3(p4.x, 1.5, p4.z - 1.6), Vector3(5.3, 3.0, 0.5)))
	alcove_root.add_child(_make_static_wall("WallW", Vector3(p4.x - 2.4, 1.5, p4.z + 2.7), Vector3(0.5, 3.0, 9.1)))
	alcove_root.add_child(_make_static_wall("WallE", Vector3(p4.x + 2.4, 1.5, p4.z + 2.7), Vector3(0.5, 3.0, 9.1)))
	test_map.add_child(alcove_root)
	await wait_physics_frames(2)
	nav.request_rebake()
	for _i: int in range(120):
		if nav.is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(nav.is_navigation_ready(), "F01: NavMesh rebaked with FoodBush04 alcove")

	# Verify FoodBush04 is initially reachable from camp through the south entrance.
	var camp_pos: Vector3 = main.get_camp_storage_zone().get_anchor_position()
	var pre_reach := nav.find_path(camp_pos, p4 + Vector3(0.0, 0.0, 1.2))
	assert_true(pre_reach.is_ok(), "F01: FoodBush04 initially reachable through south alcove entrance")

	# Candidate shelter sealing the south mouth at (p4.x, 0, p4.z + 4.4) -> footprint x in [p4.x-2.0, p4.x+2.0], z in [p4.z+2.4, p4.z+6.4].
	# Clears all walls by 0.15m and FoodBush04 by 2.4m (zero overlap), yet leaves < 2*agent_radius gap so FoodBush04 loses all access!
	var blocking_pos := Vector3(p4.x, 0.0, p4.z + 4.4)
	var validator := placement.get_validator()
	var ctx_alcove := placement.build_validation_context()
	var confirm_blocked := validator.validate_confirm(SHELTER_DEF, blocking_pos, ctx_alcove)
	assert_false(confirm_blocked.valid, "F01: Sealing access to additional source FoodBush04 must be rejected")
	assert_eq(confirm_blocked.reason_code, PlacementValidator.REASON_CORRIDOR_BLOCKED, "F01: Rejection reason must be corridor_blocked")

	# Legitimate open placement away from entrance must remain valid.
	var legitimate_pos := Vector3(-4.0, 0.0, -10.5)
	var confirm_ok := validator.validate_confirm(SHELTER_DEF, legitimate_pos, ctx_alcove)
	assert_true(confirm_ok.valid, "F01: Legitimate open placement remains valid (got %s)" % String(confirm_ok.reason_code))

	alcove_root.queue_free()
	await wait_process_frames(2)

	# 4. Discoverability badges toggle must apply to ALL 14 playable sources (not only canonical 6).
	var all_14: Array[ResourceSource] = []
	for node: Node in main.get_tree().get_nodes_in_group(ResourceSource.GROUP_RESOURCE_SOURCES):
		if node is ResourceSource and is_instance_valid(node) and node.is_inside_tree() and (node as ResourceSource).get_world_3d() == main.get_world_3d():
			all_14.append(node as ResourceSource)
	assert_eq(all_14.size(), 14, "F01: Scene exposes 14 playable sources for badge check")
	test_map.set_resource_discoverability_badges_visible(false)
	for src: ResourceSource in all_14:
		var badge := src.get_node_or_null("DiscoverabilityBadge") as Node3D
		assert_not_null(badge, "F01: Source %s has DiscoverabilityBadge" % String(src.source_id))
		if badge != null:
			assert_false(badge.visible, "F01: Badge hidden on %s when toggled off" % String(src.source_id))
	test_map.set_resource_discoverability_badges_visible(true)
	for src: ResourceSource in all_14:
		var badge := src.get_node_or_null("DiscoverabilityBadge") as Node3D
		if badge != null:
			assert_true(badge.visible, "F01: Badge restored on %s when toggled on" % String(src.source_id))

	await _teardown_fixture(view)


func _start_left_drag_hold(viewport: SubViewport, start_point: Vector2, shift_pressed: bool = false) -> void:
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


func _finish_left_drag_hold(viewport: SubViewport, start_point: Vector2, end_point: Vector2, shift_pressed: bool = false) -> void:
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
	await wait_process_frames(2)


func test_r1_f02_drag_gesture_preserves_source_nature_across_origin_invalidation() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var selection := main.get_selection_manager()
	var feedback := main.get_autonomous_gather_feedback()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var t3 := _find_source_by_id(main, &"wood_tree_03")
	var t4 := _find_source_by_id(main, &"wood_tree_04")
	var t5 := _find_source_by_id(main, &"wood_tree_05")
	assert_not_null(board, "F02: Board present")
	assert_not_null(leader_a, "F02: LeaderA present")
	assert_not_null(leader_b, "F02: LeaderB present")
	assert_not_null(t3, "F02: WoodTree03 present")
	assert_not_null(t4, "F02: WoodTree04 present")
	assert_not_null(t5, "F02: WoodTree05 present")
	if board == null or leader_a == null or leader_b == null or t3 == null or t4 == null or t5 == null:
		await _teardown_fixture(view)
		return

	# Place LeaderB inside the eastern grove drag area and pre-select LeaderA.
	leader_b.global_position = Vector3(14.0, 0.0, -0.5)
	selection.select_single(leader_a)
	_focus_camera(main, Vector2(14.8, -0.8))
	await wait_process_frames(2)

	# Case 1: Origin source depleted between mouse_down and mouse_up, another valid tree + LeaderB inside box.
	var p_t3 := _source_screen_point(view, t3)
	var p_t4 := _source_screen_point(view, t4)
	await _start_left_drag_hold(view, p_t3, false)
	while not t3.is_depleted():
		t3.extract(t3.get_remaining_amount())
	assert_true(t3.is_depleted(), "F02-C1: Origin tree depleted mid-drag")
	await _finish_left_drag_hold(view, p_t3, Vector2(p_t4.x + 28.0, p_t4.y + 28.0), false)

	assert_eq(selection.get_selected_units(), [leader_a], "F02-C1: Depleted origin drag must NOT convert to RTS unit selection")
	assert_null(board.get_active_task_for_source(t3), "F02-C1: Depleted origin tree not registered")
	assert_not_null(board.get_active_task_for_source(t4), "F02-C1: Peer valid tree inside box still registered")

	# Clean board for Case 2
	for u: Unit in main.get_units():
		u.cancel_current_order()
	for tk: WorkTask in board.get_active_tasks():
		board.close_task(tk, WorkTask.State.CANCELLED, "f02_reset")
	await wait_process_frames(2)

	# Case 2: Origin source FREED (effectively destroyed!) between mouse_down and mouse_up, with peer t5 + LeaderB inside box.
	var ephemeral_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	ephemeral_tree.name = "F02EphemeralTree"
	ephemeral_tree.source_id = &"f02_ephemeral_tree"
	ephemeral_tree.position = Vector3(13.0, 0.0, 1.5)
	main.get_test_map().get_resource_sources_root().add_child(ephemeral_tree)
	await wait_physics_frames(2)

	selection.select_single(leader_a)
	var p_eph := _source_screen_point(view, ephemeral_tree)
	var p_t5 := _source_screen_point(view, t5)
	await _start_left_drag_hold(view, p_eph, false)
	ephemeral_tree.free() # Immediate effective destruction before mouse_up!
	await wait_process_frames(1)
	await _finish_left_drag_hold(view, p_eph, Vector2(p_t5.x + 28.0, p_t5.y + 28.0), false)

	assert_eq(selection.get_selected_units(), [leader_a], "F02-C2: Freed origin drag must NEVER convert into RTS unit selection")
	assert_not_null(board.get_active_task_for_source(t5), "F02-C2: Valid peer tree t5 inside box still registered")

	# Clean board for Case 3
	for u: Unit in main.get_units():
		u.cancel_current_order()
	for tk: WorkTask in board.get_active_tasks():
		board.close_task(tk, WorkTask.State.CANCELLED, "f02_reset2")
	await wait_process_frames(2)

	# Case 3: Origin source destroyed AND NO valid peer source inside box, WITH LeaderB inside box.
	var solo_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	solo_tree.name = "F02SoloTree"
	solo_tree.source_id = &"f02_solo_tree"
	solo_tree.position = Vector3(-2.0, 0.0, -10.0)
	main.get_test_map().get_resource_sources_root().add_child(solo_tree)
	leader_b.global_position = Vector3(-0.5, 0.0, -10.0)
	_focus_camera(main, Vector2(-1.2, -10.0))
	await wait_physics_frames(2)

	selection.select_single(leader_a)
	var p_solo := _source_screen_point(view, solo_tree)
	var p_lb := view.get_camera_3d().unproject_position(leader_b.global_position + Vector3(0.0, 0.9, 0.0))
	await _start_left_drag_hold(view, p_solo, false)
	solo_tree.queue_free()
	await wait_process_frames(2)
	await _finish_left_drag_hold(view, p_solo, Vector2(p_lb.x + 24.0, p_lb.y + 24.0), false)

	assert_eq(selection.get_selected_units(), [leader_a], "F02-C3: Destroyed solo origin must preserve previous unit selection")
	assert_eq(board.get_active_tasks().size(), 0, "F02-C3: Zero tasks registered when no valid source in box")
	assert_false(feedback.last_message.is_empty(), "F02-C3: Safe feedback shown when no valid source remains")

	# Case 4: Origin source moved out of allowed domain (other_region) between mouse_down and mouse_up.
	var domain_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	domain_tree.name = "F02DomainTree"
	domain_tree.source_id = &"f02_domain_tree"
	domain_tree.position = Vector3(-2.0, 0.0, -10.0)
	main.get_test_map().get_resource_sources_root().add_child(domain_tree)
	await wait_physics_frames(2)

	selection.select_single(leader_a)
	var p_dom := _source_screen_point(view, domain_tree)
	await _start_left_drag_hold(view, p_dom, false)
	domain_tree.set_meta(&"region_id", &"other_region")
	await _finish_left_drag_hold(view, p_dom, Vector2(p_lb.x + 24.0, p_lb.y + 24.0), false)

	assert_eq(selection.get_selected_units(), [leader_a], "F02-C4: Out-of-domain origin must NOT convert into RTS unit selection")
	assert_null(board.get_active_task_for_source(domain_tree), "F02-C4: Out-of-domain source rejected")

	# Case 5: Esc cancels source-origin drag even if origin was destroyed mid-drag.
	await _start_left_drag_hold(view, p_dom, false)
	domain_tree.free()
	var mm := InputEventMouseMotion.new()
	mm.position = p_dom + Vector2(40.0, 30.0)
	mm.global_position = mm.position
	view.push_input(mm, false)
	await wait_process_frames(1)
	await _press_esc(view)
	var up := InputEventMouseButton.new()
	up.position = p_dom + Vector2(40.0, 30.0)
	up.global_position = up.position
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	view.push_input(up, false)
	await wait_process_frames(2)
	assert_eq(selection.get_selected_units(), [leader_a], "F02-C5: Esc preserves selection cleanly")

	# Case 6: Ground-origin drag still selects LeaderB cleanly (RTS selection preserved).
	var p_ground := view.get_camera_3d().unproject_position(Vector3(-3.0, 0.0, -11.5))
	await _left_drag(view, p_ground, Vector2(p_lb.x + 26.0, p_lb.y + 26.0), false)
	await wait_process_frames(2)
	assert_true(selection.get_selected_units().has(leader_b), "F02-C6: Ground-origin drag still selects RTS units")

	await _teardown_fixture(view)


func test_r1_t02_real_construction_reserved_withdrawal_and_community_coexistence() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var inventory := main.get_settlement_inventory()
	var cm := main.get_construction_manager()
	var cmd := main.get_command_controller()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")

	assert_not_null(board, "T02: Board present")
	assert_not_null(dispatcher, "T02: Dispatcher present")
	assert_not_null(leader_a, "T02: LeaderA present")
	assert_not_null(leader_b, "T02: LeaderB present")
	assert_not_null(t1, "T02: WoodTree01 present")
	assert_not_null(t2, "T02: WoodTree02 present")
	if board == null or dispatcher == null or leader_a == null or leader_b == null or t1 == null or t2 == null:
		await _teardown_fixture(view)
		return

	# 1. Real physical stock on CampStorageZone + legitimate ConstructionSite creation.
	assert_true(inventory.deposit(&"wood", 12), "T02: Physical camp wood deposited")
	assert_true(inventory.deposit(&"stone", 6), "T02: Physical camp stone deposited")
	var site_res := cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, -5.0))
	assert_true(bool(site_res.get("ok", false)), "T02: Legitimate ConstructionSite created from real stock")
	var site := site_res.get("site") as ConstructionSite
	assert_not_null(site, "T02: Site instance valid")
	if site == null:
		await _teardown_fixture(view)
		return
	assert_true(inventory.get_reserved_pile_entries(site.reservation_id, &"wood").size() > 0, "T02: Real physical reserved wood pile exists")

	# 2. Issue real ConstructOrder so LeaderB performs legitimate ReservedWithdrawalCoordinator withdrawal.
	assert_true(cmd.command_units_to_site(site, [leader_b]), "T02: Legitimate ConstructOrder accepted for LeaderB")
	Engine.time_scale = 3.0
	var withdrew_reserved: bool = false
	for _i: int in range(3000):
		var b_load := leader_b.get_carry_load()
		if b_load.get_current_weight() > 0 and CommunityTaskDispatcher._has_non_free_provenance_lots(b_load):
			withdrew_reserved = true
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	assert_true(withdrew_reserved, "T02: LeaderB withdrew legitimate SITE_RESERVED lot via ReservedWithdrawalCoordinator")
	if not withdrew_reserved:
		await _teardown_fixture(view)
		return

	# Interrupt LeaderB so it is IDLE while holding legitimate SITE_RESERVED cargo (and move closer to t1 than LeaderA).
	leader_b.cancel_current_order()
	await wait_process_frames(2)
	leader_b.global_position = Vector3(7.5, 0.0, -1.5)
	leader_a.global_position = Vector3(-2.5, 0.0, 2.5)
	await wait_physics_frames(1)
	var b_wood_before := leader_b.get_carry_load().get_amount(&"wood")
	var b_stone_before := leader_b.get_carry_load().get_amount(&"stone")
	assert_eq(leader_b.get_state(), Unit.State.IDLE, "T02: LeaderB IDLE with legitimate SITE_RESERVED cargo")
	assert_true(leader_b.get_carry_load().validate_provenance(), "T02: LeaderB SITE_RESERVED provenance valid")

	# 3. Register community gather on t1 -> closer LeaderB must be skipped, eligible LeaderA completes full cycle.
	t1.configure(t1.source_id, t1.get_definition(), 2, 2, 2)
	var wood_before_gather := inventory.get_physical_amount(&"wood")
	var reg1 := board.register_gather_task(t1)
	var task1 := reg1.get("task") as WorkTask
	await wait_process_frames(2)
	await wait_physics_frames(1)
	assert_not_null(task1, "T02: Gather task registered alongside active site")
	assert_eq(task1.assigned_unit, leader_a, "T02: Eligible LeaderA dispatched while closer IDLE LeaderB with SITE_RESERVED is protected")
	assert_null(leader_b.get_current_order(), "T02: LeaderB with SITE_RESERVED cargo receives no incompatible community order")

	Engine.time_scale = 3.0
	for _i: int in range(6000):
		if board.get_active_tasks().is_empty():
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)
	assert_true(board.get_active_tasks().is_empty(), "T02: LeaderA completed community gather cleanly")
	assert_eq(inventory.get_physical_amount(&"wood") - wood_before_gather, 2, "T02: Exact +2 wood delivered without disturbing reserved stock")
	assert_eq(leader_b.get_carry_load().get_amount(&"wood"), b_wood_before, "T02: LeaderB SITE_RESERVED wood conserved")
	assert_eq(leader_b.get_carry_load().get_amount(&"stone"), b_stone_before, "T02: LeaderB SITE_RESERVED stone conserved")
	assert_true(CommunityTaskDispatcher._has_non_free_provenance_lots(leader_b.get_carry_load()), "T02: SITE_RESERVED lot never converted to FREE_GATHERED")

	# 4. Regional transactional lock blocks community dispatch until released, then resumes cleanly.
	t2.configure(t2.source_id, t2.get_definition(), 2, 2, 2)
	inventory._is_delivering = true
	var reg2 := board.register_gather_task(t2)
	var task2 := reg2.get("task") as WorkTask
	await wait_process_frames(3)
	assert_not_null(task2, "T02: Second task registered during transactional busy window")
	assert_null(task2.assigned_unit, "T02: No dispatch while regional inventory transaction is busy")
	assert_eq(task2.last_reason, "economy_busy", "T02: Task waits with economy_busy during lock")

	inventory._is_delivering = false
	dispatcher.request_dispatch()
	await wait_process_frames(3)
	await wait_physics_frames(1)
	assert_eq(task2.assigned_unit, leader_a, "T02: Resumes dispatch cleanly after transactional lock release")
	assert_null(leader_b.get_current_order(), "T02: LeaderB still protected after lock release")

	await _teardown_fixture(view)


func test_r1_t03_lifecycle_signals_ensure_wired_and_reinstantiation() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var world := main.get_world_3d()
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var agi := main.get_input_controller() as AutonomousGatherInput
	var t1 := _find_source_by_id(main, &"wood_tree_01")

	assert_not_null(board, "T03: Board present")
	assert_not_null(dispatcher, "T03: Dispatcher present")
	assert_not_null(agi, "T03: AutonomousGatherInput present")
	assert_not_null(t1, "T03: WoodTree01 present")
	if board == null or dispatcher == null or agi == null or t1 == null:
		await _teardown_fixture(view)
		return

	# 1. Active task & highlight -> teardown_community_work disconnects signals & prevents _ensure_wired reactivation.
	var reg := board.register_gather_task(t1)
	var task := reg.get("task") as WorkTask
	await wait_process_frames(2)
	await wait_physics_frames(1)
	assert_not_null(task, "T03: Task registered")
	assert_not_null(task.assigned_unit, "T03: Worker dispatched")
	assert_eq(_count_highlight_children(t1), 1, "T03: Highlight attached")

	for u: Unit in main.get_units():
		u.cancel_current_order()
	await wait_process_frames(2)

	agi.teardown_community_work()
	dispatcher.teardown()
	board.teardown()
	await wait_process_frames(2)

	assert_false(board.task_registered.is_connected(agi._on_task_registered), "T03: Input disconnected from board.task_registered")
	assert_false(board.task_registered.is_connected(dispatcher._on_board_task_registered), "T03: Dispatcher disconnected from board")
	assert_eq(_count_highlight_children(t1), 0, "T03: Zero orphan highlights after teardown")

	# Deferred or explicit _ensure_wired() MUST NOT reactivate torn-down community components!
	agi.call("_ensure_wired")
	agi.call_deferred("_ensure_wired")
	await wait_process_frames(3)
	assert_false(board.task_registered.is_connected(agi._on_task_registered), "T03: _ensure_wired must NOT reconnect torn-down input")
	assert_false(board.task_registered.is_connected(dispatcher._on_board_task_registered), "T03: _ensure_wired must NOT reactivate torn-down dispatcher")

	# Idempotent second teardown call
	agi.teardown_community_work()
	dispatcher.teardown()
	board.teardown()

	# 2. Controlled teardown releases regional authority cleanly (observed synchronously & via World3D).
	var pre := main.preflight_economic_teardown()
	assert_true(bool(pre.get("ok", false)), "T03: Preflight ok")
	var td := main.request_controlled_teardown()
	assert_true(bool(td.get("ok", false)), "T03: Controlled teardown ok")
	var rel := main.get_last_domain_release_result()
	assert_true(bool(rel.get("ok", false)), "T03: Release result ok captured synchronously")
	await wait_process_frames(3)
	assert_false(world.has_meta(ReservedWithdrawalCoordinator.DOMAIN_META), "T03: RegionalAuthority removed from World3D")

	# 3. Legitimate reinstantiation of a fresh MainScene in the same SubViewport/World3D works cleanly.
	var main2 := MAIN_SCENE.instantiate() as MainScene
	view.add_child(main2)
	for _i: int in range(120):
		if main2.get_test_map().get_navigation().is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(main2.get_test_map().get_navigation().is_navigation_ready(), "T03: Reinstantiated MainScene navigation ready")
	await wait_process_frames(3)
	var rig2 := main2.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig2 != null:
		rig2.edge_pan_enabled = false

	var board2 := main2.get_community_work_board()
	var t1_2 := _find_source_by_id(main2, &"wood_tree_01")
	assert_not_null(board2, "T03: Second MainScene has fresh board")
	assert_not_null(t1_2, "T03: Second MainScene has WoodTree01")
	if board2 != null and t1_2 != null:
		_focus_camera(main2, Vector2(9.5, -1.5))
		await wait_process_frames(1)
		await _left_click(view, _source_screen_point(view, t1_2), false)
		await wait_process_frames(2)
		await wait_physics_frames(1)
		var task2 := board2.get_active_task_for_source(t1_2)
		assert_not_null(task2, "T03: Fresh MainScene registers community task normally")
		if task2 != null:
			assert_not_null(task2.assigned_unit, "T03: Fresh MainScene dispatches worker without stale interference")
			assert_eq(task2.state, WorkTask.State.IN_PROGRESS, "T03: Fresh MainScene enters IN_PROGRESS")

	await _teardown_fixture(view)


func test_r1_t04_invalid_economic_admission_all_entry_vectors() -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(1280, 720)
	add_test_child(view)

	var main := MAIN_SCENE.instantiate() as MainScene
	var leader_a := main.get_node("Units/LeaderA") as Unit
	var wood_def: ResourceDefinition = load("res://data/resources/wood.tres") as ResourceDefinition
	leader_a.get_carry_load().add_units(wood_def, 1) # Invalid pre-admission non-empty carry!
	view.add_child(main)
	for _i: int in range(120):
		if main.get_test_map().get_navigation().is_navigation_ready():
			break
		await wait_physics_frames(1)
	assert_true(main.get_test_map().get_navigation().is_navigation_ready(), "T04: Navigation ready")
	await wait_process_frames(3)
	var rig := main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var feedback := main.get_autonomous_gather_feedback()
	var selection := main.get_selection_manager()
	var inventory := main.get_settlement_inventory()
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var r1 := _find_source_by_id(main, &"stone_rock_01")

	assert_false(main.get_economy_admission_reason().is_empty(), "T04: Admission reason populated")
	assert_not_null(board, "T04: Board present")
	assert_not_null(dispatcher, "T04: Dispatcher present")
	assert_not_null(feedback, "T04: Feedback present")
	assert_not_null(leader_b, "T04: LeaderB present")
	assert_not_null(t1, "T04: WoodTree01 present")
	assert_not_null(t2, "T04: WoodTree02 present")
	assert_not_null(r1, "T04: StoneRock01 present")
	if board == null or dispatcher == null or feedback == null or leader_b == null or t1 == null or t2 == null or r1 == null:
		await _teardown_fixture(view)
		return

	var w0 := inventory.get_physical_amount(&"wood")
	var s0 := inventory.get_physical_amount(&"stone")
	var f0 := inventory.get_physical_amount(&"food")
	var t1_rem0 := t1.get_remaining_amount()
	var t2_rem0 := t2.get_remaining_amount()
	var r1_rem0 := r1.get_remaining_amount()
	var a_wood0 := leader_a.get_carry_load().get_amount(&"wood")
	var b_weight0 := leader_b.get_carry_load().get_current_weight()

	# Pre-select LeaderB and place LeaderA near wood grove to catch any accidental RTS drag fallback.
	selection.select_single(leader_b)
	leader_a.global_position = Vector3(10.0, 0.0, 2.0)
	_focus_camera(main, Vector2(9.5, 2.0))
	await wait_process_frames(2)

	# 1. Single left-click on source
	feedback.last_message = ""
	await _left_click(view, _source_screen_point(view, t1), false)
	await wait_process_frames(2)
	assert_eq(board.get_active_tasks().size(), 0, "T04-1: Single click registers 0 tasks")
	assert_string_contains(feedback.last_message.to_lower(), "bloqueada", "T04-1: Honest blocked feedback on click")

	# 2. Shift + left-click on source
	feedback.last_message = ""
	await _left_click(view, _source_screen_point(view, t2), true)
	await wait_process_frames(2)
	assert_eq(board.get_active_tasks().size(), 0, "T04-2: Shift+click registers 0 tasks")
	assert_string_contains(feedback.last_message.to_lower(), "bloqueada", "T04-2: Honest blocked feedback on Shift+click")

	# 3. Box drag starting on source across another tree AND LeaderA -> must NOT select LeaderA, must report blocked!
	feedback.last_message = ""
	var p_t1 := _source_screen_point(view, t1)
	var p_t2 := _source_screen_point(view, t2)
	await _left_drag(view, p_t1, Vector2(p_t2.x - 24.0, p_t2.y + 24.0), false)
	await wait_process_frames(2)
	assert_eq(board.get_active_tasks().size(), 0, "T04-3: Source-origin drag registers 0 tasks under blocked admission")
	assert_eq(selection.get_selected_units(), [leader_b], "T04-3: Blocked source drag must preserve previous RTS selection")
	assert_string_contains(feedback.last_message.to_lower(), "bloqueada", "T04-3: Honest blocked feedback on source drag")

	# 4. Direct board group registration + explicit dispatch request -> zero dispatch
	board.register_gather_group([t1, t2])
	dispatcher.request_dispatch()
	await wait_process_frames(3)
	for u: Unit in main.get_units():
		assert_null(u.get_current_order(), "T04-4: Zero dispatch after direct register_gather_group")

	# 5. Direct board single registration + explicit dispatch request -> zero dispatch
	board.register_gather_task(r1)
	dispatcher.request_dispatch()
	await wait_process_frames(3)
	for u: Unit in main.get_units():
		assert_null(u.get_current_order(), "T04-5: Zero dispatch after direct register_gather_task")

	# 6. Zero economic mutation across stock, sources, and carry loads
	assert_eq(inventory.get_physical_amount(&"wood"), w0, "T04-6: Wood stock untouched")
	assert_eq(inventory.get_physical_amount(&"stone"), s0, "T04-6: Stone stock untouched")
	assert_eq(inventory.get_physical_amount(&"food"), f0, "T04-6: Food stock untouched")
	assert_eq(t1.get_remaining_amount(), t1_rem0, "T04-6: WoodTree01 untouched")
	assert_eq(t2.get_remaining_amount(), t2_rem0, "T04-6: WoodTree02 untouched")
	assert_eq(r1.get_remaining_amount(), r1_rem0, "T04-6: StoneRock01 untouched")
	assert_eq(leader_a.get_carry_load().get_amount(&"wood"), a_wood0, "T04-6: LeaderA carry load untouched")
	assert_eq(leader_b.get_carry_load().get_current_weight(), b_weight0, "T04-6: LeaderB carry load untouched")

	await _teardown_fixture(view)


func test_r1_r01_regional_isolation_adversarial_investigation() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var t1 := _find_source_by_id(main, &"wood_tree_01") # canonical without region_id meta
	var t3 := _find_source_by_id(main, &"wood_tree_03") # additional with region_id="default" meta

	assert_not_null(board, "R01: Board present")
	assert_not_null(dispatcher, "R01: Dispatcher present")
	assert_not_null(t1, "R01: Canonical WoodTree01 present")
	assert_not_null(t3, "R01: Additional WoodTree03 present")
	if board == null or dispatcher == null or t1 == null or t3 == null:
		await _teardown_fixture(view)
		return

	# 1 & 2. Canonical source without metadata + additional source with region_id="default" both accepted.
	assert_true(board.is_source_in_region_domain(t1), "R01-1: Canonical source without explicit region_id accepted")
	assert_true(board.is_source_in_region_domain(t3), "R01-2: Additional source with region_id=default accepted")

	# 3. Explicitly foreign-region source rejected in direct, group, click, and box selection.
	var foreign_root := Node3D.new()
	foreign_root.name = "R01ForeignRegionRoot"
	foreign_root.set_meta(&"region_id", &"region_beta")
	main.add_child(foreign_root)
	var foreign_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	foreign_tree.name = "R01ForeignTree"
	foreign_tree.source_id = &"r01_foreign_tree"
	foreign_tree.position = Vector3(11.5, 0.0, 2.0)
	foreign_root.add_child(foreign_tree)
	await wait_physics_frames(2)

	assert_false(board.is_source_in_region_domain(foreign_tree), "R01-3: Foreign ancestral region_id rejected")
	var reg_direct := board.register_gather_task(foreign_tree)
	assert_false(bool(reg_direct.get("ok", false)), "R01-3: Direct registration rejected")
	assert_eq(String(reg_direct.get("reason", "")), "region_mismatch", "R01-3: Direct rejection reason is region_mismatch")
	var reg_group := board.register_gather_group([foreign_tree])
	assert_false(bool(reg_group.get("ok", false)), "R01-3: Group registration rejected")

	_focus_camera(main, Vector2(11.5, 2.0))
	await wait_process_frames(1)
	var p_for := _source_screen_point(view, foreign_tree)
	await _left_click(view, p_for, false)
	await wait_process_frames(2)
	assert_null(board.get_active_task_for_source(foreign_tree), "R01-3: Click on foreign-region tree rejected")

	# 4. Separate World3D source rejected everywhere.
	var other_vp := SubViewport.new()
	other_vp.own_world_3d = true
	other_vp.size = Vector2i(256, 256)
	add_test_child(other_vp)
	var other_w_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	other_w_tree.name = "R01OtherWorldTree"
	other_w_tree.source_id = &"r01_other_world_tree"
	other_w_tree.position = Vector3(11.5, 0.0, 2.0)
	other_vp.add_child(other_w_tree)
	await wait_physics_frames(2)
	assert_false(board.is_source_in_region_domain(other_w_tree), "R01-4: Other World3D rejected by board")
	assert_false(SelectionBoxMath.is_source_in_box(view.get_camera_3d(), other_w_tree, Rect2(0, 0, 1280, 720), Rect2(0, 0, 1280, 720)), "R01-4: Other World3D rejected by SelectionBoxMath")
	other_vp.queue_free()

	# 5. Two distinct regions in the SAME World3D with region_id roots stay mutually isolated.
	var alpha_root := Node3D.new()
	alpha_root.set_meta(&"region_id", &"region_alpha")
	main.add_child(alpha_root)
	var alpha_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	alpha_tree.source_id = &"r01_alpha_tree"
	alpha_tree.position = Vector3(4.0, 0.0, -10.0)
	alpha_root.add_child(alpha_tree)
	var board_alpha := CommunityWorkBoard.new()
	alpha_root.add_child(board_alpha)
	board_alpha.configure(&"region_alpha", main.get_world_3d())
	var board_beta := CommunityWorkBoard.new()
	foreign_root.add_child(board_beta)
	board_beta.configure(&"region_beta", main.get_world_3d())
	await wait_physics_frames(1)

	assert_true(bool(board_alpha.register_gather_task(alpha_tree).get("ok", false)), "R01-6: Alpha board accepts alpha source")
	assert_false(bool(board_alpha.register_gather_task(foreign_tree).get("ok", false)), "R01-6: Alpha board rejects beta source")
	assert_true(bool(board_beta.register_gather_task(foreign_tree).get("ok", false)), "R01-6: Beta board accepts beta source")
	assert_false(bool(board_beta.register_gather_task(alpha_tree).get("ok", false)), "R01-6: Beta board rejects alpha source")

	# 6. Reparenting/domain change after registration prevents dispatch and economic mutation.
	for u: Unit in main.get_units():
		u.issue_order(MoveOrder.new(Vector3(-18.0, 0.0, -18.0), Vector3(-18.0, 0.0, -18.0), false))
	await wait_physics_frames(1)
	var movable_tree := TREE_SOURCE_SCENE.instantiate() as ResourceSource
	movable_tree.source_id = &"r01_movable_tree"
	movable_tree.position = Vector3(5.0, 0.0, -10.0)
	main.get_test_map().get_resource_sources_root().add_child(movable_tree)
	await wait_physics_frames(1)
	var reg_mov := board.register_gather_task(movable_tree)
	assert_true(bool(reg_mov.get("ok", false)), "R01-7: Initially valid tree registered while workers busy")
	var mov_rem0 := movable_tree.get_remaining_amount()
	# Reparent into foreign_root (region_beta) before workers become free!
	movable_tree.reparent(foreign_root)
	await wait_process_frames(1)
	for u: Unit in main.get_units():
		u.cancel_current_order()
	dispatcher.request_dispatch()
	await wait_process_frames(3)
	for u: Unit in main.get_units():
		assert_null(u.get_current_order(), "R01-7: Reparented foreign-region source must NOT be dispatched")
	assert_eq(movable_tree.get_remaining_amount(), mov_rem0, "R01-7: Zero extraction after domain change")

	board_alpha.teardown()
	board_beta.teardown()
	alpha_root.queue_free()
	foreign_root.queue_free()
	await _teardown_fixture(view)
