extends TestCase
## Integration tests for T1.8 RTS right-click movement commands (Tests A-E):
## individual & group right-click moves, destination marker feedback, obstacle & ramp routing,
## invalid/unreachable edge cases, right-click selection preservation, and rapid click spam.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const MAX_NAV_WAIT_FRAMES: int = 120
const MAX_MOVE_FRAMES: int = 600 # 10 seconds at 60 Hz
const AC08_ARRIVAL_TOLERANCE_M: float = 0.5
const AC08_MIN_UNIT_SEPARATION_M: float = WorldNavigation.DEFAULT_AGENT_RADIUS * 2.0


func after_each() -> void:
	_release_all_inputs()


func _release_all_inputs() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_push_mouse_button(MOUSE_BUTTON_LEFT, Vector2.ZERO, false, false)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_push_mouse_button(MOUSE_BUTTON_RIGHT, Vector2.ZERO, false, false)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_push_mouse_button(MOUSE_BUTTON_MIDDLE, Vector2.ZERO, false, false)


func _spawn_main_scene() -> Dictionary:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	add_test_child(main_root)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	if nav != null:
		var wait_frames: int = 0
		while not nav.is_navigation_ready() and wait_frames < MAX_NAV_WAIT_FRAMES:
			await wait_physics_frames(1)
			wait_frames += 1

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
		"test_map": test_map,
		"nav": nav,
		"rig": rig,
		"camera": rig.get_camera() if rig != null else null,
		"selection_manager": main_root.get_selection_manager(),
		"command_controller": main_root.get_command_controller(),
		"destination_marker": main_root.get_destination_marker(),
		"controller": main_root.get_input_controller(),
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _project_world_point(rig: RtsCameraRig, camera: Camera3D, world_pos: Vector3) -> Vector2:
	rig.set_focus_position(Vector2(world_pos.x, world_pos.z))
	return camera.unproject_position(world_pos)


func _push_mouse_move(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	get_viewport().push_input(motion, true)


func _push_mouse_button(button: MouseButton, screen_pos: Vector2, pressed: bool, shift_held: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = screen_pos
	ev.global_position = screen_pos
	ev.pressed = pressed
	ev.shift_pressed = shift_held
	get_viewport().push_input(ev, true)


func _simulate_left_click(screen_pos: Vector2, shift_held: bool = false) -> void:
	_push_mouse_move(screen_pos)
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_LEFT, screen_pos, true, shift_held)
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_LEFT, screen_pos, false, shift_held)
	await wait_process_frames(2)


func _simulate_right_click(screen_pos: Vector2) -> void:
	_push_mouse_move(screen_pos)
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_RIGHT, screen_pos, true)
	await wait_process_frames(1)
	_push_mouse_button(MOUSE_BUTTON_RIGHT, screen_pos, false)
	await wait_process_frames(2)


func _wait_until_units_idle(units: Array[Unit], max_frames: int = MAX_MOVE_FRAMES) -> int:
	var frames: int = 0
	while frames < max_frames:
		var any_moving: bool = false
		for unit: Unit in units:
			if unit.get_state() != Unit.State.IDLE:
				any_moving = true
				break
		if not any_moving:
			return frames
		await wait_physics_frames(1)
		frames += 1
	return frames


func _distance_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func test_01_individual_right_click_orders_for_each_protagonist_and_marker() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var camera: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var marker: DestinationMarker = ctx["destination_marker"] as DestinationMarker
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	var a_finished: Array[UnitOrder] = []
	leader_a.order_finished.connect(func(order: UnitOrder) -> void:
		a_finished.append(order)
	)

	# 1. Select LeaderA via left-click and command to ground point
	var a_screen: Vector2 = camera.unproject_position(SelectionBoxMath.get_unit_world_anchor(leader_a))
	await _simulate_left_click(a_screen)
	assert_eq(selection.get_selection_count(), 1)
	assert_true(selection.is_selected(leader_a))

	var dest_a := Vector3(-6.0, 0.0, -1.0)
	_project_world_point(rig, camera, dest_a)
	await wait_process_frames(2)
	var dest_a_screen: Vector2 = camera.unproject_position(dest_a)
	await _simulate_right_click(dest_a_screen)

	assert_true(marker.is_marker_active(), "DestinationMarker must appear upon valid right-click order")
	assert_eq(leader_a.get_state(), Unit.State.MOVING)
	assert_eq(leader_b.get_state(), Unit.State.IDLE, "Unselected LeaderB must not receive LeaderA order")
	assert_true(selection.is_selected(leader_a) and selection.get_selection_count() == 1, "Right click must preserve selection")

	var frames_a: int = await _wait_until_units_idle([leader_a])
	assert_lt(float(frames_a), float(MAX_MOVE_FRAMES), "LeaderA must arrive within timeout")
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(a_finished.size(), 1)
	assert_eq(a_finished[0].status, UnitOrder.Status.SUCCEEDED)
	assert_true(_distance_xz(leader_a.global_position, dest_a) <= AC08_ARRIVAL_TOLERANCE_M, "LeaderA must arrive within 0.5m")

	# Wait for DestinationMarker auto-fade (> 0.65s across process frames)
	var fade_frames: int = 0
	while marker.is_marker_active() and fade_frames < 90:
		await wait_process_frames(1)
		fade_frames += 1
	assert_false(marker.is_marker_active(), "DestinationMarker must disappear automatically after pulse duration")
	assert_false(marker.visible)

	# 2. Switch selection exclusively to LeaderB and move independently
	var b_anchor: Vector3 = SelectionBoxMath.get_unit_world_anchor(leader_b)
	_project_world_point(rig, camera, b_anchor)
	await wait_process_frames(2)
	var b_screen: Vector2 = camera.unproject_position(b_anchor)
	await _simulate_left_click(b_screen)
	assert_eq(selection.get_selection_count(), 1)
	assert_true(selection.is_selected(leader_b))

	var a_pos_before_b_move: Vector3 = leader_a.global_position
	var dest_b := Vector3(6.5, 0.0, 0.5)
	_project_world_point(rig, camera, dest_b)
	await wait_process_frames(2)
	await _simulate_right_click(camera.unproject_position(dest_b))

	assert_eq(leader_b.get_state(), Unit.State.MOVING)
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	var frames_b: int = await _wait_until_units_idle([leader_b])
	assert_lt(float(frames_b), float(MAX_MOVE_FRAMES))
	assert_true(_distance_xz(leader_b.global_position, dest_b) <= AC08_ARRIVAL_TOLERANCE_M, "LeaderB must arrive within 0.5m")
	assert_vec3_near(leader_a.global_position, a_pos_before_b_move, 0.05, "LeaderA must remain stationary")


func test_02_simultaneous_group_move_distributes_non_overlapping_targets_ac08() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var camera: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	selection.set_selection([leader_a, leader_b])
	assert_eq(selection.get_selection_count(), 2)

	var click_world := Vector3(0.0, 0.0, -2.5)
	_project_world_point(rig, camera, click_world)
	await wait_process_frames(2)
	await _simulate_right_click(camera.unproject_position(click_world))

	assert_eq(selection.get_selection_count(), 2, "Right click must never alter multi-unit selection")
	assert_eq(leader_a.get_state(), Unit.State.MOVING)
	assert_eq(leader_b.get_state(), Unit.State.MOVING)

	var plan: GroupMovePlanner.PlanResult = cmd.get_last_plan()
	assert_not_null(plan)
	assert_true(plan.valid)
	assert_true(plan.all_slots_reachable)
	assert_eq(plan.targets.size(), 2)

	var assigned_a: Vector3 = (leader_a.get_current_order() as MoveOrder).target_position
	var assigned_b: Vector3 = (leader_b.get_current_order() as MoveOrder).target_position
	assert_true(_distance_xz(assigned_a, assigned_b) >= AC08_MIN_UNIT_SEPARATION_M + 0.5, "Planned slots must exceed minimum separation")

	var frames: int = await _wait_until_units_idle([leader_a, leader_b])
	assert_lt(float(frames), float(MAX_MOVE_FRAMES), "Both units must reach group destination within 10s")
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(leader_b.get_state(), Unit.State.IDLE)

	assert_true(_distance_xz(leader_a.global_position, assigned_a) <= AC08_ARRIVAL_TOLERANCE_M, "LeaderA within 0.5m of assigned target")
	assert_true(_distance_xz(leader_b.global_position, assigned_b) <= AC08_ARRIVAL_TOLERANCE_M, "LeaderB within 0.5m of assigned target")
	var final_sep: float = _distance_xz(leader_a.global_position, leader_b.global_position)
	assert_true(final_sep >= AC08_MIN_UNIT_SEPARATION_M, "Final separation must satisfy >= 2 * agent_radius (AC-08)")


func test_03_navigation_through_wall_gap_and_onto_ramp_plateau_and_obstacle_click() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var camera: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var controller: RtsInputController = ctx["controller"] as RtsInputController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	# 1. Group move across WallWithGap to z = -11.5
	selection.set_selection([leader_a, leader_b])
	var north_goal := Vector3(0.0, 0.0, -11.5)
	_project_world_point(rig, camera, north_goal)
	await wait_process_frames(2)
	await _simulate_right_click(camera.unproject_position(north_goal))

	var gap_frames: int = await _wait_until_units_idle([leader_a, leader_b])
	assert_lt(float(gap_frames), float(MAX_MOVE_FRAMES), "Group must route through WallGap cleanly")
	assert_lt(leader_a.global_position.z, -8.5, "LeaderA must cross to north side of WallWithGap")
	assert_lt(leader_b.global_position.z, -8.5, "LeaderB must cross to north side of WallWithGap")
	assert_true(_distance_xz(leader_a.global_position, leader_b.global_position) >= AC08_MIN_UNIT_SEPARATION_M)

	# 2. Single unit order onto elevated Ramp -> Plateau
	selection.select_single(leader_a)
	var plateau_goal := Vector3(17.0, 2.0, -14.0)
	_project_world_point(rig, camera, plateau_goal)
	await wait_process_frames(2)
	await _simulate_right_click(camera.unproject_position(plateau_goal))

	var plateau_frames: int = await _wait_until_units_idle([leader_a])
	assert_lt(float(plateau_frames), float(MAX_MOVE_FRAMES), "LeaderA must climb ramp to plateau")
	assert_true(leader_a.global_position.y >= 1.85, "LeaderA must stand on elevated plateau")
	assert_true(_distance_xz(leader_a.global_position, plateau_goal) <= AC08_ARRIVAL_TOLERANCE_M)

	# 3. Right-click directly on static obstacle (WallWest) resolves adjacent valid navigable spot
	selection.select_single(leader_b)
	var wall_top := Vector3(-6.0, 2.4, -6.0)
	_project_world_point(rig, camera, wall_top)
	await wait_process_frames(2)
	var wall_screen: Vector2 = camera.unproject_position(wall_top)
	var obs_pick: PickResult = controller.pick_at_screen_pos(wall_screen)
	assert_true(obs_pick.is_obstacle(), "Probe onto WallWest must yield PickResult.Kind.OBSTACLE")

	var b_orders: Array[UnitOrder] = []
	leader_b.order_finished.connect(func(order: UnitOrder) -> void:
		b_orders.append(order)
	)
	await _simulate_right_click(wall_screen)
	assert_eq(leader_b.get_state(), Unit.State.MOVING)
	var obs_frames: int = await _wait_until_units_idle([leader_b])
	assert_lt(float(obs_frames), float(MAX_MOVE_FRAMES))
	assert_eq(b_orders.size(), 1)
	assert_eq(b_orders[0].status, UnitOrder.Status.SUCCEEDED, "Obstacle click must resolve a nearby reachable ground spot")


func test_04_invalid_commands_empty_sky_enclosure_unit_click_preready_and_removal() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var camera: Camera3D = ctx["camera"] as Camera3D
	var nav: WorldNavigation = ctx["nav"] as WorldNavigation
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var marker: DestinationMarker = ctx["destination_marker"] as DestinationMarker
	var controller: RtsInputController = ctx["controller"] as RtsInputController
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	# 1. Empty selection right-click -> clean no-op
	selection.clear_selection()
	_project_world_point(rig, camera, Vector3.ZERO)
	await wait_process_frames(2)
	await _simulate_right_click(camera.unproject_position(Vector3.ZERO))
	assert_false(marker.is_marker_active(), "No marker when selection is empty")
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(leader_b.get_state(), Unit.State.IDLE)

	# 2. Sky / out-of-bounds right-click (PickResult.NONE) -> ignored cleanly without altering selection
	selection.select_single(leader_a)
	rig.set_focus_position(Vector2(-29.0, -29.0))
	rig.set_target_zoom_distance(16.0, true)
	await wait_process_frames(2)
	var oob_screen := Vector2(18.0, 18.0)
	var oob_pick: PickResult = controller.pick_at_screen_pos(oob_screen)
	assert_true(oob_pick.is_none(), "Top-left screen corner near map corner must pick NONE/sky")
	await _simulate_right_click(oob_screen)
	assert_true(selection.is_selected(leader_a) and selection.get_selection_count() == 1)
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_false(marker.is_marker_active())

	# 3. Provisional right-click on another unit preserves selection and doesn't crash
	var b_world: Vector3 = SelectionBoxMath.get_unit_world_anchor(leader_b)
	_project_world_point(rig, camera, b_world)
	await wait_process_frames(2)
	await _simulate_right_click(camera.unproject_position(b_world))
	assert_eq(selection.get_selection_count(), 1, "Right-clicking another unit must not alter selection")
	assert_true(selection.is_selected(leader_a))
	await _wait_until_units_idle([leader_a])

	# 4. Pre-ready navmesh rejects commands safely
	nav._is_ready = false
	var cmd_when_unready: bool = cmd.command_at(PickResult.from_ground(Vector3(2.0, 0.0, 2.0), Vector3.UP))
	assert_false(cmd_when_unready, "CommandController must ignore orders while navigation is not ready")
	nav._is_ready = true

	# 5. Unreachable ClosedEnclosure interior honors WorldNavigation/MoveOrder failure contract (AC-10)
	var a_orders: Array[UnitOrder] = []
	leader_a.order_finished.connect(func(order: UnitOrder) -> void:
		a_orders.append(order)
	)
	var enclosure_interior := Vector3(-16.0, 0.0, 12.0)
	_project_world_point(rig, camera, enclosure_interior)
	await wait_process_frames(2)
	await _simulate_right_click(camera.unproject_position(enclosure_interior))

	var enc_frames: int = await _wait_until_units_idle([leader_a])
	assert_lt(float(enc_frames), float(MAX_MOVE_FRAMES), "Unreachable enclosure order must resolve & finish within 10s")
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_true(a_orders.size() >= 1)
	var last_order: UnitOrder = a_orders[a_orders.size() - 1]
	assert_eq(last_order.status, UnitOrder.Status.FAILED, "ClosedEnclosure order must NOT falsely claim SUCCEEDED")
	assert_eq(last_order.failure_reason, UnitOrder.REASON_UNREACHABLE)

	# 6. Selected unit freed/removed from tree must not crash subsequent group command
	selection.set_selection([leader_a, leader_b])
	leader_a.queue_free()
	await wait_process_frames(2)
	var post_free_ok: bool = cmd.command_at(PickResult.from_ground(Vector3(0.0, 0.0, 0.0), Vector3.UP))
	assert_true(post_free_ok, "Remaining selected unit must still accept command cleanly")
	await _wait_until_units_idle([leader_b])


func test_05_rapid_command_spam_20hz_replaces_orders_without_marker_buildup_ac11() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var main_root: MainScene = ctx["main"] as MainScene
	var rig: RtsCameraRig = ctx["rig"] as RtsCameraRig
	var camera: Camera3D = ctx["camera"] as Camera3D
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var marker: DestinationMarker = ctx["destination_marker"] as DestinationMarker
	var leader_a: Unit = ctx["leader_a"] as Unit
	var leader_b: Unit = ctx["leader_b"] as Unit

	selection.set_selection([leader_a, leader_b])
	rig.set_focus_position(Vector2(0.0, 0.0))
	rig.set_target_zoom_distance(26.0, true)
	await wait_process_frames(3)

	var a_replaced_count: Array[int] = [0]
	var a_succeeded_count: Array[int] = [0]
	leader_a.order_finished.connect(func(order: UnitOrder) -> void:
		if order.status == UnitOrder.Status.CANCELLED and order.failure_reason == UnitOrder.REASON_REPLACED:
			a_replaced_count[0] += 1
		elif order.status == UnitOrder.Status.SUCCEEDED:
			a_succeeded_count[0] += 1
	)

	var initial_scene_children: int = main_root.get_child_count()
	var initial_marker_children: int = marker.get_child_count()
	var initial_pulse_count: int = marker.get_pulse_count()

	# Issue 24 commands across ~1.2 seconds (20 clicks/sec cadence = every 3 physics frames at 60 Hz)
	var waypoints: Array[Vector3] = [
		Vector3(-4.0, 0.0, -1.0),
		Vector3(4.0, 0.0, -1.0),
		Vector3(4.0, 0.0, 5.0),
		Vector3(-4.0, 0.0, 5.0),
	]
	for idx: int in range(23):
		var target_pt: Vector3 = waypoints[idx % waypoints.size()]
		var scr: Vector2 = camera.unproject_position(target_pt)
		_push_mouse_button(MOUSE_BUTTON_RIGHT, scr, true)
		_push_mouse_button(MOUSE_BUTTON_RIGHT, scr, false)
		await wait_physics_frames(3)

	# 24th final authoritative destination
	var final_click := Vector3(0.0, 0.0, -2.0)
	var final_scr: Vector2 = camera.unproject_position(final_click)
	await _simulate_right_click(final_scr)

	assert_eq(main_root.get_child_count(), initial_scene_children, "MainScene must not accumulate DestinationMarker nodes")
	assert_eq(marker.get_child_count(), initial_marker_children, "DestinationMarker must not accumulate child nodes")
	assert_eq(marker.get_pulse_count() - initial_pulse_count, 24, "Every valid click must reuse and pulse the single marker")

	var settle_frames: int = await _wait_until_units_idle([leader_a, leader_b])
	assert_lt(float(settle_frames), float(MAX_MOVE_FRAMES), "Units must converge on latest spam destination without getting stuck")
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(leader_b.get_state(), Unit.State.IDLE)
	assert_true(a_replaced_count[0] >= 20, "Rapid consecutive commands must cleanly cancel previous orders with REASON_REPLACED")
	assert_eq(a_succeeded_count[0], 1, "Only the final command after spam must finish SUCCEEDED")
	assert_true(_distance_xz(leader_a.global_position, leader_b.global_position) >= AC08_MIN_UNIT_SEPARATION_M)
