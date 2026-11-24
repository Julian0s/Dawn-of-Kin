extends TestCase
## Integration tests for R-03A D1 — Independent source selection, explicit HUD authorization,
## D1-B individual deselection, D1-C explicit reauthorization, minimal D2.2 contextual HUD,
## concentric selection vs task rings, anti-click-through, and 720p/1080p layout geometry.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
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


func test_d1_07_mid_drag_shift_lock_and_escape_cancellation_without_stopping_tasks() -> void:
	var view := await _fixture()
	var main := view.get_child(0) as MainScene
	var board := main.get_community_work_board()
	var model := main.get_source_selection_model()
	var selection := main.get_selection_manager()
	var hud := main.get_community_selection_actions_hud()
	var overlay := main.get_selection_box_overlay()
	var leader_a := _find_unit_by_id(main, &"leader_a")
	var t1 := _find_source_by_id(main, &"wood_tree_01")
	var t2 := _find_source_by_id(main, &"wood_tree_02")
	assert_not_null(leader_a)
	assert_not_null(t1)
	assert_not_null(t2)
	if leader_a == null or t1 == null or t2 == null:
		await _teardown_fixture(view)
		return

	# A) Hold Shift at press, release Shift mid-drag -> stays SOURCE_BOX_ADD (no flip to RTS unit box).
	selection.select_single(leader_a)
	_focus_camera(main, Vector2(t1.global_position.x, t1.global_position.z), 22.0)
	await wait_process_frames(2)
	var p1 := _source_screen_point(view, t1)
	await _left_drag(view, p1 - Vector2(40.0, 40.0), p1 + Vector2(40.0, 40.0), true, false, false)
	assert_true(model.is_selected(t1), "Releasing Shift mid-drag keeps locked SOURCE_BOX_ADD mode")
	assert_eq(selection.get_selected_units(), [leader_a], "Unit selection untouched on locked source drag")

	# B) Press WITHOUT Shift, press Shift mid-drag -> stays UNIT_BOX_RTS (no flip to source box).
	model.clear()
	selection.clear_selection()
	leader_a.global_position = t1.global_position + Vector3(-2.0, 0.0, 1.5)
	_focus_camera(main, Vector2(t1.global_position.x, t1.global_position.z), 22.0)
	await wait_process_frames(2)
	var pu := _unit_screen_point(view, leader_a)
	await _left_drag(view, pu - Vector2(45.0, 45.0), pu + Vector2(45.0, 45.0), false, true, true)
	assert_true(selection.is_selected(leader_a), "Pressing Shift mid-drag keeps locked UNIT_BOX_RTS mode")
	assert_true(model.is_empty(), "Locked UNIT_BOX_RTS does NOT add sources")

	# C) Esc during active Shift+drag cancels gesture without mutating selection.
	var p2 := _source_screen_point(view, t2)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = p2 - Vector2(40.0, 40.0)
	down.global_position = down.position
	down.pressed = true
	down.shift_pressed = true
	view.push_input(down, true)
	await wait_process_frames(1)
	var mm := InputEventMouseMotion.new()
	mm.position = p2 + Vector2(40.0, 40.0)
	mm.global_position = mm.position
	mm.shift_pressed = true
	view.push_input(mm, true)
	await wait_process_frames(1)
	assert_true(overlay.is_box_active(), "Box overlay active before Esc")
	assert_true(overlay.is_source_mode(), "Overlay uses distinct source style during Shift+drag")

	await _press_escape(view)
	assert_false(overlay.is_box_active(), "Esc cancels active source drag")
	assert_true(model.is_empty(), "Cancelled drag must NOT select sources")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = p2 + Vector2(40.0, 40.0)
	up.global_position = up.position
	up.pressed = false
	up.shift_pressed = true
	view.push_input(up, true)
	await wait_process_frames(1)
	assert_true(model.is_empty(), "Release after Esc cancellation is ignored")

	# D) Esc outside drag clears selection and hides HUD, WITHOUT cancelling authorized tasks.
	model.select_single(t1)
	var wood_btn := hud.get_category_button(&"wood")
	await _click_hud_button(view, wood_btn)
	await wait_process_frames(3)
	assert_eq(board.get_active_tasks().size(), 1, "Task active after explicit HUD authorization")

	await _press_escape(view)
	await wait_process_frames(2)
	assert_true(model.is_empty(), "Esc clears source selection")
	assert_false(hud.is_panel_visible(), "HUD hides after Esc clears selection")
	assert_eq(board.get_active_tasks().size(), 1, "Esc must NEVER cancel active community tasks")

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

	# State 1: Available (unselected, no task) -> 0 rings.
	assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 0, "State 1: no selection ring")
	assert_eq(_count_rings_on_source(t1, "AutoGatherTaskRing_"), 0, "State 1: no task ring")

	# State 2: Selected (not authorized) -> outer selection ring only.
	model.select_single(t1)
	await wait_process_frames(2)
	assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 1, "State 2: selection ring attached")
	assert_eq(_count_rings_on_source(t1, "AutoGatherTaskRing_"), 0, "State 2: still 0 task rings")

	# State 3: Selected + Authorized -> BOTH concentric rings simultaneously.
	await _click_hud_button(view, hud.get_category_button(&"wood"))
	await wait_process_frames(3)
	assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 1, "State 3: selection ring kept")
	assert_eq(_count_rings_on_source(t1, "AutoGatherTaskRing_"), 1, "State 3: task ring attached alongside selection ring")

	# State 4: Deselected + Authorized -> task ring remains, selection ring removed.
	model.clear()
	await wait_process_frames(2)
	assert_eq(_count_rings_on_source(t1, "SourceSelectionRing_"), 0, "State 4: selection ring removed on deselect")
	assert_eq(_count_rings_on_source(t1, "AutoGatherTaskRing_"), 1, "State 4: task ring preserved after deselect")

	# Teardown hygiene: zero orphan rings anywhere on map.
	model.select_single(t1)
	await wait_process_frames(1)
	g_in.teardown_community_work()
	await wait_process_frames(2)
	assert_eq(_count_all_rings(main, "SourceSelectionRing_"), 0, "Zero orphan selection rings after teardown")
	assert_eq(_count_all_rings(main, "AutoGatherTaskRing_"), 0, "Zero orphan task rings after teardown")

	await _teardown_fixture(view)
