extends SceneTree
## Visual demonstration and screenshot capture script for T1.5.
## Executes real MoveOrders on MainScene protagonists (no artificial teleportation)
## and saves PNG captures in res://test_output/ for visual inspection.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const OUTPUT_DIR: String = "res://test_output"
const MAX_NAV_WAIT_FRAMES: int = 120
const MAX_STEP_FRAMES: int = 600


func _initialize() -> void:
	call_deferred("_run_demo")


func _run_demo() -> void:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	root.add_child(main_root)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	var overlay: DebugOverlay = main_root.get_node_or_null("UiLayer/DebugOverlay") as DebugOverlay
	if test_map == null or rig == null:
		push_error("Main scene is missing TestMap or RtsCameraRig.")
		quit(1)
		return

	rig.edge_pan_enabled = false
	var nav: WorldNavigation = test_map.get_navigation()
	if nav == null:
		push_error("TestMap is missing WorldNavigation.")
		quit(1)
		return

	var waited: int = 0
	while not nav.is_navigation_ready() and waited < MAX_NAV_WAIT_FRAMES:
		await physics_frame
		waited += 1

	if not nav.is_navigation_ready():
		push_error("WorldNavigation did not become ready.")
		quit(1)
		return

	var units: Array[Unit] = main_root.get_units()
	if units.size() < 2:
		push_error("Expected 2 protagonist units in MainScene.")
		quit(1)
		return

	var leader_a: Unit = units[0]
	var leader_b: Unit = units[1]
	var space_state: PhysicsDirectSpaceState3D = test_map.get_world_3d().direct_space_state

	# 1. Both protagonists at rest (IDLE)
	rig.set_focus_position(Vector2(0.0, 2.5))
	rig.set_target_zoom_distance(24.0, true)
	await _wait_render_frames(6)
	_print_telemetry("Shot 1 (IDLE)", leader_a, leader_b, space_state, overlay)
	if not _save_screenshot("t1_5_01_idle.png"):
		quit(1)
		return

	# 2. Issue real MoveOrders: LeaderA through 4m wall gap, LeaderB to plateau via ramp
	var order_a: MoveOrder = MoveOrder.new(Vector3(-6.0, 0.0, -12.0))
	var order_b: MoveOrder = MoveOrder.new(Vector3(18.0, 2.0, -14.0))
	leader_a.issue_order(order_a)
	leader_b.issue_order(order_b)

	rig.set_focus_position(Vector2(0.0, -6.0))
	rig.set_target_zoom_distance(28.0, true)

	var shot2_taken: bool = false
	var shot3_taken: bool = false
	var frame_idx: int = 0

	while (order_a.is_active() or order_b.is_active()) and frame_idx < MAX_STEP_FRAMES:
		await physics_frame
		frame_idx += 1

		if not shot2_taken and leader_a.global_position.z <= -5.5:
			await _wait_render_frames(2)
			_print_telemetry("Shot 2 (Wall Gap)", leader_a, leader_b, space_state, overlay)
			if not _save_screenshot("t1_5_02_wall_gap.png"):
				quit(1)
				return
			shot2_taken = true
			rig.set_focus_position(Vector2(9.5, -14.0))
			rig.set_target_zoom_distance(28.0, true)

		if shot2_taken and not shot3_taken and leader_b.global_position.x >= 7.5 and leader_b.global_position.y >= 0.55:
			await _wait_render_frames(2)
			_print_telemetry("Shot 3 (Ramp Climb)", leader_a, leader_b, space_state, overlay)
			if not _save_screenshot("t1_5_03_ramp_climb.png"):
				quit(1)
				return
			shot3_taken = true

	if not shot2_taken or not shot3_taken:
		push_error("Failed to capture wall gap (%s) or ramp climb (%s) screenshots. frames=%d B_pos=%s B_state=%s B_order_status=%d B_reason=%s" % [
			str(shot2_taken), str(shot3_taken), frame_idx,
			str(leader_b.global_position), leader_b.get_state_name(), order_b.status, order_b.failure_reason
		])
		quit(1)
		return

	print("Arrival Phase 1: A=%s (%s), B=%s (%s)" % [
		str(leader_a.global_position), leader_a.get_state_name(),
		str(leader_b.global_position), leader_b.get_state_name(),
	])

	# 4. Both units moving simultaneously under distant RTS zoom
	var order_a2: MoveOrder = MoveOrder.new(Vector3(6.0, 0.0, 12.0))
	var order_b2: MoveOrder = MoveOrder.new(Vector3(-4.0, 0.0, 10.0))
	leader_a.issue_order(order_a2)
	leader_b.issue_order(order_b2)

	rig.set_focus_position(Vector2(2.0, -1.0))
	rig.set_target_zoom_distance(48.0, true)

	for _i: int in range(110):
		await physics_frame
	await _wait_render_frames(2)
	_print_telemetry("Shot 4 (Both Moving Distant RTS Zoom)", leader_a, leader_b, space_state, overlay)
	if not _save_screenshot("t1_5_04_both_moving_rts_zoom.png"):
		quit(1)
		return

	var settle_frames: int = 0
	while (order_a2.is_active() or order_b2.is_active()) and settle_frames < MAX_STEP_FRAMES:
		await physics_frame
		settle_frames += 1

	print("Arrival Phase 2: A=%s (%s, status=%d), B=%s (%s, status=%d)" % [
		str(leader_a.global_position), leader_a.get_state_name(), order_a2.status,
		str(leader_b.global_position), leader_b.get_state_name(), order_b2.status,
	])
	quit(0)


func _wait_render_frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame


func _print_telemetry(label: String, a: Unit, b: Unit, space_state: PhysicsDirectSpaceState3D, overlay: DebugOverlay) -> void:
	var dy_a: float = _terrain_delta_y(space_state, a.global_position)
	var dy_b: float = _terrain_delta_y(space_state, b.global_position)
	var fps_line: String = overlay.get_stats_text().replace("\n", " | ") if overlay != null else ""
	print("[%s] A(id=%s, state=%s, pos=%s, yaw=%.2f, dy=%.4f) | B(id=%s, state=%s, pos=%s, yaw=%.2f, dy=%.4f) | Overlay=(%s)" % [
		label,
		str(a.get_character_id()), a.get_state_name(), str(a.global_position), a.rotation.y, dy_a,
		str(b.get_character_id()), b.get_state_name(), str(b.global_position), b.rotation.y, dy_b,
		fps_line,
	])


func _terrain_delta_y(space_state: PhysicsDirectSpaceState3D, pos: Vector3) -> float:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(pos.x, pos.y + 3.0, pos.z),
		Vector3(pos.x, pos.y - 5.0, pos.z),
		CollisionLayers.MASK_TERRAIN
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return absf(pos.y - (hit["position"] as Vector3).y)


func _save_screenshot(filename: String) -> bool:
	var out_dir_abs: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	var mkdir_err: Error = DirAccess.make_dir_recursive_absolute(out_dir_abs)
	if mkdir_err != OK:
		push_error("Failed to create '%s': %s" % [out_dir_abs, error_string(mkdir_err)])
		return false

	var gdignore_path: String = out_dir_abs.path_join(".gdignore")
	if not FileAccess.file_exists(gdignore_path):
		var f: FileAccess = FileAccess.open(gdignore_path, FileAccess.WRITE)
		if f != null:
			f.close()

	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("Captured image is empty for %s" % filename)
		return false

	var file_abs: String = out_dir_abs.path_join(filename)
	var save_err: Error = img.save_png(file_abs)
	if save_err != OK:
		push_error("Failed to save '%s': %s" % [file_abs, error_string(save_err)])
		return false

	print("Screenshot saved: %s (%dx%d)" % [file_abs, img.get_width(), img.get_height()])
	return true
