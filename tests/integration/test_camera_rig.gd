extends TestCase
## Integration tests for RtsCameraRig: pivot hierarchy, zoom limits and smoothing,
## simulated keyboard/drag pan, proportional speed, map bounds, time_scale & pause
## independence, and MainScene/DebugOverlay preservation.

const CAMERA_RIG_SCENE: PackedScene = preload("res://src/camera/rts_camera_rig.tscn")
const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")


func after_each() -> void:
	Engine.time_scale = 1.0
	if get_tree() != null:
		get_tree().paused = false
	_release_all_camera_actions()


func test_01_rig_initial_projection_and_pivot_hierarchy() -> void:
	var rig: RtsCameraRig = CAMERA_RIG_SCENE.instantiate() as RtsCameraRig
	add_test_child(rig)
	await wait_process_frames(2)

	var yaw_pivot: Node3D = rig.get_yaw_pivot()
	var pitch_pivot: Node3D = rig.get_pitch_pivot()
	var cam: Camera3D = rig.get_camera()

	assert_not_null(yaw_pivot, "RtsCameraRig must have YawPivot")
	assert_not_null(pitch_pivot, "RtsCameraRig must have PitchPivot")
	assert_not_null(cam, "RtsCameraRig must have Camera3D")
	if cam == null or yaw_pivot == null or pitch_pivot == null:
		return

	assert_eq(cam.projection, Camera3D.PROJECTION_PERSPECTIVE)
	assert_near(cam.fov, 35.0, 0.01)
	assert_near(rad_to_deg(yaw_pivot.rotation.y), 45.0, 0.05)
	assert_near(rad_to_deg(pitch_pivot.rotation.x), -55.0, 0.05)
	assert_near(rig.get_current_zoom_distance(), 36.0, 0.01)

	var expected_offset: Vector3 = CameraMath.compute_camera_local_offset(
		36.0,
		deg_to_rad(45.0),
		deg_to_rad(55.0)
	)
	assert_vec3_near(cam.global_position - rig.global_position, expected_offset, 0.02, "Camera3D world offset must match isometric rig math")


func test_02_zoom_limits_and_smooth_convergence() -> void:
	var rig: RtsCameraRig = CAMERA_RIG_SCENE.instantiate() as RtsCameraRig
	add_test_child(rig)
	await wait_process_frames(1)

	rig.zoom_by(-20.0)
	assert_near(rig.get_target_zoom_distance(), rig.min_distance, 0.001, "Zoom in must clamp at min_distance")

	var prev_dist: float = rig.get_current_zoom_distance()
	for _i: int in range(60):
		rig.step_camera(1.0 / 60.0)
		var curr_dist: float = rig.get_current_zoom_distance()
		assert_true(curr_dist <= prev_dist + 0.0001, "Zoom in must converge monotonically without oscillation")
		assert_true(curr_dist >= rig.min_distance - 0.0001, "Zoom must never undershoot min_distance")
		prev_dist = curr_dist
	assert_near(rig.get_current_zoom_distance(), rig.min_distance, 0.02, "Zoom must converge to min_distance")

	rig.zoom_by(30.0)
	assert_near(rig.get_target_zoom_distance(), rig.max_distance, 0.001, "Zoom out must clamp at max_distance")

	prev_dist = rig.get_current_zoom_distance()
	for _i: int in range(60):
		rig.step_camera(1.0 / 60.0)
		var curr_dist: float = rig.get_current_zoom_distance()
		assert_true(curr_dist >= prev_dist - 0.0001, "Zoom out must converge monotonically without oscillation")
		assert_true(curr_dist <= rig.max_distance + 0.0001, "Zoom must never overshoot max_distance")
		prev_dist = curr_dist
	assert_near(rig.get_current_zoom_distance(), rig.max_distance, 0.02, "Zoom must converge to max_distance")


func test_03_simulated_keyboard_pan_and_bounds_clamping() -> void:
	var rig: RtsCameraRig = CAMERA_RIG_SCENE.instantiate() as RtsCameraRig
	rig.edge_pan_enabled = false
	add_test_child(rig)
	rig.set_map_bounds(Rect2(-32.0, -32.0, 64.0, 64.0))
	rig.set_focus_position(Vector2.ZERO)
	await wait_process_frames(1)

	_set_action_pressed(InputActions.CAMERA_PAN_RIGHT, true)
	await wait_process_frames(12)
	_set_action_pressed(InputActions.CAMERA_PAN_RIGHT, false)
	await wait_process_frames(1)

	var moved: Vector2 = rig.get_focus_position()
	var expected_dir: Vector2 = CameraMath.screen_pan_to_world_xz(Vector2(1.0, 0.0), deg_to_rad(45.0))
	assert_gt(moved.length(), 0.5, "Simulated pan right must move camera focus")
	assert_vec2_near(moved.normalized(), expected_dir, 0.02, "Focus displacement direction must align with isometric screen right")

	_set_action_pressed(InputActions.CAMERA_PAN_RIGHT, true)
	_set_action_pressed(InputActions.CAMERA_PAN_UP, true)
	await wait_process_frames(1)
	for _i: int in range(180):
		rig.step_camera(1.0 / 60.0)
	_set_action_pressed(InputActions.CAMERA_PAN_RIGHT, false)
	_set_action_pressed(InputActions.CAMERA_PAN_UP, false)
	await wait_process_frames(1)

	var bounded: Vector2 = rig.get_focus_position()
	assert_true(bounded.x >= -32.0 and bounded.x <= 32.0, "Focus X must stay within map bounds")
	assert_true(bounded.y >= -32.0 and bounded.y <= 32.0, "Focus Z must stay within map bounds")
	assert_near(bounded.y, -32.0, 0.01, "Holding up+right toward north edge must clamp cleanly at z=-32")


func test_04_simulated_middle_drag_moves_focus_and_respects_bounds() -> void:
	var rig: RtsCameraRig = CAMERA_RIG_SCENE.instantiate() as RtsCameraRig
	rig.edge_pan_enabled = false
	add_test_child(rig)
	rig.set_map_bounds(Rect2(-32.0, -32.0, 64.0, 64.0))
	rig.set_focus_position(Vector2.ZERO)
	await wait_process_frames(1)

	var press: InputEventAction = InputEventAction.new()
	press.action = InputActions.CAMERA_DRAG
	press.pressed = true
	Input.parse_input_event(press)

	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(640.0, 360.0)
	motion.relative = Vector2(120.0, 0.0)
	Input.parse_input_event(motion)

	var release: InputEventAction = InputEventAction.new()
	release.action = InputActions.CAMERA_DRAG
	release.pressed = false
	Input.parse_input_event(release)

	await wait_process_frames(2)

	var focus_after_drag: Vector2 = rig.get_focus_position()
	var expected_left: Vector2 = CameraMath.screen_pan_to_world_xz(Vector2(-1.0, 0.0), deg_to_rad(45.0))
	assert_gt(focus_after_drag.length(), 0.2, "Middle-mouse drag must displace focus")
	assert_vec2_near(focus_after_drag.normalized(), expected_left, 0.02, "Dragging cursor right must grab-pan focus left")

	var post_release_motion: InputEventMouseMotion = InputEventMouseMotion.new()
	post_release_motion.position = Vector2(740.0, 360.0)
	post_release_motion.relative = Vector2(200.0, 0.0)
	Input.parse_input_event(post_release_motion)
	await wait_process_frames(2)
	assert_vec2_near(rig.get_focus_position(), focus_after_drag, 0.001, "Mouse motion after drag release must not move camera")


func test_05_pan_speed_scales_with_zoom_distance() -> void:
	var rig: RtsCameraRig = CAMERA_RIG_SCENE.instantiate() as RtsCameraRig
	rig.edge_pan_enabled = false
	add_test_child(rig)
	rig.set_map_bounds(Rect2(-100.0, -100.0, 200.0, 200.0))
	await wait_process_frames(1)

	rig.set_target_zoom_distance(rig.min_distance, true)
	rig.set_focus_position(Vector2.ZERO)
	Input.action_press(InputActions.CAMERA_PAN_RIGHT)
	for _i: int in range(30):
		rig.step_camera(1.0 / 60.0)
	Input.action_release(InputActions.CAMERA_PAN_RIGHT)
	var dist_at_min_zoom: float = rig.get_focus_position().length()

	rig.set_target_zoom_distance(rig.max_distance, true)
	rig.set_focus_position(Vector2.ZERO)
	Input.action_press(InputActions.CAMERA_PAN_RIGHT)
	for _i: int in range(30):
		rig.step_camera(1.0 / 60.0)
	Input.action_release(InputActions.CAMERA_PAN_RIGHT)
	var dist_at_max_zoom: float = rig.get_focus_position().length()

	var actual_ratio: float = dist_at_max_zoom / maxf(dist_at_min_zoom, 0.001)
	var expected_ratio: float = rig.max_distance / rig.min_distance
	assert_near(actual_ratio, expected_ratio, 0.05, "Pan displacement must scale proportionally with zoom distance")


func test_06_real_time_delta_independent_of_time_scale_and_pause() -> void:
	var rig: RtsCameraRig = CAMERA_RIG_SCENE.instantiate() as RtsCameraRig
	rig.edge_pan_enabled = false
	add_test_child(rig)
	rig.set_map_bounds(Rect2(-100.0, -100.0, 200.0, 200.0))
	await wait_process_frames(2)

	Engine.time_scale = 0.5
	rig.set_focus_position(Vector2.ZERO)
	_set_action_pressed(InputActions.CAMERA_PAN_UP, true)
	await get_tree().create_timer(0.18, true, false, true).timeout
	_set_action_pressed(InputActions.CAMERA_PAN_UP, false)
	var disp_half: float = rig.get_focus_position().length()

	Engine.time_scale = 4.0
	rig.set_focus_position(Vector2.ZERO)
	_set_action_pressed(InputActions.CAMERA_PAN_UP, true)
	await get_tree().create_timer(0.18, true, false, true).timeout
	_set_action_pressed(InputActions.CAMERA_PAN_UP, false)
	var disp_four_x: float = rig.get_focus_position().length()

	assert_gt(disp_half, 1.0, "Camera must pan cleanly at 0.5x time_scale")
	assert_gt(disp_four_x, 1.0, "Camera must pan cleanly at 4.0x time_scale")
	var ratio: float = disp_four_x / maxf(disp_half, 0.001)
	assert_gt(ratio, 0.65, "4x vs 0.5x real-time camera displacement ratio must stay near 1.0 (not 8x)")
	assert_lt(ratio, 1.45, "4x vs 0.5x real-time camera displacement ratio must stay near 1.0 (not 8x)")

	Engine.time_scale = 1.0
	get_tree().paused = true
	rig.set_focus_position(Vector2.ZERO)
	_set_action_pressed(InputActions.CAMERA_PAN_LEFT, true)
	await get_tree().create_timer(0.12, true, false, true).timeout
	_set_action_pressed(InputActions.CAMERA_PAN_LEFT, false)
	var disp_paused: float = rig.get_focus_position().length()
	get_tree().paused = false
	assert_gt(disp_paused, 0.5, "Camera must continue panning while SceneTree is paused")


func test_07_no_unexpected_drift_and_main_scene_preservation() -> void:
	var main_root: Node = MAIN_SCENE.instantiate()
	add_test_child(main_root)
	await wait_process_frames(8)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	var overlay: DebugOverlay = main_root.get_node_or_null("UiLayer/DebugOverlay") as DebugOverlay

	assert_not_null(test_map, "Main scene must preserve TestMap")
	assert_not_null(rig, "Main scene must compose RtsCameraRig")
	assert_not_null(overlay, "Main scene must preserve UiLayer/DebugOverlay")
	if test_map == null or rig == null:
		return

	assert_eq(rig.get_map_bounds(), test_map.get_map_bounds(), "Main scene must wire TestMap bounds to RtsCameraRig")
	assert_vec2_near(rig.get_focus_position(), Vector2.ZERO, 0.0001, "Camera must not drift with no user input")
	assert_near(rig.get_current_zoom_distance(), rig.default_distance, 0.0001, "Zoom must remain steady with no user input")


func _set_action_pressed(action: StringName, pressed: bool) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _release_all_camera_actions() -> void:
	var actions: Array[StringName] = [
		InputActions.CAMERA_PAN_UP,
		InputActions.CAMERA_PAN_DOWN,
		InputActions.CAMERA_PAN_LEFT,
		InputActions.CAMERA_PAN_RIGHT,
		InputActions.CAMERA_DRAG,
	]
	for action: StringName in actions:
		if Input.is_action_pressed(action):
			_set_action_pressed(action, false)
