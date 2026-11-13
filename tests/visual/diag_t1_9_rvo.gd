extends SceneTree
## Reproducible T1.9 diagnostic script (NO gameplay modifications).
## Measures minimum XZ separation, capsule/model overlap, heading flips,
## arrival states, and captures windowed screenshots at closest-approach instants
## across all 7 required RTS movement scenarios.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const OUTPUT_DIR: String = "res://test_output/t1_9_diag"
const CAPSULE_DIAMETER_M: float = 0.80 # Unit BodyCollision capsule radius = 0.40 m -> 2 * r = 0.80 m
const CORE_OVERLAP_M: float = 0.50
const MAX_SCENARIO_FRAMES: int = 480


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	var adapter_name: String = RenderingServer.get_video_adapter_name()
	var adapter_vendor: String = RenderingServer.get_video_adapter_vendor()
	print("============================================================")
	print("T1.9 RVO DIAGNOSTIC START")
	print("GPU Adapter: %s (%s)" % [adapter_name, adapter_vendor])
	print("Avoidance enabled check will be printed per unit.")
	print("============================================================")

	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	root.add_child(main_root)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	var selection: SelectionManager = main_root.get_selection_manager()
	var cmd: CommandController = main_root.get_command_controller()

	if nav == null or rig == null or selection == null or cmd == null:
		push_error("MainScene missing required nodes for T1.9 diagnostic.")
		quit(1)
		return

	rig.edge_pan_enabled = false

	var nav_wait: int = 0
	while not nav.is_navigation_ready() and nav_wait < 120:
		await physics_frame
		nav_wait += 1

	var leader_a: Unit = null
	var leader_b: Unit = null
	for unit: Unit in main_root.get_units():
		if unit.get_character_id() == &"leader_a":
			leader_a = unit
		elif unit.get_character_id() == &"leader_b":
			leader_b = unit

	if leader_a == null or leader_b == null:
		push_error("Missing LeaderA or LeaderB.")
		quit(1)
		return

	var agent_a: NavigationAgent3D = leader_a.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	var agent_b: NavigationAgent3D = leader_b.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	print("NavigationAgent3D avoidance_enabled: LeaderA=%s | LeaderB=%s" % [
		str(agent_a.avoidance_enabled if agent_a != null else false),
		str(agent_b.avoidance_enabled if agent_b != null else false),
	])

	var out_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Failed to create output dir: %s" % out_dir)
		quit(1)
		return

	for _i: int in range(10):
		await process_frame
		await physics_frame

	# Scenario 1: Side-by-side group walk
	await _run_scenario_group(
		"01_side_by_side",
		leader_a, leader_b, selection, cmd, rig,
		Vector3(-1.2, 0.0, 6.0), Vector3(1.2, 0.0, 6.0),
		Vector3(0.0, 0.0, -3.5), Vector2(0.0, 1.0), 22.0, out_dir
	)

	# Scenario 2: Head-on opposite crossing (collinear individual orders)
	await _run_scenario_individual(
		"02_head_on_crossing",
		leader_a, leader_b, selection, rig,
		Vector3(-5.5, 0.0, 0.0), Vector3(5.5, 0.0, 0.0),
		Vector3(5.5, 0.0, 0.0), Vector3(-5.5, 0.0, 0.0),
		Vector2(0.0, 0.0), 20.0, out_dir
	)

	# Scenario 3: Diagonal crossing
	await _run_scenario_individual(
		"03_diagonal_crossing",
		leader_a, leader_b, selection, rig,
		Vector3(-5.0, 0.0, 5.0), Vector3(5.0, 0.0, 5.0),
		Vector3(5.0, 0.0, -3.0), Vector3(-5.0, 0.0, -3.0),
		Vector2(0.0, 1.0), 22.0, out_dir
	)

	# Scenario 4: Both crossing through WallWithGap
	await _run_scenario_group(
		"04_wall_gap_transit",
		leader_a, leader_b, selection, cmd, rig,
		Vector3(-2.5, 0.0, 2.5), Vector3(2.5, 0.0, 2.5),
		Vector3(0.0, 0.0, -11.5), Vector2(0.0, -5.5), 24.0, out_dir
	)

	# Scenario 5a: Both climbing the ramp
	await _run_scenario_group(
		"05a_ramp_climb",
		leader_a, leader_b, selection, cmd, rig,
		Vector3(3.5, 0.0, -13.0), Vector3(3.5, 0.0, -15.0),
		Vector3(17.5, 2.0, -14.0), Vector2(10.5, -14.0), 24.0, out_dir
	)

	# Scenario 5b: Both descending the ramp
	await _run_scenario_group(
		"05b_ramp_descent",
		leader_a, leader_b, selection, cmd, rig,
		Vector3(16.5, 2.0, -13.0), Vector3(16.5, 2.0, -15.0),
		Vector3(3.5, 0.0, -14.0), Vector2(10.5, -14.0), 24.0, out_dir
	)

	# Scenario 6a: Same center target via group command (CommandController)
	await _run_scenario_group(
		"06a_same_target_group_cmd",
		leader_a, leader_b, selection, cmd, rig,
		Vector3(-3.0, 0.0, 3.0), Vector3(3.0, 0.0, 3.0),
		Vector3(0.0, 0.0, 0.0), Vector2(0.0, 1.0), 20.0, out_dir
	)

	# Scenario 6b: Same literal center target via two separate sequential single-unit commands (CommandController)
	await _run_scenario_sequential_individual_cmds(
		"06b_same_target_individual_orders",
		leader_a, leader_b, selection, cmd, rig,
		Vector3(-3.0, 0.0, 3.0), Vector3(3.0, 0.0, 3.0),
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0),
		Vector2(0.0, 1.0), 18.0, out_dir
	)

	# Scenario 8: Unit moving directly past a stationary IDLE unit
	await _run_scenario_past_idle(
		"08_moving_past_idle_unit",
		leader_a, leader_b, selection, rig,
		Vector3(-5.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0),
		Vector3(5.0, 0.0, 0.0), Vector2(0.0, 0.0), 18.0, out_dir
	)

	# Scenario 7: Order replacement mid-movement
	await _run_scenario_replacement(
		"07_order_replacement_mid_move",
		leader_a, leader_b, selection, cmd, rig, out_dir
	)

	print("============================================================")
	print("T1.9 RVO DIAGNOSTIC COMPLETE")
	print("============================================================")
	quit(0)


func _reset_units(
	leader_a: Unit,
	leader_b: Unit,
	pos_a: Vector3,
	pos_b: Vector3,
	rig: RtsCameraRig,
	cam_focus: Vector2,
	cam_zoom: float
) -> void:
	leader_a.cancel_current_order()
	leader_b.cancel_current_order()
	leader_a.global_position = pos_a
	leader_b.global_position = pos_b
	leader_a.velocity = Vector3.ZERO
	leader_b.velocity = Vector3.ZERO
	rig.set_focus_position(cam_focus)
	rig.set_target_zoom_distance(cam_zoom, true)
	for _i: int in range(6):
		await process_frame
		await physics_frame


func _run_scenario_group(
	label: String,
	leader_a: Unit,
	leader_b: Unit,
	selection: SelectionManager,
	cmd: CommandController,
	rig: RtsCameraRig,
	start_a: Vector3,
	start_b: Vector3,
	click_pos: Vector3,
	cam_focus: Vector2,
	cam_zoom: float,
	out_dir: String
) -> void:
	await _reset_units(leader_a, leader_b, start_a, start_b, rig, cam_focus, cam_zoom)
	selection.set_selection([leader_a, leader_b])
	cmd.command_at(PickResult.from_ground(click_pos, Vector3.UP))
	await _monitor_and_capture(label, leader_a, leader_b, out_dir)


func _run_scenario_individual(
	label: String,
	leader_a: Unit,
	leader_b: Unit,
	selection: SelectionManager,
	rig: RtsCameraRig,
	start_a: Vector3,
	start_b: Vector3,
	target_a: Vector3,
	target_b: Vector3,
	cam_focus: Vector2,
	cam_zoom: float,
	out_dir: String
) -> void:
	await _reset_units(leader_a, leader_b, start_a, start_b, rig, cam_focus, cam_zoom)
	selection.set_selection([leader_a, leader_b])
	leader_a.issue_order(MoveOrder.new(target_a))
	leader_b.issue_order(MoveOrder.new(target_b))
	await _monitor_and_capture(label, leader_a, leader_b, out_dir)


func _run_scenario_sequential_individual_cmds(
	label: String,
	leader_a: Unit,
	leader_b: Unit,
	selection: SelectionManager,
	cmd: CommandController,
	rig: RtsCameraRig,
	start_a: Vector3,
	start_b: Vector3,
	target_a: Vector3,
	target_b: Vector3,
	cam_focus: Vector2,
	cam_zoom: float,
	out_dir: String
) -> void:
	await _reset_units(leader_a, leader_b, start_a, start_b, rig, cam_focus, cam_zoom)
	selection.select_single(leader_a)
	cmd.command_at(PickResult.from_ground(target_a, Vector3.UP))
	await physics_frame
	selection.select_single(leader_b)
	cmd.command_at(PickResult.from_ground(target_b, Vector3.UP))
	await _monitor_and_capture(label, leader_a, leader_b, out_dir)


func _run_scenario_past_idle(
	label: String,
	leader_a: Unit,
	leader_b: Unit,
	selection: SelectionManager,
	rig: RtsCameraRig,
	start_a: Vector3,
	idle_b: Vector3,
	target_a: Vector3,
	cam_focus: Vector2,
	cam_zoom: float,
	out_dir: String
) -> void:
	await _reset_units(leader_a, leader_b, start_a, idle_b, rig, cam_focus, cam_zoom)
	selection.select_single(leader_a)
	leader_a.issue_order(MoveOrder.new(target_a))
	await _monitor_and_capture(label, leader_a, leader_b, out_dir)


func _run_scenario_replacement(
	label: String,
	leader_a: Unit,
	leader_b: Unit,
	selection: SelectionManager,
	cmd: CommandController,
	rig: RtsCameraRig,
	out_dir: String
) -> void:
	await _reset_units(
		leader_a, leader_b,
		Vector3(-2.5, 0.0, 4.0), Vector3(2.5, 0.0, 4.0),
		rig, Vector2(0.0, 1.0), 22.0
	)
	selection.set_selection([leader_a, leader_b])
	cmd.command_at(PickResult.from_ground(Vector3(0.0, 0.0, -3.0), Vector3.UP))

	# Run 38 frames (~0.63 s) then issue a reversed crossed replacement order
	for _i: int in range(38):
		await physics_frame
	await _save_shot(out_dir.path_join("%s_01_before_replace.png" % label))
	cmd.command_at(PickResult.from_ground(Vector3(0.0, 0.0, 4.5), Vector3.UP))
	await _monitor_and_capture(label, leader_a, leader_b, out_dir, true)


func _monitor_and_capture(
	label: String,
	leader_a: Unit,
	leader_b: Unit,
	out_dir: String,
	skip_initial_shot: bool = false
) -> void:
	var last_status_a: Array[int] = [-1]
	var last_status_b: Array[int] = [-1]
	var conn_a := func(order: UnitOrder) -> void:
		last_status_a[0] = order.status
	var conn_b := func(order: UnitOrder) -> void:
		last_status_b[0] = order.status
	leader_a.order_finished.connect(conn_a)
	leader_b.order_finished.connect(conn_b)

	var min_dist: float = INF
	var min_frame: int = -1
	var min_pos_a: Vector3 = Vector3.ZERO
	var min_pos_b: Vector3 = Vector3.ZERO
	var overlap_08_frames: int = 0
	var overlap_05_frames: int = 0
	var heading_flips_a: int = 0
	var heading_flips_b: int = 0

	var prev_dist: float = _dist_xz(leader_a.global_position, leader_b.global_position)
	var prev_yaw_a: float = leader_a.rotation.y
	var prev_yaw_b: float = leader_b.rotation.y
	var captured_mid: bool = skip_initial_shot
	var captured_closest: bool = false

	var frames: int = 0
	while frames < MAX_SCENARIO_FRAMES:
		await physics_frame
		frames += 1

		var dist: float = _dist_xz(leader_a.global_position, leader_b.global_position)
		if dist < min_dist:
			min_dist = dist
			min_frame = frames
			min_pos_a = leader_a.global_position
			min_pos_b = leader_b.global_position

		if dist < CAPSULE_DIAMETER_M:
			overlap_08_frames += 1
		if dist < CORE_OVERLAP_M:
			overlap_05_frames += 1

		var dyaw_a: float = absf(wrapf(leader_a.rotation.y - prev_yaw_a, -PI, PI))
		var dyaw_b: float = absf(wrapf(leader_b.rotation.y - prev_yaw_b, -PI, PI))
		if dyaw_a > deg_to_rad(60.0) and frames > 3:
			heading_flips_a += 1
		if dyaw_b > deg_to_rad(60.0) and frames > 3:
			heading_flips_b += 1
		prev_yaw_a = leader_a.rotation.y
		prev_yaw_b = leader_b.rotation.y

		if not captured_mid and frames == 30:
			captured_mid = true
			await _save_shot(out_dir.path_join("%s_01_mid.png" % label))

		# Capture right when distance inflects upward after passing closest point (< 1.6 m)
		if not captured_closest and dist > prev_dist + 0.01 and prev_dist < 1.6:
			captured_closest = true
			print("  [%s closest-capture] frame=%d | dist=%.3f m | A=%s | B=%s" % [
				label, frames, dist, str(leader_a.global_position), str(leader_b.global_position)
			])
			await _save_shot(out_dir.path_join("%s_02_closest.png" % label))

		prev_dist = dist

		if leader_a.get_state() == Unit.State.IDLE and leader_b.get_state() == Unit.State.IDLE:
			break

	if not captured_closest:
		await _save_shot(out_dir.path_join("%s_02_closest.png" % label))
	await _save_shot(out_dir.path_join("%s_03_end.png" % label))

	leader_a.order_finished.disconnect(conn_a)
	leader_b.order_finished.disconnect(conn_b)

	var final_dist: float = _dist_xz(leader_a.global_position, leader_b.global_position)
	print("[SCENARIO %s] frames=%d | min_dist_xz=%.3f m (at f=%d, A=%s, B=%s) | final_dist_xz=%.3f m | overlap<0.8m=%df | overlap<0.5m=%df | flips=(%d,%d) | states=(%d,%d) | order_status=(%d,%d)" % [
		label, frames, min_dist, min_frame, str(min_pos_a), str(min_pos_b),
		final_dist, overlap_08_frames, overlap_05_frames,
		heading_flips_a, heading_flips_b,
		leader_a.get_state(), leader_b.get_state(),
		last_status_a[0], last_status_b[0],
	])


func _save_shot(abs_path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png(abs_path)


static func _dist_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
