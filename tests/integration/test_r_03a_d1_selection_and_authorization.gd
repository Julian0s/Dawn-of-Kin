extends TestCase
## Integration tests for R-03A D1 — Independent source selection, explicit HUD authorization,
## D1-B individual deselection, D1-C explicit reauthorization, minimal D2.2 contextual HUD,
## concentric selection vs task rings, anti-click-through, and 720p/1080p layout geometry.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const SHELTER_DEF: BuildingDefinition = preload("res://data/buildings/shelter_basic.tres")
const D1_ICON_WOOD: Texture2D = preload("res://assets/ui/d2/icons/ico_work_chop.png")
const D1_ICON_STONE: Texture2D = preload("res://assets/ui/d2/icons/ico_work_mine.png")
const D1_ICON_FOOD: Texture2D = preload("res://assets/ui/d2/icons/ico_work_harvest.png")


func _fixture(viewport_size: Vector2i = Vector2i(1280, 720)) -> SubViewport:
	var view := SubViewport.new()
	view.size = viewport_size
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.disable_3d = false
	view.own_world_3d = true
	view.physics_object_picking = true
	var main := MAIN_SCENE.instantiate() as MainScene
	view.add_child(main)
	add_test_child(view)
	await wait_process_frames(4)
	await wait_physics_frames(4)
	var rig := main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false
		rig.set_target_zoom_distance(22.0, true)
	await wait_process_frames(2)
	return view


func _teardown_fixture(view: SubViewport) -> void:
	if view == null or not is_instance_valid(view):
		return
	var main := view.get_child(0) as MainScene if view.get_child_count() > 0 else null
	if main != null and is_instance_valid(main):
		var units: Array[Unit] = main.get_units()
		for u: Unit in units:
			if u != null and is_instance_valid(u):
				u.cancel_current_order(UnitOrder.REASON_CANCELLED)
		var g_in := main.get_input_controller() as AutonomousGatherInput
		if g_in != null:
			g_in.teardown_community_work()
		if main.get_community_task_dispatcher() != null:
			main.get_community_task_dispatcher().teardown()
		if main.get_community_work_board() != null:
			main.get_community_work_board().teardown()
	if view.get_parent() != null:
		view.get_parent().remove_child(view)
	view.queue_free()
	await wait_process_frames(2)
	await wait_physics_frames(1)


func _find_source_by_id(main: MainScene, sid: StringName) -> ResourceSource:
	for src: ResourceSource in main.get_test_map().get_all_region_resource_sources():
		if src.get_source_id() == sid:
			return src
	return null


func _find_unit_by_id(main: MainScene, cid: StringName) -> Unit:
	for u: Unit in main.get_units():
		if u.get_character_id() == cid:
			return u
	return null


func _focus_camera(main: MainScene, focus_xz: Vector2, zoom_dist: float = 22.0) -> void:
	var rig := main.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.set_focus_position(focus_xz)
		rig.set_target_zoom_distance(zoom_dist, true)


func _source_screen_point(view: SubViewport, src: ResourceSource) -> Vector2:
	var main := view.get_child(0) as MainScene
	var cam := (main.get_node("RtsCameraRig") as RtsCameraRig).get_camera()
	return cam.unproject_position(src.global_position + Vector3(0.0, 0.7, 0.0))


func _unit_screen_point(view: SubViewport, unit: Unit) -> Vector2:
	var main := view.get_child(0) as MainScene
	var cam := (main.get_node("RtsCameraRig") as RtsCameraRig).get_camera()
	return cam.unproject_position(SelectionBoxMath.get_unit_world_anchor(unit))


func _world_screen_point(view: SubViewport, world_pos: Vector3) -> Vector2:
	var main := view.get_child(0) as MainScene
	var cam := (main.get_node("RtsCameraRig") as RtsCameraRig).get_camera()
	return cam.unproject_position(world_pos)


func _left_click(view: SubViewport, pos: Vector2, shift_held: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.shift_pressed = shift_held
	view.push_input(motion, true)
	await wait_process_frames(1)

	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = pos
		ev.global_position = pos
		ev.pressed = pressed
		ev.shift_pressed = shift_held
		view.push_input(ev, true)
		await wait_process_frames(1)


func _left_drag(
	view: SubViewport,
	start_pos: Vector2,
	end_pos: Vector2,
	shift_press: bool,
	shift_motion: bool,
	shift_release: bool
) -> void:
	var m0 := InputEventMouseMotion.new()
	m0.position = start_pos
	m0.global_position = start_pos
	m0.shift_pressed = shift_press
	view.push_input(m0, true)
	await wait_process_frames(1)

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = start_pos
	down.global_position = start_pos
	down.pressed = true
	down.shift_pressed = shift_press
	view.push_input(down, true)
	await wait_process_frames(1)

	for step: int in range(1, 5):
		var p: Vector2 = start_pos.lerp(end_pos, float(step) / 4.0)
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.shift_pressed = shift_motion
		view.push_input(mm, true)
		await wait_process_frames(1)

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = end_pos
	up.global_position = end_pos
	up.pressed = false
	up.shift_pressed = shift_release
	view.push_input(up, true)
	await wait_process_frames(1)


func _press_escape(view: SubViewport) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		view.push_input(key, true)
		await wait_process_frames(1)


func _click_hud_button(view: SubViewport, btn: Button) -> void:
	var rect: Rect2 = btn.get_global_rect()
	var center: Vector2 = rect.position + rect.size * 0.5
	await _left_click(view, center, false)
	await wait_process_frames(2)


func _count_rings_on_source(src: ResourceSource, prefix: String) -> int:
	var total: int = 0
	for child: Node in src.get_children():
		if child.name.begins_with(prefix) and not child.is_queued_for_deletion():
			total += 1
	return total


func _count_all_rings(main: MainScene, prefix: String) -> int:
	var total: int = 0
	for src: ResourceSource in main.get_test_map().get_all_region_resource_sources():
		total += _count_rings_on_source(src, prefix)
	return total


func test_d1_01_left_click_selects_without_creating_task_or_moving_workers() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	assert_not_null(t1, "D1-01: WoodTree01 present")
	assert_not_null(model, "D1-01: SourceSelectionModel present")
	assert_not_null(hud, "D1-01: CommunitySelectionActionsHud present")
	if t1 == null or model == null or hud == null:
		await _teardown_fixture(view)
		return

	_focus_camera(main, Vector2(t1.global_position.x, t1.global_position.z))
	await wait_process_frames(2)
	await _left_click(view, _source_screen_point(view, t1), false)
	await wait_process_frames(3)
	await wait_physics_frames(2)

	assert_eq(model.get_selected_sources(), [t1], "D1-01: Clicking t1 selects it in SourceSelectionModel")
	assert_eq(board.get_active_tasks().size(), 0, "D1-01: Clicking a source must NOT create a WorkTask automatically")
	for u: Unit in main.get_units():
		assert_null(u.get_current_order(), "D1-01: Selecting a source must NOT issue orders or move workers")
	assert_true(hud.is_panel_visible(), "D1-01: Contextual HUD must become visible when a source is selected")
	assert_eq(hud.get_visible_category_ids(), [&"wood"], "D1-01: Only wood category visible")
	assert_eq(hud.get_category_count_text(&"wood"), "1", "D1-01: Wood count == 1")

	await _teardown_fixture(view)


func test_d1_02_shift_drag_from_empty_ground_selects_sources_without_units() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var selection := main.get_selection_manager()
	var hud := main.get_community_selection_actions_hud()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	assert_not_null(leader_a)
	assert_not_null(leader_b)
	assert_not_null(t1)
	assert_not_null(t2)
	if leader_a == null or leader_b == null or t1 == null or t2 == null:
		await _teardown_fixture(view)
		return

	selection.select_single(leader_a)
	leader_b.global_position = (t1.global_position + t2.global_position) * 0.5
	_focus_camera(main, Vector2(leader_b.global_position.x, leader_b.global_position.z))
	await wait_process_frames(2)

	var p1 := _source_screen_point(view, t1)
	var p2 := _source_screen_point(view, t2)
	var start_ground := Vector2(minf(p1.x, p2.x) - 60.0, minf(p1.y, p2.y) - 60.0)
	var end_ground := Vector2(maxf(p1.x, p2.x) + 60.0, maxf(p1.y, p2.y) + 60.0)
	await _left_drag(view, start_ground, end_ground, true, true, true)
	await wait_process_frames(2)

	assert_eq(selection.get_selected_units(), [leader_a], "D1-02: Shift+drag from empty ground must NOT alter RTS unit selection")
	assert_eq(board.get_active_tasks().size(), 0, "D1-02: Shift+drag must NOT auto-register tasks")
	assert_true(model.is_selected(t1), "D1-02: t1 selected")
	assert_true(model.is_selected(t2), "D1-02: t2 selected")
	assert_true(hud.is_panel_visible(), "D1-02: Contextual HUD visible after Shift+drag from empty ground")

	await _teardown_fixture(view)


func test_d1_03_unshifted_drag_starting_on_tree_performs_rts_unit_box_selection() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var selection := main.get_selection_manager()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	assert_not_null(leader_a)
	assert_not_null(t1)
	if leader_a == null or t1 == null:
		await _teardown_fixture(view)
		return

	selection.clear_selection()
	leader_a.global_position = t1.global_position + Vector3(-2.0, 0.0, 1.5)
	_focus_camera(main, Vector2(t1.global_position.x, t1.global_position.z))
	await wait_process_frames(2)

	var p_tree := _source_screen_point(view, t1)
	var p_unit := _unit_screen_point(view, leader_a)
	var delta := p_unit - p_tree
	var pad := Vector2(
		44.0 if delta.x >= 0.0 else -44.0,
		44.0 if delta.y >= 0.0 else -44.0
	)
	var end_pt := p_unit + pad
	await _left_drag(view, p_tree, end_pt, false, false, false)
	await wait_process_frames(2)

	assert_true(selection.get_selected_units().has(leader_a), "D1-03: Unshifted drag starting over tree MUST perform RTS unit selection")
	assert_true(model.is_empty(), "D1-03: Unshifted drag starting over tree must NOT select natural sources")
	assert_eq(board.get_active_tasks().size(), 0, "D1-03: Unshifted drag starting over tree must NOT register community tasks")

	await _teardown_fixture(view)


func test_d1_04_shift_click_heterogeneous_without_rejection_or_task_creation() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var feedback := main.get_autonomous_gather_feedback()
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	var b1 := _find_source_by_id(main, &"food_bush_01")
	assert_not_null(t1)
	assert_not_null(r1)
	assert_not_null(b1)
	if t1 == null or r1 == null or b1 == null:
		await _teardown_fixture(view)
		return

	feedback.last_message = ""
	_focus_camera(main, Vector2(t1.global_position.x, t1.global_position.z))
	await wait_process_frames(2)
	await _left_click(view, _source_screen_point(view, t1), false)

	_focus_camera(main, Vector2(r1.global_position.x, r1.global_position.z))
	await wait_process_frames(2)
	await _left_click(view, _source_screen_point(view, r1), true)

	_focus_camera(main, Vector2(b1.global_position.x, b1.global_position.z))
	await wait_process_frames(2)
	await _left_click(view, _source_screen_point(view, b1), true)
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 0, "D1-04: Shift+click heterogeneous sources must NOT register tasks")
	assert_false(feedback.last_message.contains("Seleção atual é de"), "D1-04: Must NOT emit old single-type rejection message")
	assert_eq(model.get_counts_by_resource(), {&"wood": 1, &"stone": 1, &"food": 1})
	assert_eq(hud.get_visible_category_ids(), [&"wood", &"stone", &"food"])

	await _teardown_fixture(view)


func test_d1_05_example_a_and_b_single_replacement_and_d1b_deselect_preserves_others() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	assert_not_null(t1)
	assert_not_null(t2)
	assert_not_null(r1)
	if t1 == null or t2 == null or r1 == null:
		await _teardown_fixture(view)
		return

	# Example A: click t1 -> {t1}; click t2 (no Shift) -> replaces with {t2}; click t2 again (no Shift) -> {} & HUD hidden.
	_focus_camera(main, Vector2(t1.global_position.x, t1.global_position.z))
	await wait_process_frames(2)
	await _left_click(view, _source_screen_point(view, t1), false)
	assert_eq(model.get_selected_sources(), [t1], "Example A: t1 selected")

	_focus_camera(main, Vector2(t2.global_position.x, t2.global_position.z))
	await wait_process_frames(2)
	await _left_click(view, _source_screen_point(view, t2), false)
	assert_eq(model.get_selected_sources(), [t2], "Example A: clicking unselected t2 replaces t1")

	await _left_click(view, _source_screen_point(view, t2), false)
	assert_true(model.is_empty(), "D1-B: clicking already-selected sole source without Shift deselects it")
	assert_false(hud.is_panel_visible(), "HUD hides when selection becomes empty")

	# Example B + D1-B: with {t1, t2, r1} selected, clicking t1 WITHOUT Shift deselects ONLY t1.
	model.add_sources([t1, t2, r1])
	assert_eq(model.get_selected_count(), 3)
	_focus_camera(main, Vector2(t1.global_position.x, t1.global_position.z))
	await wait_process_frames(2)
	await _left_click(view, _source_screen_point(view, t1), false)

	assert_false(model.is_selected(t1), "D1-B: clicked t1 is deselected")
	assert_true(model.is_selected(t2), "D1-B: t2 remains selected")
	assert_true(model.is_selected(r1), "D1-B: r1 remains selected")
	assert_eq(model.get_counts_by_resource(), {&"wood": 1, &"stone": 1})
	assert_eq(hud.get_visible_category_ids(), [&"wood", &"stone"])
	assert_eq(hud.get_category_count_text(&"wood"), "1")
	assert_eq(hud.get_category_count_text(&"stone"), "1")

	await _teardown_fixture(view)


func test_d1_06_shift_drag_from_all_origins_subset_5_of_6_trees_and_empty_box_no_fallback() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var model := main.get_source_selection_model()
	var selection := main.get_selection_manager()
	var board := main.get_community_work_board()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var t3 := _find_source_by_id(main, &"wood_tree_03")
	var t4 := _find_source_by_id(main, &"wood_tree_04")
	var t5 := _find_source_by_id(main, &"wood_tree_05")
	var t6 := _find_source_by_id(main, &"wood_tree_06")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	var b1 := _find_source_by_id(main, &"food_bush_01")
	assert_not_null(leader_a)
	assert_not_null(t1)
	assert_not_null(t2)
	assert_not_null(t3)
	assert_not_null(t4)
	assert_not_null(t5)
	assert_not_null(t6)
	assert_not_null(r1)
	assert_not_null(b1)
	if leader_a == null or t1 == null or t2 == null or t3 == null or t4 == null or t5 == null or t6 == null or r1 == null or b1 == null:
		await _teardown_fixture(view)
		return

	selection.select_single(leader_a)

	# 1) Select 5 of 6 trees (t1..t5, leaving t6 out) via Shift+drag starting on empty ground.
	_focus_camera(main, Vector2(15.5, -1.0), 26.0)
	await wait_process_frames(2)
	var pts5: Array[Vector2] = [
		_source_screen_point(view, t1),
		_source_screen_point(view, t2),
		_source_screen_point(view, t3),
		_source_screen_point(view, t4),
		_source_screen_point(view, t5),
	]
	var min5: Vector2 = pts5[0]
	var max5: Vector2 = pts5[0]
	for pt: Vector2 in pts5:
		min5 = Vector2(minf(min5.x, pt.x), minf(min5.y, pt.y))
		max5 = Vector2(maxf(max5.x, pt.x), maxf(max5.y, pt.y))
	await _left_drag(view, min5 - Vector2(12.0, 12.0), max5 + Vector2(12.0, 12.0), true, true, true)
	await wait_process_frames(2)

	assert_eq(model.get_count_for_resource(&"wood"), 5, "Example C: Shift+drag selects 5 of 6 trees")
	assert_false(model.is_selected(t6), "6th tree outside box must NOT be selected")

	# 2) Shift+drag starting over a tree (t5 -> t6) adds t6 idempotently without toggling off t5.
	var p5 := _source_screen_point(view, t5)
	var p6 := _source_screen_point(view, t6)
	var d56 := p6 - p5
	await _left_drag(view, p5, p6 + Vector2(20.0 if d56.x >= 0.0 else -20.0, 20.0 if d56.y >= 0.0 else -20.0), true, true, true)
	assert_eq(model.get_count_for_resource(&"wood"), 6, "Shift+drag starting on tree adds t6 and keeps t1..t5")

	# 3) Shift+drag starting on a rock adds rock while preserving all 6 trees.
	_focus_camera(main, Vector2(r1.global_position.x, r1.global_position.z), 22.0)
	await wait_process_frames(2)
	var pr1 := _source_screen_point(view, r1)
	await _left_drag(view, pr1, pr1 + Vector2(45.0, 45.0), true, true, true)
	assert_true(model.is_selected(r1), "Shift+drag starting on rock selects r1")
	assert_eq(model.get_count_for_resource(&"wood"), 6, "Prior wood selection preserved")

	# 4) Shift+drag starting on a bush adds bush while preserving trees + rock.
	_focus_camera(main, Vector2(b1.global_position.x, b1.global_position.z), 22.0)
	await wait_process_frames(2)
	var pb1 := _source_screen_point(view, b1)
	await _left_drag(view, pb1, pb1 + Vector2(45.0, 45.0), true, true, true)
	assert_true(model.is_selected(b1), "Shift+drag starting on bush selects b1")

	# 5) Shift+drag starting over a unit does NOT alter unit selection and adds sources inside box.
	var b2 := _find_source_by_id(main, &"food_bush_02")
	assert_not_null(b2)
	if b2 != null:
		leader_a.global_position = b2.global_position + Vector3(-2.2, 0.0, 1.4)
		_focus_camera(main, Vector2(b2.global_position.x, b2.global_position.z), 22.0)
		await wait_process_frames(2)
		var pu := _unit_screen_point(view, leader_a)
		var pb2 := _source_screen_point(view, b2)
		var du := pb2 - pu
		await _left_drag(view, pu, pb2 + Vector2(28.0 if du.x >= 0.0 else -28.0, 28.0 if du.y >= 0.0 else -28.0), true, true, true)
		assert_true(model.is_selected(b2), "Shift+drag starting on unit adds b2")
		assert_eq(selection.get_selected_units(), [leader_a], "Shift+drag starting on unit preserves SelectionManager")

	# 6) Empty Shift+drag (no sources in box) preserves prior selection and NEVER falls back to unit box.
	var count_before_empty: int = model.get_selected_count()
	_focus_camera(main, Vector2(-8.0, 10.0), 22.0)
	await wait_process_frames(2)
	var empty_pt := _world_screen_point(view, Vector3(-8.0, 0.0, 10.0))
	await _left_drag(view, empty_pt, empty_pt + Vector2(85.0, 65.0), true, true, true)
	assert_eq(model.get_selected_count(), count_before_empty, "Empty Shift+drag preserves prior source selection")
	assert_eq(selection.get_selected_units(), [leader_a], "Empty Shift+drag never alters unit selection")
	assert_eq(board.get_active_tasks().size(), 0, "Zero tasks created during all selection drags")

	await _teardown_fixture(view)


func _push_motion(view: SubViewport, pos: Vector2, shift_held: bool) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.shift_pressed = shift_held
	view.push_input(mm, true)
	await wait_process_frames(1)


func _push_left_button(view: SubViewport, pos: Vector2, pressed: bool, shift_held: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.global_position = pos
	ev.pressed = pressed
	ev.shift_pressed = shift_held
	view.push_input(ev, true)
	await wait_process_frames(1)


func test_d1_07_f01_pre_and_post_threshold_shift_capture_and_esc_hygiene() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var selection := main.get_selection_manager()
	var hud := main.get_community_selection_actions_hud()
	var overlay := main.get_selection_box_overlay()
	var ctrl := main.get_input_controller() as AutonomousGatherInput
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	assert_not_null(leader_a)
	assert_not_null(leader_b)
	assert_not_null(t1)
	assert_not_null(t2)
	assert_not_null(ctrl)
	if leader_a == null or leader_b == null or t1 == null or t2 == null or ctrl == null:
		await _teardown_fixture(view)
		return

	var sub_px: float = ctrl.get_drag_threshold_px() * 0.4
	leader_a.global_position = t1.global_position + Vector3(-2.0, 0.0, 1.5)
	_focus_camera(main, Vector2(t1.global_position.x, t1.global_position.z), 22.0)
	await wait_process_frames(2)

	var p1 := _source_screen_point(view, t1)
	var pu := _unit_screen_point(view, leader_a)
	var box_start := Vector2(minf(p1.x, pu.x) - 45.0, minf(p1.y, pu.y) - 45.0)
	var box_end := Vector2(maxf(p1.x, pu.x) + 45.0, maxf(p1.y, pu.y) + 45.0)
	var box_cross := box_start + Vector2(ctrl.get_drag_threshold_px() + 10.0, ctrl.get_drag_threshold_px() + 10.0)

	# F01-A (pre-threshold False -> True): press without Shift, move below threshold, press Shift BEFORE crossing threshold.
	model.clear()
	selection.select_single(leader_b)
	await _push_motion(view, box_start, false)
	await _push_left_button(view, box_start, true, false)
	await _push_motion(view, box_start + Vector2(sub_px, 0.0), false)
	assert_false(overlay.is_box_active(), "F01-A: Sub-threshold motion does not lock mode yet")
	await _push_motion(view, box_cross, true)
	assert_true(overlay.is_box_active(), "F01-A: Overlay active after crossing threshold")
	assert_true(overlay.is_source_mode(), "F01-A: Pressing Shift BEFORE threshold locks SOURCE_BOX_ADD overlay")
	await _push_motion(view, box_end, true)
	await _push_left_button(view, box_end, false, true)
	await wait_process_frames(1)
	assert_true(model.is_selected(t1), "F01-A: Pressing Shift before threshold selects sources")
	assert_eq(selection.get_selected_units(), [leader_b], "F01-A: RTS unit selection preserved")
	assert_eq(board.get_active_tasks().size(), 0, "F01-A: Zero tasks created by selection")

	# F01-B (pre-threshold True -> False): press WITH Shift, move below threshold, release Shift BEFORE crossing threshold.
	model.clear()
	selection.clear_selection()
	await _push_motion(view, box_start, true)
	await _push_left_button(view, box_start, true, true)
	await _push_motion(view, box_start + Vector2(sub_px, 0.0), true)
	assert_false(overlay.is_box_active(), "F01-B: Sub-threshold motion does not lock mode yet")
	await _push_motion(view, box_cross, false)
	assert_true(overlay.is_box_active(), "F01-B: Overlay active after crossing threshold")
	assert_false(overlay.is_source_mode(), "F01-B: Releasing Shift BEFORE threshold locks UNIT_BOX_RTS overlay")
	await _push_motion(view, box_end, false)
	await _push_left_button(view, box_end, false, false)
	await wait_process_frames(1)
	assert_true(selection.is_selected(leader_a), "F01-B: Releasing Shift before threshold performs RTS unit box selection")
	assert_true(model.is_empty(), "F01-B: Zero sources added when Shift released before threshold")
	assert_eq(board.get_active_tasks().size(), 0, "F01-B: Zero tasks created")

	# F01-C (post-threshold True -> False): cross threshold WITH Shift, then release Shift AFTER threshold.
	model.clear()
	selection.select_single(leader_b)
	await _push_motion(view, box_start, true)
	await _push_left_button(view, box_start, true, true)
	await _push_motion(view, box_cross, true)
	assert_true(overlay.is_source_mode(), "F01-C: Locked SOURCE_BOX_ADD at threshold")
	await _push_motion(view, box_end, false)
	assert_true(overlay.is_source_mode(), "F01-C: Overlay stays SOURCE_BOX_ADD after releasing Shift post-threshold")
	await _push_left_button(view, box_end, false, false)
	await wait_process_frames(1)
	assert_true(model.is_selected(t1), "F01-C: Releasing Shift AFTER threshold keeps locked SOURCE_BOX_ADD")
	assert_eq(selection.get_selected_units(), [leader_b], "F01-C: Unit selection untouched")

	# F01-D (post-threshold False -> True): cross threshold WITHOUT Shift, then press Shift AFTER threshold.
	model.clear()
	selection.clear_selection()
	await _push_motion(view, box_start, false)
	await _push_left_button(view, box_start, true, false)
	await _push_motion(view, box_cross, false)
	assert_false(overlay.is_source_mode(), "F01-D: Locked UNIT_BOX_RTS at threshold")
	await _push_motion(view, box_end, true)
	assert_false(overlay.is_source_mode(), "F01-D: Overlay stays UNIT_BOX_RTS after pressing Shift post-threshold")
	await _push_left_button(view, box_end, false, true)
	await wait_process_frames(1)
	assert_true(selection.is_selected(leader_a), "F01-D: Pressing Shift AFTER threshold keeps locked UNIT_BOX_RTS")
	assert_true(model.is_empty(), "F01-D: Locked UNIT_BOX_RTS does NOT add sources")

	# F01-E (threshold crossed ONLY on release: press False -> release True with zero intermediate motion).
	model.clear()
	selection.select_single(leader_b)
	await _push_motion(view, box_start, false)
	await _push_left_button(view, box_start, true, false)
	await _push_left_button(view, box_end, false, true)
	await wait_process_frames(1)
	assert_true(model.is_selected(t1), "F01-E: Release-only threshold with Shift=true locks SOURCE_BOX_ADD")
	assert_eq(selection.get_selected_units(), [leader_b], "F01-E: Unit selection preserved on release-only source drag")

	# F01-F (threshold crossed ONLY on release: press True -> release False with zero intermediate motion).
	model.clear()
	selection.clear_selection()
	await _push_motion(view, box_start, true)
	await _push_left_button(view, box_start, true, true)
	await _push_left_button(view, box_end, false, false)
	await wait_process_frames(1)
	assert_true(selection.is_selected(leader_a), "F01-F: Release-only threshold with Shift=false locks UNIT_BOX_RTS")
	assert_true(model.is_empty(), "F01-F: Zero sources selected on release-only RTS drag")

	# F01-G (Esc cancellation during locked source drag + release ignored + next gesture clean + Esc preserves active tasks).
	model.clear()
	selection.clear_selection()
	var p2 := _source_screen_point(view, t2)
	await _push_motion(view, p2 - Vector2(40.0, 40.0), true)
	await _push_left_button(view, p2 - Vector2(40.0, 40.0), true, true)
	await _push_motion(view, p2 + Vector2(40.0, 40.0), true)
	assert_true(overlay.is_box_active(), "F01-G: Box overlay active before Esc")
	assert_true(overlay.is_source_mode(), "F01-G: Overlay uses source style during locked Shift+drag")

	await _press_escape(view)
	assert_false(overlay.is_box_active(), "F01-G: Esc cancels active source drag")
	assert_false(overlay.is_source_mode(), "F01-G: Esc resets overlay source style cleanly")
	assert_true(model.is_empty(), "F01-G: Cancelled drag must NOT select sources")
	await _push_left_button(view, p2 + Vector2(40.0, 40.0), false, true)
	assert_true(model.is_empty(), "F01-G: Release after Esc cancellation is ignored")

	# Next independent gesture (unshifted RTS drag) has zero residual Shift state.
	await _push_motion(view, box_start, false)
	await _push_left_button(view, box_start, true, false)
	await _push_motion(view, box_cross, false)
	assert_false(overlay.is_source_mode(), "F01-G: Next unshifted gesture has zero residual source overlay style")
	await _push_motion(view, box_end, false)
	await _push_left_button(view, box_end, false, false)
	assert_true(selection.is_selected(leader_a), "F01-G: Next unshifted gesture selects RTS unit cleanly")
	assert_true(model.is_empty(), "F01-G: Next unshifted gesture adds zero sources")

	# Esc outside drag clears selection and hides HUD, WITHOUT cancelling authorized tasks.
	model.select_single(t1)
	var wood_btn := hud.get_category_button(&"wood")
	await _click_hud_button(view, wood_btn)
	await wait_process_frames(3)
	assert_eq(board.get_active_tasks().size(), 1, "F01-G: Task active after explicit HUD authorization")

	await _press_escape(view)
	await wait_process_frames(2)
	assert_true(model.is_empty(), "F01-G: Esc clears source selection")
	assert_false(hud.is_panel_visible(), "F01-G: HUD hides after Esc clears selection")
	assert_eq(board.get_active_tasks().size(), 1, "F01-G: Esc must NEVER cancel active community tasks")

	await _teardown_fixture(view)


func test_d1_08_example_d_selective_authorization_preserves_selection_and_idempotency() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var inv := main.get_settlement_inventory()
	var g_in := main.get_input_controller() as AutonomousGatherInput
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	var r2 := _find_source_by_id(main, &"stone_rock_02")
	var b1 := _find_source_by_id(main, &"food_bush_01")
	assert_not_null(t1)
	assert_not_null(t2)
	assert_not_null(r1)
	assert_not_null(r2)
	assert_not_null(b1)
	if t1 == null or t2 == null or r1 == null or r2 == null or b1 == null:
		await _teardown_fixture(view)
		return

	var wood_before: int = inv.get_amount(&"wood")
	var stone_before: int = inv.get_amount(&"stone")
	var food_before: int = inv.get_amount(&"food")

	# Mixed heterogeneous selection across 3 categories.
	model.add_sources([t1, t2, r1, r2, b1])
	await wait_process_frames(2)

	assert_eq(board.get_active_tasks().size(), 0, "Mixed selection creates 0 tasks")
	assert_eq(inv.get_amount(&"wood"), wood_before, "Selection causes zero economic change (wood)")
	assert_eq(inv.get_amount(&"stone"), stone_before, "Selection causes zero economic change (stone)")
	assert_eq(inv.get_amount(&"food"), food_before, "Selection causes zero economic change (food)")
	assert_eq(hud.get_visible_category_ids(), [&"wood", &"stone", &"food"])
	assert_eq(hud.get_category_count_text(&"wood"), "2")
	assert_eq(hud.get_category_count_text(&"stone"), "2")
	assert_eq(hud.get_category_count_text(&"food"), "1")
	assert_eq(hud.get_category_visual_state(&"wood"), CommunitySelectionActionsHud.STATE_AVAILABLE)

	# Authorize ONLY wood via HUD click.
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(3)

	assert_eq(board.get_active_tasks().size(), 2, "Only the 2 wood sources become active tasks")
	assert_not_null(board.get_active_task_for_source(t1))
	assert_not_null(board.get_active_task_for_source(t2))
	assert_null(board.get_active_task_for_source(r1), "Stone must NOT be authorized when clicking wood")
	assert_null(board.get_active_task_for_source(r2), "Stone must NOT be authorized when clicking wood")
	assert_null(board.get_active_task_for_source(b1), "Food must NOT be authorized when clicking wood")
	assert_eq(model.get_selected_count(), 5, "Authorizing wood MUST preserve the entire mixed selection")
	assert_eq(hud.get_category_visual_state(&"wood"), CommunitySelectionActionsHud.STATE_AUTHORIZED)
	assert_eq(hud.get_category_visual_state(&"stone"), CommunitySelectionActionsHud.STATE_AVAILABLE)

	var wood_task_ids: Array[int] = [
		board.get_active_task_for_source(t1).task_id,
		board.get_active_task_for_source(t2).task_id,
	]

	# Repeating click on wood button is strictly idempotent (zero duplicate tasks).
	var repeat_res: Dictionary = g_in.authorize_selected_category(&"wood")
	assert_true(bool(repeat_res.get("ok", false)))
	assert_eq((repeat_res.get("created_tasks", []) as Array).size(), 0, "Idempotent click creates 0 duplicate tasks")
	assert_eq(board.get_active_tasks().size(), 2)
	assert_eq(board.get_active_task_for_source(t1).task_id, wood_task_ids[0])
	assert_eq(board.get_active_task_for_source(t2).task_id, wood_task_ids[1])

	# Successive authorization of stone from the preserved selection.
	await _click_hud_button(view, hud.get_category_button(&"stone"))
	await wait_process_frames(3)
	assert_eq(board.get_active_tasks().size(), 4, "2 wood + 2 stone tasks now active")
	assert_not_null(board.get_active_task_for_source(r1))
	assert_not_null(board.get_active_task_for_source(r2))
	assert_null(board.get_active_task_for_source(b1), "Food still unauthorized")
	assert_eq(model.get_selected_count(), 5, "Selection still preserved after successive authorization")

	await _teardown_fixture(view)


func test_d1_09_d1c_explicit_reauthorization_vs_incidental_events_and_personal_order_respect() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var cmd := main.get_command_controller()
	var selection := main.get_selection_manager()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	assert_not_null(leader_a)
	assert_not_null(leader_b)
	assert_not_null(t1)
	if leader_a == null or leader_b == null or t1 == null:
		await _teardown_fixture(view)
		return

	model.select_single(t1)
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(4)
	await wait_physics_frames(2)

	var task: WorkTask = board.get_active_task_for_source(t1)
	assert_not_null(task, "Task registered for t1")
	if task == null:
		await _teardown_fixture(view)
		return
	var original_task_id: int = task.task_id
	var original_group_id: int = task.group_id
	assert_not_null(task.assigned_unit, "An idle worker is assigned to t1")

	# Player manually overrides the first assigned worker, then the second worker when reassigned,
	# driving the task naturally into BLOCKED_REAUTHORIZATION.
	for override_idx: int in range(2):
		if task.is_blocked_reauthorization():
			break
		var w: Unit = task.assigned_unit
		if w != null:
			selection.select_single(w)
			var dest := Vector3(4.0 + float(override_idx) * 2.0, 0.0, 12.0)
			assert_true(cmd.command_at(PickResult.from_ground(dest, Vector3.UP)), "Manual override #%d issued" % (override_idx + 1))
			await wait_process_frames(4)
			await wait_physics_frames(2)

	assert_true(task.is_blocked_reauthorization(), "Manual overrides transition task to BLOCKED_REAUTHORIZATION")
	assert_eq(hud.get_category_visual_state(&"wood"), CommunitySelectionActionsHud.STATE_BLOCKED_REAUTH, "HUD reflects BLOCKED_REAUTHORIZATION")

	# Incidental events must NEVER silently unblock BLOCKED_REAUTHORIZATION:
	# 1) Deselect & reselect source.
	model.clear()
	await wait_process_frames(2)
	model.select_single(t1)
	await wait_process_frames(2)
	assert_true(task.is_blocked_reauthorization(), "Reselecting source must NOT silently unblock")

	# 2) Worker becomes IDLE (cancelling personal order).
	leader_a.cancel_current_order(UnitOrder.REASON_CANCELLED)
	await wait_process_frames(4)
	assert_true(task.is_blocked_reauthorization(), "Free worker becoming IDLE must NOT silently unblock")

	# 3) Inventory change / dispatcher flush / HUD refresh.
	main.get_settlement_inventory().inventory_changed.emit()
	dispatcher.request_dispatch()
	hud.refresh()
	await wait_process_frames(4)
	assert_true(task.is_blocked_reauthorization(), "Inventory/dispatcher/HUD refresh must NOT silently unblock")

	# Put leader_b on a personal order so reauthorization respects personal orders and assigns only idle leader_a.
	selection.select_single(leader_b)
	assert_true(cmd.command_at(PickResult.from_ground(Vector3(-19.0, 0.0, -13.0), Vector3.UP)), "LeaderB personal move issued")
	await wait_process_frames(2)
	var b_personal_order: UnitOrder = leader_b.get_current_order()
	assert_not_null(b_personal_order, "LeaderB executing personal order")

	# Explicit HUD click reauthorizes ONLY selected category's blocked task (D1-C).
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(4)
	await wait_physics_frames(2)

	assert_eq(task.task_id, original_task_id, "D1-C: Reauthorization preserves task_id")
	assert_eq(task.group_id, original_group_id, "D1-C: Reauthorization preserves group_id")
	assert_false(task.is_blocked_reauthorization(), "D1-C: Explicit HUD click clears BLOCKED_REAUTHORIZATION")
	assert_true(task.excluded_unit_ids.is_empty(), "D1-C: Excluded unit IDs cleared on reauthorized task")
	assert_eq(task.assigned_unit, leader_a, "D1-C: Idle LeaderA dispatched after explicit reauthorization")
	assert_eq(leader_b.get_current_order(), b_personal_order, "D1-C: LeaderB personal order strictly respected")

	await _teardown_fixture(view)


func test_d1_10_economy_blocked_guard_and_hud_disabled_state() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var feedback := main.get_autonomous_gather_feedback()
	var hud := main.get_community_selection_actions_hud()
	var g_in := main.get_input_controller() as AutonomousGatherInput
	var model := main.get_source_selection_model()
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	assert_not_null(t1)
	if t1 == null:
		await _teardown_fixture(view)
		return

	# Simulate blocked provenance admission honestly on input + HUD.
	g_in.configure_community_work(board, dispatcher, feedback, true, "ambiguous_domain", hud)
	hud.configure(model, board, true, "ambiguous_domain")
	model.select_single(t1)
	await wait_process_frames(2)

	var wood_btn := hud.get_category_button(&"wood")
	assert_true(hud.is_panel_visible(), "HUD visible with disabled blocked state")
	assert_eq(hud.get_category_visual_state(&"wood"), CommunitySelectionActionsHud.STATE_ECONOMY_BLOCKED)
	assert_true(wood_btn.disabled, "HUD button disabled when economy admission is blocked")

	var res: Dictionary = g_in.authorize_selected_category(&"wood")
	assert_false(bool(res.get("ok", true)), "authorize_selected_category refuses when economy is blocked")
	assert_eq(String(res.get("reason", "")), "economy_blocked")
	assert_eq(board.get_active_tasks().size(), 0, "Zero tasks registered when economy is blocked")

	await _teardown_fixture(view)


func test_d1_11_hud_icons_no_stop_button_zero_polling_and_anti_click_through() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var hud := main.get_community_selection_actions_hud()
	var model := main.get_source_selection_model()
	var selection := main.get_selection_manager()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	var b1 := _find_source_by_id(main, &"food_bush_01")
	assert_not_null(leader_a)
	assert_not_null(t1)
	assert_not_null(r1)
	assert_not_null(b1)
	if leader_a == null or t1 == null or r1 == null or b1 == null:
		await _teardown_fixture(view)
		return

	# Zero polling guarantees.
	assert_false(hud.is_processing(), "HUD must NOT poll in _process")
	assert_false(hud.is_physics_processing(), "HUD must NOT poll in _physics_process")
	assert_false(board.is_processing(), "Board must NOT poll in _process")
	assert_false(board.is_physics_processing(), "Board must NOT poll in _physics_process")
	assert_false(dispatcher.is_processing(), "Dispatcher must NOT poll in _process")
	assert_false(dispatcher.is_physics_processing(), "Dispatcher must NOT poll in _physics_process")

	# D1-A: No stop button in D1 and independent minimalist icons loaded.
	assert_false(hud.has_stop_button(), "D1-A: Parar button must NOT exist in D1")
	assert_eq((hud.get_category_button(&"wood").get_node("Content/Icon") as TextureRect).texture, D1_ICON_WOOD)
	assert_eq((hud.get_category_button(&"stone").get_node("Content/Icon") as TextureRect).texture, D1_ICON_STONE)
	assert_eq((hud.get_category_button(&"food").get_node("Content/Icon") as TextureRect).texture, D1_ICON_FOOD)

	# Anti-click-through: select leader_a + t1; click HUD wood button; verify leader_a selection NOT cleared by world click-through!
	selection.select_single(leader_a)
	model.add_sources([t1, r1, b1])
	await wait_process_frames(2)
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(3)

	assert_eq(selection.get_selected_units(), [leader_a], "Anti-click-through: HUD click must NOT clear unit selection behind panel")
	assert_eq(model.get_selected_count(), 3, "Anti-click-through: HUD click must NOT clear source selection")
	assert_eq(board.get_active_tasks().size(), 1, "HUD click authorized wood task cleanly")

	await _teardown_fixture(view)


func test_d1_12_hud_layout_geometry_720p_and_1080p_zero_overlap() -> void:
	for res: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var view := await _fixture(res)
		var main := view.get_child(0) as MainScene
		var model := main.get_source_selection_model()
		var hud := main.get_community_selection_actions_hud()
		var selection := main.get_selection_manager()
		var leader_a := _find_unit_by_id(main, &"leader_a")
		var t1 := _find_source_by_id(main, &"wood_tree_01")
		var r1 := _find_source_by_id(main, &"stone_rock_01")
		var b1 := _find_source_by_id(main, &"food_bush_01")
		assert_not_null(leader_a)
		assert_not_null(t1)
		assert_not_null(r1)
		assert_not_null(b1)
		if leader_a == null or t1 == null or r1 == null or b1 == null:
			await _teardown_fixture(view)
			return

		# Select a unit so SelectedUnitPanel is visible simultaneously at bottom-left,
		# alongside TemporaryPlacementBar at bottom-right and ResourceHud/ConstructionHud.
		selection.select_single(leader_a)
		model.add_sources([t1, r1, b1])
		await wait_process_frames(3)

		var vp_rect := Rect2(Vector2.ZERO, Vector2(res))
		var hud_rect: Rect2 = hud.get_panel_rect()
		assert_true(hud_rect.size.x > 0.0 and hud_rect.size.y > 0.0, "HUD rect valid at %s" % str(res))
		assert_true(vp_rect.encloses(hud_rect), "HUD rect fully inside viewport at %s" % str(res))

		var unit_panel: Control = main.get_resource_hud().get_selected_unit_panel()
		if unit_panel != null and unit_panel.visible:
			assert_false(hud_rect.intersects(unit_panel.get_global_rect()), "No overlap with SelectedUnitPanel at %s" % str(res))

		var stockpile_panel: Control = main.get_resource_hud().get_stockpile_panel()
		if stockpile_panel != null and stockpile_panel.visible:
			assert_false(hud_rect.intersects(stockpile_panel.get_global_rect()), "No overlap with SettlementStockpilePanel at %s" % str(res))

		var placement_bar: Control = main.get_placement_test_overlay().get_node_or_null("TemporaryPlacementBar") as Control
		if placement_bar != null and placement_bar.visible:
			assert_false(hud_rect.intersects(placement_bar.get_global_rect()), "No overlap with TemporaryPlacementBar at %s" % str(res))

		var construction_hud: Control = main.get_node_or_null("UiLayer/ConstructionHud/ConstructionBar") as Control
		if construction_hud != null and construction_hud.visible:
			assert_false(hud_rect.intersects(construction_hud.get_global_rect()), "No overlap with ConstructionBar at %s" % str(res))

		await _teardown_fixture(view)


func test_d1_13_four_visual_ring_states_and_zero_orphan_rings_on_teardown() -> void:
	## R-03A D1 R2 (Decision V2 / H-V03):
	## Validates the 4 owner-approved visual states (selection ring vs work-activity symbol):
	## 1. Available: no ring, no symbol.
	## 2. Selected: selection ring only, no symbol.
	## 3. Selected + Authorized: selection ring + work-activity symbol.
	## 4. Authorized (unselected): no ring, work-activity symbol preserved.
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var g_in := main.get_input_controller() as AutonomousGatherInput
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	assert_not_null(t1)
	if t1 == null:
		await _teardown_fixture(view)
		return

	# State 1: Available (unselected, no task) -> 0 rings, 0 work symbols.
	assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 0, "State 1: no selection ring")
	assert_eq(_count_rings_on_source(t1, "AutoGatherWorkMarker_"), 0, "State 1: no work symbol")
	assert_eq(_count_rings_on_source(t1, "AutoGatherTaskRing_"), 0, "State 1: legacy double-ring absent")

	# State 2: Selected (not authorized) -> selection ring only, no work symbol.
	model.select_single(t1)
	await wait_process_frames(2)
	assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 1, "State 2: selection ring attached")
	assert_eq(_count_rings_on_source(t1, "AutoGatherWorkMarker_"), 0, "State 2: still 0 work symbols")

	# State 3: Selected + Authorized -> selection ring + work symbol simultaneously.
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(3)
	assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 1, "State 3: selection ring kept")
	assert_eq(_count_rings_on_source(t1, "AutoGatherWorkMarker_"), 1, "State 3: work-activity symbol attached alongside selection ring")
	assert_eq(_count_rings_on_source(t1, "AutoGatherTaskRing_"), 0, "State 3: legacy inner task ring no longer created")

	# State 4: Deselected + Authorized -> work symbol remains, selection ring removed.
	model.clear()
	await wait_process_frames(2)
	assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 0, "State 4: selection ring removed on deselect")
	assert_eq(_count_rings_on_source(t1, "AutoGatherWorkMarker_"), 1, "State 4: work-activity symbol preserved after deselect")

	# Teardown hygiene: zero orphan rings or work symbols anywhere on map.
	model.select_single(t1)
	await wait_process_frames(1)
	g_in.teardown_community_work()
	await wait_process_frames(2)
	assert_eq(_count_all_rings(main, "SourceSelectionRing_"), 0, "Zero orphan selection rings after teardown")
	assert_eq(_count_all_rings(main, "AutoGatherWorkMarker_"), 0, "Zero orphan work symbols after teardown")

	await _teardown_fixture(view)


func test_d1_14_t01a_reauthorization_refused_under_blocked_admission_preserves_state() -> void:
	## R-03A D1 R1 — T01-A:
	## Step 1-5: Real behavioral flow produces a legitimate BLOCKED_REAUTHORIZATION task via HUD + personal overrides.
	## Step 6-7: Minimal controlled configuration establishes blocked economic admission (declared explicitly as controlled
	##           fixture because production MainScene evaluates admission once at _ready with no dynamic transition API),
	##           then verifies HUD disabled state, public API refusal, and full preservation of task/orders/economy.
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var feedback := main.get_autonomous_gather_feedback()
	var hud := main.get_community_selection_actions_hud()
	var g_in := main.get_input_controller() as AutonomousGatherInput
	var model := main.get_source_selection_model()
	var selection := main.get_selection_manager()
	var cmd := main.get_command_controller()
	var inventory := main.get_settlement_inventory()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	assert_not_null(leader_a)
	assert_not_null(leader_b)
	assert_not_null(t1)
	if leader_a == null or leader_b == null or t1 == null:
		await _teardown_fixture(view)
		return

	# 1-4: Authorize via real HUD and drive task legitimately into BLOCKED_REAUTHORIZATION via personal moves.
	model.select_single(t1)
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(4)
	await wait_physics_frames(2)

	var task: WorkTask = board.get_active_task_for_source(t1)
	assert_not_null(task, "T01-A: Initial wood task registered via HUD")
	if task == null:
		await _teardown_fixture(view)
		return

	for override_idx: int in range(2):
		if task.is_blocked_reauthorization():
			break
		var w: Unit = task.assigned_unit
		if w != null:
			selection.select_single(w)
			var dest := Vector3(4.0 + float(override_idx) * 2.0, 0.0, 12.0)
			assert_true(cmd.command_at(PickResult.from_ground(dest, Vector3.UP)), "T01-A: Personal override #%d issued" % (override_idx + 1))
			await wait_process_frames(4)
			await wait_physics_frames(2)

	assert_true(task.is_blocked_reauthorization(), "T01-A: Task legitimately in BLOCKED_REAUTHORIZATION")
	assert_eq(task.excluded_unit_ids.size(), 2, "T01-A: Both leaders recorded in excluded_unit_ids")

	# Free leader_a (so an idle worker exists) while keeping leader_b on a real personal order.
	leader_a.cancel_current_order(UnitOrder.REASON_CANCELLED)
	selection.select_single(leader_b)
	assert_true(cmd.command_at(PickResult.from_ground(Vector3(-18.0, 0.0, -14.0), Vector3.UP)), "T01-A: LeaderB personal order active")
	await wait_process_frames(2)
	var b_personal_order: UnitOrder = leader_b.get_current_order()

	# 5: Snapshot identity, exclusions, task counts, and economic state before blocked reauthorization attempt.
	var orig_task_id: int = task.task_id
	var orig_group_id: int = task.group_id
	var orig_exclusions: Dictionary = task.excluded_unit_ids.duplicate(true)
	var orig_all_tasks_count: int = board.get_all_tasks().size()
	var wood_stock_before: int = inventory.get_physical_amount(&"wood")
	var t1_rem_before: int = t1.get_remaining_amount()
	var a_weight_before: int = leader_a.get_carry_load().get_current_weight()
	var b_weight_before: int = leader_b.get_carry_load().get_current_weight()

	# 6: Minimal controlled fixture applying blocked economic admission reason via supported configure APIs.
	var blocked_reason: String = "load_unavailable_for_admission"
	g_in.configure_community_work(board, dispatcher, feedback, true, blocked_reason, hud)
	hud.configure(model, board, true, blocked_reason)
	model.select_single(t1)
	await wait_process_frames(2)

	var wood_btn: Button = hud.get_category_button(&"wood")
	assert_true(hud.is_panel_visible(), "T01-A: HUD panel visible with selected blocked source")
	assert_eq(hud.get_category_visual_state(&"wood"), CommunitySelectionActionsHud.STATE_ECONOMY_BLOCKED, "T01-A: HUD indicates economy_blocked")
	assert_true(wood_btn.disabled, "T01-A: HUD button disabled under blocked economic admission")

	# 7: Attempt explicit reauthorization via public API (defense-in-depth while HUD button is disabled).
	feedback.last_message = ""
	var res: Dictionary = g_in.authorize_selected_category(&"wood")
	await wait_process_frames(3)
	await wait_physics_frames(2)

	assert_false(bool(res.get("ok", true)), "T01-A: Public authorization API refuses reauthorization under blocked admission")
	assert_eq(String(res.get("reason", "")), "economy_blocked", "T01-A: Refusal reason is economy_blocked")
	assert_string_contains(feedback.last_message.to_lower(), "bloqueada", "T01-A: Honest blocked feedback shown")
	assert_eq(task.state, WorkTask.State.BLOCKED_REAUTHORIZATION, "T01-A: Task remains BLOCKED_REAUTHORIZATION")
	assert_eq(task.task_id, orig_task_id, "T01-A: task_id preserved")
	assert_eq(task.group_id, orig_group_id, "T01-A: group_id preserved")
	assert_eq(task.excluded_unit_ids, orig_exclusions, "T01-A: excluded_unit_ids preserved verbatim")
	assert_eq(board.get_all_tasks().size(), orig_all_tasks_count, "T01-A: Zero new tasks created")
	assert_null(task.assigned_unit, "T01-A: Zero worker assigned to blocked task")
	assert_null(leader_a.get_current_order(), "T01-A: Idle LeaderA not dispatched")
	assert_eq(leader_b.get_current_order(), b_personal_order, "T01-A: LeaderB personal order untouched")
	assert_eq(inventory.get_physical_amount(&"wood"), wood_stock_before, "T01-A: Wood stock invariant")
	assert_eq(t1.get_remaining_amount(), t1_rem_before, "T01-A: Source remaining invariant")
	assert_eq(leader_a.get_carry_load().get_current_weight(), a_weight_before, "T01-A: LeaderA carry invariant")
	assert_eq(leader_b.get_carry_load().get_current_weight(), b_weight_before, "T01-A: LeaderB carry invariant")

	await _teardown_fixture(view)


func test_d1_15_t01b_reauthorization_during_regional_tx_and_selective_scope() -> void:
	## R-03A D1 R1 — T01-B + Selective Reauthorization:
	## Exercises explicit reauthorization of a blocked wood task INSIDE an authentic ReservedWithdrawalCoordinator
	## transaction (real ConstructOrder on LeaderB), using a declared focal reentrant _flush_dispatch() probe to
	## verify the economy_busy guard during the active RegionalAuthority operation, followed by spontaneous
	## event-driven resumption from inventory_changed (ZERO manual request_dispatch()), while proving an unrelated
	## blocked stone task outside the selection/category remains BLOCKED_REAUTHORIZATION with exclusions intact.
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var dispatcher := main.get_community_task_dispatcher()
	var hud := main.get_community_selection_actions_hud()
	var g_in := main.get_input_controller() as AutonomousGatherInput
	var model := main.get_source_selection_model()
	var selection := main.get_selection_manager()
	var cmd := main.get_command_controller()
	var inventory := main.get_settlement_inventory()
	var cm := main.get_construction_manager()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var leader_b := _find_unit_by_id(main, &"leader_b")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	assert_not_null(leader_a)
	assert_not_null(leader_b)
	assert_not_null(t1)
	assert_not_null(r1)
	assert_not_null(cm)
	if leader_a == null or leader_b == null or t1 == null or r1 == null or cm == null:
		await _teardown_fixture(view)
		return

	var world := main.get_world_3d()
	var region_id: StringName = cm.get_region_id()
	t1.configure(t1.source_id, t1.get_definition(), 2, 2, 2)
	r1.configure(r1.source_id, r1.get_definition(), 1, 1, 2)

	# 1. Seed authentic physical piles and create a real ConstructionSite.
	assert_true(inventory.deposit(&"wood", 12), "T01-B: Camp wood deposited")
	assert_true(inventory.deposit(&"stone", 6), "T01-B: Camp stone deposited")
	var site_res: Dictionary = cm.try_create_site_from_placement(SHELTER_DEF, Vector3(-6.0, 0.0, -5.0))
	assert_true(bool(site_res.get("ok", false)), "T01-B: ConstructionSite created")
	var site := site_res.get("site") as ConstructionSite
	assert_not_null(site)
	if site == null:
		await _teardown_fixture(view)
		return

	# 2. Authorize wood (t1) and stone (r1) via HUD and legitimately drive BOTH into BLOCKED_REAUTHORIZATION.
	model.select_single(t1)
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(4)
	await wait_physics_frames(2)

	var wood_task: WorkTask = board.get_active_task_for_source(t1)
	assert_not_null(wood_task, "T01-B: Wood task active")
	if wood_task == null:
		await _teardown_fixture(view)
		return

	for override_idx: int in range(2):
		if wood_task.is_blocked_reauthorization():
			break
		var w: Unit = wood_task.assigned_unit
		if w != null:
			selection.select_single(w)
			cmd.command_at(PickResult.from_ground(Vector3(3.0 + float(override_idx) * 2.0, 0.0, 10.0), Vector3.UP))
			await wait_process_frames(4)
			await wait_physics_frames(2)
	leader_a.cancel_current_order(UnitOrder.REASON_CANCELLED)
	leader_b.cancel_current_order(UnitOrder.REASON_CANCELLED)
	await wait_process_frames(3)

	model.select_single(r1)
	await _click_hud_button(view, hud.get_category_button(&"stone"))
	await wait_process_frames(4)
	await wait_physics_frames(2)

	var stone_task: WorkTask = board.get_active_task_for_source(r1)
	assert_not_null(stone_task, "T01-B: Stone task active")
	if stone_task == null:
		await _teardown_fixture(view)
		return

	for override_idx: int in range(2):
		if stone_task.is_blocked_reauthorization():
			break
		var w: Unit = stone_task.assigned_unit
		if w != null:
			selection.select_single(w)
			cmd.command_at(PickResult.from_ground(Vector3(-3.0 - float(override_idx) * 2.0, 0.0, 10.0), Vector3.UP))
			await wait_process_frames(4)
			await wait_physics_frames(2)

	assert_true(wood_task.is_blocked_reauthorization(), "T01-B: Wood task legitimately blocked")
	assert_true(stone_task.is_blocked_reauthorization(), "T01-B: Stone task legitimately blocked (selective-scope control)")
	var orig_wood_id: int = wood_task.task_id
	var orig_wood_group: int = wood_task.group_id
	var orig_stone_id: int = stone_task.task_id
	var orig_stone_exclusions: Dictionary = stone_task.excluded_unit_ids.duplicate(true)

	# 3. Park LeaderA idle near camp and select ONLY t1 (leaving blocked r1 unselected and of another category).
	leader_a.cancel_current_order(UnitOrder.REASON_CANCELLED)
	leader_b.cancel_current_order(UnitOrder.REASON_CANCELLED)
	leader_a.global_position = Vector3(-2.5, 0.0, 2.5)
	leader_b.global_position = Vector3(2.5, 0.0, 2.5)
	model.select_single(t1)
	await wait_process_frames(2)
	await wait_physics_frames(1)

	var wood_before_tx: int = inventory.get_physical_amount(&"wood")
	var stone_before_tx: int = inventory.get_physical_amount(&"stone")
	var t1_before_tx: int = t1.get_remaining_amount()
	var r1_before_tx: int = r1.get_remaining_amount()
	var tasks_count_before_tx: int = board.get_all_tasks().size()

	var assigned_events: Array[Dictionary] = []
	var on_assigned := func(tk: WorkTask, u: Unit, o: GatherResourceOrder) -> void:
		assigned_events.append({"task": tk, "unit": u, "order": o})
	dispatcher.task_assigned.connect(on_assigned)

	var obs: Dictionary = {
		"fired": false,
		"region_active": false,
		"authority_active_op": false,
		"inventory_busy": false,
		"dispatcher_busy": false,
		"reauth_ok": false,
		"reauth_count": 0,
		"state_after_reauth": -1,
		"blocked_reason_during_tx": "",
		"assigned_during_tx": null,
		"leader_a_order_during_tx": null,
		"flush_queued_after_probe": true,
		"assigned_count_during_tx": -1,
		"inventory_changed_after_probe": false,
	}

	var on_inv_changed := func() -> void:
		if bool(obs["fired"]):
			obs["inventory_changed_after_probe"] = true
	inventory.inventory_changed.connect(on_inv_changed)

	var on_res_changed := func() -> void:
		if bool(obs["fired"]):
			return
		obs["fired"] = true
		obs["region_active"] = ReservedWithdrawalCoordinator.is_region_transaction_active_readonly(world, region_id)
		var domains_raw: Variant = world.get_meta(ReservedWithdrawalCoordinator.DOMAIN_META, {})
		if domains_raw is Dictionary:
			var auth: ReservedWithdrawalCoordinator.RegionalAuthority = (domains_raw as Dictionary).get(region_id) as ReservedWithdrawalCoordinator.RegionalAuthority
			if auth != null:
				obs["authority_active_op"] = auth.has_active_operation()
		obs["inventory_busy"] = inventory.is_transaction_busy()
		obs["dispatcher_busy"] = bool(dispatcher.call("_is_economy_busy", t1))

		# Invoke explicit administrative reauthorization while RegionalAuthority transaction is active.
		var reauth_res: Dictionary = g_in.authorize_selected_category(&"wood")
		obs["reauth_ok"] = bool(reauth_res.get("ok", false))
		obs["reauth_count"] = (reauth_res.get("reauthorized_tasks", []) as Array).size()
		obs["state_after_reauth"] = wood_task.state

		# Declared focal guard probe: execute _flush_dispatch() reentrantly while RegionalAuthority is still locked.
		dispatcher.call("_flush_dispatch")
		obs["blocked_reason_during_tx"] = wood_task.last_reason
		obs["assigned_during_tx"] = wood_task.assigned_unit
		obs["leader_a_order_during_tx"] = leader_a.get_current_order()
		obs["flush_queued_after_probe"] = dispatcher._flush_queued
		obs["assigned_count_during_tx"] = assigned_events.size()
	inventory.reservations_changed.connect(on_res_changed)

	# 4. Command LeaderB onto real ConstructOrder so ReservedWithdrawalCoordinator runs an authentic withdrawal.
	assert_true(cmd.command_units_to_site(site, [leader_b]), "T01-B: Real ConstructOrder issued to LeaderB")
	Engine.time_scale = 3.0
	for _i: int in range(1200):
		if bool(obs["fired"]):
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0

	if inventory.reservations_changed.is_connected(on_res_changed):
		inventory.reservations_changed.disconnect(on_res_changed)

	# Verify active regional transaction & focal economy_busy guard during the callback.
	assert_true(bool(obs["fired"]), "T01-B: Authentic ReservedWithdrawalCoordinator callback fired")
	assert_true(bool(obs["region_active"]), "T01-B: RegionalAuthority transaction active readonly == true")
	assert_true(bool(obs["authority_active_op"]), "T01-B: RegionalAuthority.has_active_operation() == true")
	assert_true(bool(obs["inventory_busy"]), "T01-B: SettlementInventory.is_transaction_busy() == true")
	assert_true(bool(obs["dispatcher_busy"]), "T01-B: Dispatcher._is_economy_busy() == true during withdrawal")
	assert_true(bool(obs["reauth_ok"]), "T01-B: Administrative reauthorization accepted cleanly")
	assert_eq(int(obs["reauth_count"]), 1, "T01-B: Exactly 1 wood task reauthorized")
	assert_eq(int(obs["state_after_reauth"]), WorkTask.State.PENDING_WORKERS, "T01-B: Task transitions administratively to PENDING_WORKERS")
	assert_eq(String(obs["blocked_reason_during_tx"]), "economy_busy", "T01-B: Focal guard probe blocks dispatch with economy_busy")
	assert_null(obs["assigned_during_tx"], "T01-B: Zero worker assigned during active regional transaction")
	assert_null(obs["leader_a_order_during_tx"], "T01-B: Zero order issued to LeaderA during active transaction")
	assert_false(bool(obs["flush_queued_after_probe"]), "T01-B: Probe cleared _flush_queued prior to inventory_changed")
	assert_eq(int(obs["assigned_count_during_tx"]), 0, "T01-B: Zero task_assigned emitted during blocked window")
	assert_true(bool(obs["inventory_changed_after_probe"]), "T01-B: Withdrawal naturally emitted inventory_changed after probe")

	# 5. Spontaneous event-driven resumption (NO manual dispatcher.request_dispatch() call!).
	await wait_process_frames(3)
	await wait_physics_frames(1)
	if inventory.inventory_changed.is_connected(on_inv_changed):
		inventory.inventory_changed.disconnect(on_inv_changed)

	assert_eq(assigned_events.size(), 1, "T01-B: Spontaneous inventory_changed resumed and assigned wood_task exactly once")
	assert_eq(wood_task.task_id, orig_wood_id, "T01-B: Reauthorized task_id preserved")
	assert_eq(wood_task.group_id, orig_wood_group, "T01-B: Reauthorized group_id preserved")
	assert_eq(wood_task.assigned_unit, leader_a, "T01-B: Idle LeaderA picked up reauthorized wood_task")
	assert_true(leader_a.get_current_order() is GatherResourceOrder, "T01-B: LeaderA executing GatherResourceOrder")
	assert_true(leader_b.get_current_order() is ConstructOrder, "T01-B: LeaderB ConstructOrder remains sovereign")
	assert_eq(board.get_all_tasks().size(), tasks_count_before_tx, "T01-B: Zero duplicate tasks created")

	# Selective reauthorization check (§6.5): unrelated blocked stone_task stays untouched.
	assert_eq(stone_task.state, WorkTask.State.BLOCKED_REAUTHORIZATION, "T01-B: Unselected stone task remains BLOCKED_REAUTHORIZATION")
	assert_eq(stone_task.task_id, orig_stone_id, "T01-B: Unselected stone task_id intact")
	assert_eq(stone_task.excluded_unit_ids, orig_stone_exclusions, "T01-B: Unselected stone exclusions intact")
	assert_null(stone_task.assigned_unit, "T01-B: Unselected stone task has zero assigned worker")

	# 6. Complete reauthorized wood task and verify exact conservation + provenance.
	var site_req_wood: int = site.get_required_amount(&"wood")
	var site_req_stone: int = site.get_required_amount(&"stone")
	var site_completed: bool = false
	site.site_completed.connect(func(_s: ConstructionSite, _b: BuildingInstance) -> void: site_completed = true)
	Engine.time_scale = 3.0
	for _i: int in range(3600):
		if wood_task.state == WorkTask.State.COMPLETED:
			break
		await wait_physics_frames(1)
	Engine.time_scale = 1.0
	await wait_process_frames(2)

	dispatcher.task_assigned.disconnect(on_assigned)
	assert_eq(wood_task.state, WorkTask.State.COMPLETED, "T01-B: Reauthorized wood task completed physically")
	assert_eq(t1.get_remaining_amount(), 0, "T01-B: Wood source depleted cleanly (-2 wood)")
	assert_eq(r1.get_remaining_amount(), r1_before_tx, "T01-B: Unselected blocked rock completely untouched")
	assert_eq(stone_task.state, WorkTask.State.BLOCKED_REAUTHORIZATION, "T01-B: Stone task still blocked after wood completion")
	assert_true(leader_a.get_carry_load().validate_provenance(), "T01-B: LeaderA provenance valid")
	assert_true(leader_b.get_carry_load().validate_provenance(), "T01-B: LeaderB provenance valid")

	var delivered_wood: int = site_req_wood if site_completed else (site.get_total_received_amount(&"wood") if is_instance_valid(site) else 0)
	var delivered_stone: int = site_req_stone if site_completed else (site.get_total_received_amount(&"stone") if is_instance_valid(site) else 0)
	var wood_carried: int = leader_a.get_carry_load().get_amount(&"wood") + leader_b.get_carry_load().get_amount(&"wood")
	var stone_carried: int = leader_a.get_carry_load().get_amount(&"stone") + leader_b.get_carry_load().get_amount(&"stone")
	assert_eq(
		inventory.get_physical_amount(&"wood") + wood_carried + delivered_wood,
		wood_before_tx + t1_before_tx,
		"T01-B: Exact wood conservation across reauthorized gather and concurrent construction"
	)
	assert_eq(
		inventory.get_physical_amount(&"stone") + stone_carried + delivered_stone,
		stone_before_tx,
		"T01-B: Exact stone conservation across concurrent construction"
	)

	await _teardown_fixture(view)


func _left_click_with_drift(view: SubViewport, start_pos: Vector2, drift: Vector2, with_motion: bool = true) -> void:
	var end_pos: Vector2 = start_pos + drift
	await _push_motion(view, start_pos, false)
	await _push_left_button(view, start_pos, true, false)
	if with_motion and drift.length_squared() > 0.01:
		await _push_motion(view, start_pos.lerp(end_pos, 0.5), false)
		await _push_motion(view, end_pos, false)
	await _push_left_button(view, end_pos, false, false)
	await wait_process_frames(1)


func test_r2_hf01_01_single_multi_and_repeated_ground_deselect_with_natural_drift() -> void:
	var view := await _fixture(Vector2i(1920, 1080))
	var main := view.get_child(0) as MainScene
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var input_ctrl := main.get_input_controller() as AutonomousGatherInput
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var t3 := _find_source_by_id(main, &"wood_tree_03")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	var b1 := _find_source_by_id(main, &"food_bush_01")
	assert_not_null(t1)
	assert_not_null(t2)
	assert_not_null(t3)
	assert_not_null(r1)
	assert_not_null(b1)
	assert_not_null(input_ctrl)
	if t1 == null or t2 == null or t3 == null or r1 == null or b1 == null or input_ctrl == null:
		await _teardown_fixture(view)
		return

	_focus_camera(main, Vector2(0.0, 0.0), 36.0)
	await wait_process_frames(2)

	var free_ground_world_pts: Array[Vector3] = [
		Vector3(0.0, 0.0, -2.0),
		Vector3(-5.0, 0.0, 4.5),
		Vector3(4.5, 0.0, -2.5),
		Vector3(3.5, 0.0, 4.5),
		Vector3(-5.5, 0.0, -2.5),
	]

	# §11.1 Basic single-source deselection (exact click + natural micro-drift > 6px threshold).
	for drift: Vector2 in [Vector2.ZERO, Vector2(4.0, 1.0), Vector2(8.0, 1.5), Vector2(14.0, -3.0)]:
		model.select_single(t1)
		await wait_process_frames(2)
		assert_eq(model.get_selected_count(), 1, "H-F01 single setup")
		assert_true(hud.is_panel_visible(), "H-F01 single HUD visible")
		assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 1, "H-F01 single ring visible")

		var pt: Vector2 = _world_screen_point(view, free_ground_world_pts[0])
		assert_true(input_ctrl.pick_at_screen_pos(pt).is_ground(), "H-F01 target is free ground")
		await _left_click_with_drift(view, pt, drift, true)
		await wait_process_frames(2)

		assert_true(model.is_empty(), "H-F01 single: free-ground click (drift=%s) must clear selection" % str(drift))
		assert_false(hud.is_panel_visible(), "H-F01 single: HUD must hide after free-ground click (drift=%s)" % str(drift))
		assert_eq(_count_all_rings(main, "SourceSelectionRing_"), 0, "H-F01 single: zero orphan selection rings (drift=%s)" % str(drift))

	# §11.2 Multi-source deselection: multiple trees, wood+stone, and all 3 categories.
	var sets_to_test: Array[Array] = [
		[t1, t2, t3],
		[t1, t2, r1],
		[t1, r1, b1],
	]
	var drifts_for_sets: Array[Vector2] = [
		Vector2(9.5, 2.0),
		Vector2(-11.0, 3.0),
		Vector2(18.0, 6.0),
	]
	for idx: int in range(sets_to_test.size()):
		var typed_set: Array[ResourceSource] = []
		for item: Variant in sets_to_test[idx]:
			typed_set.append(item as ResourceSource)
		model.clear()
		model.add_sources(typed_set)
		await wait_process_frames(2)
		assert_eq(model.get_selected_count(), typed_set.size(), "H-F01 multi setup #%d" % idx)
		var g_pt: Vector2 = _world_screen_point(view, free_ground_world_pts[idx + 1])
		assert_true(input_ctrl.pick_at_screen_pos(g_pt).is_ground(), "H-F01 multi #%d: target is free ground" % idx)
		await _left_click_with_drift(view, g_pt, drifts_for_sets[idx], true)
		await wait_process_frames(2)
		assert_true(model.is_empty(), "H-F01 multi #%d: single click on free ground clears entire group" % idx)
		assert_false(hud.is_panel_visible(), "H-F01 multi #%d: HUD hidden" % idx)
		assert_eq(_count_all_rings(main, "SourceSelectionRing_"), 0, "H-F01 multi #%d: zero orphan rings" % idx)

	# §11.3 Repeated cycles across distinct positions and drift profiles (including fast flick without intermediate motion).
	var cycle_drifts: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(7.0, 0.0),
		Vector2(-8.5, 2.0),
		Vector2(3.5, -2.5),
		Vector2(12.0, 5.0),
		Vector2(28.0, 18.0),
	]
	for c_idx: int in range(cycle_drifts.size()):
		model.add_sources([t1, r1])
		await wait_process_frames(1)
		var world_pt: Vector3 = free_ground_world_pts[c_idx % free_ground_world_pts.size()]
		var screen_pt: Vector2 = _world_screen_point(view, world_pt)
		var use_motion: bool = (c_idx % 2 == 0)
		await _left_click_with_drift(view, screen_pt, cycle_drifts[c_idx], use_motion)
		await wait_process_frames(1)
		assert_true(model.is_empty(), "H-F01 cycle #%d (drift=%s, motion=%s): deselected on first try" % [c_idx, str(cycle_drifts[c_idx]), str(use_motion)])
		assert_false(hud.is_panel_visible(), "H-F01 cycle #%d: HUD hidden" % c_idx)

	await _teardown_fixture(view)


func test_r2_hf01_02_ground_deselect_preserves_authorized_work_and_economy() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var inv := main.get_settlement_inventory()
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	assert_not_null(t1)
	if t1 == null:
		await _teardown_fixture(view)
		return

	_focus_camera(main, Vector2(0.0, 0.0), 36.0)
	await wait_process_frames(2)

	var wood_stock_before: int = inv.get_physical_amount(&"wood")
	model.select_single(t1)
	await wait_process_frames(2)
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(4)
	await wait_physics_frames(2)

	var task: WorkTask = board.get_active_task_for_source(t1)
	assert_not_null(task, "H-F01-02: Task authorized via HUD")
	if task == null:
		await _teardown_fixture(view)
		return
	var orig_task_id: int = task.task_id
	var assigned_before: Unit = task.assigned_unit
	assert_not_null(assigned_before, "H-F01-02: Worker dispatched to authorized task")

	# Click once on free ground with natural 9px micro-drift -> selection clears, authorized work persists!
	var g_pt: Vector2 = _world_screen_point(view, Vector3(0.0, 0.0, -2.0))
	await _left_click_with_drift(view, g_pt, Vector2(9.0, 2.0), true)
	await wait_process_frames(2)

	assert_true(model.is_empty(), "H-F01-02: Free-ground click clears source selection")
	assert_false(hud.is_panel_visible(), "H-F01-02: HUD hides after clearing selection")
	assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 0, "H-F01-02: Selection ring removed")
	assert_eq(_count_rings_on_source(t1, "AutoGatherWorkMarker_"), 1, "H-F01-02: Work symbol preserved after terrain deselect")
	assert_eq(board.get_active_tasks().size(), 1, "H-F01-02: Authorized task NOT cancelled by terrain deselect")
	assert_eq(board.get_active_task_for_source(t1).task_id, orig_task_id, "H-F01-02: Same task_id preserved")
	assert_eq(task.assigned_unit, assigned_before, "H-F01-02: Worker continues working undisturbed")
	assert_eq(inv.get_physical_amount(&"wood"), wood_stock_before, "H-F01-02: Zero spurious stock mutation on deselect")

	await _teardown_fixture(view)


func test_r2_hf01_03_input_protection_boundaries_and_legitimate_drags() -> void:
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var model := main.get_source_selection_model()
	var selection := main.get_selection_manager()
	var hud := main.get_community_selection_actions_hud()
	var input_ctrl := main.get_input_controller() as AutonomousGatherInput
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	assert_not_null(leader_a)
	assert_not_null(t1)
	assert_not_null(r1)
	if leader_a == null or t1 == null or r1 == null:
		await _teardown_fixture(view)
		return

	_focus_camera(main, Vector2(0.0, 0.0), 36.0)
	await wait_process_frames(2)

	# 1. Sub-threshold movement (3.5px) over a source still registers as a valid click (not drag).
	_focus_camera(main, Vector2(t1.global_position.x, t1.global_position.z), 22.0)
	await wait_process_frames(2)
	var t1_pt: Vector2 = _source_screen_point(view, t1)
	await _left_click_with_drift(view, t1_pt, Vector2(3.5, 0.0), true)
	await wait_process_frames(2)
	assert_eq(model.get_selected_sources(), [t1], "H-F01-03: Sub-threshold click on source still selects it")

	# 2. Legitimate unshifted RTS unit box drag capturing LeaderA selects LeaderA and preserves coexistence.
	_focus_camera(main, Vector2(0.0, 0.0), 36.0)
	await wait_process_frames(2)
	var u_pt: Vector2 = _unit_screen_point(view, leader_a)
	await _left_drag(view, u_pt - Vector2(40.0, 40.0), u_pt + Vector2(40.0, 40.0), false, false, false)
	await wait_process_frames(2)
	assert_true(selection.is_selected(leader_a), "H-F01-03: Legitimate unshifted drag selects LeaderA")
	assert_true(model.is_selected(t1), "H-F01-03: Unit box drag capturing unit preserves source selection coexistence")

	# 3. Clicking on an OBSTACLE (WallWest) is differentiated from free ground (§5.5).
	var wall_pt: Vector2 = _world_screen_point(view, Vector3(-8.0, 1.25, -6.0))
	assert_true(input_ctrl.pick_at_screen_pos(wall_pt).is_obstacle(), "H-F01-03: Target is obstacle")
	await _left_click(view, wall_pt, false)
	await wait_process_frames(2)
	assert_true(model.is_selected(t1), "H-F01-03: Direct click on obstacle does not indiscriminately clear sources")

	# 4. Empty Shift+drag on free ground still preserves source selection.
	var empty_pt: Vector2 = _world_screen_point(view, Vector3(0.0, 0.0, -2.0))
	await _left_drag(view, empty_pt, empty_pt + Vector2(55.0, 35.0), true, true, true)
	await wait_process_frames(2)
	assert_true(model.is_selected(t1), "H-F01-03: Empty Shift+drag preserves source selection")

	# 5. Click on HUD button does not leak to world, while click outside HUD in transparent area clears selection cleanly.
	selection.select_single(leader_a)
	model.add_sources([t1, r1])
	await wait_process_frames(2)
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(2)
	assert_eq(selection.get_selected_units(), [leader_a], "H-F01-03: HUD click never leaks to world")

	var outside_hud_pt: Vector2 = _world_screen_point(view, Vector3(-5.0, 0.0, 4.5))
	assert_true(input_ctrl.pick_at_screen_pos(outside_hud_pt).is_ground(), "H-F01-03: outside HUD point is free ground")
	await _left_click_with_drift(view, outside_hud_pt, Vector2(8.0, -2.0), true)
	await wait_process_frames(2)
	assert_true(model.is_empty(), "H-F01-03: Click in transparent world region clears selection")

	# 6. Esc leaves zero residual state.
	model.select_single(r1)
	await wait_process_frames(1)
	await _press_escape(view)
	await wait_process_frames(1)
	assert_true(model.is_empty(), "H-F01-03: Esc clears selection cleanly")
	assert_false(input_ctrl.is_drag_gesture_active(), "H-F01-03: Zero residual drag state after Esc")
	assert_eq(input_ctrl.get_active_drag_mode(), AutonomousGatherInput.DragMode.NONE, "H-F01-03: DragMode NONE after Esc")

	await _teardown_fixture(view)


func _find_work_marker(src: ResourceSource) -> Sprite3D:
	for child: Node in src.get_children():
		if child is Sprite3D and String(child.name).begins_with("AutoGatherWorkMarker_") and not child.is_queued_for_deletion():
			return child as Sprite3D
	return null


func _has_any_collider_descendant(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child: Node in node.get_children():
		if _has_any_collider_descendant(child):
			return true
	return false


func test_r2_hv01_d2_2_basalt_stone_hud_materiality_polygons_and_states() -> void:
	var view := await _fixture(Vector2i(1920, 1080))
	var main := view.get_child(0) as MainScene
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var selection := main.get_selection_manager()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	var b1 := _find_source_by_id(main, &"food_bush_01")
	assert_not_null(leader_a)
	assert_not_null(t1)
	assert_not_null(t2)
	assert_not_null(r1)
	assert_not_null(b1)
	if leader_a == null or t1 == null or t2 == null or r1 == null or b1 == null:
		await _teardown_fixture(view)
		return

	# Verify D2.2 atlas reuse ("slab_cmd_basalt"), D2PolygonalSlab surfaces, and zero polling.
	assert_true(hud.is_atlas_loaded(), "H-V01: D2AtlasLibrary loaded cleanly")
	assert_eq(hud.get_atlas_region_key(), "slab_cmd_basalt", "H-V01: Reuses canonical slab_cmd_basalt region")
	assert_false(hud.is_processing(), "H-V01: Zero _process polling")
	assert_false(hud.is_physics_processing(), "H-V01: Zero _physics_process polling")
	assert_false(hud.has_stop_button(), "H-V01: No Parar button in D1 R2")
	assert_false(hud.is_panel_visible(), "H-V01: Hidden with 0 categories")

	for res_id: StringName in [&"wood", &"stone", &"food"]:
		var slab: D2PolygonalSlab = hud.get_category_slab(res_id)
		assert_not_null(slab, "H-V01: D2PolygonalSlab exists for %s" % String(res_id))
		if slab != null:
			assert_true(slab.texture is AtlasTexture, "H-V01: Slab uses AtlasTexture from homologated D2.2 atlas")
			assert_eq(slab.get_scaled_polygon().size(), 4, "H-V01: Slab uses canonical 4-vertex beveled basalt polygon")
			assert_true(slab.contains_local_point(slab.size * 0.5), "H-V01: Solid basalt center intercepts input")
			assert_false(slab.contains_local_point(Vector2(1.0, 1.0)), "H-V01: Transparent shadow margin passes input through")

	# 1 -> 2 -> 3 categories visibility and count progression.
	model.select_single(t1)
	await wait_process_frames(2)
	assert_true(hud.is_panel_visible(), "H-V01: Visible with 1 category")
	assert_eq(hud.get_visible_category_ids(), [&"wood"])
	assert_eq(hud.get_category_count_text(&"wood"), "1")
	assert_eq(hud.get_category_visual_state(&"wood"), CommunitySelectionActionsHud.STATE_AVAILABLE)

	model.add_sources([t2, r1])
	await wait_process_frames(2)
	assert_eq(hud.get_visible_category_ids(), [&"wood", &"stone"])
	assert_eq(hud.get_category_count_text(&"wood"), "2")
	assert_eq(hud.get_category_count_text(&"stone"), "1")

	model.add_sources([b1])
	await wait_process_frames(2)
	assert_eq(hud.get_visible_category_ids(), [&"wood", &"stone", &"food"])

	# Partial vs Authorized state transition on basalt slabs.
	var board := main.get_community_work_board()
	board.register_gather_task(t1)
	await wait_process_frames(2)
	assert_eq(hud.get_category_visual_state(&"wood"), CommunitySelectionActionsHud.STATE_PARTIAL, "H-V01: 1/2 wood authorized -> partial state")
	assert_eq(hud.get_category_visual_state(&"stone"), CommunitySelectionActionsHud.STATE_AVAILABLE, "H-V01: stone stays available")

	# Click wood basalt slab to authorize remaining tree (anti-click-through preserves unit selection).
	selection.select_single(leader_a)
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(2)
	assert_eq(hud.get_category_visual_state(&"wood"), CommunitySelectionActionsHud.STATE_AUTHORIZED, "H-V01: 2/2 wood authorized -> authorized state")
	assert_eq(selection.get_selected_units(), [leader_a], "H-V01: Anti-click-through on solid basalt slab preserves unit selection")

	await _teardown_fixture(view)


func test_r2_hv03_work_marker_lifecycle_pending_blocked_depletion_removal_and_picker() -> void:
	## R-03A D1 R2 (§12.2 + §8.6):
	## Validates work-activity symbol across PENDING_WORKERS, IN_PROGRESS, BLOCKED_REAUTHORIZATION,
	## reauthorization, depletion, source removal, WorldPicker non-interference, and MainScene reinstantiation.
	var view := await _fixture(Vector2i(1280, 720))
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var hud := main.get_community_selection_actions_hud()
	var cmd := main.get_command_controller()
	var selection := main.get_selection_manager()
	var input_ctrl := main.get_input_controller() as AutonomousGatherInput
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	var r1 := _find_source_by_id(main, &"stone_rock_01")
	var b1 := _find_source_by_id(main, &"food_bush_01")
	assert_not_null(t1)
	assert_not_null(t2)
	assert_not_null(r1)
	assert_not_null(b1)
	if t1 == null or t2 == null or r1 == null or b1 == null:
		await _teardown_fixture(view)
		return

	# Authorize 3 distinct categories (wood, stone, food): with only 2 leaders, at least 1 task stays PENDING_WORKERS!
	model.add_sources([t1, r1, b1])
	await wait_process_frames(2)
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await _click_hud_button(view, hud.get_category_button(&"stone"))
	await _click_hud_button(view, hud.get_category_button(&"food"))
	await wait_process_frames(4)
	await wait_physics_frames(2)

	var task_w := board.get_active_task_for_source(t1)
	var task_s := board.get_active_task_for_source(r1)
	var task_f := board.get_active_task_for_source(b1)
	assert_not_null(task_w)
	assert_not_null(task_s)
	assert_not_null(task_f)

	# All 3 sources MUST display their respective work-activity symbols (including PENDING_WORKERS without worker!).
	var any_pending: bool = (
		(task_w != null and task_w.state == WorkTask.State.PENDING_WORKERS)
		or (task_s != null and task_s.state == WorkTask.State.PENDING_WORKERS)
		or (task_f != null and task_f.state == WorkTask.State.PENDING_WORKERS)
	)
	assert_true(any_pending, "H-V03: At least 1 authorized task is in PENDING_WORKERS waiting for worker")

	var m_w := _find_work_marker(t1)
	var m_s := _find_work_marker(r1)
	var m_f := _find_work_marker(b1)
	assert_not_null(m_w, "H-V03: Wood work symbol visible")
	assert_not_null(m_s, "H-V03: Stone work symbol visible")
	assert_not_null(m_f, "H-V03: Food work symbol visible (persists in PENDING_WORKERS)")
	if m_w != null and m_s != null and m_f != null:
		assert_eq(m_w.get_meta(&"work_marker_resource"), &"wood")
		assert_eq(m_s.get_meta(&"work_marker_resource"), &"stone")
		assert_eq(m_f.get_meta(&"work_marker_resource"), &"food")
		assert_eq(String(m_w.get_meta(&"work_marker_state")), "active")
		assert_false(_has_any_collider_descendant(m_w), "H-V03: Work marker has zero CollisionObject3D")
		assert_false(_has_any_collider_descendant(m_s), "H-V03: Stone marker has zero CollisionObject3D")
		assert_false(_has_any_collider_descendant(m_f), "H-V03: Food marker has zero CollisionObject3D")
		assert_eq(m_w.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "H-V03: Marker casts zero shadows")

	# Repeated authorization does not duplicate marker.
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(2)
	assert_eq(_count_rings_on_source(t1, "AutoGatherWorkMarker_"), 1, "H-V03: Repeated auth creates 0 duplicate markers")

	# WorldPicker still picks each source cleanly with markers attached.
	for src: ResourceSource in [t1, r1, b1]:
		_focus_camera(main, Vector2(src.global_position.x, src.global_position.z), 22.0)
		await wait_process_frames(1)
		var pk: PickResult = input_ctrl.pick_at_screen_pos(_source_screen_point(view, src))
		assert_true(pk.is_resource_source() and pk.resource_source == src, "H-V03: WorldPicker unaffected by work marker on %s" % String(src.source_id))

	# Drive t1 task into BLOCKED_REAUTHORIZATION and verify marker switches to "blocked" state via signal, then back on reauth.
	if task_w != null:
		for override_idx: int in range(2):
			if task_w.is_blocked_reauthorization():
				break
			var w: Unit = task_w.assigned_unit
			if w != null:
				selection.select_single(w)
				cmd.command_at(PickResult.from_ground(Vector3(3.0 + float(override_idx) * 2.0, 0.0, 12.0), Vector3.UP))
				await wait_process_frames(4)
				await wait_physics_frames(2)
		if task_w.is_blocked_reauthorization():
			assert_eq(String(_find_work_marker(t1).get_meta(&"work_marker_state")), "blocked", "H-V03: Blocked task switches marker to blocked treatment")
			model.select_single(t1)
			await wait_process_frames(1)
			await _click_hud_button(view, hud.get_category_button(&"wood"))
			await wait_process_frames(3)
			assert_eq(String(_find_work_marker(t1).get_meta(&"work_marker_state")), "active", "H-V03: Reauthorization restores active work marker")

	# Depletion closes task and removes work marker cleanly.
	while not r1.is_depleted():
		r1.extract(r1.max_extract_per_operation)
	await wait_process_frames(2)
	assert_eq(_count_rings_on_source(r1, "AutoGatherWorkMarker_"), 0, "H-V03: Depletion removes work marker")

	# Source removal from tree closes task and leaves zero orphan markers.
	model.select_single(t2)
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(2)
	var t2_task: WorkTask = board.get_active_task_for_source(t2)
	assert_not_null(t2_task, "H-V03: t2 task created prior to removal")
	assert_eq(_count_rings_on_source(t2, "AutoGatherWorkMarker_"), 1, "H-V03: t2 marker attached prior to removal")
	t2.get_parent().remove_child(t2)
	t2.queue_free()
	await wait_process_frames(2)
	assert_false(t2_task.is_active(), "H-V03: Source removal closes task cleanly")

	await _teardown_fixture(view)

	# Reinstantiation of MainScene starts cleanly with 0 residual markers or rings.
	var view2 := await _fixture(Vector2i(1280, 720))
	var main2 := view2.get_child(0) as MainScene
	assert_eq(_count_all_rings(main2, "SourceSelectionRing_"), 0, "H-V03: Clean selection rings on reinstantiated MainScene")
	assert_eq(_count_all_rings(main2, "AutoGatherWorkMarker_"), 0, "H-V03: Clean work markers on reinstantiated MainScene")
	await _teardown_fixture(view2)
