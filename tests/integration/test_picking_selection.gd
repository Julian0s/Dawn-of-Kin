extends TestCase
## Integration tests for T1.6 picking & click selection in MainScene:
## Tests A-I covering left-click selection, Shift+toggle, ground clear, Esc,
## SceneTree removal, min/max zoom & moving-unit picking, terrain/sky/obstacle/occlusion,
## camera compatibility, and drag-threshold / hover suppression.

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

	var units: Array[Unit] = main_root.get_units()
	var leader_a: Unit = null
	var leader_b: Unit = null
	for unit: Unit in units:
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
		"test_map": main_root.get_node_or_null("TestMap") as TestMap,
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _project_unit_screen_pos(camera: Camera3D, unit: Unit) -> Vector2:
	return camera.unproject_position(unit.global_position + Vector3(0.0, 1.0, 0.0))


func _simulate_mouse_move(screen_pos: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	motion.relative = relative
	get_viewport().push_input(motion, true)


func _simulate_mouse_button(button: MouseButton, screen_pos: Vector2, pressed: bool, shift_held: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = screen_pos
	ev.global_position = screen_pos
	ev.pressed = pressed
	ev.shift_pressed = shift_held
	get_viewport().push_input(ev, true)


func _simulate_left_click(screen_pos: Vector2, shift_held: bool = false) -> void:
	_simulate_mouse_move(screen_pos)
	await wait_process_frames(1)
	_simulate_mouse_button(MOUSE_BUTTON_LEFT, screen_pos, true, shift_held)
	await wait_process_frames(1)
	_simulate_mouse_button(MOUSE_BUTTON_LEFT, screen_pos, false, shift_held)
	await wait_process_frames(2)


func _simulate_key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	get_viewport().push_input(down, true)
	await wait_process_frames(1)

	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	get_viewport().push_input(up, true)
	await wait_process_frames(1)


func _set_action_pressed(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _release_all_inputs() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_simulate_mouse_button(MOUSE_BUTTON_LEFT, Vector2.ZERO, false, false)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_simulate_mouse_button(MOUSE_BUTTON_MIDDLE, Vector2.ZERO, false, false)
	for action: StringName in [
		InputActions.SELECT,
		InputActions.CLEAR_SELECTION,
		InputActions.SELECTION_MODIFIER,
		InputActions.CAMERA_DRAG,
		InputActions.CAMERA_PAN_UP,
		InputActions.CAMERA_PAN_DOWN,
		InputActions.CAMERA_PAN_LEFT,
		InputActions.CAMERA_PAN_RIGHT,
	]:
		if Input.is_action_pressed(action):
			_set_action_pressed(action, false)


func test_01_exclusive_left_click_selection_and_transfer() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	assert_not_null(cam)
	assert_not_null(manager)
	assert_not_null(leader_a)
	assert_not_null(leader_b)
	assert_true(manager.is_empty(), "Initial selection must be empty")

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_a))
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_a))
	assert_true(leader_a.is_selected())
	assert_false(leader_b.is_selected())
	assert_true((leader_a.get_selection_indicator().get_node("SelectedRing") as MeshInstance3D).visible)
	assert_false((leader_b.get_selection_indicator().get_node("SelectedRing") as MeshInstance3D).visible)

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_b))
	assert_eq(manager.get_selection_count(), 1)
	assert_false(manager.is_selected(leader_a))
	assert_false(leader_a.is_selected())
	assert_true(manager.is_selected(leader_b))
	assert_true(leader_b.is_selected())
	assert_false((leader_a.get_selection_indicator().get_node("SelectedRing") as MeshInstance3D).visible)
	assert_true((leader_b.get_selection_indicator().get_node("SelectedRing") as MeshInstance3D).visible)


func test_02_shift_click_multi_selection_and_toggle() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_a), false)
	assert_eq(manager.get_selection_count(), 1)

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_b), true)
	assert_eq(manager.get_selection_count(), 2)
	assert_true(manager.is_selected(leader_a))
	assert_true(manager.is_selected(leader_b))

	# Shift+click already-selected unit removes it cleanly without duplicates.
	await _simulate_left_click(_project_unit_screen_pos(cam, leader_b), true)
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_a))
	assert_false(manager.is_selected(leader_b))

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_a), true)
	assert_true(manager.is_empty())


func test_03_ground_click_clears_and_shift_ground_preserves() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_a), false)
	assert_eq(manager.get_selection_count(), 1)

	var empty_ground_pos: Vector2 = cam.unproject_position(Vector3(0.0, 0.0, 6.0))
	await _simulate_left_click(empty_ground_pos, true)
	assert_eq(manager.get_selection_count(), 1, "Shift+click on ground must preserve active selection")
	assert_true(manager.is_selected(leader_a))

	await _simulate_left_click(empty_ground_pos, false)
	assert_true(manager.is_empty(), "Plain left click on ground must clear selection")


func test_04_clear_selection_action_esc() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_a), false)
	await _simulate_left_click(_project_unit_screen_pos(cam, leader_b), true)
	assert_eq(manager.get_selection_count(), 2)

	await _simulate_key(KEY_ESCAPE)
	assert_true(manager.is_empty(), "Esc must clear all selected units")
	assert_false(leader_a.is_selected())
	assert_false(leader_b.is_selected())


func test_05_selected_unit_removed_from_tree_updates_selection() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_a), false)
	await _simulate_left_click(_project_unit_screen_pos(cam, leader_b), true)
	assert_eq(manager.get_selection_count(), 2)

	var signal_counts: Array[int] = [0]
	manager.selection_changed.connect(func(_units: Array[Unit]) -> void:
		signal_counts[0] += 1
	)

	leader_a.get_parent().remove_child(leader_a)
	leader_a.queue_free()
	await wait_process_frames(2)

	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_b))
	assert_gt(signal_counts[0], 0, "Removing selected unit from SceneTree must emit selection_changed")


func test_06_picking_at_min_and_max_zoom_and_during_movement() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	# Min zoom (closest).
	rig.set_target_zoom_distance(rig.min_distance)
	for _i: int in range(60):
		rig.step_camera(1.0 / 60.0)
	await wait_process_frames(2)

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_a))
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_a), "Min zoom click must select LeaderA")

	# Max zoom (farthest).
	rig.set_target_zoom_distance(rig.max_distance)
	for _i: int in range(60):
		rig.step_camera(1.0 / 60.0)
	await wait_process_frames(2)

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_b))
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_b), "Max zoom click must select LeaderB")

	# Issue programmatic MoveOrder to LeaderA and pick it mid-walk without interrupting movement.
	manager.clear_selection()
	leader_a.issue_order(MoveOrder.new(Vector3(-2.5, 0.0, 9.0)))
	await wait_physics_frames(15)
	assert_eq(leader_a.get_state(), Unit.State.MOVING)

	await _simulate_left_click(_project_unit_screen_pos(cam, leader_a))
	assert_true(manager.is_selected(leader_a), "Moving unit must remain clickable")
	assert_eq(leader_a.get_state(), Unit.State.MOVING, "Clicking to select must never cancel active MoveOrder")


func test_07_world_picker_ground_sky_obstacle_and_occlusion() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var controller: RtsInputController = ctx["controller"] as RtsInputController
	var leader_a: Unit = ctx["leader_a"] as Unit

	var ground_pick: PickResult = controller.pick_at_screen_pos(cam.unproject_position(Vector3(0.0, 0.0, 6.0)))
	assert_true(ground_pick.is_ground(), "Open terrain must resolve as PickResult.Kind.GROUND")

	# WallWest spans x=[-14, -2], z=-6, height=2.5. Center near (-8, 1.25, -6).
	var wall_screen_pos: Vector2 = cam.unproject_position(Vector3(-8.0, 1.25, -6.0))
	var wall_pick: PickResult = controller.pick_at_screen_pos(wall_screen_pos)
	assert_true(wall_pick.is_obstacle(), "Solid obstacle WallWest must resolve as PickResult.Kind.OBSTACLE")

	# Upward/sky ray via WorldPicker returns NONE.
	var sky_picker := WorldPicker.new()
	var sky_res: PickResult = sky_picker.pick_along_ray(cam.get_world_3d().direct_space_state, cam.global_position, Vector3.UP)
	assert_true(sky_res.is_none(), "Sky ray with no physics hit must resolve as PickResult.Kind.NONE")

	# Corner outside 64x64 slab when camera focuses near (-32, -32) also picks NONE.
	rig.set_focus_position(Vector2(-32.0, -32.0))
	rig.set_target_zoom_distance(rig.max_distance)
	for _i: int in range(40):
		rig.step_camera(1.0 / 60.0)
	await wait_process_frames(2)
	var off_map_res: PickResult = controller.pick_at_screen_pos(Vector2(20.0, 20.0))
	assert_true(off_map_res.is_none(), "Ray outside TestMap terrain slab must resolve as PickResult.Kind.NONE")

	# Occlusion check: place LeaderA directly behind WallWest relative to camera at focus=(0,0).
	rig.set_focus_position(Vector2.ZERO)
	rig.set_target_zoom_distance(rig.default_distance)
	for _i: int in range(40):
		rig.step_camera(1.0 / 60.0)
	await wait_process_frames(2)

	var cam_to_wall_xz := Vector3(-8.0, 0.0, -6.0) - Vector3(cam.global_position.x, 0.0, cam.global_position.z)
	cam_to_wall_xz = cam_to_wall_xz.normalized()
	leader_a.global_position = Vector3(-8.0, 0.0, -6.0) + cam_to_wall_xz * 1.15
	await wait_physics_frames(3)

	var occluded_screen_pos: Vector2 = _project_unit_screen_pos(cam, leader_a)
	var occluded_pick: PickResult = controller.pick_at_screen_pos(occluded_screen_pos)
	assert_true(occluded_pick.is_obstacle(), "WallWest occluding LeaderA must return OBSTACLE instead of picking through wall")


func test_08_camera_compatibility_and_no_left_click_movement() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var leader_a: Unit = ctx["leader_a"] as Unit

	var initial_a_pos: Vector3 = leader_a.global_position
	await _simulate_left_click(_project_unit_screen_pos(cam, leader_a))
	assert_true(manager.is_selected(leader_a))

	# Wait briefly: left-click selection must NOT trigger movement.
	await wait_physics_frames(6)
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_vec3_near(leader_a.global_position, initial_a_pos, 0.01)

	# Middle-mouse drag continues panning camera without clearing selection.
	var focus_before_drag: Vector2 = rig.get_focus_position()
	_simulate_mouse_button(MOUSE_BUTTON_MIDDLE, Vector2(400.0, 300.0), true)
	await wait_process_frames(1)
	_simulate_mouse_move(Vector2(520.0, 340.0), Vector2(120.0, 40.0))
	await wait_process_frames(2)
	_simulate_mouse_button(MOUSE_BUTTON_MIDDLE, Vector2(520.0, 340.0), false)
	await wait_process_frames(2)

	assert_gt(rig.get_focus_position().distance_to(focus_before_drag), 0.1, "Middle mouse drag must pan camera")
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_a), "Camera middle drag must preserve selection")

	# WASD continues working alongside RtsInputController.
	var focus_before_wasd: Vector2 = rig.get_focus_position()
	_set_action_pressed(InputActions.CAMERA_PAN_UP, true)
	await wait_process_frames(8)
	_set_action_pressed(InputActions.CAMERA_PAN_UP, false)
	assert_gt(rig.get_focus_position().distance_to(focus_before_wasd), 0.1, "WASD pan must still work")
	assert_true(manager.is_selected(leader_a))


func test_09_drag_threshold_suppression_hover_and_rapid_clicks() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var cam: Camera3D = ctx["camera"] as Camera3D
	var manager: SelectionManager = ctx["selection_manager"] as SelectionManager
	var controller: RtsInputController = ctx["controller"] as RtsInputController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var a_screen: Vector2 = _project_unit_screen_pos(cam, leader_a)
	var b_screen: Vector2 = _project_unit_screen_pos(cam, leader_b)
	var ground_screen: Vector2 = cam.unproject_position(Vector3(0.0, 0.0, 6.0))

	# Drag across > threshold over empty ground: activates drag gesture and leaves selection empty.
	var empty_drag_end: Vector2 = ground_screen + Vector2(60.0, 40.0)
	_simulate_mouse_move(ground_screen)
	await wait_process_frames(1)
	_simulate_mouse_button(MOUSE_BUTTON_LEFT, ground_screen, true)
	await wait_process_frames(1)
	_simulate_mouse_move(empty_drag_end)
	await wait_process_frames(1)
	assert_true(controller.is_drag_gesture_active(), "Movement beyond drag threshold must mark drag gesture active")
	_simulate_mouse_button(MOUSE_BUTTON_LEFT, empty_drag_end, false)
	await wait_process_frames(2)

	assert_true(manager.is_empty(), "Empty box drag beyond threshold must leave selection empty")
	assert_false(controller.is_drag_gesture_active(), "Drag gesture flag must reset cleanly after release")

	# Hover transitions without button pressed.
	_simulate_mouse_move(b_screen)
	await wait_process_frames(2)
	assert_eq(controller.get_hovered_unit(), leader_b)
	assert_true(leader_b.is_hovered())
	assert_true((leader_b.get_selection_indicator().get_node("HoverRing") as MeshInstance3D).visible)

	_simulate_mouse_move(ground_screen)
	await wait_process_frames(2)
	assert_null(controller.get_hovered_unit())
	assert_false(leader_b.is_hovered())
	assert_false((leader_b.get_selection_indicator().get_node("HoverRing") as MeshInstance3D).visible)

	# Rapid alternating clicks remain consistent.
	await _simulate_left_click(a_screen)
	await _simulate_left_click(b_screen)
	await _simulate_left_click(a_screen)
	assert_eq(manager.get_selection_count(), 1)
	assert_true(manager.is_selected(leader_a))
	assert_false(leader_b.is_selected())
