extends TestCase
## Integration tests for T1.7 box selection in MainScene:
## multi-unit drag across all 4 directions, replacement vs Shift+add, empty box behavior,
## click vs drag threshold, cancellation via Esc/focus loss, zoom & camera compatibility.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")


func after_each() -> void:
	_release_all_inputs()


func _spawn_main_scene() -> Dictionary:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	add_test_child(main_root)
	await wait_process_frames(4)
	await wait_physics_frames(4)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var leader_a: Unit = null
	var leader_b: Unit = null
	for unit: Unit in main_root.get_units():
		if unit.get_character_id() == &"leader_a":
			leader_a = unit
		elif unit.get_character_id() == &"leader_b":
			leader_b = unit

	return {
		"main": main_root,
		"rig": rig,
		"camera": rig.get_camera() if rig != null else null,
		"selection_manager": main_root.get_selection_manager(),
		"controller": main_root.get_input_controller(),
		"overlay": main_root.get_selection_box_overlay(),
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _project_unit_anchor(camera: Camera3D, unit: Unit) -> Vector2:
	return camera.unproject_position(SelectionBoxMath.get_unit_world_anchor(unit))


func _push_mouse_move(screen_pos: Vector2, relative: Vector2 = Vector2.ZERO, shift_held: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	motion.relative = relative
	motion.shift_pressed = shift_held
	get_viewport().push_input(motion, true)


func _push_mouse_button(button: MouseButton, screen_pos: Vector2, pressed: bool, shift_held: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = screen_pos
	ev.global_position = screen_pos
	ev.pressed = pressed
	ev.shift_pressed = shift_held
	get_viewport().push_input(ev, true)


func _simulate_box_drag(start_pos: Vector2, end_pos: Vector2, shift_held: bool = false) -> void:
	_push_mouse_move(start_pos, Vector2.ZERO, shift_held)
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_LEFT, start_pos, true, shift_held)
	await wait_process_frames(1)
	_push_mouse_move(start_pos.lerp(end_pos, 0.5), Vector2.ZERO, shift_held)
	await wait_process_frames(1)
	_push_mouse_move(end_pos, Vector2.ZERO, shift_held)
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_LEFT, end_pos, false, shift_held)
	await wait_process_frames(2)


func _simulate_left_click(screen_pos: Vector2, shift_held: bool = false) -> void:
	_push_mouse_move(screen_pos)
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_LEFT, screen_pos, true, shift_held)
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_LEFT, screen_pos, false, shift_held)
	await wait_process_frames(2)


func _push_escape() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.physical_keycode = KEY_ESCAPE
	down.pressed = true
	get_viewport().push_input(down, true)
	await wait_process_frames(1)

	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	get_viewport().push_input(up, true)
	await wait_process_frames(1)


func _release_all_inputs() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_push_mouse_button(MOUSE_BUTTON_LEFT, Vector2.ZERO, false, false)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_push_mouse_button(MOUSE_BUTTON_MIDDLE, Vector2.ZERO, false, false)


func test_01_box_drag_selects_both_units_in_all_four_directions() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var overlay: SelectionBoxOverlay = ctx["overlay"] as SelectionBoxOverlay
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	assert_not_null(overlay, "MainScene must compose SelectionBoxOverlay")
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(overlay.visible)

	var a_pos: Vector2 = _project_unit_anchor(cam, leader_a)
	var b_pos: Vector2 = _project_unit_anchor(cam, leader_b)
	var min_pt := Vector2(minf(a_pos.x, b_pos.x) - 45.0, minf(a_pos.y, b_pos.y) - 45.0)
	var max_pt := Vector2(maxf(a_pos.x, b_pos.x) + 45.0, maxf(a_pos.y, b_pos.y) + 45.0)

	var corners: Array[Array] = [
		[min_pt, max_pt],
		[max_pt, min_pt],
		[Vector2(max_pt.x, min_pt.y), Vector2(min_pt.x, max_pt.y)],
		[Vector2(min_pt.x, max_pt.y), Vector2(max_pt.x, min_pt.y)],
	]

	for pair: Array in corners:
		manager.clear_selection()
		await wait_process_frames(1)
		await _simulate_box_drag(pair[0] as Vector2, pair[1] as Vector2, false)
		assert_eq(manager.get_selection_count(), 2, "Box drag must select both protagonists regardless of drag direction")
		assert_true(manager.is_selected(leader_a))
		assert_true(manager.is_selected(leader_b))
		assert_false(overlay.is_box_active(), "SelectionBoxOverlay must hide immediately after release")
		assert_false(overlay.visible)


func test_02_box_drag_replaces_existing_selection() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	await _simulate_left_click(_project_unit_anchor(cam, leader_b))
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_b))

	var a_pos: Vector2 = _project_unit_anchor(cam, leader_a)
	await _simulate_box_drag(a_pos - Vector2(35.0, 35.0), a_pos + Vector2(35.0, 35.0), false)
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_a))
	assert_false(manager.is_selected(leader_b))


func test_03_empty_box_clears_without_shift_and_preserves_with_shift() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit

	await _simulate_left_click(_project_unit_anchor(cam, leader_a))
	assert_eq(manager.get_selection_count(), 1)

	var empty_start: Vector2 = cam.unproject_position(Vector3(-8.0, 0.0, 10.0))
	var empty_end: Vector2 = empty_start + Vector2(80.0, 60.0)

	# Empty box with Shift preserves existing selection.
	await _simulate_box_drag(empty_start, empty_end, true)
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_a))

	# Empty box without Shift clears selection.
	await _simulate_box_drag(empty_start, empty_end, false)
	assert_true(manager.is_empty())


func test_04_shift_box_adds_units_without_duplicates() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var controller: RtsInputController = ctx["controller"] as RtsInputController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit
	# R-03A D1 reconciliation: on MainScene with multi_source_enabled=true, Shift+drag is canonically
	# reassigned to additive natural resource source box selection (verified in test_r_03a_d1_selection_and_authorization.gd).
	# Disable multi_source_enabled here to keep regression coverage of base RtsInputController Shift+box unit addition.
	if controller is AutonomousGatherInput:
		(controller as AutonomousGatherInput).multi_source_enabled = false

	await _simulate_left_click(_project_unit_anchor(cam, leader_a))
	assert_eq(manager.get_selection_count(), 1)

	var signal_counts: Array[int] = [0]
	manager.selection_changed.connect(func(_units: Array[Unit]) -> void:
		signal_counts[0] += 1
	)

	var a_pos: Vector2 = _project_unit_anchor(cam, leader_a)
	var b_pos: Vector2 = _project_unit_anchor(cam, leader_b)
	var min_pt := Vector2(minf(a_pos.x, b_pos.x) - 40.0, minf(a_pos.y, b_pos.y) - 40.0)
	var max_pt := Vector2(maxf(a_pos.x, b_pos.x) + 40.0, maxf(a_pos.y, b_pos.y) + 40.0)

	await _simulate_box_drag(min_pt, max_pt, true)
	assert_eq(manager.get_selection_count(), 2)
	assert_true(manager.is_selected(leader_a))
	assert_true(manager.is_selected(leader_b))
	assert_eq(signal_counts[0], 1, "Adding box units must emit selection_changed once")

	# Repeating Shift+box over already-selected units must not duplicate or emit redundantly.
	await _simulate_box_drag(min_pt, max_pt, true)
	assert_eq(manager.get_selection_count(), 2)
	assert_eq(signal_counts[0], 1)


func test_05_click_vs_drag_threshold_distinction() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var controller: RtsInputController = ctx["controller"] as RtsInputController
	var overlay: SelectionBoxOverlay = ctx["overlay"] as SelectionBoxOverlay
	var leader_a: Unit = ctx["leader_a"] as Unit

	var a_pos: Vector2 = _project_unit_anchor(cam, leader_a)
	var small_delta := Vector2(controller.get_drag_threshold_px() * 0.4, 0.0)

	_push_mouse_move(a_pos)
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_LEFT, a_pos, true)
	await wait_process_frames(1)
	_push_mouse_move(a_pos + small_delta)
	await wait_process_frames(1)
	assert_false(controller.is_drag_gesture_active(), "Small jitter below threshold must stay a click")
	assert_false(overlay.is_box_active())
	_push_mouse_button(MOUSE_BUTTON_LEFT, a_pos + small_delta, false)
	await wait_process_frames(2)

	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_a))


func test_06_box_drag_cancellation_via_esc_and_focus_loss() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var controller: RtsInputController = ctx["controller"] as RtsInputController
	var overlay: SelectionBoxOverlay = ctx["overlay"] as SelectionBoxOverlay
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	await _simulate_left_click(_project_unit_anchor(cam, leader_a))
	assert_eq(manager.get_selection_count(), 1)

	var a_pos: Vector2 = _project_unit_anchor(cam, leader_a)
	var b_pos: Vector2 = _project_unit_anchor(cam, leader_b)
	_push_mouse_move(a_pos - Vector2(30.0, 30.0))
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_LEFT, a_pos - Vector2(30.0, 30.0), true)
	await wait_process_frames(1)
	_push_mouse_move(b_pos + Vector2(30.0, 30.0))
	await wait_process_frames(1)
	assert_true(controller.is_drag_gesture_active())
	assert_true(overlay.is_box_active())

	# Esc during active drag cancels the box without altering selection; release afterward is ignored.
	await _push_escape()
	assert_false(controller.is_drag_gesture_active())
	assert_false(overlay.is_box_active())
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_a))

	_push_mouse_button(MOUSE_BUTTON_LEFT, b_pos + Vector2(30.0, 30.0), false)
	await wait_process_frames(1)
	assert_eq(manager.get_selection_count(), 1)

	# Window focus loss also cancels an active drag cleanly.
	_push_mouse_button(MOUSE_BUTTON_LEFT, a_pos - Vector2(30.0, 30.0), true)
	await wait_process_frames(1)
	_push_mouse_move(b_pos + Vector2(30.0, 30.0))
	await wait_process_frames(1)
	assert_true(overlay.is_box_active())
	controller.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await wait_process_frames(1)
	assert_false(controller.is_drag_gesture_active())
	assert_false(overlay.is_box_active())


func test_07_box_selection_across_zoom_levels_and_camera_compatibility() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	for zoom_dist: float in [rig.min_distance, rig.max_distance]:
		manager.clear_selection()
		rig.set_target_zoom_distance(zoom_dist, true)
		await wait_process_frames(2)

		var a_pos: Vector2 = _project_unit_anchor(cam, leader_a)
		var b_pos: Vector2 = _project_unit_anchor(cam, leader_b)
		var min_pt := Vector2(minf(a_pos.x, b_pos.x) - 35.0, minf(a_pos.y, b_pos.y) - 35.0)
		var max_pt := Vector2(maxf(a_pos.x, b_pos.x) + 35.0, maxf(a_pos.y, b_pos.y) + 35.0)
		await _simulate_box_drag(min_pt, max_pt, false)
		assert_eq(manager.get_selection_count(), 2, "Box selection must work at zoom %.1f" % zoom_dist)

	# Middle-mouse drag continues panning camera without clearing box selection.
	var focus_before: Vector2 = rig.get_focus_position()
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, Vector2(400.0, 300.0), true)
	await wait_process_frames(1)
	_push_mouse_move(Vector2(500.0, 330.0), Vector2(100.0, 30.0))
	await wait_process_frames(2)
	_push_mouse_button(MOUSE_BUTTON_MIDDLE, Vector2(500.0, 330.0), false)
	await wait_process_frames(1)
	assert_gt(rig.get_focus_position().distance_to(focus_before), 0.1)
	assert_eq(manager.get_selection_count(), 2)
