extends SceneTree
## Visual verification script for T1.8 (windowed 1280x720, --fixed-fps 60):
## Captures right-click individual order + DestinationMarker, group order issuance,
## wall-gap individual routing, and final separated idle convergence.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const OUTPUT_DIR: String = "res://test_output"


func _initialize() -> void:
	call_deferred("_run_captures")


func _run_captures() -> void:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	root.add_child(main_root)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	var selection: SelectionManager = main_root.get_selection_manager()
	var marker: DestinationMarker = main_root.get_destination_marker()
	var cmd: CommandController = main_root.get_command_controller()

	if nav == null or rig == null or selection == null or marker == null or cmd == null:
		push_error("MainScene missing required T1.8 nodes.")
		quit(1)
		return

	rig.edge_pan_enabled = false
	rig.set_focus_position(Vector2(0.0, 1.0))
	rig.set_target_zoom_distance(25.0, true)

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
		push_error("MainScene missing LeaderA or LeaderB.")
		quit(1)
		return

	var output_abs_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(output_abs_dir)
	if mkdir_err != OK:
		push_error("Failed to create output dir: %s" % error_string(mkdir_err))
		quit(1)
		return

	for _i: int in range(15):
		await process_frame
		await physics_frame

	var cam: Camera3D = rig.get_camera()

	# 1. Select LeaderA and right-click destination -> capture immediate DestinationMarker + movement start
	var a_screen: Vector2 = cam.unproject_position(SelectionBoxMath.get_unit_world_anchor(leader_a))
	await _left_click(a_screen)
	var solo_dest := Vector3(-4.0, 0.0, -2.0)
	await _right_click(cam.unproject_position(solo_dest))
	for _i: int in range(4):
		await process_frame
		await physics_frame
	if not marker.is_marker_active():
		push_error("Expected DestinationMarker active after LeaderA right-click.")
		quit(1)
		return
	if not await _save_shot(output_abs_dir.path_join("t1_8_01_leader_a_order_and_marker.png")):
		quit(1)
		return

	# Let LeaderA settle briefly or finish before switching to group order
	await _wait_idle([leader_a], 300)

	# 2. Select both units and right-click north of WallWithGap -> capture group command + marker
	selection.set_selection([leader_a, leader_b])
	rig.set_focus_position(Vector2(0.0, -4.5))
	rig.set_target_zoom_distance(27.0, true)
	for _i: int in range(4):
		await process_frame
		await physics_frame

	var north_goal := Vector3(0.0, 0.0, -10.5)
	await _right_click(cam.unproject_position(north_goal))
	for _i: int in range(3):
		await process_frame
		await physics_frame
	if not await _save_shot(output_abs_dir.path_join("t1_8_02_group_order_issued.png")):
		quit(1)
		return

	# 3. Advance ~75 physics frames so both units actively navigate through the WallGap
	for _i: int in range(75):
		await process_frame
		await physics_frame
	if not await _save_shot(output_abs_dir.path_join("t1_8_03_wall_gap_individual_routes.png")):
		quit(1)
		return

	# 4. Wait until both reach final targets and return IDLE; verify AC-08 separation and capture
	await _wait_idle([leader_a, leader_b], 450)
	rig.set_focus_position(Vector2(0.0, -10.5))
	for _i: int in range(8):
		await process_frame
		await physics_frame

	var final_sep: float = Vector2(leader_a.global_position.x - leader_b.global_position.x, leader_a.global_position.z - leader_b.global_position.z).length()
	print("T1.8 VISUAL SUMMARY: LeaderA=%s (state=%d) | LeaderB=%s (state=%d) | sep_xz=%.3f m | marker_active=%s" % [
		str(leader_a.global_position),
		leader_a.get_state(),
		str(leader_b.global_position),
		leader_b.get_state(),
		final_sep,
		str(marker.is_marker_active()),
	])

	if leader_a.get_state() != Unit.State.IDLE or leader_b.get_state() != Unit.State.IDLE:
		push_error("Expected both protagonists IDLE at final visual check.")
		quit(1)
		return
	if final_sep < 1.0:
		push_error("Expected final separation >= 1.0 m (got %.3f m)." % final_sep)
		quit(1)
		return

	if not await _save_shot(output_abs_dir.path_join("t1_8_04_final_separated_idle.png")):
		quit(1)
		return

	quit(0)


func _left_click(pos: Vector2) -> void:
	await _mouse_move(pos)
	_mouse_button(MOUSE_BUTTON_LEFT, pos, true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_LEFT, pos, false)
	await process_frame


func _right_click(pos: Vector2) -> void:
	await _mouse_move(pos)
	_mouse_button(MOUSE_BUTTON_RIGHT, pos, true)
	await process_frame
	_mouse_button(MOUSE_BUTTON_RIGHT, pos, false)
	await process_frame


func _mouse_move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)
	await process_frame


func _mouse_button(button: MouseButton, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = pos
	ev.global_position = pos
	ev.pressed = pressed
	root.push_input(ev, true)


func _wait_idle(units: Array[Unit], max_frames: int) -> void:
	var frames: int = 0
	while frames < max_frames:
		var moving: bool = false
		for unit: Unit in units:
			if unit.get_state() != Unit.State.IDLE:
				moving = true
				break
		if not moving:
			return
		await physics_frame
		frames += 1


func _save_shot(abs_path: String) -> bool:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("Failed to capture viewport image.")
		return false
	var err: Error = image.save_png(abs_path)
	if err != OK:
		push_error("Failed to save PNG '%s': %s" % [abs_path, error_string(err)])
		return false
	print("Saved screenshot: %s" % abs_path)
	return true
