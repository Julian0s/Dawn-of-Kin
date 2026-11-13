extends SceneTree
## Visual capture script for T1.6: launches MainScene in windowed mode and captures
## real mouse/keyboard picking & selection states at close/mid and max RTS zoom.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const OUTPUT_DIR: String = "res://test_output"


func _initialize() -> void:
	call_deferred("_run_captures")


func _run_captures() -> void:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	root.add_child(main_root)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	var manager: SelectionManager = main_root.get_selection_manager()
	if rig == null or manager == null:
		push_error("MainScene missing RtsCameraRig or SelectionManager.")
		quit(1)
		return

	rig.edge_pan_enabled = false
	rig.set_focus_position(Vector2(0.0, 2.5))
	rig.set_target_zoom_distance(26.0, true)

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
		push_error("Failed to create output directory '%s': %s" % [output_abs_dir, error_string(mkdir_err)])
		quit(1)
		return

	var gdignore_path: String = output_abs_dir.path_join(".gdignore")
	if not FileAccess.file_exists(gdignore_path):
		var gdignore_file: FileAccess = FileAccess.open(gdignore_path, FileAccess.WRITE)
		if gdignore_file != null:
			gdignore_file.close()

	for _i: int in range(30):
		await process_frame
		await physics_frame

	var cam: Camera3D = rig.get_camera()
	var a_screen: Vector2 = cam.unproject_position(leader_a.global_position + Vector3(0.0, 1.0, 0.0))
	var b_screen: Vector2 = cam.unproject_position(leader_b.global_position + Vector3(0.0, 1.0, 0.0))
	var clear_ground_screen: Vector2 = cam.unproject_position(Vector3(0.0, 0.0, 7.0))

	# 1. LeaderA selected exclusively.
	await _click_at(a_screen, false)
	await _move_mouse(clear_ground_screen)
	if not _verify_state(manager.get_selection_count() == 1 and manager.is_selected(leader_a), "Expected only LeaderA selected"):
		quit(1)
		return
	if not await _save_shot(output_abs_dir.path_join("t1_6_01_leader_a_selected.png")):
		quit(1)
		return

	# 2. LeaderB selected exclusively (transfers from LeaderA).
	await _click_at(b_screen, false)
	await _move_mouse(clear_ground_screen)
	if not _verify_state(manager.get_selection_count() == 1 and manager.is_selected(leader_b) and not manager.is_selected(leader_a), "Expected only LeaderB selected"):
		quit(1)
		return
	if not await _save_shot(output_abs_dir.path_join("t1_6_02_leader_b_selected.png")):
		quit(1)
		return

	# 3. Hover on unselected LeaderA while LeaderB stays selected.
	await _move_mouse(a_screen)
	if not _verify_state(leader_a.is_hovered() and not leader_a.is_selected() and leader_b.is_selected(), "Expected hover on LeaderA alongside selected LeaderB"):
		quit(1)
		return
	if not await _save_shot(output_abs_dir.path_join("t1_6_05_hover_unselected.png")):
		quit(1)
		return

	# 4. Both selected via Shift+click on LeaderA.
	await _click_at(a_screen, true)
	await _move_mouse(clear_ground_screen)
	if not _verify_state(manager.get_selection_count() == 2 and manager.is_selected(leader_a) and manager.is_selected(leader_b), "Expected both units selected via Shift+click"):
		quit(1)
		return
	if not await _save_shot(output_abs_dir.path_join("t1_6_03_both_selected_shift.png")):
		quit(1)
		return

	# 5. Readability check at max camera zoom (58.0m) with both units selected.
	rig.set_target_zoom_distance(rig.max_distance, true)
	rig.set_focus_position(Vector2.ZERO)
	for _i: int in range(6):
		await process_frame
	if not await _save_shot(output_abs_dir.path_join("t1_6_06_zoom_max_readability.png")):
		quit(1)
		return

	# 6. Clear selection via Esc at closer zoom.
	rig.set_focus_position(Vector2(0.0, 2.5))
	rig.set_target_zoom_distance(26.0, true)
	for _i: int in range(6):
		await process_frame
	await _press_escape()
	if not _verify_state(manager.is_empty() and not leader_a.is_selected() and not leader_b.is_selected(), "Expected empty selection after Esc"):
		quit(1)
		return
	if not await _save_shot(output_abs_dir.path_join("t1_6_04_none_selected.png")):
		quit(1)
		return

	print("T1.6 visual selection scenario completed successfully (6 captures).")
	quit(0)


func _move_mouse(screen_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	root.push_input(motion, true)
	for _i: int in range(3):
		await process_frame


func _click_at(screen_pos: Vector2, shift_held: bool) -> void:
	await _move_mouse(screen_pos)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = screen_pos
	down.global_position = screen_pos
	down.pressed = true
	down.shift_pressed = shift_held
	root.push_input(down, true)
	await process_frame

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = screen_pos
	up.global_position = screen_pos
	up.pressed = false
	up.shift_pressed = shift_held
	root.push_input(up, true)
	for _i: int in range(3):
		await process_frame


func _press_escape() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_ESCAPE
	down.physical_keycode = KEY_ESCAPE
	down.pressed = true
	root.push_input(down, true)
	await process_frame

	var up := InputEventKey.new()
	up.keycode = KEY_ESCAPE
	up.physical_keycode = KEY_ESCAPE
	up.pressed = false
	root.push_input(up, true)
	for _i: int in range(3):
		await process_frame


func _verify_state(condition: bool, message: String) -> bool:
	if not condition:
		push_error("Visual scenario assertion failed: %s" % message)
		return false
	return true


func _save_shot(abs_path: String) -> bool:
	for _i: int in range(4):
		await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("Failed to capture viewport image for '%s'." % abs_path)
		return false
	var err: Error = img.save_png(abs_path)
	if err != OK:
		push_error("Failed to save PNG '%s': %s" % [abs_path, error_string(err)])
		return false
	print("Saved visual capture: %s" % abs_path)
	return true
